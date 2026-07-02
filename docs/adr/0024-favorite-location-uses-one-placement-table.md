# Favorite location uses one placement table

The GRDB Favorite Library schema will model **Favorite Location** with one `favorite_locations` table containing `item_id`, `category_id`, and optional `collection_id`, instead of copying Android's separate category and collection cross-reference tables. This matches the iOS domain model where direct category placement and collection placement are variants of the same user-owned organization concept, and it keeps location deletion, multi-location rules, and future WebDAV tombstones in one place.
