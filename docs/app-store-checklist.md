# App Store Launch Checklist

_Last verified: 2026-07-05 (branch `refactoring`)._

Status of DesignSphere against the App Review Guidelines, split into what is
**verified in this repo**, what must be done **in App Store Connect**, and the
**open risks** to resolve before submitting. Companion doc:
[project-audit.md](project-audit.md).

---

## ✅ Verified in the repo

| Item | Guideline | Status |
| --- | --- | --- |
| Privacy usage strings (`NSWorldSensingUsageDescription`, `NSHandsTrackingUsageDescription`) | 5.1.1 | Present in `DesignSphere-Info.plist` and pbxproj `INFOPLIST_KEY_*` (keep the two in sync). Unused camera string removed 2026-07-05. |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | 5.1 | Ships automatically (synchronized folder). Declares no tracking, no data collection, and both required-reason APIs in use: UserDefaults (`CA92.1`) and file timestamps (`C617.1`, added 2026-07-05 — the LRU model cache and project listing read modification dates). |
| Export compliance | — | `ITSAppUsesNonExemptEncryption = false` (HTTPS-only, exempt). Added 2026-07-05 so submissions skip the per-build encryption questionnaire. |
| App Transport Security | — | No `http://` URLs anywhere; catalog is HTTPS (Cloudflare R2). No ATS exceptions declared. |
| App icon | 2.3.8 | Layered visionOS icon present (`AppIcon.solidimagestack`, 3 layers). |
| Bundle identity | — | `com.designsphere.app`, v1.0 (build 1), category `public.app-category.lifestyle`. |
| Entitlements | 2.5.1 | Cleaned 2026-07-05 (non-standard `com.apple.developer.arkit` key removed). **Confirm signing on the next device build.** |
| No dead user-facing UI | 2.1 | SharePlay is fully removed from the UI (orphaned source files remain in the repo but are unreachable). |
| Accessibility labels/hints | — | Toolbar, settings, and edit panel carry labels + hints; high-contrast mode supported. |

## 📋 To do in App Store Connect

- [ ] **Privacy policy URL** — required even though the app collects no data.
- [ ] **Privacy nutrition labels** — declare **"Data Not Collected"** (matches
  the manifest: no collection, no tracking).
- [ ] **Support URL** and marketing description. The description must match
  wired-up reality — do **not** promise SharePlay, LiDAR scanning, or voice
  commands (they are roadmap items; see project-audit.md).
- [ ] **Screenshots** — must be captured on Apple Vision Pro (device
  screenshots, not simulator composites, per 2.3.3).
- [ ] **Age rating questionnaire** (expect 4+).
- [ ] **Review notes** — mention that the catalog streams from Cloudflare R2,
  so first launch needs network; models download on placement.

## ⚠️ The path to submission — what actually remains

Everything statically checkable in the repo is done (see the table above).
These four blocks are what stand between the current state and a confident
submission, **ordered by risk**:

### 1. Asset license audit — the one real legal/rejection risk (4.1 / 5.2)

- [ ] The app _redistributes_ 180+ models to users from R2. Poly Haven and
  The Base Mesh are CC0 (fine). **BlenderKit assets need a per-asset license
  check** — BlenderKit's royalty-free license generally covers use _inside_ a
  rendered product, not redistribution of the asset files themselves. Audit
  `catalog.json` sources and drop or replace anything not clearly
  redistributable.

### 2. One session on a physical Vision Pro

Compliance-relevant, not just polish: guideline 2.1 rejections mostly come
from reviewers hitting bugs, and the app hasn't been run on hardware recently.
One device session covers all of it:

- [ ] **Signing/provisioning still works** after the non-standard
  `com.apple.developer.arkit` entitlement was removed (2026-07-05). If the
  build won't sign, reverting that one-line entitlement change is the fix.
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

The "To do in App Store Connect" section above: privacy policy URL,
"Data Not Collected" labels, support URL, device-captured screenshots, age
rating, honest description, review notes. Plus:

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
