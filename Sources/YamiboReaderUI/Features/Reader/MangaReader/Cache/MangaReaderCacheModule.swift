import Combine
import Foundation
import YamiboReaderCore

public struct MangaReaderCacheRow: Hashable, Identifiable, Sendable {
    public var chapter: MangaChapter
    public var state: MangaOfflineCacheState

    public var id: String { chapter.tid }

    public init(chapter: MangaChapter, state: MangaOfflineCacheState) {
        self.chapter = chapter
        self.state = state
    }
}

public struct MangaReaderCacheSelectionState: Equatable, Sendable {
    public var selectedTIDs: Set<String>
    public var uncachedSelectedTIDs: Set<String>
    public var removableSelectedTIDs: Set<String>
    public var canCache: Bool
    public var canDelete: Bool
    public var isAllSelected: Bool

    public init(
        selectedTIDs: Set<String>,
        uncachedSelectedTIDs: Set<String>,
        removableSelectedTIDs: Set<String>,
        canCache: Bool,
        canDelete: Bool,
        isAllSelected: Bool
    ) {
        self.selectedTIDs = selectedTIDs
        self.uncachedSelectedTIDs = uncachedSelectedTIDs
        self.removableSelectedTIDs = removableSelectedTIDs
        self.canCache = canCache
        self.canDelete = canDelete
        self.isAllSelected = isAllSelected
    }
}

public enum MangaReaderCachePrompt: Equatable, Identifiable, Sendable {
    case addFavorite(title: String)

    public var id: String {
        switch self {
        case .addFavorite:
            "addFavorite"
        }
    }
}

@MainActor
public final class MangaReaderCacheViewModel: ObservableObject {
    @Published public private(set) var rows: [MangaReaderCacheRow] = []
    @Published public private(set) var favorite: Favorite?
    @Published public private(set) var prompt: MangaReaderCachePrompt?
    @Published public private(set) var errorMessage: String?

    private let context: MangaLaunchContext
    private let panel: MangaDirectoryPanelPresentation
    private let favoriteStore: any FavoriteStoring
    private let offlineCacheStore: any MangaOfflineCacheStoring

    public init(
        context: MangaLaunchContext,
        panel: MangaDirectoryPanelPresentation,
        favoriteStore: any FavoriteStoring,
        offlineCacheStore: any MangaOfflineCacheStoring
    ) {
        self.context = context
        self.panel = panel
        self.favoriteStore = favoriteStore
        self.offlineCacheStore = offlineCacheStore
    }

    public var allChapterTIDs: Set<String> {
        Set(rows.map(\.chapter.tid))
    }

    public func load() async {
        favorite = await favoriteStore.favorite(for: context.originalThreadURL)
        await refreshRows()
    }

    public func refreshRows() async {
        let ownerName = offlineCacheOwnerName
        var nextRows: [MangaReaderCacheRow] = []
        for chapter in panel.displayChapters {
            let state: MangaOfflineCacheState
            if let ownerName {
                state = await offlineCacheStore.offlineCacheState(ownerName: ownerName, tid: chapter.tid)
            } else {
                state = .uncached
            }
            nextRows.append(MangaReaderCacheRow(chapter: chapter, state: state))
        }
        rows = nextRows
    }

    public func selectionState(for selectedTIDs: Set<String>) -> MangaReaderCacheSelectionState {
        let validSelection = selectedTIDs.intersection(allChapterTIDs)
        let stateByTID = Dictionary(uniqueKeysWithValues: rows.map { ($0.chapter.tid, $0.state) })
        let uncached = validSelection.filter { stateByTID[$0] == .uncached }
        let removable = validSelection.filter { tid in
            switch stateByTID[tid] {
            case .cached, .caching:
                true
            case .uncached, nil:
                false
            }
        }
        return MangaReaderCacheSelectionState(
            selectedTIDs: validSelection,
            uncachedSelectedTIDs: Set(uncached),
            removableSelectedTIDs: Set(removable),
            canCache: !uncached.isEmpty,
            canDelete: !removable.isEmpty,
            isAllSelected: !rows.isEmpty && validSelection.count == rows.count
        )
    }

    public func cacheSelected(tids selectedTIDs: Set<String>) async {
        errorMessage = nil
        guard favorite != nil else {
            prompt = .addFavorite(title: presentationTitle)
            return
        }
        guard let ownerName = offlineCacheOwnerName else { return }

        let targetTIDs = selectionState(for: selectedTIDs).uncachedSelectedTIDs
        guard !targetTIDs.isEmpty else { return }

        do {
            for chapter in panel.displayChapters where targetTIDs.contains(chapter.tid) {
                _ = try await offlineCacheStore.enqueueOfflineCacheWork(
                    MangaOfflineCacheWorkRequest(
                        ownerName: ownerName,
                        tid: chapter.tid,
                        chapterTitle: chapter.rawTitle,
                        chapterURL: chapter.url
                    )
                )
            }
            await refreshRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSelected(tids selectedTIDs: Set<String>) async {
        errorMessage = nil
        guard let ownerName = offlineCacheOwnerName else { return }
        let targetTIDs = selectionState(for: selectedTIDs).removableSelectedTIDs
        guard !targetTIDs.isEmpty else { return }

        do {
            for chapter in panel.displayChapters where targetTIDs.contains(chapter.tid) {
                try await offlineCacheStore.removeMembership(ownerName: ownerName, tid: chapter.tid)
            }
            await refreshRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearPrompt() {
        prompt = nil
    }

    private var presentationTitle: String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? panel.directoryTitle : title
    }

    private var offlineCacheOwnerName: String? {
        let ownerName = panel.directoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return ownerName.isEmpty ? nil : ownerName
    }
}
