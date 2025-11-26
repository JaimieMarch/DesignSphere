import SwiftUI

struct FocusModeSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        FocusModeView(isPresented: $isPresented)
            .padding(32)                       // match EditModelSheet
            .frame(width: 600, height: 700)    // same size as other sheet
    }
}
