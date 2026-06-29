# Native forum owns forum navigation

The **Native Forum Surface** will own a SwiftUI `NavigationStack` for **Forum Home**, **Forum Board**, sub-board traversal, and thread-opening handoff instead of preserving the old WebView browsing-history model. Existing forum URL entry points, including clipboard links and reader "open in forum" actions, will first be resolved into native forum destinations and will use the **Forum Web Fallback** only when the destination is unsupported or cannot be parsed.
