import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct MeasurementView: View {
    @Binding var isPresented: Bool
    @ObservedObject var measurementManager: MeasurementManager
    let spawnRuler: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "ruler")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.secondary)

                        Text("Measurement Tools")
                            .font(.title)
                            .bold()
                    }

                    VStack(spacing: 20) {
                        Picker("Unit", selection: Binding(
                            get: { measurementManager.unit },
                            set: { measurementManager.setUnit($0) }
                        )) {
                            ForEach(MeasurementManager.Unit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Measurement unit")

                        Toggle(
                            "Show Dimensions on Objects",
                            isOn: Binding(
                                get: { measurementManager.showDimensions },
                                set: { measurementManager.setShowDimensions($0) }
                            )
                        )
                        .padding(.vertical, 8)
                        .accessibilityLabel("Show dimensions on objects")
                        .accessibilityHint("Display size labels on placed models")

                        Button(action: spawnRuler) {
                            Label(
                                measurementManager.hasVirtualRuler ? "Replace Virtual Ruler" : "Spawn Virtual Ruler",
                                systemImage: "ruler"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if measurementManager.hasVirtualRuler {
                            Button(action: { measurementManager.clearVirtualRuler() }) {
                                Label("Clear Ruler", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        Button(action: { measurementManager.startDistanceMeasurement() }) {
                            Label("Measure Between Objects", systemImage: "arrow.left.and.right")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        if measurementManager.hasActiveDistanceMeasurement || measurementManager.isAwaitingSelection {
                            Button(action: clearOrCancelMeasurement) {
                                Label(
                                    measurementManager.isAwaitingSelection ? "Cancel Measurement" : "Clear Measurement",
                                    systemImage: "xmark"
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.headline)
                            Text(measurementManager.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: { isPresented = false }) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }

    private func clearOrCancelMeasurement() {
        if measurementManager.isAwaitingSelection {
            measurementManager.cancelDistanceSelection()
        } else {
            measurementManager.clearDistanceMeasurement()
        }
    }
}
