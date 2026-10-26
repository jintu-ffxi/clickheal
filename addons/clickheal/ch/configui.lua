--[[
    ClickHeal - configui.lua
    The /ch setup panel: a dark themed window with a navigation sidebar, labelled sections and quick
    toggles along the top. Scaled with the game resolution so it stays readable at 4K. Edits the
    settings table in place and tells the caller when something changed.

    Every style/theme call is protected and always undone, so a missing function on this ImGui build
    only costs some polish, never the panel. `/ch apicheck` lists anything missing.
]]--

local imgui    = require('imgui')
local chconfig = require('ch.chconfig')
local debuffs  = require('ch.debuffs')
local spells   = require('ch.spells')
local layout   = require('ch.layout')
local fonts    = require('ch.fonts')
local commands = require('ch.commands')

local M = {}

M.open = { false }          -- ImGui wants a table for the window's open/close flag
M.page = 1                  -- selected sidebar page

function M.toggle() M.open[1] = not M.open[1] end

-- ---------------------------------------------------------------------------------------------
-- look
-- ---------------------------------------------------------------------------------------------

local ACCENT = { 0.40, 0.62, 0.95, 1.0 }
local DIM    = { 0.62, 0.65, 0.72, 1.0 }
local WARN   = { 0.96, 0.78, 0.22, 1.0 }
local GOOD   = { 0.30, 0.78, 0.46, 1.0 }
local BAD    = { 0.90, 0.36, 0.36, 1.0 }

local function mulrgb(c, k, a) return { c[1] * k, c[2] * k, c[3] * k, a or c[4] } end

local THEME_COLORS = {
    { 'ImGuiCol_WindowBg',        { 0.065, 0.075, 0.095, 0.98 } },
    { 'ImGuiCol_ChildBg',         { 0.085, 0.095, 0.120, 1.00 } },
    { 'ImGuiCol_PopupBg',         { 0.085, 0.095, 0.120, 0.99 } },
    { 'ImGuiCol_Border',          { 0.19, 0.21, 0.27, 0.90 } },
    { 'ImGuiCol_FrameBg',         { 0.125, 0.145, 0.185, 1.00 } },
    { 'ImGuiCol_FrameBgHovered',  { 0.165, 0.195, 0.255, 1.00 } },
    { 'ImGuiCol_FrameBgActive',   { 0.195, 0.235, 0.310, 1.00 } },
    { 'ImGuiCol_TitleBg',         { 0.065, 0.075, 0.095, 1.00 } },
    { 'ImGuiCol_TitleBgActive',   { 0.075, 0.090, 0.120, 1.00 } },
    { 'ImGuiCol_CheckMark',       ACCENT },
    { 'ImGuiCol_SliderGrab',      ACCENT },
    { 'ImGuiCol_SliderGrabActive', { 0.55, 0.74, 1.00, 1.00 } },
    { 'ImGuiCol_Button',          { 0.150, 0.170, 0.220, 1.00 } },
    { 'ImGuiCol_ButtonHovered',   { 0.200, 0.235, 0.310, 1.00 } },
    { 'ImGuiCol_ButtonActive',    mulrgb(ACCENT, 0.75, 1.0) },
    { 'ImGuiCol_Header',          mulrgb(ACCENT, 0.55, 0.30) },
    { 'ImGuiCol_HeaderHovered',   mulrgb(ACCENT, 0.70, 0.45) },
    { 'ImGuiCol_HeaderActive',    mulrgb(ACCENT, 0.80, 0.60) },
    { 'ImGuiCol_Separator',       { 0.19, 0.21, 0.27, 1.00 } },
    { 'ImGuiCol_Text',            { 0.90, 0.92, 0.95, 1.00 } },
    { 'ImGuiCol_TextDisabled',    DIM },
}

local sc = 1.0   -- UI scale for the current frame

--- Pushes the panel theme. Returns the number of colors and vars pushed (for pop_theme).
local function push_theme()
    local colors, vars = 0, 0
    for _, c in ipairs(THEME_COLORS) do
        local id = _G[c[1]]
        if id and pcall(imgui.PushStyleColor, id, c[2]) then colors = colors + 1 end
    end
    local function var(name, v)
        local id = _G[name]
        if id and pcall(imgui.PushStyleVar, id, v) then vars = vars + 1 end
    end
    var('ImGuiStyleVar_WindowRounding', 9 * sc)
    var('ImGuiStyleVar_ChildRounding', 7 * sc)
    var('ImGuiStyleVar_FrameRounding', 5 * sc)
    var('ImGuiStyleVar_GrabRounding', 5 * sc)
    var('ImGuiStyleVar_PopupRounding', 6 * sc)
    var('ImGuiStyleVar_WindowPadding', { 16 * sc, 14 * sc })
    var('ImGuiStyleVar_FramePadding', { 10 * sc, 6 * sc })
    var('ImGuiStyleVar_ItemSpacing', { 10 * sc, 9 * sc })
    return colors, vars
end

local function pop_theme(colors, vars)
    if colors > 0 then pcall(imgui.PopStyleColor, colors) end
    if vars > 0 then pcall(imgui.PopStyleVar, vars) end
end

