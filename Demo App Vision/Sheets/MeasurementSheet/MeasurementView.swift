import SwiftUI

struct MeasurementView: View {
    @Binding var isPresented: Bool
    @State private var measurementUnit = "inches"
    @State private var showDimensions = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header section matching other sheets
            VStack(spacing: 16) {
                Image(systemName: "ruler")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("Measurement Tools")
                    .font(.title)
                    .bold()
            }
            
            VStack(spacing: 20) {
                Picker("Unit", selection: $measurementUnit) {
                    Text("Inches").tag("inches")
                    Text("Feet").tag("feet")
                    Text("Centimeters").tag("cm")
                    Text("Meters").tag("m")
                }
                .pickerStyle(.segmented)
                
                Toggle("Show Dimensions on Objects", isOn: $showDimensions)
                    .padding(.vertical, 8)
                
                Button(action: { spawnRuler() }) {
                    Label("Spawn Virtual Ruler", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: { measureDistance() }) {
                    Label("Measure Distance", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
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
    }
    
    private func spawnRuler() {
        print("Spawn Ruler - NOT YET IMPLEMENTED")
    }
    
    private func measureDistance() {
        print("Measure Distance - NOT YET IMPLEMENTED")
    }
}
