import SwiftUI
import XRShareCollaboration

struct ImportModelSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    var body: some View {
        ImportModelView(isPresented: $isPresented, controller: controller)
    }
}
