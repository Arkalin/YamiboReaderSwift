import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaDirectorySheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle = ""
    @State private var editedPrimaryKeyword = ""
    @State private var editedSecondaryKeyword = ""
    @State private var isHeaderExpanded = false
    @State private var didLoadDraft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    chaptersSection
                    correctionSection
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.string("manga.directory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.close")) { dismiss() }
                }
            }
            .task {
                guard !didLoadDraft else { return }
                let draft = model.makeDirectoryEditDraft()
                editedTitle = draft.title
                editedPrimaryKeyword = draft.primaryKeyword
                editedSecondaryKeyword = draft.secondaryKeyword
                didLoadDraft = true
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.currentDirectoryTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(isHeaderExpanded ? nil : 1)
                .onTapGesture {
                    isHeaderExpanded.toggle()
                }

            HStack(spacing: 10) {
                ForEach(MangaDirectorySortOrder.allCases, id: \.self) { sortOrder in
                    Button(sortOrder.title) {
                        model.applyDirectorySortOrder(sortOrder)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.settings.directorySortOrder == sortOrder ? .accentColor : .gray.opacity(0.35))
                    .foregroundStyle(model.settings.directorySortOrder == sortOrder ? .white : .primary)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                if let latestChapterText = model.latestChapterText {
                    Text(latestChapterText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(model.directoryUpdateButtonTitle) {
                    Task { await model.updateDirectoryFromPanel() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isDirectoryUpdateSearchMode ? .indigo : .orange)
                .disabled(!model.isDirectoryUpdateButtonEnabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("manga.chapter_list"))
                .font(.headline)

            if model.sortedDirectoryChapters.isEmpty {
                ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.sortedDirectoryChapters) { chapter in
                        MangaDirectoryChapterRow(
                            chapter: chapter,
                            isCurrent: chapter.tid == model.currentPage?.tid,
                            isDisabled: model.isTransitioningChapter
                        ) {
                            dismiss()
                            Task { await model.jumpToChapter(chapter) }
                        }
                    }
                }
            }
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("manga.correction_title"))
                .font(.headline)

            TextField(L10n.string("manga.name"), text: $editedTitle)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.string("manga.keyword_primary"), text: $editedPrimaryKeyword)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.string("manga.keyword_secondary"), text: $editedSecondaryKeyword)
                .textFieldStyle(.roundedBorder)

            Button(L10n.string("manga.save_correction")) {
                Task {
                    await model.renameDirectory(
                        cleanBookName: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchKeyword: combinedSearchKeyword
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var combinedSearchKeyword: String {
        [editedPrimaryKeyword, editedSecondaryKeyword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

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
                .foregroundStyle(isCurrent ? .primary : .primary)

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
                .fill(isCurrent ? Color.orange.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .opacity(isDisabled && !isCurrent ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent, !isDisabled else { return }
            onSelect()
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
#endif
