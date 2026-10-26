--[[
    ClickHeal - spellstate.lua
    Decides whether a spell button is usable on a given member and why not.
    Pure function of plain tables, so it is unit-testable without the game.

    member : roster entry (see source_demo.lua for the shape)
    player : { mp = number, silenced = bool, incapacitated = bool, recast = { key = seconds_left } }
    cfg    : settings (uses max_range)

    Returns state, detail
      'ready'      - castable
      'gone'       - slot empty / member not active
      'zone'       - member is in a different zone
      'dead'       - target is KO'd (non-raise spell)
      'alive'      - raise spell on a living target
      'range'      - beyond cfg.max_range         (detail = distance)
      'blocked'    - silenced / asleep / etc.     (detail = reason text)
      'recast'     - on cooldown                  (detail = seconds left)
      'nomp'       - not enough MP                (detail = mp still needed)
      'busy'       - mid-cast or in the delay after an action (detail = seconds left); a click is queued
]]--

local spellstate = {}

function spellstate.evaluate(def, member, player, cfg)
    if not member or not member.active then return 'gone' end

    -- Self job abilities: not blocked by silence or distance; only a KO'd you or a recast stops them.
    if def.ja and def.self then
        if player.incapacitated then return 'blocked', 'You cannot act right now' end
        local jleft = player.recast and player.recast[def.key] or 0
        if jleft and jleft > 0.05 then return 'recast', jleft end
        if (player.busy_left or 0) > 0.05 then return 'busy', player.busy_left end
        return 'ready'
    end
    if def.selfonly then
        -- Cast on you wherever you clicked, so the clicked member's zone, range and KO state don't matter.
        if player.incapacitated then return 'blocked', 'You cannot cast right now' end
        if player.silenced then return 'blocked', 'Silenced' end
        local sleft = player.recast and player.recast[def.key] or 0
        if sleft and sleft > 0.05 then return 'recast', sleft end
        if def.mp and (player.mp or 0) < def.mp then return 'nomp', def.mp - (player.mp or 0) end
        if (player.busy_left or 0) > 0.05 then return 'busy', player.busy_left end
        return 'ready'
    end
    if member.zone_diff then return 'zone' end

    if def.kind == 'raise' then
        if not member.dead then return 'alive' end
    elseif member.dead then
        return 'dead'
    end

    if member.dist and member.dist > cfg.max_range then
        return 'range', member.dist
    end

    if player.incapacitated then return 'blocked', 'You cannot cast right now' end
    if player.silenced then return 'blocked', 'Silenced' end

    local left = player.recast and player.recast[def.key] or 0
    if left and left > 0.05 then return 'recast', left end

    if def.mp and (player.mp or 0) < def.mp then
        return 'nomp', def.mp - (player.mp or 0)
    end

    -- Everything else is fine; the player is just still busy with the last action.
    if (player.busy_left or 0) > 0.05 then return 'busy', player.busy_left end

    return 'ready'
end

--- Text for tooltips / status lines.
function spellstate.describe(state, detail)
    if state == 'ready'   then return 'Ready' end
    if state == 'gone'    then return 'No member' end
    if state == 'zone'    then return 'In another zone' end
    if state == 'dead'    then return 'Target is KO' end
    if state == 'alive'   then return 'Target is not KO' end
    if state == 'range'   then return string.format('Out of range (%dy)', math.floor((detail or 0) + 0.5)) end
    if state == 'blocked' then return tostring(detail or 'Blocked') end
    if state == 'recast'  then return string.format('Recast %.1fs', detail or 0) end
    if state == 'busy'    then return string.format('Casting, %.1fs (click to queue)', detail or 0) end
    if state == 'nomp'    then return string.format('Need %d more MP', math.ceil(detail or 0)) end
    return state
end

return spellstate
