import Foundation
import Testing
@testable import YamiboReaderCore

@Test func mangaReadingSessionPrepareLoadsInitialDocumentResolvesDirectoryAndClampsInitialPage() async throws {
    let context = makeMangaLaunchContext(tid: "700", initialPage: 99)
    let document = makeMangaChapterDocument(tid: "700", pageCount: 3)
    let directory = makeMangaDirectory(tids: ["700", "701"])
    let resolver = StubMangaDirectoryResolver(directory: directory)

    let session = MangaReadingSession(
        context: context,
        documentLoader: { _, _ in document },
        directoryResolver: resolver,
        maxLoadedDocuments: 10
    )

    let snapshot = try await session.prepare()

    #expect(snapshot.directory == directory)
    #expect(snapshot.window.pages.map(\.id) == ["700#0", "700#1", "700#2"])
    #expect(snapshot.window.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 2))
    #expect(snapshot.window.resolvedPageIndex == 2)
}

@Test func mangaReadingSessionMoveToLoadedPageUpdatesReadingPosition() async throws {
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { _, _ in makeMangaChapterDocument(tid: "700", pageCount: 3) },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()

    let snapshot = try await session.moveToLoadedPage(2)

    #expect(snapshot.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 2))
    #expect(snapshot.resolvedPageIndex == 2)
}

@Test func mangaReadingSessionPrefetchNearEndLoadsAdjacentNextWithoutMovingReadingPosition() async throws {
    let loader = MangaDocumentLoadRecorder(documents: [
        "700": makeMangaChapterDocument(tid: "700", pageCount: 10),
        "701": makeMangaChapterDocument(tid: "701", pageCount: 2),
    ])
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { url, htmlOverride in
            try await loader.load(url: url, htmlOverride: htmlOverride)
        },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700", "701"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()
    _ = try await session.moveToLoadedPage(8)

    let snapshot = try await session.prefetchIfNeeded(around: 8)

    #expect(snapshot?.pages.map(\.id) == [
        "700#0", "700#1", "700#2", "700#3", "700#4",
        "700#5", "700#6", "700#7", "700#8", "700#9",
        "701#0", "701#1",
    ])
    #expect(snapshot?.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 8))
    #expect(snapshot?.resolvedPageIndex == 8)
    #expect(await loader.loadCount(for: "701") == 1)
}

@Test func mangaReadingSessionPrefetchNearBeginningLoadsAdjacentPreviousWithoutMovingReadingPosition() async throws {
    let loader = MangaDocumentLoadRecorder(documents: [
        "700": makeMangaChapterDocument(tid: "700", pageCount: 2),
        "701": makeMangaChapterDocument(tid: "701", pageCount: 10),
    ])
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "701"),
        documentLoader: { url, htmlOverride in
            try await loader.load(url: url, htmlOverride: htmlOverride)
        },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700", "701"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()
    _ = try await session.moveToLoadedPage(1)

    let snapshot = try await session.prefetchIfNeeded(around: 1)

    #expect(snapshot?.pages.prefix(4).map(\.id) == ["700#0", "700#1", "701#0", "701#1"])
    #expect(snapshot?.resolvedPosition == MangaReadingPosition(tid: "701", localIndex: 1))
    #expect(snapshot?.resolvedPageIndex == 3)
    #expect(await loader.loadCount(for: "700") == 1)
}

@Test func mangaReadingSessionConcurrentPrefetchForSameTIDReusesLoadTaskAndAvoidsDuplicatePages() async throws {
    let loader = MangaDocumentLoadRecorder(
        documents: [
            "700": makeMangaChapterDocument(tid: "700", pageCount: 10),
            "701": makeMangaChapterDocument(tid: "701", pageCount: 2),
        ],
        delayNanoseconds: 50_000_000
    )
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { url, htmlOverride in
            try await loader.load(url: url, htmlOverride: htmlOverride)
        },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700", "701"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()
    _ = try await session.moveToLoadedPage(8)

    async let first = session.prefetchIfNeeded(around: 8)
    async let second = session.prefetchIfNeeded(around: 8)
    _ = try await (first, second)

    let snapshot = try await session.moveToLoadedPage(8)
    #expect(snapshot.pages.map(\.id).filter { $0.hasPrefix("701#") } == ["701#0", "701#1"])
    #expect(Set(snapshot.pages.map(\.id)).count == snapshot.pages.count)
    #expect(await loader.loadCount(for: "701") == 1)
}

