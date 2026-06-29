import SwiftUI
import YamiboReaderCore

struct ForumSearchView: View {
    @State private var model: ForumSearchViewModel

    let onThreadTap: (ForumThreadSummary) -> Void
    let onAuthorTap: (String, String?) -> Void
    let onURLSubmit: (URL) -> Void

    init(
        model: ForumSearchViewModel,
        onThreadTap: @escaping (ForumThreadSummary) -> Void,
        onAuthorTap: @escaping (String, String?) -> Void,
        onURLSubmit: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onThreadTap = onThreadTap
        self.onAuthorTap = onAuthorTap
        self.onURLSubmit = onURLSubmit
    }

    var body: some View {
        ForumSearchBodyView(
            query: $model.query,
            results: model.results,
            resultCountText: model.resultCountText,
            pageNavigation: model.pageNavigation,
            currentPage: model.currentPage,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            submit: submit,
            goToPage: goToPage,
            onThreadTap: onThreadTap,
            onAuthorTap: onAuthorTap
        )
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
        .navigationTitle(L10n.string("forum.search.title"))
        .toolbar {
            if model.canRestorePreviousPage {
                ToolbarItem {
                    Button {
                        _ = model.restorePreviousPage()
                    } label: {
                        Label(L10n.string("common.back"), systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private func submit() {
        let trimmedQuery = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        if let url = URL(string: trimmedQuery), ["http", "https"].contains(url.scheme?.lowercased()) {
            onURLSubmit(url)
            return
        }

        Task {
            await model.searchFirstPage()
        }
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }
}

private struct ForumSearchBodyView: View {
    @Binding var query: String

    let results: [ForumThreadSummary]
    let resultCountText: String?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let isLoading: Bool
    let errorMessage: String?
    let submit: () -> Void
    let goToPage: (Int) -> Void
    let onThreadTap: (ForumThreadSummary) -> Void
    let onAuthorTap: (String, String?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForumSearchInputView(query: $query, isLoading: isLoading, submit: submit)

                if isLoading && results.isEmpty {
                    ForumSearchLoadingView()
                } else if let errorMessage, results.isEmpty {
                    ForumSearchErrorView(message: errorMessage, retry: submit)
                } else if results.isEmpty {
                    ForumSearchIdleView()
                } else {
                    if let resultCountText {
                        Text(resultCountText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ForumColors.secondaryText)
                    }

                    ForEach(results) { thread in
                        ForumThreadSummaryRowView(
                            thread: thread,
                            onThreadTap: {
                                onThreadTap(thread)
                            },
                            onAuthorTap: onAuthorTap
                        )
                    }

                    if let pageNavigation {
                        ForumSearchPageNavigationView(
                            navigation: pageNavigation,
                            currentPage: currentPage,
                            goToPage: goToPage
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }
}

private struct ForumSearchInputView: View {
    @Binding var query: String

    let isLoading: Bool
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(L10n.string("forum.search.placeholder"), text: $query)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.search)
                .onSubmit(submit)
                .textFieldStyle(.roundedBorder)

            Button(action: submit) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ForumColors.brownDeep)
            .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.string("common.search"))
        }
    }
}

private struct ForumSearchPageNavigationView: View {
    let navigation: ForumPageNavigation
    let currentPage: Int
    let goToPage: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                goToPage(currentPage - 1)
            } label: {
                Label(L10n.string("forum.board.previous_page"), systemImage: "chevron.left")
            }
            .disabled(currentPage <= 1)

            Spacer()

            Text(pageText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ForumColors.secondaryText)

            Spacer()

            Button {
                goToPage(currentPage + 1)
            } label: {
                Label(L10n.string("forum.board.next_page"), systemImage: "chevron.right")
            }
            .labelStyle(.titleAndIcon)
            .disabled(navigation.totalPages.map { currentPage >= $0 } ?? false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(ForumColors.brownDeep)
        .padding(.top, 4)
    }

    private var pageText: String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", currentPage)
    }
}

private struct ForumSearchIdleView: View {
    var body: some View {
        ContentUnavailableView(
            L10n.string("forum.search.idle_title"),
            systemImage: "magnifyingglass",
            description: Text(L10n.string("forum.search.idle_message"))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct ForumSearchLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("forum.search.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct ForumSearchErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("common.load_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("common.retry"), action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
