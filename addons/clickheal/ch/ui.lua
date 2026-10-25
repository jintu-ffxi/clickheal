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

local ui = {}

-- Transient UI state (not saved): the spell armed on the bar, waiting for a member click.
ui.state = { armed = nil, flyout = nil, row_hot = false }
function ui.reset_state() ui.state.armed = nil; ui.state.flyout = nil; ui.state.row_hot = false end
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

-- Severity -> (text color, background) for debuff badges. Only the serious ones are colored.
local function badge_colors(pal, sev)
    if sev == 1 then return theme.pack(0.08, 0.04, 0.04, 1), pal.bad end
    if sev == 2 then return theme.pack(0.10, 0.07, 0.02, 1), pal.warn end
    return pal.text, pal.btn_hot
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

local function draw_button(f, x, y, size, entry, member)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local def = entry.def
    local state, detail = spellstate.evaluate(def, member, f.player, f.cfg)
    local ready = (state == 'ready')
    local hot = hovering(f, x, y, size, size)
    local round = floor(3 * s)

    -- Tile background: flat dark; the debuff-cure / raise priority tile leans toward the accent.
    local bg = hot and pal.btn_hot or pal.btn
    if entry.priority and ready then bg = theme.mix(bg, pal.accent, 0.20) end
    if not ready and state ~= 'recast' then bg = A(bg, 0.65) end
    g.rect_filled(x, y, size, size, bg, round)

    -- Thin spell-type underline.
    local lh = max(2, floor(2 * s))
    local kc = pal.kind[def.kind] or pal.accent
    g.rect_filled(x + floor(4 * s), y + size - lh - floor(3 * s), size - floor(8 * s), lh,
        A(kc, ready and 0.85 or 0.30), 0)

    if state == 'recast' then
        paint_recast(f, x, y, size, def, detail, round)
    else
        if not ready and state ~= 'nomp' then
            g.rect_filled(x, y, size, size, theme.pack(0, 0, 0, 0.35), round)
        end
        local label, col = def.short, pal.text
        if not ready then col = (state == 'nomp') and pal.mp or A(pal.text_dim, 0.8) end
        local tw, th = g.text_size(label)
        g.text(x + floor((size - tw) / 2), y + floor((size - th) / 2) - floor(2 * s), col, label)
    end

    -- Priority glow (pulsing accent outline) and hover outline.
    if entry.priority and ready then
        outline(g, x, y, size, size, max(1, floor(2 * s)), theme.alpha(pal.accent, 0.40 + 0.60 * pulse(f)))
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

local function buff_mode_on(f)
    return f.cfg.buff_mode and f.preset.buffs and #f.preset.buffs > 0
end

local function draw_button_row(f, x, y, member, count)
    local geom = f.geom
    local row
    if buff_mode_on(f) and not member.dead then
        -- Buff mode: the row offers the job's buff spells (no debuff-cure jumping to the front).
        row = spells.build_row(member, { base = f.preset.buffs, raise = f.preset.raise }, nil, count)
    else
        row = spells.build_row(member, f.preset, debuffs.info, count)
    end
    for i, entry in ipairs(row) do
        draw_button(f, x + (i - 1) * (geom.btn + geom.btn_gap), y, geom.btn, entry, member)
    end
    return #row
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

local function draw_bar(f, x, y, w, h, frac, fill, dim)
    local g, s = f.gfx, f.geom.scale
    frac = max(0, min(1, frac))
    local round = max(1, floor(2 * s))
    g.rect_filled(x, y, w, h, theme.pack(0, 0, 0, 0.45), round)
    local fw = floor(w * frac)
    if fw > 0 then g.rect_filled(x, y, max(fw, min(round * 2, w)), h, A(fill, dim), round) end
end

