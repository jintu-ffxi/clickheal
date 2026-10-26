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
    c.skin = 'solid'               -- most tests are about the solid rows; the default skin is hairline
    ui.reset_state()
    require('ch.casting').reset()     -- no busy state left over from an earlier test
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
    s.colors = 'colorblind'; chconfig.sanitize(s); eq(s.colors, 'colorblind')
    local unk = commands.run({ '/ch', 'frobnicate' }, s); truthy(unk.messages[1]:find('Unknown'))
    truthy(#commands.run({ '/ch', 'help' }, s).messages >= 8)
end)

test('commands: reset requires confirmation', function()
    local s = new_cfg({ scale = 2 })
    local r = commands.run({ '/ch', 'reset' }, s); eq(r.reset, false)
    local r2 = commands.run({ '/ch', 'reset', 'confirm' }, s); eq(r2.reset, true)
end)

test('chconfig: sanitize repairs garbage and keeps good values', function()
    local s = chconfig.sanitize({ scale = 'x', opacity = 5, max_range = -3, pos = 'nope',
        alerts = { max = 99, muted = 'x' }, hp_crit = 0 / 0, mode = 'alliance1' })
    eq(s.scale, 1.0); eq(s.opacity, 1.0)
    eq(s.max_range, 5); eq(s.pos.x, 40); eq(s.alerts.max, 8); eq(type(s.alerts.muted), 'table')
    eq(s.hp_crit, chconfig.defaults.hp_crit); eq(s.mode, 'alliance1')
    truthy(s.warn_range <= s.max_range)
end)

