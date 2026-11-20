# ZEV — Remaining Security Risks & Operational Recommendations

**Date:** November 20, 2026  
**Auditor:** Application Security & DevSecOps Engineer (Antigravity)  
**Classification:** Internal Operational Security Runbook  

---

## 1. Executive Summary

Following the execution of the 27-check pre-launch security hardening program, zero critical or high-risk vulnerabilities remain in the ZEV codebase or database policies. 

This document identifies residual low-priority risks, external infrastructure dependencies, and operational recommendations to maintain this security baseline throughout post-launch operations.

---

## 2. Residual Risks & Infrastructure Dependencies

### 2.1 Cloudflare R2 Upload Expiry & Orphan Files
- **Risk Level:** **LOW**
- **Description:** Presigned upload URLs allow direct PUT requests to Cloudflare R2. If a user generates a presigned URL but cancels or abandons the upload before finalizing the database record, orphaned binary files may remain stored in the R2 bucket.
- **Mitigation & Recommendation:** Configure an automated Cloudflare R2 Lifecycle Rule to delete unreferenced media or purge temporary upload folders after 7 days if not associated with a published post, reel, or profile picture.

### 2.2 In-Memory Rate Limiting in Multi-Instance Deployments
- **Risk Level:** **LOW**
- **Description:** Rate limiting on Next.js API routes (`checkRateLimit`) uses an in-memory sliding window per server instance. In horizontal auto-scaling scenarios (e.g. multiple serverless edge instances or multiple container replicas), rate limits are evaluated per-instance rather than globally.
- **Mitigation & Recommendation:** For massive scale (e.g. >1,000 requests per second across multiple regional instances), migrate `checkRateLimit` backing storage to Upstash Redis or Supabase KV. The current in-memory limits are more than adequate for initial launch traffic.

### 2.3 Third-Party Webhook Secret Rotation
- **Risk Level:** **LOW**
- **Description:** Webhook endpoints (such as payments or push dispatchers) rely on secret tokens. If an administrative API key is rotated without simultaneously updating deployment secrets, webhook ingestion would temporarily fail.
- **Mitigation & Recommendation:** Maintain dual-secret grace periods during scheduled credential rotations.

### 2.4 Transitive DevDependency Advisory (`minimatch`)
- **Risk Level:** **LOW / INFORMATIONAL**
- **Description:** `npm audit` flagged a moderate ReDoS advisory in `minimatch` utilized transitively by `@typescript-eslint` within development toolchains.
- **Mitigation & Recommendation:** This package is executed exclusively during local build and typechecking phases and is never included in the production bundle. Upgrade `@typescript-eslint` when upstream releases a major version update.

---

## 3. Operational Security Runbook

1. **Regular Database Policy Audits:**  
   Periodically run `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND rowsecurity = false;` to guarantee any newly created tables immediately inherit Row Level Security.
2. **Admin Access Reviews:**  
   Audit records in `admin_audit_logs` weekly to detect unusual administrative activity or permission changes.
3. **Manual Verification Enforcement:**  
   Ensure human reviewers adhere strictly to the 10 Persian verification criteria before approving Blue or Gold badges in the ZEV Admin portal.
4. **Credential Rotation Schedule:**  
   Rotate Cloudflare R2 access tokens, Agora certificates, and Supabase service keys every 90 days.
