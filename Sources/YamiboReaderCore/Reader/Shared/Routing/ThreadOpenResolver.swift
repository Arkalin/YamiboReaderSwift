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
        initialMangaPageIndex: Int = 0
    ) async throws -> ThreadOpenTarget {
        let requestURL = URL(string: threadURL.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL
            ?? threadURL.absoluteURL
        let canonicalURL = ReaderModeDetector.canonicalThreadURL(from: requestURL) ?? requestURL
        let authorID = Self.authorID(from: requestURL)

        switch favoriteType {
        case .novel:
            guard let threadID = ReaderHTMLParser.extractThreadID(from: canonicalURL) else {
                return .web(requestURL)
            }
            return .novel(
                ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: title ?? L10n.string("reader.title"),
                    source: .favorites,
                    authorID: authorID
                )
            )
        case .manga:
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: requestURL,
                    chapterURL: favoriteChapterURL ?? requestURL,
                    displayTitle: title ?? L10n.string("manga.reader.title"),
                    source: .favorites,
                    initialPage: initialMangaPageIndex
                )
            )
        case .other:
            return .web(requestURL)
        case .unknown:
            break
        }

        let snapshot = try await loadSnapshot(for: requestURL, knownTitle: title, htmlOverride: htmlOverride)
        if ReaderModeDetector.canOpenReader(url: canonicalURL, title: snapshot.title) {
            guard let threadID = ReaderHTMLParser.extractThreadID(from: canonicalURL) else {
                return .web(requestURL)
            }
            return .novel(
                ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: snapshot.title,
                    source: .forum,
                    authorID: authorID
                )
            )
        }

        if MangaHTMLParser.isLikelyMangaThread(title: snapshot.title, html: snapshot.html) {
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: requestURL,
                    chapterURL: favoriteChapterURL ?? requestURL,
                    displayTitle: MangaTitleCleaner.cleanBookName(snapshot.title.isEmpty ? (title ?? L10n.string("manga.reader.title")) : snapshot.title),
                    source: .forum,
                    initialPage: initialMangaPageIndex
                )
            )
        }

        return .web(requestURL)
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

    private static func authorID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "authorid" })?.value?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
