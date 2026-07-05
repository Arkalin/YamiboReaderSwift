import SwiftUI
import YamiboReaderCore

struct PrivateMessageView: View {
    @State private var model: PrivateMessageViewModel

    init(model: PrivateMessageViewModel) {
        _model = State(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            PrivateMessageContentView(
                page: model.page,
                currentProfile: model.currentProfile,
                currentPage: model.currentPage,
                isLoading: model.isLoading,
                errorMessage: model.errorMessage,
                retry: retry,
                goToPage: goToPage
            )

            Divider()

            PrivateMessageInputBar(
                text: $model.inputText,
                canSend: model.canSend,
                isSending: model.isSending,
                send: send
            )
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
        .navigationTitle(model.navigationTitle)
        .yamiboInlineNavigationTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await model.refresh()
                    }
                } label: {
                    Label(L10n.string("private_message.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .task {
            await model.load()
        }
        .alert(
            L10n.string("private_message.title"),
            isPresented: Binding(
                get: { model.sendResultMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearSendResult()
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.clearSendResult()
            }
        } message: {
            Text(model.sendResultMessage ?? "")
        }
    }

    private func retry() {
        Task {
            await model.refresh()
        }
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }

    private func send() {
        Task {
            await model.send()
        }
    }
}

private struct PrivateMessageContentView: View {
    let page: PrivateMessagePage?
    let currentProfile: YamiboProfile?
    let currentPage: Int
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void
    let goToPage: (Int) -> Void

    var body: some View {
        Group {
            if let page {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if page.messages.isEmpty {
                            PrivateMessageEmptyView()
                        } else {
                            ForEach(page.messages) { message in
                                PrivateMessageBubbleView(message: message, currentProfile: currentProfile)
                            }
                        }
                        PrivateMessagePageNavigationView(
                            navigation: page.pageNavigation,
                            currentPage: currentPage,
                            goToPage: goToPage
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 8)
                    }
                }
            } else if isLoading {
                PrivateMessageLoadingView()
            } else if let errorMessage {
                PrivateMessageErrorView(message: errorMessage, retry: retry)
            } else {
                PrivateMessageEmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forumPageBackground()
    }
}

private struct PrivateMessageBubbleView: View {
    let message: PrivateMessage
    let currentProfile: YamiboProfile?

    private var isMine: Bool {
        message.kind == .me
    }

    private var displayName: String {
        if isMine {
            return currentProfile?.username ?? message.author.name
        }
        return message.author.name
    }

    private var avatarURL: URL? {
        if isMine {
            return currentProfile?.avatarURL ?? message.author.avatarURL
        }
        return message.author.avatarURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isMine {
                PrivateMessageAvatarView(url: avatarURL)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.secondaryText)
                    .lineLimit(1)

                Text(message.contentText)
                    .font(.subheadline)
                    .foregroundStyle(ForumColors.textDark)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isMine ? ForumColors.accentFill : ForumColors.creamSurface, in: bubbleShape)
                    .overlay {
                        bubbleShape.stroke(ForumColors.border, lineWidth: 1)
                    }

                if let postedAtText = message.postedAtText {
                    Text(postedAtText)
                        .font(.caption2)
                        .foregroundStyle(ForumColors.brownLight)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)

            if isMine {
                PrivateMessageAvatarView(url: avatarURL)
            }
        }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

private struct PrivateMessageAvatarView: View {
    let url: URL?

    var body: some View {
        YamiboRemoteImage(request: url.map { YamiboImageRequest(url: $0) }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(ForumColors.secondaryText)
        } failure: {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }
}

private struct PrivateMessageInputBar: View {
    @Binding var text: String
    let canSend: Bool
    let isSending: Bool
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L10n.string("private_message.input_placeholder"), text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)

            Button(action: send) {
                if isSending {
                    ProgressView()
                } else {
                    Label(L10n.string("private_message.send"), systemImage: "paperplane.fill")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ForumColors.navBarBackground)
    }
}

private struct PrivateMessagePageNavigationView: View {
    let navigation: ForumPageNavigation?
    let currentPage: Int
    let goToPage: (Int) -> Void

    var body: some View {
        if let navigation {
            HStack(spacing: 12) {
                Button {
                    goToPage(currentPage - 1)
                } label: {
                    Label(L10n.string("forum.board.previous_page"), systemImage: "chevron.left")
                }
                .disabled(currentPage <= 1)

                Spacer()

                Text(pageText(navigation))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ForumColors.secondaryText)

                Spacer()

                Button {
                    goToPage(currentPage + 1)
                } label: {
                    Label(L10n.string("forum.board.next_page"), systemImage: "chevron.right")
                }
                .disabled(navigation.totalPages.map { currentPage >= $0 } ?? false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(ForumColors.brownEmphasis)
            .padding(.top, 6)
        }
    }

    private func pageText(_ navigation: ForumPageNavigation) -> String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", currentPage)
    }
}

private struct PrivateMessageLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PrivateMessageErrorView: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct PrivateMessageEmptyView: View {
    var body: some View {
        ContentUnavailableView(L10n.string("private_message.empty"), systemImage: "bubble.left")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
    }
}
