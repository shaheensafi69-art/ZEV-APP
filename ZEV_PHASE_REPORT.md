# ZEV — Phase Execution Report

This document tracks verified checks, schema changes, migrations, modified files, test results, rollback readiness, and remaining work after every phase of the ZEV Engineering Transformation Roadmap.

---

## Phase 0 — Complete System Audit & Pre-Migration Backup
**Status**: Completed (`2026-11-12`)

### 1. What Was Audited
- **Flutter Application (`/Users/Safi_Sahib/zev-app`)**: `pubspec.yaml`, `vercel-build.sh`, `lib/main.dart`, auth/session/OAuth services (`AuthHelper`, `GoogleAuthService`, `MfaService`, `MultiAccountService`, `PasskeyAuthService`, `RegisterScreen`, `LoginScreen`, `GoogleProfileCompletionScreen`), storage/safety/Telegram services (`CloudflareStorageService`, `ContentSafetyService`, `TelegramNotificationService`), deep links & notifications (`DeepLinkService`, `NotificationService`, `NotificationSettingsScreen`, `NotificationsScreen`), social/profile/activity/highlights (`ProfileScreen`, `ContentDeletionService`, `FeedShareSheet`, `UserActivityScreen`, `ActivityLikesScreen`, `StoryHighlightService`), video/ads/presence (`ZevVideoThumbnail`, `ReelVideoCacheManager`, `ZevNativeAd*`, `UserPresenceService`), plus Android/iOS configs (`AndroidManifest.xml`, `google-services.json`, `Info.plist`, `GoogleService-Info.plist`, Release & Debug keystores).
- **Web & API Repository (`/Users/Safi_Sahib/zev-web`)**: `package.json`, `src/app/api/delete-account/route.ts`, `src/app/api/assetlinks/route.ts`, `public/.well-known/assetlinks.json`, `cloudflare-worker-assetlinks.js`, `src/app/[locale]/delete-account/page.tsx`.
- **Supabase PostgreSQL (`zjwmioalrhkyfbzhdnnw.supabase.co`, PG 17.11)**: All 35 `public` tables, 1 view (`notifications`), 305 constraints (35 PK, 55 FK, 77 Unique, 0 explicit CHECK), indexes, triggers, functions, RLS policies, Realtime publications, FCM token distribution, and orphan/counter drift checks.
- **Cloudflare R2 (`safiacademy-media`)**: Full bucket object scan (`133` objects / `531.17 MB`), isolated `zev/` audit (`12` objects / `9.39 MB`, `3` orphaned `5.43 MB`), CORS, and HTTP `Cache-Control` headers.
- **Firebase (`zevapp-3c6b5`)**: Android & iOS project registrations, FCM token state, local CLI/service-account credential availability.

### 2. Issues Discovered
- **55 `auth.users` vs. 44 `profiles`** (11 orphaned accounts due to `RegisterScreen` upserting nonexistent `'role': 'student'`).
- **3 redundant FCM columns** (`zev_fmc`, `zev_fcm`, `fcm_token`) with one active account (`shaheensafi011`) having their valid token only in `zev_fmc`.
- **Orphans & Drift**: 5 orphan `discussion_likes`, 238 orphan `user_notifications`, 2 `reels` with `likes_count=0` vs. actual `1`, 0 FKs on `discussion_likes.student_id` / `discussion_comments.student_id` / `user_notifications.user_id`.
- **Broken Functions & Policies**: `notify_on_reel_comment()` (`NEW.comment`), conflicting username regex/generators, broken `get_admin_dashboard_stats()`, anonymous `INSERT/UPDATE/DELETE` on `reels`/`reel_*`, and **6 RLS-enabled tables with zero policies**.
- **Client Secrets & Storage**: `.env` bundled in `pubspec.yaml`, hardcoded Telegram bot tokens in Dart, plaintext password secret in `SharedPreferences`, obsolete `enpuoypqpklndnnhndax` fallback in `vercel-build.sh`.
- **Google OAuth & AssetLinks**: Web Client ID used as `iosClientId`, empty `oauth_client` in `google-services.json`, truncated 31-octet SHA-256 hashes in all 3 `assetlinks.json` targets.
- **UI/UX & Functional Bugs**: Missing `firebase_options.dart`, missing Firebase Admin service account JSON locally, 9 duplicate screen/sheet pairs, wrong table/column queries (`story_highlights`, `post_bookmarks`, `user_id` vs `student_id`, `reels.caption`), dark ad widgets vs Clearmorphism, light-text contrast bug on `/[locale]/delete-account`, and 3 orphaned `zev/` files in R2.

### 3. Changes Made
- Zero schema or application code mutations were made during Phase 0.
- Updated `/Users/Safi_Sahib/zev-app/.gitignore` to protect `/backups/` and `/scripts/migrations/*.env`.
- Generated full Phase 0 backup:
  - `/Users/Safi_Sahib/zev-app/backups/pre_migration_backup.sql` (429,054 bytes)
  - `/Users/Safi_Sahib/zev-app/backups/pre_migration_backup.dump` (229,560 bytes, 405 TOC entries)
- Published `/Users/Safi_Sahib/zev-app/ZEV_AUDIT_REPORT.md` and initialized `/Users/Safi_Sahib/zev-app/ZEV_PHASE_REPORT.md`.

### 4. Verification & Test Results
- `pg_dump --version` (`18.6`) backup completed with exit code `0`.
- `pg_restore --list pre_migration_backup.dump` verified 405 TOC entries cleanly.
- Live PostgreSQL, R2, and Keystore verification probes executed and logged with zero data loss or modification.

### 5. Rollback Status
- Full cold backup verified and stored locally outside Git. Ready to begin non-destructive Phase 1 implementation.

### 6. Next Phase
- **Phase 1 — Infrastructure, Authentication, Session Security, Google OAuth, Deep Links & `/api/v1/*` Backend API**

---

## Phase 1A & 1B — Server API Foundation, AssetLinks & Web Contrast
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Next.js backend (`/Users/Safi_Sahib/zev-web`), Cloudflare R2 `zev/` prefix upload/delete contracts, AssetLinks Android signing certificates (Release & Debug SHA-256), Google Vision / Gemini safety moderation, Telegram webhook/bot notifications, Firebase Messaging HTTP v1 requirements, and contrast accessibility on `zevapp.com`.

### 2. Issues Discovered
- Mobile client held R2 S3 credentials, Google Vision/Gemini keys, and Telegram bot tokens directly in bundled `.env`.
- `assetlinks.json` (static, dynamic route, and Cloudflare worker) carried truncated 31-octet SHA-256 hashes instead of full 32-byte colon-hex SHA-256 digests.
- Light-on-light contrast bugs on `/[locale]/delete-account`, `privacy`, `terms`, `support`, `AppMockup`, and `DownloadModal`.
- Client-side `user_verifications` / `subscriptions` writes risked overwriting active subscriptions and lacked atomic server validation.

### 3. Changes Made
- Created server-only helpers under `/Users/Safi_Sahib/zev-web/src/lib/server/`: `supabaseAdmin.ts`, `r2Signer.ts`, `telegram.ts`, `fcm.ts`.
- Implemented `/Users/Safi_Sahib/zev-web/src/app/api/v1/` authenticated routes:
  - `media/presign`, `media/delete` (strict `zev/` prefix enforcement & ownership checks)
  - `safety/moderate`, `support/ticket`, `verification/request`, `push/send`, `referral/claim`, `account/export`, `account/deactivate`
  - Refactored `/api/delete-account` to clean up `zev/` media safely and preserve referential integrity.
- Updated `public/.well-known/assetlinks.json`, `src/app/api/assetlinks/route.ts`, and `cloudflare-worker-assetlinks.js` with full 32-byte Release + Debug SHA-256 fingerprints.
- Fixed light-on-light text contrast bugs across web pages/components.

### 4. Verification & Test Results
- `npm --prefix /Users/Safi_Sahib/zev-web run build` exited with code `0` (Next.js `15.5.26`).
- End-to-end R2 presign/PUT/HEAD/DELETE smoke test under `zev/` exited with code `0`.
- Remaining deployment dependency tracked for owner: add `FIREBASE_SERVICE_ACCOUNT_JSON` on Vercel for `zev-web` HTTP v1 push dispatch.

---

## Phase 1C — Flutter Session Persistence, Secure Storage, Zero Client Secrets & OAuth/Deep Link Fixes
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- `pubspec.yaml`, `vercel-build.sh`, `lib/main.dart`, `AndroidManifest.xml`, `build.gradle.kts`, all auth screens (`RegisterScreen`, `LoginScreen`, `GoogleProfileCompletionScreen`, `ForgotPasswordScreen`), and all client services (`AuthHelper`, `GoogleAuthService`, `PasskeyAuthService`, `MfaService`, `MultiAccountService`, `CloudflareStorageService`, `ContentSafetyService`, `TelegramNotificationService`, `DeepLinkService`, `ZevSplashScreen`, `ZevBlueVerificationScreen`, `HelpSupportScreen`, `HelpSupportSheet`).

### 2. Issues Discovered
- `.env` bundled as a Flutter asset with `flutter_dotenv` exposing secrets.
- `RegisterScreen` attempted `profiles.upsert({ 'role': 'student' })` even though `profiles` has no `role` column (root cause of 11 orphaned `auth.users` rows). Also mishandled auto-confirmed sessions (`authResponse.session != null`) and empty `date_of_birth`.
- `AuthHelper` wrote to all 3 legacy FCM columns (`zev_fmc`, `zev_fcm`, `fcm_token`) and ran global `push_subscriptions` deletes on logout across devices.
- Passkey secrets (`zev_pk_secret_*`) were stored in plaintext `SharedPreferences`.
- Cold-start deep links relied on a racy `Future.delayed(700ms)`.
- `HelpSupportScreen` / `HelpSupportSheet` simulated ticket creation with a `600ms` stub and random IDs.