--- Runs fn with one text color pushed (always popped).
local function with_color(color, fn)
    local id = _G.ImGuiCol_Text
    local pushed = id and pcall(imgui.PushStyleColor, id, color)
    fn()
    if pushed then pcall(imgui.PopStyleColor, 1) end
end

local function xy(a, b)
    if type(a) == 'number' then return a, b or 0 end
    if type(a) == 'table' or type(a) == 'userdata' then
        local ok1, x = pcall(function() return a.x or a[1] end)
        local ok2, y = pcall(function() return a.y or a[2] end)
        return (ok1 and x) or 0, (ok2 and y) or 0
    end
    return 0, 0
end

-- ---------------------------------------------------------------------------------------------
-- measuring and layout helpers
--
-- Nothing here assumes a font size or window width. Labels, combo text and list rows are measured
-- with CalcTextSize, controls fill whatever room the content area has, and anything that does not
-- fit side by side drops below its label (or is cut short with "..") instead of running off the edge.
-- ---------------------------------------------------------------------------------------------

local MARGIN = 18               -- base px kept free on the right of the content area (scrollbar and air)

local label_w, ctrl_w, full_w = 200, 260, 400   -- current page's columns, in pixels (set every frame)
local stacked = false           -- narrow content: every control sits under its label
local widest, widest_prev = 0, 0
local reset_armed = false

local function text_w(text)
    local ok, a, b = pcall(imgui.CalcTextSize, text)
    if ok then
        local w = xy(a, b)
        if w and w > 0 then return w end
    end
    return #text * 7 * sc
end

--- Height of one line of text at the current font.
local function text_h()
    local ok, a, b = pcall(imgui.CalcTextSize, 'Ag')
    if ok then
        local _, h = xy(a, b)
        if h and h > 0 then return h end
    end
    return 16 * sc
end

--- Shortens `text` with ".." so it fits in `maxw` pixels.
local function clip(text, maxw)
    if text_w(text) <= maxw then return text end
    local lo, hi = 0, #text
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if text_w(text:sub(1, mid) .. '..') <= maxw then lo = mid else hi = mid - 1 end
    end
    return text:sub(1, lo) .. '..'
end

--- Sets the columns for this frame from the room the content area really has.
local function set_columns(avail)
    full_w = math.max(120 * sc, math.floor(avail - MARGIN * sc))
    stacked = full_w < 360 * sc
    -- A proportional gap as well as a fixed one: with scaled fonts the measured width can run a little short.
    label_w = math.min(math.floor(full_w * 0.46), math.max(120 * sc, math.floor(widest_prev * 1.08 + 24 * sc)))
    ctrl_w = math.max(90 * sc, math.floor(full_w - label_w))
end

--- Draws the label and positions the next widget: beside it when both fit, else on the next line.
-- Returns the width the control will get.
local function label(text, tip)
    local shown = clip(text, full_w)
    local tw = text_w(shown)
    if tw > widest then widest = tw end
    imgui.Text(shown)
    if imgui.IsItemHovered() then
        if tip then imgui.SetTooltip(tip) elseif shown ~= text then imgui.SetTooltip(text) end
    end
    if stacked or tw * 1.08 + 16 * sc > label_w then
        imgui.SetNextItemWidth(full_w)
        return full_w
    end
    imgui.SameLine(label_w)
    imgui.SetNextItemWidth(ctrl_w)
    return ctrl_w
end

-- ImGui's Text calls take printf-style text here, so a literal % must be doubled.
local function esc(text) return (tostring(text):gsub('%%', '%%%%')) end

local function hint(text)
    with_color(DIM, function() imgui.TextWrapped(esc(text)) end)
end

local function warn_text(text)
    with_color(WARN, function() imgui.TextWrapped(esc(text)) end)
end

local function section(title)
    imgui.Spacing()
    with_color(ACCENT, function() imgui.TextWrapped(esc(string.upper(title))) end)   -- wraps, never cut
    imgui.Separator()
end

-- The box comes first and its text follows on the same line, wrapping when the window is narrow, so a
-- checkbox and its words always stay together and are never cut short.
local function checkbox(text, tbl, key, tip)
    local t = { tbl[key] and true or false }
    local changed = false
    if imgui.Checkbox('##' .. key, t) then
        tbl[key] = t[1]
        changed = true
    end
    local box_hover = imgui.IsItemHovered()
    imgui.SameLine()
    imgui.TextWrapped(esc(text))
    if tip and (box_hover or imgui.IsItemHovered()) then imgui.SetTooltip(tip) end
    return changed
end

--- A checkbox with its text on the right, for long lists. The text is cut short if it would not fit.
local function check_row(text, id, value)
    local t = { value and true or false }
    local changed = imgui.Checkbox('##' .. id, t)
    imgui.SameLine()
    local shown = clip(text, full_w - 40 * sc)
    imgui.Text(shown)
    if shown ~= text and imgui.IsItemHovered() then imgui.SetTooltip(text) end
    return changed, t[1]
end

--- A button whose text is cut short if the content area is too narrow for it.
local function button(text, id)
    return imgui.Button(clip(text, full_w - 24 * sc) .. '##' .. id)
end

