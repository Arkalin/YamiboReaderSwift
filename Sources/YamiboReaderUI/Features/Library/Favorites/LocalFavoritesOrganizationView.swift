import SwiftUI
import YamiboReaderCore

struct LocalFavoritesOrganizationView: View {
    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let cards: [FavoriteCardProjection]
    @Binding var selectedCategoryID: String

    var body: some View {
        NavigationStack {
            List {
                LocalFavoriteCategorySection(
                    categories: categories,
                    selectedCategoryID: $selectedCategoryID
                )
                LocalFavoriteCollectionSection(collections: visibleCollections)
                LocalFavoriteItemSection(cards: cards)
            }
            .modifier(LocalFavoriteListStyleModifier())
            .navigationTitle(L10n.string("favorites.title"))
            .toolbar {
                ToolbarItem(placement: LocalFavoriteToolbarPlacement.trailing) {
                    Menu {
                        Button {
                        } label: {
                            Label(L10n.string("favorites.tags"), systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L10n.string("common.more"))
                }
            }
        }
    }

    private var visibleCollections: [LocalFavoriteCollection] {
        collections
            .filter { $0.categoryID == selectedCategoryID }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }
}

private struct LocalFavoriteListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.listStyle(.insetGrouped)
        #else
        content.listStyle(.automatic)
        #endif
    }
}

private enum LocalFavoriteToolbarPlacement {
    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

private struct LocalFavoriteCategorySection: View {
    let categories: [FavoriteCategory]
    @Binding var selectedCategoryID: String

    var body: some View {
        Section {
            Picker(L10n.string("favorites.categories"), selection: $selectedCategoryID) {
                ForEach(categories) { category in
                    Text(category.name)
                        .tag(category.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct LocalFavoriteCollectionSection: View {
    let collections: [LocalFavoriteCollection]

    var body: some View {
        if !collections.isEmpty {
            Section(L10n.string("favorites.collections")) {
                ForEach(collections) { collection in
                    LocalFavoriteCollectionRow(
                        name: collection.name,
                        color: collection.color
                    )
                }
            }
        }
    }
}

private struct LocalFavoriteCollectionRow: View {
    let name: String
    let color: FavoriteCollectionColor

    var body: some View {
        Label {
            Text(name)
                .font(.body)
        } icon: {
            Circle()
                .fill(swiftUIColor)
                .frame(width: 12, height: 12)
        }
    }

    private var swiftUIColor: Color {
        switch color {
        case .red:
            .red
        case .orange:
            .orange
        case .yellow:
            .yellow
        case .green:
            .green
        case .blue:
            .blue
        case .purple:
            .purple
        case .pink:
            .pink
        case .gray:
            .gray
        }
    }
}

private struct LocalFavoriteItemSection: View {
    let cards: [FavoriteCardProjection]

    var body: some View {
        Section {
            ForEach(cards) { card in
                LocalFavoriteItemRow(
                    title: card.item.resolvedDisplayTitle,
                    sourceGroupLabel: card.sourceGroupLabel,
                    progressPercent: card.progressPercent,
                    chapterPageProgress: card.chapterPageProgress,
                    recentReadingAt: card.recentReadingAt
                )
            }
        } header: {
            Text(L10n.string("favorites.items_count", cards.count))
        }
    }
}

private struct LocalFavoriteItemRow: View {
    let title: String
    let sourceGroupLabel: String
    let progressPercent: Int?
    let chapterPageProgress: String?
    let recentReadingAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)
                Text(sourceGroupLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LocalFavoriteItemMetadataLine(
                    progressPercent: progressPercent,
                    chapterPageProgress: chapterPageProgress,
                    recentReadingAt: recentReadingAt
                )
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                } label: {
                    Label(L10n.string("favorites.tags"), systemImage: "tag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(L10n.string("common.more"))
        }
        .padding(.vertical, 4)
    }
}

private struct LocalFavoriteItemMetadataLine: View {
    let progressPercent: Int?
    let chapterPageProgress: String?
    let recentReadingAt: Date?

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
    }
}
