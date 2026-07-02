import CoreGraphics
import Foundation
import Testing
@preconcurrency import GRDB
@testable import YamiboReaderCore

@Test func sessionStorePersistsCookieAndLoginState() async throws {
    let defaults = try #require(UserDefaults(suiteName: "session-store-tests"))
    defaults.removePersistentDomain(forName: "session-store-tests")
    let store = SessionStore(defaults: defaults, key: "session")

    try await store.updateCookie("sid=123", isLoggedIn: true)
    let session = await store.load()

    #expect(session.cookie == "sid=123")
    #expect(session.isLoggedIn)
    #expect(session.userAgent == YamiboDefaults.defaultMobileUserAgent)
}

@Test func sessionStoreUpdatesUserAgentFromWebSession() async throws {
    let defaults = try #require(UserDefaults(suiteName: "web-session-store-tests"))
    defaults.removePersistentDomain(forName: "web-session-store-tests")
    let store = SessionStore(defaults: defaults, key: "session")

    try await store.updateWebSession(
        cookie: "sid=999; EeqY_2132_auth=web-token",
        userAgent: "Custom-UA",
        isLoggedIn: true
    )
    let session = await store.load()

    #expect(session.cookie == "sid=999; EeqY_2132_auth=web-token")
    #expect(session.userAgent == "Custom-UA")
    #expect(session.isLoggedIn)
}

@Test func sessionStoreIgnoresAnonymousWebCookieWhenNativeSessionIsAuthenticated() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "web-session-anonymous-over-auth-tests")
    let store = SessionStore(defaults: defaults, key: "session")
    let authenticatedSession = SessionState(
        cookie: "sid=1; EeqY_2132_auth=native-token; salt=old",
        userAgent: "Native-UA",
        isLoggedIn: true,
        accountUID: "535977"
    )
    try await store.save(authenticatedSession)

    try await store.updateWebSession(
        cookie: "sid=anonymous; salt=new",
        userAgent: "Web-UA",
        isLoggedIn: false
    )

    let session = await store.load()
    #expect(session.cookie == authenticatedSession.cookie)
    #expect(session.userAgent == authenticatedSession.userAgent)
    #expect(session.isLoggedIn)
    #expect(session.accountUID == "535977")
}

@Test func sessionStoreSavesAnonymousWebCookieWhenNotAuthenticated() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "web-session-anonymous-tests")
    let store = SessionStore(defaults: defaults, key: "session")

    try await store.updateWebSession(
        cookie: "sid=anonymous; salt=web",
        userAgent: "Web-UA",
        isLoggedIn: false
    )

    let session = await store.load()
    #expect(session.cookie == "sid=anonymous; salt=web")
    #expect(session.userAgent == "Web-UA")
    #expect(!session.isLoggedIn)
    #expect(session.accountUID == nil)
}

@Test func sessionStorePromotesAuthenticatedWebCookie() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "web-session-promote-auth-tests")
    let store = SessionStore(defaults: defaults, key: "session")

    try await store.updateWebSession(
        cookie: "sid=web; EeqY_2132_auth=web-token",
        userAgent: "Web-UA",
        isLoggedIn: true
    )

    let session = await store.load()
    #expect(session.cookie == "sid=web; EeqY_2132_auth=web-token")
    #expect(session.userAgent == "Web-UA")
    #expect(session.isLoggedIn)
    #expect(session.accountUID == nil)
}

@Test func sessionStorePreservesAccountUIDWhenWebAuthenticationTokenIsUnchanged() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "web-session-preserve-uid-tests")
    let store = SessionStore(defaults: defaults, key: "session")
    try await store.save(
        SessionState(
            cookie: "sid=old; EeqY_2132_auth=same-token; salt=old",
            userAgent: "Native-UA",
            isLoggedIn: true,
            accountUID: "535977"
        )
    )

    try await store.updateWebSession(
        cookie: "sid=new; EeqY_2132_auth=same-token; salt=new",
        userAgent: "Web-UA",
        isLoggedIn: true
    )

    let session = await store.load()
    #expect(session.cookie == "sid=new; EeqY_2132_auth=same-token; salt=new")
    #expect(session.userAgent == "Web-UA")
    #expect(session.isLoggedIn)
    #expect(session.accountUID == "535977")
}

@Test func sessionStoreIgnoresDifferentWebAuthenticationTokenWhenNativeSessionIsAuthenticated() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "web-session-token-change-tests")
    let store = SessionStore(defaults: defaults, key: "session")
    let nativeSession = SessionState(
        cookie: "sid=old; EeqY_2132_auth=native-token",
        userAgent: "Native-UA",
        isLoggedIn: true,
        accountUID: "535977"
    )
    try await store.save(nativeSession)

    try await store.updateWebSession(
        cookie: "sid=stale; EeqY_2132_auth=stale-web-token",
        userAgent: "Web-UA",
        isLoggedIn: true
    )

    let session = await store.load()
    #expect(session.cookie == nativeSession.cookie)
    #expect(session.userAgent == nativeSession.userAgent)
    #expect(session.isLoggedIn)
    #expect(session.accountUID == "535977")
}

@Test func sessionStateRejectsEmptyAndDeletedAuthenticationCookieValues() {
    #expect(SessionState.authenticationCookieValue(in: "EeqY_2132_auth=valid-token") == "valid-token")
    #expect(SessionState.authenticationCookieValue(in: "sid=1; EeqY_2132_auth=; salt=2") == nil)
    #expect(SessionState.authenticationCookieValue(in: "sid=1; EeqY_2132_auth=deleted; salt=2") == nil)
    #expect(!SessionState.hasAuthenticationCookie("sid=1; EeqY_2132_auth=null; salt=2"))
}

@Test func settingsStorePersistsReaderFlags() async throws {
    let defaults = try #require(UserDefaults(suiteName: "settings-store-tests"))
    defaults.removePersistentDomain(forName: "settings-store-tests")
    let store = SettingsStore(defaults: defaults, key: "settings")
    let settings = AppSettings(
        reader: ReaderAppearanceSettings(
            fontScale: 1.1,
            fontFamily: .rounded,
            lineHeightScale: 1.6,
            characterSpacingScale: 0.04,
            horizontalPadding: 20,
            usesJustifiedText: true,
            loadsInlineImages: false,
            showsAuthorRepliesToOthers: false,
            showsTwoPagesInLandscapeOnPad: true,
            backgroundStyle: .paper,
            readingMode: .vertical,
            pagedTurnStyle: .quickFade,
            pageTurnDirection: .rightToLeft,
            translationMode: .traditional
        ),
        manga: MangaReaderSettings(
            readingMode: .paged,
            pagedTurnStyle: .pageCurl,
            pageTurnDirection: .leftToRight,
            pageScaleMode: .fitHeight,
            pageEdgeFillStyle: .system,
            brightness: 0.82,
            zoomEnabled: false,
            showsTwoPagesInLandscapeOnPad: true,
            directorySortOrder: .descending
        ),
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        favoriteAppearance: FavoriteAppearanceSettings(
            collection: .purple,
            novel: .red,
            manga: .green,
            other: .gray
        ),
        applePencilPageTurn: ApplePencilPageTurnSettings(
            isEnabled: true,
            behavior: .doubleTapNextSqueezePrevious
        ),
        homePage: .favorites,
        usesDataSaverMode: true,
        collapsesFavoriteSections: true
    )

    try await store.save(settings)
    let loaded = await store.load()

    #expect(loaded == settings)
}

@Test func appSettingsDecodesLegacyPayloadWithDefaultWebBrowserSettings() async throws {
    let legacy = """
    {
      "reader": {
        "fontScale": 1.0
      },
      "manga": {
        "readingMode": "vertical"
      },
      "usesDataSaverMode": false,
      "collapsesFavoriteSections": true
    }
    """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))

    #expect(decoded.webBrowser.showsNavigationBar == true)
    #expect(decoded.homePage == .forum)
    #expect(decoded.favoriteAppearance == FavoriteAppearanceSettings())
    #expect(decoded.favoriteBackground == FavoriteBackgroundSettings())
    #expect(decoded.applePencilPageTurn == ApplePencilPageTurnSettings())
    #expect(decoded.collapsesFavoriteSections == true)
}

@Test func favoriteBackgroundSettingsEncodesDecodesAndClampsValues() throws {
    let payload = """
    {
      "isEnabled": true,
      "imageID": "image-a",
      "scale": 9.0,
      "offsetX": -4.0,
      "offsetY": 2.0,
      "blurRadius": 80.0
    }
    """

    let decoded = try JSONDecoder().decode(FavoriteBackgroundSettings.self, from: Data(payload.utf8))

    #expect(decoded.isEnabled)
    #expect(decoded.imageID == "image-a")
    #expect(decoded.scale == FavoriteBackgroundSettings.maximumScale)
    #expect(decoded.offsetX == FavoriteBackgroundSettings.minimumOffset)
    #expect(decoded.offsetY == FavoriteBackgroundSettings.maximumOffset)
    #expect(decoded.blurRadius == FavoriteBackgroundSettings.maximumBlurRadius)

    let encoded = try JSONEncoder().encode(decoded)
    let roundTrip = try JSONDecoder().decode(FavoriteBackgroundSettings.self, from: encoded)
    #expect(roundTrip == decoded)
}

@Test func applePencilPageTurnBehaviorMapsGesturesToPageDeltas() {
    #expect(ApplePencilPageTurnBehavior.doubleTapPreviousSqueezeNext.pageDelta(for: .doubleTap) == -1)
    #expect(ApplePencilPageTurnBehavior.doubleTapPreviousSqueezeNext.pageDelta(for: .squeeze) == 1)
    #expect(ApplePencilPageTurnBehavior.doubleTapNextSqueezePrevious.pageDelta(for: .doubleTap) == 1)
    #expect(ApplePencilPageTurnBehavior.doubleTapNextSqueezePrevious.pageDelta(for: .squeeze) == -1)
}

