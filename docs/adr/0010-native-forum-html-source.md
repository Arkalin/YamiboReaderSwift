# Native forum uses Yamibo mobile HTML as its source

The **Native Forum Surface** will first be backed by Yamibo mobile forum HTML parsed through the existing `YamiboClient` and Kanna pipeline instead of introducing or reverse-engineering a separate API. This matches the repository's existing authenticated Yamibo data access pattern for favorites, readers, profiles, and comments, while keeping the **Forum Web Fallback** for unsupported interactions, verification flows, and parser failures.
