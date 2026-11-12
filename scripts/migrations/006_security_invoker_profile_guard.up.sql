-- 006_security_invoker_profile_guard.up.sql
-- Make protect_profile_privileged_columns SECURITY INVOKER so current_user reflects
-- the actual invoking role ('authenticated'/'anon' for direct REST writes, 'postgres'
-- inside trusted SECURITY DEFINER triggers/RPCs, or 'service_role' via backend admin).

CREATE OR REPLACE FUNCTION public.protect_profile_privileged_columns()
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

  IF NEW.is_verified IS DISTINCT FROM OLD.is_verified
     OR NEW.lifetime_blue_eligible IS DISTINCT FROM OLD.lifetime_blue_eligible
     OR NEW.referral_count IS DISTINCT FROM OLD.referral_count
     OR NEW.referred_by IS DISTINCT FROM OLD.referred_by
     OR NEW.is_restricted IS DISTINCT FROM OLD.is_restricted
     OR NEW.restricted_until IS DISTINCT FROM OLD.restricted_until
     OR NEW.restriction_reason IS DISTINCT FROM OLD.restriction_reason
     OR NEW.warning_count IS DISTINCT FROM OLD.warning_count
     OR NEW.last_warning_at IS DISTINCT FROM OLD.last_warning_at
     OR NEW.last_warning_reason IS DISTINCT FROM OLD.last_warning_reason
     OR NEW.is_banned IS DISTINCT FROM OLD.is_banned
     OR NEW.banned_until IS DISTINCT FROM OLD.banned_until
     OR NEW.ban_reason IS DISTINCT FROM OLD.ban_reason
     OR NEW.account_status IS DISTINCT FROM OLD.account_status
     OR NEW.followers_count IS DISTINCT FROM OLD.followers_count
     OR NEW.following_count IS DISTINCT FROM OLD.following_count
     OR NEW.posts_count IS DISTINCT FROM OLD.posts_count
     OR NEW.reels_count IS DISTINCT FROM OLD.reels_count THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected profile attributes'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