@Test func appSettingsDecodesPartialFavoriteAppearanceWithDefaults() async throws {
    let legacy = """
    {
      "favoriteAppearance": {
        "novel": "red"
      }
    }
    """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))

    #expect(decoded.favoriteAppearance.collection == .orange)
    #expect(decoded.favoriteAppearance.novel == .red)
    #expect(decoded.favoriteAppearance.manga == .blue)
    #expect(decoded.favoriteAppearance.other == .cyan)
}

@Test func appSettingsPersistsHomePageWhenEncodingAndDecoding() throws {
    let settings = AppSettings(homePage: .favorites)

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

    #expect(decoded.homePage == .favorites)
}

@Test func readerAppearanceSettingsDecodesLegacyPayloadWithFontDefaults() async throws {
    let legacy = """
    {
      "fontScale": 1.2,
      "lineHeightScale": 1.5,
      "horizontalPadding": 18,
      "usesNightMode": true,
      "loadsInlineImages": false,
      "backgroundStyle": "paper",
      "readingMode": "vertical",
      "translationMode": "traditional"
    }
    """

    let decoded = try JSONDecoder().decode(ReaderAppearanceSettings.self, from: Data(legacy.utf8))

    #expect(decoded.fontFamily == .systemSans)
    #expect(decoded.characterSpacingScale == 0)
    #expect(decoded.usesJustifiedText == false)
    #expect(decoded.showsAuthorRepliesToOthers == true)
    #expect(decoded.showsTwoPagesInLandscapeOnPad == false)
    #expect(decoded.pagedTurnStyle == .slide)
    #expect(decoded.pageTurnDirection == .leftToRight)
    #expect(decoded.fontScale == 1.2)
    #expect(decoded.lineHeightScale == 1.5)
}

@Test func readerAppearanceSettingsEncodesAndDecodesPagedTurnOptions() throws {
    let settings = ReaderAppearanceSettings(
        readingMode: .paged,
        pagedTurnStyle: .pageCurl,
        pageTurnDirection: .rightToLeft
    )

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ReaderAppearanceSettings.self, from: encoded)

    #expect(decoded.readingMode == .paged)
    #expect(decoded.pagedTurnStyle == .pageCurl)
    #expect(decoded.pageTurnDirection == .rightToLeft)
}

@Test func mangaReaderSettingsDecodesLegacyPayloadWithAscendingDirectorySortOrder() async throws {
    let legacy = """
    {
      "readingMode": "paged",
      "brightness": 0.8,
      "zoomEnabled": false
    }
    """

    let decoded = try JSONDecoder().decode(MangaReaderSettings.self, from: Data(legacy.utf8))

    #expect(decoded.readingMode == .paged)
    #expect(decoded.pagedTurnStyle == .slide)
    #expect(decoded.pageTurnDirection == .leftToRight)
    #expect(decoded.pageScaleMode == .fitWidth)
    #expect(decoded.pageEdgeFillStyle == .black)
    #expect(decoded.showsTwoPagesInLandscapeOnPad == false)
    #expect(decoded.directorySortOrder == .ascending)
}

@Test func mangaReaderSettingsEncodesAndDecodesPagedOptions() throws {
    let settings = MangaReaderSettings(
        readingMode: .paged,
        pagedTurnStyle: .quickFade,
        pageTurnDirection: .leftToRight,
        pageScaleMode: .fitHeight,
        pageEdgeFillStyle: .system,
        brightness: 0.9,
        zoomEnabled: false,
        showsTwoPagesInLandscapeOnPad: true,
        directorySortOrder: .descending
    )

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(MangaReaderSettings.self, from: encoded)

    #expect(decoded == settings)
}

@Test func favoriteStoreUpdatesNovelReadingPosition() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-progress-tests"))
    defaults.removePersistentDomain(forName: "favorite-progress-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=30&mobile=2"))

    _ = try await store.updateNovelReadingPosition(
        NovelReadingPosition(
            threadURL: url,
            view: 2,
            maxView: 5,
            chapterTitle: "第三章",
            authorID: "77",
            resumePoint: ReaderResumePoint(
                view: 2,
                displayedTextOffset: 128,
                chapterOrdinal: 2,
                chapterTitle: "第三章",
                segmentProgress: 0.4,
                authorID: "77",
                readingModeHint: .vertical
            ),
            documentSurfaceProgressPercent: 43
        )
    )

    let favorite = await store.favorite(for: url)
    #expect(favorite?.lastView == 2)
    #expect(favorite?.novelMaxView == 5)
    #expect(favorite?.mangaPageIndex == 0)
    #expect(favorite?.lastChapter == "第三章")
    #expect(favorite?.authorID == "77")
    #expect(favorite?.novelResumePoint?.displayedTextOffset == 128)
    #expect(favorite?.novelDocumentSurfaceProgressPercent == 43)
    #expect(favorite?.type == .novel)
}

@Test func favoriteDecodesLegacyNovelProgressWithoutDocumentSurfacePercent() throws {
    let payload: [String: Any] = [
        "id": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=302&mobile=2",
        "title": "旧小说收藏",
        "url": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=302&mobile=2",
        "lastView": 2,
        "type": FavoriteType.novel.rawValue,
        "novelMaxView": 5,
        "novelResumePoint": [
            "schemaVersion": ReaderResumePoint.schemaVersion,
            "view": 2,
            "displayedTextOffset": 128,
            "chapterOrdinal": 0,
            "segmentProgress": 0.86,
            "readingModeHint": "vertical"
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)

    let favorite = try JSONDecoder().decode(Favorite.self, from: data)

    #expect(favorite.novelDocumentSurfaceProgressPercent == nil)
}

@Test func favoriteStorePostsChangeNotificationWhenProgressChanges() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-store-notification-tests"))
    defaults.removePersistentDomain(forName: "favorite-store-notification-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301&mobile=2"))

    let notificationTask = Task {
        for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
            let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String
            if changeID == store.changeID {
                return true
            }
        }
        return false
    }
    await Task.yield()

    _ = try await store.updateNovelReadingPosition(
        NovelReadingPosition(
            threadURL: url,
            view: 2,
            chapterTitle: "第三章",
            authorID: "77"
        )
    )

    let didReceive = await notificationTask.value
    #expect(didReceive)
}

@Test func favoriteStoreCanMarkLastReadAt() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-last-read-tests"))
    defaults.removePersistentDomain(forName: "favorite-last-read-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let favorite = Favorite(
        title: "最近阅读收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=302&mobile=2"))
    )
    let readAt = Date(timeIntervalSince1970: 1_700_000_000)
    try await store.saveFavorites([favorite])

    let updated = try await store.markLastReadAt(for: favorite.id, date: readAt)
    let loaded = await store.favorite(id: favorite.id)

    #expect(updated.first?.lastReadAt == readAt)
    #expect(loaded?.lastReadAt == readAt)
}

@Test func favoriteStoreFindsFavoriteByCanonicalThreadURL() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-canonical-lookup-tests"))
    defaults.removePersistentDomain(forName: "favorite-canonical-lookup-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let listURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=302&extra=page%3D1&mobile=2"))
    let detailURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mobile=2&page=25&tid=302&mod=viewthread"))
    let favorite = Favorite(title: "列表收藏", url: listURL, type: .novel)
    try await store.saveFavorites([favorite])

    let loaded = await store.favorite(for: detailURL)

    #expect(loaded?.id == favorite.id)
    #expect(ReaderCacheIdentity.canonicalThreadURL(from: listURL) == ReaderCacheIdentity.canonicalThreadURL(from: detailURL))
}

@Test func favoriteStoreUpdatesNovelReadingPositionByCanonicalThreadURL() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-canonical-progress-tests"))
    defaults.removePersistentDomain(forName: "favorite-canonical-progress-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let listURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303&extra=page%3D1&mobile=2"))
    let readerURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?page=4&mobile=2&mod=viewthread&tid=303&authorid=77"))
    let favorite = Favorite(title: "列表收藏", url: listURL, type: .novel)
    try await store.saveFavorites([favorite])

    let updated = try await store.updateNovelReadingPosition(
        NovelReadingPosition(threadURL: readerURL, view: 4, chapterTitle: "第四章")
    )
    let favorites = await store.loadFavorites()

    #expect(updated.id == favorite.id)
    #expect(favorites.count == 1)
    #expect(favorites.first?.url == listURL)
    #expect(favorites.first?.lastView == 4)
    #expect(favorites.first?.lastChapter == "第四章")
    #expect(ReaderCacheIdentity.canonicalThreadURL(from: listURL) == ReaderCacheIdentity.canonicalThreadURL(from: readerURL))
}

@Test func favoriteStoreRemoteRefreshTouchesOnlyRemoteFavoritesClock() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-remote-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-remote-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=330&mobile=2"))
    let favorite = Favorite(title: "旧标题", displayName: "本地名", url: url, lastView: 3)

    try await store.saveLibrarySnapshot(FavoriteLibrarySnapshot(favorites: [favorite], collections: []))

    _ = try await store.mergeRemoteFavorites([
        Favorite(title: "新标题", url: url, remoteFavoriteID: "remote-330")
    ])

    let metadata = await store.loadLibrarySnapshot().syncMetadata
    #expect(metadata.remoteFavoritesUpdatedAt != nil)
    #expect(metadata.readingPositionUpdatedAtByCanonicalURL.isEmpty)
    #expect(metadata.lastReadAtUpdatedAtByCanonicalURL.isEmpty)
    #expect(metadata.favoriteMetadataUpdatedAtByCanonicalURL.isEmpty)
    #expect(metadata.favoriteOrganizationUpdatedAtByCanonicalURL.isEmpty)
    #expect(metadata.collectionUpdatedAtByID.isEmpty)
    #expect(metadata.tagUpdatedAtByID.isEmpty)
}

