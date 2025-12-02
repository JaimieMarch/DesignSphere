//
//  EditModelView.swift
//  Demo App Vision


import SwiftUI
import RealityKit
import XRShareCollaboration


struct EditModelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: CollaborativeSessionController
    
    @State private var modelScale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    @State private var modelDepth: Float = 10
    @State private var modelHeight: Float = 10
    @State private var modelWidth: Float = 10
    @State private var selectedTab = 0
    @State private var width: Double = 50
    @State private var height: Double = 80
    @State private var depth: Double = 50
    @State private var X: Double = 0
    @State private var Y: Double = 0
    @State private var Z: Double = 0
    @State private var selectedColor: Color = .gray
    @State private var customColor: Color = .cyan
    @State private var selectedEntity: Entity? = nil
    @State private var ogSize: SIMD3<Float>? = nil
    
    private let presetColors: [Color] = [.red, .green, .blue, .orange, .purple]
    
    var body: some View {
        VStack(spacing: 24) {
            
            Image(systemName: "pencil")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Edit Model")
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)
            
            Text(controller.selectedModelIDVar?.displayName ?? "Unknown Model")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            
            Picker("", selection: $selectedTab) {
                Text("Size").tag(0)
                Text("Position").tag(1)
                Text("Style").tag(2)
            }
            .pickerStyle(.segmented)
            
            VStack(spacing: 20) {
                if selectedTab == 0 {
                    sizeControl(title: "Width", value: $modelWidth)
                        .padding(.vertical, 8)
                    sizeControl(title: "Height", value: $modelHeight)
                        .padding(.vertical, 8)
                    sizeControl(title: "Depth", value: $modelDepth)
                        .padding(.vertical, 8)
                    Spacer(minLength:12)
                    Button {
                        removeSelectedModel()
                        dismiss()
                        
                    } label: {
                        Text("Remove Furniture")
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .padding(.top, 8)
                } else if selectedTab == 1 {
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
                                
                                ColorPicker("", selection: $customColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: 70, height: 70)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .onChange(of: customColor) {
                                        selectedColor = customColor
                                        
                                        var mat = PhysicallyBasedMaterial()
                                        mat.baseColor = .init(tint: UIColor(selectedColor))
                                        selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                                        selectedEntity?.components.set(MaterialTypeComponent(materialType: "custom"))
                                    }
                                    .overlay(
                                        Circle().stroke(
                                            selectedColor == customColor ? .white : .gray.opacity(0.3),
                                            lineWidth: selectedColor == customColor ? 3 : 1
                                        )
                                    )
                                
        
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
                                mat.normal = .init(texture: .init(try! .load(named: "wood_grain")))
                                selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                                selectedEntity?.components.set(MaterialTypeComponent(materialType: "wood"))
                            }

                            materialButton("Metal", icon: "shippingbox.fill") {
                                var mat = PhysicallyBasedMaterial()
                                mat.baseColor = .init(tint: UIColor(selectedColor))
                                mat.roughness = 0.2
                                mat.metallic = 1.0
                                mat.specular = 0.5
                                selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                                selectedEntity?.components.set(MaterialTypeComponent(materialType: "metal"))
                            }
                        }
                        
                        HStack(spacing: 14) {
                            materialButton("Fabric", icon: "square.grid.3x3.fill") {
                                var mat = PhysicallyBasedMaterial()
                                mat.baseColor = .init(tint: UIColor(selectedColor))
                                mat.roughness = 0.85
                                mat.metallic = 0.0
                                mat.normal = .init(texture: .init(try! .load(named: "fabric")))
                                selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                                selectedEntity?.components.set(MaterialTypeComponent(materialType: "fabric"))
                            }

                            materialButton("Leather", icon: "seal.fill") {
                                var mat = PhysicallyBasedMaterial()
                                mat.baseColor = .init(tint: UIColor(selectedColor))
                                mat.roughness = 0.8
                                mat.metallic = 0.2
                                mat.normal = .init(texture: .init(try! .load(named: "leather")))
                                selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                                selectedEntity?.components.set(MaterialTypeComponent(materialType: "leather"))
                            }
                        }
                        
                        Button {
                            selectedEntity?.restoreOriginalMaterials()
                            selectedEntity?.components.remove(MaterialTypeComponent.self)
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
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Text("Close")
                    
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .frame(width: 700, height: 850)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1))
            )
            .shadow(radius: 5)
            .padding()
            .onAppear {
                
                if let model = controller.returnSelectedModel(),
                   let entity = model.modelEntity {

                    selectedEntity = entity

                    // Try to get original bounds from component (set during load)
                    if let originalBoundsComp = entity.components[OriginalBoundsComponent.self] {
                        ogSize = originalBoundsComp.originalSize
                    } else {
                        // Fallback: calculate from current bounds
                        let bounds = entity.visualBounds(relativeTo: entity)
                        let size = bounds.max - bounds.min
                        ogSize = size
                    }

                    // Calculate current displayed dimensions
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
            .onChange(of: controller.selectedModelInstanceIDVar) { _ in
                updateSelectedEntity()
            }
            .onChange(of: modelWidth) { _, newValue in
                modelWidth = newValue
                updateEntityScale()
            }
            .onChange(of: modelHeight) { _, newValue in
                modelHeight = newValue
                updateEntityScale()
            }
            .onChange(of: modelDepth) { _, newValue in
                modelDepth = newValue
                updateEntityScale()
            }
            .onChange(of: X) { _, newValue in
                X = newValue
                updateEntityPosition()
            }
            .onChange(of: Y) { _, newValue in
                Y = newValue
                updateEntityPosition()
            }
            .onChange(of: Z) { _, newValue in
                Z = newValue
                updateEntityPosition()
            }
            
            
        }
        
        private let minValue: Float = -300
        private let maxValue: Float = 300
        
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
                                    .font(.system(size: 20, weight: .semibold))
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
                                    String(format: "%.2f", value.wrappedValue )
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
                                    .font(.system(size: 20, weight: .semibold))
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
                                .font(.system(size: 20, weight: .semibold))
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
                                .font(.system(size: 20, weight: .semibold))
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
                .background(Color.gray.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        
        private func colorCircle(_ color: Color) -> some View {
            Circle()
                .fill(color)
                .frame(width: 66, height: 66)
                .overlay(
                    Circle()
                        .stroke(lineWidth: selectedColor == color ? 3 : 1)
                        .foregroundStyle(selectedColor == color ? .white : .gray.opacity(0.4))
                )
                .onTapGesture {
                    selectedColor = color

                    var mat = PhysicallyBasedMaterial()
                    mat.baseColor = .init(tint: UIColor(color))
                    selectedEntity?.replaceAndStoreOldMaterials(material: mat)
                    selectedEntity?.components.set(MaterialTypeComponent(materialType: "custom"))
                    //                if let id = controller.selectedModelInstanceIDVar {
                    //                    controller.setMaterial(for: id, to: mat)
                    //
                    //                }
                }
                .shadow(radius: selectedColor == color ? 3 : 0)
        }
            
        private func updateEntityScale() {
            guard let model = controller.returnSelectedModel(),
                  let entity = model.modelEntity,
                  let og = ogSize else { return }
            
            
            let changeWidth  = modelWidth  / 100
            let changeHeight = modelHeight / 100
            let changeDepth  = modelDepth  / 100

          
            let scaleX = changeWidth  / og.x
            let scaleY = changeHeight / og.y
            let scaleZ = changeDepth  / og.z

            entity.scale = SIMD3<Float>(scaleX, scaleY, scaleZ)
        }
        
        private func updateEntityPosition() {
            guard let model = controller.returnSelectedModel(),
                  let entity = model.modelEntity else { return }
            
            entity.position = SIMD3<Float>(Float(X),Float(Y),Float(Z))
        }
        
        private func updateSelectedEntity() {
            guard let model = controller.returnSelectedModel(),
                  let entity = model.modelEntity else {
                selectedEntity = nil
                return
            }

            selectedEntity = entity

            // Try to get original bounds from component (set during load)
            if let originalBoundsComp = entity.components[OriginalBoundsComponent.self] {
                ogSize = originalBoundsComp.originalSize
            } else {
                // Fallback: calculate from current bounds
                let bounds = entity.visualBounds(relativeTo: entity)
                let size = bounds.max - bounds.min
                ogSize = size
            }

            // Calculate current displayed dimensions
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
        
    }
    