@Test func mangaReadingSessionUpdateDirectoryReordersWindowAndPreservesCurrentPosition() async throws {
    let loader = MangaDocumentLoadRecorder(documents: [
        "700": makeMangaChapterDocument(tid: "700", pageCount: 1),
        "701": makeMangaChapterDocument(tid: "701", pageCount: 1),
    ])
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { url, htmlOverride in
            try await loader.load(url: url, htmlOverride: htmlOverride)
        },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700", "701"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()
    _ = try await session.prefetchIfNeeded(around: 0)

    let snapshot = try await session.updateDirectory(
        makeMangaDirectory(tids: ["701", "700"]),
        preserving: MangaReadingPosition(tid: "700", localIndex: 0)
    )

    #expect(snapshot.pages.map(\.id) == ["701#0", "700#0"])
    #expect(snapshot.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 0))
    #expect(snapshot.resolvedPageIndex == 1)
}

@Test func mangaReadingSessionFarDirectoryJumpReturnsReopenNativeWithoutMutatingWindow() async throws {
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { _, _ in makeMangaChapterDocument(tid: "700", pageCount: 2) },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: ["700", "701", "702"])),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()

    let result = try await session.jump(
        to: makeMangaChapter(tid: "702", index: 2),
        from: MangaReadingPosition(tid: "700", localIndex: 1)
    )

    if case let .reopenNative(context) = result {
        #expect(MangaTitleCleaner.extractTid(from: context.chapterURL.absoluteString) == "702")
        #expect(context.initialPage == 0)
    } else {
        Issue.record("Expected far jump to request native reopen")
    }

    let snapshot = try await session.moveToLoadedPage(1)
    #expect(snapshot.pages.map(\.id) == ["700#0", "700#1"])
    #expect(snapshot.resolvedPosition == MangaReadingPosition(tid: "700", localIndex: 1))
}

@Test func mangaReadingSessionAdjacentJumpLoadsChapterAndBoundsWindowToPreservedChapter() async throws {
    let documents = Dictionary(uniqueKeysWithValues: (700 ... 712).map { tid in
        ("\(tid)", makeMangaChapterDocument(tid: "\(tid)", pageCount: 1))
    })
    let loader = MangaDocumentLoadRecorder(documents: documents)
    let session = MangaReadingSession(
        context: makeMangaLaunchContext(tid: "700"),
        documentLoader: { url, htmlOverride in
            try await loader.load(url: url, htmlOverride: htmlOverride)
        },
        directoryResolver: StubMangaDirectoryResolver(directory: makeMangaDirectory(tids: (700 ... 712).map(String.init))),
        maxLoadedDocuments: 10
    )
    _ = try await session.prepare()

    var latestSnapshot: MangaChapterWindowSnapshot?
    for tid in 701 ... 712 {
        let result = try await session.jump(
            to: makeMangaChapter(tid: "\(tid)", index: tid - 700),
            from: MangaReadingPosition(tid: "\(tid - 1)", localIndex: 0)
        )
        if case let .loaded(snapshot) = result {
            latestSnapshot = snapshot
        } else {
            Issue.record("Expected adjacent jump \(tid) to load")
        }
    }

    #expect(latestSnapshot?.pages.count == 10)
    #expect(latestSnapshot?.pages.first?.tid == "703")
    #expect(latestSnapshot?.pages.last?.tid == "712")
    #expect(latestSnapshot?.resolvedPosition == MangaReadingPosition(tid: "712", localIndex: 0))
    #expect(latestSnapshot?.resolvedPageIndex == 9)
}

private struct StubMangaDirectoryResolver: MangaReadingDirectoryResolving {
    var directory: MangaDirectory

    func resolveInitialDirectory(
        context: MangaLaunchContext,
        document: MangaChapterDocument
    ) async throws -> MangaDirectory {
        directory
    }
}

private actor MangaDocumentLoadRecorder {
    private var documents: [String: MangaChapterDocument]
    private var counts: [String: Int] = [:]
    private let delayNanoseconds: UInt64

    init(documents: [String: MangaChapterDocument], delayNanoseconds: UInt64 = 0) {
        self.documents = documents
        self.delayNanoseconds = delayNanoseconds
    }

    func load(url: URL, htmlOverride: String?) async throws -> MangaChapterDocument {
        let tid = MangaTitleCleaner.extractTid(from: url.absoluteString) ?? url.absoluteString
        counts[tid, default: 0] += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let document = documents[tid] else {
            throw YamiboError.parsingFailed(context: "missing document \(tid)")
        }
        return document
    }

    func loadCount(for tid: String) -> Int {
        counts[tid, default: 0]
    }
}

private func makeMangaLaunchContext(tid: String, initialPage: Int = 0) -> MangaLaunchContext {
    MangaLaunchContext(
        originalThreadURL: makeMangaChapterURL(tid: "thread"),
        chapterURL: makeMangaChapterURL(tid: tid),
        displayTitle: "测试漫画",
        source: .forum,
        initialPage: initialPage
    )
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

private func makeMangaChapter(tid: String, index: Int) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: "第\(index + 1)话",
        chapterNumber: Double(index + 1),
        url: makeMangaChapterURL(tid: tid)
    )
}

private func makeMangaChapterURL(tid: String) -> URL {
    URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
}
