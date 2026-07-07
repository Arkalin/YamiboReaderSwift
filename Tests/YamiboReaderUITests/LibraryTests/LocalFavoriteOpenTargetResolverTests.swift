import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class LocalFavoriteOpenTargetResolverTests: XCTestCase {
    func testNormalThreadOpenTargetUsesNativeReaderWithoutMutatingFavoriteUpdatedAt() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_000)
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadID: "901"),
            title: "普通主题",
            locations: [.category(document.defaultCategory.id)],
            updatedAt: originalUpdatedAt
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .nativeThread(openedURL, title)? = opened else {
            return XCTFail("Expected a native thread open target")
        }
        XCTAssertEqual(openedURL, YamiboRoute.threadByID(tid: "901", page: 1, authorID: nil, reverse: false).url)
        XCTAssertEqual(title, "普通主题")
        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.id == item.id }
        XCTAssertEqual(storedItem?.updatedAt, originalUpdatedAt)
    }
}
