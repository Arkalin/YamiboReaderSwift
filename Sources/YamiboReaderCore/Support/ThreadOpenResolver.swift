import Foundation

public actor ThreadOpenResolver {
    private let client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func resolve(
        threadURL: URL,
        title: String? = nil,
        htmlOverride: String? = nil,
        favoriteType: FavoriteType = .unknown,
        favoriteChapterURL: URL? = nil,
        initialPage: Int = 0
    ) async throws -> ThreadOpenTarget {
        let canonicalURL = ReaderModeDetector.canonicalThreadURL(from: threadURL) ?? threadURL

        switch favoriteType {
        case .novel:
            return .novel(
                ReaderLaunchContext(
                    threadURL: canonicalURL,
                    threadTitle: title ?? "小说阅读",
                    source: .favorites,
                    initialPage: initialPage
                )
            )
        case .manga:
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: canonicalURL,
                    chapterURL: favoriteChapterURL ?? canonicalURL,
                    displayTitle: title ?? "漫画阅读",
                    source: .favorites,
                    initialPage: initialPage
                )
            )
        case .other:
            return .web(canonicalURL)
        case .unknown:
            break
        }

        let snapshot = try await loadSnapshot(for: canonicalURL, knownTitle: title, htmlOverride: htmlOverride)
        if ReaderModeDetector.canOpenReader(url: canonicalURL, title: snapshot.title) {
            return .novel(
                ReaderLaunchContext(
                    threadURL: canonicalURL,
                    threadTitle: snapshot.title,
                    source: .forum
                )
            )
        }

        if MangaHTMLParser.isLikelyMangaThread(title: snapshot.title, html: snapshot.html) {
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: canonicalURL,
                    chapterURL: favoriteChapterURL ?? canonicalURL,
                    displayTitle: MangaTitleCleaner.cleanBookName(snapshot.title.isEmpty ? (title ?? "漫画阅读") : snapshot.title),
                    source: .forum,
                    initialPage: initialPage
                )
            )
        }

        return .web(canonicalURL)
    }

    private func loadSnapshot(for url: URL, knownTitle: String?, htmlOverride: String?) async throws -> (title: String, html: String) {
        if let htmlOverride, !htmlOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let extractedTitle = ReaderHTMLParser.extractPageTitle(from: htmlOverride) ?? knownTitle ?? ""
            return (extractedTitle, htmlOverride)
        }

        let html = try await client.fetchHTML(for: .thread(url: url, page: 1, authorID: nil))
        let extractedTitle = ReaderHTMLParser.extractPageTitle(from: html) ?? knownTitle ?? ""
        return (extractedTitle, html)
    }
}
