import SwiftUI

struct SharePlayView: View {
    @Binding var isPresented: Bool
    @State private var sessionCode = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Header section matching all other sheets
            VStack(spacing: 16) {
                Image(systemName: "person.2")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("SharePlay")
                    .font(.title)
                    .bold()
                
                Text("Collaborate with others in real-time")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                Button(action: { startSharePlay() }) {
                    Label("Start New Session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                HStack(spacing: 12) {
                    TextField("Session Code", text: $sessionCode)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Join") {
                        joinSharePlay()
                    }
                    .buttonStyle(.bordered)
                    .disabled(sessionCode.isEmpty)
                }
            }
            
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
        .frame(width: 600, height: 700)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
        .shadow(radius: 5)
        .padding()
    }
    
    private func startSharePlay() {
        print("Start SharePlay - NOT YET IMPLEMENTED")
    }
    
    private func joinSharePlay() {
        print("Join SharePlay with code: \(sessionCode) - NOT YET IMPLEMENTED")
    }
}
