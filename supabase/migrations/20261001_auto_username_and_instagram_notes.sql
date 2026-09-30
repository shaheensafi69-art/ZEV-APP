-- =========================================================================
-- Migration: Auto Username Generator & 24-Hour Instagram-Style User Notes
-- =========================================================================

-- 1. Auto Username Generator function for new and existing users
CREATE OR REPLACE FUNCTION generate_unique_username(p_first_name TEXT, p_last_name TEXT, p_email TEXT)
RETURNS TEXT AS $$
DECLARE
    v_base TEXT;
    v_candidate TEXT;
    v_counter INT := 0;
BEGIN
    -- Construct base username from first_name and last_name
    v_base := lower(regexp_replace(coalesce(trim(p_first_name), '') || '_' || coalesce(trim(p_last_name), ''), '[^a-z0-9_]', '', 'g'));
    v_base := regexp_replace(v_base, '^_+|_+$', '', 'g');
    v_base := regexp_replace(v_base, '_+', '_', 'g');

    -- Fallback to email prefix if base is empty or too short
    IF length(v_base) < 3 THEN
        v_base := lower(regexp_replace(split_part(coalesce(p_email, 'user'), '@', 1), '[^a-z0-9_]', '', 'g'));
    END IF;

    IF length(v_base) < 3 THEN
        v_base := 'zev_user';
    END IF;

    v_candidate := v_base;

    -- Ensure uniqueness in profiles table
    WHILE EXISTS (SELECT 1 FROM profiles WHERE lower(username) = lower(v_candidate)) LOOP
        v_counter := v_counter + 1;
        v_candidate := v_base || '_' || v_counter;
    END LOOP;

    RETURN v_candidate;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger function to automatically assign unique username before insert if missing
CREATE OR REPLACE FUNCTION trg_assign_auto_username()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.username IS NULL OR trim(NEW.username) = '' THEN
        NEW.username := generate_unique_username(NEW.first_name, NEW.last_name, NEW.email);
    ELSE
        -- Ensure clean format (no spaces, no @)
        NEW.username := lower(regexp_replace(trim(replace(NEW.username, '@', '')), '[^a-z0-9_]', '', 'g'));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profiles_auto_username ON profiles;
CREATE TRIGGER trg_profiles_auto_username
BEFORE INSERT OR UPDATE OF first_name, last_name, username ON profiles
FOR EACH ROW
WHEN (NEW.username IS NULL OR trim(NEW.username) = '')
EXECUTE FUNCTION trg_assign_auto_username();

-- 3. Backfill existing profiles that have no username
DO $$
DECLARE
    r RECORD;
    new_un TEXT;
BEGIN
    FOR r IN SELECT id, first_name, last_name, email FROM profiles WHERE username IS NULL OR trim(username) = '' LOOP
        new_un := generate_unique_username(r.first_name, r.last_name, r.email);
        UPDATE profiles SET username = new_un WHERE id = r.id;
    END LOOP;
END $$;

-- 4. Create user_notes table (24-Hour Instagram Style Thought Bubble)
CREATE TABLE IF NOT EXISTS user_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    note_text VARCHAR(60) NOT NULL,
    emoji VARCHAR(10) DEFAULT '',
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + interval '24 hours'),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT user_notes_single_active UNIQUE (user_id)
);

-- Index for instant querying of active notes (B-tree composite index)
CREATE INDEX IF NOT EXISTS idx_user_notes_active ON user_notes(user_id, expires_at DESC);

-- Enable RLS for user_notes
ALTER TABLE user_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view active notes" ON user_notes;
CREATE POLICY "Public can view active notes"
ON user_notes FOR SELECT
TO authenticated, anon
USING (expires_at > NOW());

DROP POLICY IF EXISTS "Users can manage own note" ON user_notes;
CREATE POLICY "Users can manage own note"
ON user_notes FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- =========================================================================
-- Security Fix 1: Enable RLS on public.post_reposts (Resolves Critical Alert)
-- =========================================================================
ALTER TABLE IF EXISTS public.post_reposts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reposts" ON public.post_reposts;
CREATE POLICY "Anyone can view reposts"
ON public.post_reposts FOR SELECT
TO authenticated, anon
USING (true);

DROP POLICY IF EXISTS "Users can insert own reposts" ON public.post_reposts;
CREATE POLICY "Users can insert own reposts"
ON public.post_reposts FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own reposts" ON public.post_reposts;
CREATE POLICY "Users can delete own reposts"
ON public.post_reposts FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- =========================================================================
-- Security Fix 2: Secure Admin Policy on public.profiles (Resolves Critical Alert)
-- Replaces insecure user_metadata reference with app_metadata or profiles.role check
-- =========================================================================
DROP POLICY IF EXISTS "Allow admin full update access" ON public.profiles;

CREATE POLICY "Allow admin full update access"
ON public.profiles FOR UPDATE
TO authenticated
USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    OR (auth.jwt() -> 'app_metadata' ->> 'is_admin')::boolean = true
    OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND (role = 'admin' OR is_admin = true)
    )
)
WITH CHECK (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    OR (auth.jwt() -> 'app_metadata' ->> 'is_admin')::boolean = true
    OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND (role = 'admin' OR is_admin = true)
    )
);
