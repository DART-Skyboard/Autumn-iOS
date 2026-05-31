# SURGICAL REPORT: iOS Deployment Workflow (No-Mac / Mobile-Only)

**Prepared by:** Jules (AI CI/CD Specialist)
**Status:** Optimization & Diagnostic Phase

## 1. Executive Summary
The goal is to enable a fully automated iOS build-and-deploy pipeline for the "Autumn" app using GitHub Actions, bypassing the requirement for a physical Mac. The current infrastructure uses **Tuist** for project generation and **Fastlane** for App Store Connect interaction.

---

## 2. Critical Observations & Fixes

### A. Code Signing (The "No-Mac" Hurdle)
**Issue:** iOS apps require valid Certificates and Provisioning Profiles. Usually, these are created on a Mac.
**Best Practice Fix:**
- Use **Fastlane Match** with a private "Certificates" repository. This acts as a cloud-based source of truth for signing identities.
- Since you are using the **App Store Connect API Key**, Fastlane can now generate these on-the-fly in the CI runner.
- **Action Taken:** Updated `Fastfile` to utilize the API Key for all authentication, which is more reliable than session-based Apple IDs.

### B. Project Generation (Tuist)
**Issue:** Tuist is excellent for maintaining a consistent project structure without checking in the `.xcodeproj`.
**Fix:** The CI now explicitly runs `tuist install` and `tuist generate`.
- **Recommendation:** Ensure all new files are added to `Project.swift` or follow the glob patterns (e.g., `Sources/**`).

### C. Secret Management
**Issue:** The workflow depends on several secrets that must be exactly right.
**Verification List:**
- `APP_STORE_CONNECT_API_KEY_CONTENT`: The full text of your `.p8` file.
- `APP_STORE_CONNECT_ISSUER_ID`: Found in App Store Connect > Users and Access > Integrations.
- `GH_PAT` or `Report-Diag`: A GitHub Personal Access Token with `repo` scope to allow the CI to write back failure reports.

### D. The "Surgical" Diagnostic Loop
**Feature:** If a build fails, the workflow now automatically commits the last 20 lines of the error log back to `reports/DIAGNOSTIC_REPORT.txt`.
**Benefit:** You can read the exact error on your phone via GitHub without needing to dig into the Actions log UI, which is often difficult to navigate on mobile.

---

## 3. Recommended "Surgical" Next Steps

1.  **Verify App Store Connect App Entry:** Ensure an app with Bundle ID `DART-Meadow-LLC.Autumn` exists in App Store Connect.
2.  **API Key Permissions:** The API key `P6Z72KS63T` must have **App Manager** or **Admin** access to create certificates and upload builds.
3.  **Cloud Signing Bootstrap:** If the build fails with "No profile found", we should add `get_certificates` and `get_provisioning_profile` to the `Fastfile` to force the CI to create them.

---

## 4. Automation Checklist
- [x] Tuist project generation (Cloud-ready).
- [x] Fastlane integration with API Key.
- [x] Automated failure reporting (Mobile-friendly).
- [ ] Successful TestFlight upload (Pending secret verification).

---

## 5. Pro-Tip for Mobile Users
To trigger a new build from your phone, you don't always need to change code. You can go to the **Actions** tab in GitHub, select the **Build & Deploy** workflow, and click **Run workflow**.

---
*End of Report*
