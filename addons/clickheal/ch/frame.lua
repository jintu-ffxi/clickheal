--[[
    ClickHeal - frame.lua
    Turns (settings + data source + display size + time) into everything one frame needs to draw:
    the roster, layout geometry, alert list and palette. The in-game addon, the offline tests and
    the PNG preview tool all call this, so they exercise identical logic.
]]--

local layout  = require('ch.layout')
local casting = require('ch.casting')
local theme   = require('ch.theme')
local spells  = require('ch.spells')
local alerts  = require('ch.alerts')

local frame = {}

local SAMPLE_DEBUFFS = {
    { 'poison' }, { 'slow', 'paralysis' }, { 'silence' }, { 'blindness', 'poison', 'sleep' },
    { 'doom' }, { 'curse', 'weight' }, { 'bind' },
}
local SAMPLE_BUFFS = {
    { 'haste', 'protect', 'shell' }, { 'regen', 'refresh' }, { 'protect', 'shell', 'stoneskin', 'blink' },
}

--- Debug page: gives demo members sample debuffs / buffs so the status UI can be tested. Demo mode only: a live
-- party always shows its real statuses. Returns the list unchanged when no switch is on or demo mode is off; otherwise shallow copies of the members.
function frame.apply_debug(list, cfg)
    local d = cfg.debug
    if not cfg.demo or not d or not (d.force_debuffs or d.force_buffs) then return list end
    local out = {}
    for i, m in ipairs(list) do
        if m.active and not m.dead then
            local c = {}
            for k, v in pairs(m) do c[k] = v end
            if d.force_debuffs then
                c.debuffs = {}
                for _, k in ipairs(SAMPLE_DEBUFFS[(m.slot % #SAMPLE_DEBUFFS) + 1]) do c.debuffs[#c.debuffs + 1] = k end
                c.debuff_rem = c.debuff_rem or {}
                c.has_buff_data = true
            end
            if d.force_buffs then
                c.buffs = {}
                for _, k in ipairs(SAMPLE_BUFFS[(m.slot % #SAMPLE_BUFFS) + 1]) do c.buffs[#c.buffs + 1] = { key = k, rem = 60, total = 120 } end
                c.has_buff_data = true
            end
            m = c
        end
        out[i] = m
    end
    return out
end

--- source: { roster = function(t, cfg) -> array, player = function(t) -> table }
function frame.build(cfg, source, t, disp_w, disp_h, dismissed)
    local roster_list = frame.apply_debug(source.roster(t, cfg), cfg)
    local by_slot, present = {}, {}
    for _, m in ipairs(roster_list) do
        by_slot[m.slot] = m
        if m.active then present[math.floor(m.slot / 6)] = true end
    end

    local player = casting.decorate(source.player(t), t)
    local preset, preset_name = spells.preset_for(player.job, player.sub)
    -- Only what the player can use (sub job at half level, learned spells), unless they asked to see the rest greyed out.
    if not cfg.show_locked then preset = spells.fit(preset, player) end

    local groups = layout.groups_for(cfg.mode, true, present)
    local lopts = {
        orientation = cfg.orientation,
        auto_scale = cfg.auto_scale, scale = cfg.scale, groups = groups,
        row_w = cfg.row_w, row_h = (cfg.skin == 'hairline') and cfg.hl_row_h or cfg.row_h, debuff_icon = cfg.debuff_icon, buff_icon = cfg.buff_icon,
        mp_h = cfg.show_mp and cfg.mp_height or 0,
        mp_pct = cfg.show_mp_pct and cfg.mp_pct_scale or nil,
    }
    lopts.skin, lopts.triage, lopts.hl_pct, lopts.name_scale = cfg.skin, cfg.triage, cfg.hl_pct, cfg.name_scale
    lopts.tri_list_h = cfg.triage_opts and cfg.triage_opts.list_h
    lopts.tri_list_icons = cfg.triage_opts and cfg.triage_opts.list_icons
    lopts.font_mult = cfg.font_mult
    lopts.header = cfg.show_header or not cfg.locked   -- unlocking always brings the bar back so you can move and lock
    if cfg.triage then
        local shown, n = {}, 0
        for _, gi in ipairs(groups) do shown[gi] = true end
        for _, m in ipairs(roster_list) do
            if m.active and shown[math.floor(m.slot / 6)] then n = n + 1 end
        end
        lopts.triage_n = math.min(17, math.max(0, n - 1))
    end
    local geom = layout.compute(lopts, disp_h)

    local list, total = alerts.build(roster_list, cfg, preset, t, dismissed or {})
    local more = math.max(0, (total or #list) - #list)
    local rows = math.max(1, #list)
    local abar = layout.alert_bar(lopts, disp_h, rows, more > 0)

    -- Default alert bar position: horizontally centered, a bit below the top edge.
    local apos = cfg.alert_pos
    if not apos then
        apos = { x = math.floor((disp_w - abar.w) / 2), y = math.floor(disp_h * 0.12) }
    end

    return {
        cfg = cfg, pal = theme.get(cfg.colors),
        roster_list = roster_list, roster = by_slot, player = player,
        preset = preset, preset_name = preset_name,
        geom = geom, groups = groups, group_set = (function() local t2 = {}; for _, gi in ipairs(groups) do t2[gi] = true end; return t2 end)(),
        alerts = list, alert_total = total or #list, alert_more = more,
        abar = abar, alert_pos = apos,
        now = t, disp_w = disp_w, disp_h = disp_h,
    }
end

return frame
