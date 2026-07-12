import SwiftUI
import YamiboReaderCore

/// Composition root for the favorites tab: creates the library organizer,
/// the remote sync session, and the update monitor, and routes resolved open
/// targets into the app-level readers or a full-screen thread overlay.
struct LocalFavoritesRootView: View {
    @StateObject private var organizer: FavoriteLibraryOrganizer
    @StateObject private var remoteSync: FavoriteRemoteSyncSession
    @StateObject private var updateMonitor: FavoriteUpdateMonitor
    @State private var threadOverlayItem: ForumThreadOverlayItem?

    private let openTargetResolver: LocalFavoriteOpenTargetResolver
    private let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    let appModel: YamiboAppModel

    init(dependencies: LibraryDependencies, appModel: YamiboAppModel) {
        _organizer = StateObject(wrappedValue: FavoriteLibraryOrganizer(
            libraryStore: dependencies.localFavoriteLibraryStore,
            readingProgressStore: dependencies.readingProgressStore,
            settingsStore: dependencies.settingsStore,
            contentCoverStore: dependencies.contentCoverStore,
            mangaDirectoryStore: dependencies.mangaDirectoryStore,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            makeFavoriteRepository: dependencies.makeFavoriteRepository
        ))
        _remoteSync = StateObject(wrappedValue: FavoriteRemoteSyncSession(
            libraryStore: dependencies.localFavoriteLibraryStore,
            runStore: dependencies.favoriteSyncRunStore,
            contentCoverStore: dependencies.contentCoverStore,
            mangaDirectoryStore: dependencies.mangaDirectoryStore,
            settingsStore: dependencies.settingsStore,
            makeFavoriteRepository: dependencies.makeFavoriteRepository,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            makeThreadRouteResolver: dependencies.makeThreadRouteResolver
        ))
        _updateMonitor = StateObject(wrappedValue: FavoriteUpdateMonitor(
            updateStore: dependencies.favoriteUpdateStore,
            libraryStore: dependencies.localFavoriteLibraryStore,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            settingsStore: dependencies.settingsStore,
            notifier: UserNotificationFavoriteUpdateNotifier()
        ))
        openTargetResolver = LocalFavoriteOpenTargetResolver(
            libraryStore: dependencies.localFavoriteLibraryStore,
            readingProgressStore: dependencies.readingProgressStore,
            mangaDirectoryStore: dependencies.mangaDirectoryStore,
            settingsStore: dependencies.settingsStore
        )
        makeFavoriteRepository = dependencies.makeFavoriteRepository
        self.appModel = appModel
    }

    var body: some View {
        LocalFavoritesOrganizationView(
            organizer: organizer,
            remoteSync: remoteSync,
            updateMonitor: updateMonitor,
            makeFavoriteRepository: makeFavoriteRepository,
            onOpen: { item, mode, mangaScope in
                await open(item, mode: mode, mangaScope: mangaScope)
            },
            onOpenBoard: { board in
                appModel.openForumURL(
                    YamiboRoute.forumBoard(fid: board.fid, page: 1, filterID: nil, orderFilter: nil, orderBy: nil).url
                )
            }
        )
        .fullScreenCover(item: $threadOverlayItem) { item in
            ForumThreadOverlayScreen(
                item: item,
                dependencies: appModel.appContext.forumDependencies,
                appModel: appModel,
                // Opening a favorite is a real visit, not a discussion
                // companion of a running reader — it must write its
                // browsing-history row like the old forum-tab route did.
                rootIsDiscussionView: false
            )
        }
        .task {
            async let organizerLoad: Void = organizer.load()
            async let remoteSyncLoad: Void = remoteSync.load()
            async let updateMonitorLoad: Void = updateMonitor.load()
            _ = await (organizerLoad, remoteSyncLoad, updateMonitorLoad)
            // Foreground catch-up for automatic update checking: background
            // refresh timing is only best-effort.
            await updateMonitor.startCheckIfDue()
        }
    }

    private func open(_ item: FavoriteItem, mode: FavoriteLaunchMode, mangaScope: FavoriteMangaReadingScope) async {
        do {
            guard let target = try await openTargetResolver.openTarget(for: item, mode: mode, mangaScope: mangaScope) else { return }
            switch target {
            case let .novelReader(context):
                appModel.presentNovelReader(context)
            case let .mangaReader(context):
                appModel.presentMangaReader(context)
            case let .nativeThread(url, title):
                // Plain-post favorites open in a full-screen overlay so the
                // favorites tab stays put underneath, mirroring the reader's
                // 打开原帖 behavior.
                threadOverlayItem = ForumThreadOverlayItem(url: url, title: title)
            }
        } catch {
            YamiboLog.library.error("Failed to resolve open target for favorite \(item.id): \(error.localizedDescription)")
            organizer.errorMessage = error.localizedDescription
        }
    }
}
