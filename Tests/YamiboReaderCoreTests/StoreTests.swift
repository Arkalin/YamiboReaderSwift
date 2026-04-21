import Foundation
import Testing
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
        cookie: "sid=999",
        userAgent: "Custom-UA",
        isLoggedIn: true
    )
    let session = await store.load()

    #expect(session.cookie == "sid=999")
    #expect(session.userAgent == "Custom-UA")
    #expect(session.isLoggedIn)
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
            backgroundStyle: .paper,
            readingMode: .vertical,
            translationMode: .traditional
        ),
        manga: MangaReaderSettings(
            readingMode: .paged,
            brightness: 0.82,
            zoomEnabled: false,
            showsSystemStatusBar: false,
            directorySortOrder: .descending
        ),
        webBrowser: WebBrowserSettings(showsNavigationBar: false),
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
    #expect(decoded.collapsesFavoriteSections == true)
}

@Test func readerAppearanceSettingsDecodesLegacyPayloadWithFontDefaults() async throws {
    let legacy = """
    {
      "fontScale": 1.2,
      "lineHeightScale": 1.5,
      "horizontalPadding": 18,
      "usesNightMode": true,
      "showsSystemStatusBar": false,
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
    #expect(decoded.fontScale == 1.2)
    #expect(decoded.lineHeightScale == 1.5)
}

@Test func mangaReaderSettingsDecodesLegacyPayloadWithAscendingDirectorySortOrder() async throws {
    let legacy = """
    {
      "readingMode": "paged",
      "brightness": 0.8,
      "zoomEnabled": false,
      "showsSystemStatusBar": true
    }
    """

    let decoded = try JSONDecoder().decode(MangaReaderSettings.self, from: Data(legacy.utf8))

    #expect(decoded.readingMode == .paged)
    #expect(decoded.directorySortOrder == .ascending)
}

@Test func favoriteStoreUpdatesReadingProgress() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-progress-tests"))
    defaults.removePersistentDomain(forName: "favorite-progress-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=30&mobile=2"))

    _ = try await store.updateReadingProgress(
        for: url,
        progress: ReaderProgress(
            view: 2,
            page: 18,
            chapterTitle: "第三章",
            authorID: "77",
            resumePoint: ReaderResumePoint(
                view: 2,
                chapterOrdinal: 2,
                chapterTitle: "第三章",
                segmentIndex: 8,
                segmentOffset: 128,
                segmentProgress: 0.4,
                authorID: "77",
                readingModeHint: .vertical
            )
        )
    )

    let favorite = await store.favorite(for: url)
    #expect(favorite?.lastView == 2)
    #expect(favorite?.lastPage == 18)
    #expect(favorite?.lastChapter == "第三章")
    #expect(favorite?.authorID == "77")
    #expect(favorite?.novelResumePoint?.segmentIndex == 8)
    #expect(favorite?.type == .novel)
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

    _ = try await store.updateReadingProgress(
        for: url,
        progress: ReaderProgress(view: 2, page: 18, chapterTitle: "第三章", authorID: "77")
    )

    let didReceive = await notificationTask.value
    #expect(didReceive)
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
    #expect(favorite?.lastPage == 8)
    #expect(favorite?.type == .manga)
}

@Test func favoriteStoreMergesRemoteFavoritesAndPreservesHiddenLocalEntries() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-store-tests"))
    defaults.removePersistentDomain(forName: "favorite-store-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let localOnly = Favorite(
        title: "旧收藏",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")!,
        isHidden: true
    )
    try await store.saveFavorites([localOnly])

    let remote = [
        Favorite(
            title: "新收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")!
        )
    ]

    let merged = try await store.mergeRemoteFavorites(remote)

    #expect(merged.count == 2)
    #expect(merged.contains(where: { $0.id == localOnly.id && $0.isHidden }))
    #expect(merged.contains(where: { $0.title == "新收藏" }))
}

@Test func favoriteStoreCanToggleHiddenState() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-hidden-tests"))
    defaults.removePersistentDomain(forName: "favorite-hidden-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let favorite = Favorite(
        title: "测试收藏",
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=3&mobile=2")!
    )
    try await store.saveFavorites([favorite])

    let hidden = try await store.setHidden(true, for: favorite.id)
    #expect(hidden.first?.isHidden == true)

    let restored = try await store.setHidden(false, for: favorite.id)
    #expect(restored.first?.isHidden == false)
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

@Test func favoriteDecodesNovelUpdateDeduplicationFields() async throws {
    let payload = """
    {
      "id": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=711",
      "title": "旧收藏",
      "url": "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=711",
      "lastPage": 2,
      "lastView": 3,
      "isHidden": false,
      "type": 1,
      "knownMaxView": 5,
      "knownMaxViewFingerprint": "fingerprint",
      "novelUpdateStatus": "newPage",
      "lastRemoteMaxView": 6,
      "lastUpdateCheckedAt": 1700000000,
      "currentNovelUpdateSignature": "newPage:6",
      "acknowledgedNovelUpdateSignature": null,
      "notifiedNovelUpdateSignature": "newPage:5"
    }
    """

    let favorite = try JSONDecoder().decode(Favorite.self, from: Data(payload.utf8))

    #expect(favorite.knownMaxView == 5)
    #expect(favorite.knownMaxViewFingerprint == "fingerprint")
    #expect(favorite.novelUpdateStatus == .newPage)
    #expect(favorite.lastRemoteMaxView == 6)
    #expect(favorite.currentNovelUpdateSignature == "newPage:6")
    #expect(favorite.acknowledgedNovelUpdateSignature == nil)
    #expect(favorite.notifiedNovelUpdateSignature == "newPage:5")
}

@Test func favoriteStoreMergePreservesNovelUpdateMetadata() async throws {
    let defaults = try #require(UserDefaults(suiteName: "favorite-merge-update-metadata-tests"))
    defaults.removePersistentDomain(forName: "favorite-merge-update-metadata-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=719&mobile=2"))
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    try await store.saveFavorites([
        Favorite(
            title: "旧标题",
            url: url,
            type: .novel,
            knownMaxView: 8,
            knownMaxViewFingerprint: "abc",
            novelUpdateStatus: .newPage,
            lastRemoteMaxView: 9,
            lastUpdateCheckedAt: checkedAt,
            currentNovelUpdateSignature: "newPage:9",
            acknowledgedNovelUpdateSignature: "newPage:8",
            notifiedNovelUpdateSignature: "newPage:9"
        )
    ])

    let merged = try await store.mergeRemoteFavorites([
        Favorite(title: "新标题", url: url)
    ])

    #expect(merged.first?.title == "新标题")
    #expect(merged.first?.knownMaxView == 8)
    #expect(merged.first?.knownMaxViewFingerprint == "abc")
    #expect(merged.first?.novelUpdateStatus == .newPage)
    #expect(merged.first?.lastRemoteMaxView == 9)
    #expect(merged.first?.lastUpdateCheckedAt == checkedAt)
    #expect(merged.first?.currentNovelUpdateSignature == "newPage:9")
    #expect(merged.first?.acknowledgedNovelUpdateSignature == "newPage:8")
    #expect(merged.first?.notifiedNovelUpdateSignature == "newPage:9")
}

@Test func settingsStoreResetRestoresDefaults() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "settings-reset-tests")
    let store = SettingsStore(defaults: defaults, key: "settings")

    try await store.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: false)))
    try await store.reset()

    let loaded = await store.load()
    #expect(loaded == AppSettings())
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

@Test func favoriteStoreClearAllRemovesAllFavorites() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-clear-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    try await store.saveFavorites([
        Favorite(
            title: "测试收藏",
            url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=515&mobile=2"))
        )
    ])

    try await store.clearAll()

    let loaded = await store.loadFavorites()
    #expect(loaded.isEmpty)
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

@Test func mangaImageCacheStoreReportsUsageAndCanClearAll() async throws {
    let baseDirectory = makeTemporaryDirectory(prefix: "manga-image-cache-tests")
    let store = MangaImageCacheStore(baseDirectory: baseDirectory)
    let imageURL = try #require(URL(string: "https://static.yamibo.com/test-1.jpg"))
    let data = Data(repeating: 7, count: 2048)

    try await store.save(data, for: imageURL)

    let usage = await store.totalDiskUsageBytes()
    #expect(usage == data.count)

    try await store.clearAll()

    let clearedUsage = await store.totalDiskUsageBytes()
    #expect(clearedUsage == 0)
}

@Test func appContextResetApplicationDataClearsPersistedState() async throws {
    let suiteName = makeIsolatedDefaultsSuiteName(prefix: "app-reset-tests")
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    let fileManager = FileManager.default
    let rootDirectory = makeTemporaryDirectory(prefix: "app-reset-root")

    let sessionStore = SessionStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "session")
    let settingsStore = SettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "settings")
    let favoriteStore = FavoriteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "favorites")
    let readerCacheStore = ReaderCacheStore(baseDirectory: rootDirectory.appendingPathComponent("reader-cache", isDirectory: true))
    let mangaImageCacheStore = MangaImageCacheStore(baseDirectory: rootDirectory.appendingPathComponent("manga-image-cache", isDirectory: true))
    let mangaDirectoryStore = MangaDirectoryStore(
        fileManager: fileManager,
        baseDirectory: rootDirectory.appendingPathComponent("manga-directory", isDirectory: true)
    )
    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        readerCacheStore: readerCacheStore,
        mangaImageCacheStore: mangaImageCacheStore,
        mangaDirectoryStore: mangaDirectoryStore
    )

    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
    let imageURL = try #require(URL(string: "https://static.yamibo.com/test-2.jpg"))

    try await sessionStore.updateWebSession(cookie: "sid=1", userAgent: "UA", isLoggedIn: true)
    try await settingsStore.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: false)))
    try await favoriteStore.saveFavorites([Favorite(title: "测试收藏", url: threadURL)])
    try await readerCacheStore.save(
        ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            segments: [.text("测试", chapterTitle: nil)]
        )
    )
    try await mangaImageCacheStore.save(Data(repeating: 9, count: 1024), for: imageURL)
    _ = try await mangaDirectoryStore.initializeDirectory(
        currentURL: threadURL,
        rawTitle: "测试漫画 第1话",
        html: ""
    )

    try await appContext.resetApplicationData()

    let session = await sessionStore.load()
    let settings = await settingsStore.load()
    let favorites = await favoriteStore.loadFavorites()
    let readerCacheBytes = await readerCacheStore.totalDiskUsageBytes()
    let mangaCacheBytes = await mangaImageCacheStore.totalDiskUsageBytes()
    let directories = await mangaDirectoryStore.allDirectories()

    #expect(session == SessionState())
    #expect(settings == AppSettings())
    #expect(favorites.isEmpty)
    #expect(readerCacheBytes == 0)
    #expect(mangaCacheBytes == 0)
    #expect(directories.isEmpty)
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
