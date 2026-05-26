import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

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

private func makeTarget() -> ReaderChapterCommentTarget {
    ReaderChapterCommentTarget(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9001&mobile=2")!,
        view: 1,
        ownerPostID: "100",
        title: "第一章"
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
