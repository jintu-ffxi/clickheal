--[[
    ClickHeal - source_game.lua
    The real data source: your party and alliance, read from the game's memory through Ashita.

    READ ONLY. Nothing here sends a command or a packet. It returns exactly the member shape that
    source_demo.lua returns, so the UI does not care which one it is drawing.

    What Ashita exposes and what it does not:
      * name, HP/MP (+ percent), zone, job/sub/level, target index  -> every party and alliance slot
      * distance                                                    -> entities in range only
      * your own buffs/debuffs                                      -> yes (player:GetBuffs())
      * other members' buffs/debuffs                                -> NOT here (needs the party-buff
        packet, Phase 3), so has_buff_data is false for everyone but you.
      * spell and ability recasts                                   -> yes (IRecast), per spell/ability
        key through ch/spell_ids.lua; player.recast = seconds left, player.recast_total = longest seen.
    Slots match the party memory indexes: 0 = you, 1-5 = party, 6-11 = alliance 2, 12-17 = alliance 3.
    Every memory read is protected, so a missing function on this build just leaves a field empty.
]]--

local debuffs = require('ch.debuffs')
local ids     = require('ch.spell_ids')
local chatstatus = require('ch.chatstatus')

local game = {}

-- Status effect id -> buff key used by buffs.lua. UNVERIFIED against this server: confirm in Phase 0.
local BUFF_BY_ID = {
    [33] = 'haste', [42] = 'regen', [43] = 'refresh', [40] = 'protect', [41] = 'shell',
    [116] = 'phalanx', [37] = 'stoneskin', [36] = 'blink', [39] = 'aquaveil', [71] = 'sneak',
    [69] = 'invisible', [113] = 'reraise', [581] = 'flurry',
}
-- Debuffs that stop you acting at all.
local INCAPACITATED = { [0] = true, [2] = true, [7] = true, [10] = true, [14] = true, [28] = true }
local SILENCE_ID = 6

local function call(obj, name, ...)
    if not obj then return nil end
    local f = obj[name]
    if not f then return nil end
    local ok, v = pcall(f, obj, ...)
    if ok then return v end
    return nil
end

local function managers()
    local core = _G.AshitaCore
    if not core then return nil end
    local mem = call(core, 'GetMemoryManager')
    if not mem then return nil end
    return call(mem, 'GetParty'), call(mem, 'GetPlayer'), call(mem, 'GetEntity'), call(mem, 'GetRecast')
end

