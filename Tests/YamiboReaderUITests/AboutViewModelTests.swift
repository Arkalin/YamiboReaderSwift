import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class AboutViewModelTests: XCTestCase {
    func testLoadPublishesReleases() async throws {
        let appContext = YamiboAppContext(session: makeAboutViewModelTestSession())
        AboutViewModelTestURLProtocol.setHandler { request in
            let body = """
            [
              {
                "tag_name": "v1.0.0",
                "name": "Initial release",
                "body": "First build",
                "published_at": "2026-04-30T00:00:00Z",
                "html_url": "https://github.com/Arkalin/YamiboReaderSwift/releases/tag/v1.0.0"
              }
            ]
            """
            return (
                try XCTUnwrap(body.data(using: .utf8)),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        defer { AboutViewModelTestURLProtocol.reset() }

        let viewModel = await MainActor.run {
            AboutViewModel(appContext: appContext)
        }

        await viewModel.load()

        let releases = await viewModel.releases
        let isLoading = await viewModel.isLoading
        let errorMessage = await viewModel.errorMessage
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.displayTitle, "Initial release")
        XCTAssertFalse(isLoading)
        XCTAssertNil(errorMessage)
    }

    func testLoadPublishesEmptyState() async throws {
        let appContext = YamiboAppContext(session: makeAboutViewModelTestSession())
        AboutViewModelTestURLProtocol.setHandler { request in
            (
                Data("[]".utf8),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        defer { AboutViewModelTestURLProtocol.reset() }

        let viewModel = await MainActor.run {
            AboutViewModel(appContext: appContext)
        }

        await viewModel.load()

        let releases = await viewModel.releases
        let errorMessage = await viewModel.errorMessage
        XCTAssertTrue(releases.isEmpty)
        XCTAssertNil(errorMessage)
    }

    func testRetryReloadsAfterFailure() async throws {
        let appContext = YamiboAppContext(session: makeAboutViewModelTestSession())
        let lock = NSLock()
        var requestCount = 0
        AboutViewModelTestURLProtocol.setHandler { request in
            let nextCount = lock.withLock {
                requestCount += 1
                return requestCount
            }

            if nextCount == 1 {
                return (
                    Data(),
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }

            let body = """
            [
              {
                "tag_name": "v1.0.1",
                "name": "Retry success",
                "body": "Recovered",
                "published_at": "2026-05-01T00:00:00Z",
                "html_url": "https://github.com/Arkalin/YamiboReaderSwift/releases/tag/v1.0.1"
              }
            ]
            """
            return (
                try XCTUnwrap(body.data(using: .utf8)),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        defer { AboutViewModelTestURLProtocol.reset() }

        let viewModel = await MainActor.run {
            AboutViewModel(appContext: appContext)
        }

        await viewModel.load()
        let initialError = await viewModel.errorMessage
        XCTAssertNotNil(initialError)

        await viewModel.retry()

        let releases = await viewModel.releases
        let errorMessage = await viewModel.errorMessage
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.displayTitle, "Retry success")
        XCTAssertNil(errorMessage)
    }
}

private final class AboutViewModelTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) private static var handler: Handler?
    private static let lock = NSLock()

    static func setHandler(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.lock.withLock({ Self.handler }) else {
            client?.urlProtocol(self, didFailWithError: AboutViewModelTestError.missingHandler)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum AboutViewModelTestError: Error {
    case missingHandler
}

private func makeAboutViewModelTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AboutViewModelTestURLProtocol.self]
    return URLSession(configuration: configuration)
}
