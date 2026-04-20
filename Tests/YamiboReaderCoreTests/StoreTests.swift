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
        usesDataSaverMode: true,
        collapsesFavoriteSections: true
    )

    try await store.save(settings)
    let loaded = await store.load()

    #expect(loaded == settings)
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
