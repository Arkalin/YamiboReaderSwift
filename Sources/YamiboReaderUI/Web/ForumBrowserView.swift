import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit
import WebKit

public struct ForumHistoryEntry: Identifiable, Hashable {
    public let url: URL
    public let title: String

    public var id: String { url.absoluteString }

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

@MainActor
public final class ForumBrowserModel: ObservableObject {
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var pageTitle = ""
    @Published public private(set) var isLoading = false
    @Published public private(set) var canGoBack = false
    @Published public private(set) var canGoForward = false
    @Published public private(set) var history: [ForumHistoryEntry] = []
    @Published public private(set) var canOpenReader = false

    private weak var webView: WKWebView?

    private let initialURL: URL

    public init(initialURL: URL) {
        self.initialURL = initialURL
        self.currentURL = initialURL
    }

    public func attach(webView: WKWebView) {
        self.webView = webView
        if webView.url != nil {
            sync(with: webView)
        }
    }

    public func load(_ url: URL) {
        currentURL = url
        webView?.load(URLRequest(url: url))
    }

    public func reload() {
        webView?.reload()
    }

    public func goBack() {
        webView?.goBack()
    }

    public func goForward() {
        webView?.goForward()
    }

    public func stop() {
        webView?.stopLoading()
    }

    public func sync(with webView: WKWebView) {
        currentURL = webView.url ?? currentURL
        pageTitle = webView.title ?? pageTitle
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        canOpenReader = ReaderModeDetector.canOpenReader(url: currentURL, title: pageTitle)
    }

    public func recordVisit(url: URL, title: String?) {
        currentURL = url
        pageTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!
            : pageTitle
        canOpenReader = ReaderModeDetector.canOpenReader(url: currentURL, title: pageTitle)

        let entry = ForumHistoryEntry(url: url, title: resolvedTitle(for: url, explicitTitle: title))
        history.removeAll(where: { $0.url == url })
        history.insert(entry, at: 0)
        if history.count > 30 {
            history.removeLast(history.count - 30)
        }
    }

    private func resolvedTitle(for url: URL, explicitTitle: String?) -> String {
        if let explicitTitle, !explicitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitTitle
        }
        if let host = url.host, let lastPath = url.pathComponents.last, lastPath != "/" {
            return "\(host)\(url.path)"
        }
        return url.absoluteString
    }
}

public struct ForumBrowserView: View {
    @StateObject private var model: ForumBrowserModel
    @State private var showingHistory = false
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(url: URL, appContext: YamiboAppContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: ForumBrowserModel(initialURL: url))
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForumBrowserToolbar(
                model: model,
                showingHistory: $showingHistory,
                openReader: openReader
            )
            ZStack(alignment: .top) {
                IOSForumWebView(model: model, appContext: appContext)
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            ForumHistorySheet(model: model, showingHistory: $showingHistory)
        }
        .onChange(of: appModel.forumNavigationRequest?.id) { _, _ in
            if let request = appModel.forumNavigationRequest {
                model.load(request.url)
            }
        }
    }

    private func openReader() {
        guard let threadURL = ReaderModeDetector.canonicalThreadURL(from: model.currentURL) else { return }
        appModel.presentReader(
            ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: model.pageTitle.isEmpty ? "小说阅读" : model.pageTitle,
                source: .forum
            )
        )
    }
}

private struct ForumHistorySheet: View {
    @ObservedObject var model: ForumBrowserModel
    @Binding var showingHistory: Bool

    var body: some View {
        NavigationStack {
            List(model.history) { entry in
                Button {
                    model.load(entry.url)
                    showingHistory = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .foregroundStyle(.primary)
                        Text(entry.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("浏览历史")
            .toolbar {
                ToolbarItem {
                    Button("关闭") {
                        showingHistory = false
                    }
                }
            }
        }
    }
}

private struct ForumBrowserToolbar: View {
    @ObservedObject var model: ForumBrowserModel
    @Binding var showingHistory: Bool
    let openReader: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForumBrowserToolbarButtons(model: model, showingHistory: $showingHistory, openReader: openReader)
            ForumBrowserLocationLabel(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

private struct ForumBrowserToolbarButtons: View {
    @ObservedObject var model: ForumBrowserModel
    @Binding var showingHistory: Bool
    let openReader: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            backButton
            forwardButton
            reloadButton

            Spacer(minLength: 0)

            historyButton

            if let currentURL = model.currentURL {
                externalButton(for: currentURL)
            }

            if model.canOpenReader {
                readerButton
            }
        }
    }

    private var backButton: some View {
        Button {
            model.goBack()
        } label: {
            Image(systemName: "chevron.backward")
        }
        .disabled(!model.canGoBack)
    }

    private var forwardButton: some View {
        Button {
            model.goForward()
        } label: {
            Image(systemName: "chevron.forward")
        }
        .disabled(!model.canGoForward)
    }

    private var reloadButton: some View {
        Button {
            if model.isLoading {
                model.stop()
            } else {
                model.reload()
            }
        } label: {
            Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
        }
    }

    private var historyButton: some View {
        Button {
            showingHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .disabled(model.history.isEmpty)
    }

    private var readerButton: some View {
        Button(action: openReader) {
            Image(systemName: "book.pages")
        }
    }

    private func externalButton(for url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
}

private struct ForumBrowserLocationLabel: View {
    @ObservedObject var model: ForumBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.pageTitle.isEmpty ? "百合会论坛" : model.pageTitle)
                .font(.headline)
                .lineLimit(1)
            Text(model.currentURL?.absoluteString ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#else

public struct ForumHistoryEntry: Identifiable, Hashable {
    public let url: URL
    public let title: String
    public var id: String { url.absoluteString }
}

public struct ForumBrowserView: View {
    private let url: URL
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(url: URL, appContext: YamiboAppContext, appModel: YamiboAppModel) {
        self.url = url
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        ForumWebView(url: url)
    }
}

#endif
