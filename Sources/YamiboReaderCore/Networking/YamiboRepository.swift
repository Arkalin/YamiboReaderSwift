import Foundation

public actor YamiboRepository {
    private let client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func fetchFavorites(page: Int = 1) async throws -> [Favorite] {
        let html = try await client.fetchHTML(for: .favorites(page: page))
        let favorites = FavoriteHTMLParser.parseFavorites(from: html)
        if favorites.isEmpty {
            throw inferContentError(from: html, fallback: .parsingFailed(context: "收藏页"))
        }
        return favorites
    }

    public func fetchMangaTagList(tagID: String, page: Int = 1) async throws -> [MangaChapter] {
        let html = try await client.fetchHTML(
            for: .tag(id: tagID, page: page),
            userAgent: YamiboDefaults.desktopTagUserAgent
        )
        let chapters = MangaHTMLParser.parseListHTML(html)
        if chapters.isEmpty {
            throw inferContentError(from: html, fallback: .parsingFailed(context: "漫画目录"))
        }
        return chapters
    }

    public func searchManga(keyword: String, forumID: String = "30") async throws -> [MangaChapter] {
        let html = try await client.fetchHTML(for: .search(keyword: keyword, forumID: forumID))
        if MangaHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }
        return MangaHTMLParser.parseListHTML(html)
    }

    private func inferContentError(from html: String, fallback: YamiboError) -> YamiboError {
        if isLoginPage(html) {
            return .notAuthenticated
        }
        if MangaHTMLParser.isFloodControlOrError(html) {
            return .floodControl
        }
        return fallback
    }

    private func isLoginPage(_ html: String) -> Bool {
        let markers = [
            "请先登录",
            "登录后",
            "<title>登录 -",
            "member.php?mod=logging&action=login",
            "id=\"member_login\"",
            "class=\"pg_logging\""
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }
}
