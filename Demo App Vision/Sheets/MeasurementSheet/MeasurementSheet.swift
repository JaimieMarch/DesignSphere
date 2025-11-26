import SwiftUI

struct MeasurementSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        MeasurementView(isPresented: $isPresented)
            .padding(32)                       // match other sheets
            .frame(width: 600, height: 700)    // same size as EditModel/AIAssistant/Focus
    }
}
