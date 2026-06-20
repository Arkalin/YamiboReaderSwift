import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

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
#endif
