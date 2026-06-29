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

@Test func readerNavigationHistoryClearRemovesBackAndForwardStacks() {
    var history = ReaderNavigationHistory<Int>()
    history.recordNonlinearJump(from: 1, to: 5)
    _ = history.commitBack(from: 5)

    history.clear()

    #expect(!history.canGoBack)
    #expect(!history.canGoForward)
    #expect(history.peekBack() == nil)
    #expect(history.peekForward() == nil)
}

@Test func readerNavigationLinearReadingExpirationExpiresAfterThresholdDistinctPages() {
    var expiration = ReaderNavigationLinearReadingExpiration<Int>(threshold: 5)

    expiration.arm(at: 10)

    let repeatedInitialPageExpired = expiration.recordLinearReading(at: 10)
    let firstPageExpired = expiration.recordLinearReading(at: 11)
    let repeatedFirstPageExpired = expiration.recordLinearReading(at: 11)
    let secondPageExpired = expiration.recordLinearReading(at: 12)
    let thirdPageExpired = expiration.recordLinearReading(at: 13)
    let fourthPageExpired = expiration.recordLinearReading(at: 14)
    let fifthPageExpired = expiration.recordLinearReading(at: 15)

    #expect(!repeatedInitialPageExpired)
    #expect(!firstPageExpired)
    #expect(!repeatedFirstPageExpired)
    #expect(!secondPageExpired)
    #expect(!thirdPageExpired)
    #expect(!fourthPageExpired)
    #expect(fifthPageExpired)
    #expect(!expiration.isArmed)
}

@Test func readerNavigationLinearReadingExpirationResetDisarmsTracking() {
    var expiration = ReaderNavigationLinearReadingExpiration<Int>(threshold: 2)

    expiration.arm(at: 1)
    let firstPageExpired = expiration.recordLinearReading(at: 2)
    expiration.reset()
    let disarmedPageExpired = expiration.recordLinearReading(at: 3)

    #expect(!firstPageExpired)
    #expect(!disarmedPageExpired)
    #expect(!expiration.isArmed)
}