local function slider(text, tbl, key, lo, hi, fmt, tip)
    label(text, tip)
    local t = { tbl[key] }
    if imgui.SliderFloat('##' .. key, t, lo, hi, fmt or '%.2f') then
        tbl[key] = t[1]
        return true
    end
    return false
end

local function slider_int(text, tbl, key, lo, hi, tip)
    label(text, tip)
    local t = { math.floor(tbl[key] + 0.5) }
    if imgui.SliderInt('##' .. key, t, lo, hi) then
        tbl[key] = t[1]
        return true
    end
    return false
end

--- Dropdown over `options` ({ value, text } pairs). Returns true when the choice changed.
-- `id` keeps widget ids unique when the same key is edited in several places.
local function combo(text, tbl, key, options, tip, id)
    id = id or key
    local w = label(text, tip)
    local current_text = tostring(tbl[key])
    for _, o in ipairs(options) do
        if o[1] == tbl[key] then current_text = o[2] end
    end
    local changed = false
    if imgui.BeginCombo('##' .. id, clip(current_text, w - 34 * sc)) then
        for _, o in ipairs(options) do
            if imgui.Selectable(clip(o[2], w - 24 * sc) .. '##' .. id .. o[1], o[1] == tbl[key]) then
                tbl[key] = o[1]
                changed = true
            end
        end
        imgui.EndCombo()
    end
    return changed
end

--- A button that shows an on/off state with color. Returns true when clicked.
local function toggle_button(text, on, id, on_color)
    local pushed = 0
    local function push(name, c) local i = _G[name]; if i and pcall(imgui.PushStyleColor, i, c) then pushed = pushed + 1 end end
    if on then
        local c = on_color or ACCENT
        push('ImGuiCol_Button', mulrgb(c, 0.62, 1.0))
        push('ImGuiCol_ButtonHovered', mulrgb(c, 0.80, 1.0))
        push('ImGuiCol_ButtonActive', c)
    end
    local clicked = imgui.Button(text .. '##tg_' .. id)
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
    return clicked
end

-- ---------------------------------------------------------------------------------------------
-- pages
-- ---------------------------------------------------------------------------------------------

local MODE_OPTIONS = {
    { 'party',     'Party only (6)' },
    { 'alliance1', 'Party + 1 alliance (12)' },
    { 'alliance2', 'Party + 2 alliance (18)' },
}
local ORIENT_OPTIONS = {
    { 'columns', 'Side by side' },
    { 'stacked', 'Stacked' },
    { 'rows',    'Rows' },
}
local COLOR_OPTIONS = {
    { 'modern',     'Modern' },
    { 'job',        'Job colors' },
    { 'mono',       'Mono (greyscale)' },
    { 'colorblind', 'Color-blind friendly' },
}

local SKIN_OPTIONS = {
    { 'solid',    'Solid' },
    { 'hairline', 'Hairline' },
}

--- A collapsible group (closed by default). Falls back to a plain section when ImGui has no collapsing header.
local function collapsible(title)
    -- Without a collapsing header, or when its title would not fit, the group is simply always open.
    if imgui.CollapsingHeader == nil or text_w(title) + 40 * sc > full_w then section(title); return true end
    local ok, open = pcall(imgui.CollapsingHeader, title)
    return (not ok) or open == true
end

