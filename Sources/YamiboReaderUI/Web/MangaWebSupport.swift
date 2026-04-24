import SwiftUI
import WebKit
import YamiboReaderCore

#if os(iOS)
import UIKit

enum MangaWebMessageName {
    static let nativeOpen = "yamiboNativeManga"
}

struct MangaWebExtractionPayload: Sendable {
    var urls: [URL]
    var title: String
    var sectionName: String?
    var isAnnouncement: Bool
    var html: String?

    init?(_ rawValue: Any?, htmlFallback: String? = nil) {
        guard let dictionary = rawValue as? [String: Any] else { return nil }
        let urls = (dictionary["urls"] as? [String] ?? [])
            .compactMap(URL.init(string:))
        let title = dictionary["title"] as? String ?? ""
        let sectionName = dictionary["sectionName"] as? String
        let isAnnouncement = dictionary["isAnnouncement"] as? Bool ?? false
        let html = dictionary["html"] as? String ?? htmlFallback

        self.urls = urls
        self.title = title
        self.sectionName = sectionName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isAnnouncement = isAnnouncement
        self.html = html?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var isAllowedMangaPage: Bool {
        !isAnnouncement && MangaHTMLParser.isAllowedMangaSection(sectionName)
    }
}

enum MangaWebJavaScript {
    static let hideChromeScript = """
    (function() {
        var style = document.getElementById('yamibo-manga-hide-style');
        if (!style) {
            style = document.createElement('style');
            style.id = 'yamibo-manga-hide-style';
            (document.head || document.documentElement).appendChild(style);
        }
        style.innerHTML = [
            '.my,.mz{visibility:hidden !important;pointer-events:none !important;}',
            '.foot.flex-box:not(.foot_reply){display:none !important;}',
            '.foot_height{display:none !important;}',
            '.footer,.bm_c,.pgbtn{display:none !important;}'
        ].join('');
    })();
    """

    static func extractionScript(includeHTML: Bool) -> String {
        """
        (function() {
            function toAbsolute(rawValue) {
                try { return new URL(rawValue, document.baseURI).href; }
                catch (error) { return null; }
            }

            var sectionHeader = document.querySelector('.header h2 a');
            var sectionName = sectionHeader ? sectionHeader.innerText.trim() : '';
            var typeLabel = document.querySelector('.view_tit em');
            var isAnnouncement = !!(typeLabel && typeLabel.innerText.indexOf('公告') !== -1);
            var images = document.querySelectorAll('.img_one img, .message img:not([src*="smiley"])');
            var urls = [];

            for (var index = 0; index < images.length; index++) {
                var image = images[index];
                var rawValue = image.getAttribute('zsrc') || image.getAttribute('file') || image.getAttribute('src');
                if (!rawValue || rawValue.indexOf('smiley') !== -1) continue;
                var absolute = toAbsolute(rawValue);
                if (!absolute) continue;
                if (urls.indexOf(absolute) === -1) {
                    urls.push(absolute);
                }
            }

            return {
                title: document.title || '',
                sectionName: sectionName,
                isAnnouncement: isAnnouncement,
                urls: urls,
                html: \(includeHTML ? "document.documentElement.outerHTML" : "null")
            };
        })();
        """
    }

    static let clickInterceptorScript = """
    (function() {
        if (window.__yamiboNativeMangaAttached) return;
        window.__yamiboNativeMangaAttached = true;

        function isAllowedSection() {
            var sectionHeader = document.querySelector('.header h2 a');
            var sectionName = sectionHeader ? sectionHeader.innerText.trim() : '';
            var allowed = ['中文百合漫画区', '貼圖區', '贴图区', '原创图作区', '百合漫画图源区'];
            for (var index = 0; index < allowed.length; index++) {
                if (sectionName.indexOf(allowed[index]) !== -1) return true;
            }
            return false;
        }

        function collectPayload(targetImage) {
            var images = document.querySelectorAll('.img_one img, .message img:not([src*="smiley"])');
            var urls = [];
            var clickedIndex = 0;

            for (var index = 0; index < images.length; index++) {
                var image = images[index];
                var rawValue = image.getAttribute('zsrc') || image.getAttribute('file') || image.getAttribute('src');
                if (!rawValue || rawValue.indexOf('smiley') !== -1) continue;
                try {
                    var absolute = new URL(rawValue, document.baseURI).href;
                    if (urls.indexOf(absolute) === -1) {
                        urls.push(absolute);
                    }
                    if (image === targetImage) {
                        clickedIndex = urls.length - 1;
                    }
                } catch (error) {}
            }

            return {
                type: 'openNative',
                title: document.title || '',
                clickedIndex: clickedIndex,
                urls: urls
            };
        }

        document.addEventListener('click', function(event) {
            if (!isAllowedSection()) return;

            var candidate = event.target.closest('.img_one li, .img_one a, .message a, .img_one img, .message img');
            if (!candidate) return;

            var targetImage = candidate.tagName.toLowerCase() === 'img' ? candidate : candidate.querySelector('img');
            if (!targetImage) return;

            var rawValue = targetImage.getAttribute('zsrc') || targetImage.getAttribute('file') || targetImage.getAttribute('src') || '';
            if (!rawValue || rawValue.indexOf('smiley') !== -1) return;

            event.preventDefault();
            event.stopPropagation();

            var payload = collectPayload(targetImage);
            if (payload.urls.length > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(MangaWebMessageName.nativeOpen)) {
                window.webkit.messageHandlers.\(MangaWebMessageName.nativeOpen).postMessage(payload);
            }
        }, true);
    })();
    """
}

final class MangaWebJSBridge: NSObject, WKScriptMessageHandler {
    var onOpenNative: ((String, Int, [URL]) -> Void)?

