import Foundation
import Testing
@testable import YamiboReaderCore

// smart-comic-mode design decision #1: fid 30 defaults on, 46/37 default
// off, and only those three boards can ever be toggled at all.
@Suite("SettingsTests: Smart Comic Mode")
struct SmartComicModeSettingsTests {
    @Test func defaultsMatchDecisionOne() {
        let settings = SmartComicModeSettings()
        #expect(settings.isEnabled(forumID: "30") == true)
        #expect(settings.isEnabled(forumID: "46") == false)
        #expect(settings.isEnabled(forumID: "37") == false)
    }

    @Test func boardsOutsideManageableSetAlwaysReportEnabled() {
        let settings = SmartComicModeSettings(enabledForumIDs: [])
        #expect(settings.isEnabled(forumID: "999999") == true)
        #expect(settings.isEnabled(forumID: nil) == true)
        #expect(settings.isEnabled(forumID: "  ") == true)
    }

    @Test func toggleFlipsOnlyTheManageableBoard() {
        var settings = SmartComicModeSettings()
        settings.enabledForumIDs.insert("46")
        settings.enabledForumIDs.remove("30")
        #expect(settings.isEnabled(forumID: "30") == false)
        #expect(settings.isEnabled(forumID: "46") == true)
        #expect(settings.isEnabled(forumID: "37") == false)
    }

    @Test func appSettingsConvenienceDelegatesToSmartComicMode() {
        var appSettings = AppSettings()
        #expect(appSettings.isSmartComicModeEnabled(forumID: "30") == true)
        #expect(appSettings.isSmartComicModeEnabled(forumID: "46") == false)
        appSettings.smartComicMode.enabledForumIDs.insert("46")
        #expect(appSettings.isSmartComicModeEnabled(forumID: "46") == true)
    }
}
