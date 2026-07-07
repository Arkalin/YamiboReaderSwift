import SwiftUI
import YamiboReaderCore

/// Composition root for the favorites tab: creates the library organizer,
/// the remote sync session, and the update monitor, and routes resolved open
/// targets into the app-level readers.
struct LocalFavoritesRootView: View {
    @StateObject private var organizer: FavoriteLibraryOrganizer
    @StateObject private var remoteSync: FavoriteRemoteSyncSession
    @StateObject private var updateMonitor: FavoriteUpdateMonitor

    private let openTargetResolver: LocalFavoriteOpenTargetResolver
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
            makeFavoriteRepository: dependencies.makeFavoriteRepository,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            makeThreadRouteResolver: dependencies.makeThreadRouteResolver
        ))
        _updateMonitor = StateObject(wrappedValue: FavoriteUpdateMonitor(
            updateStore: dependencies.favoriteUpdateStore,
            libraryStore: dependencies.localFavoriteLibraryStore,
            makeForumThreadReaderRepository: dependencies.makeForumThreadReaderRepository,
            settingsStore: dependencies.settingsStore
        ))
        openTargetResolver = LocalFavoriteOpenTargetResolver(
            libraryStore: dependencies.localFavoriteLibraryStore,
            readingProgressStore: dependencies.readingProgressStore
        )
        self.appModel = appModel
    }

    var body: some View {
        LocalFavoritesOrganizationView(
            organizer: organizer,
            remoteSync: remoteSync,
            updateMonitor: updateMonitor,
            onOpen: { item, mode in
                await open(item, mode: mode)
            }
        )
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

    private func open(_ item: FavoriteItem, mode: FavoriteLaunchMode) async {
        do {
            guard let target = try await openTargetResolver.openTarget(for: item, mode: mode) else { return }
            switch target {
            case let .novelReader(context):
                appModel.presentNovelReader(context)
            case let .mangaReader(context):
                appModel.presentMangaReader(context)
            case let .nativeThread(url, title):
                appModel.openNativeForumThread(url: url, title: title)
            }
        } catch {
            organizer.errorMessage = error.localizedDescription
        }
    }
}
