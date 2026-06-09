import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderTopChrome: View {
    private let pagedChapterTitleTopLift: CGFloat = 12

    let model: ReaderContainerModel
    let topInset: CGFloat
    let onClose: () -> Void
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: model.currentChapterTitle,
            progressText: model.progressText
        )

        ReaderGlassContainer(spacing: 12) {
            let closeButtonSize: CGFloat = 44

            ZStack {
                chapterTitleView(summary.chapterTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, closeButtonSize + 16)
                    .offset(y: shouldLiftPagedChapterTitle ? -pagedChapterTitleTopLift : 0)

                HStack {
                    Spacer(minLength: 0)
                    ReaderChromeCircleButton(
                        systemName: "xmark",
                        title: L10n.string("common.close"),
                        tint: readerChromeButtonTint(for: colorScheme),
                        action: onClose
                    )
                    .frame(width: closeButtonSize, height: closeButtonSize)
                }
            }
            .frame(maxWidth: .infinity, minHeight: closeButtonSize)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .tint(readerChromeButtonTint(for: colorScheme))
    }

    @ViewBuilder
    private func chapterTitleView(_ title: String) -> some View {
        let text = Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.primary)

        if model.settings.readingMode == .vertical {
            text
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))
        } else {
            text
                .frame(maxWidth: .infinity)
        }
    }

    private var shouldLiftPagedChapterTitle: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && model.settings.readingMode == .paged
#else
        false
#endif
    }
}

struct ReaderBottomChrome: View {
    let progressSnapshot: ReaderChromeProgressSnapshot
    let readingMode: ReaderReadingMode
    let bottomInset: CGFloat
    let isVisible: Bool
    let onShowChapters: () -> Void
    let onShowSettings: () -> Void
    let onShowCache: () -> Void
    let onShowComments: () -> Void
    let onOpenForum: () -> Void
    let onJumpChapter: (Int) -> Void
    let onProgressCommit: (Int) -> Void
    let onVerticalProgressCommit: (Int) -> Void
    let onBeginVerticalProgressScrub: () -> Void
    let onEndVerticalProgressScrub: () -> Void
    let isProgressScrubbing: Bool

