import SwiftUI
import YamiboReaderCore

/// Browsing-history page pushed from the Mine tab's "浏览历史" entry.
///
/// Time-descending timeline with date-group headers, a four-way type filter,
/// local title search, swipe-to-delete, a confirm-guarded clear-all, and a
/// quick-favorite heart per row (browsing-history decision #10).
struct BrowsingHistoryView: View {
    @State private var model: BrowsingHistoryViewModel
    private let appModel: YamiboAppModel

    init(dependencies: LibraryDependencies, appModel: YamiboAppModel) {
        _model = State(initialValue: BrowsingHistoryViewModel(dependencies: dependencies))
        self.appModel = appModel
    }

    var body: some View {
        historyList
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ForumColors.creamBackground.ignoresSafeArea())
        .navigationTitle(L10n.string("forum.history"))
        .yamiboInlineNavigationTitleDisplayMode()
        .searchable(text: searchTextBinding, prompt: L10n.string("history.search.prompt"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.clearAllConfirmationPresented = true
                } label: {
                    Label(L10n.string("history.clear_all"), systemImage: "trash")
                }
                .disabled(model.entries.isEmpty)
            }
        }
        .confirmationDialog(
            L10n.string("history.clear_all.title"),
            isPresented: Bindable(model).clearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.string("history.clear_all"), role: .destructive) {
                Task { await model.clearAll() }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("history.clear_all.message"))
        }
        .favoriteQuickActionDialogs(
            addPromptPresented: Bindable(model).favoriteAddPromptPresented,
            removePrompt: Bindable(model).favoriteRemovePrompt,
            onConfirmAdd: { syncToRemote, remember in
                Task { await model.confirmFavoriteAdd(syncToRemote: syncToRemote, remember: remember) }
            },
            onConfirmRemoval: { favorite, removeRemote, remember in
                Task { await model.confirmFavoriteRemoval(favorite, removeRemote: removeRemote, remember: remember) }
            }
        )
        .alert(L10n.string("common.operation_failed"), isPresented: errorIsPresented, actions: {
            Button(L10n.string("common.ok")) {
                model.clearError()
            }
        }, message: {
            Text(model.errorMessage ?? "")
        })
        .overlay {
            if model.hasLoaded, model.entries.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    isFiltering
                        ? L10n.string("history.empty.search")
                        : L10n.string("history.empty"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
        .task {
            await model.load()
        }
        .task {
            await model.observeHistoryChanges()
        }
        .task {
            await model.observeFavoriteChanges()
        }
        .onChange(of: model.selectedCategory) {
            Task { await model.reload() }
        }
        .onChange(of: model.searchText) {
            model.scheduleReload()
        }
        .forumTransientMessage(model.transientMessage, bottomPadding: 24) {
            model.clearTransientMessage()
        }
    }

    private var historyList: some View {
        List {
            Section {
                categoryPicker
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            ForEach(daySections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
    }

    private func row(for entry: BrowsingHistoryEntry) -> some View {
        BrowsingHistoryRow(
            entry: entry,
            coverURL: model.coverURLsByEntryID[entry.id],
            isFavorited: model.isFavorited(entry),
            canToggleFavorite: model.heartThreadID(for: entry) != nil,
            onOpen: {
                Task { await open(entry) }
            },
            onToggleFavorite: {
                Task { await model.toggleFavorite(entry) }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await model.delete(entry) }
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearError()
                }
            }
        )
    }

    private var categoryPicker: some View {
        Picker(L10n.string("history.filter.all"), selection: Bindable(model).selectedCategory) {
            Text(L10n.string("history.filter.all")).tag(BrowsingHistoryCategory?.none)
            Text(L10n.string("history.filter.normal")).tag(BrowsingHistoryCategory?.some(.normal))
            Text(L10n.string("history.filter.novel")).tag(BrowsingHistoryCategory?.some(.novel))
            Text(L10n.string("history.filter.manga")).tag(BrowsingHistoryCategory?.some(.manga))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var searchTextBinding: Binding<String> {
        Bindable(model).searchText
    }

    private var isFiltering: Bool {
        model.selectedCategory != nil || !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func open(_ entry: BrowsingHistoryEntry) async {
        guard let target = await model.openTarget(for: entry) else { return }
        switch target {
        case let .novelReader(context):
            appModel.presentNovelReader(context)
        case let .mangaReader(context):
            appModel.presentMangaReader(context)
        case let .nativeThread(url, title):
            appModel.openNativeForumThread(url: url, title: title)
        }
    }

    // MARK: - Date sections

    private struct DaySection: Identifiable {
        let id: String
        let title: String
        let entries: [BrowsingHistoryEntry]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        var currentDay: Date?
        var currentEntries: [BrowsingHistoryEntry] = []

        func flush() {
            guard let day = currentDay, !currentEntries.isEmpty else { return }
            sections.append(
                DaySection(
                    id: Self.sectionIDFormatter.string(from: day),
                    title: Self.sectionTitle(for: day, calendar: calendar),
                    entries: currentEntries
                )
            )
        }

        for entry in model.entries {
            let day = calendar.startOfDay(for: entry.lastVisitTime)
            if day != currentDay {
                flush()
                currentDay = day
                currentEntries = []
            }
            currentEntries.append(entry)
        }
        flush()
        return sections
    }

    private static func sectionTitle(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return L10n.string("history.section.today")
        }
        if calendar.isDateInYesterday(day) {
            return L10n.string("history.section.yesterday")
        }
        if let daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day,
           (2...6).contains(daysAgo) {
            return L10n.string("history.section.days_ago", String(daysAgo))
        }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return Self.sameYearFormatter.string(from: day)
        }
        return Self.otherYearFormatter.string(from: day)
    }

    private static let sectionIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let sameYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let otherYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct BrowsingHistoryRow: View {
    let entry: BrowsingHistoryEntry
    let coverURL: URL?
    let isFavorited: Bool
    let canToggleFavorite: Bool
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    LocalFavoriteCoverThumbnail(url: coverURL, title: entry.title)
                        .frame(width: 52, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let positionText {
                            Text(positionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(Self.relativeFormatter.localizedString(for: entry.lastVisitTime, relativeTo: .now))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.body)
                        .foregroundStyle(isFavorited ? Color.pink : Color.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isFavorited
                        ? L10n.string("history.favorite.remove")
                        : L10n.string("history.favorite.add")
                )
            }
        }
    }

    private var positionText: String? {
        switch entry.category {
        case .normal:
            guard let pageIndex = entry.pageIndex else { return nil }
            if let pageCount = entry.pageCount, pageCount > 1 {
                return L10n.string("history.progress.page_of_total", String(pageIndex), String(pageCount))
            }
            return L10n.string("history.progress.page", String(pageIndex))
        case .novel:
            guard let chapterTitle = entry.chapterTitle else { return nil }
            return L10n.string("history.progress.chapter", chapterTitle)
        case .manga:
            let pageText = entry.pageIndex.map { L10n.string("history.progress.page", String($0 + 1)) }
            if let chapterTitle = entry.chapterTitle, chapterTitle != entry.title {
                if let pageText {
                    return L10n.string("history.progress.manga", chapterTitle, pageText)
                }
                return L10n.string("history.progress.chapter", chapterTitle)
            }
            return pageText
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
