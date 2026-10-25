--[[
    ClickHeal - actions.lua
    What happens when the user clicks a spell button or an alert.

    CASTING IS OFF BY DEFAULT. This module never talks to the game itself: it builds a normal chat
    command (one click = one /ma or /ja) and hands it to ctx.send. That only happens when ALL of these
    hold: the user ran `/ch cast on`, demo data is off, and the button was ready. Otherwise a click only
    logs what it would do (and starts a fake recast in the demo source).
    CatsEyeXI does not allow unlisted addons: do not turn casting on there without staff approval.

    Events arrive from ui.lua with the click binding ALREADY resolved (a right click on "Cure III"
    arrives as spell = 'cure2'), so nothing here resolves it again.
]]--

local spells     = require('ch.spells')
local spellstate = require('ch.spellstate')

local actions = {}

--- Target token for a roster slot. Slots are group * 6 + index.
--   0      -> <me>
--   1..5   -> <p1>..<p5>
--   6..11  -> <a10>..<a15>
--   12..17 -> <a20>..<a25>
function actions.target_token(slot)
    if slot == 0 then return '<me>' end
    if slot < 6 then return '<p' .. slot .. '>' end
    local group = math.floor(slot / 6)
    return '<a' .. group .. (slot % 6) .. '>'
end

--- The chat command for casting `def` at `token`: '/ma "Cure IV" <p1>' or '/ja "Divine Seal" <me>'.
-- Self-only spells and self abilities always target <me>.
function actions.command_for(def, token)
    local target = (def.selfonly or (def.ja and def.self)) and '<me>' or token
    return string.format('/%s "%s" %s', def.ja and 'ja' or 'ma', def.name, target)
end

--- Handles one UI event.
-- ctx = { cfg = settings, changed = function() (settings changed), demo = module|nil, log = function(text), now = seconds, roster_by_slot = {}, dismissed = {} }
-- Returns a short result string (used by tests): 'dismissed' | 'cast' | 'blocked' | 'ignored'
function actions.perform(ev, ctx)
    if ev.type == 'dismiss' then
        ctx.dismissed[ev.id] = ctx.now + 25   -- hide this alert for 25 seconds
        return 'dismissed'
    end

    if ev.type == 'note' then
        ctx.log(ev.text or '')
        return 'noted'
    end

    if ev.type == 'open_config' then
        if ctx.open_config then ctx.open_config() end
        return 'toggled'
    end

    if ev.type == 'set_scale' then
        if ctx.cfg and type(ev.value) == 'number' then
            ctx.cfg.scale = ev.value
            if ctx.changed then ctx.changed() end
        end
        return 'toggled'
    end

    if ev.type == 'toggle' then
        if ev.what == 'locked' and ctx.cfg then
            ctx.cfg.locked = not ctx.cfg.locked
            if ctx.changed then ctx.changed() end
            return 'toggled'
        end
        if ev.what == 'buff_mode' and ctx.cfg then
            ctx.cfg.buff_mode = not ctx.cfg.buff_mode
            if ctx.changed then ctx.changed() end
            return 'toggled'
        end
        if ev.what == 'bar_tab' and ctx.cfg and ev.value then
            ctx.cfg.bar_tab = ev.value
            if ctx.changed then ctx.changed() end
            return 'toggled'
        end
        return 'ignored'
    end

    if ev.type ~= 'cast' then return 'ignored' end

    local def = spells.defs[ev.spell]
    if not def then return 'ignored' end

    local m = ctx.roster_by_slot[ev.slot]
    local who = m and m.name or ('slot ' .. tostring(ev.slot))

    if ev.state and ev.state ~= 'ready' then
        ctx.log(string.format("[ClickHeal demo] Can't cast %s on %s: %s",
            def.name, who, spellstate.describe(ev.state, ev.detail)))
        return 'blocked'
    end

    local token = def.selfonly and '<me>' or actions.target_token(ev.slot)
    if def.selfonly then who = 'you' end
    if ctx.send and ctx.cfg and ctx.cfg.cast and not ctx.demo then
        local cmd = actions.command_for(def, token)
        ctx.send(cmd)
        ctx.log(string.format('%s -> %s (%s)', def.name, who, token))
        return 'sent'
    end

    ctx.log(string.format('[ClickHeal demo] %s -> %s (%s). Nothing was sent to the game.', def.name, who, token))

    if ctx.demo then ctx.demo.cast(def, ctx.now) end
    return 'cast'
end

return actions
