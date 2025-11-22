import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.largeTitle.bold())
            
            Spacer()
            
            Text("Settings will appear here")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(cornerRadius: 24)
        .padding(24)
    }
}
