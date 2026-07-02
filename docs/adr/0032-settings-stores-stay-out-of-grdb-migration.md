# Settings stores stay out of the GRDB migration

The GRDB migration will not move SettingsStore or WebDAVSyncSettingsStore into SQLite; they remain UserDefaults-backed JSON stores for now. Settings are currently loaded and saved as cohesive preference documents, and there is no current need for relational querying, WebDAV merge conflict resolution, or cross-store transactions that would justify adding them to the structured GRDB state boundary.
