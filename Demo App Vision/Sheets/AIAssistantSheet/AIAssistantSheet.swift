import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct AIAssistantSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    var body: some View {
        AIAssistantView(controller: controller, isPresented: $isPresented)
            .frame(width: 620, height: 720)
    }
}
