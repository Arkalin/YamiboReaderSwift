import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaDirectorySheet: View {
    let panel: MangaDirectoryPanelPresentation
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void
    let onUpdateDirectory: () -> Void
    let onSaveCorrection: (MangaDirectoryEditDraft) -> Void
    let onSelectChapter: (MangaChapter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MangaDirectoryEditDraft(
        cleanBookName: "",
        primaryKeyword: "",
        secondaryKeyword: ""
    )
    @State private var didSeedDraft = false

    var body: some View {
        NavigationStack {
            Form {
                MangaDirectoryMetadataSection(
                    panel: panel,
                    onSortOrderChange: onSortOrderChange,
                    onUpdateDirectory: onUpdateDirectory
                )

                MangaDirectoryChapterSection(
                    chapters: panel.displayChapters,
                    currentChapterTID: panel.currentChapterTID,
                    onSelectChapter: onSelectChapter
                )

                MangaDirectoryCorrectionSection(
                    draft: $draft,
                    onSaveCorrection: onSaveCorrection
                )
            }
            .navigationTitle(L10n.string("manga.directory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.close")) { dismiss() }
                }
            }
            .task {
                guard !didSeedDraft else { return }
                draft = panel.editDraft ?? MangaDirectoryEditDraft(
                    cleanBookName: panel.directoryTitle,
                    primaryKeyword: "",
                    secondaryKeyword: ""
                )
                didSeedDraft = true
            }
        }
    }
}

private struct MangaDirectoryMetadataSection: View {
    let panel: MangaDirectoryPanelPresentation
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void
    let onUpdateDirectory: () -> Void

    var body: some View {
        Section {
            Text(panel.directoryTitle)
                .font(.headline)
                .lineLimit(2)

            Picker(L10n.string("favorites.sort"), selection: sortOrderBinding) {
                ForEach(MangaDirectorySortOrder.allCases, id: \.self) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder)
                }
            }
            .pickerStyle(.segmented)

            if let latestChapterText = panel.latestChapterText {
                Label(latestChapterText, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = panel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Button {
                onUpdateDirectory()
            } label: {
                Label(
                    panel.updateButtonTitle,
                    systemImage: panel.isSearchMode ? "magnifyingglass" : "arrow.clockwise"
                )
            }
            .disabled(!panel.isUpdateButtonEnabled)
        }
    }

    private var sortOrderBinding: Binding<MangaDirectorySortOrder> {
        Binding(
            get: { panel.sortOrder },
            set: { onSortOrderChange($0) }
        )
    }
}

private struct MangaDirectoryChapterSection: View {
    let chapters: [MangaChapter]
    let currentChapterTID: String?
    let onSelectChapter: (MangaChapter) -> Void

    var body: some View {
        Section(L10n.string("manga.chapter_list")) {
            if chapters.isEmpty {
                ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
            } else {
                ForEach(chapters) { chapter in
                    MangaDirectoryChapterRow(
                        chapter: chapter,
                        isCurrent: chapter.tid == currentChapterTID,
                        onSelectChapter: onSelectChapter
                    )
                }
            }
        }
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let onSelectChapter: (MangaChapter) -> Void

    var body: some View {
        Button {
            guard !isCurrent else { return }
            onSelectChapter(chapter)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? .orange : .secondary)
                    .frame(width: 34, alignment: .leading)

                Text(chapter.rawTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }
}

private struct MangaDirectoryCorrectionSection: View {
    @Binding var draft: MangaDirectoryEditDraft
    let onSaveCorrection: (MangaDirectoryEditDraft) -> Void

    var body: some View {
        Section(L10n.string("manga.correction_title")) {
            TextField(L10n.string("manga.name"), text: $draft.cleanBookName)
            TextField(L10n.string("manga.keyword_primary"), text: $draft.primaryKeyword)
            TextField(L10n.string("manga.keyword_secondary"), text: $draft.secondaryKeyword)

            Button {
                onSaveCorrection(trimmedDraft)
            } label: {
                Label(L10n.string("manga.save_correction"), systemImage: "checkmark")
            }
            .disabled(trimmedDraft.cleanBookName.isEmpty)
        }
    }

    private var trimmedDraft: MangaDirectoryEditDraft {
        MangaDirectoryEditDraft(
            cleanBookName: draft.cleanBookName.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryKeyword: draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryKeyword: draft.secondaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct MangaDirectoryUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                .navigationTitle(L10n.string("manga.directory"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.string("common.close")) { dismiss() }
                    }
                }
        }
    }
}
#endif
