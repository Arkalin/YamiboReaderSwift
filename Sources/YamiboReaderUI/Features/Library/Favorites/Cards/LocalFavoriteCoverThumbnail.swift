import SwiftUI
import YamiboReaderCore

/// Cover with a text placeholder: when there is no cover URL or it fails to
/// load, the full title renders bold over a tinted background, its font size
/// stepped down by title length (Android CoverTextFallback parity).
///
/// Sizing goes through a `GeometryReader` rather than
/// `.frame(maxWidth: .infinity, maxHeight: .infinity)`: inside a List row
/// whose tap target is a `Button` label, that greedy frame style can resolve
/// against the button's ideal-size measurement pass instead of the final
/// layout size, letting the cover balloon past its intended box (real images
/// bleeding outside their frame; the text fallback stretching to the row's
/// full width). `GeometryReader` always reports the size it was actually
/// proposed, so the explicit `.frame(width:height:)` callers apply is honored
/// exactly.
struct LocalFavoriteCoverThumbnail: View {
    let url: URL?
    let title: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let url {
                    YamiboRemoteImage(source: YamiboImageSource(url: url)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } placeholder: {
                        textFallback(in: proxy.size)
                    } failure: {
                        textFallback(in: proxy.size)
                    }
                } else {
                    textFallback(in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private func textFallback(in size: CGSize) -> some View {
        LocalFavoriteCoverTextFallback(title: title, boxWidth: size.width)
            .frame(width: size.width, height: size.height)
    }
}

/// Title-on-color placeholder cover, mirroring the Android CoverTextFallback:
/// the full title, bold, horizontally centered from the top, with the font
/// size stepped by title length (32/24/19/15/12, Android parity) and
/// overflow clipped. Always rendered through an explicit size from its
/// caller (see `LocalFavoriteCoverThumbnail`) rather than sizing itself.
///
/// Android applies that step table as a fixed point size everywhere because
/// its own grid and row cards happen to compute to nearly the same cover
/// width. This app's row card is a fixed 92pt while the grid card's cover is
/// ~150pt+, so the same fixed size that fits the grid overflows the row
/// card. Scaling the whole table by `boxWidth / referenceWidth` keeps the
/// row-card fallback a proportional miniature of the grid one instead of a
/// truncated blob.
struct LocalFavoriteCoverTextFallback: View {
    let title: String
    let boxWidth: CGFloat

    /// The cover width the 32/24/19/15/12 step table below was tuned for —
    /// the fixed/staggered grid card's typical cover width on iPhone.
    private static let referenceWidth: CGFloat = 150

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
            Text(trimmedTitle)
                .font(.system(size: fontSize, weight: .bold))
                .lineSpacing(fontSize * 0.15)
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(scaledPadding)
        }
        .clipped()
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scale: CGFloat {
        guard boxWidth.isFinite, boxWidth > 0 else { return 1 }
        return boxWidth / Self.referenceWidth
    }

    private var scaledPadding: CGFloat {
        max(2, 8 * scale)
    }

    private var fontSize: CGFloat {
        max(6, baseFontSize * scale)
    }

    private var baseFontSize: CGFloat {
        switch trimmedTitle.count {
        case ...6: 32
        case ...12: 24
        case ...24: 19
        case ...40: 15
        default: 12
        }
    }
}

/// Width-filling 2x2 cover mosaic for the grid collection card: square tiles
/// with the collection color as tint, empty slots staying as tinted squares.
struct LocalFavoriteCollectionMosaic: View {
    let color: Color
    let title: String
    let coverURLs: [URL]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { column in
                        tile(at: row * 2 + column)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(at index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.18))
            if index < coverURLs.count {
                LocalFavoriteCoverThumbnail(url: coverURLs[index], title: title)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity)
    }
}

/// Flexible 2x2 cover mosaic, sized entirely by whatever frame the caller
/// applies (list rows size it to match an item row's cover so collection and
/// favorite rows come out the same height; pickers can use a small square).
struct LocalFavoriteCollectionCoverPreview: View {
    let color: Color
    let title: String
    let coverURLs: [URL]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let columnWidth = (proxy.size.width - spacing) / 2
            let rowHeight = (proxy.size.height - spacing) / 2
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    tile(at: 0, width: columnWidth, height: rowHeight)
                    tile(at: 1, width: columnWidth, height: rowHeight)
                }
                HStack(spacing: spacing) {
                    tile(at: 2, width: columnWidth, height: rowHeight)
                    tile(at: 3, width: columnWidth, height: rowHeight)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if index < coverURLs.count {
                LocalFavoriteCoverThumbnail(url: coverURLs[index], title: title)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(index == 0 ? 0.8 : 0.18))
            }
        }
        .frame(width: max(0, width), height: max(0, height))
    }
}
