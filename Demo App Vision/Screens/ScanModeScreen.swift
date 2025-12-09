// Placeholder screen for handling object scanning mode

import SwiftUI

struct ScanModeScreen: View {
    @State private var isScanningActive = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Scan Mode")
                .font(.largeTitle.bold())
            
            Image(systemName: "vision.pro.and.arrow.forward")
                .font(.system(size: 100))
                .foregroundStyle(.secondary)
            
            Text("Position your device to scan furniture and objects")
                .font(.title2)
                .multilineTextAlignment(.center)
            
            Button(action: {
                isScanningActive.toggle()
            }) {
                Label(
                    isScanningActive ? "Stop Scanning" : "Start Scanning",
                    systemImage: isScanningActive ? "stop.fill" : "play.fill"
                )
                .font(.title3)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(cornerRadius: 24)
        .padding(24)
    }
}
