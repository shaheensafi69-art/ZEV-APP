-- 013_ads_monetization_verification.up.sql
-- Phase 8: Production Ads Engine (Security-Hardened Triggers, Targeting, Frequency Caps,
-- Idempotent & Anti-Fraud Event Tracking, Atomic Budget Deduction, Invoices)
-- + Subscription Expiry & 100-Referral Lifetime Blue Verification Hardening.

-- 1. Expand ad_campaigns for frequency caps, daily pacing, approval telemetry, and micro-dollar CPM precision
ALTER TABLE public.ad_campaigns
  ADD COLUMN IF NOT EXISTS daily_frequency_cap integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS min_cooldown_seconds integer NOT NULL DEFAULT 300,
  ADD COLUMN IF NOT EXISTS spent_today numeric(14,6) NOT NULL DEFAULT 0.000000,
  ADD COLUMN IF NOT EXISTS spent_today_date date NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

ALTER TABLE public.ad_campaigns
  ALTER COLUMN spent_amount TYPE numeric(14,6);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ad_campaigns_daily_freq_cap_check'
  ) THEN
    ALTER TABLE public.ad_campaigns
      ADD CONSTRAINT ad_campaigns_daily_freq_cap_check
      CHECK (daily_frequency_cap BETWEEN 1 AND 50);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ad_campaigns_cooldown_check'
  ) THEN
    ALTER TABLE public.ad_campaigns
      ADD CONSTRAINT ad_campaigns_cooldown_check
      CHECK (min_cooldown_seconds BETWEEN 0 AND 86400);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ad_campaigns_positive_budgets_check'
  ) THEN
    ALTER TABLE public.ad_campaigns
      ADD CONSTRAINT ad_campaigns_positive_budgets_check
      CHECK (bid_amount > 0 AND daily_budget > 0 AND total_budget > 0 AND spent_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ad_creatives_status_check'
  ) THEN
    ALTER TABLE public.ad_creatives
      ADD CONSTRAINT ad_creatives_status_check
      CHECK (status IN ('pending_review', 'approved', 'rejected', 'paused'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ad_invoices_status_check'
  ) THEN
    ALTER TABLE public.ad_invoices
      ADD CONSTRAINT ad_invoices_status_check
      CHECK (status IN ('issued', 'paid', 'void'));
  END IF;
END $$;

-- 2. Anti-fraud flagging metadata on event tables
ALTER TABLE public.ad_impressions
  ADD COLUMN IF NOT EXISTS is_flagged boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS flag_reason text;

ALTER TABLE public.ad_clicks
  ADD COLUMN IF NOT EXISTS is_flagged boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS flag_reason text;

-- 3. Performance & Anti-Fraud Lookup Indexes
CREATE INDEX IF NOT EXISTS idx_ad_campaigns_eligible
  ON public.ad_campaigns (placement, status, starts_at, ends_at)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_ad_creatives_campaign_status
  ON public.ad_creatives (campaign_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ad_impressions_campaign_user_time
  ON public.ad_impressions (campaign_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ad_clicks_campaign_user_time
  ON public.ad_clicks (campaign_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ad_impressions_flagged
  ON public.ad_impressions (created_at DESC)
  WHERE is_flagged = true;

CREATE INDEX IF NOT EXISTS idx_ad_clicks_flagged
  ON public.ad_clicks (created_at DESC)
  WHERE is_flagged = true;

-- 4. Tighten RLS WITH CHECK clauses on ad_creatives and ad_targeting
DROP POLICY IF EXISTS ad_creatives_manage_owner ON public.ad_creatives;
CREATE POLICY ad_creatives_manage_owner ON public.ad_creatives
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
    AND status IN ('pending_review', 'paused')
  );

DROP POLICY IF EXISTS ad_targeting_select_owner ON public.ad_targeting;
CREATE POLICY ad_targeting_select_owner ON public.ad_targeting
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND (c.status = 'active' OR a.user_id = auth.uid())
    )
    OR public.is_app_admin()
  );

DROP POLICY IF EXISTS ad_targeting_manage_owner ON public.ad_targeting;
CREATE POLICY ad_targeting_manage_owner ON public.ad_targeting
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  );

-- 5. SECURITY INVOKER Column-Protection Triggers on Advertisers, Campaigns & Creatives
CREATE OR REPLACE FUNCTION public.protect_advertiser_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_app_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.user_id IS DISTINCT FROM auth.uid()
       OR NEW.status IS DISTINCT FROM 'pending'
       OR COALESCE(NEW.balance, 0) <> 0 THEN
      RAISE EXCEPTION 'Insufficient privileges to set advertiser verification or balance directly'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.balance IS DISTINCT FROM OLD.balance
     OR NEW.currency IS DISTINCT FROM OLD.currency THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected advertiser attributes'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_protect_advertiser_columns ON public.advertisers;
CREATE TRIGGER tr_protect_advertiser_columns
  BEFORE INSERT OR UPDATE ON public.advertisers
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_advertiser_columns();

