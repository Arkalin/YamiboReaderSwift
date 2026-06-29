import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class UserSpaceViewModelTests: XCTestCase {
    func testLoadFetchesProfileOnlyForProfileTab() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", repository: repository)

        await model.load()

        XCTAssertEqual(model.profile?.uid, "705216")
        XCTAssertEqual(model.selectedSection, .space)
        XCTAssertEqual(model.selectedSubPage, .profile)
        XCTAssertNil(model.content)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["profile:705216:张瑞泽"])
    }

    func testSelectingThreadsFetchesFirstPageAndPaginationFetchesNextPage() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", repository: repository)

        await model.selectTab(.threads)
        await model.goToPage(2)

        if case let .threads(page) = model.content {
            XCTAssertEqual(page.threads.map(\.tid), ["thread-2"])
        } else {
            XCTFail("Expected threads content")
        }
        XCTAssertEqual(model.currentPage, 2)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["threads:705216:1", "threads:705216:2"])
    }

    func testSelectingProfileLoadsProfileWhenMissing() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", repository: repository)

        await model.selectSubPage(.threads)
        model.profile = nil
        await model.selectSubPage(.profile)

        XCTAssertEqual(model.selectedSection, .space)
        XCTAssertEqual(model.selectedSubPage, .profile)
        XCTAssertEqual(model.profile?.uid, "705216")
        XCTAssertNil(model.content)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["threads:705216:1", "profile:705216:张瑞泽"])
    }

    func testInitialSectionAndSubPageLoadAndroidStyleUserSpaceGroup() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(
            uid: nil,
            titleHint: nil,
            initialSection: .blogs,
            initialSubPage: .friendBlogs,
            isSelf: true,
            repository: repository
        )

        await model.load()

        XCTAssertEqual(model.selectedSection, .blogs)
        XCTAssertEqual(model.selectedSubPage, .friendBlogs)
        XCTAssertEqual(model.navigationTitle, "我的日志")
        if case .blogs = model.content {
        } else {
            XCTFail("Expected blogs content")
        }
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["profile:self:", "friendBlogs:1"])
    }

    func testInitialTabFallsBackToFirstTabForRequestedSection() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(
            uid: "705216",
            titleHint: "张瑞泽",
            initialSection: .friends,
            initialSubPage: .myBlogs,
            isSelf: false,
            repository: repository
        )

        await model.load()

        XCTAssertEqual(model.selectedSection, .friends)
        XCTAssertEqual(model.selectedSubPage, .friends)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["profile:705216:张瑞泽", "friendPage:myFriend:1"])
    }

    func testSelectingBlogsStoresError() async throws {
        let repository = UserSpaceRepositoryStub(error: YamiboError.parsingFailed(context: "blogs"))
        let model = UserSpaceViewModel(uid: "705216", titleHint: nil, repository: repository)

        await model.selectTab(.myBlogs)

        XCTAssertNil(model.content)
        XCTAssertNotNil(model.errorMessage)
    }

    func testViewAllBlogsUsesSelectedFilter() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(uid: nil, titleHint: nil, isSelf: true, repository: repository)

        await model.selectSubPage(.viewAllBlogs)
        await model.selectViewAllBlogFilter(.hot)

        XCTAssertEqual(model.selectedSection, .blogs)
        XCTAssertEqual(model.viewAllBlogFilter, .hot)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["viewAllBlogs:latest:1", "viewAllBlogs:hot:1"])
    }

    func testBlogEditorIsAvailableOnlyForSelfBlogSection() async throws {
        let selfRepository = UserSpaceRepositoryStub()
        let selfModel = UserSpaceViewModel(uid: nil, titleHint: nil, isSelf: true, repository: selfRepository)
        let otherRepository = UserSpaceRepositoryStub()
        let otherModel = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", isSelf: false, repository: otherRepository)

        await selfModel.selectSection(.blogs)
        await otherModel.selectSection(.blogs)

        XCTAssertTrue(selfModel.canOpenBlogEditor)
        XCTAssertFalse(otherModel.canOpenBlogEditor)
    }

    func testNavigationTitleFollowsCurrentUserSpaceSection() async throws {
        let selfRepository = UserSpaceRepositoryStub()
        let selfModel = UserSpaceViewModel(uid: nil, titleHint: nil, isSelf: true, repository: selfRepository)
        let otherRepository = UserSpaceRepositoryStub()
        let otherModel = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", isSelf: false, repository: otherRepository)

        XCTAssertEqual(selfModel.navigationTitle, "我的资料")
        XCTAssertEqual(otherModel.navigationTitle, "张瑞泽的资料")

        await selfModel.selectSection(.blogs)
        await otherModel.selectSection(.threads)

        XCTAssertEqual(selfModel.navigationTitle, "我的日志")
        XCTAssertEqual(otherModel.navigationTitle, "张瑞泽 - Ta的主题")

        await selfModel.selectSubPage(.online)

        XCTAssertEqual(selfModel.navigationTitle, "在线成员")
    }

    func testLoadTreatsTargetUIDMatchingCurrentAccountAsSelf() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(
            uid: "705216",
            titleHint: "张瑞泽",
            currentAccountUID: "705216",
            repository: repository
        )

        await model.load()
        await model.beginAddFriend()

        XCTAssertTrue(model.isSelf)
        XCTAssertEqual(model.availableSubPages, [.profile])
        XCTAssertFalse(model.isAddFriendSheetPresented)
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["profile:705216:张瑞泽"])
    }

    func testAddFriendLoadsFormAndSubmitsRequest() async throws {
        let repository = UserSpaceRepositoryStub()
        let model = UserSpaceViewModel(uid: "705216", titleHint: "张瑞泽", isSelf: false, repository: repository)
        model.profile = UserSpaceProfile(uid: "705216", username: "张瑞泽")

        await model.beginAddFriend()
        await model.submitAddFriend(note: "你好", groupID: 2)

        XCTAssertFalse(model.isAddFriendSheetPresented)
        XCTAssertEqual(model.addFriendResultMessage, "好友请求已送出")
        let calls = await repository.calls()
        XCTAssertEqual(calls, ["addFriendForm:705216:张瑞泽", "addFriend:705216:form123:你好:2"])
    }
}