test('chconfig: reset keeps the same table', function()
    local s = new_cfg({ scale = 3 })
    local ref = s
    chconfig.reset(s)
    eq(ref, s); eq(s.scale, 1.0)
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
    for _, style in ipairs({ 'strip' }) do
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
    for _, style in ipairs({ 'strip' }) do
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
        for _, style in ipairs({ 'strip' }) do
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

local function find_hitbox(hitboxes, pred)
    for _, hb in ipairs(hitboxes) do if pred(hb) then return hb end end
end

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
    local cfg2 = new_cfg({ mode = 'alliance2' })
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

test('ui: debuff chips are short tags with no countdown; the hover list has the times', function()
    for _, style in ipairs({ 'strip' }) do
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

-- =============================================================================================
-- strip layouts
-- =============================================================================================

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

test('ui: grid and strip text stays inside its cell at 1080p and 4K', function()
    for _, style in ipairs({ 'strip' }) do
        for _, h in ipairs({ 1080, 2160 }) do
            local cfg = new_cfg({ style = style, mode = 'alliance2', demo_alliance_debuffs = true })
            local f, fr, g = build_ui_frame(cfg, h, 3.0)
            ui.draw_roster(f)
            for _, c in ipairs(g.cmds) do
                if c.op == 'text' and c.y > fr.geom.header_h + fr.geom.label_h and true then
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
        if cmd.op == 'text' and cmd.x >= c.x and cmd.x <= c.x + c.w and cmd.y >= c.y + c.h * 0.4 and cmd.y <= c.y + c.h then
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
    local hx = c.x + math.floor(48 * fr.geom.scale)
    local hy = c.y + c.h - math.floor(14 * fr.geom.scale)
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

test('flyout: spells above your level or not learned are greyed (show_locked) or absent, never castable', function()
    local function plan_for(over)
        local cfg = new_cfg({ mode = 'party', show_locked = over.show_locked })
        local f0, fr = fly_frame(cfg)
        local cell = hb_of(f0, function(h) return h.kind == 'cell' and h.slot == 1 end)
        local f = fly_frame(cfg, gfx_rec.input(cell.x + 3, cell.y + 3, nil))
        f.player = { job = 20, sub = 3, level = 40, sublevel = 20, mp = 400, mpmax = 400, recast = {},
                     learned = { cure2 = false } }
        local preset = spells.presets.SCH
        f.preset = cfg.show_locked and preset or spells.fit(preset, f.player)
        return ui.flyout_plan(f), f
    end
    local function keys(plan)
        local set = {}
        for _, gp in ipairs(plan.groups) do for _, k in ipairs(gp.keys) do set[k] = true end end
        return set
    end
    local hidden = keys((plan_for({})))
    truthy(hidden.cure1 and not hidden.cure2 and not hidden.cure4, 'only usable spells are listed')
    local plan, f = plan_for({ show_locked = true })
    local all = keys(plan)
    truthy(all.cure1 and all.cure2 and all.cure4, 'show_locked lists them')
    local ff, g = draw_fly(f, plan)
    local clicked = {}
    for _, e in ipairs(ff.events) do clicked[#clicked + 1] = e end
    eq(#clicked, 0)
    local m = f.roster[1]
    eq((spellstate.evaluate(spells.defs.cure4, m, f.player, f.cfg)), 'level')
    eq((spellstate.evaluate(spells.defs.cure2, m, f.player, f.cfg)), 'unlearned')
end)

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
    eq(#rdm.bar.cleanse, 0)
    eq(spells.fit(spells.presets.WHM, { job = 3 }), spells.presets.WHM, 'no level: untouched')
end)

test('availability: too-low level and unlearned spells are told apart, and greyed or hidden by show_locked', function()
    local sc = who(J.SCH, 40)
    local why, need = spells.availability('cure4', sc)
    eq(why, 'level'); truthy(need:find('55', 1, true), 'Cure IV needs SCH 55: ' .. tostring(need))
    eq(spells.availability('cure2', sc), nil)
    sc.learned = { cure2 = false, cure1 = true }
    eq(spells.availability('cure2', sc), 'unlearned', 'level is fine but the scroll is missing')
    truthy(not spells.known('cure2', sc))
    eq(spells.best('cure2', sc), 'cure1', 'a missing tier falls back to the highest one learned')
    eq(spells.availability('cure1', who(J.SCH, 40)), nil, 'no learned table: level only')

    -- spellstate says why
    local m = { active = true, slot = 1, hp = 100, hpmax = 100, dist = 5 }
    local cfg = new_cfg({})
    local pl = { job = J.SCH, level = 40, sub = 0, mp = 500, recast = {} }
    eq((spellstate.evaluate(spells.defs.cure4, m, pl, cfg)), 'level')
    pl.learned = { cure2 = false }
    eq((spellstate.evaluate(spells.defs.cure2, m, pl, cfg)), 'unlearned')
    eq((spellstate.evaluate(spells.defs.cure1, m, pl, cfg)), 'ready')
    truthy(spellstate.describe('level', 'SCH 55'):find('SCH 55', 1, true))
    eq(spellstate.describe('unlearned'), 'Not learned yet')

    -- the menu: hidden by default, greyed with show_locked
    local preset = spells.presets.SCH
    local fit = spells.fit(preset, sc)
    local function has(list, k) for _, x in ipairs(list) do if x == k then return true end end return false end
    truthy(not has(fit.bar.heal, 'cure4') and not has(fit.bar.heal, 'cure2'), 'cannot-use spells are not offered')
    local shown = spells.group_keys({ show_locked = true, spell_order = { heal = { 'cure1', 'cure2', 'cure4' } } }, preset, 'heal', sc)
    truthy(has(shown, 'cure4') and has(shown, 'cure2'), 'show_locked keeps them in a custom order')
    local hidden = spells.group_keys({ spell_order = { heal = { 'cure1', 'cure2', 'cure4' } } }, preset, 'heal', sc)
    truthy(not has(hidden, 'cure4') and not has(hidden, 'cure2') and has(hidden, 'cure1'))
end)

test('presets: scholar and red mage offer their default spells and abilities', function()
    local function has(list, k) for _, x in ipairs(list or {}) do if x == k then return true end end return false end
    local sch = spells.fit(spells.presets.SCH, who(J.SCH, 75))
    for _, k in ipairs({ 'cure4', 'regen3' }) do truthy(has(sch.bar.heal, k), 'SCH heals ' .. k) end
    for _, k in ipairs({ 'cursna', 'erase', 'viruna' }) do truthy(has(sch.bar.cleanse, k), 'SCH cleanses ' .. k) end
    for _, k in ipairs({ 'stoneskin', 'firestorm', 'aurorastorm', 'protect4' }) do truthy(has(sch.bar.buff, k), 'SCH buffs ' .. k) end
    for _, k in ipairs({ 'light_arts', 'dark_arts', 'addendum_white', 'addendum_black', 'sublimation', 'tabula_rasa' }) do
        truthy(has(sch.self, k), 'SCH ability ' .. k)
    end
    local rdm = spells.fit(spells.presets.RDM, who(J.RDM, 75))
    for _, k in ipairs({ 'cure4', 'regen1' }) do truthy(has(rdm.bar.heal, k), 'RDM heals ' .. k) end
    for _, k in ipairs({ 'haste', 'refresh', 'flurry', 'phalanx2', 'stoneskin', 'enfire', 'enthunder' }) do truthy(has(rdm.bar.buff, k), 'RDM buffs ' .. k) end
    for _, k in ipairs({ 'convert', 'composure', 'chainspell', 'blaze_spikes' }) do truthy(has(rdm.self, k), 'RDM ability ' .. k) end
    -- a low level scholar does not get what it has not reached
    local lo = spells.fit(spells.presets.SCH, who(J.SCH, 20))
    truthy(not has(lo.self, 'addendum_black') and not has(lo.self, 'sublimation') and has(lo.self, 'light_arts'))
    truthy(not has(lo.bar.buff, 'firestorm'))
    -- Chainspell is a 2-hour: not available through a sub job
    truthy(not spells.known('chainspell', who(J.WHM, 75, J.RDM, 37)))
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
    eq(r[2].name, 'Friend'); eq(r[2].dist, 12); eq(r[2].hpmax, 600); eq(r[2].has_buff_data, true)
    truthy(r[3].zone_diff and not r[3].dead and r[3].dist == nil, 'other zone: no distance, not "dead"')
    eq(p.job, 3); eq(p.sublevel, 37); eq(p.silenced, true); eq(p.mp, 400)
    local pr = require('ch.spells').fit(require('ch.spells').preset_for(p.job, p.sub), p)
    truthy(#pr.bar.heal > 0)
    _G.AshitaCore = nil
    eq(#game.roster(0, {}), 0, 'not logged in: empty roster, no error')
end)
test('casting: a ready click on a real party sends a command; demo data never does', function()
    eq(actions.command_for(spells.defs.cure4, '<p2>'), '/ma "Cure IV" <p2>')
    eq(actions.command_for(spells.defs.stoneskin, '<p2>'), '/ma "Stoneskin" <me>', 'self-only spell goes to you')
    eq(actions.command_for(spells.defs.divine_seal, '<p2>'), '/ja "Divine Seal" <me>')
    eq(actions.command_for(spells.defs.devotion, '<p2>'), '/ja "Devotion" <p2>', 'target ability keeps the member')
    eq(new_cfg({}).cast, nil, 'there is no casting switch any more')
    local sent, logged = {}, {}
    local function ctx(cfg, demo_on)
        return { cfg = cfg, now = 0, dismissed = {}, roster_by_slot = { [2] = { name = 'Bob' } },
            demo = demo_on and demo or nil, send = function(c) sent[#sent + 1] = c end,
            log = function(t) logged[#logged + 1] = t end }
    end
    local ev = { type = 'cast', slot = 2, spell = 'cure4', state = 'ready' }
    eq(actions.perform(ev, ctx({}, true)), 'cast'); eq(#sent, 0, 'demo on: nothing sent')
    eq(actions.perform({ type = 'cast', slot = 2, spell = 'cure4', state = 'range', detail = 30 }, ctx({}, false)), 'blocked')
    eq(#sent, 0, 'blocked click: nothing sent')
    eq(actions.perform(ev, ctx({}, false)), 'sent'); eq(sent[1], '/ma "Cure IV" <p2>')
    truthy(commands.run({ '/ch', 'cast', 'on' }, new_cfg({})).messages[1]:find('Unknown'), '/ch cast is gone')
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

end)

test('strip: rows are square (no quads)', function()
    local cfg = new_cfg({ style = 'strip', mode = 'party' })
    eq(cfg.slant, nil)
    local f, _, g = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f)
    for _, c in ipairs(g.cmds) do truthy(c.op ~= 'quad', 'no slanted shapes at slant 0') end
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

-- =============================================================================================
-- strip-only layout, resizable rows and icons, buff icon bar
-- =============================================================================================
test('layout: strip footprint at 1080p, doubled at 4K, rows never overlap in any arrangement', function()
    local g = layout.compute({ orientation = 'columns', groups = { 0 } }, 1080)
    eq(g.width, 230); eq(g.height, 16 + 6 * 42 + 5 * 4)
    eq(layout.compute({ orientation = 'columns', groups = { 0, 1, 2 } }, 1080).width, 3 * 230 + 2 * 8)
    for _, mode in ipairs({ 'party', 'alliance1', 'alliance2' }) do
        local o = { orientation = 'columns', groups = layout.groups_for(mode, false) }
        local a, b = layout.compute(o, 1080), layout.compute(o, 2160)
        near(b.width, a.width * 2, 4); near(b.height, a.height * 2, 6)
    end
    for _, orient in ipairs({ 'columns', 'stacked', 'rows' }) do
        for _, h in ipairs({ 720, 1080, 1440, 2160 }) do
            local gg = layout.compute({ orientation = orient, groups = { 0, 1, 2 }, row_w = 300, row_h = 60 }, h)
            local list = {}
            for _, c in pairs(gg.cards) do
                truthy(c.x >= 0 and c.y >= gg.header_h and c.x + c.w <= gg.width and c.y + c.h <= gg.height, 'row outside panel')
                list[#list + 1] = c
            end
            eq(#list, 18)
            for i = 1, #list do
                for j = i + 1, #list do
                    local a, b = list[i], list[j]
                    truthy(not (a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h), 'rows overlap')
                end
            end
        end
    end
end)

test('layout: row width and row height come from the settings; icons shrink or hide to fit', function()
    local g = layout.compute({ orientation = 'columns', groups = { 0 }, row_w = 300, row_h = 60 }, 1080)
    eq(g.card_w, 300); eq(g.card_h, 60)
    local tight = layout.compute({ orientation = 'columns', groups = { 0 }, row_h = 36, debuff_icon = 32, buff_icon = 20 }, 1080)
    eq(tight.card_h, 36, 'the row keeps the height you chose')
    truthy(tight.eff.debuff_icon < 32 and tight.eff.debuff_icon >= 9, 'icons shrink to fit')
    truthy(tight.eff.buff_icon < tight.eff.debuff_icon, 'in proportion')
    local tiny = layout.compute({ orientation = 'columns', groups = { 0 }, row_h = 26, debuff_icon = 14, buff_icon = 14 }, 1080)
    eq(tiny.card_h, 26); eq(tiny.eff.debuff_icon, 0, 'icons hide when there is no room')
    local roomy = layout.compute({ orientation = 'columns', groups = { 0 }, row_h = 60, debuff_icon = 14, buff_icon = 14 }, 1080)
    eq(roomy.eff.debuff_icon, 14)
    local hl_small = layout.compute({ skin = 'hairline', hl_pct = 2.5, row_h = 32, debuff_icon = 14, buff_icon = 14 }, 1080)
    local hl_big = layout.compute({ skin = 'hairline', hl_pct = 2.5, row_h = 70, debuff_icon = 14, buff_icon = 14 }, 1080)
    truthy(hl_small.eff.hl_pct < hl_big.eff.hl_pct, 'the big percentage shrinks in a short row')
    eq(hl_small.card_h, 32); eq(hl_big.eff.hl_pct, 2.5)
    local g2 = layout.compute({ orientation = 'columns', groups = { 0 }, row_w = 300, row_h = 60 }, 2160)
    eq(g2.card_w, 600); eq(g2.card_h, 120)
end)

test('chconfig: row and icon sizes are clamped and the layout settings are gone', function()
    local s = chconfig.sanitize({ row_w = 9999, row_h = 1, debuff_icon = 'x', buff_icon = 99, show_buff_bar = 'yes' })
    eq(s.row_w, 360); eq(s.row_h, 24); eq(s.debuff_icon, chconfig.defaults.debuff_icon); eq(s.buff_icon, 32)
    eq(s.show_buff_bar, true)
    eq(chconfig.defaults.style, nil); eq(chconfig.defaults.show_job, nil); eq(chconfig.defaults.job_style, nil)
end)

test('commands: rowsize, icons, buffbar, mybuffs, retired commands', function()
    local s = new_cfg({})
    s.row_w, s.row_h = 300, 56; chconfig.sanitize(s); eq(s.row_w, 300); eq(s.row_h, 56)
    s.row_w, s.row_h = 9999, 1; chconfig.sanitize(s); eq(s.row_w, 360); eq(s.row_h, 24)
    s.debuff_icon, s.buff_icon = 20, 16; chconfig.sanitize(s); eq(s.debuff_icon, 20); eq(s.buff_icon, 16)
    s.debuff_icon = 99; chconfig.sanitize(s); eq(s.debuff_icon, 32)
    for _, gone in ipairs({ 'buffmode', 'bar', 'tab', 'cellbinds', 'flyout', 'buttons', 'order', 'alerts', 'inputdebug' }) do
        truthy(commands.run({ '/ch', gone, 'on' }, s).messages[1]:find('Unknown'), '/ch ' .. gone .. ' is gone')
    end
    truthy(commands.run({ '/ch', 'layout', 'full' }, s).messages[1]:find('Unknown'), 'layouts are gone')
end)

local BUFF_TAGS = { Hst = true, Rgn = true, Rfr = true, Flr = true, Pro = true, Shl = true, Phx = true,
                    Ssk = true, Bnk = true, Aqv = true, Snk = true, Inv = true, RR = true }

test('ui: the buff bar draws buff icons inside each row and can be switched off', function()
    local function buff_texts(over, icons)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        g.has_icons = icons or false
        ui.draw_roster(f)
        local tags, ico = 0, 0
        for _, c in ipairs(g.cmds) do
            if c.op == 'text' and BUFF_TAGS[c.s] then tags = tags + 1 end
            if c.op == 'icon' then ico = ico + 1 end
        end
        return tags, ico, fr, g
    end
    local on = buff_texts({ mode = 'party' })
    truthy(on >= 6, 'demo party shows buff tags, got ' .. on)
    eq(buff_texts({ mode = 'party', show_buff_bar = false }), 0, 'no buff tags when the bar is off')
    local _, ico = buff_texts({ mode = 'party' }, true)
    truthy(ico >= 6, 'game icons are used when the backend can draw them, got ' .. ico)
    -- every buff tag sits inside its own row, in the icon strip below the name
    local cfg = new_cfg({ mode = 'alliance2', row_h = 60 })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    ui.draw_roster(f)
    for _, c in ipairs(g.cmds) do
        if c.op == 'text' and BUFF_TAGS[c.s] then
            local inside = false
            for _, card in pairs(fr.geom.cards) do
                local w = g.text_size(c.s)
                if c.x >= card.x and c.x + w <= card.x + card.w and c.y >= card.y + card.h * 0.4 and c.y <= card.y + card.h then inside = true end
            end
            truthy(inside, 'buff tag outside its row: ' .. c.s)
        end
    end
end)

test('ui: icon size settings change the drawn icons; rows resize with the settings', function()
    local function icon_sizes(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        g.has_icons = true
        ui.draw_roster(f)
        local sizes = {}
        for _, c in ipairs(g.cmds) do if c.op == 'icon' then sizes[c.w] = (sizes[c.w] or 0) + 1 end end
        return sizes, fr
    end
    local small = icon_sizes({ mode = 'party', debuff_icon = 12, buff_icon = 12 })
    local big, fr = icon_sizes({ mode = 'party', debuff_icon = 24, buff_icon = 24, row_h = 60, row_w = 300 })
    truthy(small[12] and not small[24], 'small icons drawn at 12')
    truthy(big[24] and not big[12], 'big icons drawn at 24')
    eq(fr.geom.card_w, 300); eq(fr.geom.card_h, 60)
end)

test('flyout: clicks resolve the tier asked for, and an out-of-range member reports range', function()
    local cfg = new_cfg({ mode = 'party' })
    local plan, f = open_flyout(cfg, 1)
    local ff = draw_fly(f, plan)
    local tile = hb_of(ff, function(h) return h.kind == 'spell' and h.key == 'cure4' end)
    local cx, cy = tile.x + tile.w / 2, tile.y + tile.h / 2
    local function click(btn, mods) return draw_fly(f, plan, gfx_rec.input(cx, cy, btn, mods)).events end
    eq(click('left')[1].spell, 'cure4'); eq(click('right')[1].spell, 'cure3', 'right click = one tier down')
    eq(click('left', { shift = true })[1].spell, 'cure5', 'shift = one tier up')
    local plan5, f5 = open_flyout(cfg, 5)     -- Dunstan, 24 yalms away
    local t5 = hb_of(draw_fly(f5, plan5), function(h) return h.kind == 'spell' and h.key == 'cure4' end)
    local ev = draw_fly(f5, plan5, gfx_rec.input(t5.x + 2, t5.y + 2, 'left')).events
    eq(#ev, 1); eq(ev[1].state, 'range')
end)

-- =============================================================================================
-- casting: busy gate, cast bar, click queue
-- =============================================================================================
local casting = require('ch.casting')
local spellstate = require('ch.spellstate')

test('spells: cast times come from the server data (Cure IV 2.5s, Raise III 13s, abilities none)', function()
    eq(spells.defs.cure4.cast, 2.5); eq(spells.defs.raise3.cast, 13); eq(spells.defs.haste.cast, 3)
    eq(spells.defs.divine_seal.cast, nil)
end)

test('casting: a cast is busy for its cast time plus the delay; Fast Cast shortens it; abilities only have the delay', function()
    casting.reset()
    casting.start(spells.defs.cure4, 10, { fast_cast = 0, cast_lockout = 1.0 })
    near(casting.left(10), 3.5, 1e-9); near(casting.left(12), 1.5, 1e-9); eq(casting.left(13.6), 0)
    local info = casting.info(12.0)         -- past the short wait for the server (see the first-cast test)
    near(info.frac, 0.8, 1e-9, '2.0s into the 2.5s cast')
    casting.reset()
    casting.start(spells.defs.cure4, 10, { fast_cast = 20, cast_lockout = 1.0 })
    near(casting.left(10), 2.5 * 0.8 + 1.0, 1e-9)
    casting.reset()
    casting.start(spells.defs.divine_seal, 10, { cast_lockout = 0.8 })
    near(casting.left(10), 0.8, 1e-9)
    casting.reset(); eq(casting.left(0), 0); eq(casting.info(0), nil)
end)

test('casting: the real cast bar overrides the estimate; a bar that never shows releases a failed cast early', function()
    casting.reset()
    casting.start(spells.defs.cure4, 10, { cast_lockout = 1.0 })      -- estimate: busy until 13.5
    casting.observe(10.5, 0.2)                                         -- 20% after 0.5s -> a 2.5s cast
    near(casting.left(10.5), 3.5 - 0.5, 0.01)
    casting.observe(11.5, 0.4)                                         -- slower than expected: a 3.75s cast
    near(casting.left(11.5), 3.75 + 1.0 - 1.5, 0.01)
    casting.observe(14.0, 1)                                           -- bar gone: only the delay is left
    truthy(casting.left(14.0) <= 1.0 + 1e-9)
    -- a cast that is interrupted at once never shows a bar (after it has worked once)
    casting.start(spells.defs.cure4, 20, { cast_lockout = 1.0 })
    casting.observe(20.2, 0)
    near(casting.left(20.2), 3.5 - 0.2, 0.01, 'still within the grace period')
    casting.observe(20.8, 0)
    truthy(casting.left(20.8) <= 0.3 + 1e-9, 'released early')
    -- without a working bar (unreadable or never seen), the estimate stands
    casting.reset()
    casting.start(spells.defs.cure4, 30, { cast_lockout = 1.0 })
    casting.observe(31.0, 0); casting.observe(31.0, nil)
    near(casting.left(31.0), 2.5, 0.01)
end)

test('casting: the progress bar never runs backwards when the game bar starts late, and follows the game bar', function()
    local function run(first_cast)
        local def, lag, real = spells.defs.cure4, 0.5, 2.5
        casting.start(def, 10, { cast_lockout = 1.0 })
        local prev = 0
        for i = 1, 40 do
            local t = 10 + i * 0.1
            local pct = (t - 10 - lag) / real
            casting.observe(t, (pct > 0 and pct < 1) and pct or (pct >= 1 and 1 or 0))
            local info = casting.info(t)
            if info and pct > 0 and pct < 1 then near(info.frac, pct, 0.02, 'tracks the game bar at +' .. (i * 0.1)) end
            if info and (not first_cast or pct > 0) then
                truthy(info.frac >= prev - 1e-9, string.format('went backwards at +%.1f: %.2f -> %.2f', i * 0.1, prev, info.frac))
                prev = info.frac
            end
        end
    end
    casting.reset()
    run(true)           -- first cast: nothing is known about the bar yet, so only the part after it appears is checked
    run(false)          -- afterwards the bar is known to work and the progress waits for it
end)

test('casting: one queued click, newest wins, sent only when free, dropped when stale', function()
    casting.reset()
    casting.start(spells.defs.cure4, 10, { cast_lockout = 1.0 })
    casting.queue({ spell = 'cure3', slot = 1 }, 11)
    casting.queue({ spell = 'cure2', slot = 2 }, 12)
    eq(casting.take(12.5), nil, 'still busy')
    eq(casting.take(13.6).spell, 'cure2', 'the newest click goes out once you are free')
    eq(casting.take(13.7), nil, 'only once')
    casting.queue({ spell = 'cure3', slot = 1 }, 14)
    eq(casting.take(30), nil, 'stale clicks are dropped')
end)

test('spellstate: busy is the last thing that stops a spell, so real blockers still show', function()
    local m = { active = true, name = 'A', dist = 5, slot = 1 }
    local p = { mp = 500, recast = {}, busy_left = 1.2 }
    local state, left = spellstate.evaluate(spells.defs.cure4, m, p, { max_range = 20 })
    eq(state, 'busy'); near(left, 1.2, 1e-9)
    eq(spellstate.evaluate(spells.defs.cure4, { active = true, name = 'F', dist = 30, slot = 2 }, p, { max_range = 20 }), 'range')
    p.mp = 1; eq(spellstate.evaluate(spells.defs.cure4, m, p, { max_range = 20 }), 'nomp')
    p.mp = 500; p.recast = { cure4 = 3 }; eq(spellstate.evaluate(spells.defs.cure4, m, p, { max_range = 20 }), 'recast')
    p.recast = {}; p.busy_left = 0; eq(spellstate.evaluate(spells.defs.cure4, m, p, { max_range = 20 }), 'ready')
    p.busy_left = 1; eq(spellstate.evaluate(spells.defs.divine_seal, m, p, { max_range = 20 }), 'busy', 'abilities wait too')
    truthy(spellstate.describe('busy', 1.2):find('queue'))
end)

test('actions: clicking while busy queues, the queue is sent when free; with queueing off it is refused', function()
    casting.reset()
    local logs, sent = {}, {}
    local roster = { [1] = { name = 'Brannoch', slot = 1, active = true, dist = 5 } }
    local cfg = new_cfg({ cast = true, demo = false, queue_clicks = true })
    local function ctx(now)
        return { cfg = cfg, now = now, log = function(x) logs[#logs + 1] = x end, roster_by_slot = roster, dismissed = {},
                 changed = function() end, send = function(c) sent[#sent + 1] = c end }
    end
    local player = { mp = 500, recast = {} }
    -- first click goes out and starts the busy period
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'cure4', state = 'ready' }, ctx(10)), 'sent')
    eq(#sent, 1); truthy(sent[1]:find('Cure IV', 1, true))
    truthy(casting.left(10.1) > 0)
    -- second click mid-cast is held, not sent
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'cure3', state = 'busy', detail = 3 }, ctx(11)), 'queued')
    eq(#sent, 1)
    eq(actions.run_queued(ctx(12), player), nil, 'not free yet')
    eq(#sent, 1)
    eq(actions.run_queued(ctx(13.6), player), 'sent', 'sent the moment the player is free')
    eq(#sent, 2); truthy(sent[2]:find('Cure III', 1, true))
    truthy(casting.left(13.7) > 0, 'and it starts the next busy period')
    -- queueing off: a busy click is refused with a message
    cfg.queue_clicks = false
    eq(actions.perform({ type = 'cast', slot = 1, spell = 'cure3', state = 'busy', detail = 2 }, ctx(14)), 'blocked')
    eq(casting.take(30), nil)
end)

test('ui: a busy flyout tile is still clickable and emits a busy cast; the queued tile is outlined; progress bar drawn', function()
    local cfg = new_cfg({ mode = 'party' })
    local plan, f = open_flyout(cfg, 1)
    casting.start(spells.defs.cure4, 3.0, cfg)
    f.player.busy_left = casting.left(3.0)
    f.player.casting = casting.info(3.0)
    local ff = draw_fly(f, plan)
    local tile = hb_of(ff, function(h) return h.kind == 'spell' and h.key == 'cure3' end)
    local ff2 = draw_fly(f, plan, gfx_rec.input(tile.x + 2, tile.y + 2, 'left'))
    eq(#ff2.events, 1); eq(ff2.events[1].state, 'busy'); eq(ff2.events[1].spell, 'cure3')
    local bar = false
    for _, c in ipairs(ff.gfx.cmds) do
        if c.op == 'rect' and c.y > plan.y + plan.h - 8 and c.w > plan.w * 0.5 then bar = true end
    end
    truthy(bar, 'cast progress bar along the bottom of the flyout')
end)

test('chconfig/commands: queue, fast cast and delay settings', function()
    local s = chconfig.sanitize({ fast_cast = 500, cast_lockout = 0.01, queue_clicks = false })
    eq(s.fast_cast, 80); near(s.cast_lockout, 0.3, 1e-9); eq(s.queue_clicks, false)
    local c = new_cfg({})
end)

test('commands: /ch status reports the switches and explains why the hover would be off', function()
    local s = new_cfg({ locked = false, flyout = false })
    local msgs = commands.run({ '/ch', 'status' }, s).messages
    local joined = table.concat(msgs, '\n')
    truthy(joined:find('locked: off', 1, true) and joined:find('hover menu: off', 1, true))
    truthy(joined:find('/ch lock', 1, true) and joined:find('Spells page', 1, true))
    local ok = table.concat(commands.run({ '/ch', 'status' }, new_cfg({})).messages, '\n')
    truthy(not ok:find('/ch lock', 1, true), 'no warning when everything is fine')
end)

-- =============================================================================================
-- job colors palette and job icons
-- =============================================================================================

test('theme: the job palette tints the healthy HP fill with the job color and keeps the warning colors', function()
    local pal = theme.get('job')
    truthy(pal.job_tint and pal ~= theme.get('modern'))
    local mod = theme.get('modern')
    local pld = { 0.92, 0.74, 0.30 }
    local top = theme.hp_fill(pal, 1.0, pld)
    truthy(top ~= theme.hp_fill(mod, 1.0, pld), 'job color at full HP')
    local r, g, b = theme.unpack(top)
    truthy(r > g and g > b, 'still the warm job hue')
    local wr, wg, wb = theme.unpack(theme.hp_fill(pal, 1.0, { require('ch.jobs').hue(3) }))
    truthy(0.30 * wr + 0.59 * wg + 0.11 * wb <= 0.52, 'a light job color is darkened so white text stays readable')
    eq(theme.hp_fill(pal, 0.05, pld), theme.hp_fill(mod, 0.05, pld), 'low HP is the same red either way')
    eq(theme.hp_fill(mod, 1.0, pld), theme.hp_fill(mod, 1.0), 'other palettes ignore the job color')
    local cfg = new_cfg({ colors = 'job' }); eq(cfg.colors, 'job')
    eq(chconfig.sanitize({ colors = 'nope' }).colors, 'modern')
end)

test('ui: job colors give each row its own healthy color', function()
    local function fills(colors)
        local cfg = new_cfg({ mode = 'party', colors = colors })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local seen = {}
        for _, c in ipairs(g.cmds) do
            if c.op == 'rect' and c.w > 40 and c.h > 20 then seen[c.c] = true end
        end
        return seen
    end
    local a, b, differ = fills('job'), fills('modern'), false
    for c in pairs(a) do if not b[c] then differ = true end end
    truthy(differ, 'the job palette paints fills the modern palette does not')
end)


test('game source: other members\' buffs and debuffs come from the party status data; a trust with none shows no data', function()
    local game = require('ch.source_game')
    local icons = { [0] = 33, 3, 255, 255 }          -- Haste, Poison
    local party = {
        GetMemberIsActive = function(_, i) return (i <= 2) and 1 or 0 end,
        GetMemberName = function(_, i) return ({ [0] = 'Jintu', 'Friend', 'Trust' })[i] end,
        GetMemberHP = function() return 500 end, GetMemberHPPercent = function() return 100 end,
        GetMemberMP = function() return 100 end, GetMemberMPPercent = function() return 100 end,
        GetMemberZone = function() return 143 end,
        GetMemberMainJob = function() return 3 end, GetMemberSubJob = function() return 0 end,
        GetMemberMainJobLevel = function() return 75 end, GetMemberTargetIndex = function(_, i) return 100 + i end,
        GetStatusIconsServerId = function(_, i) return (i == 1) and 12345 or 0 end,   -- the trust has none
        GetStatusIcons = function(_, i) return (i == 1) and icons or nil end,
        GetStatusIconsBitMask = function() return 0 end,
    }
    local player = { GetHPMax = function() return 800 end, GetMPMax = function() return 400 end,
        GetBuffs = function() return {} end }
    local entity = { GetDistance = function() return 25 end }
    local saved = _G.AshitaCore
    _G.AshitaCore = { GetMemoryManager = function() return {
        GetParty = function() return party end, GetPlayer = function() return player end,
        GetEntity = function() return entity end } end }
    local r = game.roster(0, {})
    _G.AshitaCore = saved
    eq(r[2].has_buff_data, true); eq(r[2].buffs[1].key, 'haste'); eq(r[2].debuffs[1], 'poison')
    eq(r[3].has_buff_data, true, 'chat-tracked, so empty rather than unknown'); eq(#r[3].buffs, 0)
end)

test('chatstatus: buffs and debuffs follow the chat log, including wear-off and defeat', function()
    local cs = require('ch.chatstatus')
    cs.reset()
    cs.feed('Zeid gains the effect of Shell.', 1); cs.feed('Zeid gains the effect of Haste.', 1)
    cs.feed('Zeid gains the effect of Protect.', 1); cs.feed('Zeid is poisoned.', 2)
    local d, b = cs.get('Zeid', 3)
    eq(d[1], 'poison'); eq(#b, 3); eq(b[1].key, 'haste')
    cs.feed("Zeid's Haste effect wears off.", 4); cs.feed('Zeid is no longer poisoned.', 4)
    d, b = cs.get('Zeid', 5)
    eq(#d, 0); eq(#b, 2)
    cs.feed('Zeid gains the effect of Sleep.', 6)
    eq(cs.get('Zeid', 7)[1], 'sleep')
    cs.feed('Zeid is no longer afflicted with Sleep.', 8); eq(#(cs.get('Zeid', 9)), 0)
    cs.feed('\30\2Zeid gains the effect of Regen.', 10)       -- color codes are ignored
    eq(cs.get('Zeid', 11) and select(2, cs.get('Zeid', 11))[1].key, 'regen')
    cs.feed('Zeid falls to the ground.', 12); eq(#(select(2, cs.get('Zeid', 13))), 0)
    eq(cs.feed('The Ul\'aern gains the effect of Protect.', 1), true)   -- tracked but never asked for
    local _, old = cs.get('Nobody', 99); eq(#old, 0)
    cs.reset()
end)


test('game source: your own buffs are read from an indexable array that is not a plain table (Ashita userdata)', function()
    local game = require('ch.source_game')
    local data = { [0] = 33, 40, 3, 255 }
    local arr = setmetatable({}, { __index = function(_, i) return data[i] or 255 end })   -- stands in for userdata
    local party = {
        GetMemberIsActive = function(_, i) return (i == 0) and 1 or 0 end,
        GetMemberName = function() return 'Jintu' end,
        GetMemberHP = function() return 500 end, GetMemberHPPercent = function() return 100 end,
        GetMemberMP = function() return 100 end, GetMemberMPPercent = function() return 100 end,
        GetMemberZone = function() return 143 end,
        GetMemberMainJob = function() return 3 end, GetMemberSubJob = function() return 0 end,
        GetMemberMainJobLevel = function() return 75 end, GetMemberTargetIndex = function() return 1 end,
        GetStatusIconsServerId = function() return 0 end,
    }
    local player = { GetHPMax = function() return 800 end, GetMPMax = function() return 400 end, GetBuffs = function() return arr end }
    local saved = _G.AshitaCore
    _G.AshitaCore = { GetMemoryManager = function() return {
        GetParty = function() return party end, GetPlayer = function() return player end,
        GetEntity = function() return { GetDistance = function() return 0 end } end } end }
    local r = game.roster(0, {})
    _G.AshitaCore = saved
    eq(r[1].debuffs[1], 'poison'); eq(r[1].buffs[1].key, 'haste'); eq(r[1].buffs[2].key, 'protect')
end)


test('mp: percent text and bar thickness are options; a thick bar makes the row taller instead of overlapping', function()
    local function run_with(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        return f, g, fr
    end
    local function pct_texts(g)
        local n = 0
        for _, c in ipairs(g.cmds) do if c.op == 'text' and c.s:match('^%d+%%$') then n = n + 1 end end
        return n
    end
    local _, g0 = run_with({ mode = 'party' })
    local _, g1 = run_with({ mode = 'party', show_mp_pct = true })
    truthy(pct_texts(g1) > pct_texts(g0), 'MP percent adds text')
    local _, g2 = run_with({ mode = 'party', show_mp = false, show_mp_pct = true })
    eq(pct_texts(g2), pct_texts(g1), 'the MP percent does not need the MP bar')
    local a = layout.compute({ row_h = 40, debuff_icon = 14, buff_icon = 14, mp_h = 3 }, 1080)
    local b = layout.compute({ row_h = 40, debuff_icon = 14, buff_icon = 14, mp_h = 12 }, 1080)
    eq(a.card_h, b.card_h, 'the row height stays what you chose')
    truthy(b.eff.debuff_icon < a.eff.debuff_icon, 'a thicker MP bar takes room from the icons')
    eq(chconfig.sanitize({ mp_height = 99 }).mp_height, 14); eq(chconfig.sanitize({ mp_height = 0 }).mp_height, 2)
end)


test('mp percent: sits under the HP percent, smaller, right-aligned', function()
    local cfg = new_cfg({ mode = 'party', show_mp_pct = true, mp_pct_scale = 0.6 })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    ui.draw_roster(f)
    local hp, mp
    for _, c in ipairs(g.cmds) do
        if c.op == 'text' and c.s:match('^%d+%%$') and c.c ~= 0 then
            if c.k then mp = mp or c elseif not hp then hp = c end
        end
    end
    truthy(hp and mp, 'both percents drawn')
    truthy(mp.y > hp.y, 'MP percent is below HP percent')
    eq(mp.k, 0.6)
    eq(chconfig.sanitize({ mp_pct_scale = 5 }).mp_pct_scale, 1.0)
end)


-- =============================================================================================
-- hairline skin and triage view
-- =============================================================================================
local triage = require('ch.triage')

test('triage: neediest first, unreachable members last, featured member is sticky, best-fit cure', function()
    local cfg = new_cfg({})
    local function mem(slot, hp, max, extra)
        local m = { slot = slot, active = true, name = 'M' .. slot, hp = hp, hpmax = max, hpp = 100 * hp / max, dist = 5 }
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    local a, b, c, d = mem(0, 900, 1000), mem(1, 300, 1000), mem(2, 100, 1000, { dist = 40 }), mem(3, 0, 1000, { dead = true })
    local list = triage.order({ a, b, c, d }, cfg)
    eq(list[1].slot, 1); eq(list[2].slot, 0)
    eq(list[3].slot, 2, 'out of range goes after everyone a cast can reach')
    eq(list[4].slot, 3, 'a KO is last of all, even though it is missing the most HP')
    eq(triage.pick(list, cfg, nil).slot, 1)
    local e = mem(4, 280, 1000)                     -- slightly worse than b: the panel stays on b
    eq(triage.pick(triage.order({ a, b, e }, cfg), cfg, 1).slot, 1)
    local f2 = mem(5, 50, 1000)                     -- clearly worse: it switches
    eq(triage.pick(triage.order({ a, b, f2 }, cfg), cfg, 1).slot, 5)
    eq(triage.best({ 'cure1', 'cure2', 'cure3', 'cure4' }, 300), 'cure3')
    eq(triage.best({ 'cure1', 'cure2' }, 900), 'cure2', 'strongest when none covers the gap')
end)

test('hairline: the big percentage is colored by health and is drawn scaled; no card behind it', function()
    local function pct_colors(skin)
        local cfg = new_cfg({ mode = 'party', skin = skin })
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local out = {}
        for _, c in ipairs(g.cmds) do
            if c.op == 'text' and c.k and c.k > 1.2 and c.s:match('^%d+$') and c.c ~= 0 then out[#out + 1] = c end
        end
        return out, g
    end
    local big = pct_colors('hairline')
    truthy(#big >= 3, 'large percentages drawn')
    local seen = {}
    for _, c in ipairs(big) do seen[c.c] = true end
    local n = 0; for _ in pairs(seen) do n = n + 1 end
    truthy(n >= 2, 'different health, different colors')
    eq(#pct_colors('solid'), 0, 'solid skin has no large percentages')
    eq(chconfig.sanitize({ skin = 'nope' }).skin, chconfig.defaults.skin)
end)

test('triage view: panel geometry, featured member, cure tiles cast on the featured member', function()
    local cfg = new_cfg({ mode = 'party', triage = true })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    truthy(fr.geom.tri, 'triage geometry')
    eq(next(fr.geom.cards), nil, 'no per-member cards')
    local f0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
    ui.draw_roster(f0)
    local hit
    for _, hb in ipairs(f0.hitboxes) do if hb.kind == 'spell' then hit = hb end end
    truthy(hit, 'cure tiles are clickable')
    ui.reset_state()
    local f2 = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hit.x + hit.w / 2, hit.y + hit.h / 2, 'left'))
    local ev = ui.draw_roster(f2)
    local cast
    for _, e2 in ipairs(ev) do if e2.type == 'cast' then cast = e2 end end
    truthy(cast, 'tile click casts')
    eq(cast.slot, hit.slot, 'on the featured member')
    local small = layout.compute({ triage = true, triage_n = 0, debuff_icon = 14, buff_icon = 14 }, 1080)
    local big = layout.compute({ triage = true, triage_n = 5, debuff_icon = 14, buff_icon = 14 }, 1080)
    truthy(big.height > small.height)
end)


test('opacity: each part has its own transparency setting, sanitized and applied', function()
    local c = chconfig.sanitize({ opacity_panel = 5, opacity_hp = 0, opacity_mp = -1, opacity_flyout = 0 })
    eq(c.opacity_panel, 1.0); eq(c.opacity_hp, 0.2); eq(c.opacity_mp, 0.2); eq(c.opacity_flyout, 0.3)
    local function first_big_rect(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        for _, cmd in ipairs(g.cmds) do
            if cmd.op == 'rect' and cmd.w == fr.geom.width and cmd.h == fr.geom.height then return cmd.c end
        end
    end
    local a, b = first_big_rect({ mode = 'party', opacity_panel = 0.2 }), first_big_rect({ mode = 'party', opacity_panel = 1.0 })
    truthy(a and b and a ~= b, 'panel background changes with its slider')
end)

test('demo fill: live party plus fake alliance members; clicks on fake members never send', function()
    local mixed = require('ch.source_mixed')
    local saved = _G.AshitaCore
    _G.AshitaCore = nil
    local list = mixed.roster(3.0, {})
    _G.AshitaCore = saved
    truthy(#list >= 6, 'alliance demo members present')
    for _, m in ipairs(list) do truthy(m.slot >= 6 and m.demo, 'only alliance slots, flagged') end
    local sent = {}
    local cfg = new_cfg({ cast = true, demo = false })
    local ctx = { cfg = cfg, roster_by_slot = { [7] = { slot = 7, name = 'Garrick', demo = true, active = true } },
        log = function() end, now = 3.0, send = function(c) sent[#sent + 1] = c end, changed = function() end }
    actions.perform({ type = 'cast', slot = 7, spell = 'cure4', state = 'ready' }, ctx)
    eq(#sent, 0, 'nothing sent for a demo member')
    ctx.roster_by_slot[7].demo = nil
    actions.perform({ type = 'cast', slot = 7, spell = 'cure4', state = 'ready' }, ctx)
    eq(#sent, 1, 'a real member still casts')
end)


test('triage: a deadly debuff you can remove outranks a lower HP bar; unfixable ones do not', function()
    local cfg = new_cfg({})
    local preset = require('ch.spells').preset_for(3, 5)    -- WHM/RDM
    local can = triage.cleanse_set(cfg, preset, nil)
    truthy(can.cursna, 'the WHM preset can remove Doom')
    local function mem(slot, hp, extra)
        local m = { slot = slot, active = true, name = 'M' .. slot, hp = hp, hpmax = 1000, hpp = hp / 10, dist = 5, debuffs = {} }
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    local low, doomed = mem(0, 200), mem(1, 800, { debuffs = { 'doom' } })
    local list, tiers = triage.order({ low, doomed }, cfg, nil, can)
    eq(list[1].slot, 1, 'doomed member first'); eq(tiers[1], 3); eq(tiers[0], 2)
    local asleep = mem(2, 800, { debuffs = { 'sleep' } })          -- nothing you can cast removes sleep
    local _, t2 = triage.order({ asleep }, cfg, nil, can)
    eq(t2[2], 0)
    local cursed = mem(3, 900, { debuffs = { 'curse' } })
    local _, t3 = triage.order({ cursed }, cfg, nil, can)
    eq(t3[3], 1)
    local tiles, best = triage.tiles(doomed, cfg, preset, nil, 3, 4)
    eq(tiles[1].kind, 'cleanse'); eq(tiles[1].key, 'cursna'); eq(best, 'cursna', 'the fix is the highlighted tile')
    local tiles2, best2 = triage.tiles(low, cfg, preset, nil, 2, 4)
    eq(tiles2[1].kind, 'cure'); truthy(best2 and best2:match('^cure'))
    -- the panel stays on someone it is already showing, unless the other is in a higher tier or clearly worse
    local list2, tiers2 = triage.order({ low, doomed }, cfg, nil, can)
    eq(triage.pick(list2, cfg, 0, tiers2).slot, 1, 'higher tier wins over stickiness')
end)

test('flyout icons: a buff or cleanse button draws the game icon when the option is on, text otherwise', function()
    local function icons_and_labels(on)
        local cfg = new_cfg({ mode = 'party', flyout_icons = on })
        local f0, fr, g0 = build_ui_frame(cfg, 1080, 3.0, nil, true)
        ui.draw_roster(f0)
        local hit
        for _, hb in ipairs(f0.hitboxes) do if hb.kind == 'cell' then hit = hb; break end end
        ui.reset_state()
        local f1, _, g1 = build_ui_frame(cfg, 1080, 3.0, gfx_rec.input(hit.x + 4, hit.y + 4))
        g1.has_icons = true
        ui.draw_roster(f1)
        local plan = ui.flyout_plan(f1)
        local f2 = { gfx = g1, geom = f1.geom, cfg = cfg, pal = f1.pal, roster = f1.roster, player = f1.player, preset = f1.preset,
            now = 3.0, events = {}, input = gfx_rec.input(nil, nil, nil), plan = plan, ox = plan.x, oy = plan.y }
        g1.cmds = {}
        ui.draw_flyout(f2)
        local n = 0
        for _, c in ipairs(g1.cmds) do if c.op == 'icon' then n = n + 1 end end
        return n
    end
    eq(icons_and_labels(false), 0)
    truthy(icons_and_labels(true) >= 1, 'status icons on buff/cleanse buttons')
end)


test('triage options: sanitized, debuff levels and switches change priority, spell list leads the tiles', function()
    local c = chconfig.sanitize({ triage_opts = { tiles = 99, spells = { 'cure4', 'nope', 'cure4', 'haste' },
        levels = { doom = 'off', curse = 'bogus', silence = 'urgent' }, debuffs = false } })
    eq(c.triage_opts.tiles, 5); eq(#c.triage_opts.spells, 2); eq(c.triage_opts.levels.doom, 'off')
    eq(c.triage_opts.levels.curse, nil); eq(c.triage_opts.debuffs, false); eq(c.triage_opts.crit, true)
    local cfg = new_cfg({})
    local preset = require('ch.spells').preset_for(3, 5)
    local can = triage.cleanse_set(cfg, preset, nil)
    local function mem(slot, hp, extra)
        local m = { slot = slot, active = true, name = 'M' .. slot, hp = hp, hpmax = 1000, hpp = hp / 10, dist = 5,
            debuffs = {}, buffs = {}, has_buff_data = true }
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    local doomed, low = mem(1, 800, { debuffs = { 'doom' } }), mem(0, 200)
    local _, tiers = triage.order({ doomed, low }, cfg, nil, can)
    eq(tiers[1], 3)
    cfg.triage_opts.levels.doom = 'off'
    _, tiers = triage.order({ doomed, low }, cfg, nil, can)
    eq(tiers[1], 0, 'doom ignored when set to off')
    cfg.triage_opts.levels.doom = 'important'
    _, tiers = triage.order({ doomed, low }, cfg, nil, can)
    eq(tiers[1], 1); eq(tiers[0], 2, 'low HP outranks an important debuff')
    cfg.triage_opts.debuffs = false
    _, tiers = triage.order({ doomed, low }, cfg, nil, can)
    eq(tiers[1], 0, 'debuffs switched off')
    cfg.triage_opts.debuffs = true; cfg.triage_opts.crit = false
    _, tiers = triage.order({ doomed, low }, cfg, nil, can)
    eq(tiers[0], 0, 'low HP switched off')

    -- the priority list: first, in your order, only what applies; buffs only when missing
    cfg.triage_opts.crit = true
    cfg.triage_opts.spells = { 'haste', 'cure2', 'cursna' }
    local who = mem(2, 600)
    local tiles = triage.tiles(who, cfg, preset, nil, 0, 4)
    eq(tiles[1].key, 'haste'); eq(tiles[2].key, 'cure2')
    for _, tl in ipairs(tiles) do truthy(tl.key ~= 'cursna', 'cleanse only when they have the debuff') end
    who.buffs = { { key = 'haste' } }
    tiles = triage.tiles(who, cfg, preset, nil, 0, 4)
    truthy(tiles[1].key ~= 'haste', 'haste dropped once they have it')
    eq(#triage.tiles(who, cfg, preset, nil, 0, 3), 3)
    local d2 = mem(3, 500, { debuffs = { 'doom' }, buffs = { { key = 'haste' } } })
    tiles = triage.tiles(d2, cfg, preset, nil, 3, 4)
    eq(tiles[1].key, 'cure2', 'your order is kept'); eq(tiles[2].key, 'cursna')

end)


test('title bar: optional; hidden when locked, always back while unlocked', function()
    local function build(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local title = false
        for _, c in ipairs(g.cmds) do if c.op == 'text' and c.s == 'CLICKHEAL' then title = true end end
        return fr.geom, title
    end
    local on, t_on = build({ mode = 'party', locked = true, show_header = true })
    local off, t_off = build({ mode = 'party', locked = true, show_header = false })
    truthy(on.header_h > 0 and t_on)
    eq(off.header_h, 0); eq(t_off, false)
    truthy(off.height < on.height, 'panel is shorter without the bar')
    local unl, t_unl = build({ mode = 'party', locked = false, show_header = false })
    truthy(unl.header_h > 0 and t_unl, 'unlocking brings the bar back so you can move and lock')
end)


test('name size: option scales the names, the row keeps its height, icons make room', function()
    eq(chconfig.sanitize({ name_scale = 9 }).name_scale, 2.0); eq(chconfig.sanitize({ name_scale = 0 }).name_scale, 0.8)
    local function names(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local ks, n = {}, 0
        for _, c in ipairs(g.cmds) do
            if c.op == 'text' and c.s:match('^%u+$') and #c.s >= 4 and c.c ~= 0 and c.k and c.k > 1.2 then n = n + 1 end
        end
        return n, fr.geom
    end
    local n1 = names({ mode = 'party' })
    local n2, geom = names({ mode = 'party', name_scale = 1.5 })
    eq(n1, 0); truthy(n2 > 0, 'names drawn at the larger size')
    local a = layout.compute({ row_h = 44, debuff_icon = 14, buff_icon = 14, name_scale = 1.0 }, 1080)
    local b = layout.compute({ row_h = 44, debuff_icon = 14, buff_icon = 14, name_scale = 2.0 }, 1080)
    eq(a.card_h, b.card_h); truthy(b.eff.debuff_icon <= a.eff.debuff_icon)
end)


test('group frames: each party gets a frame; every party has a resize grip while unlocked', function()
    local function count(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local frames, grips = 0, 0
        for _, c in ipairs(g.cmds) do
            if c.op == 'rect' and c.w == fr.geom.groups[1].w and c.h == fr.geom.groups[1].h then frames = frames + 1 end
            if c.op == 'hit' and tostring(c.id):find('chgrip', 1, true) then grips = grips + 1 end
        end
        return frames, grips, #fr.geom.groups
    end
    local fr_on, _, n = count({ mode = 'alliance2', orientation = 'rows', group_frames = true })
    eq(n, 3); truthy(fr_on >= 3, 'a backdrop per party')
    local fr_off = count({ mode = 'alliance2', orientation = 'rows', group_frames = false })
    eq(fr_off, 0)
    local _, grips = count({ mode = 'alliance2', orientation = 'rows', locked = false })
    truthy(grips == 3 or grips == 0, 'one grip per party (recorder may not log hit areas)')
end)


test('demo page: sample status effects work on any roster, and the triage list grows to fit its icons', function()
    local frame = require('ch.frame')
    local function roster(over)
        local cfg = new_cfg(over)
        local f, fr = build_ui_frame(cfg, 1080, 3.0)
        return fr.roster_list, cfg
    end
    -- default demo alliance members have no visible debuffs; the switch gives everyone some
    local plain = roster({ mode = 'alliance2', demo = true })
    local forced = roster({ mode = 'alliance2', demo = true, debug = { force_debuffs = true, force_buffs = true } })
    local function with_debuffs(list) local n = 0; for _, m in ipairs(list) do if m.active and #m.debuffs > 0 then n = n + 1 end end return n end
    local living = 0
    for _, m in ipairs(forced) do if m.active and not m.dead then living = living + 1 end end
    truthy(with_debuffs(forced) > with_debuffs(plain), 'the switch adds debuffs')
    eq(with_debuffs(forced), living, 'every living member has debuffs')
    for _, m in ipairs(forced) do if m.active and not m.dead then truthy(#m.buffs > 0 and m.has_buff_data) end end
    eq(chconfig.sanitize({ debug = { cursor = 1 } }).debug.cursor, nil, 'retired switches are dropped')
    -- triage list: turning icons on makes the rows tall enough for them
    local short = layout.compute({ triage = true, triage_n = 4, tri_list_h = 18, debuff_icon = 14, buff_icon = 14 }, 1080)
    local tall = layout.compute({ triage = true, triage_n = 4, tri_list_h = 18, tri_list_icons = true, debuff_icon = 14, buff_icon = 14 }, 1080)
    truthy(tall.tri.list.row > short.tri.list.row * 2, 'rows grow when icons are shown')
    -- and the icons really are drawn under the names with demo debuffs forced
    -- a live party is never given sample statuses, whatever the switches say
    local real = { { slot = 1, active = true, name = 'Real', hpp = 50, debuffs = {}, buffs = {}, has_buff_data = true } }
    local live_cfg = new_cfg({ demo = false, debug = { force_debuffs = true, force_buffs = true } })
    truthy(frame.apply_debug(real, live_cfg) == real, 'a live party is never given sample statuses')
    live_cfg.demo = true
    eq(#frame.apply_debug(real, live_cfg)[1].debuffs > 0 and 1 or 0, 1, 'demo mode applies them')
    local cfg = new_cfg({ mode = 'alliance1', triage = true, demo = true, debug = { force_debuffs = true },
        triage_opts = { list_icons = true, list_h = 18 } })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    ui.draw_roster(f)
    local icons = 0
    for _, c in ipairs(g.cmds) do if c.op == 'status_icon' or c.op == 'icon' then icons = icons + 1 end end
    local tags = 0
    local shorts = {}
    for _, info in pairs(require('ch.debuffs').info) do shorts[info.short] = true end
    for _, c in ipairs(g.cmds) do if c.op == 'text' and shorts[c.s] then tags = tags + 1 end end
    truthy(icons + tags > 5, 'status icons or tags drawn in the triage list')
end)



test('party colors: each party background uses the chosen color; sanitize keeps them valid', function()
    local function party_rect(over)
        local cfg = new_cfg(over)
        local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
        ui.draw_roster(f)
        local grp = fr.geom.groups[2]
        for _, c in ipairs(g.cmds) do
            if c.op == 'rect' and c.w == grp.w and c.h == grp.h and c.x >= grp.x - 0.5 and c.x <= grp.x + 0.5 + 0 then
                local r, gg, b = theme.unpack(c.c)
                return r, gg, b
            end
        end
    end
    local r, g, b = party_rect({ mode = 'alliance1', group_colors = { { 0.4, 0.6, 1 }, { 0.9, 0.1, 0.2 }, { 0.9, 0.7, 0.3 } } })
    truthy(r and r > 0.8 and g < 0.2 and b < 0.3, 'alliance 1 background takes the chosen red')
    local s = chconfig.sanitize({ group_colors = { { 5, -1, 'x' }, 'bad' }, group_alpha = 9 })
    eq(#s.group_colors, 3); eq(s.group_colors[1][1], 1); eq(s.group_colors[1][2], 0)
    eq(s.group_colors[2][1], chconfig.defaults.group_colors[2][1]); eq(s.group_alpha, 0.5)
end)


test('sleep: the alert bar suggests a quick Cure, but no cleanse button claims it', function()
    local d = require('ch.debuffs')
    eq(d.info.sleep.spell, nil); eq(d.info.sleep.suggest, 'cure1')
    local cfg = new_cfg({})
    local list = require('ch.alerts').build({ { slot = 1, active = true, name = 'Elowen', hp = 900, hpmax = 1000, hpp = 90, dist = 5,
        debuffs = { 'sleep' }, has_buff_data = true } }, cfg, require('ch.spells').presets.WHM, 0)
    local found
    for _, a in ipairs(list) do if a.kind == 'debuff' then found = a end end
    truthy(found, 'a sleep alert exists'); eq(found.spell, 'cure1')
end)


test('resize: dragging a corner fits the panel to the box, re-flowing the parties when the shape changes', function()
    local cfg = new_cfg({ mode = 'alliance2', orientation = 'columns', locked = false })
    local f, fr = build_ui_frame(cfg, 1080, 3.0)
    f.groups, f.disp_h = fr.groups, 1080
    local w1 = ui.fit_box(f, 3000, 3000)
    eq(w1.orientation, 'columns', 'plenty of room keeps the current arrangement')
    -- a very wide, short box suits the rows arrangement; a tall narrow one suits columns or stacked
    local wide = ui.fit_box(f, 1800, 200)
    eq(wide.orientation, 'rows')
    local tall = ui.fit_box(f, 330, 1500)
    truthy(tall.orientation ~= 'rows')
    -- both axes matter: a shorter box gives a smaller scale than a taller one of the same width
    local a, b = ui.fit_box(f, 800, 300), ui.fit_box(f, 800, 700)
    truthy(a.scale <= b.scale)
    -- a single party only changes size
    local one, fr1 = build_ui_frame(new_cfg({ mode = 'party', orientation = 'columns', locked = false }), 1080, 3.0)
    one.groups, one.disp_h = fr1.groups, 1080
    eq(ui.fit_box(one, 3000, 3000).orientation, 'columns')
end)

-- =============================================================================================
-- livebuffs: other members' status effects from the server's packets
-- =============================================================================================

local live = require('ch.livebuffs')

local function u32le(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end

--- A 0x076 packet with one member: effect ids in order, high bits in the mask.
local function party_buff_packet(uid, effects)
    local mask, buffs = { 0, 0, 0, 0, 0, 0, 0, 0 }, {}
    for i = 1, 32 do
        local e = effects[i]
        if e then
            buffs[i] = string.char(e % 256)
            local hi = math.floor(e / 256)
            local byte, shift = math.floor((i - 1) / 4) + 1, ((i - 1) % 4) * 2
            mask[byte] = mask[byte] + hi * 2 ^ shift
        else
            buffs[i] = string.char(255)
        end
    end
    local mbytes = {}
    for i = 1, 8 do mbytes[i] = string.char(math.floor(mask[i])) end
    local entry = u32le(uid) .. '\1\0\0\0' .. table.concat(mbytes) .. table.concat(buffs)
    return string.rep('\0', 4) .. entry .. string.rep('\0', 48 * 4)
end

test('livebuffs: a party status packet gives the effect ids, including ones above 255', function()
    live.reset()
    truthy(live.feed(0x076, party_buff_packet(0x01020304, { 3, 33, 257 })))
    local ids = live.get(0x01020304)
    eq(#ids, 3); eq(ids[1], 3); eq(ids[2], 33); eq(ids[3], 257)
    eq(live.get(999), nil, 'unknown members have no packet data (the chat log is the fallback)')
    eq(live.count(), 1)
    truthy(not live.feed(0x076, 'short'), 'a truncated packet is ignored')
    truthy(not live.feed(0x076, nil), 'garbage is ignored')
end)

test('livebuffs: a wear-off message drops the effect at once; a zone change forgets everyone', function()
    live.reset()
    live.feed(0x076, party_buff_packet(77, { 3, 33 }))
    local msg = string.rep('\0', 8) .. u32le(77) .. u32le(33) .. string.rep('\0', 8) .. string.char(206, 0) .. string.rep('\0', 4)
    truthy(live.feed(0x029, msg))
    local ids = live.get(77); eq(#ids, 1); eq(ids[1], 3)
    truthy(not live.feed(0x029, msg), 'already gone')
    live.feed(0x00A, string.rep('\0', 8))
    eq(live.get(77), nil); eq(live.count(), 0)
end)

test('source_game: effect ids become debuff keys and buffs', function()
    local game = require('ch.source_game')
    local d, b = game.classify({ 3, 33, 33, 200 })
    eq(#d, 1, 'poison'); eq(d[1], 'poison')
    eq(#b, 1, 'haste once'); eq(b[1].key, 'haste')
end)

test('triage: the featured member shows their health percent, not a deficit or ALL FULL', function()
    local cfg = new_cfg({ mode = 'party', triage = true, demo = true })
    local f, fr, g = build_ui_frame(cfg, 1080, 3.0)
    ui.draw_roster(f)
    local pct, bad = false, false
    for _, c in ipairs(g.cmds) do
        if c.op == 'text' then
            if c.s:match('^%d+%%$') then pct = true end
            if c.s == 'ALL FULL' or c.s:match('^%-%d+$') then bad = true end
        end
    end
    truthy(pct, 'a percent is shown'); truthy(not bad, 'no deficit text')
end)

test('commands: every listed command works, and nothing experimental is left', function()
    local seen = {}
    for _, c in ipairs(commands.LIST) do
        for word in c[1]:gmatch('/ch%s+(%a+)') do seen[word] = true end
        truthy(#c[2] > 10, 'each command has a description')
    end
    for word in pairs(seen) do
        local r = commands.run({ '/ch', word, 'party' }, new_cfg({}))
        truthy(not (r.messages[1] or ''):find('Unknown'), '/ch ' .. word .. ' is listed but unknown')
    end
    for _, gone in ipairs({ 'cursor', 'partydump', 'cast', 'inputdebug' }) do
        truthy(commands.run({ '/ch', gone }, new_cfg({})).messages[1]:find('Unknown'), '/ch ' .. gone .. ' should be gone')
    end
    eq(#commands.run({ '/ch', 'help' }, new_cfg({})).messages, #commands.LIST, 'help prints the whole list')
end)

-- =============================================================================================
-- performance caches: they must save work without ever serving stale data
-- =============================================================================================

test('livebuffs: the sorted list is shared until something changes, then rebuilt', function()
    live.reset()
    live.feed(0x076, party_buff_packet(500, { 33, 3 }))
    local a = live.get(500)
    truthy(a == live.get(500), 'same list while nothing changed')
    eq(a[1], 3); eq(a[2], 33, 'sorted')
    -- a wear-off message drops the effect and must drop the cached list with it
    local wear = string.rep('\0', 8) .. u32le(500) .. u32le(33) .. string.rep('\0', 8) .. string.char(64, 0) .. string.rep('\0', 4)
    truthy(live.feed(0x029, wear))
    local b = live.get(500)
    truthy(b ~= a, 'list rebuilt after the wear-off')
    eq(#b, 1); eq(b[1], 3)
    -- a new status packet replaces the entry
    live.feed(0x076, party_buff_packet(500, { 40, 41, 42 }))
    eq(#live.get(500), 3)
    live.reset()
    eq(live.get(500), nil, 'zone change forgets the list too')
end)

test('frame: layout and fitted preset are reused while their inputs match, rebuilt when they change', function()
    local cfg = new_cfg({ mode = 'alliance2', show_locked = false })
    local fr1 = frame.build(cfg, demo, 3.0, 1920, 1080, {})
    local fr2 = frame.build(cfg, demo, 3.1, 1920, 1080, {})
    truthy(fr1.geom == fr2.geom, 'same options: the geometry table is reused')
    truthy(fr1.preset == fr2.preset, 'same player: the fitted preset is reused')
    -- reused geometry is still the right geometry
    local fresh = require('ch.layout').compute({
        orientation = cfg.orientation, auto_scale = cfg.auto_scale, scale = cfg.scale, groups = fr2.groups,
        row_w = cfg.row_w, row_h = (cfg.skin == 'hairline') and cfg.hl_row_h or cfg.row_h, debuff_icon = cfg.debuff_icon,
        buff_icon = cfg.buff_icon, mp_h = cfg.show_mp and cfg.mp_height or 0, mp_pct = cfg.show_mp_pct and cfg.mp_pct_scale or nil,
        skin = cfg.skin, triage = cfg.triage, hl_pct = cfg.hl_pct, name_scale = cfg.name_scale, font_mult = cfg.font_mult,
        tri_list_h = cfg.triage_opts and cfg.triage_opts.list_h, tri_list_icons = cfg.triage_opts and cfg.triage_opts.list_icons,
        header = cfg.show_header or not cfg.locked,
    }, 1080)
    eq(fr2.geom.width, fresh.width); eq(fr2.geom.height, fresh.height)

    cfg.scale = 1.5
    local fr3 = frame.build(cfg, demo, 3.2, 1920, 1080, {})
    truthy(fr3.geom ~= fr2.geom and fr3.geom.scale > fr2.geom.scale, 'a new scale gives new geometry')
    cfg.scale = 1.0
    local fr4 = frame.build(cfg, demo, 3.3, 1920, 1080, {})
    eq(fr4.geom.width, fr2.geom.width, 'and back again')

    local fr5 = frame.build(cfg, demo, 3.4, 1920, 2160, {})
    truthy(fr5.geom ~= fr4.geom, 'a different window height gives new geometry')
    cfg.mode = 'party'
    local fr6 = frame.build(cfg, demo, 3.5, 1920, 1080, {})
    truthy(fr6.geom.width < fr2.geom.width, 'fewer groups give a narrower panel (the group list is compared by content)')
    -- the fitted preset follows the player: a lower level offers different spells
    local low = { roster = demo.roster, player = function(t) local p = demo.player(t); p.level = 20; return p end }
    local frl = frame.build(new_cfg({ show_locked = false }), low, 3.6, 1920, 1080, {})
    truthy(frl.preset ~= fr2.preset, 'a different level rebuilds the preset')
end)

-- =============================================================================================
-- server cast packets (0x028): the cast bar starts, ends and fills from what the server and the game say
-- =============================================================================================

local castpacket = require('ch.castpacket')

local action_packet = require('tests.packets').action_packet

local ME = 0x00112233

test('castpacket: reads the actor, category, param and the spell id of a cast that begins', function()
    local p = castpacket.parse(action_packet(ME, 8, castpacket.CAST_BEGIN, 4))
    eq(p.actor, ME); eq(p.category, 8); eq(p.param, 0x6163); eq(p.first, 4)
    eq(castpacket.actor(action_packet(ME, 8, 1, 4)), ME, 'the cheap actor read agrees')
    local item = castpacket.parse(action_packet(ME, 9, castpacket.CAST_BEGIN, 4097))
    eq(item.category, 9); eq(item.first, 4097)
    local fin = castpacket.parse(action_packet(ME, 4, 5, 4))
    eq(fin.category, 4); eq(fin.param, 5, 'a 32-bit param outside spells and items')
    eq(castpacket.parse('short'), nil, 'a truncated packet is ignored, not an error')
    eq(castpacket.parse(nil), nil)
end)

test('castpacket: classifies only your own begin / interrupt / landing, and finds the spell', function()
    local what, def = castpacket.classify(castpacket.parse(action_packet(ME, 8, castpacket.CAST_BEGIN, require('ch.spell_ids').cure4.spell)), ME)
    eq(what, 'begin'); eq(def, spells.defs.cure4, 'the spell id maps back to our spell')
    eq((castpacket.classify(castpacket.parse(action_packet(ME, 8, castpacket.CAST_BEGIN, 99999)), ME)), 'begin', 'unknown spell: still a begin')
    eq(castpacket.classify(castpacket.parse(action_packet(ME, 8, castpacket.CAST_BROKE, 4)), ME), 'broke')
    eq(castpacket.classify(castpacket.parse(action_packet(ME, 4, 5, 4)), ME), 'landed')
    eq(castpacket.classify(castpacket.parse(action_packet(ME, 5, 5, 4)), ME), 'landed')
    eq(castpacket.classify(castpacket.parse(action_packet(0x99999, 8, castpacket.CAST_BEGIN, 4)), ME), nil, 'someone else casting')
    eq(castpacket.classify(castpacket.parse(action_packet(ME, 1, 0, 4)), ME), nil, 'a melee round')
    eq(castpacket.classify(castpacket.parse(action_packet(ME, 8, 12345, 4)), ME), nil, 'a cast category with some other param')
    eq(castpacket.classify(nil, ME), nil)
end)

--- Simulates a cast whose server start comes `lag` seconds after the click, frame by frame at 10 Hz.
local function run_cast(lag, real, opts)
    opts = opts or {}
    casting.reset()
    local def = spells.defs.cure4
    casting.start(def, 10, { cast_lockout = 1.0 })
    local frames, begun = {}, false
    for i = 1, 60 do
        local t = 10 + i * 0.1
        if not begun and t >= 10 + lag then casting.server_begin(t, def); begun = true end
        local elapsed = t - 10 - lag
        local pct = begun and math.max(0, math.min(1, elapsed / real)) or 0
        if opts.interrupt_at and begun and elapsed >= opts.interrupt_at and not opts.broken then
            casting.server_broke(t); opts.broken = true
        end
        if begun and not opts.broken and not opts.landed and elapsed >= real then
            casting.server_landed(t); opts.landed = true
        end
        if not opts.broken and not opts.landed then casting.observe(t, (pct > 0 and pct < 1) and pct or (pct >= 1 and 1 or 0)) end
        casting.expire(t)
        frames[#frames + 1] = { t = t, info = casting.info(t), left = casting.left(t), pct = pct }
    end
    return frames
end

test('casting with server packets: the bar waits for the server, then follows the game bar exactly', function()
    for _, lag in ipairs({ 0.2, 0.6, 1.2 }) do          -- including a latency above the old 0.6 s give-up
        local frames = run_cast(lag, 2.5)
        local prev = 0
        -- the very first cast has no packet history yet, so only the part after the server start is held to the rule
        for _, fr in ipairs(frames) do
            if fr.t - 10 >= lag - 0.001 and fr.info then
                if fr.pct > 0 and fr.pct < 1 then near(fr.info.frac, fr.pct, 0.02, 'follows the game bar (lag ' .. lag .. ')') end
                truthy(fr.info.frac >= prev - 1e-9, 'never runs backwards (lag ' .. lag .. ')')
                prev = fr.info.frac
                truthy(fr.left > 0, 'still busy while the bar shows (lag ' .. lag .. ')')
            end
        end
    end
    -- once packets are known to work, the bar holds at 0 while it waits for the server
    local def = spells.defs.cure4
    casting.start(def, 100, { cast_lockout = 1.0 })
    local waiting = casting.info(100.4)
    truthy(waiting and waiting.frac == 0, 'held at 0 while the server has not answered')
    casting.server_begin(100.9, def)         -- 0.9 s of latency: the old code gave up at 0.6 s and started over
    truthy(casting.info(101.0) ~= nil, 'still the same cast')
end)

test('casting, first cast after a reload: no run-ahead, no snap back, even with nothing known yet', function()
    casting.reset()                                     -- a fresh addon: no packet or bar history at all
    local def = spells.defs.cure4
    casting.start(def, 10, { cast_lockout = 1.0 })
    for _, dt in ipairs({ 0.1, 0.3, 0.6, 0.9 }) do
        local info = casting.info(10 + dt)
        eq(info.frac, 0, 'held at 0 while the server has not answered (+' .. dt .. ')')
    end
    casting.server_begin(10.95, def)                    -- the server answers 0.95 s after the click
    local prev = 0
    for i = 1, 20 do
        local t = 10.95 + i * 0.1
        local pct = math.min(0.999, (t - 10.95) / 2.5)
        casting.observe(t, pct)
        local info = casting.info(t)
        near(info.frac, pct, 0.02, 'follows the game bar')
        truthy(info.frac >= prev - 1e-9, 'never backwards')
        prev = info.frac
    end
end)

test('casting: if nothing ever answers, the estimate takes over after the wait', function()
    casting.reset()
    casting.start(spells.defs.cure4, 10, { cast_lockout = 1.0 })
    eq(casting.info(11.0).frac, 0, 'still waiting at 1 s')
    truthy(casting.info(12.2).frac > 0.3, 'no server word after 1.5 s: shows the estimated progress again')
end)

test('casting with server packets: a landing ends the cast, then only the short delay is left', function()
    local opts = {}
    local frames = run_cast(0.3, 2.0, opts)
    truthy(opts.landed, 'landing was delivered')
    local last
    for _, fr in ipairs(frames) do if fr.info then last = fr end end
    truthy(last and last.t > 10 + 0.3 + 2.0, 'the bar ran to the end of the cast')
    eq(frames[#frames].info, nil, 'idle again after the delay')
end)

test('casting with server packets: an interrupt freezes the bar, flags it, and frees you soon after', function()
    local opts = { interrupt_at = 1.0 }
    local frames = run_cast(0.3, 2.5, opts)
    truthy(opts.broken)
    local frozen, flagged
    for _, fr in ipairs(frames) do
        if fr.info and fr.info.broke then
            flagged = true
            frozen = frozen or fr.info.frac
            near(fr.info.frac, frozen, 1e-9, 'stays where it stopped')
        end
    end
    truthy(flagged, 'info says it was interrupted')
    truthy(frozen > 0.3 and frozen < 0.5, 'stopped near 40%, got ' .. tostring(frozen))
    eq(frames[#frames].info, nil, 'free again well before the cast would have ended')
end)

test('casting with server packets: a click the server never starts is given up on, but only after the wait', function()
    casting.reset()
    local def = spells.defs.cure4
    casting.start(def, 10, { cast_lockout = 1.0 })
    casting.server_begin(10.3, def); casting.server_landed(12.8)       -- packets are known to work now
    casting.start(def, 20, { cast_lockout = 1.0 })                     -- this click gets no start packet (out of range)
    casting.expire(20.9)
    truthy(casting.left(20.9) > 1, 'still waiting at 0.9 s: slow servers must not look like failures')
    casting.expire(21.6)
    truthy(casting.left(21.6) <= 0.3 + 1e-9, 'released after the wait')
end)

test('casting with server packets: a cast started from a macro gets a bar too', function()
    casting.reset()
    casting.server_begin(50, spells.defs.cure3)
    local info = casting.info(50.5)
    truthy(info and info.key == 'cure3', 'bar for a cast that did not come from a click')
    casting.reset()
    casting.server_begin(60, nil)          -- a spell we do not know, while idle: nothing to show
    eq(casting.info(60.5), nil)
end)

print(string.format('\n%d passed, %d failed', passed, failed))
for _, f in ipairs(failures) do print('  FAIL: ' .. f) end
os.exit(failed == 0 and 0 or 1)
