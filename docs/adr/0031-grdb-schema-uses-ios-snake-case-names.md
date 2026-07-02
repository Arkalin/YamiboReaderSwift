# GRDB schema uses iOS snake_case names

The iOS GRDB schema will use snake_case table and column names that reflect the iOS domain model, while using Android SQLDelight tables as behavioral and field-shape references rather than naming compatibility targets. This avoids implying a one-to-one schema port where iOS concepts such as **Favorite Location** and **Reading Progress Store** deliberately differ from Android tables like `LocalFavoriteItemCategoryCrossRef` and `ReadingHistory`.
