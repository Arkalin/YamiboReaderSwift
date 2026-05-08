import Foundation
import Testing
@testable import YamiboReaderCore

@Test func mangaChapterWindowCreatesInitialSnapshotAndResolvesReadingPosition() {
    let directory = makeMangaDirectory(tids: ["700", "701"])
    let document = makeMangaChapterDocument(tid: "700", pageCount: 3)

    let window = MangaChapterWindow(
        directory: directory,
        initialDocument: document,
        position: MangaReadingPosition(tid: "700", localIndex: 1)
    )

    #expect(window.snapshot.pages.map(\.id) == ["700#0", "700#1", "700#2"])
    #expect(window.snapshot.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 1))
    #expect(window.snapshot.resolvedPageIndex == 1)
}

@Test func mangaChapterWindowInsertsAdjacentNextDocumentAndPreservesReadingPosition() {
    let directory = makeMangaDirectory(tids: ["700", "701"])
    let currentPosition = MangaReadingPosition(tid: "700", localIndex: 1)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: currentPosition
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "701", pageCount: 3),
        preserving: currentPosition
    )

    if case let .changed(snapshot) = result {
        #expect(snapshot.pages.map(\.id) == ["700#0", "700#1", "701#0", "701#1", "701#2"])
        #expect(snapshot.resolvedPosition == currentPosition)
        #expect(snapshot.resolvedPageIndex == 1)
    } else {
        Issue.record("Expected adjacent insertion to change the Manga Chapter Window")
    }
}

@Test func mangaChapterWindowInsertsAdjacentPreviousDocumentAndShiftsResolvedPageIndex() {
    let directory = makeMangaDirectory(tids: ["699", "700"])
    let currentPosition = MangaReadingPosition(tid: "700", localIndex: 1)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: currentPosition
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "699", pageCount: 3),
        preserving: currentPosition
    )

    if case let .changed(snapshot) = result {
        #expect(snapshot.pages.map(\.id) == ["699#0", "699#1", "699#2", "700#0", "700#1"])
        #expect(snapshot.resolvedPosition == currentPosition)
        #expect(snapshot.resolvedPageIndex == 4)
    } else {
        Issue.record("Expected adjacent previous insertion to change the Manga Chapter Window")
    }
}

@Test func mangaChapterWindowRejectsDuplicateChapterIdentity() {
    let directory = makeMangaDirectory(tids: ["700", "701"])
    let position = MangaReadingPosition(tid: "700", localIndex: 0)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: position
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "700", pageCount: 4),
        preserving: position
    )

    if case let .unchanged(snapshot, reason) = result {
        #expect(reason == .duplicateChapter)
        #expect(snapshot.pages.map(\.id) == ["700#0", "700#1"])
    } else {
        Issue.record("Expected duplicate chapter insertion to be unchanged")
    }
}

@Test func mangaChapterWindowRejectsUnknownChapterForAdjacentInsertion() {
    let directory = makeMangaDirectory(tids: ["700", "701"])
    let position = MangaReadingPosition(tid: "700", localIndex: 0)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: position
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "999", pageCount: 1),
        preserving: position
    )

    if case let .unchanged(snapshot, reason) = result {
        #expect(reason == .unknownChapter)
        #expect(snapshot.pages.map(\.id) == ["700#0", "700#1"])
    } else {
        Issue.record("Expected unknown adjacent insertion to be unchanged")
    }
}

@Test func mangaChapterWindowRejectsKnownButNonAdjacentInsertion() {
    let directory = makeMangaDirectory(tids: ["700", "701", "702"])
    let position = MangaReadingPosition(tid: "700", localIndex: 0)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: position
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "702", pageCount: 1),
        preserving: position
    )

    if case let .unchanged(snapshot, reason) = result {
        #expect(reason == .notAdjacent)
        #expect(snapshot.pages.map(\.id) == ["700#0", "700#1"])
    } else {
        Issue.record("Expected known non-adjacent insertion to be unchanged")
    }
}

