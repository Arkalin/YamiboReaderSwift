#if os(iOS)
import Foundation
import GameController
import Observation
import YamiboReaderCore

/// App-wide game-controller listener. Translates `GCControllerLiveInput`
/// element changes into logical ``GamepadEvent``s and delivers them to the
/// top of a consumer stack (reader below, comments sheet above). The settings
/// page can preempt dispatch with a capture session to bind buttons.
///
/// Listens to every connected controller at once; the readers gate on their
/// own presentation state, this class only gates on the master switch.
@MainActor
@Observable
public final class GamepadInputManager {
    public struct CapturedElement: Hashable, Sendable {
        public let alias: String
        public let sfSymbolsName: String?
        public let localizedName: String?

        public init(alias: String, sfSymbolsName: String?, localizedName: String?) {
            self.alias = alias
            self.sfSymbolsName = sfSymbolsName
            self.localizedName = localizedName
        }
    }

    public enum CaptureFeedback: Hashable, Sendable {
        /// A bindable element was pressed; the capture session has ended.
        case captured(CapturedElement)
        /// A fixed/system element was pressed; the session keeps waiting.
        case rejected
    }

    public struct ElementDisplayInfo: Hashable, Sendable {
        public let sfSymbolsName: String?
        public let localizedName: String?
    }

    /// Vendor names of every connected controller, for the settings page.
    public private(set) var connectedControllerNames: [String] = []

    public var isControllerConnected: Bool {
        !connectedControllerNames.isEmpty
    }

    @ObservationIgnored private var settings = GamepadSettings()
    @ObservationIgnored private var handlerStack: [(token: UUID, handler: (GamepadEvent) -> Void)] = []
    @ObservationIgnored private var captureHandler: ((CaptureFeedback) -> Void)?
    @ObservationIgnored private var pressTracker = GamepadPressTracker()
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private var monitorTasks: [Task<Void, Never>] = []

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        startMonitoring()
    }

    deinit {
        for task in monitorTasks {
            task.cancel()
        }
    }

    // MARK: - Consumer stack

    /// Registers `handler` as the active event consumer, stacking above any
    /// current one. Returns a token for ``removeHandler(_:)`` on disappear.
    @discardableResult
    public func pushHandler(_ handler: @escaping (GamepadEvent) -> Void) -> UUID {
        let token = UUID()
        handlerStack.append((token, handler))
        return token
    }

    public func removeHandler(_ token: UUID?) {
        guard let token else { return }
        handlerStack.removeAll { $0.token == token }
    }

    // MARK: - Binding capture

    /// Suspends event dispatch and reports the next press instead. Bindable
    /// presses end the session; excluded ones emit `.rejected` and keep it
    /// alive. Works regardless of the master switch so the settings page can
    /// always rebind.
    public func beginCapture(_ feedback: @escaping (CaptureFeedback) -> Void) {
        captureHandler = feedback
    }

    public func cancelCapture() {
        captureHandler = nil
    }

    /// Looks up display metadata for a persisted alias on the currently
    /// connected controllers, so bound rows can render real glyphs.
    public func displayInfo(forElementAlias alias: String) -> ElementDisplayInfo? {
        for controller in GCController.controllers() {
            guard let element = controller.physicalInputProfile.elements[alias] else { continue }
            return ElementDisplayInfo(
                sfSymbolsName: element.sfSymbolsName,
                localizedName: element.localizedName
            )
        }
        return nil
    }

    // MARK: - Controller monitoring

    private func startMonitoring() {
        for controller in GCController.controllers() {
            attach(controller)
        }
        refreshConnectionState()

        monitorTasks.append(Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                guard !Task.isCancelled else { return }
                guard let controller = notification.object as? GCController else { continue }
                guard let self else { return }
                self.attach(controller)
                self.refreshConnectionState()
            }
        })
        monitorTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.pressTracker.reset()
                self.refreshConnectionState()
            }
        })
        monitorTasks.append(Task { [weak self] in
            await self?.reloadSettings()
            for await _ in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                await self?.reloadSettings()
            }
        })
    }

    private func reloadSettings() async {
        settings = await settingsStore.load().system.gamepad
    }

    private func refreshConnectionState() {
        connectedControllerNames = GCController.controllers().map {
            $0.vendorName ?? $0.productCategory
        }
    }

    private func attach(_ controller: GCController) {
        let controllerKey = ObjectIdentifier(controller)
        let input = controller.input
        input.queue = .main
        input.elementValueDidChangeHandler = { [weak self] _, element in
            MainActor.assumeIsolated {
                self?.handleElementChange(element, controllerKey: controllerKey)
            }
        }
    }

    // MARK: - Event translation

    private func handleElementChange(_ element: any GCPhysicalInputElement, controllerKey: ObjectIdentifier) {
        if let button = element as? GCButtonElement {
            let aliases = button.aliases
            guard registerPress(
                button.pressedInput.isPressed,
                key: "\(controllerKey)#\(aliases.sorted().first ?? "?")"
            ) else { return }
            routeButtonPress(aliases: aliases)
            return
        }

        // Thumbsticks surface as direction-pad elements too; only the real
        // pad carries fixed directional semantics (sticks stay ignored).
        if let dpad = element as? GCDirectionPadElement,
           dpad.aliases.contains(GamepadElementAlias.directionPad) {
            let cardinals: [(GamepadDpadDirection, any GCPressedStateInput)] = [
                (.up, dpad.up), (.down, dpad.down), (.left, dpad.left), (.right, dpad.right),
            ]
            for (direction, pressedInput) in cardinals {
                guard registerPress(
                    pressedInput.isPressed,
                    key: "\(controllerKey)#dpad.\(direction.rawValue)"
                ) else { continue }
                routeDpadPress(direction)
            }
        }
    }

    private func registerPress(_ isPressed: Bool, key: String) -> Bool {
        pressTracker.registerPressState(isPressed, forKey: key)
    }

    private func routeButtonPress(aliases: Set<String>) {
        if let captureHandler {
            guard let alias = GamepadElementAlias.canonicalBindableAlias(in: aliases) else {
                captureHandler(.rejected)
                return
            }
            let display = displayInfo(forElementAlias: alias)
            self.captureHandler = nil
            captureHandler(.captured(CapturedElement(
                alias: alias,
                sfSymbolsName: display?.sfSymbolsName,
                localizedName: display?.localizedName
            )))
            return
        }

        guard settings.isEnabled, let handler = handlerStack.last?.handler else { return }
        if aliases.contains(GamepadElementAlias.buttonMenu) {
            handler(.menu)
            return
        }
        guard let action = settings.action(boundToAnyOf: aliases) else { return }
        handler(.bound(action))
    }

    private func routeDpadPress(_ direction: GamepadDpadDirection) {
        if let captureHandler {
            captureHandler(.rejected)
            return
        }
        guard settings.isEnabled, let handler = handlerStack.last?.handler else { return }
        handler(.dpad(direction))
    }
}
#endif