-- Draw right-aligned debuff badges going leftwards from `right`. Stops at `left`.
-- Most severe first, so a critical debuff is never the one hidden behind "+N".
-- Timers ("PAR 0:41") are used only when every badge still fits with them; otherwise short names.
-- Hovering the badges lists every debuff, its time left and the spell that cures it.
-- Returns the x where the badges start (so the name can use the space before it).
local function draw_debuff_chips(f, m, right, y, h, left, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local list = sorted_debuffs(m)
    if #list == 0 then return right end
    local gap = max(1, floor(3 * s))
    local pad = floor(7 * s)

    local function label_of(key, timed)
        local info = debuffs.info[key]
        local rem = m.debuff_rem and m.debuff_rem[key]
        if timed and rem then return info.short .. ' ' .. buffs.fmt(rem) end
        return info.short
    end

    -- Chips are the short tag only; the time left is in the hover list.
    local timed = false

    local x = right
    -- Width of the "+N" overflow badge; reserved whenever more badges follow the current one.
    local reserve_w = g.text_size('+9') + pad + gap
    for i, key in ipairs(list) do
        local info = debuffs.info[key]
        local label = label_of(key, timed)
        local w = g.text_size(label) + pad
        local reserve = (i < #list) and reserve_w or 0
        if x - w - reserve < left then
            -- This badge (and the rest) will not fit alongside an overflow marker: show "+N" instead.
            local extra = '+' .. (#list - i + 1)
            local ew = g.text_size(extra) + pad
            if x - ew >= left then
                x = x - ew
                chip(f, x, y, h, extra, pal.text, pal.btn_hot, dim)
                x = x - gap
            end
            break
        end
        x = x - w
        local fg, bg = badge_colors(pal, info.sev)
        chip(f, x, y, h, label, fg, bg, dim)
        x = x - gap
    end

    -- Hover: the full list, including whatever did not fit.
    if hovering(f, x + gap, y, right - x - gap, h) then
        local lines = {}
        for _, key in ipairs(list) do
            local info = debuffs.info[key]
            local rem = m.debuff_rem and m.debuff_rem[key]
            local cure = info.spell and spells.defs[info.spell] and spells.defs[info.spell].name or 'no cure'
            lines[#lines + 1] = string.format('%s%s   (%s)', info.label,
                rem and ('  ' .. buffs.fmt(rem)) or '', cure)
        end
        f.tooltip = lines
    end
    return x
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

--- Name, then the job in dim text. The long form ("WHM/SCH 99") is used when it fits, else "WHM".
local function draw_name_and_job(f, m, x, y, avail, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local gap = floor(6 * s)
    local nw = g.text_size(m.name)

    if not f.cfg.show_job then
        local name = fit(g, m.name, avail)
        g.text(x, y, name_color(f, m, dim), name)
        return
    end

    if f.cfg.job_style == 'tag' then
        local tag = jobs.abbr(m.job)
        local role_col = (pal.role and pal.role[jobs.role(m.job)]) or pal.text_dim
        local cw = g.text_size(tag) + floor(7 * s)
        local min_name = g.text_size(m.name:sub(1, 3)) + floor(4 * s)
        if avail >= cw + gap + min_name then
            local th = select(2, g.text_size('Ag'))
            chip(f, x, y - 1, th + 2, tag, role_col, pal.btn, dim)
            local nx = x + cw + gap
            local room = avail - cw - gap
            local sub = (m.sub and m.sub > 0) and ('/' .. jobs.abbr(m.sub)) or nil
            local name_w = g.text_size(m.name)
            if sub and room >= name_w + floor(4 * s) + g.text_size(sub) then
                g.text(nx, y, name_color(f, m, dim), m.name)
                g.text(nx + name_w + floor(4 * s), y, A(pal.text_dim, dim), sub)
            else
                g.text(nx, y, name_color(f, m, dim), (fit(g, m.name, room)))
            end
            return
        end
        -- no room for the tag: fall through to the plain text style
    end

    local long_job  = jobs.label(m.job, m.sub, m.level)
    local short_job = jobs.abbr(m.job)
    local lw, sw = g.text_size(long_job), g.text_size(short_job)
    local jcol = A(pal.text_dim, dim)

    if avail >= nw + gap + lw then
        g.text(x, y, name_color(f, m, dim), m.name)
        g.text(x + nw + gap, y, jcol, long_job)
    elseif avail >= nw + gap + sw then
        g.text(x, y, name_color(f, m, dim), m.name)
        g.text(x + nw + gap, y, jcol, short_job)
    else
        g.text(x, y, name_color(f, m, dim), (fit(g, m.name, avail)))
    end
end

--- Distance text, right-aligned at `right`. Returns the new right edge.
local function draw_distance(f, m, right, y, out_of_range, near_limit, dim)
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    if not f.cfg.show_dist then return right end
    local dt = dist_text(m)
    local dw = g.text_size(dt)
    right = right - dw
    local dc = out_of_range and pal.bad or (near_limit and pal.warn or pal.text_dim)
    g.text(right, y, A(dc, m.zone_diff and dim or 1), dt)
    return right - floor(8 * s)
end

--- Strip of small buff pips under the HP bar: a short label, and a thin line that shrinks as the
-- timer runs down. Amber under 30s, pulsing under 10s. Clicking a pip recasts that buff.
local function draw_buff_strip(f, m, x, y, w, dim, hh, interactive)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local list = buffs.list(m, f.cfg, f.preset)
    if #list == 0 then return end
    local h = hh or (geom.buff_h - max(1, floor(1 * s)))
    if interactive == nil then interactive = true end
    local gap = max(1, floor(2 * s))
    local round = max(1, floor(2 * s))
    local th = select(2, g.text_size('Ag'))
    local reserve_w = g.text_size('+9') + floor(7 * s) + gap
    local bx = x

    for i, b in ipairs(list) do
        local pw = g.text_size(b.info.short) + floor(7 * s)
        local more = #list - i
        if bx + pw + ((more > 0) and (reserve_w + gap) or 0) > x + w then
            local extra = '+' .. (#list - i + 1)
            local ew = g.text_size(extra) + floor(7 * s)
            if bx + ew <= x + w then
                g.rect_filled(bx, y, ew, h, A(pal.btn, dim), round)
                g.text(bx + floor(3.5 * s), y + floor((h - th) / 2) - floor(1 * s), A(pal.text_dim, dim), extra)
            end
            break
        end

        local urg = buffs.urgency(b.rem)
        local hot = interactive and hovering(f, bx, y, pw, h)
        local bg = hot and pal.btn_hot or pal.btn
        if urg == 'soon' or urg == 'urgent' then bg = theme.mix(bg, pal.warn, 0.16) end
        g.rect_filled(bx, y, pw, h, A(bg, dim), round)

        local tcol = (urg == 'none' or urg == 'long') and pal.text_dim or pal.text
        g.text(bx + floor(3.5 * s), y + floor((h - th) / 2) - floor(1 * s), A(tcol, dim), b.info.short)

        -- Timer line along the bottom of the pip.
        if b.rem and b.total and b.total > 0 then
            local lh = max(1, floor(1.5 * s))
            local frac = max(0, min(1, b.rem / b.total))
            local lw = max(1, floor((pw - floor(4 * s)) * frac))
            local lc = pal.kind.buff or pal.accent
            local la = 0.75
            if urg == 'soon' then lc = pal.warn
            elseif urg == 'urgent' then
                lc = pal.warn
                la = 0.35 + 0.65 * ((f.cfg.alerts.pulse and pulse(f)) or 1)
            end
            g.rect_filled(bx + floor(2 * s), y + h - lh - 1, lw, lh, A(lc, la * dim), 0)
        end

        if interactive then note_hitbox(f, 'buff', bx, y, pw, h, { slot = m.slot, key = b.key }) end

        if hot then
            outline(g, bx, y, pw, h, max(1, floor(1 * s)), A(pal.accent, 0.8))
            local spell_key = buffs.recast_spell(b.key, f.preset)
            local lines = { b.rem and string.format('%s   %s left', b.info.label, buffs.fmt(b.rem)) or b.info.label }
            if spell_key then
                lines[#lines + 1] = 'Click: recast ' .. spells.defs[spell_key].name .. ' on ' .. m.name
            end
            f.tooltip = lines

            if spell_key and click_button(f) == 'left' then
                local def = spells.defs[spell_key]
                local state, detail = spellstate.evaluate(def, m, f.player, f.cfg)
                f.events[#f.events + 1] = {
                    type = 'cast', via = 'buff', slot = m.slot, spell = spell_key,
                    button = 'left', mods = f.input.mods or {}, state = state, detail = detail,
                }
            end
        end
        bx = bx + pw + gap
    end
end

local function draw_full(f, m, r, out_of_range, near_limit, dim)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local pad = geom.pad
    local x0, xr = r.x + pad, r.x + r.w - pad
    local th = select(2, g.text_size('Ag'))
    local y1 = r.y + floor(5 * s)
    local ph = th + 2

    -- Row 1, right cluster: hp%, distance, debuff badges.
    local right = xr
    local hpt = hp_text(m)
    right = right - g.text_size(hpt)
    g.text(right, y1, A(hp_text_color(f, m), dim), hpt)
    right = right - floor(8 * s)
    right = draw_distance(f, m, right, y1, out_of_range, near_limit, dim)
    local chips_left = draw_debuff_chips(f, m, right, y1 - 1, ph, x0 + floor(40 * s), dim)

    -- Row 1, left: name + job.
    draw_name_and_job(f, m, x0, y1, chips_left - x0 - floor(6 * s), dim)

    -- Row 2: slim HP bar, hairline MP bar.
    local yb = r.y + floor(22 * s)
    local hb = max(3, floor(5 * s))
    local frac = (m.hpp or 0) / 100
    draw_bar(f, x0, yb, xr - x0, hb, frac, theme.hp_color(pal, frac), dim)
    if f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        draw_bar(f, x0, yb + hb + max(1, floor(1.5 * s)), xr - x0, max(2, floor(2 * s)),
            (m.mp or 0) / m.mpmax, pal.mp, dim * 0.8)
    end

    -- Row 3: buff pips (optional).
    if geom.buff_h > 0 then
        draw_buff_strip(f, m, x0, r.y + geom.buff_y, xr - x0, dim)
    end

    -- Row 4: ability tiles.
    local ys = r.y + geom.btn_y
    draw_button_row(f, x0, ys, m, geom.max_buttons)

    -- Range / zone banner over the dimmed tiles.
    local banner
    if m.zone_diff then banner = 'OTHER ZONE' elseif out_of_range then banner = 'OUT OF RANGE' end
    if banner then
        local bh = floor(16 * s)
        local by = ys + floor((geom.btn - bh) / 2)
        g.rect_filled(x0, by, xr - x0, bh, theme.pack(0.02, 0.02, 0.03, 0.88), floor(3 * s))
        local tw, tth = g.text_size(banner)
        g.text(x0 + floor((xr - x0 - tw) / 2), by + floor((bh - tth) / 2),
            m.zone_diff and pal.text_dim or pal.bad, banner)
    end
end

local function draw_compact(f, m, r, out_of_range, near_limit, dim)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local pad = geom.pad
    local x0, xr = r.x + pad, r.x + r.w - pad
    local th = select(2, g.text_size('Ag'))
    local ty = r.y + floor((r.h - th) / 2) - floor(2 * s)

    -- Tiles on the right.
    local bx = xr - geom.buttons_w
    local by = r.y + floor((r.h - geom.btn) / 2)
    draw_button_row(f, bx, by, m, geom.max_buttons)

    -- Right cluster: hp%, distance, badges.
    local right = bx - floor(8 * s)
    local hpt = hp_text(m)
    right = right - g.text_size(hpt)
    g.text(right, ty, A(hp_text_color(f, m), dim), hpt)
    right = right - floor(8 * s)
    right = draw_distance(f, m, right, ty, out_of_range, near_limit, dim)
    local chips_left = draw_debuff_chips(f, m, right, ty - 1, th + 2, x0 + floor(30 * s), dim)

    draw_name_and_job(f, m, x0, ty, chips_left - x0 - floor(6 * s), dim)

    -- Hairline HP bar under the text.
    local frac = (m.hpp or 0) / 100
    local hb = max(2, floor(3 * s))
    draw_bar(f, x0, r.y + r.h - hb - floor(4 * s), bx - floor(8 * s) - x0, hb, frac, theme.hp_color(pal, frac), dim)
end

local function draw_minimal(f, m, r, out_of_range, near_limit, dim)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local pad = geom.pad
    local x0, xr = r.x + pad, r.x + r.w - pad
    local th = select(2, g.text_size('Ag'))
    local ty = r.y + floor((r.h - th) / 2) - floor(2 * s)

    local hovered = hovering(f, r.x, r.y, r.w, r.h)
    local right = xr

    if hovered and not m.zone_diff then
        -- Hover reveals the ability tiles over the right side of the card.
        local bx = xr - geom.buttons_w
        local by = r.y + floor((r.h - geom.btn) / 2)
        g.rect_filled(bx - pad, r.y + 1, geom.buttons_w + 2 * pad, r.h - 2, theme.alpha(pal.bg, 0.95), floor(3 * s))
        draw_button_row(f, bx, by, m, geom.max_buttons)
        right = bx - pad - floor(6 * s)
    else
        local hpt = hp_text(m)
        right = right - g.text_size(hpt)
        g.text(right, ty, A(hp_text_color(f, m), dim), hpt)
        right = right - floor(8 * s)
        right = draw_distance(f, m, right, ty, out_of_range, near_limit, dim)
        right = draw_debuff_chips(f, m, right, ty - 1, th + 2, x0 + floor(60 * s), dim)
    end

    -- Name (+ job when it fits).
    draw_name_and_job(f, m, x0, ty, right - x0 - floor(6 * s), dim)

    -- Hairline HP bar along the bottom edge.
    local frac = (m.hpp or 0) / 100
    local hb = max(2, floor(2 * s))
    draw_bar(f, x0, r.y + r.h - hb - floor(3 * s), xr - x0, hb, frac, theme.hp_color(pal, frac), dim)
end

-- ------------------------------------------------------------------------------------------
-- Grid / Strip layouts: the whole cell is the click target (WoW-style click casting)
-- ------------------------------------------------------------------------------------------

--- Glow around a member who has a debuff worth curing (critical or important only).
local function cell_glow(f, m, r, dim)
    if m.dead or m.zone_diff then return end
    local list = sorted_debuffs(m)
    local top = list[1] and debuffs.info[list[1]]
    if not top or top.sev > 2 or not top.spell then return end
    local g, pal, s = f.gfx, f.pal, f.geom.scale
    local p = f.cfg.alerts.pulse and pulse(f) or 1
    outline(g, r.x, r.y, r.w, r.h, max(1, floor(1.5 * s)), A(sev_color(pal, top.sev), (0.45 + 0.45 * p) * dim))
end

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

local function job_pair(m)
    local s = jobs.abbr(m.job)
    if m.sub and m.sub > 0 then s = s .. '/' .. jobs.abbr(m.sub) end
    return s
end

--- WoW-style cell: the HP bar fills the whole cell, name on top, job/distance/% underneath,
-- debuff chips top right, buff pips beside the job, a hairline MP bar along the bottom.
local function draw_grid(f, m, r, out_of_range, near_limit, dim)
    local g, pal, geom, s = f.gfx, f.pal, f.geom, f.geom.scale
    local pad = geom.pad
    local x0, xr = r.x + pad, r.x + r.w - pad
    local th = select(2, g.text_size('Ag'))
    local inset = max(2, floor(2 * s))

    if not m.dead and not m.zone_diff then
        local frac = (m.hpp or 0) / 100
        local fw = floor((r.w - 2 * inset) * frac)
        if fw > 0 then
            g.rect_filled(r.x + inset, r.y + inset, fw, r.h - 2 * inset,
                theme.alpha(theme.hp_color(pal, frac), 0.38 * dim), floor(3 * s))
        end
    end
    cell_glow(f, m, r, dim)

    -- Line 1: name (left), debuff chips (right).
    local y1 = r.y + floor(4 * s)
    -- Chips only get the room the full name leaves free, so names are never cut short.
    local chips_left = draw_debuff_chips(f, m, xr, y1 - 1, th + 2, x0 + g.text_size(m.name) + floor(8 * s), dim)
    local name = fit(g, m.name, chips_left - x0 - floor(6 * s))
    g.text(x0, y1, name_color(f, m, dim), name)

    -- Line 2: job, buff pips, distance, hp%.
    local y2 = y1 + th + floor(2 * s)
    local right = xr
    local hpt = hp_text(m)
    right = right - g.text_size(hpt)
    g.text(right, y2, A(hp_text_color(f, m), dim), hpt)
    right = right - floor(6 * s)
    right = draw_distance(f, m, right, y2, out_of_range, near_limit, dim)

    local jt = job_pair(m)
    local jw = g.text_size(jt)
    if x0 + jw <= right then
        g.text(x0, y2, A(pal.text_dim, dim), jt)
        if f.cfg.show_buffs then
            local px = x0 + jw + floor(6 * s)
            local pw = right - px
            if pw >= floor(24 * s) then draw_buff_strip(f, m, px, y2 - 1, pw, dim, th + 2, false) end
        end
    end

    if f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        local mh = max(2, floor(3 * s))
        draw_bar(f, x0, r.y + r.h - mh - floor(3 * s), xr - x0, mh, (m.mp or 0) / m.mpmax, pal.mp, dim * 0.9)
    end

    cell_interact(f, m, r)
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
    local sl = floor((f.cfg.slant or 0) * s)      -- how far the top edge leans (0 = square rows)
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
    local aw = g.text_size(abbr)
    local fg = (f.cfg.colors == 'mono') and pal.text or theme.pack(0.07, 0.08, 0.10, 1.0)
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
            local fc, fa = theme.hp_fill(pal, frac), 0.96 * dim
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

    local name = m.name:upper()
    local nw = g.text_size(name)
    local show_d = f.cfg.show_dist and not m.is_you
    local dist_w = show_d and (g.text_size(dist_text(m)) + floor(6 * s)) or 0
    local chips_left = right

    local room = chips_left - xl - floor(4 * s)
    local shown = fit(g, name, room - dist_w)
    g.text(xl + 1, y1 + 1, theme.pack(0, 0, 0, 0.75 * dim), shown)
    g.text(xl, y1, name_color(f, m, dim), shown)
    if show_d then
        local dt = dist_text(m)
        local dx = xl + g.text_size(shown) + floor(6 * s)
        if dx + g.text_size(dt) <= chips_left then
            local dc = out_of_range and pal.bad or (near_limit and pal.warn or A(pal.text, 0.72))
            g.text(dx + 1, y1 + 1, theme.pack(0, 0, 0, 0.6 * dim), dt)
            g.text(dx, y1, A(dc, m.zone_diff and dim or 1), dt)
        end
    end

    -- A thin MP bar along the bottom edge (follows the slant). HP is the row itself.
    local mb = max(2, floor(3 * s))
    if f.cfg.show_mp and m.mpmax and m.mpmax > 0 and not m.dead then
        local ym = r.y + r.h - mb - floor(3 * s)
        local mx0, mx1 = left_at(ym + mb / 2) + pad, right_at(ym + mb / 2) - pad
        g.rect_filled(mx0, ym, mx1 - mx0, mb, theme.pack(0, 0, 0, 0.55), 1)
        local mfw = floor((mx1 - mx0) * max(0, min(1, (m.mp or 0) / m.mpmax)))
        if mfw > 0 then g.rect_filled(mx0, ym, mfw, mb, A(pal.mp, 0.95 * dim), 1) end
    end

    -- Debuff icon strip along the bottom of the row, above the MP bar.
    if not m.dead and not m.zone_diff then
        local ih = floor(14 * s)
        local iy = r.y + r.h - mb - floor(4 * s) - ih
        draw_debuff_strip(f, m, xl, iy, xr - xl, ih, dim)
    end

    cell_interact(f, m, r)
end

-- ------------------------------------------------------------------------------------------
-- Hover flyout (Grid / Strip): the hovered member's spells, in a window beside their row
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

    g.rect_filled(ox, oy, plan.w, plan.h, theme.alpha(pal.bg, 0.97), floor(5 * s))
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
    if f.tooltip then g.tooltip(f.tooltip, s) end
    return f.events
end

-- ------------------------------------------------------------------------------------------
-- Shared spell bar (Grid / Strip): pick a spell, then click a member
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

local DRAW_STYLE = { full = draw_full, compact = draw_compact, minimal = draw_minimal, grid = draw_grid, strip = draw_strip }

local function draw_member(f, m, r)
    local out_of_range, near_limit, dim = member_flags(f, m)
    card_frame(f, m, r, dim)
    local draw = DRAW_STYLE[f.geom.style] or draw_full
    draw(f, m, r, out_of_range, near_limit, dim)
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
    g.rect_filled(ox, oy, geom.width, geom.height, theme.alpha(pal.bg, f.cfg.opacity * 0.80), floor(5 * s))
    g.rect_filled(ox, oy, geom.width, geom.header_h, theme.alpha(pal.card_hot, f.cfg.opacity * 0.55), floor(5 * s))
    g.text(ox + floor(6 * s), oy + floor((geom.header_h - th) / 2), A(pal.text_dim, 0.9), 'CLICKHEAL')

    -- Heal / Buff mode switch (only for jobs that have buff spells).
    local chip_w = 0
    local flyout_layout = f.cfg.flyout and (geom.style == 'grid' or geom.style == 'strip')
    if f.preset.buffs and #f.preset.buffs > 0 and not geom.bar and not flyout_layout then
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
    do
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
    if candidates then
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

    -- Cards.
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
