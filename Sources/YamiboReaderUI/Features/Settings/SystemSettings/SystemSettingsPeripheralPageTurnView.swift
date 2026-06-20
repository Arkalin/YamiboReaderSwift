import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit
#endif

struct SystemSettingsPeripheralPageTurnView: View {
    @ObservedObject var viewModel: SystemSettingsViewModel
    @State private var showsApplePencilHelp = false

    private var showsApplePencilSection: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
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

            Section(L10n.string("settings.gamepad")) {
                StaticGamepadMappingRow(title: L10n.string("settings.gamepad.next_page"))
                StaticGamepadMappingRow(title: L10n.string("settings.gamepad.previous_page"))
                StaticGamepadMappingRow(title: L10n.string("settings.gamepad.open_comments"))
            }
        }
        .navigationTitle(L10n.string("settings.peripheral_behavior"))
    }
}

private struct StaticGamepadMappingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(L10n.string("settings.gamepad.unset"))
                .foregroundStyle(.secondary)
        }
    }
}
