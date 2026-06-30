# YamiboReader Forum Context

Domain language for native Yamibo forum browsing, forum-board presentation, and fallback web handling.

Current forum/thread parity work uses the current KMP/Compose `yamibo-app` implementation as the behavioral reference. Do not use the old Android `YamiboReaderPro` app as an acceptance reference for these surfaces.

## Language

**Native Forum Surface**:
The app-owned forum browsing surface rendered from structured forum data with native SwiftUI components. It covers forum home, board, and thread-list browsing rather than web-only interaction flows.
_Avoid_: forum web view, browser tab, native reader

**Forum Tab Boundary**:
The product boundary for current KMP/Compose-aligned forum work on iOS. Native forum, search, user-space, blog, and forum action fallbacks live inside the existing Forum tab navigation stack. This work must not add or restructure bottom tabs, and message badge logic such as `hasNewMessage` is outside this boundary unless requested separately.
_Avoid_: new bottom message tab, profile-tab badge behavior, app-wide tab redesign

**Forum Native Palette**:
The current KMP/Compose Yamibo color scheme adapted to native forum components and forum web fallback backgrounds on iOS: deep/primary brown for navigation and emphasis, cream background and cream surface for pages/cards, orange for badges/actions, and red for counts or alerts.
_Avoid_: system accent colors, platform default list background, arbitrary iOS-only theme

**Forum Home**:
The top-level Yamibo forum browsing entry that groups or lists available boards before the user enters a specific board's thread list.
_Avoid_: default board, forum browser homepage, root web page

**Forum Home Carousel**:
The rotating visual feature area on **Forum Home**. Current KMP/Compose-aligned native behavior opens carousel items only when the target resolves to a Yamibo thread; non-thread carousel targets render as imagery but do not open **Forum Web Fallback**.
_Avoid_: swiper, banner, homepage image slider

**Forum Board**:
A single Yamibo board's native browsing surface, including board metadata, sub-boards, pinned items, thread list, sorting, filtering, and pagination.
_Avoid_: forum page, thread reader, board web view

**Forum Board Favorite**:
The Yamibo action that adds a **Forum Board** to the current **Yamibo Account**'s forum favorites through an authenticated native request.
_Avoid_: local favorite, favorite library item, bookmark board

**Forum Search**:
The native Yamibo forum title-search workflow entered from **Forum Home** or a **Forum Board**.
_Avoid_: manga directory search, web search, favorite search

**Forum Search Results**:
The paged native list of Yamibo thread summaries returned by **Forum Search**, optionally scoped to one **Forum Board**.
_Avoid_: search web page, board thread list, tag results

**User Space**:
The native profile surface for a Yamibo user, organized like the current KMP/Compose app into Space, Threads, Blogs, and Friends sections. It includes profile metadata plus paged subpages for threads, replies, my blogs, friend blogs, view-all blogs, friends, online members, visitors, and traces. Forum author taps route here. Self-vs-other presentation is resolved against the current Yamibo account UID, not only the presence of a target UID.
_Avoid_: mine tab profile, account settings, user web page

**User Space Friend Request**:
The authenticated add-friend flow entered from another user's **User Space**. The app fetches the Discuz friend form, renders the note/group controls natively, and submits through native HTTP.
_Avoid_: local friend, WebView-only add friend, follow user

**User Space Friend Action**:
An action link attached to a **User Space** friend row, such as private message or delete friend. Private message opens the native **Private Message** surface and submits through native HTTP; delete friend remains a **Forum Web Fallback** until a native delete flow exists.
_Avoid_: friend request, local contact action

**Private Message**:
The native one-to-one Yamibo private-message conversation opened from **User Space** friend/message actions or **Message Center** private-message summaries inside the **Forum Tab Boundary**. It loads paged Discuz PM messages and sends replies through authenticated native HTTP. App-wide bottom message tabs and `hasNewMessage` badge behavior are out of scope unless requested separately.
_Avoid_: bottom message tab, push notification inbox, WebView-only PM

