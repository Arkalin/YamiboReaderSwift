import SwiftUI
import YamiboReaderCore

struct FavoriteDetailView: View {
    let favoriteID: String
    @ObservedObject var viewModel: FavoritesViewModel
    let appContext: YamiboAppContext
    let appModel: YamiboAppModel
    let openFavorite: (Favorite, FavoriteLaunchMode) -> Void

    @State private var showingEditDisplayName = false
    @State private var editingDisplayName = ""
    @State private var showingClearCacheConfirmation = false
    @State private var showingSubfolderNotice = false
    @State private var showingCacheClearedNotice = false

    private var favorite: Favorite? {
        viewModel.favorite(id: favoriteID)
    }

    var body: some View {
        Group {
            if let favorite {
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard(for: favorite)
                        actionSection(for: favorite)
                        supportSection(for: favorite)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .background(detailBackground(for: favorite.type))
                .navigationTitle("收藏菜单")
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button("编辑显示名称") {
                                editingDisplayName = favorite.displayName ?? favorite.resolvedDisplayTitle
                                showingEditDisplayName = true
                            }

                            Button(favorite.isHidden ? "取消隐藏" : "隐藏") {
                                Task {
                                    await viewModel.setHidden(!favorite.isHidden, for: favorite)
                                }
                            }

                            Button("清除缓存", role: .destructive) {
                                showingClearCacheConfirmation = true
                            }
                            .disabled(favorite.type != .novel)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .alert("编辑显示名称", isPresented: $showingEditDisplayName) {
                    TextField("显示名称", text: $editingDisplayName)
                    Button("取消", role: .cancel) {}
                    Button("保存") {
                        Task {
                            await viewModel.setDisplayName(editingDisplayName, for: favorite)
                        }
                    }
                } message: {
                    Text("留空后将恢复显示原标题。")
                }
                .alert("确认清除缓存", isPresented: $showingClearCacheConfirmation) {
                    Button("取消", role: .cancel) {}
                    Button("清除", role: .destructive) {
                        Task {
                            if await viewModel.clearCache(for: favorite) {
                                showingCacheClearedNotice = true
                            }
                        }
                    }
                } message: {
                    Text("将清除这个小说收藏的本地阅读缓存。")
                }
                .alert("子收藏夹", isPresented: $showingSubfolderNotice) {
                    Button("知道了", role: .cancel) {}
                } message: {
                    Text("子收藏夹功能暂未开放。")
                }
                .alert("缓存已清除", isPresented: $showingCacheClearedNotice) {
                    Button("确定", role: .cancel) {}
                } message: {
                    Text("已清除该收藏项的本地小说缓存。")
                }
            } else {
                ContentUnavailableView("收藏不存在", systemImage: "exclamationmark.bubble")
                    .navigationTitle("收藏菜单")
            }
        }
    }

    @ViewBuilder
    private func headerCard(for favorite: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(favoriteAccentColor(for: favorite.type))
                    .frame(width: 14, height: 14)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(favorite.resolvedDisplayTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
                        Text(lastChapter)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            HStack(spacing: 10) {
                DetailBadge(
                    title: favorite.type.title,
                    systemImage: iconName(for: favorite.type),
                    tint: favoriteAccentColor(for: favorite.type)
                )

                if favorite.isHidden {
                    DetailBadge(
                        title: "已隐藏",
                        systemImage: "eye.slash.fill",
                        tint: .secondary
                    )
                }
            }

            if let progressText = favoriteProgressText(for: favorite) {
                Label(progressText, systemImage: "bookmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(favoriteAccentColor(for: favorite.type).opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func actionSection(for favorite: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("阅读操作")
                .font(.headline)

            HStack(spacing: 14) {
                actionButton(
                    title: "开始",
                    systemImage: "backward.end.fill",
                    tint: favoriteAccentColor(for: favorite.type).opacity(0.14),
                    foregroundStyle: favoriteAccentColor(for: favorite.type)
                ) {
                    openFavorite(favorite, .start)
                }

                actionButton(
                    title: "继续",
                    systemImage: "play.fill",
                    tint: favoriteAccentColor(for: favorite.type),
                    foregroundStyle: .white
                ) {
                    openFavorite(favorite, .resume)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
        }
    }

    @ViewBuilder
    private func supportSection(for favorite: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更多操作")
                .font(.headline)

            HStack(spacing: 14) {
                actionButton(
                    title: "子收藏夹",
                    systemImage: "folder.badge.plus",
                    tint: .secondary.opacity(0.12),
                    foregroundStyle: .secondary
                ) {
                    showingSubfolderNotice = true
                }

                ShareLink(item: favorite.url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                        Text("分享")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foregroundStyle: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint)
            )
            .foregroundStyle(foregroundStyle)
        }
        .buttonStyle(.plain)
    }

    private func detailBackground(for type: FavoriteType) -> some View {
        LinearGradient(
            colors: [
                favoriteAccentColor(for: type).opacity(0.16),
                Color.primary.opacity(0.04),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func iconName(for type: FavoriteType) -> String {
        switch type {
        case .unknown: "questionmark.circle.fill"
        case .novel: "text.book.closed.fill"
        case .manga: "photo.on.rectangle.angled"
        case .other: "globe.asia.australia.fill"
        }
    }
}

private struct DetailBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }
}
