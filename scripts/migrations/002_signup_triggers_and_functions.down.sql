-- 002_signup_triggers_and_functions.down.sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_auth_user();
DROP FUNCTION IF EXISTS public.expire_stale_subscriptions();
DROP FUNCTION IF EXISTS public.is_username_available(text);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'discussion_posts_student_id_fkey') THEN
    ALTER TABLE public.discussion_posts DROP CONSTRAINT discussion_posts_student_id_fkey;
  END IF;
  ALTER TABLE public.discussion_posts
    ADD CONSTRAINT discussion_posts_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES auth.users(id) ON DELETE CASCADE;
END $$;

