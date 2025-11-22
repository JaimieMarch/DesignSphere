import SwiftUI

struct FocusModeSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Focus Mode")
                .font(.title)
                .bold()
            
            Image(systemName: "eye")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Enter an immersive environment to focus on your design without distractions")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button(action: {
                enterFocusMode()
                isPresented = false
            }) {
                Label("Enter Focus Mode", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 350)
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
    }
}
