--[[
    ClickHeal - ui.lua
    Draws the party/alliance frames, ability tiles and the alert bar.

    Look: neutral and flat. Names are bright, everything secondary (job, distance) is dim, HP is a
    slim bar, abilities are dark tiles with a thin underline for the spell type. Color is reserved
    for things that need attention (low HP, debuffs, out of range, alerts) and one cool accent for
    hover and priority cures.

    This module never touches ImGui directly. It draws through a small "gfx" interface:
        gfx.rect_filled(x, y, w, h, color, rounding)
        gfx.text(x, y, color, str)
        gfx.text_size(str) -> w, h
        gfx.tooltip(lines, scale)
    and reads mouse state from `f.input`. Two backends implement gfx: gfx_imgui.lua (in game)
    and gfx_record.lua (tests and the PNG previews), so the exact same drawing code is exercised
    by the offline tests.

    Frame table `f` (built by the caller every frame):
        gfx, geom, cfg, pal, roster (slot -> member), player, preset, now,
        ox, oy            screen position of the panel's top-left corner
        input             { mx, my, hovered, interactive, clicked = {left,right,middle}, mods }
        events            (out) list of { type = 'cast'|'dismiss', ... }
        hitboxes          (optional, out) list of clickable rectangles, used by tests
]]--

local theme      = require('ch.theme')
local jobs       = require('ch.jobs')
local debuffs    = require('ch.debuffs')
local spells     = require('ch.spells')
local spellstate = require('ch.spellstate')
local buffs      = require('ch.buffs')
local bindings   = require('ch.bindings')
local layout     = require('ch.layout')
local triage     = require('ch.triage')

local ui = {}

-- Transient UI state (not saved): the spell armed on the bar, waiting for a member click.
ui.state = { armed = nil, flyout = nil, row_hot = false, trail = {}, tri_slot = nil }
function ui.reset_state() ui.state.armed = nil; ui.state.flyout = nil; ui.state.row_hot = false; ui.state.trail = {}; ui.state.tri_slot = nil end
local floor, max, min = math.floor, math.max, math.min

-- ------------------------------------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------------------------------------

local function A(c, a)
    if a >= 0.999 then return c end
    return theme.alpha(c, a)
end

local function pulse(f)
    -- 0..1, quantized so the color cache in the ImGui backend stays small.
    return floor((0.5 + 0.5 * math.sin(f.now * 5)) * 6) / 6
end

local function outline(g, x, y, w, h, t, c)
    g.rect_filled(x, y, w, t, c, 0)
    g.rect_filled(x, y + h - t, w, t, c, 0)
    g.rect_filled(x, y + t, t, h - 2 * t, c, 0)
    g.rect_filled(x + w - t, y + t, t, h - 2 * t, c, 0)
end

