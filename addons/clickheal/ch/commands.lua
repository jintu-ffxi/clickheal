--[[
    ClickHeal - commands.lua
    The /ch command line. Pure: takes an args array and the settings table, returns what happened.

    run(args, s) -> { messages = { ... }, changed = bool, toggle_config = bool, reset = bool }
    `args` is the split command line, e.g. { '/ch', 'scale', '1.5' }.
]]--

local chconfig = require('ch.chconfig')
local bindings = require('ch.bindings')
local spells   = require('ch.spells')

local commands = {}

local HELP = {
    '/ch                      open / close the setup panel',
    '/ch show | hide          show or hide the frames',
    '/ch lock | unlock        lock = clickable, unlock = drag to move',
    '/ch scale <0.5-4|auto>   size multiplier (auto = follow game resolution)',
    '/ch layout <full|compact|minimal|grid|strip>',
    '/ch mode <party|alliance1|alliance2>   (or 6 / 12 / 18)',
    '/ch orient <columns|stacked|rows>',
    '/ch demo [on|off]        demo data (off = your real party)',
    '/ch slant <0-16>         strip rows: 0 = square (default), higher = leaning edge',
    '/ch buttons <24-64> [2-16]  flyout button size (and spacing)',
    '/ch cast [on|off]        a click really casts the spell (off = only logs). Needs demo off.',
    '/ch alerts [on|off]      priority alert bar',
    '/ch colors <modern|mono|colorblind>',
    '/ch buffs [on|off]       buff pip strip on full cards',
    '/ch mybuffs [on|off]     pips: only buffs your job can cast',
    '/ch timers [on|off]      seconds left on debuff chips and buff pips',
    '/ch job <text|tag>       job shown as text (WHM/SCH 99) or as a tag chip',
    '/ch buffmode [heal|buff] spell row shows heals or buffs (no argument = switch)',
    '/ch flyout [on|off]      hover a member (Grid / Strip) to open their spell flyout',
    '/ch order <heal|cleanse|buff|raise|ability> <spell keys...>   spell order, same for every member;  /ch order <group> reset',
    '/ch bar [on|off]         shared spell bar under the Grid / Strip cells (pick a spell, then click a member)',
    '/ch tab <heal|cleanse|buff|raise>   which spells the bar shows',
    '/ch cellbinds [on|off]   Grid / Strip: plain clicks on a cell cast the bound spell too',
    '/ch bind <click> <spell|cleanse|none>   grid/strip click casting, e.g. /ch bind shift+rmb cure1',
    '/ch binds                list the current click bindings;  /ch bind reset  clears your changes',
    '/ch reset confirm        restore every setting to defaults',
    '/ch apicheck             check which Ashita/ImGui calls this install supports',
    '/ch partydump            print the raw party status-icon data (for debuff icon support)',
    '/ch inputdebug [on|off]  log where each mouse click lands (for debugging clicks)',
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

    elseif cmd == 'layout' or cmd == 'style' then
        local v = lower(a3)
        if v and in_list(chconfig.enums.style, v) then
            s.style = v; out.changed = true; say('Layout: ' .. v)
        else
            say('Usage: /ch layout <full|compact|minimal|grid|strip>')
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

    elseif cmd == 'slant' then
        local n = tonumber(a3)
        if not n then
            say('Usage: /ch slant <0-16>   (now ' .. s.slant .. '; 0 = square rows)')
        else
            s.slant = n; chconfig.sanitize(s); out.changed = true
            say('Row slant: ' .. s.slant)
        end

    elseif cmd == 'buttons' then
        local size, gap = tonumber(a3), tonumber(args[4])
        if not size then
            say('Usage: /ch buttons <24-64> [spacing 2-16]   (now ' .. s.fly_btn .. ' / ' .. s.fly_gap .. ')')
        else
            s.fly_btn = size
            if gap then s.fly_gap = gap end
            chconfig.sanitize(s); out.changed = true
            say('Flyout buttons: size ' .. s.fly_btn .. ', spacing ' .. s.fly_gap)
        end

    elseif cmd == 'cast' then
        s.cast = onoff(a3, s.cast); out.changed = true
        if s.cast and s.demo then
            say('Casting: on, but demo data is on, so clicks still only log. Use /ch demo off to cast for real.')
        elseif s.cast then
            say('Casting: ON. A click now sends the spell to the game. Only use this where addons are allowed.')
        else
            say('Casting: off. Clicks only log.')
        end

    elseif cmd == 'alerts' then
        s.alerts.enabled = onoff(a3, s.alerts.enabled); out.changed = true
        say('Alert bar: ' .. (s.alerts.enabled and 'on' or 'off'))

    elseif cmd == 'colors' or cmd == 'colours' then
        local v = lower(a3)
        if v and in_list(chconfig.enums.colors, v) then
            s.colors = v; out.changed = true; say('Colors: ' .. v)
        else
            say('Usage: /ch colors <modern|mono|colorblind>')
        end

    elseif cmd == 'buffs' then
        s.show_buffs = onoff(a3, s.show_buffs); out.changed = true
        say('Buff pips: ' .. (s.show_buffs and 'on' or 'off'))
    elseif cmd == 'mybuffs' then
        s.buffs_mine_only = onoff(a3, s.buffs_mine_only); out.changed = true
        say('Pips show: ' .. (s.buffs_mine_only and 'only buffs your job casts' or 'all known buffs'))
    elseif cmd == 'timers' then
        s.show_timers = onoff(a3, s.show_timers); out.changed = true
        say('Timers: ' .. (s.show_timers and 'on' or 'off'))
    elseif cmd == 'job' then
        local v = lower(a3)
        if v and in_list(chconfig.enums.job_style, v) then
            s.job_style = v; out.changed = true; say('Job display: ' .. v)
        else
            say('Usage: /ch job <text|tag>')
        end
    elseif cmd == 'buffmode' then
        local v = lower(a3)
        if v == 'buff' or v == 'buffs' then s.buff_mode = true
        elseif v == 'heal' or v == 'heals' then s.buff_mode = false
        else s.buff_mode = not s.buff_mode end
        out.changed = true
        say('Spell row: ' .. (s.buff_mode and 'buffs' or 'heals and cleanses'))

    elseif cmd == 'flyout' then
        s.flyout = onoff(a3, s.flyout); out.changed = true
        say('Hover flyout: ' .. (s.flyout and 'on' or 'off'))

    elseif cmd == 'order' then
        local group = lower(a3)
        local ok_group = { heal = true, cleanse = true, buff = true, raise = true, ability = true }
        if not group or not ok_group[group] then
            say('Usage: /ch order <heal|cleanse|buff|raise|ability> <spell keys...>   or   /ch order <group> reset')
        elseif lower(args[4]) == 'reset' then
            s.spell_order[group] = nil; out.changed = true; say('Order for ' .. group .. ' reset to the job default.')
        elseif not args[4] then
            out.show_order = group
        else
            local keys, bad = {}, nil
            for i = 4, #args do
                local k = tostring(args[i]):lower()
                if spells.defs[k] then keys[#keys + 1] = k else bad = bad or k end
            end
            if bad then
                say('Unknown spell key: ' .. bad .. '   (keys look like cure4, curaga2, paralyna, haste, divine_seal)')
            else
                s.spell_order[group] = keys; out.changed = true
                say(group .. ' order: ' .. table.concat(keys, ' '))
            end
        end

    elseif cmd == 'bar' then
        s.spellbar = onoff(a3, s.spellbar); out.changed = true
        say('Spell bar: ' .. (s.spellbar and 'on' or 'off'))
    elseif cmd == 'tab' then
        local v = lower(a3)
        if v and in_list(chconfig.enums.bar_tab, v) then
            s.bar_tab = v; out.changed = true; say('Spell bar tab: ' .. v)
        else
            say('Usage: /ch tab <heal|cleanse|buff|raise>')
        end
    elseif cmd == 'cellbinds' then
        s.cell_binds = onoff(a3, s.cell_binds); out.changed = true
        say('Cell click bindings: ' .. (s.cell_binds and 'on' or 'off'))

    elseif cmd == 'binds' then
        out.show_binds = true

    elseif cmd == 'bind' then
        if lower(a3) == 'reset' then
            s.bindings = {}; out.changed = true; say('Click bindings reset to the job defaults.')
        else
            local slot = bindings.parse_slot(a3)
            local val = args[4] and tostring(args[4]):lower() or nil
            if val == 'none' or val == 'off' or val == '-' then val = '-' end
            if not slot or not val or not bindings.valid_value(val) then
                say('Usage: /ch bind <lmb|rmb|mmb|shift+lmb|ctrl+rmb|alt+lmb ...> <spell key|cleanse|none>   e.g. /ch bind lmb cure4')
            else
                s.bindings[slot] = val; out.changed = true
                say(string.format('%s -> %s', bindings.SHORT[slot], val))
            end
        end

    elseif cmd == 'inputdebug' then
        out.input_debug = (args[3] ~= 'off')
        say('Input debug ' .. (out.input_debug and 'on: click things and read the [input] lines.' or 'off.'))
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
