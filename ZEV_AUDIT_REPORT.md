# ZEV — Complete Engineering & Security Audit Report (Phase 0)

> **Date**: 2026-11-12  
> **Scope**: `zev-app` (Flutter Mobile & Web), `zev-web` (Next.js Website & Backend API), `zev_admin` (Next.js Admin Portal), Supabase PostgreSQL (`zjwmioalrhkyfbzhdnnw.supabase.co`), Cloudflare R2 (`safiacademy-media` / `https://media.zevapp.com`), Firebase (`zevapp-3c6b5`).  
> **Security Notice**: All secrets, tokens, connection strings, and credentials have been omitted or masked from this report.

---

## 1. Executive Summary & Pre-Migration Backup Verification

Before performing any database schema modification or source refactoring, a complete Phase 0 audit and full recoverable database backup were executed.

### Recoverable Database Backup Status
- **Source Engine**: PostgreSQL `17.11` (`pg_dump` `18.6` compatible client dump)
- **Plain SQL Backup**: `/Users/Safi_Sahib/zev-app/backups/pre_migration_backup.sql` (**429,054 bytes**, 5,202 lines) — verified readable and contains full DDL + data.
- **Custom Format Archive**: `/Users/Safi_Sahib/zev-app/backups/pre_migration_backup.dump` (**229,560 bytes**) — verified with `pg_restore --list` (**405 TOC entries**).
- **Git Hygiene**: `/Users/Safi_Sahib/zev-app/.gitignore` updated to ignore `/backups/` and `/scripts/migrations/*.env`.

### Critical Headline Risks Found
1. **Authentication & Signup Silent Profile Failure**: `RegisterScreen` inserts `'role': 'student'` into `profiles` (a column that does not exist in `profiles`), causing upsert failure swallowed silently, leaving **11 orphaned `auth.users` accounts (55 auth users vs. 44 `profiles`)**. Session storage uses plaintext `SharedPreferences` instead of OS-backed `FlutterSecureStorage`, and `PasskeyAuthService` persists plaintext password secrets (`zev_pk_secret_*`) in `SharedPreferences`.
2. **Severe Client Secret Exposure**: `pubspec.yaml` bundles `.env` into release binaries, containing service role, database, R2, Stripe, Vision/Gemini, and OAuth secrets. `TelegramNotificationService` also hardcodes two Telegram Bot tokens directly inside compiled Dart source literals.
3. **Permissive & Missing RLS Policies**: `reels`, `reel_comments`, `reel_likes`, and `reel_views` allow anonymous/public inserts, updates, and deletes (`qual=true`). Six RLS-enabled tables (`message_reactions`, `referrals`, `story_views`, `subscriptions`, `user_restrictions`, `admin_audit_logs`) have **zero policies**, blocking legitimate flows or forcing insecure workarounds. `profiles` exposes PII publicly and lacks column protection on `is_verified`, `lifetime_blue_eligible`, `warning_count`, `is_restricted`, and `referral_count`.
4. **Google OAuth & Deep Links Misconfiguration**: `GoogleAuthService` defaults `iosClientId` to the Web Client ID, `ios/Runner/Info.plist` mirrors that Web Client ID, `android/app/google-services.json` has an empty `oauth_client: []`, `GoogleService-Info.plist` lacks `CLIENT_ID`/`REVERSED_CLIENT_ID`, and all three Digital Asset Links sources (`zev-web/public/.well-known/assetlinks.json`, `api/assetlinks/route.ts`, `cloudflare-worker-assetlinks.js`) contain truncated 31-byte SHA-256 hashes missing both the actual Release and Debug keystore fingerprints.
5. **Firebase Push & FCM Fragmentation**: `profiles` contains 3 redundant FCM columns (`zev_fmc`, `zev_fcm`, `fcm_token`) with one active user (`shaheensafi011`) having a valid 142-char token stored **only** in `zev_fmc`. `lib/firebase_options.dart` is missing, `flutter_local_notifications` and Android channel creation are absent, and no local Firebase Admin SDK service account JSON exists for backend push dispatch.
6. **Design & Functional Regressions**: 9 duplicated Screen vs. `*_sheet.dart` pairs under `features/profile/`, wrong foreign-key column names (`user_id` vs. `student_id`, `post_bookmarks` vs. `discussion_bookmarks`, `story_highlights` vs. `user_highlights`, `reels.caption` vs. `title`/`description`), fake UI stubs (`FeedShareSheet._sendToFriend`, `UserActivityScreen._weeklyUsage`, `help_support_sheet`), per-tile video controllers, dark-mode AdMob widgets contradicting ZEV Clearmorphism (`ZevColors`), and white text on light pink background in `zev-web/src/app/[locale]/delete-account/page.tsx`.

