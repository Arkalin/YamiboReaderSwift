import SwiftUI
import YamiboReaderCore

struct SystemSettingsHomePageSelector: View {
    let homePage: AppHomePage
    let isBusy: Bool
    let onSelect: (AppHomePage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("settings.home_page"))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                ForEach([AppHomePage.forum, .favorites], id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.systemImageName)
                                .font(.subheadline.weight(.semibold))
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(homePage == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(homePage == option ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SystemSettingsRow: View {
    let title: String
    let value: String?
    let showsChevron: Bool
    let titleColor: Color

    init(title: String, value: String? = nil, showsChevron: Bool = true, titleColor: Color = .primary) {
        self.title = title
        self.value = value
        self.showsChevron = showsChevron
        self.titleColor = titleColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(titleColor)

            Spacer(minLength: 0)

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