    @State private var sliderState = ReaderProgressSliderState()
    @State private var scrubState = ReaderProgressScrubState()
    @State private var progressTickFeedbackGenerator = UISelectionFeedbackGenerator()
    @State private var progressStartFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @State private var progressCommitFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @State private var lastFeedbackTickStartIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            bottomControls
                .readerChromeAnchoredPopupVisibility(isVisible)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.bottom, chromeLayout.bottomControlsAdditionalBottomOffset)

            progressSummary
                .readerChromeFadeVisibility(isVisible)
                .padding(.horizontal, 12)
        }
        .padding(.top, chromeLayout.bottomChromeTopPadding)
        .padding(.bottom, max(bottomInset - 18, 8))
        .onAppear {
            sliderState.reset(to: sliderSnapshot)
        }
        .onChange(of: sliderSnapshot) { _, newValue in
            sliderState.reset(to: newValue)
        }
        .onChange(of: sliderModelValue) { _, newValue in
            sliderState.syncModelValue(newValue)
        }
    }

    private var chromeLayout: ReaderBottomChromeLayoutPresentation {
        ReaderBottomChromeLayoutPresentation()
    }

    private var bottomControls: some View {
        HStack(alignment: .top, spacing: chromeLayout.verticalScrubberSideSpacing) {
            VStack(spacing: chromeLayout.panelSpacing) {
                progressControl
                actionRow
            }
            .frame(width: chromeLayout.maxChromeWidth)

            if progressChromePresentation.showsVerticalScrubber {
                verticalProgressControl
                    .frame(width: chromeLayout.verticalScrubberWidth, alignment: .trailing)
            }
        }
        .frame(
            maxWidth: chromeLayout.maxChromeWidth + verticalProgressControlReservedWidth,
            alignment: .trailing
        )
    }

    private var verticalProgressControlReservedWidth: CGFloat {
        guard progressChromePresentation.showsVerticalScrubber else { return 0 }
        return chromeLayout.verticalScrubberSideSpacing + chromeLayout.verticalScrubberWidth
    }

    private var verticalProgressControl: some View {
        ReaderVerticalProgressCapsule(
            restingProgressFraction: progressSnapshot.currentProgressFraction,
            scrubContext: progressSnapshot.progressScrubContext,
            ticks: progressSnapshot.progressChapterTicks,
            onBeginScrub: onBeginVerticalProgressScrub,
            onCommit: onVerticalProgressCommit,
            onEndScrub: onEndVerticalProgressScrub
        )
        .frame(width: chromeLayout.verticalScrubberWidth, alignment: .trailing)
    }

    private var actionRow: some View {
        let presentation = actionRowPresentation
        return HStack(spacing: 0) {
            bottomActionButton(
                action: ReaderBottomAction(kind: .browser),
                title: L10n.string("common.original_post"),
                systemName: "safari",
                handler: onOpenForum
            )
            Spacer(minLength: chromeLayout.actionButtonSpacing)
            bottomActionButton(
                action: ReaderBottomAction(kind: .bookmark, isDisabled: true),
                title: "书签",
                systemName: "bookmark",
                handler: {}
            )
            Spacer(minLength: chromeLayout.actionButtonSpacing)
            bottomActionButton(
                action: ReaderBottomAction(kind: .cache),
                title: L10n.string("reader.cache"),
                systemName: "square.and.arrow.down",
                handler: onShowCache
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: chromeLayout.actionButtonRowHeight)
        .opacity(presentation.opacity)
        .allowsHitTesting(presentation.allowsHitTesting)
        .accessibilityHidden(presentation.isAccessibilityHidden)
    }

    private var actionRowPresentation: ReaderBottomActionRowPresentation {
        ReaderBottomActionRowPresentation(isScrubbing: isProgressScrubbing || scrubState.phase == .scrubbing)
    }

    @ViewBuilder
    private var progressSummary: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: progressSnapshot.currentChapterTitle,
            progressText: progressSnapshot.progressText
        )

        let content = VStack(spacing: 2) {
            Text(summary.pageProgressLine)
            if !summary.webProgressLine.isEmpty {
                Text(summary.webProgressLine)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.center)

        if readingMode == .vertical {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .readerChromePanel(cornerRadius: 16, tint: readerChromePanelTint(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func bottomActionButton(
        action: ReaderBottomAction,
        title: String,
        systemName: String,
        handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: chromeLayout.actionButtonIconFrame, height: chromeLayout.actionButtonIconFrame)
        }
        .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
        .opacity(action.isDisabled ? 0.34 : 1)
        .disabled(action.isDisabled)
        .accessibilityLabel(title)
    }

    private var progressControl: some View {
        VStack(spacing: chromeLayout.panelSpacing) {
            if let preview = scrubState.preview, scrubState.phase == .scrubbing {
                ReaderVerticalProgressPreviewCapsule(preview: preview)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ReaderDirectoryProgressCapsule(
                title: progressChromePresentation.horizontalCapsuleText(percentText: progressSnapshot.currentProgressPercentText),
                progressFraction: displayedProgressFraction,
                showsFill: progressChromePresentation.showsHorizontalFill,
                supportsScrub: progressChromePresentation.supportsHorizontalScrub && sliderHasAvailableRange,
                isScrubbing: scrubState.phase == .scrubbing,
                ticks: progressSnapshot.progressChapterTicks,
                onTapDirectory: onShowChapters,
                onScrub: { locationX, width in
                    handleHorizontalCapsuleScrub(locationX: locationX, width: width)
                },
                onEndScrub: {
                    commitHorizontalCapsuleScrub()
                }
            )
            .opacity(shouldHideDirectoryCapsule ? 0 : 1)
            .allowsHitTesting(!shouldHideDirectoryCapsule)
            .accessibilityHidden(shouldHideDirectoryCapsule)

            secondaryCapsuleButton(
                title: L10n.string("reader.comments"),
                systemName: "text.bubble",
                action: onShowComments
            )

            secondaryCapsuleButton(
                title: L10n.string("settings.title"),
                systemName: "gearshape",
                action: onShowSettings
            )
        }
    }

    private func secondaryCapsuleButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        let presentation = actionRowPresentation
        let controlTint = chromeLayout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor

        return Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 12)
                Image(systemName: systemName)
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(chromeLayout.directoryCapsuleContentUsesAccentColor ? controlTint : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: chromeLayout.progressPanelHeight)
            .padding(.horizontal, 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))
        .opacity(presentation.opacity)
        .allowsHitTesting(presentation.allowsHitTesting)
        .accessibilityHidden(presentation.isAccessibilityHidden)
        .accessibilityLabel(title)
    }

    private var shouldHideDirectoryCapsule: Bool {
        chromeLayout.hidesDirectoryCapsuleDuringVerticalScrub
            && readingMode == .vertical
            && isProgressScrubbing
    }

    private var progressChromePresentation: ReaderProgressChromePresentation {
        ReaderProgressChromePresentation(readingMode: readingMode, isChromeVisible: true)
    }

    private var sliderRange: ClosedRange<Double> {
        if readingMode == .vertical {
            0 ... 100
        } else {
            0 ... Double(max(progressSnapshot.surfaceCount - 1, 0))
        }
    }

    private var sliderModelValue: Double {
        if readingMode == .vertical {
            Double(progressSnapshot.currentProgressPercent)
        } else {
            Double(max(progressSnapshot.currentSurfaceNumber - 1, 0))
        }
    }

    private var sliderSnapshot: ReaderProgressSliderSnapshot {
        ReaderProgressSliderSnapshot(
            readingMode: readingMode,
            visibleView: progressSnapshot.visibleView,
            surfaceCount: progressSnapshot.surfaceCount,
            currentSurfaceNumber: progressSnapshot.currentSurfaceNumber,
            currentProgressPercent: progressSnapshot.currentProgressPercent
        )
    }

    private var sliderHasAvailableRange: Bool {
        sliderRange.lowerBound < sliderRange.upperBound
    }

    private var displayedProgressFraction: Double {
        if scrubState.phase == .scrubbing {
            guard progressSnapshot.surfaceCount > 1 else { return 0 }
            return Double(scrubState.targetSurfaceIndex) / Double(max(progressSnapshot.surfaceCount - 1, 1))
        }
        return progressSnapshot.currentProgressFraction
    }

    private var progressLabelText: String {
        progressSnapshot.progressSliderLabelText(
            isEditing: sliderState.isEditing,
            sliderValue: sliderState.sliderValue,
            targetSurfaceIndex: sliderTargetSurfaceIndex
        )
    }

    private var sliderTargetSurfaceIndex: Int {
        progressSnapshot.targetSurfaceIndex(forProgressValue: sliderState.sliderValue)
    }

    private var scrubContext: ReaderProgressScrubContext {
        progressSnapshot.progressScrubContext
    }

    private func handleHorizontalCapsuleScrub(locationX: CGFloat, width: CGFloat) {
        guard progressChromePresentation.supportsHorizontalScrub, width > 0 else { return }
        let fraction = min(max(locationX / width, 0), 1)
        let value = sliderRange.lowerBound + Double(fraction) * (sliderRange.upperBound - sliderRange.lowerBound)
        let update = scrubState.update(value: value, context: scrubContext)
        triggerFeedback(update.haptics)
    }

    private func commitHorizontalCapsuleScrub() {
        guard scrubState.phase == .scrubbing else { return }
        let update = scrubState.end()
        triggerFeedback(update.haptics)
        if let target = update.committedSurfaceIndex {
            onProgressCommit(target)
        }
        sliderState.sliderValue = sliderModelValue
    }

    private func triggerFeedback(_ haptics: [ReaderProgressScrubHaptic]) {
        for haptic in haptics {
            switch haptic {
            case .start:
                progressStartFeedbackGenerator.impactOccurred()
                progressStartFeedbackGenerator.prepare()
                progressTickFeedbackGenerator.prepare()
            case .chapterTick:
                progressTickFeedbackGenerator.selectionChanged()
                progressTickFeedbackGenerator.prepare()
            case .commit:
                progressCommitFeedbackGenerator.impactOccurred()
                progressCommitFeedbackGenerator.prepare()
            }
        }
    }

    private func triggerProgressTickFeedbackIfNeeded() {
        guard let tickStartIndex = progressSnapshot.progressChapterTickStartIndex(forSurfaceIndex: sliderTargetSurfaceIndex) else {
            lastFeedbackTickStartIndex = nil
            return
        }
        guard lastFeedbackTickStartIndex != tickStartIndex else { return }

        progressTickFeedbackGenerator.selectionChanged()
        progressTickFeedbackGenerator.prepare()
        lastFeedbackTickStartIndex = tickStartIndex
    }
}

