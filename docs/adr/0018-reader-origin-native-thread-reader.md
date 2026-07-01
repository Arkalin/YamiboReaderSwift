# Reader-origin forum opens use native thread reader

Reader-origin open-forum actions from native novel and manga readers now open **Native Thread Reader** rather than **Forum Web Fallback**. This supersedes the reader-origin fallback portion of ADR 0012 and ADR 0015.

These actions preserve the user's original-post or discussion intent by bypassing novel/manga content classification and mapping thread URLs directly to regular-thread presentation. Thread page, `findpost`, and target post identifiers are carried into `ThreadReaderLaunchContext` when available so the native surface can open or highlight the original post context.

`ForumBrowserView` remains the internal **Forum Web Fallback** for flows without native contracts, including posting, replying, editing, authentication or verification pages, unsupported station links, and parser failure recovery.
