--[[
    ClickHeal - layout.lua
    Pure geometry: resolution scaling, card sizes and screen footprint. No ImGui, no Ashita.

    All base sizes below are in "1080p pixels". Everything is multiplied by one scale factor:
        scale = (game window height / 1080) * user multiplier
    so a 4K window (2160 high) gets 2.0 automatically and the UI keeps the same proportions.
]]--

local layout = {}

layout.BASE_HEIGHT = 1080
layout.PARTY_SIZE  = 6

-- Base (1080p) metrics of one strip row: a job block, then the HP-fill row with debuff icons below.
layout.STRIP = { card_w = 230, card_h = 42, pad = 4, text_h = 22 }   -- text_h: name line + gaps above the icon strip

-- Triage view (base px): the featured member's panel, then a compact list of everyone else.
layout.TRI = { pad = 6, gap = 6, head_h = 24, bar_h = 14, tile_h = 34, list_h = 18, list_gap = 2 }

layout.HEADER_H   = 16   -- slim title strip
layout.LABEL_H    = 18   -- per-group label (only when more than one group is shown)
layout.CARD_GAP   = 4
layout.GROUP_GAP  = 8
layout.MIN_BTN    = 24   -- smallest allowed spell button (base px); keeps click targets usable

-- Alert bar metrics (base px).
layout.ALERT = { w = 400, row_h = 30, gap = 3, pad = 4 }

--- Scale factor for a given game window height.
-- opts.auto_scale: follow the window height; opts.scale: user multiplier (absolute when auto is off).
function layout.scale(opts, display_h)
    local mult = opts.scale or 1.0
    if opts.auto_scale == false then return mult end
    local h = display_h
    if not h or h <= 0 then h = layout.BASE_HEIGHT end
    return (h / layout.BASE_HEIGHT) * mult
end

local function round(v) return math.floor(v + 0.5) end

--- What fits inside a row of the chosen height. The row height always wins: the icon sizes, the hairline
-- percentage and the MP extras shrink (or switch off) when there is not enough room. Base px.
-- Returns { debuff_icon, buff_icon, mp_h, mp_pct, hl_pct }; an icon size of 0 means the strip is hidden.
function layout.effective(opts)
    local row_h = math.max(24, opts.row_h or layout.STRIP.card_h)
    local di, bi = opts.debuff_icon or 14, opts.buff_icon or 14
    local e = { debuff_icon = di, buff_icon = bi, mp_h = opts.mp_h or 0, mp_pct = opts.mp_pct, hl_pct = opts.hl_pct or 2.0 }
    if opts.triage then return e end
    local name_extra = math.ceil(13 * math.max(0, (opts.name_scale or 1) - 1))   -- a bigger name is taller

    local function fit_icons(avail)
        local biggest = math.max(di, bi)
        if avail >= biggest then return end
        local r = math.max(0, avail) / biggest
        e.debuff_icon, e.buff_icon = math.floor(di * r), math.floor(bi * r)
        if math.max(e.debuff_icon, e.buff_icon) < 9 then e.debuff_icon, e.buff_icon = 0, 0 end
    end

    if opts.skin == 'hairline' then
        local mph = (e.mp_h > 0) and math.max(1, math.floor(e.mp_h * 0.5)) or 0
        local top = row_h - (3 + 5 + 1 + mph + 3)                 -- room above the rail
        local lh = opts.font_mult and 15 * opts.font_mult or 13   -- the real line height when it is known
        local function pct_k(mp) return (top - 2 - (mp and math.max(0, lh * mp - 3) or 0)) / lh end
        local k = pct_k(e.mp_pct)
        if e.mp_pct and k < math.min(e.hl_pct, 1.3) then e.mp_pct = nil; k = pct_k(nil) end
        e.hl_pct = math.max(1.0, math.min(e.hl_pct, k))
        fit_icons(top - 19 - name_extra)                                       -- name line + gaps above the icons
    else
        local extras = math.max(0, e.mp_h - 3)
        local avail = row_h - layout.STRIP.text_h - extras - name_extra
        if avail < 9 then e.mp_h = math.min(e.mp_h, 3); avail = row_h - layout.STRIP.text_h - name_extra end
        fit_icons(avail)
    end
    return e
