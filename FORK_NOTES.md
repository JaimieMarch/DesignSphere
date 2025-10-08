# Fork Notes

This fork restructures the original Demo App project into a visionOS-first starter with the collaboration engine packaged up for reuse.

## Package Overview

- `Packages/XRShareCollaboration` compiles the previous `Shared/` sources into a Swift package.
- Resources (USDZ assets) now live under `Demo App Vision/Resources/Models` and are discovered at runtime via the bundle helper.
- `CollaborativeSessionController` is the high-level entry point. It wraps `ARViewModel`, `ModelManager`, `SharePlayCoordinator`, and exposes published state plus RealityView hooks.
- Core networking, SharePlay messages, spatial alignment, and manipulation logic remain unchanged aside from access-control tweaks where required.

## App Surface

- Only the `Demo App Vision` target remains. The iOS app and the old multi-window visionOS UI were removed.
- `StarterView` is intentionally small: it preloads assets, offers Local Preview, launches SharePlay, and lists available models.
- Model catalogue, cache, and manager sources now live under `Demo App Vision/Models` so they can be edited directly from the app target while remaining shared with the package.
- `SharePlayLauncher` is a minimal button that activates `XRShareActivity` after the controller prepares the session.

## Extending the UI

- Observe `CollaborativeSessionController` to drive new surfaces (`isConnected`, `participantCount`, `availableModels`, `placedModelSummaries`).
- Call `controller.addModel(_:)`, `controller.removeAllModels()`, or `controller.resetScene()` from your own UI components.
- Use `controller.makeRealityContent(_:session:)` / `updateRealityContent(_:)` inside any `RealityView` to keep collaboration wiring intact.

## Build & Testing Tips

- Open `Demo App.xcodeproj` and build the `Demo App Vision` scheme.
- The project references the local package via a Swift Package dependency; no manual file lists are required.
- To add new USDZ assets, drop them into `Demo App Vision/Resources/Models` and rebuild so both the app and package pick them up.
- SharePlay still requires a real device + FaceTime account for end-to-end validation.

## Legacy UI Code

The previous visionOS windows, menus, and debug panels were removed to keep the starter approachable. Their logic still exists inside the package history if you need examples of more advanced flows.
