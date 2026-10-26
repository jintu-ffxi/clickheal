# Changelog

## 1.0.2

- The cast progress bar no longer jumps back and restarts when you start a cast. It now follows the game's own cast bar and waits for it to start.
- Faster and lighter in game: the party is read about 15 times a second instead of every frame, and the per-frame drawing work and memory churn are roughly halved. No visible change.
- Fixed memory that could keep growing while dragging the scale or changing opacity, and a status icon being released while still on screen.

## 1.0.1

- Casts are no longer echoed to the chat log (the game already shows them).
- Chat messages no longer carry a duplicate `[ClickHeal]` tag, and blocked-click messages no longer say "demo" on a real party.

## 1.0.0

First release.

- Party and alliance frames (6, 12 or 18 members) with HP, MP, job, distance and status effects.
- Hover spell menu: HEAL / CLEAN / BUFF / RAISE, plus SONG and ABIL on your own row. One click casts.
- Only spells you can use are offered (job level, sub job at half level, learned spells). Optionally show the rest greyed out.
- Default menus for White Mage, Scholar, Red Mage, Paladin, Black Mage and Bard (sub job support).
- Alert bar, triage view, solid and hairline looks (hairline is the default), columns / stacked / rows layouts.
- Status effects from the game's party packets, then party memory, then the chat log.
- Demo mode with a fake party; demo members never cast.
- Setup panel (`/ch`) with a Commands page. Commands: show/hide, lock/unlock, scale, mode, orient, demo, status, reset, apicheck, help.
