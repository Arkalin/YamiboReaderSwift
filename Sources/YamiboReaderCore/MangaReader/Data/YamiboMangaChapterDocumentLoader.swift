import Foundation

public struct YamiboMangaChapterDocumentLoader: MangaChapterDocumentLoading {
    public var client: YamiboClient

    public init(client: YamiboClient) {
        self.client = client
    }

    public func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        let chapterURL = MangaReaderDataSupport.normalizedChapterURL(url)

        return try await MangaReaderDataSupport.mapNetworkErrors {
            let html = try await client.fetchHTML(url: chapterURL)
            try MangaReaderDataSupport.validateReadableMangaHTML(html)

            guard let tid = MangaTitleCleaner.extractTid(from: chapterURL.absoluteString)?.mangaReaderTrimmedNonEmpty else {
                throw MangaReaderDataSupport.currentMangaChapterParsingFailure()
            }

            let rawTitle = MangaHTMLParser.extractThreadTitle(from: html)?.mangaReaderTrimmedNonEmpty ?? tid
            let chapterTitle = MangaTitleCleaner.cleanThreadTitle(rawTitle).mangaReaderTrimmedNonEmpty
                ?? rawTitle.mangaReaderTrimmedNonEmpty
                ?? tid
            let imageURLs = MangaHTMLParser.extractImageURLs(from: html, baseURL: chapterURL)
            guard !imageURLs.isEmpty else {
                throw MangaReaderDataSupport.currentMangaChapterParsingFailure()
            }

            return MangaChapterDocument(
                tid: tid,
                ownerPostID: MangaHTMLParser.extractFirstPostID(from: html),
                chapterTitle: chapterTitle,
                chapterURL: chapterURL,
                imageURLs: imageURLs
            )
        }
    }
}