@Test func favoriteStoreReadingPositionAndLastReadClocksAreSeparate() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-reading-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-reading-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=331&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString
    let favorite = Favorite(title: "阅读 clock", url: url)
    let readAt = Date(timeIntervalSince1970: 1_900_000_000)

    try await store.saveLibrarySnapshot(FavoriteLibrarySnapshot(favorites: [favorite], collections: []))

    _ = try await store.updateNovelReadingPosition(NovelReadingPosition(threadURL: url, view: 4, chapterTitle: "第四章"))
    let afterProgress = await store.loadLibrarySnapshot().syncMetadata
    let progressClock = try #require(afterProgress.readingPositionUpdatedAtByCanonicalURL[canonicalKey])
    #expect(afterProgress.remoteFavoritesUpdatedAt == nil)
    #expect(afterProgress.lastReadAtUpdatedAtByCanonicalURL[canonicalKey] == nil)

    _ = try await store.markLastReadAt(for: favorite.id, date: readAt)
    let afterLastRead = await store.loadLibrarySnapshot().syncMetadata
    #expect(afterLastRead.readingPositionUpdatedAtByCanonicalURL[canonicalKey] == progressClock)
    #expect(afterLastRead.lastReadAtUpdatedAtByCanonicalURL[canonicalKey] == readAt)
}

@Test func favoriteStoreDeletingFavoriteTouchesRemoteFavoritesClock() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-delete-list-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-delete-list-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=332&mobile=2"))
    let favorite = Favorite(title: "删除 clock", url: url)
    let baseClock = Date(timeIntervalSince1970: 1_000)

    try await store.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        syncMetadata: FavoriteLibrarySyncMetadata(remoteFavoritesUpdatedAt: baseClock)
    ))

    let updated = try await store.deleteFavorites(ids: [favorite.id])
    let metadata = await store.loadLibrarySnapshot().syncMetadata
    let listClock = try #require(metadata.remoteFavoritesUpdatedAt)

    #expect(updated.favorites.isEmpty)
    #expect(listClock > baseClock)
}

@Test func favoriteStoreDeletingFavoritePreservesOwnedMangaOfflineCache() async throws {
    let defaults = try #require(UserDefaults(suiteName: makeIsolatedDefaultsSuiteName(prefix: "favorite-delete-offline-cache")))
    let root = makeTemporaryDirectory(prefix: "favorite-delete-offline-cache")
    let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: root.appendingPathComponent("offline", isDirectory: true))
    let store = FavoriteStore(defaults: defaults, key: "favorites", mangaOfflineCacheStore: offlineStore)
    let removedFavoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=335&mobile=2"))
    let remainingFavoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=336&mobile=2"))
    let removedFavorite = Favorite(id: "favorite-removed", title: "待删除漫画", url: removedFavoriteURL, type: .manga)
    let remainingFavorite = Favorite(id: "favorite-remaining", title: "保留漫画", url: remainingFavoriteURL, type: .manga)
    let removedImage = try #require(URL(string: "https://img.example.com/favorite-delete-removed.jpg"))
    let sharedImage = try #require(URL(string: "https://img.example.com/favorite-delete-shared.jpg"))
    let workImage = try #require(URL(string: "https://img.example.com/favorite-delete-work.jpg"))

    try await store.saveFavorites([removedFavorite, remainingFavorite])
    try await offlineStore.saveOfflineImageData(Data([1]), for: removedImage)
    try await offlineStore.saveOfflineImageData(Data([2]), for: sharedImage)
    try await offlineStore.saveOfflineImageData(Data([3]), for: workImage)
    try await offlineStore.saveMembership(makeMangaOfflineMembership(
        ownerName: removedFavorite.title,
        tid: "335",
        imageURLs: [removedImage, sharedImage]
    ))
    try await offlineStore.saveMembership(makeMangaOfflineMembership(
        ownerName: remainingFavorite.title,
        tid: "336",
        imageURLs: [sharedImage]
    ))
    _ = try await offlineStore.enqueueOfflineCacheWork(makeMangaOfflineWorkRequest(
        ownerName: removedFavorite.title,
        tid: "337",
        targetImageURLs: [workImage]
    ))
    try await offlineStore.updateOfflineCacheWorkProgress(
        ownerName: removedFavorite.title,
        tid: "337",
        targetImageURLs: [workImage],
        completedImageURLs: [workImage],
        currentBytesPerSecond: nil
    )

    _ = try await store.deleteFavorites(ids: [removedFavorite.id])

    #expect(await offlineStore.membership(ownerName: removedFavorite.title, tid: "335") != nil)
    #expect(await offlineStore.offlineCacheWork(ownerName: removedFavorite.title, tid: "337") != nil)
    #expect(await offlineStore.offlineImageData(for: removedImage) == Data([1]))
    #expect(await offlineStore.offlineImageData(for: workImage) == Data([3]))
    #expect(await offlineStore.offlineImageData(for: sharedImage) == Data([2]))
    #expect(await offlineStore.membership(ownerName: remainingFavorite.title, tid: "336") != nil)
}

@Test func favoriteStoreRemoteReconcilePreservesMangaOfflineCacheForDisappearingFavorite() async throws {
    let defaults = try #require(UserDefaults(suiteName: makeIsolatedDefaultsSuiteName(prefix: "favorite-reconcile-offline-cache")))
    let root = makeTemporaryDirectory(prefix: "favorite-reconcile-offline-cache")
    let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: root.appendingPathComponent("offline", isDirectory: true))
    let store = FavoriteStore(defaults: defaults, key: "favorites", mangaOfflineCacheStore: offlineStore)
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=338&mobile=2"))
    let favorite = Favorite(id: "favorite-reconciled-away", title: "远端删除漫画", url: favoriteURL, remoteFavoriteID: "remote-338", type: .manga)
    let imageURL = try #require(URL(string: "https://img.example.com/favorite-reconcile.jpg"))

    try await store.saveFavorites([favorite])
    try await offlineStore.saveOfflineImageData(Data([4]), for: imageURL)
    try await offlineStore.saveMembership(makeMangaOfflineMembership(
        ownerName: favorite.title,
        tid: "338",
        imageURLs: [imageURL]
    ))

    _ = try await store.mergeRemoteFavorites([])

    let preserved = try #require(await store.loadFavorites().first)
    #expect(preserved.url == favoriteURL)
    #expect(preserved.remoteFavoriteID == nil)
    #expect(await offlineStore.membership(ownerName: favorite.title, tid: "338") != nil)
    #expect(await offlineStore.offlineImageData(for: imageURL) == Data([4]))
}

@Test func favoriteStoreCreatingNovelFavoriteFromReadingPositionTouchesListAndReadingClocks() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-create-novel-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-create-novel-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=333&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString

    _ = try await store.updateNovelReadingPosition(NovelReadingPosition(threadURL: url, view: 4, chapterTitle: "第四章"))
    let afterCreate = await store.loadLibrarySnapshot().syncMetadata
    let listClock = try #require(afterCreate.remoteFavoritesUpdatedAt)
    let readingClock = try #require(afterCreate.readingPositionUpdatedAtByCanonicalURL[canonicalKey])

    #expect(listClock == readingClock)

    _ = try await store.updateNovelReadingPosition(NovelReadingPosition(threadURL: url, view: 5, chapterTitle: "第五章"))
    let afterExistingUpdate = await store.loadLibrarySnapshot().syncMetadata
    #expect(afterExistingUpdate.remoteFavoritesUpdatedAt == listClock)
}

@Test func favoriteStoreCreatingMangaFavoriteFromReadingPositionTouchesListAndReadingClocks() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-create-manga-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-create-manga-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=334&mobile=2"))
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=334&page=2&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString

    _ = try await store.updateMangaProgress(for: url, chapterURL: chapterURL, chapterTitle: "第二话", pageIndex: 7)
    let metadata = await store.loadLibrarySnapshot().syncMetadata
    let listClock = try #require(metadata.remoteFavoritesUpdatedAt)
    let readingClock = try #require(metadata.readingPositionUpdatedAtByCanonicalURL[canonicalKey])

    #expect(listClock == readingClock)
}

@Test func favoriteLibrarySnapshotPersistsTagsAcrossRemoteRefresh() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-tag-model-tests"))
    defaults.removePersistentDomain(forName: "favorite-tag-model-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303&mobile=2"))
    let tag = FavoriteTag(
        id: "tag-love",
        name: "爱情",
        color: .red,
        manualOrder: 0,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let favorite = Favorite(
        title: "带标签收藏",
        url: url,
        tagIDs: [tag.id]
    )

    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(
            favorites: [favorite],
            collections: [],
            tags: [tag]
        )
    )

    let stored = await store.loadLibrarySnapshot()
    #expect(stored.tags == [tag])
    #expect(stored.favorites.first?.tagIDs == [tag.id])

    _ = try await store.mergeRemoteFavorites([])
    let archived = await store.loadLibrarySnapshot()
    #expect(archived.favorites.first?.tagIDs == [tag.id])

    _ = try await store.mergeRemoteFavorites([
        Favorite(title: "远端返回", url: url)
    ])
    let restored = await store.loadLibrarySnapshot()
    #expect(restored.favorites.first?.tagIDs == [tag.id])
}

