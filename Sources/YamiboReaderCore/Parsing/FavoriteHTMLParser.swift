import Foundation

public enum FavoriteHTMLParser {
    public static func parseFavorites(from html: String) -> [Favorite] {
        let patterns = [
            #"<a[^>]*href="([^"]*(?:viewthread|thread-)[^"]*)"[^>]*>(.*?)</a>"#,
            #"<a[^>]*href='([^']*(?:viewthread|thread-)[^']*)'[^>]*>(.*?)</a>"#
        ]

        var favorites: [Favorite] = []
        var seen = Set<String>()

        for pattern in patterns {
            for groups in HTMLTextExtractor.matches(pattern: pattern, in: html) where groups.count >= 3 {
                let href = groups[1]
                guard let url = HTMLTextExtractor.absoluteURL(from: href) else { continue }
                let title = HTMLTextExtractor.stripTags(groups[2])
                guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
                favorites.append(Favorite(title: title, url: url))
            }
        }

        return favorites
    }
}