---

## 2. Current Architecture

```
+-------------------------------+       +----------------------------------+
|     ZEV Mobile / Web App      |       |     ZEV Marketing & API Site     |
|  Flutter 3.47.9 / Dart 3.11   |       |  Next.js 15.2 (zev-web)          |
|  com.zevapp.app (v1.0.0+9)    |       |  https://www.zevapp.com          |
+---------------+---------------+       +-----------------+----------------+
                |                                         |
                | Currently direct R2/Vision/Telegram!    | Currently only /api/delete-account
                | (To migrate -> /api/v1/* proxy)         | & /api/assetlinks
                v                                         v
+-------------------------------------------------------------------------+
|               Supabase PostgreSQL 17.11 + Auth + Realtime               |
|                  (zjwmioalrhkyfbzhdnnw.supabase.co)                     |
+------------------------------------+------------------------------------+
                                     |
         +---------------------------+---------------------------+
         v                                                       v
+-----------------------------------+      +------------------------------+
|  Cloudflare R2 (safiacademy-media)|      |  Firebase Project zevapp-3c6b5|
|  CDN: https://media.zevapp.com    |      |  FCM Sender: 467206192154    |
|  Shared bucket — MUST restrict    |      |  Android + iOS registered    |
|  ZEV mutations to zev/ prefix!    |      |                              |
+-----------------------------------+      +------------------------------+

Separate Operations Portal: zev_admin (Next.js, adminportal.zevapp.com)
```

---

## 3. Existing Database Schema, Constraints & Integrity Audit

- **Engine**: PostgreSQL `17.11`
- **Installed Extensions**: `pg_stat_statements (1.11)`, `pgcrypto (1.3)`, `plpgsql (1.0)`, `supabase_vault (0.3.1)`, `uuid-ossp (1.1)`
- **Total Size Across Public Tables**: ~2,344 KB (~2.34 MB) across **35 tables** and **1 view** (`public.notifications` -> `user_notifications`), **0 materialized views**
- **Constraints**: `35` Primary Keys, `55` Foreign Keys, `77` Unique constraints, **0 explicit `CHECK` constraints** (beyond `_not_null`), plus an `rls_auto_enable` event trigger enabling RLS automatically on new `public` tables
- **Realtime Publications (`supabase_realtime`)**: `direct_messages`, `discussion_likes`, `discussion_posts`, `reels`, `user_follows`, `user_notifications`

### Existing Tables & Live Row Counts