### 3. Changes Made
- Removed `flutter_dotenv` and `- .env` asset from `pubspec.yaml` and `vercel-build.sh` (removed legacy `enpuoypqpklndnnhndax` / `safiacademy.org` fallbacks); added `flutter_secure_storage: ^9.2.4` and `flutter_local_notifications: ^18.0.1` + core library desugaring in `android/app/build.gradle.kts`.
- Created `lib/core/config/app_config.dart`, `lib/core/services/secure_local_storage.dart`, `lib/core/services/auth_session_manager.dart`, and `lib/core/services/api_client.dart`.
- Migrated auth session tokens and passkey secrets to OS Keystore/Keychain (`SecureLocalStorage` with transparent migration from `SharedPreferences`), added singleflight token refresh on resume and `401` retry, standing checks (`is_banned`/`is_restricted`), device-scoped logout (`signOutCurrentDevice`), and global sign-out (`signOutAllDevices`).
- Purged all R2 HMAC signing, Telegram bot tokens, Google Vision/Gemini keys, `zev_fmc`/`zev_fcm` DB writes, and `'student'` defaults from Flutter; routed uploads, moderation, support tickets, verification requests, and referral claims through authenticated `/api/v1/*` APIs.
- Fixed `RegisterScreen` profile creation bug, `is_verified`/`role` mismatches, `DeepLinkService` `_isAppReady`/`_pendingUri` queuing, and `AndroidManifest.xml` deep link routes.

### 4. Verification & Test Results
- `grep -rnE "flutter_dotenv|dotenv|zev_fmc|zev_fcm|safiacademy|enpuoypqpklndnnhndax" lib pubspec.yaml vercel-build.sh`: zero code/config leaks or legacy column writes remain.
- `flutter pub get`: exited `0`.
- `flutter analyze`: `No issues found! (ran in 12.8s)`, exited `0`.
- **Remaining Native OAuth Gap (Owner Action)**: `ios/Runner/GoogleService-Info.plist` still lacks dedicated iOS `CLIENT_ID` & `REVERSED_CLIENT_ID`, and `android/app/google-services.json` has `"oauth_client": []` (once added in Firebase/Google Cloud Console along with Play App Signing SHA-256, Android Release & iOS Google Sign-In will match end-to-end).

### 5. Rollback Status
- Non-destructive client & server refactor; git revert restores prior state cleanly while cold DB backup remains intact.

### 6. Next Phase
- **Phase 2 — Reversible Database Foundation, FCM Consolidation (`user_devices`), RLS Hardening & Atomic Counters**

---

## Phase 2 — Reversible Database Foundation, FCM Consolidation, RLS Hardening & Normalized Schema
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Live PostgreSQL `17.11` schema (`35` public tables, RLS policies, triggers, functions, FK constraints, orphan rows, counter drift), all `zev_fmc`/`zev_fcm` references across client & backend repos, `zev-web` `/api/v1/push/send` and `/api/v1/account/export`, and `zev_admin` admin routes (`verifications`, `users`, `content`).

### 2. Issues Discovered
- `protect_profile_privileged_columns()` trigger initially evaluated `current_user` as `postgres` when declared `SECURITY DEFINER`, failing to block direct client (`authenticated`) updates to privileged columns (`referral_count`, `is_verified`, `lifetime_blue_eligible`, `followers_count`).
- `zev_admin` `/api/admin/users` had broken `DELETE FROM discussion_likes/discussion_comments WHERE user_id = $1` (column is `student_id`), non-unique upsert conflicts, missing `plan_price`, and unparameterized `interval '${durationInterval}'` SQL interpolation; `/api/admin/verifications` also omitted `lifetime_blue_eligible = false` guard during subscription expiry sweeps.
- `zev-web` `/api/v1/push/send` and `/api/v1/account/export` referenced legacy `zev_fmc`/`zev_fcm` or `follows` instead of `user_devices`, `fcm_token`, and `user_follows`.

### 3. Changes Made
- Created `/Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs` plus 6 paired reversible `.up.sql` / `.down.sql` migrations:
  - `001_fcm_devices_and_cleanup`: Created `public.user_devices` with explicit RLS (`user_devices_*_own`) and indexes; coalesced all active FCM tokens (including `shaheensafi011` and `javad_mansuri`) into `profiles.fcm_token` + `user_devices` with zero loss; dropped `zev_fmc` & `zev_fcm`; purged 5 orphan `discussion_likes` & 238 orphan `user_notifications`; added cascading FKs; dropped redundant constraints/indexes.
  - `002_signup_triggers_and_functions`: Updated `generate_unique_username` / `trg_assign_auto_username` to preserve `.` (`^[a-z0-9_.]{3,30}$`); added `is_username_available(text)` RPC; backfilled all 11 orphaned `auth.users` into `profiles` (deduplicating colliding `sheraz_jan`); installed `on_auth_user_created`; fixed `notify_on_reel_comment` (`NEW.comment_text`); rewrote `create_direct_message_notification` / `notify_on_direct_message` (block-aware + null-safe); rewrote `get_admin_dashboard_stats`; added `expire_stale_subscriptions()` preserving `lifetime_blue_eligible = true`.
  - `003_rls_hardening`: Added `is_blocked_between(uuid, uuid)`; hardened core social/messaging tables (`profiles`, `reels`, `discussion_posts`, `direct_messages`, `user_follows`, `student_friends`, `user_notifications`, etc.) and added explicit policies to all 6 previously policy-less RLS tables (`admin_audit_logs`, `message_reactions`, `referrals`, `story_views`, `subscriptions`, `user_restrictions`).
  - `004_core_schema_expansion_indexes`: Expanded normalized schema (`user_settings`, `user_privacy_settings`, `user_preferences`, `user_sessions`, `user_security_logs`, `user_links`, `account_deletions`, `notification_preferences`, `notification_deliveries`, `follow_requests`, `close_friends`, `user_mutes`, `post_media`, `comment_likes`, `comment_pins`, `post_views`, `post_reports`, `hidden_posts`, `media_deletion_queue`, `story_reactions`, `story_replies`, `story_mutes`, `search_history`, `trending_topics`, `appeals`, `conversations`, `conversation_members`, anti-recursion helpers `is_conversation_member`/`is_conversation_admin`, `message_deliveries`, `message_reads`, `message_deletions`, `message_edits`, `conversation_pins`, `conversation_mutes`, `message_requests`, `advertisers`, `ad_campaigns`, `ad_creatives`, `ad_targeting`, `ad_impressions`, `ad_clicks`, `ad_conversions`, `ad_frequency_caps`, `ad_invoices`, `live_streams`, `live_comments`, `live_reactions`, `live_viewers`), backfilled 1:1 `conversations` for direct messages, and added composite, partial, and GIN indexes.
  - `005_atomic_counters_reconcile`: Installed 16 atomic counter triggers, `accept_follow_request(uuid)`, `mark_conversation_read(uuid)`, `record_reel_view(uuid)`, and `reconcile_all_counters()` RPC (`55` profiles, `7` posts, `17` reels, `7` follows, `3` conversations, `0` drift).
  - `006_security_invoker_profile_guard`: Converted `protect_profile_privileged_columns()` to `SECURITY INVOKER` so `current_user = 'authenticated'` is blocked with `42501` while `SECURITY DEFINER` triggers still increment counters cleanly.
- Updated `/Users/Safi_Sahib/zev-web/src/app/api/v1/push/send/route.ts` and `/Users/Safi_Sahib/zev-web/src/app/api/v1/account/export/route.ts` for consolidated `user_devices`/`fcm_token`/`user_follows`.
- Fixed `/Users/Safi_Sahib/zev_admin/src/app/api/admin/{verifications,users,content}/route.ts` (including parameterized `make_interval` in `BAN_USER` and `RESTRICT_USER`).

