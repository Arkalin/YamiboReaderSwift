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
            showsTwoPagesInLandscapeOnPad: true,
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
        favoriteAppearance: FavoriteAppearanceSettings(
            collection: .purple,
            novel: .red,
            manga: .green,
            other: .gray
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
    #expect(decoded.collapsesFavoriteSections == true)
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
    #expect(decoded.showsTwoPagesInLandscapeOnPad == false)
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

@Test func favoriteStoreReordersVisibleSubsetWithoutDisturbingHiddenEntries() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-reorder-subset-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let firstVisible = Favorite(title: "可见1", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=611&mobile=2")), type: .novel)
    let hidden = Favorite(title: "隐藏项", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=612&mobile=2")), isHidden: true, type: .novel)
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
    let hiddenLocalOnly = Favorite(title: "本地隐藏", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=623&mobile=2")), isHidden: true)
    let removedRemote = Favorite(title: "将被移除", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=624&mobile=2")))
    try await store.saveFavorites([localFirst, localSecond, hiddenLocalOnly, removedRemote])

    let newRemote = Favorite(title: "新同步收藏", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=625&mobile=2")), remoteFavoriteID: "25")
    let remoteSecond = Favorite(title: "远端更新2", url: localSecond.url, remoteFavoriteID: "22", type: .manga)
    let remoteFirst = Favorite(title: "远端更新1", url: localFirst.url, remoteFavoriteID: "11", type: .novel)

    let merged = try await store.mergeRemoteFavorites([newRemote, remoteSecond, remoteFirst])

    #expect(merged.map(\.id) == [newRemote.id, localFirst.id, localSecond.id, hiddenLocalOnly.id])
    #expect(merged[1].title == "远端更新1")
    #expect(merged[2].title == "远端更新2")
    #expect(merged[2].remoteFavoriteID == "22")
    #expect(merged[3].isHidden == true)
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

@Test func favoriteStoreCanRenameAndHideCollections() async throws {
    let defaults = try makeIsolatedDefaults(prefix: "favorite-collection-edit-tests")
    let store = FavoriteStore(defaults: defaults, key: "favorites")

    let favorite = Favorite(title: "根页收藏", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=908&mobile=2")))
    try await store.saveFavorites([favorite])

    let created = try await store.createCollection(name: "旧合集", favoriteIDs: [favorite.id])
    let collectionID = try #require(created.collections.first?.id)

    let renamed = try await store.setCollectionName("  新合集  ", for: collectionID)
    #expect(renamed.collections.first?.name == "新合集")

    let hidden = try await store.setCollectionHidden(true, for: collectionID)
    #expect(hidden.collections.first?.isHidden == true)

    let loaded = await store.loadCollections()
    #expect(loaded.first?.name == "新合集")
    #expect(loaded.first?.isHidden == true)
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
