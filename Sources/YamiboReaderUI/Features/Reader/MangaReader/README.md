# MangaReader

This directory owns the phase 2 manga reader rewrite UI.

The legacy reader implementation has moved to `docs/reference/manga-reader-legacy/` and is reference material only. It does not participate in package compilation.

## Phase 2 Scope

- Keep `MangaReaderView(context:appModel:)` routeable from existing app presentation.
- Keep `MangaWebFallbackView(context:appModel:)` as a placeholder for retained Web route contracts.
- Show a compiling SwiftUI skeleton with route metadata.
- Do not perform network loading, progress writes, WebKit fallback, image caching, or continuous-reading recovery.

## Phase 6 Vertical Viewport Plan

- Implement the real vertical manga viewport for iOS only. Non-iOS builds should continue to compile without exposing a manga reader fallback view.
- Replace the loaded diagnostic page list with a UIKit `UICollectionView` hosted by `UIViewRepresentable`.
- Use `UICollectionViewCompositionalLayout`; do not implement the vertical viewport with SwiftUI `ScrollView` or `LazyVStack`.
- Own the UI image pipeline from `MangaReaderModel` for the lifetime of one reader route.
- Keep image bytes behind `MangaImageDataLoading`; decode `Data` into `UIImage` in UI Presentation.
- Cache successful decoded images with `NSCache<NSString, UIImage>` and de-duplicate in-flight image loads by image URL.
- Do not cache image failures. Cells should show a lightweight failure state and retry should issue a fresh pipeline request.
- Let `MangaReaderWorkflow` retain the current **Manga Chapter Window** after prepare and expose an in-memory move-to-loaded-page operation.
- Update **Manga Reading Position** only in memory during Phase 6. Do not write manga progress or resume state.
- Report the current page from the viewport by the largest visible page area, breaking ties toward the page closest to the viewport top.
- On first display, land directly on the prepared current page after first layout without animation; hide the collection view until that initial placement is complete.
- Size page cells from decoded image aspect ratio, using an estimated placeholder height before image decode.
- Use a conventional `UICollectionViewDataSource`, matching the existing reader viewport style.
- Do not add explicit image prefetching, zoom gestures, paged mode, two-page mode, adjacent chapter loading, WebKit fallback, or diagnostic route details in Phase 6.

## Target Areas

- `Presentation/`: SwiftUI-facing reader skeleton and future presentation model.
- `Chrome/`: future controls and command surfaces.
- `Directory/`: future **Manga Directory** UI.
- `Settings/`: future manga settings draft UI.
- `WebFallback/`: future Web fallback adapters and views.