    func attach(to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: MangaWebMessageName.nativeOpen)
        controller.add(self, name: MangaWebMessageName.nativeOpen)
    }

    func detach(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: MangaWebMessageName.nativeOpen)
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == MangaWebMessageName.nativeOpen else { return }
        guard let dictionary = message.body as? [String: Any] else { return }
        let title = dictionary["title"] as? String ?? L10n.string("manga.reader.title")
        let clickedIndex = dictionary["clickedIndex"] as? Int ?? 0
        let urls = (dictionary["urls"] as? [String] ?? []).compactMap(URL.init(string:))
        guard !urls.isEmpty else { return }
        let handler = onOpenNative
        Task { @MainActor in
            handler?(title, max(0, clickedIndex), urls)
        }
    }
}

@MainActor
final class MangaWebViewPool {
    static let shared = MangaWebViewPool()

    private var visibleWebView: WKWebView?
    private var probeWebView: WKWebView?
    private var visibleInUse = false
    private var probeInUse = false

    private init() {}

    func acquireVisibleWebView() -> WKWebView {
        visibleInUse = true
        if let visibleWebView {
            return visibleWebView
        }

        let webView = Self.makeWebView(dataStore: .default())
        visibleWebView = webView
        return webView
    }

    func releaseVisibleWebView(_ webView: WKWebView) {
        guard visibleWebView === webView else { return }
        visibleInUse = false
        sanitize(webView, preservePageState: true)
    }

    func acquireProbeWebView() -> (webView: WKWebView, isPooled: Bool) {
        guard !probeInUse else {
            return (Self.makeWebView(dataStore: .default()), false)
        }

        probeInUse = true
        if let probeWebView {
            return (probeWebView, true)
        }

        let webView = Self.makeWebView(dataStore: .default())
        probeWebView = webView
        return (webView, true)
    }

    func releaseProbeWebView(_ webView: WKWebView, isPooled: Bool) {
        if isPooled {
            probeInUse = false
        }
        sanitize(webView, preservePageState: isPooled)
    }

    private static func makeWebView(dataStore: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    private func sanitize(_ webView: WKWebView, preservePageState: Bool) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: MangaWebMessageName.nativeOpen)
        if !preservePageState {
            webView.loadHTMLString("", baseURL: nil)
        }
    }
}

extension WKWebView {
    func yamiboApplySession(_ sessionState: SessionState) async {
        let cookies = sessionState.cookie
            .split(separator: ";")
            .compactMap { cookiePart -> HTTPCookie? in
                let pair = cookiePart.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return HTTPCookie(properties: [
                    .domain: "bbs.yamibo.com",
                    .path: "/",
                    .name: pair[0].trimmingCharacters(in: .whitespaces),
                    .value: pair[1].trimmingCharacters(in: .whitespaces),
                    .secure: "TRUE"
                ])
            }

        for cookie in cookies {
            await configuration.websiteDataStore.httpCookieStore.setCookieAsync(cookie)
        }
        customUserAgent = sessionState.userAgent
    }

    func yamiboRunJavaScript(_ javaScript: String) async {
        await withCheckedContinuation { continuation in
            evaluateJavaScript(javaScript) { _, _ in
                continuation.resume()
            }
        }
    }

    func yamiboEvaluateExtractionPayload(
        _ javaScript: String,
        htmlFallback: String? = nil
    ) async -> MangaWebExtractionPayload? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript(javaScript) { value, _ in
                continuation.resume(
                    returning: MangaWebExtractionPayload(value, htmlFallback: htmlFallback)
                )
            }
        }
    }

    func yamiboOuterHTML() async -> String? {
        await withCheckedContinuation { continuation in
            evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }
}

private extension WKHTTPCookieStore {
    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