local function page_appearance(s, ctx)
    local changed = false
    section('Members')
    changed = combo('Members shown', s, 'mode', MODE_OPTIONS,
        'Alliance parties are drawn with the same strip rows as your own party.') or changed
    changed = combo('Arrangement', s, 'orientation', ORIENT_OPTIONS,
        'Side by side: a column per party. Stacked: one tall column. Rows: a horizontal strip per party.') or changed

    section('Style')
    changed = checkbox('Show title bar', s, 'show_header', 'The CLICKHEAL / MOVE / CFG bar above the rows. Off = rows only (open this panel with /ch). The bar comes back while the frames are unlocked.') or changed
    changed = combo('Row style', s, 'skin', SKIN_OPTIONS,
        'Solid: the filled HP row. Hairline: no cards, a large colored percentage and a thin HP rail.') or changed
    if s.skin == 'hairline' then
        changed = slider('Percent size', s, 'hl_pct', 1.0, 3.0, '%.2f', 'Size of the large HP percentage in the Hairline style.') or changed
    end
    changed = checkbox('Frame around each party', s, 'group_frames', 'With alliance parties shown, draws a tinted border and label around the main party, alliance 1 and alliance 2.') or changed
    if s.group_frames then
        changed = slider('Party background strength', s, 'group_alpha', 0.03, 0.5, '%.2f', 'How strong the party colors below are, in the frames and in the triage list.') or changed
        for i, name in ipairs({ 'Party color', 'Alliance 1 color', 'Alliance 2 color' }) do
            label(name, 'Background and border color for the ' .. (name:gsub(' color', '')):lower() .. '.')
            local c = s.group_colors[i]
            if imgui.ColorEdit3('##group_colors' .. i, c) then changed = true end
        end
    end
    changed = checkbox('Triage view', s, 'triage', 'One panel for whoever needs healing most, with cure buttons sized to what is missing, and a compact list of everyone else. Fine-tune it on the Triage page.') or changed
    changed = combo('Palette', s, 'colors', COLOR_OPTIONS,
        'Modern: neutral, color only for status. Job colors: each row takes its job\'s color while healthy. Mono: greyscale. Color-blind: safe status colors.') or changed

    section('Size')
    if not s.auto_scale then
        changed = checkbox('Follow game resolution', s, 'auto_scale', '1080p = 1x, 4K = 2x. Turn this back on to size the frames from your screen.') or changed
    end
    changed = slider(s.auto_scale and 'Frame zoom' or 'Frame size (absolute)', s, 'scale', 0.5, 3.0, '%.2f',
        'Makes everything in the party frames bigger or smaller. 1.00 follows your screen resolution (4K draws twice the size of 1080p).') or changed
    changed = slider('Text size', s, 'font_mult', 0.6, 2.0, '%.2f', 'Text in the party frames, on top of Frame zoom.') or changed
    changed = slider('Name size', s, 'name_scale', 0.8, 2.0, '%.2f', 'Size of the player names. The row height stays as set, so the icons shrink to make room.') or changed
    if ctx and ctx.geom and ctx.disp_w and ctx.disp_h then
        local g = ctx.geom
        hint(string.format('Now %d x %d px (%.1f%% x %.1f%% of the %d x %d screen), effective scale %.2f.',
            g.width, g.height, g.width / ctx.disp_w * 100, g.height / ctx.disp_h * 100, ctx.disp_w, ctx.disp_h, g.scale))
    end

    section('Rows')
    changed = slider_int('Row width', s, 'row_w', 160, 360, 'Width of each member row, in pixels at 1080p.') or changed
    if s.skin == 'hairline' then
        changed = slider_int('Row height', s, 'hl_row_h', 28, 90, 'Height of each member row, in pixels at 1080p. The percentage, icons and extras shrink to fit; icons hide when there is no room.') or changed
    else
        changed = slider_int('Row height', s, 'row_h', 24, 72, 'Height of each member row, in pixels at 1080p. The icons and extras shrink to fit; icons hide when there is no room.') or changed
    end
    changed = checkbox('Show distance', s, 'show_dist') or changed
    changed = checkbox('Show MP bar', s, 'show_mp') or changed
    changed = slider_int('MP bar thickness', s, 'mp_height', 2, 14, 'Height of the MP bar along the bottom of each row, in pixels at 1080p.') or changed
    changed = checkbox('Show MP percent', s, 'show_mp_pct', 'Adds the MP percentage (in the MP color) under the HP percentage. Works with or without the MP bar.') or changed
    if s.show_mp_pct then changed = slider('MP percent size', s, 'mp_pct_scale', 0.5, 1.0, '%.2f', 'Size of the MP percent relative to the HP percent. Smaller fits tight rows.') or changed end

    section('Status icons')
    changed = slider_int('Debuff icon size', s, 'debuff_icon', 10, 32, 'Icons along the bottom of each row, in pixels at 1080p.') or changed
    changed = checkbox('Show buff icon bar', s, 'show_buff_bar', 'A second strip of buff icons on each row.') or changed
    changed = slider_int('Buff icon size', s, 'buff_icon', 10, 32) or changed
    changed = checkbox('Only buffs my job can cast', s, 'buffs_mine_only', 'Hides buffs you cannot recast, such as food or other jobs\' songs.') or changed

    if collapsible('Transparency') then
        changed = slider('Row background', s, 'opacity', 0.2, 1.0, '%.2f', 'How solid each member row\'s background is.') or changed
        changed = slider('Panel background', s, 'opacity_panel', 0.0, 1.0, '%.2f', 'The backdrop behind all rows and the title strip. 0 = fully see-through.') or changed
        changed = slider('HP bar', s, 'opacity_hp', 0.2, 1.0, '%.2f', 'How solid the HP fill is.') or changed
        changed = slider('MP bar', s, 'opacity_mp', 0.2, 1.0, '%.2f', 'How solid the MP bar is.') or changed
        changed = slider('Spell menu background', s, 'opacity_flyout', 0.3, 1.0, '%.2f', 'The spell menu that opens when you hover a member.') or changed
    end
    return changed
end

local function page_flyout(s)
    local changed = false
    section('Spell menu on hover')
    changed = checkbox('Open on hover', s, 'flyout', 'Hover a member to open their spell buttons beside the row.') or changed
    changed = checkbox('Show spell icons', s, 'flyout_icons', 'Buff and cleanse buttons show the game\'s status icon (Haste, Poison...). Put your own PNGs in assets/spells/<spell key>.png to cover any spell, for example cure4.png. Spells without an icon keep their text.') or changed
    changed = slider_int('Button size', s, 'fly_btn', 24, 64, 'In pixels at 1080p; scales with the game resolution.') or changed
    changed = slider_int('Button spacing', s, 'fly_gap', 2, 16) or changed

    section('Heal range')
    changed = slider('Out of range beyond (yalms)', s, 'max_range', 5.0, 30.0, '%.1f',
        'Members farther than this are grayed out and cannot be targeted.') or changed
    changed = slider('Distance turns yellow beyond', s, 'warn_range', 1.0, s.max_range, '%.1f') or changed
    return changed