| Category | Table | Rows | Size | Notes / Deficiencies |
|---|---|---:|---:|---|
| Users | `profiles` | 44 | 496 kB | Missing `is_private`, `is_banned`, `is_deactivated`, counter columns; 3 FCM columns (`zev_fmc`, `zev_fcm`, `fcm_token`); 11 missing profiles for `auth.users` |
| Users | `push_subscriptions` | 1 | 80 kB | Single row (`javad_mansuri`, `app_name='zev'`, Android) |
| Users | `user_trusted_devices` | 1 | 64 kB | Used by MFA |
| Verification | `user_verifications` | 8 | 96 kB | 5 `verified`, 3 `revoked`; duplicate indexes on `user_id` |
| Billing / Refs | `subscriptions` | 0 | 40 kB | Needs zero-policy RLS fix & expiration enforcement |
| Billing / Refs | `referrals` | 0 | 48 kB | Duplicate `referee_id`/`referred_id` columns; 0 RLS policies |
| Social Graph | `user_follows` | 7 | 104 kB | No `status` for private follow requests; missing self-follow check |
| Social Graph | `student_friends` | 2 | 48 kB | Public `SELECT qual=true` leaks pending requests |
| Social Graph | `user_blocks` | 0 | 32 kB | Missing self-block check; blocks not enforced on posts/comments/DMs/follows |
| Feed / Posts | `discussion_posts` | 7 | 32 kB | Only 6 columns; lacks `video_url`, `post_type`, `visibility`, `status`, counters, `deleted_at` |
| Feed / Posts | `discussion_comments` | 3 | 48 kB | Missing FK on `student_id`; lacks edit/pin/soft-delete/likes_count |
| Feed / Posts | `discussion_likes` | 14 | 40 kB | Missing FK on `student_id`; **5 orphaned rows** |
| Feed / Posts | `discussion_bookmarks` | 0 | 16 kB | Code in 2 places wrongly queries `post_bookmarks` |
| Feed / Posts | `post_reposts` | 2 | 40 kB | Active |
| Discovery | `hashtags` | 10 | 96 kB | Duplicate index on `tag` |
| Discovery | `post_hashtags` | 0 | 32 kB | Over-permissive `ALL` RLS policy |
| Reels | `reels` | 17 | 64 kB | **2 drifted `likes_count` rows** (`0` vs actual `1`); anon write/delete RLS! |
| Reels | `reel_comments` | 1 | 48 kB | Broken `notify_on_reel_comment()` trigger (`NEW.comment`); anon write/delete RLS! |
| Reels | `reel_likes` | 35 | 72 kB | Redundant indexes; anon write/delete RLS! |
| Reels | `reel_views` | 88 | 72 kB | Redundant indexes; anon insert RLS! |
| Reels | `reel_bookmarks` | 1 | 72 kB | Active |
| Reels | `reel_hashtags` | 0 | 32 kB | Over-permissive `ALL` RLS policy |
| Stories | `user_stories` | 4 | 48 kB | Lacks close-friends visibility flag & view counter |
| Stories | `story_views` | 0 | 16 kB | RLS enabled, **0 policies** |
| Stories | `story_likes` | 0 | 16 kB | Missing owner/block checks |
| Highlights | `user_highlights` | 168 | 88 kB | 42 users x 4 default groups, `with_cover_url=0`; app wrongly queries `story_highlights` |
| Highlights | `user_highlight_stories` | 0 | 24 kB | Empty |
| Messaging | `direct_messages` | 56 | 128 kB | 1:1 DM only; no `conversation_id`, groups, reply/forward/edit/delete-for-me |
| Messaging | `message_reactions` | 0 | 24 kB | RLS enabled, **0 policies** |
| Messaging | `chat_pins` | 0 | 40 kB | Per-peer only; no group support |
| Notifications | `user_notifications` | 773 | 400 kB | Missing FK on `user_id`; **238 orphaned rows**; forged inserts allowed (`check=true`) |
| Moderation | `user_reports` | 0 | 32 kB | User reports only |
| Moderation | `user_restrictions` | 0 | 16 kB | RLS enabled, **0 policies** |
| Moderation | `user_support_tickets` | 0 | 16 kB | Ignored by `help_support_sheet.dart` |
| Admin | `admin_audit_logs` | 7 | 32 kB | RLS enabled, **0 policies**; no FK |

