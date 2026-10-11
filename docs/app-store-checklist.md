# App Store Launch Checklist

_Last verified: 2026-10-11. Full audit evidence: [release-audit-2026-10-11.md](release-audit-2026-10-11.md). Repository fixes pass local verification; distribution and physical-device gates remain._

Status of DesignSphere against the App Review Guidelines, split into what is
**verified in this repo**, what must be done **in App Store Connect**, and the
**open risks** to resolve before submitting. Companion doc:
[project-audit.md](project-audit.md).

---

## ✅ Verified in the repo

| Item | Guideline | Status |
| --- | --- | --- |
| Privacy usage strings | 5.1.1 | `NSWorldSensingUsageDescription` only, rewritten in user-benefit terms. `NSHandsTrackingUsageDescription` was **removed** on 2026-08-30: no `HandTrackingProvider`/`HandAnchor` exists anywhere: the only providers are WorldTracking, PlaneDetection and RoomTracking, and manipulation runs on RealityKit entity gestures. Apple rejects strings for unused APIs. |
| Single source of truth for Info.plist | — | The 14 `INFOPLIST_KEY_*` build settings were deleted (2026-08-30). `GENERATE_INFOPLIST_FILE = NO`, so they shipped nothing while requiring hand-syncing; one had no plist counterpart and would have collided if anyone ever flipped that flag. `DesignSphere-Info.plist` is now authoritative. |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | 5.1 | Ships in the built `.app` (verified in the archive payload). Declares Cloudflare request metadata as non-linked, non-tracking **Other Diagnostic Data** for **App Functionality**, plus both required-reason APIs in use: UserDefaults (`CA92.1`) and file timestamps (`C617.1`). Audited both directions: every declared API is used, and no undeclared required-reason API is called. |
| Production privacy decision | 5.1 | Cloudflare may retain IP/request metadata, so "Data Not Collected" is not used. Exact Connect answers in `production-privacy-declaration.md`. |
| Export compliance | — | `ITSAppUsesNonExemptEncryption = false` (HTTPS-only, exempt). |
| App Transport Security | — | No `http://` anywhere; no ATS exceptions declared. Zero third-party SDKs: no analytics, crash reporter, or tracker. Nothing is ever uploaded (no POST/PUT/upload task exists). |
| App icon | 2.3.8 | Layered visionOS icon present (`AppIcon.solidimagestack`, 3 layers); present in the built `Assets.car`. |
| Bundle identity | — | `com.designsphere.app`, v1.0 (build 1). |
| Entitlements | 2.5.1 | Empty `<dict/>`, which is correct — nothing in this app needs an entitlement on visionOS. **Distribution identity and provisioning profile remain missing as of this audit.** |
| Generic Release archive | 2.1 / 2.5 | Passes unsigned for `generic/platform=visionOS`. Payload verified to contain the production Info.plist, privacy manifest, icon and executable. Distribution signing and upload remain open. |
| Asset licensing | 4.1 / 5.2 | Production catalog re-verified 2026-10-11; unproven editor photos replaced with original generated normal maps. Previously verified 2026-08-30 against `asset_provenance.json`: **182 assets, every one CC0 1.0** (66 Poly Haven across 19 author groups, 116 The Base Mesh), attribution not required, redistribution allowed. App icon is project-owned. No BlenderKit asset present. |
| Accurate in-app copy | 2.3 | Swept 2026-08-30. Removed claims of video tutorials, LiDAR "scans" filtering, "exact scale" measurement, "shared anchor" collaboration jargon, and "room scans" the app cannot produce. |
| Declared document type is handled | 2.1 | Fixed 2026-10-11. The plist claims ownership of `.dsbackup`; opening one now asks to restore it instead of launching to nothing. `LSSupportsOpeningDocumentsInPlace = false` is declared, which also clears the upload warning for document types without it. |
| CI verification | — | Local pipeline/package/app tests, strict lint, and the unsigned Release archive pass. The expanded GitHub Actions workflow still needs to run after the audit changes are committed and pushed; local results do not establish hosted CI success. |
| Accessibility | — | The editor's 24 unlabeled controls now carry labels derived from their real behaviour; gaze targets raised to ~60pt; per-row labels on destructive actions; header traits, announcements, and Reduce Motion support added. |

