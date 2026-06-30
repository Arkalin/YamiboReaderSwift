# YamiboReader Library and Account Context

Domain language for favorites, reading metadata, Yamibo accounts, profiles, and sign-out semantics.

## Language

**Favorite Library**:
The local projection of Yamibo remote favorites plus user-owned reading metadata, display names, hidden state, and collections.
_Avoid_: favorite store, favorites snapshot, favorites list

**Reading Progress Store**:
The device-local source of truth for per-thread novel and manga reading position, independent from whether the thread is currently visible in the **Favorite Library**.
_Avoid_: favorite progress, archive progress, recent route

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

## Relationships

- A **Favorite Library** is remote-favorite-first: Yamibo remote favorites decide which remote-backed favorite entries exist, while local metadata preserves user-owned reading and organization state for those entries.
- The **Reading Progress Store** owns current local reading position for novels and manga. Removing a visible favorite does not remove the matching **Reading Progress Store** record.
- Visible **Favorite Library** entries may mirror the **Reading Progress Store** reading position for favorite-list display and existing WebDAV favorite payload compatibility, but reader resume should prefer the **Reading Progress Store**.
- The **Reading Progress Store** is device-local in the current schema and is not part of the WebDAV sync payload.
- A **Favorite Library** persists a novel's **Novel Reading Position** through its semantic resume point and reader page document view; it never stores a novel runtime surface ordinal or displayed page number.
- Manga page persistence uses the manga-specific `mangaPageIndex` Interface. The historical JSON key `lastPage` may remain as a schema compatibility key, but it is not a Swift Interface and is never written from novel reading.
- When a Yamibo remote favorite disappears, the **Favorite Library** removes it from the visible library and archives its local metadata so a later remote re-add can restore reading position, display name, hidden state, and collection membership.
- Archived **Favorite Library** metadata is synchronized through WebDAV with the visible library because reading position and organization state are user-owned data.
- Archived **Favorite Library** metadata is matched by canonical thread URL, not Yamibo remote favorite ID, because a remote favorite ID can change when the same thread is removed and re-added.
- When archived **Favorite Library** metadata restores a favorite whose collection no longer exists, the favorite is restored at the root while preserving display name, hidden state, and reading positions.
- **Mine Home** presents the current **Yamibo Account** through its **Yamibo Profile**.
- **Mine Home** may expose manga offline cache progress, grouped by **Favorite Library** entry, while the offline cache work remains owned by the Manga Reader context.
- **Mine Home** represents pending manga offline cache activity by unfinished chapter work count, not by completed cached chapters or favorite group count.
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
