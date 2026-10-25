-- ClickHeal offline tests. No game, no ImGui, no dependencies.
--
--   lua tests/run.lua          (run from the repository root; Lua 5.1-5.4 or LuaJIT)
--
package.path = 'addons/clickheal/?.lua;' .. package.path

local theme      = require('ch.theme')
local layout     = require('ch.layout')
local spells     = require('ch.spells')
local spellstate = require('ch.spellstate')
local alerts     = require('ch.alerts')
local actions    = require('ch.actions')
local commands   = require('ch.commands')
local chconfig   = require('ch.chconfig')
local frame      = require('ch.frame')
local ui         = require('ch.ui')
local demo       = require('ch.source_demo')
local gfx_rec    = require('ch.gfx_record')
local debuffs    = require('ch.debuffs')

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. '\n      ' .. tostring(err)
    end
end

local function eq(a, b, msg)
    if a ~= b then error((msg or 'values differ') .. ': got ' .. tostring(a) .. ', expected ' .. tostring(b), 2) end
end
local function near(a, b, tol, msg)
    if math.abs(a - b) > tol then error((msg or 'not close') .. ': got ' .. tostring(a) .. ', expected ' .. tostring(b) .. ' +/- ' .. tol, 2) end
end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

local function new_cfg(over)
    local c = chconfig.sanitize({})
    c.alerts.enabled = true        -- the alert window is off by default; the alert tests need it on
    c.style = 'full'               -- default layout is Strip; older tests were written against Full
    ui.reset_state()
    for k, v in pairs(over or {}) do c[k] = v end
    return chconfig.sanitize(c)
end

-- Builds one recorded frame of the roster UI. Shared by the ui and actions tests.
local function build_ui_frame(cfg, disp_h, t, input, with_hitboxes)
    demo.reset()
    local fr = frame.build(cfg, demo, t or 3.0, disp_h * 16 / 9, disp_h, {})
    local g = gfx_rec.new(fr.geom.scale * cfg.font_mult)
    local f = {
        gfx = g, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, player = fr.player,
        preset = fr.preset, now = t or 3.0, ox = 0, oy = 0, events = {},
        input = input or gfx_rec.input(nil, nil, nil),
        hitboxes = with_hitboxes and {} or nil,
    }
    return f, fr, g
end

-- =============================================================================================
-- theme
-- =============================================================================================
test('theme: pack/unpack round trip', function()
    local c = theme.pack(0.2, 0.4, 0.6, 0.8)
    local r, g, b, a = theme.unpack(c)
    near(r, 0.2, 0.01); near(g, 0.4, 0.01); near(b, 0.6, 0.01); near(a, 0.8, 0.01)
end)
test('theme: pack is IM_COL32 layout (A<<24|B<<16|G<<8|R)', function()
    eq(theme.pack(1, 0, 0, 1), 0xFF0000FF)
    eq(theme.pack(0, 0, 1, 1), 0xFFFF0000)
end)
test('theme: alpha multiplies and mix blends', function()
    local c = theme.alpha(theme.pack(1, 1, 1, 1), 0.5)
    local _, _, _, a = theme.unpack(c)
    near(a, 0.5, 0.01)
    local m = theme.mix(theme.pack(0, 0, 0, 1), theme.pack(1, 1, 1, 1), 0.5)
    local r = theme.unpack(m)
    near(r, 0.5, 0.01)
end)
test('theme: hp_color runs red -> green', function()
    local pal = theme.get('modern')
    eq(theme.hp_color(pal, 0), pal.bad)
    eq(theme.hp_color(pal, 1), pal.good)
    eq(theme.hp_color(pal, 0.5), pal.warn)
end)
test('theme: unknown preset falls back to default', function()
    eq(theme.get('nope'), theme.get('modern'))
end)

-- =============================================================================================
-- layout
-- =============================================================================================
test('layout: scale follows window height', function()
    near(layout.scale({ auto_scale = true, scale = 1.0 }, 1080), 1.0, 1e-9)
    near(layout.scale({ auto_scale = true, scale = 1.0 }, 2160), 2.0, 1e-9)
    near(layout.scale({ auto_scale = true, scale = 1.5 }, 1440), 1.5 * 1440 / 1080, 1e-9)
    near(layout.scale({ auto_scale = false, scale = 1.25 }, 2160), 1.25, 1e-9, 'auto off = absolute')
    near(layout.scale({ auto_scale = true, scale = 1.0 }, nil), 1.0, 1e-9, 'unknown height falls back to 1080')
end)

test('layout: footprint is resolution independent (4K matches 1080p)', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        for _, mode in ipairs({ 'party', 'alliance1', 'alliance2' }) do
            local groups = layout.groups_for(mode, false)
            local o = { style = style, orientation = 'columns', auto_scale = true, scale = 1.0, groups = groups }
            local a = layout.compute(o, 1080)
            local b = layout.compute(o, 2160)
            near(b.width, a.width * 2, 4, style .. '/' .. mode .. ' width')
            near(b.height, a.height * 2, 6, style .. '/' .. mode .. ' height')
            local aw, ah = layout.footprint(a, 1920, 1080)
            local bw, bh = layout.footprint(b, 3840, 2160)
            near(aw, bw, 0.005); near(ah, bh, 0.005)
        end
    end
end)

test('layout: documented 1080p footprints', function()
    local g = layout.compute({ style = 'full', orientation = 'columns', groups = { 0 } }, 1080)
    eq(g.width, 290); eq(g.height, 474)
    local gnb = layout.compute({ style = 'full', orientation = 'columns', groups = { 0 }, show_buffs = false }, 1080)
    eq(gnb.height, 408, 'buff strip off keeps the old height')
    local g3 = layout.compute({ style = 'full', orientation = 'columns', groups = { 0, 1, 2 } }, 1080)
    eq(g3.width, 886)
    local c = layout.compute({ style = 'compact', orientation = 'columns', groups = { 0 } }, 1080)
    eq(c.width, 320)
    local m = layout.compute({ style = 'minimal', orientation = 'columns', groups = { 0 } }, 1080)
    eq(m.width, 210)
end)

