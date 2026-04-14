import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct MeasurementSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    var body: some View {
        MeasurementView(
            isPresented: $isPresented,
            measurementManager: controller.measurementManager,
            spawnRuler: {
                controller.measurementManager.spawnVirtualRuler(
                    deviceTransform: controller.worldTrackingDeviceTransform
                )
            }
        )
    }
}
