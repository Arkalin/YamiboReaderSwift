# Centralized GRDB database lifecycle

YamiboReader will create and migrate the local GRDB database through one app-level database entry point, with stores receiving the shared `DatabaseWriter` or reader dependency instead of opening their own SQLite connections or registering migrations independently. This keeps schema ordering, default seeding, reset behavior, cache metadata, and test fixtures consistent across Favorite Library, Reading Progress, cache indexing, and other structured local stores.
