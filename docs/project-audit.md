# Project Audit & Backlog

_Last audited: 2026-10-11 (branch `app-store-compliance`). Current release
verification: 209 Swift tests (1 skipped live-network test) and an unsigned
generic-device Release archive are green with Xcode 27 against the visionOS 27
simulator. The 25 pipeline tests were last run on 2026-08-30._

This document records the **true state** of features that are partially shipped,
deferred, gated behind flags, or removed from the UI — and the prioritized
backlog of what remains. It exists because the feature list in the README
described intent rather than the wired-up reality; this is the source of truth
for "what's actually done vs. on the back burner."

Companion docs: [remote-catalog.md](remote-catalog.md) (asset pipeline → R2 →
loader) and [design-assistant.md](design-assistant.md) (on-device recommender +
Foundation Models layer).

---

## Feature flags

All gating lives in
[`AppFeatureFlags`](../Demo App Vision/Configuration/AppFeatureFlags.swift):

| Flag | Value | Effect |
| --- | --- | --- |
| `settingsScreenEnabled` | `true` | Settings tab appears in the nav ornament. Tab visibility is driven by `ScreenTab.enabledCases` in `StarterView`, so any screen can be dropped from the nav. |
| `measurementToolsEnabled` | `true` | Shows the ruler button in the bottom toolbar. (Graduated from Labs on 2026-06-26 — it is no longer gated by a per-user toggle.) |
| `sharePlayEnabled` | `false` | SharePlay is disabled. No toolbar button is rendered. |
| `aiAssistantEnabled` | `true` | Design Assistant (sparkles) button + sheet. |
| `remoteCatalogEnabled` | `true` | Catalog served from the R2 manifest; models download lazily. |

---

## Audited feature status

### ✅ Measurement Tools — complete, in the default toolbar

Fully implemented and wired end-to-end; **not** "in development." As of
2026-06-26 it is graduated out of Labs — the ruler button shows whenever
`measurementToolsEnabled` is true (the per-user `labsMeasurementToolsEnabled`
toggle was removed across the toolbar, `AppSettings`, Settings UI, backup format,
and tests).

- Engine: [`MeasurementManager`](../Packages/XRShareCollaboration/Sources/XRShareCollaboration/Measurement/MeasurementManager.swift)
  — object dimension overlays, object-to-object distance (closest-segment
  between bounds), a 3D virtual ruler, unit conversion (in/ft/cm/m), and live
  overlay refresh when unit/visibility changes.
- Wired in `CollaborativeSessionController`: owns the manager, sets the shared
  anchor, routes spatial taps (`handleSpatialTap`), and calls `syncScene` as the
  scene changes.
- UI: [`MeasurementView`](../Demo App Vision/Sheets/MeasurementSheet/MeasurementView.swift)
  drives every capability.
- Covered by `MeasurementTests` in the package suite.

**Remaining:** on-device verification of the spatial overlays/ruler.

### ✅ Model Import — complete for USDZ

Fully functional; **not** "in development."

- [`ImportModelView`](../Demo App Vision/Sheets/ImportModelSheet/ImportModelView.swift)
  validates type/size (150 MB cap), sanitizes and de-duplicates the name,
  rejects names colliding with built-ins, copies into `Documents/Imports/`, sets
  file protection, then calls `controller.refreshAvailableModels()` so the
  import shows up in the catalog immediately.

