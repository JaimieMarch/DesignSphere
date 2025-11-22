import SwiftUI
import RealityKit
import XRShareCollaboration

struct EditModelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: CollaborativeSessionController
    
    @State private var selectedTab = 0
    @State private var modelWidth: Float = 10
    @State private var modelHeight: Float = 10
    @State private var modelDepth: Float = 10
    @State private var X: Double = 0
    @State private var Y: Double = 0
    @State private var Z: Double = 0
    @State private var selectedColor: Color = .blue
    @State private var customColor: Color = .cyan

    var body: some View {
        VStack(spacing: 24) {
            EditModelHeader(
                modelName: controller.selectedModelIDVar?.displayName ?? "Unknown Model"
            )
            
            Picker("", selection: $selectedTab) {
                Text("Size").tag(0)
                Text("Position").tag(1)
                Text("Style").tag(2)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 16) {
                switch selectedTab {
                case 0:
                    SizeTab(width: $modelWidth, height: $modelHeight, depth: $modelDepth)
                case 1:
                    PositionTab(x: $X, y: $Y, z: $Z)
                case 2:
                    StyleTab(selectedColor: $selectedColor, customColor: $customColor)
                default:
                    EmptyView()
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
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
        .shadow(radius: 5)
        .padding()
        .onAppear { loadModelProperties() }
        .onChange(of: modelWidth) { _, _ in updateEntityScale() }
        .onChange(of: modelHeight) { _, _ in updateEntityScale() }
        .onChange(of: modelDepth) { _, _ in updateEntityScale() }
        .onChange(of: X) { _, _ in updateEntityPosition() }
        .onChange(of: Y) { _, _ in updateEntityPosition() }
        .onChange(of: Z) { _, _ in updateEntityPosition() }
    }
    
    private func loadModelProperties() {
        guard let modelID = controller.selectedModelIDVar?.displayName,
              let model = controller.returnSelectedModel(named: modelID),
              let entity = model.modelEntity else { return }
        
        modelWidth = entity.scale.x
        modelHeight = entity.scale.y
        modelDepth = entity.scale.z
        X = Double(entity.position.x)
        Y = Double(entity.position.y)
        Z = Double(entity.position.z)
    }

    private func updateEntityScale() {
        guard let modelID = controller.selectedModelIDVar?.displayName,
              let model = controller.returnSelectedModel(named: modelID),
              let entity = model.modelEntity else { return }
        entity.scale = SIMD3<Float>(modelWidth, modelHeight, modelDepth)
    }
    
    private func updateEntityPosition() {
        guard let modelID = controller.selectedModelIDVar?.displayName,
              let model = controller.returnSelectedModel(named: modelID),
              let entity = model.modelEntity else { return }
        entity.position = SIMD3<Float>(Float(X), Float(Y), Float(Z))
    }
}
