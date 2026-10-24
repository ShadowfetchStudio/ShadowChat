# Changelog

## 3.0 — Classic messenger upgrade (2026-10-24)

### Added
- Synthesized door-open, door-close, incoming-message, and send sounds, with a Sounds preference.
- Away messages with saved presets, `%n` / `%t` / `%d` codes, a sticky-note icon, an away banner in IM windows, and automatic return when you send.
- Buddy List menu strip (My ShadowChat / People / Help) and a status header with an Available / Away picker and unread total.
- Sign-on and sign-off door icons, idle times for quiet bridge programs, and a "signed on at" ticker in the footer.
- "is typing…" / "Last message received at…" strip under every transcript; `✎ typing…` in the Buddy List.
- Optional timestamps, smileys drawn as faces, a text color menu, and a smiley picker.
- Unread counts per room, a Dock badge, a Dock bounce in the background, and windows that open for new messages.
- Auto sign on, Show Connect window at launch, and Open windows for new messages preferences.
- `⌘,`, `⇧⌘L`, `⇧⌘K`, `⇧⌘A`, `⇧⌘T` shortcuts and a People menu in the menu bar.
- `ClassicFeatureTests`.

### Changed
- Setup and Away Message open as single windows instead of a sheet on every open window.
- The transcript only follows new lines when you are already at the bottom.
- ShadowChat system notices render in grey italics; an empty streaming reply is hidden behind the typing strip.
- The IM message box takes focus when the window opens.
