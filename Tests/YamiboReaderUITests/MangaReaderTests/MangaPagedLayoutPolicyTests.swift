import CoreGraphics
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@Suite("MangaReaderTests: Paged Layout Policy")
struct MangaPagedLayoutPolicyTests {
    @Test func twoPageSpreadActivatesOnlyForIPadPagedLandscapePreference() {
        let settings = MangaReaderSettings(
            readingMode: .paged,
            pageScaleMode: .fitHeight,
            showsTwoPagesInLandscapeOnPad: true
        )

        #expect(MangaPagedLayoutPolicy.usesTwoPageSpread(
            settings: settings,
            isPadDevice: true,
            availableSize: CGSize(width: 1180, height: 820)
        ))
        #expect(!MangaPagedLayoutPolicy.usesTwoPageSpread(
            settings: settings,
            isPadDevice: true,
            availableSize: CGSize(width: 820, height: 1180)
        ))
        #expect(!MangaPagedLayoutPolicy.usesTwoPageSpread(
            settings: settings,
            isPadDevice: false,
            availableSize: CGSize(width: 1180, height: 820)
        ))
    }

    @Test func twoPageSpreadRequiresPagedModeAndEnabledPreference() {
        let landscapeSize = CGSize(width: 1180, height: 820)
        let disabledSettings = MangaReaderSettings(
            readingMode: .paged,
            pageScaleMode: .fitHeight,
            showsTwoPagesInLandscapeOnPad: false
        )
        let verticalSettings = MangaReaderSettings(
            readingMode: .vertical,
            pageScaleMode: .fitHeight,
            showsTwoPagesInLandscapeOnPad: true
        )

        #expect(!MangaPagedLayoutPolicy.usesTwoPageSpread(
            settings: disabledSettings,
            isPadDevice: true,
            availableSize: landscapeSize
        ))
        #expect(!MangaPagedLayoutPolicy.usesTwoPageSpread(
            settings: verticalSettings,
            isPadDevice: true,
            availableSize: landscapeSize
        ))
    }

    @Test func twoPageSpreadForcesFitWidthWithoutMutatingSavedScalePreference() {
        let fitHeightSettings = MangaReaderSettings(
            readingMode: .paged,
            pageScaleMode: .fitHeight,
            showsTwoPagesInLandscapeOnPad: true
        )
        let fitWidthSettings = MangaReaderSettings(
            readingMode: .paged,
            pageScaleMode: .fitWidth,
            showsTwoPagesInLandscapeOnPad: false
        )

        #expect(MangaPagedLayoutPolicy.effectivePageScaleMode(
            settings: fitHeightSettings,
            usesTwoPageSpread: true
        ) == .fitWidth)
        #expect(fitHeightSettings.pageScaleMode == .fitHeight)
        #expect(MangaPagedLayoutPolicy.effectivePageScaleMode(
            settings: fitHeightSettings,
            usesTwoPageSpread: false
        ) == .fitHeight)
        #expect(MangaPagedLayoutPolicy.effectivePageScaleMode(
            settings: fitWidthSettings,
            usesTwoPageSpread: false
        ) == .fitWidth)
    }
}
