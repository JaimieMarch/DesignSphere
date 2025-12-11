// Bottom toolbar ornament for presenting key UI action
// Each button toggles a bound Boolean, which triggers the corresponding sheet

import SwiftUI
import XRShareCollaboration

struct ToolbarOrnament: View {
    @Binding var showMeasurementOptions: Bool
    @Binding var showFocusModeSheet: Bool
    @Binding var showEditSheet: Bool
    @Binding var showImportSheet: Bool
    @ObservedObject var controller: CollaborativeSessionController
    
    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    HStack(spacing: 8) {
                        Button {
                            showFocusModeSheet = true
                        } label: {
                            Image(systemName: "eye")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        
                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)

                        Button {
                            showMeasurementOptions = true
                        } label: {
                            Image(systemName: "ruler")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)

                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 28, height: 28)
                        }
                        // Only enabled when a model is selected.
                        .disabled(controller.selectedModelIDVar == nil)
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                    }
                }
            }
    }
}
