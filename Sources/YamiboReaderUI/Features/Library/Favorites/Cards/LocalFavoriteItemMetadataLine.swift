import SwiftUI
import YamiboReaderCore

/// Compact metadata line: reading progress, chapter/page position, recency,
/// and content update date.
struct LocalFavoriteItemMetadataLine: View {
    let progressPercent: Int?
    let chapterPageProgress: String?
    let recentReadingAt: Date?
    let lastUpdatedAt: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metadataContent
            }
            VStack(alignment: .leading, spacing: 2) {
                metadataContent
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var metadataContent: some View {
        if let progressPercent {
            Label("\(progressPercent)%", systemImage: "chart.line.uptrend.xyaxis")
        }
        if let chapterPageProgress {
            Label(chapterPageProgress, systemImage: "book.pages")
        }
        if let recentReadingAt {
            Label {
                Text(recentReadingAt, format: .dateTime.month().day())
            } icon: {
                Image(systemName: "clock")
            }
        }
        if let lastUpdatedAt {
            Label {
                Text(lastUpdatedAt, format: .dateTime.month().day())
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }
}

/// Row of up to four tag chips shown on item rows and cards.
struct LocalFavoriteTagChipRow: View {
    let tags: [FavoriteTag]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(4)) { tag in
                        Text(tag.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tag.color.iconTextColor)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tag.color.swiftUIColor, in: Capsule())
                    }
                }
            }
            .scrollDisabled(true)
        }
    }
}
