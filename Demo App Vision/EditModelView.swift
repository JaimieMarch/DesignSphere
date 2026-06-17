//  Provides the UI for editing a selected model.
//  Supports adjusting scale, rotation, materials, and deletion
//  Provides color and texture setting of models

import SwiftUI
import RealityKit
import XRShareCollaboration


struct EditModelView: View {
    @ObservedObject var controller: CollaborativeSessionController

    @State private var modelDepth: Float = 10
    @State private var modelHeight: Float = 10
    @State private var modelWidth: Float = 10
    @State private var selectedTab = 0
    @State private var X: Double = 0
    @State private var Y: Double = 0
    @State private var Z: Double = 0
    @State private var selectedColor: Color = .gray
    @State private var customColor: Color = .cyan
    @State private var selectedEntity: Entity? = nil
    @State private var ogSize: SIMD3<Float>? = nil

    private let presetColors: [Color] = [.red, .green, .blue, .orange, .purple]
    private let minValue: Float = -300
    private let maxValue: Float = 300

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Model")
                        .font(.title3.weight(.semibold))

                    Text(controller.selectedModelIDVar?.displayName ?? "Unknown Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Button {
                    controller.collapseEditMenu()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close edit menu")
            }

            Picker("Edit Mode", selection: $selectedTab) {
                Text("Size").tag(0)
                Text("Position").tag(1)
                Text("Style").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Edit mode selector")
            .accessibilityHint("Choose between size, position, or style editing")

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack(spacing: 10) {
                        quickActionButton(title: "Duplicate", icon: "plus.square.on.square") {
                            controller.duplicateSelectedModel()
                            refreshSelectedModelState()
                        }

                        quickActionButton(title: "Rotate 90", icon: "rotate.right") {
                            controller.rotateSelectedModelByQuarterTurn()
                            refreshSelectedModelState()
                        }
                    }

                    VStack(spacing: 20) {
                        if selectedTab == 0 {
                            sizeControl(title: "Width", value: $modelWidth)
                                .padding(.vertical, 8)
                            sizeControl(title: "Height", value: $modelHeight)
                                .padding(.vertical, 8)
                            sizeControl(title: "Depth", value: $modelDepth)
                                .padding(.vertical, 8)
                            Spacer(minLength: 12)
                            Button {
                                removeSelectedModel()
                            } label: {
                                Text("Remove Furniture")
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .accessibilityLabel("Remove furniture")
                            .accessibilityHint("Permanently removes this item from your design")
                            .padding(.top, 8)
                        } else if selectedTab == 1 {
                            nudgePad
                                .padding(.bottom, 10)
                            coordinateControl(title: "X Position", value: $X)
                                .padding(.vertical, 8)
                            coordinateControl(title: "Y Position", value: $Y)
                                .padding(.vertical, 8)
                            coordinateControl(title: "Z Position", value: $Z)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 16) {
                                Text("Colour")
                                    .font(.title3.weight(.semibold))

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(presetColors, id: \.self) { color in
                                            colorCircle(color)
                                        }

                                        ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                                            .labelsHidden()
                                            .frame(width: 66, height: 66)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                            .onChange(of: customColor) {
                                                selectedColor = customColor

                                                var mat = PhysicallyBasedMaterial()
                                                mat.baseColor = .init(tint: UIColor(selectedColor))
                                                controller.applyMaterialToSelectedModel(mat, materialType: "custom")
                                            }
                                            .overlay(
                                                Circle().stroke(
                                                    selectedColor == customColor ? .white : .gray.opacity(0.4),
                                                    lineWidth: selectedColor == customColor ? 3 : 1
                                                )
                                            )
                                            .accessibilityLabel("Custom color picker")
                                            .accessibilityHint("Opens color picker to choose a custom color")
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                            VStack(spacing: 18) {
                                Text("Material")
                                    .font(.title3.weight(.semibold))

                                HStack(spacing: 14) {
                                    materialButton("Wood", icon: "tree") {
                                        var mat = PhysicallyBasedMaterial()
                                        mat.baseColor = .init(tint: UIColor(selectedColor))
                                        mat.roughness = 0.6
                                        mat.metallic = 0.0
                                        if let texture = TextureCache.shared.texture(named: "wood_grain") {
                                            mat.normal = .init(texture: .init(texture))
                                        }
                                        controller.applyMaterialToSelectedModel(mat, materialType: "wood")
                                    }

                                    materialButton("Metal", icon: "shippingbox.fill") {
                                        var mat = PhysicallyBasedMaterial()
                                        mat.baseColor = .init(tint: UIColor(selectedColor))
                                        mat.roughness = 0.2
                                        mat.metallic = 1.0
                                        mat.specular = 0.5
                                        controller.applyMaterialToSelectedModel(mat, materialType: "metal")
                                    }
                                }

                                HStack(spacing: 14) {
                                    materialButton("Fabric", icon: "square.grid.3x3.fill") {
                                        var mat = PhysicallyBasedMaterial()
                                        mat.baseColor = .init(tint: UIColor(selectedColor))
                                        mat.roughness = 0.85
                                        mat.metallic = 0.0
                                        if let texture = TextureCache.shared.texture(named: "fabric") {
                                            mat.normal = .init(texture: .init(texture))
                                        }
                                        controller.applyMaterialToSelectedModel(mat, materialType: "fabric")
                                    }

                                    materialButton("Leather", icon: "seal.fill") {
                                        var mat = PhysicallyBasedMaterial()
                                        mat.baseColor = .init(tint: UIColor(selectedColor))
                                        mat.roughness = 0.8
                                        mat.metallic = 0.2
                                        if let texture = TextureCache.shared.texture(named: "leather") {
                                            mat.normal = .init(texture: .init(texture))
                                        }
                                        controller.applyMaterialToSelectedModel(mat, materialType: "leather")
                                    }
                                }

                                Button {
                                    controller.restoreSelectedModelMaterials()
                                    selectedColor = .gray
                                } label: {
                                    Text("Restore")
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .padding(.top, 4)
                            }
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Button {
                            controller.deselectModel()
                        } label: {
                            Text("Deselect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Deselect model")
                        .accessibilityHint("Deselects the current model and closes the editor")

                        Button(action: { controller.collapseEditMenu() }) {
                            Text("Hide")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Hide edit menu")
                        .accessibilityHint("Closes the edit panel while keeping the model selected")
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .onAppear {
            if let model = controller.returnSelectedModel(),
               let entity = model.modelEntity {

                selectedEntity = entity

                if let originalBoundsComp = entity.components[OriginalBoundsComponent.self] {
                    ogSize = originalBoundsComp.originalSize
                } else {
                    let bounds = entity.visualBounds(relativeTo: entity)
                    let size = bounds.max - bounds.min
                    ogSize = size
                }

                let currentBounds = entity.visualBounds(relativeTo: nil)
                let currentSize = currentBounds.max - currentBounds.min

                modelWidth  = currentSize.x * 100
                modelHeight = currentSize.y * 100
                modelDepth  = currentSize.z * 100

                let position = entity.position
                X = Double(position.x)
                Y = Double(position.y)
                Z = Double(position.z)
            }
        }
        .onChange(of: controller.selectedModelInstanceIDVar) {
            controller.commitSelectedModelEditTransaction()
            updateSelectedEntity()
        }
        .onChange(of: controller.expandedEditModelInstanceIDVar) {
            if controller.expandedEditModelInstanceIDVar != nil {
                updateSelectedEntity()
            }
        }
        .onDisappear {
            controller.commitSelectedModelEditTransaction()
        }
        .onChange(of: modelWidth) { updateEntityScale() }
        .onChange(of: modelHeight) { updateEntityScale() }
        .onChange(of: modelDepth) { updateEntityScale() }
        .onChange(of: X) { updateEntityPosition() }
        .onChange(of: Y) { updateEntityPosition() }
        .onChange(of: Z) { updateEntityPosition() }
    }

    private func sizeControl(title: String, value: Binding<Float>) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(spacing: 18) {
                Button {
                    value.wrappedValue = max(minValue, value.wrappedValue - 1)
                } label: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "minus")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        )
                }
                Spacer()
                    .frame(width: 20)

                HStack {
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                String(format: "%.2f", value.wrappedValue)
                            },
                            set: { newText in
                                if let cmValue = Float(newText) {
                                    value.wrappedValue = cmValue
                                }
                            }
                        )
                    )
                    .font(.title3.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 100, height: 52)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text("cm")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                    .frame(width: 20)

                Button {
                    value.wrappedValue = min(maxValue, value.wrappedValue + 1)
                } label: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        )
                }
            }
            .shadow(radius: 2, y: 1)
        }
        .padding(.horizontal, 6)
    }

    private func coordinateControl(title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(spacing: 18) {
                Button {
                    value.wrappedValue = max(-4.0, value.wrappedValue - 0.01)
                } label: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "minus")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        )
                }
                Spacer()
                    .frame(width: 20)

                HStack {
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                String(format: "%.2f", value.wrappedValue)
                            },
                            set: { newText in
                                if let v = Double(newText) {
                                    value.wrappedValue = min(4.0, max(-4.0, v))
                                }
                            }
                        )
                    )
                    .font(.title3.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 100, height: 52)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
                    .frame(width: 20)

                Button {
                    value.wrappedValue = min(4.0, value.wrappedValue + 0.01)
                } label: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        )
                }
            }
            .shadow(radius: 2, y: 1)
        }
        .padding(.horizontal, 6)
    }

    private func materialButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) material")
        .accessibilityHint("Apply \(title.lowercased()) texture to the model")
    }

    private func colorCircle(_ color: Color) -> some View {
        let colorName = colorToName(color)
        let isSelected = selectedColor == color
        return Circle()
            .fill(color)
            .frame(width: 66, height: 66)
            .overlay(
                Circle()
                    .stroke(lineWidth: isSelected ? 3 : 1)
                    .foregroundStyle(isSelected ? .white : .gray.opacity(0.4))
            )
            .onTapGesture {
                selectedColor = color

                var mat = PhysicallyBasedMaterial()
                mat.baseColor = .init(tint: UIColor(color))
                controller.applyMaterialToSelectedModel(mat, materialType: "custom")
            }
            .shadow(radius: isSelected ? 3 : 0)
            .accessibilityLabel("\(colorName) color")
            .accessibilityHint("Apply \(colorName) color to the model")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorToName(_ color: Color) -> String {
        switch color {
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .orange: return "Orange"
        case .purple: return "Purple"
        default: return "Custom"
        }
    }

    private func updateEntityScale() {
        guard let model = controller.returnSelectedModel(),
              model.modelEntity != nil,
              let og = ogSize else { return }

        let changeWidth  = modelWidth  / 100
        let changeHeight = modelHeight / 100
        let changeDepth  = modelDepth  / 100

        let scaleX = changeWidth  / og.x
        let scaleY = changeHeight / og.y
        let scaleZ = changeDepth  / og.z

        controller.updateSelectedModelScale(SIMD3<Float>(scaleX, scaleY, scaleZ))
    }

    private func updateEntityPosition() {
        guard let model = controller.returnSelectedModel(),
              model.modelEntity != nil else { return }

        controller.updateSelectedModelPosition(SIMD3<Float>(Float(X), Float(Y), Float(Z)))
    }

    private func updateSelectedEntity() {
        guard let model = controller.returnSelectedModel(),
              let entity = model.modelEntity else {
            selectedEntity = nil
            return
        }

        selectedEntity = entity

        if let originalBoundsComp = entity.components[OriginalBoundsComponent.self] {
            ogSize = originalBoundsComp.originalSize
        } else {
            let bounds = entity.visualBounds(relativeTo: entity)
            let size = bounds.max - bounds.min
            ogSize = size
        }

        let currentBounds = entity.visualBounds(relativeTo: nil)
        let currentSize = currentBounds.max - currentBounds.min

        modelWidth  = currentSize.x * 100
        modelHeight = currentSize.y * 100
        modelDepth  = currentSize.z * 100

        let position = entity.position
        X = Double(position.x)
        Y = Double(position.y)
        Z = Double(position.z)
    }

    private func removeSelectedModel() {
        guard let model = controller.returnSelectedModel() else { return }
        controller.removeModelById(withInstanceID: model.id)
    }

    private func quickActionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var nudgePad: some View {
        VStack(spacing: 10) {
            Text("Quick Position")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Spacer()
                nudgeButton(icon: "arrow.up", offset: SIMD3<Float>(0, 0, -0.05))
                nudgeButton(icon: "arrow.up.to.line.compact", offset: SIMD3<Float>(0, 0.05, 0))
                Spacer()
            }

            HStack(spacing: 10) {
                nudgeButton(icon: "arrow.left", offset: SIMD3<Float>(-0.05, 0, 0))
                nudgeButton(icon: "arrow.down.to.line.compact", offset: SIMD3<Float>(0, -0.05, 0))
                nudgeButton(icon: "arrow.right", offset: SIMD3<Float>(0.05, 0, 0))
            }

            HStack(spacing: 10) {
                Spacer()
                nudgeButton(icon: "arrow.down", offset: SIMD3<Float>(0, 0, 0.05))
                Spacer()
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nudgeButton(icon: String, offset: SIMD3<Float>) -> some View {
        Button {
            controller.nudgeSelectedModel(by: offset)
            refreshSelectedModelState()
        } label: {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 52, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func refreshSelectedModelState() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            updateSelectedEntity()
        }
    }
}