@Test func mangaChapterWindowResetsToUnknownChapterDocument() {
    let directory = makeMangaDirectory(tids: ["700"])
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 2),
        position: MangaReadingPosition(tid: "700", localIndex: 0)
    )

    let snapshot = window.reset(
        to: makeMangaChapterDocument(tid: "999", pageCount: 2),
        position: MangaReadingPosition(tid: "999", localIndex: 1)
    )

    #expect(snapshot.pages.map(\.id) == ["999#0", "999#1"])
    #expect(snapshot.resolvedPosition == MangaReadingPosition(tid: "999", localIndex: 1))
    #expect(snapshot.resolvedPageIndex == 1)
}

@Test func mangaChapterWindowClampsReadingPositionToNearestValidPage() {
    let directory = makeMangaDirectory(tids: ["700"])
    let window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 3),
        position: MangaReadingPosition(tid: "700", localIndex: 99)
    )

    #expect(window.snapshot.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 2))
    #expect(window.snapshot.resolvedPageIndex == 2)
}

@Test func mangaChapterWindowUpdateDirectoryReordersExistingDocuments() {
    let initialDirectory = makeMangaDirectory(tids: ["700", "701"])
    let position = MangaReadingPosition(tid: "700", localIndex: 0)
    var window = MangaChapterWindow(
        directory: initialDirectory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 1),
        position: position
    )
    _ = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "701", pageCount: 1),
        preserving: position
    )

    let snapshot = window.updateDirectory(
        makeMangaDirectory(tids: ["701", "700"]),
        preserving: position
    )

    #expect(snapshot.pages.map(\.id) == ["701#0", "700#0"])
    #expect(snapshot.resolvedPosition == position)
    #expect(snapshot.resolvedPageIndex == 1)
}

@Test func mangaChapterWindowTrimsWithoutRemovingPreservedReadingPosition() {
    let directory = makeMangaDirectory(tids: ["700", "701", "702"])
    let position = MangaReadingPosition(tid: "701", localIndex: 0)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 1),
        position: MangaReadingPosition(tid: "700", localIndex: 0),
        maxLoadedDocuments: 2
    )
    _ = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "701", pageCount: 1),
        preserving: position
    )

    let result = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "702", pageCount: 1),
        preserving: position
    )

    if case let .changed(snapshot) = result {
        #expect(snapshot.pages.map(\.id) == ["701#0", "702#0"])
        #expect(snapshot.resolvedPosition == position)
        #expect(snapshot.resolvedPageIndex == 0)
    } else {
        Issue.record("Expected adjacent insertion with trimming to change the Manga Chapter Window")
    }
}

@Test func mangaChapterWindowFindsAdjacentChaptersFromPositionAndLoadedRange() {
    let directory = makeMangaDirectory(tids: ["699", "700", "701"])
    let position = MangaReadingPosition(tid: "700", localIndex: 0)
    var window = MangaChapterWindow(
        directory: directory,
        initialDocument: makeMangaChapterDocument(tid: "700", pageCount: 1),
        position: position
    )

    #expect(window.adjacentChapter(from: position, delta: -1)?.tid == "699")
    #expect(window.adjacentChapter(from: position, delta: 1)?.tid == "701")
    #expect(window.adjacentChapterForLoadedRange(delta: -1)?.tid == "699")
    #expect(window.adjacentChapterForLoadedRange(delta: 1)?.tid == "701")

    _ = window.insertAdjacentDocument(
        makeMangaChapterDocument(tid: "701", pageCount: 1),
        preserving: position
    )

    #expect(window.adjacentChapterForLoadedRange(delta: 1) == nil)
}

private func makeMangaDirectory(tids: [String]) -> MangaDirectory {
    MangaDirectory(
        cleanBookName: "测试漫画",
        strategy: .links,
        sourceKey: "测试漫画",
        chapters: tids.enumerated().map { index, tid in
            MangaChapter(
                tid: tid,
                rawTitle: "第\(index + 1)话",
                chapterNumber: Double(index + 1),
                url: makeMangaChapterURL(tid: tid)
            )
        }
    )
}

private func makeMangaChapterDocument(tid: String, pageCount: Int) -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: makeMangaChapterURL(tid: tid),
        pages: (0 ..< pageCount).map { URL(string: "https://img.example.com/\(tid)-\($0).jpg")! },
        html: ""
    )
}

private func makeMangaChapterURL(tid: String) -> URL {
    URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
}
