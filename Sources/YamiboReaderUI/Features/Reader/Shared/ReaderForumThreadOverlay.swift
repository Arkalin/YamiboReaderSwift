import SwiftUI
import YamiboReaderCore

#if os(iOS)

/// A reader's 打开原帖 request, presented full screen above the reader
/// instead of dismissing it and rerouting the forum tab.
struct ReaderForumThreadOverlayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String?
}

/// The full-screen cover content for `ReaderForumThreadOverlayItem`: a full
/// forum stack (`.readerOverlay` mode) rooted at the original post, so
/// in-post links, user profiles and boards all stay inside the overlay while
/// the reader keeps running underneath. A cover has no swipe-to-dismiss, so
/// the root keeps an explicit close button.
struct ReaderForumThreadOverlayScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var navigator: ForumDestinationNavigator

    private let item: ReaderForumThreadOverlayItem

    init(
        item: ReaderForumThreadOverlayItem,
        dependencies: ForumDependencies,
        appModel: YamiboAppModel,
        discussionWorkTIDs: Set<String>
    ) {
        self.item = item
        _navigator = State(wrappedValue: ForumDestinationNavigator(
            dependencies: dependencies,
            appModel: appModel,
            mode: .readerOverlay,
            discussionWorkTIDs: discussionWorkTIDs
        ))
    }

    var body: some View {
        ForumDestinationStackView(navigator: navigator) {
            ForumThreadLinkScreen(
                url: item.url,
                title: item.title,
                containingFid: nil,
                authorID: nil,
                // The overlay root is the work's own thread opened as a
                // discussion companion — it must not write its own
                // browsing-history row (browsing-history decision #14), same
                // as the old `.readerDiscussion` dismissal route.
                isDiscussionView: true,
                navigator: navigator
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ReaderToolbarIconButton(
                        systemName: "xmark",
                        title: L10n.string("common.done"),
                        action: { dismiss() }
                    )
                }
            }
            .forumNavigationBarStyle()
        }
    }
}

#endif
