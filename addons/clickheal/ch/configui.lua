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
local bindings = require('ch.bindings')

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
-- layout helpers: a label column on the left, the control on the right
-- ---------------------------------------------------------------------------------------------

local LABEL_W, CTRL_W = 200, 260
local reset_armed = false

--- Positions the next widget in the control column, after its label.
local function label(text, tip)
    imgui.Text(text)
    if tip and imgui.IsItemHovered() then imgui.SetTooltip(tip) end
    imgui.SameLine(LABEL_W)
    imgui.SetNextItemWidth(CTRL_W)
end

local function hint(text)
    with_color(DIM, function() imgui.TextWrapped(text) end)
end

local function section(title)
    imgui.Spacing()
    imgui.TextColored(ACCENT, string.upper(title))
    imgui.Separator()
end

local function checkbox(text, tbl, key, tip)
    label(text, tip)
    local t = { tbl[key] and true or false }
    if imgui.Checkbox('##' .. key, t) then
        tbl[key] = t[1]
        return true
    end
    return false
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
local function combo(text, tbl, key, options, tip)
    label(text, tip)
    local current_text = tostring(tbl[key])
    for _, o in ipairs(options) do
        if o[1] == tbl[key] then current_text = o[2] end
    end
    local changed = false
    if imgui.BeginCombo('##' .. key, current_text) then
        for _, o in ipairs(options) do
            if imgui.Selectable(o[2] .. '##' .. key .. o[1], o[1] == tbl[key]) then
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

local STYLE_OPTIONS = {
    { 'full',    'Full - job, bars, distance, spell row' },
    { 'compact', 'Compact - one line per member' },
    { 'minimal', 'Minimal - spells appear on hover' },
    { 'grid',    'Grid - click the cell itself, bars fill the cell' },
    { 'strip',   'Strip - job block, HP bar row, debuff icons' },
}
local MODE_OPTIONS = {
    { 'party',     'Party only (6)' },
    { 'alliance1', 'Party + 1 alliance party (12)' },
    { 'alliance2', 'Party + 2 alliance parties (18)' },
}
local ORIENT_OPTIONS = {
    { 'columns', 'Side by side (each party is a column)' },
    { 'stacked', 'Stacked (one tall column)' },
    { 'rows',    'Rows (each party is a horizontal strip)' },
}
local COLOR_OPTIONS = {
    { 'modern',     'Modern - neutral, color only for status' },
    { 'mono',       'Mono - greyscale, even calmer' },
    { 'colorblind', 'Color-blind friendly' },
}
local JOB_OPTIONS = {
    { 'text', 'Text - WHM/SCH 75' },
    { 'tag',  'Tag - job chip + sub job' },
}

local function page_layout(s, ctx)
    local changed = false
    section('Frame')
    changed = combo('Layout', s, 'style', STYLE_OPTIONS, 'How each party member is drawn.') or changed
    changed = combo('Members shown', s, 'mode', MODE_OPTIONS) or changed
    changed = combo('Arrangement', s, 'orientation', ORIENT_OPTIONS) or changed
    changed = checkbox('Hide empty parties', s, 'hide_empty_groups') or changed
    changed = checkbox('Show empty slots', s, 'show_empty_slots') or changed

    section('Size')
    changed = checkbox('Follow game resolution', s, 'auto_scale', '1080p = 1x, 4K = 2x.') or changed
    changed = slider(s.auto_scale and 'Size multiplier' or 'Size (absolute)', s, 'scale', 0.5, 3.0, '%.2f',
        'You can also drag the corner of the window while it is unlocked.') or changed
    changed = slider('Text size', s, 'font_mult', 0.6, 2.0) or changed
    changed = slider('Opacity', s, 'opacity', 0.2, 1.0) or changed
    if ctx.geom then
        local g = ctx.geom
        hint(string.format('Now %d x %d px (%.1f%% x %.1f%% of the %d x %d screen), effective scale %.2f.',
            g.width, g.height, g.width / ctx.disp_w * 100, g.height / ctx.disp_h * 100, ctx.disp_w, ctx.disp_h, g.scale))
    end

    section('Position')
    changed = checkbox('Locked', s, 'locked', 'Locked = clicks cast. Unlocked = drag the window and its corner.') or changed
    label('Frame position')
    if imgui.Button('Reset to default##resetpos') then
        s.pos = { x = chconfig.defaults.pos.x, y = chconfig.defaults.pos.y }
        s.alert_pos = nil
        ctx.force_pos()
        changed = true
    end
    return changed
