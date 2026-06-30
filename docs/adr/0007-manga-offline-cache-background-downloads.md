# ADR 0007: Manga Offline Cache Background Downloads

Date: 2026-06-28

## Status

Proposed for the manga offline cache queue.

## Context

The **Manga Offline Cache Queue** must continue user-started manga image downloads while the app is backgrounded, but it must not promise progress after the user force-quits the app. The queue also needs recoverable state across app restarts without automatically resuming network work.

## Decision

Use a background `URLSession` with `URLSessionDownloadTask` for manga image downloads. On iOS 26 and newer, when the user explicitly continues the queue, wrap the active queue run in a `BGContinuedProcessingTask` so the system can present user-initiated long-running progress and cancellation. Persist queue membership, chapter progress, and paused/failed state separately from the system tasks; after app restart, restore the queue as paused and require the user to continue before submitting new background work.

The queue layer remains responsible for limiting work: it downloads one chapter at a time and submits at most three active image download tasks for that chapter, even when using a background `URLSession`. The system may delay or suspend those tasks, but the app does not enqueue an entire chapter's image list into the background session at once.

Offline cache image bytes are user-retained content with visible disk usage and no configured size limit. They are stored separately from the existing transparent image byte cache, whose bytes remain reclaimable. When an offline cache run needs an image URL already present in the transparent image byte cache, it copies those bytes into offline cache storage instead of downloading the URL again; the original transparent cache entry remains under the transparent cache's own LRU lifecycle.

Do not promise continued downloading after user force-quit. If the system stops execution or the app restarts, the product promise is recoverable queue state, not uninterrupted transfer.

## Consequences

The manga offline cache implementation needs explicit offline-cache membership and queue storage independent of the existing transparent document and image byte caches. It also needs a foreground/UI progress model that can reconcile completed background download callbacks, failed image requests, pause/cancel actions, and restart recovery.

The manga image loading path also needs offline-aware lookup: for images belonging to the current offline-cache membership, read user-retained offline bytes before falling back to the transparent image byte cache and network loader. That lookup requires enough favorite/chapter context to distinguish offline membership from ordinary URL cache hits.

Offline cache execution should use its own image acquisition seam rather than using the reader's cached image loader as the core executor. Acquisition first checks the transparent image byte cache and copies hits into offline storage; misses fetch through the network path and write user-retained offline bytes, while transparent cache population remains an implementation choice of that path.

Queue persistence should keep target image URLs and completed image URLs for fast UI restoration, then reconcile against the offline image store before continuing work. The offline image store remains the source of truth for whether a page image is available offline.

`YamiboAppContext.resetApplicationData()` must clear offline-cache membership, queue state, and offline image bytes alongside the existing manga directory, chapter document, and transparent image byte caches.

Delivery can be phased: first implement persistent membership and queue storage, reader and Mine Home queue UI, foreground execution, cancel/delete/recovery semantics, and offline-aware reads; then replace or extend the executor with background `URLSessionDownloadTask` and iOS 26 `BGContinuedProcessingTask` integration. The first phase should already use the final queue execution model of one active chapter and at most three concurrent image transfers for that chapter, so the second phase changes the transport mechanism rather than the product state machine.

## Verification

Tests should focus on Core stores, queue state transitions, foreground execution, cancel/delete cleanup, restart recovery, transparent-cache copy behavior, offline-aware image reads, and disk reconciliation. UI tests should cover view-model projections and commands for the reader cache sheet, Mine Home queue entry, queue sheet, and settings cleanup flow without asserting against Swift source text or relying on brittle full-sheet interaction scripts.
