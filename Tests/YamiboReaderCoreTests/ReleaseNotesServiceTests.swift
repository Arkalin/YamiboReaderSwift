import XCTest
@testable import YamiboReaderCore

final class ReleaseNotesServiceTests: XCTestCase {
    func testFetchRecentReleasesRequestsGitHubReleasesAndDecodesResponse() async throws {
        let session = makeReleaseNotesTestSession()
        ReleaseNotesTestURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/repos/Arkalin/YamiboReaderSwift/releases")
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "per_page" })?
                .value, "5")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

            let body = """
            [
              {
                "tag_name": "v1.2.0",
                "name": "Version 1.2",
                "body": "Added release notes\\nFixed bugs",
                "published_at": "2026-05-01T10:20:30Z",
                "html_url": "https://github.com/Arkalin/YamiboReaderSwift/releases/tag/v1.2.0"
              },
              {
                "tag_name": "v1.1.0",
                "name": "",
                "body": "",
                "published_at": null,
                "html_url": "https://github.com/Arkalin/YamiboReaderSwift/releases/tag/v1.1.0"
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
        defer { ReleaseNotesTestURLProtocol.reset() }

        let releases = try await ReleaseNotesService(session: session).fetchRecentReleases()

        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases[0].tagName, "v1.2.0")
        XCTAssertEqual(releases[0].displayTitle, "Version 1.2")
        XCTAssertEqual(releases[0].displayBody, "Added release notes\nFixed bugs")
        XCTAssertEqual(releases[0].publishedAt, Date(timeIntervalSince1970: 1_777_630_830))
        XCTAssertEqual(releases[1].displayTitle, "v1.1.0")
        XCTAssertNil(releases[1].displayBody)
    }

    func testFetchRecentReleasesThrowsForHTTPError() async throws {
        let session = makeReleaseNotesTestSession()
        ReleaseNotesTestURLProtocol.setHandler { request in
            (
                Data(),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        defer { ReleaseNotesTestURLProtocol.reset() }

        do {
            _ = try await ReleaseNotesService(session: session).fetchRecentReleases()
            XCTFail("Expected fetch to throw")
        } catch let error as YamiboError {
            XCTAssertEqual(error, .invalidResponse(statusCode: 500))
        }
    }

    func testFetchRecentReleasesThrowsForInvalidJSON() async throws {
        let session = makeReleaseNotesTestSession()
        ReleaseNotesTestURLProtocol.setHandler { request in
            (
                Data("not-json".utf8),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        defer { ReleaseNotesTestURLProtocol.reset() }

        do {
            _ = try await ReleaseNotesService(session: session).fetchRecentReleases()
            XCTFail("Expected fetch to throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}

private final class ReleaseNotesTestURLProtocol: URLProtocol {
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
            client?.urlProtocol(self, didFailWithError: ReleaseNotesTestError.missingHandler)
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

private enum ReleaseNotesTestError: Error {
    case missingHandler
}

private func makeReleaseNotesTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReleaseNotesTestURLProtocol.self]
    return URLSession(configuration: configuration)
}
