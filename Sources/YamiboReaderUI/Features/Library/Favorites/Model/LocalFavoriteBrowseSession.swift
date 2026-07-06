import Foundation

/// Interactive browse session for the favorites screen: multi-selection and
/// search-mode state. Pure state machine with no persistence dependencies.
@MainActor
final class LocalFavoriteBrowseSession: ObservableObject {
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedFavoriteIDs: Set<String> = []
    @Published private(set) var selectedCollectionIDs: Set<String> = []
    @Published private(set) var isSearchMode = false
    @Published var searchDraftText = ""

    var selectedFavoriteCount: Int {
        selectedFavoriteIDs.count
    }

    var selectedCollectionCount: Int {
        selectedCollectionIDs.count
    }

    var selectedEntryCount: Int {
        selectedFavoriteIDs.count + selectedCollectionIDs.count
    }

    var canCreateCollectionFromSelection: Bool {
        !selectedFavoriteIDs.isEmpty
    }

    // MARK: - Selection

    func enterSelectionMode() {
        isSearchMode = false
        isSelectionMode = true
    }

    func exitSelectionMode() {
        isSelectionMode = false
        clearSelection()
    }

    func clearSelection() {
        selectedFavoriteIDs.removeAll()
        selectedCollectionIDs.removeAll()
    }

    func toggleFavoriteSelection(id: String) {
        isSearchMode = false
        isSelectionMode = true
        if selectedFavoriteIDs.contains(id) {
            selectedFavoriteIDs.remove(id)
        } else {
            selectedFavoriteIDs.insert(id)
        }
    }

    func toggleCollectionSelection(id: String) {
        isSearchMode = false
        isSelectionMode = true
        if selectedCollectionIDs.contains(id) {
            selectedCollectionIDs.remove(id)
        } else {
            selectedCollectionIDs.insert(id)
        }
    }

    func selectAll(favoriteIDs: [String], collectionIDs: [String]) {
        isSearchMode = false
        isSelectionMode = true
        selectedFavoriteIDs.formUnion(favoriteIDs)
        selectedCollectionIDs.formUnion(collectionIDs)
    }

    func invertSelection(favoriteIDs: [String], collectionIDs: [String]) {
        isSearchMode = false
        isSelectionMode = true
        for id in favoriteIDs {
            if selectedFavoriteIDs.contains(id) {
                selectedFavoriteIDs.remove(id)
            } else {
                selectedFavoriteIDs.insert(id)
            }
        }
        for id in collectionIDs {
            if selectedCollectionIDs.contains(id) {
                selectedCollectionIDs.remove(id)
            } else {
                selectedCollectionIDs.insert(id)
            }
        }
    }

    /// Drops selections that no longer exist in the library document and exits
    /// selection mode when nothing remains selected.
    func prune(validFavoriteIDs: Set<String>, validCollectionIDs: Set<String>) {
        selectedFavoriteIDs.formIntersection(validFavoriteIDs)
        selectedCollectionIDs.formIntersection(validCollectionIDs)
        if selectedEntryCount == 0, isSelectionMode {
            isSelectionMode = false
        }
    }

    // MARK: - Search

    func enterSearchMode(draftText: String) {
        exitSelectionMode()
        searchDraftText = draftText
        isSearchMode = true
    }

    /// Trims and returns the draft as the submitted search text.
    func submitSearchDraft() -> String {
        isSearchMode = true
        return searchDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func exitSearchMode() {
        isSearchMode = false
        searchDraftText = ""
        exitSelectionMode()
    }
}
