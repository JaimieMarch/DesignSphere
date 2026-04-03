import SwiftUI
import XRShareCollaboration

struct FocusModeSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    var body: some View {
        FocusModeView(isPresented: $isPresented, controller: controller)
    }
}
