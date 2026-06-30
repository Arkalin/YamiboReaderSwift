# Novel reader content cache uses author-scoped thread pages

Native novel reading uses the author-scoped forum **Thread Page** cache as the authoritative cached source for novel-thread content. The persisted **Novel Reader Projection** is retained only as a derived performance cache for reader layout, chapter identity, segment identity, image references, and cache prewarming; it must be validated against the corresponding **Thread Page** before reuse.

We deliberately do not treat `ReaderCacheStore` as an offline source of truth and do not derive novel content from unfiltered all-posts **Thread Page** data. Unfiltered thread data may supply header metadata and help discover author scope, but preview text, chapter directories, readable content, cache-management state, and offline readiness all require an author-scoped **Thread Page**.

This keeps Novel Detail, cache management, and native novel reading on one content source while avoiding a second persistent novel-content truth. Creating or updating a cached reader view succeeds when the author-scoped **Thread Page** is saved; saving the derived projection is nonfatal prewarming, while deleting a cached reader view removes both the authoritative **Thread Page** and its derived projection.

Existing persisted reader documents are not eagerly migrated and do not count as cached or offline-ready without a matching author-scoped **Thread Page**. They become invalid on read when that validation is unavailable and may be removed lazily during update or deletion.

Behavior tests for this decision should prove that valid author-scoped **Thread Page** data can open the reader without a duplicate fetch, old reader documents cannot open offline by themselves, unfiltered all-posts **Thread Page** data cannot produce preview, directory, or reader content, cache-management state follows author-scoped **Thread Page** data, deletion removes both source and projection, projection prewarm failure is nonfatal after the source page is saved, missing author scope is retryable, and empty projections fail as reader content errors.
