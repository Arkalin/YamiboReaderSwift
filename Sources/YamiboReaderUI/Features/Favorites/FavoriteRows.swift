import SwiftUI
import YamiboReaderCore

struct FavoriteRow: View {
    let favorite: Favorite
    let isResolving: Bool
    let isDeleting: Bool
    let isSelected: Bool
    let isSelecting: Bool
    let tags: [FavoriteTag]
    let tagSearchText: String
    let prioritizedTagIDs: Set<String>
    let accentColor: Color
    let actionMenu: AnyView?
    let onOpen: () -> Void

    init(
        favorite: Favorite,
        isResolving: Bool,
        isDeleting: Bool,
        isSelected: Bool,
        isSelecting: Bool,
        tags: [FavoriteTag],
        tagSearchText: String,
        prioritizedTagIDs: Set<String>,
        accentColor: Color,
        actionMenu: AnyView? = nil,
        onOpen: @escaping () -> Void
    ) {
        self.favorite = favorite
        self.isResolving = isResolving
        self.isDeleting = isDeleting
        self.isSelected = isSelected
        self.isSelecting = isSelecting
        self.tags = tags
        self.tagSearchText = tagSearchText
        self.prioritizedTagIDs = prioritizedTagIDs
        self.accentColor = accentColor
        self.actionMenu = actionMenu
        self.onOpen = onOpen
    }

