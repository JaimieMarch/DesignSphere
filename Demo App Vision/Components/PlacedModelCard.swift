import SwiftUI

struct PlacedModelCard: View {
    let name: String
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .frame(height: 100)
                
                // Remove button appears on hover
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .glassBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
