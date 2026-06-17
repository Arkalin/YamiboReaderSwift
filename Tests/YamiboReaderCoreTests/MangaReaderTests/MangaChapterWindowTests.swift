import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Chapter Window")
struct MangaReaderTestsChapterWindow {
    @Test func chapterWindowRejectsEmptyDocuments() {
        #expect(MangaChapterWindow(documents: []) == nil)
    }

    @Test func chapterWindowClampsInitialPositionToAvailablePage() throws {
        let document = try makeDocument(tid: "700", pageCount: 2)

        let window = MangaChapterWindow(
            initialDocument: document,
            position: MangaReadingPosition(tid: "700", localIndex: 99)
        )

        #expect(window.documents == [document])
        #expect(window.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 1))
    }

    @Test func chapterWindowClearsUnknownOrEmptyPositions() throws {
        let loadedDocument = try makeDocument(tid: "700", pageCount: 2)
        let emptyDocument = try makeDocument(tid: "701", pageCount: 0)
        let window = try #require(MangaChapterWindow(documents: [loadedDocument, emptyDocument]))

        #expect(window.clampedPosition(MangaReadingPosition(tid: "999", localIndex: 0)) == nil)
        #expect(window.clampedPosition(MangaReadingPosition(tid: "701", localIndex: 0)) == nil)
    }

    @Test func chapterWindowUpdatesPositionThroughClamp() throws {
        let document = try makeDocument(tid: "700", pageCount: 3)
        var window = MangaChapterWindow(initialDocument: document)

        window.updatePosition(MangaReadingPosition(tid: "700", localIndex: 4))

        #expect(window.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 2))
    }
}

private func makeDocument(tid: String, pageCount: Int) throws -> MangaChapterDocument {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html"))
    let imageURLs = try (0..<pageCount).map { index in
        try #require(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
    }
    return MangaChapterDocument(
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: chapterURL,
        imageURLs: imageURLs
    )
}
