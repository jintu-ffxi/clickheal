--[[
    ClickHeal - Ashita v4 addon
    Click-to-heal party / alliance frames for FFXI.

    PHASE 1: interface shell running on DEMO DATA ONLY.
      * It does not read party/game memory.
      * It does not send any command or packet to the game. A click only logs what it WOULD cast.
    Do not load this on a live server until the server's staff have approved it.
]]--

addon.name    = 'clickheal'
addon.author  = 'ClickHeal'
addon.version = '0.1.0'
addon.desc    = 'Click-to-heal party/alliance frames (Phase 1: UI shell with demo data only).'
addon.link    = ''

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
local mousefix = require('ch.mousefix')
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
    if res.cursor ~= nil then state.cursor = res.cursor end
    if res.party_dump then game_source.dump_status(log) end
    if res.api_check then state.api_check = true end   -- runs in the next draw frame; ImGui is not valid here
    if res.changed then
        chconfig.sanitize(cfg)
        settings.save()
    end
end)

-- ---------------------------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------------------------

-- Debug page 'Log clicks': one chat line per mouse click saying which window saw it.
local function debug_click(name, inp, rect)
    if not (cfg.debug and cfg.debug.input) or not inp.clicked then return end
    local c = inp.clicked
    if not (c.left or c.right or c.middle) then return end
    log(string.format('[input] %s window click: %s mouse=(%d,%d) window=(%d,%d %dx%d) hovered=%s',
        name, c.left and 'left' or (c.right and 'right' or 'middle'), inp.mx, inp.my,
        rect.x, rect.y, rect.w, rect.h, tostring(inp.hovered)))
end

--- /ch cursor: a crosshair at the mouse position ImGui reports, plus the numbers behind it. If the crosshair
-- sits away from the real pointer, the offset comes from the client or Windows scaling, not from ClickHeal.
-- Windows' own idea of the pointer and of the game window, to compare with ImGui's (needs ffi + user32).
local os_cursor
do
    local okf, ffi = pcall(require, 'ffi')
    if okf then
        pcall(ffi.cdef, [[
            typedef struct { long x, y; } CH_POINT;
            typedef struct { long l, t, r, b; } CH_RECT;
            int GetCursorPos(CH_POINT* p);
            int ScreenToClient(void* hwnd, CH_POINT* p);
            int GetClientRect(void* hwnd, CH_RECT* r);
            int GetSystemMetrics(int i);
            void* GetForegroundWindow(void);
            unsigned int GetDpiForWindow(void* hwnd);
        ]])
        os_cursor = function()
            local u = ffi.C
            local hwnd = u.GetForegroundWindow()
            local p, r = ffi.new('CH_POINT[1]'), ffi.new('CH_RECT[1]')
            u.GetCursorPos(p); u.GetClientRect(hwnd, r)
            local rx, ry = tonumber(p[0].x), tonumber(p[0].y)
            u.ScreenToClient(hwnd, p)
            return rx, ry, tonumber(u.GetSystemMetrics(0)), tonumber(u.GetSystemMetrics(1)),
                tonumber(p[0].x), tonumber(p[0].y), tonumber(r[0].r), tonumber(r[0].b)
        end
    end
end

local function draw_cursor()
    local dl = imgui.GetForegroundDrawList()
    local mx, my = imgui.GetMousePos()
    if type(mx) ~= 'number' then mx, my = mx.x or mx[1], mx.y or mx[2] end
    local dw, dh = gfx.display_size()
    local col = imgui.GetColorU32({ 1, 0.1, 0.9, 1 })
    dl:AddLine({ mx - 14, my }, { mx + 14, my }, col, 1)
    dl:AddLine({ mx, my - 14 }, { mx, my + 14 }, col, 1)
    local fx, fy = mousefix.factors(dw, dh)
    local cw, chh = mousefix.client_size()
    local gcol = imgui.GetColorU32({ 0.2, 1, 0.3, 1 })
    local cx, cy = mx * fx, my * fy
    dl:AddLine({ cx - 14, cy }, { cx + 14, cy }, gcol, 1)
    dl:AddLine({ cx, cy - 14 }, { cx, cy + 14 }, gcol, 1)
    local lines = {
        string.format('imgui mouse %d,%d   display %dx%d   (magenta cross)', mx, my, dw, dh),
        string.format('game window client %s   stretch %.3f x %.3f   (green cross = corrected)', cw and (cw .. 'x' .. chh) or 'unknown', fx, fy),
    }
    if os_cursor then
        local ok, rx, ry, sw, sh, cx, cy, cw, ch = pcall(os_cursor)
        if ok then
            lines[#lines + 1] = string.format('windows cursor %d,%d   screen %dx%d', rx, ry, sw, sh)
            lines[#lines + 1] = string.format('diff imgui-windows %d,%d   screen/display %.3f x %.3f', mx - rx, my - ry, sw / dw, sh / dh)
            lines[#lines + 1] = string.format('(foreground window client %d,%d of %dx%d)', cx, cy, cw, ch)
        end
    end
    for i, l in ipairs(lines) do dl:AddText({ mx + 16, my + 4 + i * 16 }, col, l) end
end

local function draw()
    if state.cursor or (cfg.debug and cfg.debug.cursor) then pcall(draw_cursor) end
    if state.api_check then
        state.api_check = nil
        apicheck.run(imgui, log)
    end
    local t = gfx.now()
    local disp_w, disp_h = gfx.display_size()
    local source = cfg.demo and demo or ((cfg.demo_fill and mixed) or game_source)

    casting.observe(t, source.castbar and source.castbar() or nil)   -- the game's own cast bar, when it can be read
    local fr = frame.build(cfg, source, t, disp_w, disp_h, state.dismissed)
    gfx.set_font_scale(fr.geom.scale * cfg.font_mult)
    gfx.set_mouse_fix(cfg.mouse_fix)

    local events = {}
    local base = {
        gfx = gfx, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, roster_list = fr.roster_list, group_set = fr.group_set, groups = fr.groups, player = fr.player,
        preset = fr.preset, now = t, events = events, disp_w = disp_w, disp_h = disp_h,
    }

    if cfg.visible then
        -- Roster panel.
        local px, py = gfx.begin_surface('ClickHeal', cfg.pos.x, cfg.pos.y, fr.geom.width, fr.geom.height,
            { movable = not cfg.locked, force_pos = state.force_pos, back = true })
        if px then
            local f = {}
            for k, v in pairs(base) do f[k] = v end
            f.ox, f.oy = px, py
            f.input = gfx.input()
            f.input.interactive = cfg.locked
            debug_click('roster', f.input, { x = px, y = py, w = fr.geom.width, h = fr.geom.height })
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
                local f = {}
                for k, v in pairs(base) do f[k] = v end
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
        local pf = {}
        for k, v in pairs(base) do pf[k] = v end
        pf.input = nil
        local plan = ui.flyout_plan(pf)
        if plan then
            local fx, fy = gfx.begin_surface('ClickHeal Flyout', plan.x, plan.y, plan.w, plan.h,
                { movable = false, force_pos = true })
            if fx then
                local f = {}
                for k, v in pairs(base) do f[k] = v end
                f.ox, f.oy, f.plan = fx, fy, plan
                f.input = gfx.input()
                f.input.interactive = true
                debug_click('FLYOUT', f.input, { x = fx, y = fy, w = plan.w, h = plan.h })
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
