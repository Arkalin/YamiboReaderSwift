import SwiftUI
import YamiboReaderCore
import UIKit

struct SystemSettingsPeripheralPageTurnView: View {
    @ObservedObject var viewModel: SystemSettingsViewModel
    var gamepadInput: GamepadInputManager?
    @State private var showsApplePencilHelp = false
    @State private var capturingAction: GamepadAction?
    @State private var showsCaptureRejectedNotice = false
    @State private var captureRejectionDismissTask: Task<Void, Never>?

    private var showsApplePencilSection: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isControllerConnected: Bool {
        gamepadInput?.isControllerConnected == true
    }

    var body: some View {
        Form {
            if showsApplePencilSection {
                Section("Apple Pencil") {
                    HStack(spacing: 8) {
                        Text(L10n.string("apple_pencil.page_turn"))
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsApplePencilHelp.toggle()
                            }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { viewModel.applePencilPageTurn.isEnabled },
                            set: { viewModel.updateApplePencilPageTurnEnabled($0) }
                        ))
                        .labelsHidden()
                        .disabled(viewModel.isBusy)
                    }
                    if showsApplePencilHelp {
                        Text(L10n.string("apple_pencil.help"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Picker(
                        L10n.string("apple_pencil.behavior.title"),
                        selection: Binding(
                            get: { viewModel.applePencilPageTurn.behavior },
                            set: { viewModel.updateApplePencilPageTurnBehavior($0) }
                        )
                    ) {
                        ForEach(ApplePencilPageTurnBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .disabled(viewModel.isBusy)
                }
            }

            Section {
                connectionStatusRow
                Toggle(L10n.string("settings.gamepad.enabled"), isOn: Binding(
                    get: { viewModel.gamepad.isEnabled },
                    set: { viewModel.updateGamepadEnabled($0) }
                ))
                .disabled(viewModel.isBusy)
                ForEach(GamepadAction.userBindableActions, id: \.self) { action in
                    gamepadBindingRow(action)
                }
                fixedMenuRow
                Button(L10n.string("settings.gamepad.restore_defaults")) {
                    cancelCaptureIfNeeded()
                    viewModel.restoreGamepadDefaultBindings()
                }
                .disabled(viewModel.isBusy)
            } header: {
                Text(L10n.string("settings.gamepad"))
            } footer: {
                Text(gamepadFooterText)
            }
        }
        .navigationTitle(L10n.string("settings.peripheral_behavior"))
        .onDisappear {
            cancelCaptureIfNeeded()
        }
    }

    private var connectionStatusRow: some View {
        HStack(spacing: 12) {
            Text(L10n.string("settings.gamepad.status"))
            Spacer(minLength: 0)
            Text(connectionStatusText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var connectionStatusText: String {
        guard let gamepadInput, gamepadInput.isControllerConnected else {
            return L10n.string("settings.gamepad.status.disconnected")
        }
        return L10n.string(
            "settings.gamepad.status.connected",
            gamepadInput.connectedControllerNames.joined(separator: "、")
        )
    }

    private var fixedMenuRow: some View {
        HStack(spacing: 12) {
            Text(GamepadAction.toggleChrome.title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text(L10n.string("settings.gamepad.menu_fixed"))
                .foregroundStyle(.secondary)
        }
    }

    private var gamepadFooterText: String {
        var lines = [L10n.string("settings.gamepad.dpad_note")]
        if !isControllerConnected {
            lines.append(L10n.string("settings.gamepad.connect_hint"))
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func gamepadBindingRow(_ action: GamepadAction) -> some View {
        if capturingAction == action {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(action.title)
                    Spacer(minLength: 8)
                    Text(showsCaptureRejectedNotice
                        ? L10n.string("settings.gamepad.capture_rejected")
                        : L10n.string("settings.gamepad.capture_prompt"))
                        .font(.footnote)
                        .foregroundStyle(showsCaptureRejectedNotice ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                HStack(spacing: 20) {
                    Button(L10n.string("common.cancel")) {
                        cancelCaptureIfNeeded()
                    }
                    if viewModel.gamepad.bindings[action] != nil {
                        Button(L10n.string("settings.gamepad.clear_binding"), role: .destructive) {
                            cancelCaptureIfNeeded()
                            viewModel.clearGamepadBinding(for: action)
                        }
                    }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
        } else {
            Button {
                beginCapture(for: action)
            } label: {
                HStack(spacing: 12) {
                    Text(action.title)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    bindingValueLabel(for: action)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy || !isControllerConnected || capturingAction != nil)
        }
    }

    @ViewBuilder
    private func bindingValueLabel(for action: GamepadAction) -> some View {
        if let alias = viewModel.gamepad.bindings[action] {
            let display = gamepadInput?.displayInfo(forElementAlias: alias)
            HStack(spacing: 6) {
                if let symbolName = display?.sfSymbolsName {
                    Image(systemName: symbolName)
                }
                Text(display?.localizedName ?? alias)
            }
            .foregroundStyle(.secondary)
        } else {
            Text(L10n.string("settings.gamepad.unset"))
                .foregroundStyle(.secondary)
        }
    }

    private func beginCapture(for action: GamepadAction) {
        guard let gamepadInput else { return }
        capturingAction = action
        showsCaptureRejectedNotice = false
        gamepadInput.beginCapture { feedback in
            switch feedback {
            case let .captured(element):
                captureRejectionDismissTask?.cancel()
                capturingAction = nil
                showsCaptureRejectedNotice = false
                viewModel.bindGamepadAction(action, toElementAlias: element.alias)
            case .rejected:
                showsCaptureRejectedNotice = true
                captureRejectionDismissTask?.cancel()
                captureRejectionDismissTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    showsCaptureRejectedNotice = false
                }
            }
        }
    }

    private func cancelCaptureIfNeeded() {
        captureRejectionDismissTask?.cancel()
        captureRejectionDismissTask = nil
        gamepadInput?.cancelCapture()
        capturingAction = nil
        showsCaptureRejectedNotice = false
    }
}
