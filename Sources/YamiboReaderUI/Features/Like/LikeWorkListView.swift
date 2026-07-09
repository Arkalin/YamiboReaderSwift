import SwiftUI
import YamiboReaderCore

/// First-level Like list: one row per liked work, pushed from Mine.
struct LikeWorkListView: View {
    let likeDependencies: LikeDependencies
    let contentCoverStore: ContentCoverStore
    let favoriteLibraryStore: FavoriteLibraryStore
    let appModel: YamiboAppModel

    @State private var summaries: [LikeWorkSummary] = []
    @State private var titlesByWorkKey: [LikeWorkKey: String] = [:]
    @State private var coverURLsByWorkKey: [LikeWorkKey: URL] = [:]
    @State private var searchText = ""

    private var filteredSummaries: [LikeWorkSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return summaries }
        return summaries.filter { title(for: $0.workKey).localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(filteredSummaries, id: \.workKey) { summary in
            NavigationLink {
                LikeWorkItemsView(
                    work: summary.workKey,
                    workTitle: title(for: summary.workKey),
                    like: likeDependencies,
                    onOpenAnchor: { anchor in openAnchor(anchor, work: summary.workKey) },
                    onDismiss: nil
                )
            } label: {
                row(for: summary)
            }
        }
        .listStyle(.plain)
        // Kept permanently mounted rather than swapped for an empty-state
        // view — see the matching comment in LikeWorkItemsView.body for why
        // that swap makes `.searchable`'s search bar ghost during a push.
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView(L10n.string("likes.empty_state"), systemImage: "heart")
            } else if filteredSummaries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle(L10n.string("likes.section_title"))
        .searchable(text: $searchText, prompt: L10n.string("likes.search_placeholder"))
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: LikeStore.didChangeNotification)) { notification in
            guard let changeID = notification.userInfo?[LikeStore.changeIDUserInfoKey] as? String,
                  changeID == likeDependencies.likeStore.changeID else {
                return
            }
            Task { await load() }
        }
    }

    private func row(for summary: LikeWorkSummary) -> some View {
        HStack(spacing: 12) {
            LocalFavoriteCoverThumbnail(url: coverURLsByWorkKey[summary.workKey], title: title(for: summary.workKey))
                .frame(width: 92, height: 128)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: summary.workKey))
                    .font(.body)
                    .lineLimit(2)
                Text(String(summary.itemCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func title(for workKey: LikeWorkKey) -> String {
        titlesByWorkKey[workKey] ?? workKey.id
    }

    private func load() async {
        async let fetchedSummaries = likeDependencies.likeStore.workSummaries()
        async let favoriteDocument = try? favoriteLibraryStore.load()
        let (summaries, document) = await (fetchedSummaries, favoriteDocument ?? FavoriteLibraryDocument())
        self.summaries = summaries

        var titles: [LikeWorkKey: String] = [:]
        var covers: [LikeWorkKey: URL] = [:]
        for summary in summaries {
            let key = summary.workKey
            switch key.kind {
            case .novel:
                // Like Items don't persist a work title (unlike
                // implementation-design.md §1); best-effort resolve it from a
                // matching favorite, falling back to the raw tid.
                titles[key] = document.items.first(where: { $0.target.threadID == key.id })?.resolvedDisplayTitle
                covers[key] = await contentCoverStore.cover(for: .thread(tid: key.id))?.resolvedURL
            case .manga:
                titles[key] = key.id
                covers[key] = await contentCoverStore.cover(for: .smartManga(cleanBookName: key.id))?.resolvedURL
            }
        }
        titlesByWorkKey = titles
        coverURLsByWorkKey = covers
    }

    private func openAnchor(_ anchor: LikeAnchorPayload, work: LikeWorkKey) {
        let workTitle = title(for: work)
        switch anchor {
        case let .novelText(textAnchor):
            openNovelReader(
                threadID: work.id,
                workTitle: workTitle,
                resumePoint: NovelResumePoint(
                    view: textAnchor.view,
                    chapterIdentity: textAnchor.chapterIdentity,
                    textSegmentIdentity: textAnchor.textSegmentIdentity,
                    displayedTextOffset: textAnchor.range.location,
                    chapterOrdinal: 0,
                    segmentProgress: 0,
                    authorID: textAnchor.resolvedAuthorID,
                    readingModeHint: .paged
                )
            )
        case let .novelImage(imageAnchor):
            openNovelReader(
                threadID: work.id,
                workTitle: workTitle,
                resumePoint: NovelResumePoint(
                    view: imageAnchor.view,
                    chapterIdentity: imageAnchor.chapterIdentity,
                    textSegmentIdentity: NovelTextSegmentIdentity(rawValue: imageAnchor.imageSegmentIdentity),
                    displayedTextOffset: 0,
                    chapterOrdinal: 0,
                    segmentProgress: 0,
                    authorID: imageAnchor.resolvedAuthorID,
                    readingModeHint: .paged
                )
            )
        case let .mangaImage(mangaAnchor):
            appModel.presentMangaReader(
                MangaLaunchContext(
                    originalThreadID: mangaAnchor.chapterTID,
                    chapterTID: mangaAnchor.chapterTID,
                    displayTitle: workTitle,
                    source: .like,
                    initialPage: mangaAnchor.pageLocalIndex,
                    directoryName: work.id,
                    isPreview: true,
                    // Likes are keyed by `LikeWorkKey.mangaTitle(cleanBookName:)`
                    // (a `MangaDirectory`-level identity, `work.id` above),
                    // which can only exist once a directory has actually been
                    // resolved — and per decision #12, that only ever happens
                    // for a mode-on board. So every liked manga image
                    // necessarily came from a mode-on read.
                    isSmartModeEnabled: true
                )
            )
        }
    }

    private func openNovelReader(threadID: String, workTitle: String, resumePoint: NovelResumePoint) {
        appModel.presentNovelReader(
            NovelLaunchContext(
                threadID: threadID,
                threadTitle: workTitle,
                source: .like,
                initialView: resumePoint.view,
                initialResumePoint: resumePoint,
                isPreview: true
            )
        )
    }
}
