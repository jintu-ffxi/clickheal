# ClickHeal - Handoff

A click-to-heal party/alliance frame for FFXI on **Ashita v4**, in the spirit of Nostrum, built with ImGui. Written in Lua. Target server: CatsEyeXI (custom Ashita v4). Current phase: **Phase 1 - UI shell on demo data. Nothing has run in-game yet.**

## 1. Hard constraints (read first)

- **CatsEyeXI does not allow unlisted addons.** Do not load ClickHeal on the live server without staff approval.
- Testing happens on the owner's own **local LandSandBoat (LSB) private server**: `docs/LOCAL_TEST_SERVER.md` (native) or `docs/LOCAL_TEST_SERVER_PODMAN.md` (Podman on Windows 11 / WSL2). The Podman PATH problem after `winget install` is solved.
- **Casting is opt-in.** `ch/actions.lua` builds one `/ma` or `/ja` per click and hands it to `ctx.send` (`QueueCommand`), but only when `/ch cast on` AND `/ch demo off` AND the button was ready. Default is off; otherwise a click only logs. Never enable it on CatsEyeXI without staff approval.
- **Real data (read-only):** `ch/source_game.lua` reads party/alliance, distance, zone and your own buffs from Ashita memory. Other members' buffs/debuffs and spell recasts are not read yet. Verified in-game on the local LSB server: roster, hover flyout, clicks reach the flyout.
- Local LSB is similar to, not identical to, CatsEyeXI. "Works locally" does not mean "works on CatsEyeXI".

## 2. Requirements (from the owner)

- Click-cast on party and alliance (1-2 alliance parties), 18 slots.
- Modern UI that scales to 4K; `/ch` command line plus an in-game setup panel.
- Show each member's job and distance, with an out-of-range indication.
- Debuffs shown on the member's own bar (several at once), with priority handling (e.g. Paralyze -> Paralyna). Buff timers on the bars. Curaga.
- 75-era spell cross-reference for WHM / RDM / SCH, including job abilities.
- Must be readable at a glance while healing in real time; not cluttered.

## 3. Design decisions already made