@Test func favoriteLibrarySnapshotDecodesLegacyTagsAndDropsDanglingTagReferences() async throws {
    let legacySnapshot = """
    {
      "favorites": [],
      "collections": [],
      "archivedMetadata": [
        {
          "canonicalThreadURL": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=304",
          "displayName": "旧归档",
          "lastPage": 1,
          "lastView": 1,
          "lastChapter": null,
          "authorID": null,
          "novelResumePoint": null,
          "isHidden": false,
          "type": 1,
          "lastMangaURL": null,
          "parentCollectionID": null,
          "manualOrder": 0,
          "lastReadAt": null
        }
      ]
    }
    """

    let decoded = try JSONDecoder().decode(FavoriteLibrarySnapshot.self, from: Data(legacySnapshot.utf8))

    #expect(decoded.tags.isEmpty)

    let defaults = try #require(UserDefaults(suiteName: "favorite-tag-sanitize-tests"))
    defaults.removePersistentDomain(forName: "favorite-tag-sanitize-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=305&mobile=2"))
    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(
            favorites: [
                Favorite(title: "悬空标签", url: url, tagIDs: ["missing-tag", "missing-tag"])
            ],
            collections: [],
            tags: []
        )
    )

    let loaded = await store.loadLibrarySnapshot()
    #expect(loaded.favorites.first?.tagIDs == [])
}

@Test func favoriteStoreCanCreateEditAndDeleteTags() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-tag-management-tests"))
    defaults.removePersistentDomain(forName: "favorite-tag-management-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=306&mobile=2"))
    let existing = FavoriteTag(
        id: "existing",
        name: "既有",
        color: .gray,
        manualOrder: 0,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(
            favorites: [
                Favorite(title: "标签管理", url: url, tagIDs: [existing.id])
            ],
            collections: [],
            tags: [existing]
        )
    )

    let createdAt = Date(timeIntervalSince1970: 20)
    let created = try await store.createTag(
        name: " 新标签 ",
        color: .red,
        date: createdAt
    )

    #expect(created.tags.map(\.name) == ["新标签", "既有"])
    #expect(created.tags.first?.manualOrder == 0)
    #expect(created.tags.first?.createdAt == createdAt)
    #expect(created.tags.first?.updatedAt == createdAt)
    #expect(created.tags.last?.manualOrder == 1)

    let newTagID = try #require(created.tags.first?.id)
    let editedAt = Date(timeIntervalSince1970: 30)
    let edited = try await store.updateTag(
        id: newTagID,
        name: "改名",
        color: .blue,
        date: editedAt
    )
    let editedTag = try #require(edited.tags.first(where: { $0.id == newTagID }))
    #expect(editedTag.name == "改名")
    #expect(editedTag.color == .blue)
    #expect(editedTag.createdAt == createdAt)
    #expect(editedTag.updatedAt == editedAt)

    await #expect(throws: YamiboError.self) {
        try await store.updateTag(id: newTagID, name: "既有", color: .blue)
    }

    let deleted = try await store.deleteTag(id: existing.id)
    #expect(deleted.tags.map(\.id) == [newTagID])
    #expect(deleted.favorites.first?.tagIDs == [])
}

@Test func favoriteStoreCanOverwriteTagsForMultipleFavoritesWithoutMovingThem() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-batch-tag-tests"))
    defaults.removePersistentDomain(forName: "favorite-batch-tag-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let rootURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=406&mobile=2"))
    let collectionURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=407&mobile=2"))
    let untouchedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=408&mobile=2"))
    let oldTag = FavoriteTag(id: "old", name: "旧", color: .gray, manualOrder: 0)
    let newTag = FavoriteTag(id: "new", name: "新", color: .red, manualOrder: 1)
    let rootFavorite = Favorite(title: "根收藏", url: rootURL, manualOrder: 4, tagIDs: [oldTag.id])
    let collectionFavorite = Favorite(
        title: "合集收藏",
        url: collectionURL,
        parentCollectionID: "collection-1",
        manualOrder: 2,
        tagIDs: [oldTag.id]
    )
    let untouchedFavorite = Favorite(title: "未选择", url: untouchedURL, manualOrder: 5, tagIDs: [oldTag.id])
    let collection = FavoriteCollection(id: "collection-1", name: "合集", manualOrder: 0)

    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(
            favorites: [rootFavorite, collectionFavorite, untouchedFavorite],
            collections: [collection],
            tags: [oldTag, newTag]
        )
    )
    let baseline = await store.loadLibrarySnapshot()
    let baselineRoot = try #require(baseline.favorites.first(where: { $0.id == rootFavorite.id }))
    let baselineCollectionFavorite = try #require(baseline.favorites.first(where: { $0.id == collectionFavorite.id }))

    let updated = try await store.setTagIDs([newTag.id], forFavoriteIDs: [rootFavorite.id, collectionFavorite.id])
    let updatedRoot = try #require(updated.favorites.first(where: { $0.id == rootFavorite.id }))
    let updatedCollectionFavorite = try #require(updated.favorites.first(where: { $0.id == collectionFavorite.id }))
    let unchangedFavorite = try #require(updated.favorites.first(where: { $0.id == untouchedFavorite.id }))

    #expect(updatedRoot.tagIDs == [newTag.id])
    #expect(updatedRoot.parentCollectionID == nil)
    #expect(updatedRoot.manualOrder == baselineRoot.manualOrder)
    #expect(updatedCollectionFavorite.tagIDs == [newTag.id])
    #expect(updatedCollectionFavorite.parentCollectionID == collection.id)
    #expect(updatedCollectionFavorite.manualOrder == baselineCollectionFavorite.manualOrder)
    #expect(unchangedFavorite.tagIDs == [oldTag.id])

    let cleared = try await store.setTagIDs([], forFavoriteIDs: [rootFavorite.id, collectionFavorite.id])
    #expect(cleared.favorites.first(where: { $0.id == rootFavorite.id })?.tagIDs == [])
    #expect(cleared.favorites.first(where: { $0.id == collectionFavorite.id })?.tagIDs == [])
}

@Test func favoriteStoreRefreshesOnlyTagsWhoseAssociationsChanged() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-tag-association-date-tests"))
    defaults.removePersistentDomain(forName: "favorite-tag-association-date-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let oldDate = Date(timeIntervalSince1970: 10)
    let changedDate = Date(timeIntervalSince1970: 20)
    let first = Favorite(
        title: "第一",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=409&mobile=2")),
        tagIDs: ["old"]
    )
    let second = Favorite(
        title: "第二",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=410&mobile=2")),
        tagIDs: ["new"]
    )
    let oldTag = FavoriteTag(id: "old", name: "旧", color: .gray, manualOrder: 0, updatedAt: oldDate)
    let newTag = FavoriteTag(id: "new", name: "新", color: .red, manualOrder: 1, updatedAt: oldDate)
    let untouchedTag = FavoriteTag(id: "untouched", name: "未变", color: .blue, manualOrder: 2, updatedAt: oldDate)

    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(
            favorites: [first, second],
            collections: [],
            tags: [oldTag, newTag, untouchedTag]
        )
    )

    let updated = try await store.setTagIDs(["new"], forFavoriteIDs: [first.id], date: changedDate)

    #expect(updated.tags.first(where: { $0.id == oldTag.id })?.updatedAt == changedDate)
    #expect(updated.tags.first(where: { $0.id == newTag.id })?.updatedAt == changedDate)
    #expect(updated.tags.first(where: { $0.id == untouchedTag.id })?.updatedAt == oldDate)
}

@Test func favoriteStoreCanReorderTagsAndRefreshOnlyDraggedTag() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-tag-reorder-tests"))
    defaults.removePersistentDomain(forName: "favorite-tag-reorder-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let oldDate = Date(timeIntervalSince1970: 30)
    let movedDate = Date(timeIntervalSince1970: 40)
    let first = FavoriteTag(id: "first", name: "第一", color: .gray, manualOrder: 0, updatedAt: oldDate)
    let second = FavoriteTag(id: "second", name: "第二", color: .red, manualOrder: 1, updatedAt: oldDate)
    let third = FavoriteTag(id: "third", name: "第三", color: .blue, manualOrder: 2, updatedAt: oldDate)

    try await store.saveLibrarySnapshot(
        FavoriteLibrarySnapshot(favorites: [], collections: [], tags: [first, second, third])
    )

    let reordered = try await store.reorderTags(
        visibleIDs: [first.id, second.id, third.id],
        fromOffsets: IndexSet(integer: 2),
        toOffset: 0,
        date: movedDate
    )

    #expect(reordered.tags.map(\.id) == [third.id, first.id, second.id])
    #expect(reordered.tags.map(\.manualOrder) == [0, 1, 2])
    #expect(reordered.tags.first(where: { $0.id == third.id })?.updatedAt == movedDate)
    #expect(reordered.tags.first(where: { $0.id == first.id })?.updatedAt == oldDate)
    #expect(reordered.tags.first(where: { $0.id == second.id })?.updatedAt == oldDate)
}

@Test func favoriteStoreUpdatesMangaProgress() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-manga-progress-tests"))
    defaults.removePersistentDomain(forName: "favorite-manga-progress-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=40&mobile=2"))
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=41&mobile=2"))

    _ = try await store.updateMangaProgress(
        for: url,
        chapterURL: chapterURL,
        chapterTitle: "第5话",
        pageIndex: 8
    )

    let favorite = await store.favorite(for: url)
    #expect(favorite?.lastMangaURL == chapterURL)
    #expect(favorite?.lastChapter == "第5话")
    #expect(favorite?.mangaPageIndex == 8)
    #expect(favorite?.type == .manga)
}

@Test func favoriteStoreMergesRemoteFavoritesAndPreservesLocalEntriesWithoutArchive() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-store-tests"))
    defaults.removePersistentDomain(forName: "favorite-store-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let localOnly = Favorite(
        title: "旧收藏",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")!
    )
    try await store.saveFavorites([localOnly])

    let remote = [
        Favorite(
            title: "新收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")!
        )
    ]

    let merged = try await store.mergeRemoteFavorites(remote)
    let snapshot = await store.loadLibrarySnapshot()

    #expect(merged.count == 2)
    #expect(merged.contains(where: { $0.id == localOnly.id }))
    #expect(merged.contains(where: { $0.title == "新收藏" }))
    #expect(snapshot.favorites.contains(where: { $0.id == localOnly.id }))
}

