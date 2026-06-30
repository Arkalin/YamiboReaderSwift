# MangaReader Core Boundary

This directory owns the production manga reader core boundary.

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
- `MangaDirectoryWorkflow` for **Manga Directory** initialization, update, forced search, cooldown, rename, and merge rules

The core implementation supports final reader behavior through directory workflow, chapter-window updates, reading-position progress, adjacent chapter navigation, prefetch contracts, and image/cache seams. Do not reintroduce reduced staged behavior as an acceptance boundary.

## Phase 8 Directory Workflow

- **Manga Directory** initialization and remote update rules live in Core Application.
- Search cooldown is app-session state and is not persisted to disk.
- Directory update failures are non-fatal to the visible reader; the current **Manga Chapter Window** remains loaded.
- Directory changes are applied to the **Manga Chapter Window** while preserving the current **Manga Reading Position**.
- Directory search stays scoped to the manga forum (`30`) in production.

## Data

Repository seams for future implementations:

- `MangaChapterDocumentLoading`
- `MangaDirectoryRepository`
- `MangaDirectorySeed`
- `MangaDirectoryPersisting`
- `MangaImageDataLoading`

HTML parsing details belong behind repository implementations and should not leak through these seams.
