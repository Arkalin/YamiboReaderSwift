# MangaReader

This directory owns the phase 2 manga reader rewrite UI.

The legacy reader implementation has moved to `docs/reference/manga-reader-legacy/` and is reference material only. It does not participate in package compilation.

## Phase 2 Scope

- Keep `MangaReaderView(context:appModel:)` routeable from existing app presentation.
- Keep `MangaWebFallbackView(context:appModel:)` as a placeholder for retained Web route contracts.
- Show a compiling SwiftUI skeleton with route metadata.
- Do not perform network loading, progress writes, WebKit fallback, image caching, or continuous-reading recovery.

## Target Areas

- `Presentation/`: SwiftUI-facing reader skeleton and future presentation model.
- `Chrome/`: future controls and command surfaces.
- `Directory/`: future **Manga Directory** UI.
- `Settings/`: future manga settings draft UI.
- `WebFallback/`: future Web fallback adapters and views.