### Broken Functions, Triggers & Schema Mismatches
1. **`notify_on_reel_comment()`**: Reads `NEW.comment`, but `reel_comments` column is `comment_text` -> triggers runtime SQL error on every reel comment insertion.
2. **Duplicate/Conflicting DM Notifications**: `create_direct_message_notification()` (active on `tr_direct_message_inserted`) inserts hardcoded Persian `'💬 پیام جدید'` and omits `app_source='zev'`; unused `notify_on_direct_message()` also exists in `public`.
3. **Conflicting Username Normalization**: `generate_unique_username()` and `trg_assign_auto_username()` strip `.` (`[^a-z0-9_]`), conflicting with `check_username_unique_and_format()` (`^[a-z0-9_.]{3,30}$`).
4. **Broken Admin RPC**: `get_admin_dashboard_stats()` queries non-existent `profiles.role`, `courses`, `tickets`, and `transactions`.
5. **Verification State Conflict**: `handle_referral_insert()` sets `profiles.is_verified = true` directly at 100 referrals without creating/syncing `user_verifications`, whereas `sync_profile_verification()` resets `is_verified = false` on delete/revoke without checking `lifetime_blue_eligible` or active non-expired `subscriptions`.
6. **FCM Token Fragmentation (`profiles` vs. `push_subscriptions`)**: `has_zev_fmc=2`, `has_zev_fcm=1`, `has_fcm_token=1`. Specifically, user `shaheensafi011` (`acc15e15-73e9-4785-abf5-be8beec2581f`, active `2026-11-11`) has a valid 142-char FCM token **only** in `zev_fmc`. Dropping `zev_fmc` without coalescing first would erase their push reachability.
7. **Legacy Media URLs Remaining in DB**: 81 unique referenced media URLs split across `media.safiacademy.org` (55), obsolete `enpuoypqpklndnnhndax.supabase.co` (16), `media.zevapp.com` (9), `lh3.googleusercontent.com` (1).

---

## 4. Feature Status Matrix (`Healthy` / `Partial` / `Broken` / `Missing`)

