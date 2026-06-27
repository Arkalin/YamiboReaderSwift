import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class ReaderCacheOperationModuleTests: XCTestCase {
    func testSelectionStateSeparatesCachedUncachedAndInvalidViews() {
        let module = ReaderCacheOperationModule()
        let selection = module.selectionState(
            for: [0, 1, 2, 4],
            snapshot: makeSnapshot(cacheableViews: [1, 2, 3], cachedViews: [1, 3])
        )

        XCTAssertEqual(selection.selectedViews, [1, 2])
        XCTAssertEqual(selection.cachedSelectedViews, [1])
        XCTAssertEqual(selection.uncachedSelectedViews, [2])
        XCTAssertTrue(selection.canCache)
        XCTAssertTrue(selection.canUpdate)
        XCTAssertTrue(selection.canDelete)
        XCTAssertFalse(selection.isAllSelected)
    }

    func testSelectionStateReportsAllSelectedOnlyForValidCompleteSelection() {
        let module = ReaderCacheOperationModule()
        let selection = module.selectionState(
            for: [1, 2, 3, 99],
            snapshot: makeSnapshot(cacheableViews: [1, 2, 3], cachedViews: [1])
        )

        XCTAssertEqual(selection.selectedViews, [1, 2, 3])
        XCTAssertTrue(selection.isAllSelected)
    }

    func testStartCachingUpdatesProgressAndCompletion() async throws {
        let repository = FakeCacheOperationRepository(cachedViews: [1])
        let module = ReaderCacheOperationModule()
        module.syncCachedViews([1])

        module.startCaching(
            views: [1, 2, 3],
            snapshot: makeSnapshot(cacheableViews: [1, 2, 3], cachedViews: [1]),
            repository: repository,
            summary: { _, result in "done \(result.completedViews.count)" }
        )

        XCTAssertTrue(module.state.isRunning)
        XCTAssertEqual(module.state.queuedViews, [2, 3])

        try await waitFor {
            module.state.isFinished
        }

        XCTAssertEqual(module.cachedViews, [1, 2, 3])
        XCTAssertEqual(module.state.status, .completed)
        XCTAssertEqual(module.state.completedViews, [2, 3])
        XCTAssertEqual(module.state.summaryMessage, "done 2")
    }

    func testStopCachingCancelsRemainingQueueButKeepsCompletedViews() async throws {
        let repository = FakeCacheOperationRepository(cachedViews: [1], delayNanoseconds: 40_000_000)
        let module = ReaderCacheOperationModule()
        module.syncCachedViews([1])

        module.startCaching(
            views: [2, 3, 4],
            snapshot: makeSnapshot(cacheableViews: [1, 2, 3, 4], cachedViews: [1]),
            repository: repository,
            summary: { _, result in result.wasCancelled ? "cancelled" : "completed" }
        )

        try await Task.sleep(nanoseconds: 60_000_000)
        module.stopCaching()

        try await waitFor {
            module.state.isFinished
        }

        XCTAssertEqual(module.state.status, .cancelled)
        XCTAssertLessThan(module.state.completedViews.count, 3)
        XCTAssertTrue(module.cachedViews.isSuperset(of: [1]))
    }

    func testUpdateCachedViewsRewritesOnlySelectedCachedViews() async throws {
        let repository = FakeCacheOperationRepository(cachedViews: [1, 2])
        let module = ReaderCacheOperationModule()
        module.syncCachedViews([1, 2])

        module.updateCachedViews(
            [1, 3],
            snapshot: makeSnapshot(cacheableViews: [1, 2, 3], cachedViews: [1, 2]),
            repository: repository,
            summary: { _, result in "updated \(result.completedViews.count)" },
            onFailure: { _ in XCTFail("Update should not fail") }
        )

        try await waitFor {
            module.state.isFinished
        }

        let deletedViews = await repository.deletedViews
        let cachedBatches = await repository.cachedBatches
        XCTAssertEqual(deletedViews, [[1]])
        XCTAssertEqual(cachedBatches, [[1]])
        XCTAssertEqual(module.cachedViews, [1, 2])
        XCTAssertEqual(module.state.status, .completed)
        XCTAssertEqual(module.state.completedViews, [1])
    }

    func testRepositoryReceivesSnapshotContextForCacheUpdateDeleteAndRefresh() async throws {
        let context = ReaderCacheOperationContext(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&mobile=2")!,
            authorID: "42",
            contentSource: .authorFilteredPage
        )
        let snapshot = ReaderCacheOperationSnapshot(
            cacheableViews: [1, 2, 3],
            cachedViews: [1],
            context: context
        )
        let repository = FakeCacheOperationRepository(cachedViews: [1])
        let module = ReaderCacheOperationModule()
        module.syncCachedViews([1])

        module.startCaching(
            views: [2],
            snapshot: snapshot,
            repository: repository,
            summary: { _, _ in "cached" }
        )
        try await waitFor { module.state.isFinished }

        module.updateCachedViews(
            [1],
            snapshot: snapshot,
            repository: repository,
            summary: { _, _ in "updated" },
            onFailure: { _ in XCTFail("Update should not fail") }
        )
        try await waitFor { module.state.isFinished && module.state.summaryMessage == "updated" }

        try await module.deleteCachedViews([1], snapshot: snapshot, repository: repository)

        let contexts = await repository.receivedContexts
        XCTAssertFalse(contexts.isEmpty)
        XCTAssertTrue(contexts.allSatisfy { $0 == context })
    }

    private func makeSnapshot(
        cacheableViews: Set<Int>,
        cachedViews: Set<Int>
    ) -> ReaderCacheOperationSnapshot {
        ReaderCacheOperationSnapshot(
            cacheableViews: cacheableViews,
            cachedViews: cachedViews,
            context: ReaderCacheOperationContext(
                threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")!,
                authorID: nil,
                contentSource: .fallbackUnfilteredPage
            )
        )
    }
}

