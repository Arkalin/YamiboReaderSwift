# Native Forum Migration Plan

Status: superseded as an implementation-phase plan. Use `CONTEXT.md` and ADRs for current target behavior; reduced-scope references below describe historical migration slices, not the current acceptance standard.

This plan replaces the forum tab's WebView-first browser with a **Native Forum Surface** while keeping **Forum Web Fallback** only for flows that still require Yamibo web behavior.

## Confirmed Product Boundaries

- The forum tab opens **Forum Home** directly through native SwiftUI.
- There is no user-facing setting or menu item to switch back to the old WebView browser.
- **Forum Web Fallback** remains internal for posting, reader-origin forum links, unsupported URLs, login or verification flows, and parser failure recovery.
- **Forum Home** should match the current KMP/Compose app's information architecture and behavior, but the Swift implementation should use iOS-native visual treatment.
- `hasNewMessage` was outside this historical migration slice.

## Native Surfaces

### Forum Home

Forum Home should include:

- Top header with logo and search entry.
- **Forum Home Carousel** with automatic and manual paging.
- Collapsible forum category sections.
- Forum board rows or cards with name, optional description, and optional today count.
- Cache-first loading, background refresh, pull-to-refresh, loading state, error state, and retry.

Forum Home parsing succeeds when it yields at least one category and at least one board. Carousel parsing is optional; missing or failed carousel data hides the carousel instead of failing the page.

Category expansion follows the current KMP/Compose behavior:

- The first three categories are expanded by default.
- Later categories are collapsed by default.
- User expansion state is kept for the current page session.
- Refreshing data should not reset existing category expansion state.
- Expansion state is not persisted as a setting.

Forum Home Carousel behavior:

- Carousel item data is cached with Forum Home.
- Images used async loading and normal URL caching only in this historical migration slice; custom carousel image disk cache was not part of that slice.
- Image failure shows a placeholder and does not fail Forum Home.
- Clicking an item opens a thread natively when a thread id can be parsed; otherwise it uses **Forum Web Fallback**.

### Forum Board

Forum Board should include:

- Board title and metadata/statistics.
- Sub-boards.
- Pinned items.
- Thread list.
- Pagination.
- Sorting and filtering.
- Pull-to-refresh, loading, error, retry, and parser failure recovery.
- Post-thread entry routed through **Forum Web Fallback** or the existing action WebView pattern.
- **Forum Board Favorite** as a native authenticated HTTP write.

Board browsing should be native. Write-heavy or web-only flows should remain fallback unless explicitly called out as native.

### Forum Search

Forum Search is in scope for the native migration.

- Home search performs forum-wide title search.
- Board search scopes search to the current board.
- **Forum Search Results** show a paged native list of **Forum Thread Summary** values.
- Search result thread taps use the same opening strategy as board thread taps.
- If search requires `formhash`, use the parsed value and the current session. If it is missing, show a login or refresh error.

## Data Access

Use Yamibo mobile HTML parsed through the existing `YamiboClient` and Kanna path.

Add a forum repository boundary, likely created from `YamiboAppContext`, with methods shaped around:

- `fetchForumHome(preferCache:)`
- `fetchForumBoard(fid:page:filter:order:preferCache:)`
- `searchForum(query:fid:page:)`
- `addBoardFavorite(fid:formHash:)`
- cache lookup and refresh operations behind those methods

All native requests must use `SessionStore` as the source of cookie and user agent. Do not read `WKWebsiteDataStore` directly from native forum code.

## Domain Models

Use one compact thread summary model across board lists, pinned thread rows, and search results.

Suggested core model set:

- `ForumHomePage`
- `ForumCategory`
- `ForumBoardSummary`
- `ForumHomeCarouselItem`
- `ForumBoardPage`
- `ForumThreadSummary`
- `ForumPinnedItem`
- `ForumPageNavigation`
- `ForumFilterOption`
- `ForumOrderOption`
- `ForumSearchPage`

Fields that are not consistently available in Yamibo HTML should be optional. Missing auxiliary fields should hide their UI affordance rather than fail parsing.

## Cache Policy

Use a file-backed JSON `ForumCacheStore`, not `UserDefaults`.

- Forum Home: one cache entry, 12-hour TTL.
- Forum Board: keyed by `fid/page/filter/order`, 2-hour TTL.
- Search results can be uncached initially unless implementation finds a clear need.
- Screens may show valid cached data first, then refresh in the background.
- Pull-to-refresh bypasses cache and updates cache on success.

## Navigation

Add a native forum navigation host using SwiftUI `NavigationStack`.

The route graph should support:

- Forum Home.
- Forum Board by board id and title.
- Forum Search and results.
- Internal Web fallback targets.

External URL entry points should resolve intent before routing:

- URLs with `fid` route to **Forum Board** when parseable.
- Board/search thread taps route through `ThreadOpenResolver`.
- Reader-origin "open in forum" URLs route directly to **Forum Web Fallback**.
- Unknown or unsupported URLs route to **Forum Web Fallback**.

This means the current `ForumNavigationRequest(url:)` should become intent-aware rather than a raw WebView load request.

## Thread Opening Rules

Thread links from Board, pinned thread rows, carousel thread targets, and Search Results:

- Try `ThreadOpenResolver`.
- Open native novel or manga readers when supported.
- Open **Forum Web Fallback** for unsupported thread types or resolver failure.

Thread links from reader "open in forum" actions:

- Open **Forum Web Fallback** directly.
- Preserve page, post, or redirect URL context where available.

## Native Writes

### Forum Board Favorite

Implement **Forum Board Favorite** as a native authenticated request.

- Parse `formhash` from Forum Home or Forum Board HTML.
- Use `SessionState.cookie` and `SessionState.userAgent`.
- If authentication or `formhash` is unavailable, show a login or refresh error.
- Do not silently fall back to WebView for this action.

### Posting

Posting a new thread remained **Forum Web Fallback** or action WebView in this historical migration slice.

## Implementation Order

1. Add domain models, URL route resolver, repository structure, and `ForumCacheStore`.
2. Implement Forum Home parser and fixture tests.
3. Implement native Forum Home UI and route into Forum Board.
4. Implement Forum Board parser, repository fetch, cache, and fixture tests.
5. Implement Board UI, pagination, sorting, filtering, sub-boards, pinned items, and thread opening.
6. Add Forum Home Carousel.
7. Add Forum Search and Search Results.
8. Add native Forum Board Favorite.
9. Wire posting through Web fallback/action WebView.
10. Replace `RootTabView`'s forum tab with the native forum navigation host.

## Testing

Do not add source-code assertion tests. Tests must verify behavior through models, fixtures, repositories, and routing.

Recommended tests:

- `ForumHTMLParserTests` for Home, Board, Search, and failure boundaries using HTML fixtures.
- `ForumRouteResolverTests` for `fid`, `tid`, thread rewrite, reader-origin web intent, and unknown URL fallback.
- `ForumCacheStoreTests` for TTL, cache keys, cache hit, expiry, and refresh writes.
- Forum view model tests with fake repositories for load, cache-first refresh, pull-to-refresh, search, sorting/filtering, native favorite success, and native favorite failure.

UI snapshot tests were not required for this historical migration slice.

## Open Implementation Details

- Exact HTML selectors must be chosen from current Yamibo mobile pages and backed by fixtures.
- The final visual design should follow the Swift app's existing style, not Compose colors or Material components.
- Search result caching is intentionally deferred unless later profiling or UX shows it is needed.
