# Yamibo X Reader Navigation Context

Domain language for cross-reader navigation behavior shared by manga and novel readers.

## Language

**Reader Return Anchor**:
A stable reading position stored as an item in **Reader Navigation History**. It is not a bookmark and is not created by ordinary page turns, scrolling, automatic adjacent loading, restoration, or layout changes.
_Avoid_: bookmark, previous page, page jump marker

**Reader Navigation History**:
The cross-reader navigation state used to move backward and forward between stable reading positions after user-initiated non-linear jumps.
_Avoid_: single return anchor, browser history, jump cache

**Current Stable Reading Position**:
The reader position reached through normal linear reading and used as the source position when a later non-linear jump adds a **Reader Return Anchor**. Ordinary page turns and scrolling update it without mutating **Reader Navigation History**.
_Avoid_: current page, last jump source, visible position

**Reader Back Stack**:
The ordered stack of **Reader Return Anchors** available to return to from the current reader position.
_Avoid_: left stack, previous stack, undo stack

**Reader Forward Stack**:
The ordered stack of **Reader Return Anchors** available after moving backward through **Reader Navigation History**.
_Avoid_: right stack, redo stack, next stack

**Reader Preview Mode**:
A reader session state, fixed when the session launches, in which reading progress, resume route, and Favorite Library recency are never persisted while everything else about the reader — layout, chrome, chapter comments, prefetch, and offline cache — behaves normally. Reader chrome shows a visible indicator while it is active.
_Avoid_: read-only mode, ephemeral session, sandbox session

## Relationships

- **Reader Preview Mode** is decided once when a reader session launches from a designated jump, such as the Mine Home My Likes jump-to-original action; it is not entered or left partway through an existing session.
- **Reader Preview Mode** does not change **Reader Navigation History**, **Reader Return Anchor**, or **Current Stable Reading Position** semantics; it only controls whether the session's reading position is persisted outside the session.

- Ordinary linear reading updates the **Current Stable Reading Position** without changing **Reader Back Stack** or **Reader Forward Stack**.
- A user-initiated non-linear jump freezes the latest accepted **Current Stable Reading Position** at request start and adds it to **Reader Back Stack** only after the jump target resolves successfully.
- Moving backward through **Reader Navigation History** pushes the latest accepted **Current Stable Reading Position** to **Reader Forward Stack** only after the top **Reader Back Stack** anchor resolves successfully.
- Moving forward through **Reader Navigation History** pushes the latest accepted **Current Stable Reading Position** to **Reader Back Stack** only after the top **Reader Forward Stack** anchor resolves successfully.
- Reader navigation controls expose **Reader Back Stack** and **Reader Forward Stack** availability as directional controls, not as user-visible page or position labels.
- **Reader Navigation History** belongs to the current reader session and is discarded when that reader session closes.
- A superseded navigation request must not change **Reader Navigation History**.
- **Current Stable Reading Position** is initialized only after the reader publishes a valid accepted reading position.
- Adding a **Reader Return Anchor** is skipped when the source and target resolve to the same stable reading position.
- Adding a **Reader Return Anchor** is skipped when it would duplicate the current top anchor in the destination stack.
- User-initiated non-linear jumps may proceed without changing **Reader Navigation History** when no **Current Stable Reading Position** is available.
- Restoring from **Reader Navigation History** discards anchors that cannot resolve to a stable reading position in the current reader session.
- Moving backward or forward through **Reader Navigation History** transfers the latest accepted **Current Stable Reading Position** to the opposite stack only after a target anchor resolves successfully.
- **Reader Back Stack** and **Reader Forward Stack** each retain at most ten **Reader Return Anchors**.
- A **Reader Return Anchor** stores a reader-semantic position rather than a UI surface index or displayed page label.
- **Reader Navigation History** may cross reader document boundaries when the target **Reader Return Anchor** can be resolved in the current reader session.
- After a successful non-linear jump or a successful backward/forward restore, five ordinary linear page or surface changes expire **Reader Navigation History** and clear both **Reader Back Stack** and **Reader Forward Stack**. Repeated reports of the same stable reading position do not count toward this expiration.