end

-- Spell choices for a binding: none, cleanse, then every party spell grouped by kind.
local BIND_OPTIONS

-- Spells that fit a flyout group and that the player has learned (everything when the level is unknown).
local function order_options(group, who)
    local keys = {}
    for key, d in pairs(spells.defs) do
        if spells.group_of(d) == group and spells.known(key, who) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local da, db = spells.defs[a], spells.defs[b]
        if da.kind ~= db.kind then return da.kind < db.kind end
        return a < b
    end)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = { key, spells.defs[key].name } end
    return out
end

-- Reorder the spells in each flyout group. The order is the same for every party member.
local function page_spells(s, ctx)
    local changed = false
    section('Spell order')
    hint('The order of the buttons in the hover flyout (same for every member). ^ and v move a spell, x removes it, and "Add" at the bottom of a group adds one you know.')
    local preset = ctx.preset or spells.presets.generic

    -- Row: number + name on the left (cut short if needed), the three small buttons at the right.
    local btns_w = 0
    for _, b in ipairs({ '^', 'v', 'x' }) do btns_w = btns_w + text_w(b) + 20 * sc + 10 * sc end
    local name_raw = full_w - btns_w - 10 * sc
    -- Names are never cut short: when the longest does not fit beside the buttons, the buttons go under the name.
    local longest = 0
    for _, gdef in ipairs(spells.GROUPS) do
        for i, k in ipairs(spells.group_keys(s, preset, gdef[1], ctx.player)) do
            local d = spells.defs[k]
            longest = math.max(longest, text_w(string.format('%2d.  %s', i, d and d.name or k)))
        end
    end
    local inline = name_raw >= longest + 8 * sc
    local name_w = inline and name_raw or full_w
    local function slot_button(text, id, on)
        if on then return imgui.SmallButton(text .. '##' .. id) end
        pcall(imgui.Dummy, { text_w(text) + 20 * sc, text_h() })   -- keeps the other buttons where they are
        return false
    end

    for _, gdef in ipairs(spells.GROUPS) do
        local id, label_text = gdef[1], gdef[2]
        local list = {}
        for i, k in ipairs(spells.group_keys(s, preset, id, ctx.player)) do list[i] = k end
        local header_open = true
        if imgui.CollapsingHeader then
            header_open = imgui.CollapsingHeader(clip(string.format('%s  (%d)', label_text, #list), full_w - 40 * sc) .. '##hdr_' .. id,
                _G.ImGuiTreeNodeFlags_DefaultOpen or 32)
        else
            imgui.Text(label_text)
        end
        if header_open then
            local edited = false
            local i = 1
            while i <= #list do
                local def = spells.defs[list[i]]
                imgui.Text(clip(string.format('%2d.  %s', i, def and def.name or list[i]), name_w - 4 * sc))
                if inline then imgui.SameLine(name_w + 6 * sc) end
                if slot_button('^', string.format('up_%s_%d', id, i), i > 1) then
                    list[i], list[i - 1] = list[i - 1], list[i]; edited = true
                end
                imgui.SameLine()
                if slot_button('v', string.format('dn_%s_%d', id, i), i < #list) then
                    list[i], list[i + 1] = list[i + 1], list[i]; edited = true
                end
                imgui.SameLine()
                if imgui.SmallButton(string.format('x##rm_%s_%d', id, i)) then
                    table.remove(list, i); edited = true
                else
                    i = i + 1
                end
            end
            local add_w = math.max(90 * sc, math.min(320 * sc, full_w - text_w('Add') - 16 * sc))
            imgui.SetNextItemWidth(add_w)
            if imgui.BeginCombo('Add##add_' .. id, clip('(choose a spell)', add_w - 34 * sc)) then
                for _, o in ipairs(order_options(id, ctx.player)) do
                    if imgui.Selectable(clip(o[2], add_w - 24 * sc) .. '##add' .. id .. o[1], false) then
                        list[#list + 1] = o[1]; edited = true
                    end
                end
                imgui.EndCombo()
            end
            if edited then s.spell_order[id] = list; changed = true end
            if s.spell_order[id] then
                if button('Reset this group', 'rs_' .. id) then
                    s.spell_order[id] = nil; changed = true
                end
            end
        end
    end
    return changed
end

local function triage_level_of(s, key)
    return require('ch.triage').level(s, key)
end

local TRIAGE_LEVELS = {
    { 'urgent',    'Urgent (top priority)' },
    { 'important', 'Important' },
    { 'off',       'Ignore' },
}

--- Every spell the triage panel can offer for the player: single-target cures, Curagas, cleanses and buffs.
local function triage_options(who)
    local out, seen = {}, {}
    for _, group in ipairs({ 'heal', 'cleanse', 'buff' }) do
        for _, o in ipairs(order_options(group, who)) do
            local d = spells.defs[o[1]]
            local ok = (group ~= 'heal') or d.kind == 'cure' or d.kind == 'curaga'
            if ok and not seen[o[1]] then seen[o[1]] = true; out[#out + 1] = o end
        end
    end
    return out
end

local function page_triage(s, ctx)
    local changed = false
    local o = s.triage_opts
    section('Triage view')
    hint('One panel for the member who needs help most, with spell buttons for them, and a compact list of everyone else.')
    changed = checkbox('Debuffs raise priority', o, 'debuffs', 'A member with a debuff you can remove can outrank a member with lower HP.') or changed
    changed = checkbox('Low HP raises priority', o, 'crit', 'A member at or below the low HP threshold (Alerts page) outranks healthier ones.') or changed
    changed = slider_int('Spell buttons', o, 'tiles', 3, 5, 'How many spell buttons the panel shows.') or changed
    changed = checkbox('Buffs and debuffs under names', o, 'list_icons', 'The list of everyone else shows the status icons under each name. The row needs enough height; raise List row height if none appear.') or changed
    changed = slider_int('List row height', o, 'list_h', 14, 48, 'Height of each row in the list of everyone else, in pixels at 1080p. With icons on, about 34 or more fits them.') or changed

    section('How each debuff counts')
    hint('Only debuffs one of your spells can remove are considered. Urgent beats low HP, Important comes after it.')
    for _, key in ipairs(debuffs.order) do
        local info = debuffs.info[key]
        if info and info.spell then
            local t = { v = triage_level_of(s, key) }
            if combo(info.label, t, 'v', TRIAGE_LEVELS, nil, 'tl_' .. key) then
                o.levels[key] = t.v; changed = true
            end
        end
    end

    section('Spells to offer first')
    hint('Your list comes first, in this order, for the featured member. A spell only shows when it applies: cures always, a cleanse when they have that debuff, a buff when they lack it. Empty = automatic.')
    local list = {}
    for i, k in ipairs(o.spells) do list[i] = k end
    local btns_w = 0
    for _, b in ipairs({ '^', 'v', 'x' }) do btns_w = btns_w + text_w(b) + 20 * sc + 10 * sc end
    local name_raw = full_w - btns_w - 10 * sc
    local name_w = math.max(80 * sc, name_raw)
    local edited = false
    local i = 1
    while i <= #list do
        local def = spells.defs[list[i]]
        imgui.Text(clip(string.format('%2d.  %s', i, def and def.name or list[i]), math.min(name_w, full_w) - 4 * sc))
        if name_raw >= 60 * sc then imgui.SameLine(name_w + 6 * sc) end   -- too narrow: the buttons wrap below the name
        if i > 1 and imgui.SmallButton(string.format('^##tup_%d', i)) then
            list[i], list[i - 1] = list[i - 1], list[i]; edited = true
        end
        imgui.SameLine()
        if i < #list and imgui.SmallButton(string.format('v##tdn_%d', i)) then
            list[i], list[i + 1] = list[i + 1], list[i]; edited = true
        end
        imgui.SameLine()
        if imgui.SmallButton(string.format('x##trm_%d', i)) then
            table.remove(list, i); edited = true
        else
            i = i + 1
        end
    end
    local add_w = math.max(90 * sc, math.min(320 * sc, full_w - text_w('Add') - 16 * sc))
    imgui.SetNextItemWidth(add_w)
    if imgui.BeginCombo('Add##tadd', clip('(choose a spell)', add_w - 34 * sc)) then
        for _, opt in ipairs(triage_options(ctx.player)) do
            if imgui.Selectable(clip(opt[2], add_w - 24 * sc) .. '##tadd' .. opt[1], false) then
                local dup = false
                for _, k in ipairs(list) do if k == opt[1] then dup = true end end
                if not dup then list[#list + 1] = opt[1]; edited = true end
            end
        end
        imgui.EndCombo()
    end
    if edited then o.spells = list; changed = true end
    if #o.spells > 0 and button('Back to automatic', 'trst') then o.spells = {}; changed = true end
    return changed
end

local function page_alerts(s)
    local changed = false
    local a = s.alerts
    section('Alert bar')
    changed = checkbox('Show the alert bar', a, 'enabled', 'A separate window listing who needs help.') or changed
    changed = checkbox('Pulse critical alerts', a, 'pulse') or changed
    changed = checkbox('Alert when a member is KO', a, 'raise_alert', 'Suggests Raise.') or changed
    changed = checkbox('Alert on low HP', a, 'hp_alert') or changed
    changed = slider_int('Low HP threshold (%)', s, 'hp_crit', 5, 95) or changed
    changed = slider_int('Alerts shown at once', a, 'max', 1, 8) or changed

    section('Debuffs that raise an alert')
    hint('Untick to silence one. The suggested cure is shown in brackets.')
    for _, key in ipairs(debuffs.order) do
        local info = debuffs.info[key]
        local sp = info.spell or info.suggest
        local spell = sp and spells.defs[sp] and spells.defs[sp].name or 'no spell'
        local did, on = check_row(string.format('%s  (%s)', info.label, spell), 'debuff_' .. key, not a.muted[key])
        if did then
            a.muted[key] = (not on) or nil
            changed = true
        end
    end
    return changed
end

local function page_casting(s)
    local changed = false
    section('Casting')
    changed = checkbox('Queue clicks while casting', s, 'queue_clicks', 'A click made mid-cast is held and sent the moment you can act, so you can click spells one after another.') or changed
    if s.demo then
        warn_text('Demo data is on, so clicks never cast. Turn it off on the Demo page.')
    else
        hint('A click sends a normal /ma or /ja. Only use this where addons are allowed.')
    end

    section('Advanced')
    changed = slider('Delay after each action (s)', s, 'cast_lockout', 0.3, 3.0, '%.1f', 'Time before the next spell or ability can start, after the cast finishes.') or changed
    changed = slider_int('Fast Cast (%)', s, 'fast_cast', 0, 80, 'Shortens the estimated cast time. Only used when the game\'s cast bar cannot be read.') or changed
    return changed
end

-- Steps instead of a slider: a slider changes the text size under the mouse while it is dragged, and the
-- layout moves with it.
local TEXT_SIZE_OPTIONS = {
    { 80, '80%' }, { 100, '100% (default)' }, { 115, '115%' }, { 130, '130%' },
    { 150, '150%' }, { 175, '175%' }, { 200, '200%' }, { 250, '250%' },
}

local function page_general(s, ctx)
    local changed = false
    section('Frames')
    changed = checkbox('Show the party frames', s, 'visible', 'Off hides the frames. /ch show and /ch hide do the same.') or changed
    changed = checkbox('Locked', s, 'locked', 'Locked = clicks cast. Unlocked = drag the window, and drag a corner grip to resize it (the parties re-flow to fit the shape).') or changed
    label('Frame position')
    if button('Reset to default', 'resetpos') then
        s.pos = { x = chconfig.defaults.pos.x, y = chconfig.defaults.pos.y }
        s.alert_pos = nil
        ctx.force_pos()
        changed = true
    end

    section('This window')
    changed = combo('Setup text size', s, 'ui_zoom', TEXT_SIZE_OPTIONS, 'Text size in this setup window (sidebar, labels, options). The window and its controls keep their size. 100 = normal. Use the frame sizes on the Appearance page for the party frames.') or changed

    section('Reset')
    if reset_armed then
        warn_text('This restores every setting to its default.')
        if button('Yes, reset everything', 'resetyes') then
            chconfig.reset(s)
            ctx.force_pos()
            reset_armed = false
            changed = true
        end
        if text_w('Yes, reset everything') + text_w('Cancel') + 64 * sc <= full_w then imgui.SameLine() end
        if button('Cancel', 'resetno') then reset_armed = false end
    else
        if button('Reset all settings...', 'resetall') then reset_armed = true end
    end
    return changed
end

local function page_demo(s)
    local changed = false
    local d = s.debug
    section('Demo mode')
    hint('A fake party for trying layouts, with no party needed. Demo members never cast.')
    changed = checkbox('Demo mode', s, 'demo', 'On = a fake party. Off = your real party. The DEMO MODE button at the top does the same.') or changed
    if s.demo then
        changed = checkbox('Show alliance debuffs', s, 'demo_alliance_debuffs', 'Pretend the alliance members have debuffs you can see.') or changed
        section('Sample status effects')
        hint('Handy for trying the icon rows and the triage priorities.')
        changed = checkbox('Give everyone debuffs', d, 'force_debuffs', 'Every demo member gets a sample set of debuffs (poison, slow, doom ...).') or changed
        changed = checkbox('Give everyone buffs', d, 'force_buffs', 'Every demo member gets a sample set of buffs (haste, protect, regen ...).') or changed
    else
        changed = checkbox('Fill empty alliance slots', s, 'demo_fill', 'Keeps your real party live and adds fake alliance members so you can try the alliance layout. Clicks on fake members only log, they never cast.') or changed
    end
    return changed
end

--- Every slash command and what it does (the same list /ch help prints).
local function page_commands()
    section('Slash commands')
    hint('Type these in the game chat. /clickheal works in place of /ch.')
    for _, c in ipairs(commands.LIST) do
        with_color(ACCENT, function() imgui.TextWrapped(esc(c[1])) end)
        with_color(DIM, function() imgui.TextWrapped(esc(c[2])) end)
        imgui.Spacing()
    end
    return false
end

local function page_spells_all(s, ctx)
    local a = page_flyout(s)
    local b = page_spells(s, ctx)
    return a or b
end

M.PAGES = {
    { 'Appearance',       page_appearance },
    { 'Spells',           page_spells_all },
    { 'Triage',           page_triage },
    { 'Alerts',           page_alerts },
    { 'Casting',          page_casting },
    { 'General',          page_general },
    { 'Demo',             page_demo },
    { 'Commands',         page_commands },
}

-- ---------------------------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------------------------

--- Begins a bordered child region. Returns (began, visible). When began is true the caller MUST
-- call imgui.EndChild(), even if visible is false.
local function begin_child(id, w, h)
    local ok, vis = pcall(imgui.BeginChild, id, { w, h }, _G.ImGuiChildFlags_Borders or 1)
    return ok, ok and vis ~= false
end

--- The title row and the three quick toggles. They wrap onto a second row when the window is narrow.
-- Returns true when a setting changed.
local function draw_header(s)
    local changed = false
    imgui.TextColored(ACCENT, 'ClickHeal')
    imgui.SameLine()
    with_color(DIM, function() imgui.Text('setup') end)

    local aw = xy(imgui.GetContentRegionAvail())
    if not aw or aw <= 0 then aw = 560 * sc end
    local used = 0
    local function place(text)
        local w = text_w(text) + 22 * sc
        if used > 0 then
            if used + 8 * sc + w <= aw then imgui.SameLine(); used = used + 8 * sc else used = 0 end
        end
        used = used + w
    end

    place('DEMO MODE')
    if toggle_button('DEMO MODE', s.demo, 'data', WARN) then
        s.demo = not s.demo; changed = true
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('On = a fake demo party that never casts. Off = your real party.') end

    local lock_text = s.locked and 'LOCKED' or 'UNLOCKED'
    place(lock_text)
    if toggle_button(lock_text, s.locked, 'lock', ACCENT) then
        s.locked = not s.locked; changed = true
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Unlock to move and resize the window.') end
    return changed
end

local last_page = 0

--- ctx = { geom, disp_w, disp_h, force_pos = function, preset, player }
-- Returns (changed, err): changed = true when any setting changed (caller saves, debounced);
-- err = a message when something threw (caller reports it once).
function M.draw(s, ctx)
    if not M.open[1] then return false, nil end

    local disp_w, disp_h = ctx.disp_w or 1920, ctx.disp_h or 1080
    -- Sizes and spacing follow the screen only. The zoom changes the text size alone; controls grow with their text.
    local win_sc = math.max(1.0, disp_h / layout.BASE_HEIGHT)
    sc = win_sc
    local font_sc = win_sc * ((s.ui_zoom or 100) / 100)
    local cond_first = _G.ImGuiCond_FirstUseEver or 4
    -- Opens at a comfortable size, never larger than the screen, and cannot be dragged smaller than
    -- the point where the page layout stops being usable.
    local win_w = math.max(520 * win_sc, math.min(760 * win_sc, disp_w - 60))
    local win_h = math.max(380 * win_sc, math.min(680 * win_sc, disp_h - 80))
    imgui.SetNextWindowSize({ win_w, win_h }, cond_first)
    pcall(imgui.SetNextWindowSizeConstraints, { math.min(520 * win_sc, disp_w - 20), math.min(380 * win_sc, disp_h - 20) },
        { disp_w, disp_h })

    local changed, first_err = false, nil
    local function fail(e) if e and not first_err then first_err = e end end

    local ncol, nvar = push_theme()
    local flags = _G.ImGuiWindowFlags_NoCollapse or 0
    local okb, visible = pcall(imgui.Begin, 'ClickHeal Setup', M.open, flags)
    if not okb then
        pop_theme(ncol, nvar)
        error(visible, 0)
    end
    local fpushed = false
    if visible then
        local fk
        fpushed, fk = fonts.push(fonts.SETUP_PX * font_sc)
        pcall(imgui.SetWindowFontScale, fpushed and fk or font_sc)

        local ok, err = pcall(function()
            if draw_header(s) then changed = true end
            imgui.Spacing()

            -- Sidebar: as wide as its longest page name.
            local nav_w = 0
            local nav_h = text_h() + 8 * sc    -- tall enough for the zoomed text
            for _, p in ipairs(M.PAGES) do nav_w = math.max(nav_w, text_w('  ' .. p[1])) end
            nav_w = math.floor(nav_w + 52 * sc)   -- text + child padding + a possible scrollbar
            local nav_began, nav_vis = begin_child('##nav', nav_w, 0)
            if nav_began then
                if nav_vis then
                    -- Tight rows: every page must fit in the sidebar without scrolling (the last ones were cut off).
                    local sp = _G.ImGuiStyleVar_ItemSpacing and pcall(imgui.PushStyleVar, _G.ImGuiStyleVar_ItemSpacing, { 10 * sc, 3 * sc })
                    local nok, nerr = pcall(function()
                        for i, p in ipairs(M.PAGES) do
                            if imgui.Selectable('  ' .. p[1] .. '##nav' .. i, M.page == i, 0, { 0, math.floor(math.max(26 * sc, nav_h)) }) then
                                M.page = i
                            end
                        end
                    end)
                    if sp then pcall(imgui.PopStyleVar, 1) end
                    if not nok then fail('navigation: ' .. tostring(nerr)) end
                end
                imgui.EndChild()
            end
            imgui.SameLine()

            -- Content.
            local c_began, c_vis = begin_child('##content', 0, 0)
            if c_began then
                if c_vis then
                    if M.page ~= last_page then widest_prev = 0; last_page = M.page end
                    local aw = xy(imgui.GetContentRegionAvail())
                    if not aw or aw <= 0 then aw = 560 * sc end
                    set_columns(aw)
                    widest = 0
                    local page = M.PAGES[M.page] or M.PAGES[1]
                    local pok, res = pcall(page[2], s, ctx)
                    if pok then
                        if res then changed = true end
                    else
                        fail(page[1] .. ' page: ' .. tostring(res))
                    end
                    widest_prev = widest
                end
                imgui.EndChild()
            end
        end)
        if not ok then fail('setup panel: ' .. tostring(err)) end
    end
    fonts.pop(fpushed)
    imgui.End()
    pop_theme(ncol, nvar)

    if changed then chconfig.sanitize(s) end
    return changed, first_err
end

return M
