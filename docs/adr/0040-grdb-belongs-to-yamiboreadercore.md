# GRDB belongs to YamiboReaderCore

GRDB 7.11.1 will be added as a YamiboReaderCore dependency because the database entry point, schema migrations, and GRDB-backed stores are Core data concerns rather than UI concerns. YamiboReaderUI should continue depending on Core store and repository APIs instead of opening or migrating the database itself.