CREATE OR REPLACE FUNCTION public.protect_ad_campaign_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_app_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status NOT IN ('draft', 'pending_review')
       OR COALESCE(NEW.spent_amount, 0) <> 0
       OR COALESCE(NEW.spent_today, 0) <> 0
       OR COALESCE(NEW.impressions_count, 0) <> 0
       OR COALESCE(NEW.clicks_count, 0) <> 0
       OR COALESCE(NEW.conversions_count, 0) <> 0
       OR NEW.approved_at IS NOT NULL THEN
      RAISE EXCEPTION 'Insufficient privileges to bypass ad campaign review or initialize spend counters'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.advertiser_id IS DISTINCT FROM OLD.advertiser_id
     OR NEW.spent_amount IS DISTINCT FROM OLD.spent_amount
     OR NEW.spent_today IS DISTINCT FROM OLD.spent_today
     OR NEW.spent_today_date IS DISTINCT FROM OLD.spent_today_date
     OR NEW.impressions_count IS DISTINCT FROM OLD.impressions_count
     OR NEW.clicks_count IS DISTINCT FROM OLD.clicks_count
     OR NEW.conversions_count IS DISTINCT FROM OLD.conversions_count
     OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
     OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
     OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status NOT IN ('draft', 'pending_review', 'paused')) THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected ad campaign financial or approval fields'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_protect_ad_campaign_columns ON public.ad_campaigns;
CREATE TRIGGER tr_protect_ad_campaign_columns
  BEFORE INSERT OR UPDATE ON public.ad_campaigns
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_ad_campaign_columns();

CREATE OR REPLACE FUNCTION public.protect_ad_creative_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_app_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'pending_review' THEN
      RAISE EXCEPTION 'Insufficient privileges to pre-approve ad creatives'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.campaign_id IS DISTINCT FROM OLD.campaign_id
     OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status NOT IN ('pending_review', 'paused')) THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected ad creative approval fields'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_protect_ad_creative_columns ON public.ad_creatives;
CREATE TRIGGER tr_protect_ad_creative_columns
  BEFORE INSERT OR UPDATE ON public.ad_creatives
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_ad_creative_columns();

-- 6. Harden expire_stale_subscriptions() so lifetime / >=100 referral holders are strictly protected
CREATE OR REPLACE FUNCTION public.expire_stale_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_verifs int := 0;
  v_expired_subs int := 0;
  v_expired_restr int := 0;
  v_uid uuid;
  v_revoked_ids uuid[] := '{}';
BEGIN
  WITH exp_v AS (
    UPDATE public.user_verifications uv
    SET is_active = false,
        status = 'expired',
        updated_at = now()
    FROM public.profiles p
    WHERE uv.user_id = p.id
      AND uv.is_active = true
      AND uv.expires_at IS NOT NULL
      AND uv.expires_at < now()
      AND COALESCE(p.lifetime_blue_eligible, false) = false
      AND COALESCE(uv.plan_type, '') NOT IN ('lifetime', 'lifetime_referral')
      AND COALESCE(p.referral_count, 0) < 100
    RETURNING uv.user_id
  ),
  upd_p AS (
    UPDATE public.profiles p
    SET is_verified = false,
        updated_at = now()
    WHERE p.id IN (SELECT user_id FROM exp_v)
      AND COALESCE(p.lifetime_blue_eligible, false) = false
      AND COALESCE(p.referral_count, 0) < 100
    RETURNING p.id
  )
  SELECT COALESCE(array_agg(id), '{}'), count(*) INTO v_revoked_ids, v_expired_verifs FROM upd_p;

  FOREACH v_uid IN ARRAY v_revoked_ids LOOP
    INSERT INTO public.user_notifications (
      user_id, title, message, notification_type, app_source, is_read, created_at
    ) VALUES (
      v_uid,
      'ZEV Blue Subscription Expired',
      'Your timed ZEV Blue subscription ended. Renew anytime or invite 100 friends for free Lifetime Blue!',
      'verification',
      'zev',
      false,
      now()
    );
  END LOOP;

  WITH exp_s AS (
    UPDATE public.subscriptions s
    SET is_active = false,
        status = 'expired',
        updated_at = now()
    FROM public.profiles p
    WHERE s.user_id = p.id
      AND s.is_active = true
      AND s.expires_at IS NOT NULL
      AND s.expires_at < now()
      AND COALESCE(p.lifetime_blue_eligible, false) = false
      AND COALESCE(s.plan_type, s.plan, '') NOT IN ('lifetime', 'lifetime_referral')
      AND COALESCE(p.referral_count, 0) < 100
    RETURNING s.id
  )
  SELECT count(*) INTO v_expired_subs FROM exp_s;

  WITH exp_r AS (
    UPDATE public.user_restrictions
    SET status = 'expired'
    WHERE status = 'active'
      AND expires_at IS NOT NULL
      AND expires_at < now()
    RETURNING user_id
  ),
  lift_p AS (
    UPDATE public.profiles p
    SET is_restricted = false,
        restricted_until = NULL,
        restriction_reason = NULL,
        updated_at = now()
    WHERE p.id IN (SELECT DISTINCT user_id FROM exp_r)
      AND NOT EXISTS (
        SELECT 1 FROM public.user_restrictions ur
        WHERE ur.user_id = p.id
          AND ur.status = 'active'
          AND ur.type = 'RESTRICTION'
          AND (ur.expires_at IS NULL OR ur.expires_at > now())
      )
    RETURNING p.id
  )
  SELECT count(*) INTO v_expired_restr FROM lift_p;

  RETURN jsonb_build_object(
    'expired_verifications', v_expired_verifs,
    'expired_subscriptions', v_expired_subs,
    'lifted_restrictions', v_expired_restr
  );
