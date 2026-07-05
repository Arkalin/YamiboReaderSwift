import Foundation
import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaReaderCacheSheet: View {
    @StateObject private var model: MangaReaderCacheViewModel
    @State private var queueViewModel: MineHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSelecting = false
    @State private var selectedTIDs: Set<String> = []
    @State private var isQueuePresented = false
    @State private var cacheQueueBadgeFlight: MangaReaderCacheQueueBadgeFlight?

    init(
        context: MangaLaunchContext,
        panel: MangaDirectoryPanelPresentation,
        appContext: YamiboAppContext
    ) {
        _model = StateObject(
            wrappedValue: MangaReaderCacheViewModel(
                context: context,
                panel: panel,
                localFavoriteLibraryStore: appContext.localFavoriteLibraryStore,
                offlineCacheStore: appContext.offlineCacheStore,
                offlineCacheQueueControllerProvider: {
                    await appContext.makeOfflineCacheQueueExecutor()
                }
            )
        )
        _queueViewModel = State(initialValue: MineHomeViewModel(appContext: appContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage = model.errorMessage {
                        MangaReaderCacheErrorBanner(message: errorMessage)
                    }

                    MangaReaderCacheChapterSection(
                        rows: model.rows,
                        isSelecting: $isSelecting,
                        selectedTIDs: $selectedTIDs,
                        isAllSelected: selectionState.isAllSelected,
                        onToggleAll: toggleAll
                    )
                }
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
            .navigationTitle(L10n.string("manga.offline_cache.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("common.close"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    MangaNovelReaderCacheQueueToolbarButton(
                        entryCount: model.offlineCacheQueueEntryCount,
                        action: {
                            isQueuePresented = true
                        }
                    )
                }

                if isSelecting && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        MangaReaderCacheSelectionToolbar(
                            selectionState: selectionState,
                            onCache: cacheSelection,
                            onDelete: deleteSelection
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting && !usesSystemSelectionBottomToolbar {
                    MangaReaderCacheSelectionActionBar(
                        selectionState: selectionState,
                        onCache: cacheSelection,
                        onDelete: deleteSelection
                    )
                }
            }
            .sheet(isPresented: $isQueuePresented) {
                MineOfflineCacheQueueSheet(viewModel: queueViewModel)
            }
            .task {
                await model.load()
            }
            .refreshable {
                await model.refreshRows()
            }
            .onChange(of: model.allChapterTIDs) { _, validTIDs in
                selectedTIDs.formIntersection(validTIDs)
            }
            .sensoryFeedback(.selection, trigger: selectedTIDs)
            .alert(item: Binding(get: { model.prompt }, set: { _ in model.clearPrompt() })) { prompt in
                switch prompt {
                case let .addFavorite(title):
                    Alert(
                        title: Text(L10n.string("manga.offline_cache.add_favorite_title")),
                        message: Text(L10n.string("manga.offline_cache.add_favorite_message", title)),
                        dismissButton: .default(Text(L10n.string("common.ok"))) {
                            model.clearPrompt()
                        }
                    )
                }
            }
        }
        .overlayPreferenceValue(MangaReaderCacheQueueBadgeAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                MangaReaderCacheQueueBadgeFlightLayer(
                    flight: cacheQueueBadgeFlight,
                    sourceFrame: anchors[.cacheButton].map { proxy[$0] },
                    destinationFrame: anchors[.queueButton].map { proxy[$0] },
                    containerSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets,
                    onFinished: clearCacheQueueBadgeFlight
                )
            }
            .allowsHitTesting(false)
        }
    }

    private var selectionState: MangaNovelReaderCacheSelectionState {
        model.selectionState(for: selectedTIDs)
    }

    private var usesSystemSelectionBottomToolbar: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    private func toggleAll() {
        if selectionState.isAllSelected {
            selectedTIDs = []
        } else {
            selectedTIDs = model.allChapterTIDs
        }
    }

    private func cacheSelection() {
        let targets = selectedTIDs
        let uncachedSelectionCount = selectionState.uncachedSelectedTIDs.count
        Task { @MainActor in
            await model.cacheSelected(tids: targets)
            if model.errorMessage == nil, model.prompt == nil {
                cacheQueueBadgeFlight = MangaReaderCacheQueueBadgeFlight(count: uncachedSelectionCount)
                await Task.yield()
            }
            exitSelectionModeIfActionFinished()
        }
    }

    private func deleteSelection() {
        let targets = selectedTIDs
        Task {
            await model.deleteSelected(tids: targets)
            exitSelectionModeIfActionFinished()
        }
    }

    @MainActor
    private func exitSelectionModeIfActionFinished() {
        guard model.errorMessage == nil else { return }
        isSelecting = false
        selectedTIDs = []
    }

    @MainActor
    private func clearCacheQueueBadgeFlight(_ id: UUID) {
        guard cacheQueueBadgeFlight?.id == id else { return }
        cacheQueueBadgeFlight = nil
    }
}

