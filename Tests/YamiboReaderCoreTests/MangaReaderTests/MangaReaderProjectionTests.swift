import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Reader Projection")
struct MangaReaderTestsReaderProjection {
    @Test func readerProjectionStoresParsedImageContentWithoutHTML() throws {
        let url = try #require(URL(string: "https://bbs.yamibo.com/thread-700-1-1.html"))
        let imageURL = try #require(URL(string: "https://img.example.com/700-0.jpg"))

        let projection = MangaReaderProjection(
            tid: "700",
            ownerPostID: "900",
            chapterTitle: "第1话",
            chapterURL: url,
            imageURLs: [imageURL]
        )

        #expect(projection.tid == "700")
        #expect(projection.ownerPostID == "900")
        #expect(projection.chapterTitle == "第1话")
        #expect(projection.chapterURL == url)
        #expect(projection.imageURLs == [imageURL])
    }

    @Test func readerProjectionFallsBackToTIDWhenOwnerPostIDIsBlank() throws {
        let url = try #require(URL(string: "https://bbs.yamibo.com/thread-701-1-1.html"))

        let projection = MangaReaderProjection(
            tid: "701",
            ownerPostID: "  ",
            chapterTitle: "第2话",
            chapterURL: url,
            imageURLs: []
        )

        #expect(projection.ownerPostID == "701")
    }
}
