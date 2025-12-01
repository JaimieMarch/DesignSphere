import SwiftUI
import XRShareCollaboration

struct EditModelSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController
        
    var body: some View {
        EditModelView(controller: controller)
            .padding(32)
            .frame(width: 700, height: 850)
    }
}