private struct MangaReaderCacheQueueBadgeFlight: Identifiable, Equatable {
    let id = UUID()
    let count: Int
}

private enum MangaReaderCacheQueueBadgeAnchorRole: Hashable {
    case cacheButton
    case queueButton
}

private struct MangaReaderCacheQueueBadgeAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [MangaReaderCacheQueueBadgeAnchorRole: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [MangaReaderCacheQueueBadgeAnchorRole: Anchor<CGRect>],
        nextValue: () -> [MangaReaderCacheQueueBadgeAnchorRole: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct MangaReaderCacheQueueBadgeAnchorModifier: ViewModifier {
    let role: MangaReaderCacheQueueBadgeAnchorRole?

    func body(content: Content) -> some View {
        content.anchorPreference(
            key: MangaReaderCacheQueueBadgeAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            guard let role else { return [:] }
            return [role: anchor]
        }
    }
}

private extension View {
    func mangaReaderCacheQueueBadgeAnchor(
        _ role: MangaReaderCacheQueueBadgeAnchorRole?
    ) -> some View {
        modifier(MangaReaderCacheQueueBadgeAnchorModifier(role: role))
    }
}

private struct MangaReaderCacheQueueBadgeFlightLayer: View {
    let flight: MangaReaderCacheQueueBadgeFlight?
    let sourceFrame: CGRect?
    let destinationFrame: CGRect?
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let onFinished: @MainActor (UUID) -> Void

    var body: some View {
        if let flight {
            MangaReaderCacheQueueBadgeFlightView(
                flight: flight,
                source: sourcePoint,
                destination: destinationPoint,
                onFinished: onFinished
            )
        }
    }

    private var sourcePoint: CGPoint {
        if let sourceFrame {
            return CGPoint(x: sourceFrame.midX, y: max(12, sourceFrame.minY - 12))
        }

        return CGPoint(
            x: max(34, containerSize.width / 2 - 41),
            y: max(28, containerSize.height - safeAreaInsets.bottom - 76)
        )
    }

    private var destinationPoint: CGPoint {
        if let destinationFrame {
            return CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        }

        return CGPoint(
            x: max(24, containerSize.width - 42),
            y: max(24, safeAreaInsets.top + 24)
        )
    }
}

private struct MangaReaderCacheQueueBadgeFlightView: View {
    private static let flightDurationMilliseconds: UInt64 = 720
    private static let reduceMotionDurationMilliseconds: UInt64 = 180

    let flight: MangaReaderCacheQueueBadgeFlight
    let source: CGPoint
    let destination: CGPoint
    let onFinished: @MainActor (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var hasArrived = false
    @State private var didStart = false

    var body: some View {
        MangaReaderCacheQueueFlightBadge(count: flight.count)
            .scaleEffect(hasArrived ? 0.55 : 1)
            .opacity(hasArrived ? 0 : 1)
            .position(displayedPosition)
            .accessibilityHidden(true)
            .onAppear {
                startFlight()
            }
            .id(flight.id)
    }

    private var displayedPosition: CGPoint {
        if accessibilityReduceMotion {
            return source
        }
        return hasArrived ? destination : source
    }

    @MainActor
    private func startFlight() {
        guard !didStart else { return }
        didStart = true

        withAnimation(animation) {
            hasArrived = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(removalDelayMilliseconds))
            onFinished(flight.id)
        }
    }

    private var animation: Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: 0.18)
        }
        return .timingCurve(0.22, 0.86, 0.18, 1.0, duration: 0.72)
    }

    private var removalDelayMilliseconds: UInt64 {
        accessibilityReduceMotion
            ? Self.reduceMotionDurationMilliseconds
            : Self.flightDurationMilliseconds
    }
}

private struct MangaReaderCacheQueueFlightBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, count < 10 ? 0 : 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.red))
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

private struct MangaNovelReaderCacheQueueToolbarButton: View {
    let entryCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ReaderCacheDownloadQueueIcon(isActive: entryCount > 0)
                    .mangaReaderCacheQueueBadgeAnchor(.queueButton)
                Text(verbatim: "\(entryCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 12, alignment: .trailing)
            }
            .frame(minWidth: 48, minHeight: 32, alignment: .center)
            .foregroundStyle(entryCount > 0 ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string("reader.cache_queue_button_accessibility_format", entryCount)
        )
    }
}

