# Account stores stay out of the GRDB migration

The GRDB migration will not move SessionStore, YamiboProfileStore, or YamiboCheckInStore into SQLite, even though Android stores daily sign records in SQLDelight. These account-adjacent stores remain outside the structured GRDB boundary so the database focuses on Favorite Library, Reading Progress, cache metadata, queue metadata, and other non-authentication local state.