@Test func favoriteStoreCanUpdateFavoriteType() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-type-tests"))
    defaults.removePersistentDomain(forName: "favorite-type-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let favorite = Favorite(
        title: "测试收藏",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=99&mobile=2")!
    )
    try await store.saveFavorites([favorite])

    let updated = try await store.setType(.novel, for: favorite.id)
    #expect(updated.first?.type == .novel)
}

@Test func favoriteStoreCanPersistDisplayNameAndClearIt() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-display-name-tests"))
    defaults.removePersistentDomain(forName: "favorite-display-name-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let favorite = Favorite(
        title: "原标题",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=199&mobile=2")!
    )
    try await store.saveFavorites([favorite])

    let renamed = try await store.setDisplayName("自定义名称", for: favorite.id)
    #expect(renamed.first?.displayName == "自定义名称")
    #expect(renamed.first?.resolvedDisplayTitle == "自定义名称")

    let cleared = try await store.setDisplayName("   ", for: favorite.id)
    #expect(cleared.first?.displayName == nil)
    #expect(cleared.first?.resolvedDisplayTitle == "原标题")
}

@Test func favoriteStoreNoOpMetadataUpdatesDoNotAdvanceMetadataClock() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-metadata-noop-clock-tests"))
    defaults.removePersistentDomain(forName: "favorite-metadata-noop-clock-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=200&mobile=2"))
    let canonicalKey = ReaderCacheIdentity.canonicalThreadURL(from: url).absoluteString
    let baseClock = Date(timeIntervalSince1970: 1_000)
    let favorite = Favorite(
        title: "原标题",
        displayName: "自定义名称",
        url: url,
        type: .novel
    )
    var syncMetadata = FavoriteLibrarySyncMetadata()
    syncMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey] = baseClock

    try await store.saveLibrarySnapshot(FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        syncMetadata: syncMetadata
    ))

    _ = try await store.setType(.novel, for: favorite.id)
    _ = try await store.setDisplayName("  自定义名称  ", for: favorite.id)

    let afterNoOps = await store.loadLibrarySnapshot()
    #expect(afterNoOps.syncMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey] == baseClock)

    _ = try await store.setDisplayName("新名称", for: favorite.id)
    let afterRealChange = await store.loadLibrarySnapshot()
    let changedClock = try #require(afterRealChange.syncMetadata.favoriteMetadataUpdatedAtByCanonicalURL[canonicalKey])
    #expect(changedClock > baseClock)
    #expect(afterRealChange.favorites.first?.displayName == "新名称")
}

@Test func favoriteStoreMergePreservesLocalDisplayName() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-merge-display-name-tests"))
    defaults.removePersistentDomain(forName: "favorite-merge-display-name-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=288&mobile=2"))

    try await store.saveFavorites([
        Favorite(title: "旧标题", displayName: "我的名字", url: url)
    ])

    let merged = try await store.mergeRemoteFavorites([
        Favorite(title: "新标题", url: url)
    ])

    #expect(merged.first?.title == "新标题")
    #expect(merged.first?.displayName == "我的名字")
    #expect(merged.first?.resolvedDisplayTitle == "我的名字")
}

@Test func favoriteStoreMergeUpdatesRemoteFavoriteIDFromServer() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-merge-remote-id-tests"))
    defaults.removePersistentDomain(forName: "favorite-merge-remote-id-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=289&mobile=2"))

    try await store.saveFavorites([
        Favorite(title: "旧标题", url: url)
    ])

    let merged = try await store.mergeRemoteFavorites([
        Favorite(title: "新标题", url: url, remoteFavoriteID: "9988")
    ])

    #expect(merged.first?.remoteFavoriteID == "9988")
}

@Test func favoriteStoreCanPersistManualReorder() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-reorder-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let first = Favorite(title: "第一项", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=601&mobile=2")))
    let second = Favorite(title: "第二项", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=602&mobile=2")))
    let third = Favorite(title: "第三项", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=603&mobile=2")))
    try await store.saveFavorites([first, second, third])

    let reordered = try await store.reorderFavorites(
        visibleIDs: [first.id, second.id, third.id],
        fromOffsets: IndexSet(integer: 0),
        toOffset: 3
    )

    #expect(reordered.map(\.id) == [second.id, third.id, first.id])
    let persisted = await store.loadFavorites()
    #expect(persisted.map(\.id) == [second.id, third.id, first.id])
}

@Test func favoriteStoreReordersVisibleSubsetWithoutDisturbingExcludedEntries() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-reorder-subset-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let firstVisible = Favorite(title: "可见1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=611&mobile=2")), type: .novel)
    let hidden = Favorite(title: "中间项", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=612&mobile=2")), type: .novel)
    let secondVisible = Favorite(title: "可见2", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=613&mobile=2")), type: .novel)
    let otherType = Favorite(title: "其他分类", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=614&mobile=2")), type: .manga)
    let thirdVisible = Favorite(title: "可见3", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=615&mobile=2")), type: .novel)
    try await store.saveFavorites([firstVisible, hidden, secondVisible, otherType, thirdVisible])

    let reordered = try await store.reorderFavorites(
        visibleIDs: [firstVisible.id, secondVisible.id, thirdVisible.id],
        fromOffsets: IndexSet(integer: 2),
        toOffset: 0
    )

    #expect(reordered.map(\.id) == [thirdVisible.id, hidden.id, firstVisible.id, otherType.id, secondVisible.id])
}

@Test func favoriteStoreMergePreservesManualOrderAndPrependsNewRemoteFavorites() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-merge-order-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let localFirst = Favorite(title: "本地1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=621&mobile=2")), remoteFavoriteID: "1")
    let localSecond = Favorite(title: "本地2", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=622&mobile=2")), remoteFavoriteID: "2")
    let hiddenLocalOnly = Favorite(title: "本地保留", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=623&mobile=2")))
    let removedRemote = Favorite(title: "将被移除", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=624&mobile=2")))
    try await store.saveFavorites([localFirst, localSecond, hiddenLocalOnly, removedRemote])

    let newRemote = Favorite(title: "新同步收藏", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=625&mobile=2")), remoteFavoriteID: "25")
    let remoteSecond = Favorite(title: "远端更新2", url: localSecond.url, remoteFavoriteID: "22", type: .manga)
    let remoteFirst = Favorite(title: "远端更新1", url: localFirst.url, remoteFavoriteID: "11", type: .novel)

    let merged = try await store.mergeRemoteFavorites([newRemote, remoteSecond, remoteFirst])

    #expect(merged.map(\.id) == [newRemote.id, localFirst.id, localSecond.id, hiddenLocalOnly.id, removedRemote.id])
    #expect(merged[1].title == "远端更新1")
    #expect(merged[2].title == "远端更新2")
    #expect(merged[2].remoteFavoriteID == "22")
    let snapshot = await store.loadLibrarySnapshot()
    #expect(snapshot.favorites.first(where: { $0.id == hiddenLocalOnly.id })?.remoteFavoriteID == nil)
    #expect(snapshot.favorites.first(where: { $0.id == removedRemote.id })?.remoteFavoriteID == nil)
}

@Test func favoriteStoreCanDeleteFavoriteByID() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-delete-tests"))
    defaults.removePersistentDomain(forName: "favorite-delete-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let first = Favorite(
        title: "保留项",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=390&mobile=2")!
    )
    let second = Favorite(
        title: "删除项",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=391&mobile=2")!
    )
    try await store.saveFavorites([first, second])

    let updated = try await store.deleteFavorite(id: second.id)
    #expect(updated.count == 1)
    #expect(updated.first?.id == first.id)
}

@Test func favoriteStoreLoadsLegacyFavoritesWithDefaultCollectionFields() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-legacy-migration-tests")
    let legacyPayload = """
    [
      {
        "id": "legacy-1",
        "title": "旧收藏1",
        "url": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2",
        "lastPage": 3,
        "lastView": 1,
        "isHidden": false,
        "type": 1
      },
      {
        "id": "legacy-2",
        "title": "旧收藏2",
        "url": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&mobile=2",
        "lastPage": 0,
        "lastView": 1,
        "isHidden": false,
        "type": 2
      }
    ]
    """
    defaults.set(Data(legacyPayload.utf8), forKey: "favorites")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let loaded = await store.loadFavorites()

    #expect(loaded.map(\.id) == ["legacy-1", "legacy-2"])
    #expect(loaded.map(\.parentCollectionID) == [nil, nil])
    #expect(loaded.map(\.manualOrder) == [0, 1])
    #expect(loaded.map(\.lastReadAt) == [nil, nil])
}

@Test func favoriteStoreCanCreateMoveAndDissolveCollections() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-collections-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let first = Favorite(title: "根页1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=903&mobile=2")))
    let second = Favorite(title: "根页2", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=904&mobile=2")))
    let third = Favorite(title: "根页3", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=905&mobile=2")))
    try await store.saveFavorites([first, second, third])

    let created = try await store.createCollection(name: "测试合集", favoriteIDs: [first.id, third.id])
    let collectionID = try #require(created.collections.first?.id)
    #expect(created.collections.map(\.name) == ["测试合集"])
    #expect(created.favorites.first(where: { $0.id == first.id })?.parentCollectionID == collectionID)
    #expect(created.favorites.first(where: { $0.id == third.id })?.parentCollectionID == collectionID)
    #expect(created.favorites.first(where: { $0.id == second.id })?.parentCollectionID == nil)

    let movedBack = try await store.moveFavorites(ids: [third.id], toCollectionID: nil)
    #expect(movedBack.favorites.first(where: { $0.id == third.id })?.parentCollectionID == nil)

    let dissolved = try await store.dissolveCollections(ids: [collectionID])
    #expect(dissolved.collections.isEmpty)
    #expect(dissolved.favorites.allSatisfy { $0.parentCollectionID == nil })
}

@Test func favoriteStoreCanRenameCollections() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-collection-edit-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let favorite = Favorite(title: "根页收藏", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=908&mobile=2")))
    try await store.saveFavorites([favorite])

    let created = try await store.createCollection(name: "旧合集", favoriteIDs: [favorite.id])
    let collectionID = try #require(created.collections.first?.id)

    let renamed = try await store.setCollectionName("  新合集  ", for: collectionID)
    #expect(renamed.collections.first?.name == "新合集")

    let loaded = await store.loadCollections()
    #expect(loaded.first?.name == "新合集")
}

@Test func favoriteStoreCanReorderMixedRootEntries() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-root-mixed-reorder-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let first = Favorite(title: "根页1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=906&mobile=2")))
    let second = Favorite(title: "根页2", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=907&mobile=2")))
    try await store.saveFavorites([first, second])

    let created = try await store.createCollection(name: "合集A", favoriteIDs: [first.id])
    let collection = try #require(created.collections.first)

    let reordered = try await store.reorderRootEntries(
        visibleEntryKeys: ["collection:\(collection.id)", "favorite:\(second.id)"],
        fromOffsets: IndexSet(integer: 1),
        toOffset: 0
    )

    #expect(reordered.collections.first?.manualOrder == 1)
    let rootFavorite = try #require(reordered.favorites.first(where: { $0.id == second.id }))
    #expect(rootFavorite.parentCollectionID == nil)
    #expect(rootFavorite.manualOrder == 0)
}

