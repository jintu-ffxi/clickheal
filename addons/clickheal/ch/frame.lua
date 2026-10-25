--[[
    ClickHeal - frame.lua
    Turns (settings + data source + display size + time) into everything one frame needs to draw:
    the roster, layout geometry, alert list and palette. The in-game addon, the offline tests and
    the PNG preview tool all call this, so they exercise identical logic.
]]--

local layout  = require('ch.layout')
local theme   = require('ch.theme')
local spells  = require('ch.spells')
local alerts  = require('ch.alerts')

local frame = {}

--- source: { roster = function(t, cfg) -> array, player = function(t) -> table }
function frame.build(cfg, source, t, disp_w, disp_h, dismissed)
    local roster_list = source.roster(t, cfg)
    local by_slot, present = {}, {}
    for _, m in ipairs(roster_list) do
        by_slot[m.slot] = m
        if m.active then present[math.floor(m.slot / 6)] = true end
    end

    local player = source.player(t)
    local preset, preset_name = spells.preset_for(player.job, player.sub)
    preset = spells.fit(preset, player)   -- only what the player has learned (sub job at half level)

    local groups = layout.groups_for(cfg.mode, cfg.hide_empty_groups, present)
    local lopts = {
        style = cfg.style, orientation = cfg.orientation,
        auto_scale = cfg.auto_scale, scale = cfg.scale, groups = groups,
        show_buffs = cfg.show_buffs, spellbar = cfg.spellbar,
    }
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
        geom = geom, groups = groups,
        alerts = list, alert_total = total or #list, alert_more = more,
        abar = abar, alert_pos = apos,
        now = t, disp_w = disp_w, disp_h = disp_h,
    }
end

return frame
