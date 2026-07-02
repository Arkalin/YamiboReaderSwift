# GRDB migration does not import legacy JSON stores

The GRDB-backed stores will not import, dual-write, or delete the existing UserDefaults JSON stores such as the local-first Favorite Library document and Reading Progress records. After the GRDB migration, GRDB starts as the authoritative store for new structured local state, while legacy JSON keys may remain on disk as inert historical data rather than participating in app behavior.
