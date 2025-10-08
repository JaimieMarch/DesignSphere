import SwiftUI
import GroupActivities
#if canImport(UIKit)
import UIKit
#endif
import XRShareCollaboration


/// To start the sessions
@available(visionOS 26.0, *)
struct SharePlayLauncher: View {
    @Binding var isActivating: Bool
    @Binding var errorMessage: String?
    var onPrepare: () -> Void
    @State private var showingShareSheet = false

    var body: some View {
        Button(action: activateSharePlay) {
            if isActivating {
                ProgressView()
            } else {
                Label("Start SharePlay", systemImage: "shareplay")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isActivating)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheetView()
        }
    }

    private func activateSharePlay() {
        errorMessage = nil
        onPrepare()
        isActivating = true
        showingShareSheet = true
        isActivating = false
    }
}

/// Show apple's shareplay menu (bottom of the window text to the move tab) 
#if canImport(UIKit)
@available(visionOS 26.0, *)
private struct ShareSheetView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GroupActivitySharingController {
        GroupActivitySharingController(preparationHandler: {
            DemoActivity()
        })
    }

    func updateUIViewController(_ controller: GroupActivitySharingController, context: Context) {}
}
#endif
