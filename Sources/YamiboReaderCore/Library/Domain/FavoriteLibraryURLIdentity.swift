import Foundation

enum FavoriteLibraryURLIdentity {
    static func canonicalThreadURL(from url: URL) -> URL {
        let resolvedURL = URL(string: url.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL ?? url.absoluteURL
        guard let threadID = threadID(from: resolvedURL) else { return resolvedURL }

        var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)
            ?? URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme ?? YamiboRoute.baseURL.scheme
        components.host = components.host ?? YamiboRoute.baseURL.host
        components.path = "/forum.php"
        components.queryItems = [
            .init(name: "mod", value: "viewthread"),
            .init(name: "tid", value: threadID)
        ]
        return components.url ?? resolvedURL
    }

    static func canonicalThreadURLKey(for url: URL) -> String {
        canonicalThreadURL(from: url).absoluteString
    }

    static func favorite(_ favorite: Favorite, matches url: URL) -> Bool {
        favorite.url == url ||
            favorite.id == url.absoluteString ||
            canonicalThreadURLKey(for: favorite.url) == canonicalThreadURLKey(for: url)
    }

    private static func threadID(from url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tid" || $0.name == "ptid" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return url.absoluteString.range(of: #"thread-(\d+)-\d+-\d+\.html"#, options: .regularExpression)
            .flatMap { range in
                let substring = String(url.absoluteString[range])
                return substring.split(separator: "-").dropFirst().first.map(String.init)
            }
    }
}
