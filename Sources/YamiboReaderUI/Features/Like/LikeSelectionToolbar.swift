import SwiftUI
import YamiboReaderCore

/// Shared multi-select bottom bar for both My Likes list screens (works and
/// excerpts): a single destructive "delete selected" action, styled after
/// `OfflineCacheManagementSelectionToolbar`/`ActionBar`. iOS 26 renders it as
/// a system bottom-bar `ToolbarItem`; earlier systems fall back to a
/// `safeAreaInset` material bar — see `usesSystemSelectionBottomToolbar`.
struct LikeSelectionDeleteButton: View {
    let selectedCount: Int
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 22)

                Text(L10n.string("common.delete"))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 66)
            .foregroundStyle(Color.red)
            .opacity(selectedCount > 0 ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedCount == 0)
        .accessibilityLabel(L10n.string("likes.delete_selected_format", selectedCount))
    }
}

struct LikeSelectionToolbar: View {
    let selectedCount: Int
    let onDelete: () -> Void

    var body: some View {
        LikeSelectionDeleteButton(selectedCount: selectedCount, onDelete: onDelete)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

struct LikeSelectionActionBar: View {
    let selectedCount: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                LikeSelectionDeleteButton(selectedCount: selectedCount, onDelete: onDelete)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}

var likeSelectionUsesSystemBottomToolbar: Bool {
    if #available(iOS 26, *) { return true }
    return false
}
