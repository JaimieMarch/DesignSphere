//
//  EditModelView.swift
//  Demo App Vision
//
//  Created by Jaimie on 2025-11-19.
//

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
    @State private var selectedColor: Color = .blue
    @State private var customColor: Color = .cyan

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

            VStack(spacing: 16) {
                if selectedTab == 0 {
                    sizeSlider(title: "Width", value: $modelWidth)
                    sizeSlider(title: "Height", value: $modelHeight)
                    sizeSlider(title: "Depth", value: $modelDepth)
                } else if selectedTab == 1 {
                    coordinateSlider(title: "X Position", value: $X)
                    coordinateSlider(title: "Y Position", value: $Y)
                    coordinateSlider(title: "Z Position", value: $Z)
                } else {
                    VStack(spacing: 12) {
                        Text("Colour").bold()
                        Grid {
                            GridRow {
                                ForEach(0..<3, id: \.self) { index in
                                    colorCircle(presetColors[index])
                                }
                            }
                            GridRow {
                                ForEach(3..<5, id: \.self) { index in
                                    colorCircle(presetColors[index])
                                }
                                ColorPicker("", selection: $customColor)
                                    .labelsHidden()
                                    .onChange(of: customColor) {
                                        selectedColor = customColor
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

          
            Button(action: { dismiss() }) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 600, height: 700)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1))
        )
        .shadow(radius: 5)
        .padding()
        .onAppear {
        
            if let modelID = controller.selectedModelIDVar?.displayName,
               let model = controller.returnSelectedModel(named: modelID),
               let entity = model.modelEntity {
                
                let scale = entity.scale
                modelDepth = scale.x
                modelHeight = scale.y
                modelWidth = scale.z
            }
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

    }

 
    private func sizeSlider(title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value.wrappedValue * 100)) cm")
                    .foregroundStyle(.secondary)
            }

            Slider(value: Binding(
                get: { value.wrappedValue * 100 },
                set: { value.wrappedValue = $0 / 100 }
            ), in: 0...100)
            .tint(.white)
            .controlSize(.large)
        }
    }

    private func coordinateSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: -100...100)
                .tint(.white)
                .controlSize(.large)
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
            .onTapGesture { selectedColor = color }
            .shadow(radius: selectedColor == color ? 3 : 0)
    }

    private func updateEntityScale() {
        guard let modelID = controller.selectedModelIDVar?.displayName,
              let model = controller.returnSelectedModel(named: modelID),
              let entity = model.modelEntity else { return }
        entity.scale = SIMD3<Float>(modelWidth, modelHeight, modelDepth)
    }
}