private struct ReaderProgressChapterTickOverlay: View {
    let ticks: [ReaderProgressChapterTick]
    let currentTint: Color

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        GeometryReader { geometry in
            ForEach(Array(ticks.enumerated()), id: \.element.chapter.startIndex) { _, tick in
                Capsule()
                    .fill(tick.isCurrent ? currentTint : Color.secondary.opacity(0.38))
                    .frame(width: tick.isCurrent ? 3 : 2, height: tick.isCurrent ? 12 : 8)
                    .position(
                        x: layout.capsuleChapterTickCoordinate(
                            position: tick.position,
                            length: geometry.size.width,
                            edgeInset: layout.capsuleChapterTickRoundedEdgeInset
                        ),
                        y: geometry.size.height / 2
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct ReaderDirectoryProgressCapsule: View {
    let title: String
    let progressFraction: Double
    let showsFill: Bool
    let supportsScrub: Bool
    let isScrubbing: Bool
    let ticks: [ReaderProgressChapterTick]
    let onTapDirectory: () -> Void
    let onScrub: (CGFloat, CGFloat) -> Void
    let onEndScrub: () -> Void
    @State private var dragStartProgressFraction: Double?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let layout = ReaderBottomChromeLayoutPresentation()
            let controlTint = layout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor
            let width = max(geometry.size.width, 1)
            let clampedProgress = min(max(progressFraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))

                if showsFill {
                    Rectangle()
                        .fill(controlTint.opacity(colorScheme == .dark ? 0.24 : 0.18))
                        .frame(
                            width: layout.capsuleProgressFillExtent(
                                position: clampedProgress,
                                length: width,
                                edgeInset: layout.capsuleChapterTickRoundedEdgeInset
                            )
                        )
                        .accessibilityHidden(true)
                }

                ReaderProgressChapterTickOverlay(ticks: ticks, currentTint: controlTint)
                    .opacity(showsChapterTicks(layout: layout) ? 1 : 0)

                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 12)
                    Image(systemName: "list.bullet")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(layout.directoryCapsuleContentUsesAccentColor ? controlTint : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .opacity(layout.horizontalDirectoryContentHiddenWhileScrubbing && isScrubbing ? 0 : 1)
            }
            .frame(height: 44)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))
            .gesture(scrubGesture(width: width), including: supportsScrub ? .gesture : .subviews)
            .onTapGesture(perform: onTapDirectory)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityHint(L10n.string("reader.chapters"))
        }
        .frame(height: ReaderBottomChromeLayoutPresentation().progressPanelHeight)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard supportsScrub else { return }
                if dragStartProgressFraction == nil {
                    dragStartProgressFraction = progressFraction
                }
                let targetFraction = ReaderProgressDragMapping.value(
                    startProgressFraction: dragStartProgressFraction ?? progressFraction,
                    translation: value.translation.width,
                    length: width,
                    range: 0...1
                )
                onScrub(CGFloat(targetFraction) * width, width)
            }
            .onEnded { _ in
                guard supportsScrub else { return }
                dragStartProgressFraction = nil
                onEndScrub()
            }
    }

    private func showsChapterTicks(layout: ReaderBottomChromeLayoutPresentation) -> Bool {
        let canShowTicks = showsFill || layout.directoryChapterTicksDoNotRequireProgressFill
        return canShowTicks && (!layout.horizontalChapterTicksVisibleOnlyWhileScrubbing || isScrubbing)
    }
}

