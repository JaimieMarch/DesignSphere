// Application entry point for the XRShare demo app
// Initializes XRShare controller, sets up the main window
// Defines the immersive space on visionOS for RealityKit content

import SwiftUI
import XRShareCollaboration
#if os(visionOS)
import RealityKit
#endif

@available(visionOS 26.0, *)
@main
struct DemoApp: App {
    @StateObject private var controller = CollaborativeSessionController()
    @StateObject private var appSettings = AppSettings()

    var body: some SwiftUI.Scene {
        WindowGroup("StarterView") {
            StarterView(controller: controller)
                .modifier(HighContrastAdaptive())
                .modifier(BackupOpenHandler(controller: controller))
                .environmentObject(appSettings)
        }
        .defaultSize(width: 1280, height: 720)
        // `.contentSize` pins the window to its content, which leaves no way to
        // enlarge it to compensate for larger Dynamic Type.
        .windowResizability(.contentMinSize)

#if os(visionOS)
        ImmersiveSpace(id: "CollaborativeSpace") {
            let entityTap = SpatialTapGesture().targetedToAnyEntity()
            let backgroundTap = SpatialTapGesture()
            RealityView { content, attachments in
                controller.makeRealityContent(content, session: controller.immersiveSession)
                controller.syncEditMenuAttachment(attachments.entity(for: "model-edit-panel"))
            } update: { content, attachments in
                controller.syncEditMenuAttachment(attachments.entity(for: "model-edit-panel"))
                controller.updateRealityContent(content)
            } attachments: {
                if controller.expandedEditModelInstanceIDVar != nil {
                    Attachment(id: "model-edit-panel") {
                        // The immersive space is a separate scene, and scenes do
                        // not inherit one another's environment — without these
                        // two lines the user's high-contrast setting silently
                        // does nothing on the surface that needs it most.
                        EditModelView(controller: controller)
                            .frame(width: 380, height: 620)
                            .modifier(HighContrastAdaptive())
                            .environmentObject(appSettings)
                    }
                }
            }
            .gesture(
                entityTap.exclusively(before: backgroundTap)
                    .onEnded { value in
                        switch value {
                        case .first(let targetedValue):
                            controller.handleSpatialTap(on: targetedValue.entity)
                        case .second:
                            controller.handleEmptySpatialTap()
                        }
                    }
            )
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
#endif
    }

}

/// Applies the app's high-contrast affordances, honouring both the in-app
/// setting and the system's Increase Contrast switch.
///
/// This is a modifier rather than a wrapper view because it has to be applied
/// once per scene: system contrast is unreadable at `App` level, and SwiftUI
/// scenes do not inherit each other's environment.
@available(visionOS 26.0, *)
private struct HighContrastAdaptive: ViewModifier {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var useHighContrast: Bool {
        appSettings.highContrastTextEnabled || systemContrast == .increased
    }

    func body(content: Content) -> some View {
        content
            .environment(\.legibilityWeight, useHighContrast ? .bold : nil)
            .contrast(useHighContrast ? 1.15 : 1.0)
    }
}
