import SwiftUI

struct LoadingScreen: View {
    @Binding var isLoading: Bool
    @Binding var loadingProgress: Float
    @Binding var loadingMessage: String

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // App Icon or Logo
                Image(systemName: "cube.transparent")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)

                // App Name
                Text("DesignSphere")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

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
                        .foregroundStyle(.white.opacity(0.8))

                    // Loading Message
                    Text(loadingMessage)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(width: 300)
                }
                .padding(.top, 20)
            }
        }
        .opacity(isLoading ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isLoading)
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
