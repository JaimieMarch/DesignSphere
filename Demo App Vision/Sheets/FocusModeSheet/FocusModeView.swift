import SwiftUI
import XRShareCollaboration

struct FocusModeView: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    @State private var widthMeters: Double
    @State private var depthMeters: Double
    @State private var heightMeters: Double

    private let widthRange: ClosedRange<Double> = 4.0...10.0
    private let depthRange: ClosedRange<Double> = 4.0...10.0
    private let heightRange: ClosedRange<Double> = 2.5...5.0

    init(isPresented: Binding<Bool>, controller: CollaborativeSessionController) {
        self._isPresented = isPresented
        self.controller = controller
        let dims = controller.focusRoomDimensions
        self._widthMeters = State(initialValue: Double(dims.width))
        self._depthMeters = State(initialValue: Double(dims.depth))
        self._heightMeters = State(initialValue: Double(dims.height))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: controller.isFocusModeActive ? "eye.circle.fill" : "eye")
                        .font(.system(size: 60))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)

                    Text("Enter an immersive environment to focus on your design without distractions. Please note that focus mode is currently only a visual environment - your work will persist once you exit.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Safety notice
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("For the best possible experience and for your safety, avoid moving around while in focus mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Room Dimensions")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    dimensionSlider(
                        label: "Width",
                        subtitle: "Left to right span",
                        value: $widthMeters,
                        range: widthRange
                    )

                    dimensionSlider(
                        label: "Depth",
                        subtitle: "Front to back span",
                        value: $depthMeters,
                        range: depthRange
                    )

                    dimensionSlider(
                        label: "Height",
                        subtitle: "Floor to ceiling span",
                        value: $heightMeters,
                        range: heightRange
                    )
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if controller.isFocusModeActive {
                    Button(action: {
                        exitFocusMode()
                        isPresented = false
                    }) {
                        Label("Exit Focus Mode", systemImage: "arrow.left.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button(action: {
                        enterFocusMode()
                        isPresented = false
                    }) {
                        Label("Enter Focus Mode", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .frame(width: 500)
            .navigationTitle("Focus Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        .onChange(of: widthMeters) {
            pushDimensionChanges()
        }
        .onChange(of: depthMeters) {
            pushDimensionChanges()
        }
        .onChange(of: heightMeters) {
            pushDimensionChanges()
        }
        .onChange(of: controller.focusRoomDimensions) {
            let dims = controller.focusRoomDimensions
            widthMeters = Double(dims.width)
            depthMeters = Double(dims.depth)
            heightMeters = Double(dims.height)
        }
    }

    private func enterFocusMode() {
        controller.enterFocusMode()
    }

    private func exitFocusMode() {
        controller.exitFocusMode()
    }

    @ViewBuilder
    private func dimensionSlider(
        label: String,
        subtitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f") m")
                    .font(.headline)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }

    private func pushDimensionChanges() {
        controller.updateFocusRoomDimensions(
            width: Float(widthMeters),
            depth: Float(depthMeters),
            height: Float(heightMeters)
        )
    }
}
