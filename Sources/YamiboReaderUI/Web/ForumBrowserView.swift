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
    @Published public private(set) var canOpenNative = false

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
        canOpenNative = canOpenNativeTarget(url: currentURL)
    }

    public func recordVisit(url: URL, title: String?) {
        currentURL = url
        pageTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!
            : pageTitle
        canOpenNative = canOpenNativeTarget(url: currentURL)

        let entry = ForumHistoryEntry(url: url, title: resolvedTitle(for: url, explicitTitle: title))
        history.removeAll(where: { $0.url == url })
        history.insert(entry, at: 0)
        if history.count > 30 {
            history.removeLast(history.count - 30)
        }
    }

    public func currentHTML() async -> String? {
        guard let webView else { return nil }
        return await webView.outerHTML()
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

    private func canOpenNativeTarget(url: URL?) -> Bool {
        guard let absolute = url?.absoluteString.lowercased() else { return false }
        return absolute.contains("mod=viewthread") || absolute.contains("thread-")
    }
}

public struct ForumBrowserView: View {
    @StateObject private var model: ForumBrowserModel
    @State private var showingHistory = false
    @State private var showsNavigationBar = true
    @State private var actionErrorMessage: String?
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel
    private let listensToForumNavigationRequest: Bool

    public init(
        url: URL,
        appContext: YamiboAppContext,
        appModel: YamiboAppModel,
        listensToForumNavigationRequest: Bool = true
    ) {
        _model = StateObject(wrappedValue: ForumBrowserModel(initialURL: url))
        self.appContext = appContext
        self.appModel = appModel
        self.listensToForumNavigationRequest = listensToForumNavigationRequest
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForumBrowserChrome(
                model: model,
                showingHistory: $showingHistory,
                openNative: openNative,
                showsLocationLabel: showsNavigationBar
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
        .task {
            await refreshNavigationBarVisibility()
        }
        .task {
            await observeSettingsChanges()
        }
        .onChange(of: appModel.forumNavigationRequest?.id) { _, _ in
            guard listensToForumNavigationRequest else { return }
            if let request = appModel.forumNavigationRequest {
                model.load(request.url)
            }
        }
        .alert("无法原生打开", isPresented: .constant(actionErrorMessage != nil), actions: {
            Button("确定") {
                actionErrorMessage = nil
            }
        }, message: {
            Text(actionErrorMessage ?? "")
        })
    }

    private func refreshNavigationBarVisibility() async {
        let settings = await appContext.settingsStore.load()
        showsNavigationBar = settings.webBrowser.showsNavigationBar
    }

    private func observeSettingsChanges() async {
        for await notification in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[SettingsStore.changeIDUserInfoKey] as? String,
                  changeID == appContext.settingsStore.changeID else {
                continue
            }
            await refreshNavigationBarVisibility()
        }
    }

    private func openNative() {
        Task {
            guard let threadURL = ReaderModeDetector.canonicalThreadURL(from: model.currentURL) else { return }
            do {
                let html = await model.currentHTML()
                let resolver = await appContext.makeThreadOpenResolver()
                let target = try await resolver.resolve(
                    threadURL: threadURL,
                    title: model.pageTitle,
                    htmlOverride: html,
                    favoriteType: .unknown
                )
                switch target {
                case let .novel(context):
                    appModel.presentReader(context)
                case let .manga(context):
                    await appModel.openManga(
                        context,
                        currentHTML: html,
                        currentTitle: model.pageTitle
                    )
                case .web:
                    actionErrorMessage = "当前帖子不适合原生阅读。"
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
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

struct ForumBrowserChrome: View {
    @ObservedObject var model: ForumBrowserModel
    @Binding var showingHistory: Bool
    let openNative: () -> Void
    let showsLocationLabel: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForumBrowserToolbarButtons(model: model, showingHistory: $showingHistory, openNative: openNative)
            if showsLocationLabel {
                ForumBrowserLocationLabel(model: model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

struct ForumBrowserToolbarButtons: View {
    @ObservedObject var model: ForumBrowserModel
    @Binding var showingHistory: Bool
    let openNative: () -> Void

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

            if model.canOpenNative {
                nativeButton
            }
        }
    }

    private var backButton: some View {
        Button {
            model.goBack()
        } label: {
            Image(systemName: "chevron.backward")
        }
        .accessibilityIdentifier("forum-browser-back-button")
        .disabled(!model.canGoBack)
    }

    private var forwardButton: some View {
        Button {
            model.goForward()
        } label: {
            Image(systemName: "chevron.forward")
        }
        .accessibilityIdentifier("forum-browser-forward-button")
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
        .accessibilityIdentifier("forum-browser-reload-button")
    }

    private var historyButton: some View {
        Button {
            showingHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityIdentifier("forum-browser-history-button")
        .disabled(model.history.isEmpty)
    }

    private var nativeButton: some View {
        Button(action: openNative) {
            Image(systemName: "sparkles.rectangle.stack")
        }
        .accessibilityIdentifier("forum-browser-open-native-button")
    }

    private func externalButton(for url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityIdentifier("forum-browser-share-button")
    }
}

struct ForumBrowserLocationLabel: View {
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
        .accessibilityIdentifier("forum-browser-location-label")
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

    public init(
        url: URL,
        appContext: YamiboAppContext,
        appModel: YamiboAppModel,
        listensToForumNavigationRequest: Bool = true
    ) {
        self.url = url
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        ForumWebView(url: url)
    }
}

#endif

#if os(iOS)
private extension WKWebView {
    func outerHTML() async -> String? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }
}
#endif
