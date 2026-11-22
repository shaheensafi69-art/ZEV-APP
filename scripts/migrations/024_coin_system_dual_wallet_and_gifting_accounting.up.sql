-- =========================================================================
-- MIGRATION 024: ZEV DUAL-WALLET (COINS & USD EARNINGS) & 40/60 GIFTING LEDGER
-- =========================================================================

-- 1. Ensure columns exist on profiles table
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS coins_balance BIGINT DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS earnings_usd NUMERIC(12, 4) DEFAULT 0.0000 NOT NULL,
  ADD COLUMN IF NOT EXISTS earnings_coins BIGINT DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_coins_purchased BIGINT DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_coins_spent BIGINT DEFAULT 0 NOT NULL;

-- Add check constraints to guarantee no negative balances
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_coins_balance_positive') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT check_coins_balance_positive CHECK (coins_balance >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_earnings_usd_positive') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT check_earnings_usd_positive CHECK (earnings_usd >= 0);
  END IF;
END $$;

-- 2. Create coin_packages table
CREATE TABLE IF NOT EXISTS public.coin_packages (
  id TEXT PRIMARY KEY,
  coins INTEGER NOT NULL CHECK (coins > 0),
  usd_price NUMERIC(10, 2) NOT NULL CHECK (usd_price > 0),
  discount_percent INTEGER DEFAULT 0 CHECK (discount_percent >= 0 AND discount_percent <= 100),
  badge TEXT,
  is_popular BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on coin_packages and allow public read
ALTER TABLE public.coin_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read on coin_packages" ON public.coin_packages;
CREATE POLICY "Allow public read on coin_packages"
  ON public.coin_packages
  FOR SELECT
  TO authenticated, anon
  USING (is_active = TRUE);

-- Populate official coin packages
INSERT INTO public.coin_packages (id, coins, usd_price, discount_percent, badge, is_popular, is_active, sort_order)
VALUES
  ('tier_70', 70, 0.99, 0, NULL, FALSE, TRUE, 1),
  ('tier_350', 350, 4.79, 5, NULL, FALSE, TRUE, 2),
  ('tier_700', 700, 9.49, 10, 'MOST POPULAR', TRUE, TRUE, 3),
  ('tier_1400', 1400, 18.49, 15, 'CREATOR CHOICE', FALSE, TRUE, 4),
  ('tier_3500', 3500, 44.99, 20, 'VIP STREAMER', FALSE, TRUE, 5),
  ('tier_7000', 7000, 84.99, 25, 'ELITE PRO', FALSE, TRUE, 6),
  ('tier_17500', 17500, 199.99, 30, 'MAX SAVINGS', FALSE, TRUE, 7)
ON CONFLICT (id) DO UPDATE SET
  coins = EXCLUDED.coins,
  usd_price = EXCLUDED.usd_price,
  discount_percent = EXCLUDED.discount_percent,
  badge = EXCLUDED.badge,
  is_popular = EXCLUDED.is_popular,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;

-- 3. Create gift_transactions table (Immutable Ledger)
CREATE TABLE IF NOT EXISTS public.gift_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  room_id TEXT,
  gift_name TEXT NOT NULL,
  gift_emoji TEXT DEFAULT '🎁',
  coins_amount INTEGER NOT NULL CHECK (coins_amount > 0),
  gross_usd NUMERIC(10, 4) NOT NULL CHECK (gross_usd >= 0),
  creator_usd NUMERIC(10, 4) NOT NULL CHECK (creator_usd >= 0),
  platform_usd NUMERIC(10, 4) NOT NULL CHECK (platform_usd >= 0),
  status TEXT DEFAULT 'completed' NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gift_tx_sender ON public.gift_transactions(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_tx_receiver ON public.gift_transactions(receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_tx_room ON public.gift_transactions(room_id);

ALTER TABLE public.gift_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their sent or received gifts" ON public.gift_transactions;
CREATE POLICY "Users can view their sent or received gifts"
  ON public.gift_transactions
  FOR SELECT
  TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- 4. Create payout_requests table for Creator Cashouts
CREATE TABLE IF NOT EXISTS public.payout_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount_usd NUMERIC(10, 2) NOT NULL CHECK (amount_usd >= 10.00), -- Minimum $10 payout
  payout_method TEXT NOT NULL, -- 'paypal', 'bank_transfer', 'usdt'
  destination_account TEXT NOT NULL, -- email or wallet address or IBAN
  status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own payout requests" ON public.payout_requests;
CREATE POLICY "Users can view own payout requests"
  ON public.payout_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own payout requests" ON public.payout_requests;
CREATE POLICY "Users can insert own payout requests"
  ON public.payout_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- 5. Atomic Supabase RPC: send_live_gift
-- Enforces TikTok-style 40% Creator / 60% Platform revenue split
CREATE OR REPLACE FUNCTION public.send_live_gift(
  p_receiver_id UUID,
  p_gift_name TEXT,
  p_gift_emoji TEXT,
  p_coins INTEGER,
  p_room_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id UUID;
  v_sender_coins BIGINT;
  v_gross_usd NUMERIC(10, 4);
  v_creator_usd NUMERIC(10, 4);
  v_platform_usd NUMERIC(10, 4);
  v_tx_id UUID;
  v_new_sender_balance BIGINT;
  v_new_receiver_earnings NUMERIC(12, 4);
BEGIN
  -- Authenticate caller
  v_sender_id := auth.uid();
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED: User must be signed in.';
  END IF;

  IF v_sender_id = p_receiver_id THEN
    RAISE EXCEPTION 'SELF_GIFT_PROHIBITED: Cannot send gifts to yourself.';
  END IF;

  IF p_coins <= 0 THEN
    RAISE EXCEPTION 'INVALID_COIN_AMOUNT: Coins must be greater than zero.';
  END IF;

  -- Verify sender has enough coins (lock sender row)
  SELECT coins_balance INTO v_sender_coins
  FROM public.profiles
  WHERE id = v_sender_id
  FOR UPDATE;

  IF v_sender_coins IS NULL OR v_sender_coins < p_coins THEN
    RAISE EXCEPTION 'INSUFFICIENT_COINS: Balance is %, required %.', COALESCE(v_sender_coins, 0), p_coins;
  END IF;

  -- 40% / 60% Accounting Model (Exact TikTok math):
  -- Base rate: 70 coins = $0.99 USD => 1 coin = $0.0141428 USD
  v_gross_usd := ROUND((p_coins::NUMERIC * 0.0141428), 4);
  v_creator_usd := ROUND((v_gross_usd * 0.40), 4); -- 40% TO CREATOR
  v_platform_usd := v_gross_usd - v_creator_usd;     -- 60% TO PLATFORM

  -- Deduct from sender
  UPDATE public.profiles
  SET
    coins_balance = coins_balance - p_coins,
    total_coins_spent = total_coins_spent + p_coins,
    updated_at = NOW()
  WHERE id = v_sender_id
  RETURNING coins_balance INTO v_new_sender_balance;

  -- Credit to receiver (USD earnings + gift coins)
  UPDATE public.profiles
  SET
    earnings_usd = earnings_usd + v_creator_usd,
    earnings_coins = earnings_coins + p_coins,
    updated_at = NOW()
  WHERE id = p_receiver_id
  RETURNING earnings_usd INTO v_new_receiver_earnings;

  -- Insert immutable ledger record
  INSERT INTO public.gift_transactions (
    sender_id,
    receiver_id,
    room_id,
    gift_name,
    gift_emoji,
    coins_amount,
    gross_usd,
    creator_usd,
    platform_usd,
    status
  )
  VALUES (
    v_sender_id,
    p_receiver_id,
    p_room_id,
    p_gift_name,
    p_gift_emoji,
    p_coins,
    v_gross_usd,
    v_creator_usd,
    v_platform_usd,
    'completed'
  )
  RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'transaction_id', v_tx_id,
    'sender_coins_balance', v_new_sender_balance,
    'coins_sent', p_coins,
    'gross_usd', v_gross_usd,
    'creator_usd_earned', v_creator_usd,
    'platform_usd_retained', v_platform_usd
  );
END;
$$;
