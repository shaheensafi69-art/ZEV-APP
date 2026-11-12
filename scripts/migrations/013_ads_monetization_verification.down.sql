-- 013_ads_monetization_verification.down.sql

REVOKE ALL ON FUNCTION public.generate_advertiser_invoice(uuid) FROM authenticated;
DROP FUNCTION IF EXISTS public.generate_advertiser_invoice(uuid);

REVOKE ALL ON FUNCTION public.get_my_advertiser_dashboard() FROM authenticated;
DROP FUNCTION IF EXISTS public.get_my_advertiser_dashboard();

REVOKE ALL ON FUNCTION public.record_ad_event(text, uuid, uuid, text, text, text, numeric, uuid) FROM anon, authenticated, service_role;
DROP FUNCTION IF EXISTS public.record_ad_event(text, uuid, uuid, text, text, text, numeric, uuid);

REVOKE ALL ON FUNCTION public.serve_eligible_ad(text, uuid, text, text) FROM anon, authenticated, service_role;
DROP FUNCTION IF EXISTS public.serve_eligible_ad(text, uuid, text, text);

REVOKE ALL ON FUNCTION public.toggle_own_ad_campaign_status(uuid, boolean) FROM authenticated;
DROP FUNCTION IF EXISTS public.toggle_own_ad_campaign_status(uuid, boolean);

REVOKE ALL ON FUNCTION public.create_ad_campaign_with_creative(
  text, text, text, text, numeric, numeric, numeric, text, text, text, text, text, text,
  text[], text[], text[], integer, integer, text, timestamptz, timestamptz, integer, integer
) FROM authenticated;
DROP FUNCTION IF EXISTS public.create_ad_campaign_with_creative(
  text, text, text, text, numeric, numeric, numeric, text, text, text, text, text, text,
  text[], text[], text[], integer, integer, text, timestamptz, timestamptz, integer, integer
);

REVOKE ALL ON FUNCTION public.register_or_update_advertiser(text, text, text) FROM authenticated;
DROP FUNCTION IF EXISTS public.register_or_update_advertiser(text, text, text);

REVOKE ALL ON FUNCTION public.claim_lifetime_referral_blue() FROM authenticated;
DROP FUNCTION IF EXISTS public.claim_lifetime_referral_blue();

DROP TRIGGER IF EXISTS tr_protect_ad_creative_columns ON public.ad_creatives;
DROP FUNCTION IF EXISTS public.protect_ad_creative_columns();

DROP TRIGGER IF EXISTS tr_protect_ad_campaign_columns ON public.ad_campaigns;
DROP FUNCTION IF EXISTS public.protect_ad_campaign_columns();

DROP TRIGGER IF EXISTS tr_protect_advertiser_columns ON public.advertisers;
DROP FUNCTION IF EXISTS public.protect_advertiser_columns();

DROP POLICY IF EXISTS ad_targeting_manage_owner ON public.ad_targeting;
CREATE POLICY ad_targeting_manage_owner ON public.ad_targeting
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS ad_targeting_select_owner ON public.ad_targeting;

DROP POLICY IF EXISTS ad_creatives_manage_owner ON public.ad_creatives;
CREATE POLICY ad_creatives_manage_owner ON public.ad_creatives
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  );

DROP INDEX IF EXISTS idx_ad_clicks_flagged;
DROP INDEX IF EXISTS idx_ad_impressions_flagged;
DROP INDEX IF EXISTS idx_ad_clicks_campaign_user_time;
DROP INDEX IF EXISTS idx_ad_impressions_campaign_user_time;
DROP INDEX IF EXISTS idx_ad_creatives_campaign_status;
DROP INDEX IF EXISTS idx_ad_campaigns_eligible;

ALTER TABLE public.ad_clicks
  DROP COLUMN IF EXISTS flag_reason,
  DROP COLUMN IF EXISTS is_flagged;

ALTER TABLE public.ad_impressions
  DROP COLUMN IF EXISTS flag_reason,
  DROP COLUMN IF EXISTS is_flagged;

ALTER TABLE public.ad_invoices DROP CONSTRAINT IF EXISTS ad_invoices_status_check;
ALTER TABLE public.ad_creatives DROP CONSTRAINT IF EXISTS ad_creatives_status_check;
ALTER TABLE public.ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_positive_budgets_check;
ALTER TABLE public.ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_cooldown_check;
ALTER TABLE public.ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_daily_freq_cap_check;

ALTER TABLE public.ad_campaigns
  ALTER COLUMN spent_amount TYPE numeric(12,2) USING ROUND(spent_amount, 2),
  DROP COLUMN IF EXISTS rejection_reason,
  DROP COLUMN IF EXISTS approved_at,
  DROP COLUMN IF EXISTS spent_today_date,
  DROP COLUMN IF EXISTS spent_today,
  DROP COLUMN IF EXISTS min_cooldown_seconds,
  DROP COLUMN IF EXISTS daily_frequency_cap;

-- Restore prior expire_stale_subscriptions() definition from Phase 5 baseline
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
    RETURNING uv.user_id
  ),
  upd_p AS (
    UPDATE public.profiles p
    SET is_verified = false,
        updated_at = now()
    WHERE p.id IN (SELECT user_id FROM exp_v)
      AND COALESCE(p.lifetime_blue_eligible, false) = false
    RETURNING p.id
  )
  SELECT count(*) INTO v_expired_verifs FROM upd_p;

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
