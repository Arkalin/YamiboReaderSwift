import SwiftUI
import YamiboReaderCore

/// Remote cover thumbnail with a colored fallback placeholder.
struct LocalFavoriteCoverThumbnail: View {
    let url: URL?
    let fallbackColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fallbackColor.opacity(0.16))
            if let url {
                YamiboRemoteImage(source: YamiboImageSource(url: url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                } failure: {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(fallbackColor)
    }
}

/// 2x2 cover mosaic used as a collection's preview.
struct LocalFavoriteCollectionCoverPreview: View {
    let color: Color
    let coverURLs: [URL]

    private let cellSize: CGFloat = 23

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(cellSize), spacing: 2),
                GridItem(.fixed(cellSize), spacing: 2)
            ],
            spacing: 2
        ) {
            ForEach(0..<4, id: \.self) { index in
                if index < coverURLs.count {
                    LocalFavoriteCoverThumbnail(url: coverURLs[index], fallbackColor: color)
                        .frame(width: cellSize, height: cellSize)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(index == 0 ? 0.8 : 0.18))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