private actor FakeCacheOperationRepository: ReaderCacheOperationRepository {
    private(set) var deletedViews: [Set<Int>] = []
    private(set) var cachedBatches: [Set<Int>] = []
    private(set) var receivedContexts: [ReaderCacheOperationContext] = []
    private var storedCachedViews: Set<Int>
    private let delayNanoseconds: UInt64

    init(cachedViews: Set<Int>, delayNanoseconds: UInt64 = 0) {
        self.storedCachedViews = cachedViews
        self.delayNanoseconds = delayNanoseconds
    }

    func cachedViews(for context: ReaderCacheOperationContext) async -> Set<Int> {
        receivedContexts.append(context)
        return storedCachedViews
    }

    func deleteCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext
    ) async throws {
        receivedContexts.append(context)
        deletedViews.append(views)
        storedCachedViews.subtract(views)
    }

    func cacheViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult {
        receivedContexts.append(context)
        let targets = views.sorted()
        cachedBatches.append(Set(targets))
        var completedViews: [Int] = []
        var wasCancelled = false

        for view in targets {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    wasCancelled = true
                    break
                }
            }
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            completedViews.append(view)
            storedCachedViews.insert(view)
            await progress?(ReaderCacheBatchProgress(
                totalCount: targets.count,
                completedCount: completedViews.count,
                currentView: view,
                completedViews: completedViews,
                failedViews: [],
                status: .running
            ))
        }

        await progress?(ReaderCacheBatchProgress(
            totalCount: targets.count,
            completedCount: completedViews.count,
            currentView: nil,
            completedViews: completedViews,
            failedViews: [],
            status: wasCancelled ? .cancelled : .completed
        ))
        return ReaderCacheBatchResult(
            totalCount: targets.count,
            completedViews: completedViews,
            failedViews: [],
            wasCancelled: wasCancelled
        )
    }
}

@MainActor
private func waitFor(
    timeout: TimeInterval = 2,
    intervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    XCTFail("Timed out waiting for condition")
}
