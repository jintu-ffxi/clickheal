--[[
    ClickHeal - actions.lua
    What happens when the user clicks a spell button or an alert.

    This module never talks to the game itself: it builds a normal chat command (one click = one /ma
    or /ja) and hands it to ctx.send. That happens when demo data is off and the button is ready.
    Demo data and demo members never cast: a click only logs what it would do (and starts a fake recast).
    CatsEyeXI does not allow unlisted addons: do not run ClickHeal there without staff approval.

    Events arrive from ui.lua with the click binding ALREADY resolved (a right click on "Cure III"
    arrives as spell = 'cure2'), so nothing here resolves it again.
]]--

local spells     = require('ch.spells')
local spellstate = require('ch.spellstate')
local casting    = require('ch.casting')

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

    if ev.type == 'set_layout' then
        if ctx.cfg and type(ev.scale) == 'number' then
            ctx.cfg.scale = ev.scale
            if ev.orientation == 'columns' or ev.orientation == 'stacked' or ev.orientation == 'rows' then
                ctx.cfg.orientation = ev.orientation
            end
            if ctx.changed then ctx.changed() end
        end
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
        return 'ignored'
    end

    if ev.type ~= 'cast' then return 'ignored' end

    local def = spells.defs[ev.spell]
    if not def then return 'ignored' end

    local m = ctx.roster_by_slot[ev.slot]
    local who = m and m.name or ('slot ' .. tostring(ev.slot))

    -- Mid-cast (or in the delay after an action): hold the click and send it when the player is free.
    if ev.state == 'busy' then
        if ctx.cfg and ctx.cfg.queue_clicks then
            casting.queue(ev, ctx.now)
            return 'queued'
        end
        ctx.log(string.format("[ClickHeal] Can't cast %s yet: %s", def.name, spellstate.describe(ev.state, ev.detail)))
        return 'blocked'
    end

    if ev.state and ev.state ~= 'ready' then
        ctx.log(string.format("[ClickHeal demo] Can't cast %s on %s: %s",
            def.name, who, spellstate.describe(ev.state, ev.detail)))
        return 'blocked'
    end

    local token = def.selfonly and '<me>' or actions.target_token(ev.slot)
    if def.selfonly then who = 'you' end
    if m and m.demo and not def.selfonly then
        ctx.log(string.format('[ClickHeal demo] %s -> %s (demo member). Nothing was sent to the game.', def.name, who))
        casting.start(def, ctx.now, ctx.cfg)
        return 'cast'
    end
    if ctx.send and not ctx.demo then
        local cmd = actions.command_for(def, token)
        ctx.send(cmd)
        casting.start(def, ctx.now, ctx.cfg)
        return 'sent'
    end

    ctx.log(string.format('[ClickHeal demo] %s -> %s (%s). Nothing was sent to the game.', def.name, who, token))

    if ctx.demo then ctx.demo.cast(def, ctx.now) end
    casting.start(def, ctx.now, ctx.cfg)
    return 'cast'
end

--- Sends the held click once the player can act again. `player` is this frame's player table.
-- Returns what perform returned, or nil when nothing was due.
function actions.run_queued(ctx, player)
    local ev = casting.take(ctx.now)
    if not ev then return nil end
    local def = spells.defs[ev.spell]
    local m = ctx.roster_by_slot[ev.slot]
    if not def or not m then return nil end
    local p = {}
    for k, v in pairs(player or {}) do p[k] = v end
    p.busy_left = casting.left(ctx.now)
    local state, detail = spellstate.evaluate(def, m, p, ctx.cfg)
    local ev2 = {}
    for k, v in pairs(ev) do ev2[k] = v end
    ev2.state, ev2.detail = state, detail
    return actions.perform(ev2, ctx)
end

return actions
