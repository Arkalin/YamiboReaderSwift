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
                    Text("\(directory.chapters.count) 个章节")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        Task {
                            _ = try? await store.deleteDirectory(named: directory.cleanBookName)
                            await reload()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索漫画名称")
            .navigationTitle("漫画目录管理")
            .toolbar {
                ToolbarItem {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem {
                    Button("清空") {
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
