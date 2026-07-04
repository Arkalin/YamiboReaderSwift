import Foundation

public struct MangaChapter: Codable, Hashable, Identifiable, Sendable {
    public let tid: String
    public var rawTitle: String
    public var chapterNumber: Double
    public var url: URL
    public var view: Int
    public var authorUID: String?
    public var authorName: String?
    public var groupIndex: Int
    public var publishTime: Date?

    public var id: String { tid }

    public init(
        tid: String,
        rawTitle: String,
        chapterNumber: Double,
        url: URL,
        view: Int = 1,
        authorUID: String? = nil,
        authorName: String? = nil,
        groupIndex: Int = 0,
        publishTime: Date? = nil
    ) {
        self.tid = tid
        self.rawTitle = rawTitle
        self.chapterNumber = chapterNumber
        self.url = url
        self.view = max(1, view)
        self.authorUID = authorUID
        self.authorName = authorName
        self.groupIndex = groupIndex
        self.publishTime = publishTime
    }

    public static func view(from url: URL) -> Int {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
            .flatMap(Int.init) ?? 1
        return max(1, page)
    }
}