private actor UserSpaceRepositoryStub: UserSpacePageLoading {
    let error: Error?
    var recordedCalls: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func fetchProfile(uid: String?, titleHint: String?) async throws -> UserSpaceProfile {
        recordedCalls.append("profile:\(uid ?? "self"):\(titleHint ?? "")")
        if let error { throw error }
        return UserSpaceProfile(uid: uid ?? "self", username: titleHint ?? "User")
    }

    func fetchThreads(uid: String?, page: Int) async throws -> UserSpaceThreadPage {
        recordedCalls.append("threads:\(uid ?? "self"):\(page)")
        if let error { throw error }
        return UserSpaceThreadPage(
            threads: [ForumThreadSummary(tid: "thread-\(page)", title: "Thread", url: URL(string: "https://bbs.yamibo.com/thread-\(page)-1-1.html")!)],
            pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 3)
        )
    }

    func fetchReplies(uid: String?, page: Int) async throws -> UserSpaceReplyPage {
        recordedCalls.append("replies:\(uid ?? "self"):\(page)")
        if let error { throw error }
        return UserSpaceReplyPage(replies: [])
    }

    func fetchBlogs(uid: String?, page: Int) async throws -> UserSpaceBlogPage {
        recordedCalls.append("blogs:\(uid ?? "self"):\(page)")
        if let error { throw error }
        return UserSpaceBlogPage(blogs: [])
    }

    func fetchMyBlogs(uid: String?, page: Int) async throws -> UserSpaceBlogPage {
        recordedCalls.append("myBlogs:\(uid ?? "self"):\(page)")
        if let error { throw error }
        return UserSpaceBlogPage(blogs: [])
    }

    func fetchFriendBlogs(page: Int) async throws -> UserSpaceBlogPage {
        recordedCalls.append("friendBlogs:\(page)")
        if let error { throw error }
        return UserSpaceBlogPage(blogs: [])
    }

    func fetchViewAllBlogs(filter: UserSpaceViewAllBlogFilter, page: Int) async throws -> UserSpaceBlogPage {
        recordedCalls.append("viewAllBlogs:\(filter.rawValue):\(page)")
        if let error { throw error }
        return UserSpaceBlogPage(blogs: [])
    }

    func fetchFriendPage(type: UserSpaceFriendType, page: Int) async throws -> UserSpaceFriendPage {
        recordedCalls.append("friendPage:\(type.rawValue):\(page)")
        if let error { throw error }
        return UserSpaceFriendPage(friends: [])
    }

    func fetchAddFriendForm(uid: String, nameHint: String?) async throws -> UserSpaceAddFriendForm {
        recordedCalls.append("addFriendForm:\(uid):\(nameHint ?? "")")
        if let error { throw error }
        return UserSpaceAddFriendForm(
            uid: uid,
            name: nameHint,
            formHash: "form123",
            options: [
                UserSpaceAddFriendOption(id: 1, name: "好友"),
                UserSpaceAddFriendOption(id: 2, name: "同好")
            ]
        )
    }

    func addFriend(uid: String, formHash: String, note: String, groupID: Int) async throws -> String {
        recordedCalls.append("addFriend:\(uid):\(formHash):\(note):\(groupID)")
        if let error { throw error }
        return "好友请求已送出"
    }

    func calls() -> [String] {
        recordedCalls
    }
}
