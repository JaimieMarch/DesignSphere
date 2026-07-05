# Project Audit & Backlog

_Last audited: 2026-07-05 (branch `refactoring`). Full deterministic test
suite (`Tools/run-tests.sh`) green as of this date: 21 pipeline tests, 131
package tests (1 skipped live-network test), and the app-target suite._

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

- [x] **Info.plist privacy/usage strings audit** — done 2026-07-05. The
  required strings are present: `NSWorldSensingUsageDescription` and
  `NSHandsTrackingUsageDescription` exist in both
  [`DesignSphere-Info.plist`](../DesignSphere-Info.plist) and the
  `INFOPLIST_KEY_*` build settings in the pbxproj (the two copies are
  duplicated — keep them in sync). Two follow-ups came out of the audit:
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
- [x] **Resolve SharePlay** — decided 2026-07-05: keep the dormant code in the
  repo for future wiring (see above).
- [x] **Graduate Measurement out of Labs** — done 2026-06-26 (ruler now in the
  default toolbar; on-device verification still pending).
- [ ] **Reconcile Focus Mode UI copy** with the enclosure behavior. As of
  2026-07-05 the remaining offender is the toolbar accessibility hint
  ("Opens focus mode options to hide or show real-world items" in
  `ToolbarOrnament.swift`); the sheet and tutorial copy are already accurate.
- [ ] **Apple HIG / guidelines conformance pass.** App Review readiness is now
  tracked item-by-item in [app-store-checklist.md](app-store-checklist.md)
  (repo-side items verified 2026-07-05; Connect-side work and license risks
  listed there).

### Medium-term

- [ ] Performance budget for 180+ streamed models — LOD, occlusion culling,
  progressive loading.
- [ ] Cold-start-with-no-network UX (no cached catalog at all).
- [ ] Accessibility — VoiceOver pass, high-contrast, alternative input.
- [ ] OBJ/FBX import via the conversion pipeline.

### Long-term (roadmap)

LiDAR furniture scanning, CloudKit cross-device sync, full SharePlay
collaboration, voice commands, multi-room projects, expanded materials library,
cross-platform (iPad/iPhone) preview. (See the README roadmap for the full list.)
