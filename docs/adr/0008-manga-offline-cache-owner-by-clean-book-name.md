# Manga offline cache is owned by clean book name

Manga offline-cache membership is moving from favorite-entry ownership to cleaned manga-title ownership so the same title can share offline content across favorite, forum, and resume entry points. The product has not shipped with the old model, so existing developer-local favorite-owned offline-cache records will not be migrated; this avoids carrying legacy favorite identity through the new model.

**Consequences**

Old offline-cache records keyed by favorite identity are not valid offline-cache ownership after this decision. The implementation should ignore legacy records for new owner-based state lookup instead of attempting best-effort owner inference, and it does not need a user-facing cleanup path for developer-local legacy files.

Directory renames should also rename the matching offline-cache owner, but this does not require a cross-store transaction. If the directory rename succeeds and the offline-cache owner rename fails, the directory rename may remain committed while the UI reports the cache rename failure.