**Message Center**:
The native KMP/Compose-aligned forum message list opened from the current user's **User Space** message-alert action or Yamibo `home.php?mod=space&do=pm/notice` links. It includes paged private-message summaries and paged notice summaries inside the **Forum Tab Boundary**. It may open **Private Message** conversations and **User Space** profiles natively, while composing a new private message and unsupported notice actions remain **Forum Web Fallback**. `hasNewMessage` badge behavior remains out of scope unless requested separately.
_Avoid_: app-wide bottom message tab, push notification inbox, badge polling

**User Space Blog Composer**:
The authenticated blog posting/editing action entered from the current user's **User Space** Blogs section. The Blogs lists remain native, while composing or editing a blog uses **Forum Web Fallback**.
_Avoid_: native blog reader, thread post composer, forum board post

**Blog Reader**:
The native detail surface for a Yamibo user-space blog entry. It includes the root blog content, author metadata, stats, action links, comments, pagination, and native authenticated root comment submission. Unsupported per-comment reply flows remain **Forum Web Fallback**.
_Avoid_: blog web view, thread reader, article browser

**Blog Comment Submission**:
The authenticated native HTTP action that posts a root comment to a **Blog Reader** page using the current **Yamibo Account** form hash. On success, the current blog page is refreshed so the comment list matches the site.
_Avoid_: per-comment reply, blog composer, thread comment

**Forum Thread Summary**:
A compact representation of a Yamibo thread used by **Forum Board**, pinned thread lists, and **Forum Search Results** before the thread is opened.
_Avoid_: reader document, post summary, favorite item

**Forum Thread Tap Context**:
The source context supplied when a user opens a **Forum Thread Summary**, including the containing **Forum Board** when the list itself is board-scoped and mode flags such as tag manga browsing. It does not replace the thread's own board identity when that identity is carried by the summary.
_Avoid_: cell state, navigation path, tap URL

**Novel Detail**:
The shared native intermediate surface opened for a novel **Forum Thread Summary** before entering novel reading. It presents novel-thread metadata from the structured **Thread Page** header, chapter or post entry points, and reading actions rather than immediately starting the novel reader, and the caller hosts it in that caller's navigation stack.
_Avoid_: direct novel reader, novel web page, thread reader

**Forum Thread Routing**:
The classification of a **Forum Thread Summary** and its **Forum Thread Tap Context** into **Novel Detail**, **Manga Detail**, **Native Thread Reader**, or **Forum Web Fallback**. When a containing **Forum Board** is known from the tap context, that board identity is tried before the thread summary's own board identity; content-title or body-shape inference is only a fallback for threads without known board context.
_Avoid_: title guessing, web-first opening, cell-local routing

**Forum Taxonomy**:
The Core forum-domain classification of Yamibo board identities into mutually exclusive thread kinds used by **Forum Thread Routing**. It owns board-based novel, manga, regular, and unknown classification instead of leaving that ownership to reader parsers.
_Avoid_: reader mode detector, parser-owned board list, scattered fid checks

**Thread Route Target**:
The pure value produced by **Forum Thread Routing** for a caller to map into its own navigation stack. It describes the intended destination without mutating app-level reader presentation or a caller's navigation path, and carries both the canonical thread URL and parsed thread or board identity when available.
_Avoid_: navigation side effect, destination enum leak, direct presentation

**Thread Route Request**:
The caller-supplied input to **Forum Thread Routing**, carrying the thread URL or identity plus any known title, author, board identity, target post identity, and **Forum Thread Tap Context**. It lets URL-only and favorite-library callers use the same routing contract without fabricating a **Forum Thread Summary**, while preserving both URL-based loading and parsed identity-based routing.
_Avoid_: fake summary, row-only input, navigation request

**Native Thread Reader**:
The shared app-owned reading surface for a regular Yamibo thread, distinct from novel and manga readers. It is the default destination for a readable **Forum Thread Summary** that is not classified as novel, manga, or web-only, and the caller hosts it in that caller's navigation stack.
_Avoid_: forum web view, normal web thread, reader fallback

**Thread Page**:
The structured regular-thread document loaded for **Native Thread Reader**, centered on forum posts, post metadata such as author, floor, posted time, last-edited text, pinned state, management action links, content blocks, poll state, rating summaries, post comments, attachments, and pagination rather than novel chapters or manga pages.
_Avoid_: reader page document, novel chapter, web page snapshot

