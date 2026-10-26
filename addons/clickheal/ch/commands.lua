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
    '/ch mode <party|alliance1|alliance2>   (or 6 / 12 / 18)',
    '/ch orient <columns|stacked|rows>',
    '/ch demo [on|off]        demo data (off = your real party)',
    '/ch slant <0-16>         strip rows: 0 = square (default), higher = leaning edge',
    '/ch buttons <24-64> [2-16]  flyout button size (and spacing)',
    '/ch status               show the switches that decide what hover and clicks do',
    '/ch cast [on|off]        a click really casts the spell (off = only logs). Needs demo off.',
    '/ch queue [on|off]       hold a click made mid-cast and send it when you can act',
    '/ch fastcast <0-80>      Fast Cast %, shortens the estimated cast time',
    '/ch lockout <0.3-3>      seconds of delay after each cast or ability',
    '/ch alerts [on|off]      priority alert bar',
    '/ch colors <modern|job|mono|colorblind>',
    '/ch skin <solid|hairline>  row style',
    '/ch triage [on|off]      neediest-first panel with best-fit cures',
    '/ch mp pct [on|off]      MP percent beside the HP percent',
    '/ch mp height <2-14>     MP bar thickness',
    '/ch mp size <0.5-1>      MP percent text size',
    '/ch jobicons [on|off]    job pictograms instead of the three letters',
    '/ch rowsize <w> <h>      member row width and height (160-360, 30-72)',
    '/ch icons <debuff> [buff]  status icon sizes (10-32)',
    '/ch buffbar [on|off]     buff icon bar on each row',
    '/ch mybuffs [on|off]     buff bar: only buffs your job can cast',
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

    elseif cmd == 'status' then
        local function yn(v) return v and 'on' or 'off' end
        say(string.format('shown: %s   locked: %s   hover flyout: %s   demo data: %s   casting: %s',
            yn(s.visible), yn(s.locked), yn(s.flyout), yn(s.demo), yn(s.cast)))
        say(string.format('shared spell bar: %s   plain-click casting: %s   buff clicks: %s   click queue: %s',
            yn(s.spellbar), yn(s.cell_binds), yn(s.buff_mode), yn(s.queue_clicks)))
        local cs = require('ch.chatstatus')
        say('chat-tracked members: ' .. cs.count() .. '   chat lines seen: ' .. cs.seen)
        if cs.last_raw then
            say('last "effect" line, raw bytes: ' .. cs.last_raw:gsub('[^\32-\126]', function(c) return '<' .. c:byte() .. '>' end))
        end
        if not s.locked then say('The hover flyout only works while LOCKED. /ch lock') end
        if not s.flyout then say('Hover flyout is off. /ch flyout on') end
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

    elseif cmd == 'rowsize' then
        local w, h = tonumber(a3), tonumber(args[4])
        if not w or not h then
            say('Usage: /ch rowsize <width 160-360> <height 30-72>   (now ' .. s.row_w .. ' x ' .. s.row_h .. ')')
        else
            s.row_w, s.row_h = w, h
            chconfig.sanitize(s); out.changed = true
            say('Row size: ' .. s.row_w .. ' x ' .. s.row_h)
        end

    elseif cmd == 'skin' then
        local v = (a3 or ''):lower()
        if v == 'solid' or v == 'hairline' then
            s.skin = v; out.changed = true
            say('Row style: ' .. v)
        else
            say('Usage: /ch skin <solid|hairline>   (now ' .. s.skin .. ')')
        end

    elseif cmd == 'triage' then
        s.triage = onoff(a3, s.triage); out.changed = true
        say('Triage view: ' .. (s.triage and 'on' or 'off'))

    elseif cmd == 'mp' then
        local sub = (a3 or ''):lower()
        if sub == 'pct' then
            s.show_mp_pct = onoff(args[4] and args[4]:lower(), s.show_mp_pct); out.changed = true
            say('MP percent: ' .. (s.show_mp_pct and 'on' or 'off'))
        elseif sub == 'size' and tonumber(args[4]) then
            s.mp_pct_scale = tonumber(args[4]); chconfig.sanitize(s); out.changed = true
            say(string.format('MP percent size: %.2f', s.mp_pct_scale))
        elseif sub == 'height' and tonumber(args[4]) then
            s.mp_height = tonumber(args[4]); chconfig.sanitize(s); out.changed = true
            say('MP bar thickness: ' .. s.mp_height)
        else
            say('Usage: /ch mp pct [on|off]   or   /ch mp height <2-14>   (now ' .. (s.show_mp_pct and 'pct on' or 'pct off') .. ', height ' .. s.mp_height .. ')')
        end

    elseif cmd == 'icons' then
        local d, b = tonumber(a3), tonumber(args[4])
        if not d then
            say('Usage: /ch icons <debuff 10-32> [buff 10-32]   (now ' .. s.debuff_icon .. ' / ' .. s.buff_icon .. ')')
        else
            s.debuff_icon = d
            if b then s.buff_icon = b end
            chconfig.sanitize(s); out.changed = true
            say('Icon sizes: debuff ' .. s.debuff_icon .. ', buff ' .. s.buff_icon)
        end

    elseif cmd == 'jobicons' then
        s.job_icon = onoff(a3, s.job_icon); out.changed = true
        say('Job icons: ' .. (s.job_icon and 'on' or 'off'))

    elseif cmd == 'queue' then
        s.queue_clicks = onoff(a3, s.queue_clicks); out.changed = true
        say('Click queue: ' .. (s.queue_clicks and 'on' or 'off'))

    elseif cmd == 'fastcast' then
        local n = tonumber(a3)
        if not n then
            say('Usage: /ch fastcast <0-80>   (now ' .. s.fast_cast .. '%)')
        else
            s.fast_cast = n; chconfig.sanitize(s); out.changed = true
            say('Fast Cast: ' .. s.fast_cast .. '%')
        end

    elseif cmd == 'lockout' then
        local n = tonumber(a3)
        if not n then
            say(string.format('Usage: /ch lockout <0.3-3>   (now %.1fs)', s.cast_lockout))
        else
            s.cast_lockout = n; chconfig.sanitize(s); out.changed = true
            say(string.format('Delay after each action: %.1fs', s.cast_lockout))
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
            say('Usage: /ch colors <modern|job|mono|colorblind>')
        end

    elseif cmd == 'buffbar' then
        s.show_buff_bar = onoff(a3, s.show_buff_bar); out.changed = true
        say('Buff icon bar: ' .. (s.show_buff_bar and 'on' or 'off'))
    elseif cmd == 'mybuffs' then
        s.buffs_mine_only = onoff(a3, s.buffs_mine_only); out.changed = true
        say('Buff bar shows: ' .. (s.buffs_mine_only and 'only buffs your job casts' or 'all known buffs'))
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
