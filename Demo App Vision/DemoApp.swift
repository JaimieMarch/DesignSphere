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
    // Added semantic search service
    @StateObject private var search = SemanticSearch()

    var body: some SwiftUI.Scene {
        WindowGroup("StarterView") {
            StarterView(controller: controller)
                // Added inject search into view hierarchy
                .environmentObject(search)
            /// RESIZING IS DISABLED
            /// ENABLING IT WILL LEAD TO THE ORNAMENT BREAKING
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
