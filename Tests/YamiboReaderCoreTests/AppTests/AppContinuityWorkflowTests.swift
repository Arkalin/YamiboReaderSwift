import Foundation
import Testing
@testable import YamiboReaderCore

@MainActor
@Test func appContinuityRestoreReconcilesNovelRouteWithFavoriteLibraryProgress() async throws {
    let keyPrefix = UUID().uuidString
    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let resumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).resume")
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2"))
    let staleRoute = ReaderResumeRoute.novel(
        ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "旧标题",
            source: .resume,
            initialView: 1
        )
    )
    let resumePoint = ReaderResumePoint(
        view: 5,
        displayedTextOffset: 120,
        chapterOrdinal: 2,
        chapterTitle: "第二章",
        segmentProgress: 0.4,
        authorID: "42",
        readingModeHint: .paged
    )
    try await resumeRouteStore.save(staleRoute)
    try await favoriteStore.saveFavorites([
        Favorite(
            title: "远端小说",
            url: threadURL,
            lastView: 5,
            authorID: "42",
            novelResumePoint: resumePoint,
            type: .novel
        )
    ])
    let workflow = AppContinuityWorkflow(
        appContext: YamiboAppContext(
            readerResumeRouteStore: resumeRouteStore,
            favoriteStore: favoriteStore
        )
    )

    let restoredRoute = await workflow.restoreExplicitly(
        canRestoreReaderRoute: true,
        reconcilesWithFavoriteProgress: true
    )

    let expectedContext = ReaderLaunchContext(
        threadURL: threadURL,
        threadTitle: "远端小说",
        source: .resume,
        initialView: 5,
        authorID: "42",
        initialResumePoint: resumePoint
    )
    #expect(restoredRoute == .novel(expectedContext))
    #expect(await resumeRouteStore.load() == .novel(expectedContext))
}

@MainActor
@Test func appContinuityDoesNotRestoreOrphanMangaRouteWithoutFavoriteProgress() async throws {
    let keyPrefix = UUID().uuidString
    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let resumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).resume")
    let originalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
    let route = MangaPresentationRoute.native(
        MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: originalURL,
            displayTitle: "大家不可以忘記三之昔的一個貢獻",
            source: .resume,
            initialPage: 0
        )
    )
    try await resumeRouteStore.save(.manga(route))
    let workflow = AppContinuityWorkflow(
        appContext: YamiboAppContext(
            readerResumeRouteStore: resumeRouteStore,
            favoriteStore: favoriteStore
        )
    )

    let restoredRoute = await workflow.restoreExplicitly(
        canRestoreReaderRoute: true,
        reconcilesWithFavoriteProgress: true
    )

    #expect(restoredRoute == nil)
    #expect(await resumeRouteStore.load() == nil)
}

@MainActor
@Test func appContinuityIgnoresLateReadingPositionAfterRouteDismissal() async throws {
    let keyPrefix = UUID().uuidString
    let resumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).resume")
    let workflow = AppContinuityWorkflow(
        appContext: YamiboAppContext(readerResumeRouteStore: resumeRouteStore)
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&mobile=2"))
    let route = ReaderResumeRoute.novel(
        ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "测试小说",
            source: .resume,
            initialView: 1
        )
    )

    workflow.readerRoutePresented(route)
    try await waitForReaderResumeRoute(resumeRouteStore, equals: route)
    workflow.readerRouteDismissed()
    workflow.readerReadingPositionChanged(route)

    #expect(await resumeRouteStore.load() == nil)
}

private func waitForReaderResumeRoute(
    _ store: ReaderResumeRouteStore,
    equals expected: ReaderResumeRoute?,
    timeout: TimeInterval = 1
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await store.load() == expected {
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(await store.load() == expected)
}
