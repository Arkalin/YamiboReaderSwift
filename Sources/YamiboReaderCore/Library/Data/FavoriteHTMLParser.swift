import Foundation
import SwiftSoup

public enum FavoriteHTMLParser {
    public static func parseFavorites(from html: String) -> [Favorite] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }
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
            return favorites
        }

        let links = (try? document.select("a[href*='viewthread'], a[href*='thread-']")) ?? Elements()
        for link in links {
            let href = ((try? link.attr("href")) ?? "")
            guard let url = HTMLTextExtractor.absoluteURL(from: href) else { continue }
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
            favorites.append(Favorite(title: title, url: url))
        }

        return favorites
    }

    private static func parseFavorite(from item: Element, seen: inout Set<String>) -> Favorite? {
        guard let link = findFavoriteLink(in: item) else { return nil }
        let href = ((try? link.attr("href")) ?? "")
        guard let url = HTMLTextExtractor.absoluteURL(from: href) else { return nil }

        let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { return nil }

        let remoteFavoriteID = extractRemoteFavoriteID(from: item)
        return Favorite(title: title, url: url, remoteFavoriteID: remoteFavoriteID)
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
}