end

local function page_appearance(s)
    local changed = false
    section('Colors')
    changed = combo('Palette', s, 'colors', COLOR_OPTIONS) or changed

    section('Rows')
    changed = slider_int('Row slant (0 = square)', s, 'slant', 0, 16, 'Strip layout only. 0 gives clean rounded rows.') or changed
    changed = checkbox('Show job and sub job', s, 'show_job') or changed
    changed = combo('Job display', s, 'job_style', JOB_OPTIONS) or changed
    changed = checkbox('Show distance', s, 'show_dist') or changed
    changed = checkbox('Show MP bar', s, 'show_mp') or changed

    section('Buffs')
    changed = checkbox('Buff pips under the HP bar', s, 'show_buffs', 'Full layout only.') or changed
    changed = checkbox('Only buffs my job can cast', s, 'buffs_mine_only') or changed
    changed = checkbox('Seconds left on pips', s, 'show_timers') or changed
    changed = checkbox('Spell row shows buffs', s, 'buff_mode', 'Also: the HEAL/BUFF switch in the title bar.') or changed
    return changed
end

local function page_flyout(s)
    local changed = false
    section('Hover flyout')
    changed = checkbox('Open on hover', s, 'flyout', 'Hover a member to open their spell buttons beside the row.') or changed
    changed = slider_int('Button size', s, 'fly_btn', 24, 64, 'In pixels at 1080p; scales with the game resolution.') or changed
    changed = slider_int('Button spacing', s, 'fly_gap', 2, 16) or changed

    section('Other ways to cast')
    changed = checkbox('Shared spell bar', s, 'spellbar', 'Pick a spell, then click a member.') or changed
    changed = checkbox('Cast on a plain row click', s, 'cell_binds', 'Uses the Bindings page.') or changed

    section('Heal range')
    changed = slider('Out of range beyond (yalms)', s, 'max_range', 5.0, 30.0, '%.1f',
        'Members farther than this are grayed out and cannot be targeted.') or changed
    changed = slider('Distance turns yellow beyond', s, 'warn_range', 1.0, s.max_range, '%.1f') or changed
    return changed
end

