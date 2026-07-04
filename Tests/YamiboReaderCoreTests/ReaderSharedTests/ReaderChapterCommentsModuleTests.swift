import Foundation
import XCTest
@testable import YamiboReaderCore

@MainActor
final class ReaderChapterCommentsModuleTests: XCTestCase {
    func testLoadUsesCachedPageWithoutCallingAdapterAgain() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["first"]))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.load(target)

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected cached chapter comments")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["first"])
        XCTAssertEqual(adapter.initialTargets, [target])
    }

    func testRefreshSuccessUpdatesCacheAndClearsErrors() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["old"])),
            .failure(TestError("refresh failed")),
            .success(makePage(target: target, bodies: ["new"]))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.refresh(target)
        XCTAssertEqual(module.refreshError, "refresh failed")

        await module.refresh(target)
        await module.load(target)

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected refreshed chapter comments")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["new"])
        XCTAssertNil(module.refreshError)
        XCTAssertEqual(adapter.initialTargets, [target, target, target])
    }

    func testRefreshFirstFailureEntersFailedState() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [.failure(TestError("initial failed"))]
        let module = adapter.makeModule()

        await module.refresh(target)

        XCTAssertEqual(module.state, .failed(target, "initial failed"))
        XCTAssertNil(module.refreshError)
    }

    func testRefreshFailureWithCachePreservesLoadedPageAndSetsRefreshError() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["cached"])),
            .failure(TestError("refresh failed"))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.refresh(target)

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected cached comments to remain visible")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["cached"])
        XCTAssertEqual(module.refreshError, "refresh failed")
    }

    func testLoadMoreSuccessAppendsPageAndUpdatesCache() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["first"], nextView: 2))
        ]
        adapter.moreResults = [
            .success(makePage(target: target, bodies: ["second"], nextView: nil))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.loadNextPage()
        await module.load(target)

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected merged chapter comments")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["first", "second"])
        XCTAssertNil(page.nextView)
        XCTAssertEqual(adapter.moreRequests, [ChapterCommentsAdapterSpy.MoreRequest(target: target, view: 2)])
    }

    func testLoadMoreFailurePreservesCurrentPageAndResetsLoadingFlag() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["first"], nextView: 2))
        ]
        adapter.moreResults = [.failure(TestError("more failed"))]
        let module = adapter.makeModule()

        await module.load(target)
        await module.loadNextPage()

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected current comments to remain visible")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["first"])
        XCTAssertFalse(module.isLoadingMore)
        XCTAssertEqual(module.loadMoreError, "more failed")
    }

    func testNilTargetIsUnsupported() async throws {
        let adapter = ChapterCommentsAdapterSpy()
        let module = adapter.makeModule()

        await module.load(nil)

        XCTAssertEqual(module.state, .unsupported)
        XCTAssertTrue(adapter.initialTargets.isEmpty)
    }

    func testRefreshNilTargetIsUnsupported() async throws {
        let adapter = ChapterCommentsAdapterSpy()
        let module = adapter.makeModule()

        await module.refresh(nil)

        XCTAssertEqual(module.state, .unsupported)
        XCTAssertTrue(adapter.initialTargets.isEmpty)
    }

    func testCacheIsSeparatedByFullTarget() async throws {
        let target = makeTarget()
        let sameThreadDifferentOwner = makeTarget(ownerPostID: "101")
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["first-owner"])),
            .success(makePage(target: sameThreadDifferentOwner, bodies: ["second-owner"]))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.load(sameThreadDifferentOwner)
        await module.load(target)

        guard case let .loaded(loadedTarget, page) = module.state else {
            XCTFail("Expected cached comments for the original full target")
            return
        }
        XCTAssertEqual(loadedTarget, target)
        XCTAssertEqual(page.comments.map(\.body), ["first-owner"])
        XCTAssertEqual(adapter.initialTargets, [target, sameThreadDifferentOwner])
    }

    func testLoadMoreWithoutLoadedStateDoesNotCallAdapter() async throws {
        let adapter = ChapterCommentsAdapterSpy()
        let module = adapter.makeModule()

        await module.loadNextPage()

        XCTAssertTrue(adapter.moreRequests.isEmpty)
        XCTAssertFalse(module.isLoadingMore)
    }

    func testLoadMoreWithoutNextViewDoesNotCallAdapter() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["only-page"], nextView: nil))
        ]
        let module = adapter.makeModule()

        await module.load(target)
        await module.loadNextPage()

        XCTAssertTrue(adapter.moreRequests.isEmpty)
        XCTAssertFalse(module.isLoadingMore)
    }

    func testLoadCachedTargetClearsRefreshErrorAndPreservesLoadMoreError() async throws {
        let target = makeTarget()
        let adapter = ChapterCommentsAdapterSpy()
        adapter.initialResults = [
            .success(makePage(target: target, bodies: ["cached"], nextView: 2)),
            .failure(TestError("refresh failed"))
        ]
        adapter.moreResults = [.failure(TestError("more failed"))]
        let module = adapter.makeModule()

        await module.load(target)
        await module.refresh(target)
        await module.loadNextPage()
        await module.load(target)

        guard case let .loaded(_, page) = module.state else {
            XCTFail("Expected cached comments")
            return
        }
        XCTAssertEqual(page.comments.map(\.body), ["cached"])
        XCTAssertNil(module.refreshError)
        XCTAssertEqual(module.loadMoreError, "more failed")
    }
}

@MainActor
private final class ChapterCommentsAdapterSpy {
    struct MoreRequest: Equatable {
        var target: ReaderChapterCommentTarget
        var view: Int
    }

    var initialResults: [Result<ChapterCommentsPage, Error>] = []
    var moreResults: [Result<ChapterCommentsPage, Error>] = []
    private(set) var initialTargets: [ReaderChapterCommentTarget] = []
    private(set) var moreRequests: [MoreRequest] = []

    func makeModule() -> ReaderChapterCommentsModule {
        ReaderChapterCommentsModule(
            adapter: ReaderChapterCommentsModule.Adapter(
                loadInitial: { [self] target in
                    initialTargets.append(target)
                    return try initialResults.removeFirst().get()
                },
                loadMore: { [self] target, view in
                    moreRequests.append(MoreRequest(target: target, view: view))
                    return try moreResults.removeFirst().get()
                }
            ),
            onChange: nil
        )
    }
}

private struct TestError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private func makeTarget(
    ownerPostID: String = "100",
    title: String? = "第一章",
    authorID: String? = nil
) -> ReaderChapterCommentTarget {
    ReaderChapterCommentTarget(
        threadID: "9001",
        view: 1,
        ownerPostID: ownerPostID,
        title: title,
        authorID: authorID
    )
}

private func makePage(
    target: ReaderChapterCommentTarget,
    bodies: [String],
    nextView: Int? = nil
) -> ChapterCommentsPage {
    ChapterCommentsPage(
        target: target,
        comments: bodies.enumerated().map { index, body in
            ChapterComment(
                id: "\(target.ownerPostID)-\(index)-\(body)",
                source: .postComment,
                authorName: "作者",
                body: body,
                postID: "\(index)"
            )
        },
        isBoundaryClosed: nextView == nil,
        nextView: nextView
    )
}
