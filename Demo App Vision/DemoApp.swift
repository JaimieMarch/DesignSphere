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
            ContrastAwareRoot(controller: controller)
                .environmentObject(appSettings)
                .frame(width: 1280, height: 720)
        }
        .windowResizability(.contentSize)

#if os(visionOS)
        ImmersiveSpace(id: "CollaborativeSpace") {
            RealityView { content in
                controller.makeRealityContent(content, session: controller.immersiveSession)
            } update: { content in
                controller.updateRealityContent(content)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        controller.handleSpatialTap(on: value.entity)
                    }
            )
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
#endif
    }
}

/// Wrapper view that reads system contrast (unavailable at App level)
@available(visionOS 26.0, *)
private struct ContrastAwareRoot: View {
    @ObservedObject var controller: CollaborativeSessionController
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var useHighContrast: Bool {
        appSettings.highContrastTextEnabled || systemContrast == .increased
    }

    var body: some View {
        StarterView(controller: controller)
            .environment(\.legibilityWeight, useHighContrast ? .bold : nil)
            .contrast(useHighContrast ? 1.15 : 1.0)
    }
}
