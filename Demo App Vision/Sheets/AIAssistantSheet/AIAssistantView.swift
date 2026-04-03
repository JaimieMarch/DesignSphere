import SwiftUI

struct AIAssistantView: View {
    @Binding var isPresented: Bool
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "microphone")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(isListening ? .blue : .secondary)
                    .symbolEffect(.variableColor.iterative, value: isListening)
                
                Text("AI Design Assistant")
                    .font(.title)
                    .bold()
                
                Text(isListening ? "Listening..." : "Tap to speak your design request")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
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
}
