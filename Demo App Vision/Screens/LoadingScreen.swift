import SwiftUI

struct LoadingScreen: View {
    @Binding var isLoading: Bool
    @Binding var loadingProgress: Float
    @Binding var loadingMessage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Glass over passthrough — a visionOS window should never paint an
            // opaque slab over the user's room.
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // App Icon or Logo
                Image(systemName: "cube.transparent")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

                // App Name
                Text("DesignSphere")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)

                // Progress Section
                VStack(spacing: 16) {
                    // Progress Bar
                    ProgressView(value: loadingProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                        .tint(.blue)

                    // Percentage
                    Text("\(Int(loadingProgress * 100))%")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.primary)

                    // Loading Message
                    Text(loadingMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 300)
                }
                .padding(.top, 20)
            }
        }
        .opacity(isLoading ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isLoading)
        // A zero-opacity view still takes hits and still shows up in the
        // accessibility tree, so an unconditionally mounted overlay would
        // swallow taps on the whole window for the rest of the session.
        .allowsHitTesting(isLoading)
        .accessibilityHidden(!isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading DesignSphere, \(Int(loadingProgress * 100)) percent, \(loadingMessage)")
    }
}

#Preview {
    LoadingScreen(
        isLoading: .constant(true),
        loadingProgress: .constant(0.6),
        loadingMessage: .constant("Loading models...")
    )
}