### 4. Verification & Test Results
- `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: `0` RLS tables without policies, `0` tables without RLS, `0` missing profiles for `55` active auth users, `0` `zev_fmc`/`zev_fcm` leftovers, `0` orphans, `0` drifted counters (`ALL VERIFICATION CHECKS PASSED`).
- Live SQL security probe (`ROLE authenticated`): `42501` blocked direct updates to `referral_count = 999`, `is_verified`, `lifetime_blue_eligible`, `followers_count`; allowed own `bio` update; verified atomic `followers_count` increment (`4 -> 5`).
- Live `EXPLAIN ANALYZE` benchmarks: `feed_cursor` (`0.114 ms`), `reels_cursor` (`0.064 ms`), `chat_thread` (`0.181 ms` via `idx_direct_messages_created_at`), `profile_search` (`0.149 ms`).
- `npm --prefix /Users/Safi_Sahib/zev-web run build`: exited `0`.
- `npm --prefix /Users/Safi_Sahib/zev_admin run build`: exited `0`.

### 5. Rollback Status
- Every migration (`001`–`006`) has an explicit `.down.sql` counterpart and `schema_migrations` tracking, backed by verified Phase 0 cold dump (`pre_migration_backup.dump`).

### 6. Next Phase
- **Phase 3 — Social Core, Profile, Privacy, Activity, Duplicate Sheet Removal & Clearmorphic UI Completion (`zev-app`)**



---

## Phase 3 — Social Core, Profile, Privacy, Activity, Comments, Highlights & Clearmorphic UI Completion
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- All social graph flows (`Follow`, `Unfollow`, `Follow Requests` for private accounts, `Remove Follower`, `Block`, `Unblock`, `Restrict`, `Mute`), threaded comments, reposts, bookmarks, likes, highlights, edit profile & links, privacy & security, login session management, GDPR account data export, account deactivation & deletion, and user activity screens (`ActivityLikesScreen`, `ActivityContentScreen`, `ActivityCommentsScreen`, `ActivityArchiveScreen`, `ActivityDeletedScreen`).
- All 3 server-side account lifecycle API routes (`/api/v1/account/{export,deactivate,delete}`) and the Supabase schema triggers/RPCs (`is_username_available`, `accept_follow_request`, `reconcile_all_counters`).

### 2. Issues Discovered
- **Activity Screens Querying Nonexistent Tables/Columns**:
  - `ActivityLikesScreen` and `ActivityContentScreen` queried `discussion_likes.user_id` (real column: `student_id`), `discussion_posts.video_url` (videos use `image_url`), `reels.caption` (`reels` uses `title`/`description`), omitted `deleted_at IS NULL`, and showed `SnackBar` stubs instead of playing liked/published reels.
  - `ActivityCommentsScreen` queried `discussion_comments.user_id` & `.content` (real columns: `student_id`, `comment_text`) and `reel_comments.content`.
  - `ActivityArchiveScreen` and `ActivityDeletedScreen` were static mock placeholders with zero Supabase queries or restore/permanent-delete actions.
  - `UserActivityScreen` queried `discussion_*.user_id` and displayed hardcoded `sampleSearches` instead of live `search_history`, `user_security_logs`, and `AppSessionTrackerService` metrics.
- **Privacy, Follow & Profile Bugs**:
  - `UserFollowsScreen` queried legacy `student_friends`, lacked a private-account Requests tab and owner Remove Follower flow, and ignored visitor privacy/block gating.
  - `EditProfileScreen` lacked debounced `is_username_available` + 14-day cooldown enforcement, `profiles.location`, `user_links` CRUD, and old-avatar R2 deletion, and silently proceeded even if avatar upload failed.
  - `PrivacySecurityScreen` persisted blocklists locally in `SharedPreferences` and wrote nonexistent `profiles.show_activity_status`/`allow_story_sharing` columns instead of `user_privacy_settings`, `user_blocks`, `user_mutes`, `user_sessions`, and real export/deactivate/delete endpoints.
  - `ProfileScreen` referenced `story_highlights`, `post_bookmarks`, `is_deactivated`, `_profile['full_name']`, and used deprecated `NotificationService` stubs instead of `SocialGraphService`.
  - `StoryHighlightModel` had `$hexList__` string-interpolation bug breaking custom gradient encoding, and `ZevColors` lacked semantic `errorRed`, `successGreen`, and `warningAmber` constants.

### 3. Changes Made
- **Backend (`/Users/Safi_Sahib/zev-web`)**:
  - Added `/api/v1/account/deactivate/route.ts` and `/api/v1/account/delete/route.ts` (cleaning R2 `zev/` media assets, logging security/deletion audits, revoking auth sessions, and removing auth/profile records safely).
  - Enhanced `/api/v1/account/export/route.ts` for GDPR JSON export.
- **Flutter Core (`/Users/Safi_Sahib/zev-app/lib/core/`)**:
  - Added `ZevColors.errorRed`, `ZevColors.successGreen`, `ZevColors.warningAmber` in `theme/zev_theme.dart`.
  - Extended `ApiClient` (`delete()`), `AuthSessionManager`, `AppSessionTrackerService`, `SocialGraphService`, `ContentDeletionService` (post/reel edit, archive, 30-day soft-trash, restore, permanent delete + R2 cleanup queue fallback), `RichTextHelper`, and unified Light Clearmorphic `CommentsThreadSheet`.
- **Feed, Reels & Highlights (`/Users/Safi_Sahib/zev-app/lib/features/{feed,reels}/`)**:
  - Added `location` and `editedAt` support in `FeedPostItem`, fixed share/bookmark/repost flows in `FeedPostCard`/`FeedShareSheet`/`FeedViewerScreen`/`PostDetailScreen`/`FullscreenMediaViewer`, integrated swipe-up `ReelPlayerItem` playback + `ReelCommentsSheet` + `StoryHighlightService` (`user_highlights`/`user_highlight_items`) and Light Clearmorphic `CreateHighlightSheet` / `HighlightViewerScreen`.
- **Profile, Privacy & Activity (`/Users/Safi_Sahib/zev-app/lib/features/profile/screens/`)**:
  - Refactored `ProfileScreen`, `UserFollowsScreen` (visitor policy gating + Requests/Followers/Following tabs + Remove Follower), `EditProfileScreen` (`is_username_available`, 14-day cooldown, `location`, `user_links` CRUD, avatar R2 cleanup), `PrivacySecurityScreen` (`user_privacy_settings`, Blocked/Muted sheets, live `user_sessions` revocation, live Export/Deactivate/Delete flows), `UserActivityScreen` (`student_id` counts, `AppSessionTrackerService`, `search_history`, `user_security_logs`), and all 5 `activity/*.dart` screens (`ActivityLikesScreen`, `ActivityContentScreen`, `ActivityCommentsScreen`, `ActivityArchiveScreen`, `ActivityDeletedScreen`) with live Supabase queries, `ReelPlayerItem` playback, comment deletion, story re-share / unarchive, and 30-day trash restore / permanent R2 delete.

### 4. Verification & Test Results
- `cd /Users/Safi_Sahib/zev-app && flutter analyze`: **`No issues found! (ran in 13.3s)`**, exit code **`0`**.
- `npm --prefix /Users/Safi_Sahib/zev-web run build`: exited **`0`** (compiled cleanly, 192 static routes + all `/api/v1/*` handlers).
- `grep -rnE "story_highlights|post_bookmarks|is_deactivated|increment_reel_comments|show_activity_status|allow_story_sharing|_profile\['full_name'\]" /Users/Safi_Sahib/zev-app/lib`: **`LEGACY_REFS_CLEAN`** (0 matches). Note: one legacy `student_friends` reference remains inside `notifications_screen.dart` scheduled for Phase 5.
- `grep -rn "discussion_" /Users/Safi_Sahib/zev-app/lib | grep -E "video_url|\.eq\('user_id'"`: **`DISCUSSION_REFS_CLEAN`** (0 matches).
- `SELECT public.reconcile_all_counters();`: `0` drifted posts/reels/stories/hashtags/profiles.
- `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: **`ALL VERIFICATION CHECKS PASSED (0 anomalies)`**.

### 5. Rollback Status
- Non-destructive application-layer changes reversible via Git; all underlying schema migrations (`001`–`008`) remain paired and verified against Phase 0 dump.

### 6. Next Phase
- **Phase 4 — Real-Time Chat, Presence, Receipts, Typing, Reply/Forward/Edit/Delete/Reactions, Attachments, Group Chats, Message Requests & Offline Queue**

---

## Phase 4 — Real-Time Chat, Presence, Receipts, Groups, Attachments & Offline Queue
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Existing 1:1 DM flow, `profiles.last_seen_at`, `direct_messages`, `conversations`, `conversation_members`, `message_reactions`, `message_deliveries`, `message_reads`, `message_deletions`, `message_edits`, `conversation_pins`, `conversation_mutes`, `message_requests`, `user_notes`, `/api/v1/media/presign`, `CloudflareStorageService`, `SocialGraphService`, `DeepLinkService`, and `NotificationService`.

### 2. Issues Discovered
- Chat UI lacked group conversations, message requests Accept/Decline handling, edit/delete-for-me/delete-for-everyone flows, forward picker, document attachments (`direct_messages`), typing broadcasts, scoped per-thread Realtime subscriptions, privacy-respecting `hide_online_status` lookup, cursor pagination, global/in-chat message search, pin/mute actions, and offline retry queue persistence.
- `ChatListScreen` notes bar overloaded `profiles.bio` instead of dedicated 24h `user_notes`.
- `FeedShareSheet` had a stubbed group button and needed shared-post/reel card support inside `ChatConversationScreen`.
- `ChatCacheService` previously compared group sender attribution against `lastSenderId` rather than `currentUserId`.
- `NotificationService` & `DeepLinkService` needed unified handling for `/chat/conv:<conversationId>` (`group_message`), `/chat/<conv_id>` (`group_invitation`), and relative `/...` notification `link_url` paths.

### 3. Changes Made
- **Database Migration (`009_chat_realtime_and_groups.{up,down}.sql`)**:
  - Created `public.user_notes` (24h ephemeral inbox notes with RLS & Realtime) + partial chat indexes (`conversation_pins`, `conversation_mutes`, `message_requests`).
  - Added privacy-respecting `get_profiles_presence(uuid[])`, `create_group_conversation(text, uuid[], text)`, `edit_direct_message(uuid, text)`, `delete_message_for_me(uuid)`, `delete_message_for_everyone(uuid)`, `delete_conversation_for_me(uuid)`, and `respond_message_request(uuid, text)`.
  - Installed `trg_direct_message_handle_request`, upgraded `trg_direct_message_update_conversation`, upgraded `mark_messages_delivered()`, and updated `create_direct_message_notification()` (respecting mute/block state and emitting `/chat/conv:<id>` for groups and `/chat/<sender_id>` for 1:1 DMs).
  - Enabled `supabase_realtime` publication on `user_notes`, `conversations`, `conversation_members`, `message_deliveries`, `message_reads`, `message_requests`, and `message_reactions`.
- **Backend (`/Users/Safi_Sahib/zev-web/src/app/api/v1/media/presign/route.ts`)**:
  - Expanded document MIME whitelist (`.pdf`, `.txt`, `.csv`, `.json`, `.zip`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx` up to 50 MB) strictly restricted to `folder === 'direct_messages'`.
- **Flutter Chat Stack & Core Services (`/Users/Safi_Sahib/zev-app/lib/`)**:
  - Updated `CloudflareStorageService` (`inferMimeType` + document extensions), `UserPresenceService` (`fetchPresenceMap`, `setHideOnlineStatus`, `markPendingMessagesDelivered`, 45s heartbeat), and `PrivacySecurityScreen` (`hide_online_status` sync).
  - Rebuilt `ChatConversationItem`, `DirectMessageModel`, `ChatCacheService` (bounded LRU + `SharedPreferences` persistent outbox queue + `peerToConversationId`), and `ChatService` (`sendSharedContentToConversation`, group management, cursor fetch, search, pin/mute/request RPCs).
  - Created Light Clearmorphic `lib/features/chat/widgets/new_chat_sheet.dart` (New Message / New Group / `showMemberPicker`) and `lib/features/chat/widgets/chat_modals.dart` (`ForwardPickerSheet`, `GroupInfoSheet`, `FileMessageCard`, `VideoMessageBubblePlayer`, `FullScreenVideoViewer`, `SharedContentMessageCard`).
  - Upgraded `FeedShareSheet`, `ChatListScreen` (`Primary` / `Groups` / `Requests` tabs, 24h `user_notes`, global message search, Pin/Mute/Mark Read/Delete For Me), and `ChatConversationScreen` (cursor pagination, offline auto-flush & retry CTA, Broadcast typing, Sent/Delivered/Read receipts, Reply/Forward/Edit/Delete For Me/Delete For Everyone, Emoji Reactions, Voice/Image/Video/File attachments, Shared Post/Reel cards, In-Chat Search, Report Message).
  - Upgraded `DeepLinkService._openChat` and `NotificationService.handleNotificationClick` for `conv:<id>`, `group_invitation`, `group_message`, `direct_message`, and relative `/chat/*` links.

### 4. Verification & Test Results
- `cd /Users/Safi_Sahib/zev-app && flutter analyze`: **`No issues found! (ran in 15.9s)`**, exit code **`0`**.
- `npm --prefix /Users/Safi_Sahib/zev-web run build`: exited **`0`**.
- `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: **`ALL VERIFICATION CHECKS PASSED (0 anomalies)`**.
- Live SQL transactional smoke test (`BEGIN ... SET LOCAL ROLE authenticated ... ROLLBACK`): verified `supabase_realtime` publications across all 13 live tables, `get_profiles_presence`, `create_group_conversation`, `direct_messages` insert, `edit_direct_message` (`was_edited: true`), `delete_message_for_everyone` (`was_deleted: true`), `delete_message_for_me` (`cnt: 1`), and `delete_conversation_for_me` cleanly with full rollback.

### 5. Rollback Status
- Migration `009` has paired `009_chat_realtime_and_groups.down.sql`; Flutter & Next.js changes revert cleanly via Git.

### 6. Next Phase
- **Phase 5 — Notification Center, Firebase FCM HTTP v1 Setup, Foreground Local Notifications, Live Badges & Notification Preferences**


---

## Phase 5 — Notification Center, Firebase FCM HTTP v1, Live Badges & Notification Preferences

### 1. What Was Examined
- Audited `NotificationService`, `AuthHelper`, `DeepLinkService`, `NotificationsScreen`, `NotificationItem`, `NotificationSettingsScreen`, `ZevMainLayout`, `FeedViewerScreen`, `ChatConversationScreen`, `SocialGraphService`, `CommentsThreadSheet`, `FeedPostCard`, `ReelPlayerItem`, `/Users/Safi_Sahib/zev-web/src/lib/server/fcm.ts`, `/Users/Safi_Sahib/zev-web/src/app/api/v1/push/send/route.ts`, `/Users/Safi_Sahib/zev-web/src/app/api/v1/account/export/route.ts`, `android/app/google-services.json`, `android/app/src/main/AndroidManifest.xml`, and `ios/Runner/GoogleService-Info.plist`.

### 2. Issues Discovered
- `NotificationsScreen` queried a nonexistent column `reel_comments.comment` (real schema column is `comment_text`), causing reel comments in activity feeds to fail silently into empty results.
- Legacy `student_friends` table queries remained in `NotificationsScreen` and `zev-web/src/app/api/v1/account/export/route.ts` despite canonical `follow_requests` + `user_follows`.
- `NotificationService` lacked deterministic `DefaultFirebaseOptions.currentPlatform`, `flutter_local_notifications` Android channel setup (`zev_notifications_channel`), `onTokenRefresh` persistence, and race-free cold-start routing gated until `DeepLinkService` readiness.
- `/api/v1/push/send` emitted `data.deep_link`, whereas `NotificationService.handleNotificationClick` only read `link_url`/`link`, causing cold-start/background push taps to fall back to generic screens; `/api/v1/push/send` also lacked category-level enforcement (`likes_enabled`, `comments_enabled`, `follows_enabled`, `mentions_enabled`, `stories_enabled`, `live_enabled`, `marketing_enabled`), `quiet_hours_start`/`quiet_hours_end` UTC enforcement, and live APNs/Android unread badge counts.
- `NotificationSettingsScreen` only persisted preferences locally in `SharedPreferences` instead of syncing with `public.notification_preferences` (which `/api/v1/push/send` enforces).
- Unread badge UI was decentralized (a simple dot in `FeedViewerScreen`, zero counters on `ZevMainLayout` tablet sidebar, no synchronized `BadgeCounterService`).

### 3. Changes Made
- **Database Migration (`010_notifications_preferences_and_badges.{up,down}.sql`)**:
  - Added partial indexes `idx_user_notifications_unread_badge` and `idx_follow_requests_target_pending`.
  - Created `public.get_unread_badge_counts()` and `public.get_or_init_notification_preferences()` (`SECURITY DEFINER`, `authenticated` role).
- **Web Push Backend (`/Users/Safi_Sahib/zev-web`)**:
  - Updated `src/lib/server/fcm.ts` to support Android `notification.icon` (`ic_notification`), `#00D4FF` accent, `tag` collapse keys, and APNs numeric `aps.badge`.
  - Updated `src/app/api/v1/push/send/route.ts` to enforce all `notification_preferences` toggles + UTC quiet hours, query live unread counts for APNs `badge`, and include both `deep_link` and `link_url`.
  - Removed legacy `student_friends` query from `src/app/api/v1/account/export/route.ts`.
- **Flutter Notification Stack (`/Users/Safi_Sahib/zev-app/lib/`)**:
  - Added `lib/firebase_options.dart` (`DefaultFirebaseOptions.currentPlatform` for project `zevapp-3c6b5`).
  - Created `lib/core/services/badge_counter_service.dart` (`BadgeCounterService`) backed by `get_unread_badge_counts()` + Realtime subscriptions (`user_notifications`, `direct_messages`, `message_reads`, `message_requests`).
  - Upgraded `DeepLinkService` (`isAppReady`, `addOnReadyCallback`), `NotificationService` (`flutter_local_notifications`, `onTokenRefresh`, cold-start flush, Light Clearmorphic `showInAppBanner`, `dispatchPushNotification`, `UserFollowsScreen` requests tab `initialTabIndex: 2`), and `AuthHelper` (`user_devices` heartbeat & logout cleanup).
  - Upgraded `NotificationItem`, `NotificationsScreen` (`comment_text` fix, inline `follow_requests` Confirm/Delete, smart actor coalescing, cursor pagination, swipe-to-delete), and `NotificationSettingsScreen` (`notification_preferences` upsert + Quiet Hours UTC pickers, Light Clearmorphic styling with `ZevColors.softSurface` / `ZevColors.border`).
  - Wired `BadgeCounterService` into `lib/main.dart` (resume refresh), `ZevMainLayout` (tablet sidebar unread pills + auth lifecycle start/stop), `FeedViewerScreen` (live unread numeric pills on Heart & Messages icons), and `ChatConversationScreen` (refresh after marking read).
  - Hooked asynchronous `NotificationService().dispatchPushNotification(...)` (without inserting duplicate DB notification rows alongside DB triggers) in `SocialGraphService` (`toggleFollow`, `acceptFollowRequest`), `CommentsThreadSheet`, `FeedPostCard` (`_toggleLike`), and `ReelPlayerItem` (`_toggleLike`).

### 4. Verification & Test Results
- `cd /Users/Safi_Sahib/zev-app && flutter analyze`: **`No issues found! (ran in 16.6s)`**, exit code **`0`**.
- `npm --prefix /Users/Safi_Sahib/zev-web run build`: exited **`0`**.
- `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: **`ALL VERIFICATION CHECKS PASSED (0 anomalies)`**.
- `grep -rnE "student_friends|zev_fmc|zev_fcm" /Users/Safi_Sahib/zev-app/lib /Users/Safi_Sahib/zev-web/src`: **0 runtime usages** (only explicit legacy local pref cleanup `prefs.remove('zev_fmc_token_$userId')` in `auth_helper.dart:88`).
- Live SQL transactional smoke test (`BEGIN ... SET LOCAL ROLE authenticated ... ROLLBACK`): verified `get_unread_badge_counts()`, `get_or_init_notification_preferences()` returning all schema fields, and `notification_preferences` `quiet_hours_start`/`quiet_hours_end` update with full rollback.
- **External / Native Credential Notes (Preserved Honestly)**:
  - Server-side FCM HTTP v1 delivery in `zev-web` requires `FIREBASE_SERVICE_ACCOUNT_JSON` set in Vercel environment variables.
  - `android/app/google-services.json` currently has `"oauth_client": []` and `ios/Runner/GoogleService-Info.plist` omits iOS OAuth `CLIENT_ID` (required if native Android/iOS OAuth clients are registered later in Firebase Console).

### 5. Rollback Status
- Migration `010` includes `010_notifications_preferences_and_badges.down.sql`; Flutter & Next.js changes revert cleanly via Git.

### 6. Next Phase
- **Phase 6 — Media Pipeline, Cloudflare R2 `zev/` Orphan Cleanup & Performance Optimization**

---

## Phase 6 — Media Pipeline, Cloudflare R2 `zev/` Orphan Cleanup & Performance Optimization
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Flutter media upload, caching, thumbnail extraction, and video player lifecycle across `CloudflareStorageService`, `ZevCachedImage`, `ZevVideoThumbnail`, `ReelVideoCacheManager`, `ExploreScreen` (`ExploreVideoTile`), `ChatModals` (`VideoMessageBubblePlayer`, `FullScreenVideoViewer`), `VideoTrimmerSheet`, `EditProfileScreen`, `CreatePostScreen`, `CreateReelScreen`, and `CreateStoryScreen`.
- Home Feed & Reels data-fetching waterfalls in `FeedViewerScreen` (`7` sequential queries per refresh) and `ReelsViewerScreen` (`5` sequential queries per refresh), plus PostgreSQL query plans and index coverage across `user_stories`, `discussion_*`, `reel_*`, `hidden_posts`, `user_follows`, `user_blocks`, and `user_mutes`.
- `/Users/Safi_Sahib/zev-web/src/app/api/v1/media/delete/route.ts` and Cloudflare R2 bucket `safiacademy-media` strictly isolated to the `zev/` prefix.

### 2. Issues Discovered
- **Cloudflare R2 `zev/` Prefix Issues**: All `12` `zev/` objects (`9.39 MB`) had `Cache-Control: null`; `avatar_90a9fbf8...heic` carried `Content-Type: application/octet-stream` instead of `image/heic`; and `3` unreferenced orphan objects (`5.43 MiB` across 2 old PNG avatars and 1 orphan highlight MP4) consumed unused storage.
- **Media Deletion API Bug**: `/api/v1/media/delete` queried nonexistent column `profiles.cover_url` (canonical column: `cover_image_url`).
- **Video Decoder Leaks & Dark Surfaces**: `ReelVideoCacheManager.preloadVideos()` allocated `VideoPlayerController.networkUrl` objects inside `.catchError`, `ExploreVideoTile` and `VideoMessageBubblePlayer` risked eager HW video decoder exhaustion while scrolling, `ZevVideoThumbnail` lacked bounded LRU eviction/in-flight deduplication/widget-update cleanup and showed dark `#0F172A`/`#1E293B` fallbacks, and `VideoTrimmerSheet` rendered dark `#0F172A` surfaces instead of `ZevColors` Light Clearmorphism.
- **Upload UX & Client Compression Gaps**: No off-main-thread EXIF-baked image resizing before upload, no exponential-backoff retry for transient errors, no upload progress bars/percentages or inline `Retry` UI on `CreatePostScreen`, `CreateReelScreen`, and `CreateStoryScreen`, and `tempCtrl.dispose()` lacked `try/finally` protection in `CreateStoryScreen._pickVideo`.
- **N+1 / Sequential Query Waterfalls & Missing Keyset Cursors**: `FeedViewerScreen._fetchPosts()` executed `7` sequential roundtrips and `ReelsViewerScreen._fetchReels()` executed `5` sequential roundtrips without keyset cursor pagination or Light Clearmorphic skeletons.

### 3. Changes Made
- **Database Migration (`011_performance_indexes_and_feed_cursors.{up,down}.sql`)**:
  - Added 11 composite/partial indexes (`idx_user_stories_active_created`, `idx_discussion_comments_active_post`, `idx_hidden_posts_user_target`, `idx_user_follows_pair`, `idx_user_blocks_pair`, `idx_user_mutes_pair`, `idx_reel_likes_user_reel`, `idx_reel_bookmarks_user_reel`, `idx_discussion_likes_student_post`, `idx_post_reposts_user_post`, `idx_discussion_bookmarks_user_post`).
  - Added single-roundtrip keyset-paginated RPCs `public.get_feed_posts_page(timestamptz, uuid, integer, boolean)` (with aggregated `post_media` JSON array) and `public.get_reels_page(timestamptz, uuid, integer, boolean)`.
- **Backend (`/Users/Safi_Sahib/zev-web/src/app/api/v1/media/delete/route.ts`)**: Fixed `cover_url` -> `cover_image_url` in profile ownership lookup.
- **Cloudflare R2 `zev/` Cleanup & Cache Optimization (`safiacademy-media`, zero non-`zev/` objects touched)**:
  - Re-uploaded all 9 DB-referenced `zev/` objects byte-for-byte with `Cache-Control: public, max-age=31536000, immutable` and accurate `Content-Type` (including `image/heic`).
  - Permanently deleted ONLY the 3 verified orphan `zev/` keys (`5,691,037` bytes freed).
- **Flutter Media Pipeline, Skeletons & Keyset Feeds (`/Users/Safi_Sahib/zev-app/lib/`)**:
  - Created `core/services/media_compression_service.dart` (`Isolate.run` EXIF-baked resize `1440px` / JPEG quality `84` + thumbnail helper) and `core/widgets/zev_skeleton.dart` (`ZevSkeleton` & `ZevFeedCardSkeleton`).
  - Upgraded `CloudflareStorageService` (background-isolate compression, exponential-backoff retries up to 3 attempts, `headers ?? requiredHeaders`, live progress callback), `EditProfileScreen` (`maxImageDimension: 800, imageQuality: 85`), `ZevCachedImage`, `ZevVideoThumbnail` (48-entry LRU cache, `_inFlightExtractions`, `_disposed`/`didUpdateWidget` guards, Light Clearmorphic skeletons), `ReelVideoCacheManager` (leak cleanup), `ExploreVideoTile`, `VideoMessageBubblePlayer`, `FullScreenVideoViewer`, and Light Clearmorphic `VideoTrimmerSheet`.
  - Added upload stage + progress bars + inline `Retry` UI to `CreatePostScreen`, `CreateReelScreen`, and `CreateStoryScreen` (with `try/finally` + `mounted` video controller disposal guards).
  - Refactored `FeedViewerScreen` and `ReelsViewerScreen` to single-roundtrip keyset pagination (`get_feed_posts_page` / `get_reels_page`), monotonic generation guards, Light Clearmorphic `ZevFeedCardSkeleton` loading placeholders, and scroll-threshold pagination.

### 4. Before / After Performance Benchmarks & Verification
- **Database & Query Waterfalls**:
  - **Feed Roundtrips**: Before: `7` sequential Supabase queries per refresh -> After: **`1`** single-roundtrip RPC (`get_feed_posts_page` total Execution Time **`1.733 ms`**, Planning **`0.045 ms`** for 7 rows with joins + counters + `media_items`).
  - **Reels Roundtrips**: Before: `5` sequential Supabase queries per refresh -> After: **`1`** single-roundtrip RPC (`get_reels_page` total Execution Time **`1.617 ms`**, Planning **`0.041 ms`** for 17 rows).
  - **Active Stories Query (`user_stories`)**: Before: `0.636 ms` Execution (`0.890 ms` Planning) -> After: **`0.081 ms`** Execution (`0.357 ms` Planning); indexed schema count reached `90` `idx_*` indexes cleanly.
  - **Keyset Pagination Check (`ROLLBACK`-safe SQL probe)**: Verified `get_feed_posts_page` (`page1: 3`, `page2: 3`, **`0` overlap**) and `get_reels_page` (`p1: 5`, `p2: 5`, **`0` overlap**) under `ROLE authenticated` and `ROLE anon`.
- **Cloudflare R2 `zev/` Storage & CDN Headers**:
  - Before: `12` objects (`9.39 MB`), `3` verified orphans (`5.43 MiB`), `12/12` missing `Cache-Control`, `.heic` served as `application/octet-stream`.
  - After: **`9`** objects (**`3.96 MB`**, `0` orphans, `-57.8%` `zev/` storage used), `9/9` verified `HEAD=200` with matching `Content-Length`, valid MIME (`image/heic` etc.), and `Cache-Control: public, max-age=31536000, immutable`.
  - Live CDN `HEAD https://media.zevapp.com/zev/feed/feed_acc15e15-73e9-4785-abf5-be8beec2581f_1793692138660.jpg`: `200`, `cache-control: public, max-age=31536000, immutable`, `content-type: image/jpeg` (first edge check showed `cf-cache-status: DYNAMIC`; Cloudflare Edge caching HIT behavior depends on zone cache rule configuration).
- **Static Analysis, Build & DB Integrity**:
  - `cd /Users/Safi_Sahib/zev-app && flutter analyze`: **`No issues found! (ran in 22.9s)`**, exit code **`0`**.
  - `npm --prefix /Users/Safi_Sahib/zev-web run build`: exited **`0`**.
  - `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: **`ALL VERIFICATION CHECKS PASSED (0 anomalies)`**.
  - **Scope Note on Client Video Transcoding / HLS**: On-device image resize + JPEG compression runs off-main-thread via `Isolate.run`, while multi-bitrate server-side HLS video transcoding is deferred unless dedicated worker infrastructure (Cloudflare Stream / FFmpeg worker) is provisioned; raw mobile videos upload directly via presigned R2 PUT URLs with progress + retry.

### 5. Rollback Status
- Migration `011` includes `011_performance_indexes_and_feed_cursors.down.sql`; code changes revert cleanly via Git. Note: deleted R2 orphan files (`5.43 MiB` previously unreferenced anywhere in Postgres) are permanently removed from R2.

### 6. Next Phase
- **Phase 7 — Content Experience: Following vs For You Feed, Ranking Refinement, Unified Search & Trending/Hashtags, and Stories Enhancements**


---

## Phase 7 — Content Experience: Following Feed, Ranking Refinement, Unified Search & Trending Hashtags, and Stories Enhancements
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Audited `FeedViewerScreen`, `ReelsViewerScreen`, `FeedStoriesTray`, `FeedPostCard`, `PostDetailScreen`, `ExploreScreen`, `DiscoverScreen`, `CreateStoryScreen`, `StoryViewerScreen`, `FeedAlgorithmService`, `RichTextHelper`, `NotificationService`, and `NotificationsScreen`.
- Audited PostgreSQL schema & triggers for `hashtags`, `post_hashtags`, `reel_hashtags`, `search_history`, `user_stories`, `story_views`, `story_likes`, `story_reactions`, `story_replies`, `story_mutes`, `close_friends`, and `post_views`.

### 2. Issues Discovered
- **Following Feed Switcher Missing**: `FeedViewerScreen` (`p_following_only: false`) and `ReelsViewerScreen` (`p_following_only: false`) had static `ZEV ⌄` / `Reels ⌄` headers with no working `For You` vs `Following` switcher.
- **No Hastags Feed / RTL Script Support / Search Persistence**: `RichTextHelper._tokenRegex` omitted extended Arabic/Persian Unicode blocks (`\u0750-\u077F`, `\uFB50-\uFDFF`, `\uFE70-\uFEFF`) and hashtag taps showed a stub snackbar instead of opening a hashtag feed; `hashtags`, `post_hashtags`, `reel_hashtags`, `search_history`, and `post_views` lacked live triggers/RPCs; `ExploreScreen` lacked pagination, recent search history, trending hashtags, and follow/request integration; `DiscoverScreen` lacked `get_discover_creators` privacy/video thumbnail support and `SocialGraphService.toggleFollow` request status handling.
- **Stories & Notification Routing Gaps**:
  - `CreateStoryScreen` lacked a Close Friends audience selector (`visibility: 'close_friends' | 'public'`) and inline Close Friends list manager.
  - `StoryViewerScreen` lacked `initialStoryId` / `openByStoryId`, Close Friends badge display, idempotent server view recording (`record_story_view`), Owner Insights (`Viewers`, `Reactions`, `Replies`), Story Highlights integration, soft-delete (`deleted_at`), story mute (`story_mutes`), quick emoji reactions (`story_reactions`), story likes (`story_likes`), and direct replies (`story_replies`).
  - `FeedStoriesTray` lacked Close Friends emerald-cyan rings, seen-story muted rings, and distinct tap vs `+` add handling when the user has an active story.
  - Both `NotificationService.handleNotificationClick` and `NotificationsScreen._openNotificationTarget` matched `like`/`reply` before `story`, misrouting `story_like`, `story_reaction`, and `story_reply` notifications into `PostDetailScreen`.
- **Ranking Signals Static**: `FeedAlgorithmService` lacked session seen-item demotion (`markSeen` / `markReelSeen`), positive interaction affinity (`recordPositiveInteraction`), and negative feedback suppression (`recordNegativeFeedback`).

### 3. Changes Made
- **Database Migration (`012_content_experience_search_stories.{up,down}.sql`)**:
  - Normalized `post_hashtags` / `reel_hashtags` / `hashtags` usage counters via `extract_hashtags(text)` and `sync_post_hashtags` / `sync_reel_hashtags` triggers (backfilling existing posts/reels).
  - Created `record_post_view(uuid)`, hardened story notification triggers (`notify_on_story_like`, `tr_notify_story_reply`, `tr_notify_story_reaction`), `get_trending_hashtags(integer)`, `get_hashtag_content(text, integer)`, `search_unified_content(text, integer)`, `save_search_history(...)`, `get_recent_searches(integer)`, `clear_search_history(uuid)`, `get_explore_grid_page(text, integer, integer)`, `get_discover_creators(text, text, integer)`, `get_story_feed_trays()`, `record_story_view(uuid)`, `get_story_insights_and_viewers(uuid)`, `toggle_close_friend(uuid)`, and `get_close_friends_profiles(text)`.
- **Flutter UI & Services (`/Users/Safi_Sahib/zev-app/lib/`)**:
  - Added `FeedPostItem.fromRpcMap`, `ReelItem.fromRpcMap`, and `ActiveFriendStory.{isMe, hasUnseen, hasCloseFriendStory}`.
  - Upgraded `FeedAlgorithmService` with bounded session tracking (`_seenPostIds`, `_seenReelIds`, `_suppressedPostIds`, `_suppressedReelIds`, `_suppressedAuthorIds`, `_authorAffinity`, `_topicAffinity`).
  - Extended `RichTextHelper` Unicode hashtag regex and wired hashtag taps to new Light Clearmorphic `HashtagFeedScreen` (`features/discover/screens/hashtag_feed_screen.dart`).
  - Created `CloseFriendsSheet` (`features/stories/widgets/close_friends_sheet.dart`) and upgraded `CreateStoryScreen` (`Everyone` vs `Close Friends`), `StoryViewerScreen` (full viewer/owner bar, Insights modal, Highlights integration, emoji reactions, likes, replies, mute, delete, `openByStoryId`), and `FeedStoriesTray`.
  - Fixed `story_*` precedence in `NotificationService.handleNotificationClick` and `NotificationsScreen._openNotificationTarget`.
  - Upgraded `FeedViewerScreen` & `ReelsViewerScreen` with working `For You` / `Following` switchers, `FeedStoriesTray` refresh on story viewer pop, `FeedPostCard` interaction & negative-feedback wiring, and `PostDetailScreen` `record_post_view` tracking.
  - Upgraded `ExploreScreen` (paginated `get_explore_grid_page`, Recent Searches + Trending `#Hashtags` focus panel, `search_unified_content` across `Accounts`/`Reels`/`Posts`/`#Tags`, follow/request buttons, Light Clearmorphic skeletons & reel search tiles, functional Share & Not Interested preview actions) and `DiscoverScreen` (`get_discover_creators`, `SocialGraphService.toggleFollow`, video thumbnail badges, `ZevSkeleton`).

### 4. Verification & Test Results
- `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs verify`: **`ALL VERIFICATION CHECKS PASSED (0 anomalies)`** (verified after clean `down 012` + `up` cycle).
- Live SQL `BEGIN ... ROLLBACK` smoke tests executed across `authenticated` and `anon` roles verifying `get_explore_grid_page`, `search_unified_content`, `get_discover_creators`, `get_trending_hashtags`, `get_hashtag_content`, `get_story_feed_trays`, `save_search_history`/`get_recent_searches`/`clear_search_history`, and `toggle_close_friend`/`get_close_friends_profiles`.
- `cd /Users/Safi_Sahib/zev-app && flutter analyze`: **`No issues found! (ran in 21.5s)`**, exit code **`0`**.

### 5. Rollback Status
- Migration `012` includes `012_content_experience_search_stories.down.sql`; Flutter changes revert cleanly via Git.

### 6. Next Phase
- **Phase 8 — Ads, Monetization, Blue Verification & Subscription Lifecycle**


---

## Phase 8 — Ads, Monetization, Blue Verification & Subscription Lifecycle
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Audited `advertisers`, `ad_campaigns`, `ad_creatives`, `ad_targeting`, `ad_impressions`, `ad_clicks`, `ad_conversions`, `ad_frequency_caps`, `ad_invoices`, `user_verifications`, `subscriptions`, `referrals`, and `profiles.{is_verified, referral_count, lifetime_blue_eligible}` in live Supabase PostgreSQL.
- Audited `/Users/Safi_Sahib/zev-web/src/app/api/v1/verification/request/route.ts` and ZEV Ads delivery/tracking API surface.
- Audited `/Users/Safi_Sahib/zev_admin/src/app/api/admin/{users,verifications,subscriptions}/route.ts` and admin views.
- Audited Flutter verification (`ZevBlueVerificationScreen`), native ad slots (`ZevNativeAdCard`, `ZevNativeAdReelUnit`, `ZevNativeAdStoryUnit`), and creator settings (`ProfileSettingsScreen`).

### 2. Issues Discovered
- **Ads Schema Without Serving / Billing / Anti-Fraud RPCs**: Core ad tables lacked column-protection triggers (allowing direct balance/approval tampering if mutated client-side), lacked daily frequency caps/cooldown telemetry (`daily_frequency_cap`, `min_cooldown_seconds`, `spent_today`), and lacked server-side idempotent impression/click/conversion billing (`CPM`/`CPC`/`CPA`) and invoice generation.
- **Native Ad Units Bypassed Internal ZEV Campaigns**: `ZevNativeAdCard`, `ZevNativeAdReelUnit`, and `ZevNativeAdStoryUnit` needed unified delivery prioritizing active approved ZEV Ads Manager campaigns via `/api/v1/ads/serve` + idempotent `/api/v1/ads/track` before falling back to mobile AdMob `NativeAd`.
- **Subscription & 100-Referral Lifetime Integrity**: Stale verification/subscription expiry sweeps needed explicit protection so `lifetime`, `lifetime_referral`, `lifetime_blue_eligible = true`, and `referral_count >= 100` accounts are never downgraded when timed plans expire, plus a self-service 100-referral claim flow.

### 3. Changes Made
- **Database Migration (`013_ads_monetization_verification.{up,down}.sql`)**:
  - Expanded `ad_campaigns`, `ad_impressions`, and `ad_clicks` (`daily_frequency_cap`, `min_cooldown_seconds`, `spent_today`, `spent_today_date`, `approved_at`, `rejection_reason`, `is_flagged`, `flag_reason`, `numeric(14,6)` budget precision), added `CHECK` constraints and 6 performance/anti-fraud indexes, and tightened `ad_creatives` / `ad_targeting` RLS `WITH CHECK`.
  - Added `SECURITY INVOKER` column-protection triggers (`tr_protect_advertiser_columns`, `tr_protect_ad_campaign_columns`, `tr_protect_ad_creative_columns`).
  - Added `expire_stale_subscriptions()`, `claim_lifetime_referral_blue()`, `register_or_update_advertiser(...)`, `create_ad_campaign_with_creative(...)`, `toggle_own_ad_campaign_status(...)`, `serve_eligible_ad(...)`, `record_ad_event(...)` (idempotent + anti-fraud velocity checks + atomic conditional budget deduction), `get_my_advertiser_dashboard()`, and `generate_advertiser_invoice(...)`.
- **Web API (`/Users/Safi_Sahib/zev-web/src/app/api/v1/`)**:
  - Added `ads/campaigns/route.ts` (`GET`, `POST`, `PATCH`), `ads/serve/route.ts` (`GET`, `POST`), and `ads/track/route.ts` (`POST`) with rate limiting and Zod/UUID validation.
  - Upgraded `verification/request/route.ts` to support `referral_milestone` self-claim and preserve active paid subscriptions while logging support tickets + Telegram alerts.
- **Admin Portal (`/Users/Safi_Sahib/zev_admin/src/`)**:
  - Created `app/api/admin/ads/route.ts` (`GET` & `POST`: `APPROVE_ADVERTISER`, `SUSPEND_ADVERTISER`, `TOP_UP_BALANCE`, `APPROVE_CAMPAIGN`, `REJECT_CAMPAIGN`) and `components/views/AdsMonetizationView.tsx` wired into `Sidebar.tsx` and `app/page.tsx`.
  - Hardened `app/api/admin/{users,verifications,subscriptions}/route.ts` to preserve `lifetime` / `lifetime_referral` / `>= 100` referral badges across expiry sweeps and compute exact plan expirations (`monthly`, `yearly`, `lifetime`, `lifetime_referral`).
- **Flutter Ads & Blue Verification (`/Users/Safi_Sahib/zev-app/lib/`)**:
  - Created `core/services/zev_ads_service.dart` (`ZevSponsoredAd`, `ZevAdvertiserProfile`, `ZevAdCampaign`, `ZevAdInvoice`, `ZevAdsService` with session slot caching & idempotent impression/click keys) and `features/ads/screens/ads_manager_screen.dart` (100% Light Clearmorphism Ads Manager + Cloudflare R2 `ads/` creative uploads + targeting/budget/invoice console) wired into `ProfileSettingsScreen`.
  - Upgraded `ZevNativeAdCard`, `ZevNativeAdReelUnit`, and `ZevNativeAdStoryUnit` to serve internal ZEV sponsored campaigns across Feed, Explore, Reels, and Stories with mobile AdMob fallback, and wired `"Claim Free Lifetime Blue Tick"` in `ZevBlueVerificationScreen`.

### 4. Verification & Test Results
- Migration `013` applied and verified in live Supabase PostgreSQL (`migrate.mjs status`: `013_ads_monetization_verification` applied `2026-11-12T03:59:39.088Z`).
- End-to-end static analysis (`flutter analyze`), test suite (`flutter test`), Next.js production builds (`zev-web`, `zev_admin`), and DB integrity checks (`migrate.mjs verify`) are recorded alongside Phase 9 and Phase 10 verification runs below.

### 5. Rollback Status
- Migration `013` includes `013_ads_monetization_verification.down.sql`; Next.js and Flutter files revert cleanly via Git.

### 6. Next Phase
- **Phase 9 — Advanced Features: Carousels, Collaborators & User Tagging, Drafts & Scheduled Posts, Creator Insights & Appeals, and Interactive ZEV Live Chat & Presence Rooms**


---

## Phase 9 — Advanced Features: Carousels, Collaborators & User Tagging, Drafts & Scheduled Posts, Creator Insights, Standing Appeals & Interactive ZEV Live Chat Rooms
**Status**: Completed (`2026-11-12`)

### 1. What Was Examined
- Audited `discussion_posts`, `post_media`, `post_views`, `reel_views`, `appeals`, `user_restrictions`, `live_streams`, `live_comments`, `live_reactions`, and `live_viewers` in PostgreSQL alongside existing feed/post, creator analytics, account standing, and Realtime architecture.
- Audited Flutter feed creation & display (`FeedPostItem`, `CreatePostScreen`, `FeedPostCard`, `PostDetailScreen`, `FullscreenMediaViewer`), profile & settings navigation (`ProfileScreen`, `ProfileSettingsScreen`, `UserActivityScreen`, `PrivacySecurityScreen`, `HelpSupportScreen`), splash/login standing checks (`ZevSplashScreen`, `LoginScreen`, `GoogleAuthService`), and `zev_admin` moderation navigation (`Sidebar.tsx`, `app/page.tsx`, `/api/admin/stats/route.ts`).

### 2. Issues Discovered
- **Single-Media Post Limitation & Missing Metadata**: `CreatePostScreen` and `FeedPostCard` supported only a single image without ordered `post_media` carousel slides, collaborator attribution, tagged people sheets, drafts saving, or scheduled publishing timestamps.
- **Scheduled & Draft Leakage Risk**: `discussion_posts` / `post_media` RLS and `record_post_view` / `PostDetailScreen` needed strict owner-only visibility for `is_draft = true` and future `scheduled_at` posts.
- **No Creator Insights or Standing Appeal Flow**: Creators had no unified windowed analytics dashboard, and banned/restricted users lacked an in-app standing review screen and evidence-backed appeal workflow connected to `zev_admin`.
- **No Live Rooms Implementation**: `live_streams` / `live_comments` / `live_reactions` / `live_viewers` tables existed without RLS-hardened RPCs, Realtime publication, or Clearmorphic lobby/room UI (requiring honest Supabase Realtime chat & presence rooms without simulated A/V video).

### 3. Changes Made
- **Database Tables, Indexes, RLS & Functions Changed (`014_creator_insights_live_appeals.up.sql`)**:
  - **Tables & Indexes**: Reused canonical normalized tables without duplicate schemas; added `idx_discussion_posts_drafts_sched`, `idx_appeals_status_created`, `idx_live_streams_status_started`, `idx_post_views_post_viewed`, and `idx_reel_views_reel_viewed`.
  - **RLS & Realtime**: Hardened `discussion_posts_select_visible`, `post_media_select_visible`, `live_streams_select_visible`, `live_comments_select_visible`, `live_comments_insert_live`, `live_reactions_select_visible`, `live_reactions_insert_live`, and `live_viewers_select_visible`; enabled `supabase_realtime` on `appeals`, `live_streams`, `live_comments`, `live_reactions`, and `live_viewers` (bringing live Realtime tables to `18`).
  - **RPCs & Functions**: Hardened `record_post_view(uuid)`, upgraded `get_feed_posts_page(...)` (29 columns with `media_items`, `collaborator_ids`, `tagged_user_ids`, `collaborator_profiles`, `tagged_profiles`), and added `get_my_drafts_and_scheduled_posts()`, `publish_post_now(uuid)`, `get_creator_insights(integer)`, `submit_restriction_appeal(text, text, uuid, text[])`, `start_live_stream(text, text, text)`, `end_live_stream(uuid)`, `join_live_stream(uuid)`, and `leave_live_stream(uuid)`.
- **Migrations Executed**:
  - Applied `014_creator_insights_live_appeals` via `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs up` (recorded `2026-11-12T04:55:54.580Z`).
- **Files Modified / Created**:
  - **Flutter (`/Users/Safi_Sahib/zev-app/lib/`)**:
    - Updated `features/feed/models/feed_post_item.dart` (`FeedPostMediaItem`, `FeedPostUserTag`, `effectiveMediaUrls`, `collaborators`, `taggedUsers`, `isDraft`, `scheduledAt`).
    - Updated `features/feed/screens/create_post_screen.dart` (up to 8-slide carousel reorder/remove, 3 collaborators, 5 tagged accounts picker, draft saving, scheduled `DatePicker`/`TimePicker`, R2 cleanup rollback on failed submit).
    - Updated `features/feed/widgets/feed_post_card.dart`, `features/feed/screens/post_detail_screen.dart`, and `features/feed/screens/fullscreen_media_viewer.dart` (`PageView` multi-slide carousel + `1/N` badge, `"with @collab"` header, `People in this post` Clearmorphic sheet, draft/schedule visibility checks).
    - Created `features/feed/screens/drafts_scheduled_screen.dart` (`DraftsScheduledScreen` backed by `get_my_drafts_and_scheduled_posts`, `publish_post_now`, and R2-safe deletion).
    - Created `features/profile/screens/creator_insights_screen.dart` (`CreatorInsightsScreen` backed by `get_creator_insights` for `7`/`14`/`30`/`90` day windows).
    - Created `features/profile/widgets/appeal_restriction_sheet.dart` (`AppealRestrictionSheet` with up to 3 evidence screenshots via R2 & `submit_restriction_appeal`) and `features/auth/screens/account_standing_screen.dart` (`AccountStandingScreen`), wired into `zev_splash_screen.dart`, `login_screen.dart`, `google_auth_service.dart`, `profile_screen.dart`, `privacy_security_screen.dart`, and `help_support_screen.dart`.
    - Created `features/live/screens/live_rooms_screen.dart` (`LiveRoomsScreen`) and `features/live/screens/live_room_screen.dart` (`LiveRoomScreen`) for Light Clearmorphic Realtime chat & presence rooms, wired from `FeedViewerScreen` (`LiveRoomsScreen.open`) and `ProfileScreen` Create sheet (`LiveRoom`, `Drafts & Scheduled`).
    - Wired `CreatorInsightsScreen` & `DraftsScheduledScreen` into `profile_settings_screen.dart`, `user_activity_screen.dart`, and `profile_screen.dart`.
  - **Admin Portal (`/Users/Safi_Sahib/zev_admin/src/`)**:
    - Created `app/api/admin/appeals/route.ts` and `components/views/AppealsView.tsx` (`pending`, `under_review`, `approved`, `rejected`, evidence lightbox, standing restoration on `APPROVE`, and `admin_audit_logs` + notification writes).
    - Updated `app/api/admin/stats/route.ts`, `components/Sidebar.tsx`, `lib/types.ts`, and `app/page.tsx` (`pendingAppeals` badge and `appeals` console view).

### 4. Verification, Tests & Remaining Gaps
- **Live SQL Transactional Smoke Test (`ROLE authenticated`, `BEGIN...ROLLBACK`)**: `PHASE9_RPC_SMOKE` passed (`get_creator_insights(30)` -> `days: 30, series_len: 30`; `get_my_drafts_and_scheduled_posts()` -> `0`; `get_feed_posts_page` -> `7` rows; `start_live_stream` -> `live`, `live_comments` insert -> `true`, `end_live_stream` -> `ended`).
- **Automated Tests & Analysis**: `flutter test` (`+13: All tests passed!`) and `flutter analyze` (`No issues found! (ran in 22.9s)`) both exited `0`.
- **Admin Build**: `npm --prefix /Users/Safi_Sahib/zev_admin run build` exited `0` (includes `/api/admin/appeals` and `AppealsView`).
- **Remaining / Intentional Scope Boundaries**:
  - `LiveRoomsScreen` / `LiveRoomScreen` deliver real-time chat, reactions, and active participant presence via Supabase Realtime; full WebRTC/Agora A/V broadcast infrastructure is deferred until a dedicated signaling/SFU provider is provisioned.
  - Physical-device multi-user Realtime sync and notification tap verification remain for owner hardware QA.

### 5. Rollback Status
- Reversible via `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs down 014` (`014_creator_insights_live_appeals.down.sql` restores prior `get_feed_posts_page` 25-column signature, policies, and removes Phase 9 functions/indexes) plus Git revert of app/admin files.

### 6. Next Phase
- **Phase 10 — Production Readiness: Security Hardening, Automated Tests, Android Release Build & Signature Verification, Database Integrity Audit & Rollback Verification**

---

## Phase 10 — Production Readiness: Security Hardening, Automated Tests, Build & Signing Verification, DB Audit & Rollback Readiness
**Status**: Completed (Engineering & Verification Complete; External Owner Store/Deploy Prerequisites Itemized Below) (`2026-11-12`)

### 1. What Was Examined
- **Security & Secret Hygiene**: Audited `zev_admin` Next.js 16 authentication (`src/lib/adminAuth.ts`, `src/app/api/admin/auth/route.ts`, `src/proxy.ts`), all `15` `/api/admin/*` route handlers, `zev_admin` subscription/verification mutations (`subscriptions/route.ts`, `verifications/route.ts`), `zev-web` `/api/v1/*` handlers, and `zev-app` source/assets/config (`pubspec.yaml`, `vercel-build.sh`, `lib/**`).
- **Tests, Builds & Signing**: Audited Flutter test suite (`test/widget_test.dart`, `test/core_models_services_test.dart`), static analysis (`flutter analyze`), Android Release Gradle & signing config (`android/gradle.properties`, `android/app/build.gradle.kts`, `AndroidManifest.xml`, keystore APK certificate vs `zev-web/public/.well-known/assetlinks.json`), iOS plist/signing config (`Info.plist`, `GoogleService-Info.plist`), and both Next.js production builds (`zev_admin` `16.4.5`, `zev-web` `15.5.26`).
- **Database Integrity & Recovery**: Audited all migrations `001`–`014`, RLS coverage, policy counts, index coverage, orphan/counter invariants, and backup dump readability (`pg_restore`).

### 2. Issues Discovered
- **`zev_admin` Hardcoded Fallback Secrets & Missing Auth Rate Limit**: `src/lib/adminAuth.ts` fell back to a hardcoded string (`'ZEV-KEY-ALPHA-78942-MASTER'`) when signing env vars were absent, and `src/app/api/admin/auth/route.ts` included 11 hardcoded plaintext fallback master keys (`ADMIN_KEY_1`–`ADMIN_KEY_10` defaults + legacy `'zev2026admin'`), short-circuited on the first key match, had no per-IP brute-force rate limit, and only logged failed attempts via direct PG.
- **Outdated Flutter Widget Test & Deprecated `anonKey`**: `test/widget_test.dart` needed full alignment with Phase 3–9 Light Clearmorphic widgets (`ZevRichText`, `ZevFeedCardSkeleton`, `AccountStandingScreen`, `FeedPostCard`) and replacement of deprecated `Supabase.initialize(anonKey: ...)` with `publishableKey:`.
- **Android Release Build Blocked by `dl.google.com` IPv4 HTTP 404**: `flutter build apk --release` failed resolving `androidx.media:media:1.1.0` and `com.android.tools.build:gradle:8.11.1` on the local network because `https://dl.google.com` returned HTTP `404` over IPv4 (`142.250.130.136`) vs HTTP `200` over IPv6 while Gradle held stale negative cache entries and invalid `systemProp.*` placement in `gradle.properties`.

### 3. Changes Made
- **Security Hardening (`/Users/Safi_Sahib/zev_admin/src/`)**:
  - Updated `lib/adminAuth.ts`: Removed all hardcoded secret fallbacks; fails closed (`null` / `{ valid: false }`) if `ADMIN_SESSION_SECRET` and `SUPABASE_SERVICE_ROLE_KEY` are unset; derives session HMAC key via domain-separated `HMAC-SHA256('zev-admin-session-key-v1', secret)`.
  - Updated `app/api/admin/auth/route.ts`: Removed all 11 hardcoded plaintext fallback passkeys (`ZEV-KEY-...` / `zev2026admin`); strictly reads `ADMIN_KEY_1`–`ADMIN_KEY_10` (`length >= 16`) from `process.env` (returns `503` if none configured); performs full-loop constant-time SHA-256 comparison across all configured keys; adds per-IP sliding-window rate limiting (`429`, max 12 attempts per 5 minutes); persists `FAILED_KEY_LOGIN_ATTEMPT` and `KEY_LOGIN` audit logs via PG primary + `supabaseAdmin` HTTPS fallback.
  - Verified `app/api/admin/subscriptions/route.ts` & `app/api/admin/verifications/route.ts`: Verified `directOk` PG-primary / `supabaseAdmin`-fallback gating (zero duplicate writes), `admin_audit_logs` inserts, and `lifetime` / `lifetime_referral` / `>= 100` referral protection during expiry sweeps.
- **Automated Tests & Android Gradle Fix (`/Users/Safi_Sahib/zev-app/`)**:
  - Updated `test/widget_test.dart` (`publishableKey:` + 4 widget tests covering `ZevRichText`, `ZevFeedCardSkeleton`, `AccountStandingScreen`, `FeedPostCard` carousel/collaborators/tagged pills) alongside `test/core_models_services_test.dart` (9 unit tests covering `TextDirectionHelper`, `FeedPostItem`, `ReelItem`, `FeedAlgorithmService`, `ZevSponsoredAd`, `ZevAdCampaign`).
  - Updated `android/gradle.properties`: Moved `-Djava.net.preferIPv6Addresses=true` into `org.gradle.jvmargs` (L1) and removed invalid `systemProp.*`; refreshed Gradle dependencies cleanly so Google Maven artifacts resolved over IPv6 and populated the local Gradle cache.
- **Database / Migrations**: Zero new schema changes required in Phase 10; verified complete `001`–`014` stack (85 tables, 188 policies, 242 indexes, 118 functions, 18 Realtime tables).

### 4. Verification, Test Matrix & Results (All Executed After Final Code Edits)
| Check | Scope / Command | Measured Outcome |
| :--- | :--- | :--- |
| Flutter Unit & Widget Tests | `cd /Users/Safi_Sahib/zev-app && flutter test` | **Passed (`+13: All tests passed!`)**, exit code `0` (`test/core_models_services_test.dart` + `test/widget_test.dart`) |
| Flutter Static Analysis | `cd /Users/Safi_Sahib/zev-app && flutter analyze` | **Passed (`No issues found! (ran in 22.9s)`)**, exit code `0` |
| Android Release APK Build | `./gradlew --stop && flutter build apk --release` | **Passed (`67.7s`)**, exit code `0` -> `/Users/Safi_Sahib/zev-app/build/app/outputs/flutter-apk/app-release.apk` (`259.4MB`, ProGuard/R8 + icon tree-shake) |
| Release Cert vs AssetLinks | `apksigner verify --print-certs ...app-release.apk` | **Verified**: `CN=Shaheen Safi, O=Safi International Capital LTD`, SHA-256 `9d13b2ef718bf1006f14c23351859bf6ba299b23f213f858055a952d300189cc` matches `zev-web/public/.well-known/assetlinks.json` |
| Admin Portal Build | `npm --prefix /Users/Safi_Sahib/zev_admin run build` | **Passed (`Next.js 16.4.5` Turbopack)**, TypeScript `3.6s`, `21/21` static pages, `15` `/api/admin/*` routes + `Proxy`, exit code `0` |
| Web / API Build | `npm --prefix /Users/Safi_Sahib/zev-web run build` | **Passed (`Next.js 15.5.26`)**, `195/195` static pages + all `13` `/api/v1/*`, `/api/assetlinks`, `/api/delete-account` routes, exit code `0` (benign `@next/swc-darwin-x64` dlopen notice falls back cleanly) |
| Admin Route Auth Audit | `grep -L requireAdminSession` across `zev_admin/src/app/api/admin/**/route.ts` | Only `auth/route.ts` unauthenticated (login endpoint); all `14` data/action routes enforce `requireAdminSession` + `src/proxy.ts` cookie HMAC |
| Source Secret Scan | `grep -rnE "ZEV-KEY-\|zev2026admin\|eyJhbGciOi"` across `zev_admin/src`, `zev-app/lib`, `zev-web/src` | **Clean** (zero hardcoded keys/JWTs; only UI input hint `placeholder="ZEV-KEY-..."` in `LoginView.tsx:139`) |
| DB Migration Status & Verify | `node scripts/migrations/migrate.mjs status && verify` | Migrations `001`–`014` all `applied: true`; **0 anomalies** (`0` policy-less RLS tables, `0` unprotected tables, `0` missing profiles, `0` `zev_fmc`/`zev_fcm` refs, `0` orphans, `0` drifted counters) |
| Live PostgreSQL Totals | `verify_db_stats.mjs` | `85` public tables (`85/85` RLS enabled), `188` RLS policies, `242` indexes, `118` public functions, `18` `supabase_realtime` tables |
| Backup Restore Check | `/usr/local/Cellar/libpq/18.6/bin/pg_restore --schema-only -f /dev/null backups/pre_migration_backup.dump` | **`PG_RESTORE_OK`**, exit code `0` (verified with PG 18.6 matching dump version) |

### 5. Remaining Gaps & External Owner Prerequisites
1. **Backend & Admin Vercel Deployment (`zev-web`, `zev_admin`)**: Commit and deploy updated Next.js code and verify production environment variables in Vercel (`FIREBASE_SERVICE_ACCOUNT_JSON`, `ADMIN_KEY_1`–`ADMIN_KEY_10`, `ADMIN_SESSION_SECRET` / `SUPABASE_SERVICE_ROLE_KEY`, R2 keys, `DATABASE_DIRECT_URL`).
2. **Firebase Native OAuth Credentials (`zevapp-3c6b5`)**: Register Android Release & Google Play App Signing SHA-256 fingerprints in Firebase/Google Cloud Console and download updated `android/app/google-services.json` (currently `oauth_client: []`); register iOS OAuth client ID and add `CLIENT_ID` / `REVERSED_CLIENT_ID` into `ios/Runner/GoogleService-Info.plist` for iOS Google Sign-In.
3. **Store Packaging & Apple Code Signing**: Generate Android Play Store `.aab` (`flutter build appbundle --release`; if a fresh CI runner hits an IPv4-404 CDN edge on `dl.google.com`, pass `JAVA_TOOL_OPTIONS="-Djava.net.preferIPv6Addresses=true"`) and archive/sign the iOS release build in Xcode / App Store Connect with APNs push credentials.
4. **Physical-Device E2E QA & Production Network Profiling**: Run manual interactive acceptance on real Android/iOS hardware (Google Login in Release, foreground/background/terminated FCM push notification tap routing, camera media uploads, AdMob fill, multi-device chat/live sync, real-network p50/p95 latency & frame-jank measurements per `map.txt`), and configure Cloudflare Edge cache rules for `media.zevapp.com` if first-hop CDN `HIT` caching is desired.

### 6. Rollback Status
- **Full Rollback Available**:
  - Database schema reverts cleanly migration-by-migration (`014` down to `001`) via `node /Users/Safi_Sahib/zev-app/scripts/migrations/migrate.mjs down <version>`.
  - Full cold Phase 0 dump (`/Users/Safi_Sahib/zev-app/backups/pre_migration_backup.dump`) is tested readable with `pg_restore` 18.6 (`exit code 0`).
  - All Flutter (`zev-app`), web/API (`zev-web`), and admin (`zev_admin`) working-tree changes revert cleanly via Git prior to release deployment.

### 7. Next Phase
- **Roadmap Complete (Phases 0–10 Completed)** — Ready for owner environment-variable sync, Vercel/Store deployment, and physical-device release QA.
