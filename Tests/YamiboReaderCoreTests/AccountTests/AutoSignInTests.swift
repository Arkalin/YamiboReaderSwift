import Foundation
import Testing
@testable import YamiboReaderCore

private struct AutoSignStubResponse {
    let statusCode: Int
    let body: String
}

private enum AutoSignStubOutput {
    case response(AutoSignStubResponse)
    case error(Error)
}

private final class AutoSignURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static var handlers: [String: (URLRequest) -> AutoSignStubOutput] = [:]
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func setHandler(_ handler: @escaping (URLRequest) -> AutoSignStubOutput, for testID: String) {
        lock.lock()
        handlers[testID] = handler
        lock.unlock()
    }

    static func removeHandler(for testID: String) {
        lock.lock()
        handlers.removeValue(forKey: testID)
        lock.unlock()
    }

    override func startLoading() {
        let testID = request.value(forHTTPHeaderField: "X-AutoSign-Test-ID") ?? ""
        Self.lock.lock()
        let handler = Self.handlers[testID]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch handler(request) {
        case let .response(output):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: output.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(output.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Test func autoSignReturnsNotAuthenticatedWhenSessionIsMissing() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "not-auth")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded()

    #expect(result == .notAuthenticated)
}

@Test func autoSignRecognizesAlreadySignedPageAndPersistsToday() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "already-signed")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    try await sessionStore.save(
        SessionState(
            cookie: "foo=1; EeqY_2132_auth=user-a",
            userAgent: "Test-UA",
            isLoggedIn: true
        )
    )

    AutoSignURLProtocol.setHandler({ request in
        #expect(request.value(forHTTPHeaderField: "Cookie") == "foo=1; EeqY_2132_auth=user-a")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Test-UA")
        return .response(
            AutoSignStubResponse(
                statusCode: 200,
                body: #"<a class="btna">今日已打卡</a>"#
            )
        )
    }, for: testID)
    defer { AutoSignURLProtocol.removeHandler(for: testID) }

    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded(force: true)

    #expect(result == .alreadySignedToday)
    let lastSignedDate = await autoSignStore.lastSignedDate(
        session: SessionState(cookie: "foo=1; EeqY_2132_auth=user-a", userAgent: "Test-UA", isLoggedIn: true)
    )
    #expect(lastSignedDate != nil)
}

@Test func autoSignRequestsSignURLAndSucceedsAfterVerification() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "sign-success")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    let sessionState = SessionState(
        cookie: "sid=1; EeqY_2132_auth=user-b",
        userAgent: "Test-UA",
        isLoggedIn: true
    )
    try await sessionStore.save(sessionState)

    let lock = NSLock()
    var signPageVisits = 0
    var requestedURLs: [String] = []

    AutoSignURLProtocol.setHandler({ request in
        lock.lock()
        requestedURLs.append(request.url!.absoluteString)
        let currentVisit = signPageVisits
        if request.url == AutoSignInService.signPageURL {
            signPageVisits += 1
        }
        lock.unlock()

        if request.url == AutoSignInService.signPageURL, currentVisit == 0 {
            return .response(
                AutoSignStubResponse(
                    statusCode: 200,
                    body: #"<a class="btna">点击打卡</a><a href="plugin.php?id=zqlj_sign&amp;sign=abc123">立即签到</a>"#
                )
            )
        }

        if request.url?.absoluteString == "https://bbs.yamibo.com/plugin.php?id=zqlj_sign&sign=abc123" {
            return .response(AutoSignStubResponse(statusCode: 200, body: "<html>ok</html>"))
        }

        return .response(
            AutoSignStubResponse(
                statusCode: 200,
                body: #"<a class="btna">今日已打卡</a>"#
            )
        )
    }, for: testID)
    defer { AutoSignURLProtocol.removeHandler(for: testID) }

    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded(force: true)

    #expect(result == .success)
    #expect(requestedURLs == [
        "https://bbs.yamibo.com/plugin.php?id=zqlj_sign&mobile=2",
        "https://bbs.yamibo.com/plugin.php?id=zqlj_sign&sign=abc123",
        "https://bbs.yamibo.com/plugin.php?id=zqlj_sign&mobile=2"
    ])
    let needsSignIn = await autoSignStore.needsSignIn(session: sessionState)
    #expect(needsSignIn == false)
}