private struct MangaReaderCacheErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
            )
    }
}

private struct MangaReaderCacheChapterSection: View {
    let rows: [MangaReaderCacheRow]
    @Binding var isSelecting: Bool
    @Binding var selectedTIDs: Set<String>
    let isAllSelected: Bool
    let onToggleAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaReaderCacheSelectionHeader(
                isSelecting: isSelecting,
                isAllSelected: isAllSelected,
                isEmpty: rows.isEmpty,
                onToggleAll: onToggleAll,
                onToggleSelectionMode: toggleSelectionMode
            )
            .frame(height: 38, alignment: .center)

            if rows.isEmpty {
                ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(rows) { row in
                        MangaReaderCacheRowView(
                            row: row,
                            isSelecting: isSelecting,
                            isSelected: selectedTIDs.contains(row.id),
                            onToggleSelection: {
                                toggleSelection(row.id)
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleSelectionMode() {
        if isSelecting {
            isSelecting = false
            selectedTIDs = []
        } else {
            isSelecting = true
        }
    }

    private func toggleSelection(_ tid: String) {
        if !isSelecting {
            isSelecting = true
            selectedTIDs.insert(tid)
            return
        }

        if selectedTIDs.contains(tid) {
            selectedTIDs.remove(tid)
        } else {
            selectedTIDs.insert(tid)
        }
    }
}

private struct MangaReaderCacheSelectionHeader: View {
    let isSelecting: Bool
    let isAllSelected: Bool
    let isEmpty: Bool
    let onToggleAll: () -> Void
    let onToggleSelectionMode: () -> Void

    var body: some View {
        HStack {
            if isSelecting {
                Button(isAllSelected ? L10n.string("common.invert_selection") : L10n.string("common.select_all")) {
                    onToggleAll()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isEmpty)
            } else {
                Text(L10n.string("manga.offline_cache.chapter_section"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(isSelecting ? L10n.string("common.done") : L10n.string("common.select")) {
                onToggleSelectionMode()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .disabled(isEmpty && !isSelecting)
        }
    }
}

private struct MangaReaderCacheRowView: View {
    let row: MangaReaderCacheRow
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(MangaChapterDisplayFormatter.displayNumber(for: row.chapter))
                .font(.caption.weight(.bold))
                .foregroundStyle(numberColor)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.chapter.rawTitle)
                    .font(.subheadline)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MangaReaderCacheStateBadge(state: row.state, isDimmed: isDimmed)
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
            onToggleSelection()
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isDimmed: Bool {
        isSelecting && !isSelected
    }

    private var titleColor: Color {
        isDimmed ? .secondary : .primary
    }

    private var numberColor: Color {
        isDimmed ? Color.secondary.opacity(0.55) : .secondary
    }
}

private struct MangaReaderCacheStateBadge: View {
    let state: MangaOfflineCacheState
    let isDimmed: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var title: String {
        switch state {
        case .cached:
            L10n.string("reader.cached")
        case .uncached:
            L10n.string("manga.offline_cache.uncached")
        case .caching:
            L10n.string("manga.offline_cache.caching")
        }
    }

    private var systemImage: String {
        switch state {
        case .cached:
            "checkmark.seal.fill"
        case .uncached:
            "icloud"
        case .caching:
            "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        if isDimmed {
            return Color.secondary.opacity(0.55)
        }
        switch state {
        case .cached:
            return Color.green
        case .uncached:
            return Color.secondary
        case .caching:
            return Color.orange
        }
    }
}

private struct MangaReaderCacheSelectionToolbar: View {
    let selectionState: MangaNovelReaderCacheSelectionState
    let onCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            toolbarButton(
                title: L10n.string("reader.cache_action.cache"),
                systemImage: "square.and.arrow.down",
                role: nil,
                isEnabled: selectionState.canCache,
                badgeAnchorRole: .cacheButton,
                action: onCache
            )
            toolbarButton(
                title: L10n.string("common.delete"),
                systemImage: "trash",
                role: .destructive,
                isEnabled: selectionState.canDelete,
                action: onDelete
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        isEnabled: Bool,
        badgeAnchorRole: MangaReaderCacheQueueBadgeAnchorRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 22)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 66)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .mangaReaderCacheQueueBadgeAnchor(badgeAnchorRole)
        .accessibilityLabel(title)
    }
}

private struct MangaReaderCacheSelectionActionBar: View {
    let selectionState: MangaNovelReaderCacheSelectionState
    let onCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            MangaReaderCacheSelectionToolbar(
                selectionState: selectionState,
                onCache: onCache,
                onDelete: onDelete
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}
#endif
