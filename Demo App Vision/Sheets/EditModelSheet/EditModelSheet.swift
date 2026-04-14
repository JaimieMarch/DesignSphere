import SwiftUI
import XRShareCollaboration

struct EditModelSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController
        
    var body: some View {
        EditModelView(controller: controller)
    }
}