end

--- Computes every rectangle the UI needs, in final screen pixels relative to the panel origin.
--
-- opts:
--   orientation, auto_scale, scale
--   groups : array of group indexes to show (0 = your party, 1 = alliance 1, 2 = alliance 2)
-- Returns a table; `cards[slot]` = { x, y, w, h, group, index } where slot = group * 6 + index.
function layout.compute(opts, display_h)
    local base = layout.STRIP
    local s = layout.scale(opts, display_h)

    local eff = layout.effective(opts)
    local row_h = math.max(24, opts.row_h or base.card_h)
    -- One line of text in base px (the game draws 15 px text times the text multiplier). Bars, tiles and strips that
    -- hold text grow with it; without a multiplier (older callers, tests) the fixed sizes below are used.
    local lh = opts.font_mult and (15 * opts.font_mult) or nil

    local g = {
        scale   = s,
        orient  = opts.orientation or 'columns',
        header_h = (opts.header == false) and 0 or round(math.max(layout.HEADER_H, lh and math.ceil(lh + 3) or 0) * s),
        card_w  = round((opts.row_w or base.card_w) * s),
        -- The row is exactly as tall as the user chose; icons, percentage and extras shrink to fit (layout.effective).
        card_h  = round(row_h * s),
        eff     = eff,
        pad     = math.max(1, round(base.pad * s)),
        gap     = math.max(1, round(layout.CARD_GAP * s)),
        group_gap = round(layout.GROUP_GAP * s),
        groups  = {},
        cards   = {},
    }

    local groups = opts.groups
    if not groups or #groups == 0 then groups = { 0 } end
    if opts.triage then groups = {} end   -- the triage panel replaces the per-member rows
    local multi = #groups > 1
    g.label_h = multi and round(layout.LABEL_H * s) or 0

    local n = layout.PARTY_SIZE
    local col_h = n * g.card_h + (n - 1) * g.gap     -- one party stacked vertically
    local row_w = n * g.card_w + (n - 1) * g.gap     -- one party laid out horizontally

    local x, y = 0, g.header_h
    local total_w, total_h = 0, g.header_h

    for gi, group in ipairs(groups) do
        local gw, gh
        if g.orient == 'rows' then gw, gh = row_w, g.card_h else gw, gh = g.card_w, col_h end
        local gx, gy = x, y

        g.groups[gi] = { index = group, x = gx, y = gy, w = gw, h = gh + g.label_h, label_h = g.label_h }

        for i = 0, n - 1 do
            local cx, cy = gx, gy + g.label_h
            if g.orient == 'rows' then cx = gx + i * (g.card_w + g.gap) else cy = cy + i * (g.card_h + g.gap) end
            g.cards[group * n + i] = { x = cx, y = cy, w = g.card_w, h = g.card_h, group = group, index = i }
        end

        total_w = math.max(total_w, gx + gw)
        total_h = math.max(total_h, gy + gh + g.label_h)

        -- Advance for the next group.
        if g.orient == 'columns' then
            x = x + gw + g.group_gap
        else
            y = y + gh + g.label_h + g.group_gap
        end
    end

    if opts.triage then
        local T = layout.TRI
        local pad, gap = round(T.pad * s), round(T.gap * s)
        local icon_h = round(math.max(opts.debuff_icon or 14, opts.buff_icon or 14) * s)
        local head_h, bar_h = round(T.head_h * s), round(T.bar_h * s)
        local tile_h = round(math.max(T.tile_h, lh and math.ceil(2 * lh + 8) or 0) * s)   -- two lines of text and padding
        local main_h = pad + head_h + gap + bar_h + gap + icon_h + gap + tile_h + pad
        local n = math.max(0, opts.triage_n or 0)
        local row_base = math.max(opts.tri_list_h or T.list_h, lh and math.ceil(lh + 2) or 0)
        if opts.tri_list_icons then   -- icons under the name need a name line plus the icons
            row_base = math.max(row_base, 24 * (opts.font_mult or 1) + 5 + math.max(opts.debuff_icon or 14, opts.buff_icon or 14))
        end
        local row, lg = round(row_base * s), math.max(1, round(T.list_gap * s))
        local list_h = (n > 0) and (n * row + (n - 1) * lg) or 0
        g.tri = {
            main = { x = 0, y = g.header_h, w = g.card_w, h = main_h, pad = pad, gap = gap,
                head_h = head_h, bar_h = bar_h, icon_h = icon_h, tile_h = tile_h },
            list = { x = 0, y = g.header_h + main_h + gap, w = g.card_w, row = row, gap = lg, n = n },
        }
        total_w = g.card_w
        total_h = g.header_h + main_h + ((n > 0) and (gap + list_h) or 0)
    end

    g.width, g.height = total_w, total_h
    return g
