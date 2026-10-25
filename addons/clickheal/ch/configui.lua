--[[
    ClickHeal - configui.lua
    The /ch setup panel. Plain ImGui widgets, scaled with the game resolution so it stays readable
    at 4K. Edits the settings table in place and tells the caller when something changed.

    UNVERIFIED AGAINST A LIVE ASHITA BUILD (see gfx_imgui.lua); `/ch apicheck` lists any widget
    functions missing on your install.
]]--

local imgui    = require('imgui')
local chconfig = require('ch.chconfig')
local debuffs  = require('ch.debuffs')
local spells   = require('ch.spells')
local layout   = require('ch.layout')
local bindings = require('ch.bindings')

local M = {}

M.open = { false }          -- ImGui wants a table for the window's open/close flag

function M.toggle() M.open[1] = not M.open[1] end

local WARN = { 0.96, 0.78, 0.22, 1.0 }
local DIM  = { 0.62, 0.65, 0.72, 1.0 }
local GOOD = { 0.30, 0.78, 0.40, 1.0 }

local reset_armed = false

-- ---------------------------------------------------------------------------------------------
-- widget helpers (each returns true when the user changed the value)
-- ---------------------------------------------------------------------------------------------

local function checkbox(label, tbl, key)
    local t = { tbl[key] and true or false }
    if imgui.Checkbox(label, t) then
        tbl[key] = t[1]
        return true
    end
    return false
end

local function slider(label, tbl, key, lo, hi, fmt)
    local t = { tbl[key] }
    if imgui.SliderFloat(label, t, lo, hi, fmt or '%.2f') then
        tbl[key] = t[1]
        return true
    end
    return false
end

local function slider_int(label, tbl, key, lo, hi)
    local t = { math.floor(tbl[key] + 0.5) }
    if imgui.SliderInt(label, t, lo, hi) then
        tbl[key] = t[1]
        return true
    end
    return false
end

--- Dropdown over `options` ({ value, text } pairs). Returns true when the choice changed.
local function combo(label, tbl, key, options)
    local current_text = tostring(tbl[key])
    for _, o in ipairs(options) do
        if o[1] == tbl[key] then current_text = o[2] end
    end
    local changed = false
    if imgui.BeginCombo(label, current_text) then
        for _, o in ipairs(options) do
            if imgui.Selectable(o[2], o[1] == tbl[key]) then
                tbl[key] = o[1]
                changed = true
            end
        end
        imgui.EndCombo()
    end
    return changed
end

local function hint(text)
    imgui.TextColored(DIM, text)
end

-- ---------------------------------------------------------------------------------------------
-- tabs
-- ---------------------------------------------------------------------------------------------

