import SwiftUI

// MARK: - Size Tab
struct SizeTab: View {
    @Binding var width: Float
    @Binding var height: Float
    @Binding var depth: Float
    
    var body: some View {
        VStack(spacing: 16) {
            DimensionSlider(title: "Width", value: $width)
            DimensionSlider(title: "Height", value: $height)
            DimensionSlider(title: "Depth", value: $depth)
        }
    }
}

// MARK: - Position Tab
struct PositionTab: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double
    
    var body: some View {
        VStack(spacing: 16) {
            CoordinateSlider(title: "X Position", value: $x)
            CoordinateSlider(title: "Y Position", value: $y)
            CoordinateSlider(title: "Z Position", value: $z)
        }
    }
}

// MARK: - Style Tab
struct StyleTab: View {
    @Binding var selectedColor: Color
    @Binding var customColor: Color
    
    private let presetColors: [Color] = [.red, .green, .blue, .orange, .purple]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Colour").bold()
            
            Grid {
                GridRow {
                    ForEach(0..<3, id: \.self) { index in
                        ColorCircle(
                            color: presetColors[index],
                            isSelected: selectedColor == presetColors[index],
                            onTap: { selectedColor = presetColors[index] }
                        )
                    }
                }
                GridRow {
                    ForEach(3..<5, id: \.self) { index in
                        ColorCircle(
                            color: presetColors[index],
                            isSelected: selectedColor == presetColors[index],
                            onTap: { selectedColor = presetColors[index] }
                        )
                    }
                    ColorPicker("", selection: $customColor)
                        .labelsHidden()
                        .onChange(of: customColor) { _, newValue in
                            selectedColor = newValue
                        }
                }
            }
        }
    }
}
