import Foundation
import Testing
@testable import YamiboReaderCore

// gamepad-control design decisions #3/#13/#14: defaults follow physical
// positions (bottom/left/top face button), Menu is never bindable, and
// rebinding steals the element from whichever action held it.
@Suite("SettingsTests: Gamepad Settings")
struct GamepadSettingsTests {
    @Test func defaultsAreEnabledWithFaceButtonBindings() {
        let settings = GamepadSettings()
        #expect(settings.isEnabled)
        #expect(settings.bindings == [
            .nextPage: GamepadElementAlias.buttonA,
            .previousPage: GamepadElementAlias.buttonX,
            .openComments: GamepadElementAlias.buttonY,
        ])
    }

    @Test func bindingStealsElementFromPreviousOwner() {
        var settings = GamepadSettings()
        settings.bind(.openComments, toElementAlias: GamepadElementAlias.buttonX)
        #expect(settings.bindings[.openComments] == GamepadElementAlias.buttonX)
        #expect(settings.bindings[.previousPage] == nil)
        #expect(settings.bindings[.nextPage] == GamepadElementAlias.buttonA)
    }

    @Test func bindingToFreshElementKeepsOtherBindings() {
        var settings = GamepadSettings()
        settings.bind(.nextPage, toElementAlias: GamepadElementAlias.rightShoulder)
        #expect(settings.bindings[.nextPage] == GamepadElementAlias.rightShoulder)
        #expect(settings.bindings[.previousPage] == GamepadElementAlias.buttonX)
        #expect(settings.bindings[.openComments] == GamepadElementAlias.buttonY)
    }

    @Test func toggleChromeIsNeverBindable() {
        var settings = GamepadSettings()
        settings.bind(.toggleChrome, toElementAlias: GamepadElementAlias.buttonB)
        #expect(settings.bindings[.toggleChrome] == nil)
        #expect(GamepadAction.userBindableActions == [.nextPage, .previousPage, .openComments])
    }

    @Test func clearBindingLeavesActionUnbound() {
        var settings = GamepadSettings()
        settings.clearBinding(for: .nextPage)
        #expect(settings.bindings[.nextPage] == nil)
        #expect(settings.action(boundToAnyOf: [GamepadElementAlias.buttonA]) == nil)
    }

    @Test func restoreDefaultBindingsDiscardsCustomization() {
        var settings = GamepadSettings()
        settings.bind(.nextPage, toElementAlias: GamepadElementAlias.leftTrigger)
        settings.clearBinding(for: .openComments)
        settings.restoreDefaultBindings()
        #expect(settings.bindings == GamepadSettings.defaultBindings)
    }

    @Test func actionLookupMatchesAnyAliasInTheSet() {
        let settings = GamepadSettings()
        // Live-input elements report several aliases at once; any hit counts.
        let aliases: Set<String> = ["Button B", GamepadElementAlias.buttonX]
        #expect(settings.action(boundToAnyOf: aliases) == .previousPage)
        #expect(settings.action(boundToAnyOf: ["Left Thumbstick"]) == nil)
    }

    @Test func actionLookupIgnoresNonBindableEntries() {
        // Defensive: a hand-edited or corrupted store must not let Menu's
        // fixed action be shadowed through the bindings table.
        var settings = GamepadSettings()
        settings.bindings[.toggleChrome] = GamepadElementAlias.buttonB
        #expect(settings.action(boundToAnyOf: [GamepadElementAlias.buttonB]) == nil)
    }

    @Test func serializationRoundTripsThroughAppSettings() throws {
        var settings = GamepadSettings()
        settings.isEnabled = false
        settings.bind(.nextPage, toElementAlias: GamepadElementAlias.rightShoulder)
        settings.clearBinding(for: .openComments)

        var appSettings = AppSettings()
        appSettings.system.gamepad = settings

        let data = try JSONEncoder().encode(appSettings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.system.gamepad == settings)
    }

    @Test func bindableAliasWhitelistExcludesFixedAndSystemElements() {
        #expect(GamepadElementAlias.isUserBindable(anyOf: [GamepadElementAlias.buttonA]))
        #expect(GamepadElementAlias.isUserBindable(anyOf: [GamepadElementAlias.leftThumbstickButton]))
        #expect(!GamepadElementAlias.isUserBindable(anyOf: [GamepadElementAlias.buttonMenu]))
        #expect(!GamepadElementAlias.isUserBindable(anyOf: [GamepadElementAlias.buttonHome]))
        #expect(!GamepadElementAlias.isUserBindable(anyOf: [GamepadElementAlias.directionPad]))
        #expect(!GamepadElementAlias.isUserBindable(anyOf: ["Left Thumbstick"]))
        // An element advertising both a bindable and an unknown alias binds.
        #expect(GamepadElementAlias.isUserBindable(anyOf: ["Cross Button", GamepadElementAlias.buttonA]))
    }
}

