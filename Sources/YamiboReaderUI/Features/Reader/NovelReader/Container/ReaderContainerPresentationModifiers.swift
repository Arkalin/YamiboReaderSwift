import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderContainerLifecycleModifier: ViewModifier {
    let currentLayout: ReaderContainerLayout
    let onInitialTask: () async -> Void
    let onLayoutChange: (ReaderContainerLayout) -> Void
    let onMemoryWarning: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                await onInitialTask()
            }
            .onChange(of: currentLayout) { _, newValue in
                onLayoutChange(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )) { _ in
                onMemoryWarning()
            }
            .onDisappear {
                onDisappear()
            }
    }
}

struct ReaderContainerPresentationModifier: ViewModifier {
    @ObservedObject var model: ReaderContainerModel
    @Binding var showingSettings: Bool
    @Binding var showingCachePanel: Bool
    @Binding var showingCacheProgress: Bool
    @Binding var showingChapterSheet: Bool
    @Binding var showingChapterComments: Bool
    @Binding var imageBrowserItem: ReaderImageBrowserItem?

    let chapterCommentsTarget: ReaderChapterCommentTarget?
    let onJumpToChapterDirectoryChapter: (ReaderChapter) -> Void
    let onPreviewChapterDirectoryWebView: (Int) -> Void
    let onOpenOriginalPostFromComments: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showingChapterSheet) {
                ReaderChapterSheet(model: model) { chapter in
                    onJumpToChapterDirectoryChapter(chapter)
                } onSelectWebView: { view in
                    onPreviewChapterDirectoryWebView(view)
                }
            }
            .sheet(isPresented: $showingChapterComments) {
                ReaderChapterCommentsSheet(model: model, target: chapterCommentsTarget) { url in
                    onOpenOriginalPostFromComments(url)
                }
            }
            .sheet(isPresented: $showingCachePanel) {
                ReaderCachePanel(model: model) {
                    showingCachePanel = false
                    showingCacheProgress = true
                }
            }
            .sheet(
                isPresented: $showingCacheProgress,
                onDismiss: {
                    if model.hasCacheOperationSession {
                        model.hideCacheProgress()
                    }
                }
            ) {
                ReaderCacheProgressSheet(model: model) {
                    showingCacheProgress = false
                }
            }
            .fullScreenCover(item: $imageBrowserItem) { item in
                ReaderImageBrowserView(
                    url: item.url,
                    title: item.title,
                    refererURL: model.forumURL,
                    imageDataLoader: model.inlineImageLoadingContext.loader
                ) {
                    imageBrowserItem = nil
                }
                .presentationBackground(.clear)
            }
    }
}

struct ReaderContainerStateObserverModifier: ViewModifier {
    @ObservedObject var model: ReaderContainerModel
    @Binding var showingSettings: Bool
    @Binding var showingCachePanel: Bool
    @Binding var showingCacheProgress: Bool
    @Binding var showingChapterSheet: Bool
    @Binding var showingChapterComments: Bool
    @Binding var imageBrowserItem: ReaderImageBrowserItem?

    let isStatusBarHidden: Bool
    let onUpdateChromeForContentState: () -> Void
    let onRestoreVerticalPositionIfNeeded: () -> Void

    func body(content: Content) -> some View {
        content
            .statusBar(hidden: isStatusBarHidden)
            .onChange(of: model.isLoading) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: model.errorMessage) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: model.readerSurfaces.count) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: model.readerPresentation?.generation) { _, _ in
                onUpdateChromeForContentState()
                onRestoreVerticalPositionIfNeeded()
            }
            .onChange(of: model.settings.readingMode) { _, _ in
                onUpdateChromeForContentState()
                onRestoreVerticalPositionIfNeeded()
            }
            .onChange(of: showingSettings) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: showingCachePanel) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: showingCacheProgress) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: showingChapterSheet) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: showingChapterComments) { _, _ in
                onUpdateChromeForContentState()
            }
            .onChange(of: imageBrowserItem) { _, _ in
                onUpdateChromeForContentState()
            }
    }
}

struct ReaderChromeHeightObserverModifier: ViewModifier {
    @Binding var topChromeHeight: CGFloat
    @Binding var bottomChromeHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ReaderTopChromeHeightPreferenceKey.self) { value in
                guard topChromeHeight != value else { return }
                topChromeHeight = value
            }
            .onPreferenceChange(ReaderBottomChromeHeightPreferenceKey.self) { value in
                guard bottomChromeHeight != value else { return }
                bottomChromeHeight = value
            }
    }
}
#endif
