import Foundation
import YamiboReaderCore

struct MangaProbeSnapshot: Equatable, Sendable {
    var title: String?
    var html: String?
    var sectionName: String?
    var isAnnouncement: Bool
    var imageURLs: [URL]
    var baseURL: URL

    init(
        title: String?,
        html: String?,
        sectionName: String?,
        isAnnouncement: Bool,
        imageURLs: [URL],
        baseURL: URL
    ) {
        self.title = title
        self.html = html
        self.sectionName = sectionName
        self.isAnnouncement = isAnnouncement
        self.imageURLs = imageURLs
        self.baseURL = baseURL
    }

    init(html: String, title: String?, fallbackTitle: String, baseURL: URL) {
        self.html = html
        self.sectionName = MangaHTMLParser.extractSectionName(from: html)
        self.isAnnouncement = MangaHTMLParser.isAnnouncement(from: html)
        self.imageURLs = MangaHTMLParser.extractImageURLs(from: html, baseURL: baseURL)
        self.baseURL = baseURL
        self.title = MangaHTMLParser.extractThreadTitle(from: html) ?? title ?? fallbackTitle
    }
}

enum MangaProbeClassification: Equatable, Sendable {
    case success(MangaProbePayload)
    case notManga
    case noImages
}

enum MangaProbeClassifier {
    static func classify(_ snapshot: MangaProbeSnapshot) -> MangaProbeClassification {
        if snapshot.isAnnouncement {
            return .notManga
        }

        if let sectionName = snapshot.sectionName,
           !MangaHTMLParser.isAllowedMangaSection(sectionName) {
            return .notManga
        }

        if let html = snapshot.html,
           !MangaHTMLParser.isLikelyMangaThread(title: snapshot.title, html: html) {
            return .notManga
        }

        guard !snapshot.imageURLs.isEmpty else {
            return .noImages
        }

        return .success(
            MangaProbePayload(
                images: snapshot.imageURLs,
                title: snapshot.title ?? "",
                html: snapshot.html,
                sectionName: snapshot.sectionName
            )
        )
    }
}
