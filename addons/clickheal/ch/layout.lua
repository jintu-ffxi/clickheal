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

-- Base (1080p) metrics per style.
-- btn_y: top of the spell row inside a full card.
layout.STYLES = {
    full    = { card_w = 290, card_h = 62, btn = 26, btn_gap = 3, pad = 5, btn_y = 33 },
    compact = { card_w = 320, card_h = 28, btn = 24, btn_gap = 2, pad = 4, btn_y = 2 },
    minimal = { card_w = 210, card_h = 26, btn = 24, btn_gap = 2, pad = 3, btn_y = 1 },
    strip   = { card_w = 230, card_h = 42, btn = 24, btn_gap = 2, pad = 4, btn_y = 0 },   -- job block + slim bars
    grid    = { card_w = 140, card_h = 42, btn = 24, btn_gap = 2, pad = 4, btn_y = 0 },   -- whole cell is the click target
}

layout.BUFF_H     = 11   -- buff pip strip (full style only, when show_buffs)
layout.BAR = { btn = 26, gap = 3, tab_h = 15, pad = 4, tiles = 9 }   -- shared spell bar (grid / strip)
layout.HEADER_H   = 16   -- slim title strip
layout.LABEL_H    = 13   -- per-group label (only when more than one group is shown)
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

--- Computes every rectangle the UI needs, in final screen pixels relative to the panel origin.
--
-- opts:
--   style, orientation, auto_scale, scale
--   groups : array of group indexes to show (0 = your party, 1 = alliance 1, 2 = alliance 2)
-- Returns a table; `cards[slot]` = { x, y, w, h, group, index } where slot = group * 6 + index.
function layout.compute(opts, display_h)
    local base = layout.STYLES[opts.style] or layout.STYLES.full
    local s = layout.scale(opts, display_h)
    local buff_h = ((opts.style or 'full') == 'full' and opts.show_buffs ~= false) and layout.BUFF_H or 0

    local g = {
        scale   = s,
        style   = opts.style or 'full',
        orient  = opts.orientation or 'columns',
        header_h = round(layout.HEADER_H * s),
        card_w  = round(base.card_w * s),
        card_h  = round((base.card_h + buff_h) * s),
        buff_h  = round(buff_h * s),
        btn     = round(math.max(base.btn, layout.MIN_BTN) * s),
        btn_gap = math.max(1, round(base.btn_gap * s)),
        pad     = math.max(1, round(base.pad * s)),
        btn_y   = round((base.btn_y + buff_h) * s),
        buff_y  = round(base.btn_y * s),
        gap     = math.max(1, round(layout.CARD_GAP * s)),
        group_gap = round(layout.GROUP_GAP * s),
        groups  = {},
        cards   = {},
    }

    local groups = opts.groups
    if not groups or #groups == 0 then groups = { 0 } end
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

    -- Shared spell bar under the cells (Grid / Strip only).
    if opts.spellbar and (g.style == 'grid' or g.style == 'strip') then
        local b = layout.BAR
        local btn = round(math.max(b.btn, layout.MIN_BTN) * s)
        local gap = math.max(1, round(b.gap * s))
        local pad = math.max(1, round(b.pad * s))
        local tab_h = round(b.tab_h * s)
        local bw = b.tiles * (btn + gap) - gap + 2 * pad
        local bh = pad + tab_h + gap + btn + pad
        local by = total_h + g.group_gap
        g.bar = { x = 0, y = by, w = bw, h = bh, btn = btn, gap = gap, pad = pad, tab_h = tab_h, tiles = b.tiles }
        total_w = math.max(total_w, bw)
        total_h = by + bh
    end

    g.width, g.height = total_w, total_h

    -- How many spell buttons fit on one card's spell row (full) or button strip (compact/minimal).
    local avail
    if g.style == 'full' then
        avail = g.card_w - 2 * g.pad
    elseif g.style == 'compact' then
        avail = round(4 * (base.btn + base.btn_gap) * s)  -- room reserved on the right
    else
        avail = round(4 * (base.btn + base.btn_gap) * s)  -- hover overlay on the right
    end
    g.max_buttons = math.max(1, math.floor((avail + g.btn_gap) / (g.btn + g.btn_gap)))
    g.buttons_w = g.max_buttons * (g.btn + g.btn_gap) - g.btn_gap
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
    local row_h, gap, pad = round(a.row_h * s), math.max(1, round(a.gap * s)), round(a.pad * s)
    local more_h = has_more and round(16 * s) or 0   -- room for the "+N more" note inside the window
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
