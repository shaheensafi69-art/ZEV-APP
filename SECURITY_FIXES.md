# ZEV — Security Fixes Log

**Date:** November 20, 2026  
**Auditor:** Application Security & DevSecOps Engineer (Antigravity)  
**Scope:** Remediation of vulnerabilities identified in Pre-Launch Audit  

---

## Index of Implemented Fixes

1. [FIX-01: User Verifications Table Hardening & Default Alteration](#fix-01-user-verifications-table-hardening--default-alteration)
2. [FIX-02: User Verifications Trigger Protection Against Privilege Escalation](#fix-02-user-verifications-trigger-protection-against-privilege-escalation)
3. [FIX-03: Row-Level Security Policies for Verification Requests](#fix-03-row-level-security-policies-for-verification-requests)
4. [FIX-04: Profiles Privilege Escalation Trigger (`badge_tier` Protection)](#fix-04-profiles-privilege-escalation-trigger-badge_tier-protection)
5. [FIX-05: Strict CORS Middleware & Preflight (OPTIONS) Handler in `zev-web`](#fix-05-strict-cors-middleware--preflight-options-handler-in-zev-web)
6. [FIX-06: Production Security Response Headers in `zev-web`](#fix-06-production-security-response-headers-in-zev-web)
7. [FIX-07: Production Security Response Headers in `zev_admin`](#fix-07-production-security-response-headers-in-zev_admin)
8. [FIX-08: Flutter Client Verification Portal Realignment (10 Persian Conditions)](#fix-08-flutter-client-verification-portal-realignment-10-persian-conditions)

---

### FIX-01: User Verifications Table Hardening & Default Alteration
- **Component:** Supabase PostgreSQL (`public.user_verifications`)
- **Vulnerability:** Previously, `status` defaulted to `'verified'` and `is_active` defaulted to `true`. An unrestricted insert could have granted automatic verification.
- **Action Taken:** Executed schema migration altering column defaults to secure states:
  ```sql
  ALTER TABLE public.user_verifications 
    ALTER COLUMN status SET DEFAULT 'pending',
    ALTER COLUMN is_active SET DEFAULT false;
  ```
- **Verification:** Verified via `information_schema.columns`.

---

### FIX-02: User Verifications Trigger Protection Against Privilege Escalation
- **Component:** Supabase PostgreSQL Trigger Function
- **Action Taken:** Created `protect_user_verifications_privileged_columns` function and trigger:
  ```sql
  CREATE OR REPLACE FUNCTION public.protect_user_verifications_privileged_columns()
  RETURNS trigger AS $$
  BEGIN
    IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
       OR COALESCE(auth.role(), '') = 'service_role'
       OR public.is_app_admin() THEN
      RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
      IF NEW.user_id != auth.uid() THEN
        RAISE EXCEPTION 'Cannot submit verification for another user' USING ERRCODE = '42501';
      END IF;
      IF NEW.status != 'pending' OR NEW.is_active = true THEN
        RAISE EXCEPTION 'New verifications must be pending and inactive' USING ERRCODE = '42501';
      END IF;
    ELSIF TG_OP = 'UPDATE' THEN
      IF OLD.user_id != auth.uid() OR NEW.user_id != OLD.user_id THEN
        RAISE EXCEPTION 'Cannot modify other user verification' USING ERRCODE = '42501';
      END IF;
      IF NEW.status IS DISTINCT FROM OLD.status
         OR NEW.is_active IS DISTINCT FROM OLD.is_active
         OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
         OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
        RAISE EXCEPTION 'Insufficient privileges to approve verification' USING ERRCODE = '42501';
      END IF;
    END IF;

    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER;
  ```
- **Verification:** Attached BEFORE INSERT OR UPDATE trigger `trg_protect_user_verifications`.

---

### FIX-03: Row-Level Security Policies for Verification Requests
- **Component:** Supabase PostgreSQL RLS
- **Action Taken:** Implemented explicit RLS policies on `public.user_verifications`:
  - `Users can insert own pending verification`:
    `FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending' AND is_active = false)`
  - `Users can update own pending verification`:
    `FOR UPDATE TO authenticated USING (auth.uid() = user_id AND status = 'pending') WITH CHECK (auth.uid() = user_id AND status = 'pending' AND is_active = false)`
  - `Admins full access on user_verifications`:
    `FOR ALL TO authenticated USING (public.is_app_admin()) WITH CHECK (public.is_app_admin())`

---

### FIX-04: Profiles Privilege Escalation Trigger (`badge_tier` Protection)
- **Component:** Supabase PostgreSQL (`public.profiles`)
- **Action Taken:** Added `NEW.badge_tier IS DISTINCT FROM OLD.badge_tier` to the list of protected columns in `protect_profile_privileged_columns()`. Non-admins attempting to set their badge tier to `'blue'` or `'gold'` are rejected with exception `42501`.

---

### FIX-05: Strict CORS Middleware & Preflight (OPTIONS) Handler in `zev-web`
- **Component:** `zev-web/src/middleware.ts`
- **Issue:** Cross-origin requests from `web.zevapp.com` to `/api/v1/ads/campaigns` failed because static wildcard `Access-Control-Allow-Origin: *` conflicted with client credentials (`withCredentials: true`), causing the browser to abort.
- **Action Taken:**
  - Added strict origin allowlist (`zevapp.com`, `web.zevapp.com`, `adminportal.zevapp.com`, `localhost:*`, `127.0.0.1:*`).
  - Added instant `OPTIONS` preflight interceptor returning `204 No Content` with validated `Access-Control-Allow-Origin: <exact origin>`, `Access-Control-Allow-Credentials: true`, and all necessary request headers.
  - Adjusted matcher in `middleware.ts` to allow API requests to be processed by CORS filter.

---

### FIX-06: Production Security Response Headers in `zev-web`
- **Component:** `zev-web/next.config.mjs`
- **Action Taken:** Replaced open wildcard headers with standard production security response headers:
  ```javascript
  const securityHeaders = [
    { key: 'X-DNS-Prefetch-Control', value: 'on' },
    { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
    { key: 'X-XSS-Protection', value: '1; mode=block' },
    { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
    { key: 'X-Content-Type-Options', value: 'nosniff' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
    { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  ];
  ```

---

### FIX-07: Production Security Response Headers in `zev_admin`
- **Component:** `zev_admin/next.config.ts`
- **Action Taken:** Added security response headers including `X-Frame-Options: DENY`, `Strict-Transport-Security`, `Content-Security-Policy`, and `nosniff`.

---

### FIX-08: Flutter Client Verification Portal Realignment (10 Persian Conditions)
- **Component:** `zev-app/lib/features/profile/screens/zev_blue_verification_screen.dart`
- **Action Taken:** Replaced commercial/subscription messaging with the exact 10 Persian verification requirements:
  1. Minimum 500,000 real followers
  2. Official identity verification
  3. Public recognition and notoriety
  4. Active and continuous activity
  5. Content quality and professional standards
  6. Strict legal and ethical compliance
  7. Two-Factor Authentication (2FA) active
  8. Account stability (minimum 6 months old, complete profile)
  9. Non-commercial authenticity
  10. Strict adherence to ZEV Community Guidelines
  - Added non-negotiable policy banner (non-purchasable, no bypass).
  - Added Gold tier requirement (1M+ followers + Blue prerequisite).
  - Form persists verification requests to `user_verifications` with `status = 'pending'`.
