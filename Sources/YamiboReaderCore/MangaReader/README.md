# MangaReader Core Boundary

This directory owns the phase 2 manga reader rewrite boundary.

The legacy manga reader implementation has been moved to `docs/reference/manga-reader-legacy/` and is reference-only. New production code must not depend on legacy implementation classes or actors.

## Domain

Pure manga reader values and rules:

- `MangaChapter`
- `MangaDirectory`
- `MangaDirectoryStrategy`
- `MangaChapterDocument`
- `MangaChapterWindow`
- `MangaReadingPosition`

`MangaChapterDocument` represents parsed image-page content. It does not expose raw HTML.

## Application

Application-level values and projections that do not depend on SwiftUI or WebKit:

- app route contracts
- reader settings contracts
- `MangaReaderPageProjection`

Phase 2 intentionally does not implement directory workflows, continuous reading, progress writes, automatic WebKit fallback, prefetching, or image caching.

## Data

Repository seams for future implementations:

- `MangaChapterDocumentLoading`
- `MangaDirectoryRepository`
- `MangaDirectorySeed`
- `MangaDirectoryPersisting`
- `MangaImageDataLoading`

HTML parsing details belong behind repository implementations and should not leak through these seams.