END;
$$;

-- 7. Self-service 100-Referral Lifetime Blue Claim RPC
CREATE OR REPLACE FUNCTION public.claim_lifetime_referral_blue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_prof public.profiles%ROWTYPE;
  v_real_count int := 0;
  v_effective_count int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_prof FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)::int INTO v_real_count
  FROM public.referrals
  WHERE referrer_id = v_uid;

  v_effective_count := GREATEST(COALESCE(v_prof.referral_count, 0), v_real_count);
  IF v_effective_count < 100 AND COALESCE(v_prof.lifetime_blue_eligible, false) = false THEN
    RETURN jsonb_build_object(
      'ok', false,
      'eligible', false,
      'referral_count', v_effective_count,
      'required', 100,
      'message', format('You currently have %s / 100 verified referrals.', v_effective_count)
    );
  END IF;

  UPDATE public.profiles
  SET is_verified = true,
      lifetime_blue_eligible = true,
      referral_count = GREATEST(COALESCE(referral_count, 0), v_effective_count),
      updated_at = now()
  WHERE id = v_uid;

  INSERT INTO public.user_verifications (
    user_id, badge_type, status, is_active, plan_type, badge_label,
    verification_reason, verified_at, expires_at, updated_at
  ) VALUES (
    v_uid, 'blue_tick', 'verified', true, 'lifetime_referral', 'Referral Legend',
    format('Earned Free Lifetime ZEV Blue via %s verified referrals', v_effective_count),
    now(), NULL, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    badge_type = 'blue_tick',
    status = 'verified',
    is_active = true,
    plan_type = 'lifetime_referral',
    badge_label = 'Referral Legend',
    verification_reason = EXCLUDED.verification_reason,
    verified_at = now(),
    expires_at = NULL,
    updated_at = now();

  INSERT INTO public.subscriptions (
    user_id, plan_type, plan, plan_price, amount, currency,
    status, is_active, starts_at, expires_at, payment_method, created_at, updated_at
  ) VALUES (
    v_uid, 'lifetime_referral', 'lifetime_referral', '$0.00', 0.00, 'USD',
    'active', true, now(), NULL, '100-Referral Milestone', now(), now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    plan_type = 'lifetime_referral',
    plan = 'lifetime_referral',
    plan_price = '$0.00',
    amount = 0.00,
    status = 'active',
    is_active = true,
    starts_at = now(),
    expires_at = NULL,
    payment_method = '100-Referral Milestone',
    updated_at = now();

  INSERT INTO public.user_notifications (
    user_id, title, message, notification_type, app_source, is_read, created_at
  ) VALUES (
    v_uid,
    'Lifetime ZEV Blue Unlocked!',
    'You reached 100 referrals and unlocked your permanent Free ZEV Blue Verification Badge.',
    'verification',
    'zev',
    false,
    now()
  );

  RETURN jsonb_build_object(
    'ok', true,
    'eligible', true,
    'referral_count', v_effective_count,
    'plan_type', 'lifetime_referral'
  );
END;
$$;

-- 8. Advertiser & Campaign Self-Service RPCs
CREATE OR REPLACE FUNCTION public.register_or_update_advertiser(
  p_business_name text,
  p_website text DEFAULT NULL,
  p_contact_email text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.advertisers%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF length(trim(COALESCE(p_business_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Business name must be at least 2 characters' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.advertisers (
    user_id, business_name, website, contact_email, status, balance, currency, created_at, updated_at
  ) VALUES (
    v_uid,
    left(trim(p_business_name), 120),
    NULLIF(trim(COALESCE(p_website, '')), ''),
    NULLIF(trim(COALESCE(p_contact_email, '')), ''),
    'pending',
    0.00,
    'USD',
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    business_name = left(trim(p_business_name), 120),
    website = COALESCE(NULLIF(trim(COALESCE(p_website, '')), ''), public.advertisers.website),
    contact_email = COALESCE(NULLIF(trim(COALESCE(p_contact_email, '')), ''), public.advertisers.contact_email),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('ok', true, 'advertiser', to_jsonb(v_row));
END;
$$;

CREATE OR REPLACE FUNCTION public.create_ad_campaign_with_creative(
  p_name text,
  p_objective text DEFAULT 'awareness',
  p_placement text DEFAULT 'feed',
  p_pricing_model text DEFAULT 'CPM',
  p_bid_amount numeric DEFAULT 2.50,
  p_daily_budget numeric DEFAULT 10.00,
  p_total_budget numeric DEFAULT 50.00,
  p_title text DEFAULT '',
  p_body text DEFAULT '',
  p_media_url text DEFAULT NULL,
  p_media_type text DEFAULT 'image',
  p_cta_label text DEFAULT 'Learn More',
  p_destination_url text DEFAULT 'https://www.zevapp.com',
  p_countries text[] DEFAULT '{}',
  p_languages text[] DEFAULT '{}',
  p_interests text[] DEFAULT '{}',
  p_min_age integer DEFAULT 13,
  p_max_age integer DEFAULT 99,
  p_gender text DEFAULT 'all',
  p_starts_at timestamptz DEFAULT now(),
  p_ends_at timestamptz DEFAULT NULL,
  p_daily_frequency_cap integer DEFAULT 3,
  p_min_cooldown_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_campaign_id uuid;
  v_creative_id uuid;
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_pricing text := upper(trim(COALESCE(p_pricing_model, 'CPM')));
  v_media_type text := lower(trim(COALESCE(p_media_type, 'image')));
  v_dest text := trim(COALESCE(p_destination_url, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Please register your advertiser profile first' USING ERRCODE = 'P0001';
  END IF;

  IF v_adv.status = 'suspended' THEN
    RAISE EXCEPTION 'Advertiser account is suspended' USING ERRCODE = '42501';
  END IF;

  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore', 'all') THEN
    RAISE EXCEPTION 'Invalid placement: %', p_placement USING ERRCODE = '22023';
  END IF;

  IF v_pricing NOT IN ('CPM', 'CPC', 'CPA') THEN
    RAISE EXCEPTION 'Invalid pricing model: %', p_pricing_model USING ERRCODE = '22023';
  END IF;

  IF v_media_type NOT IN ('image', 'video') THEN
    v_media_type := 'image';
  END IF;

  IF COALESCE(p_bid_amount, 0) <= 0 OR COALESCE(p_daily_budget, 0) < 1 OR COALESCE(p_total_budget, 0) < p_daily_budget THEN
    RAISE EXCEPTION 'Invalid budget or bid amount (daily >= 1, total >= daily, bid > 0)' USING ERRCODE = '22023';
  END IF;

  IF length(trim(COALESCE(p_name, ''))) < 2 OR length(trim(COALESCE(p_title, ''))) < 2 OR length(trim(COALESCE(p_body, ''))) < 2 THEN
    RAISE EXCEPTION 'Campaign name, creative headline, and body are required' USING ERRCODE = '22023';
  END IF;

  IF v_dest !~* '^https?://' THEN
    RAISE EXCEPTION 'Destination URL must begin with http:// or https://' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.ad_campaigns (
    advertiser_id, name, objective, placement, status, pricing_model,
    bid_amount, daily_budget, total_budget, spent_amount, spent_today, spent_today_date,
    starts_at, ends_at, daily_frequency_cap, min_cooldown_seconds, created_at, updated_at
  ) VALUES (
    v_adv.id,
    left(trim(p_name), 120),
    COALESCE(NULLIF(trim(p_objective), ''), 'awareness'),
    v_placement,
    'pending_review',
    v_pricing,
    ROUND(p_bid_amount, 4),
    ROUND(p_daily_budget, 2),
    ROUND(p_total_budget, 2),
    0.000000,
    0.000000,
    CURRENT_DATE,
    COALESCE(p_starts_at, now()),
    p_ends_at,
    LEAST(50, GREATEST(1, COALESCE(p_daily_frequency_cap, 3))),
    LEAST(86400, GREATEST(0, COALESCE(p_min_cooldown_seconds, 300))),
    now(),
    now()
  )
  RETURNING id INTO v_campaign_id;

  INSERT INTO public.ad_creatives (
    campaign_id, title, body, media_url, media_type, cta_label, destination_url, status, created_at, updated_at
  ) VALUES (
    v_campaign_id,
    left(trim(p_title), 140),
    left(trim(p_body), 500),
    NULLIF(trim(COALESCE(p_media_url, '')), ''),
    v_media_type,
    left(COALESCE(NULLIF(trim(p_cta_label), ''), 'Learn More'), 40),
    v_dest,
    'pending_review',
    now(),
    now()
  )
  RETURNING id INTO v_creative_id;

  INSERT INTO public.ad_targeting (
    campaign_id, countries, languages, interests, min_age, max_age, gender, created_at, updated_at
  ) VALUES (
    v_campaign_id,
    COALESCE(p_countries, '{}'),
    COALESCE(p_languages, '{}'),
    COALESCE(p_interests, '{}'),
    GREATEST(13, COALESCE(p_min_age, 13)),
    LEAST(99, GREATEST(GREATEST(13, COALESCE(p_min_age, 13)), COALESCE(p_max_age, 99))),
    COALESCE(NULLIF(trim(p_gender), ''), 'all'),
    now(),
    now()
  );

  RETURN jsonb_build_object(
    'ok', true,
    'campaign_id', v_campaign_id,
    'creative_id', v_creative_id,
    'status', 'pending_review'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.toggle_own_ad_campaign_status(
  p_campaign_id uuid,
  p_pause boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_c public.ad_campaigns%ROWTYPE;
  v_adv_status text;
  v_next_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT c.* INTO v_c
  FROM public.ad_campaigns c
  JOIN public.advertisers a ON a.id = c.advertiser_id
  WHERE c.id = p_campaign_id AND a.user_id = v_uid
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campaign not found or access denied' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_adv_status FROM public.advertisers WHERE id = v_c.advertiser_id;

  IF p_pause THEN
    IF v_c.status NOT IN ('active', 'pending_review', 'paused') THEN
      RAISE EXCEPTION 'Only active or pending campaigns can be paused (current: %)', v_c.status USING ERRCODE = 'P0001';
    END IF;
    v_next_status := 'paused';
  ELSE
    IF v_adv_status <> 'approved' THEN
      RAISE EXCEPTION 'Advertiser account must be approved before resuming' USING ERRCODE = 'P0001';
    END IF;
    IF v_c.approved_at IS NULL THEN
      v_next_status := 'pending_review';
    ELSIF v_c.spent_amount >= v_c.total_budget THEN
      RAISE EXCEPTION 'Campaign budget is exhausted' USING ERRCODE = 'P0001';
    ELSIF v_c.ends_at IS NOT NULL AND v_c.ends_at <= now() THEN
      RAISE EXCEPTION 'Campaign schedule has ended' USING ERRCODE = 'P0001';
    ELSE
      v_next_status := 'active';
    END IF;
  END IF;

  UPDATE public.ad_campaigns
  SET status = v_next_status, updated_at = now()
  WHERE id = p_campaign_id;

  RETURN jsonb_build_object('ok', true, 'campaign_id', p_campaign_id, 'status', v_next_status);
END;
$$;

-- 9. Eligible Ad Delivery RPC (Placement + Schedule + Budget + Targeting + Frequency Cap + Cooldown)
CREATE OR REPLACE FUNCTION public.serve_eligible_ad(
  p_placement text DEFAULT 'feed',
  p_user_id uuid DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_interest text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_uid uuid;
  v_country text := NULLIF(trim(COALESCE(p_country, '')), '');
  v_interest text := NULLIF(trim(COALESCE(p_interest, '')), '');
  v_rec record;
BEGIN
  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore') THEN
    v_placement := 'feed';
  END IF;

  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role' THEN
    v_uid := COALESCE(p_user_id, auth.uid());
  ELSE
    v_uid := auth.uid();
  END IF;

  IF v_uid IS NOT NULL AND v_country IS NULL THEN
    SELECT NULLIF(trim(country), '') INTO v_country
    FROM public.profiles
    WHERE id = v_uid;
  END IF;

  SELECT
    c.id AS campaign_id,
    c.name AS campaign_name,
    c.objective,
    c.placement AS campaign_placement,
    c.pricing_model,
    c.bid_amount,
    c.daily_frequency_cap,
    c.min_cooldown_seconds,
    cr.id AS creative_id,
    cr.title,
    cr.body,
    cr.media_url,
    cr.media_type,
    cr.cta_label,
    cr.destination_url,
    adv.id AS advertiser_id,
    adv.business_name
  INTO v_rec
  FROM public.ad_campaigns c
  JOIN public.advertisers adv ON adv.id = c.advertiser_id
  JOIN public.ad_creatives cr ON cr.campaign_id = c.id
  LEFT JOIN public.ad_targeting t ON t.campaign_id = c.id
  WHERE adv.status = 'approved'
    AND c.status = 'active'
    AND c.approved_at IS NOT NULL
    AND cr.status = 'approved'
    AND (c.placement = v_placement OR c.placement = 'all')
    AND c.starts_at <= now()
    AND (c.ends_at IS NULL OR c.ends_at > now())
    AND c.spent_amount < c.total_budget
    AND (
      CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END
    ) < c.daily_budget
    AND (
      t.id IS NULL
      OR cardinality(t.countries) = 0
      OR (v_country IS NOT NULL AND lower(v_country) = ANY (SELECT lower(x) FROM unnest(t.countries) AS x))
    )
    AND (
      t.id IS NULL
      OR cardinality(t.interests) = 0
      OR (v_interest IS NOT NULL AND lower(v_interest) = ANY (SELECT lower(x) FROM unnest(t.interests) AS x))
    )
    AND (
      v_uid IS NULL
      OR NOT EXISTS (
        SELECT 1 FROM public.ad_frequency_caps fc
        WHERE fc.campaign_id = c.id
          AND fc.user_id = v_uid
          AND fc.window_date = CURRENT_DATE
          AND (
            fc.impressions_today >= c.daily_frequency_cap
            OR (
              c.min_cooldown_seconds > 0
              AND fc.last_shown_at > now() - make_interval(secs => c.min_cooldown_seconds)
            )
          )
      )
    )
  ORDER BY
    (adv.user_id = v_uid) ASC NULLS LAST,
    (c.spent_amount / GREATEST(c.total_budget, 1)) ASC,
    random()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'ad', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'ad', jsonb_build_object(
      'campaign_id', v_rec.campaign_id,
      'creative_id', v_rec.creative_id,
      'advertiser_id', v_rec.advertiser_id,
      'business_name', v_rec.business_name,
      'campaign_name', v_rec.campaign_name,
      'objective', v_rec.objective,
      'placement', v_placement,
      'pricing_model', v_rec.pricing_model,
      'title', v_rec.title,
      'body', v_rec.body,
      'media_url', v_rec.media_url,
      'media_type', v_rec.media_type,
      'cta_label', v_rec.cta_label,
      'destination_url', v_rec.destination_url
    )
  );
END;
$$;

-- 10. Idempotent, Anti-Fraud, Atomic Budget Deduction Event Tracker
CREATE OR REPLACE FUNCTION public.record_ad_event(
  p_event_type text,
  p_campaign_id uuid,
  p_creative_id uuid DEFAULT NULL,
  p_placement text DEFAULT 'feed',
  p_idempotency_key text DEFAULT NULL,
  p_event_name text DEFAULT 'conversion',
  p_conversion_value numeric DEFAULT 0,
  p_viewer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event text := lower(trim(COALESCE(p_event_type, '')));
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_key text := NULLIF(trim(COALESCE(p_idempotency_key, '')), '');
  v_uid uuid;
  v_c public.ad_campaigns%ROWTYPE;
  v_adv_status text;
  v_effective_today numeric(14,6);
  v_unit_cost numeric(14,6) := 0;
  v_remaining_total numeric(14,6) := 0;
  v_actual_cost numeric(14,6) := 0;
  v_fraud_reason text := NULL;
  v_recent_clicks int := 0;
  v_cap_row public.ad_frequency_caps%ROWTYPE;
  v_new_spent numeric(14,6);
  v_new_status text;
BEGIN
  IF v_event NOT IN ('impression', 'click', 'conversion') THEN
    RAISE EXCEPTION 'Invalid ad event_type: %', p_event_type USING ERRCODE = '22023';
  END IF;

  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore', 'all') THEN
    v_placement := 'feed';
  END IF;

  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role' THEN
    v_uid := COALESCE(p_viewer_id, auth.uid());
  ELSE
    v_uid := auth.uid();
  END IF;

  SELECT c.* INTO v_c
  FROM public.ad_campaigns c
  WHERE c.id = p_campaign_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'recorded', false, 'error', 'Campaign not found');
  END IF;

  SELECT status INTO v_adv_status FROM public.advertisers WHERE id = v_c.advertiser_id;

  -- Idempotency short-circuit before fraud/billing checks
  IF v_key IS NOT NULL THEN
    IF v_event = 'impression' AND EXISTS (SELECT 1 FROM public.ad_impressions WHERE idempotency_key = v_key) THEN
      RETURN jsonb_build_object(
        'ok', true, 'recorded', false, 'duplicate', true, 'fraud_flagged', false,
        'cost_charged', 0, 'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
        'campaign_status', v_c.status
      );
    ELSIF v_event = 'click' AND EXISTS (SELECT 1 FROM public.ad_clicks WHERE idempotency_key = v_key) THEN
      RETURN jsonb_build_object(
        'ok', true, 'recorded', false, 'duplicate', true, 'fraud_flagged', false,
        'cost_charged', 0, 'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
        'campaign_status', v_c.status
      );
    ELSIF v_event = 'conversion' AND EXISTS (SELECT 1 FROM public.ad_conversions WHERE idempotency_key = v_key) THEN
      RETURN jsonb_build_object(
        'ok', true, 'recorded', false, 'duplicate', true, 'fraud_flagged', false,
        'cost_charged', 0, 'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
        'campaign_status', v_c.status
      );
    END IF;
  END IF;

  IF v_c.status <> 'active' OR v_adv_status <> 'approved' OR v_c.approved_at IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true, 'recorded', false, 'duplicate', false, 'fraud_flagged', false,
      'cost_charged', 0, 'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
      'campaign_status', v_c.status
    );
  END IF;

  -- Anti-Fraud & Frequency Enforcement
  IF v_event = 'impression' AND v_uid IS NOT NULL THEN
    SELECT * INTO v_cap_row
    FROM public.ad_frequency_caps
    WHERE campaign_id = p_campaign_id AND user_id = v_uid AND window_date = CURRENT_DATE
    FOR UPDATE;

    IF FOUND THEN
      IF v_cap_row.impressions_today >= v_c.daily_frequency_cap THEN
        v_fraud_reason := 'daily_frequency_cap_exceeded';
      ELSIF v_c.min_cooldown_seconds > 0 AND v_cap_row.last_shown_at > now() - make_interval(secs => LEAST(30, v_c.min_cooldown_seconds)) THEN
        v_fraud_reason := 'rapid_impression_burst';
      END IF;
    END IF;
  ELSIF v_event = 'click' AND v_uid IS NOT NULL THEN
    SELECT count(*)::int INTO v_recent_clicks
    FROM public.ad_clicks
    WHERE campaign_id = p_campaign_id
      AND user_id = v_uid
      AND created_at > now() - interval '1 hour';

    IF EXISTS (
      SELECT 1 FROM public.ad_clicks
      WHERE campaign_id = p_campaign_id AND user_id = v_uid AND created_at > now() - interval '15 seconds'
    ) THEN
      v_fraud_reason := 'rapid_click_burst';
    ELSIF v_recent_clicks >= 5 THEN
      v_fraud_reason := 'hourly_click_velocity_exceeded';
    END IF;
  END IF;

  IF v_fraud_reason IS NOT NULL THEN
    IF v_event = 'impression' THEN
      INSERT INTO public.ad_impressions (campaign_id, creative_id, user_id, placement, idempotency_key, cost_charged, is_flagged, flag_reason)
      VALUES (p_campaign_id, p_creative_id, v_uid, v_placement, v_key, 0, true, v_fraud_reason)
      ON CONFLICT (idempotency_key) DO NOTHING;
    ELSIF v_event = 'click' THEN
      INSERT INTO public.ad_clicks (campaign_id, creative_id, user_id, placement, idempotency_key, cost_charged, is_flagged, flag_reason)
      VALUES (p_campaign_id, p_creative_id, v_uid, v_placement, v_key, 0, true, v_fraud_reason)
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
      'ok', true,
      'recorded', false,
      'duplicate', false,
      'fraud_flagged', true,
      'flag_reason', v_fraud_reason,
      'cost_charged', 0,
      'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
      'campaign_status', v_c.status
    );
  END IF;

  -- Compute Cost by Pricing Model
  IF v_event = 'impression' AND v_c.pricing_model = 'CPM' THEN
    v_unit_cost := ROUND(v_c.bid_amount / 1000.0, 6);
  ELSIF v_event = 'click' AND v_c.pricing_model = 'CPC' THEN
    v_unit_cost := ROUND(v_c.bid_amount, 6);
  ELSIF v_event = 'conversion' AND v_c.pricing_model = 'CPA' THEN
    v_unit_cost := ROUND(v_c.bid_amount, 6);
  END IF;

  v_remaining_total := GREATEST(0, v_c.total_budget - v_c.spent_amount);
  v_effective_today := CASE WHEN v_c.spent_today_date = CURRENT_DATE THEN v_c.spent_today ELSE 0 END;

  IF v_remaining_total <= 0 THEN
    UPDATE public.ad_campaigns SET status = 'completed', updated_at = now()
    WHERE id = p_campaign_id AND status = 'active';
    RETURN jsonb_build_object(
      'ok', true, 'recorded', false, 'duplicate', false, 'fraud_flagged', false,
      'cost_charged', 0, 'remaining_budget', 0, 'campaign_status', 'completed'
    );
  END IF;

  v_actual_cost := LEAST(v_unit_cost, v_remaining_total);

  -- Atomic Conditional Budget Update
  UPDATE public.ad_campaigns
  SET
    spent_amount = spent_amount + v_actual_cost,
    spent_today = v_effective_today + v_actual_cost,
    spent_today_date = CURRENT_DATE,
    impressions_count = impressions_count + CASE WHEN v_event = 'impression' THEN 1 ELSE 0 END,
    clicks_count = clicks_count + CASE WHEN v_event = 'click' THEN 1 ELSE 0 END,
    conversions_count = conversions_count + CASE WHEN v_event = 'conversion' THEN 1 ELSE 0 END,
    status = CASE
      WHEN (spent_amount + v_actual_cost) >= total_budget THEN 'completed'
      ELSE status
    END,
    updated_at = now()
  WHERE id = p_campaign_id
    AND status = 'active'
    AND (spent_amount + v_actual_cost) <= total_budget
  RETURNING spent_amount, status INTO v_new_spent, v_new_status;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'recorded', false, 'duplicate', false, 'fraud_flagged', false,
      'cost_charged', 0, 'remaining_budget', GREATEST(0, v_c.total_budget - v_c.spent_amount),
      'campaign_status', v_c.status
    );
  END IF;

  IF v_actual_cost > 0 THEN
    UPDATE public.advertisers
    SET balance = GREATEST(0, balance - v_actual_cost),
        updated_at = now()
    WHERE id = v_c.advertiser_id AND balance > 0;
  END IF;

  IF v_event = 'impression' THEN
    INSERT INTO public.ad_impressions (campaign_id, creative_id, user_id, placement, idempotency_key, cost_charged)
    VALUES (p_campaign_id, p_creative_id, v_uid, v_placement, v_key, v_actual_cost);

    IF v_uid IS NOT NULL THEN
      INSERT INTO public.ad_frequency_caps (campaign_id, user_id, impressions_today, last_shown_at, window_date)
      VALUES (p_campaign_id, v_uid, 1, now(), CURRENT_DATE)
      ON CONFLICT (campaign_id, user_id, window_date) DO UPDATE SET
        impressions_today = public.ad_frequency_caps.impressions_today + 1,
        last_shown_at = now();
    END IF;
  ELSIF v_event = 'click' THEN
    INSERT INTO public.ad_clicks (campaign_id, creative_id, user_id, placement, idempotency_key, cost_charged)
    VALUES (p_campaign_id, p_creative_id, v_uid, v_placement, v_key, v_actual_cost);
  ELSIF v_event = 'conversion' THEN
    INSERT INTO public.ad_conversions (campaign_id, user_id, event_name, value, idempotency_key)
    VALUES (p_campaign_id, v_uid, left(COALESCE(NULLIF(trim(p_event_name), ''), 'conversion'), 64), GREATEST(0, COALESCE(p_conversion_value, 0)), v_key);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'recorded', true,
    'duplicate', false,
    'fraud_flagged', false,
    'cost_charged', v_actual_cost,
    'spent_amount', v_new_spent,
    'remaining_budget', GREATEST(0, v_c.total_budget - v_new_spent),
    'campaign_status', v_new_status
  );
END;
$$;

-- 11. Advertiser Dashboard & Invoice RPCs
CREATE OR REPLACE FUNCTION public.get_my_advertiser_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_campaigns jsonb := '[]'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_totals jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'advertiser', NULL,
      'campaigns', '[]'::jsonb,
      'invoices', '[]'::jsonb,
      'totals', jsonb_build_object(
        'impressions', 0, 'clicks', 0, 'conversions', 0, 'spent', 0, 'ctr', 0
      )
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_json ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_campaigns
  FROM (
    SELECT
      c.created_at,
      jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'objective', c.objective,
        'placement', c.placement,
        'status', c.status,
        'pricing_model', c.pricing_model,
        'bid_amount', c.bid_amount,
        'daily_budget', c.daily_budget,
        'total_budget', c.total_budget,
        'spent_amount', c.spent_amount,
        'spent_today', CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END,
        'impressions_count', c.impressions_count,
        'clicks_count', c.clicks_count,
        'conversions_count', c.conversions_count,
        'ctr', CASE WHEN c.impressions_count > 0 THEN ROUND((c.clicks_count::numeric / c.impressions_count::numeric) * 100.0, 2) ELSE 0 END,
        'daily_frequency_cap', c.daily_frequency_cap,
        'min_cooldown_seconds', c.min_cooldown_seconds,
        'starts_at', c.starts_at,
        'ends_at', c.ends_at,
        'approved_at', c.approved_at,
        'rejection_reason', c.rejection_reason,
        'created_at', c.created_at,
        'creative', (
          SELECT jsonb_build_object(
            'id', cr.id, 'title', cr.title, 'body', cr.body,
            'media_url', cr.media_url, 'media_type', cr.media_type,
            'cta_label', cr.cta_label, 'destination_url', cr.destination_url,
            'status', cr.status
          )
          FROM public.ad_creatives cr
          WHERE cr.campaign_id = c.id
          ORDER BY cr.created_at DESC
          LIMIT 1
        ),
        'targeting', (
          SELECT jsonb_build_object(
            'countries', t.countries, 'languages', t.languages,
            'interests', t.interests, 'min_age', t.min_age,
            'max_age', t.max_age, 'gender', t.gender
          )
          FROM public.ad_targeting t
          WHERE t.campaign_id = c.id
          LIMIT 1
        )
      ) AS row_json
    FROM public.ad_campaigns c
    WHERE c.advertiser_id = v_adv.id
  ) sub;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC), '[]'::jsonb)
  INTO v_invoices
  FROM public.ad_invoices i
  WHERE i.advertiser_id = v_adv.id;

  SELECT jsonb_build_object(
    'impressions', COALESCE(SUM(impressions_count), 0),
    'clicks', COALESCE(SUM(clicks_count), 0),
    'conversions', COALESCE(SUM(conversions_count), 0),
    'spent', ROUND(COALESCE(SUM(spent_amount), 0), 2),
    'ctr', CASE WHEN COALESCE(SUM(impressions_count), 0) > 0
      THEN ROUND((COALESCE(SUM(clicks_count), 0)::numeric / SUM(impressions_count)::numeric) * 100.0, 2)
      ELSE 0 END
  )
  INTO v_totals
  FROM public.ad_campaigns
  WHERE advertiser_id = v_adv.id;

  RETURN jsonb_build_object(
    'ok', true,
    'advertiser', to_jsonb(v_adv),
    'campaigns', v_campaigns,
    'invoices', v_invoices,
    'totals', v_totals
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_advertiser_invoice(p_campaign_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_amount numeric(12,2) := 0;
  v_start timestamptz;
  v_inv public.ad_invoices%ROWTYPE;
  v_inv_no text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advertiser profile not found' USING ERRCODE = 'P0001';
  END IF;

  IF p_campaign_id IS NOT NULL THEN
    SELECT ROUND(COALESCE(spent_amount, 0), 2), starts_at
    INTO v_amount, v_start
    FROM public.ad_campaigns
    WHERE id = p_campaign_id AND advertiser_id = v_adv.id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Campaign not found' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    SELECT ROUND(COALESCE(SUM(spent_amount), 0), 2), MIN(starts_at)
    INTO v_amount, v_start
    FROM public.ad_campaigns
    WHERE advertiser_id = v_adv.id;
  END IF;

  v_inv_no := 'ZEV-INV-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  INSERT INTO public.ad_invoices (
    advertiser_id, campaign_id, invoice_number, amount, currency, status, period_start, period_end, created_at
  ) VALUES (
    v_adv.id, p_campaign_id, v_inv_no, GREATEST(0, COALESCE(v_amount, 0)), v_adv.currency, 'issued', COALESCE(v_start, v_adv.created_at), now(), now()
  )
  RETURNING * INTO v_inv;

  RETURN jsonb_build_object('ok', true, 'invoice', to_jsonb(v_inv));
END;
$$;

-- 12. Explicit Role Grants
REVOKE ALL ON FUNCTION public.claim_lifetime_referral_blue() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_lifetime_referral_blue() TO authenticated;

REVOKE ALL ON FUNCTION public.register_or_update_advertiser(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_or_update_advertiser(text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_ad_campaign_with_creative(
  text, text, text, text, numeric, numeric, numeric, text, text, text, text, text, text,
  text[], text[], text[], integer, integer, text, timestamptz, timestamptz, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ad_campaign_with_creative(
  text, text, text, text, numeric, numeric, numeric, text, text, text, text, text, text,
  text[], text[], text[], integer, integer, text, timestamptz, timestamptz, integer, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.toggle_own_ad_campaign_status(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.toggle_own_ad_campaign_status(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.serve_eligible_ad(text, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.serve_eligible_ad(text, uuid, text, text) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.record_ad_event(text, uuid, uuid, text, text, text, numeric, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_ad_event(text, uuid, uuid, text, text, text, numeric, uuid) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_my_advertiser_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_advertiser_dashboard() TO authenticated;

REVOKE ALL ON FUNCTION public.generate_advertiser_invoice(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_advertiser_invoice(uuid) TO authenticated;
