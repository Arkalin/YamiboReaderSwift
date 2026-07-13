# Yamibo X Library and Account Context

Domain language for favorites, reading metadata, Yamibo accounts, profiles, and sign-out semantics.

## Language

**Favorite Library**:
The user's local-first collection of saved Yamibo content plus user-owned reading metadata, display names, and organization.
_Avoid_: remote favorites projection, favorite store, favorites snapshot, favorites list

**Favorite Item**:
One saved Yamibo content target in the **Favorite Library**, independent of where it appears in the user's organization.
_Avoid_: favorite row, favorite card, remote favorite

**Favorite Content Target**:
The stable Yamibo content identity of a **Favorite Item**, such as a normal thread, novel thread, or manga title.
_Avoid_: URL string, remote favorite ID, row ID

**Favorite Location**:
One organizational placement of a **Favorite Item** inside the **Favorite Library**, such as a category or collection.
_Avoid_: tag, folder membership, favorite path

**Favorite Category**:
A top-level organizational area in the **Favorite Library** used to switch between groups of favorite content.
_Avoid_: tab, root folder, tag

**Default Favorite Category**:
The required fallback **Favorite Category** for newly created or imported **Favorite Items** when no other category is chosen.
_Avoid_: uncategorized, inbox, root folder

**Favorite Collection**:
A named and color-coded grouping inside a **Favorite Category** that can contain **Favorite Items**.
_Avoid_: category, folder, tag group

**Dissolve Favorite Collection**:
Removing a **Favorite Collection** while preserving its contained **Favorite Items** by placing them directly in the parent **Favorite Category**.
_Avoid_: delete collection, clear collection

**Favorite Tag**:
A user-owned label on a **Favorite Item** used for filtering and annotation, independent of where the item appears.
_Avoid_: category, collection, folder

**Favorite Display Name**:
A user-owned title override for a **Favorite Item** used for local presentation and search.
_Avoid_: thread title, remote title, collection name

**Favorite Source Group**:
A temporary filtering group for **Favorite Items** based on their Yamibo source, such as a forum board, manga title, or unknown source.
_Avoid_: favorite type, category, tag

**Favorite Cover URL**:
The synchronized image URL candidate used to present a **Favorite Item** in the **Favorite Library**.
_Avoid_: image cache, cover bytes, background image

**Reading Progress Store**:
The separately synchronized source of truth for per-thread novel and manga reading position, independent from whether the thread is currently visible in the **Favorite Library**.
_Avoid_: favorite progress, archive progress, recent route

**Like Library**:
The user's local-first collection of liked excerpts -- text passages and images captured from supported readers -- grouped by the owning content target.
_Avoid_: likes list, highlight store, excerpt store, bookmark list

**Like Item**:
One liked excerpt in the **Like Library**: a text excerpt or an image captured from one owning content target.
_Avoid_: highlight, clipping, bookmark, favorite row

**Like Anchor**:
The persisted in-work location of a **Like Item** used to jump back to its original reading position.
_Avoid_: selection range, runtime generation offset, TextKit position

**Like Highlight**:
The persistent in-reader decoration that marks an existing text **Like Item** in novel reader content and offers view or remove actions when tapped.
_Avoid_: text selection, temporary highlight, annotation

**Yamibo Account**:
The authenticated Yamibo forum identity represented by UID, display name, profile, user group, and forum credit totals.
_Avoid_: app account, local user, session

**Yamibo Profile**:
The Yamibo forum profile data for one **Yamibo Account**, including public identity, avatar, user group, and forum credit fields.
_Avoid_: personal homepage, profile web page, account card

**Yamibo Profile Avatar**:
The profile image associated with a **Yamibo Profile** for the current **Yamibo Account**.
_Avoid_: generic authenticated image, account icon, user picture

**Yamibo User Group**:
The Yamibo forum permission tier assigned to a **Yamibo Account** from its forum credit totals.
_Avoid_: rank, role, level

**Forum Credit Progress**:
The current **Yamibo Account**'s total forum credits measured against the next **Yamibo User Group** threshold.
_Avoid_: points bar, score progress, user level progress

**Mine Home**:
The app's account home surface for the current **Yamibo Account**.
_Avoid_: profile web view, my page, user center

**Download Queue**:
The Mine Home-accessible queue surface that presents unfinished user-requested offline-cache work across supported reader contexts.
_Avoid_: manga-only queue, novel-only queue, transient progress sheet

**Offline Cache Management**:
The app-level surface for finding, inspecting, and deleting completed or pending user-retained offline-cache content across supported reader contexts.
_Avoid_: favorite management, transparent cache cleanup, download history

