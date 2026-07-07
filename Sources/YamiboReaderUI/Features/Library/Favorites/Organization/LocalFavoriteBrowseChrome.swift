import SwiftUI
import YamiboReaderCore

/// Chrome shared by every layout mode: the category tab bar, the active
/// filter strip, and the layout/sort chips row. Every content view (grid,
/// staggered, row-card, row-card-text) renders this exact same component so
/// their spacing and visibility rules cannot drift apart again.
///
/// Each piece is gated at this level (not inside its own body) so an
/// inactive filter strip is a genuinely absent child, not an empty one —
/// otherwise the enclosing stack's spacing would still open a gap on both
/// sides of it.
struct LocalFavoriteBrowseChrome: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let routes: LocalFavoritesRoutes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if organizer.selectedCollection == nil {
                LocalFavoriteCategoryTabBar(organizer: organizer, routes: routes)
            }
            if organizer.filter.hasActiveFilters {
                LocalFavoriteActiveFilterStrip(organizer: organizer)
            }
            LocalFavoriteViewOptionChips(organizer: organizer)
        }
    }
}
