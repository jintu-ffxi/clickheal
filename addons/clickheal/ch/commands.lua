--[[
    ClickHeal - commands.lua
    The /ch command line. Pure: takes an args array and the settings table, returns what happened.

    run(args, s) -> { messages = { ... }, changed = bool, toggle_config = bool, reset = bool }
    `args` is the split command line, e.g. { '/ch', 'scale', '1.5' }.
]]--

local chconfig = require('ch.chconfig')

local commands = {}

local HELP = {
    '/ch                      open / close the setup panel',
    '/ch show | hide          show or hide the frames',
    '/ch lock | unlock        lock = clickable, unlock = drag to move',
    '/ch scale <0.5-4|auto>   size multiplier (auto = follow game resolution)',
    '/ch mode <party|alliance1|alliance2>   (or 6 / 12 / 18)',
    '/ch orient <columns|stacked|rows>',
    '/ch demo [on|off]        demo data (off = your real party)',
    '/ch status               show the switches that decide what hover and clicks do',
    '/ch reset confirm        restore every setting to defaults',
    '/ch apicheck             check which Ashita/ImGui calls this install supports',
    '/ch partydump            print the raw party status-icon data (for debuff icon support)',
    '/ch cursor [on|off]     draw a crosshair at the mouse position ImGui sees (for debugging offset clicks)',
}

local function lower(v) return v and tostring(v):lower() or nil end

local MODE_ALIAS = { ['6'] = 'party', ['12'] = 'alliance1', ['18'] = 'alliance2' }

local function onoff(arg, current)
    local a = lower(arg)
    if a == 'on' or a == 'true' or a == '1' then return true end
    if a == 'off' or a == 'false' or a == '0' then return false end
    return not current
end

local function in_list(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

function commands.run(args, s)
    local out = { messages = {}, changed = false, toggle_config = false, reset = false }
    local function say(t) out.messages[#out.messages + 1] = t end

    local cmd = lower(args[2])
    local a3  = args[3]

    if cmd == nil or cmd == 'config' or cmd == 'setup' then
        out.toggle_config = true

    elseif cmd == 'status' then
        local function yn(v) return v and 'on' or 'off' end
        say(string.format('shown: %s   locked: %s   hover menu: %s   demo data: %s   click queue: %s',
            yn(s.visible), yn(s.locked), yn(s.flyout), yn(s.demo), yn(s.queue_clicks)))
        local live = require('ch.livebuffs')
        say(string.format('status effects: %d members from game data, %d from chat   chat lines seen: %d',
            live.count(), require('ch.chatstatus').count(), require('ch.chatstatus').seen))
        local cs = require('ch.chatstatus')
        if cs.last_raw then
            say('last "effect" line, raw bytes: ' .. cs.last_raw:gsub('[^\32-\126]', function(c) return '<' .. c:byte() .. '>' end))
        end
        if not s.locked then say('The hover menu only works while LOCKED. /ch lock') end
        if not s.flyout then say('The hover spell menu is off (Spells page).') end
        if not s.visible then say('Frames are hidden. /ch show') end

    elseif cmd == 'help' or cmd == '?' then
        for _, l in ipairs(HELP) do say(l) end

    elseif cmd == 'show' then
        s.visible = true; out.changed = true; say('Frames shown.')
    elseif cmd == 'hide' then
        s.visible = false; out.changed = true; say('Frames hidden. /ch show to bring them back.')

    elseif cmd == 'lock' then
        s.locked = true; out.changed = true; say('Locked: frames are clickable and fixed in place.')
    elseif cmd == 'unlock' then
        s.locked = false; out.changed = true; say('Unlocked: drag the frames to move them. Clicking spells is off until you /ch lock.')

    elseif cmd == 'scale' then
        if lower(a3) == 'auto' then
            s.auto_scale = true; s.scale = 1.0; out.changed = true
            say('Scale: auto (follows game resolution), multiplier 1.0')
        else
            local n = tonumber(a3)
            if not n or n < 0.5 or n > 4 then
                say('Usage: /ch scale <0.5-4>  or  /ch scale auto')
            else
                s.scale = n; out.changed = true
                say(string.format('Scale multiplier: %.2f (%s)', n, s.auto_scale and 'on top of auto scale' or 'absolute'))
            end
        end

    elseif cmd == 'mode' then
        local v = lower(a3)
        v = MODE_ALIAS[v or ''] or v
        if v and in_list(chconfig.enums.mode, v) then
            s.mode = v; out.changed = true; say('Mode: ' .. v)
        else
            say('Usage: /ch mode <party|alliance1|alliance2>  (or 6 / 12 / 18)')
        end

    elseif cmd == 'orient' or cmd == 'orientation' then
        local v = lower(a3)
        if v and in_list(chconfig.enums.orientation, v) then
            s.orientation = v; out.changed = true; say('Orientation: ' .. v)
        else
            say('Usage: /ch orient <columns|stacked|rows>')
        end

    elseif cmd == 'demo' then
        s.demo = onoff(a3, s.demo); out.changed = true
        say('Demo data: ' .. (s.demo and 'on' or 'off'))

    elseif cmd == 'cursor' then
        out.cursor = (args[3] ~= 'off')
        say('Cursor test ' .. (out.cursor and 'on: a crosshair is drawn where ImGui thinks the mouse is. /ch cursor off to stop.' or 'off.'))
    elseif cmd == 'partydump' then
        out.party_dump = true
    elseif cmd == 'apicheck' then
        out.api_check = true     -- handled by the entry file (needs the live ImGui tables)

    elseif cmd == 'reset' then
        if lower(a3) == 'confirm' then
            out.reset = true; out.changed = true; say('All settings reset to defaults.')
        else
            say('This restores every setting. Run "/ch reset confirm" to do it.')
        end

    else
        say('Unknown command "' .. tostring(args[2]) .. '". Try /ch help')
    end

    return out
end

return commands
