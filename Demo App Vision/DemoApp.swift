//
//  App Entry point
//

import SwiftUI
import XRShareCollaboration
#if os(visionOS)
import RealityKit
#endif

@available(visionOS 26.0, *)
@main
struct DemoApp: App {
    @StateObject private var controller = CollaborativeSessionController()

    var body: some SwiftUI.Scene {
        WindowGroup("StarterView") {
            StarterView(controller: controller)
        }
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 1200)
        
        
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


