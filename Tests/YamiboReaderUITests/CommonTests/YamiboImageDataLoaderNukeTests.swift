import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("CommonTests: Nuke-backed Yamibo image data loader", .serialized)
struct YamiboImageDataLoaderNukeTests {
    @Test func loaderSendsCookieUserAgentAndRefererThroughYamiboSeam() async throws {
        let harness = NukeImageDataTestHarness()
        defer { harness.reset() }
        let pipeline = try makeIsolatedImageDataPipeline()
        harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=1")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "UnitAgent")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/thread-1.html")
            #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/*") == true)
            return NukeImageDataTestResponse(data: Data([1, 2, 3]))
        }
        let loader = YamiboImageDataLoader(
            client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
            pipeline: pipeline
        )

        let data = try await loader.imageData(
            for: imageRequest(refererURL: URL(string: "https://bbs.yamibo.com/thread-1.html")!)
        )

        #expect(data == Data([1, 2, 3]))
        #expect(harness.requests.count == 1)
    }

    @Test func loaderReusesNukeDataCacheAcrossLoaderInstances() async throws {
        let harness = NukeImageDataTestHarness()
        defer { harness.reset() }
        let pipeline = try makeIsolatedImageDataPipeline()
        let counter = LockedCounter()
        harness.setHandler { _ in
            counter.increment()
            return NukeImageDataTestResponse(data: Data([8, 6]))
        }
        let request = imageRequest(url: "https://img.example.com/nuke-cache-\(UUID().uuidString).jpg")
        let firstLoader = YamiboImageDataLoader(
            client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
            pipeline: pipeline
        )
        let secondLoader = YamiboImageDataLoader(
            client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
            pipeline: pipeline
        )

        let first = try await firstLoader.imageData(for: request)
        try await waitForCachedData(in: pipeline, request: request)
        let second = try await secondLoader.imageData(for: request)

        #expect(first == Data([8, 6]))
        #expect(second == Data([8, 6]))
        #expect(counter.value == 1)
    }

    @Test func loaderMapsAuthAndEmptyDataFailures() async throws {
        let authHarness = NukeImageDataTestHarness()
        defer { authHarness.reset() }
        let authPipeline = try makeIsolatedImageDataPipeline()
        authHarness.setHandler { _ in
            NukeImageDataTestResponse(statusCode: 403, data: Data([1]))
        }
        let authLoader = YamiboImageDataLoader(
            client: YamiboClient(session: authHarness.session),
            pipeline: authPipeline
        )
        await #expect(throws: YamiboError.notAuthenticated) {
            _ = try await authLoader.imageData(for: imageRequest())
        }

        let emptyHarness = NukeImageDataTestHarness()
        defer { emptyHarness.reset() }
        let emptyPipeline = try makeIsolatedImageDataPipeline()
        emptyHarness.setHandler { _ in
            NukeImageDataTestResponse(data: Data())
        }
        let emptyLoader = YamiboImageDataLoader(
            client: YamiboClient(session: emptyHarness.session),
            pipeline: emptyPipeline
        )
        await #expect(throws: YamiboError.unreadableBody) {
            _ = try await emptyLoader.imageData(for: imageRequest())
        }
    }

    @Test func pipelineUsesExpectedCacheBudgetAndNoURLCacheDiskStorage() throws {
        let pipeline = try makeIsolatedImageDataPipeline()

        #expect(pipeline.dataCacheLimitBytes == YamiboNukeImageDataPipeline.defaultDataCacheLimitBytes)
        #expect(pipeline.usesURLCacheDiskStorage == false)
    }
}

private struct NukeImageDataTestResponse: Sendable {
    var statusCode: Int
    var data: Data
    var headers: [String: String]

    init(statusCode: Int = 200, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

private final class NukeImageDataTestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var handlersByTestID: [String: @Sendable (URLRequest) throws -> NukeImageDataTestResponse] = [:]
    nonisolated(unsafe) private static var recordedRequestsByTestID: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    static func setHandler(
        for testID: String,
        handler: @escaping @Sendable (URLRequest) throws -> NukeImageDataTestResponse
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

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let testID = request.value(forHTTPHeaderField: "X-Nuke-Image-Test-ID")
        let currentHandler: (@Sendable (URLRequest) throws -> NukeImageDataTestResponse)? = Self.withLockedState {
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

    private static func withLockedState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private final class NukeImageDataTestHarness {
    let testID = UUID().uuidString
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NukeImageDataTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Nuke-Image-Test-ID": testID]
        self.session = URLSession(configuration: configuration)
    }

    func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> NukeImageDataTestResponse) {
        NukeImageDataTestURLProtocol.setHandler(for: testID, handler: handler)
    }

    var requests: [URLRequest] {
        NukeImageDataTestURLProtocol.requests(for: testID)
    }

    func reset() {
        NukeImageDataTestURLProtocol.reset(testID: testID)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private func imageRequest(
    namespace: String = "test",
    refererURL: URL? = nil,
    url: String = "https://img.example.com/a-\(UUID().uuidString).jpg"
) -> YamiboImageRequest {
    YamiboImageRequest(
        url: URL(string: url)!,
        refererURL: refererURL,
        cacheNamespace: YamiboImageCacheNamespace(value: namespace)
    )
}

private func makeIsolatedImageDataPipeline() throws -> YamiboNukeImageDataPipeline {
    try YamiboNukeImageDataPipeline(
        dataCacheDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("yamibo-nuke-ui-test-\(UUID().uuidString)", isDirectory: true)
    )
}

private func waitForCachedData(
    in pipeline: YamiboNukeImageDataPipeline,
    request: YamiboImageRequest
) async throws {
    for _ in 0 ..< 20 {
        if pipeline.cachedData(for: request) != nil {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(pipeline.cachedData(for: request) != nil)
}
