import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaDirectorySheet: View {
    let panel: MangaDirectoryPanelPresentation
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void
    let onUpdateDirectory: () -> Void
    let onSaveCorrection: (MangaDirectoryEditDraft) -> Void
    let onDeleteChapters: (Set<String>) -> Void
    let onSelectChapter: (MangaChapter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MangaDirectoryEditDraft(
        cleanBookName: "",
        primaryKeyword: "",
        secondaryKeyword: ""
    )
    @State private var didSeedDraft = false
    @State private var isCorrectionPresented = false
    @State private var isSelecting = false
    @State private var selectedChapterTIDs: Set<String> = []
    @State private var isCurrentChapterDeleteAlertPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MangaDirectoryMetadataSection(
                        panel: panel,
                        isSelecting: isSelecting,
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
                        isSelecting: $isSelecting,
                        selectedChapterTIDs: $selectedChapterTIDs,
                        onSortOrderChange: onSortOrderChange,
                        onSelectChapter: onSelectChapter,
                        onDeleteChapter: deleteChapter
                    )
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting && !usesSystemSelectionBottomToolbar {
                    MangaDirectorySelectionActionBar(
                        selectedChapterTIDs: selectedChapterTIDs,
                        onDelete: deleteSelectedChapters
                    )
                }
            }
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

                if isSelecting && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        MangaDirectorySelectionToolbarCapsule(
                            selectedChapterTIDs: selectedChapterTIDs,
                            onDelete: deleteSelectedChapters
                        )
                    }
                }
            }
            .task {
                guard !didSeedDraft else { return }
                seedDraft(from: panel)
                didSeedDraft = true
            }
            .onChange(of: panel.displayChapters.map(\.tid)) { _, visibleTIDs in
                selectedChapterTIDs.formIntersection(Set(visibleTIDs))
            }
            .sensoryFeedback(.selection, trigger: selectedChapterTIDs)
            .alert(L10n.string("manga.delete_current_chapter_failed"), isPresented: $isCurrentChapterDeleteAlertPresented) {
                Button(L10n.string("common.ok"), role: .cancel) {}
            } message: {
                Text(L10n.string("manga.delete_current_chapter_failed_message"))
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

    private var usesSystemSelectionBottomToolbar: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    private func seedDraft(from panel: MangaDirectoryPanelPresentation) {
        draft = panel.editDraft ?? MangaDirectoryEditDraft(
            cleanBookName: panel.directoryTitle,
            primaryKeyword: "",
            secondaryKeyword: ""
        )
    }

    private func deleteSelectedChapters() {
        let selectedTIDs = selectedChapterTIDs
        guard !selectedTIDs.isEmpty else {
            return
        }
        if selectedTIDs.contains(panel.currentChapterTID ?? "") {
            isCurrentChapterDeleteAlertPresented = true
            return
        }
        onDeleteChapters(selectedTIDs)
        exitSelectionMode()
    }

    private func deleteChapter(_ chapter: MangaChapter) {
        if chapter.tid == panel.currentChapterTID {
            isCurrentChapterDeleteAlertPresented = true
            return
        }
        onDeleteChapters([chapter.tid])
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedChapterTIDs.removeAll()
    }
}

private struct MangaDirectorySelectionToolbarCapsule: View {
    let selectedChapterTIDs: Set<String>
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton(
                title: L10n.string("common.delete"),
                systemImage: "trash",
                role: .destructive,
                isEnabled: canDelete,
                action: onDelete
            )
            .disabled(!canDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canDelete: Bool {
        !selectedChapterTIDs.isEmpty
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            toolbarLabel(title: title, systemImage: systemImage, role: role)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private func toolbarLabel(
        title: String,
        systemImage: String,
        role: ButtonRole?
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 24, height: 22)

            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: 66)
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .contentShape(Rectangle())
    }
}

private struct MangaDirectoryMetadataSection: View {
    let panel: MangaDirectoryPanelPresentation
    let isSelecting: Bool
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

