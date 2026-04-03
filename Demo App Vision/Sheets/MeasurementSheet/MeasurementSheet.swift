import SwiftUI

struct MeasurementSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        MeasurementView(isPresented: $isPresented)
    }
}
