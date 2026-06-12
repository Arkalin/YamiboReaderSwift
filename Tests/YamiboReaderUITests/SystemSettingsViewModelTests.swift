import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class SystemSettingsViewModelTests: XCTestCase {
    func testLoadReadsApplePencilPageTurnSettings() async throws {
        let fixture = try makeFixture()
        let savedSettings = ApplePencilPageTurnSettings(
            isEnabled: true,
            behavior: .doubleTapNextSqueezePrevious
        )
        try await fixture.settingsStore.save(AppSettings(applePencilPageTurn: savedSettings))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.applePencilPageTurn, savedSettings)
    }

    func testLoadReadsFavoriteBackgroundSettings() async throws {
        let fixture = try makeFixture()
        let savedSettings = FavoriteBackgroundSettings(
            isEnabled: true,
            imageID: "background",
            scale: 1.7,
            offsetX: 0.2,
            offsetY: -0.3,
            blurRadius: 11
        )
        try await fixture.settingsStore.save(AppSettings(favoriteBackground: savedSettings))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.favoriteBackground, savedSettings)
    }

    func testApplyFavoriteBackgroundPersistsImageAndSettings() async throws {
        let fixture = try makeFixture()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let imageData = Data(repeating: 6, count: 128)
        let draftSettings = FavoriteBackgroundSettings(
            isEnabled: true,
            scale: 2,
            offsetX: 0.5,
            offsetY: -0.25,
            blurRadius: 14
        )

        let didApply = await viewModel.applyFavoriteBackground(
            imageData: imageData,
            draftSettings: draftSettings
        )

        XCTAssertTrue(didApply)
        let loaded = await fixture.settingsStore.load()
        let imageID = try XCTUnwrap(loaded.favoriteBackground.imageID)
        XCTAssertTrue(loaded.favoriteBackground.isEnabled)
        XCTAssertEqual(loaded.favoriteBackground.scale, 2)
        XCTAssertEqual(loaded.favoriteBackground.offsetX, 0.5)
        XCTAssertEqual(loaded.favoriteBackground.offsetY, -0.25)
        XCTAssertEqual(loaded.favoriteBackground.blurRadius, 14)
        let savedImageData = await fixture.favoriteBackgroundImageStore.loadData(imageID: imageID)
        XCTAssertEqual(savedImageData, imageData)
        XCTAssertEqual(viewModel.favoriteBackground, loaded.favoriteBackground)
    }

    func testRestoreDefaultFavoriteBackgroundClearsImageAndSettings() async throws {
        let fixture = try makeFixture()
        let imageID = "background"
        try await fixture.favoriteBackgroundImageStore.save(Data(repeating: 7, count: 96), imageID: imageID)
        try await fixture.settingsStore.save(AppSettings(
            favoriteBackground: FavoriteBackgroundSettings(isEnabled: true, imageID: imageID)
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let didRestore = await viewModel.restoreDefaultFavoriteBackground()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.favoriteBackground, FavoriteBackgroundSettings())
        let loadedSettings = await fixture.settingsStore.load()
        XCTAssertEqual(loadedSettings.favoriteBackground, FavoriteBackgroundSettings())
        let savedImageData = await fixture.favoriteBackgroundImageStore.loadData(imageID: imageID)
        XCTAssertNil(savedImageData)
    }

    func testUpdateApplePencilEnabledPersistsSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings())

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        viewModel.updateApplePencilPageTurnEnabled(true)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.applePencilPageTurn.isEnabled
        }
        XCTAssertTrue(viewModel.applePencilPageTurn.isEnabled)
    }

    func testUpdateApplePencilBehaviorPersistsSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings())

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        viewModel.updateApplePencilPageTurnBehavior(.doubleTapNextSqueezePrevious)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.applePencilPageTurn.behavior == .doubleTapNextSqueezePrevious
        }
        XCTAssertEqual(viewModel.applePencilPageTurn.behavior, .doubleTapNextSqueezePrevious)
    }

    func testResetApplicationRestoresDefaultApplePencilSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings(
            applePencilPageTurn: ApplePencilPageTurnSettings(
                isEnabled: true,
                behavior: .doubleTapNextSqueezePrevious
            )
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let didReset = await viewModel.resetApplication()

        XCTAssertTrue(didReset)
        XCTAssertEqual(viewModel.applePencilPageTurn, ApplePencilPageTurnSettings())
        let loaded = await fixture.settingsStore.load()
        XCTAssertEqual(loaded.applePencilPageTurn, ApplePencilPageTurnSettings())
        XCTAssertEqual(viewModel.favoriteBackground, FavoriteBackgroundSettings())
    }
}

private struct SystemSettingsFixture {
    let appContext: YamiboAppContext
    let settingsStore: SettingsStore
    let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
}

private func makeFixture() throws -> SystemSettingsFixture {
    let suiteName = "system-settings-view-model-\(UUID().uuidString)"
    try makeDefaults(suiteName: suiteName).removePersistentDomain(forName: suiteName)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("system-settings-view-model-\(UUID().uuidString)", isDirectory: true)
    let settingsStore = SettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "settings")
    let favoriteBackgroundImageStore = FavoriteBackgroundImageStore(
        baseDirectory: root.appendingPathComponent("favorite-background", isDirectory: true)
    )
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(defaults: try makeDefaults(suiteName: suiteName), key: "session"),
        autoSignInStore: AutoSignInStore(defaults: try makeDefaults(suiteName: suiteName), keyPrefix: "auto-sign-in"),
        settingsStore: settingsStore,
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "webdav"),
        readerResumeRouteStore: ReaderResumeRouteStore(defaults: try makeDefaults(suiteName: suiteName), key: "reader-resume-route"),
        favoriteStore: FavoriteStore(defaults: try makeDefaults(suiteName: suiteName), key: "favorites"),
        readerCacheStore: ReaderCacheStore(baseDirectory: root.appendingPathComponent("reader-cache", isDirectory: true)),
        mangaImageCacheStore: MangaImageCacheStore(baseDirectory: root.appendingPathComponent("manga-image-cache", isDirectory: true)),
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: MangaDirectoryStore(baseDirectory: root.appendingPathComponent("manga-directory", isDirectory: true))
    )

    return SystemSettingsFixture(
        appContext: appContext,
        settingsStore: settingsStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore
    )
}

private func makeDefaults(suiteName: String) throws -> UserDefaults {
    try XCTUnwrap(UserDefaults(suiteName: suiteName))
}

@MainActor
private func waitFor(
    timeout: TimeInterval = 2,
    pollInterval: UInt64 = 20_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    XCTFail("Timed out waiting for condition")
}
