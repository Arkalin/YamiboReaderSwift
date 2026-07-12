import SwiftUI
import YamiboReaderCore

private enum ForumBoardReaderModeSelection: Hashable, CaseIterable {
    case plain
    case novel
    case manga

    var title: String {
        switch self {
        case .plain:
            L10n.string("forum.board.reader_settings.mode.plain")
        case .novel:
            L10n.string("forum.board.reader_settings.mode.novel")
        case .manga:
            L10n.string("forum.board.reader_settings.mode.manga")
        }
    }
}

struct ForumBoardReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: ForumBoardViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.string("forum.board.reader_settings.mode"), selection: modeBinding) {
                        ForEach(ForumBoardReaderModeSelection.allCases, id: \.self) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }

                    if case .manga = model.boardReaderEntry?.mode {
                        Toggle(
                            L10n.string("forum.board.reader_settings.smart_toggle"),
                            isOn: smartComicModeBinding
                        )
                    }
                } footer: {
                    Text(L10n.string("forum.board.reader_settings.footer"))
                }
            }
            .navigationTitle(L10n.string("forum.board.reader_settings"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // A failure alert left over from a previous presentation must not
            // fire out of context on the fresh sheet.
            model.boardReaderErrorMessage = nil
            await model.refreshBoardReaderEntry()
        }
        .alert(
            L10n.string("common.operation_failed"),
            isPresented: Binding(
                get: { model.boardReaderErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.boardReaderErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.boardReaderErrorMessage = nil
            }
        } message: {
            Text(model.boardReaderErrorMessage ?? "")
        }
    }

    private var currentSelection: ForumBoardReaderModeSelection {
        switch model.boardReaderEntry?.mode {
        case .novel:
            .novel
        case .manga:
            .manga
        case .normal, nil:
            .plain
        }
    }

    private var modeBinding: Binding<ForumBoardReaderModeSelection> {
        Binding(
            get: { currentSelection },
            set: { selection in
                // The change guard doubles as entry hygiene: a never-
                // configured board re-selecting 普通 is a no-op (no `.normal`
                // entry gets created), while switching AWAY from novel/manga
                // records the explicit `.normal` entry that forces plain
                // opening in the favorites dispatch (R12).
                guard selection != currentSelection else { return }
                switch selection {
                case .plain:
                    model.setBoardReaderMode(.normal)
                case .novel:
                    model.setBoardReaderMode(.novel)
                case .manga:
                    // Newly manga-configured boards default Smart Comic Mode
                    // off (PRD decision #8).
                    model.setBoardReaderMode(.manga(smartEnabled: false))
                }
            }
        )
    }

    private var smartComicModeBinding: Binding<Bool> {
        Binding(
            get: {
                if case .manga(smartEnabled: true) = model.boardReaderEntry?.mode {
                    return true
                }
                return false
            },
            set: { isEnabled in
                model.setBoardReaderMode(.manga(smartEnabled: isEnabled))
            }
        )
    }
}
