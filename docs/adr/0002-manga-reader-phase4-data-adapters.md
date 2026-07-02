# ADR 0002: Manga Reader Phase 4 Data Adapter Boundaries

Date: 2026-06-18

## Status

Accepted for the phase 4 implementation plan. The file-backed manga metadata stores described here were later superseded by the GRDB store migration; references to them are historical.

## Context

ADR 0001 defines the new manga reader boundary map and keeps HTML, network fetches, and persistence details behind Core Data repository seams. Phase 4 implements the real Data adapters for those seams after the Domain **Manga Chapter Window**, **Manga Directory**, and **Manga Chapter Document** work has landed.

The main trade-off is whether to reuse legacy manga repository/store shapes for speed or keep the new Data boundary narrow enough that later Application workflows own directory construction, merge strategy, cooldown, progress, prefetching, and UI loading state.

## Decision

Phase 4 Data adapters directly hold `YamiboClient`; they do not wrap or extend the existing `YamiboRepository` manga methods. `YamiboMangaChapterDocumentLoader` and `YamiboMangaDirectoryRepository` use `YamiboClient.fetchHTML`, compose existing parser helpers, and map content-level login/flood-control pages before returning new manga reader Domain values. `YamiboMangaImageDataLoader` builds image requests itself from the `YamiboClient` session, cookie, and user agent snapshot.

`YamiboMangaChapterDocumentLoader` returns a `MangaChapterDocument` without raw HTML. It uses the chapter URL `tid` as the canonical chapter identity, cleans the chapter title with `MangaTitleCleaner.cleanThreadTitle`, falls back to `tid` for missing titles, treats missing image URLs as a parsing failure for the current manga chapter, and tolerates missing owner post IDs by relying on the Domain fallback to `tid`.

Chapter URL normalization for Phase 4 is: use `YamiboRoute.thread(url: page: 1, authorID: nil).url`, preserve any `authorid` already present in the input URL, force `page=1`, and ensure `mobile=2` and `mod=viewthread` are present. `YamiboRoute.thread` should be hardened so duplicate query keys do not trap. This behavior must be covered by tests because it is deliberately narrower than full author filtering and deliberately stricter than preserving arbitrary input page numbers.

`YamiboMangaDirectoryRepository` returns raw directory ingredients only:

- `loadDirectorySeed(for:)` fetches the current chapter page, returns the current chapter, clean book name, tag IDs, same-page chapters, and first post ID, but does not decide `MangaDirectoryStrategy`.
- `loadTagDirectory(tagIDs:)` fetches all pages for each normalized unique tag ID sequentially, uses `YamiboDefaults.desktopTagUserAgent`, assigns stable `groupIndex` by tag order, and does not sort, merge, or deduplicate returned chapters.
- `searchDirectory(keyword:forumID:)` trims input, defaults blank forum IDs to `"30"`, follows search pagination through `searchID` when present, and does not apply cooldown, fallback, sorting, merging, or deduplication.

Remote pagination has no artificial maximum page cap in Phase 4. Requests are sequential and should check cancellation between pages. Login, flood-control, and non-2xx responses fail the operation instead of returning partial results; 2xx follow-up pages that parse to no chapters are skipped.

The phase-4 file-backed manga directory store is persistence-only. The `MangaDirectoryPersisting` protocol supports load by clean book name, load by contained chapter `tid`, save, and delete by name. The concrete store is an actor with a lazy index, uses a new manga-reader-specific directory under Application Support instead of the legacy `manga-directory` path, saves a trimmed copy of `cleanBookName`, treats missing deletes as successful no-ops, degrades safely on corrupt or missing index data, and self-heals missing or corrupt indexed directory files when possible. The concrete store may expose `clearAll()` outside the protocol so `YamiboAppContext.resetApplicationData()` can clear the new local manga reader data.

The chapter `tid` lookup is a runtime scan over directories reachable from the existing `cleanBookName -> fileName` index. It intentionally does not add a `tid -> fileName` disk index or change the directory index schema. The lookup exists so a cached **Manga Directory** can be recovered when launch context lacks a directory name but the current cached **Manga Chapter Document** has a known `tid`.

`YamiboMangaImageDataLoader` is an actor that sends user agent, cookie, optional referer, and image accept headers. It maps 401/403 to `YamiboError.notAuthenticated`, non-2xx responses to `YamiboError.invalidResponse`, empty data to `YamiboError.unreadableBody`, and offline transport errors to `YamiboError.offline`. It deduplicates in-flight requests by image URL only. Phase 4 does not implement image disk or memory caching.

`YamiboAppContext` should add narrow factories only after the concrete adapters exist. The context holds one long-lived manga directory store, while network adapters are created from the current `SessionStore` snapshot each time, matching the existing repository factory pattern.

## Rejected Alternatives

Phase 4 does not make `YamiboRepository` implement the new manga reader repository protocols. That would make the new Data seam inherit legacy method shapes and encourage adding directory seed, document loading, and image behavior to a mixed repository.

Phase 4 does not migrate the legacy `MangaDirectoryStore` responsibilities back into source. Directory initialization strategy, update fallback, search cooldown, rename/merge, and sorting are Application workflow decisions.

Phase 4 does not connect the new adapters to UI presentation or introduce an Application workflow skeleton. The phase is complete when adapters, factories, parser/route support, and focused tests are in place.

Phase 4 does not implement WebKit fallback, hidden probing, image caching, prefetch strategy, progress writes, tag-empty search fallback, or search cooldown.

## Consequences

The first implementation may fetch the same chapter page once for directory seed data and once for the chapter document. That duplication is accepted to keep Data DTOs narrow and avoid returning HTML or image payloads through `MangaDirectorySeed`.

The new directory store path avoids accidental reuse of legacy persisted state. Any legacy directory migration must be designed explicitly in a later phase.

Tests should treat request shape as part of the contract: normalized chapter URLs, preserved input `authorid`, forced page 1, cookie/user-agent propagation, tag desktop user agent, image referer behavior, login/flood priority, pagination behavior, and file-store degradation all need focused coverage.
