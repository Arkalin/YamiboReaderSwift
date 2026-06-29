# YamiboReader Forum Context

Domain language for native Yamibo forum browsing, forum-board presentation, and fallback web handling.

## Language

**Native Forum Surface**:
The app-owned forum browsing surface rendered from structured forum data with native SwiftUI components. It covers forum home, board, and thread-list browsing rather than web-only interaction flows.
_Avoid_: forum web view, browser tab, native reader

**Forum Home**:
The top-level Yamibo forum browsing entry that groups or lists available boards before the user enters a specific board's thread list.
_Avoid_: default board, forum browser homepage, root web page

**Forum Home Carousel**:
The rotating visual feature area on **Forum Home** whose items may link to Yamibo threads or web-only forum targets.
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

**Forum Thread Summary**:
A compact representation of a Yamibo thread used by **Forum Board**, pinned thread lists, and **Forum Search Results** before the thread is opened.
_Avoid_: reader document, post summary, favorite item

**Forum Web Fallback**:
The Yamibo web surface retained for forum interactions that are not represented by the **Native Forum Surface**, including posting, replying, editing, sign-in or verification pages, unsupported station links, and parser failure recovery.
_Avoid_: forum page, native forum, web reader
