# Nuke DataCache for regenerable images

YamiboReader will use Nuke's image loading pipeline with Nuke `DataCache` for regenerable remote images instead of preserving the app-owned **Transparent Image Data Cache** semantics from ADR 0041. This means the former `FileImageDataCacheStore` identity, GRDB metadata, namespace-specific persistent keys, protected avatar retention, and settings-level transparent-cache diagnostics are no longer product requirements for ordinary regenerable images; they may be removed or reduced to adapters around Nuke where useful. **Manga Offline Cache** is explicitly out of scope for this replacement and remains user-retained offline content that must not depend on Nuke's reclaimable cache.

## Status

Accepted. Supersedes ADR 0041.

## Consequences

The implementation should treat Nuke as the owner of the ordinary remote image cache policy and should actively configure Nuke `DataCache` rather than relying only on the default `URLCache` path, while preserving explicit offline-cache membership, queue state, offline image bytes, and storage controls for **Manga Offline Cache**. The dedicated Yamibo image pipeline should make `DataCache` the ordinary-image disk cache and disable or minimize URLSession `URLCache` disk storage for that same pipeline so ordinary images are not duplicated across two disk cache layers. The first Nuke migration should not make **Manga Offline Cache** acquisition depend on copying bytes from Nuke's ordinary cache; offline acquisition should fetch or otherwise obtain its own bytes and write them to offline storage, with any future Nuke-cache reuse treated only as an optimization. Any "clear image cache" UI should be redefined around Nuke's cache behavior and must remain separate from offline manga cleanup.

The first Nuke `DataCache` budget should be 512 MB. This carries forward the app's previous ordinary-image disk budget expectation without preserving the old GRDB-backed namespace, retention-policy, or protected-avatar semantics.

Nuke should remain behind YamiboReader's image loading seams rather than spreading Nuke request and pipeline types through feature code. Callers should keep using project-owned interfaces such as `YamiboImageDataLoading`, `MangaImageDataLoading`, and UI image adapters; Nuke-backed adapters translate those requests, authentication headers, referer behavior, error mapping, cache clearing, and display integration internally.

The app-owned shared facade should keep the existing `YamiboImagePipeline` name while becoming Nuke-backed internally. The implementation should use one shared ordinary-image pipeline rather than long-lived per-account pipelines.

The Nuke migration should remove cache namespace inputs rather than preserving them as compatibility fields. `YamiboImageRequest.cacheNamespace`, `YamiboImageCacheNamespace`, `NovelInlineImageCacheNamespace`, and environment/loading contexts that exist only to thread ordinary-image cache namespaces should be deleted or reshaped during the migration.

`Referer` remains request context only. Nuke-backed adapters should send it as an HTTP header when needed, but ordinary image cache identity should stay URL-based and should not reintroduce referer-scoped persistent cache keys.

The package dependency boundary follows the same split: `YamiboReaderCore` may depend on Nuke for request loading, raw-byte access, cache ownership, and adapter implementation, while `YamiboReaderUI` may depend on NukeUI only for SwiftUI/UIKit display adapters. NukeUI must not become a Core dependency.

The package dependency should be exact-pinned to the current latest Nuke release at implementation planning time. As of 2026-07-03, that version is `13.0.6`; `Package.swift` should use an exact package requirement for `https://github.com/kean/Nuke` and consume the `Nuke` and `NukeUI` products from that same pinned version. The root package manifest should also move from `swift-tools-version: 6.0` to `6.2` with the Nuke dependency addition.

The Nuke migration follows ADR 0044's platform decision: the package no longer needs to preserve macOS 14 support. Nuke-backed image adapters and UI display integration may be implemented for the supported iOS package surface instead of maintaining macOS-specific image paths.

The repository-wide iOS-only cleanup from ADR 0044 should land before the Nuke migration begins.

The settings surface may keep a user-facing "clear image cache" action, but it should clear Nuke's ordinary image caches rather than a YamiboReader-owned GRDB image-cache store. The app no longer requires precise ordinary-image-cache disk-usage accounting; if Nuke cannot expose reliable usage, the settings UI should avoid presenting exact bytes. Resetting application data should clear Nuke's ordinary image caches and **Manga Offline Cache**, while the ordinary-image-cache clear action must not delete offline manga content. Login-state changes and sign out do not need special Nuke cache-clearing behavior beyond whatever explicit reset or user cache-clear action is invoked.

Raw image bytes remain a project-owned interface requirement for saving images, sharing images, and writing **Manga Offline Cache** bytes. Nuke-backed adapters may reuse original response data from Nuke when that is stable and available, but raw-byte correctness must not depend on a Nuke display-cache hit; adapters may perform an authenticated network load for bytes without reintroducing `FileImageDataCacheStore` or another YamiboReader-owned persistent ordinary-image byte cache.

Tests should move away from the superseded namespace/session-isolation contract. Namespace-specific and GRDB `FileImageDataCacheStore` behavior tests should be removed or replaced with behavior tests for the new contract: URL-based Nuke cache behavior through YamiboReader seams, `Referer` header injection, raw-byte fallback, explicit image-cache clear/reset behavior, and **Manga Offline Cache** independence from Nuke's ordinary cache.

## Implementation Order

1. Complete the repository-wide iOS-only cleanup from ADR 0044.
2. Add Nuke 13.0.6 with `swift-tools-version: 6.2`, then introduce the Nuke-backed `YamiboImagePipeline` facade and Core adapters with a 512 MB Nuke `DataCache`.
3. Migrate image call sites and delete the superseded namespace and `FileImageDataCacheStore` wiring, while keeping **Manga Offline Cache** byte acquisition independent.
4. Update settings behavior and replace the old namespace/GRDB image-cache tests with tests for the new Nuke-backed contract.
