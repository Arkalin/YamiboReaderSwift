import Foundation

struct MangaReaderDataTestResponse: Sendable {
    var statusCode: Int
    var data: Data
    var headers: [String: String]

    init(statusCode: Int = 200, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }

    init(statusCode: Int = 200, html: String, headers: [String: String] = [:]) {
        self.init(
            statusCode: statusCode,
            data: Data(html.utf8),
            headers: headers
        )
    }
}

final class MangaReaderDataTestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var handlersByTestID: [String: @Sendable (URLRequest) throws -> MangaReaderDataTestResponse] = [:]
    nonisolated(unsafe) private static var recordedRequestsByTestID: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    static func setHandler(
        for testID: String,
        handler: @escaping @Sendable (URLRequest) throws -> MangaReaderDataTestResponse
    ) {
        withLockedState {
            handlersByTestID[testID] = handler
            recordedRequestsByTestID[testID] = []
        }
    }

    static func reset(testID: String) {
        withLockedState {
            handlersByTestID.removeValue(forKey: testID)
            recordedRequestsByTestID.removeValue(forKey: testID)
        }
    }

    static func requests(for testID: String) -> [URLRequest] {
        withLockedState { recordedRequestsByTestID[testID] ?? [] }
    }

    private static func withLockedState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let testID = request.value(forHTTPHeaderField: "X-Manga-Test-ID")
        let currentHandler: (@Sendable (URLRequest) throws -> MangaReaderDataTestResponse)? = Self.withLockedState {
            if let testID {
                Self.recordedRequestsByTestID[testID, default: []].append(request)
                return Self.handlersByTestID[testID]
            }
            return nil
        }

        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let output = try currentHandler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: output.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: output.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: output.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class MangaReaderDataTestHarness {
    let testID = UUID().uuidString
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderDataTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Manga-Test-ID": testID]
        self.session = URLSession(configuration: configuration)
    }

    func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> MangaReaderDataTestResponse) {
        MangaReaderDataTestURLProtocol.setHandler(for: testID, handler: handler)
    }

    var requests: [URLRequest] {
        MangaReaderDataTestURLProtocol.requests(for: testID)
    }

    func reset() {
        MangaReaderDataTestURLProtocol.reset(testID: testID)
    }
}
