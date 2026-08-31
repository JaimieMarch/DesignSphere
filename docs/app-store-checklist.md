# App Store Launch Checklist

_Last verified: 2026-08-30 (branch `app-store-compliance`)._

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
| Entitlements | 2.5.1 | Empty `<dict/>`, which is correct — nothing in this app needs an entitlement on visionOS. **Confirm signing on the next device build.** |
| Generic Release archive | 2.1 / 2.5 | Passes unsigned for `generic/platform=visionOS`. Payload verified to contain the production Info.plist, privacy manifest, icon and executable. Distribution signing and upload remain open. |
| Asset licensing | 4.1 / 5.2 | Independently re-verified 2026-08-30 against `asset_provenance.json`: **182 assets, every one CC0 1.0** (66 Poly Haven across 19 author groups, 116 The Base Mesh), attribution not required, redistribution allowed. App icon is project-owned. No BlenderKit asset present. |
| Accurate in-app copy | 2.3 | Swept 2026-08-30. Removed claims of video tutorials, LiDAR "scans" filtering, "exact scale" measurement, "shared anchor" collaboration jargon, and "room scans" the app cannot produce. |
| Accessibility | — | The editor's 24 unlabeled controls now carry labels derived from their real behaviour; gaze targets raised to ~60pt; per-row labels on destructive actions; header traits, announcements, and Reduce Motion support added. |

## 📋 To do in App Store Connect

- [ ] **Privacy policy URL** and **Support URL** — see the blocker below; the
  prepared URLs do not resolve yet.
- [ ] **Privacy nutrition labels** — declare **Other Diagnostic Data**, used for
  **App Functionality**, **not linked to identity**, **not used for tracking**.
  Do not select "Data Not Collected"; that would contradict the shipped privacy
  manifest and the in-app policy screen.
- [ ] **Screenshots** — 1–10 images at exactly 3840 × 2160, **no alpha
  channel**. The visionOS Simulator captures at exactly that size natively, so
  no resize or crop is needed — but it writes RGBA PNGs, which Apple rejects.
  Convert before uploading; the verified recipe is in `app-store-metadata.md`.
  Two converted captures are staged in `AppStore-Screenshots/` (untracked).
- [ ] **Age rating questionnaire** (expect 4+).
- [ ] **App motion information** — required for visionOS. "No high motion" is
  now defensible: the full-window scale/blur tab transitions are gated behind
  Reduce Motion.
- [ ] **Review notes** — prepared in `app-store-metadata.md`.
- [ ] **Paid Apple Developer Program membership** and an App Store distribution
  certificate/profile for `com.designsphere.app`.

## ⚠️ The path to submission — what actually remains

### 1. Publish the policy and support pages — BLOCKER

`docs/` exists only on this working branch. **`origin/main` has no `docs/`
directory at all**, so both prepared URLs currently 404:

- `https://github.com/JaimieMarch/DesignSphere/blob/main/docs/privacy-policy.md`
- `https://github.com/JaimieMarch/DesignSphere/blob/main/docs/support.md`

A Privacy Policy URL is a mandatory App Store Connect field and App Review does
open it. Two options, both free (the repository is public):

- **Merge this work to `main`.** The blob URLs above then resolve as-is, and the
  in-app "View Online" links in `AppInformationView` start working.
- **Enable GitHub Pages** (Settings → Pages → Deploy from a branch → `main`,
  folder `/docs`). `docs/_config.yml` and `docs/index.md` are already in place
  and exclude the internal engineering docs from the published site. URLs become
  `https://jaimiemarch.github.io/DesignSphere/privacy-policy.html` and
  `…/support.html`; update `AppInformationView.onlineURL` to match if you take
  this path.

Verify whichever you choose in a signed-out browser before entering it.

### 2. One session on a physical Vision Pro

Compliance-relevant, not just polish: 2.1 rejections mostly come from reviewers
hitting bugs, and the app has not run on hardware recently.

- [ ] **Signing/provisioning works.** The July 26 archive attempt found a valid
  local signing identity but **zero installed provisioning profiles**, and
  failed because none exists for `com.designsphere.app`. Sign in to the paid
  team and let Xcode create the profile, then rerun a signed archive.
- [ ] **The four 2.1 fixes hold on device** — project save/restore actually
  restoring models, catalog thumbnails rendering, import appearing in the
  catalog, no tile spinning forever.
- [ ] **Measurement overlays + ruler** draw and respond to unit changes.
- [ ] **World-anchor persistence** — save in one room, reload in place.
- [ ] **Foundation Models NL box** appears and answers on-device.

### 3. One DNS change (optional, costs money)

- [ ] Move the catalog off `pub-*.r2.dev` (Cloudflare's rate-limited dev
  endpoint) to a custom domain. Not a guideline violation, but throttling while
  a reviewer browses looks broken, and that *is* a 2.1 rejection. Deferred
  because a custom domain has to be bought; the throttling exposure is instead
  mitigated in code (see below).

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
