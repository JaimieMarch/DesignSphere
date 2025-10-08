# Demo App Vision Starter

This fork trims the project down to a visionOS‑only starter app backed by the original collaboration stack. The SharePlay, networking, model loading, and RealityKit logic now lives in the `XRShareCollaboration` Swift package so new teams can focus on UI while keeping the realtime backend intact.

## Highlights

- ✅ visionOS 1.0+ target (`Demo App Vision` scheme only)
- ✅ SharePlay collaboration preserved via `XRShareCollaboration` package
- ✅ Minimal SwiftUI shell (`StarterView`) with a clean entry point to extend
- ✅ `RealityView` immersive stage driven by the package’s `CollaborativeSessionController`
- ✅ Built-in USDZ samples; drop new assets under `Demo App Vision/Resources/Models`

## Getting Started

1. Open `Demo App.xcodeproj` in Xcode 16 or newer.
2. Select the `Demo App Vision` scheme and a visionOS simulator or device.
3. Run the app. Use **Local Preview** to pre-load assets and open the immersive stage.
4. Tap **Start SharePlay** to activate the packaged `XRShareActivity` and share the session with teammates.

## Project Layout

- `Packages/XRShareCollaboration`
  - `Core/`, `Networking/`, `Utilities/`, `UI/` — collaboration logic now compiled as a Swift package.
  - `Collaboration/CollaborativeSessionController.swift` — public façade that exposes high-level session APIs and RealityView hooks.
- `Demo App Vision/`
  - `Models/` — catalogue, caching, and management logic co-located with the app target (shared with the package via symlink).
  - `Resources/Models/` — sample USDZ assets discovered at runtime. Add more files here to surface new entries in the starter UI.
  - `DemoAppVision.swift` — app entry point wiring the controller into window + immersive scenes.
  - `StarterView.swift` — simplified menu for launching local/SharePlay sessions and spawning models.
  - `SharePlayLauncher.swift` — tiny helper to activate the packaged `XRShareActivity`.
  - `Assets.xcassets` + `Info.plist` + `.entitlements` — unchanged platform configuration.

## Working with the Package

- Import `XRShareCollaboration` and initialize `CollaborativeSessionController` to access SharePlay, model catalog, and stage management.
- Call `controller.preloadIfNeeded()` during launch to warm caches (`ModelCache`, `ThumbnailCache`, `ARViewModel.loadModels`).
- Use `controller.availableModels` (an array of descriptors) to build custom pickers, and `controller.addModel(_:)` to place items.
- The controller exposes `makeRealityContent(_:session:)` and `updateRealityContent(_:)` so you can plug it into any `RealityView`.

## Extending the Starter

- Add your own SwiftUI surfaces by observing `CollaborativeSessionController`’s published state (`isConnected`, `participantCount`, `placedModelSummaries`).
- To customise SharePlay flows, wrap or extend the provided `SharePlayLauncher` while continuing to call `XRShareActivity().activate()`.
- The original, more advanced UI code has been removed from the target but remains available inside the package should you need deeper examples.

## Requirements

- Xcode 16+
- visionOS 1.0+ (APIs use the 26.0 availability identifiers)
- iCloud / FaceTime account for SharePlay testing on device

Enjoy building on top of a clean visionOS surface with the full collaboration core just a package import away.
