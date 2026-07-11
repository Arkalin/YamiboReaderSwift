import Foundation

/// Logical reader actions a game controller can trigger. The raw values are
/// persisted inside ``GamepadSettings/bindings``.
public enum GamepadAction: String, Codable, Hashable, CaseIterable, Sendable {
    case nextPage
    case previousPage
    case openComments
    case toggleChrome

    /// The Menu button is hard-wired to ``toggleChrome`` so a controller can
    /// always summon the chrome; it never appears in the bindings table.
    public var isUserBindable: Bool {
        self != .toggleChrome
    }

    public static var userBindableActions: [GamepadAction] {
        allCases.filter(\.isUserBindable)
    }

    public var title: String {
        switch self {
        case .nextPage: L10n.string("settings.gamepad.next_page")
        case .previousPage: L10n.string("settings.gamepad.previous_page")
        case .openComments: L10n.string("settings.gamepad.open_comments")
        case .toggleChrome: L10n.string("settings.gamepad.toggle_chrome")
        }
    }
}

/// Stable GameController element alias strings (`GCInput*` constants). Kept as
/// plain strings so the settings layer stays free of GameController imports;
/// the UI glue matches them against `GCPhysicalInputElement.aliases`.
public enum GamepadElementAlias {
    public static let buttonA = "Button A"
    public static let buttonB = "Button B"
    public static let buttonX = "Button X"
    public static let buttonY = "Button Y"
    public static let leftShoulder = "Left Shoulder"
    public static let rightShoulder = "Right Shoulder"
    public static let leftTrigger = "Left Trigger"
    public static let rightTrigger = "Right Trigger"
    public static let buttonOptions = "Button Options"
    public static let buttonMenu = "Button Menu"
    public static let buttonHome = "Button Home"
    public static let leftThumbstickButton = "Left Thumbstick Button"
    public static let rightThumbstickButton = "Right Thumbstick Button"
    public static let directionPad = "Direction Pad"

    /// Elements a user may bind in the capture UI, in canonical preference
    /// order. The direction pad and Menu carry fixed semantics, Home is
    /// intercepted by the system, and analog elements never qualify.
    public static let bindableAliasPriority: [String] = [
        buttonA, buttonB, buttonX, buttonY,
        leftShoulder, rightShoulder,
        leftTrigger, rightTrigger,
        buttonOptions,
        leftThumbstickButton, rightThumbstickButton,
    ]

    public static let userBindableAliases = Set(bindableAliasPriority)

    public static func isUserBindable<Aliases: Sequence<String>>(anyOf aliases: Aliases) -> Bool {
        aliases.contains(where: userBindableAliases.contains)
    }

    /// Picks the stable alias to persist when an element advertises several
    /// (live-input elements report a whole alias set at once).
    public static func canonicalBindableAlias<Aliases: Collection<String>>(in aliases: Aliases) -> String? {
        bindableAliasPriority.first(where: aliases.contains)
    }
}

public struct GamepadSettings: Codable, Hashable, Sendable {
    /// Master switch. Gates action dispatch inside the readers only; the
    /// settings page keeps capturing and showing connection state regardless.
    public var isEnabled: Bool

    /// Maps user-bindable actions to a GameController element alias. Menu and
    /// the direction pad are fixed in code and never stored here. An absent
    /// key means the action is unbound.
    public var bindings: [GamepadAction: String]

    public init(
        isEnabled: Bool = true,
        bindings: [GamepadAction: String] = Self.defaultBindings
    ) {
        self.isEnabled = isEnabled
        self.bindings = bindings
    }

    /// Defaults follow physical positions (bottom/left/top face button); the
    /// UI renders per-controller glyphs so Nintendo-labelled pads stay honest.
    public static let defaultBindings: [GamepadAction: String] = [
        .nextPage: GamepadElementAlias.buttonA,
        .previousPage: GamepadElementAlias.buttonX,
        .openComments: GamepadElementAlias.buttonY,
    ]

    public func action(boundToAnyOf aliases: Set<String>) -> GamepadAction? {
        bindings.first { action, alias in
            action.isUserBindable && aliases.contains(alias)
        }?.key
    }

    /// Binds `action` to `alias`, stealing the alias from any action that
    /// currently holds it (last write wins; the losing action becomes unbound).
    public mutating func bind(_ action: GamepadAction, toElementAlias alias: String) {
        guard action.isUserBindable else { return }
        for (existingAction, existingAlias) in bindings where existingAlias == alias {
            bindings.removeValue(forKey: existingAction)
        }
        bindings[action] = alias
    }

