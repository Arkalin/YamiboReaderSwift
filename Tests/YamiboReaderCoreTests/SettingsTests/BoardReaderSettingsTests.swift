import Foundation
import Testing
@testable import YamiboReaderCore

// Pluggable-reader-config decisions #1/#4/#8: any board is configurable, the
// factory default carries over the old hardcoded taxonomy (49/55 novel,
// 30/46/37 manga, smart bit on only for 30), and the smart query follows one
// rule with no special cases.
@Suite("SettingsTests: Board Reader Settings")
struct BoardReaderSettingsTests {
    @Test func defaultInitIsFactoryDefault() {
        let settings = BoardReaderSettings()
        #expect(settings == BoardReaderSettings.factoryDefault)
        #expect(settings.entries.count == 5)
        #expect(settings.entry(forumID: "49")?.mode == .novel)
        #expect(settings.entry(forumID: "55")?.mode == .novel)
        #expect(settings.entry(forumID: "30")?.mode == .manga(smartEnabled: true))
        #expect(settings.entry(forumID: "46")?.mode == .manga(smartEnabled: false))
        #expect(settings.entry(forumID: "37")?.mode == .manga(smartEnabled: false))
        // fid 30 is the only board with a verified built-in name snapshot;
        // 46/37 stay nil so the UI shows its own placeholder.
        #expect(settings.entry(forumID: "30")?.boardName == "中文百合漫画区")
        #expect(settings.entry(forumID: "46")?.boardName == nil)
    }

    @Test func smartQueryFollowsOneRuleWithNoSpecialCases() {
        let settings = BoardReaderSettings()
        // Only "configured as manga AND smart bit on" reports true.
        #expect(settings.isSmartComicModeEnabled(forumID: "30") == true)
        // Manga with smart off.
        #expect(settings.isSmartComicModeEnabled(forumID: "46") == false)
        #expect(settings.isSmartComicModeEnabled(forumID: "37") == false)
        // Novel boards.
        #expect(settings.isSmartComicModeEnabled(forumID: "49") == false)
        // Unconfigured board, nil and blank fids.
        #expect(settings.isSmartComicModeEnabled(forumID: "999999") == false)
        #expect(settings.isSmartComicModeEnabled(forumID: nil) == false)
        #expect(settings.isSmartComicModeEnabled(forumID: "  ") == false)
        // Trimmed lookup still matches.
        #expect(settings.isSmartComicModeEnabled(forumID: " 30 ") == true)
    }

    @Test func threadKindClassifiesFromConfiguredEntries() {
        let settings = BoardReaderSettings()
        #expect(settings.threadKind(forumID: "49") == .novel)
        #expect(settings.threadKind(forumID: "55") == .novel)
        #expect(settings.threadKind(forumID: "30") == .manga)
        // The smart bit never affects classification.
        #expect(settings.threadKind(forumID: "46") == .manga)
        #expect(settings.threadKind(forumID: "999999") == .unknown)
        #expect(settings.threadKind(forumID: nil) == .unknown)
        #expect(settings.threadKind(forumID: "  ") == .unknown)
    }

    @Test func hasAnySmartEnabledBoardIsPurelyAConfigurationCheck() {
        var settings = BoardReaderSettings()
        #expect(settings.hasAnySmartEnabledBoard == true)
        settings.setEntry(.init(mode: .manga(smartEnabled: false)), forumID: "30")
        #expect(settings.hasAnySmartEnabledBoard == false)
        settings.setEntry(.init(mode: .manga(smartEnabled: true)), forumID: "46")
        #expect(settings.hasAnySmartEnabledBoard == true)
        settings = BoardReaderSettings(entries: [:])
        #expect(settings.hasAnySmartEnabledBoard == false)
    }

    @Test func entryMutationsTrimAndIgnoreBlankForumIDs() {
        var settings = BoardReaderSettings(entries: [:])
        settings.setEntry(.init(mode: .novel, boardName: "文学区"), forumID: " 60 ")
        #expect(settings.entry(forumID: "60")?.mode == .novel)
        #expect(settings.entry(forumID: "60")?.boardName == "文学区")

        settings.setEntry(.init(mode: .manga(smartEnabled: true)), forumID: "  ")
        settings.setEntry(.init(mode: .manga(smartEnabled: true)), forumID: nil)
        #expect(settings.entries.count == 1)

        settings.removeEntry(forumID: " 60 ")
        #expect(settings.entry(forumID: "60") == nil)
        #expect(settings.entries.isEmpty)
    }

    @Test func codableRoundTripPreservesEntries() throws {
        var settings = BoardReaderSettings()
        settings.setEntry(.init(mode: .manga(smartEnabled: true), boardName: "自定义板块"), forumID: "77")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(BoardReaderSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func appSettingsConvenienceDelegatesToBoardReader() {
        var appSettings = AppSettings()
        #expect(appSettings.isSmartComicModeEnabled(forumID: "30") == true)
        #expect(appSettings.isSmartComicModeEnabled(forumID: "46") == false)
        appSettings.boardReader.setEntry(.init(mode: .manga(smartEnabled: true)), forumID: "46")
        #expect(appSettings.isSmartComicModeEnabled(forumID: "46") == true)
    }
}
