# ZEV Firebase Push Notification Architectural Audit & Diagnostic Report

**Target Environment:** Production (`com.zevapp.app`)  
**Firebase Project ID:** `zev-app-844ef`  
**Firebase Sender ID (Project Number):** `557150004230`  
**Target Physical Test Device:** Samsung Galaxy S23 Ultra (`SM-S918U` / Android 14 API 34)  
**Backend API Gateway:** `https://www.zevapp.com/api/v1/push/send` (Vercel Edge/Serverless)  
**Date of Audit:** November 13, 2026  

---

## 1. Executive Summary & Root Cause Analysis

Prior to this intervention, Push Notifications in the ZEV application were failing silently. The deep investigation identified three fatal breakdowns across the delivery chain:

| Layer | Component | Root Cause Breakdown | Status |
| :--- | :--- | :--- | :--- |
| **Firebase Project** | Credentials & Project ID | The previous Firebase project `zevapp-3c6b5` was deleted. FCM tokens issued under Sender ID `467206192154` were permanently invalidated by Google (`403 SENDER_ID_MISMATCH`). | **Resolved** (Migrated to `zev-app-844ef`) |
| **Backend (Vercel)** | Service Account Key | Vercel production environment variable `FIREBASE_SERVICE_ACCOUNT_JSON` was referencing credentials from the deleted project. Every dispatch to `/api/v1/push/send` returned `failedCount: 5`. | **Resolved** (Updated & Redeployed) |
| **Client (Android)** | Google Services & Channels | Mobile client needed `google-services.json` rebuilt with project number `557150004230` and notification channel registered with `Importance.max`. | **Resolved** (Synchronized `zev_notifications_channel`) |
| **In-App Experience** | Active Chat Noise | When user was in an active chat room, background/realtime listeners fired redundant banners for that exact conversation. | **Resolved** (`_isViewingActiveChat` lifecycle filter) |

---

## 2. Infrastructure & Configuration Verification

### 2.1 Firebase Project Configuration
- **Active Project:** `zev-app-844ef`
- **Sender ID:** `557150004230`
- **Android App:** `com.zevapp.app` (`1:557150004230:android:5d9e8501608c6d8933cf87`)
- **iOS App:** `com.zevapp.app` (`1:557150004230:ios:5e7441bd05f98b6833cf87`)
- **Web App:** `1:557150004230:web:bac688ed8bf4f51d33cf87`
- **Web Push / VAPID Key:** `BJHpXJtWyirbIrXTWNE2B40KGwXO7cTtdZNiBc0xTsQ1aTg1MhJcwDGhzA04qO1oSL4_BTNDwG6xQ-kycn-36VE`
- **SHA-1 Registered:**
  - Debug: `FC:97:D5:EC:8B:6F:69:0A:4B:27:15:E8:4C:A9:71:A2:FA:73:0A:53`
  - Release: `9C:D4:0C:D7:FD:6C:C9:8A:22:13:4E:DC:23:D8:26:D8:91:87:10:6B`
- **Service Account Email:** `firebase-adminsdk-fbsvc@zev-app-844ef.iam.gserviceaccount.com`

### 2.2 Client-Side Configuration Files
1. **Android Config:** `/Users/Safi_Sahib/zev-app/android/app/google-services.json`
   - Verified matching package `com.zevapp.app` and project number `557150004230`.
2. **iOS Config:** `/Users/Safi_Sahib/zev-app/ios/Runner/GoogleService-Info.plist`
   - Verified matching bundle ID `com.zevapp.app` and project `zev-app-844ef`.
3. **Dart Firebase Options:** `/Users/Safi_Sahib/zev-app/lib/firebase_options.dart`
   - Contains platform-specific `FirebaseOptions` mapping to `zev-app-844ef`.
4. **App Config:** `/Users/Safi_Sahib/zev-app/lib/core/config/app_config.dart`
   - Synchronized default `firebaseVapidKey` with `BJHpXJtWyirbIrXTWNE2B40KGwXO7cTtdZNiBc0xTsQ1aTg1MhJcwDGhzA04qO1oSL4_BTNDwG6xQ-kycn-36VE`.

---

