import SwiftUI
import XRShareCollaboration

struct FocusModeView: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController
    @ObservedObject var focusModeManager: FocusModeManager

    @State private var widthMeters: Double
    @State private var depthMeters: Double
    @State private var heightMeters: Double
    @State private var suppressDimensionBroadcast = false

    private enum RoomPreset: String, CaseIterable, Identifiable {
        case compact
        case balanced
        case expansive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact:
                return "Compact"
            case .balanced:
                return "Balanced"
            case .expansive:
                return "Expansive"
            }
        }

        var subtitle: String {
            switch self {
            case .compact:
                return "Smaller, more intimate layout"
            case .balanced:
                return "Default studio proportions"
            case .expansive:
                return "Roomier view with more breathing space"
            }
        }

        var dimensions: (width: Double, depth: Double, height: Double) {
            switch self {
            case .compact:
                return (5.2, 5.2, 2.9)
            case .balanced:
                return (7.0, 7.0, 3.2)
            case .expansive:
                return (8.6, 8.6, 3.8)
            }
        }
    }

    private struct FocusModeCard<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.weight(.semibold))
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    init(isPresented: Binding<Bool>, controller: CollaborativeSessionController) {
        self._isPresented = isPresented
        self._controller = ObservedObject(wrappedValue: controller)
        self._focusModeManager = ObservedObject(wrappedValue: controller.focusModeManager)

        let dims = controller.focusRoomDimensions
        self._widthMeters = State(initialValue: Double(dims.width))
        self._depthMeters = State(initialValue: Double(dims.depth))
        self._heightMeters = State(initialValue: Double(dims.height))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                ScrollView {
                    VStack(spacing: 18) {
                        headerCard
                        themeSection
                        roomSection
                        controlSection
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            }
            .padding(14)
            .navigationTitle("Focus Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
        .onAppear {
            syncSliderState(with: focusModeManager.focusRoomDimensions)
        }
        .onChange(of: focusModeManager.focusRoomDimensions) { _, newValue in
            syncSliderState(with: newValue)
        }
        .onChange(of: widthMeters) { _, _ in
            pushDimensionChanges()
        }
        .onChange(of: depthMeters) { _, _ in
            pushDimensionChanges()
        }
        .onChange(of: heightMeters) { _, _ in
            pushDimensionChanges()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.thinMaterial)

            LinearGradient(
                colors: [
                    focusModeManager.activeTheme.swatch.opacity(0.14),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            Circle()
                .fill(focusModeManager.activeTheme.swatch.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 55)
                .offset(x: 170, y: -210)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var headerCard: some View {
        FocusModeCard(title: "Focus Room") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(focusModeManager.activeTheme.swatch.opacity(0.22))
                            .frame(width: 72, height: 72)

                        Image(systemName: focusModeManager.activeTheme.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(focusModeManager.activeTheme.swatch)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(focusModeManager.isFocusModeActive ? "Focus mode active" : "Ready to enter")
                            .font(.title2.weight(.semibold))
                        Text("A controlled spatial room for uninterrupted design work.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        statusPill

                        if let lastRecenteredAt = focusModeManager.lastRecenteredAt {
                            Text(lastRecenteredAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(focusModeManager.activeTheme.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    metricChip(title: "Width", value: widthMeters)
                    metricChip(title: "Depth", value: depthMeters)
                    metricChip(title: "Height", value: heightMeters)
                }
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if focusModeManager.isRecentering {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: focusModeManager.isFocusModeActive ? "checkmark.circle.fill" : "sparkle")
            }

            Text(focusModeManager.statusText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var themeSection: some View {
        FocusModeCard(title: "Environment Style") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose the room mood before entering focus mode. The environment updates live.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(FocusModeManager.FocusModeTheme.allCases) { theme in
                        Button {
                            focusModeManager.setFocusTheme(theme)
                        } label: {
                            themeCard(theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func themeCard(_ theme: FocusModeManager.FocusModeTheme) -> some View {
        let isSelected = focusModeManager.activeTheme == theme

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(theme.swatch.opacity(0.18))
                        .frame(width: 38, height: 38)

                    Image(systemName: theme.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.swatch)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.swatch)
                }
            }

            Text(theme.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(theme.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? theme.swatch.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? theme.swatch.opacity(0.12) : .clear, radius: 12, y: 4)
    }

    private var roomSection: some View {
        FocusModeCard(title: "Room Geometry") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Use presets for fast tuning, then refine the room with sliders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(RoomPreset.allCases) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(preset.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.thinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 14) {
                    dimensionSlider(
                        label: "Width",
                        subtitle: "Left to right span",
                        value: $widthMeters,
                        range: 4.0...10.0
                    )

                    dimensionSlider(
                        label: "Depth",
                        subtitle: "Front to back span",
                        value: $depthMeters,
                        range: 4.0...10.0
                    )

                    dimensionSlider(
                        label: "Height",
                        subtitle: "Floor to ceiling span",
                        value: $heightMeters,
                        range: 2.5...5.0
                    )
                }
            }
        }
    }

    private var controlSection: some View {
        FocusModeCard(title: "Actions") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recentering uses your current view and preserves the room style you picked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if focusModeManager.isFocusModeActive {
                    HStack(spacing: 12) {
                        Button {
                            focusModeManager.exitFocusMode()
                        } label: {
                            Label("Exit Focus Mode", systemImage: "arrow.backward.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(focusModeManager.isRecentering)

                        Button {
                            focusModeManager.recenterFocusMode()
                        } label: {
                            Label(
                                focusModeManager.isRecentering ? "Recentering..." : "Recenter Room",
                                systemImage: "scope"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(focusModeManager.isRecentering)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button {
                            focusModeManager.enterFocusMode()
                        } label: {
                            Label("Enter Focus Mode", systemImage: "arrow.forward.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            isPresented = false
                        } label: {
                            Text("Keep Editing")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(value.wrappedValue, specifier: "%.1f") m")
                    .font(.headline)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: 0.1)
                .tint(focusModeManager.activeTheme.swatch)
                .accessibilityLabel("\(label) slider")
                .accessibilityValue("\(value.wrappedValue, specifier: "%.1f") meters")
        }
    }

    private func metricChip(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.1f") m")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func applyPreset(_ preset: RoomPreset) {
        let dims = preset.dimensions
        suppressDimensionBroadcast = true
        widthMeters = dims.width
        depthMeters = dims.depth
        heightMeters = dims.height
        Task { @MainActor in
            suppressDimensionBroadcast = false
            pushDimensionChanges()
        }
    }

    private func syncSliderState(with dims: FocusModeManager.FocusRoomDimensions) {
        suppressDimensionBroadcast = true
        widthMeters = Double(dims.width)
        depthMeters = Double(dims.depth)
        heightMeters = Double(dims.height)
        Task { @MainActor in
            suppressDimensionBroadcast = false
        }
    }

    private func pushDimensionChanges() {
        guard suppressDimensionBroadcast == false else { return }
        controller.updateFocusRoomDimensions(
            width: Float(widthMeters),
            depth: Float(depthMeters),
            height: Float(heightMeters)
        )
    }
}
