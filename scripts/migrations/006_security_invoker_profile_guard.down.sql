-- 006_security_invoker_profile_guard.down.sql
ALTER FUNCTION public.protect_profile_privileged_columns() SECURITY DEFINER;

