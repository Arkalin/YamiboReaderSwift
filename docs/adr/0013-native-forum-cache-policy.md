# Native forum cache policy follows forum page volatility

The **Native Forum Surface** will use a file-backed JSON `ForumCacheStore` rather than `UserDefaults` for parsed forum data. **Forum Home** uses a single cached page with a 12-hour TTL, while **Forum Board** pages are cached by board, page, filter, and order with a 2-hour TTL; screens may show cached data first and then refresh, and pull-to-refresh bypasses the cache.
