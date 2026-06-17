import SwiftUI
import YamiboReaderCore

public struct MangaWebFallbackView: View {
    private let context: MangaWebContext
    private let appModel: YamiboAppModel

    public init(context: MangaWebContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        NavigationStack {
            MangaWebFallbackSkeletonContent(
                currentURL: context.currentURL,
                originalThreadURL: context.originalThreadURL
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        appModel.dismissManga()
                    } label: {
                        Label(L10n.string("common.close"), systemImage: "xmark")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appModel.dismissManga(openThreadInForum: context.currentURL)
                    } label: {
                        Label(L10n.string("common.original_post"), systemImage: "safari")
                    }
                }
            }
            .navigationTitle(L10n.string("manga_web.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

private struct MangaWebFallbackSkeletonContent: View {
    let currentURL: URL
    let originalThreadURL: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MangaWebFallbackHeader()
                MangaWebFallbackStatus()
                MangaReaderRouteRow(title: L10n.string("manga.skeleton.current_url"), url: currentURL)
                MangaReaderRouteRow(title: L10n.string("manga.skeleton.original_thread"), url: originalThreadURL)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
    }
}

private struct MangaWebFallbackHeader: View {
    var body: some View {
        Label(L10n.string("manga_web.title"), systemImage: "safari")
            .font(.title2)
            .fontWeight(.semibold)
    }
}

private struct MangaWebFallbackStatus: View {
    var body: some View {
        Text(L10n.string("manga_web.skeleton.message"))
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
