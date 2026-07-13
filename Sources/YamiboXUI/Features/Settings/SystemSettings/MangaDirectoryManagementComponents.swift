import SwiftUI
import YamiboReaderCore

struct MangaDirectoryManagementRowView: View {
    let row: MangaDirectoryManagementRow
    let isSelecting: Bool
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                Text(row.summaryText)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelecting && isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSelected)
        .onTapGesture {
            // No per-directory drill-down exists here, so a tap outside
            // selection mode is a no-op — only the "select" toolbar button
            // and swipe-to-delete are live until selection mode is entered.
            if isSelecting {
                select()
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete()
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        }
    }

    private var isDimmed: Bool {
        isSelecting && !isSelected
    }

    private var titleColor: Color {
        isDimmed ? .secondary : .primary
    }

    private var secondaryColor: Color {
        isDimmed ? Color.secondary.opacity(0.55) : .secondary
    }
}

struct MangaDirectoryManagementSelectAllButton: View {
    let viewModel: SystemSettingsViewModel

    var body: some View {
        Button(title) {
            viewModel.toggleAllMangaDirectoryManagementRows()
        }
        .disabled(viewModel.mangaDirectoryManagementIsEmpty)
        .accessibilityLabel(title)
    }

    private var title: String {
        viewModel.isMangaDirectoryManagementSelectionComplete
            ? L10n.string("common.invert_selection")
            : L10n.string("common.select_all")
    }
}

struct MangaDirectoryManagementEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(L10n.string("settings.manga_directory.empty_title"))
                .font(.headline)

            Text(L10n.string("settings.manga_directory.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
        )
    }
}

private struct MangaDirectoryManagementAlertModifier: ViewModifier {
    @ObservedObject var viewModel: SystemSettingsViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                viewModel.pendingMangaDirectoryManagementConfirmation?.title ?? "",
                isPresented: confirmationIsPresented,
                presenting: viewModel.pendingMangaDirectoryManagementConfirmation
            ) { confirmation in
                // "清除", not "common.delete" ("删除") — the dialog's own
                // title/message are framed as a cleanup ("清理"), and the
                // confirm button should read as the same action, not a
                // more destructive-sounding synonym.
                Button(L10n.string("common.clear"), role: .destructive) {
                    Task {
                        _ = await viewModel.confirmMangaDirectoryManagementDeletion(confirmation)
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {
                    viewModel.cancelMangaDirectoryManagementConfirmation()
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingMangaDirectoryManagementConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    Task { @MainActor in
                        viewModel.cancelMangaDirectoryManagementConfirmation()
                    }
                }
            }
        )
    }
}

extension View {
    func mangaDirectoryManagementAlert(viewModel: SystemSettingsViewModel) -> some View {
        modifier(MangaDirectoryManagementAlertModifier(viewModel: viewModel))
    }
}
