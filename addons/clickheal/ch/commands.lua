--[[
    ClickHeal - commands.lua
    The /ch command line. Pure: takes an args array and the settings table, returns what happened.

    run(args, s) -> { messages = { ... }, changed = bool, toggle_config = bool, reset = bool }
    `args` is the split command line, e.g. { '/ch', 'scale', '1.5' }.
]]--

local chconfig = require('ch.chconfig')

local commands = {}

--- Every command, in the order /ch help and the setup panel list them: { what you type, what it does }.
commands.LIST = {
    { '/ch',                       'Open or close the setup panel.' },
    { '/ch show   |   /ch hide',   'Show or hide the party frames.' },
    { '/ch lock   |   /ch unlock', 'Locked: clicks cast. Unlocked: drag the frames to move them, drag a corner to resize.' },
    { '/ch scale <0.5-4|auto>',    'Size multiplier for the frames. auto follows the game resolution.' },
    { '/ch mode <party|alliance1|alliance2>', 'How many members to show: 6, 12 or 18 (the numbers work too).' },
    { '/ch orient <columns|stacked|rows>',    'How the parties are laid out.' },
    { '/ch demo [on|off]',         'Demo mode: a fake party for trying layouts. It never casts. No argument switches it.' },
    { '/ch status',                'Show what is switched on and where other members\' status effects come from.' },
    { '/ch reset confirm',         'Put every setting back to its default.' },
    { '/ch apicheck',              'List the game functions this install is missing. Handy to include in a bug report.' },
    { '/ch help',                  'Print this list in the chat log.' },
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
        if not s.locked then say('The hover menu only works while LOCKED. /ch lock') end
        if not s.flyout then say('The hover spell menu is off (Spells page).') end
        if not s.visible then say('Frames are hidden. /ch show') end

    elseif cmd == 'help' or cmd == '?' then
        for _, c in ipairs(commands.LIST) do say(string.format('%-34s %s', c[1], c[2])) end

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