--- Truncates `str` with ".." so it fits in maxw pixels.
local function fit(g, str, maxw)
    if maxw <= 0 then return '', 0 end
    local w = g.text_size(str)
    if w <= maxw then return str, w end
    local s2 = str
    while #s2 > 1 do
        s2 = s2:sub(1, #s2 - 1)
        local w2 = g.text_size(s2 .. '..')
        if w2 <= maxw then return s2 .. '..', w2 end
    end
    return '', 0
end

local function hovering(f, x, y, w, h)
    local i = f.input
    if not i or not i.interactive or not i.hovered then return false end
    return i.mx >= x and i.mx < x + w and i.my >= y and i.my < y + h
end

local function note_hitbox(f, kind, x, y, w, h, extra)
    if not f.hitboxes then return end
    local hb = { kind = kind, x = x, y = y, w = w, h = h }
    for k, v in pairs(extra or {}) do hb[k] = v end
    f.hitboxes[#f.hitboxes + 1] = hb
end

local function click_button(f)
    local c = f.input and f.input.clicked
    if not c then return nil end
    if c.left then return 'left' end
    if c.right then return 'right' end
    if c.middle then return 'middle' end
    return nil
end

--- A small rounded label. Returns its width.
local function chip(f, x, y, h, text, fg, bg, dim)
    local g, s = f.gfx, f.geom.scale
    local tw, th = g.text_size(text)
    local w = tw + floor(7 * s)
    g.rect_filled(x, y, w, h, A(bg, dim), floor(3 * s))
    g.text(x + floor(3.5 * s), y + floor((h - th) / 2), A(fg, dim), text)
    return w
end

local function dist_text(m)
    if not m.dist then return '--' end
    return string.format('%dy', floor(m.dist + 0.5))
end

local function sorted_debuffs(m)
    local list = {}
    if m.has_buff_data and m.debuffs then
        for _, k in ipairs(m.debuffs) do
            if debuffs.info[k] then list[#list + 1] = k end
        end
    end
    table.sort(list, debuffs.compare)
    return list
end

local function sev_color(pal, sev)
    if sev == 1 then return pal.bad end
    if sev == 2 then return pal.warn end
    return pal.text_dim
end

-- ------------------------------------------------------------------------------------------
-- ability tile
-- ------------------------------------------------------------------------------------------

--- Countdown text: 4.2 / 42 / 1:05 / 12m / 2h.
function ui.fmt_recast(sec)
    if sec < 10 then return string.format('%.1f', sec) end
    local c = math.ceil(sec)
    if c < 60 then return tostring(c) end
    if c < 600 then return string.format('%d:%02d', floor(c / 60), c % 60) end
    if c < 3600 then return string.format('%dm', math.ceil(c / 60)) end
    return string.format('%dh', math.ceil(c / 3600))
end

--- A tile that is on cooldown: grayed out, the time left in the middle (with a shadow so it reads
-- on any background) and a thin bar along the bottom that fills as the cooldown runs out.
local function paint_recast(f, x, y, size, def, left, round)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    g.rect_filled(x, y, size, size, theme.pack(0.13, 0.13, 0.14, 0.86), round)
    local rt = f.player and f.player.recast_total
    local total = math.max((rt and rt[def.key]) or def.recast or left, left, 0.1)
    local bh = max(2, floor(3 * s))
    local fill = floor((size - floor(8 * s)) * (1 - min(1, left / total)))
    g.rect_filled(x + floor(4 * s), y + size - bh - floor(3 * s), size - floor(8 * s), bh, theme.pack(1, 1, 1, 0.12), 0)
    if fill > 0 then
        g.rect_filled(x + floor(4 * s), y + size - bh - floor(3 * s), fill, bh, A(pal.accent, 0.95), 0)
    end
    local label = ui.fmt_recast(left)
    local tw, th = g.text_size(label)
    local tx, ty = x + floor((size - tw) / 2), y + floor((size - th) / 2) - floor(2 * s)
    g.text(tx + 1, ty + 1, theme.pack(0, 0, 0, 0.9), label)
    g.text(tx, ty, pal.text, label)
end

local SPELL_DEBUFF_ICON
--- The game status icon id that stands for a spell: the buff it applies, or the debuff it removes.
local function spell_status_icon(def)
    if def.buff and buffs.id_of[def.buff] then return buffs.id_of[def.buff] end
    if not SPELL_DEBUFF_ICON then
        local count, first = {}, {}
        for key, info in pairs(debuffs.info) do
            if info.spell and debuffs.id_of[key] then
                count[info.spell] = (count[info.spell] or 0) + 1
                first[info.spell] = debuffs.id_of[key]
            end
        end
        SPELL_DEBUFF_ICON = {}
        for spell, n in pairs(count) do if n == 1 then SPELL_DEBUFF_ICON[spell] = first[spell] end end   -- Erase covers several, so it keeps text
    end
    return SPELL_DEBUFF_ICON[def.key]
end

--- Draws the spell's icon inside a button when the option is on and one exists. True when drawn.
local function draw_spell_icon(f, x, y, size, def)
    if not f.cfg.flyout_icons then return false end
    local g, s = f.gfx, f.geom.scale
    local isz = size - floor(10 * s)
    local ix, iy = x + floor((size - isz) / 2), y + floor(3 * s)
    if g.spell_icon and g.spell_icon(ix, iy, isz, def.key) then return true end
    local sid = spell_status_icon(def)
    if sid and g.status_icon and g.status_icon(ix, iy, isz, sid) then return true end
    return false
end

local function draw_button(f, x, y, size, entry, member)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local def = entry.def
    local state, detail = spellstate.evaluate(def, member, f.player, f.cfg)
    local ready = (state == 'ready')
    local busy = (state == 'busy')      -- mid-cast: still clickable, the click is queued
    local hot = hovering(f, x, y, size, size)
    local round = floor(3 * s)

    -- Tile background: flat dark; the debuff-cure / raise priority tile leans toward the accent.
    local bg = hot and pal.btn_hot or pal.btn
    if entry.priority and ready then bg = theme.mix(bg, pal.accent, 0.20) end
    if not ready and state ~= 'recast' and not busy then bg = A(bg, 0.65) end
    g.rect_filled(x, y, size, size, bg, round)

    -- Thin spell-type underline.
    local lh = max(2, floor(2 * s))
    local kc = pal.kind[def.kind] or pal.accent
    g.rect_filled(x + floor(4 * s), y + size - lh - floor(3 * s), size - floor(8 * s), lh,
        A(kc, (ready or busy) and 0.85 or 0.30), 0)

    local with_icon = draw_spell_icon(f, x, y, size, def)
    if state == 'recast' then
        paint_recast(f, x, y, size, def, detail, round)
    else
        if not ready and state ~= 'nomp' and not busy then
            g.rect_filled(x, y, size, size, theme.pack(0, 0, 0, 0.35), round)
        end
        if not with_icon then
            local label, col = def.short, pal.text
            if busy then col = A(pal.text, 0.72)
            elseif not ready then col = (state == 'nomp') and pal.mp or A(pal.text_dim, 0.8) end
            local tw, th = g.text_size(label)
            g.text(x + floor((size - tw) / 2), y + floor((size - th) / 2) - floor(2 * s), col, label)
        end
    end

    -- Priority glow (pulsing accent outline) and hover outline.
    if entry.priority and ready then
        outline(g, x, y, size, size, max(1, floor(2 * s)), theme.alpha(pal.accent, 0.40 + 0.60 * pulse(f)))
    end

    -- The click waiting for the cast to finish.
    if f.player and f.player.queued == def.key then
        outline(g, x, y, size, size, max(1, floor(2 * s)), A(pal.accent, 0.9))
    end

    note_hitbox(f, 'spell', x, y, size, size, { slot = member.slot, key = def.key })

    if hot then
        outline(g, x, y, size, size, max(1, floor(1 * s)), A(pal.accent, 0.9))

        f.tooltip = {
            string.format('%s   (%d MP)', def.name, def.mp or 0),
            def.selfonly and 'Target: you (self only)' or ('Target: ' .. member.name),
            'Status: ' .. spellstate.describe(state, detail),
            spells.binding_lines(def),
        }

        local btn = click_button(f)
        if btn then
            local mods = f.input.mods or {}
            local rkey = spells.resolve(def, btn, mods) or def.key
            local rdef = spells.defs[rkey] or def
            local rstate, rdetail = spellstate.evaluate(rdef, member, f.player, f.cfg)
            f.events[#f.events + 1] = {
                type = 'cast', via = 'card', slot = member.slot, spell = rkey,
                button = btn, mods = mods, state = rstate, detail = rdetail,
            }
        end
    end
end

-- ------------------------------------------------------------------------------------------
-- member cards
-- ------------------------------------------------------------------------------------------

local function member_flags(f, m)
    local out_of_range = m.dist ~= nil and m.dist > f.cfg.max_range
    local near_limit = m.dist ~= nil and m.dist > f.cfg.warn_range and not out_of_range
    local dim = 1.0
    if m.zone_diff then dim = 0.40 elseif out_of_range then dim = 0.58 end
    return out_of_range, near_limit, dim
end

local function card_frame(f, m, r, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local hot = hovering(f, r.x, r.y, r.w, r.h)
    local bg
    if m.dead then bg = theme.mix(pal.card, pal.dead, 0.6)
    elseif hot then bg = pal.card_hot
    else bg = pal.card end
    g.rect_filled(r.x, r.y, r.w, r.h, theme.alpha(bg, f.cfg.opacity), floor(4 * s))

    -- Critical HP: a pulsing red frame is the one loud thing on a card.
    local crit = (not m.dead) and (not m.zone_diff) and m.hpp and m.hpp <= f.cfg.hp_crit
    if crit then
        local p = f.cfg.alerts.pulse and pulse(f) or 1
        outline(g, r.x, r.y, r.w, r.h, max(1, floor(2 * s)), theme.alpha(pal.bad, 0.30 + 0.70 * p))
    end
end

local function hp_text(m)
    if m.dead then return 'KO' end
    return string.format('%d%%', floor(m.hpp or 0))
end

--- Percent text is quiet when healthy and only takes a color when it matters.
local function hp_text_color(f, m)
    local pal = f.pal
    if m.dead then return pal.bad end
    local p = m.hpp or 0
    if p <= f.cfg.hp_crit then return pal.bad end
    if p < 60 then return pal.warn end
    return pal.text_dim
end

local function name_color(f, m, dim)
    local pal = f.pal
    if m.dead then return A(pal.text_dim, dim) end
    if m.is_you then return A(pal.accent, dim) end
    return A(pal.text, dim)
end

--- A horizontal strip of debuff icons (the game's own icon when it can be loaded, else a small text
-- tag), most severe first, "+N" when they do not fit. Hovering lists every debuff with its cure.
-- Returns the number of debuffs drawn.
local function draw_debuff_strip(f, m, x, y, w, h, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local list = sorted_debuffs(m)
    if #list == 0 or w < h then return 0 end
    local gap = max(1, floor(3 * s))
    local pad = floor(6 * s)
    local cx, shown = x, 0
    local more_w = g.text_size('+9') + pad
    for i, key in ipairs(list) do
        local info = debuffs.info[key]
        local icon_ok = false
        local iw = h
        local label = info.short
        local tw = g.text_size(label) + pad
        local need = (g.status_icon and debuffs.id_of[key]) and iw or tw
        local reserve = (i < #list) and (more_w + gap) or 0
        if cx + need + reserve > x + w then
            local extra = '+' .. (#list - i + 1)
            local ew = g.text_size(extra) + pad
            if cx + ew <= x + w then chip(f, cx, y, h, extra, pal.text, pal.btn_hot, dim) end
            break
        end
        if g.status_icon and debuffs.id_of[key] then
            icon_ok = g.status_icon(cx, y, iw, debuffs.id_of[key])
        end
        if icon_ok then
            -- A thin severity-colored underline so the worst ones stand out even as icons.
            if info.sev <= 2 then
                g.rect_filled(cx, y + h - max(1, floor(2 * s)), iw, max(1, floor(2 * s)), A(sev_color(pal, info.sev), dim), 0)
            end
            cx = cx + iw + gap
        else
            -- Dark backing with a colored edge and text: readable on any HP fill color.
            local col = (info.sev <= 2) and sev_color(pal, info.sev) or pal.text
            local w = tw
            g.rect_filled(cx, y, w, h, theme.pack(0.04, 0.05, 0.07, 0.88 * dim), floor(3 * s))
            outline(g, cx, y, w, h, max(1, floor(1 * s)), A(col, 0.85 * dim))
            local lw, lh = g.text_size(label)
            g.text(cx + floor((w - lw) / 2), y + floor((h - lh) / 2), A(col, dim), label)
            cx = cx + tw + gap
        end
        shown = shown + 1
    end
    if hovering(f, x, y, w, h) then
        local lines = {}
        for _, key in ipairs(list) do
            local info = debuffs.info[key]
            local rem = m.debuff_rem and m.debuff_rem[key]
            local cure = info.spell and spells.defs[info.spell] and spells.defs[info.spell].name or 'no cure'
            lines[#lines + 1] = string.format('%s%s   (%s)', info.label, rem and ('  ' .. buffs.fmt(rem)) or '', cure)
        end
        f.tooltip = lines
    end
    return shown
end

--- A horizontal strip of buff icons in display order (the game's icon, else a small text tag), with a
-- thin timer line along the bottom of each. Amber under 30s, pulsing under 10s. "+N" when they do
-- not fit. Hovering lists every buff with its time left. Returns the number drawn.
local function draw_buff_strip(f, m, list, x, y, w, h, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    if #list == 0 or w < h then return 0 end
    local gap = max(1, floor(3 * s))
    local pad = floor(6 * s)
    local cx, shown = x, 0
    local more_w = g.text_size('+9') + pad
    local th = max(1, floor(2 * s))
    for i, b in ipairs(list) do
        local label = b.info.short
        local tw = g.text_size(label) + pad
        local sid = buffs.id_of[b.key]
        local need = (g.status_icon and sid) and h or tw
        local reserve = (i < #list) and (more_w + gap) or 0
        if cx + need + reserve > x + w then
            local extra = '+' .. (#list - i + 1)
            if cx + g.text_size(extra) + pad <= x + w then chip(f, cx, y, h, extra, pal.text, pal.btn_hot, dim) end
            break
        end
        local urg = buffs.urgency(b.rem)
        local iw = need
        local icon_ok = g.status_icon and sid and g.status_icon(cx, y, h, sid) or false
        if not icon_ok then
            iw = tw
            g.rect_filled(cx, y, tw, h, theme.pack(0.04, 0.05, 0.07, 0.88 * dim), floor(3 * s))
            local lw, lh = g.text_size(label)
            g.text(cx + floor((tw - lw) / 2), y + floor((h - lh) / 2), A(pal.kind.buff or pal.accent, dim), label)
        end
        if b.rem and b.total and b.total > 0 then
            local lc, la = pal.kind.buff or pal.accent, 0.85
            if urg == 'soon' then lc = pal.warn
            elseif urg == 'urgent' then lc, la = pal.warn, 0.35 + 0.65 * ((f.cfg.alerts.pulse and pulse(f)) or 1) end
            local frac = max(0, min(1, b.rem / b.total))
            g.rect_filled(cx, y + h - th, max(1, floor(iw * frac)), th, A(lc, la * dim), 0)
        end
        cx = cx + iw + gap
        shown = shown + 1
    end
    if hovering(f, x, y, w, h) then
        local lines = {}
        for _, b in ipairs(list) do
            lines[#lines + 1] = b.rem and string.format('%s   %s left', b.info.label, buffs.fmt(b.rem)) or b.info.label
        end
        f.tooltip = lines
    end
    return shown
end

-- ------------------------------------------------------------------------------------------
-- Strip rows: the whole row is the click target (hover opens the flyout)
-- ------------------------------------------------------------------------------------------

--- Hover outline, tooltip, and the click -> cast event.
-- Armed spell (picked on the bar): left click casts it on this member, right click cancels.
-- Otherwise, if cell click bindings are on (or there is no bar), a click casts the bound spell.
local function cell_interact(f, m, r)
    note_hitbox(f, 'cell', r.x, r.y, r.w, r.h, { slot = m.slot })
    if not hovering(f, r.x, r.y, r.w, r.h) then return end
    local g, pal, s = f.gfx, f.pal, f.geom.scale

    if f.cfg.flyout then
        -- Hovering a row opens its spell flyout (drawn by draw_flyout in its own window).
        local keep = ui.state.flyout and ui.state.flyout.slot == m.slot and ui.state.flyout.fly or nil
        ui.state.flyout = { slot = m.slot, row = { x = r.x, y = r.y, w = r.w, h = r.h }, fly = keep }
        ui.state.row_hot = true
    else
        outline(g, r.x, r.y, r.w, r.h, max(1, floor(1.5 * s)), A(pal.accent, 0.9))
    end

    local head = string.format('%s   %s   %s', m.name, jobs.label(m.job, m.sub), dist_text(m))
    local btn = click_button(f)
    local armed = ui.state.armed and spells.defs[ui.state.armed] or nil

    if armed then
        local state, detail = spellstate.evaluate(armed, m, f.player, f.cfg)
        if not f.tooltip then
            f.tooltip = { head, string.format('Click: %s on %s', armed.name, m.name),
                'Status: ' .. spellstate.describe(state, detail), 'Right click: cancel' }
        end
        if btn == 'right' then
            ui.state.armed = nil
        elseif btn == 'left' then
            f.events[#f.events + 1] = {
                type = 'cast', via = 'bar', slot = m.slot, spell = armed.key, button = 'left',
                mods = f.input.mods or {}, state = state, detail = detail,
            }
            if not spells.sticky(armed) then ui.state.armed = nil end
        end
        return
    end

    local use_binds = f.cfg.cell_binds or (not f.geom.bar and not f.cfg.flyout)
    if not use_binds then
        if not f.tooltip and not f.cfg.flyout then f.tooltip = { head, 'Pick a spell on the bar, then click a member' } end
        return
    end

    local eff = bindings.effective(f.cfg, f.preset)
    local lines = { head }
    for _, l in ipairs(bindings.describe(eff, m, f.preset)) do lines[#lines + 1] = l end
    if f.cfg.buff_mode and not m.dead then lines[#lines + 1] = '(buff mode: click casts buffs)' end
    if not f.tooltip then f.tooltip = lines end

    if not btn then return end
    local mods = f.input.mods or {}
    local slot = bindings.slot_name(btn, mods)
    local value = slot and eff[slot] or nil
    local key, why = bindings.resolve(value, m, f.preset, btn)
    if not key then
        if why then f.events[#f.events + 1] = { type = 'note', text = '[ClickHeal] ' .. why } end
        return
    end
    local def = spells.defs[key]
    local state, detail = spellstate.evaluate(def, m, f.player, f.cfg)
    f.events[#f.events + 1] = {
        type = 'cast', via = 'cell', slot = m.slot, spell = key, button = btn, mods = mods,
        state = state, detail = detail,
    }
end

--- What actually fits in the row (see layout.effective); falls back to the settings for hand-built frames.
local function eff(f)
    local e = f.geom.eff
    if e then return e end
    local c = f.cfg
    return { debuff_icon = c.debuff_icon, buff_icon = c.buff_icon, mp_h = c.show_mp and c.mp_height or 0,
        mp_pct = (c.show_mp and c.show_mp_pct) and c.mp_pct_scale or nil, hl_pct = c.hl_pct }
end

--- Height of the debuff/buff icon band (px).
local function icon_band(f)
    local s, e = f.geom.scale, eff(f)
    return max(floor(e.debuff_icon * s), floor(e.buff_icon * s))
end

--- Debuff icons on the left and buff icons beside them (each takes the whole width when the other has
-- nothing to show), inside x = xl..xr, with the band's top edge at iy.
local function draw_icon_strip(f, m, xl, xr, iy, dim)
    if m.dead or m.zone_diff then return end
    local s = f.geom.scale
    local e = eff(f)
    local di, bi = floor(e.debuff_icon * s), floor(e.buff_icon * s)
    local sh = max(di, bi)
    local sw = xr - xl
    if sh <= 0 or sw < sh then return end
    local blist = f.cfg.show_buff_bar and buffs.list(m, f.cfg, f.preset) or {}
    local nd = #sorted_debuffs(m)
    local igap = floor(8 * s)
    local dw, bx, bw = sw, xl, sw
    if nd > 0 and #blist > 0 then
        dw = floor((sw - igap) * 0.5)
        bx, bw = xl + dw + igap, sw - dw - igap
    end
    if nd > 0 then draw_debuff_strip(f, m, xl, iy + floor((sh - di) / 2), dw, di, dim) end
    if #blist > 0 then draw_buff_strip(f, m, blist, bx, iy + floor((sh - bi) / 2), bw, bi, dim) end
end

-- Slanted shapes (top edge shifted right by `sl`), drawn as quads when the backend has them.
local function para(f, x, y, w, h, sl, c, round)
    local g = f.gfx
    if sl <= 0 then
        g.rect_filled(x, y, w, h, c, math.min(round or 0, floor(w / 2), floor(h / 2)))
    elseif g.quad_filled then
        g.quad_filled(x + sl, y, x + w, y, x + w - sl, y + h, x, y + h, c)
    else
        g.rect_filled(x, y, w, h, c, 0)
    end
end

local function para_outline(f, x, y, w, h, sl, c, th)
    local g = f.gfx
    if sl > 0 and g.quad_outline then
        g.quad_outline(x + sl, y, x + w, y, x + w - sl, y + h, x, y + h, c, th)
    else
        outline(g, x, y, w, h, th, c)
    end
end

--- Strip row, YunaUI style: a coloured job block, then a slanted row with the NAME, a small
-- distance, the percentage, debuff tags, and two thin glowing bars (HP white, MP blue) underneath.
-- Hovering a row opens its spell flyout (see draw_flyout).
local function draw_strip(f, m, r, out_of_range, near_limit, dim)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local th = select(2, g.text_size('Ag'))
    local sl = 0                                  -- rows are square
    local rnd = floor(4 * s)                      -- corner rounding for square rows
    local bw = floor(32 * s)                      -- job block
    local x0 = r.x + bw + floor(3 * s)            -- slanted row starts here
    local rw = r.w - bw - floor(3 * s)
    local hot = hovering(f, r.x, r.y, r.w, r.h)
    local sel = ui.state.flyout and ui.state.flyout.slot == m.slot

    -- Job block.
    local jr, jg, jb = jobs.hue(m.job)
    local block = (f.cfg.colors == 'mono') and pal.btn_hot or theme.pack(jr, jg, jb, 1.0)
    g.rect_filled(r.x, r.y, bw, r.h, A(block, 0.92 * dim), floor(3 * s))
    local abbr = jobs.abbr(m.job)
    local fg = (f.cfg.colors == 'mono') and pal.text or theme.pack(0.07, 0.08, 0.10, 1.0)
    local aw = g.text_size(abbr)
    g.text(r.x + floor((bw - aw) / 2), r.y + floor((r.h - th) / 2) - floor(2 * s), A(fg, dim), abbr)

    -- Slanted row background (+ outline when it is the open row).
    local bg
    if m.dead then bg = theme.mix(pal.card, pal.dead, 0.6)
    elseif hot or sel then bg = pal.card_hot
    else bg = pal.card end
    para(f, x0, r.y, rw, r.h, sl, theme.alpha(bg, f.cfg.opacity), rnd)

    -- The whole row is the HP bar: it fills from the left and shifts green -> yellow -> orange -> red.
    local frac = max(0, min(1, (m.hpp or 0) / 100))
    if not m.dead and not m.zone_diff then
        local ins = (sl > 0) and 0 or max(1, floor(2 * s))
        local tx, ty, tw_, th_ = x0 + ins, r.y + ins, rw - 2 * ins, r.h - 2 * ins
        local rr = max(0, rnd - ins)
        -- Dark track behind the fill, so an empty bar still reads as a bar.
        para(f, tx, ty, tw_, th_, sl, theme.pack(0.04, 0.05, 0.07, 0.55 * dim), rr)
        if frac > 0 then
            local fw = floor((tw_ - sl) * frac) + sl
            -- Deepened so the white text on top stays readable at every HP level.
            local fc, fa = theme.hp_fill(pal, frac, { jr, jg, jb }), f.cfg.opacity_hp * dim
            if out_of_range then
                -- Too far to cast on: wash the color out to gray so it reads as "not available".
                fc, fa = theme.mix(fc, theme.pack(0.42, 0.42, 0.45, 1), 0.85), 0.55
            end
            para(f, tx, ty, fw, th_, sl, A(fc, fa), rr)
            if sl <= 0 and fw > 2 * rr then   -- a faint light edge along the top of the fill
                g.rect_filled(tx + rr, ty, fw - 2 * rr, max(1, floor(1 * s)), theme.pack(1, 1, 1, 0.16 * dim), 0)
            end
        end
    end
    local crit = (not m.dead) and (not m.zone_diff) and m.hpp and m.hpp <= f.cfg.hp_crit
    if crit then
        local p = f.cfg.alerts.pulse and pulse(f) or 1
        para_outline(f, x0, r.y, rw, r.h, sl, theme.alpha(pal.bad, 0.30 + 0.70 * p), max(1, floor(1.5 * s)))
    elseif hot or sel then
        para_outline(f, x0, r.y, rw, r.h, sl, A(pal.text, 0.85), max(1, floor(1.5 * s)))
    end

    -- Edge of the slanted row at a given y (so text and bars follow the lean).
    local function left_at(y) return x0 + sl * (1 - (y - r.y) / r.h) end
    local function right_at(y) return x0 + rw - sl * ((y - r.y) / r.h) end

    -- Name line at the top of the row; the debuff icon strip and MP bar are below it.
    local y1 = r.y + floor(5 * s)
    local pad = floor(((sl > 0) and 6 or 9) * s)
    local xl = left_at(y1 + th / 2) + pad
    local xr = right_at(y1 + th / 2) - pad

    -- Percentage (right), then debuff tags left of it.
    local hpt = hp_text(m)
    local right = xr - g.text_size(hpt)
    g.text(right + 1, y1 + 1, theme.pack(0, 0, 0, 0.75 * dim), hpt)
    g.text(right, y1, A(m.dead and hp_text_color(f, m) or pal.text, dim), hpt)
    right = right - floor(6 * s)
    local icons_xr = xr
    if eff(f).mp_pct and f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        -- MP percent sits under the HP percent, right-aligned, in a smaller size.
        local k = eff(f).mp_pct
        local mpt = string.format('%d%%', floor(100 * max(0, min(1, (m.mp or 0) / m.mpmax)) + 0.5))
        local mw, mh = g.text_size_scaled(mpt, k)
        local mx, my = xr - mw, y1 + th - floor(1 * s)
        g.text_scaled(mx + 1, my + 1, theme.pack(0, 0, 0, 0.75 * dim), mpt, k)
        g.text_scaled(mx, my, A(pal.mp, dim), mpt, k)
        icons_xr = min(xr, mx - floor(6 * s))
    end

    local name = m.name:upper()
    local nk = f.cfg.name_scale or 1
    local show_d = f.cfg.show_dist and not m.is_you
    local dist_w = show_d and (g.text_size(dist_text(m)) + floor(6 * s)) or 0
    local chips_left = right

    local room = chips_left - xl - floor(4 * s)
    local shown = fit(g, name, (room - dist_w) / nk)
    g.text_scaled(xl + 1, y1 + 1, theme.pack(0, 0, 0, 0.75 * dim), shown, nk)
    g.text_scaled(xl, y1, name_color(f, m, dim), shown, nk)
    if show_d then
        local dt = dist_text(m)
        local dx = xl + g.text_size_scaled(shown, nk) + floor(6 * s)
        if dx + g.text_size(dt) <= chips_left then
            local dc = out_of_range and pal.bad or (near_limit and pal.warn or A(pal.text, 0.72))
            g.text(dx + 1, y1 + 1, theme.pack(0, 0, 0, 0.6 * dim), dt)
            g.text(dx, y1, A(dc, m.zone_diff and dim or 1), dt)
        end
    end

    -- A thin MP bar along the bottom edge (follows the slant). HP is the row itself.
    local e0 = eff(f)
    local mb = max(2, floor(((e0.mp_h > 0) and e0.mp_h or min(f.cfg.mp_height or 3, 3)) * s))
    if f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        local ym = r.y + r.h - mb - floor(3 * s)
        local mx0, mx1 = left_at(ym + mb / 2) + pad, right_at(ym + mb / 2) - pad
        g.rect_filled(mx0, ym, mx1 - mx0, mb, theme.pack(0, 0, 0, 0.55), 1)
        local mfw = floor((mx1 - mx0) * max(0, min(1, (m.mp or 0) / m.mpmax)))
        if mfw > 0 then g.rect_filled(mx0, ym, mfw, mb, A(pal.mp, f.cfg.opacity_mp * dim), 1) end
    end

    -- Icon strip along the bottom of the row, above the MP bar.
    draw_icon_strip(f, m, xl, icons_xr, r.y + r.h - mb - floor(4 * s) - icon_band(f), dim)

    cell_interact(f, m, r)
end

-- ------------------------------------------------------------------------------------------
-- Hover flyout: the hovered member's spells, in a window beside their row
-- ------------------------------------------------------------------------------------------

local function flyout_groups(f, m)
    local out = {}
    for _, gdef in ipairs(spells.GROUPS) do
        local id = gdef[1]
        if not spells.SELF_GROUPS[id] or m.is_you then
            local keys = {}
            for _, k in ipairs(spells.group_keys(f.cfg, f.preset, id, f.player)) do
                if spells.defs[k] then keys[#keys + 1] = k end
            end
            if #keys > 0 then out[#out + 1] = { id = id, label = gdef[2], keys = keys } end
        end
    end
    return out
end

--- Decides whether a flyout is open and where. Call after draw_roster, before opening the window.
-- Returns nil, or { x, y, w, h, geo, groups, slot }. Also keeps the flyout open while the mouse
-- is on its row or on the flyout itself (with a short grace period against flicker).
function ui.flyout_plan(f)
    local st = ui.state.flyout
    if not st or not f.cfg.flyout then return nil end
    local m = f.roster[st.slot]
    if not m or not m.active then ui.state.flyout = nil; return nil end
    local groups = flyout_groups(f, m)
    if #groups == 0 then return nil end
    local counts = {}
    for i, gp in ipairs(groups) do counts[i] = { id = gp.id, n = #gp.keys } end
    local lopts = { auto_scale = f.cfg.auto_scale, scale = f.cfg.scale, fly_btn = f.cfg.fly_btn, fly_gap = f.cfg.fly_gap }
    local geo = layout.flyout(lopts, f.disp_h or 1080, counts)
    local x, y = layout.flyout_position(st.row, geo, f.disp_w or 1920, f.disp_h or 1080)
    st.fly = { x = x, y = y, w = geo.w, h = geo.h }
    return { x = x, y = y, w = geo.w, h = geo.h, geo = geo, groups = groups, slot = st.slot }
end

--- Called once per frame after the roster is drawn: closes the flyout when the mouse has left
-- both the row and the flyout.
local function update_flyout_state(f)
    local st = ui.state.flyout
    if not st then return end
    if ui.state.row_hot then st.until_t = nil; return end
    local i = f.input or {}
    local fl = st.fly
    local inside = fl and i.mx and i.mx >= fl.x and i.mx < fl.x + fl.w and i.my >= fl.y and i.my < fl.y + fl.h
    local on_row = st.row and i.mx and i.mx >= st.row.x and i.mx < st.row.x + st.row.w
        and i.my >= st.row.y and i.my < st.row.y + st.row.h
    if (inside or on_row) and (i.interactive ~= false) then st.until_t = nil; return end
    st.until_t = st.until_t or (f.now + 0.12)
    if f.now >= st.until_t then ui.state.flyout = nil end
end

--- Draws the open flyout. f.plan = ui.flyout_plan result; f.ox, f.oy = the flyout window's position.
function ui.draw_flyout(f)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    f.events = f.events or {}
    f.tooltip = nil
    local plan = f.plan
    local geo = plan.geo
    local m = f.roster[plan.slot]
    if not m then return f.events end
    local ox, oy = f.ox, f.oy
    local th = select(2, g.text_size('Ag'))

    g.rect_filled(ox, oy, plan.w, plan.h, theme.alpha(pal.bg, f.cfg.opacity_flyout), floor(5 * s))
    outline(g, ox, oy, plan.w, plan.h, 1, theme.alpha(pal.border, 0.95))

    -- Spells that fix what this member has (or Raise when KO'd) get the priority outline.
    local needed = {}
    if m.has_buff_data and m.debuffs and not m.dead then
        for _, k in ipairs(m.debuffs) do
            local info = debuffs.info[k]
            if info and info.spell then needed[info.spell] = true end
        end
    end

    for i, gp in ipairs(plan.groups) do
        local ry = oy + geo.rows[i].y
        g.text(ox + geo.pad, ry + floor((geo.btn - th) / 2), A(pal.text, 0.7), gp.label)
        for j, key in ipairs(gp.keys) do
            local def = spells.defs[key]
            local pr = needed[key] or (m.dead and def.kind == 'raise')
            draw_button(f, ox + geo.pad + geo.label_w + (j - 1) * (geo.btn + geo.gap), ry, geo.btn,
                { def = def, priority = pr and true or false }, m)
        end
    end
    -- What you are casting: a thin progress line along the bottom edge (full width while only the short delay is left).
    local c = f.player and f.player.casting
    if c then
        local bh = max(2, floor(3 * s))
        g.rect_filled(ox + 1, oy + plan.h - bh - 1, plan.w - 2, bh, theme.pack(1, 1, 1, 0.08), 0)
        g.rect_filled(ox + 1, oy + plan.h - bh - 1, max(1, floor((plan.w - 2) * c.frac)), bh, A(pal.accent, 0.95), 0)
    end
    if f.tooltip then g.tooltip(f.tooltip, s) end
    return f.events
end

-- ------------------------------------------------------------------------------------------
-- Shared spell bar: pick a spell, then click a member
-- ------------------------------------------------------------------------------------------

--- What the party needs right now: set of -na/Erase spell keys, and how many members are KO'd.
local function party_needs(f)
    local spells_needed, dead = {}, 0
    for _, m in pairs(f.roster) do
        if m.active and not m.zone_diff then
            if m.dead then dead = dead + 1
            elseif m.has_buff_data and m.debuffs then
                for _, k in ipairs(m.debuffs) do
                    local info = debuffs.info[k]
                    if info and info.spell and not f.cfg.alerts.muted[k] then spells_needed[info.spell] = true end
                end
            end
        end
    end
    return spells_needed, dead
end

local function draw_bar_tile(f, x, y, size, key, needed, armed)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local def = spells.defs[key]
    local dummy = { active = true, dead = (def.kind == 'raise') }
    local state, detail = spellstate.evaluate(def, dummy, f.player, f.cfg)
    local ready = (state == 'ready')
    local hot = hovering(f, x, y, size, size)
    local round = floor(3 * s)

    local bg = hot and pal.btn_hot or pal.btn
    if armed then bg = theme.mix(bg, pal.accent, 0.35) end
    if not ready and state ~= 'recast' then bg = A(bg, 0.65) end
    g.rect_filled(x, y, size, size, bg, round)

    local lh = max(2, floor(2 * s))
    local kc = pal.kind[def.kind] or pal.accent
    g.rect_filled(x + floor(4 * s), y + size - lh - floor(3 * s), size - floor(8 * s), lh, A(kc, ready and 0.85 or 0.30), 0)

    if state == 'recast' then
        paint_recast(f, x, y, size, def, detail, round)
    else
        if not ready and state ~= 'nomp' then
            g.rect_filled(x, y, size, size, theme.pack(0, 0, 0, 0.35), round)
        end
        local label = def.short
        local col = ready and pal.text or (state == 'nomp' and pal.mp or A(pal.text_dim, 0.8))
        local tw, th = g.text_size(label)
        g.text(x + floor((size - tw) / 2), y + floor((size - th) / 2) - floor(2 * s), col, label)
    end

    if armed then
        outline(g, x, y, size, size, max(1, floor(2 * s)), pal.accent)
    elseif needed then
        outline(g, x, y, size, size, max(1, floor(2 * s)), theme.alpha(pal.warn, 0.35 + 0.65 * pulse(f)))
    elseif hot then
        outline(g, x, y, size, size, max(1, floor(1 * s)), A(pal.accent, 0.9))
    end

    note_hitbox(f, 'bar_tile', x, y, size, size, { key = key })
    if hot then
        f.tooltip = {
            string.format('%s   (%d MP)', def.name, def.mp or 0),
            'Status: ' .. spellstate.describe(state, detail),
            armed and 'Click: disarm' or (spells.sticky(def) and 'Click: arm (stays armed), then click members'
                or 'Click: arm, then click a member'),
        }
        local btn = click_button(f)
        if btn == 'left' then
            ui.state.armed = armed and nil or key
        elseif btn == 'right' then
            ui.state.armed = nil
        end
    end
end

local function draw_spellbar(f)
    local b = f.geom.bar
    if not b then return end
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local tabs = spells.bar_tabs(f.preset)
    if #tabs == 0 then return end

    local cur = tabs[1]
    for _, tb in ipairs(tabs) do if tb.id == f.cfg.bar_tab then cur = tb end end

    local bx, by = f.ox + b.x, f.oy + b.y
    local th = select(2, g.text_size('Ag'))
    g.rect_filled(bx, by, b.w, b.h, theme.alpha(pal.card, f.cfg.opacity), floor(4 * s))

    local needed, dead = party_needs(f)
    local any_needed = next(needed) ~= nil

    -- Tabs.
    local tx, ty = bx + b.pad, by + b.pad
    for _, tb in ipairs(tabs) do
        local tw = g.text_size(tb.label) + floor(10 * s)
        local hot = hovering(f, tx, ty, tw, b.tab_h)
        local bg = hot and pal.btn_hot or pal.btn
        if tb.id == cur.id then bg = theme.mix(bg, pal.accent, 0.28) end
        g.rect_filled(tx, ty, tw, b.tab_h, bg, floor(3 * s))
        g.text(tx + floor(5 * s), ty + floor((b.tab_h - th) / 2),
            tb.id == cur.id and pal.text or pal.text_dim, tb.label)
        local attention = (tb.id == 'cleanse' and any_needed) or (tb.id == 'raise' and dead > 0)
        if attention and tb.id ~= cur.id then
            local d = max(3, floor(4 * s))
            g.rect_filled(tx + tw - d - 1, ty + 1, d, d, theme.alpha(pal.warn, 0.45 + 0.55 * pulse(f)), floor(d / 2))
        end
        note_hitbox(f, 'bar_tab', tx, ty, tw, b.tab_h, { id = tb.id })
        if hot and click_button(f) == 'left' and tb.id ~= cur.id then
            f.events[#f.events + 1] = { type = 'toggle', what = 'bar_tab', value = tb.id }
        end
        tx = tx + tw + floor(3 * s)
    end

    -- Status text to the right of the tabs.
    local armed = ui.state.armed and spells.defs[ui.state.armed] or nil
    local cands
    if armed then
        cands = { 'Armed: ' .. armed.name .. ' - click a member, right click cancels',
                  'Armed: ' .. armed.name .. ' - click a member', 'Armed: ' .. armed.name, armed.name }
    else
        cands = { 'Pick a spell, then click a member', 'Pick a spell, then a member', 'Spell, then member' }
    end
    local room = bx + b.w - b.pad - tx - floor(4 * s)
    local msg
    for _, c in ipairs(cands) do
        if g.text_size(c) <= room then msg = c; break end
    end
    if msg then
        g.text(bx + b.w - b.pad - g.text_size(msg), ty + floor((b.tab_h - th) / 2),
            armed and pal.accent or A(pal.text_dim, 0.8), msg)
    end

    -- Tiles.
    local x0, y0 = bx + b.pad, ty + b.tab_h + b.gap
    for i, key in ipairs(cur.keys) do
        if i > b.tiles then break end
        draw_bar_tile(f, x0 + (i - 1) * (b.btn + b.gap), y0, b.btn, key,
            (needed[key] or (cur.id == 'raise' and dead > 0 and spells.defs[key].kind == 'raise')) and true or false,
            ui.state.armed == key)
    end
end

-- ------------------------------------------------------------------------------------------
-- Hairline row: no card, a colored job line, a large colored percentage, a thin HP rail
-- ------------------------------------------------------------------------------------------

--- The pale "what you just lost" trail behind the HP rail: follows HP up at once, drains down slowly.
local function trail_value(f, m, frac)
    local T = ui.state.trail
    if not T then T = {}; ui.state.trail = T end
    local now = f.now or 0
    local st = T[m.slot]
    if not st then st = { v = frac, t = now }; T[m.slot] = st end
    if frac >= st.v then st.v = frac else st.v = max(frac, st.v - max(0, now - st.t) * 0.30) end
    st.t = now
    return st.v
end

--- Text with extra space between letters (the tracked small-caps look). Returns the width drawn.
local function spaced_width(g, str, space, k)
    local w = 0
    for i = 1, #str do w = w + g.text_size_scaled(str:sub(i, i), k) + ((i < #str) and space or 0) end
    return w
end

local function spaced_text(g, x, y, c, str, space, k)
    local cx = x
    for i = 1, #str do
        local ch = str:sub(i, i)
        g.text_scaled(cx, y, c, ch, k)
        cx = cx + g.text_size_scaled(ch, k) + space
    end
    return cx - x - space
end

--- Hairline: no card. Name in tracked capitals with the job beside it, status icons under the name, a large
-- health-colored percentage on the right, and one thin HP rail across the full width at the bottom
-- (with a pale trail for what was just lost) and a hairline of MP under it. The job is a colored line.
local function draw_hairline(f, m, r, out_of_range, near_limit, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local th = select(2, g.text_size('Ag'))
    local hot = hovering(f, r.x, r.y, r.w, r.h)
    local sel = ui.state.flyout and ui.state.flyout.slot == m.slot
    local frac = max(0, min(1, (m.hpp or 0) / 100))
    local alive = not m.dead and not m.zone_diff
    local jr, jg, jb = jobs.hue(m.job)
    local crit = alive and m.hpp and m.hpp <= f.cfg.hp_crit
    local pl = crit and (f.cfg.alerts.pulse and pulse(f) or 1) or 1

    if hot or sel then g.rect_filled(r.x, r.y, r.w, r.h, theme.pack(1, 1, 1, 0.05), floor(2 * s)) end

    -- Job line down the left edge (a pulsing red line when HP is critical).
    local jcol = (f.cfg.colors == 'mono') and pal.text or theme.pack(jr, jg, jb, 1.0)
    if crit then jcol = pal.bad end
    local lw = max(2, floor(2 * s))
    g.rect_filled(r.x, r.y + floor(3 * s), lw, r.h - floor(6 * s), A(jcol, (crit and (0.35 + 0.65 * pl) or 0.95) * dim), 0)

    local xl = r.x + floor(10 * s)
    local xr = r.x + r.w - floor(4 * s)

    -- Large percentage on the right, colored by health, small % sign; MP percent under it.
    local k = eff(f).hl_pct or 2.0
    local num = m.dead and 'KO' or string.format('%d', floor(m.hpp or 0))
    local nw, nh = g.text_size_scaled(num, k)
    local sw = m.dead and 0 or (g.text_size_scaled('%', 0.55) + floor(1 * s))
    local px, py = xr - nw - sw, r.y + floor(1 * s)
    local pcol = m.dead and pal.bad or theme.hp_color(pal, frac)
    g.text_scaled(px + 1, py + 1, theme.pack(0, 0, 0, 0.7 * dim), num, k)
    g.text_scaled(px, py, A(pcol, dim), num, k)
    if not m.dead then
        local _, sh2 = g.text_size_scaled('%', 0.55)
        g.text_scaled(px + nw + floor(1 * s), py + nh - sh2 - floor(3 * s), A(pcol, 0.85 * dim), '%', 0.55)
    end
    local left = px
    if eff(f).mp_pct and f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        local k2 = eff(f).mp_pct
        local mpt = string.format('%d%%', floor(100 * max(0, min(1, (m.mp or 0) / m.mpmax)) + 0.5))
        local mw = g.text_size_scaled(mpt, k2)
        g.text_scaled(xr - mw, py + nh - floor(2 * s), A(pal.mp, dim), mpt, k2)
        left = min(left, xr - mw)
    end
    local limit = left - floor(10 * s)

    -- Name in tracked capitals, then the job and the distance.
    local y1 = r.y + floor(3 * s)
    local nx = xl
    local name = m.name:upper()
    local show_d = f.cfg.show_dist and not m.is_you
    local dt = show_d and dist_text(m) or nil
    local dist_w = dt and (g.text_size(dt) + floor(8 * s)) or 0
    local ab = jobs.abbr(m.job)
    local ab_w = ab and (g.text_size(ab) + floor(8 * s)) or 0
    local kn = 0.92 * (f.cfg.name_scale or 1)
    local space = max(1, floor(2 * s))
    local avail = limit - nx
    local name_w = spaced_width(g, name, space, kn)
    local ncol = name_color(f, m, dim)
    local tx
    if name_w + ab_w <= avail then
        spaced_text(g, nx + 1, y1 + 1, theme.pack(0, 0, 0, 0.7 * dim), name, space, kn)
        spaced_text(g, nx, y1, ncol, name, space, kn)
        tx = nx + name_w + floor(8 * s)
    else
        local shown = fit(g, name, avail - ab_w)
        g.text(nx + 1, y1 + 1, theme.pack(0, 0, 0, 0.7 * dim), shown)
        g.text(nx, y1, ncol, shown)
        tx = nx + g.text_size(shown) + floor(8 * s)
    end
    if ab and tx + g.text_size(ab) <= limit then
        g.text(tx, y1, A(pal.text_dim, 0.8 * dim), ab)
        tx = tx + g.text_size(ab) + floor(8 * s)
    end
    if dt and tx + g.text_size(dt) <= limit then
        local dc = out_of_range and pal.bad or (near_limit and pal.warn or A(pal.text, 0.6))
        g.text(tx, y1, A(dc, m.zone_diff and dim or 1), dt)
    end

    -- Status icons sit under the name, left of the big percentage.
    draw_icon_strip(f, m, xl, limit, y1 + th + floor(3 * s), dim)

    -- One rail across the full width at the bottom, with the damage trail, then a hairline of MP.
    local mph = (f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead) and max(1, floor(eff(f).mp_h * 0.5 * s)) or 0
    local rh = (hot or sel) and max(3, floor(5 * s)) or max(2, floor(3 * s))
    local ry = r.y + r.h - floor(3 * s) - mph - floor(1 * s) - max(3, floor(5 * s))
    local rw = xr - xl
    if rw > 4 then
        g.rect_filled(xl, ry, rw, rh, theme.pack(1, 1, 1, 0.14 * dim), 0)
        if alive then
            local tv = trail_value(f, m, frac)
            if tv > frac + 0.004 then g.rect_filled(xl, ry, floor(rw * tv), rh, theme.pack(1, 1, 1, 0.30 * dim), 0) end
            local fc, fa = theme.hp_fill(pal, frac, { jr, jg, jb }), f.cfg.opacity_hp * dim
            if out_of_range then fc, fa = theme.mix(fc, theme.pack(0.42, 0.42, 0.45, 1), 0.85), 0.55 end
            if frac > 0 then g.rect_filled(xl, ry, max(1, floor(rw * frac)), rh, A(fc, fa), 0) end
        end
        if mph > 0 then
            local my = ry + max(3, floor(5 * s)) + floor(1 * s)
            g.rect_filled(xl, my, rw, mph, theme.pack(0, 0, 0, 0.5), 0)
            local mfw = floor(rw * max(0, min(1, (m.mp or 0) / m.mpmax)))
            if mfw > 0 then g.rect_filled(xl, my, mfw, mph, A(pal.mp, f.cfg.opacity_mp * dim), 0) end
        end
    end

    cell_interact(f, m, r)
end

-- ------------------------------------------------------------------------------------------
-- Triage: the neediest member in one panel, cure buttons sized to the gap, everyone else in a list
-- ------------------------------------------------------------------------------------------

local function draw_tile(f, x, y, w, h, def, member, best, potency, note)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local state, detail = spellstate.evaluate(def, member, f.player, f.cfg)
    local ready = (state == 'ready')
    local busy = (state == 'busy')
    local hot = hovering(f, x, y, w, h)
    local bg = hot and pal.btn_hot or pal.btn
    if best and (ready or busy) then bg = theme.mix(bg, pal.accent, 0.22) end
    if not ready and not busy and state ~= 'recast' then bg = A(bg, 0.65) end
    g.rect_filled(x, y, w, h, bg, floor(3 * s))
    local th = select(2, g.text_size('Ag'))
    local tcol = (ready or busy) and pal.text or A(pal.text_dim, 0.8)
    local name = fit(g, (def.name:gsub('^Cure ', '')), w - floor(8 * s))
    g.text(x + floor(5 * s), y + floor(4 * s), tcol, name)
    local sub
    if state == 'recast' then sub = ui.fmt_recast(detail)
    elseif state == 'nomp' then sub = 'no MP'
    elseif note then sub = note
    elseif not potency then sub = def.kind == 'curaga' and 'area' or (def.mp and (def.mp .. ' MP') or '')
    else sub = string.format('+%d', potency or 0) end
    local subcol = (state == 'nomp') and pal.mp or (note and state == 'ready') and pal.warn or A(pal.text_dim, 0.95)
    g.text(x + floor(5 * s), y + h - th - floor(4 * s), subcol, fit(g, sub, w - floor(8 * s)))
    if best and (ready or busy) then outline(g, x, y, w, h, max(1, floor(1.5 * s)), A(pal.accent, 0.9)) end
    if f.player and f.player.queued == def.key then outline(g, x, y, w, h, max(1, floor(2 * s)), A(pal.accent, 0.9)) end
    note_hitbox(f, 'spell', x, y, w, h, { slot = member.slot, key = def.key })
    if hot then
        outline(g, x, y, w, h, max(1, floor(1 * s)), A(pal.accent, 0.9))
        f.tooltip = {
            string.format('%s   (%d MP)', def.name, def.mp or 0),
            'Target: ' .. member.name,
            'Status: ' .. spellstate.describe(state, detail),
            note and ((note == 'buff') and 'Buff you can add' or ('Removes ' .. note)) or (potency and ('Roughly +' .. potency .. ' HP (estimate)') or ''),
        }
        local btn = click_button(f)
        if btn then
            local mods = f.input.mods or {}
            local rkey = spells.resolve(def, btn, mods) or def.key
            local rdef = spells.defs[rkey] or def
            local rstate, rdetail = spellstate.evaluate(rdef, member, f.player, f.cfg)
            f.events[#f.events + 1] = {
                type = 'cast', via = 'card', slot = member.slot, spell = rkey,
                button = btn, mods = mods, state = rstate, detail = rdetail,
            }
        end
    end
end

local function draw_triage(f)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local T = geom.tri
    if not T then return end
    local ox, oy = f.ox, f.oy
    local th = select(2, g.text_size('Ag'))
    local rl, gs = f.roster_list, f.group_set
    if not rl then
        rl = {}
        for _, m in pairs(f.roster or {}) do rl[#rl + 1] = m end
    end
    if not gs and f.groups then gs = {}; for _, gi in ipairs(f.groups) do gs[gi] = true end end
    local can = triage.cleanse_set(f.cfg, f.preset, f.player)
    local list, tiers = triage.order(rl, f.cfg, gs, can)
    local feat = triage.pick(list, f.cfg, ui.state.tri_slot, tiers)
    ui.state.tri_slot = feat and feat.slot or nil

    local M = T.main
    local mx, my = ox + M.x, oy + M.y
    g.rect_filled(mx, my, M.w, M.h, theme.alpha(pal.card, f.cfg.opacity), floor(4 * s))
    if not feat then
        g.text(mx + M.pad, my + M.pad, A(pal.text_dim, 0.8), 'No party members')
        return
    end

    local out_of_range, near_limit, dim = member_flags(f, feat)
    local def_hp = triage.deficit(feat)
    local frac = max(0, min(1, (feat.hpp or 0) / 100))
    local tier = tiers[feat.slot] or 0
    local tiles, best_key = triage.tiles(feat, f.cfg, f.preset, f.player, tier, (f.cfg.triage_opts and f.cfg.triage_opts.tiles) or 4)
    local fix = triage.fixable(feat, can)
    local jr, jg, jb = jobs.hue(feat.job)
    local x0, x1 = mx + M.pad, mx + M.w - M.pad
    if def_hp > 0 and triage.eligible(feat, f.cfg) then
        outline(g, mx, my, M.w, M.h, max(1, floor(1 * s)), A(theme.hp_color(pal, frac), 0.55))
    end

    -- Head: name large, job small, missing HP on the right.
    local hy = my + M.pad
    local kn = 1.35
    local nm = fit(g, feat.name:upper(), floor(M.w * 0.5))
    local nw, nh = g.text_size_scaled(nm, kn)
    local ny = hy + floor((M.head_h - nh) / 2)
    g.rect_filled(x0, hy + floor(2 * s), max(2, floor(2 * s)), M.head_h - floor(4 * s), A(theme.pack(jr, jg, jb, 1.0), dim), 0)
    local nx = x0 + floor(8 * s)
    g.text_scaled(nx + 1, ny + 1, theme.pack(0, 0, 0, 0.7), nm, kn)
    g.text_scaled(nx, ny, name_color(f, feat, dim), nm, kn)
    g.text(nx + nw + floor(6 * s), hy + floor((M.head_h - th) / 2), A(pal.text_dim, 0.85), jobs.abbr(feat.job))
    local right_txt, right_col
    if feat.dead then right_txt, right_col = 'KO', pal.bad
    elseif tier == 3 and fix[1] then right_txt, right_col = debuffs.info[fix[1].key].label, pal.bad
    elseif def_hp > 0 then right_txt, right_col = '-' .. def_hp, theme.hp_color(pal, frac)
    else right_txt, right_col = 'ALL FULL', pal.good end
    local rw_, rh_ = g.text_size_scaled(right_txt, 1.2)
    g.text_scaled(x1 - rw_, hy + floor((M.head_h - rh_) / 2), A(right_col, dim), right_txt, 1.2)

    -- HP bar with a preview of the best-fit cure.
    local by = hy + M.head_h + M.gap
    local bw = x1 - x0
    g.rect_filled(x0, by, bw, M.bar_h, theme.pack(0, 0, 0, 0.45), floor(2 * s))
    if not feat.dead and not feat.zone_diff then
        local fc = theme.hp_fill(pal, frac, { jr, jg, jb })
        if out_of_range then fc = theme.mix(fc, theme.pack(0.42, 0.42, 0.45, 1), 0.85) end
        local fw = floor(bw * frac)
        if fw > 0 then g.rect_filled(x0, by, fw, M.bar_h, A(fc, f.cfg.opacity_hp), floor(2 * s)) end
        local pot = best_key and triage.POTENCY[best_key] or 0
        if pot > 0 and feat.hpmax and feat.hpmax > 0 and def_hp > 0 then
            local pw = floor(bw * min(1 - frac, pot / feat.hpmax))
            if pw > 0 then g.rect_filled(x0 + fw, by, pw, M.bar_h, A(pal.accent, 0.50), 0) end
        end
    end
    local hptxt = string.format('%d / %d', feat.hp or 0, feat.hpmax or 0)
    local hw = g.text_size(hptxt)
    g.text(x0 + floor((bw - hw) / 2), by + floor((M.bar_h - th) / 2), theme.pack(1, 1, 1, 0.95), hptxt)

    -- Status icons, then cure tiles.
    local iy = by + M.bar_h + M.gap
    draw_icon_strip(f, feat, x0, x1, iy, dim)
    local ty = iy + M.icon_h + M.gap
    local n = #tiles
    if n == 0 then
        g.text(x0, ty + floor((M.tile_h - th) / 2), A(pal.text_dim, 0.8), 'No cures learned')
    else
        local tgap = floor(4 * s)
        local tw = floor((bw - (n - 1) * tgap) / n)
        for i, tl in ipairs(tiles) do
            local note
            if tl.kind == 'cleanse' and tl.debuff then note = debuffs.info[tl.debuff].label
            elseif tl.kind == 'buff' then note = 'buff' end
            draw_tile(f, x0 + (i - 1) * (tw + tgap), ty, tw, M.tile_h, spells.defs[tl.key], feat, tl.key == best_key,
                triage.POTENCY[tl.key], note)
        end
    end

    -- Hovering the head opens the usual flyout / click bindings for this member.
    cell_interact(f, feat, { x = mx, y = my, w = M.w, h = M.pad + M.head_h + M.gap + M.bar_h })

    -- Everyone else, neediest first.
    local L = T.list
    local ly = oy + L.y
    local lx = ox + L.x
    for _, m in ipairs(list) do
        if m ~= feat then
            local rr = { x = lx, y = ly, w = L.w, h = L.row }
            local oor, nlim, d2 = member_flags(f, m)
            local mf = max(0, min(1, (m.hpp or 0) / 100))
            local mjr, mjg, mjb = jobs.hue(m.job)
            local hot = hovering(f, rr.x, rr.y, rr.w, rr.h)
            if hot then g.rect_filled(rr.x, rr.y, rr.w, rr.h, theme.pack(1, 1, 1, 0.06), floor(2 * s)) end
            g.rect_filled(rr.x, rr.y + floor(2 * s), max(2, floor(2 * s)), rr.h - floor(4 * s), A(theme.pack(mjr, mjg, mjb, 1.0), d2), 0)
            local pt = m.dead and 'KO' or string.format('%d%%', floor(m.hpp or 0))
            local pw = g.text_size('100%')
            local pcol = m.dead and pal.bad or theme.hp_color(pal, mf)
            local ty2 = rr.y + floor((rr.h - th) / 2)
            g.text(rr.x + rr.w - g.text_size(pt) - floor(3 * s), ty2, A(pcol, d2), pt)
            local nm2 = fit(g, m.name:upper(), floor(rr.w * 0.34))
            g.text(rr.x + floor(8 * s), ty2, name_color(f, m, d2), nm2)
            local bx = rr.x + floor(rr.w * 0.40)
            local bw2 = rr.x + rr.w - pw - floor(10 * s) - bx
            if bw2 > 6 then
                local bh = max(2, floor(3 * s))
                local byy = rr.y + floor((rr.h - bh) / 2)
                g.rect_filled(bx, byy, bw2, bh, theme.pack(1, 1, 1, 0.14 * d2), 0)
                if not m.dead and not m.zone_diff and mf > 0 then
                    local fc = theme.hp_fill(pal, mf, { mjr, mjg, mjb })
                    if oor then fc = theme.mix(fc, theme.pack(0.42, 0.42, 0.45, 1), 0.85) end
                    g.rect_filled(bx, byy, max(1, floor(bw2 * mf)), bh, A(fc, f.cfg.opacity_hp * d2), 0)
                end
            end
            local nd = (not m.dead) and #sorted_debuffs(m) or 0
            if nd > 0 then
                local dsz = max(3, floor(5 * s))
                local worst = debuffs.info[sorted_debuffs(m)[1]]
                g.rect_filled(bx - dsz - floor(3 * s), rr.y + floor((rr.h - dsz) / 2), dsz, dsz, sev_color(pal, worst and worst.sev or 3), 0)
            end
            cell_interact(f, m, rr)
            ly = ly + L.row + L.gap
        end
    end
end

local function draw_member(f, m, r)
    local out_of_range, near_limit, dim = member_flags(f, m)
    if f.cfg.skin == 'hairline' then
        draw_hairline(f, m, r, out_of_range, near_limit, dim)
        return
    end
    card_frame(f, m, r, dim)
    draw_strip(f, m, r, out_of_range, near_limit, dim)
end

local function draw_empty(f, r)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    outline(g, r.x, r.y, r.w, r.h, 1, theme.alpha(pal.border, 0.55))
    local th = select(2, g.text_size('Ag'))
    g.text(r.x + f.geom.pad + 2, r.y + floor((r.h - th) / 2), theme.alpha(pal.text_dim, 0.45), '-')
end

-- ------------------------------------------------------------------------------------------
-- roster panel
-- ------------------------------------------------------------------------------------------

local GROUP_NAMES = { [0] = 'PARTY', [1] = 'ALLIANCE 1', [2] = 'ALLIANCE 2' }

function ui.draw_roster(f)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    f.events = f.events or {}
    f.tooltip = nil
    ui.state.row_hot = false
    local ox, oy = f.ox, f.oy
    local th = select(2, g.text_size('Ag'))

    -- Panel background + slim header strip.
    g.rect_filled(ox, oy, geom.width, geom.height, theme.alpha(pal.bg, f.cfg.opacity_panel), floor(5 * s))
    local has_header = geom.header_h > 0
    if has_header then
        g.rect_filled(ox, oy, geom.width, geom.header_h, theme.alpha(pal.card_hot, f.cfg.opacity_panel * 0.75), floor(5 * s))
        g.text(ox + floor(6 * s), oy + floor((geom.header_h - th) / 2), A(pal.text_dim, 0.9), 'CLICKHEAL')
    end

    -- Heal / Buff mode switch (only for jobs that have buff spells).
    local chip_w = 0
    if has_header and f.preset.buffs and #f.preset.buffs > 0 and not geom.bar and not f.cfg.flyout then
        local label = f.cfg.buff_mode and 'BUFF' or 'HEAL'
        local cx = ox + g.text_size('CLICKHEAL') + floor(14 * s)
        local ch_h = geom.header_h - 2
        local cw = g.text_size('BUFF') + floor(10 * s)
        local hot = hovering(f, cx, oy + 1, cw, ch_h)
        local bg = hot and pal.btn_hot or pal.btn
        if f.cfg.buff_mode then bg = theme.mix(bg, pal.accent, 0.25) end
        g.rect_filled(cx, oy + 1, cw, ch_h, bg, floor(3 * s))
        local lw = g.text_size(label)
        g.text(cx + floor((cw - lw) / 2), oy + floor((geom.header_h - th) / 2),
            f.cfg.buff_mode and pal.text or pal.text_dim, label)
        note_hitbox(f, 'mode', cx, oy + 1, cw, ch_h, {})
        if hot then
            f.tooltip = { 'Spell row: ' .. (f.cfg.buff_mode and 'buffs' or 'heals and cleanses'), 'Click to switch   (/ch buffmode)' }
            if click_button(f) == 'left' then
                f.events[#f.events + 1] = { type = 'toggle', what = 'buff_mode' }
            end
        end
        chip_w = cw + floor(8 * s)
    end

    -- Header buttons (work whether the panel is locked or not): MOVE/LOCK and CFG, right-aligned.
    local buttons_w = 0
    if has_header then
        local i = f.input
        local function header_button(right_x, label, tip, event)
            local bw = g.text_size(label) + floor(10 * s)
            local bx, by, bh = right_x - bw, oy + 1, geom.header_h - 2
            local hot = i and i.hovered and i.mx >= bx and i.mx < bx + bw and i.my >= by and i.my < by + bh
            g.rect_filled(bx, by, bw, bh, hot and pal.btn_hot or pal.btn, floor(3 * s))
            local lw = g.text_size(label)
            g.text(bx + floor((bw - lw) / 2), oy + floor((geom.header_h - th) / 2), hot and pal.text or pal.text_dim, label)
            note_hitbox(f, 'header', bx, by, bw, bh, { label = label })
            if hot then
                f.tooltip = tip
                if i.clicked and i.clicked.left then f.events[#f.events + 1] = event end
            end
            return bw + floor(4 * s)
        end
        local right_x = ox + geom.width - floor(4 * s)
        local used = header_button(right_x, 'CFG', { 'Setup panel', '(/ch)' }, { type = 'open_config' })
        right_x = right_x - used
        used = used + header_button(right_x, f.cfg.locked and 'MOVE' or 'LOCK',
            f.cfg.locked and { 'Unlock to move and resize', 'Drag the window, drag the corner to resize   (/ch unlock)' }
                or { 'Lock in place so clicks cast', '(/ch lock)' },
            { type = 'toggle', what = 'locked' })
        buttons_w = used + floor(4 * s)
    end

    -- Right-hand status tag: use the longest wording that fits next to the title.
    local candidates, tag_col
    if not f.cfg.locked then
        candidates = { 'UNLOCKED - drag to move  (/ch lock)', 'UNLOCKED - drag to move', 'UNLOCKED' }
        tag_col = pal.warn
    elseif f.cfg.demo then
        candidates = { 'DEMO DATA', 'DEMO' }
        tag_col = A(pal.text_dim, 0.7)
    end
    if candidates and has_header then
        local title_w = g.text_size('CLICKHEAL') + floor(6 * s) + chip_w
        local room = geom.width - title_w - floor(18 * s) - buttons_w
        for _, tag in ipairs(candidates) do
            local tw = g.text_size(tag)
            if tw <= room then
                g.text(ox + geom.width - buttons_w - tw - floor(6 * s), oy + floor((geom.header_h - th) / 2), tag_col, tag)
                break
            end
        end
    end

    -- Resize grip (only while unlocked): drag the bottom-right corner to scale the whole panel.
    if not f.cfg.locked and g.hit_area then
        local gs = floor(14 * s)
        local gx, gy = ox + geom.width - gs, oy + geom.height - gs
        g.current_input = f.input
        local held = g.hit_area('##chgrip', gx, gy, gs, gs)
        local col = held and pal.accent or A(pal.text_dim, 0.8)
        for k = 1, 3 do
            local o = floor(k * 4 * s)
            g.rect_filled(gx + gs - o - 1, gy + gs - floor(2 * s) - 1, floor(2 * s), floor(2 * s), col, 0)
            g.rect_filled(gx + gs - floor(2 * s) - 1, gy + gs - o - 1, floor(2 * s), floor(2 * s), col, 0)
        end
        if held then
            local rs = ui.state.resize
            if not rs then rs = { w0 = geom.width, scale0 = f.cfg.scale }; ui.state.resize = rs end
            local ratio = (f.input.mx - ox + gs / 2) / rs.w0
            local v = floor(rs.scale0 * ratio / 0.05 + 0.5) * 0.05
            v = max(0.5, min(3.0, v))
            if math.abs(v - f.cfg.scale) >= 0.049 then
                f.events[#f.events + 1] = { type = 'set_scale', value = v }
            end
        else
            ui.state.resize = nil
        end
    else
        ui.state.resize = nil
    end

    -- Group labels.
    if geom.label_h > 0 then
        for _, grp in ipairs(geom.groups) do
            g.text(ox + grp.x + floor(3 * s), oy + grp.y, A(pal.text_dim, 0.8), GROUP_NAMES[grp.index] or 'GROUP')
        end
    end

    -- Cards (or the triage panel).
    if f.cfg.triage then draw_triage(f) end
    for _, grp in ipairs(geom.groups) do
        for i = 0, 5 do
            local slot = grp.index * 6 + i
            local c = geom.cards[slot]
            local r = { x = ox + c.x, y = oy + c.y, w = c.w, h = c.h }
            local m = f.roster[slot]
            if m and m.active then
                draw_member(f, m, r)
            elseif f.cfg.show_empty_slots then
                draw_empty(f, r)
            end
        end
    end

    draw_spellbar(f)
    update_flyout_state(f)

    -- A right click anywhere on the panel drops the armed spell.
    if ui.state.armed and click_button(f) == 'right' and hovering(f, ox, oy, geom.width, geom.height) then
        ui.state.armed = nil
    end

    if f.tooltip then g.tooltip(f.tooltip, s) end
    return f.events
end

-- ------------------------------------------------------------------------------------------
-- alert bar
-- ------------------------------------------------------------------------------------------

--- f additionally needs: alerts (list), abar (layout.alert_bar result), placeholder (bool)
function ui.draw_alerts(f)
    local g, pal, s = f.gfx, f.pal, f.abar.scale
    f.events = f.events or {}
    f.tooltip = nil
    local ab = f.abar
    local ox, oy = f.ox, f.oy
    local th = select(2, g.text_size('Ag'))

    g.rect_filled(ox, oy, ab.w, ab.h, theme.alpha(pal.bg, f.cfg.opacity * 0.85), floor(5 * s))

    if f.placeholder then
        g.rect_filled(ox + ab.pad, oy + ab.pad, ab.w - 2 * ab.pad, ab.row_h, theme.alpha(pal.card_hot, 0.9), floor(4 * s))
        g.text(ox + ab.pad + floor(12 * s), oy + ab.pad + floor((ab.row_h - th) / 2), pal.warn,
            'Alert bar - drag to move  (/ch lock when done)')
        return f.events
    end

    for i, al in ipairs(f.alerts) do
        local rx, ry = ox + ab.pad, oy + ab.pad + (i - 1) * (ab.row_h + ab.gap)
        local rw, rh = ab.w - 2 * ab.pad, ab.row_h
        local sc = sev_color(pal, al.sev)
        local dim = al.in_range and 1.0 or 0.58

        local hot = hovering(f, rx, ry, rw, rh)
        g.rect_filled(rx, ry, rw, rh, hot and pal.card_hot or pal.card, floor(4 * s))

        -- Severity stripe on the left: the main visual signal.
        g.rect_filled(rx, ry, floor(4 * s), rh, A(sc, dim), floor(2 * s))

        -- Critical alerts get a pulsing frame.
        if al.sev == 1 and f.cfg.alerts.pulse then
            outline(g, rx, ry, rw, rh, max(1, floor(2 * s)), theme.alpha(pal.bad, 0.25 + 0.75 * pulse(f)))
        end

        local ty = ry + floor((rh - th) / 2)
        local x = rx + floor(14 * s)
        g.text(x, ty, A(pal.text, dim), al.name)
        x = x + g.text_size(al.name) + floor(8 * s)
        g.text(x, ty, A(sc == pal.text_dim and pal.text or sc, dim), al.text)

        -- Right side: suggested spell + why it may not be castable.
        local right = rx + rw - floor(8 * s)
        if al.spell then
            local def = spells.defs[al.spell]
            local member = f.roster[al.slot]
            local state, detail = spellstate.evaluate(def, member, f.player, f.cfg)
            local ready = (state == 'ready')

            local label = def.name
            local pw = g.text_size(label) + floor(16 * s)
            local px = right - pw
            local ph = rh - floor(10 * s)
            local py = ry + floor((rh - ph) / 2)
            local pbg = hot and ready and theme.mix(pal.btn_hot, pal.accent, 0.30) or pal.btn_hot
            g.rect_filled(px, py, pw, ph, ready and pbg or A(pal.btn, 0.8), floor(3 * s))
            local kc = pal.kind[def.kind] or pal.accent
            g.rect_filled(px + floor(5 * s), py + ph - max(2, floor(2 * s)) - floor(2 * s),
                pw - floor(10 * s), max(2, floor(2 * s)), A(kc, ready and 0.85 or 0.3), 0)
            g.text(px + floor(8 * s), py + floor((ph - th) / 2) - floor(2 * s),
                ready and pal.text or pal.text_dim, label)

            if not ready and state ~= 'recast' then
                local why = (state == 'range') and 'out of range' or spellstate.describe(state, detail)
                local ww = g.text_size(why)
                g.text(px - ww - floor(8 * s), ty, A(pal.text_dim, 0.9), why)
            end

            note_hitbox(f, 'alert', rx, ry, rw, rh, { id = al.id, slot = al.slot, key = al.spell })
            if hot then
                local btn = click_button(f)
                if btn == 'left' then
                    f.events[#f.events + 1] = {
                        type = 'cast', via = 'alert', slot = al.slot, spell = al.spell,
                        button = 'left', mods = f.input.mods or {}, state = state, detail = detail,
                    }
                elseif btn == 'right' then
                    f.events[#f.events + 1] = { type = 'dismiss', id = al.id }
                end
            end
        else
            local note = 'no suggested spell'
            local nw = g.text_size(note)
            g.text(right - nw, ty, A(pal.text_dim, 0.9), note)
            if hot and click_button(f) == 'right' then
                f.events[#f.events + 1] = { type = 'dismiss', id = al.id }
            end
        end
    end

    if f.more and f.more > 0 then
        local label = string.format('+%d more', f.more)
        local lw = g.text_size(label)
        g.text(ox + ab.w - lw - floor(8 * s), oy + ab.h - (ab.more_h or 0) + floor(1 * s), A(pal.text_dim, 0.9), label)
    end
    return f.events
end

return ui