## 3. End-to-End Delivery Architecture

```
[Sender / Trigger]
      │
      ▼
[ZEV Backend API (/api/v1/push/send)]
      │
      ├─► Look up target user active tokens in Supabase (`user_devices`)
      ├─► Generate OAuth2 Google Access Token (RS256 JWT using Service Account)
      ├─► POST payload to FCM HTTP v1 (`fcm.googleapis.com/v1/projects/zev-app-844ef/messages:send`)
      │
      ▼
[Google FCM Gateway]
      │
      ▼
[User Device (Samsung Galaxy S23 Ultra)]
      ├─► Background/Terminated: Handled natively by OS → System Tray Banner
      └─► Foreground: Handled by `FirebaseMessaging.onMessage` → In-App Glassmorphic Alert
```

---

## 4. FCM Token Lifecycle & Database Sync

1. **Token Generation:**
   - On app launch, `FirebaseMessaging.instance.getToken()` queries Google Play Services using `557150004230`.
   - The token is registered to `profiles.fcm_token` and `user_devices` (device ID `CP2A.260605.016`, platform `android`).
2. **Token Refresh:**
   - `FirebaseMessaging.instance.onTokenRefresh` listens for token rotations and updates Supabase automatically.
3. **Automatic Stale Token Pruning:**
   - When FCM returns `UNREGISTERED` or `INVALID_ARGUMENT`, the backend immediately marks `is_active: false` in `user_devices` to keep the dispatch pipeline performant and clean.

---

## 5. Verification & Test Outcomes

### Priority Test 1: Direct FCM Token Dispatch
- **Target Device Token:** `e4aJlPSgT7yrUiJ17lceKq...` (Samsung Galaxy S23 Ultra)
- **FCM Endpoint:** `https://fcm.googleapis.com/v1/projects/zev-app-844ef/messages:send`
- **Result:** **HTTP 200 OK**
- **Google Message ID:** `projects/zev-app-844ef/messages/0:1794556067589982%67b69a5667b69a56`

### Priority Test 2: Production Backend `/api/v1/push/send` Dispatch
- **Target User ID:** `acc15e15-73e9-4785-abf5-be8beec2581f` (`shaheensafi011`)
- **API URL:** `https://www.zevapp.com/api/v1/push/send`
- **Payload:**
  ```json
  {
    "recipientUserId": "acc15e15-73e9-4785-abf5-be8beec2581f",
    "title": "ZEV Live Push Verification",
    "body": "پیام تستی به گوشی سامسونگ S23 Ultra شما با موفقیت ارسال شد!",
    "notificationType": "message",
    "deepLink": "/chat/test"
  }
  ```
- **Response:**
  ```json
  {"ok":true,"configured":true,"sentCount":1,"failedCount":0,"invalidTokensCount":0}
  ```

### Priority Test 3: End-to-End Chat Event Dispatch
- **Sender:** User `8be98ef6-06ce-49f2-8222-118371e03f7d` (`@shaheensafi09`)
- **Recipient:** User `acc15e15-73e9-4785-abf5-be8beec2581f` (`@shaheensafi011`)
- **Audit Table Verification:** Recorded in Supabase `notification_deliveries`:
  - `id`: `af234bac-e7b5-4040-aa29-21155cc1bbf6`
  - `status`: `sent`
  - `tokens_targeted`: `1`
  - `sent_count`: `1`
  - `failed_count`: `0`
  - `created_at`: `2026-11-13T12:48:04.387196+00:00`

---

## 6. Android OS Channel & Permission Confirmation

- **Android Permission:** `android.permission.POST_NOTIFICATIONS: granted=true`
- **Channel ID:** `zev_notifications_channel`
- **Importance:** `Importance.max` (Enables sound, vibration, and heads-up banner display)
- **Accent Color:** `#00D4FF` (ZEV Cyan)
- **Small Icon:** `@drawable/ic_notification` (White silhouette conforming to Android Material guidelines)
- **Active Chat Suppression:** Confirmed. Entering `ChatConversationScreen` binds `activeChatConversationId` and `activeChatPeerId`, preventing disruptive in-app banners while reading messages in real-time.