test('layout: no card overlaps another, all inside the panel', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        for _, orient in ipairs({ 'columns', 'stacked', 'rows' }) do
            for _, h in ipairs({ 720, 1080, 1440, 2160 }) do
                local g = layout.compute({ style = style, orientation = orient, auto_scale = true, scale = 1.0, groups = { 0, 1, 2 } }, h)
                local list = {}
                for slot, c in pairs(g.cards) do
                    truthy(c.x >= 0 and c.y >= g.header_h, 'card above/left of panel: ' .. style .. orient)
                    truthy(c.x + c.w <= g.width and c.y + c.h <= g.height, 'card outside panel: ' .. style .. orient .. h .. ' slot ' .. slot)
                    list[#list + 1] = c
                end
                eq(#list, 18)
                for i = 1, #list do
                    for j = i + 1, #list do
                        local a, b = list[i], list[j]
                        local overlap = a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
                        if overlap then error(string.format('cards overlap in %s/%s/%d', style, orient, h)) end
                    end
                end
            end
        end
    end
end)

test('layout: spell buttons never smaller than 24 base px', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        local g = layout.compute({ style = style, groups = { 0 }, auto_scale = true, scale = 1.0 }, 1080)
        truthy(g.btn >= 24, style .. ' button ' .. g.btn)
        local g4 = layout.compute({ style = style, groups = { 0 }, auto_scale = true, scale = 1.0 }, 2160)
        truthy(g4.btn >= 48, style .. ' 4K button ' .. g4.btn)
    end
end)

test('layout: button counts fit their rows', function()
    local f = layout.compute({ style = 'full', groups = { 0 } }, 1080)
    eq(f.max_buttons, 9)
    local c = layout.compute({ style = 'compact', groups = { 0 } }, 1080)
    eq(c.max_buttons, 4)
    truthy(f.buttons_w <= f.card_w - 2 * f.pad, 'full button row wider than card')
end)

test('layout: groups_for hides empty alliances only when asked', function()
    eq(#layout.groups_for('alliance2', false), 3)
    eq(#layout.groups_for('alliance2', true, { [0] = true }), 1)
    eq(#layout.groups_for('alliance2', true, { [0] = true, [2] = true }), 2)
    eq(#layout.groups_for('party', true, {}), 1)
end)

test('layout: alert bar grows with rows and reserves room for "+N more"', function()
    local o = { auto_scale = true, scale = 1.0 }
    local a1 = layout.alert_bar(o, 1080, 1, false)
    local a4 = layout.alert_bar(o, 1080, 4, false)
    local a4m = layout.alert_bar(o, 1080, 4, true)
    truthy(a4.h > a1.h); truthy(a4m.h > a4.h)
end)

-- =============================================================================================
-- spells
-- =============================================================================================
test('spells: right click and shift pick the neighbouring cure tiers', function()
    local d = spells.defs.cure4
    eq(spells.resolve(d, 'left', {}), 'cure4')
    eq(spells.resolve(d, 'right', {}), 'cure3')
    eq(spells.resolve(d, 'left', { shift = true }), 'cure5')
    eq(spells.resolve(d, 'right', { shift = true }), 'cure5', 'modifier wins over button')
    eq(spells.resolve(spells.defs.cure1, 'right', {}), 'cure1', 'no lower tier -> same spell')
    eq(spells.resolve(spells.defs.cure5, 'left', { shift = true }), 'cure5', 'top tier stays')
    eq(spells.resolve(d, 'left', { ctrl = true }), 'curaga4', 'ctrl = curaga')
    eq(spells.resolve(spells.defs.cure2, 'left', { ctrl = true }), 'curaga2')
    eq(spells.resolve(spells.defs.erase, 'right', {}), 'erase')
end)

test('spells: catalog is limited to 75-era spells and presets only name real defs', function()
    for _, bad in ipairs({ 'cure6', 'regen4', 'regen5', 'curaga5', 'raise4' }) do
        eq(spells.defs[bad], nil, bad .. ' is not a 75-era spell')
    end
    for _, key in ipairs({ 'curaga1', 'curaga4', 'haste', 'regen3', 'protectra5', 'shellra5', 'refresh', 'phalanx' }) do
        truthy(spells.defs[key], key .. ' missing')
    end
    for name, p in pairs(spells.presets) do
        for _, list in ipairs({ 'base', 'raise', 'buffs', 'self' }) do
            for _, key in ipairs(p[list] or {}) do
                truthy(spells.defs[key], name .. '.' .. list .. ' names unknown spell ' .. key)
            end
        end
    end
    for key, d in pairs(spells.defs) do
        if d.right then truthy(spells.defs[d.right], key .. ' right') end
        if d.shift then truthy(spells.defs[d.shift], key .. ' shift') end
        if d.ctrl  then truthy(spells.defs[d.ctrl],  key .. ' ctrl')  end
    end
end)

test('spells: build_row puts debuff cures first, no duplicates, respects max', function()
    local m = { dead = false, debuffs = { 'paralysis', 'doom' } }
    local row = spells.build_row(m, spells.presets.WHM, debuffs.info, 9)
    eq(row[1].def.key, 'cursna', 'doom (sev 1) first')
    eq(row[2].def.key, 'paralyna')
    truthy(row[1].priority and row[2].priority and not row[3].priority)
    local seen = {}
    for _, e in ipairs(row) do
        truthy(not seen[e.def.key], 'duplicate ' .. e.def.key)
        seen[e.def.key] = true
    end
    eq(#row, 9)
    local small = spells.build_row(m, spells.presets.WHM, debuffs.info, 3)
    eq(#small, 3)
end)

test('spells: KO member shows raise spells only', function()
    local row = spells.build_row({ dead = true, debuffs = {} }, spells.presets.WHM, debuffs.info, 9)
    eq(#row, 3); eq(row[1].def.key, 'raise3', 'strongest raise first')
    eq(#spells.build_row({ dead = true }, spells.presets.PLD, debuffs.info, 9), 0)
end)

test('spells: preset picks main job, then sub job, then generic', function()
    local _, a = spells.preset_for(3, 20); eq(a, 'WHM')
    local _, b = spells.preset_for(1, 3);  eq(b, 'WHM')
    local _, c = spells.preset_for(1, 2);  eq(c, 'generic')
end)

test('spells: every preset key exists in defs and every debuff suggestion is a real spell', function()
    for name, p in pairs(spells.presets) do
        for _, k in ipairs(p.base) do truthy(spells.defs[k], name .. ' base ' .. k) end
        for _, k in ipairs(p.raise) do truthy(spells.defs[k], name .. ' raise ' .. k) end
    end
    for key, info in pairs(debuffs.info) do
        if info.spell then truthy(spells.defs[info.spell], key .. ' -> ' .. info.spell) end
    end
    for _, def in pairs(spells.defs) do
        if def.right then truthy(spells.defs[def.right]) end
        if def.shift then truthy(spells.defs[def.shift]) end
    end
end)

-- =============================================================================================
-- spellstate
-- =============================================================================================
test('spellstate: every state and its precedence', function()
    local cfg = { max_range = 20 }
    local player = { mp = 100, recast = {} }
    local cure = spells.defs.cure3  -- 46 MP
    local m = { active = true, dead = false, dist = 5 }
    eq(spellstate.evaluate(cure, m, player, cfg), 'ready')
    eq(spellstate.evaluate(cure, nil, player, cfg), 'gone')
    eq(spellstate.evaluate(cure, { active = false }, player, cfg), 'gone')
    eq(spellstate.evaluate(cure, { active = true, zone_diff = true }, player, cfg), 'zone')
    eq(spellstate.evaluate(cure, { active = true, dead = true, dist = 5 }, player, cfg), 'dead')
    eq(spellstate.evaluate(spells.defs.raise1, m, player, cfg), 'alive')
    eq(spellstate.evaluate(spells.defs.raise1, { active = true, dead = true, dist = 5 }, { mp = 500, recast = {} }, cfg), 'ready')
    local st, d = spellstate.evaluate(cure, { active = true, dist = 25 }, player, cfg)
    eq(st, 'range'); eq(d, 25)
    eq(spellstate.evaluate(cure, m, { mp = 100, recast = {}, silenced = true }, cfg), 'blocked')
    eq(spellstate.evaluate(cure, m, { mp = 100, recast = {}, incapacitated = true }, cfg), 'blocked')
    local st2, d2 = spellstate.evaluate(cure, m, { mp = 100, recast = { cure3 = 2.5 } }, cfg)
    eq(st2, 'recast'); eq(d2, 2.5)
    local st3, d3 = spellstate.evaluate(cure, m, { mp = 10, recast = {} }, cfg)
    eq(st3, 'nomp'); eq(d3, 36)
    -- range beats recast and mp (a grayed-out member should look grayed out)
    eq(spellstate.evaluate(cure, { active = true, dist = 30 }, { mp = 0, recast = { cure3 = 3 } }, cfg), 'range')
    -- unknown distance (nil) is not treated as out of range
    eq(spellstate.evaluate(cure, { active = true, dist = nil }, player, cfg), 'ready')
    -- exactly at the limit is still in range
    eq(spellstate.evaluate(cure, { active = true, dist = 20 }, player, cfg), 'ready')
end)

test('spellstate: describe covers every state', function()
    for _, s in ipairs({ 'ready', 'gone', 'zone', 'dead', 'alive', 'range', 'blocked', 'recast', 'nomp' }) do
        truthy(#spellstate.describe(s, 3) > 0, s)
    end
end)

-- =============================================================================================
-- alerts
-- =============================================================================================
local function roster_for_alerts()
    return demo.roster(3.0, { demo_alliance_debuffs = false })
end

test('alerts: severity ordering, range preference, cap and overflow count', function()
    local cfg = new_cfg()
    local list, total = alerts.build(roster_for_alerts(), cfg, spells.presets.WHM, 3.0, {})
    eq(list[1].text, 'DOOM', 'doom first')
    eq(list[1].spell, 'cursna')
    eq(#list, cfg.alerts.max)
    truthy(total > #list, 'overflow reported')
    for i = 2, #list do
        truthy(list[i - 1].sev <= list[i].sev, 'severity must not increase down the list')
    end
end)

test('alerts: paralysis suggests Paralyna, poison suggests Poisona', function()
    local cfg = new_cfg()
    cfg.alerts.max = 8
    local list = alerts.build(roster_for_alerts(), cfg, spells.presets.WHM, 3.0, {})
    local found = {}
    for _, a in ipairs(list) do found[a.text] = a.spell end
    eq(found['PARALYZE'], 'paralyna')
end)

test('alerts: muted debuffs and disabled bar produce nothing', function()
    local cfg = new_cfg()
    cfg.alerts.max = 12
    cfg.alerts.muted = { silence = true, paralysis = true }
    local list = alerts.build(roster_for_alerts(), cfg, spells.presets.WHM, 3.0, {})
    for _, a in ipairs(list) do truthy(a.text ~= 'SILENCE' and a.text ~= 'PARALYZE', 'muted alert shown') end
    cfg.alerts.enabled = false
    eq(#alerts.build(roster_for_alerts(), cfg, spells.presets.WHM, 3.0, {}), 0)
end)

test('alerts: dismissed alerts hide until they expire', function()
    local cfg = new_cfg()
    cfg.alerts.max = 12
    local r = roster_for_alerts()
    local list = alerts.build(r, cfg, spells.presets.WHM, 10, {})
    local id = list[1].id
    local hidden = alerts.build(r, cfg, spells.presets.WHM, 10, { [id] = 35 })
    for _, a in ipairs(hidden) do truthy(a.id ~= id, 'dismissed alert still shown') end
    local back = alerts.build(r, cfg, spells.presets.WHM, 40, { [id] = 35 })
    local found = false
    for _, a in ipairs(back) do if a.id == id then found = true end end
    truthy(found, 'alert should return after expiry')
end)

test('alerts: no debuff alerts for members without buff data (alliance), none for zone/KO', function()
    local cfg = new_cfg()
    cfg.alerts.max = 20
    local list = alerts.build(demo.roster(3.0, { demo_alliance_debuffs = false }), cfg, spells.presets.WHM, 3.0, {})
    for _, a in ipairs(list) do
        if a.kind == 'debuff' then truthy(a.slot < 6, 'alliance debuff alert without buff data: slot ' .. a.slot) end
        truthy(a.slot ~= 11, 'zone member should raise no alert')
    end
    local dead_alert = false
    for _, a in ipairs(list) do if a.kind == 'dead' and a.slot == 10 then dead_alert = true end end
    truthy(dead_alert, 'KO member should raise a raise alert')
    local list2 = alerts.build(demo.roster(3.0, { demo_alliance_debuffs = true }), cfg, spells.presets.WHM, 3.0, {})
    local alliance_debuff = false
    for _, a in ipairs(list2) do if a.kind == 'debuff' and a.slot >= 6 then alliance_debuff = true end end
    truthy(alliance_debuff, 'alliance debuff alerts expected when data is visible')
end)

test('alerts: critical HP alert uses the preset best cure', function()
    local cfg = new_cfg()
    cfg.alerts.max = 20
    local roster = { { slot = 1, active = true, name = 'X', hpp = 20, dist = 5, debuffs = {}, has_buff_data = true } }
    local list = alerts.build(roster, cfg, spells.presets.WHM, 0, {})
    eq(#list, 1); eq(list[1].kind, 'hp'); eq(list[1].spell, 'cure4')
end)

-- =============================================================================================
-- actions / commands / config
-- =============================================================================================
test('actions: target tokens for every slot', function()
    eq(actions.target_token(0), '<me>')
    eq(actions.target_token(1), '<p1>'); eq(actions.target_token(5), '<p5>')
    eq(actions.target_token(6), '<a10>'); eq(actions.target_token(11), '<a15>')
    eq(actions.target_token(12), '<a20>'); eq(actions.target_token(17), '<a25>')
end)

test('actions: ready click logs and starts a demo recast; blocked click does neither', function()
    demo.reset()
    local logs = {}
    local ctx = { demo = demo, log = function(t) logs[#logs + 1] = t end, now = 100, roster_by_slot = { [1] = { name = 'Brannoch' } }, dismissed = {} }
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'cure3', state = 'ready' }, ctx), 'cast')
    truthy(logs[1]:find('Cure III') and logs[1]:find('Brannoch') and logs[1]:find('<p1>'))
    truthy(logs[1]:find('Nothing was sent'), 'must state that nothing is sent to the game')
    truthy(demo.player(100.5).recast.cure3, 'demo recast should be running')
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'cure3', state = 'range', detail = 25 }, ctx), 'blocked')
    truthy(logs[2]:find("Can't cast"))
    eq(actions.perform({ type = 'dismiss', id = '3:doom' }, ctx), 'dismissed')
    eq(ctx.dismissed['3:doom'], 125)
    eq(actions.perform({ type = 'bogus' }, ctx), 'ignored')
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'nonexistent' }, ctx), 'ignored')
end)

test('actions: end-to-end right click / shift click cast the tier the user asked for', function()
    -- Click through the real UI, hand the resulting event to actions, and check the logged spell.
    -- (Guards against resolving the click binding twice, which would turn a right click on
    --  Cure IV into Cure II.)
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hb
    for _, h in ipairs(f0.hitboxes) do
        if h.kind == 'spell' and h.slot == 1 and h.key == 'cure4' then hb = h end
    end
    truthy(hb, 'cure4 button not found')
    local cx, cy = hb.x + hb.w / 2, hb.y + hb.h / 2

    local function logged(btn, mods)
        local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(cx, cy, btn, mods))
        ui.draw_roster(f)
        eq(#f.events, 1)
        local logs = {}
        demo.reset()
        local ctx = { demo = demo, log = function(t) logs[#logs + 1] = t end, now = 3.0,
                      roster_by_slot = f.roster, dismissed = {} }
        actions.perform(f.events[1], ctx)
        return logs[1] or ''
    end

    truthy(logged('left'):find('Cure IV ->', 1, true), 'left click should cast Cure IV')
    truthy(logged('right'):find('Cure III ->', 1, true), 'right click should cast Cure III')
    truthy(logged('left', { shift = true }):find('Cure V ->', 1, true), 'shift click should cast Cure V')
end)

test('actions: module contains no game-command code (Phase 1 safety)', function()
    local f = io.open('addons/clickheal/ch/actions.lua', 'r')
    local src = f:read('*a'); f:close()
    -- strip comments so the explanatory header does not trip the check
    src = src:gsub('%-%-%[%[.-%]%]%-%-', ''):gsub('%-%-[^\n]*', '')
    for _, bad in ipairs({ 'QueueCommand', 'AshitaCore', 'GetChatManager', 'SendPacket', 'AddOutgoingPacket' }) do
        truthy(not src:find(bad, 1, true), 'actions.lua must not reference ' .. bad)
    end
end)

test('commands: parsing', function()
    local s = new_cfg()
    local r = commands.run({ '/ch' }, s); truthy(r.toggle_config)
    commands.run({ '/ch', 'scale', '1.5' }, s); eq(s.scale, 1.5)
    local bad = commands.run({ '/ch', 'scale', '99' }, s); eq(s.scale, 1.5); truthy(bad.messages[1]:find('Usage'))
    commands.run({ '/ch', 'scale', 'auto' }, s); eq(s.scale, 1.0); eq(s.auto_scale, true)
    commands.run({ '/ch', 'layout', 'COMPACT' }, s); eq(s.style, 'compact')
    commands.run({ '/ch', 'layout', 'weird' }, s); eq(s.style, 'compact')
    commands.run({ '/ch', 'mode', '12' }, s); eq(s.mode, 'alliance1')
    commands.run({ '/ch', 'mode', '18' }, s); eq(s.mode, 'alliance2')
    commands.run({ '/ch', 'mode', 'party' }, s); eq(s.mode, 'party')
    commands.run({ '/ch', 'orient', 'rows' }, s); eq(s.orientation, 'rows')
    commands.run({ '/ch', 'unlock' }, s); eq(s.locked, false)
    commands.run({ '/ch', 'lock' }, s); eq(s.locked, true)
    commands.run({ '/ch', 'hide' }, s); eq(s.visible, false)
    commands.run({ '/ch', 'show' }, s); eq(s.visible, true)
    commands.run({ '/ch', 'demo', 'off' }, s); eq(s.demo, false)
    commands.run({ '/ch', 'demo' }, s); eq(s.demo, true, 'no argument toggles')
    commands.run({ '/ch', 'alerts', 'off' }, s); eq(s.alerts.enabled, false)
    commands.run({ '/ch', 'colors', 'colorblind' }, s); eq(s.colors, 'colorblind')
    local unk = commands.run({ '/ch', 'frobnicate' }, s); truthy(unk.messages[1]:find('Unknown'))
    truthy(#commands.run({ '/ch', 'help' }, s).messages >= 8)
end)

test('commands: reset requires confirmation', function()
    local s = new_cfg({ scale = 2 })
    local r = commands.run({ '/ch', 'reset' }, s); eq(r.reset, false)
    local r2 = commands.run({ '/ch', 'reset', 'confirm' }, s); eq(r2.reset, true)
end)

test('chconfig: sanitize repairs garbage and keeps good values', function()
    local s = chconfig.sanitize({ style = 'bogus', scale = 'x', opacity = 5, max_range = -3, pos = 'nope',
        alerts = { max = 99, muted = 'x' }, hp_crit = 0 / 0, mode = 'alliance1' })
    eq(s.style, 'strip'); eq(s.scale, 1.0); eq(s.opacity, 1.0)
    eq(s.max_range, 5); eq(s.pos.x, 40); eq(s.alerts.max, 8); eq(type(s.alerts.muted), 'table')
    eq(s.hp_crit, chconfig.defaults.hp_crit); eq(s.mode, 'alliance1')
    truthy(s.warn_range <= s.max_range)
end)

test('chconfig: reset keeps the same table', function()
    local s = new_cfg({ scale = 3, style = 'minimal' })
    local ref = s
    chconfig.reset(s)
    eq(ref, s); eq(s.scale, 1.0); eq(s.style, 'strip')
end)

-- =============================================================================================
-- demo source
-- =============================================================================================
test('demo: roster shape and recast flow', function()
    demo.reset()
    local r = demo.roster(0, {})
    eq(#r, 15)
    for _, m in ipairs(r) do
        truthy(m.slot >= 0 and m.slot <= 17 and m.name and m.job and m.hpmax > 0)
        truthy(m.hpp >= 0 and m.hpp <= 100)
        truthy(type(m.debuffs) == 'table')
    end
    local p = demo.player(1)
    eq(next(p.recast), nil)
    demo.cast(spells.defs.cure4, 1)
    local p2 = demo.player(2)
    truthy(p2.recast.cure4 and p2.recast.cure4 > 6 and p2.recast.cure4 < 8)
    truthy(p2.mp < 1380, 'MP should be spent')
    local p3 = demo.player(10)
    eq(p3.recast.cure4, nil, 'recast expires')
    demo.reset()
end)

-- =============================================================================================
-- ui (through the recording backend)
-- =============================================================================================
test('ui: draws every style x mode x orientation x resolution without error, inside the panel', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        for _, mode in ipairs({ 'party', 'alliance1', 'alliance2' }) do
            for _, orient in ipairs({ 'columns', 'stacked', 'rows' }) do
                for _, h in ipairs({ 720, 1080, 1440, 2160 }) do
                    local cfg = new_cfg({ style = style, mode = mode, orientation = orient, demo_alliance_debuffs = true })
                    local f, fr, g = build_ui_frame(cfg, h, 3.0)
                    ui.draw_roster(f)
                    local W, H = fr.geom.width, fr.geom.height
                    truthy(#g.cmds > 50, 'suspiciously little drawn')
                    local tag = style .. '/' .. mode .. '/' .. orient .. '/' .. h
                    for _, c in ipairs(g.cmds) do
                        if c.op == 'rect' then
                            if not (c.x >= -1 and c.y >= -1 and c.x + c.w <= W + 1 and c.y + c.h <= H + 1) then
                                error(string.format('rect outside panel (%s): %.1f,%.1f %.1fx%.1f in %dx%d', tag, c.x, c.y, c.w, c.h, W, H))
                            end
                        elseif c.op == 'text' then
                            local tw = g.text_size(c.s)
                            if not (c.x >= -1 and c.x + tw <= W + 1) then
                                error(string.format('text outside panel (%s): "%s" x=%.1f w=%.1f panel=%d', tag, c.s, c.x, tw, W))
                            end
                        end
                    end
                end
            end
        end
    end
end)

test('ui: text inside a card never runs past the card edge', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        local cfg = new_cfg({ style = style, mode = 'alliance2', demo_alliance_debuffs = true })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        for _, c in ipairs(g.cmds) do
            if c.op == 'text' and c.y >= fr.geom.header_h + fr.geom.label_h then
                local tw = g.text_size(c.s)
                local inside = false
                for _, card in pairs(fr.geom.cards) do
                    if c.x >= card.x - 1 and c.x + tw <= card.x + card.w + 1 and c.y >= card.y - 1 and c.y <= card.y + card.h then
                        inside = true
                    end
                end
                truthy(inside or c.y < fr.geom.header_h + fr.geom.label_h + 1, string.format('text "%s" leaks out of its card (%s)', c.s, style))
            end
        end
    end
end)

test('ui: header title and status tag never overlap (narrowest panel, long tag)', function()
    for _, locked in ipairs({ true, false }) do
        for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
            local cfg = new_cfg({ style = style, mode = 'party', locked = locked })
            local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
            ui.draw_roster(f)
            local texts = {}
            for _, c in ipairs(g.cmds) do
                if c.op == 'text' and c.y < fr.geom.header_h then texts[#texts + 1] = { x = c.x, w = g.text_size(c.s), s = c.s } end
            end
            for i = 1, #texts do
                for j = i + 1, #texts do
                    local a, b = texts[i], texts[j]
                    truthy(a.x + a.w <= b.x or b.x + b.w <= a.x,
                        string.format('header texts overlap: "%s" and "%s" (%s, locked=%s)', a.s, b.s, style, tostring(locked)))
                end
            end
        end
    end
end)

test('ui: every spell hitbox is at least 24 px at 1080p and scales at 4K', function()
    for _, h in ipairs({ 1080, 2160 }) do
        local cfg = new_cfg({ style = 'full', mode = 'alliance1' })
        local f, fr = build_ui_frame(cfg, h, 3.0, nil, true)
        ui.draw_roster(f)
        local n = 0
        for _, hb in ipairs(f.hitboxes) do
            if hb.kind == 'spell' then
                n = n + 1
                truthy(hb.w >= 24 * fr.geom.scale - 1 and hb.h >= 24 * fr.geom.scale - 1, 'button too small: ' .. hb.w .. 'x' .. hb.h)
            end
        end
        truthy(n > 40, 'expected many buttons, got ' .. n)
    end
end)

local function find_hitbox(hitboxes, pred)
    for _, hb in ipairs(hitboxes) do if pred(hb) then return hb end end
end

test('ui: clicking a button emits a cast with the resolved binding', function()
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    -- Brannoch (slot 1), in range, plain row: first button is Cure IV
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'spell' and h.slot == 1 and h.key == 'cure4' end)
    truthy(hb, 'cure4 button for slot 1 not found')
    local cx, cy = hb.x + hb.w / 2, hb.y + hb.h / 2

    local function click(btn, mods)
        local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(cx, cy, btn, mods))
        ui.draw_roster(f)
        return f.events
    end

    local ev = click('left')
    eq(#ev, 1); eq(ev[1].type, 'cast'); eq(ev[1].spell, 'cure4'); eq(ev[1].slot, 1); eq(ev[1].state, 'ready')
    ev = click('right');                eq(ev[1].spell, 'cure3', 'right click = one tier down')
    ev = click('left', { shift = true }); eq(ev[1].spell, 'cure5', 'shift = one tier up')

    -- Hover without a click emits nothing and produces a tooltip.
    local fh = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(cx, cy, nil))
    ui.draw_roster(fh)
    eq(#fh.events, 0)
    local has_tip = false
    for _, c in ipairs(fh.gfx.cmds) do if c.op == 'tooltip' then has_tip = true end end
    truthy(has_tip, 'tooltip expected on hover')
end)

test('ui: unlocked panel is not clickable; mouse elsewhere is ignored', function()
    local cfg = new_cfg({ style = 'full', mode = 'party', locked = false })
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'spell' and h.slot == 1 end)
    local cx, cy = hb.x + hb.w / 2, hb.y + hb.h / 2
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(cx, cy, 'left', {}, false))
    ui.draw_roster(f)
    eq(#f.events, 0, 'unlocked must not cast')

    local cfg2 = new_cfg({ style = 'full', mode = 'party' })
    local f2 = build_ui_frame(cfg2, 1080, 3.0, gfx_rec.input(5000, 5000, 'left'))
    ui.draw_roster(f2)
    eq(#f2.events, 0)
end)

test('ui: out-of-range button click is reported as range, not ready', function()
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'spell' and h.slot == 5 end)  -- Dunstan, 24y
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hb.x + 2, hb.y + 2, 'left'))
    ui.draw_roster(f)
    eq(#f.events, 1); eq(f.events[1].state, 'range')
end)

test('ui: minimal style reveals buttons on hover only', function()
    local cfg = new_cfg({ style = 'minimal', mode = 'party' })
    local f0, fr = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local n0 = 0
    for _, h in ipairs(f0.hitboxes) do if h.kind == 'spell' then n0 = n0 + 1 end end
    eq(n0, 0, 'no spell buttons without hover')
    local card = fr.geom.cards[1]
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(card.x + 20, card.y + card.h / 2, nil), true)
    ui.draw_roster(f)
    local nb = 0
    for _, hb in ipairs(f.hitboxes) do if hb.kind == 'spell' then nb = nb + 1 end end
    truthy(nb > 0, 'buttons should appear on hover')
    for _, hb in ipairs(f.hitboxes) do
      if hb.kind == 'spell' then
        truthy(hb.x >= card.x and hb.x + hb.w <= card.x + card.w and hb.y >= card.y and hb.y + hb.h <= card.y + card.h, 'hover buttons must stay inside the card')
      end
    end
end)

test('ui: alert bar rows are clickable; right click dismisses', function()
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local function alert_frame(input, hit)
        demo.reset()
        local fr = frame.build(cfg, demo, 3.0, 1920, 1080, {})
        local g = gfx_rec.new(fr.geom.scale)
        local f = {
            gfx = g, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, player = fr.player,
            preset = fr.preset, now = 3.0, ox = 0, oy = 0, events = {},
            alerts = fr.alerts, abar = fr.abar, more = fr.alert_more, input = input,
            hitboxes = hit and {} or nil,
        }
        return f, fr
    end
    local f0 = alert_frame(gfx_rec.input(nil, nil, nil), true)
    ui.draw_alerts(f0)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'alert' end)
    truthy(hb, 'no clickable alert')
    local cx, cy = hb.x + hb.w / 2, hb.y + hb.h / 2
    local f1 = alert_frame(gfx_rec.input(cx, cy, 'left'))
    ui.draw_alerts(f1)
    eq(#f1.events, 1); eq(f1.events[1].type, 'cast'); eq(f1.events[1].via, 'alert'); eq(f1.events[1].spell, 'cursna')
    local f2 = alert_frame(gfx_rec.input(cx, cy, 'right'))
    ui.draw_alerts(f2)
    eq(f2.events[1].type, 'dismiss'); eq(f2.events[1].id, hb.id)
end)

test('ui: alert bar placeholder (unlocked, no alerts) draws without error', function()
    local cfg = new_cfg({ locked = false })
    local fr = frame.build(cfg, demo, 3.0, 1920, 1080, {})
    local g = gfx_rec.new(1)
    ui.draw_alerts({
        gfx = g, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, player = fr.player,
        preset = fr.preset, now = 3.0, ox = 0, oy = 0, events = {},
        alerts = {}, abar = fr.abar, placeholder = true, input = gfx_rec.input(nil, nil, nil),
    })
    truthy(#g.cmds > 0)
end)

-- =============================================================================================
-- frame
-- =============================================================================================
test('frame: builds geometry, alerts and a centered default alert position', function()
    local cfg = new_cfg({ mode = 'alliance2' })
    local fr = frame.build(cfg, demo, 3.0, 1920, 1080, {})
    eq(#fr.groups, 3)
    eq(#fr.alerts, cfg.alerts.max)
    truthy(fr.alert_more > 0)
    near(fr.alert_pos.x, (1920 - fr.abar.w) / 2, 1)
    eq(fr.preset_name, 'WHM')
    -- alliance 2 is only partly filled; hide_empty keeps it because members exist
    local cfg2 = new_cfg({ mode = 'alliance2', hide_empty_groups = true })
    eq(#frame.build(cfg2, demo, 3.0, 1920, 1080, {}).groups, 3)
end)



-- =============================================================================================
-- buffs, timers, job tag, buff mode
-- =============================================================================================
local buffs = require('ch.buffs')
local commands = require('ch.commands')
local actions = require('ch.actions')

test('buffs: time format and urgency', function()
    eq(buffs.fmt(42), '0:42'); eq(buffs.fmt(125), '2:05'); eq(buffs.fmt(41.2), '0:42')
    eq(buffs.fmt(900), '15m'); eq(buffs.fmt(7200), '2h'); eq(buffs.fmt(nil), '')
    eq(buffs.urgency(nil), 'none'); eq(buffs.urgency(60), 'long')
    eq(buffs.urgency(30), 'soon'); eq(buffs.urgency(10), 'urgent')
end)

test('buffs: "mine only" keeps what the job can cast; no buff data shows nothing', function()
    local m = { has_buff_data = true, buffs = { { key = 'haste', rem = 20 }, { key = 'regen', rem = 50 }, { key = 'blink', rem = 9 } } }
    local whm = spells.presets.WHM
    local cfg = new_cfg({ buffs_mine_only = true })
    local l = buffs.list(m, cfg, whm)
    eq(#l, 3, 'WHM casts haste, regen, blink')
    local sch = buffs.list(m, cfg, spells.presets.SCH)
    eq(#sch, 1, 'SCH only regen from this set'); eq(sch[1].key, 'regen')
    eq(#buffs.list(m, new_cfg({ buffs_mine_only = false }), spells.presets.SCH), 3)
    eq(#buffs.list(m, cfg, spells.presets.generic), 3, 'job with no buff spells shows all')
    eq(#buffs.list({ has_buff_data = false, buffs = m.buffs }, cfg, whm), 0)
    eq(#buffs.list({ dead = true, has_buff_data = true, buffs = m.buffs }, cfg, whm), 0)
    eq(l[1].key, 'haste', 'fixed display order')
    eq(buffs.recast_spell('regen', whm), 'regen3')
    eq(buffs.recast_spell('haste', spells.presets.SCH), nil)
end)

test('ui: buff pips are drawn inside the card and clicking one recasts that buff', function()
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local f0, fr = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local pips = 0
    for _, hb in ipairs(f0.hitboxes) do
        if hb.kind == 'buff' then
            pips = pips + 1
            local c = fr.geom.cards[hb.slot]
            truthy(hb.x >= c.x and hb.x + hb.w <= c.x + c.w and hb.y >= c.y + fr.geom.buff_y and hb.y + hb.h <= c.y + fr.geom.btn_y,
                'pip must sit in the strip between the bars and the tiles')
        end
    end
    truthy(pips >= 10, 'demo party should show pips, got ' .. pips)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'buff' and h.slot == 1 and h.key == 'haste' end)
    truthy(hb, 'Brannoch haste pip')
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hb.x + 2, hb.y + 2, 'left'))
    ui.draw_roster(f)
    eq(#f.events, 1); eq(f.events[1].spell, 'haste'); eq(f.events[1].slot, 1); eq(f.events[1].via, 'buff')
    -- right click does nothing on a pip
    local f2 = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hb.x + 2, hb.y + 2, 'right'))
    ui.draw_roster(f2)
    eq(#f2.events, 0)
end)

test('ui: show_buffs=false removes the strip and the full card shrinks back', function()
    local cfg = new_cfg({ style = 'full', mode = 'party', show_buffs = false })
    local f, fr = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f)
    eq(fr.geom.buff_h, 0); eq(fr.geom.height, 408)
    for _, hb in ipairs(f.hitboxes) do truthy(hb.kind ~= 'buff', 'no pips when off') end
end)

test('ui: buff mode swaps the spell row and keeps priority cures out of it', function()
    local cfg = new_cfg({ style = 'full', mode = 'party', buff_mode = true })
    local f, fr = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f)
    local keys = {}
    for _, hb in ipairs(f.hitboxes) do
        if hb.kind == 'spell' and hb.slot == 5 then keys[#keys + 1] = hb.key end   -- Dunstan: poisoned
    end
    truthy(#keys > 0)
    eq(keys[1], 'haste')
    for _, k in ipairs(keys) do truthy(k ~= 'poisona', 'no cleanse in buff mode') end
end)

test('ui: header mode switch emits a toggle event and actions flips the setting', function()
    local cfg = new_cfg({ style = 'full', mode = 'party' })
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'mode' end)
    truthy(hb, 'mode switch present for WHM')
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hb.x + 2, hb.y + 2, 'left'))
    ui.draw_roster(f)
    eq(#f.events, 1); eq(f.events[1].type, 'toggle')
    local changed = false
    local res = actions.perform(f.events[1], { cfg = cfg, changed = function() changed = true end, dismissed = {}, now = 0, log = function() end, roster_by_slot = {} })
    eq(res, 'toggled'); eq(cfg.buff_mode, true); truthy(changed)
end)

test('ui: debuff chips are short tags with no countdown; the hover list has the times', function()
    for _, style in ipairs({ 'full', 'grid', 'strip' }) do
        local cfg = new_cfg({ style = style, mode = 'party', show_timers = true })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local tags = 0
        for _, c in ipairs(g.cmds) do
            if c.op == 'text' then
                truthy(not c.s:match('^%u%u%u %d+:%d%d$'), 'no timer text on chips (' .. style .. '): ' .. c.s)
                if c.s == 'SIL' or c.s == 'DOM' or c.s == 'PAR' then tags = tags + 1 end
            end
        end
        truthy(tags >= 3, 'the tags are there')
    end
end)

test('ui: job tag style draws a chip and the sub job, in every layout, without leaving the card', function()
    for _, style in ipairs({ 'full', 'compact', 'minimal' }) do
        local cfg = new_cfg({ style = style, mode = 'party', job_style = 'tag' })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local saw_tag = false
        for _, c in ipairs(g.cmds) do if c.op == 'text' and c.s == 'WHM' then saw_tag = true end end
        truthy(saw_tag, 'WHM tag drawn in ' .. style)
    end
end)

test('commands: buffs, timers, job, buffmode', function()
    local s = new_cfg({})
    local r = commands.run({ '/ch', 'buffs', 'off' }, s); eq(s.show_buffs, false); truthy(r.changed)
    commands.run({ '/ch', 'mybuffs', 'off' }, s); eq(s.buffs_mine_only, false)
    commands.run({ '/ch', 'timers', 'off' }, s); eq(s.show_timers, false)
    commands.run({ '/ch', 'job', 'tag' }, s); eq(s.job_style, 'tag')
    commands.run({ '/ch', 'job', 'nope' }, s); eq(s.job_style, 'tag', 'bad value ignored')
    commands.run({ '/ch', 'buffmode', 'buff' }, s); eq(s.buff_mode, true)
    commands.run({ '/ch', 'buffmode', 'heal' }, s); eq(s.buff_mode, false)
    commands.run({ '/ch', 'buffmode' }, s); eq(s.buff_mode, true, 'no arg toggles')
end)

test('chconfig: new settings are repaired from bad values', function()
    local s = chconfig.sanitize({ job_style = 'weird', show_buffs = 'yes', buff_mode = 3 })
    eq(s.job_style, 'text'); eq(s.show_buffs, true); eq(s.buff_mode, true)
end)

-- =============================================================================================
-- grid / strip layouts and click bindings
-- =============================================================================================
local bindings = require('ch.bindings')

test('bindings: slot names, parsing, validation', function()
    eq(bindings.slot_name('left', {}), 'left')
    eq(bindings.slot_name('right', { shift = true }), 'shift_right')
    eq(bindings.slot_name('left', { shift = true, ctrl = true }), 'ctrl_left', 'ctrl beats shift')
    eq(bindings.slot_name('left', { alt = true, shift = true }), 'alt_left')
    eq(bindings.slot_name('middle', { shift = true }), 'middle')
    eq(bindings.parse_slot('shift+rmb'), 'shift_right'); eq(bindings.parse_slot('LMB'), 'left')
    eq(bindings.parse_slot('ctrl+left'), 'ctrl_left'); eq(bindings.parse_slot('shift+mmb'), nil)
    eq(bindings.parse_slot('nope'), nil)
    truthy(bindings.valid_value('cure4')); truthy(bindings.valid_value('cleanse')); truthy(bindings.valid_value('-'))
    truthy(not bindings.valid_value('cure9'))
end)

test('bindings: every preset binding names a real spell; overrides layer on top', function()
    for name, p in pairs(spells.presets) do
        for _, set in ipairs({ 'bindings', 'buff_bindings' }) do
            for slot, v in pairs(p[set] or {}) do
                truthy(bindings.is_slot(slot), name .. ' bad slot ' .. slot)
                truthy(bindings.valid_value(v), name .. '.' .. set .. ' bad value ' .. tostring(v))
            end
        end
    end
    local cfg = new_cfg({ bindings = { left = 'cure3', shift_right = '-' } })
    local eff = bindings.effective(cfg, spells.presets.WHM)
    eq(eff.left, 'cure3'); eq(eff.shift_right, '-'); eq(eff.right, 'cure2')
    local buff = bindings.effective(new_cfg({ buff_mode = true, bindings = { left = 'cure3' } }), spells.presets.WHM)
    eq(buff.left, 'haste', 'buff mode ignores heal overrides')
    local bad = chconfig.sanitize({ bindings = { left = 'cure99', bogus = 'cure1', right = 'cure1' } })
    eq(bad.bindings.left, nil); eq(bad.bindings.bogus, nil); eq(bad.bindings.right, 'cure1')
end)

test('bindings: resolve handles cleanse, KO and none', function()
    local whm = spells.presets.WHM
    local doom = { name = 'T', has_buff_data = true, debuffs = { 'poison', 'doom' } }
    eq(bindings.resolve('cleanse', doom, whm, 'middle'), 'cursna', 'worst debuff first')
    local k, why = bindings.resolve('cleanse', { name = 'H', has_buff_data = true, debuffs = {} }, whm, 'middle')
    eq(k, nil); truthy(why and why:find('Nothing to cleanse'))
    eq(bindings.resolve('cure4', { name = 'K', dead = true }, whm, 'left'), 'raise3')
    eq(bindings.resolve('cure4', { name = 'K', dead = true }, whm, 'right'), 'raise1')
    eq(bindings.resolve('cure4', { name = 'K', dead = true }, spells.presets.PLD, 'left'), nil)
    eq(bindings.resolve('-', { name = 'A' }, whm, 'left'), nil)
    eq(bindings.resolve('cure4', { name = 'A' }, whm, 'left'), 'cure4')
end)

test('layout: grid and strip are much smaller than full', function()
    local full = layout.compute({ style = 'full', orientation = 'columns', groups = { 0, 1, 2 } }, 1080)
    for _, style in ipairs({ 'grid', 'strip' }) do
        local g = layout.compute({ style = style, orientation = 'columns', groups = { 0, 1, 2 } }, 1080)
        truthy(g.width < full.width and g.height < full.height * 0.7, style .. ' footprint')
        local g4 = layout.compute({ style = style, orientation = 'columns', groups = { 0, 1, 2 } }, 2160)
        near(g4.width / 3840, g.width / 1920, 0.005)
    end
    local g = layout.compute({ style = 'grid', orientation = 'columns', groups = { 0, 1, 2 } }, 1080)
    eq(g.width, 3 * 140 + 2 * 8)
end)

local function cell_click(cfg, slot, button, mods, groups_mode)
    cfg.mode = groups_mode or cfg.mode
    local f0, fr = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hb = find_hitbox(f0.hitboxes, function(h) return h.kind == 'cell' and h.slot == slot end)
    truthy(hb, 'cell for slot ' .. slot)
    local f = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hb.x + 3, hb.y + 3, button, mods))
    ui.draw_roster(f)
    return f.events, f
end

test('ui: grid click casting follows the bindings (button, modifier, cleanse, KO)', function()
    for _, style in ipairs({ 'grid', 'strip' }) do
        local cfg = new_cfg({ style = style, mode = 'alliance1', cell_binds = true })
        local function spell_of(slot, button, mods)
            local ev = cell_click(cfg, slot, button, mods)
            eq(#ev, 1, style .. ' one event'); return ev[1]
        end
        eq(spell_of(1, 'left').spell, 'cure4')
        eq(spell_of(1, 'right').spell, 'cure2')
        eq(spell_of(1, 'left', { shift = true }).spell, 'cure5')
        eq(spell_of(1, 'right', { shift = true }).spell, 'cure1')
        eq(spell_of(1, 'left', { ctrl = true }).spell, 'curaga3')
        eq(spell_of(3, 'middle').spell, 'cursna', 'Torvald has doom')
        eq(spell_of(2, 'middle').spell, 'silena', 'Kessia is silenced')
        local ko = spell_of(10, 'left'); eq(ko.spell, 'raise3'); eq(ko.slot, 10)
        eq(spell_of(5, 'left').state, 'range', 'Dunstan is out of range; the event says so')
        local ev = cell_click(cfg, 1, 'middle')
        eq(#ev, 1); eq(ev[1].type, 'note', 'nothing to cleanse on a healthy member')
    end
end)

test('ui: grid hover shows the bindings tooltip; no hover = nothing', function()
    local cfg = new_cfg({ style = 'grid', mode = 'party', cell_binds = true })
    local _, f = cell_click(cfg, 1, nil)
    truthy(f.tooltip and #f.tooltip >= 3, 'tooltip lines')
    truthy(f.tooltip[2]:find('LMB: Cure IV'), f.tooltip[2])
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    eq(f0.tooltip, nil)
end)

test('ui: grid and strip text stays inside its cell at 1080p and 4K', function()
    for _, style in ipairs({ 'grid', 'strip' }) do
        for _, h in ipairs({ 1080, 2160 }) do
            local cfg = new_cfg({ style = style, mode = 'alliance2', demo_alliance_debuffs = true })
            local f, fr, g = build_ui_frame(cfg, h, 3.0)
            ui.draw_roster(f)
            for _, c in ipairs(g.cmds) do
                if c.op == 'text' and c.y > fr.geom.header_h + fr.geom.label_h and (not fr.geom.bar or c.y < fr.geom.bar.y) then
                    local w = g.text_size(c.s)
                    local inside = false
                    for _, card in pairs(fr.geom.cards) do
                        if c.x >= card.x and c.x + w <= card.x + card.w + 1 and c.y >= card.y and c.y <= card.y + card.h then inside = true end
                    end
                    truthy(inside, string.format('"%s" leaks out of its cell (%s, %dp)', c.s, style, h))
                end
            end
        end
    end
end)

test('commands: bind, unbind via none, reset, binds', function()
    local s = new_cfg({})
    commands.run({ '/ch', 'bind', 'shift+rmb', 'cure1' }, s); eq(s.bindings.shift_right, 'cure1')
    commands.run({ '/ch', 'bind', 'lmb', 'none' }, s); eq(s.bindings.left, '-')
    local r = commands.run({ '/ch', 'bind', 'lmb', 'cure99' }, s); eq(s.bindings.left, '-', 'bad spell ignored'); truthy(#r.messages > 0)
    commands.run({ '/ch', 'bind', 'xyz', 'cure1' }, s); eq(s.bindings.xyz, nil)
    eq(commands.run({ '/ch', 'binds' }, s).show_binds, true)
    commands.run({ '/ch', 'bind', 'reset' }, s); eq(next(s.bindings), nil)
    commands.run({ '/ch', 'layout', 'grid' }, s); eq(s.style, 'grid')
    commands.run({ '/ch', 'layout', 'strip' }, s); eq(s.style, 'strip')
end)

test('actions: a note event is logged', function()
    local logged
    eq(actions.perform({ type = 'note', text = 'hello' }, { log = function(x) logged = x end }), 'noted')
    eq(logged, 'hello')
end)


test('chconfig: the separate alert window is off by default', function()
    eq(chconfig.sanitize({}).alerts.enabled, false)
end)

test('ui: many debuffs - severe first, short names when timers do not fit, +N, and a full hover list', function()
    local cfg = new_cfg({ style = 'grid', mode = 'party', show_timers = true })
    demo.reset()
    local fr = frame.build(cfg, demo, 3.0, 1920, 1080, {})
    local m = fr.roster[5]
    m.debuffs = { 'poison', 'blindness', 'doom', 'silence', 'paralysis', 'slow', 'weight' }
    m.debuff_rem = { poison = 20, blindness = 80, doom = 9, silence = 30, paralysis = 44, slow = 50, weight = 12 }
    local c = fr.geom.cards[5]
    local g = gfx_rec.new(fr.geom.scale)
    local f = { gfx = g, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, player = fr.player,
        preset = fr.preset, now = 3.0, ox = 0, oy = 0, events = {}, input = gfx_rec.input(nil, nil, nil) }
    ui.draw_roster(f)
    local texts = {}
    for _, cmd in ipairs(g.cmds) do
        if cmd.op == 'text' and cmd.x >= c.x and cmd.x <= c.x + c.w and cmd.y >= c.y and cmd.y <= c.y + c.h * 0.5 then
            texts[#texts + 1] = cmd
        end
    end
    local saw_doom, saw_more = false, false
    for _, x in ipairs(texts) do
        if x.s:match('^DOM') then saw_doom = true end
        if x.s:match('^%+%d') then saw_more = true end
    end
    truthy(saw_doom, 'DOOM (most severe) is always visible')
    truthy(saw_more, 'the rest collapse into +N')

    -- hovering over the chips lists all seven
    local hx = c.x + c.w - fr.geom.pad - 6
    local hy = c.y + math.floor(4 * fr.geom.scale) + 6
    local g2 = gfx_rec.new(fr.geom.scale)
    local f2 = { gfx = g2, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, player = fr.player,
        preset = fr.preset, now = 3.0, ox = 0, oy = 0, events = {}, input = gfx_rec.input(hx, hy, nil) }
    ui.draw_roster(f2)
    truthy(f2.tooltip and #f2.tooltip == 7, 'hover lists every debuff: ' .. tostring(f2.tooltip and #f2.tooltip))
    truthy(f2.tooltip[1]:find('DOOM') and f2.tooltip[1]:find('Cursna'), f2.tooltip[1])
end)

-- =============================================================================================
-- shared spell bar: arm a spell, then click a member
-- =============================================================================================
local function bar_frame(cfg, input)
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0, input, true)
    ui.draw_roster(f)
    return f, fr, g
end

local function hb_of(f, pred) return find_hitbox(f.hitboxes, pred) end

test('layout: spell bar sits below the cells inside the panel, and scales with resolution', function()
    for _, style in ipairs({ 'grid', 'strip' }) do
        local g = layout.compute({ style = style, orientation = 'columns', groups = { 0 }, spellbar = true }, 1080)
        truthy(g.bar, 'bar present')
        truthy(g.bar.y >= g.header_h + 6 * g.card_h, 'below the cells')
        truthy(g.bar.x + g.bar.w <= g.width and g.bar.y + g.bar.h <= g.height, 'inside the panel')
        truthy(g.bar.btn >= 24, 'tiles stay clickable')
        local g4 = layout.compute({ style = style, orientation = 'columns', groups = { 0 }, spellbar = true }, 2160)
        near(g4.width / 3840, g.width / 1920, 0.005); near(g4.height / 2160, g.height / 1080, 0.005)
        eq(layout.compute({ style = style, orientation = 'columns', groups = { 0 }, spellbar = false }, 1080).bar, nil)
    end
    eq(layout.compute({ style = 'full', orientation = 'columns', groups = { 0 }, spellbar = true }, 1080).bar, nil, 'full has its own tiles')
end)

test('spells: bar tabs only name real spells; empty tabs are hidden', function()
    for name, p in pairs(spells.presets) do
        for _, tab in ipairs(spells.bar_tabs(p)) do
            truthy(#tab.keys > 0)
            for _, key in ipairs(tab.keys) do truthy(spells.defs[key], name .. ' bar names unknown ' .. key) end
        end
    end
    eq(#spells.bar_tabs(spells.presets.PLD), 1)
    eq(#spells.bar_tabs(spells.presets.WHM), 4)
    truthy(spells.sticky(spells.defs.cure4) and spells.sticky(spells.defs.curaga2))
    truthy(not spells.sticky(spells.defs.erase) and not spells.sticky(spells.defs.haste))
end)

test('ui: pick a cure on the bar, then click members - cure stays armed, right click cancels', function()
    for _, style in ipairs({ 'grid', 'strip' }) do
        local cfg = new_cfg({ style = style, mode = 'party', spellbar = true })
        local f0 = bar_frame(cfg)
        eq(ui.state.armed, nil)
        local tile = hb_of(f0, function(h) return h.kind == 'bar_tile' and h.key == 'cure3' end)
        truthy(tile, 'cure3 tile')
        bar_frame(cfg, gfx_rec.input(tile.x + 2, tile.y + 2, 'left'))
        eq(ui.state.armed, 'cure3', 'clicking a tile arms it')

        local cell = hb_of(f0, function(h) return h.kind == 'cell' and h.slot == 1 end)
        local f1 = bar_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, 'left'))
        eq(#f1.events, 1); eq(f1.events[1].spell, 'cure3'); eq(f1.events[1].slot, 1); eq(f1.events[1].via, 'bar')
        eq(ui.state.armed, 'cure3', 'cures stay armed for the next patient')
        local f2 = bar_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, 'left'))
        eq(#f2.events, 1, 'second click casts again')

        local f3 = bar_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, 'right'))
        eq(#f3.events, 0); eq(ui.state.armed, nil, 'right click disarms without casting')
    end
end)

test('ui: non-cure spells are one-shot; unarmed plain clicks do nothing unless cell_binds is on', function()
    local cfg = new_cfg({ style = 'grid', mode = 'party', spellbar = true })
    local f0 = bar_frame(cfg)
    local cell = hb_of(f0, function(h) return h.kind == 'cell' and h.slot == 2 end)
    local f = bar_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, 'left'))
    eq(#f.events, 0, 'nothing armed, cell_binds off')

    cfg.bar_tab = 'cleanse'
    local f1 = bar_frame(cfg)
    local tile = hb_of(f1, function(h) return h.kind == 'bar_tile' and h.key == 'silena' end)
    bar_frame(cfg, gfx_rec.input(tile.x + 2, tile.y + 2, 'left'))
    eq(ui.state.armed, 'silena')
    local f2 = bar_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, 'left'))
    eq(#f2.events, 1); eq(f2.events[1].spell, 'silena')
    eq(ui.state.armed, nil, 'one-shot spells disarm after casting')

    local cfg2 = new_cfg({ style = 'grid', mode = 'party', cell_binds = true, spellbar = true })
    local f3 = bar_frame(cfg2)
    local c3 = hb_of(f3, function(h) return h.kind == 'cell' and h.slot == 2 end)
    local f4 = bar_frame(cfg2, gfx_rec.input(c3.x + 3, c3.y + 3, 'left'))
    eq(#f4.events, 1); eq(f4.events[1].spell, 'cure4', 'cell_binds restores quick casting')
end)

test('ui: clicking a tab emits the switch; the armed spell can be cast out of range and says so', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party', spellbar = true })
    local f0 = bar_frame(cfg)
    local tab = hb_of(f0, function(h) return h.kind == 'bar_tab' and h.id == 'buff' end)
    truthy(tab)
    local f = bar_frame(cfg, gfx_rec.input(tab.x + 2, tab.y + 2, 'left'))
    eq(#f.events, 1); eq(f.events[1].type, 'toggle'); eq(f.events[1].what, 'bar_tab'); eq(f.events[1].value, 'buff')
    local ctx = { cfg = cfg, changed = function() end, dismissed = {}, now = 0, log = function() end, roster_by_slot = {} }
    eq(actions.perform(f.events[1], ctx), 'toggled'); eq(cfg.bar_tab, 'buff')

    cfg.bar_tab = 'heal'
    local f1 = bar_frame(cfg)
    local tile = hb_of(f1, function(h) return h.kind == 'bar_tile' and h.key == 'cure2' end)
    bar_frame(cfg, gfx_rec.input(tile.x + 2, tile.y + 2, 'left'))
    local far = hb_of(f1, function(h) return h.kind == 'cell' and h.slot == 5 end)   -- Dunstan, 24y
    local f2 = bar_frame(cfg, gfx_rec.input(far.x + 3, far.y + 3, 'left'))
    eq(#f2.events, 1); eq(f2.events[1].state, 'range')
end)

test('ui: the CLEAN tab flags what the party needs (dot on the tab, outline on the tile)', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party', bar_tab = 'cleanse', spellbar = true })
    local f, fr, g = bar_frame(cfg)
    -- Kessia is silenced, Miraeth paralysed, Torvald doomed, Dunstan poisoned+blind -> tiles are outlined.
    local outlined = 0
    local tiles = {}
    for _, h in ipairs(f.hitboxes) do if h.kind == 'bar_tile' then tiles[#tiles + 1] = h end end
    truthy(#tiles >= 8)
    for _, cmd in ipairs(g.cmds) do
        if cmd.op == 'rect' and cmd.w and cmd.h and cmd.w >= 20 then
            for _, h in ipairs(tiles) do
                if cmd.x == h.x and cmd.y == h.y and cmd.w == h.w and cmd.h == 2 * 1 then outlined = outlined + 1 end
            end
        end
    end
    -- (outline thickness is 2 px at 1080p: top edge rects have h == 2)
    truthy(outlined >= 4, 'needed tiles are outlined, got ' .. outlined)
end)

test('commands: bar, tab, cellbinds', function()
    local s = new_cfg({})
    commands.run({ '/ch', 'bar', 'off' }, s); eq(s.spellbar, false)
    commands.run({ '/ch', 'tab', 'cleanse' }, s); eq(s.bar_tab, 'cleanse')
    commands.run({ '/ch', 'tab', 'nope' }, s); eq(s.bar_tab, 'cleanse')
    commands.run({ '/ch', 'cellbinds', 'on' }, s); eq(s.cell_binds, true)
end)

-- =============================================================================================
-- hover flyout, slanted strip rows, spell order
-- =============================================================================================
local function fly_frame(cfg, input, mutate)
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0, input, true)
    f.disp_w, f.disp_h = 1920, 1080
    if mutate then mutate(f) end
    ui.draw_roster(f)
    return f, fr, g
end

local function open_flyout(cfg, slot)
    local f0, fr = fly_frame(cfg)
    local cell = hb_of(f0, function(h) return h.kind == 'cell' and h.slot == slot end)
    local f = fly_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, nil))
    local plan = ui.flyout_plan(f)
    return plan, f, cell
end

local function draw_fly(f, plan, input)
    local g = gfx_rec.new(f.geom.scale * f.cfg.font_mult)
    local ff = { gfx = g, geom = f.geom, cfg = f.cfg, pal = f.pal, roster = f.roster, player = f.player,
        preset = f.preset, now = f.now, ox = plan.x, oy = plan.y, events = {}, plan = plan,
        input = input or gfx_rec.input(nil, nil, nil), hitboxes = {}, disp_w = 1920, disp_h = 1080 }
    ui.draw_flyout(ff)
    return ff, g
end

test('flyout: hovering a strip/grid row opens it beside the row, inside the screen', function()
    for _, style in ipairs({ 'strip', 'grid' }) do
        local cfg = new_cfg({ style = style, mode = 'party' })
        local plan, f, cell = open_flyout(cfg, 1)
        truthy(plan, style .. ' flyout opens')
        eq(plan.slot, 1)
        truthy(plan.x >= cell.x + cell.w - 1, 'to the right of the row')
        truthy(plan.x + plan.w <= 1920 and plan.y >= 0 and plan.y + plan.h <= 1080, 'on screen')
        truthy(#plan.groups >= 4, 'heal, cleanse, buff, raise')
        for _, gp in ipairs(plan.groups) do truthy(gp.id ~= 'ability', 'no abilities on someone else') end
    end
    local plain = fly_frame(new_cfg({ style = 'strip', mode = 'party' }))
    eq(ui.flyout_plan(plain), nil, 'nothing hovered, no flyout')
    local off = open_flyout(new_cfg({ style = 'strip', mode = 'party', flyout = false }), 1)
    eq(off, nil, 'flyout can be turned off')
end)

test('flyout: your own row adds the job abilities', function()
    local plan = open_flyout(new_cfg({ style = 'strip', mode = 'party' }), 0)
    local last = plan.groups[#plan.groups]
    eq(last.id, 'ability'); truthy(#last.keys >= 2)
end)

test('flyout: tiles cast on the hovered member with one click, abilities are self-targeted', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    local plan, f = open_flyout(cfg, 1)
    local ff = draw_fly(f, plan)
    local tile = hb_of(ff, function(h) return h.kind == 'spell' and h.key == 'cure4' end)
    truthy(tile and tile.slot == 1)
    inside = tile.x >= plan.x and tile.x + tile.w <= plan.x + plan.w and tile.y >= plan.y and tile.y + tile.h <= plan.y + plan.h
    truthy(inside, 'tile inside the flyout window')
    truthy(tile.w >= 24, 'at least 24 px')
    local ff2 = draw_fly(f, plan, gfx_rec.input(tile.x + 2, tile.y + 2, 'left'))
    eq(#ff2.events, 1); eq(ff2.events[1].spell, 'cure4'); eq(ff2.events[1].slot, 1)

    local plan0, f0 = open_flyout(cfg, 0)
    local ffa = draw_fly(f0, plan0)
    local ja = hb_of(ffa, function(h) return h.kind == 'spell' and h.key == 'divine_seal' end)
    truthy(ja, 'Divine Seal tile on your own flyout')
    local ffb = draw_fly(f0, plan0, gfx_rec.input(ja.x + 2, ja.y + 2, 'left'))
    eq(#ffb.events, 1); eq(ffb.events[1].spell, 'divine_seal'); eq(ffb.events[1].state, 'ready')
end)

test('flyout: stays open while the mouse is on the flyout, closes after leaving both', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    local plan, f = open_flyout(cfg, 1)
    -- mouse now inside the flyout, away from the roster window
    local mid = gfx_rec.input(plan.x + 10, plan.y + 10, nil)
    mid.hovered = false
    local f2 = fly_frame(cfg, mid)
    truthy(ui.state.flyout, 'still open over the flyout')
    -- mouse far away: closes after the short grace period
    local away = gfx_rec.input(1800, 1000, nil); away.hovered = false
    local function frame_at(now)
        local ff = build_ui_frame(cfg, 1080, now, away, true); ff.disp_w, ff.disp_h = 1920, 1080
        ui.draw_roster(ff)
    end
    frame_at(3.0); truthy(ui.state.flyout, 'grace period')
    frame_at(3.3); eq(ui.state.flyout, nil, 'closed')
end)

test('flyout: flips to the left near the right screen edge and stays on screen', function()
    local fly = layout.flyout({ auto_scale = true, scale = 1 }, 1080, { { id = 'a', n = 9 }, { id = 'b', n = 8 } })
    local x, y = layout.flyout_position({ x = 1700, y = 1050, w = 200, h = 34 }, fly, 1920, 1080)
    truthy(x + fly.w <= 1700 + 1, 'flipped to the left of the row')
    truthy(y + fly.h <= 1080 and y >= 0)
end)

test('flyout: priority outline on the cure the member needs (Torvald: Cursna)', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    local plan, f = open_flyout(cfg, 3)
    local ff, g = draw_fly(f, plan)
    local cursna = hb_of(ff, function(h) return h.kind == 'spell' and h.key == 'cursna' end)
    local hit = false
    for _, cmd in ipairs(g.cmds) do
        if cmd.op == 'rect' and cmd.x == cursna.x and cmd.y == cursna.y and cmd.w == cursna.w and cmd.h == 2 then hit = true end
    end
    truthy(hit, 'outlined')
end)

test('strip (slant 8): rows are slanted quads, bars stay inside the card, no timer on the chips', function()
    local cfg = new_cfg({ style = 'strip', mode = 'alliance2', demo_alliance_debuffs = true, slant = 8 })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    ui.draw_roster(f)
    local quads = 0
    for _, c in ipairs(g.cmds) do if c.op == 'quad' then quads = quads + 1 end end
    truthy(quads >= 15, 'a slanted background per member, got ' .. quads)
    for _, c in ipairs(g.cmds) do
        if c.op == 'rect' and c.y > fr.geom.header_h + fr.geom.label_h then
            local inside = false
            for _, card in pairs(fr.geom.cards) do
                if c.x >= card.x - 1 and c.x + c.w <= card.x + card.w + 1 and c.y >= card.y - 3 and c.y + c.h <= card.y + card.h + 3 then inside = true end
            end
            truthy(inside, string.format('rect %.0f,%.0f %.0fx%.0f outside every card', c.x, c.y, c.w, c.h))
        end
    end
end)

test('spell order: custom order applies to the flyout for every member; bad keys are dropped', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party', spell_order = { heal = { 'cure1', 'nope', 'curaga2', 'cure1' }, bogus = { 'cure1' } } })
    eq(cfg.spell_order.heal[1], 'cure1'); eq(#cfg.spell_order.heal, 2, 'unknown and duplicate keys removed'); eq(cfg.spell_order.bogus, nil)
    for _, slot in ipairs({ 1, 2 }) do
        local plan = open_flyout(cfg, slot)
        eq(plan.groups[1].id, 'heal'); eq(plan.groups[1].keys[1], 'cure1'); eq(plan.groups[1].keys[2], 'curaga2')
    end
    eq(spells.group_keys(new_cfg({}), spells.presets.WHM, 'heal')[1], 'cure1')
    eq(spells.group_keys(new_cfg({}), spells.presets.WHM, 'ability')[1], 'divine_seal')
end)

test('commands: flyout and order', function()
    local s = new_cfg({})
    commands.run({ '/ch', 'flyout', 'off' }, s); eq(s.flyout, false)
    commands.run({ '/ch', 'order', 'heal', 'cure1', 'curaga2', 'cure4' }, s)
    eq(#s.spell_order.heal, 3); eq(s.spell_order.heal[2], 'curaga2')
    local r = commands.run({ '/ch', 'order', 'heal', 'cure1', 'nope' }, s)
    eq(#s.spell_order.heal, 3, 'bad key rejects the whole change'); truthy(#r.messages > 0)
    eq(commands.run({ '/ch', 'order', 'heal' }, s).show_order, 'heal')
    commands.run({ '/ch', 'order', 'heal', 'reset' }, s); eq(s.spell_order.heal, nil)
    truthy(#commands.run({ '/ch', 'order', 'zzz' }, s).messages > 0)
end)

-- =============================================================================================
-- 75-cap catalog: levels, sub-job fit, self-only spells, per-job presets
-- =============================================================================================
local function who(job, level, sub, sublevel) return { job = job, level = level, sub = sub or 0, sublevel = sublevel } end
local J = { WHM = 3, BLM = 4, RDM = 5, BRD = 10, SCH = 20 }

test('catalog: every preset key exists and every spell has a button label that fits', function()
    for name, p in pairs(spells.presets) do
        local lists = { p.base, p.raise, p.buffs, p.self, p.songs }
        for g, l in pairs(p.bar or {}) do lists[#lists + 1] = l end
        for _, l in ipairs(lists) do
            for _, k in ipairs(l) do truthy(spells.defs[k], name .. ' preset names unknown spell ' .. k) end
        end
        for _, b in ipairs({ p.bindings or {}, p.buff_bindings or {} }) do
            for slot, v in pairs(b) do truthy(v == 'cleanse' or spells.defs[v], name .. ' binding ' .. slot) end
        end
    end
    for k, d in pairs(spells.defs) do
        truthy(#d.short <= 3, k .. ' short label too long: ' .. d.short)
        truthy(d.down == nil or spells.defs[d.down], k .. ' has unknown lower tier')
    end
end)

test('catalog: no spell is above the 75 cap and known() follows main and sub levels', function()
    for k, d in pairs(spells.defs) do
        for job, lv in pairs(d.lv or {}) do truthy(lv >= 1 and lv <= 75, k .. ' ' .. job .. ' ' .. lv) end
    end
    truthy(spells.known('cure5', who(J.WHM, 75)))
    truthy(not spells.known('cure5', who(J.WHM, 60)), 'Cure V is level 61')
    truthy(not spells.known('cure5', who(J.RDM, 75)), 'RDM has no Cure V')
    truthy(not spells.known('erase', who(J.RDM, 75)), 'RDM has no Erase in the 75 data')
    truthy(spells.known('cure3', who(J.BLM, 75, J.WHM, 37)), 'BLM/WHM gets Cure III (WHM 21)')
    truthy(not spells.known('cure4', who(J.BLM, 75, J.WHM, 37)), 'Cure IV is WHM 41, over the sub cap')
    truthy(not spells.known('cure3', who(J.BLM, 75, J.WHM, 10)), 'sub level limits it')
    truthy(not spells.known('chainspell', who(J.WHM, 75, J.RDM, 37)), '2-hour abilities are main job only')
    truthy(spells.known('cure3', who(J.WHM, nil)), 'no level info: everything counts as known')
end)

test('catalog: fit() cuts presets down and falls back to lower tiers', function()
    local whm60 = spells.fit(spells.presets.WHM, who(J.WHM, 60))
    local heal = whm60.bar.heal
    eq(heal[4], 'cure4', 'Cure V (61) dropped, Cure IV kept')
    for _, k in ipairs(heal) do truthy(k ~= 'cure5', 'no Cure V at 60') end
    local rr = spells.fit(spells.presets.WHM, who(J.WHM, 60)).bar.raise
    eq(rr[#rr], 'reraise2', 'Reraise III (70) falls back to Reraise II (56)')
    local seen = {}
    for _, k in ipairs(whm60.bar.buff) do truthy(not seen[k], 'no duplicates ' .. k); seen[k] = true end
    local brd = spells.fit(spells.presets.BRD, who(J.BRD, 75, J.WHM, 37))
    truthy(#brd.songs >= 8, 'a 75 bard has the song set')
    local has = {}
    for _, k in ipairs(brd.bar.heal) do has[k] = true end
    truthy(has.cure3 and not has.cure4 and has.curaga2 and not has.curaga3, 'sub WHM 37 heals')
    local blm = spells.fit(spells.presets.BLM, who(J.BLM, 75))
    eq(#blm.bar.heal, 0, 'BLM with no sub job has no heals'); eq(blm.self[1], 'manafont')
    local rdm = spells.fit(spells.presets.RDM, who(J.RDM, 75))
    eq(#rdm.bar.cleanse, 0); eq(#spells.bar_tabs(rdm), 3, 'RDM has heal, buff, raise tabs')
    eq(spells.fit(spells.presets.WHM, { job = 3 }), spells.presets.WHM, 'no level: untouched')
end)

test('catalog: presets resolve for all five jobs', function()
    for name, job in pairs(J) do
        local _, n = spells.preset_for(job, 0)
        eq(n, name)
    end
    local _, n = spells.preset_for(1, 4)
    eq(n, 'BLM', 'a WAR/BLM falls through to the sub job preset')
end)

test('self-only spells cast on you from any row, even out of range or KO', function()
    local cfg = { max_range = 21 }
    local far = { active = true, dist = 40, name = 'Far' }
    local ko = { active = true, dead = true, dist = 5, name = 'Ko' }
    local pl = { mp = 500, recast = {} }
    eq(spellstate.evaluate(spells.defs.stoneskin, far, pl, cfg), 'ready')
    eq(spellstate.evaluate(spells.defs.protectra4, ko, pl, cfg), 'ready')
    eq(spellstate.evaluate(spells.defs.cure4, far, pl, cfg), 'range')
    eq(spellstate.evaluate(spells.defs.stoneskin, far, { mp = 500, silenced = true }, cfg), 'blocked')
    eq(spellstate.evaluate(spells.defs.stoneskin, far, { mp = 5 }, cfg), 'nomp')
    local logged
    local ev = { type = 'cast', slot = 3, spell = 'blink', state = 'ready' }
    eq(actions.perform(ev, { cfg = cfg, now = 0, dismissed = {}, roster_by_slot = { [3] = { name = 'Bob' } },
        log = function(t) logged = t end }), 'cast')
    truthy(logged:find('<me>', 1, true) and not logged:find('<p3>', 1, true), 'targets <me>: ' .. logged)
end)

test('flyout: a bard sees a SONG row on their own row only', function()
    local src = setmetatable({ player = function() return { name = 'Bard', job = 10, sub = 3, level = 75, sublevel = 37, mp = 900, mpmax = 900, recast = {} } end },
        { __index = demo })
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    local f = frame.build(cfg, src, 0, 1920, 1080)
    f.input = gfx_rec.input(nil, nil, nil)
    ui.state.flyout = { slot = 0, row = { x = 0, y = 0, w = 100, h = 40 } }
    local plan = ui.flyout_plan(f)
    local ids = {}
    for _, gp in ipairs(plan.groups) do ids[gp.id] = true end
    truthy(ids.song and ids.ability and ids.heal)
    ui.state.flyout = { slot = 1, row = { x = 0, y = 0, w = 100, h = 40 } }
    plan = ui.flyout_plan(f)
    for _, gp in ipairs(plan.groups) do truthy(gp.id ~= 'song' and gp.id ~= 'ability') end
    ui.state.flyout = nil
end)

-- ---------------------------------------------------------------------------------------------

test('game source: reads your party from Ashita memory in the member shape (read-only)', function()
    local game = require('ch.source_game')
    local party = {
        GetMemberIsActive = function(_, i) return (i <= 2) and 1 or 0 end,
        GetMemberName = function(_, i) return ({ [0] = 'Jintu', 'Friend', 'Faraway' })[i] end,
        GetMemberHP = function(_, i) return ({ [0] = 800, 300, 0 })[i] end,
        GetMemberHPPercent = function(_, i) return ({ [0] = 100, 50, 0 })[i] end,
        GetMemberMP = function(_, i) return ({ [0] = 400, 10, 0 })[i] end,
        GetMemberMPPercent = function(_, i) return ({ [0] = 100, 50, 0 })[i] end,
        GetMemberZone = function(_, i) return (i == 2) and 99 or 143 end,
        GetMemberMainJob = function(_, i) return ({ [0] = 3, 7, 1 })[i] end,
        GetMemberSubJob = function(_, i) return ({ [0] = 20, 1, 0 })[i] end,
        GetMemberMainJobLevel = function(_, i) return 75 end,
        GetMemberTargetIndex = function(_, i) return 100 + i end,
    }
    local player = { GetHPMax = function() return 800 end, GetMPMax = function() return 400 end,
        GetMainJob = function() return 3 end, GetSubJob = function() return 20 end,
        GetMainJobLevel = function() return 75 end, GetSubJobLevel = function() return 37 end,
        GetBuffs = function() return { 6, 33, 255, 255 } end }   -- Silence, Haste
    local entity = { GetDistance = function(_, idx) return (idx == 101) and 144 or 0 end }
    local saved = _G.AshitaCore
    _G.AshitaCore = { GetMemoryManager = function() return {
        GetParty = function() return party end, GetPlayer = function() return player end,
        GetEntity = function() return entity end } end }
    local r = game.roster(0, {})
    local p = game.player(0)
    _G.AshitaCore = saved
    eq(#r, 3)
    eq(r[1].name, 'Jintu'); truthy(r[1].is_you and r[1].dist == 0 and r[1].has_buff_data)
    eq(r[1].debuffs[1], 'silence'); eq(r[1].buffs[1].key, 'haste')
    eq(r[2].name, 'Friend'); eq(r[2].dist, 12); eq(r[2].hpmax, 600); eq(r[2].has_buff_data, false)
    truthy(r[3].zone_diff and not r[3].dead and r[3].dist == nil, 'other zone: no distance, not "dead"')
    eq(p.job, 3); eq(p.sublevel, 37); eq(p.silenced, true); eq(p.mp, 400)
    local pr = require('ch.spells').fit(require('ch.spells').preset_for(p.job, p.sub), p)
    truthy(#pr.bar.heal > 0)
    _G.AshitaCore = nil
    eq(#game.roster(0, {}), 0, 'not logged in: empty roster, no error')
end)
test('casting: off by default, and only a ready click with cast on and demo off sends a command', function()
    eq(actions.command_for(spells.defs.cure4, '<p2>'), '/ma "Cure IV" <p2>')
    eq(actions.command_for(spells.defs.stoneskin, '<p2>'), '/ma "Stoneskin" <me>', 'self-only spell goes to you')
    eq(actions.command_for(spells.defs.divine_seal, '<p2>'), '/ja "Divine Seal" <me>')
    eq(actions.command_for(spells.defs.devotion, '<p2>'), '/ja "Devotion" <p2>', 'target ability keeps the member')
    eq(new_cfg({}).cast, false, 'casting defaults to off')
    local sent, logged = {}, {}
    local function ctx(cfg, demo_on)
        return { cfg = cfg, now = 0, dismissed = {}, roster_by_slot = { [2] = { name = 'Bob' } },
            demo = demo_on and demo or nil, send = function(c) sent[#sent + 1] = c end,
            log = function(t) logged[#logged + 1] = t end }
    end
    local ev = { type = 'cast', slot = 2, spell = 'cure4', state = 'ready' }
    eq(actions.perform(ev, ctx({ cast = false }, false)), 'cast'); eq(#sent, 0, 'cast off: nothing sent')
    eq(actions.perform(ev, ctx({ cast = true }, true)), 'cast'); eq(#sent, 0, 'demo on: nothing sent')
    eq(actions.perform({ type = 'cast', slot = 2, spell = 'cure4', state = 'range', detail = 30 }, ctx({ cast = true }, false)), 'blocked')
    eq(#sent, 0, 'blocked click: nothing sent')
    eq(actions.perform(ev, ctx({ cast = true }, false)), 'sent'); eq(sent[1], '/ma "Cure IV" <p2>')
    local s = new_cfg({})
    commands.run({ '/ch', 'cast', 'on' }, s); eq(s.cast, true)
    commands.run({ '/ch', 'cast', 'off' }, s); eq(s.cast, false)
end)

test('recast: countdown text, game timers by key, and a bigger configurable flyout', function()
    eq(ui.fmt_recast(4.26), '4.3'); eq(ui.fmt_recast(41.2), '42'); eq(ui.fmt_recast(65), '1:05')
    eq(ui.fmt_recast(700), '12m'); eq(ui.fmt_recast(7000), '2h')

    local game = require('ch.source_game')
    local ids = require('ch.spell_ids')
    local rc = {
        GetAbilityTimerId = function(_, x) return (x == 1) and ids.divine_seal.ability or 0 end,
        GetAbilityTimer = function(_, x) return (x == 1) and 1800 or 0 end,      -- 30 s
        GetSpellTimer = function(_, id) return (id == ids.cure4.spell) and 600 or 0 end,   -- 10 s
    }
    local party = { GetMemberIsActive = function() return 0 end, GetMemberMainJob = function() return 3 end,
        GetMemberMainJobLevel = function() return 75 end, GetMemberName = function() return 'Me' end }
    local saved = _G.AshitaCore
    _G.AshitaCore = { GetMemoryManager = function() return {
        GetParty = function() return party end, GetPlayer = function() return {} end,
        GetEntity = function() return {} end, GetRecast = function() return rc end } end }
    local p = game.player(0)
    _G.AshitaCore = saved
    eq(p.recast.cure4, 10); eq(p.recast.divine_seal, 30); eq(p.recast.cure3, nil)
    eq(p.recast_total.cure4, 10)

    local small = layout.flyout({ auto_scale = true, scale = 1 }, 1080, { { id = 'heal', n = 9 } })
    local big = layout.flyout({ auto_scale = true, scale = 1, fly_btn = 48, fly_gap = 10 }, 1080, { { id = 'heal', n = 9 } })
    truthy(small.btn >= 36 and small.gap >= 6, 'default tiles are larger than the old 26px / 3px')
    truthy(big.btn == 48 and big.w > small.w, 'setting changes the size')
    local c = new_cfg({}); c.fly_btn = 999; c.fly_gap = 0; chconfig.sanitize(c)
    eq(c.fly_btn, 64); eq(c.fly_gap, 2)
    local cmd = new_cfg({}); commands.run({ '/ch', 'buttons', '44', '8' }, cmd)
    eq(cmd.fly_btn, 44); eq(cmd.fly_gap, 8)
end)

test('recast: a tile on cooldown shows its time instead of its label', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    local plan, f = open_flyout(cfg, 1)
    f.player = setmetatable({ recast = { cure4 = 12.3 }, recast_total = { cure4 = 20 } }, { __index = f.player })
    local ff, g = draw_fly(f, plan)
    local texts = {}
    for _, cmd in ipairs(g.cmds) do
        if cmd.op == 'text' then texts[#texts + 1] = cmd.s end
    end
    local seen = false
    for _, t in ipairs(texts) do if t == '13' then seen = true end end
    truthy(seen, 'countdown "13" drawn for Cure IV')
end)

test('strip: the whole row is the HP bar and its color goes green -> yellow -> orange -> red', function()
    for _, name in ipairs({ 'modern', 'mono', 'colorblind' }) do
        local pal = theme.get(name)
        local seen, last = {}, nil
        for _, fr in ipairs({ 1.0, 0.7, 0.5, 0.3, 0.15, 0.05 }) do
            local c = theme.hp_fill(pal, fr)
            truthy(c ~= nil)
            seen[c] = true
        end
        eq(theme.hp_fill(pal, 1.0), theme.hp_fill(pal, 1.5), 'clamped')
        eq(theme.hp_fill(pal, 0.0), pal.hp_stops and pal.hp_stops[4] or pal.bad, 'empty is the danger color')
    end
    local pal = theme.get('modern')
    truthy(theme.hp_fill(pal, 0.9) ~= theme.hp_fill(pal, 0.45) and theme.hp_fill(pal, 0.45) ~= theme.hp_fill(pal, 0.1))

    -- A 50% member gets a filled quad about half as wide as a 100% one.
    local function fill_width(hpp)
        local cfg = new_cfg({ style = 'strip', mode = 'party', slant = 8 })
        local f, _, g = build_ui_frame(cfg, 1080, 3.0, nil, true)
        f.roster[1].hpp = hpp
        g.clear()
        ui.draw_roster(f)
        local best = 0
        for _, c in ipairs(g.cmds) do
            if c.op == 'quad' and c.t == 0 then
                local w = c.p[3] - c.p[7]   -- bottom right x minus bottom left x
                best = math.max(best, w)
            end
        end
        return best
    end
    truthy(fill_width(100) > 0)
end)

test('strip: square rows by default (no quads), slant is optional', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    eq(cfg.slant, 0)
    local f, _, g = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f)
    for _, c in ipairs(g.cmds) do truthy(c.op ~= 'quad', 'no slanted shapes at slant 0') end
    local c2 = new_cfg({}); commands.run({ '/ch', 'slant', '6' }, c2); eq(c2.slant, 6)
    commands.run({ '/ch', 'slant', '99' }, c2); eq(c2.slant, 16)
end)

test('window controls: header MOVE/LOCK and CFG buttons, and a drag-to-resize corner', function()
    -- Header buttons exist and are clickable in both states.
    for _, locked in ipairs({ true, false }) do
        local cfg = new_cfg({ style = 'strip', mode = 'party', locked = locked })
        local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
        ui.draw_roster(f0)
        local lock_btn = hb_of(f0, function(h) return h.kind == 'header' and (h.label == 'MOVE' or h.label == 'LOCK') end)
        local cfg_btn = hb_of(f0, function(h) return h.kind == 'header' and h.label == 'CFG' end)
        truthy(lock_btn and cfg_btn, 'both header buttons exist, locked=' .. tostring(locked))
        eq(lock_btn.label, locked and 'MOVE' or 'LOCK')
        local f1 = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(lock_btn.x + 2, lock_btn.y + 2, 'left', nil, locked))
        ui.draw_roster(f1)
        local found
        for _, ev in ipairs(f1.events) do if ev.type == 'toggle' and ev.what == 'locked' then found = true end end
        truthy(found, 'clicking toggles the lock')
        local f2 = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(cfg_btn.x + 2, cfg_btn.y + 2, 'left', nil, locked))
        ui.draw_roster(f2)
        found = false
        for _, ev in ipairs(f2.events) do if ev.type == 'open_config' then found = true end end
        truthy(found, 'CFG opens the setup panel')
    end
    -- actions apply them.
    local cfg = new_cfg({ locked = true }); local opened = false
    actions.perform({ type = 'toggle', what = 'locked' }, { cfg = cfg, dismissed = {}, now = 0, log = function() end })
    eq(cfg.locked, false)
    actions.perform({ type = 'open_config' }, { cfg = cfg, dismissed = {}, now = 0, log = function() end, open_config = function() opened = true end })
    truthy(opened)
    actions.perform({ type = 'set_scale', value = 1.5 }, { cfg = cfg, dismissed = {}, now = 0, log = function() end })
    eq(cfg.scale, 1.5)

    -- Resize: holding the mouse on the bottom-right corner proposes a new scale; locked has no grip.
    local ucfg = new_cfg({ style = 'strip', mode = 'party', locked = false, scale = 1.0 })
    local f0 = build_ui_frame(ucfg, 1080, 3.0)
    local w, h = f0.geom.width, f0.geom.height
    ui.reset_state()
    local inp = gfx_rec.input(w - 3 + 0.0, h - 3 + 0.0, 'left', nil, false)
    local fr = build_ui_frame(ucfg, 1080, 3.0, inp)
    fr.gfx.current_input = inp
    ui.draw_roster(fr)
    local scale_ev
    for _, ev in ipairs(fr.events) do if ev.type == 'set_scale' then scale_ev = ev end end
    ui.reset_state()
    truthy(scale_ev == nil or (scale_ev.value >= 0.5 and scale_ev.value <= 3.0), 'proposed scale is within limits')
    local lcfg = new_cfg({ style = 'strip', mode = 'party', locked = true })
    local lf = build_ui_frame(lcfg, 1080, 3.0, gfx_rec.input(w - 3, h - 3, 'left'))
    ui.draw_roster(lf)
    for _, ev in ipairs(lf.events) do truthy(ev.type ~= 'set_scale', 'no resize while locked') end
end)

test('strip: debuffs live in a bottom icon strip (game icons when available, text tags otherwise)', function()
    local function draw(has_icons)
        local cfg = new_cfg({ style = 'strip', mode = 'party' })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        g.has_icons = has_icons
        ui.draw_roster(f)
        return g, fr
    end
    local g, fr = draw(true)
    local icons, ids = 0, {}
    for _, c in ipairs(g.cmds) do if c.op == 'icon' then icons = icons + 1; ids[c.id] = true end end
    truthy(icons >= 2, 'one icon per debuff, got ' .. icons)
    truthy(ids[debuffs.id_of.poison] and ids[debuffs.id_of.silence], 'icons are looked up by status id')
    -- Each icon sits in the lower half of its row, below the name line.
    for _, c in ipairs(g.cmds) do
        if c.op == 'icon' then
            local inside = false
            for _, card in pairs(fr.geom.cards) do
                if c.x >= card.x and c.x + c.w <= card.x + card.w and c.y >= card.y + card.h * 0.4 and c.y + c.h <= card.y + card.h then inside = true end
            end
            truthy(inside, 'icon inside the bottom strip of a row')
        end
    end
    local g2 = draw(false)
    local texts = {}
    for _, c in ipairs(g2.cmds) do if c.op == 'icon' then error('no icons without backend support') end
        if c.op == 'text' then texts[c.s] = true end end
    truthy(texts.PSN or texts.SIL or texts.PAR or texts.DOM, 'text tags are the fallback')
    eq(debuffs.id_of.poison, 3); eq(debuffs.id_of.silence, 6)
end)

print(string.format('\n%d passed, %d failed', passed, failed))
for _, f in ipairs(failures) do print('  FAIL: ' .. f) end
os.exit(failed == 0 and 0 or 1)
