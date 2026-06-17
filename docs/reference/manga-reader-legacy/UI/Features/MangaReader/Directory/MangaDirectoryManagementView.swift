import SwiftUI
import YamiboReaderCore

@MainActor
public struct MangaDirectoryManagementView: View {
    private let store: MangaDirectoryStore
    @State private var directories: [MangaDirectory] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    public init(store: MangaDirectoryStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List(filteredDirectories) { directory in
                VStack(alignment: .leading, spacing: 4) {
                    Text(directory.cleanBookName)
                        .font(.headline)
                    Text(L10n.string("manga_directory.chapter_count", directory.chapters.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(L10n.string("common.delete"), role: .destructive) {
                        Task {
                            _ = try? await store.deleteDirectory(named: directory.cleanBookName)
                            await reload()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("manga_directory.search_prompt"))
            .navigationTitle(L10n.string("settings.manga_directory_management"))
            .toolbar {
                ToolbarItem {
                    Button(L10n.string("common.close")) { dismiss() }
                }
                ToolbarItem {
                    Button(L10n.string("common.clear_all")) {
                        Task {
                            try? await store.clearAll()
                            await reload()
                        }
                    }
                    .disabled(directories.isEmpty)
                }
            }
            .task {
                await reload()
            }
        }
    }

    private var filteredDirectories: [MangaDirectory] {
        guard !searchText.isEmpty else { return directories }
        return directories.filter {
            $0.cleanBookName.localizedCaseInsensitiveContains(searchText)
                || ($0.searchKeyword?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func reload() async {
        directories = await store.allDirectories()
    }
}
