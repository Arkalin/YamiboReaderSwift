# MangaReader

This directory owns the manga reader UI.

The legacy reader implementation has moved to `docs/reference/manga-reader-legacy/` and is reference material only. It does not participate in package compilation.

## Current Surface

- `MangaReaderView(context:appModel:)` is the native reader route from existing app presentation.
- `MangaWebFallbackView(context:appModel:)` is a real Web fallback backed by `ForumBrowserView`, not a diagnostic placeholder.
- Route contracts must preserve manga launch, native/Web suspension, and continuity behavior while the reader evolves.
- New work should target user-visible final behavior rather than phase scaffolding.

## Current Implementation Contract

- The reader is a production native manga surface with real loading, presentation, navigation, and progress behavior.
- iOS viewports are native UIKit-backed presentation surfaces hosted from SwiftUI. Non-iOS builds may compile without exposing the interactive manga reader.
- The UI owns decoded image lifetime for one reader route while image bytes stay behind `MangaImageDataLoading`.
- Image pipelines cache successful decoded images, de-duplicate in-flight image loads by image URL, and do not cache failures.
- **MangaReaderWorkflow** owns the current **Manga Chapter Window**, adjacent chapter movement, directory updates, and page-level **Manga Reading Position**.
- Reader progress and resume state are written only from real **Manga Reading Position** updates, never from placeholder state.
- Vertical reading reports the current page from visible page geometry. Paged reading owns its own page/spread plan and does not replace page-level progress with spread identity.
- Page cells are sized from decoded image aspect ratio with stable placeholder geometry before image decode.
- New work should extend final user-visible reading behavior, not reintroduce phase scaffolding or diagnostic fallback routes.

## Target Areas

- `Presentation/`: SwiftUI-facing reader surface and presentation model.
- `Chrome/`: future controls and command surfaces.
- `Directory/`: future **Manga Directory** UI.
- `Settings/`: future manga settings draft UI.
- `WebFallback/`: retained Web fallback adapters and views.