// gamepad-control design decision #4: actions fire exactly once per physical
// press — on the released→pressed edge — and never on release or repeats.
// (`registerPressState` is mutating, so results are hoisted out of #expect.)
@Suite("SettingsTests: Gamepad Press Tracker")
struct GamepadPressTrackerTests {
    @Test func firesExactlyOnceOnRisingEdge() {
        var tracker = GamepadPressTracker()
        let initialPress = tracker.registerPressState(true, forKey: "Button A")
        let heldRepeat = tracker.registerPressState(true, forKey: "Button A")
        let release = tracker.registerPressState(false, forKey: "Button A")
        let secondPress = tracker.registerPressState(true, forKey: "Button A")
        #expect(initialPress)
        #expect(!heldRepeat)
        #expect(!release)
        #expect(secondPress)
    }

    @Test func tracksElementsIndependently() {
        var tracker = GamepadPressTracker()
        let pressA = tracker.registerPressState(true, forKey: "Button A")
        let pressX = tracker.registerPressState(true, forKey: "Button X")
        let releaseA = tracker.registerPressState(false, forKey: "Button A")
        let heldX = tracker.registerPressState(true, forKey: "Button X")
        #expect(pressA)
        #expect(pressX)
        #expect(!releaseA)
        #expect(!heldX)
    }

    @Test func resetForgetsHeldButtons() {
        var tracker = GamepadPressTracker()
        let firstPress = tracker.registerPressState(true, forKey: "Button A")
        tracker.reset()
        let pressAfterReset = tracker.registerPressState(true, forKey: "Button A")
        #expect(firstPress)
        #expect(pressAfterReset)
    }
}

// gamepad-control design decision #8 (D-pad semantics table) and #11
// (comments-sheet command set). Paged left/right must honor the manga
// right-to-left page turn direction the same way tap zones do.
@Suite("SettingsTests: Gamepad Command Resolver")
struct GamepadCommandResolverTests {
    private let ltr = GamepadReadingSurface.paged(isRightToLeft: false)
    private let rtl = GamepadReadingSurface.paged(isRightToLeft: true)

    @Test func menuTogglesChromeOnEverySurface() {
        #expect(GamepadCommandResolver.readerCommand(for: .menu, surface: ltr) == .toggleChrome)
        #expect(GamepadCommandResolver.readerCommand(for: .menu, surface: rtl) == .toggleChrome)
        #expect(GamepadCommandResolver.readerCommand(for: .menu, surface: .vertical) == .toggleChrome)
    }

    @Test func boundActionsTurnPagesWhenPaged() {
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.nextPage), surface: ltr) == .turnPage(1))
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.previousPage), surface: rtl) == .turnPage(-1))
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.openComments), surface: ltr) == .openComments)
    }

    @Test func boundPageActionsScrollWhenVertical() {
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.nextPage), surface: .vertical) == .scrollStep(.down))
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.previousPage), surface: .vertical) == .scrollStep(.up))
        #expect(GamepadCommandResolver.readerCommand(for: .bound(.openComments), surface: .vertical) == .openComments)
    }

    @Test func dpadHorizontalFollowsPageTurnDirection() {
        // Left-to-right: physical left goes back, right advances.
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.left), surface: ltr) == .turnPage(-1))
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.right), surface: ltr) == .turnPage(1))
        // Right-to-left flips horizontal, mirroring directionalTapZone.
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.left), surface: rtl) == .turnPage(1))
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.right), surface: rtl) == .turnPage(-1))
    }

    @Test func dpadVerticalAxisIsDirectionIndependentWhenPaged() {
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.up), surface: ltr) == .turnPage(-1))
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.down), surface: rtl) == .turnPage(1))
    }

    @Test func dpadScrollsWhenVerticalAndHorizontalIsDead() {
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.up), surface: .vertical) == .scrollStep(.up))
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.down), surface: .vertical) == .scrollStep(.down))
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.left), surface: .vertical) == nil)
        #expect(GamepadCommandResolver.readerCommand(for: .dpad(.right), surface: .vertical) == nil)
    }

    @Test func commentsSheetScrollsClosesAndIgnoresTheRest() {
        #expect(GamepadCommandResolver.commentsCommand(for: .dpad(.up)) == .scroll(.up))
        #expect(GamepadCommandResolver.commentsCommand(for: .dpad(.down)) == .scroll(.down))
        #expect(GamepadCommandResolver.commentsCommand(for: .bound(.openComments)) == .close)
        #expect(GamepadCommandResolver.commentsCommand(for: .menu) == .close)
        #expect(GamepadCommandResolver.commentsCommand(for: .bound(.nextPage)) == nil)
        #expect(GamepadCommandResolver.commentsCommand(for: .bound(.previousPage)) == nil)
        #expect(GamepadCommandResolver.commentsCommand(for: .dpad(.left)) == nil)
        #expect(GamepadCommandResolver.commentsCommand(for: .dpad(.right)) == nil)
    }
}