    private var tagChipSummary: FavoriteTagChipSummary {
        makeFavoriteTagChipSummary(
            for: favorite,
            tags: tags,
            searchText: tagSearchText,
            prioritizedTagIDs: prioritizedTagIDs
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(selectionAccentColor)
                .frame(width: 5)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(favorite.resolvedDisplayTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isResolving || isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 2)
                    }

                    if let actionMenu {
                        actionMenu
                            .padding(.top, -12)
                            .padding(.trailing, -10)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(favoriteDetailLineItems(for: favorite), id: \.self) { line in
                        FavoriteDetailLineView(line: line)
                    }

                    if favorite.isHidden {
                        Label(L10n.string("common.hidden"), systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !tagChipSummary.chips.isEmpty {
                        FavoriteTagChipRow(summary: tagChipSummary)
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .favoriteCardSurface(
            accentColor: accentColor,
            fallbackFill: .regularMaterial,
            fallbackBorderOpacity: 0.18,
            glassTintOpacity: 0.05,
            isInteractive: !isSelecting,
            isSelected: isSelected
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .favoriteCardTapGesture(isEnabled: !isSelecting, perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var titleColor: Color {
        isSelecting && !isSelected ? .secondary : .primary
    }

    private var selectionAccentColor: Color {
        isSelecting && !isSelected ? accentColor.opacity(0.35) : accentColor
    }
}

private struct FavoriteDetailLineView: View {
    let line: FavoriteDetailLine

    var body: some View {
        switch line {
        case let .text(text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .novelProgress(chapterTitle, progressText):
            HStack(spacing: 0) {
                if let chapterTitle, !chapterTitle.isEmpty {
                    Text(chapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)

                    Text(" · \(progressText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                } else {
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FavoriteTagChipRow: View {
    let summary: FavoriteTagChipSummary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(summary.chips) { tag in
                FavoriteTagChip(tag: tag)
            }

            if summary.overflowCount > 0 {
                Text("+\(summary.overflowCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.secondary.opacity(0.12))
                    )
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FavoriteTagChip: View {
    let tag: FavoriteTag

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.color.swiftUIColor)
                .frame(width: 6, height: 6)

            Text(tag.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Capsule(style: .continuous)
                .fill(tag.color.swiftUIColor.opacity(0.13))
        )
    }
}

struct FavoriteCollectionRow: View {
    let collection: FavoriteCollection
    let summary: FavoriteCollectionSummary
    let isSelected: Bool
    let isSelecting: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(selectionAccentColor)
                .frame(width: 7)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selectionAccentColor.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "folder.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(selectionAccentColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(collection.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(L10n.string("favorite_category.collection"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(accentColor)

                        if collection.isHidden {
                            Label(L10n.string("common.hidden"), systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .favoriteCardSurface(
            accentColor: accentColor,
            fallbackFill: accentColor.opacity(0.08),
            fallbackBorderOpacity: 0.32,
            glassTintOpacity: 0.1,
            isInteractive: !isSelecting,
            isSelected: isSelected
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var titleColor: Color {
        isSelecting && !isSelected ? .secondary : .primary
    }

    private var selectionAccentColor: Color {
        isSelecting && !isSelected ? accentColor.opacity(0.35) : accentColor
    }

    private var summaryText: String {
        if summary.hiddenCount > 0 {
            return L10n.string("favorites.collection_summary_hidden", summary.itemCount, summary.hiddenCount)
        }
        return L10n.string("favorites.collection_summary", summary.itemCount)
    }
}

struct FavoriteGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

private extension View {
    @ViewBuilder
    func favoriteCardSurface<Fill: ShapeStyle>(
        accentColor: Color,
        fallbackFill: Fill,
        fallbackBorderOpacity: Double,
        glassTintOpacity: Double,
        isInteractive: Bool,
        isSelected: Bool
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            if isInteractive {
                self
                    .glassEffect(
                        .regular
                            .tint(accentColor.opacity(glassTintOpacity))
                            .interactive(),
                        in: .rect(cornerRadius: 24)
                    )
                    .favoriteCardShadow()
            } else {
                self
                    .glassEffect(
                        .regular
                            .tint(accentColor.opacity(glassTintOpacity)),
                        in: .rect(cornerRadius: 24)
                    )
                    .favoriteCardShadow()
            }
        } else {
            self
                .favoriteCardFallbackSurface(fallbackFill)
                .favoriteCardBorder(
                    accentColor: accentColor,
                    fallbackBorderOpacity: fallbackBorderOpacity,
                    isSelected: isSelected
                )
                .favoriteCardShadow()
        }
        #else
        self
            .favoriteCardFallbackSurface(fallbackFill)
            .favoriteCardBorder(
                accentColor: accentColor,
                fallbackBorderOpacity: fallbackBorderOpacity,
                isSelected: isSelected
            )
            .favoriteCardShadow()
        #endif
    }

    func favoriteCardFallbackSurface<Fill: ShapeStyle>(_ fill: Fill) -> some View {
        background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(fill)
        )
    }

    func favoriteCardBorder(
        accentColor: Color,
        fallbackBorderOpacity: Double,
        isSelected: Bool
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : accentColor.opacity(fallbackBorderOpacity),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }

    func favoriteCardShadow() -> some View {
        shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    func favoriteCardTapGesture(isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        if isEnabled {
            onTapGesture(perform: action)
        } else {
            self
        }
    }
}

func makeFavoriteSelectionActionState(
    scope: FavoriteScope,
    selectedFavoriteCount: Int,
    selectedCollectionCount: Int
) -> FavoriteSelectionActionState {
    let state = FavoriteLibraryProjection.selectionActionState(
        scope: scope.libraryScope,
        selectedFavoriteCount: selectedFavoriteCount,
        selectedCollectionCount: selectedCollectionCount
    )
    return FavoriteSelectionActionState(
        canTag: state.canTag,
        canCreateCollection: state.canCreateCollection,
        canMove: state.canMove,
        canDelete: state.canDelete
    )
}

func makeBatchTagSelectionState(
    favorites: [Favorite],
    selectedFavoriteIDs: Set<String>
) -> FavoriteBatchTagSelectionState {
    let state = FavoriteLibraryProjection.batchTagSelectionState(
        favorites: favorites,
        selectedFavoriteIDs: selectedFavoriteIDs
    )
    return FavoriteBatchTagSelectionState(
        initialTagIDs: state.initialTagIDs,
        showsOverwriteWarning: state.showsOverwriteWarning
    )
}

func filteredFavoriteTags(_ tags: [FavoriteTag], searchText: String) -> [FavoriteTag] {
    FavoriteLibraryProjection.filteredTags(tags, searchText: searchText)
}

func canReorderFavoriteTags(sortOrder: FavoriteTagSortOrder, searchText: String) -> Bool {
    FavoriteLibraryProjection.canReorderTags(sortOrder: sortOrder.libraryTagSortOrder, searchText: searchText)
}

func canReorderFavoriteEntries(
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    FavoriteLibraryProjection.canReorderEntries(
        sortOrder: sortOrder.librarySortOrder,
        searchText: searchText,
        selectedTagIDs: selectedTagIDs
    )
}

func sortedFavoriteTags(
    _ tags: [FavoriteTag],
    favorites: [Favorite],
    sortOrder: FavoriteTagSortOrder
) -> [FavoriteTag] {
    FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: sortOrder.libraryTagSortOrder)
}

func favoriteTagAssociationCounts(from favorites: [Favorite]) -> [String: Int] {
    FavoriteLibraryProjection.tagAssociationCounts(from: favorites)
}

func makeFavoriteTagChipSummary(
    for favorite: Favorite,
    tags: [FavoriteTag],
    searchText: String,
    prioritizedTagIDs: Set<String> = []
) -> FavoriteTagChipSummary {
    let summary = FavoriteLibraryProjection.tagChipSummary(
        for: favorite,
        tags: tags,
        searchText: searchText,
        prioritizedTagIDs: prioritizedTagIDs
    )
    return FavoriteTagChipSummary(
        chips: summary.chips,
        overflowCount: summary.overflowCount
    )
}

func favoriteProgressScore(for favorite: Favorite) -> Int {
    favorite.lastView * 1000 + favorite.mangaPageIndex
}

func progressScore(for favorite: Favorite) -> Int {
    favoriteProgressScore(for: favorite)
}

func makeFilteredFavorites(
    from favorites: [Favorite],
    scope: FavoriteScope = .root,
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> [Favorite] {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: [])
    return FavoriteLibraryProjection.favorites(
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: sortOrder.librarySortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
}

func makeFavoriteListEntries(
    scope: FavoriteScope,
    favorites: [Favorite],
    collections: [FavoriteCollection],
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> [FavoriteListEntry] {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: collections)
    return FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: sortOrder.librarySortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
    .map(\.favoriteListEntry)
}

func rootCollectionMatches(
    _ collection: FavoriteCollection,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    let entries = makeFavoriteListEntries(
        scope: .root,
        favorites: favorites,
        collections: [collection],
        showsHidden: showsHidden,
        filter: filter,
        sortOrder: .manual,
        searchText: searchText,
        selectedTagIDs: selectedTagIDs
    )
    return entries.contains(.collection(collection))
}

func makeFavoriteCollectionSummary(
    for collection: FavoriteCollection,
    favorites: [Favorite],
    scope: FavoriteScope,
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> FavoriteCollectionSummary {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: [])
    let summary = FavoriteLibraryProjection.collectionSummary(
        for: collection,
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: .manual,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
    return FavoriteCollectionSummary(
        itemCount: summary.itemCount,
        hiddenCount: summary.hiddenCount
    )
}

private func favoriteSearchTextForCollectionMatch(
    _ collection: FavoriteCollection,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String>
) -> String {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedTagIDs.isEmpty,
          filter == .all,
          !trimmedSearchText.isEmpty,
          collection.name.localizedCaseInsensitiveContains(trimmedSearchText) else {
        return searchText
    }
    return ""
}

enum FavoriteDetailLine: Hashable {
    case text(String)
    case novelProgress(chapterTitle: String?, progressText: String)

    var displayText: String {
        switch self {
        case let .text(text):
            return text
        case let .novelProgress(chapterTitle, progressText):
            if let chapterTitle, !chapterTitle.isEmpty {
                return "\(chapterTitle) · \(progressText)"
            }
            return progressText
        }
    }
}

func favoriteProgressText(for favorite: Favorite) -> String? {
    if favorite.type == .novel {
        return favoriteNovelProgressText(for: favorite)
    }
    if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
        if favorite.type == .manga, favorite.mangaPageIndex > 0 {
            if let chapterLabel = favoriteMangaChapterLabel(from: lastChapter) {
                return L10n.string("favorites.progress.page_with_chapter", favorite.mangaPageIndex + 1, chapterLabel)
            }
            return L10n.string("favorites.progress.page", favorite.mangaPageIndex + 1)
        }
        return lastChapter
    }
    if favorite.type == .manga, favorite.mangaPageIndex > 0 {
        return L10n.string("favorites.progress.page", favorite.mangaPageIndex + 1)
    }
    if favorite.type == .unknown, favorite.mangaPageIndex > 0 || favorite.lastView > 1 {
        return L10n.string("favorites.progress.page_web", favorite.mangaPageIndex + 1, favorite.lastView)
    }
    return nil
}

func favoriteNovelProgressText(for favorite: Favorite) -> String? {
    guard favorite.type == .novel,
          favorite.novelResumePoint != nil else {
        return nil
    }

    let percent = favorite.novelDocumentSurfaceProgressPercent
    guard let maxView = favorite.novelMaxView, maxView > 1 else {
        guard let percent else { return nil }
        return L10n.string("favorites.progress.novel_percent", percent)
    }

    let view = min(max(favorite.lastView, 1), maxView)
    guard let percent else {
        return L10n.string("favorites.progress.novel_web", view, maxView)
    }

    return L10n.string(
        "favorites.progress.novel_page_web",
        percent,
        view,
        maxView
    )
}

func favoriteMangaChapterLabel(from rawTitle: String) -> String? {
    let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return nil }

    let chapterNumber = MangaTitleCleaner.extractChapterNumber(trimmedTitle)
    let displayNumber = MangaChapterDisplayFormatter.displayNumber(
        rawTitle: trimmedTitle,
        chapterNumber: chapterNumber
    )

    guard !displayNumber.isEmpty else { return nil }
    return L10n.string("favorites.manga_chapter", displayNumber)
}

func favoriteDetailLineItems(for favorite: Favorite) -> [FavoriteDetailLine] {
    var lines: [FavoriteDetailLine] = []

    if favorite.type == .manga {
        if let progressText = favoriteProgressText(for: favorite) {
            lines.append(.text(progressText))
        } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !lastChapter.isEmpty {
            lines.append(.text(lastChapter))
        }

        if lines.isEmpty {
            lines.append(.text(favorite.type.title))
        }

        return Array(lines.prefix(1))
    }

    if favorite.type == .novel {
        let chapterTitle = favorite.novelResumePoint?.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackChapterTitle = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayChapterTitle = [chapterTitle, fallbackChapterTitle]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let progressText = favoriteProgressText(for: favorite)

        if let progressText {
            lines.append(.novelProgress(chapterTitle: displayChapterTitle, progressText: progressText))
        } else if let displayChapterTitle {
            lines.append(.text(displayChapterTitle))
        }
    } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastChapter.isEmpty {
        lines.append(.text(lastChapter))
    }

    if favorite.type != .novel,
       let progressText = favoriteProgressText(for: favorite),
       !lines.contains(.text(progressText)) {
        lines.append(.text(progressText))
    }

    if lines.isEmpty {
        lines.append(.text(favorite.type.title))
    }

    return Array(lines.prefix(2))
}

func favoriteDetailLines(for favorite: Favorite) -> [String] {
    favoriteDetailLineItems(for: favorite).map(\.displayText)
}

func favoriteAccentAppearanceColor(
    for type: FavoriteType,
    appearance: FavoriteAppearanceSettings
) -> FavoriteAppearanceColor {
    switch type {
    case .novel:
        appearance.novel
    case .manga:
        appearance.manga
    case .other:
        appearance.other
    case .unknown:
        .gray
    }
}

func favoriteAccentColor(for type: FavoriteType, appearance: FavoriteAppearanceSettings) -> Color {
    favoriteAccentAppearanceColor(for: type, appearance: appearance).swiftUIColor
}

func favoriteCollectionAccentColor(for appearance: FavoriteAppearanceSettings) -> Color {
    appearance.collection.swiftUIColor
}

func favoriteCollectionAccentAppearanceColor(for appearance: FavoriteAppearanceSettings) -> FavoriteAppearanceColor {
    appearance.collection
}

func favoriteAccentColor(for type: FavoriteType) -> Color {
    favoriteAccentColor(for: type, appearance: .init())
}

func favoriteCollectionAccentColor() -> Color {
    favoriteCollectionAccentColor(for: .init())
}

func orderedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
    collections.sorted { lhs, rhs in
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func entryManualOrder(_ entry: FavoriteListEntry) -> Int {
    switch entry {
    case let .collection(collection):
        collection.manualOrder
    case let .favorite(favorite):
        favorite.manualOrder
    }
}

private func compareRecentReadFavorites(_ lhs: Favorite, _ rhs: Favorite) -> Bool {
    switch (lhs.lastReadAt, rhs.lastReadAt) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func compareRecentReadEntries(
    _ lhs: FavoriteListEntry,
    _ rhs: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    switch (
        entryLastReadAt(
            lhs,
            favorites: favorites,
            showsHidden: showsHidden,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        ),
        entryLastReadAt(
            rhs,
            favorites: favorites,
            showsHidden: showsHidden,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    ) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if entryManualOrder(lhs) != entryManualOrder(rhs) {
            return entryManualOrder(lhs) < entryManualOrder(rhs)
        }
        return lhs.id < rhs.id
    }
}

private func entryLastReadAt(
    _ entry: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Date? {
    switch entry {
    case let .favorite(favorite):
        return favorite.lastReadAt
    case let .collection(collection):
        let containedFavoriteSearchText = favoriteSearchTextForCollectionMatch(
            collection,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
        return makeFilteredFavorites(
            from: favorites,
            scope: .collection(collection),
            showsHidden: showsHidden,
            filter: filter,
            sortOrder: .recentRead,
            searchText: containedFavoriteSearchText,
            selectedTagIDs: selectedTagIDs
        )
        .compactMap(\.lastReadAt)
        .max()
    }
}

extension View {
    @ViewBuilder
    func onDragIf(_ condition: Bool, value: String, onStart: @escaping () -> Void) -> some View {
        if condition {
            onDrag {
                onStart()
                return NSItemProvider(object: value as NSString)
            }
        } else {
            self
        }
    }
}