@Test func favoriteStoreMergePreservesCollectionMembershipAndManualOrder() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-collection-merge-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let first = Favorite(title: "旧标题1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=908&mobile=2")))
    let second = Favorite(title: "旧标题2", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=909&mobile=2")))
    try await store.saveFavorites([first, second])

    let created = try await store.createCollection(name: "合集A", favoriteIDs: [second.id])
    let collectionID = try #require(created.collections.first?.id)

    let merged = try await store.mergeRemoteFavorites([
        Favorite(title: "新标题1", url: first.url, remoteFavoriteID: "11"),
        Favorite(title: "新标题2", url: second.url, remoteFavoriteID: "22")
    ])

    let mergedSecond = try #require(merged.first(where: { $0.id == second.id }))
    #expect(mergedSecond.parentCollectionID == collectionID)
    #expect(mergedSecond.remoteFavoriteID == "22")
    #expect(mergedSecond.manualOrder == 0)
}

@Test func favoriteStorePreservesRemoteMissingFavoriteWithoutArchive() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-archive-removed-remote-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=930&mobile=2"))
    let collection = FavoriteCollection(id: "collection-a", name: "合集A")
    let resumePoint = ReaderResumePoint(
        view: 3,
        displayedTextOffset: 120,
        chapterOrdinal: 2,
        chapterTitle: "第二章",
        segmentProgress: 0.3,
        authorID: "77",
        readingModeHint: .vertical
    )
    let favorite = Favorite(
        title: "旧远端收藏",
        displayName: "我的收藏名",
        url: url,
        remoteFavoriteID: "remote-930",
        mangaPageIndex: 8,
        lastView: 3,
        lastChapter: "第二章",
        authorID: "77",
        novelResumePoint: resumePoint,
        novelMaxView: 6,
        novelDocumentSurfaceProgressPercent: 43,
        type: .novel,
        parentCollectionID: collection.id,
        manualOrder: 0,
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try await store.saveLibrarySnapshot(FavoriteLibrarySnapshot(favorites: [favorite], collections: [collection]))

    let merged = try await store.mergeRemoteFavorites([])
    let snapshot = await store.loadLibrarySnapshot()

    let preserved = try #require(merged.first)
    #expect(preserved.remoteFavoriteID == nil)
    #expect(preserved.displayName == "我的收藏名")
    #expect(preserved.parentCollectionID == collection.id)
    #expect(preserved.novelResumePoint == resumePoint)
    #expect(snapshot.favorites == [preserved])
}

@Test func settingsStoreResetRestoresDefaults() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "settings-reset-tests")
    let store = SettingsStore(defaults: defaults, key: "settings")

    try await store.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: false), homePage: .favorites))
    try await store.reset()

    let loaded = await store.load()
    #expect(loaded == AppSettings())
    #expect(loaded.homePage == .forum)
}

@Test func settingsStoreLoadSyncMatchesAsyncLoad() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "settings-sync-tests")
    let actorDefaults = try #require(UserDefaults(suiteName: suiteName))
    actorDefaults.removePersistentDomain(forName: suiteName)
    let syncDefaults = try #require(UserDefaults(suiteName: suiteName))
    let store = SettingsStore(defaults: actorDefaults, key: "settings")
    let saved = AppSettings(
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
        homePage: .favorites,
        usesDataSaverMode: true
    )

    try await store.save(saved)

    let syncLoaded = SettingsStore.loadSync(defaults: syncDefaults, key: "settings")
    let asyncLoaded = await store.load()

    #expect(syncLoaded == saved)
    #expect(syncLoaded == asyncLoaded)
}

@Test func sessionStoreResetRestoresDefaults() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "session-reset-tests")
    let store = SessionStore(defaults: defaults, key: "session")

    try await store.updateWebSession(
        cookie: "sid=reset",
        userAgent: "Test-UA",
        isLoggedIn: true
    )
    try await store.reset()

    let loaded = await store.load()
    #expect(loaded == SessionState())
}

@Test func readerResumeRouteStorePersistsNovelRouteAndClearsIt() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "reader-resume-novel-tests")
    let store = ReaderResumeRouteStore(defaults: defaults, key: "reader-route")
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=611&mobile=2"))
    let resumePoint = ReaderResumePoint(
        view: 2,
        displayedTextOffset: 20,
        chapterOrdinal: 3,
        chapterTitle: "第三章",
        segmentProgress: 0.5,
        authorID: "42",
        readingModeHint: .vertical
    )
    let context = ReaderLaunchContext(
        threadURL: threadURL,
        threadTitle: "测试小说",
        source: .resume,
        initialView: 2,
        authorID: "42",
        initialResumePoint: resumePoint
    )

    try await store.save(.novel(context))

    #expect(await store.load() == .novel(context))

    await store.clear()

    #expect(await store.load() == nil)
}

@Test func readerResumeRouteStorePersistsMangaRouteAndIgnoresInvalidData() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "reader-resume-manga-tests")
    let store = ReaderResumeRouteStore(defaults: defaults, key: "reader-route")
    let originalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=612&mobile=2"))
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=613&mobile=2"))
    let route = MangaPresentationRoute.native(
        MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: chapterURL,
            displayTitle: "测试漫画",
            source: .resume,
            initialPage: 7,
            directoryName: "测试漫画"
        )
    )

    try await store.save(.manga(route))

    let persistedRoute = try persistedResumeRoute(.manga(route))
    #expect(await store.load() == persistedRoute)

    let invalidDefaults = try makeIsolatedDefaults(prefix: "reader-resume-invalid-tests")
    invalidDefaults.set(Data("legacy".utf8), forKey: "reader-route")
    let invalidStore = ReaderResumeRouteStore(defaults: invalidDefaults, key: "reader-route")

    #expect(await invalidStore.load() == nil)
}

private func persistedResumeRoute(_ route: ReaderResumeRoute) throws -> ReaderResumeRoute {
    let data = try JSONEncoder().encode(route)
    return try JSONDecoder().decode(ReaderResumeRoute.self, from: data)
}

@Test func readerResumeRouteStoreSuppressesLatePositionSaveAfterClearUntilNextPresentation() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "reader-resume-suppression-tests")
    let store = ReaderResumeRouteStore(defaults: defaults, key: "reader-route")
    let firstURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=614&mobile=2"))
    let secondURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=615&mobile=2"))
    let firstRoute = ReaderResumeRoute.novel(
        ReaderLaunchContext(
            threadURL: firstURL,
            threadTitle: "第一本",
            source: .resume
        )
    )
    let secondRoute = ReaderResumeRoute.novel(
        ReaderLaunchContext(
            threadURL: secondURL,
            threadTitle: "第二本",
            source: .resume
        )
    )

    try await store.save(firstRoute)
    await store.clear()
    try await store.saveReadingPosition(firstRoute)

    #expect(await store.load() == nil)

    try await store.save(secondRoute)

    #expect(await store.load() == secondRoute)
}

