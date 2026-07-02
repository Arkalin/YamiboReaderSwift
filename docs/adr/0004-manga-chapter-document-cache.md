# ADR 0004: Manga Chapter Document Cache

Date: 2026-06-18

## Status

Accepted for the post-image-byte-cache manga reader pipeline. The original file-backed chapter document store was later superseded by the GRDB store migration.

## Context

The manga reader now caches image bytes, but opening a chapter still fetches the chapter HTML so `YamiboMangaChapterDocumentLoader` can parse the image URL list. ADR 0001 and ADR 0002 require the new manga reader Data seams to return parsed **Manga Chapter Document** values without exposing raw HTML.

## Decision

Add a persistent Core/Data cache for parsed **Manga Chapter Document** values. `YamiboMangaChapterDocumentLoader` remains responsible for network HTML fetch, Yamibo response validation, and parsing. A new `CachedMangaChapterDocumentLoader` wraps `MangaChapterDocumentLoading`, checks a `MangaChapterDocumentPersisting` store first, and on cache miss deduplicates the full miss flow by normalized chapter URL within that loader instance. The miss task checks the store a second time before loading upstream, then saves the parsed document. Cache save failures do not fail the current load.

The cache key is `MangaReaderDataSupport.normalizedChapterURL(url).absoluteString`, not chapter `tid` or **Manga Directory** name. The store persists JSON files named `manga_chapter_document_<sha256>.json` under `Application Support/YamiboReader/manga-reader/chapter-documents/`. It is app-install scoped, is not cleared on ordinary sign-out, and is cleared by `YamiboAppContext.resetApplicationData()`.

The store normalizes the persisted `chapterURL` to the cache URL when saving. On read, if the normalized URL contains a `tid`, the cached document's `tid` must match it; mismatches remove that entry and are treated as misses. Request deduplication is intentionally scoped to a single cached loader instance; the store does not own network in-flight coordination.

Cache hits are authoritative: they return the cached **Manga Chapter Document** without fetching chapter HTML or refreshing in the background. There is no TTL. If upstream loading fails after a miss, the cached loader checks the store one final time and returns that document if one has appeared; otherwise it rethrows the original error.

The document cache does not change **Manga Directory** resolution. A fully offline current-chapter open still requires both a cached **Manga Chapter Document** and a locally available **Manga Directory** for the current context; this ADR does not change directory fallback behavior.

The concrete store does not need an LRU or disk limit because parsed document JSON is small compared with image byte data. It exposes `clearAll()` and concrete-only diagnostics such as `totalDiskUsageBytes()`. Corrupt or incompatible indexes clear the whole document cache directory; missing, unreadable, undecodable, or invalid indexed documents remove that entry and are treated as misses. A loaded cached document is valid only if `tid`, `chapterTitle`, and `imageURLs` are non-empty.

## Verification

Tests should split responsibilities: store tests cover normalized URL keys, SHA-256 file names, persisted URL normalization, corrupt index recovery, single-entry self-healing, `tid` mismatch rejection, clearing, and disk usage; cached-loader tests cover hit/miss behavior, URL-level concurrent miss deduplication, upstream failure fallback, save-failure tolerance, and task-internal cache rechecks; app-context tests cover factory wiring and reset cleanup.

## Rejected Alternatives

Do not cache raw chapter HTML. Raw HTML parsing remains hidden behind Data adapters, and **Manga Chapter Document** is the boundary value.

Do not fold chapter documents into the manga directory store. A **Manga Directory** is the ordered chapter list for a title, while a **Manga Chapter Document** is parsed image-page content for one chapter; they share lifecycle but not identity.

Do not add automatic background refresh or TTL without a product requirement. Either would reintroduce chapter HTML requests even when the document is cached.
