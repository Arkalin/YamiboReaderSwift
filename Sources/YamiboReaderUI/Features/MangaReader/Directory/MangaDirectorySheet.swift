import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

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
    @State private var isCorrectionPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MangaDirectoryMetadataSection(
                        panel: panel,
                        onUpdateDirectory: onUpdateDirectory,
                        onEditDirectory: {
                            seedDraft(from: panel)
                            isCorrectionPresented = true
                        }
                    )

                    MangaDirectoryChapterSection(
                        chapters: panel.displayChapters,
                        currentChapterTID: panel.currentChapterTID,
                        sortOrder: panel.sortOrder,
                        onSortOrderChange: onSortOrderChange,
                        onSelectChapter: onSelectChapter
                    )
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.string("manga.directory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("common.close"))
                }
            }
            .task {
                guard !didSeedDraft else { return }
                seedDraft(from: panel)
                didSeedDraft = true
            }
            .sheet(isPresented: $isCorrectionPresented) {
                MangaDirectoryCorrectionSheet(
                    draft: $draft,
                    onSaveCorrection: { draft in
                        onSaveCorrection(draft)
                        isCorrectionPresented = false
                    }
                )
                .presentationDetents([.height(280)])
            }
        }
    }

    private func seedDraft(from panel: MangaDirectoryPanelPresentation) {
        draft = panel.editDraft ?? MangaDirectoryEditDraft(
            cleanBookName: panel.directoryTitle,
            primaryKeyword: "",
            secondaryKeyword: ""
        )
    }
}

private struct MangaDirectoryMetadataSection: View {
    let panel: MangaDirectoryPanelPresentation
    let onUpdateDirectory: () -> Void
    let onEditDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                onEditDirectory()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(panel.directoryTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 12) {
                if let latestChapterText = panel.latestChapterText {
                    Text(latestChapterText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(panel.updateButtonTitle) {
                    onUpdateDirectory()
                }
                .buttonStyle(.borderedProminent)
                .tint(panel.isSearchMode ? .indigo : .orange)
                .disabled(!panel.isUpdateButtonEnabled)
            }

            if let errorMessage = panel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct MangaDirectoryChapterSection: View {
    let chapters: [MangaChapter]
    let currentChapterTID: String?
    let sortOrder: MangaDirectorySortOrder
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void
    let onSelectChapter: (MangaChapter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MangaDirectorySortToggleButton(
                    sortOrder: sortOrder,
                    onSortOrderChange: onSortOrderChange
                )

                Spacer(minLength: 0)
            }

            if chapters.isEmpty {
                ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
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
}

private struct MangaDirectorySortToggleButton: View {
    let sortOrder: MangaDirectorySortOrder
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void

    var body: some View {
        Button {
            onSortOrderChange(toggledSortOrder)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .foregroundStyle(sortOrder == .ascending ? .orange : .gray.opacity(0.35))

                Image(systemName: "arrow.up")
                    .foregroundStyle(sortOrder == .descending ? .orange : .gray.opacity(0.35))
            }
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("favorites.sort"))
        .accessibilityValue(sortOrder.title)
    }

    private var toggledSortOrder: MangaDirectorySortOrder {
        switch sortOrder {
        case .ascending: .descending
        case .descending: .ascending
        }
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let onSelectChapter: (MangaChapter) -> Void

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? .orange : .secondary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                TruncationAwareText(
                    chapter.rawTitle,
                    font: UIFont.preferredFont(forTextStyle: .subheadline),
                    lineLimit: isExpanded ? nil : 1,
                    isTruncated: $isTruncated
                )
                .font(.subheadline)
                .foregroundStyle(.primary)

                if isTruncated {
                    Button(isExpanded ? L10n.string("common.collapse") : L10n.string("common.expand")) {
                        isExpanded.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if isCurrent {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isCurrent
                        ? Color.orange.opacity(0.12)
                        : Color(uiColor: .secondarySystemGroupedBackground)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent else { return }
            onSelectChapter(chapter)
        }
    }
}

private struct MangaDirectoryCorrectionSheet: View {
    @Binding var draft: MangaDirectoryEditDraft
    let onSaveCorrection: (MangaDirectoryEditDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                MangaDirectoryCorrectionFields(
                    draft: $draft
                )
            }
            .navigationTitle(L10n.string("manga.correction_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("common.close"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSaveCorrection(trimmedDraft)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(trimmedDraft.cleanBookName.isEmpty)
                    .accessibilityLabel(L10n.string("manga.save_correction"))
                }
            }
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

private struct MangaDirectoryCorrectionFields: View {
    @Binding var draft: MangaDirectoryEditDraft

    var body: some View {
        Section {
            TextField(L10n.string("manga.name"), text: $draft.cleanBookName)

            TextField(L10n.string("manga.keyword_primary"), text: $draft.primaryKeyword)

            TextField(L10n.string("manga.keyword_secondary"), text: $draft.secondaryKeyword)
        }
    }
}

private struct TruncationAwareText: View {
    let text: String
    let font: UIFont
    let lineLimit: Int?
    @Binding var isTruncated: Bool

    @State private var availableWidth: CGFloat = 0

    init(
        _ text: String,
        font: UIFont,
        lineLimit: Int?,
        isTruncated: Binding<Bool>
    ) {
        self.text = text
        self.font = font
        self.lineLimit = lineLimit
        _isTruncated = isTruncated
    }

    var body: some View {
        Text(text)
            .lineLimit(lineLimit)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            availableWidth = proxy.size.width
                            updateTruncation()
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            availableWidth = newValue
                            updateTruncation()
                        }
                }
            )
    }

    private func updateTruncation() {
        guard availableWidth > 0 else { return }
        let rect = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        .boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        isTruncated = rect.height > (font.lineHeight * 1.2)
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
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(L10n.string("common.close"))
                    }
                }
        }
    }
}
#endif
