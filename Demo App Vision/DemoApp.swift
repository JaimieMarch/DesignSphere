//
//  App Entry
//

import SwiftUI
import XRShareCollaboration
import RealityKit

@available(visionOS 26.0, *)
@main
struct DemoApp: App {
    // Creates the primary controller for the app
    // Collaborative session controller is the brains
    @StateObject private var controller = CollaborativeSessionController()

    var body: some SwiftUI.Scene {
        // Is the 2D window group for the UI elements
        WindowGroup("StarterView") {
            StarterView(controller: controller)
            // Resizing is disabled intentionally to provide app-wide consistency 
                .frame(width: 1280, height: 720)
        }
        .windowResizability(.contentSize)
        
        // Is the 3D space (RealityKit's ImmersiveSpace) in which content goes.
        ImmersiveSpace(id: "CollaborativeSpace") {
            RealityView { content in
                controller.makeRealityContent(content, session: controller.immersiveSession)
            } update: { content in
                controller.updateRealityContent(content)
            }
        }
    }
}


