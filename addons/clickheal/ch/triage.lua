--[[
    ClickHeal - triage.lua
    Pure logic for the Triage view: who needs help most, and which spell fits. No ImGui, no Ashita.

    Priority, highest first (members a cast cannot reach are always last, KO'd members after the rest of those):
      tier 3  a deadly debuff you can remove right now (Doom, Petrify)
      tier 2  HP at or below the critical threshold
      tier 1  an important debuff you can remove (Curse, Silence, Paralysis)
      tier 0  everything else
    Within a tier, the member missing the most HP comes first.

    The potency numbers are rough in-game averages for a mid-level healer, used only to preview and to pick
    the "best fit" tile. They are not read from the game.
]]--

local spells  = require('ch.spells')
local debuffs = require('ch.debuffs')

local triage = {}

triage.POTENCY = { cure1 = 90, cure2 = 190, cure3 = 390, cure4 = 650, cure5 = 900, cure6 = 1100 }

function triage.deficit(m)
    return math.max(0, (m.hpmax or 0) - (m.hp or 0))
end

--- Can a cast land on this member right now (alive, same zone, in range)?
function triage.eligible(m, cfg)
    if not m or not m.active or m.dead or m.zone_diff then return false end
    if m.dist ~= nil and m.dist > cfg.max_range then return false end
    return true
end

--- Set { spell_key = true } of the cleansing spells you can use (the preset's cleanse group).
function triage.cleanse_set(cfg, preset, player)
    local set = {}
    for _, k in ipairs(spells.group_keys(cfg, preset, 'cleanse', player)) do
        if spells.known(k, player) then set[k] = true end
    end
    return set
end

local function opts(cfg) return (cfg and cfg.triage_opts) or { debuffs = true, crit = true, tiles = 4, spells = {}, levels = {} } end

--- How the debuff counts: 'urgent', 'important' or 'off' (the user's choice, else by severity).
function triage.level(cfg, key)
    local lv = opts(cfg).levels[key]
    if lv then return lv end
    local info = debuffs.info[key]
    if not info then return 'off' end
    return (info.sev == 1 and 'urgent') or (info.sev == 2 and 'important') or 'off'
end

--- Debuffs on this member that one of your spells removes, worst first: { { key, spell, sev }, ... }.
function triage.fixable(m, can)
    local out = {}
    if not m or m.dead or not m.debuffs then return out end
    for _, k in ipairs(m.debuffs) do
        local info = debuffs.info[k]
        if info and info.spell and can and can[info.spell] then out[#out + 1] = { key = k, spell = info.spell, sev = info.sev } end
    end
    table.sort(out, function(a, b) if a.sev ~= b.sev then return a.sev < b.sev end return a.key < b.key end)
    return out
end

--- Priority tier (see the header). -1 when a cast cannot reach the member.
function triage.tier(m, cfg, can)
    if not triage.eligible(m, cfg) then return -1 end
    local o = opts(cfg)
    local top
    if o.debuffs then
        for _, d in ipairs(triage.fixable(m, can)) do
            local lv = triage.level(cfg, d.key)
            if lv == 'urgent' then top = 'urgent'; break end
            if lv == 'important' then top = top or 'important' end
        end
    end
    if top == 'urgent' then return 3 end
    if o.crit and m.hpp and m.hpp <= cfg.hp_crit then return 2 end
    if top == 'important' then return 1 end
    return 0
end

--- Active members of the visible groups, neediest first. Returns the list and a { [slot] = tier } table.
-- `groups` is an optional set { [group] = true }; `can` is the cleanse set.
function triage.order(roster_list, cfg, groups, can)
    local out, tiers = {}, {}
    for _, m in ipairs(roster_list or {}) do
        if m.active and (not groups or groups[math.floor(m.slot / 6)]) then
            out[#out + 1] = m
            tiers[m.slot] = triage.tier(m, cfg, can)
        end
    end
    table.sort(out, function(a, b)
        local ta, tb = tiers[a.slot], tiers[b.slot]
        if ta ~= tb then return ta > tb end
        if (a.dead and true or false) ~= (b.dead and true or false) then return not a.dead end   -- among those a cast cannot reach, KO'd members are last of all
        local da, db = triage.deficit(a), triage.deficit(b)
        if da ~= db then return da > db end
        return a.slot < b.slot
    end)
    return out, tiers
end

--- The member to feature. Keeps the previous one unless someone is clearly worse off (a higher tier, or a much
-- bigger HP gap), so the panel does not flicker between two similar members.
function triage.pick(list, cfg, prev_slot, tiers)
    local top = list[1]
    if not top or not triage.eligible(top, cfg) then return top end
    if prev_slot then
        for _, m in ipairs(list) do
            if m.slot == prev_slot and triage.eligible(m, cfg) then
                local pt, tt = tiers and tiers[m.slot] or 0, tiers and tiers[top.slot] or 0
                local pd, td = triage.deficit(m), triage.deficit(top)
                if pt >= tt and (pt > 0 or pd > 0) and (pt > tt or td < pd * 1.25 + 60) then return m end
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
        if d and d.kind == 'cure' and triage.POTENCY[k] and spells.known(k, player) then out[#out + 1] = k end
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

local function has_buff(m, key)
    for _, b in ipairs(m.buffs or {}) do if b.key == key then return true end end
    return false
end

--- Is this spell worth offering for this member right now?
-- Cures: always. Cleansing: when the member has a debuff it removes. Buffs: when the member lacks it.
function triage.applicable(key, m)
    local def = spells.defs[key]
    if not def then return false end
    local group = spells.group_of(def)
    if def.kind == 'cure' or def.kind == 'curaga' then return true end
    if group == 'cleanse' then
        for _, k in ipairs(m.debuffs or {}) do
            local info = debuffs.info[k]
            if info and info.spell == key then return true end
        end
        return false
    end
    if group == 'buff' and def.buff then
        if def.selfonly and not m.is_you then return false end
        return m.has_buff_data and not has_buff(m, def.buff) or false
    end
    return false
end

--- The tiles to show for the featured member, and the key to highlight as the best fit.
-- Your priority list (triage_opts.spells) comes first, in your order, keeping only what applies right now;
-- then automatic picks fill the rest: spells that remove its debuffs, then the strongest single-target cures.
-- Returns { { key, kind = 'cleanse'|'cure'|'buff'|'other', debuff = key }, ... }, best_key.
function triage.tiles(m, cfg, preset, player, tier, max)
    local o = opts(cfg)
    max = max or o.tiles or 4
    local can = triage.cleanse_set(cfg, preset, player)
    local fix = triage.fixable(m, can)
    local tiles, seen = {}, {}

    local function add(key, kind, debuff)
        if #tiles < max and not seen[key] then
            seen[key] = true
            tiles[#tiles + 1] = { key = key, kind = kind, debuff = debuff }
        end
    end
    local function kind_of(key)
        local def = spells.defs[key]
        local group = def and spells.group_of(def)
        if group == 'cleanse' then return 'cleanse' end
        if def and (def.kind == 'cure' or def.kind == 'curaga') then return 'cure' end
        return 'buff'
    end
    local function debuff_for(key)
        for _, k in ipairs(m.debuffs or {}) do
            local info = debuffs.info[k]
            if info and info.spell == key then return k end
        end
    end

    for _, key in ipairs(o.spells or {}) do
        if spells.known(key, player) and triage.applicable(key, m) then add(key, kind_of(key), debuff_for(key)) end
    end
    for _, d in ipairs(fix) do
        local n = 0
        for _, t in ipairs(tiles) do if t.kind == 'cleanse' then n = n + 1 end end
        if n < 2 then add(d.spell, 'cleanse', d.key) end
    end
    local cures = triage.cure_keys(cfg, preset, player)
    local room = max - #tiles
    for i = math.max(1, #cures - room + 1), #cures do add(cures[i], 'cure') end

    -- Best fit: a cleanse for an urgent/important debuff (or when nothing is missing), else the cure that fits the gap.
    local best
    local first_cleanse
    for _, t in ipairs(tiles) do if t.kind == 'cleanse' and not first_cleanse then first_cleanse = t end end
    if first_cleanse and (tier == 3 or tier == 1 or triage.deficit(m) == 0) then
        best = first_cleanse.key
    else
        local present = {}
        for _, t in ipairs(tiles) do if t.kind == 'cure' and triage.POTENCY[t.key] then present[#present + 1] = t.key end end
        table.sort(present, function(x, y) return triage.POTENCY[x] < triage.POTENCY[y] end)
        best = triage.best(present, triage.deficit(m)) or triage.best(cures, triage.deficit(m))
    end
    return tiles, best
end

return triage
