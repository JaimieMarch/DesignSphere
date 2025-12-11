import SwiftUI
import XRShareCollaboration

struct FocusModeSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController
    private let sheetSize = CGSize(width: 520, height: 820)

    var body: some View {
        FocusModeView(isPresented: $isPresented, controller: controller)
            .frame(width: sheetSize.width, height: sheetSize.height)
    }
}
