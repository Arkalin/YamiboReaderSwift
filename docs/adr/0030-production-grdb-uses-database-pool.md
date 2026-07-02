# Production GRDB uses DatabasePool

The production YamiboReader database entry point will use GRDB `DatabasePool` with WAL-style concurrent read behavior, while stores depend on GRDB abstractions such as `DatabaseWriter` so tests can use a temporary pool or in-memory queue when appropriate. This supports UI reads, cache metadata reads, and background metadata writes without binding store implementations to one concrete connection type.