struct ReaderVerticalProgressCapsule: View {
    let restingProgressFraction: Double
    let scrubContext: ReaderProgressScrubContext
    let ticks: [ReaderProgressChapterTick]
    let onBeginScrub: () -> Void
    let onCommit: (Int) -> Void
    let onEndScrub: () -> Void
    @State private var dragStartProgressFraction: Double?
    @State private var scrubState = ReaderProgressScrubState()
    @State private var progressStartFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @State private var progressTickFeedbackGenerator = UISelectionFeedbackGenerator()
    @State private var progressCommitFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let preview = scrubState.preview
        let totalWidth = isScrubbing ? layout.verticalPreviewWidth + layout.verticalScrubberSideSpacing + layout.verticalScrubberWidth : layout.verticalScrubberWidth

        GeometryReader { geometry in
            let height = max(geometry.size.height, 1)
            let clampedProgress = min(max(displayedProgressFraction, 0), 1)
            let thumbY = min(max(height * clampedProgress, 0), height)

            ZStack(alignment: .topTrailing) {
                verticalProgressBar(height: height, thumbY: thumbY)
                    .frame(width: layout.verticalScrubberWidth, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                if isScrubbing, let preview {
                    ReaderVerticalProgressPreviewCapsule(preview: preview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: min(max(thumbY - layout.verticalPreviewHeight / 2, 0), max(height - layout.verticalPreviewHeight, 0)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.size.width, height: height, alignment: .topTrailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartProgressFraction == nil {
                            dragStartProgressFraction = displayedProgressFraction
                        }
                        let targetFraction = ReaderProgressDragMapping.value(
                            startProgressFraction: dragStartProgressFraction ?? displayedProgressFraction,
                            translation: value.translation.height,
                            length: height,
                            range: 0...1
                        )
                        updateScrub(value: targetFraction * 100)
                    }
                    .onEnded { _ in
                        dragStartProgressFraction = nil
                        commitScrub()
                    }
            )
            .accessibilityLabel("目录 · 进度")
        }
        .frame(width: totalWidth)
        .frame(height: layout.verticalScrubberHeight)
    }

    private var displayedProgressFraction: Double {
        if scrubState.phase == .scrubbing {
            guard scrubContext.surfaceCount > 1 else { return 0 }
            return Double(scrubState.targetSurfaceIndex) / Double(max(scrubContext.surfaceCount - 1, 1))
        }
        return restingProgressFraction
    }

    private var isScrubbing: Bool {
        scrubState.phase == .scrubbing
    }

    private func updateScrub(value: Double) {
        let wasScrubbing = scrubState.phase == .scrubbing
        let update = scrubState.update(value: value, context: scrubContext)
        if !wasScrubbing, scrubState.phase == .scrubbing {
            onBeginScrub()
        }
        triggerFeedback(update.haptics)
    }

    private func commitScrub() {
        guard scrubState.phase == .scrubbing else {
            scrubState.reset()
            onEndScrub()
            return
        }
        let update = scrubState.end()
        triggerFeedback(update.haptics)
        if let target = update.committedSurfaceIndex {
            onCommit(target)
        }
        scrubState.reset()
        onEndScrub()
    }

    private func triggerFeedback(_ haptics: [ReaderProgressScrubHaptic]) {
        for haptic in haptics {
            switch haptic {
            case .start:
                progressStartFeedbackGenerator.impactOccurred()
                progressStartFeedbackGenerator.prepare()
                progressTickFeedbackGenerator.prepare()
            case .chapterTick:
                progressTickFeedbackGenerator.selectionChanged()
                progressTickFeedbackGenerator.prepare()
            case .commit:
                progressCommitFeedbackGenerator.impactOccurred()
                progressCommitFeedbackGenerator.prepare()
            }
        }
    }

    private func verticalProgressBar(height: CGFloat, thumbY: CGFloat) -> some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let controlTint = layout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor

        return ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))

