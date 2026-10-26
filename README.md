# ClickHeal

Click-to-heal party and alliance frames for **Final Fantasy XI** on **Ashita v4** (written for CatsEyeXI, but nothing in it is server specific). Inspired by Windower's Nostrum; this is a ground-up rewrite on Ashita's built-in ImGui, not a port.

**Status: Phase 1 - interface shell, demo data only.**

| | Phase 1 (this) |
|---|---|
| Draws party / alliance frames, job, HP/MP, distance, debuff badges, spell buttons, alert bar | yes |
| Setup panel, `/ch` commands, scaling to 4K, three layouts | yes |
| Reads the real party from the game | **no** (demo data) |
| Sends any command or packet to the game | **no** - a click only logs what it *would* cast |

## Read this before you load it on a live server

CatsEyeXI's published policy is that addons/plugins not on its approved list are not allowed. ClickHeal is not on that list, and being harmless does not change that. Phase 1 never reads game memory and never sends anything, but it is still an unlisted addon.

- Get staff approval before loading it on the live server (offering the source for review is the strongest thing you can do), **or**
- test it on a private server you run yourself (for example LandSandBoat with a normal Ashita v4 install), where no one else's rules apply.

`tests/` and `tools/` need no game at all.

## Preview

Rendered by the real drawing code (`tools/dump_draw.lua` + `tools/preview.py`). They are a faithful replay of what the addon asks ImGui to draw, **not screenshots** - the game's own font will look slightly different.

| Full, party | Full, 18 members | Compact, 18 members |
|---|---|---|
| ![](docs/preview/full_party_1080.png) | ![](docs/preview/full_alliance2_1080.png) | ![](docs/preview/compact_alliance2_1080.png) |

Also in `docs/preview/`: the tooltip, the minimal style's hover reveal, the color-blind palette, and a 4K render.

What the frames show:

- **Job / sub / level** chip per member, colored by role (healer, tank, DD, caster, support).
- **Distance** in yalms. Grey normally, **yellow** near the heal-range limit, **red** past it - and the whole card dims with an **OUT OF RANGE** banner (or **OTHER ZONE**).
- **Debuff badges** (`PAR`, `PSN`, `DOM`...). The matching cure (Paralyna for Paralysis, Cursna for Doom...) jumps to the front of that member's spell row with a pulsing outline.
- **Priority alert bar**: Doom / Petrify / Sleep / Terror first, then Silence / Paralysis, then the minor ones; low-HP and KO'd members too. Click an alert to cast its suggested spell; right-click to hide it for 25 s.
- **Spell buttons**: left click = that spell, right click = one tier down, Shift+click = one tier up (Cure IV: RMB = Cure III, Shift = Cure V). Cooldown sweep + timer, "not enough MP" tint, grey when out of range or KO'd. Hover for a tooltip with the target, status and bindings.
- **KO'd members** show Raise buttons instead.

### Screen footprint (1080p; the percentages are the same at 1440p and 4K)

The UI scales with the game window height (`scale = height / 1080 x your multiplier`), so it covers the same share of the screen at any resolution.

| Layout | Party (6) | Party + 1 alliance (12) | Party + 2 alliances (18) |
|---|---|---|---|
| **Full** | 290 x 474 px (15.1% x 43.9%) | 588 x 487 (30.6% x 45.1%) | 886 x 487 (46.1% x 45.1%) |
| Full, buff strip off (`/ch buffs off`) | 290 x 408 (15.1% x 37.8%) | 588 x 421 (30.6% x 39.0%) | 886 x 421 (46.1% x 39.0%) |
| **Compact** | 320 x 204 (16.7% x 18.9%) | 648 x 217 (33.8% x 20.1%) | 976 x 217 (50.8% x 20.1%) |
| **Minimal** | 210 x 192 (10.9% x 17.8%) | 428 x 205 (22.3% x 19.0%) | 646 x 205 (33.6% x 19.0%) |

Regenerate with `lua tools/footprint.lua`. Spell buttons are never smaller than 24 px at 1080p (48 px at 4K).

### Strip layout with the hover flyout (default)

