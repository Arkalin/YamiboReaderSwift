# Manga directory moves to GRDB

Manga Directory metadata and chapter lists will move from file-backed JSON indexes into GRDB tables. This makes chapter `tid` ownership lookup indexed instead of file-scanned and lets Manga Directory rename operations update matching Favorite Library targets, Reading Progress records, and Manga Offline Cache owner metadata in one transaction.
