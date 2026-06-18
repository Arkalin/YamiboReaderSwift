# ADR 0003: Manga Image Byte Cache

Date: 2026-06-18

## Status

Accepted for the post-phase 6 image loading pipeline.

## Context

Phase 6 added a UI image pipeline that decodes manga image `Data` into platform images and keeps a route-lifetime decoded image cache, but the Core/Data layer still fetched image bytes from the network on every cold route. Phase 4 intentionally left image disk caching out, so the persistent byte cache is a follow-up Core/Data concern.

## Decision

Add a disk-backed manga image byte cache as a transparent Core/Data decorator around `MangaImageDataLoading`. `YamiboMangaImageDataLoader` remains responsible for network requests, request headers, response validation, error mapping, and URL-level network request deduplication. A cached loader checks disk first, and on miss deduplicates the full miss flow by image URL within that loader instance, rechecks disk inside the miss task, performs the upstream load, writes successful non-empty bytes to disk, and returns the fetched data even if the cache write fails.

The cache identity is the exact `imageURL.absoluteString`; referer is request context only and does not participate in the cache key. Cache files use `SHA-256(imageURL.absoluteString)` with the URL path extension when present, or `.bin` otherwise. The cache is global to the app install rather than account-scoped, is not cleared on ordinary sign-out, and is cleared by `YamiboAppContext.resetApplicationData()`.

Concurrent request deduplication is intentionally scoped to one cached loader instance. The disk store does not own network in-flight coordination, and separate loader instances may still fetch the same image concurrently before one has written the shared disk cache.

Name the protocol `MangaImageDataCaching`, the concrete disk store `FileMangaImageDataCacheStore`, and the decorator `CachedMangaImageDataLoader`.

The concrete disk store uses `Application Support/YamiboReader/manga-reader/image-data/`, maintains an index with file name, byte count, and last access time, and enforces a default 512 MB LRU disk limit. A single image larger than the disk limit is returned from the network but not written to disk. Saving empty data removes any existing entry for that URL and does not write an empty file. Cache hits update in-memory access time and mark the index dirty, but do not synchronously rewrite `index.json`; later saves, trims, or explicit maintenance writes persist the updated access times. `clearAll()` deletes the image cache directory, clears in-memory state, and does not write an empty index; later saves recreate the directory and index.

Corrupt or incompatible indexes clear the image cache directory; missing, unreadable, or empty indexed files remove that index entry and are treated as cache misses. The concrete store may expose maintenance and diagnostics such as `clearAll()` and `totalDiskUsageBytes()`, but the cached loader should depend on only the narrow cache protocol it needs. The Core cache stores only bytes and does not validate MIME type or decode images; UI Presentation keeps responsibility for image decoding and decoded image memory caching.

## Rejected Alternatives

Do not add Core memory caching for image bytes. The UI pipeline already owns route-lifetime decoded image caching, and keeping another byte cache would duplicate memory use without changing persistent reuse.

Do not migrate the legacy `manga-image-cache` directory. The legacy reader is reference-only, image bytes are regenerable, and the new manga reader data path should start with a clean schema.

## Verification

Tests should split responsibilities: real disk-store tests cover persistence, hashed file names, capacity trimming, corrupt index recovery, single-entry self-healing, oversize images, empty saves, clearing, and disk usage; cached-loader tests cover hit/miss behavior, upstream failure behavior, save-failure tolerance, and URL-level concurrent miss deduplication; app-context tests cover wiring and reset cleanup.
