import Foundation

public struct ReleaseNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String { htmlURL.absoluteString }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let publishedAt: Date?
    public let htmlURL: URL

    public init(
        tagName: String,
        name: String?,
        body: String?,
        publishedAt: Date?,
        htmlURL: URL
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
    }

    public var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return tagName
    }

    public var displayBody: String? {
        guard let body else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }
}

public struct ReleaseNotesService: Sendable {
    public static let defaultLimit = 5

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchRecentReleases(limit: Int = Self.defaultLimit) async throws -> [ReleaseNote] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/Arkalin/YamiboReaderSwift/releases"
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(limit))
        ]

        guard let url = components.url else {
            throw YamiboError.invalidResponse(statusCode: nil)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("YamiboReader", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YamiboError.invalidResponse(statusCode: nil)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw YamiboError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ReleaseNote].self, from: data)
    }
}
