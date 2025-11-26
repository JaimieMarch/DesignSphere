import SwiftUI

struct SharePlaySheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        SharePlayView(isPresented: $isPresented)
            .padding(32)                       // consistent with others
            .frame(width: 600, height: 700)    // same size as EditModel, FocusMode, etc.
    }
}
