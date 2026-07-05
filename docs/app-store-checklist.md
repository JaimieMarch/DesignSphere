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

## ⚠️ Open risks to resolve before submitting

1. **Model asset licenses (guidelines 4.1 / 5.2 — IP).** The app
   *redistributes* 180+ models to users from R2. Poly Haven and The Base Mesh
   are CC0 (fine). **BlenderKit assets need a per-asset license check** —
   BlenderKit's royalty-free license generally covers use *inside* a rendered
   product, not redistribution of the asset files themselves. This is the
   biggest legal/review exposure in the project. Audit `catalog.json` sources
   and drop or replace anything not clearly redistributable.
2. **`pub-*.r2.dev` catalog URL.** The r2.dev development URL is rate-limited
   by Cloudflare and not intended for production traffic. Put the bucket
   behind a custom domain before launch (`AppFeatureFlags.remoteCatalogBaseURL`).
3. **First-launch-offline UX (2.1 completeness).** With no network and no
   cached catalog the browse screen is empty. Reviewers test on real networks
   so this is unlikely to block, but a friendly "connect to load the catalog"
   state is cheap insurance (tracked in project-audit backlog).
4. **On-device verification pass** — measurement overlays/ruler, world-anchor
   persistence, Foundation Models NL box, and a sanity check of the edit panel
   (its invisibility was a scale bug, fixed + regression-tested 2026-07-05).
5. **Paid Apple Developer Program membership** and App Store distribution
   certificate/profile for `com.designsphere.app`.
