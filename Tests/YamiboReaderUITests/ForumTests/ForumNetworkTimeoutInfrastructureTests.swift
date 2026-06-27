import Foundation
import Testing
@testable import YamiboReaderUI

@Test func forumWebViewLoadsUseSharedNetworkRequestHelper() throws {
    let browserSource = try projectSource("Sources/YamiboReaderUI/Features/Forum/ForumBrowserView.swift")
    let webViewSource = try projectSource("Sources/YamiboReaderUI/Features/Forum/ForumWebView.swift")

    #expect(browserSource.contains("YamiboNetworkConfiguration.makeRequest(url: url)"))
    #expect(webViewSource.contains("YamiboNetworkConfiguration.makeRequest(url: url)"))
    #expect(!browserSource.contains("webView?.load(URLRequest(url: url))"))
    #expect(!webViewSource.contains("webView.load(URLRequest(url: url))"))
}

private func projectSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
}
