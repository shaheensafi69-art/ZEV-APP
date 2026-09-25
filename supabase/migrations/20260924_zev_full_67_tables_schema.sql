-- ==============================================================================
-- ZEV PLATFORM COMPLETE DATABASE SCHEMA (67 TABLES + SOCIAL EXTENSIONS)
-- Domain: zevapp.com | Generated for Supabase & PostgreSQL
-- Includes all 67 requested tables with types, constraints, and RLS policies
-- ==============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 31. PROFILES (Base user table linked to auth.users)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    father_name TEXT,
    date_of_birth DATE,
    email TEXT UNIQUE,
    phone_number TEXT,
    country TEXT,
    preferred_language TEXT DEFAULT 'en',
    role TEXT DEFAULT 'STUDENT',
    avatar_url TEXT,
    cover_image_url TEXT,
    bio TEXT,
    total_score INT DEFAULT 0,
    wallet_balance NUMERIC(14,2) DEFAULT 0.00,
    referral_code TEXT UNIQUE,
    referral_link TEXT,
    referral_discount_rate NUMERIC(5,2) DEFAULT 0.00,
    referred_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    fcm_token TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 1. AI_CHAT_HISTORY
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_chat_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    user_prompt TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 2. ANNOUNCEMENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    target_role TEXT DEFAULT 'ALL',
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 16. COURSES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    title TEXT NOT NULL,
    description TEXT,
    category TEXT,
    teacher_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    price NUMERIC(10,2) DEFAULT 0.00,
    thumbnail_url TEXT,
    is_published BOOLEAN DEFAULT true,
    instructor_name TEXT,
    instructor_bio TEXT,
    instructor_image_url TEXT,
    instructor_2_name TEXT,
    instructor_2_bio TEXT,
    instructor_2_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 9. CLASS_GROUPS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    class_name TEXT NOT NULL,
    schedule_info TEXT,
    start_date DATE,
    end_date DATE,
    meeting_link TEXT,
    signal_group_link TEXT,
    class_time TEXT,
    class_days TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 4. ASSIGNMENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    class_group_id UUID REFERENCES class_groups(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    deadline TIMESTAMPTZ,
    max_score INT DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 3. ASSIGNMENT_SUBMISSIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS assignment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID REFERENCES assignments(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    grade NUMERIC(5,2),
    feedback TEXT,
    submitted_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 5. ATTENDANCE_LOGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_group_id UUID REFERENCES class_groups(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    status TEXT NOT NULL, -- 'PRESENT', 'ABSENT', 'LATE'
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 6. AWARDS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS awards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    icon_url TEXT,
    points_required INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 7. BLOGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS blogs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    title TEXT NOT NULL,
    slug TEXT UNIQUE,
    content TEXT,
    author_name TEXT,
    cover_image TEXT,
    category TEXT,
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 8. CERTIFICATES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    certificate_code TEXT UNIQUE NOT NULL,
    issue_date DATE DEFAULT CURRENT_DATE,
    certificate_url TEXT NOT NULL
);

-- ------------------------------------------------------------------------------
-- 10. CLASS_MESSAGES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_group_id UUID REFERENCES class_groups(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    message_text TEXT NOT NULL,
    attachment_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 11. CLASS_RECORDINGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_recordings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_group_id UUID REFERENCES class_groups(id) ON DELETE CASCADE,
    video_url TEXT NOT NULL,
    duration_minutes INT DEFAULT 0,
    recorded_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 12. CLASS_STUDENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_group_id UUID REFERENCES class_groups(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT now(),
    is_paid BOOLEAN DEFAULT false,
    is_trial BOOLEAN DEFAULT false,
    trial_ends_at TIMESTAMPTZ,
    UNIQUE(class_group_id, student_id)
);

-- ------------------------------------------------------------------------------
-- 13. COUPONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    discount_percentage NUMERIC(5,2) NOT NULL,
    max_uses INT DEFAULT 100,
    used_count INT DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 14. COURSE_REVIEWS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS course_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment_text TEXT,
    is_approved BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 15. COURSE_SECTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS course_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    section_order INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 28. LESSONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lessons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    section_id UUID REFERENCES course_sections(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    video_url TEXT,
    content_text TEXT,
    lesson_order INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 17. DEVICE_ACTIVITIES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    device_name TEXT,
    country TEXT,
    city TEXT,
    ip_address TEXT,
    logged_in_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 18. DIRECT_MESSAGES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    message_text TEXT NOT NULL,
    attachment_url TEXT,
    attachment_type TEXT,
    is_delivered BOOLEAN DEFAULT false,
    is_read BOOLEAN DEFAULT false,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 22. DISCUSSION_POSTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discussion_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 19. DISCUSSION_BOOKMARKS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discussion_bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES discussion_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(post_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 20. DISCUSSION_COMMENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discussion_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES discussion_posts(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES discussion_comments(id) ON DELETE CASCADE,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 21. DISCUSSION_LIKES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discussion_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES discussion_posts(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(post_id, student_id)
);

-- ------------------------------------------------------------------------------
-- 23. DONATION_CAMPAIGNS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS donation_campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    title TEXT NOT NULL,
    goal_amount NUMERIC(14,2) DEFAULT 0.00,
    raised_amount NUMERIC(14,2) DEFAULT 0.00,
    currency TEXT DEFAULT 'USD',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 24. ENROLLMENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    progress_percentage NUMERIC(5,2) DEFAULT 0.00,
    enrolled_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(student_id, course_id)
);

-- ------------------------------------------------------------------------------
-- 25. GRADUATES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS graduates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    class_group_id UUID REFERENCES class_groups(id) ON DELETE SET NULL,
    graduation_date DATE,
    final_score NUMERIC(5,2),
    letter_grade TEXT,
    testimonial TEXT,
    is_featured_on_wall BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 26. INSTRUCTOR_APPLICATIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS instructor_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    country TEXT,
    date_of_birth DATE,
    language TEXT,
    category TEXT,
    course_title TEXT,
    course_description TEXT,
    experience_level TEXT,
    teaching_format TEXT,
    bio TEXT,
    achievements TEXT,
    portfolio_url TEXT,
    sample_video_url TEXT,
    resume_url TEXT,
    avatar_url TEXT,
    status TEXT DEFAULT 'PENDING',
    admin_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 27. LESSON_NOTES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lesson_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    lesson_id UUID REFERENCES lessons(id) ON DELETE CASCADE,
    timestamp_seconds INT DEFAULT 0,
    note_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 29. MESSAGE_REACTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES direct_messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(message_id, user_id, emoji)
);

-- ------------------------------------------------------------------------------
-- 30. PARTNERS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    name TEXT NOT NULL,
    slug TEXT UNIQUE,
    logo_url TEXT,
    website_url TEXT,
    description TEXT,
    nda_file_url TEXT,
    nda_signed_date DATE,
    nda_expiry_date DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 35. QUIZZES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    class_group_id UUID REFERENCES class_groups(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    passing_score NUMERIC(5,2) DEFAULT 70.00,
    quiz_type TEXT DEFAULT 'GENERAL',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 32. QUIZ_ATTEMPTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    quiz_id UUID REFERENCES quizzes(id) ON DELETE CASCADE,
    score NUMERIC(5,2) DEFAULT 0.00,
    is_passed BOOLEAN DEFAULT false,
    attempted_at TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'COMPLETED',
    letter_grade TEXT,
    teacher_general_feedback TEXT
);

-- ------------------------------------------------------------------------------
-- 33. QUIZ_QUESTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quiz_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID REFERENCES quizzes(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    option_a TEXT NOT NULL,
    option_b TEXT NOT NULL,
    option_c TEXT,
    option_d TEXT,
    correct_option TEXT NOT NULL,
    points INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 34. QUIZ_STUDENT_ANSWERS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quiz_student_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_id UUID REFERENCES quiz_questions(id) ON DELETE CASCADE,
    student_answer_text TEXT,
    points_earned NUMERIC(5,2) DEFAULT 0.00,
    is_correct BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 39. REELS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    video_url TEXT NOT NULL,
    thumbnail_url TEXT,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT,
    duration_seconds INT DEFAULT 0,
    views_count INT DEFAULT 0,
    likes_count INT DEFAULT 0,
    comments_count INT DEFAULT 0,
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 36. REEL_COMMENTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reel_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 37. REEL_LIKES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reel_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(reel_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 38. REEL_VIEWS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reel_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    viewer_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    viewed_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 66. REEL_BOOKMARKS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reel_bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(reel_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 40. REFERRALS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    referred_student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    reward_amount NUMERIC(10,2) DEFAULT 0.00,
    is_paid BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 41. SCHEDULED_NOTIFICATIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scheduled_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    is_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 42. SCHOLARSHIPS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scholarships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_group_id UUID DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    title TEXT NOT NULL,
    slug TEXT UNIQUE,
    continent TEXT,
    country TEXT,
    university TEXT,
    degree_level TEXT,
    deadline DATE,
    description TEXT,
    eligibility_criteria TEXT,
    required_documents TEXT,
    apply_link TEXT,
    cover_image TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 60. USER_STORIES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_stories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    media_url TEXT NOT NULL,
    media_type TEXT DEFAULT 'IMAGE', -- 'IMAGE', 'VIDEO', 'NOTE'
    caption TEXT,
    duration_seconds INT DEFAULT 15,
    expires_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '24 hours'),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 43. STORY_LIKES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS story_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID REFERENCES user_stories(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(story_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 44. STORY_VIEWS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS story_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID REFERENCES user_stories(id) ON DELETE CASCADE,
    viewer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(story_id, viewer_id)
);

-- ------------------------------------------------------------------------------
-- 45. STUDENT_AWARDS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_awards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    award_id UUID REFERENCES awards(id) ON DELETE CASCADE,
    awarded_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(student_id, award_id)
);

-- ------------------------------------------------------------------------------
-- 46. STUDENT_FRIENDS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_friends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'PENDING', -- 'PENDING', 'ACCEPTED', 'REJECTED'
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(sender_id, receiver_id)
);

-- ------------------------------------------------------------------------------
-- 67. USER_FOLLOWS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    following_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(follower_id, following_id)
);

-- ------------------------------------------------------------------------------
-- 47. STUDENT_LESSON_PROGRESS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_lesson_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    lesson_id UUID REFERENCES lessons(id) ON DELETE CASCADE,
    is_completed BOOLEAN DEFAULT false,
    watched_duration_seconds INT DEFAULT 0,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(student_id, lesson_id)
);

-- ------------------------------------------------------------------------------
-- 48. STUDENT_SECURITY_SETTINGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_security_settings (
    student_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    pin_code TEXT,
    is_biometric_enabled BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 49. STUDENT_STREAKS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_streaks (
    student_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    current_streak INT DEFAULT 0,
    longest_streak INT DEFAULT 0,
    last_activity_date DATE DEFAULT CURRENT_DATE,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 50. SUBSCRIPTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    plan_name TEXT NOT NULL,
    status TEXT DEFAULT 'ACTIVE',
    start_date TIMESTAMPTZ DEFAULT now(),
    end_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 51. TEACHER_INFO
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teacher_info (
    id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    date_of_birth DATE,
    bio TEXT,
    achievements TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 52. TEACHER_INFO_COURSES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teacher_info_courses (
    teacher_info_id UUID REFERENCES teacher_info(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    PRIMARY KEY (teacher_info_id, course_id)
);

-- ------------------------------------------------------------------------------
-- 53. TEACHER_NOTES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teacher_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    note_text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 54. TEACHER_TODOS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teacher_todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    task_text TEXT NOT NULL,
    is_completed BOOLEAN DEFAULT false,
    due_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 56. TICKETS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    department TEXT NOT NULL,
    status TEXT DEFAULT 'OPEN',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 55. TICKET_MESSAGES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES tickets(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    message_text TEXT NOT NULL,
    attachment_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 57. TRADING_JOURNALS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trading_journals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    trade_date DATE DEFAULT CURRENT_DATE,
    symbol TEXT NOT NULL,
    position_type TEXT NOT NULL, -- 'BUY', 'SELL'
    setup_strategy TEXT,
    lot_size NUMERIC(10,4),
    entry_price NUMERIC(14,5),
    stop_loss NUMERIC(14,5),
    take_profit NUMERIC(14,5),
    exit_price NUMERIC(14,5),
    profit_loss_usd NUMERIC(14,2),
    rr_multiple NUMERIC(6,2),
    emotions TEXT,
    analysis_notes TEXT,
    chart_image_url TEXT,
    teacher_score NUMERIC(5,2),
    teacher_feedback TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 58. TRANSACTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    amount NUMERIC(14,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    transaction_type TEXT NOT NULL,
    status TEXT DEFAULT 'PENDING',
    payment_gateway TEXT,
    reference_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 59. USER_NOTIFICATIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    notification_type TEXT,
    link_url TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 61. WALLET_TRANSACTIONS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    amount NUMERIC(14,2) NOT NULL,
    transaction_type TEXT NOT NULL,
    description TEXT,
    reference_id TEXT,
    status TEXT DEFAULT 'SUCCESS',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 62. WISHLISTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wishlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(student_id, course_id)
);

-- ------------------------------------------------------------------------------
-- 63. RESELLER_PRODUCTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reseller_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_product_id TEXT,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    cost_price NUMERIC(14,2) NOT NULL,
    profit_type TEXT DEFAULT 'FIXED',
    profit_margin NUMERIC(10,2) DEFAULT 0.00,
    selling_price NUMERIC(14,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    in_stock BOOLEAN DEFAULT true,
    is_active BOOLEAN DEFAULT true,
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 64. RESELLER_ORDERS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reseller_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    product_id UUID REFERENCES reseller_products(id) ON DELETE CASCADE,
    external_order_id TEXT,
    cost_price NUMERIC(14,2) NOT NULL,
    sale_price NUMERIC(14,2) NOT NULL,
    profit_amount NUMERIC(14,2) NOT NULL,
    order_payload JSONB,
    api_response JSONB,
    status TEXT DEFAULT 'PENDING',
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 65. RESELLER_SYNC_LOGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reseller_sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    items_updated INT DEFAULT 0,
    status TEXT DEFAULT 'SUCCESS',
    log_details TEXT,
    synced_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- ADDITIONAL SOCIAL EXTENSIONS (Instagram Notes & Reposts)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    note_text VARCHAR(60) NOT NULL,
    expires_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '24 hours'),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

CREATE TABLE IF NOT EXISTS post_reposts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    post_id UUID REFERENCES discussion_posts(id) ON DELETE CASCADE,
    reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE discussion_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reels ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notes ENABLE ROW LEVEL SECURITY;

-- Read policies (Public feed & profiles)
CREATE POLICY "Public profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Public posts are viewable by everyone" ON discussion_posts FOR SELECT USING (true);
CREATE POLICY "Public reels are viewable by everyone" ON reels FOR SELECT USING (true);
CREATE POLICY "Public stories are viewable by everyone" ON user_stories FOR SELECT USING (expires_at > now());
CREATE POLICY "Public user notes are viewable by everyone" ON user_notes FOR SELECT USING (expires_at > now());
CREATE POLICY "Public follows are viewable by everyone" ON user_follows FOR SELECT USING (true);

-- User write policies
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own posts" ON discussion_posts FOR INSERT WITH CHECK (auth.uid() = student_id);
CREATE POLICY "Users can insert own reels" ON reels FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can insert own stories" ON user_stories FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can insert or update own note" ON user_notes FOR ALL USING (auth.uid() = user_id);

-- Direct messaging policies (Only sender or receiver)
CREATE POLICY "Users can read their own direct messages" ON direct_messages FOR SELECT 
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send direct messages" ON direct_messages FOR INSERT 
WITH CHECK (auth.uid() = sender_id);

-- Realtime enablement
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE user_notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE reel_likes;
ALTER PUBLICATION supabase_realtime ADD TABLE reel_comments;
ALTER PUBLICATION supabase_realtime ADD TABLE discussion_likes;