--- Reads a list the game hands back. Ashita returns these as userdata arrays, not Lua tables, so index
-- 0..n (or 1..n when 0 is empty) under pcall. Returns a plain array of numbers, or nil if it is not indexable.
local function read_list(list, n)
    if list == nil then return nil end
    local out, got = {}, false
    local first = 0
    local ok0, v0 = pcall(function() return list[0] end)
    if not ok0 then return nil end
    if v0 == nil then first = 1 end
    for i = 0, n - 1 do
        local ok, v = pcall(function() return list[first + i] end)
        if ok and v ~= nil then
            v = tonumber(v)
            if v then out[#out + 1] = v; got = true end
        end
    end
    return out, got
end

--- Your status effect ids (255 / -1 mean "empty slot").
local function own_buff_ids(player)
    local ids = {}
    local list = read_list(call(player, 'GetBuffs'), 32)
    for _, id in ipairs(list or {}) do
        if id > 0 and id < 255 then ids[#ids + 1] = id end
    end
    return ids
end

local function own_status(player)
    local debuff_keys, buff_list, silenced, stopped = {}, {}, false, false
    for _, id in ipairs(own_buff_ids(player)) do
        local d = debuffs.by_id[id]
        if d then debuff_keys[#debuff_keys + 1] = d end
        if BUFF_BY_ID[id] then buff_list[#buff_list + 1] = { key = BUFF_BY_ID[id] } end
        if id == SILENCE_ID then silenced = true end
        if INCAPACITATED[id] then stopped = true end
    end
    return debuff_keys, buff_list, silenced, stopped
end

--- Another party member's status effects, read from the party status packet the game keeps in memory.
-- Returns debuff keys, buff list, or nil when the game has sent nothing for this slot. That is the normal
-- case for trusts and for members the client has no status data for. UNVERIFIED layout (see /ch partydump):
-- GetStatusIcons(slot) is 32 icon ids (low 8 bits), GetStatusIconsBitMask(slot) holds 2 more bits per entry.
local function member_status(party, slot)
    local sid = call(party, 'GetStatusIconsServerId', slot)
    if type(sid) ~= 'number' or sid == 0 then return nil end
    local icons = read_list(call(party, 'GetStatusIcons', slot), 32)
    if not icons then return nil end
    local mask = call(party, 'GetStatusIconsBitMask', slot)
    mask = (type(mask) == 'number' or type(mask) == 'cdata') and tonumber(mask) or nil
    local d, b, seen = {}, {}, {}
    for i = 0, #icons - 1 do
        local v = icons[i + 1]
        if v > 0 and v < 255 then
            local id = v
            if mask and mask < 2 ^ 53 then id = v + 256 * (math.floor(mask / 2 ^ (2 * i)) % 4) end
            if not seen[id] then
                seen[id] = true
                local dk = debuffs.by_id[id]
                if dk then d[#d + 1] = dk end
                if BUFF_BY_ID[id] then b[#b + 1] = { key = BUFF_BY_ID[id] } end
            end
        end
    end
    return d, b
end

-- Recast timers are in 1/60 s. `peak` remembers the longest value seen per key, so the button can
-- drain a full circle even though the game only reports what is left.
local peak = {}

-- Scholar stratagems share one timer (ability id 231) that refills one charge at a time.
local STRATAGEM_ID = 231
local function stratagem_wait(timer_sec, sch_level)
    local per, maxc = 48, 5
    if sch_level < 30 then per, maxc = 240, 1
    elseif sch_level < 50 then per, maxc = 120, 2
    elseif sch_level < 70 then per, maxc = 80, 3
    elseif sch_level < 90 then per, maxc = 60, 5 end
    local charges = math.floor((per * maxc - timer_sec) / per)
    if charges >= 1 then return 0 end
    return timer_sec - per * (maxc - 1)
end

--- { key = seconds left } and { key = longest seen }, for every spell/ability we know the ids of.
local function read_recasts(rc, sch_level)
    local left, total = {}, {}
    if not rc then return left, total end
    local abil = {}
    for x = 0, 31 do
        local id, t = call(rc, 'GetAbilityTimerId', x), call(rc, 'GetAbilityTimer', x)
        if type(t) == 'number' and t > 0 and id and (id ~= 0 or x == 0) then abil[id] = t end
    end
    for key, v in pairs(ids) do
        local sec = 0
        if v.spell then
            local t = call(rc, 'GetSpellTimer', v.spell)
            if type(t) == 'number' and t > 0 then sec = t / 60 end
        elseif v.ability and abil[v.ability] then
            sec = abil[v.ability] / 60
            if v.ability == STRATAGEM_ID then sec = stratagem_wait(sec, sch_level) end
        end
        if sec > 0.05 then
            left[key] = sec
            peak[key] = math.max(peak[key] or 0, sec)
            total[key] = peak[key]
        else
            peak[key] = nil
        end
    end
    return left, total
end

--- Max from current and percent; falls back to the current value when the percent is unknown.
local function max_from(cur, pct)
    cur = cur or 0
    if pct and pct > 0 and cur > 0 then return math.max(cur, math.floor(cur * 100 / pct + 0.5)) end
    return math.max(cur, 1)
end

--- The roster for this frame: an array of members for every active slot (inactive slots omitted
-- the UI treats a missing slot as empty).
function game.roster(_, _)
    local out = {}
    local party, player, entity = managers()
    if not party then return out end

    local my_zone = call(party, 'GetMemberZone', 0)
    local d_keys, b_list = own_status(player)

    for slot = 0, 17 do
        if (call(party, 'GetMemberIsActive', slot) or 0) > 0 then
            local name = call(party, 'GetMemberName', slot) or ''
            local hp, hpp = call(party, 'GetMemberHP', slot) or 0, call(party, 'GetMemberHPPercent', slot) or 0
            local mp, mpp = call(party, 'GetMemberMP', slot) or 0, call(party, 'GetMemberMPPercent', slot) or 0
            local zone = call(party, 'GetMemberZone', slot)
            local is_you = (slot == 0)
            local zone_diff = (not is_you) and zone ~= nil and my_zone ~= nil and zone ~= my_zone

            local hpmax = max_from(hp, hpp)
            local mpmax = max_from(mp, mpp)
            if is_you then
                hpmax = call(player, 'GetHPMax') or hpmax
                mpmax = call(player, 'GetMPMax') or mpmax
            end

            local dist
            if is_you then
                dist = 0
            elseif not zone_diff then
                local idx = call(party, 'GetMemberTargetIndex', slot)
                if idx and idx > 0 then
                    local sq = call(entity, 'GetDistance', idx)
                    if type(sq) == 'number' and sq >= 0 then dist = math.sqrt(sq) end
                end
            end

            local md, mb
            if not is_you then
                md, mb = member_status(party, slot)
                if not md then md, mb = chatstatus.get(name) end   -- no party status data: use what the chat log said
            end

            out[#out + 1] = {
                slot = slot, active = true, name = name,
                job = call(party, 'GetMemberMainJob', slot) or 0,
                sub = call(party, 'GetMemberSubJob', slot) or 0,
                level = call(party, 'GetMemberMainJobLevel', slot) or 0,
                hp = hp, hpmax = hpmax, hpp = hpp,
                mp = mp, mpmax = mpmax, mpp = mpp,
                dist = dist, zone_diff = zone_diff or nil,
                dead = (not zone_diff) and hp == 0 and hpp == 0,
                debuffs = is_you and d_keys or md or {}, debuff_rem = {},
                buffs = is_you and b_list or mb or {}, has_buff_data = true,
                is_you = is_you,
            }
        end
    end
    return out
end

--- Your own state for button availability.
function game.player(_)
    local party, player, _, rc = managers()
    if not party then
        return { name = '', job = 0, sub = 0, level = 0, mp = 0, mpmax = 0, recast = {}, recast_total = {} }
    end
    local _, _, silenced, stopped = own_status(player)
    local level = call(player, 'GetMainJobLevel') or call(party, 'GetMemberMainJobLevel', 0) or 0
    local main = call(player, 'GetMainJob') or call(party, 'GetMemberMainJob', 0) or 0
    local sch_level = (main == 20) and level or (call(player, 'GetSubJobLevel') or 0)
    local recast, recast_total = read_recasts(rc, sch_level)
    return {
        name = call(party, 'GetMemberName', 0) or '',
        job = call(player, 'GetMainJob') or call(party, 'GetMemberMainJob', 0) or 0,
        sub = call(player, 'GetSubJob') or call(party, 'GetMemberSubJob', 0) or 0,
        level = level,
        sublevel = call(player, 'GetSubJobLevel'),
        mp = call(party, 'GetMemberMP', 0) or 0,
        mpmax = call(player, 'GetMPMax') or 0,
        silenced = silenced, incapacitated = stopped,
        recast = recast, recast_total = recast_total,
    }
end

--- /ch partydump: prints what the party memory says about status icons, so we can see how other
-- members' debuffs are laid out on this client. Read only. `emit(line)` gets each line.
--- Progress of the game's own cast bar, 0..1, or nil when it cannot be read.
function game.castbar()
    local core = _G.AshitaCore
    local mem = core and call(core, 'GetMemoryManager')
    local bar = mem and call(mem, 'GetCastBar')
    if not bar then return nil end
    local pct = call(bar, 'GetPercent')
    if type(pct) ~= 'number' then return nil end
    if pct > 1 then pct = pct / 100 end
    return math.max(0, math.min(1, pct))
end

function game.dump_status(emit)
    local party = managers()
    if not party then emit('partydump: party memory not available (not logged in?)'); return end
    local function show(v)
        local t = type(v)
        if t == 'table' then
            local parts = {}
            for k, x in pairs(v) do
                if x ~= 0 and x ~= 255 and x ~= -1 then parts[#parts + 1] = tostring(k) .. '=' .. tostring(x) end
                if #parts >= 24 then parts[#parts + 1] = '...'; break end
            end
            return 'table{' .. table.concat(parts, ',') .. '}'
        end
        return t .. ' ' .. tostring(v)
    end
    emit('--- partydump (slots 0-5) ---')
    for slot = 0, 5 do
        if (call(party, 'GetMemberIsActive', slot) or 0) > 0 then
            emit(string.format('slot %d %s: serverid=%s target=%s mask=%s', slot, tostring(call(party, 'GetMemberName', slot)),
                tostring(call(party, 'GetStatusIconsServerId', slot)), tostring(call(party, 'GetStatusIconsTargetIndex', slot)),
                tostring(call(party, 'GetStatusIconsBitMask', slot))))
            emit('  GetStatusIcons(' .. slot .. ') = ' .. show(call(party, 'GetStatusIcons', slot)))
        end
    end
    -- Flat-array layout probe: non-empty values across the first 5 x 32 entries.
    local flat = {}
    for i = 0, 159 do
        local v = call(party, 'GetStatusIcons', i)
        if type(v) == 'number' and v ~= 0 and v ~= 255 then flat[#flat + 1] = i .. '=' .. v end
    end
    emit('  flat GetStatusIcons(0..159) non-empty: ' .. (#flat > 0 and table.concat(flat, ' ') or '(none)'))
    emit('--- end partydump: cast a debuff on a party member, run again, and send both outputs ---')
end

return game
