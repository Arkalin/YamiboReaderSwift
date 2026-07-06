import SwiftUI
import YamiboReaderCore

struct ForumThreadPollVotersRequest: Identifiable, Equatable {
    var threadID: String
    var optionID: String?

    var id: String {
        "\(threadID)\u{1F}\(optionID ?? "")"
    }
}

struct ForumThreadPollVotersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionID: String?
    @State private var pageNumber = 1
    @State private var votersPage: ForumThreadPollVotersPage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let request: ForumThreadPollVotersRequest
    let load: (String, String?, Int) async throws -> ForumThreadPollVotersPage
    let onUserTap: (String, String?) -> Void

    init(
        request: ForumThreadPollVotersRequest,
        load: @escaping (String, String?, Int) async throws -> ForumThreadPollVotersPage,
        onUserTap: @escaping (String, String?) -> Void
    ) {
        self.request = request
        self.load = load
        self.onUserTap = onUserTap
        _selectedOptionID = State(initialValue: request.optionID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && votersPage == nil {
                    ForumThreadReaderLoadingView()
                } else if let errorMessage, votersPage == nil {
                    ForumThreadReaderErrorView(message: errorMessage) {
                        Task {
                            await loadPage()
                        }
                    }
                } else if let votersPage {
                    VStack(alignment: .leading, spacing: 14) {
                        optionMenu(votersPage)

                        if votersPage.voters.isEmpty {
                            Text(L10n.string("forum.thread.poll_voters_empty"))
                                .font(.body)
                                .foregroundStyle(ForumColors.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(votersPage.voters, id: \.self) { voter in
                                        ForumThreadPollVoterButton(user: voter, onUserTap: openUser)
                                    }
                                }
                            }
                        }

                        ForumThreadReaderPageNavigationView(
                            navigation: votersPage.pageNavigation,
                            currentPage: votersPage.pageNavigation?.currentPage ?? pageNumber,
                            goToPage: { page in
                                pageNumber = page
                            }
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.string("forum.thread.poll_voters"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if isLoading && votersPage != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        .task(id: loadIdentity) {
            await loadPage()
        }
    }

    @ViewBuilder
    private func optionMenu(_ page: ForumThreadPollVotersPage) -> some View {
        if !page.pollOptions.isEmpty {
            Menu {
                ForEach(page.pollOptions) { option in
                    Button(option.name) {
                        selectedOptionID = option.id
                        pageNumber = 1
                    }
                }
            } label: {
                HStack {
                    Text(selectedOptionName(in: page))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForumColors.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var loadIdentity: String {
        "\(selectedOptionID ?? "")\u{1F}\(pageNumber)"
    }

    private func selectedOptionName(in page: ForumThreadPollVotersPage) -> String {
        let id = selectedOptionID ?? page.selectedOptionID
        return page.pollOptions.first(where: { $0.id == id })?.name
            ?? page.pollOptions.first?.name
            ?? L10n.string("forum.thread.poll_voters")
    }

    private func loadPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            votersPage = try await load(request.threadID, selectedOptionID, pageNumber)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openUser(uid: String, name: String?) {
        dismiss()
        onUserTap(uid, name)
    }
}

private struct ForumThreadPollVoterButton: View {
    let user: BlogReaderUser
    let onUserTap: (String, String?) -> Void

    var body: some View {
        if let uid = user.uid {
            Button {
                onUserTap(uid, user.name)
            } label: {
                Text(user.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ForumColors.brownPrimary)
            .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text(user.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ForumColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