## 📋 To do in App Store Connect

- [ ] **Privacy policy URL** and **Support URL** — enter the two GitHub URLs
  listed under step 1 below. Both resolve as of 2026-10-11.
- [ ] **Privacy nutrition labels** — declare **Other Diagnostic Data**, used for
  **App Functionality**, **not linked to identity**, **not used for tracking**.
  Do not select "Data Not Collected"; that would contradict the shipped privacy
  manifest and the in-app policy screen.
- [ ] **Screenshots** — 1–10 images at exactly 3840 × 2160, **no alpha
  channel**. The audited visionOS Simulator captures at that size. Export JPEG
  directly with the recipe in `app-store-metadata.md`. Two JPEG captures are
  staged in `AppStore-Screenshots/`; finish the representative feature set.
- [ ] **Age rating questionnaire** (expect 4+).
- [ ] **App motion information** — required for visionOS. "No high motion" is
  now defensible: the full-window scale/blur tab transitions are gated behind
  Reduce Motion.
- [ ] **Review notes** — prepared in `app-store-metadata.md`.
- [ ] **Paid Apple Developer Program membership** and an App Store distribution
  certificate/profile for `com.designsphere.app`.

## ⚠️ The path to submission — what actually remains

### 1. Publish the policy and support pages — ✅ DONE 2026-10-11

Both URLs returned HTTP 200 during the October 11 audit and are linked in
Settings. Enter them in App Store Connect:

- <https://github.com/JaimieMarch/DesignSphere/blob/main/docs/privacy-policy.md>
- <https://github.com/JaimieMarch/DesignSphere/blob/main/docs/support.md>

GitHub Pages remains an optional hosting choice. The current public repository
URLs work without changing the app's links.

### 2. One session on a physical Vision Pro

Compliance-relevant, not just polish: 2.1 rejections mostly come from reviewers
hitting bugs, and the app has not run on hardware recently.

- [ ] **Signing/provisioning works.** The October 11 audit found one Apple
  Development identity, no distribution identity, and **zero installed
  provisioning profiles**. Sign in to the paid team and let Xcode create the
  required signing assets, then create a signed archive.
- [ ] **The four 2.1 fixes hold on device** — project save/restore actually
  restoring models, catalog thumbnails rendering, import appearing in the
  catalog, no tile spinning forever.
- [ ] **Measurement overlays + ruler** draw and respond to unit changes.
- [ ] **World-anchor persistence** — save in one room, reload in place.
- [ ] **Foundation Models NL box** appears and answers on-device.

### 3. Configure a production catalog domain (recommended before launch)

- [ ] Attach an existing owned domain or subdomain to the catalog's R2 bucket,
  or acquire a domain if needed. Cloudflare documents `r2.dev` as rate-limited
  and intended for development, rather than production. Once the custom domain
  works, update and verify the app and canary URLs before building the release.
  This is a reliability recommendation, not a separate Apple submission rule.
  See [Cloudflare's public-bucket guide](https://developers.cloudflare.com/r2/buckets/public-buckets/).

### Known-but-low-risk

- **HIG / design conformance (2.4 / 4.0):** inherently a live-device judgment
  call by Apple. The loading screen's opaque black slab was replaced with glass;
  remaining risk is low but unverifiable in advance.
- **Nav ornament architecture:** a `TabView` is nested inside a manual
  `.ornament()`, which duplicates a system affordance, and `ToolbarOrnament`
  declares a `bottomOrnament` toolbar while itself being hosted in another
  manual ornament. Working, but non-idiomatic. Left alone deliberately —
  restructuring is risky and unverifiable without hardware.
- **Dormant code:** the SharePlay UI/coordinator, `VideoTutorialLibraryView`,
  and `EditModelComponents`/`EditModelTabs` compile but are unreachable. No
  review exposure; see project-audit.md for the standing decision.
