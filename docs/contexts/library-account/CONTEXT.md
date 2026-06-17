# YamiboReader Library and Account Context

Domain language for favorites, reading metadata, Yamibo accounts, profiles, and sign-out semantics.

## Language

**Favorite Library**:
The local projection of Yamibo remote favorites plus user-owned reading metadata, display names, hidden state, and collections.
_Avoid_: favorite store, favorites snapshot, favorites list

**Yamibo Account**:
The authenticated Yamibo forum identity represented by UID, display name, profile, user group, and forum credit totals.
_Avoid_: app account, local user, session

**Yamibo Profile**:
The Yamibo forum profile data for one **Yamibo Account**, including public identity, avatar, user group, and forum credit fields.
_Avoid_: personal homepage, profile web page, account card

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

## Relationships

- A **Favorite Library** is remote-favorite-first: Yamibo remote favorites decide which remote-backed favorite entries exist, while local metadata preserves user-owned reading and organization state for those entries.
- A **Favorite Library** persists a novel's **Novel Reading Position** through its semantic resume point and reader page document view; it never stores a novel runtime surface ordinal or displayed page number.
- Manga page persistence uses the manga-specific `mangaPageIndex` Interface. The historical JSON key `lastPage` may remain as a schema compatibility key, but it is not a Swift Interface and is never written from novel reading.
- When a Yamibo remote favorite disappears, the **Favorite Library** removes it from the visible library and archives its local metadata so a later remote re-add can restore reading position, display name, hidden state, and collection membership.
- Archived **Favorite Library** metadata is synchronized through WebDAV with the visible library because reading position and organization state are user-owned data.
- Archived **Favorite Library** metadata is matched by canonical thread URL, not Yamibo remote favorite ID, because a remote favorite ID can change when the same thread is removed and re-added.
- When archived **Favorite Library** metadata restores a favorite whose collection no longer exists, the favorite is restored at the root while preserving display name, hidden state, and reading positions.
- **Mine Home** presents the current **Yamibo Account** through its **Yamibo Profile**.
- A **Yamibo Profile** identifies the account's current **Yamibo User Group** and forum credit totals.
- **Forum Credit Progress** uses the account's total forum credits and the next **Yamibo User Group** threshold.
- **Mine Home** may show a cached **Yamibo Profile** while refreshing it, and a failed refresh does not end the **Yamibo Account** authentication state.
- A **Security Question** may be required to authenticate a **Yamibo Account**.
- A **Yamibo Account** stores authentication state in the app, not the account password.
- **Yamibo Sign Out** clears current authentication and cached profile state without clearing the **Favorite Library** or reading settings.
