--[[
    ClickHeal - triage.lua
    Pure logic for the Triage view: who needs healing most, and which cure fits the gap.
    No ImGui, no Ashita.

    The potency numbers are rough in-game averages for a mid-level healer, used only to preview
    and to pick the "best fit" tile. They are not read from the game.
]]--

local spells = require('ch.spells')

local triage = {}

triage.POTENCY = { cure1 = 90, cure2 = 190, cure3 = 390, cure4 = 650, cure5 = 900, cure6 = 1100 }

function triage.deficit(m)
    return math.max(0, (m.hpmax or 0) - (m.hp or 0))
end

--- Can a cure land on this member right now (alive, same zone, in range)?
function triage.eligible(m, cfg)
    if not m or not m.active or m.dead or m.zone_diff then return false end
    if m.dist ~= nil and m.dist > cfg.max_range then return false end
    return true
end

--- Active members of the visible groups, neediest first. Members a cure cannot reach go last.
-- `groups` is an optional set { [group] = true }.
function triage.order(roster_list, cfg, groups)
    local out = {}
    for _, m in ipairs(roster_list or {}) do
        if m.active and (not groups or groups[math.floor(m.slot / 6)]) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b)
        local ea, eb = triage.eligible(a, cfg), triage.eligible(b, cfg)
        if ea ~= eb then return ea end
        local da, db = triage.deficit(a), triage.deficit(b)
        if da ~= db then return da > db end
        return a.slot < b.slot
    end)
    return out
end

--- The member to feature. Keeps the previous one unless someone is clearly worse off, so the panel
-- does not flicker between two similar members.
function triage.pick(list, cfg, prev_slot)
    local top = list[1]
    if not top or not triage.eligible(top, cfg) then return top end
    if prev_slot then
        for _, m in ipairs(list) do
            if m.slot == prev_slot and triage.eligible(m, cfg) then
                local pd, td = triage.deficit(m), triage.deficit(top)
                if pd > 0 and td < pd * 1.25 + 60 then return m end
            end
        end
    end
    return top
end

--- Single-target cure keys the player can use, weakest first.
function triage.cure_keys(cfg, preset, player)
    local out = {}
    for _, k in ipairs(spells.group_keys(cfg, preset, 'heal', player)) do
        local d = spells.defs[k]
        if d and d.kind == 'cure' and triage.POTENCY[k] then out[#out + 1] = k end
    end
    table.sort(out, function(a, b) return triage.POTENCY[a] < triage.POTENCY[b] end)
    return out
end

--- Key whose potency covers the deficit with the least waste; the strongest when none does.
function triage.best(keys, deficit)
    local best
    for _, k in ipairs(keys) do
        local p = triage.POTENCY[k]
        if p >= deficit then return k end
        best = k
    end
    return best
end

return triage
