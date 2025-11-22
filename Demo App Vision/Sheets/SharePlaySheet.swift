import SwiftUI

struct SharePlaySheet: View {
    @Binding var isPresented: Bool
    @State private var sessionCode = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Text("SharePlay")
                .font(.title)
                .bold()
            
            Image(systemName: "person.2")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Collaborate with others in real-time")
                .font(.body)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                Button(action: { startSharePlay() }) {
                    Label("Start New Session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                HStack {
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
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 400)
    }
    
    private func startSharePlay() {
        print("Start SharePlay - NOT YET IMPLEMENTED")
    }
    
    private func joinSharePlay() {
        print("Join SharePlay with code: \(sessionCode) - NOT YET IMPLEMENTED")
    }
}
