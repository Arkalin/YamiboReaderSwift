import Foundation
import Observation
import SwiftUI
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct MineHomeView: View {
    @State private var viewModel: MineHomeViewModel
    @State private var showingSettingsSheet = false
    @State private var showingAboutSheet = false
    @State private var showingSignOutConfirmation = false

    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(appContext: YamiboAppContext, appModel: YamiboAppModel) {
        _viewModel = State(initialValue: MineHomeViewModel(appContext: appContext))
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoggedIn {
                    MineProfileSection(
                        profile: viewModel.profile,
                        sessionState: viewModel.session,
                        isRefreshing: viewModel.isRefreshingProfile,
                        showSignOutConfirmation: {
                            showingSignOutConfirmation = true
                        }
                    )
                } else {
                    MineLoginSection(viewModel: viewModel)
                }

                MineSettingsSection(
                    showSettings: {
                        showingSettingsSheet = true
                    },
                    showAbout: {
                        showingAboutSheet = true
                    }
                )
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(L10n.string("tab.mine"))
            .disabled(viewModel.isBusy)
            .refreshable {
                await viewModel.refreshProfile()
            }
            .task {
                await viewModel.load()
            }
            .alert(L10n.string("common.operation_failed"), isPresented: errorIsPresented, actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .confirmationDialog(
                L10n.string("mine.sign_out"),
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .hidden
            ) {
                Button(L10n.string("mine.sign_out"), role: .destructive) {
                    Task {
                        await viewModel.signOut()
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            }
            .overlay {
                if viewModel.isSigningOut {
                    ProgressView(L10n.string("mine.signing_out"))
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SystemSettingsView(appContext: appContext) {
                    await appModel.bootstrap()
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView(appContext: appContext)
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

@MainActor
@Observable
private final class MineHomeViewModel {
    var session = SessionState()
    var profile: YamiboProfile?
    var errorMessage: String?
    var isLoading = false
    var isRefreshingProfile = false
    var isLoggingIn = false
    var isSigningOut = false

    let loginQuestions = YamiboLoginQuestion.defaultQuestions

    private let appContext: YamiboAppContext

    init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    var isLoggedIn: Bool {
        session.isLoggedIn && SessionState.hasAuthenticationCookie(session.cookie)
    }

    var isBusy: Bool {
        isLoading || isLoggingIn || isSigningOut
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        session = await appContext.sessionStore.load()
        profile = await appContext.profileStore.load()
        if isLoggedIn {
            await refreshProfile(presentsErrors: profile == nil)
        }
    }

    func refreshProfile() async {
        await refreshProfile(presentsErrors: true)
    }

    func login(username: String, password: String, questionID: String, answer: String) async -> Bool {
        guard !isLoggingIn else { return false }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            profile = try await appContext.makeAccountService().login(
                YamiboLoginRequest(
                    username: username,
                    password: password,
                    questionID: questionID,
                    answer: answer
                )
            )
            session = await appContext.sessionStore.load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await appContext.makeAccountService().signOut()
            session = await appContext.sessionStore.load()
            profile = await appContext.profileStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshProfile(presentsErrors: Bool) async {
        guard isLoggedIn, !isRefreshingProfile else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        do {
            profile = try await appContext.makeAccountService().refreshProfile()
            session = await appContext.sessionStore.load()
            errorMessage = nil
        } catch YamiboError.notAuthenticated {
            try? await appContext.makeAccountService().clearLocalAuthentication()
            session = await appContext.sessionStore.load()
            profile = await appContext.profileStore.load()
            errorMessage = YamiboError.notAuthenticated.localizedDescription
        } catch {
            if presentsErrors {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MineProfileSection: View {
    let profile: YamiboProfile?
    let sessionState: SessionState
    let isRefreshing: Bool
    let showSignOutConfirmation: () -> Void

    var body: some View {
        Section {
            if let profile {
                Button(action: showSignOutConfirmation) {
                    MineProfileCard(profile: profile, sessionState: sessionState)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } else {
                MineProfileLoadingCard(isRefreshing: isRefreshing)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
    }
}

private struct MineProfileCard: View {
    let profile: YamiboProfile
    let sessionState: SessionState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MineAvatarView(
                url: profile.avatarURL,
                cookie: sessionState.cookie,
                userAgent: sessionState.userAgent
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 10) {
                MineProfileIdentityRow(username: profile.username, uid: profile.uid)
                MineCreditProgressView(progress: YamiboUserGroups.progress(for: profile))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 96)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.string("mine.profile_card_sign_out_hint"))
    }
}

private struct MineProfileIdentityRow: View {
    let username: String
    let uid: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(username.isEmpty ? L10n.string("mine.unknown_user") : username)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                MineUIDText(uid: uid)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(username.isEmpty ? L10n.string("mine.unknown_user") : username)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                MineUIDText(uid: uid)
            }
        }
    }
}

private struct MineUIDText: View {
    let uid: String

    var body: some View {
        Text(L10n.string("mine.uid_format", uid))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct MineCreditProgressView: View {
    let progress: ForumCreditProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fraction)
                .tint(.accentColor)

            HStack(spacing: 8) {
                Text(progress.currentGroupName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(L10n.string("mine.credit_progress_format", progress.currentTotalPoints, progress.targetTotalPoints))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct MineProfileLoadingCard: View {
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("common.loading"))
                    .font(.title3.weight(.semibold))
                ProgressView()
                    .opacity(isRefreshing ? 1 : 0)
            }
        }
        .frame(minHeight: 96)
    }
}

private struct MineLoginSection: View {
    let viewModel: MineHomeViewModel

    @AppStorage("yamibo.login.username") private var username = ""
    @State private var password = ""
    @State private var selectedQuestionID = YamiboLoginQuestion.none.id
    @State private var answer = ""

    var body: some View {
        Section {
            TextField(L10n.string("mine.login_username"), text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            SecureField(L10n.string("mine.login_password"), text: $password)
                .textContentType(.password)

            Picker(L10n.string("mine.security_question"), selection: $selectedQuestionID) {
                ForEach(viewModel.loginQuestions) { question in
                    Text(question.title).tag(question.id)
                }
            }

            if selectedQuestionID != YamiboLoginQuestion.none.id {
                TextField(L10n.string("mine.security_answer"), text: $answer)
                    .autocorrectionDisabled()
            }
        }

        Section {
            Button {
                Task {
                    let didLogin = await viewModel.login(
                        username: username,
                        password: password,
                        questionID: selectedQuestionID,
                        answer: answer
                    )
                    if didLogin {
                        password = ""
                        answer = ""
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isLoggingIn {
                        ProgressView()
                    } else {
                        Text(L10n.string("mine.login"))
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(loginIsDisabled)
        }
    }

    private var loginIsDisabled: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.isEmpty
            || viewModel.isLoggingIn
    }
}

private struct MineSettingsSection: View {
    let showSettings: () -> Void
    let showAbout: () -> Void

    var body: some View {
        Section {
            MineSettingsRow(
                title: L10n.string("settings.title"),
                systemImage: "gearshape.fill",
                tint: .gray,
                action: showSettings
            )

            MineSettingsRow(
                title: L10n.string("about.title"),
                systemImage: "info.circle.fill",
                tint: .blue,
                action: showAbout
            )
        }
    }
}

private struct MineSettingsRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MineAvatarView: View {
    let url: URL?
    let cookie: String
    let userAgent: String

    @State private var image: Image?

    var body: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.14))

            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .clipShape(Circle())
        .task(id: AvatarRequestIdentity(url: url, cookie: cookie, userAgent: userAgent)) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> Image? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode else {
                return nil
            }
            return platformImage(from: data)
        } catch {
            return nil
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

private struct AvatarRequestIdentity: Hashable {
    let url: URL?
    let cookie: String
    let userAgent: String
}