**Forum Web Fallback**:
The Yamibo web surface retained for forum interactions that are not represented by the **Native Forum Surface**, including posting, replying, editing, sign-in or verification pages, unsupported station links, and parser failure recovery.
_Avoid_: forum page, native forum, web reader

## Relationships

- **Forum Thread Routing** classifies a thread by containing **Forum Board** from **Forum Thread Tap Context** first, then by the **Forum Thread Summary** or **Thread Route Request** board identity, then by fetched thread metadata. A recognized **Forum Taxonomy** kind from those board identities outranks caller-supplied known thread kind hints.
- If **Forum Thread Routing** has a board identity but **Forum Taxonomy** does not recognize it, a caller-supplied known thread kind may classify the thread. Without that hint, the thread defaults to **Native Thread Reader** as a regular thread and records a taxonomy-miss diagnostic.
- Title, tag, or section-marker inference is only a final fallback when board identity and known kind cannot classify the thread. Generic image-heavy HTML inference must not classify an unknown thread as **Manga Detail**; manga classification requires recognized **Forum Taxonomy** or a caller-supplied known thread kind. Novel fallback inference must be limited to explicit section, title, or tag markers and must not infer novel status from body length or prose shape.
- **Forum Search Results** supply a containing **Forum Board** in **Forum Thread Tap Context** only when the returned result set is known to be scoped to that board. Global or uncertain search results rely on per-thread board identity or fetched metadata instead.
- Pinned items that identify a thread use the same **Forum Thread Routing** path as regular **Forum Thread Summary** taps, with the containing **Forum Board** supplied when known. Announcement or non-thread pinned items remain **Forum Web Fallback** behavior.
- **Forum Home Carousel** items that identify a thread use **Forum Thread Routing** with a URL-only **Thread Route Request**. Carousel items that do not identify a thread remain non-opening imagery rather than **Forum Web Fallback** links.
- In-app links use an outer link resolver to parse Yamibo URL kind. Thread and find-post links then build a **Thread Route Request** and reuse **Forum Thread Routing**, while forum boards, user spaces, blogs, tags, and web-only links remain outside the thread router's responsibility.
- Favorite-library metadata may provide a known thread kind hint to **Forum Thread Routing**, but library-specific favorite types do not belong to the routing contract.
- **Native Thread Reader** targets current KMP/Compose-aligned structured thread reading, including post metadata, pinned state, management action links, poll result state, rating summaries, post comments, styled and aligned text ranges, ruby annotations, images, attachments, quotes, code, tables, collapsible and locked sections, pagination, target-post positioning, and scalable rendering for long posts. Web fallback is reserved for interactions or privileged actions that do not yet have native contracts, not as an acceptance boundary for thread reading itself.
- **Native Thread Reader** uses a regular **Thread Page** model and parser instead of reusing the novel reader page document model.
- **Native Thread Reader** loads all posts by default. Author identity passed through routing is profile metadata and must not implicitly filter regular thread content; any "author only" view would be an explicit reader control.
- When a **Thread Route Request** carries a target post identity, **Native Thread Reader** attempts to open the containing thread page and scroll to or highlight that target post.
- Inline image taps inside **Native Thread Reader** open a generic image viewer or browser with raw-image copy, share, and save actions when authenticated image data is available. They do not reclassify the thread as manga and do not route to **Manga Detail** or manga reading. Caller-specific actions such as setting a cover are not part of the generic thread-reader image contract.
- Shared detail surfaces may provide a secondary "view thread" or discussion action that opens **Native Thread Reader** for the same thread. They do not need a separate proactive "open original forum" action; reader-origin open-forum actions remain **Forum Web Fallback** behavior.
- **Forum Thread Routing** returns **Forum Web Fallback** only for destinations known to be web-only or unsupported by native surfaces, including authentication, verification, or challenge pages that require web handling. Network and parser failures during routing surface as retryable native errors rather than automatically opening web fallback.
- **Novel Detail** is owned by the novel-reader context as a shared entry surface, while **Forum Thread Routing** may produce it as a **Thread Route Target**. Its header metadata is derived from a loaded **Thread Page** so title, first-post author, post time, views, replies, forum label, and cover candidate follow the same source model as **Native Thread Reader**.