@Test func autoSignSkipsNetworkWhenTodayIsAlreadyRecorded() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "skip-today")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    let sessionState = SessionState(
        cookie: "sid=1; EeqY_2132_auth=user-c",
        userAgent: "Test-UA",
        isLoggedIn: true
    )
    try await sessionStore.save(sessionState)
    await autoSignStore.markSignedIn(session: sessionState)

    let lock = NSLock()
    var requestCount = 0
    AutoSignURLProtocol.setHandler({ _ in
        lock.lock()
        requestCount += 1
        lock.unlock()
        return .error(URLError(.badServerResponse))
    }, for: testID)
    defer { AutoSignURLProtocol.removeHandler(for: testID) }

    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded()

    #expect(result == .skippedToday)
    #expect(requestCount == 0)
}

@Test func autoSignReturnsParseFailedWhenSignLinkIsMissing() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "parse-failed")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    try await sessionStore.save(
        SessionState(
            cookie: "sid=1; EeqY_2132_auth=user-d",
            userAgent: "Test-UA",
            isLoggedIn: true
        )
    )

    AutoSignURLProtocol.setHandler({ _ in
        .response(
            AutoSignStubResponse(
                statusCode: 200,
                body: #"<a class="btna">点击打卡</a>"#
            )
        )
    }, for: testID)
    defer { AutoSignURLProtocol.removeHandler(for: testID) }

    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded(force: true)

    #expect(result == .parseFailed)
}

@Test func autoSignReturnsVerificationFailedWhenServerDoesNotConfirmSignIn() async throws {
    let testID = UUID().uuidString
    let suiteName = makeAutoSignSuiteName(prefix: "verify-failed")
    let sessionStore = SessionStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), key: "session")
    let autoSignStore = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    try await sessionStore.save(
        SessionState(
            cookie: "sid=1; EeqY_2132_auth=user-e",
            userAgent: "Test-UA",
            isLoggedIn: true
        )
    )

    let lock = NSLock()
    var signPageVisits = 0

    AutoSignURLProtocol.setHandler({ request in
        if request.url == AutoSignInService.signPageURL {
            lock.lock()
            let currentVisit = signPageVisits
            signPageVisits += 1
            lock.unlock()

            if currentVisit == 0 {
                return .response(
                    AutoSignStubResponse(
                        statusCode: 200,
                        body: #"<a class="btna">点击打卡</a><a href="plugin.php?id=zqlj_sign&sign=late">立即签到</a>"#
                    )
                )
            }
            return .response(
                AutoSignStubResponse(
                    statusCode: 200,
                    body: "<html>still not signed</html>"
                )
            )
        }

        return .response(AutoSignStubResponse(statusCode: 200, body: "<html>ok</html>"))
    }, for: testID)
    defer { AutoSignURLProtocol.removeHandler(for: testID) }

    let service = AutoSignInService(
        sessionStore: sessionStore,
        autoSignInStore: autoSignStore,
        session: makeAutoSignSession(testID: testID),
        verificationDelayNanoseconds: 0
    )

    let result = await service.signInIfNeeded(force: true)

    #expect(result == .verificationFailed)
}

@Test func autoSignStoreSeparatesDifferentAccounts() async throws {
    let suiteName = makeAutoSignSuiteName(prefix: "account-isolation")
    let store = AutoSignInStore(defaults: try makeAutoSignDefaults(suiteName: suiteName), keyPrefix: "auto-sign")
    let first = SessionState(cookie: "foo=1; EeqY_2132_auth=alpha", isLoggedIn: true)
    let second = SessionState(cookie: "foo=1; EeqY_2132_auth=beta", isLoggedIn: true)

    await store.markSignedIn(session: first)

    let firstDate = await store.lastSignedDate(session: first)
    let secondDate = await store.lastSignedDate(session: second)
    #expect(firstDate != nil)
    #expect(secondDate == nil)
}

private func makeAutoSignSession(testID: String) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AutoSignURLProtocol.self]
    configuration.httpAdditionalHeaders = ["X-AutoSign-Test-ID": testID]
    return URLSession(configuration: configuration)
}

private func makeAutoSignSuiteName(prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString)"
}

private func makeAutoSignDefaults(suiteName: String) throws -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw YamiboError.underlying("Failed to create UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
