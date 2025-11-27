// Bottom toolbar

// Each button uses a binding toggle to show the corresponding sheet
// Styling is directly attached to each button

import SwiftUI
import XRShareCollaboration

struct ToolbarOrnament: View {
    @Binding var showMeasurementOptions: Bool
    @Binding var showFocusModeSheet: Bool
    @Binding var showAIAssistantSheet: Bool
    @Binding var showSharePlaySheet: Bool
    @Binding var showEditSheet: Bool
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
                            showAIAssistantSheet = true
                        } label: {
                            Image(systemName: "microphone")
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
                            showSharePlaySheet = true
                        } label: {
                            Image(systemName: "person.2")
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
                        .disabled(controller.selectedModelIDVar == nil)
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                    }
                }
            }
    }
}
