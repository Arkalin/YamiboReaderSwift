import Foundation
import Testing
@testable import YamiboReaderCore

private final class ForumThreadReaderRepositoryTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ForumThreadReaderRepositoryTestError.missingHandler)
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

private enum ForumThreadReaderRepositoryTestError: Error {
    case missingHandler
}

@Test func forumThreadReaderRepositoryFetchesRatingResultsNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "misc")
        #expect(items.value(named: "action") == "viewratings")
        #expect(items.value(named: "tid") == "704")
        #expect(items.value(named: "pid") == "4001")
        #expect(items.value(named: "mobile") == "2")
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"""
            <html><body>
              <table>
                <tr><th>参与人数 1</th><th>积分 +2</th><th>理由</th></tr>
                <tr><td><a href="home.php?mod=space&amp;uid=77">读者甲</a></td><td>+2</td><td>好</td></tr>
              </table>
            </body></html>
            """#
        )
    }

    let page = try await repository.fetchRatingResults(threadID: "704", postID: "4001")

    #expect(page.ratings.count == 1)
    #expect(page.ratings.first?.user.uid == "77")
}

@Test func forumThreadReaderRepositoryFetchesRateOptionsNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "misc")
        #expect(items.value(named: "action") == "rate")
        #expect(items.value(named: "tid") == "704")
        #expect(items.value(named: "pid") == "4001")
        #expect(items.value(named: "mobile") == "2")
        #expect(items.value(named: "infloat") == "yes")
        #expect(items.value(named: "handlekey") == "rate")
        #expect(items.value(named: "inajax") == "1")
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"""
            <root><![CDATA[
              <select id="rate1"><option value="1">1</option><option value="5">5</option></select>
              <select id="reason"><option value="好萌">好萌</option></select>
            ]]></root>
            """#
        )
    }

    let page = try await repository.fetchRateOptions(threadID: "704", postID: "4001")

    #expect(page.availableScores == [1, 5])
    #expect(page.defaultReasons == ["好萌"])
}

@Test func forumThreadReaderRepositoryFetchesPollVotersNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "misc")
        #expect(items.value(named: "action") == "viewvote")
        #expect(items.value(named: "tid") == "704")
        #expect(items.value(named: "polloptionid") == "12")
        #expect(items.value(named: "page") == "3")
        #expect(items.value(named: "mobile") == "2")
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"""
            <html><body>
              <select><option value="12" selected="selected">选项乙</option></select>
              <a href="home.php?mod=space&amp;uid=88">读者乙</a>
            </body></html>
            """#
        )
    }

    let page = try await repository.fetchPollVoters(threadID: "704", optionID: "12", page: 3)

    #expect(page.selectedOptionID == "12")
    #expect(page.voters.first?.uid == "88")
}

@Test func forumThreadReaderRepositoryVotesPollNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )
    var postedBody = ""

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "misc")
        #expect(items.value(named: "action") == "votepoll")
        #expect(items.value(named: "fid") == "123")
        #expect(items.value(named: "tid") == "704")
        #expect(items.value(named: "mobile") == "2")
        postedBody = String(
            data: request.forumThreadReaderRepositoryHTTPBodyData(),
            encoding: .utf8
        ) ?? ""
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"<html><body><div class="jump_c">投票成功</div></body></html>"#
        )
    }

    let message = try await repository.votePoll(
        forumID: "123",
        threadID: "704",
        optionIDs: ["11", "12"],
        formHash: "form123"
    )

    #expect(message == "投票成功")
    #expect(postedBody.contains("formhash=form123"))
    #expect(postedBody.contains("pollsubmit=true"))
    #expect(postedBody.contains("quickforward=yes"))
    #expect(postedBody.contains("pollanswers%5B%5D=11"))
    #expect(postedBody.contains("pollanswers%5B%5D=12"))
}

@Test func forumThreadReaderRepositoryRatesPostNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )
    var postedBody = ""

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "misc")
        #expect(items.value(named: "action") == "rate")
        #expect(items.value(named: "ratesubmit") == "yes")
        #expect(items.value(named: "infloat") == "yes")
        #expect(items.value(named: "handlekey") == "rateform")
        #expect(items.value(named: "inajax") == "1")
        postedBody = String(data: request.forumThreadReaderRepositoryHTTPBodyData(), encoding: .utf8) ?? ""
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"""
            <root><![CDATA[
              <div id="messagetext"><p>评分成功</p></div>
              <script>succeedhandle_rate();</script>
            ]]></root>
            """#
        )
    }

    let message = try await repository.ratePost(
        threadID: "704",
        postID: "4001",
        score: 5,
        reason: "好萌",
        formHash: "form123",
        noticeAuthor: true
    )

    #expect(message == "评分成功")
    #expect(postedBody.contains("formhash=form123"))
    #expect(postedBody.contains("tid=704"))
    #expect(postedBody.contains("pid=4001"))
    #expect(postedBody.contains("referer="))
    #expect(postedBody.contains("handlekey=rate"))
    #expect(postedBody.contains("score1=5"))
    #expect(postedBody.contains("reason=%E5%A5%BD%E8%90%8C"))
    #expect(postedBody.contains("sendreasonpm=on"))
}

@Test func forumThreadReaderRepositoryCommentsPostNatively() async throws {
    defer { ForumThreadReaderRepositoryTestURLProtocol.handler = nil }

    let repository = ForumThreadReaderRepository(
        client: YamiboClient(
            session: makeForumThreadReaderRepositoryTestSession(),
            cookie: "auth=token",
            userAgent: "Test-UA"
        )
    )
    var postedBody = ""

    ForumThreadReaderRepositoryTestURLProtocol.handler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=token")
        #expect(request.url?.path == "/forum.php")
        #expect(items.value(named: "mod") == "post")
        #expect(items.value(named: "action") == "reply")
        #expect(items.value(named: "comment") == "yes")
        #expect(items.value(named: "tid") == "704")
        #expect(items.value(named: "pid") == "4001")
        #expect(items.value(named: "extra") == "")
        #expect(items.value(named: "page") == "2")
        #expect(items.value(named: "commentsubmit") == "yes")
        #expect(items.value(named: "infloat") == "yes")
        #expect(items.value(named: "handlekey") == "commentform")
        #expect(items.value(named: "inajax") == "1")
        postedBody = String(data: request.forumThreadReaderRepositoryHTTPBodyData(), encoding: .utf8) ?? ""
        return forumThreadReaderRepositoryHTTPResponse(
            url: request.url!,
            body: #"""
            <root><![CDATA[
              <div id="messagetext"><p>点评成功</p></div>
              <script>succeedhandle_comment();</script>
            ]]></root>
            """#
        )
    }

    let message = try await repository.commentPost(
        threadID: "704",
        postID: "4001",
        message: "喜欢",
        formHash: "form123",
        page: 2
    )

    #expect(message == "点评成功")
    #expect(postedBody.contains("formhash=form123"))
    #expect(postedBody.contains("handlekey="))
    #expect(postedBody.contains("message=%E5%96%9C%E6%AC%A2"))
}

private func makeForumThreadReaderRepositoryTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ForumThreadReaderRepositoryTestURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func forumThreadReaderRepositoryHTTPResponse(
    url: URL,
    body: String,
    statusCode: Int = 200
) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    )
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}

private extension URLRequest {
    func forumThreadReaderRepositoryHTTPBodyData() -> Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
