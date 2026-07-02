# Favorite organization ids use stable strings

Favorite categories, collections, and tags will keep the iOS stable string ids, including the fixed `default` category id and UUID-style user-created ids, instead of adopting Android's autoincrement integer ids. These organization objects are user-owned WebDAV-synchronized metadata, so their database identity must be stable across devices rather than tied to one local SQLite row sequence.
