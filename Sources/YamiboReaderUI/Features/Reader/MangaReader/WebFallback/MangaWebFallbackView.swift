import SwiftUI
import YamiboReaderCore

#if os(iOS)
public struct MangaWebFallbackView: View {
    private let context: MangaWebContext
    private let appModel: YamiboAppModel

    public init(context: MangaWebContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        NavigationStack {
            ForumBrowserView(
                url: context.currentURL,
                appContext: appModel.appContext,
                appModel: appModel,
                listensToForumNavigationRequest: false
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
#endif
