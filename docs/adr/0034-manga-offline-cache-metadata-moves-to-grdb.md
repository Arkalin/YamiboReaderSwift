# Manga offline cache metadata moves to GRDB

Manga Offline Cache membership, work queue state, progress metadata, owner metadata, and offline image indexes will move into GRDB, while the actual offline image bytes remain in the file system. Unlike transparent manga, forum, and novel caches, Manga Offline Cache metadata represents explicit user intent and recoverable queue state, so it belongs in transactional structured local state rather than in regenerable cache indexes.
