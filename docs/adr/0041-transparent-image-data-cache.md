# ADR 0041: Transparent Image Data Cache

Date: 2026-07-02

## Status

Superseded by ADR 0043. This originally superseded ADR 0003's manga-only persistent image byte cache scope while preserving ADR 0003's transparent-cache semantics.

## Context

The app now has multiple image-loading paths that share `YamiboImageRequest` identity: manga pages, novel inline images, and generic remote images. Keeping the persistent byte cache named and keyed as `manga_image_data_cache` would make manga the accidental owner of regenerable image bytes that are useful outside the manga reader.

## Decision

Promote the manga transparent image byte cache to the app-wide **Transparent Image Data Cache**. The persistent identity is `namespace + image_url`; `referer_url` remains network request context and does not participate in the cache key. Manga images, novel inline images, and generic remote images use a session-derived namespace based on cookie and user agent rather than a fixed manga namespace. Profile avatars use a separate session-derived avatar namespace, such as `avatar:<hash>`, so protected avatar entries cannot overwrite ordinary evictable entries for the same URL.

The first app-wide cache implementation should wrap the generic `YamiboImageDataLoading` path with a reusable cached loader, so manga images, novel inline images, generic `YamiboRemoteImage` consumers, and profile avatars can share the same disk-backed byte cache. Profile avatars are included in the first migration but are not subject to LRU eviction.

The cache keeps one shared global LRU budget, initially 512 MB, across evictable entries. It remains a transparent, regenerable cache: it is separate from decoded in-memory image caching and from user-retained offline content such as **Manga Offline Cache**.

The app-wide cache module belongs under `YamiboReaderCore/Common/Image`, next to `YamiboImageRequest` and `YamiboImageDataLoading`, rather than under manga reader data. It should use non-manga names such as `YamiboImageDataCaching`, `FileImageDataCacheStore`, and `CachedYamiboImageDataLoader`; manga-specific names should remain only where manga offline-cache semantics are involved.

The persistent index stays intentionally small: `namespace`, `image_url`, `file_name`, `byte_count`, `last_accessed_at`, and `retention_policy`, with `(namespace, image_url)` as identity. It should not store referer, MIME type, image dimensions, or source-kind metadata. Files live under `image-data/<namespace-hash>/`, where the directory name is derived from the namespace instead of using the raw namespace as a file-system segment. File names derive from the full persistent key so namespace changes are explicit in storage layout.

`retention_policy` starts with `evictable` and `protected`. Manga, novel inline, and generic remote images use `evictable`; profile avatars use `protected`, so they can be reset or explicitly cleared but are skipped by normal LRU trimming. The 512 MB LRU budget counts and trims only evictable entries; protected bytes may appear in total disk diagnostics but do not contribute to the eviction threshold.

Protected entries are not cleared by ordinary sign-out. `YamiboAppContext.resetApplicationData()` clears all **Transparent Image Data Cache** entries and files, including protected avatar bytes.

The storage settings surface should expose a user-visible "clear image cache" action for the **Transparent Image Data Cache**. That action clears both evictable and protected transparent image bytes, but it does not delete **Manga Offline Cache**, favorite background images, reader document caches, or user-owned data.

The settings UI should replace the old manga-only image cache row with this app-wide image cache row. The row displays total **Transparent Image Data Cache** disk usage only, without exposing evictable/protected policy details to users.

Clearing image cache from settings clears disk-backed **Transparent Image Data Cache** bytes only. It does not promise to clear decoded in-memory images already held by the UI image pipeline.

Verification should cover the Core cache store, the generic cached loader, app-context wiring for reader, generic remote-image, and avatar paths, and settings ViewModel behavior for total usage and clear-image-cache isolation.

The app has not shipped with the old `manga_image_data_cache_entries` cache, so the first app-wide implementation does not need to migrate, clear, or read old manga-only transparent cache records or files.

## Consequences

`Manga Offline Cache` behavior does not change. Manga image loading still prefers matching offline membership bytes before the **Transparent Image Data Cache** and network. Transparent cache hits must not make a manga chapter count as offline cached.

The manga image loading interface may remain in the first migration, but it should become a thin adapter that owns only manga-specific offline-first behavior and delegates transparent cache reads and writes to the generic cached image data loader.