| Topic | Decision |
|---|---|
| Look | YunaUI-style strip: coloured job block, slanted row, name in caps, small distance, HP %, thin glowing HP bar and blue MP bar. |
| Click model | **Hover a row -> a flyout opens beside it** with that member's spell/ability buttons. Click a button = cast on that member. No pinning. |
| Own character | Hovering your own row shows your abilities (self JAs such as Divine Seal, Benediction). |
| Debuffs | Short tags on the bar, severity-sorted, "+N" overflow. **No countdown on the chip**; times and the curing spell appear only in the hover tooltip. |
| Alert window | The far-right alert window is off by default (`alerts.enabled=false`). Debuffs live on the bars. |
| Spell order | Configurable per group (cure / curaga / buffs / ...), **identical for all members**. |
| Layouts | **Strip only.** Full, Compact, Minimal and Grid were removed. Alliance (12/18) uses the same strip rows, one column per party. Right-click = tier down, Shift = tier up, Ctrl = matching Curaga on the flyout tiles. Row width/height, debuff and buff icon sizes are settings (`row_w`, `row_h`, `debuff_icon`, `buff_icon`). A second icon strip shows buffs (`show_buff_bar`). |
| Casting | `ch/casting.lua`: a spell is busy for its cast time (LSB `castTime`, shortened by Fast Cast) plus a short delay; abilities only the delay. Haste does not shorten spell casting; spell recast timers already come from the game. The game's cast bar (`GetCastBar():GetPercent()`, unverified, see `/ch apicheck`) overrides the estimate when readable. A click made while busy is held (one slot, newest wins, 5 s) and sent when free (`queue_clicks`). `/ch status` lists the switches that decide hover and clicks. |
| Palette and job icons | `colors = job` tints the healthy HP fill with each member's job color (still yellow/orange/red as HP drops). `job_icon` draws an original vector pictogram (`ch/jobicons.lua`) instead of the letters; no image files or texture API needed. |
| Optional | Shared spell bar (arm then click) and per-cell click bindings (`cell_binds`, `/ch bind`), both off by default. |
| Catalog | 75-era only, WHM / RDM / SCH / BLM / BRD (+PLD cures). Levels, MP and recasts come from the LandSandBoat `spell_list` / `abilities` tables (CatsEyeXI's base), not from CatsEyeXI itself. Phase 2 still replaces them with in-game resource data. |
| Learned spells | `spells.fit(preset, player)` (called in `frame.build`) keeps only what main job, or sub job at half level (37 at the cap), can cast; unlearned tiers fall back to the next lower one via `def.down`. Demo player is WHM/SCH 75/37. |
| Self-only spells | `def.selfonly` (Blink, Stoneskin, Aquaveil, Phalanx, Protectra/Shellra, Reraise, bar-spells, enspells, songs...): the tile shows on every row but a click casts on `<me>`. |
| Groups | heal / cleanse / buff / raise on every row; `song` and `ability` only on your own row (`spells.SELF_GROUPS`). BRD songs live in `preset.songs`. |

## 4. Repository map

```
addons/clickheal/clickheal.lua   Ashita entry: load/unload/command/d3d_present; surfaces
                                 'ClickHeal', 'ClickHeal Alerts', 'ClickHeal Flyout'
addons/clickheal/ch/
  layout.lua       scaling + geometry (pure). STRIP, FLYOUT, compute, flyout_position, alert_bar
  frame.lua        settings + source + display size + time -> everything one frame needs
  ui.lua           all drawing via gfx; draw_strip, debuff/buff icon strips, flyout state machine
  gfx_imgui.lua    in-game backend (NOT testable offline)
  gfx_record.lua   recording backend (tests, previews)
  configui.lua     /ch setup panel (NOT testable offline)
  spells.lua       catalog, presets (WHM/SCH/RDM/PLD/generic), group_keys, resolve
  spellstate.lua   ready / recast / no MP / range / silence
  bindings.lua     click slots -> spell resolution
  buffs.lua  debuffs.lua  alerts.lua   buff/debuff info, severity, suggested cure
  theme.lua  jobs.lua                  palettes, job colours/abbreviations
  chconfig.lua     defaults + sanitize (settings repair)
  commands.lua     /ch parser
  actions.lua      click events (log-only in Phase 1)
  source_demo.lua  fake roster; real source (source_game.lua) must return the same member shape
  apicheck.lua     /ch apicheck probes
tests/run.lua            84 unit/UI tests (keep the summary/exit tail at END of file)
tests/smoke_ashita.lua   15 tests against stubbed ashita/imgui/settings
tools/                   dump_draw.lua, preview.py, footprint.lua, test.sh, test.ps1
docs/                    README-level docs, LOCAL_TEST_SERVER*.md, preview/*.png, this file
```

Architecture rule: `ui.lua` never touches ImGui; it draws through `gfx`. Only `gfx_imgui.lua`, `configui.lua` and `clickheal.lua` touch Ashita. Scale = (display height / 1080) x user multiplier.

Member shape (what a real data source must return): `slot 0..17, active, name, job, sub, level, hp, hpmax, hpp, mp, mpmax, mpp, dist, zone_diff, dead, debuffs[], debuff_rem{}, buffs[{key,rem,total}], has_buff_data, is_you`. Target tokens: `<me>`, `<p1>-<p5>`, `<a10>-<a15>`, `<a20>-<a25>`.

## 5. Commands

`/ch` show|hide, lock|unlock, scale, mode, orient, demo, cast, slant, rowsize, icons, buffbar, mybuffs, jobicons, queue, fastcast, lockout, status, buttons, buffmode, flyout, order, bar, tab, cellbinds, bind, binds, reset, partydump, apicheck, help. Setup panel pages: Layout, Appearance, Flyout, Spells, Bindings, Alerts, General (sidebar; every control is sized from measured text, see `tests/config_layout.lua`).

Flyout is drawn only when the window is visible **and locked** and `flyout` is on.

## 6. Run the tests and previews

```
sh tools/test.sh            # or .\tools\test.ps1  (needs a Lua 5.1-5.4/LuaJIT, or texlua)
lua tools/footprint.lua
lua tools/dump_draw.lua preview_json && python tools/preview.py preview_json preview_png
```

Previews are a **replay of draw commands**, not game screenshots. Status at handoff: 84 unit + 15 smoke tests pass.

## 7. Verified vs unverified

**Verified offline:** layout maths and resolution independence, no overlaps, click -> spell resolution, ordering, flyout placement/flip/clamp, alert logic, settings repair, Begin/End and Push/Pop balance in the stub test.

**Verified offline:** 90 unit tests (new: catalog sanity, level/sub-job fit, self-only casting, bard song row). Lua can be installed with `winget install DEVCOM.Lua`; it lands in `%LOCALAPPDATA%\Programs\Lua\bin` and may need adding to PATH.

**Unverified (nothing has run in-game):**
- Ashita v4 ImGui Lua binding shapes (constants, `GetIO().DisplaySize`, modifier keys). `/ch apicheck` lists what is missing.
- Draw-list `AddQuadFilled`/`AddQuad` (strip falls back to a bounding rect if absent).
- Whether a second ImGui window (the flyout) receives clicks reliably.
- Status ids and suggested cures in `debuffs.lua`; spell costs/recasts/levels in `spells.lua`; job-ability levels.
- Whether alliance parties 2/3 expose buffs/debuffs (probably not).
- RDM Erase / -na: the LSB data gives RDM **no** -na spells and no Erase at 75 (RDM cleanse tab is empty). Confirm on CatsEyeXI.
- Song MP is 0 in the source table; Haste is WHM 40 / RDM 48 per that table. CatsEyeXI may differ.
- Regenerate `docs/preview/*.png`: the mockup flyout now differs (self-only tiles, RR3 instead of RR1, RDM empty cleanse); `tools/preview.py` needs Python, which isn't installed here.
- Real font metrics; game-icon loading.
- LSB GM commands for level/spells and UDP behaviour under Podman (see the server docs; marked [check]).

## 8. Roadmap

| Phase | Work |
|---|---|
| **0** | On the local server: `/ch apicheck`; fix binding mismatches; confirm party/alliance memory access, job/distance, buff exposure, recast/MP data. **Gate for everything below.** |
| **2** | `source_game.lua` with real data in the member shape; filter spells by learned/level; real MP & recast; real casting (one click = one normal `/ma` or `/ja`), only after Phase 0 and approval. |
| **3** | Real debuff tracking (maybe from combat-log messages for the alliance); own redrawn icons; per-job default spell orders; Scholar arts/stratagem charges; Devotion targeting; buff-mode binding editing; first-run wizard. |
| **4** | Optional WoW-style mouseover on 3D characters. |

## 9. Open questions for the owner

- Preferred default spell lists/order per job (WHM, SCH, RDM, BLM, BRD). Current BRD song default: Minuet IV/III, Victory/Advancing March, Blade Madrigal, Ballad II, Minne IV, Archer's Prelude, Dragonfoe Mambo, Paeon V.
- Flyout button count/width for alliance members.
- Confirm RDM -na/Erase availability on CatsEyeXI.

## 10. Practical notes for the next developer

- Work on copies; no git repo exists yet (`git init` locally; `.gitattributes` and `.luarc.json` are included).
- Don't add command-sending code until Phase 0 passes; keep the demo `cast` path intact for tests.
- When changing `ui.lua`, regenerate previews and run both test files; mutation checks were used to confirm tests catch regressions.

## Row styles and Triage
- `skin = 'hairline'` (`/ch skin hairline`): no card, job-colored line, large HP percentage colored by health
  (`pct_scale`), thin HP rail with a damage trail, MP hairline. Large text uses `gfx.text_scaled`
  (draw list font-size overload, UNVERIFIED in game; falls back to normal size if the call fails).
- `triage = true` (`/ch triage on`): one panel for the neediest eligible member (`ch/triage.lua`), a best-fit cure
  tile row, and a compact list of everyone else. Cure potencies in `triage.POTENCY` are rough estimates, not game data.