@Test func readingProgressStoreSavesNovelAndMangaProgressByCanonicalThreadURL() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "reading-progress-store-tests")
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let legacyData = Data(#"{"legacy":true}"#.utf8)
    defaults.set(legacyData, forKey: "reading-progress")
    let database = try YamiboDatabase.openPool(
        rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    let store = ReadingProgressStore(
        defaults: defaults,
        key: "reading-progress",
        databasePool: database
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/thread-12345-1-1.html"))
    let canonicalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=12345"))
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/thread-12346-1-1.html"))
    let threadCoverURL = try #require(URL(string: "https://img.example.com/thread-cover.jpg"))
    let resumePoint = ReaderResumePoint(
        view: 3,
        displayedTextOffset: 128,
        chapterOrdinal: 2,
        chapterTitle: "第三章",
        segmentProgress: 0.4,
        authorID: "42",
        readingModeHint: .vertical
    )

    try await store.saveNovel(NovelReadingPosition(
        threadURL: threadURL,
        view: 2,
        maxView: 8,
        chapterTitle: "旧章",
        authorID: "1",
        resumePoint: resumePoint,
        documentSurfaceProgressPercent: 37,
        threadCoverURL: threadCoverURL
    ))

    let novel = await store.load(for: canonicalURL)
    #expect(novel?.kind == .novel)
    #expect(novel?.threadURL.absoluteString == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=12345")
    #expect(novel?.threadID == "12345")
    #expect(novel?.novel?.lastView == 3)
    #expect(novel?.novel?.lastChapter == "第三章")
    #expect(novel?.novel?.authorID == "42")
    #expect(novel?.novel?.novelMaxView == 8)
    #expect(novel?.novel?.novelDocumentSurfaceProgressPercent == 37)
    #expect(novel?.novel?.threadCoverURL == threadCoverURL)
    #expect(novel?.novel?.novelResumePoint == resumePoint)

    try await store.saveManga(MangaProgressReadingPosition(
        threadURL: canonicalURL,
        chapterURL: chapterURL,
        chapterTitle: "第 12 话",
        pageIndex: 6,
        pageCount: 12
    ))

    let manga = await store.load(for: threadURL)
    #expect(manga?.kind == .manga)
    #expect(manga?.novel == nil)
    #expect(manga?.threadID == "12345")
    #expect(manga?.manga?.lastMangaURL.absoluteString == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=12346")
    #expect(manga?.manga?.chapterThreadID == "12346")
    #expect(manga?.manga?.lastChapter == "第 12 话")
    #expect(manga?.manga?.mangaPageIndex == 6)
    #expect(manga?.manga?.mangaPageCount == 12)
    let legacyDefaultsAfterSave = try #require(UserDefaults(suiteName: suiteName))
    #expect(legacyDefaultsAfterSave.data(forKey: "reading-progress") == legacyData)

    let databaseState = try await database.read { db in
        let columns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('reading_progress')")
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, kind, target_kind, thread_id, manga_chapter_thread_id, novel_last_view, manga_page_index
            FROM reading_progress
            ORDER BY kind
            """
        )
        return (
            columns: columns,
            rows: rows.map { row in
                (
                    id: row["id"] as String,
                    kind: row["kind"] as String,
                    targetKind: row["target_kind"] as String,
                    threadID: row["thread_id"] as String?,
                    mangaChapterThreadID: row["manga_chapter_thread_id"] as String?,
                    novelLastView: row["novel_last_view"] as Int?,
                    mangaPageIndex: row["manga_page_index"] as Int?
                )
            }
        )
    }
    #expect(!databaseState.columns.contains("thread_url"))
    #expect(!databaseState.columns.contains("last_manga_url"))
    #expect(databaseState.rows.count == 2)
    #expect(databaseState.rows.contains { $0.id == "thread:novel:12345" && $0.threadID == "12345" && $0.novelLastView == 3 })
    #expect(databaseState.rows.contains { $0.kind == ReadingProgressKind.manga.rawValue && $0.threadID == "12345" && $0.mangaChapterThreadID == "12346" && $0.mangaPageIndex == 6 })
}

@Test func readingProgressStoreMatchesNovelProgressWithAndWithoutExtraQuery() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "reading-progress-extra-tests")
    let store = ReadingProgressStore(
        defaults: defaults,
        key: "reading-progress"
    )
    let listURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?extra=page%3D1&mod=viewthread&tid=521519&mobile=2&page=25&authorid=406769"))
    let readerURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=521519"))

    try await store.saveNovel(NovelReadingPosition(threadURL: listURL, view: 25, chapterTitle: "第二十五章"))

    let progress = await store.load(for: readerURL)
    #expect(progress?.threadURL.absoluteString == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=521519")
    #expect(progress?.kind == .novel)
    #expect(progress?.novel?.lastView == 25)
    #expect(progress?.novel?.lastChapter == "第二十五章")
}

@Test func deletingFavoriteDoesNotDeleteIndependentReadingProgress() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "reading-progress-delete-favorite-tests")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let favoriteStore = try FavoriteStore(testSuiteName: suiteName, key: "favorites")
    let progressStore = try ReadingProgressStore(
        testSuiteName: suiteName,
        key: "reading-progress"
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=510"))
    let favorite = Favorite(title: "小说", url: threadURL, type: .novel)
    try await favoriteStore.saveFavorites([favorite])
    try await progressStore.saveNovel(NovelReadingPosition(threadURL: threadURL, view: 3, chapterTitle: "第三章"))

    _ = try await favoriteStore.deleteFavorites(ids: [favorite.id])

    #expect(await favoriteStore.favorite(for: threadURL) == nil)
    let progress = await progressStore.load(for: threadURL)
    #expect(progress?.novel?.lastView == 3)
    #expect(progress?.novel?.lastChapter == "第三章")
}

@Test func favoriteStoreClearAllRemovesAllFavorites() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-clear-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    try await store.saveFavorites([
        Favorite(
            title: "测试收藏",
            url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=515&mobile=2"))
        )
    ])
    let favoriteID = try #require(await store.loadFavorites().first?.id)
    _ = try await store.createCollection(name: "待清空合集", favoriteIDs: [favoriteID])

    try await store.clearAll()

    let loaded = await store.loadFavorites()
    let collections = await store.loadCollections()
    #expect(loaded.isEmpty)
    #expect(collections.isEmpty)
}

@Test func readerCacheStoreReportsUsageAndCanClearAll() async throws {
    let baseDirectory = makeTemporaryDirectory(prefix: "reader-cache-tests")
    let store = ReaderCacheStore(baseDirectory: baseDirectory)
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=600&mobile=2"))

    try await store.save(
        ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            segments: [.text("测试内容", chapterTitle: "第一章")]
        )
    )

    let usage = await store.totalDiskUsageBytes()
    #expect(usage > 0)

    try await store.clearAll()

    let clearedUsage = await store.totalDiskUsageBytes()
    #expect(clearedUsage == 0)
}

@Test func favoriteBackgroundImageStoreSavesLoadsDeletesAndPrunes() async throws {
    let baseDirectory = makeTemporaryDirectory(prefix: "favorite-background-tests")
    let store = FavoriteBackgroundImageStore(baseDirectory: baseDirectory)
    let firstData = Data(repeating: 3, count: 32)
    let secondData = Data(repeating: 8, count: 48)

    try await store.save(firstData, imageID: "first")
    try await store.save(secondData, imageID: "second")

    #expect(await store.loadData(imageID: "first") == firstData)
    #expect(await store.loadData(imageID: "second") == secondData)

    try await store.prune(keeping: "second")
    #expect(await store.loadData(imageID: "first") == nil)
    #expect(await store.loadData(imageID: "second") == secondData)

    try await store.delete(imageID: "second")
    #expect(await store.loadData(imageID: "second") == nil)

    try await store.save(firstData, imageID: "third")
    try await store.deleteAll()
    #expect(await store.loadData(imageID: "third") == nil)
}

@Test func clearingReaderCacheDoesNotDeleteFavoriteBackground() async throws {
    let rootDirectory = makeTemporaryDirectory(prefix: "cache-clear-background-root")
    let readerCacheStore = ReaderCacheStore(baseDirectory: rootDirectory.appendingPathComponent("reader-cache", isDirectory: true))
    let backgroundStore = FavoriteBackgroundImageStore(baseDirectory: rootDirectory.appendingPathComponent("favorite-background", isDirectory: true))
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=701&mobile=2"))
    let backgroundData = Data(repeating: 4, count: 64)

    try await readerCacheStore.save(
        ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            segments: [.text("测试", chapterTitle: nil)]
        )
    )
    try await backgroundStore.save(backgroundData, imageID: "background")

    try await readerCacheStore.clearAll()

    #expect(await backgroundStore.loadData(imageID: "background") == backgroundData)
}

@Test func favoriteBackgroundLayoutClampsScaleAndOffsetsForDifferentAspectRatios() {
    let settings = FavoriteBackgroundSettings(
        isEnabled: true,
        imageID: "background",
        scale: 4,
        offsetX: 2,
        offsetY: -2,
        blurRadius: 0
    )
    let portraitFrame = FavoriteBackgroundLayout.renderedFrame(
        imageSize: CGSize(width: 200, height: 100),
        containerSize: CGSize(width: 100, height: 200),
        settings: settings
    )
    #expect(portraitFrame.size == CGSize(width: 1200, height: 600))
    #expect(portraitFrame.offset == CGSize(width: 550, height: -200))

    let offsets = FavoriteBackgroundLayout.normalizedOffsets(
        imageSize: CGSize(width: 100, height: 200),
        containerSize: CGSize(width: 300, height: 200),
        scale: 1,
        proposedOffset: CGSize(width: 1000, height: 1000)
    )
    #expect(offsets.offsetX == 0)
    #expect(offsets.offsetY == 1)
}

@Test func appContextResetApplicationDataClearsPersistedState() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "app-reset-tests")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let rootDirectory = makeTemporaryDirectory(prefix: "app-reset-root")

    let sessionStore = SessionStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "session")
    let settingsStore = SettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "settings")
    let readerResumeRouteStore = ReaderResumeRouteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "reader-route")
    let favoriteStore = FavoriteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "favorites")
    let localFavoriteLibraryStore = LocalFirstFavoriteLibraryStore(
        defaults: try #require(UserDefaults(suiteName: suiteName)),
        key: "local-favorites"
    )
    let contentCoverStore = ContentCoverStore(
        defaults: try #require(UserDefaults(suiteName: suiteName)),
        key: "content-covers"
    )
    let readerCacheStore = ReaderCacheStore(baseDirectory: rootDirectory.appendingPathComponent("reader-cache", isDirectory: true))
    let favoriteBackgroundImageStore = FavoriteBackgroundImageStore(
        baseDirectory: rootDirectory.appendingPathComponent("favorite-background", isDirectory: true)
    )
    let mangaDirectoryStore = try makeTestGRDBMangaDirectoryStore(rootDirectory: rootDirectory)
    let mangaChapterDocumentStore = try makeTestGRDBMangaChapterDocumentStore(rootDirectory: rootDirectory)
    let mangaImageDataCacheStore = FileMangaImageDataCacheStore(
        baseDirectory: rootDirectory.appendingPathComponent("manga-image-data", isDirectory: true)
    )
    let mangaOfflineCacheStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: rootDirectory)
    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        readerResumeRouteStore: readerResumeRouteStore,
        favoriteStore: favoriteStore,
        localFavoriteLibraryStore: localFavoriteLibraryStore,
        contentCoverStore: contentCoverStore,
        readerCacheStore: readerCacheStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: mangaDirectoryStore,
        mangaChapterDocumentStore: mangaChapterDocumentStore,
        mangaImageDataCacheStore: mangaImageDataCacheStore,
        mangaOfflineCacheStore: mangaOfflineCacheStore
    )

    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))

    try await sessionStore.updateWebSession(cookie: "sid=1", userAgent: "UA", isLoggedIn: true)
    try await settingsStore.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: false)))
    try await readerResumeRouteStore.save(
        .novel(
            ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "测试小说",
                source: .resume
            )
        )
    )
    try await favoriteStore.saveFavorites([Favorite(title: "测试收藏", url: threadURL)])
    var localLibrary = FavoriteLibraryDocument()
    let localTarget = FavoriteContentTarget(kind: .normalThread, threadURL: threadURL)
    try localLibrary.addItem(
        FavoriteItem(
            target: localTarget,
            title: "本地优先收藏",
            locations: [.category(localLibrary.defaultCategory.id)]
        )
    )
    try await localFavoriteLibraryStore.save(localLibrary)
    try await readerCacheStore.save(
        ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            segments: [.text("测试", chapterTitle: nil)]
        )
    )
    try await favoriteBackgroundImageStore.save(Data(repeating: 5, count: 256), imageID: "background")
    try await mangaDirectoryStore.saveDirectory(
        MangaDirectory(
            cleanBookName: "测试漫画",
            strategy: .tag,
            sourceKey: "tag:1",
            chapters: [
                MangaChapter(
                    tid: "700",
                    rawTitle: "第1话",
                    chapterNumber: 1,
                    url: threadURL
                )
            ]
        )
    )
    try await mangaChapterDocumentStore.save(
        MangaChapterDocument(
            tid: "700",
            chapterTitle: "测试漫画",
            chapterURL: threadURL,
            imageURLs: [try #require(URL(string: "https://img.example.com/reset-1.jpg"))]
        ),
        for: threadURL
    )
    try await mangaImageDataCacheStore.save(
        Data(repeating: 6, count: 128),
        for: try #require(URL(string: "https://img.example.com/reset.jpg"))
    )
    let offlineImageURL = try #require(URL(string: "https://img.example.com/offline-reset.jpg"))
    try await mangaOfflineCacheStore.saveOfflineImageData(
        Data(repeating: 7, count: 64),
        for: offlineImageURL
    )
    try await mangaOfflineCacheStore.saveMembership(
        MangaOfflineCacheMembership(
            ownerName: "测试漫画",
            tid: "700",
            chapterTitle: "测试漫画",
            chapterURL: threadURL,
            imageURLs: [offlineImageURL]
        )
    )
    _ = try await mangaOfflineCacheStore.enqueueOfflineCacheWork(
        MangaOfflineCacheWorkRequest(
            ownerName: "测试漫画",
            tid: "701",
            chapterTitle: "测试漫画续篇",
            chapterURL: threadURL,
            targetImageURLs: [try #require(URL(string: "https://img.example.com/offline-reset-work.jpg"))]
        )
    )
    try await mangaOfflineCacheStore.setOfflineCacheQueueRunState(.running)
    let coverKey = ContentCoverKey(targetType: .threadNovel, targetID: "700")
    try await contentCoverStore.setAutomaticCover(
        try #require(URL(string: "https://img.example.com/reset-cover.jpg")),
        for: coverKey
    )

    try await appContext.resetApplicationData()

    let session = await sessionStore.load()
    let settings = await settingsStore.load()
    let readerResumeRoute = await readerResumeRouteStore.load()
    let favorites = await favoriteStore.loadFavorites()
    let localFavoriteLibrary = await localFavoriteLibraryStore.load()
    let contentCover = await contentCoverStore.cover(for: coverKey)
    let readerCacheBytes = await readerCacheStore.totalDiskUsageBytes()
    let backgroundData = await favoriteBackgroundImageStore.loadData(imageID: "background")
    let mangaDirectoryBytes = await mangaDirectoryStore.totalDiskUsageBytes()
    let mangaChapterDocumentBytes = await mangaChapterDocumentStore.totalDiskUsageBytes()
    let mangaImageDataCacheBytes = await mangaImageDataCacheStore.totalDiskUsageBytes()
    let mangaOfflineCacheBytes = await mangaOfflineCacheStore.totalDiskUsageBytes()
    let mangaOfflineMemberships = await mangaOfflineCacheStore.allMemberships()
    let mangaOfflineWorks = await mangaOfflineCacheStore.allOfflineCacheWorks()
    let mangaOfflineQueueState = await mangaOfflineCacheStore.offlineCacheQueueRunState()

    #expect(session == SessionState())
    #expect(settings == AppSettings())
    #expect(readerResumeRoute == nil)
    #expect(favorites.isEmpty)
    #expect(localFavoriteLibrary.items.isEmpty)
    #expect(await !localFavoriteLibraryStore.hasStoredDocument())
    #expect(contentCover == nil)
    #expect(readerCacheBytes == 0)
    #expect(backgroundData == nil)
    #expect(mangaDirectoryBytes == 0)
    #expect(mangaChapterDocumentBytes == 0)
    #expect(mangaImageDataCacheBytes == 0)
    #expect(mangaOfflineCacheBytes == 0)
    #expect(mangaOfflineMemberships.isEmpty)
    #expect(mangaOfflineWorks.isEmpty)
    #expect(mangaOfflineQueueState == .paused)
}

@Test func appContextBootstrapDoesNotMigrateLegacyFavoritesIntoLocalFirstLibrary() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "app-bootstrap-local-first-favorites")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let favoriteStore = FavoriteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "favorites")
    let localFavoriteLibraryStore = LocalFirstFavoriteLibraryStore(
        defaults: try #require(UserDefaults(suiteName: suiteName)),
        key: "local-favorites"
    )
    let appContext = YamiboAppContext(
        favoriteStore: favoriteStore,
        localFavoriteLibraryStore: localFavoriteLibraryStore,
        readingProgressStore: ReadingProgressStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            key: "reading-progress"
        )
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=731&mobile=2"))
    try await favoriteStore.saveFavorites([
        Favorite(
            title: "旧收藏",
            displayName: "本地名",
            url: threadURL,
            remoteFavoriteID: "remote-731",
            type: .novel
        )
    ])

    let state = await appContext.bootstrap()

    let document = await localFavoriteLibraryStore.load()
    #expect(state.localFavoriteLibrary.items.isEmpty)
    #expect(document.items.isEmpty)
    #expect(document.tags.isEmpty)
    #expect(document.collections.isEmpty)
}

@Test func contentCoverStoreNormalizesAndFiltersAutomaticCoverURLs() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "content-cover-normalize")
    let store = ContentCoverStore(defaults: defaults, key: "content-covers")
    let key = ContentCoverKey(targetType: .threadNovel, targetID: "900")

    let ignored = try #require(URL(string: "https://bbs.yamibo.com/static/image/smiley/default/none.gif"))
    let relative = try #require(URL(string: "data/attachment/forum/cover.jpg"))

    #expect(try await store.setAutomaticCover(ignored, for: key) == false)
    #expect(await store.cover(for: key) == nil)
    #expect(try await store.setAutomaticCover(relative, for: key) == true)

    let cover = try #require(await store.cover(for: key))
    #expect(cover.automaticCoverURL?.absoluteString == "https://bbs.yamibo.com/data/attachment/forum/cover.jpg")
    #expect(cover.resolvedURL == cover.automaticCoverURL)
}

@Test func contentCoverStoreResolvesManualCoverWhenDynamicDisabled() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "content-cover-manual")
    let store = ContentCoverStore(defaults: defaults, key: "content-covers")
    let key = ContentCoverKey(targetType: .threadNovel, targetID: "901")
    let automatic = try #require(URL(string: "https://img.example.com/auto.jpg"))
    let manual = try #require(URL(string: "https://img.example.com/manual.jpg"))

    try await store.setAutomaticCover(automatic, for: key)
    try await store.setManualCover(manual, for: key)

    var cover = try #require(await store.cover(for: key))
    #expect(cover.dynamicEnabled == false)
    #expect(cover.resolvedURL == manual)

    try await store.setDynamicEnabled(true, for: key)
    cover = try #require(await store.cover(for: key))
    #expect(cover.resolvedURL == automatic)
}

private func makeMangaOfflineMembership(
    ownerName: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        imageURLs: imageURLs
    )
}

private func makeMangaOfflineWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL]
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        targetImageURLs: targetImageURLs
    )
}

private func makeIsolatedDefaults(prefix: String) throws -> UserDefaults {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: prefix)
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        struct DefaultsSuiteCreationError: Error {}
        throw DefaultsSuiteCreationError()
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeIsolatedDefaultsSuiteName(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString)"
}

private func makeTemporaryDirectory(prefix: String) -> URL {
    let baseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    return baseURL
}
