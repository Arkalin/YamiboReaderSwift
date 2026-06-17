import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Chapter Document")
struct MangaReaderTestsChapterDocument {
    @Test func chapterDocumentStoresParsedImageContentWithoutHTML() throws {
        let url = try #require(URL(string: "https://bbs.yamibo.com/thread-700-1-1.html"))
        let imageURL = try #require(URL(string: "https://img.example.com/700-0.jpg"))

        let document = MangaChapterDocument(
            tid: "700",
            ownerPostID: "900",
            chapterTitle: "第1话",
            chapterURL: url,
            imageURLs: [imageURL]
        )

        #expect(document.tid == "700")
        #expect(document.ownerPostID == "900")
        #expect(document.chapterTitle == "第1话")
        #expect(document.chapterURL == url)
        #expect(document.imageURLs == [imageURL])
    }

    @Test func chapterDocumentFallsBackToTIDWhenOwnerPostIDIsBlank() throws {
        let url = try #require(URL(string: "https://bbs.yamibo.com/thread-701-1-1.html"))

        let document = MangaChapterDocument(
            tid: "701",
            ownerPostID: "  ",
            chapterTitle: "第2话",
            chapterURL: url,
            imageURLs: []
        )

        #expect(document.ownerPostID == "701")
    }
}
