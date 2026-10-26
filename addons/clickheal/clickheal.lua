--[[
    ClickHeal - Ashita v4 addon
    Click-to-heal party / alliance frames for FFXI.

    Draws your party and alliance, and casts a spell on a member when you click it in the hover menu.
    A click sends a normal chat command (/ma or /ja). It reads the game (party memory, status packets,
    recasts) but never sends packets or acts on its own.

    Some servers only allow approved addons. Get the server's staff to approve it before you load it there.
]]--

addon.name    = 'clickheal'
addon.author  = 'Jintu'
addon.version = '1.0.2'
addon.desc    = 'Click-to-heal party and alliance frames with a hover spell menu, alerts and triage view.'
addon.link    = 'https://github.com/jintu-ffxi/clickheal'

require('common')
local chat     = require('chat')
local settings = require('settings')
local imgui    = require('imgui')

local chconfig = require('ch.chconfig')
local commands = require('ch.commands')
local frame    = require('ch.frame')
local ui       = require('ch.ui')
local actions  = require('ch.actions')
local demo     = require('ch.source_demo')
local mixed    = require('ch.source_mixed')
local gfx      = require('ch.gfx_imgui')
local fonts    = require('ch.fonts')
local configui = require('ch.configui')
local casting  = require('ch.casting')
local chatstatus = require('ch.chatstatus')
local livebuffs  = require('ch.livebuffs')
local apicheck = require('ch.apicheck')
local spells   = require('ch.spells')

-- ---------------------------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------------------------

-- Ashita's settings library needs its own table type (T{}) for the defaults; the offline test stubs have no T.
local cfg = settings.load(T and T(chconfig.defaults) or chconfig.defaults)
chconfig.sanitize(cfg)
cfg.debug.force_debuffs, cfg.debug.force_buffs = false, false   -- sample statuses last for one session only

local state = {
    dismissed  = {},     -- alert id -> time it may reappear
    force_pos  = false,  -- apply saved positions once even while unlocked
    dirty_at   = nil,    -- time of the last unsaved change (saves are debounced)
    last_error = nil,
}

-- With demo data off, the roster comes from the game (read-only). See ch/source_game.lua.
local game_source = require('ch.source_game')

local function log(text)
    local ok = pcall(function() print(chat.header(addon.name):append(chat.message(text))) end)
    if not ok then print('[ClickHeal] ' .. tostring(text)) end
end

local function mark_dirty(t) state.dirty_at = t end

local function report_error(where, err)
    local msg = where .. ': ' .. tostring(err)
    if msg ~= state.last_error then       -- do not flood the chat log with the same error every frame
        state.last_error = msg
        log('Error in ' .. msg)
    end
end

-- ---------------------------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------------------------

ashita.events.register('load', 'clickheal_load', function()
    pcall(fonts.init)
    log('Loaded. Clicking a spell casts it on your real party (demo data never casts).')
    log('/ch opens the setup panel. /ch unlock to move the frames, /ch help for everything else.')
end)

ashita.events.register('text_in', 'clickheal_text_in', function(e)
    if e and e.message then pcall(chatstatus.feed, e.message) end
end)

-- Read-only: other members' status effects come from the server's own status packets.
ashita.events.register('packet_in', 'clickheal_packet_in', function(e)
    if e and e.id and (e.id == 0x076 or e.id == 0x029 or e.id == 0x00A) then pcall(livebuffs.feed, e.id, e.data) end
end)

ashita.events.register('unload', 'clickheal_unload', function()
    settings.save()
end)

settings.register('settings', 'clickheal_settings_update', function(s)
    if s ~= nil then cfg = s end
    chconfig.sanitize(cfg)
    settings.save()
end)

ashita.events.register('command', 'clickheal_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local head = args[1]:lower()
    if head ~= '/ch' and head ~= '/clickheal' then return end
    e.blocked = true

    local res = commands.run(args, cfg)
    for _, m in ipairs(res.messages) do log(m) end

    if res.toggle_config then configui.toggle() end
    if res.reset then
        chconfig.reset(cfg)
        state.force_pos = true
    end
    if res.show_order then
        local pl = (cfg.demo and demo or game_source).player(gfx.now())
        local preset = spells.preset_for(pl.job or 0, pl.sub or 0)
        log(res.show_order .. ': ' .. table.concat(spells.group_keys(cfg, preset, res.show_order), ' '))
    end
    if res.api_check then state.api_check = true end   -- runs in the next draw frame; ImGui is not valid here
    if res.changed then
        chconfig.sanitize(cfg)
        settings.save()
    end
end)

-- ---------------------------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------------------------

-- Game memory is sampled at SAMPLE_HZ, not every frame: HP, distance and recasts move far slower than the render
-- rate, and each sample is hundreds of protected memory reads. Frames in between draw the last sample.
local SAMPLE_HZ = 15
local held = { src = nil, at = -1, roster = nil, player = nil }
local held_source = {
    roster = function() return held.roster end,
    player = function() return held.player end,
}

local function sampled(source, t)
    if source == demo then return source end            -- the demo source is cheap and animates by time
    if held.src ~= source or t < held.at or t - held.at >= 1 / SAMPLE_HZ then
        held.src, held.at = source, t
        held.roster, held.player = source.roster(t, cfg), source.player(t)
    end
    return held_source
