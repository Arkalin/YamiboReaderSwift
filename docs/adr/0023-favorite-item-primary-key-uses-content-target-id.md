# Favorite item primary key uses content target identity

The GRDB Favorite Library schema will use the iOS `FavoriteContentTarget.id` string as the `favorite_items` primary key instead of adopting Android's autoincrement local favorite item id. This keeps **Favorite Item** identity aligned with the domain model and WebDAV merge semantics, where a saved item is identified by its **Favorite Content Target** rather than by a database row id or Yamibo remote favorite id.
