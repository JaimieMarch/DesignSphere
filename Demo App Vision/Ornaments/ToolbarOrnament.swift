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
    
    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack(spacing: 8) {
                        Button {
                            controller.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .disabled(!controller.canUndo)
                        .accessibilityLabel("Undo")
                        .accessibilityHint("Undo the last scene edit")

                        Button {
                            controller.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .disabled(!controller.canRedo)
                        .accessibilityLabel("Redo")
                        .accessibilityHint("Redo the last undone scene edit")

                        Button {
                            showFocusModeSheet = true
                        } label: {
                            Image(systemName: "eye")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Focus mode")
                        .accessibilityHint("Opens focus mode options to hide or show real-world items")

                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Import model")
                        .accessibilityHint("Import a custom 3D model from your device")

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

                        if AppFeatureFlags.measurementToolsEnabled && appSettings.labsMeasurementToolsEnabled {
                            Button {
                                showMeasurementOptions = true
                            } label: {
                                Image(systemName: "ruler")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("Measurement tools")
                            .accessibilityHint("Open measurement and ruler tools")
                        }
                    }
                }
            }
    }
}