| Domain | Feature | Status | Root Cause Summary |
|---|---|---|---|
| Auth & Session | Email Login & Session Persistence | **Partial** | Works short-term via `SharedPreferences`, but lacks `FlutterSecureStorage`, singleflight refresh lock, resume refresh, and revocable session logs. |
| Auth & Session | Email Registration (`RegisterScreen`) | **Broken** | Sends `'role': 'student'` to `profiles` (column doesn't exist), creating 11 `auth.users` without profiles; inserts RLS-blocked `referrals` from client. |
| Auth & Session | Google Sign-In (`GoogleAuthService`) | **Broken** | Web Client ID used as `iosClientId`; empty `oauth_client` in `google-services.json`; missing `CLIENT_ID` in `GoogleService-Info.plist`; risk of duplicate accounts. |
| Auth & Session | Passkey / Biometric Login (`PasskeyAuthService`) | **Broken** | Stores plaintext password secrets (`zev_pk_secret_*`) in `SharedPreferences` instead of OS secure enclave / hardware tokens. |
| Auth & Session | App Links / Deep Links | **Broken** | All 3 `assetlinks.json` endpoints contain truncated 31-octet SHA-256 hashes not matching Release (`9D:13:...`) or Debug (`7F:7F:...`) keystores. |
| Social Core | Follow / Unfollow / Friends | **Partial** | `user_follows` works publicly, but lacks private-account `follow_requests`, atomic counters, and block exclusion. |
| Social Core | Likes & Bookmarks | **Partial** | `reels.likes_count` has drift; `ProfileScreen` & `ContentDeletionService` query non-existent `post_bookmarks` instead of `discussion_bookmarks`. |
| Social Core | Comments (Posts & Reels) | **Broken** | Reel comments trigger crashes (`NEW.comment`); missing edit, pin, comment likes, replies UI completeness, and mention notifications. |
| Social Core | Content Deletion (`ContentDeletionService`) | **Partial** | Queries non-existent `post_bookmarks`; leaves uploaded R2 media objects orphaned. |
| Social Core | Activity & Insights (`UserActivityScreen`, `ActivityLikesScreen`) | **Broken** | Queries wrong columns (`user_id` instead of `student_id`, `discussion_posts.video_url`, `reels.caption`); `_weeklyUsage` renders hardcoded dummy metrics. |
| Profile | Highlights (`StoryHighlightService`) | **Broken** | Queries non-existent `story_highlights` table while live DB has `user_highlights` (168 rows) + `user_highlight_stories`. |
| Profile | Help & Support (`help_support_sheet.dart`) | **Broken** | Uses `Future.delayed(600ms)` stub instead of inserting into `user_support_tickets` & dispatching backend alert. |
| Profile | Settings & Privacy | **Partial** | 9 duplicated screen vs. sheet files (`edit_profile`, `mfa_settings`, `notification_settings`, etc.); `NotificationSettingsScreen` saves only to local `SharedPreferences`. |
| Chat & Sharing | Direct Messages | **Partial** | 1:1 text/media works, but missing group chats, reply/forward/edit/delete-for-everyone, active `message_reactions` RLS, offline queue, and real typing/presence without 30s DB writes. |
| Chat & Sharing | `FeedShareSheet` ("Send to Friend" / "Add to Story") | **Broken** | `_sendToFriend` updates local `_sentFriendIds` + SnackBar only without persisting to `direct_messages`. |
| Notifications | In-App Notification Center | **Partial** | 238 orphan rows; mixed table/view queries; permissive insert RLS; DM notifications hardcoded in Persian and missing `app_source='zev'`. |
| Notifications | Firebase Push (FCM) | **Partial** | Android initializes implicitly via `google-services.json`, but missing `firebase_options.dart`, `flutter_local_notifications`, channel registration, `onTokenRefresh`, and backend dispatcher. |
| Media & UI | Video Thumbnails & Reels Caching | **Broken** | `ZevVideoThumbnail` extracts/initializes video players per tile; `ReelVideoCacheManager` L97 leaks an undisposed controller in `catchError`; R2 lacks `Cache-Control`. |
| Media & UI | Ads & Monetization UI (`ZevNativeAd*`) | **Partial** | Uses dark `#0F172A`/`#080D1A` card surfaces that clash with Clearmorphism; lacks self-serve ad campaign/budget/impression/click DB backend. |
| Website (`zev-web`) | API Proxy & Delete Account UI | **Partial** | `/api/v1/*` routes missing; `/api/delete-account` reads `NEXT_PUBLIC_TELEGRAM_*`; `/[locale]/delete-account` renders `#FFFFFF` H1 text over light `#FFF1F4` card. |

---

## 5. Security, RLS & Secret Exposure Audit

1. **Client `.env` Asset Bundling (`pubspec.yaml` L64–66 & `vercel-build.sh`)**: Packaging `.env` exposes `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_DIRECT_URL`, Cloudflare R2 read/write credentials, Stripe keys, Google Vision/Gemini keys, and Telegram tokens inside mobile APK/IPA and web bundles. Furthermore, `vercel-build.sh` falls back to obsolete `enpuoypqpklndnnhndax.supabase.co` and `safiacademy.org/en`.
2. **Hardcoded Bot Tokens (`TelegramNotificationService` L13–17)**: Primary and secondary Telegram bot tokens and chat ID are hardcoded directly in Dart source code.
3. **Insecure Local Persistence**: `PasskeyAuthService` persists plaintext password strings in unencrypted `SharedPreferences`; `AuthHelper` and `MultiAccountService` persist auth flags and user roles outside `FlutterSecureStorage`.
4. **Open Anon Write/Delete RLS**:
   - `reels`: `anon` and `authenticated` can `INSERT` (`true`), `UPDATE` (`true`), `DELETE` (`(auth.uid() = user_id) OR true`) — anyone can wipe or overwrite all Reels.
   - `reel_comments` & `reel_likes` & `reel_views`: open `anon` insert/update/delete policies (`true`).
   - `user_notifications`: `authenticated` can forge notifications to any user (`check=true`).
5. **Unguarded Privilege & PII Columns on `profiles`**: Public `SELECT` exposes `email`, `phone_number`, `date_of_birth`, and FCM tokens; user `UPDATE` lacks `WITH CHECK` or trigger guards, letting malicious clients self-grant `is_verified = true`, `lifetime_blue_eligible = true`, `referral_count = 999`, or clear `is_restricted`.
6. **6 Locked-Out Tables (`RLS = true`, 0 policies)**: `message_reactions`, `referrals`, `story_views`, `subscriptions`, `user_restrictions`, `admin_audit_logs`.
7. **`discussion_posts` Missing Owner Mutations**: Users cannot update or delete their own posts via RLS because `UPDATE` and `DELETE` policies are absent.

---

## 6. Performance, Storage (R2) & Firebase Audit

### Performance & Scalability Bottlenecks
- **Every-30-Seconds Presence DB Write**: `UserPresenceService.startPresenceHeartbeat()` updates `profiles` (`last_seen`, `last_seen_at`, `is_online`, `updated_at`) every 30s per active user, generating unnecessary WAL bloat and DB write contention instead of using Supabase Realtime Presence + throttled heartbeats.
- **Duplicate & Redundant Indexes**: Redundant indexes waste write IOPS and storage across `user_verifications` (3 indexes on `user_id`), `referrals`, `subscriptions`, `hashtags`, `push_subscriptions`, `user_trusted_devices`, `direct_messages`, `reel_likes`, and `reel_views`. Missing indexes on high-traffic lookups (`discussion_posts(student_id, created_at DESC)`, `discussion_comments(post_id, created_at)`, `user_notifications(user_id, created_at DESC)`).
- **Zero-Cache Video Thumbnails & Memory Leak**: `ZevVideoThumbnail` runs client frame extraction / `VideoPlayerController` per grid tile, and `ReelVideoCacheManager` L97 creates an untracked `VideoPlayerController.networkUrl` on preload failure.
- **Uncached CDN Media**: Sampled `zev/` object on R2 returned `Cache-Control: null`, causing repeated CDN/origin hits.
- **No Cursor Pagination**: Feeds/notifications fetch flat ranges instead of keyset `(created_at, id)` cursors.

### Cloudflare R2 (`safiacademy-media`) Audit
- **Total Bucket Objects**: `133` objects (`531.17 MB`) across `25` prefixes (`121` objects / `521.78 MB` belong to **SafiAcademy** — strictly untouched).
- **`zev/` Prefix Inventory**: `12` objects (`9.39 MB`):
  - **9 referenced in DB** (`3.96 MB`)
  - **3 orphaned `zev/` objects** (`5.43 MB`): `zev/avatars/avatar_2dd6a530-..._1794347988970.png` (1,260.8 KB), `zev/avatars/avatar_2dd6a530-..._1794348493173.png` (1,260.8 KB), `zev/stories/highlight_vid_acc15e15-..._1793691174052.mp4` (3,036 KB).
- **CORS**: `200 OK` (`*` origin allowed). Needs stricter origin scoping in production if presigned PUT uploads are targeted only from verified domains/apps.

### Firebase (`zevapp-3c6b5`) & Keystore Audit
- **Sender / Project Number**: `467206192154` | **Android App**: `1:467206192154:android:3bfe5b870b675fc6fc25a3` | **iOS App**: `1:467206192154:ios:9a30149aa891ddc5fc25a3`
- **Verified Keystores**:
  - Release (`upload-keystore.jks`, alias `upload`): SHA-1 `9C:D4:0C:D7:FD:6C:C9:8A:22:13:4E:DC:23:D8:26:D8:91:87:10:6B`, SHA-256 `9D:13:B2:EF:71:8B:F1:00:6F:14:C2:33:51:85:9B:F6:BA:29:9B:23:F2:13:F8:58:05:5A:95:2D:30:01:89:CC`
  - Debug (`androiddebugkey`): SHA-1 `FC:97:D5:EC:8B:6F:69:0A:4B:27:15:E8:4C:A9:71:A2:FA:73:0A:53`, SHA-256 `7F:7F:47:75:EF:CF:F7:29:60:3B:22:5A:FE:10:08:25:AF:C0:FD:83:A4:8F:98:5C:08:20:10:0C:5D:9D:0F:F3`
- **External Credential Note**: No Firebase Admin SDK service account JSON exists locally (`firebase login` session is expired). Backend push endpoint (`/api/v1/push/send`) will support `FIREBASE_SERVICE_ACCOUNT_JSON` cleanly and report diagnostic `503` until provisioned in Vercel.

---

## 7. Prioritized Roadmap (Phases 1–10) & Risk Assessment

| Phase | Focus Area | Key Risks & Mitigations |
|---|---|---|
| **Phase 1** | Backend `/api/v1/*` Proxy, Auth, Session, OAuth, AssetLinks, Clearmorphic Web Contrast | Preserve signed-in sessions via seamless `SharedPreferences` -> `FlutterSecureStorage` migration; never embed private keys in Dart. |
| **Phase 2** | Reversible SQL Migrations, FCM Consolidation -> `user_devices`, Orphan Cleanup, RLS Hardening, Schema Expansion, Indexes & Atomic Counters | Test every migration (`up`/`down`), backfill 11 missing profiles first, coalesce `zev_fmc`/`zev_fcm`/`fcm_token` before dropping legacy columns, handle `rls_auto_enable` in every migration. |
| **Phase 3** | Social Core (Consolidate 9 Screen/Sheet pairs, Fix Wrong Columns, Follow Requests, Block/Restrict/Mute, Comments/Edits/Deletions) | Backward-compatible queries alongside new normalized columns; rollback optimistic UI cleanly on backend failure. |
| **Phase 4** | Chat & Messaging (Groups, Delivery/Read/Typing Presence, Offline Queue, Wire `FeedShareSheet`) | Ensure idempotent message UUIDs; preserve existing 56 `direct_messages` rows; avoid continuous DB heartbeat writes. |
| **Phase 5** | Notifications & FCM (`firebase_options.dart`, Local Channels, `onTokenRefresh`, DB-Backed Preferences & Badges) | Respect user notification preferences at both DB trigger and push dispatch levels; deactivate stale device tokens on logout/invalid response. |
| **Phase 6** | Media Pipeline & Performance (Presigned Progress Uploads, Blur Placeholders, Cached Thumbnails, Cursor Pagination, R2 `Cache-Control` & Orphan Cleanup of 3 `zev/` files only) | Enforce strict `zev/` path filter on every R2 listing/modification/deletion so zero SafiAcademy files are ever touched. |
| **Phase 7** | Content Experience (Following vs For You Ranking RPCs, Unified Search + History, 24h Stories + Highlights on `user_highlights`) | Preserve existing 168 `user_highlights` and 4 `user_stories` while migrating app queries off `story_highlights`. |
| **Phase 8** | Clearmorphic Ads & ZEV Blue Monetization (Clearmorphic Ad Units, Idempotent Impression/Click/Conversion, Atomic Budgets, Blue Expiration Enforcement) | Strictly keep UI aligned with `ZevColors` Clearmorphism; prevent budget race conditions via PostgreSQL row locks / atomic RPCs. |
| **Phase 9** | Creator Insights, Moderation Appeals, GDPR Data Export, Carousels, Drafts/Scheduled Posts, Live Streams | Ensure all metrics derive from real DB queries/telemetry, zero hardcoded dummy charts. |
| **Phase 10** | Full Verification (`flutter analyze`, `flutter test`, DB/RLS/Reconcile suite, `pg_restore` test, Release/Web builds, `zev_admin` check, Benchmark comparisons) | Never mark any check complete without executed output evidence. |

