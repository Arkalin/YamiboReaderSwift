# Single GRDB database for structured local state

YamiboReader will use one app-owned GRDB database file for user-owned structured data, queue and metadata tables, and the generic `cache_entries` index, while large or regenerable cache contents remain in the file system. This follows the Android SQLDelight shape and keeps cross-store operations such as Favorite Library updates, Reading Progress Store updates, offline-cache metadata changes, reset, cleanup, and schema migration under one transaction and migrator instead of splitting local state across multiple SQLite files.
