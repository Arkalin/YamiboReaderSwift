# Favorite location invariant is owned by store transactions

The rule that each **Favorite Item** must have at least one **Favorite Location** will be enforced by the GRDB-backed Favorite Library store's transactional write paths, not by SQLite triggers. The database will still enforce foreign keys and uniqueness, while operations such as deleting a category, dissolving a collection, merging WebDAV changes, or deleting an item keep the minimum-location rule in domain code where the required fallback or deletion semantics are explicit.