            if layout.verticalScrubberShowsProgressFill {
                Rectangle()
                    .fill(controlTint.opacity(colorScheme == .dark ? 0.24 : 0.18))
                    .frame(
                        width: layout.verticalScrubberWidth,
                        height: layout.capsuleProgressFillExtent(
                            position: min(max(thumbY / max(height, 1), 0), 1),
                            length: height,
                            edgeInset: layout.capsuleChapterTickRoundedEdgeInset
                        )
                    )
                    .accessibilityHidden(true)
            }

            ReaderVerticalProgressChapterTickOverlay(ticks: ticks, currentTint: controlTint)
                .opacity(layout.verticalScrubberShowsChapterTicks && (!layout.verticalChapterTicksVisibleOnlyWhileScrubbing || isScrubbing) ? 1 : 0)

            if layout.verticalScrubberShowsLiveThumb {
                Capsule()
                    .fill(controlTint.opacity(0.82))
                    .frame(width: 28, height: 3)
                    .offset(x: -18, y: min(max(thumbY - 1.5, 0), height - 3))
                    .accessibilityHidden(true)
            }
        }
        .mask(Capsule())
    }
}

private struct ReaderVerticalProgressChapterTickOverlay: View {
    let ticks: [ReaderProgressChapterTick]
    let currentTint: Color

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        GeometryReader { geometry in
            ForEach(Array(ticks.enumerated()), id: \.element.chapter.startIndex) { _, tick in
                Capsule()
                    .fill(tick.isCurrent && layout.verticalCurrentChapterTickUsesAccentColor ? currentTint : Color.secondary.opacity(0.38))
                    .frame(width: tick.isCurrent ? 28 : 18, height: tick.isCurrent ? 3 : 2)
                    .position(
                        x: layout.verticalScrubberTicksAreCentered ? geometry.size.width / 2 : geometry.size.width - 24,
                        y: layout.capsuleChapterTickCoordinate(
                            position: tick.position,
                            length: geometry.size.height,
                            edgeInset: layout.capsuleChapterTickRoundedEdgeInset
                        )
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReaderVerticalProgressPreviewCapsule: View {
    let preview: ReaderProgressScrubPreview

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let chapterTitle = preview.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(spacing: 2) {
            Text(chapterTitle?.isEmpty == false ? chapterTitle! : "目录")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("第\(preview.pageNumber)页")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .frame(width: layout.verticalPreviewWidth, height: layout.verticalPreviewHeight)
            .readerChromePanel(cornerRadius: 24, tint: Color.accentColor.opacity(0.08))
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

struct ReaderChromeIconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
        }
        .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
        .accessibilityLabel(title)
    }
}

struct ReaderChromeCircleButton: View {
    let systemName: String
    let title: String
    var tint: Color
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
        }
        .buttonBorderShape(.circle)
        .readerChromeButtonStyle(prominent: prominent, tint: tint)
        .accessibilityLabel(title)
    }
}

struct ReaderToolbarIconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel(title)
    }
}

func readerChromePanelTint(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.18)
}

func readerChromeButtonTint(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(red: 0.78, green: 0.58, blue: 0.42) : .accentColor
}
#endif
