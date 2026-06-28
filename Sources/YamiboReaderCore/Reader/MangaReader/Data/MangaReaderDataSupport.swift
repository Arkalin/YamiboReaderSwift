import Foundation

enum MangaReaderDataSupport {
    static func normalizedChapterURL(_ url: URL) -> URL {
        YamiboRoute.thread(url: url, page: 1, authorID: nil).url
    }

    static func normalizedChapterURL(_ url: URL, tid: String) -> URL {
        let normalizedTid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTid.isEmpty else {
            return normalizedChapterURL(url)
        }

        let resolvedURL = URL(string: url.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL ?? url.absoluteURL
        var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)
            ?? URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme ?? YamiboRoute.baseURL.scheme
        components.host = components.host ?? YamiboRoute.baseURL.host
        components.path = "/forum.php"

        var items: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            items[item.name] = value
        }
        items["mod"] = "viewthread"
        items["mobile"] = "2"
        items["page"] = "1"
        items["tid"] = normalizedTid
        components.queryItems = items
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return components.url ?? normalizedChapterURL(url)
    }

    static func validateReadableMangaHTML(_ html: String) throws {
        if MangaHTMLParser.isLoginPage(html) {
            throw YamiboError.notAuthenticated
        }
        if MangaHTMLParser.isFloodControlOrError(html) {
            throw YamiboError.floodControl
        }
    }

    static func currentMangaChapterParsingFailure() -> YamiboError {
        .parsingFailed(context: L10n.string("context.current_page_not_manga_chapter"))
    }

    static func mangaDirectoryParsingFailure() -> YamiboError {
        .parsingFailed(context: L10n.string("context.manga_directory"))
    }

    static func mapNetworkErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as YamiboError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw YamiboError.offline
            default:
                throw YamiboError.underlying(error.localizedDescription)
            }
        }
    }
}

extension String {
    var mangaReaderTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
