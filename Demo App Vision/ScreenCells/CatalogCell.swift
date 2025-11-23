import SwiftUI

struct CatalogCell: View {
    let name: String
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .frame(height: 130)
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .glassBackground(cornerRadius: 20)
        .overlay(alignment: .topTrailing) {
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}
