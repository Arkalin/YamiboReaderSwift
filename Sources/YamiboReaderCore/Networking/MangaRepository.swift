import Foundation

public actor MangaRepository {
    private let client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func fetchTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        var chapters: [MangaChapter] = []
        for (groupIndex, tagID) in tagIDs.enumerated() where !tagID.isEmpty {
            let firstHTML = try await client.fetchHTML(
                for: .tag(id: tagID, page: 1),
                userAgent: YamiboDefaults.desktopTagUserAgent
            )
            let firstPageItems = MangaHTMLParser.parseListHTML(firstHTML, groupIndex: groupIndex)
            if firstPageItems.isEmpty, MangaHTMLParser.isFloodControlOrError(firstHTML) {
                throw YamiboError.floodControl
            }
            chapters.append(contentsOf: firstPageItems)

            let totalPages = MangaHTMLParser.extractTotalPages(from: firstHTML)
            guard totalPages > 1 else { continue }

            for page in 2 ... totalPages {
                let html = try await client.fetchHTML(
                    for: .tag(id: tagID, page: page),
                    userAgent: YamiboDefaults.desktopTagUserAgent
                )
                chapters.append(contentsOf: MangaHTMLParser.parseListHTML(html, groupIndex: groupIndex))
            }
        }
        return chapters
    }

    public func searchAll(keyword: String, forumID: String = "30") async throws -> [MangaChapter] {
        let firstHTML = try await client.fetchHTML(for: .search(keyword: keyword, forumID: forumID))
        if MangaHTMLParser.isFloodControlOrError(firstHTML) {
            throw YamiboError.floodControl
        }

        var items = MangaHTMLParser.parseListHTML(firstHTML)
        let totalPages = MangaHTMLParser.extractTotalPages(from: firstHTML)
        guard totalPages > 1, let searchID = MangaHTMLParser.extractSearchID(from: firstHTML) else {
            return items
        }

        for page in 2 ... totalPages {
            let html = try await client.fetchHTML(for: .searchPage(searchID: searchID, page: page))
            items.append(contentsOf: MangaHTMLParser.parseListHTML(html))
        }
        return items
    }

    public func loadChapter(
        url: URL,
        htmlOverride: String? = nil
    ) async throws -> MangaChapterDocument {
        let html = try await chapterHTML(for: url, htmlOverride: htmlOverride)
        if MangaHTMLParser.isLoginPage(html) {
            throw YamiboError.notAuthenticated
        }
        if MangaHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }

        let pages = MangaHTMLParser.extractImageURLs(from: html, baseURL: url)
        guard !pages.isEmpty else {
            throw YamiboError.parsingFailed(context: "漫画图片")
        }

        let title = MangaHTMLParser.extractThreadTitle(from: html)
            ?? ReaderHTMLParser.extractPageTitle(from: html)
            ?? "漫画阅读"
        let tid = MangaTitleCleaner.extractTid(from: url.absoluteString) ?? UUID().uuidString
        return MangaChapterDocument(
            tid: tid,
            chapterTitle: MangaTitleCleaner.cleanThreadTitle(title),
            chapterURL: YamiboRoute.thread(url: url, page: 1, authorID: nil).url,
            pages: pages,
            html: html
        )
    }

    public func loadThreadSnapshot(url: URL) async throws -> (title: String, html: String) {
        let html = try await chapterHTML(for: url, htmlOverride: nil)
        let title = ReaderHTMLParser.extractPageTitle(from: html) ?? MangaHTMLParser.extractThreadTitle(from: html) ?? ""
        return (title, html)
    }

    private func chapterHTML(for url: URL, htmlOverride: String?) async throws -> String {
        if let htmlOverride, !htmlOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return htmlOverride
        }
        return try await client.fetchHTML(for: .thread(url: url, page: 1, authorID: nil))
    }
}