                    if !isSelecting {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(isSelecting)

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
                .disabled(!panel.isUpdateButtonEnabled || isSelecting)
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
    @Binding var isSelecting: Bool
    @Binding var selectedChapterTIDs: Set<String>
    let onSortOrderChange: (MangaDirectorySortOrder) -> Void
    let onSelectChapter: (MangaChapter) -> Void
    let onDeleteChapter: (MangaChapter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isSelecting {
                    Button(visibleSelectionIsComplete ? L10n.string("common.invert_selection") : L10n.string("common.select_all")) {
                        toggleVisibleSelection()
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(chapters.isEmpty)
                } else {
                    MangaDirectorySortToggleButton(
                        sortOrder: sortOrder,
                        onSortOrderChange: onSortOrderChange
                    )
                }

                Spacer(minLength: 0)

                MangaDirectorySelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        exitSelectionMode()
                    } else {
                        isSelecting = true
                    }
                }
            }
            .frame(height: 38, alignment: .center)

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
                            isSelecting: isSelecting,
                            isSelected: selectedChapterTIDs.contains(chapter.tid),
                            onSelectChapter: onSelectChapter,
                            onToggleSelection: toggleSelection,
                            onBeginSelection: beginSelection,
                            onDeleteChapter: onDeleteChapter
                        )
                    }
                }
            }
        }
    }

    private var visibleChapterTIDs: Set<String> {
        Set(chapters.map(\.tid))
    }

    private var visibleSelectionIsComplete: Bool {
        !chapters.isEmpty && visibleChapterTIDs.isSubset(of: selectedChapterTIDs)
    }

    private func toggleVisibleSelection() {
        if visibleSelectionIsComplete {
            selectedChapterTIDs.subtract(visibleChapterTIDs)
        } else {
            selectedChapterTIDs.formUnion(visibleChapterTIDs)
        }
    }

    private func toggleSelection(_ chapter: MangaChapter) {
        if selectedChapterTIDs.contains(chapter.tid) {
            selectedChapterTIDs.remove(chapter.tid)
        } else {
            selectedChapterTIDs.insert(chapter.tid)
        }
    }

    private func beginSelection(_ chapter: MangaChapter) {
        guard !isSelecting else { return }
        isSelecting = true
        selectedChapterTIDs.insert(chapter.tid)
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedChapterTIDs.removeAll()
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

private struct MangaDirectorySelectionToggleButton: View {
    let isSelecting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelecting {
                Text(L10n.string("common.done"))
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelecting ? L10n.string("common.done") : L10n.string("common.select"))
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let onSelectChapter: (MangaChapter) -> Void
    let onToggleSelection: (MangaChapter) -> Void
    let onBeginSelection: (MangaChapter) -> Void
    let onDeleteChapter: (MangaChapter) -> Void

    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var isDeleteRevealed = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeActive = false

    var body: some View {
        ZStack(alignment: .trailing) {
            swipeDeleteButton
                .opacity(isDeleteActionVisible ? 1 : 0)
                .mask(alignment: .trailing) {
                    Rectangle()
                        .frame(width: deleteActionRevealWidth)
                }
                .allowsHitTesting(isDeleteActionVisible)

            HStack(alignment: .top, spacing: 12) {
                Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(numberColor)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    TruncationAwareText(
                        chapter.rawTitle,
                        font: UIFont.preferredFont(forTextStyle: .subheadline),
                        lineLimit: isExpanded ? nil : 1,
                        isTruncated: $isTruncated
                    )
                    .font(.subheadline)
                    .foregroundStyle(titleColor)

                    if isTruncated {
                        Button(isExpanded ? L10n.string("common.collapse") : L10n.string("common.expand")) {
                            isExpanded.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                    }
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(cornerRadii: rowCornerRadii, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                UnevenRoundedRectangle(cornerRadii: rowCornerRadii, style: .continuous)
                    .strokeBorder(isSelecting && isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .offset(x: rowOffset)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSelected)
            .onTapGesture {
                if isDeleteRevealed {
                    closeDeleteAction()
                    return
                }
                if isSelecting {
                    onToggleSelection(chapter)
                } else {
                    guard !isCurrent else { return }
                    onSelectChapter(chapter)
                }
            }
            .onLongPressGesture {
                closeDeleteAction()
                onBeginSelection(chapter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .simultaneousGesture(swipeGesture)
        .onChange(of: isSelecting) { _, isSelecting in
            if isSelecting {
                closeDeleteAction()
            }
        }
    }

    private var titleColor: Color {
        isSelecting && !isSelected ? .secondary : .primary
    }

    private var numberColor: Color {
        if isSelecting {
            if isSelected {
                return isCurrent ? .orange : .secondary
            }
            return isCurrent ? Color.orange.opacity(0.45) : Color.secondary.opacity(0.55)
        }
        return isCurrent ? .orange : .secondary
    }

    private var accentColor: Color {
        isSelecting && !isSelected ? Color.orange.opacity(0.45) : .orange
    }

    private var backgroundColor: Color {
        if isCurrent {
            return Color.orange.opacity(isSelecting && !isSelected ? 0.06 : 0.12)
        }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var swipeActionWidth: CGFloat {
        76
    }

    private var rowCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: 12,
            bottomLeading: 12,
            bottomTrailing: rowTrailingCornerRadius,
            topTrailing: rowTrailingCornerRadius
        )
    }

    private var rowTrailingCornerRadius: CGFloat {
        isDeleteActionVisible ? 0 : 12
    }

    private var rowOffset: CGFloat {
        isSelecting ? 0 : swipeOffset
    }

    private var deleteActionRevealWidth: CGFloat {
        min(swipeActionWidth, max(0, -rowOffset))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if !isSwipeActive {
                    guard shouldStartSwipe(value.translation) else { return }
                    isSwipeActive = true
                }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    swipeOffset = clampedSwipeOffset(for: value.translation)
                }
            }
            .onEnded { value in
                defer {
                    isSwipeActive = false
                }

                guard isSwipeActive else { return }
                let proposedOffset = clampedSwipeOffset(for: value.translation)
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    let shouldReveal = proposedOffset < -swipeActionWidth * 0.5
                    isDeleteRevealed = shouldReveal
                    swipeOffset = shouldReveal ? -swipeActionWidth : 0
                }
            }
    }

    private var swipeDeleteButton: some View {
        Button(role: .destructive) {
            closeDeleteAction()
            onDeleteChapter(chapter)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))

                Text(L10n.string("common.delete"))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: swipeActionWidth)
            .frame(maxHeight: .infinity)
            .foregroundStyle(canDeleteFromSwipe ? Color.white : Color.secondary)
            .background(canDeleteFromSwipe ? Color.red : Color(uiColor: .tertiarySystemFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canDeleteFromSwipe || !isDeleteActionVisible)
        .accessibilityLabel(L10n.string("common.delete"))
    }

    private var canDeleteFromSwipe: Bool {
        !isCurrent && !isSelecting
    }

    private var isDeleteActionVisible: Bool {
        !isSelecting && (isDeleteRevealed || swipeOffset < -1)
    }

    private func shouldStartSwipe(_ translation: CGSize) -> Bool {
        guard !isSelecting else { return false }
        guard abs(translation.width) > abs(translation.height) * 1.25 else { return false }
        return translation.width < 0 || isDeleteRevealed
    }

    private func clampedSwipeOffset(for translation: CGSize) -> CGFloat {
        let baseOffset = isDeleteRevealed ? -swipeActionWidth : 0
        let proposedOffset = baseOffset + translation.width
        return min(0, max(-swipeActionWidth, proposedOffset))
    }

    private func closeDeleteAction() {
        guard isDeleteRevealed || swipeOffset != 0 else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            isDeleteRevealed = false
            swipeOffset = 0
        }
    }
}

private struct MangaDirectorySelectionActionBar: View {
    let selectedChapterTIDs: Set<String>
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                actionButton(
                    title: L10n.string("common.delete"),
                    systemImage: "trash",
                    role: .destructive,
                    isEnabled: canDelete,
                    action: onDelete
                )
                .disabled(!canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private var canDelete: Bool {
        !selectedChapterTIDs.isEmpty
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 22)

                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 72)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
