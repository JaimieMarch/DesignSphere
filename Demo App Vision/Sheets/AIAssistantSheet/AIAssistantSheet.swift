import SwiftUI

struct AIAssistantSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        AIAssistantView(isPresented: $isPresented)
            .padding(32)                
            .frame(width: 600, height: 700)
    }
}
