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
                .environmentObject(appSettings)
                .environment(\.legibilityWeight, appSettings.highContrastTextEnabled ? .bold : nil)
                .contrast(appSettings.highContrastTextEnabled ? 1.15 : 1.0)
            /// Resizing is disabled intentionally.
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
        }
#endif
    }
}

