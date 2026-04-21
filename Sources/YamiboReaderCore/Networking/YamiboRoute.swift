import Foundation

public enum YamiboRoute: Sendable {
    public static let baseURL = URL(string: "https://bbs.yamibo.com")!

    case favorites(page: Int)
    case favoriteDeleteForm
    case favoriteDelete
    case tag(id: String, page: Int)
    case search(keyword: String, forumID: String)
    case searchPage(searchID: String, page: Int)
    case thread(url: URL, page: Int, authorID: String?)

    public var url: URL {
        switch self {
        case let .favorites(page):
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/home.php"
            components.queryItems = [
                .init(name: "mod", value: "space"),
                .init(name: "do", value: "favorite"),
                .init(name: "view", value: "me"),
                .init(name: "type", value: "thread"),
                .init(name: "mobile", value: "2"),
                .init(name: "page", value: String(page))
            ]
            return components.url!
        case .favoriteDeleteForm:
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/misc.php"
            components.queryItems = [
                .init(name: "mod", value: "faq")
            ]
            return components.url!
        case .favoriteDelete:
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/home.php"
            components.queryItems = [
                .init(name: "mod", value: "spacecp"),
                .init(name: "ac", value: "favorite"),
                .init(name: "op", value: "delete"),
                .init(name: "type", value: "all"),
                .init(name: "checkall", value: "1")
            ]
            return components.url!
        case let .tag(id, page):
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/misc.php"
            components.queryItems = [
                .init(name: "mod", value: "tag"),
                .init(name: "type", value: "thread"),
                .init(name: "mobile", value: "no"),
                .init(name: "id", value: id),
                .init(name: "page", value: String(page))
            ]
            return components.url!
        case let .search(keyword, forumID):
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/search.php"
            components.percentEncodedQuery = [
                "mod=forum",
                "searchsubmit=yes",
                "mobile=2",
                "srchfid%5B%5D=\(forumID)",
                "srchtxt=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)",
                "srchtype=title"
            ].joined(separator: "&")
            return components.url!
        case let .searchPage(searchID, page):
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.path = "/search.php"
            components.queryItems = [
                .init(name: "mod", value: "forum"),
                .init(name: "orderby", value: "dateline"),
                .init(name: "ascdesc", value: "desc"),
                .init(name: "searchsubmit", value: "yes"),
                .init(name: "mobile", value: "2"),
                .init(name: "searchid", value: searchID),
                .init(name: "page", value: String(page))
            ]
            return components.url!
        case let .thread(url, page, authorID):
            var components = URLComponents(
                url: URL(string: url.absoluteString, relativeTo: Self.baseURL)?.absoluteURL ?? url.absoluteURL,
                resolvingAgainstBaseURL: false
            ) ?? URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            if components.host == nil {
                components.scheme = Self.baseURL.scheme
                components.host = Self.baseURL.host
            }
            if components.path.isEmpty {
                components.path = "/forum.php"
            }

            var items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            items["mod"] = items["mod"] ?? "viewthread"
            items["page"] = String(max(1, page))
            items["mobile"] = items["mobile"] ?? "2"
            if let authorID, !authorID.isEmpty {
                items["authorid"] = authorID
            }
            components.queryItems = items
                .map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
            return components.url!
        }
    }
}
