import Foundation

public enum FavoriteHTMLParser {
    public struct FavoritePageResult: Sendable {
        public var favorites: [Favorite]
        public var currentPage: Int
        public var totalPages: Int

        public init(favorites: [Favorite], currentPage: Int = 1, totalPages: Int = 1) {
            self.favorites = favorites
            self.currentPage = max(1, currentPage)
            self.totalPages = max(1, totalPages)
        }
    }

    public static func parseFavorites(from html: String) -> [Favorite] {
        parseFavoritePage(from: html).favorites
    }

    public static func parseFavoritePage(from html: String) -> FavoritePageResult {
        guard let document = try? KannaSoup.parse(html) else {
            return FavoritePageResult(favorites: [])
        }
        var favorites: [Favorite] = []
        var seen = Set<String>()

        let selectors = [
            ".sclist li",
            "li.sclist",
            ".fav_list li",
            ".favorite li"
        ]

        for selector in selectors {
            let items = (try? document.select(selector)) ?? Elements()
            guard !items.isEmpty else { continue }

            for item in items {
                guard let favorite = parseFavorite(from: item, seen: &seen) else { continue }
                favorites.append(favorite)
            }
            return FavoritePageResult(
                favorites: favorites,
                currentPage: parseCurrentPage(in: document),
                totalPages: parseTotalPages(in: document)
            )
        }

        let links = (try? document.select("a[href*='viewthread'], a[href*='thread-']")) ?? Elements()
        for link in links {
            let href = ((try? link.attr("href")) ?? "")
            guard let url = HTMLTextExtractor.absoluteURL(from: href) else { continue }
            guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: url) else { continue }
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(threadID).inserted else { continue }
            favorites.append(Favorite(title: title, threadID: threadID))
        }

        return FavoritePageResult(
            favorites: favorites,
            currentPage: parseCurrentPage(in: document),
            totalPages: parseTotalPages(in: document)
        )
    }

    private static func parseFavorite(from item: Element, seen: inout Set<String>) -> Favorite? {
        guard let link = findFavoriteLink(in: item) else { return nil }
        let href = ((try? link.attr("href")) ?? "")
        guard let url = HTMLTextExtractor.absoluteURL(from: href) else { return nil }
        guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: url) else { return nil }

        let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, seen.insert(threadID).inserted else { return nil }

        let remoteFavoriteID = extractRemoteFavoriteID(from: item)
        return Favorite(title: title, threadID: threadID, remoteFavoriteID: remoteFavoriteID)
    }

    private static func findFavoriteLink(in item: Element) -> Element? {
        let candidates = (try? item.select("a[href*='viewthread'], a[href*='thread-']")) ?? Elements()
        return candidates.first { element in
            let className = ((try? element.className()) ?? "")
            return !className.localizedCaseInsensitiveContains("mdel")
        }
    }

    private static func extractRemoteFavoriteID(from item: Element) -> String? {
        let deleteLink = (try? item.select("a.mdel, a[href*='favid=']"))?.first()
        let href = ((try? deleteLink?.attr("href")) ?? "")
        return HTMLTextExtractor.firstMatch(pattern: #"favid=(\d+)"#, in: href)?.dropFirst().first
    }

    private static func parseCurrentPage(in document: Document) -> Int {
        let currentText = ((try? document.select(".pg strong").first()?.text()) ?? "")
        return HTMLTextExtractor.firstMatch(pattern: #"(\d+)"#, in: currentText)?
            .dropFirst()
            .first
            .flatMap(Int.init) ?? 1
    }

    private static func parseTotalPages(in document: Document) -> Int {
        guard let pager = try? document.select(".pg").first() else { return 1 }
        let pagerText = ((try? pager.text()) ?? "")
        let explicitTotal = HTMLTextExtractor.firstMatch(pattern: #"共\s*(\d+)\s*页"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
            ?? HTMLTextExtractor.firstMatch(pattern: #"/\s*(\d+)\s*页"#, in: pagerText)?
            .dropFirst()
            .first
            .flatMap(Int.init)
        if let explicitTotal {
            return max(1, explicitTotal)
        }

        let linkedPages = ((try? pager.select("a[href*='page=']").array()) ?? [])
            .compactMap { element -> Int? in
                let href = (try? element.attr("href")) ?? ""
                return HTMLTextExtractor.firstMatch(pattern: #"page=(\d+)"#, in: href)?
                    .dropFirst()
                    .first
                    .flatMap(Int.init)
            }
        return max(1, linkedPages.max() ?? parseCurrentPage(in: document))
    }
}
