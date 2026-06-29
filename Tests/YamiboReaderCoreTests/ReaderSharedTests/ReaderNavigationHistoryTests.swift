import Testing
@testable import YamiboReaderCore

@Test func readerNavigationHistoryRecordsNonlinearJumpSources() {
    var history = ReaderNavigationHistory<Int>()

    history.recordNonlinearJump(from: 3, to: 9)

    #expect(history.peekBack() == 3)
    #expect(history.peekForward() == nil)
    #expect(history.canGoBack)
    #expect(!history.canGoForward)
}

@Test func readerNavigationHistorySkipsSameSourceAndTargetWithoutClearingForward() {
    var history = ReaderNavigationHistory<Int>()
    history.recordNonlinearJump(from: 1, to: 5)
    _ = history.commitBack(from: 5)

    history.recordNonlinearJump(from: 1, to: 1)

    #expect(history.peekBack() == nil)
    #expect(history.peekForward() == 5)
}

@Test func readerNavigationHistoryTransfersAnchorsAfterSuccessfulBackAndForwardRestore() {
    var history = ReaderNavigationHistory<Int>()
    history.recordNonlinearJump(from: 1, to: 5)
    history.recordNonlinearJump(from: 5, to: 9)

    #expect(history.peekBack() == 5)
    #expect(history.commitBack(from: 9) == 5)
    #expect(history.peekBack() == 1)
    #expect(history.peekForward() == 9)

    #expect(history.commitForward(from: 5) == 9)
    #expect(history.peekBack() == 5)
    #expect(history.peekForward() == nil)
}

@Test func readerNavigationHistoryDiscardsUnresolvableCandidatesWithoutTransferringCurrentAnchor() {
    var history = ReaderNavigationHistory<Int>()
    history.recordNonlinearJump(from: 1, to: 5)
    history.recordNonlinearJump(from: 5, to: 9)

    #expect(history.discardBackCandidate() == 5)

    #expect(history.peekBack() == 1)
    #expect(history.peekForward() == nil)
}

@Test func readerNavigationHistoryClearsForwardAfterSuccessfulNonlinearBranch() {
    var history = ReaderNavigationHistory<Int>()
    history.recordNonlinearJump(from: 1, to: 5)
    _ = history.commitBack(from: 5)

    history.recordNonlinearJump(from: 1, to: 8)

    #expect(history.peekBack() == 1)
    #expect(history.peekForward() == nil)
}

@Test func readerNavigationHistoryRetainsOnlyNewestAnchorsUpToCapacity() {
    var history = ReaderNavigationHistory<Int>(capacity: 3)

    history.recordNonlinearJump(from: 1, to: 2)
    history.recordNonlinearJump(from: 2, to: 3)
    history.recordNonlinearJump(from: 3, to: 4)
    history.recordNonlinearJump(from: 4, to: 5)

    #expect(history.backStack == [2, 3, 4])
}