end

local function draw()
    if state.api_check then
        state.api_check = nil
        apicheck.run(imgui, log)
    end
    local t = gfx.now()
    local disp_w, disp_h = gfx.display_size()
    local source = cfg.demo and demo or ((cfg.demo_fill and mixed) or game_source)

    casting.observe(t, source.castbar and source.castbar() or nil)   -- the game's own cast bar, when it can be read
    local fr = frame.build(cfg, sampled(source, t), t, disp_w, disp_h, state.dismissed)
    gfx.set_font_scale(fr.geom.scale * cfg.font_mult)

    local events = {}
    local base = {
        gfx = gfx, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, roster_list = fr.roster_list, group_set = fr.group_set, groups = fr.groups, player = fr.player,
        preset = fr.preset, now = t, events = events, disp_w = disp_w, disp_h = disp_h,
    }

    local base_mt = { __index = base }   -- each window's context reads the shared frame fields through this

    if cfg.visible then
        -- Roster panel.
        local px, py = gfx.begin_surface('ClickHeal', cfg.pos.x, cfg.pos.y, fr.geom.width, fr.geom.height,
            { movable = not cfg.locked, force_pos = state.force_pos, back = true })
        if px then
            local f = setmetatable({}, base_mt)
            f.ox, f.oy = px, py
            f.input = gfx.input()
            f.input.interactive = cfg.locked
            local ok, err = pcall(ui.draw_roster, f)
            if not ok then report_error('roster', err) end
            if not cfg.locked and (px ~= cfg.pos.x or py ~= cfg.pos.y) then
                cfg.pos.x, cfg.pos.y = px, py
                mark_dirty(t)
            end
        end
        gfx.end_surface()

        -- Alert bar: shown when there are alerts, or as a draggable placeholder while unlocked.
        local placeholder = (#fr.alerts == 0) and (not cfg.locked) and cfg.alerts.enabled
        if cfg.alerts.enabled and (#fr.alerts > 0 or placeholder) then
            local ap = fr.alert_pos
            local ax, ay = gfx.begin_surface('ClickHeal Alerts', ap.x, ap.y, fr.abar.w, fr.abar.h,
                { movable = not cfg.locked, force_pos = state.force_pos, back = true })
            if ax then
                local f = setmetatable({}, base_mt)
                f.ox, f.oy = ax, ay
                f.abar, f.alerts, f.more, f.placeholder = fr.abar, fr.alerts, fr.alert_more, placeholder
                f.input = gfx.input()
                f.input.interactive = cfg.locked
                local ok, err = pcall(ui.draw_alerts, f)
                if not ok then report_error('alerts', err) end
                if not cfg.locked and (ax ~= ap.x or ay ~= ap.y) then
                    cfg.alert_pos = { x = ax, y = ay }
                    mark_dirty(t)
                end
            end
            gfx.end_surface()
        end
    end
    -- Hover flyout: a small window beside the hovered member's row (Grid / Strip layouts).
    if cfg.visible and cfg.locked and cfg.flyout then
        local pf = setmetatable({}, base_mt)
        pf.input = nil
        local plan = ui.flyout_plan(pf)
        if plan then
            local fx, fy = gfx.begin_surface('ClickHeal Flyout', plan.x, plan.y, plan.w, plan.h,
                { movable = false, force_pos = true })
            if fx then
                local f = setmetatable({}, base_mt)
                f.ox, f.oy, f.plan = fx, fy, plan
                f.input = gfx.input()
                f.input.interactive = true
                local ok, err = pcall(ui.draw_flyout, f)
                if not ok then report_error('flyout', err) end
            end
            gfx.end_surface()
        end
    elseif ui.state.flyout then
        ui.state.flyout = nil
    end
    state.force_pos = false

    -- Clicks (Phase 1: these only log and start a demo recast).
    do
        local ctx = {
            demo = cfg.demo and demo or nil, log = log, now = t,
            roster_by_slot = fr.roster, dismissed = state.dismissed,
            cfg = cfg, changed = function() mark_dirty(t) end,
            open_config = function() configui.toggle() end,
            send = function(command)
                local ok, err = pcall(function() AshitaCore:GetChatManager():QueueCommand(1, command) end)
                if not ok then report_error('cast', err) end
            end,
        }
        for _, ev in ipairs(events) do actions.perform(ev, ctx) end
        actions.run_queued(ctx, fr.player)   -- a click held while casting goes out as soon as you can act
    end

    -- Setup panel.
    local changed, cerr = configui.draw(cfg, {
        geom = fr.geom, disp_w = disp_w, disp_h = disp_h,
        force_pos = function() state.force_pos = true end,
        preset = fr.preset, player = fr.player,
    })
    if cerr then report_error('setup panel', cerr) end
    if changed then mark_dirty(t) end

    -- Debounced save: write once the user has stopped fiddling for a second.
    if state.dirty_at and (t - state.dirty_at) > 1.0 then
        settings.save()
        state.dirty_at = nil
    end
end

ashita.events.register('d3d_present', 'clickheal_present', function()
    local ok, err = pcall(draw)
    if not ok then report_error('draw', err) end
end)
