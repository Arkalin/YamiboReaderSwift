import Foundation

public actor FavoriteRepository {
    private let client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func fetchFavorites(page: Int = 1) async throws -> [Favorite] {
        let html = try await client.fetchHTML(for: .favorites(page: page))
        let favorites = FavoriteHTMLParser.parseFavorites(from: html)
        if favorites.isEmpty {
            throw inferContentError(from: html, fallback: .parsingFailed(context: L10n.string("context.favorites_page")))
        }
        return favorites
    }

    public func fetchFavoritePage(page: Int = 1) async throws -> FavoriteHTMLParser.FavoritePageResult {
        let html = try await client.fetchHTML(for: .favorites(page: page))
        let parsed = FavoriteHTMLParser.parseFavoritePage(from: html)
        if parsed.favorites.isEmpty {
            throw inferContentError(from: html, fallback: .parsingFailed(context: L10n.string("context.favorites_page")))
        }
        return parsed
    }

    public func addThreadFavorite(threadURL: URL, formHash preferredFormHash: String? = nil) async throws -> Favorite? {
        guard let tid = Self.threadID(from: threadURL) else {
            throw YamiboError.missingFavoriteThreadID
        }
        let formHash = try await ensureFormHash(preferred: preferredFormHash)
        let responseHTML = try await client.fetchHTML(for: .threadFavorite(tid: tid, formHash: formHash))

        if isLoginPage(responseHTML) {
            throw YamiboError.notAuthenticated
        }
        guard isFavoriteAddSuccess(responseHTML) else {
            throw YamiboError.favoriteAddFailed
        }

        return try? await remoteFavorite(for: threadURL)
    }

    public func remoteFavorite(for threadURL: URL, maxPages: Int = 30) async throws -> Favorite? {
        guard maxPages > 0 else { return nil }
        for page in 1 ... maxPages {
            let html = try await client.fetchHTML(for: .favorites(page: page))
            let parsed = FavoriteHTMLParser.parseFavoritePage(from: html)
            if parsed.favorites.isEmpty {
                let error = inferContentError(
                    from: html,
                    fallback: .parsingFailed(context: L10n.string("context.favorites_page"))
                )
                switch error {
                case .parsingFailed:
                    return nil
                default:
                    throw error
                }
            }
            if let favorite = parsed.favorites.first(where: { Self.sameThread($0.url, threadURL) }) {
                return favorite
            }
            if parsed.currentPage >= parsed.totalPages || page >= parsed.totalPages {
                return nil
            }
        }
        return nil
    }

    public func deleteFavorite(remoteFavoriteID: String) async throws {
        let formHTML = try await client.fetchHTML(for: .favoriteDeleteForm, userAgent: YamiboDefaults.desktopTagUserAgent)
        if isLoginPage(formHTML) {
            throw YamiboError.notAuthenticated
        }
        guard let formHash = extractFormHash(from: formHTML) else {
            throw YamiboError.missingFavoriteDeleteToken
        }

        let responseHTML = try await client.submitForm(
            for: .favoriteDelete,
            fields: [
                ("formhash", formHash),
                ("delfavorite", "true"),
                ("deletesubmit", "true"),
                ("favorite[]", remoteFavoriteID)
            ],
            userAgent: YamiboDefaults.desktopTagUserAgent
        )

        if isLoginPage(responseHTML) {
            throw YamiboError.notAuthenticated
        }
        guard isFavoriteDeleteSuccess(responseHTML) else {
            throw YamiboError.favoriteDeleteFailed
        }
    }

    private func inferContentError(from html: String, fallback: YamiboError) -> YamiboError {
        if isLoginPage(html) {
            return .notAuthenticated
        }
        if isFloodControlOrError(html) {
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

    private func isFloodControlOrError(_ html: String) -> Bool {
        guard !html.contains("没有找到匹配结果") else { return false }
        return html.contains("只能进行一次搜索")
            || html.contains("防灌水")
            || html.contains("指定的搜索词长度")
    }

    private func extractFormHash(from html: String) -> String? {
        HTMLTextExtractor.firstMatch(pattern: #"name=["']formhash["']\s+value=["']([^"']+)["']"#, in: html)?.dropFirst().first
            ?? HTMLTextExtractor.firstMatch(pattern: #"formhash=([a-zA-Z0-9]+)"#, in: html)?.dropFirst().first
    }

    private func ensureFormHash(preferred: String?) async throws -> String {
        if let formHash = preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
           !formHash.isEmpty {
            return formHash
        }

        let profileHTML = try await client.fetchHTML(for: .currentProfile)
        if isLoginPage(profileHTML) {
            throw YamiboError.notAuthenticated
        }
        guard let formHash = extractFormHash(from: profileHTML) else {
            throw YamiboError.missingFavoriteAddToken
        }
        return formHash
    }

    private func isFavoriteAddSuccess(_ html: String) -> Bool {
        let markers = [
            "收藏成功",
            "信息收藏成功",
            "已收藏",
            "您已收藏过",
            "succeed",
            "操作成功"
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    private func isFavoriteDeleteSuccess(_ html: String) -> Bool {
        let markers = [
            "成功",
            "succeed",
            "操作成功",
            "收藏删除成功"
        ]
        return markers.contains { html.localizedCaseInsensitiveContains($0) }
    }

    private static func threadID(from url: URL) -> String? {
        YamiboThreadURLCanonicalizer.threadID(from: url)
    }

    private static func sameThread(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsThreadID = threadID(from: lhs),
              let rhsThreadID = threadID(from: rhs) else {
            return lhs.absoluteString == rhs.absoluteString
        }
        return lhsThreadID == rhsThreadID
    }
}
