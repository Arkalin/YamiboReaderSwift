import Foundation
import Testing
@testable import YamiboReaderCore

@Test func yamiboRemoteSyncImportsIntoSelectedCategoryOnlyAfterProbe() async throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "远端")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901"))

    let report = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-901", threadURL: url, remoteOrder: 3)],
        date: Date(timeIntervalSince1970: 10)
    ) { _ in
        FavoriteThreadProbeResult(
            target: FavoriteContentTarget(kind: .novelThread, threadID: "901"),
            title: "远端小说",
            sourceGroup: .forumBoard(id: "fid", label: "小说")
        )
    }

    let item = try #require(document.items.first)
    #expect(report.importedTargetIDs == [item.id])
    #expect(item.locations == [.category(category.id)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-901")
    #expect(item.remoteMapping?.yamiboRemoteOrder == 3)
}

@Test func yamiboRemoteSyncSkipsFailedProbeWithoutPlaceholder() async throws {
    var document = FavoriteLibraryDocument()
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902"))

    let report = await document.syncYamiboRemoteFavorites(
        into: document.defaultCategory.id,
        remoteEntries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-902", threadURL: url)]
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("offline")
    }

    #expect(report.failedRemoteFavoriteIDs == ["r-902"])
    #expect(document.items.isEmpty)
}

@Test func yamiboRemoteSyncImportsMangaIntoSelectedCategoryWithRemoteMapping() async throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "漫画同步")
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=905"))

    let report = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-905", threadURL: chapterURL, title: "第5话", remoteOrder: 7)],
        date: Date(timeIntervalSince1970: 20)
    ) { _ in
        FavoriteThreadProbeResult(
            target: FavoriteContentTarget(mangaCleanBookName: "漫画书名"),
            title: "第5话",
            sourceGroup: .mangaTitle(cleanBookName: "漫画书名")
        )
    }

    let item = try #require(document.items.first)
    #expect(report.importedTargetIDs == [item.target.id])
    #expect(item.target == FavoriteContentTarget(mangaID: "chapter:905", mangaCleanBookName: "漫画书名"))
    #expect(item.locations == [.category(category.id)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-905")
    #expect(item.remoteMapping?.yamiboRemoteOrder == 7)
    #expect(item.remoteMapping?.isMarkedRemoteMissing == false)
    #expect(item.mangaChapterMetadata?.chapterURL == chapterURL)

    let secondReport = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: [],
        date: Date(timeIntervalSince1970: 30)
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("unused")
    }

    let updatedItem = try #require(document.items.first)
    #expect(secondReport.markedMissingTargetIDs == [item.target.id])
    #expect(updatedItem.remoteMapping?.isMarkedRemoteMissing == true)
}

@Test func yamiboRemoteSyncMarksDisappearedRemoteMappingMissingWithoutDeletingItem() async throws {
    var document = FavoriteLibraryDocument()
    let target = FavoriteContentTarget(kind: .normalThread, threadID: "903")
    let item = try FavoriteItem(
        target: target,
        title: "本地",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "r-903"),
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(item)

    let report = await document.syncYamiboRemoteFavorites(
        into: document.defaultCategory.id,
        remoteEntries: []
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("unused")
    }

    let stored = try #require(document.items.first)
    #expect(report.markedMissingTargetIDs == [target.id])
    #expect(stored.remoteMapping?.isMarkedRemoteMissing == true)
}

@Test func yamiboRemoteSyncUploadsOnlyThreadItemsInCategoryWithoutRemoteMapping() async throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "同步")
    let unsyncedThread = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "904"),
        title: "本地主题",
        locations: [.category(category.id)]
    )
    let manga = try FavoriteItem(
        target: FavoriteContentTarget(mangaCleanBookName: "漫画"),
        title: "漫画",
        locations: [.category(category.id)]
    )
    document.addItem(unsyncedThread)
    document.addItem(manga)

    let report = await document.syncYamiboRemoteFavorites(
        into: category.id,
        remoteEntries: []
    ) { _ in
        throw FavoriteThreadImportFailure.probeFailed("unused")
    }

    #expect(report.uploadTargetIDs == [unsyncedThread.id])
}
