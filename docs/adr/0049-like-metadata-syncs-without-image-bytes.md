# Like Metadata Syncs Without Image Bytes

Like Items sync through WebDAV as user-owned metadata -- excerpt snapshots, image URLs, Like Anchors, timestamps, and removal tombstones -- while image bytes stay device-local, matching the existing rule that WebDAV carries user-owned JSON metadata and never binary content. Other devices re-capture bytes from the stored URL and show a placeholder when re-capture fails.