    public mutating func clearBinding(for action: GamepadAction) {
        bindings.removeValue(forKey: action)
    }

    public mutating func restoreDefaultBindings() {
        bindings = Self.defaultBindings
    }
}

// MARK: - Input events

public enum GamepadDpadDirection: String, Hashable, CaseIterable, Sendable {
    case up
    case down
    case left
    case right
}

/// A single logical controller input after the UI glue has done rising-edge
/// detection and binding lookup.
public enum GamepadEvent: Hashable, Sendable {
    /// The fixed Menu button.
    case menu
    /// A user-bound button resolved through ``GamepadSettings/bindings``.
    case bound(GamepadAction)
    /// A direction-pad press; semantics depend on the active surface.
    case dpad(GamepadDpadDirection)
}

/// Tracks per-element pressed state so callers can act exactly once per
/// physical press (rising edge) and ignore analog chatter and releases.
public struct GamepadPressTracker: Sendable {
    private var pressedElementKeys: Set<String> = []

    public init() {}

    /// Returns `true` exactly when `key` transitions from released to pressed.
    public mutating func registerPressState(_ isPressed: Bool, forKey key: String) -> Bool {
        if isPressed {
            return pressedElementKeys.insert(key).inserted
        }
        pressedElementKeys.remove(key)
        return false
    }

    public mutating func reset() {
        pressedElementKeys.removeAll()
    }
}

// MARK: - Surface interpretation

public enum GamepadScrollDirection: Hashable, Sendable {
    case up
    case down
}

/// What the reader is currently showing, as far as gamepad semantics care.
public enum GamepadReadingSurface: Hashable, Sendable {
    case paged(isRightToLeft: Bool)
    case vertical
}

/// A reader-level command produced from a ``GamepadEvent``.
public enum GamepadReaderCommand: Hashable, Sendable {
    case turnPage(Int)
    case scrollStep(GamepadScrollDirection)
    case openComments
    case toggleChrome
}

/// A command for the chapter-comments sheet while it holds gamepad focus.
public enum GamepadCommentsCommand: Hashable, Sendable {
    case scroll(GamepadScrollDirection)
    case close
}

public enum GamepadCommandResolver {
    /// Scroll step height as a fraction of the viewport; the remainder keeps
    /// visual continuity between steps.
    public static let verticalScrollViewportFraction: Double = 0.85

    /// How many comment rows one scroll step advances in the comments sheet.
    public static let commentsScrollStride = 3

    public static func readerCommand(
        for event: GamepadEvent,
        surface: GamepadReadingSurface
    ) -> GamepadReaderCommand? {
        switch event {
        case .menu:
            return .toggleChrome
        case let .bound(action):
            return boundCommand(for: action, surface: surface)
        case let .dpad(direction):
            return dpadCommand(for: direction, surface: surface)
        }
    }

    public static func commentsCommand(for event: GamepadEvent) -> GamepadCommentsCommand? {
        switch event {
        case .menu, .bound(.openComments):
            .close
        case .dpad(.up):
            .scroll(.up)
        case .dpad(.down):
            .scroll(.down)
        case .bound, .dpad:
            nil
        }
    }

    private static func boundCommand(
        for action: GamepadAction,
        surface: GamepadReadingSurface
    ) -> GamepadReaderCommand? {
        switch (action, surface) {
        case (.nextPage, .paged):
            .turnPage(1)
        case (.previousPage, .paged):
            .turnPage(-1)
        case (.nextPage, .vertical):
            .scrollStep(.down)
        case (.previousPage, .vertical):
            .scrollStep(.up)
        case (.openComments, _):
            .openComments
        case (.toggleChrome, _):
            .toggleChrome
        }
    }

    private static func dpadCommand(
        for direction: GamepadDpadDirection,
        surface: GamepadReadingSurface
    ) -> GamepadReaderCommand? {
        switch surface {
        case let .paged(isRightToLeft):
            switch direction {
            case .up:
                return .turnPage(-1)
            case .down:
                return .turnPage(1)
            case .left:
                return .turnPage(isRightToLeft ? 1 : -1)
            case .right:
                return .turnPage(isRightToLeft ? -1 : 1)
            }
        case .vertical:
            switch direction {
            case .up:
                return .scrollStep(.up)
            case .down:
                return .scrollStep(.down)
            case .left, .right:
                return nil
            }
        }
    }
}
