import SwiftUI
import YamiboReaderCore

enum ReaderLoadStateStatus: Equatable, Sendable {
    case loading
    case failed(title: String = L10n.string("common.load_failed"), message: String)
}

struct ReaderLoadStateView: View {
    let status: ReaderLoadStateStatus
    let retryAction: (() -> Void)?
    let tint: Color

    init(
        status: ReaderLoadStateStatus,
        retryAction: (() -> Void)? = nil,
        tint: Color = .primary
    ) {
        self.status = status
        self.retryAction = retryAction
        self.tint = tint
    }

    var body: some View {
        switch status {
        case .loading:
            ReaderLoadStateLoadingContent(tint: tint)
        case let .failed(title, message):
            ReaderLoadStateFailureContent(
                title: title,
                message: message,
                retryAction: retryAction,
                tint: tint
            )
        }
    }
}

private struct ReaderLoadStateLoadingContent: View {
    let tint: Color

    var body: some View {
        ProgressView(L10n.string("common.loading"))
            .tint(tint)
            .foregroundStyle(tint)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReaderLoadStateFailureContent: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)

            if !message.isEmpty {
                Text(message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let retryAction {
                Button(L10n.string("common.retry"), action: retryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .foregroundStyle(tint)
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
