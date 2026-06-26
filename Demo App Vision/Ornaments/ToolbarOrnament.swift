// Bottom toolbar ornament for presenting key UI action
// Each button toggles a bound Boolean, which triggers the corresponding sheet

import SwiftUI
import XRShareCollaboration

struct ToolbarOrnament: View {
    @ObservedObject var controller: CollaborativeSessionController
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var showMeasurementOptions: Bool
    @Binding var showFocusModeSheet: Bool
    @Binding var showImportSheet: Bool
    @Binding var showAIAssistant: Bool

    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack(spacing: 8) {
                        ornamentButton(
                            systemImage: "arrow.uturn.backward",
                            action: { controller.undo() }
                        )
                        .disabled(!controller.canUndo)
                        .accessibilityLabel("Undo")
                        .accessibilityHint("Undo the last scene edit")

                        ornamentButton(
                            systemImage: "arrow.uturn.forward",
                            action: { controller.redo() }
                        )
                        .disabled(!controller.canRedo)
                        .accessibilityLabel("Redo")
                        .accessibilityHint("Redo the last undone scene edit")

                        ornamentButton(
                            systemImage: "eye",
                            action: { showFocusModeSheet = true }
                        )
                        .accessibilityLabel("Focus mode")
                        .accessibilityHint("Opens focus mode options to hide or show real-world items")

                        ornamentButton(
                            systemImage: "square.and.arrow.down",
                            action: { showImportSheet = true }
                        )
                        .accessibilityLabel("Import model")
                        .accessibilityHint("Import a custom 3D model from your device")

                        if AppFeatureFlags.aiAssistantEnabled {
                            ornamentButton(
                                systemImage: "sparkles",
                                action: { showAIAssistant = true }
                            )
                            .accessibilityLabel("Design assistant")
                            .accessibilityHint("Get furniture suggestions and furnish a room")
                        }

                        Menu {
                            ForEach(FurnitureCollisionMode.allCases) { mode in
                                Button {
                                    appSettings.collisionMode = mode
                                    controller.setCollisionMode(mode)
                                } label: {
                                    Label(
                                        mode.label,
                                        systemImage: mode == controller.collisionMode ? "checkmark.circle.fill" : mode.symbolName
                                    )
                                }
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: controller.collisionMode.symbolName)
                                    .frame(width: 28, height: 28)

                                if controller.collisionMode != .off && controller.collisionWarningCount > 0 {
                                    Text("\(min(controller.collisionWarningCount, 9))")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.red, in: Capsule())
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Collision mode")
                        .accessibilityHint("Switch between off, warn, and prevent collision behavior")

                        if AppFeatureFlags.measurementToolsEnabled {
                            ornamentButton(
                                systemImage: "ruler",
                                action: { showMeasurementOptions = true }
                            )
                            .accessibilityLabel("Measurement tools")
                            .accessibilityHint("Open measurement and ruler tools")
                        }
                    }
                }
            }
    }

    private func ornamentButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.circle)
    }
}