local STYLE_OPTIONS = {
    { 'full',    'Full - job, bars, distance, spell row' },
    { 'compact', 'Compact - one line per member' },
    { 'minimal', 'Minimal - spells appear on hover' },
    { 'grid',    'Grid - click the cell itself (WoW-style), bars fill the cell' },
    { 'strip',   'Strip - job block, slim bars, click the row' },
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

local function tab_layout(s, ctx)
    local changed = false
    changed = combo('Layout', s, 'style', STYLE_OPTIONS) or changed
    changed = combo('Members shown', s, 'mode', MODE_OPTIONS) or changed
    changed = combo('Arrangement', s, 'orientation', ORIENT_OPTIONS) or changed
    changed = checkbox('Hover a member to open their spell flyout (Grid / Strip)', s, 'flyout') or changed
    changed = checkbox('Shared spell bar (Grid / Strip): pick a spell, then click a member', s, 'spellbar') or changed
    changed = checkbox('Also cast the bound spell on a plain cell click (Bindings tab)', s, 'cell_binds') or changed
    changed = checkbox('Hide alliance parties that are empty', s, 'hide_empty_groups') or changed
    changed = checkbox('Show empty slots', s, 'show_empty_slots') or changed

    imgui.Separator()
    changed = checkbox('Scale automatically with game resolution', s, 'auto_scale') or changed
    changed = slider(s.auto_scale and 'Size multiplier' or 'Size (absolute)', s, 'scale', 0.5, 3.0) or changed
    changed = slider('Text size', s, 'font_mult', 0.6, 2.0) or changed
    changed = slider_int('Row slant (0 = square)', s, 'slant', 0, 16) or changed
    changed = slider_int('Flyout button size', s, 'fly_btn', 24, 64) or changed
    changed = slider_int('Flyout button spacing', s, 'fly_gap', 2, 16) or changed
    changed = slider('Opacity', s, 'opacity', 0.2, 1.0) or changed
    hint('Text size: raise this if text looks cramped or tiny; ImGui\'s default font differs between setups.')

    imgui.Separator()
    if ctx.geom then
        local g = ctx.geom
        imgui.Text(string.format('Current size: %d x %d px  (%.1f%% x %.1f%% of %d x %d)',
            g.width, g.height, g.width / ctx.disp_w * 100, g.height / ctx.disp_h * 100, ctx.disp_w, ctx.disp_h))
        imgui.Text(string.format('Effective scale: %.2f', g.scale))
    end

    imgui.Separator()
    changed = checkbox('Locked (clickable, fixed in place)', s, 'locked') or changed
    hint('Unlock to drag the frames and the alert bar to a new spot. Spell clicks are off while unlocked.')
    if imgui.Button('Reset frame positions') then
        s.pos = { x = chconfig.defaults.pos.x, y = chconfig.defaults.pos.y }
        s.alert_pos = nil
        ctx.force_pos()
        changed = true
    end
    return changed
end

local function tab_alerts(s)
    local changed = false
    local a = s.alerts
    changed = checkbox('Show the priority alert bar', a, 'enabled') or changed
    changed = checkbox('Pulse critical alerts', a, 'pulse') or changed
    changed = checkbox('Alert when a member is KO (suggest Raise)', a, 'raise_alert') or changed
    changed = checkbox('Alert on low HP', a, 'hp_alert') or changed
    changed = slider_int('Low HP threshold (%)', s, 'hp_crit', 5, 95) or changed
    changed = slider_int('Alerts shown at once', a, 'max', 1, 8) or changed

    imgui.Separator()
    imgui.Text('Heal range (yalms)')
    changed = slider('Out of range beyond', s, 'max_range', 5.0, 30.0, '%.1f') or changed
    changed = slider('Distance turns yellow beyond', s, 'warn_range', 1.0, s.max_range, '%.1f') or changed

    imgui.Separator()
    imgui.Text('Debuffs that raise an alert')
    hint('Untick to silence one. The suggested spell is shown in brackets.')
    for _, key in ipairs(debuffs.order) do
        local info = debuffs.info[key]
        local spell = info.spell and spells.defs[info.spell] and spells.defs[info.spell].name or 'no spell'
        local t = { not a.muted[key] }
        if imgui.Checkbox(string.format('%s  (%s)##debuff_%s', info.label, spell, key), t) then
            a.muted[key] = (not t[1]) or nil
            changed = true
        end
    end
    hint('Alliance members\' debuffs are only visible if the game exposes them; see README.')
    return changed
end

local JOB_OPTIONS = {
    { 'text', 'Text - WHM/SCH 99' },
    { 'tag',  'Tag - job chip + sub job' },
}

local function tab_appearance(s)
    local changed = false
    changed = combo('Colors', s, 'colors', COLOR_OPTIONS) or changed
    imgui.Separator()
    changed = checkbox('Show job / sub job', s, 'show_job') or changed
    changed = combo('Job display', s, 'job_style', JOB_OPTIONS) or changed
    imgui.Separator()
    changed = checkbox('Buff pips under the HP bar (full layout)', s, 'show_buffs') or changed
    changed = checkbox('  only buffs my job can cast', s, 'buffs_mine_only') or changed
    changed = checkbox('Seconds left on pips and debuff chips', s, 'show_timers') or changed
    changed = checkbox('Spell row shows buffs instead of heals (also: HEAL/BUFF switch in the title bar)', s, 'buff_mode') or changed
    imgui.Separator()
    changed = checkbox('Show distance', s, 'show_dist') or changed
    changed = checkbox('Show MP bar', s, 'show_mp') or changed
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

local function tab_bindings(s, ctx)
    local changed = false
    imgui.Text('Click casting for the Grid and Strip layouts')
    hint('Click anywhere on a member. A KO\'d member always gets Raise (left = strongest, right = cheapest).')
    hint('Heal mode only; buff mode uses the job\'s built-in buff bindings.')
    imgui.Separator()
    local preset = ctx.preset or spells.presets.generic
    local eff = bindings.effective({ bindings = s.bindings, buff_mode = false }, preset)
    for _, slot in ipairs(bindings.SLOTS) do
        local cur = eff[slot] or '-'
        local text = tostring(cur)
        local opts = bind_options()
        for _, o in ipairs(opts) do if o[1] == cur then text = o[2] end end
        if imgui.BeginCombo(bindings.LABEL[slot] .. '##bind_' .. slot, text) then
            for _, o in ipairs(opts) do
                if imgui.Selectable(o[2] .. '##' .. slot .. o[1], o[1] == cur) then
                    s.bindings[slot] = o[1]
                    changed = true
                end
            end
            imgui.EndCombo()
        end
    end
    imgui.Separator()
    if imgui.Button('Reset bindings to job defaults') then
        s.bindings = {}
        changed = true
    end
    return changed
end

-- Reorder the spells in each flyout group. The order is the same for every party member.
local function tab_order(s, ctx)
    local changed = false
    imgui.Text('Spell order in the hover flyout (same for every member)')
    hint('Use the arrows to move a spell, x to remove it, and the list at the bottom of a group to add one.')
    local preset = ctx.preset or spells.presets.generic
    for _, gdef in ipairs(spells.GROUPS) do
        local id, label = gdef[1], gdef[2]
        imgui.Separator()
        imgui.Text(label)
        -- Work on a copy of the effective list; store it only when the user changes something.
        local list = {}
        for i, k in ipairs(spells.group_keys(s, preset, id, ctx.player)) do list[i] = k end
        local edited = false
        local i = 1
        while i <= #list do
            local def = spells.defs[list[i]]
            imgui.Text(string.format('%d. %s', i, def and def.name or list[i]))
            imgui.SameLine()
            if i > 1 and imgui.Button(string.format('^##up_%s_%d', id, i)) then
                list[i], list[i - 1] = list[i - 1], list[i]; edited = true
            end
            imgui.SameLine()
            if i < #list and imgui.Button(string.format('v##dn_%s_%d', id, i)) then
                list[i], list[i + 1] = list[i + 1], list[i]; edited = true
            end
            imgui.SameLine()
            if imgui.Button(string.format('x##rm_%s_%d', id, i)) then
                table.remove(list, i); edited = true
            else
                i = i + 1
            end
        end
        if imgui.BeginCombo('Add spell##add_' .. id, '(choose)') then
            for _, o in ipairs(order_options(id, ctx.player)) do
                if imgui.Selectable(o[2] .. '##add' .. id .. o[1], false) then
                    list[#list + 1] = o[1]; edited = true
                end
            end
            imgui.EndCombo()
        end
        if edited then s.spell_order[id] = list; changed = true end
        if s.spell_order[id] and imgui.Button('Reset ' .. label .. '##rs_' .. id) then
            s.spell_order[id] = nil; changed = true
        end
    end
    return changed
end

local function tab_general(s, ctx)
    local changed = false
    imgui.TextColored(WARN, 'Phase 1: interface preview with demo data.')
    imgui.Text('Nothing is sent to the game and no game data is read yet.')
    imgui.Separator()
    changed = checkbox('Demo data', s, 'demo') or changed
    changed = checkbox('Demo: pretend alliance debuffs are visible', s, 'demo_alliance_debuffs') or changed
    imgui.Separator()
    imgui.Text('Commands')
    hint('/ch  /ch lock  /ch unlock  /ch scale <n|auto>  /ch layout <style>')
    hint('/ch mode <party|alliance1|alliance2>  /ch help  /ch apicheck')
    imgui.Separator()
    if reset_armed then
        imgui.TextColored(WARN, 'This restores every setting.')
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

-- ---------------------------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------------------------

--- Runs one tab's contents. EndTabItem is always called, even if the contents throw, so ImGui's
-- begin/end stack stays balanced. Returns (changed, err).
local function tab(name, fn, ...)
    if not imgui.BeginTabItem(name) then return false, nil end
    local ok, res = pcall(fn, ...)
    imgui.EndTabItem()
    if ok then return res and true or false, nil end
    return false, name .. ' tab: ' .. tostring(res)
end

--- ctx = { geom, disp_w, disp_h, force_pos = function }
-- Returns (changed, err): changed = true when any setting changed (caller saves, debounced);
-- err = a message when something threw (caller reports it once).
function M.draw(s, ctx)
    if not M.open[1] then return false, nil end

    local ui_scale = math.max(1.0, (ctx.disp_h or 1080) / layout.BASE_HEIGHT)
    local cond_first = _G.ImGuiCond_FirstUseEver or 4
    imgui.SetNextWindowSize({ 520 * ui_scale, 600 * ui_scale }, cond_first)

    local changed, first_err = false, nil
    local function note(c, e)
        if c then changed = true end
        if e and not first_err then first_err = e end
    end

    local visible = imgui.Begin('ClickHeal Setup', M.open)
    if visible then
        pcall(imgui.SetWindowFontScale, ui_scale)

        if imgui.BeginTabBar('clickheal_tabs') then
            note(tab('Layout',     tab_layout, s, ctx))
            note(tab('Alerts',     tab_alerts, s))
            note(tab('Order',      tab_order, s, ctx))
            note(tab('Bindings',   tab_bindings, s, ctx))
            note(tab('Appearance', tab_appearance, s))
            note(tab('General',    tab_general, s, ctx))
            imgui.EndTabBar()
        end
    end
    imgui.End()

    if changed then chconfig.sanitize(s) end
    return changed, first_err
end

return M
