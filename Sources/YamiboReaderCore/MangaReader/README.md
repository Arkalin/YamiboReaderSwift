# MangaReader Core Boundary

This directory is the phase 1 target boundary root for the manga reader refactor. It is intentionally documentation-only during phase 1.

Do not move existing production files here until a later phase extracts behavior behind tests.

## Domain

Pure manga reader values and rules.

Target ownership:

- **Manga Directory** value semantics.
- **Manga Chapter Document** as parsed image-page content, not raw HTML.
- **Manga Chapter Window** ordering, adjacency, trimming, and **Manga Reading Position** resolution.
- Pure chapter merge/sort rules once isolated.

Current candidate mappings:

- `Support/MangaChapterWindow.swift` -> `Domain`
- `Models/MangaChapter.swift` and manga model values -> `Domain` after reviewing cross-feature ownership

## Application

Workflow coordination that is independent of SwiftUI and WebKit.

Target ownership:

- `MangaDirectoryWorkflow`
- reader preparation and jump workflow
- progress coordination
- committed settings coordination
- image prefetch policy
- probe recovery policy through a UI adapter seam

Current candidate mappings:

- `Support/MangaReadingSession.swift` -> `Application` candidate
- mixed responsibilities from `Stores/MangaDirectoryStore.swift` -> `MangaDirectoryWorkflow`
- progress sync calls from `MangaReaderModel` -> future progress workflow

## Data

Yamibo fetches, parsing adapters, and persistence implementation.

Target ownership:

- `MangaRepository`
- `MangaHTMLParser`
- persistence-only `MangaDirectoryStore`
- `MangaImageRepository`
- `MangaImageCacheStore`

Current candidate mappings:

- `Networking/MangaRepository.swift` -> `Data`
- `Parsing/MangaHTMLParser.swift` -> `Data`
- `Stores/MangaDirectoryStore.swift` -> split into `Data` store plus `Application` workflow
- `Networking/MangaImageRepository.swift` -> `Data`
- `Support/MangaImageCacheStore.swift` -> `Data`

## Phase 1 Constraints

- No Swift protocols or placeholder public types.
- No production routing changes.
- No movement of existing files.
- No WebKit dependency in Core.
- No behavior changes.
