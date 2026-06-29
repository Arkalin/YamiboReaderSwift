# YamiboReader Forum Context

Domain language for native Yamibo forum browsing, forum-board presentation, and fallback web handling.

## Language

**Native Forum Surface**:
The app-owned forum browsing surface rendered from structured forum data with native SwiftUI components. It covers forum home, board, and thread-list browsing rather than web-only interaction flows.
_Avoid_: forum web view, browser tab, native reader

**Forum Tab Boundary**:
The product boundary for Android-aligned forum work on iOS. Native forum, search, user-space, blog, and forum action fallbacks live inside the existing Forum tab navigation stack. This work must not add or restructure bottom tabs, and message badge logic such as `hasNewMessage` is outside this boundary unless requested separately.
_Avoid_: new bottom message tab, profile-tab badge behavior, app-wide tab redesign

**Forum Android Palette**:
The Android default Yamibo color scheme applied to native forum components and forum web fallback backgrounds on iOS: deep/primary brown for navigation and emphasis, cream background and cream surface for pages/cards, orange for badges/actions, and red for counts or alerts.
_Avoid_: system accent colors, platform default list background, arbitrary iOS-only theme

**Forum Home**:
The top-level Yamibo forum browsing entry that groups or lists available boards before the user enters a specific board's thread list.
_Avoid_: default board, forum browser homepage, root web page

**Forum Home Carousel**:
The rotating visual feature area on **Forum Home**. Android-aligned native behavior opens carousel items only when the target resolves to a Yamibo thread; non-thread carousel targets render as imagery but do not open **Forum Web Fallback**.
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
The native profile surface for a Yamibo user, organized like Android into Space, Threads, Blogs, and Friends sections. It includes profile metadata plus paged subpages for threads, replies, my blogs, friend blogs, view-all blogs, friends, online members, visitors, and traces. Forum author taps route here. Self-vs-other presentation is resolved against the current Yamibo account UID, not only the presence of a target UID.
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
The native Android-aligned forum message list opened from the current user's **User Space** message-alert action or Yamibo `home.php?mod=space&do=pm/notice` links. It includes paged private-message summaries and paged notice summaries inside the **Forum Tab Boundary**. It may open **Private Message** conversations and **User Space** profiles natively, while composing a new private message and unsupported notice actions remain **Forum Web Fallback**. `hasNewMessage` badge behavior remains out of scope unless requested separately.
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

**Forum Web Fallback**:
The Yamibo web surface retained for forum interactions that are not represented by the **Native Forum Surface**, including posting, replying, editing, sign-in or verification pages, unsupported station links, and parser failure recovery.
_Avoid_: forum page, native forum, web reader