**Remaining:** OBJ/FBX support (currently USDZ-only — these would route through
the catalog pipeline's conversion path).

### 🟡 Focus Mode — neutral design space done; real-world removal not

- [`FocusModeManager`](../Packages/XRShareCollaboration/Sources/XRShareCollaboration/FocusMode/FocusModeManager.swift)
  builds a fully designed neutral room shell (floor/walls/ceiling, trim, cove
  glow, corner posts, light rails) with **4 themes** (Calm Studio, Warm Atelier,
  Bright Loft, Night Gallery), three-point lighting, head-anchored recentering,
  and resizable room dimensions.
- The shell **encloses** the viewer to replace the distracting environment — it
  does **not** selectively erase individual real-world furniture from
  passthrough (the toolbar's "hide/show real-world items" framing overstates
  this; true per-object passthrough filtering is not implemented and is hard to
  do reliably on visionOS).

**Remaining:** reconcile the UI copy with what the shell actually does; optional
real-scene occlusion work if selective hiding is ever pursued.

### 🔴 SharePlay — removed from the UI, code orphaned

- `sharePlayEnabled = false`; there is **no SharePlay button** in
  [`ToolbarOrnament`](../Demo App Vision/Ornaments/ToolbarOrnament.swift).
- [`SharePlaySheet`](../Demo App Vision/Sheets/SharePlaySheet/SharePlaySheet.swift)
  and [`SharePlayLauncher`](../Demo App Vision/SharePlayLauncher.swift) compile
  but are **not referenced anywhere** (dead code). The sheet's actions just
  `print("NOT YET IMPLEMENTED")`.
- The real peer-to-peer logic is commented out in
  `SharePlayCoordinator` (package networking layer).

**Decision (2026-07-05): keep as-is.** The orphaned UI and commented
coordinator stay in the repo as the starting point for future SharePlay work.
They are unreachable from the app, so there is no user-facing or App Review
impact — contributors should just know this code is intentionally dormant, not
wired in.

### ✅ Already shipped (for completeness)

Remote R2 catalog with lazy download + LRU caching, intent-aware catalog search,
the on-device Design Assistant (DesignAdvisor + optional Foundation Models),
designer color palettes, first-run onboarding, undo/redo, collision handling.

**Collision (updated 2026-07-01, `a4f955e`):** collision is now a single Labs
toggle in Settings, **off by default**. The toggle maps off ↔ `prevent`; the
`.warn` case still exists in `FurnitureCollisionMode` and legacy stored values
decode correctly, but it is no longer reachable from the UI (unknown/absent
stored values fall back to `.off`, covered by `AppSettingsTests`).

---

## Toolbar / navigation: what was removed

The README WISHLIST item "add removed screens back into workflow" refers to:

1. **SharePlay** — removed from the bottom toolbar entirely (see above).
2. **Measurement** — _was_ hidden behind the Labs toggle; **graduated into the
   default toolbar on 2026-06-26** and is now always available.
3. **Settings tab** — currently enabled, but the `ScreenTab.isEnabled` /
   `enabledCases` mechanism in `StarterView` exists specifically so tabs can be
   pulled from the nav ornament.

---

## Backlog

### Near-term (release-readiness)

- [x] **Info.plist privacy/usage strings audit** — done 2026-07-05, revised
  2026-08-30. `NSWorldSensingUsageDescription` is the only usage string the
  app needs, and it now describes the user benefit rather than plane
  detection. `NSHandsTrackingUsageDescription` was removed: nothing in the app
  or package instantiates a `HandTrackingProvider`, and Apple rejects strings
  for unused APIs. The duplicate `INFOPLIST_KEY_*` build settings are gone
  too — `GENERATE_INFOPLIST_FILE` is `NO`, so they never shipped anything, and
  [`DesignSphere-Info.plist`](../DesignSphere-Info.plist) is now the single
  source of truth. Two follow-ups came out of the original audit:
- [x] **Remove the unused `NSMainCameraUsageDescription`** — done 2026-07-05
  (removed from both the plist and the pbxproj). No code in the app or package
  touches camera APIs, and main-camera access on visionOS is an enterprise-only
  entitlement anyway.
- [x] **Remove the `com.apple.developer.arkit` entitlement key** — done
  2026-07-05. It is not a standard visionOS entitlement (ARKit data access is
  granted via the usage-description keys + runtime permission, not an
  entitlement), and an unrecognized entitlement can break device
  provisioning/signing. **Sanity-check the next device build** — if signing
  complains, this is the first thing to revisit.
- [ ] **On-device verification pass** — measurement overlays + ruler,
  world-anchor cross-room persistence, and the Foundation Models NL box.
  (The edit panel is no longer on this list: its invisibility was **not** a
  simulator limitation but a leftover 0.0012 points-to-meters scale factor
  from the `ViewAttachmentComponent` era that shrank the RealityView
  attachment — which arrives already sized in meters — to under a millimeter.
  Fixed 2026-07-05 and pinned by `EditMenuAttachmentTests`; it should now
  render in the simulator and on device alike.)
- [x] **Generic-device Release archive** — passed unsigned on July 26, 2026.
  The first archive attempt exposed that `DEVELOPMENT_ASSET_PATHS` pointed at
  the entire app source folder, which excluded root-level production Swift
  files from archive compilation. The invalid setting was removed from Debug
  and Release. Distribution signing, TestFlight upload, and device installation
  remain part of the on-device verification blocker.
- [x] **Resolve SharePlay** — decided 2026-07-05: keep the dormant code in the
  repo for future wiring (see above).
- [x] **Graduate Measurement out of Labs** — done 2026-06-26 (ruler now in the
  default toolbar; on-device verification still pending).
- [x] **Reconcile Focus Mode UI copy** with the enclosure behavior — done.
  The toolbar hint now reads "Opens focus mode options for a distraction-free
  design space", and the manager's status text no longer says "shared anchor",
  which was collaboration vocabulary for a session this build has no concept of.

- [x] **The catalog resolved models through an empty bundle** — found and
  fixed 2026-08-30. The app ships zero bundled `.usdz`, but `ModelType.allCases()`
  scanned `Bundle` and synthesised a `placeholder` entry when it found nothing,
  and several paths trusted it. Consequences, all user-visible: loading a saved
  project restored **no** models while alerting "loaded successfully"; the first
  eight catalog tiles showed a generic ARKit glyph; a manifest entry with no
  thumbnail spun forever; and a USDZ import reported success but never joined
  the catalog. See the 2.1 commit for the full accounting.
- [ ] **Apple HIG / guidelines conformance pass.** App Review readiness is now
  tracked item-by-item in [app-store-checklist.md](app-store-checklist.md)
  (repo-side items verified 2026-07-05; Connect-side work and license risks
  listed there).

- [x] **Release-readiness pass, 2026-10-11.**
  - A model whose hosted file fails its checksum now reads "Unavailable right
    now" with no Retry button, since retrying could only fail again. Server and
    network errors keep Retry.
  - Opening a `.dsbackup` file from Files, Mail or AirDrop now asks to restore
    it. The plist has declared DesignSphere the owner of that file type all
    along, but nothing handled the open, so the app launched and did nothing.
    `LSSupportsOpeningDocumentsInPlace = false` is declared to match: the app
    reads a copy and never edits the original.
  - Restoring a backup from Settings now refreshes the catalog, so restored
    imported models appear without a relaunch.
  - The catalog loads behind the app instead of in front of it. The launch
    overlay now clears as soon as the immersive space opens; the catalog
    screen shows its own spinner, which says it is still connecting after
    4 s. A cached manifest is used after at most 6 s instead of 20 s.
    Restoring a project waits for the catalog first, and the Design Assistant
    says the catalog is still loading instead of "no models for that room".
  - A tile whose download failed transiently shows "Retry in N min" with Retry
    disabled until the store's backoff ends, instead of a button that is
    silently refused.
  - SwiftLint is clean in strict mode on every file changed since `main`. CI's
    lint job had failed on every run since October 2025, so its build job had
    never run; that job also targeted a runner without the visionOS 26 SDK and
    resolved a root `Package.swift` that does not exist. Both are fixed. The
    lint config now allows conventional one-letter math names and the
    placement engines' long parameter lists and tuples; refactoring those is
    device-only work. 86 older violations remain in files untouched since
    `main`, which CI does not lint until they change.
  - Ambiguous `.none` matches on mesh classification are spelled out. No
    behavior changed. The remaining "switch must be exhaustive" warnings come
    from visionOS 27's new `.slanted` plane alignment; the app only requests
    horizontal and vertical planes, and `@unknown default` covers it safely.

### Medium-term

- [ ] Performance budget for 180+ streamed models — LOD, occlusion culling,
  progressive loading.
- [x] Cold-start-with-no-network UX — the "Catalog unavailable" view with a
  Retry exists, and 2026-08-30 fixed the paths that made it misbehave (a
  phantom "Placeholder" tile, a retry that skipped the loading state, and a
  dead-end fallback whose error nothing presented).
- [x] Accessibility — VoiceOver pass done 2026-08-30 across the editor,
  sheets, and settings; gaze targets raised to ~60pt; Reduce Motion honoured.
  High-contrast styling now reaches the immersive edit panel too: the contrast
  logic moved into a `HighContrastAdaptive` modifier applied per scene, because
  SwiftUI scenes do not inherit each other's environment. Alternative input is
  still untouched.
- [ ] OBJ/FBX import via the conversion pipeline.
- [x] Thumbnail fetching is bounded — cells load from `.task` with a 200 ms
  debounce, so a cell flicked past during a scroll is cancelled before it
  costs a request, and downloads are capped at 4 concurrent by
  `ThumbnailDownloadLimiter`.

### Known, deliberately not fixed

- **The nav ornament nests a `TabView` inside a manual `.ornament()`**, which
  duplicates a system affordance, and `ToolbarOrnament` declares a
  `bottomOrnament` toolbar while itself being hosted in another manual
  ornament. Works, but non-idiomatic; restructuring is unverifiable without
  hardware.

### Long-term (roadmap)

LiDAR furniture scanning, CloudKit cross-device sync, full SharePlay
collaboration, voice commands, multi-room projects, expanded materials library,
cross-platform (iPad/iPhone) preview. (See the README roadmap for the full list.)