- **Rows** are styled after YunaUI's party list: a coloured job block, a slanted row with the NAME, small distance and percentage, debuff tags, and two thin glowing bars (HP soft white, MP blue). The slant uses `AddQuadFilled`; if your Ashita build lacks it the rows fall back to square (check `/ch apicheck`).
- **Hover a row** and a flyout opens beside it with that member's spells, grouped HEAL / CLEAN / BUFF / RAISE. One click on a tile casts it on that member; no arming, no pinning. Move the mouse onto the flyout and it stays open; leave both and it closes after a split second. Near the screen edge it flips to the other side.
- **Your own row** also shows your job abilities (ABIL: Divine Seal, Benediction for White Mage; Light Arts, Celerity, Accession ... for Scholar; Convert, Composure, Chainspell for Red Mage).
- **What the member needs is outlined** in the flyout (Cursna for Doom, Silena for Silence, Raise for a KO'd member); positions never change, so muscle memory works.
- **Order is yours and the same for every member**: `/ch order heal cure1 cure2 cure3 cure4 curaga3`, `/ch order <group> reset`, or the setup panel's Order tab (arrows, remove, add).
- **Debuff tags** are short (SIL, PAR, DOM), worst first, `+N` when there are too many. No countdown on the row; hover the tags for the full list with times and the curing spell. A member with a critical or important debuff gets an outline.
- **Grid** (`/ch layout grid`) is the same flyout with WoW-style fill-the-cell bars. The old shared bar (`/ch bar on`) and plain-click bindings (`/ch cellbinds on`, `/ch bind ...`) are still available, off by default.
- `/ch flyout off` turns the flyout off. **Unverified in game:** that a second small ImGui window can sit beside the panel and take clicks, and the quad calls. Phase 0 will tell.

### Buffs, timers, heal/buff mode

- **Buff pips** sit under each HP bar on the Full layout: a short label (Hst, Rgn, Pro...) with a thin line that shrinks with the timer. Amber under 30 s, pulsing under 10 s. By default only buffs your job can cast are shown (`/ch mybuffs off` shows all). Click a pip to recast that buff on that member.
- **Debuff chips** show seconds left (PAR 0:41) when there is room.
- **HEAL / BUFF switch** in the title bar (or `/ch buffmode`): the spell row shows the job's buff spells instead of heals and cleanses.
- **Ctrl+click** a Cure tile for the matching Curaga.
- **Job display:** `/ch job text` (WHM/SCH 99) or `/ch job tag` (job chip + sub job; healers' chips are highlighted).
- Compact and Minimal layouts show debuff timers but no buff pips (no room).
- Alliance members' buffs and debuffs are only drawn if the game exposes them (not known yet); the demo hides them.
- Spell list is limited to the 75-era catalog (Cure I-V, Curaga I-IV, Regen I-III, Raise I-III, Haste, Protectra/Shellra, Refresh, Phalanx, ...). Levels come from public wikis; CatsEyeXI may differ. Job abilities are defined in `ch/spells.lua` but not drawn yet.

## Install (once you are allowed to)

1. Copy the folder `addons/clickheal` into your Ashita install's `addons` folder, so you have `Ashita/addons/clickheal/clickheal.lua`.
2. In game: `/addon load clickheal`
3. `/ch` opens the setup panel.

First-run tips: the frames start **locked** (clickable, fixed in place) at the left of the screen. `/ch unlock` lets you drag the frames and the alert bar anywhere; `/ch lock` when you are done (clicking spells is off while unlocked, so a drag can never cast).

## Commands

```
/ch                      open / close the setup panel
/ch show | hide          show or hide the frames
/ch lock | unlock        lock = clickable, unlock = drag to move
/ch scale <0.5-4|auto>   size multiplier (auto = follow game resolution)
/ch layout <full|compact|minimal>
/ch mode <party|alliance1|alliance2>   (or 6 / 12 / 18)
/ch orient <columns|stacked|rows>
/ch demo [on|off]        demo data (Phase 1 only has demo data)
/ch alerts [on|off]      priority alert bar
/ch colors <modern|mono|colorblind>
/ch reset confirm        restore every setting to defaults
/ch apicheck             report which Ashita/ImGui calls this install supports
/ch help
```

Settings are saved per character through Ashita's `settings` library.

## Developing

Needs a Lua interpreter on PATH only for the tests (Lua 5.1-5.4 or LuaJIT). On Windows: `scoop install lua` or `choco install lua`.

```
.\tools\test.ps1          # or: sh tools/test.sh   (VS Code: Terminal > Run Task > "Test: unit tests")
lua tools/footprint.lua   # screen footprint table
lua tools/dump_draw.lua preview_json && python tools/preview.py preview_json preview_png
```

Git: `git init`, `git add .`, `git commit`. `.gitattributes` keeps line endings stable on Windows. In VS Code, install the recommended **Lua** extension (sumneko); `.luarc.json` already declares the Ashita/ImGui globals.

### How it is put together

```
addons/clickheal/
  clickheal.lua        Ashita entry: events, /ch command, settings, per-frame glue
  ch/
    layout.lua         scaling + geometry (pure)            \
    spells.lua         spell defs, presets, click bindings   |
    spellstate.lua     ready / recast / no MP / range ...    |  pure Lua,
    alerts.lua         debuff + HP + KO alert list           |  unit-tested
    debuffs.lua        debuff -> severity -> suggested spell |  without the game
    jobs.lua theme.lua chconfig.lua commands.lua actions.lua /
    frame.lua          builds everything one frame needs (shared by game, tests, previews)
    ui.lua             draws through a tiny gfx interface; never touches ImGui directly
    gfx_imgui.lua      the in-game backend (Ashita ImGui)         <- not testable offline
    gfx_record.lua     recording backend for tests / previews
    configui.lua       the /ch setup panel                        <- not testable offline
    source_demo.lua    fake party/alliance data
    apicheck.lua       /ch apicheck
tests/run.lua          unit + UI tests (84)
tests/smoke_ashita.lua the Ashita glue against stubbed ashita/imgui/settings (13)
tools/                 footprint table, preview renderer, test runners
docs/preview/          rendered previews
docs/LOCAL_TEST_SERVER.md  plan: private LandSandBoat server for safe testing
```

The split is deliberate: `ui.lua` draws through `gfx`, so the *same drawing code* runs in the game (ImGui) and in the tests/previews (recorder). Only `gfx_imgui.lua`, `configui.lua` and `clickheal.lua` touch Ashita, and `/ch apicheck` probes everything they rely on.

## What is verified and what is not

**Verified offline** (84 + 15 tests, plus mutation checks that deliberately re-introduce bugs to confirm the tests catch them): layout maths and resolution independence, no overlapping cards, nothing drawn outside its card or panel, header text never collides, button size minimums, click -> spell resolution (right / Shift), alert ordering/muting/dismissal, spell state precedence, target tokens for all 18 slots, command parsing, settings repair, and that the Ashita glue keeps every Begin/End and Push/Pop balanced even when a call throws.

**Not verified - needs a real Ashita v4 build:**

- That the ImGui calls in `gfx_imgui.lua` / `configui.lua` match the Ashita v4 Lua bindings exactly (argument shapes, constants, how `GetIO().DisplaySize` and the modifier keys are exposed). They are written from knowledge of the API. **Run `/ch apicheck` first** and it will list anything missing on your build.
- How the real ImGui font measures text. Use the *Text size* slider if text looks cramped.
- All status ids and suggested spells in `ch/debuffs.lua` are defaults to confirm against CatsEyeXI, and all spell costs/recasts in `ch/spells.lua` are demo placeholders until Phase 2 reads them from the game's resource data.

## Known limitations / design notes

- **Alliance debuffs.** As far as I know the game only reports status effects for your own party, not alliance parties 2 and 3. If that holds, alliance cards will show job, HP, MP and distance but no debuff badges or debuff alerts. The demo has a switch to pretend otherwise (`demo_alliance_debuffs`). Phase 0 should confirm this; a workaround (tracking status from combat-log messages) is a possible Phase 3 item.
- **Heal range** defaults to 20 yalms (configurable). Per-spell ranges are a later refinement.
- The alert bar suggests; it never casts anything by itself. Every cast will be one deliberate click.

## Roadmap

| Phase | What |
|---|---|
| **0** | On your install: `/ch apicheck`; confirm party/alliance memory access, job and distance fields, who exposes buffs, recast/MP data. Needs permission to load on a live server, or a local test server. |
| **1** | **Done** - UI shell on demo data. |
| **2** | Real party data (`source_game.lua` returning the same member shape), real spell availability / MP / recast from resource data, and real casting: one click = one normal `/ma` command. |
| **3** | Real debuff tracking, per-job profiles, drag-to-reorder spell sets in the panel, icons, first-run wizard. |
| **4** (optional) | WoW-style mouseover on 3D characters (world-to-screen hit testing). |
