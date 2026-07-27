# App Store Launch Checklist

_Last verified: 2026-07-26 (branch `refactoring`)._

Status of DesignSphere against the App Review Guidelines, split into what is
**verified in this repo**, what must be done **in App Store Connect**, and the
**open risks** to resolve before submitting. Companion doc:
[project-audit.md](project-audit.md).

---

## ✅ Verified in the repo

| Item | Guideline | Status |
| --- | --- | --- |
| Privacy usage strings (`NSWorldSensingUsageDescription`, `NSHandsTrackingUsageDescription`) | 5.1.1 | Present in `DesignSphere-Info.plist` and pbxproj `INFOPLIST_KEY_*` (keep the two in sync). Unused camera string removed 2026-07-05. |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | 5.1 | Ships automatically (synchronized folder). Declares Cloudflare network/request metadata conservatively as non-linked, non-tracking **Other Diagnostic Data** used for **App Functionality**, plus both required-reason APIs in use: UserDefaults (`CA92.1`) and file timestamps (`C617.1`). |
| Production privacy decision | 5.1 | Cloudflare may retain IP/request metadata, so “Data Not Collected” is not used. The exact App Store Connect answers and evidence are recorded in `production-privacy-declaration.md`. |
| Export compliance | — | `ITSAppUsesNonExemptEncryption = false` (HTTPS-only, exempt). Added 2026-07-05 so submissions skip the per-build encryption questionnaire. |
| App Transport Security | — | No `http://` URLs anywhere; catalog is HTTPS (Cloudflare R2). No ATS exceptions declared. |
| App icon | 2.3.8 | Layered visionOS icon present (`AppIcon.solidimagestack`, 3 layers). |
| Bundle identity | — | `com.designsphere.app`, v1.0 (build 1), category `public.app-category.lifestyle`. |
| Entitlements | 2.5.1 | Cleaned 2026-07-05 (non-standard `com.apple.developer.arkit` key removed). **Confirm signing on the next device build.** |
| Generic Release archive | 2.1 / 2.5 | Passed July 26, 2026 after removing the source folder from `DEVELOPMENT_ASSET_PATHS`. The unsigned arm64 archive contains the production Info.plist, privacy manifest, icon/assets, and executable. Distribution signing and upload remain open. |
| No dead user-facing UI | 2.1 | SharePlay is fully removed from the UI (orphaned source files remain in the repo but are unreachable). |
| Accessibility labels/hints | — | Toolbar, settings, and edit panel carry labels + hints; high-contrast mode supported. |
| App Store metadata packet | 2.3 | Product copy, privacy/age-rating answers, required visionOS motion answer, screenshot plan, and review notes are prepared in `app-store-metadata.md`. Account-specific fields remain open. |

## 📋 To do in App Store Connect

- [ ] **Privacy policy URL** — required even though the app collects no data.
- [ ] **Privacy nutrition labels** — declare **Other Diagnostic Data**, used for
  **App Functionality**, **not linked to identity**, and **not used for
  tracking**. Do not select “Data Not Collected.”
- [ ] **Support URL** and marketing description. Copy is prepared in
  `app-store-metadata.md`; do **not** promise SharePlay, LiDAR scanning, or voice
  commands (they are roadmap items; see project-audit.md).
- [ ] **Screenshots** — capture and upload 1–10 images at exactly 3840 × 2160
  with no alpha channel. Apple permits accurate Simulator captures that are
  resized/cropped correctly, while recommending Developer Capture on device.
- [ ] **Age rating questionnaire** (expect 4+).
- [ ] **App motion information** — required for visionOS; the prepared answer is
  No high motion, subject to confirmation during the device pass.
- [ ] **Review notes** — mention that the catalog streams from Cloudflare R2,
  so first launch needs network; models download on placement. Copy is prepared
  in `app-store-metadata.md`.

## ⚠️ The path to submission — what actually remains

Everything statically checkable in the repo is done (see the table above).
These four blocks are what stand between the current state and a confident
submission, **ordered by risk**:

### 1. Asset license audit — completed July 26, 2026 (4.1 / 5.2)

- [x] All 182 production models map to a CC0 Poly Haven or The Base Mesh record;
  generated thumbnails, embedded textures, and app-icon ownership are covered.
  No BlenderKit asset is present. See `asset-license-audit.md`.

### 2. One session on a physical Vision Pro

Compliance-relevant, not just polish: guideline 2.1 rejections mostly come
from reviewers hitting bugs, and the app hasn't been run on hardware recently.
One device session covers all of it:

- [x] **Generic-device Release compilation and archive contents** — verified
  locally with signing disabled on July 26, 2026. This found and fixed a target
  setting that had incorrectly marked the whole source folder as Development
  Assets. It does not validate certificates, provisioning, or installation.
- [ ] **Signing/provisioning still works** after the non-standard
  `com.apple.developer.arkit` entitlement was removed (2026-07-05). The July 26
  archive attempt found one valid local signing identity but zero installed
  provisioning profiles and failed specifically because no profile exists for
  `com.designsphere.app`. Sign in to the correct paid team and let Xcode create
  or install the profile, then rerun the signed archive.
- [ ] **Edit panel renders** — its invisibility was a scale bug (fixed +
  regression-tested 2026-07-05), but only verified in the simulator so far.
- [ ] **Measurement overlays + ruler** draw and respond to unit changes.
- [ ] **World-anchor persistence** — save in one room, reload in place.
- [ ] **Foundation Models NL box** appears and answers on-device (requires
  Apple Intelligence hardware; invisible in the simulator).

### 3. One DNS change

- [ ] Move the catalog off `pub-*.r2.dev` (Cloudflare's rate-limited dev
  endpoint) to a custom domain (`AppFeatureFlags.remoteCatalogBaseURL`). Not a
  guideline violation per se — but if the endpoint throttles while a reviewer
  browses the catalog, the app looks broken and that _is_ a 2.1 rejection.

### 4. App Store Connect form-filling (~an hour, all mandatory)

The "To do in App Store Connect" section above: privacy policy URL, the prepared
Other Diagnostic Data label, support URL, compliant screenshots, age rating,
app-motion answer, honest description, review notes. Plus:

- [ ] **Paid Apple Developer Program membership** and an App Store
  distribution certificate/profile for `com.designsphere.app`.

### Known-but-low-risk (won't block, worth knowing)

- **First-launch-offline UX (2.1):** with no network and no cached catalog the
  browse screen is empty. Reviewers test on real networks, so this is unlikely
  to block; a friendly "connect to load the catalog" state is cheap insurance
  (tracked in the project-audit backlog).
- **HIG / design conformance (2.4 / 4.0):** inherently a live-device judgment
  call by Apple; the UI follows visionOS conventions, so treat as low risk but
  unverifiable in advance.
