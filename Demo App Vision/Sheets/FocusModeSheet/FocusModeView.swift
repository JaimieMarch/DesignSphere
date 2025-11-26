import SwiftUI

struct FocusModeView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Header section matching EditModelView / AIAssistantView style
            VStack(spacing: 16) {
                Image(systemName: "eye")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("Focus Mode")
                    .font(.title)
                    .bold()
                
                Text("Enter an immersive environment to focus on your design without distractions")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
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
            
            Button(action: { isPresented = false }) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 600, height: 700) // match other views
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
        .shadow(radius: 5)
        .padding()
    }
    
    private func enterFocusMode() {
        print("Focus Mode - NOT YET IMPLEMENTED")
        // later: hook into your actual focus-mode logic / controller
    }
}
