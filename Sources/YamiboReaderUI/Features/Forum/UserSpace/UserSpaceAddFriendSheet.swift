import SwiftUI
import YamiboReaderCore

struct UserSpaceAddFriendSheet: View {
    let targetName: String?
    let form: UserSpaceAddFriendForm?
    let isLoading: Bool
    let isSubmitting: Bool
    let errorMessage: String?
    let retry: () -> Void
    let submit: (String, Int) -> Void
    let dismiss: () -> Void

    @State private var note = ""
    @State private var selectedGroupID: Int?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    UserSpaceAddFriendLoadingView()
                } else if let errorMessage {
                    UserSpaceErrorView(message: errorMessage, retry: retry)
                } else if let form {
                    UserSpaceAddFriendFormView(
                        targetName: form.name ?? targetName,
                        avatarURL: form.avatarURL,
                        options: form.options,
                        note: Binding(
                            get: { note },
                            set: { note = String($0.prefix(10)) }
                        ),
                        selectedGroupID: Binding(
                            get: { selectedGroupID ?? form.options.first?.id ?? 1 },
                            set: { selectedGroupID = $0 }
                        ),
                        isSubmitting: isSubmitting,
                        submit: {
                            submit(note, selectedGroupID ?? form.options.first?.id ?? 1)
                        }
                    )
                } else {
                    UserSpaceEmptyView(message: L10n.string("user_space.add_friend_form_unavailable"))
                }
            }
            .navigationTitle(L10n.string("user_space.add_friend"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: dismiss)
                        .disabled(isSubmitting)
                }
            }
            .task(id: form?.formHash) {
                selectedGroupID = form?.options.first?.id
            }
        }
    }
}

private struct UserSpaceAddFriendFormView: View {
    let targetName: String?
    let avatarURL: URL?
    let options: [UserSpaceAddFriendOption]
    @Binding var note: String
    @Binding var selectedGroupID: Int
    let isSubmitting: Bool
    let submit: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    YamiboRemoteImage(source: avatarURL.map { YamiboImageSource(url: $0) }) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(ForumColors.secondaryText)
                    } failure: {
                        Image(systemName: "person.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(targetName ?? L10n.string("user_space.unknown_user"))
                            .font(.headline)
                        Text(L10n.string("user_space.add_friend_note_limit"))
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L10n.string("user_space.add_friend_note")) {
                TextField(L10n.string("user_space.add_friend_note_placeholder"), text: $note)
                    .disabled(isSubmitting)
            }

            Section(L10n.string("user_space.add_friend_group")) {
                Picker(L10n.string("user_space.add_friend_group"), selection: $selectedGroupID) {
                    ForEach(options) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .disabled(isSubmitting)
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(L10n.string("user_space.add_friend_submit"))
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isSubmitting)
            }
        }
    }
}

private struct UserSpaceAddFriendLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("user_space.add_friend_loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
