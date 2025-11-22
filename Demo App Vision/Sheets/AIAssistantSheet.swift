import SwiftUI

struct AIAssistantSheet: View {
    @Binding var isPresented: Bool
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("AI Design Assistant")
                .font(.title)
                .bold()
            
            Image(systemName: "microphone")
                .font(.system(size: 60))
                .foregroundStyle(isListening ? .blue : .secondary)
                .symbolEffect(.variableColor.iterative, value: isListening)
            
            Text(isListening ? "Listening..." : "Tap to speak your design request")
                .font(.body)
                .foregroundStyle(.secondary)
            
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
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(width: 400, height: 350)
    }
}