end

layout.FLYOUT = { btn = 36, gap = 6, pad = 9, label_w = 58, gap_to_row = 0 }

--- Geometry of the hover flyout. groups = array of { id, n } (n = tiles in that group's row).
-- Returns { w, h, btn, gap, pad, label_w, rows = { { y } ... } } in final pixels.
function layout.flyout(opts, display_h, groups)
    local s = layout.scale(opts, display_h)
    local F = layout.FLYOUT
    -- opts.fly_btn / opts.fly_gap (base px) are the user's button size and spacing.
    local btn = round(math.max(opts.fly_btn or F.btn, layout.MIN_BTN) * s)
    local gap, pad = math.max(1, round((opts.fly_gap or F.gap) * s)), math.max(1, round(F.pad * s))
    local label_w = round(F.label_w * s)
    local maxn = 1
    for _, g in ipairs(groups) do maxn = math.max(maxn, g.n) end
    local out = {
        scale = s, btn = btn, gap = gap, pad = pad, label_w = label_w, rows = {},
        w = pad * 2 + label_w + maxn * (btn + gap) - gap,
        h = pad * 2 + #groups * btn + math.max(0, #groups - 1) * gap,
        gap_to_row = round(F.gap_to_row * s),
    }
    for i = 1, #groups do out.rows[i] = { y = pad + (i - 1) * (btn + gap) } end
    return out
end

--- Where the flyout goes: beside the hovered row (right, else left), kept on screen.
-- row = { x, y, w, h } in screen pixels; fly = layout.flyout result.
function layout.flyout_position(row, fly, display_w, display_h)
    display_w = display_w or 1920; display_h = display_h or 1080
    local x = row.x + row.w + fly.gap_to_row
    if x + fly.w > display_w then x = row.x - fly.w - fly.gap_to_row end
    if x < 0 then x = 0 end
    local y = row.y - fly.pad
    if y + fly.h > display_h then y = display_h - fly.h end
    if y < 0 then y = 0 end
    return round(x), round(y)
end

--- Alert bar geometry for `rows` visible alerts.
function layout.alert_bar(opts, display_h, rows, has_more)
    local s = layout.scale(opts, display_h)
    local a = layout.ALERT
    rows = math.max(1, rows or 1)
    -- A row has to hold the spell pill: text, then its underline (the text grows with the font multiplier).
    local lh = opts.font_mult and 15 * opts.font_mult or 0
    local row_h, gap, pad = round(math.max(a.row_h, math.ceil(lh + 16)) * s), math.max(1, round(a.gap * s)), round(a.pad * s)
    local more_h = has_more and round(math.max(16, math.ceil(lh + 3)) * s) or 0   -- room for the "+N more" note inside the window
    return {
        scale = s,
        w = round(a.w * s),
        h = pad * 2 + rows * row_h + (rows - 1) * gap + more_h,
        row_h = row_h, gap = gap, pad = pad, more_h = more_h,
    }
end

--- Screen footprint as fractions of the display (for sanity-checking layouts).
function layout.footprint(g, display_w, display_h)
    return g.width / display_w, g.height / display_h
end

--- Which party groups to show: your party, plus alliances when the mode asks for them.
-- `present` (optional) is a table group -> true; empty groups are dropped when hide_empty is set.
function layout.groups_for(mode, hide_empty, present)
    local count = ({ party = 1, alliance1 = 2, alliance2 = 3 })[mode] or 1
    local list = {}
    for gi = 0, count - 1 do
        if gi == 0 or not hide_empty or not present or present[gi] then
            list[#list + 1] = gi
        end
    end
    return list
end

return layout