-- Spell choices for a binding: none, cleanse, then every party spell grouped by kind.
local BIND_OPTIONS
local function bind_options()
    if BIND_OPTIONS then return BIND_OPTIONS end
    local order = { cure = 1, curaga = 2, status = 3, raise = 4, regen = 5, buff = 6 }
    local keys = {}
    for key, d in pairs(spells.defs) do
        if not d.ja then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local da, db = spells.defs[a], spells.defs[b]
        local oa, ob = order[da.kind] or 9, order[db.kind] or 9
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    BIND_OPTIONS = { { '-', '(nothing)' }, { 'cleanse', 'Cleanse - the right -na/Erase for their worst debuff' } }
    for _, key in ipairs(keys) do
        BIND_OPTIONS[#BIND_OPTIONS + 1] = { key, spells.defs[key].name }
    end
    return BIND_OPTIONS
end

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

local function page_bindings(s, ctx)
    local changed = false
    section('Click bindings')
    hint('Used by the Grid layout, and by the Strip layout when "Cast on a plain row click" is on. A KO\'d member always gets Raise (left = strongest, right = cheapest). Buff mode uses the job\'s built-in buff bindings.')
    imgui.Spacing()
    local preset = ctx.preset or spells.presets.generic
    local eff = bindings.effective({ bindings = s.bindings, buff_mode = false }, preset)
    for _, slot in ipairs(bindings.SLOTS) do
        local cur = eff[slot] or '-'
        local text = tostring(cur)
        local opts = bind_options()
        for _, o in ipairs(opts) do if o[1] == cur then text = o[2] end end
        label(bindings.LABEL[slot])
        if imgui.BeginCombo('##bind_' .. slot, text) then
            for _, o in ipairs(opts) do
                if imgui.Selectable(o[2] .. '##' .. slot .. o[1], o[1] == cur) then
                    s.bindings[slot] = o[1]
                    changed = true
                end
            end
            imgui.EndCombo()
        end
    end
    imgui.Spacing()
    if imgui.Button('Reset bindings to job defaults') then
        s.bindings = {}
        changed = true
    end
    return changed
end

-- Reorder the spells in each flyout group. The order is the same for every party member.
local function page_spells(s, ctx)
    local changed = false
    section('Spell order')
    hint('The order of the buttons in the hover flyout (same for every member). ^ and v move a spell, x removes it, and "Add" at the bottom of a group adds one you know.')
    local preset = ctx.preset or spells.presets.generic
    for _, gdef in ipairs(spells.GROUPS) do
        local id, label_text = gdef[1], gdef[2]
        local list = {}
        for i, k in ipairs(spells.group_keys(s, preset, id, ctx.player)) do list[i] = k end
        local header_open = true
        if imgui.CollapsingHeader then
            header_open = imgui.CollapsingHeader(string.format('%s  (%d)##hdr_%s', label_text, #list, id),
                _G.ImGuiTreeNodeFlags_DefaultOpen or 32)
        else
            imgui.Text(label_text)
        end
        if header_open then
            local edited = false
            local i = 1
            while i <= #list do
                local def = spells.defs[list[i]]
                imgui.Text(string.format('%2d.  %s', i, def and def.name or list[i]))
                imgui.SameLine(LABEL_W + 40 * sc)
                if i > 1 and imgui.SmallButton(string.format('^##up_%s_%d', id, i)) then
                    list[i], list[i - 1] = list[i - 1], list[i]; edited = true
                end
                imgui.SameLine()
                if i < #list and imgui.SmallButton(string.format('v##dn_%s_%d', id, i)) then
                    list[i], list[i + 1] = list[i + 1], list[i]; edited = true
                end
                imgui.SameLine()
                if imgui.SmallButton(string.format('x##rm_%s_%d', id, i)) then
                    table.remove(list, i); edited = true
                else
                    i = i + 1
                end
            end
            imgui.SetNextItemWidth(CTRL_W)
            if imgui.BeginCombo('Add##add_' .. id, '(choose a spell)') then
                for _, o in ipairs(order_options(id, ctx.player)) do
                    if imgui.Selectable(o[2] .. '##add' .. id .. o[1], false) then
                        list[#list + 1] = o[1]; edited = true
                    end
                end
                imgui.EndCombo()
            end
            if edited then s.spell_order[id] = list; changed = true end
            if s.spell_order[id] then
                imgui.SameLine()
                if imgui.Button('Reset##rs_' .. id) then
                    s.spell_order[id] = nil; changed = true
                end
            end
        end
    end
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
        local spell = info.spell and spells.defs[info.spell] and spells.defs[info.spell].name or 'no spell'
        local t = { not a.muted[key] }
        if imgui.Checkbox(string.format('%s  (%s)##debuff_%s', info.label, spell, key), t) then
            a.muted[key] = (not t[1]) or nil
            changed = true
        end
    end
    return changed
end

local function page_general(s, ctx)
    local changed = false
    section('Data')
    changed = checkbox('Demo data', s, 'demo', 'On = fake party for trying the layout. Off = your real party.') or changed
    if s.demo then
        changed = checkbox('Demo: show alliance debuffs', s, 'demo_alliance_debuffs') or changed
    end

    section('Casting')
    changed = checkbox('Click casts the spell', s, 'cast', 'Off = a click only prints what it would cast.') or changed
    if s.demo then
        with_color(WARN, function() imgui.TextWrapped('Demo data is on, so clicks never cast. Turn Demo data off first.') end)
    elseif s.cast then
        with_color(WARN, function() imgui.TextWrapped('Casting is ON: a click sends a normal /ma or /ja. Only use this where addons are allowed.') end)
    else
        hint('Casting is off. Clicks only log what they would do.')
    end

    section('Commands')
    hint('/ch  /ch lock  /ch unlock  /ch scale <n|auto>  /ch layout <style>  /ch mode <party|alliance1|alliance2>')
    hint('/ch cast  /ch demo  /ch buttons <size> [gap]  /ch slant <n>  /ch partydump  /ch apicheck  /ch help')

    section('Reset')
    if reset_armed then
        with_color(WARN, function() imgui.TextWrapped('This restores every setting to its default.') end)
        if imgui.Button('Yes, reset everything') then
            chconfig.reset(s)
            ctx.force_pos()
            reset_armed = false
            changed = true
        end
        imgui.SameLine()
        if imgui.Button('Cancel') then reset_armed = false end
    else
        if imgui.Button('Reset all settings...') then reset_armed = true end
    end
    return changed
end

M.PAGES = {
    { 'Layout',     page_layout },
    { 'Appearance', page_appearance },
    { 'Flyout',     page_flyout },
    { 'Spells',     page_spells },
    { 'Bindings',   page_bindings },
    { 'Alerts',     page_alerts },
    { 'General',    page_general },
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

--- The title row and the three quick toggles. Returns true when a setting changed.
local function draw_header(s)
    local changed = false
    imgui.TextColored(ACCENT, 'ClickHeal')
    imgui.SameLine()
    with_color(DIM, function() imgui.Text('setup') end)

    if toggle_button(s.demo and 'DEMO DATA' or 'LIVE DATA', not s.demo, 'data', GOOD) then
        s.demo = not s.demo; changed = true
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Switch between a fake demo party and your real party.') end
    imgui.SameLine()
    local casting = s.cast and not s.demo
    if toggle_button(casting and 'CASTING ON' or 'CASTING OFF', casting, 'cast', WARN) then
        s.cast = not s.cast; changed = true
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(s.demo and 'Needs live data.' or 'When on, a click really casts the spell.') end
    imgui.SameLine()
    if toggle_button(s.locked and 'LOCKED' or 'UNLOCKED', s.locked, 'lock', ACCENT) then
        s.locked = not s.locked; changed = true
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Unlock to move and resize the window.') end
    return changed
end

--- ctx = { geom, disp_w, disp_h, force_pos = function, preset, player }
-- Returns (changed, err): changed = true when any setting changed (caller saves, debounced);
-- err = a message when something threw (caller reports it once).
function M.draw(s, ctx)
    if not M.open[1] then return false, nil end

    sc = math.max(1.0, (ctx.disp_h or 1080) / layout.BASE_HEIGHT)
    LABEL_W, CTRL_W = math.floor(200 * sc), math.floor(250 * sc)
    local cond_first = _G.ImGuiCond_FirstUseEver or 4
    imgui.SetNextWindowSize({ 760 * sc, 600 * sc }, cond_first)

    local changed, first_err = false, nil
    local function fail(e) if e and not first_err then first_err = e end end

    local ncol, nvar = push_theme()
    local flags = _G.ImGuiWindowFlags_NoCollapse or 0
    local okb, visible = pcall(imgui.Begin, 'ClickHeal Setup', M.open, flags)
    if not okb then
        pop_theme(ncol, nvar)
        error(visible, 0)
    end
    if visible then
        pcall(imgui.SetWindowFontScale, sc)

        local ok, err = pcall(function()
            if draw_header(s) then changed = true end
            imgui.Spacing()

            -- Sidebar.
            local nav_w = math.floor(138 * sc)
            local nav_began, nav_vis = begin_child('##nav', nav_w, 0)
            if nav_began then
                if nav_vis then
                    local nok, nerr = pcall(function()
                        for i, p in ipairs(M.PAGES) do
                            if imgui.Selectable('  ' .. p[1] .. '##nav' .. i, M.page == i, 0, { 0, math.floor(30 * sc) }) then
                                M.page = i
                            end
                        end
                    end)
                    if not nok then fail('navigation: ' .. tostring(nerr)) end
                end
                imgui.EndChild()
            end
            imgui.SameLine()

            -- Content.
            local c_began, c_vis = begin_child('##content', 0, 0)
            if c_began then
                if c_vis then
                    local aw = xy(imgui.GetContentRegionAvail())
                    if aw and aw > 0 then CTRL_W = math.max(math.floor(160 * sc), math.floor(aw - LABEL_W - 20 * sc)) end
                    local page = M.PAGES[M.page] or M.PAGES[1]
                    local pok, res = pcall(page[2], s, ctx)
                    if pok then
                        if res then changed = true end
                    else
                        fail(page[1] .. ' page: ' .. tostring(res))
                    end
                end
                imgui.EndChild()
            end
        end)
        if not ok then fail('setup panel: ' .. tostring(err)) end
    end
    imgui.End()
    pop_theme(ncol, nvar)

    if changed then chconfig.sanitize(s) end
    return changed, first_err
end

return M
