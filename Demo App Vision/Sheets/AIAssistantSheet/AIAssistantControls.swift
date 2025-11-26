import SwiftUI

struct MicToggleButton: View {
    @Binding var isListening: Bool
    
    var body: some View {
        Button(action: {
            isListening.toggle()
        }) {
            Label(
                isListening ? "Stop Listening" : "Start Listening",
                systemImage: isListening ? "stop.fill" : "mic.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

struct CloseSheetButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label("Close", systemImage: "xmark.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
