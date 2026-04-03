import SwiftUI

// MARK: - Header
struct EditModelHeader: View {
    let modelName: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)

            Text("Edit Model")
                .font(.title)
                .bold()

            Text(modelName)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sliders
struct DimensionSlider: View {
    let title: String
    @Binding var value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value * 100)) cm")
                    .foregroundStyle(.secondary)
            }

            Slider(value: Binding(
                get: { value * 100 },
                set: { value = $0 / 100 }
            ), in: 0...100)
            .tint(.white)
            .controlSize(.large)
            .accessibilityLabel("\(title) slider")
            .accessibilityValue("\(Int(value * 100)) centimeters")
        }
    }
}

struct CoordinateSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value))")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: -10...10, step: 0.001)
                .tint(.white)
                .controlSize(.large)
                .accessibilityLabel("\(title) position slider")
                .accessibilityValue("\(Int(value))")
        }
    }
}

// MARK: - Color Picker
struct ColorCircle: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 66, height: 66)
                .overlay(
                    Circle()
                        .stroke(lineWidth: isSelected ? 3 : 1)
                        .foregroundStyle(isSelected ? .white : .gray.opacity(0.4))
                )
                .shadow(radius: isSelected ? 3 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color swatch")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
    }
}
