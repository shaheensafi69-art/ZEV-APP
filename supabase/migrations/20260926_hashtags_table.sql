-- ==============================================================================
-- 69. HASHTAGS SYSTEM FOR ZEV SOCIAL PLATFORM
-- ==============================================================================

CREATE TABLE IF NOT EXISTS hashtags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tag TEXT UNIQUE NOT NULL,
    posts_count INT DEFAULT 0,
    reels_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index on tag for ultra-fast hashtag search and auto-complete
CREATE INDEX IF NOT EXISTS idx_hashtags_tag ON hashtags (tag);
CREATE INDEX IF NOT EXISTS idx_hashtags_posts_count ON hashtags (posts_count DESC);
CREATE INDEX IF NOT EXISTS idx_hashtags_reels_count ON hashtags (reels_count DESC);

-- Table linking posts to hashtags
CREATE TABLE IF NOT EXISTS post_hashtags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES discussion_posts(id) ON DELETE CASCADE,
    hashtag_id UUID REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(post_id, hashtag_id)
);

CREATE INDEX IF NOT EXISTS idx_post_hashtags_post_id ON post_hashtags (post_id);
CREATE INDEX IF NOT EXISTS idx_post_hashtags_hashtag_id ON post_hashtags (hashtag_id);

-- Table linking reels to hashtags
CREATE TABLE IF NOT EXISTS reel_hashtags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    hashtag_id UUID REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(reel_id, hashtag_id)
);

CREATE INDEX IF NOT EXISTS idx_reel_hashtags_reel_id ON reel_hashtags (reel_id);
CREATE INDEX IF NOT EXISTS idx_reel_hashtags_hashtag_id ON reel_hashtags (hashtag_id);

-- Row Level Security (RLS)
ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE reel_hashtags ENABLE ROW LEVEL SECURITY;

-- Public read policies
CREATE POLICY "Public hashtags are viewable by everyone" ON hashtags FOR SELECT USING (true);
CREATE POLICY "Public post_hashtags are viewable by everyone" ON post_hashtags FOR SELECT USING (true);
CREATE POLICY "Public reel_hashtags are viewable by everyone" ON reel_hashtags FOR SELECT USING (true);

-- Authenticated insert/update policies
CREATE POLICY "Authenticated users can insert hashtags" ON hashtags FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can update hashtags" ON hashtags FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can link post hashtags" ON post_hashtags FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can link reel hashtags" ON reel_hashtags FOR ALL USING (auth.role() = 'authenticated');

-- Initial popular trending hashtags for community
INSERT INTO hashtags (tag, posts_count, reels_count)
VALUES 
    ('Technology', 1420, 310),
    ('Photography', 850, 420),
    ('ArtAndDesign', 610, 195),
    ('Education', 1280, 540),
    ('Music', 530, 280),
    ('Lifestyle', 940, 410),
    ('Motivation', 770, 390)
ON CONFLICT (tag) DO UPDATE 
SET posts_count = EXCLUDED.posts_count,
    reels_count = EXCLUDED.reels_count;