**Security Question**:
The optional Yamibo login challenge configured on a **Yamibo Account**, composed of a selected question and answer.
_Avoid_: captcha, verification code, password hint

**Yamibo Sign Out**:
Ending the current **Yamibo Account** authentication state in the app while preserving user-owned library, reading, sync, and app settings.
_Avoid_: reset application, clear data, delete account

**Yamibo Check-In**:
The Yamibo forum daily check-in action for the current **Yamibo Account**, available from Mine Home and app automation entry points.
_Avoid_: sign in, login, automatic-only sign-in

**App Continuity**:
The app workflow that keeps the **Favorite Library**, reader resume route, WebDAV sync, and current reading entry consistent across launch, foreground refresh, local data changes, and backgrounding.
_Avoid_: app sync, startup restore, lifecycle handler

**Favorite Update Notification**:
The local system notification delivered when a favorite update check detects new content for a tracked **Favorite Item** — at most one per item, replaced in place as further updates accumulate onto the same undismissed event.
_Avoid_: remote push, APNs, server notification

## Relationships

- A **Favorite Library** is local-first: user-owned **Favorite Items** decide what saved content exists, while Yamibo remote favorites are a sync target for supported items.
- A **Favorite Item** is identified by its **Favorite Content Target**, not by a Yamibo remote favorite ID or raw URL string.
- Thread-based **Favorite Content Targets** use Yamibo thread `tid` as their persistent identity; thread URLs are external input and network construction details rather than stored favorite identity.
- **Favorite Content Target** kind replaces favorite type as the domain distinction between normal threads, novel threads, and manga titles.
- Normal thread and novel thread **Favorite Content Targets** are distinct because they carry different reading entry and progress semantics.
- Manga title **Favorite Content Targets** use the owning **Manga Directory** `cleanBookName`, while chapter URLs are opening and recovery metadata.
- Manga chapter imports resolve the owning manga title by checking whether the chapter `tid` already belongs to a local **Manga Directory** before falling back to newly probed directory title metadata.
- Fuzzy manga title matches do not automatically merge manga title **Favorite Items**; they require later user correction or explicit directory identity changes.
- Renaming a **Manga Directory** changes the manga title identity and must migrate matching manga title **Favorite Items** and manga reading positions.
- When a **Favorite Item** is reclassified from one **Favorite Content Target** kind to another, the existing item is retargeted instead of creating a duplicate item.
- If probing discovers duplicate normal-thread and novel-thread **Favorite Items** for the same thread, the **Favorite Library** keeps the probed target kind and merges user-owned metadata and locations into that item.
- Remote favorite import probes newly discovered remote thread favorites before creating **Favorite Items** so normal thread and novel thread targets can be classified immediately.
- If probing a remote thread favorite fails during import, the **Favorite Library** skips creating the **Favorite Item** and reports the sync failure instead of creating a placeholder item.
- When remote favorite import probes a manga chapter thread, it creates or updates the owning manga title **Favorite Item** and stores the chapter as opening or import-source metadata rather than treating the remote favorite as the whole manga title's remote mapping.
- A **Favorite Item** may have multiple **Favorite Locations**. Removing one **Favorite Location** does not remove the **Favorite Item** if other locations remain.
- A persisted **Favorite Item** must have at least one **Favorite Location**.
- A **Favorite Location** places a **Favorite Item** either directly in a **Favorite Category** or inside a **Favorite Collection** within a **Favorite Category**.
- A **Favorite Item** may appear in multiple **Favorite Locations** within the same **Favorite Category**, including both directly in the category and inside one or more of its collections.
- Every **Favorite Library** has a **Default Favorite Category**, and newly created or imported **Favorite Items** use it when no other **Favorite Category** is selected.
- Non-default **Favorite Categories** are user-owned organization and may be created, renamed, reordered, and deleted.
- Deleting a non-default **Favorite Category** removes that category's **Favorite Collections** and moves its contained **Favorite Items** to the **Default Favorite Category** rather than deleting the items.
- **Dissolve Favorite Collection** is the default collection removal behavior and does not delete the contained **Favorite Items**.
- A **Favorite Tag** labels a **Favorite Item** but is not a **Favorite Location** and does not decide where the item appears.
- **Favorite Tags** synchronize through WebDAV as user-owned metadata and are not uploaded to or imported from Yamibo remote favorites.
- A **Favorite Display Name** does not change the Yamibo content title and is never uploaded as a Yamibo remote favorite title.
- A **Favorite Source Group** is a temporary filter and is not user-owned organization.
- A **Favorite Cover URL** is **Favorite Item** metadata, while downloaded cover image bytes are device-local cache data and are not part of the **Favorite Library**.
- Favorite list sorting uses organization/default order, content update time, Yamibo remote favorite order, display title, **Favorite Source Group**, or last read time; reading progress is not a **Favorite Library** sort dimension.
- Favorite search matches **Favorite Display Name** or content title, **Favorite Source Group** label, and **Favorite Collection** name; raw URLs and Yamibo remote favorite IDs are not search fields.
- Favorite page counts and search badges use the currently displayed entry count, not the globally distinct **Favorite Item** count.
- Deleting a **Favorite Location** is an organization change only and never deletes the matching Yamibo remote favorite.
- Deleting a **Favorite Item** may delete the matching Yamibo remote favorite when the item supports remote sync and the user chooses that sync behavior.
- Deleting a manga title **Favorite Item** does not delete Yamibo remote chapter favorites imported as opening or import-source metadata.
- When a Yamibo remote favorite disappears during sync, the **Favorite Library** preserves the matching **Favorite Item** and its user-owned organization, while clearing or marking the remote sync mapping.
- Archived favorite metadata is not part of the local-first **Favorite Library** model and is not preserved when adopting the model.
- WebDAV sync carries the user-owned **Favorite Library**, including **Favorite Items**, **Favorite Locations**, **Favorite Categories**, **Favorite Collections**, **Favorite Tags**, and display metadata.
- WebDAV sync may carry a **Favorite Item**'s Yamibo remote favorite mapping as sync metadata, but that mapping never decides whether the item exists or where it appears.
- WebDAV sync does not carry Yamibo authentication state, remote sync task progress, sync logs, or platform background task state.
- WebDAV merges **Favorite Locations** by preserving locations added on different devices; explicit location removal requires removal metadata so deleted locations are not recreated by stale devices.
- WebDAV merges **Favorite Tag** associations by preserving tags added on different devices; explicit tag association removal requires removal metadata so deleted associations are not recreated by stale devices.
- WebDAV merges single-value **Favorite Item** metadata with field-domain clocks so changing one domain, such as cover metadata, does not overwrite another domain, such as display name.
- Yamibo remote favorite sync operates on one **Favorite Category** at a time: remote thread favorites are imported into that category, and local thread **Favorite Items** in that category may be uploaded to Yamibo remote favorites.
- Manga title **Favorite Items** are local-only for Yamibo remote favorite sync.
- The **Reading Progress Store** owns current local reading position for novels and manga. Removing a visible favorite does not remove the matching **Reading Progress Store** record.
- The **Reading Progress Store** identifies synchronized reading positions by stable content target identity, using Yamibo thread `tid` for thread-based content rather than raw or canonical URL strings.
- Manga reading positions in the **Reading Progress Store** are owned by manga title identity and store the current chapter identity and page index.
- Visible **Favorite Library** entries may mirror the **Reading Progress Store** reading position for favorite-list display and existing WebDAV favorite payload compatibility, but reader resume should prefer the **Reading Progress Store**.
- Favorite cards may display recent reading, chapter, page, or percent progress, but those progress values are projections from the **Reading Progress Store** rather than **Favorite Item** authority.
- The **Reading Progress Store** syncs separately from the **Favorite Library** so reading position can move across devices without making favorites own reader state.
- A **Favorite Library** persists a novel's **Novel Reading Position** through its semantic resume point and reader page document view; it never stores a novel runtime surface ordinal or displayed page number.
- Manga page persistence uses the manga-specific `mangaPageIndex` Interface. The historical JSON key `lastPage` may remain as a schema compatibility key, but it is not a Swift Interface and is never written from novel reading.
- The **Like Library** is local-first and independent of the **Favorite Library**: liking never requires favoriting, and deleting a **Favorite Item** never deletes **Like Items** for the same content target.
- A **Like Item** is owned by a **Favorite Content Target** identity: novel threads use Yamibo thread `tid`, manga titles use the owning **Manga Directory** `cleanBookName`; normal forum threads are not capture sources.
- Novel content targets may own text and image **Like Items** (novel illustrations); manga titles own image **Like Items** only.
- Renaming a **Manga Directory** migrates matching manga title **Like Items** together with manga reading positions.
- A text **Like Item** stores its excerpt snapshot as displayed text after translation-mode transformation, and its **Like Anchor** uses the persisted **Novel Reading Position** coordinate space: chapter identity, segment identity, and displayed-text Character offsets.
- A manga image **Like Item** anchors by chapter `tid` and page `localIndex`; a novel image **Like Item** anchors by its image segment identity.
- Text **Like Item** ranges never overlap within one content target: adding a range that overlaps or touches existing text **Like Items** merges them into one item whose excerpt snapshot is re-captured over the union range.
- Adding a **Like Item** with a **Like Anchor** identical to an existing item is idempotent.
- An image **Like Item** captures its image bytes into user-retained storage at like time; the bytes are user-retained content rather than transparent cache, and deleting the **Like Item** deletes the bytes.
- WebDAV sync carries **Like Item** metadata -- excerpt snapshots, image URLs, **Like Anchors**, and timestamps -- with removal metadata so deleted **Like Items** are not recreated by stale devices; image bytes stay device-local, and other devices re-capture bytes by URL with a placeholder on failure.
- Jumping to a **Like Item** from the **Mine Home** My Likes entry opens the reader in **Reader Preview Mode**: reading progress, resume route, and Favorite Library recency are not persisted for that session. Jumping to a **Like Item** from the in-reader likes sheet (browsing likes without leaving the current reader) remains an ordinary non-linear reader jump: reading progress updates normally and a return anchor is offered, following reader-navigation semantics.
- A **Like Item** is never deleted because its **Like Anchor** fails to resolve; jumping falls back to the owning chapter start, and a missing **Like Highlight** does not remove the list entry.
- The **Mine Home** My Likes entry presents two levels: a works list with covers and like counts ordered by most recent like activity, then the owning work's **Like Items** ordered by in-work position.
- The reader bottom chrome like button presents the current work's **Like Items** and reuses the second-level likes surface.
- **Like Highlights** render persistently in novel reader content in both paged and vertical reading modes and open a view, copy, or remove menu when tapped; liked images show a heart badge instead of a text highlight.
- **Mine Home** presents the current **Yamibo Account** through its **Yamibo Profile**.
- **Mine Home** exposes the **Download Queue** while each offline-cache work item remains owned by its reader context.
- **Download Queue** may contain manga and novel offline-cache work together, with row type and grouping making the reader context explicit.
- **Mine Home** represents pending **Download Queue** activity by unfinished work item count, not by completed cached content or owner group count.
- Failed work remains in the **Download Queue** until the user continues the queue, cancels the work, or deletes the matching offline-cache content. Continuing the queue retries failed work as well as queued or paused work.
- The offline-cache queue executor owns **Download Queue** run lifecycle, while each single work item's durable source payload and image asset transfer are processed through a shared work processor with reader-specific strategy adapters.
- **Offline Cache Management** groups offline-cache content by reader context and owner, supports deleting an owner group, and supports deleting individual cached chapter or view entries.
- Manga offline cache records and image bytes are device-local content availability data and are not synchronized as **Favorite Library** metadata through WebDAV.
- Manga offline cache completion does not update **Favorite Library** reading progress, resume routes, or recent-reading timestamps.
- A **Yamibo Profile Avatar** belongs to a **Yamibo Profile**, not to a generic app image-loading model.
- A **Yamibo Profile** identifies the account's current **Yamibo User Group** and forum credit totals.
- **Forum Credit Progress** uses the account's total forum credits and the next **Yamibo User Group** threshold.
- **Mine Home** may show a cached **Yamibo Profile** while refreshing it, and a failed refresh does not end the **Yamibo Account** authentication state.
- A **Security Question** may be required to authenticate a **Yamibo Account**.
- A **Yamibo Account** stores authentication state in the app, not the account password.
- **Yamibo Sign Out** clears current authentication and cached profile state without clearing the **Favorite Library** or reading settings.
- **Yamibo Sign Out** preserves manga offline cache records, queued work, and image bytes because they are owned by the local **Favorite Library** rather than the current authentication state.
- **Yamibo Check-In** is distinct from Yamibo Account login and may reuse the latest local daily check-in record to avoid unnecessary forum requests.
- **App Continuity** may use WebDAV sync before restoring a reader resume route so the restored entry reflects the latest user-owned **Favorite Library** reading metadata.
- **Favorite Update Notifications** are opt-in from the favorites updates page and require a system notification permission grant to turn on; while the permission is later revoked, deliveries are skipped silently and the updates page surfaces the blocked state.
- Handling a favorite update event in-app — marking it read, dismissing it, or disabling notifications — removes its delivered **Favorite Update Notification**, and the app icon badge tracks the unread event count shown on the favorites bell.
- Tapping a **Favorite Update Notification** opens its **Favorite Item** through the same resume-mode resolver path as the favorites page, falling back to the favorites tab when the item no longer exists.
- **Favorite Update Notification** state is device-local platform state; like update tracking baselines and events, it is never carried by WebDAV sync.
