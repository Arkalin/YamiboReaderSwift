import Foundation

public enum AutoSignInResult: Equatable, Sendable {
    case success
    case alreadySignedToday
    case skippedToday
    case notAuthenticated
    case parseFailed
    case verificationFailed
    case networkFailed(String)

    public var message: String {
        switch self {
        case .success:
            "签到成功"
        case .alreadySignedToday, .skippedToday:
            "今日已打卡"
        case .notAuthenticated:
            "未登录，请先在 App 中登录"
        case .parseFailed:
            "签到页面解析失败，请稍后重试"
        case .verificationFailed:
            "签到未生效，请手动签到"
        case let .networkFailed(message):
            message
        }
    }
}

public struct AutoSignInService: Sendable {
    public static let signPageURL = URL(string: "https://bbs.yamibo.com/plugin.php?id=zqlj_sign&mobile=2")!

    private let sessionStore: SessionStore
    private let autoSignInStore: AutoSignInStore
    private let session: URLSession
    private let verificationDelayNanoseconds: UInt64

    public init(
        sessionStore: SessionStore,
        autoSignInStore: AutoSignInStore,
        session: URLSession = .shared,
        verificationDelayNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.sessionStore = sessionStore
        self.autoSignInStore = autoSignInStore
        self.session = session
        self.verificationDelayNanoseconds = verificationDelayNanoseconds
    }

    public func signInIfNeeded(force: Bool = false) async -> AutoSignInResult {
        let sessionState = await sessionStore.load()
        guard sessionState.isLoggedIn, !sessionState.cookie.isEmpty else {
            return .notAuthenticated
        }

        if !force {
            let needsSignIn = await autoSignInStore.needsSignIn(session: sessionState)
            if !needsSignIn {
                return .skippedToday
            }
        }

        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )

        let signPageHTML: String
        do {
            signPageHTML = try await client.fetchHTML(url: Self.signPageURL)
        } catch {
            return mapNetworkError(error)
        }

        if Self.isAlreadySigned(in: signPageHTML) {
            await autoSignInStore.markSignedIn(session: sessionState)
            return .alreadySignedToday
        }

        guard let signURL = Self.extractSignURL(from: signPageHTML) else {
            return .parseFailed
        }

        do {
            _ = try await client.fetchHTML(url: signURL)
        } catch {
            return mapNetworkError(error)
        }

        if verificationDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: verificationDelayNanoseconds)
        }

        do {
            let verificationHTML = try await client.fetchHTML(url: Self.signPageURL)
            guard Self.isAlreadySigned(in: verificationHTML) else {
                return .verificationFailed
            }
            await autoSignInStore.markSignedIn(session: sessionState)
            return .success
        } catch {
            return mapNetworkError(error)
        }
    }

    private func mapNetworkError(_ error: Error) -> AutoSignInResult {
        if let yamiboError = error as? YamiboError, yamiboError == .notAuthenticated {
            return .notAuthenticated
        }
        let message = (error as? LocalizedError)?.errorDescription ?? "网络异常，请稍后重试"
        return .networkFailed(message.isEmpty ? "网络异常，请稍后重试" : message)
    }

    private static func isAlreadySigned(in html: String) -> Bool {
        html.contains(#"class="btna">今日已打卡</a>"#)
    }

    private static func extractSignURL(from html: String) -> URL? {
        guard html.contains(#"class="btna">点击打卡</a>"#) else {
            return nil
        }

        let pattern = #"href="(plugin\.php\?id=zqlj_sign(?:&amp;|&)sign=[^"]+)""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
            let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        let path = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: path, relativeTo: YamiboRoute.baseURL)?.absoluteURL
    }
}
