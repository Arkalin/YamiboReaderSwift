import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MessageCenterViewModelTests: XCTestCase {
    func testLoadFetchesPrivateMessagesByDefault() async throws {
        let repository = MessageCenterRepositoryStub()
        let model = MessageCenterViewModel(repository: repository)

        await model.load()

        XCTAssertEqual(model.selectedTab, .privateMessages)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.navigationTitle, "我的消息")
        if case let .privateMessages(page) = model.content {
            XCTAssertEqual(page.messages.map(\.uid), ["800001"])
        } else {
            XCTFail("Expected private messages content")
        }
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["privateMessages:1"])
    }

    func testSelectingNoticesLoadsFirstNoticePageAndPaginationLoadsNextPage() async throws {
        let repository = MessageCenterRepositoryStub()
        let model = MessageCenterViewModel(repository: repository)

        await model.selectTab(.notices)
        await model.goToPage(2)

        XCTAssertEqual(model.selectedTab, .notices)
        XCTAssertEqual(model.currentPage, 2)
        XCTAssertEqual(model.navigationTitle, "我的提醒")
        if case let .notices(page) = model.content {
            XCTAssertEqual(page.notices.map(\.noticeID), ["notice-2"])
        } else {
            XCTFail("Expected notices content")
        }
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["notices:1", "notices:2"])
    }

    func testLoadStoresError() async throws {
        let repository = MessageCenterRepositoryStub(error: YamiboError.parsingFailed(context: "messages"))
        let model = MessageCenterViewModel(repository: repository)

        await model.load()

        XCTAssertNil(model.content)
        XCTAssertNotNil(model.errorMessage)
    }
}

private actor MessageCenterRepositoryStub: MessageCenterPageLoading {
    let error: Error?
    var recordedCalls: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func fetchPrivateMessages(page: Int) async throws -> UserSpacePrivateMessagePage {
        recordedCalls.append("privateMessages:\(page)")
        if let error { throw error }
        return UserSpacePrivateMessagePage(
            messages: [
                UserSpacePrivateMessageSummary(
                    uid: "800001",
                    name: "好友A",
                    title: "好友A",
                    message: "最近一条消息",
                    timeText: "2026-06-01 10:30"
                )
            ],
            pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 3)
        )
    }

    func fetchNotices(page: Int) async throws -> UserSpaceNoticePage {
        recordedCalls.append("notices:\(page)")
        if let error { throw error }
        return UserSpaceNoticePage(
            notices: [
                UserSpaceNoticeSummary(
                    noticeID: "notice-\(page)",
                    contentHTML: "提醒",
                    contentText: "提醒"
                )
            ],
            pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 3)
        )
    }

    func calls() -> [String] {
        recordedCalls
    }
}
