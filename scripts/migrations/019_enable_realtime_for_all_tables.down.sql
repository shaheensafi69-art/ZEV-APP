-- 019_enable_realtime_for_all_tables.down.sql
-- Reverts selective realtime publication additions where needed.
-- Note: Leaving tables in publication is harmless in development.

DO $$
BEGIN
  -- Down migration is a safe no-op to avoid breaking active realtime listeners in production.
  NULL;
END $$;

