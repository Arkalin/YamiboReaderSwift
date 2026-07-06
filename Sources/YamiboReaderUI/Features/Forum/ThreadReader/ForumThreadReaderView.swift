import SwiftUI
import YamiboReaderCore

struct ForumThreadReaderView: View {
    @State private var model: ForumThreadReaderViewModel

    let onUserTap: (String, String?) -> Void
    let onURLTap: (URL) -> Void

    init(
        model: ForumThreadReaderViewModel,
        onUserTap: @escaping (String, String?) -> Void,
        onURLTap: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onUserTap = onUserTap
        self.onURLTap = onURLTap
    }

    var body: some View {
        ForumThreadReaderBodyView(
            page: model.page,
            pageNavigation: model.pageNavigation,
            currentPage: model.currentPage,
            targetPostID: model.targetPostID,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isFavorited: model.isFavorited,
            refresh: refresh,
            retry: model.retry,
            goToPage: goToPage,
            toggleFavorite: toggleFavorite,
            makeImageBrowserRequest: model.imageBrowserRequest,
            imageBrowserCoverActionsProvider: model.imageBrowserCoverActionsProvider,
            loadRatingResults: model.loadRatingResults,
            loadRateOptions: model.loadRateOptions,
            loadPollVoters: model.loadPollVoters,
            votePoll: model.votePoll,
            ratePost: model.ratePost,
            commentPost: model.commentPost,
            onUserTap: onUserTap,
            onURLTap: onURLTap
        )
        .navigationTitle(model.navigationTitle)
        .yamiboInlineNavigationTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await model.refresh()
                    }
                } label: {
                    Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .alert(
            L10n.string("forum.thread.favorite_failed"),
            isPresented: favoriteErrorBinding,
            actions: {
                Button(L10n.string("common.ok")) {
                    model.clearFavoriteError()
                }
            },
            message: {
                Text(model.favoriteErrorMessage ?? "")
            }
        )
        .task {
            await model.load()
        }
        .forumTransientMessage(model.transientMessage, bottomPadding: model.page == nil ? 24 : 82) {
            model.clearTransientMessage()
        }
    }

    private func refresh() async {
        await model.refresh()
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }

    private func toggleFavorite() {
        Task {
            await model.toggleFavorite()
        }
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding(
            get: {
                model.favoriteErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    model.clearFavoriteError()
                }
            }
        )
    }
}
