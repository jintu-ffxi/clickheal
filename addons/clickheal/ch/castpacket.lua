--[[
    ClickHeal - castpacket.lua
    Reads the server's action packet (0x028) far enough to tell when YOUR cast starts, is interrupted or lands.
    Read only, and pure: clickheal.lua feeds it each incoming packet.

    The packet is a bit-packed record (bits numbered from the least significant bit of each byte, little endian),
    starting at bit 40:
        actor id 32 | target count 10 | category 4 | param 16 + 16 (spells, items) or 32 | recast 32 |
        then per target: id 32 | action count 4 | per action: reaction 5, animation 12, effect 7, knockback 3, param 17 ...

    Your own casts, by category:
        8 (magic) or 9 (item) with param 0x6163 (24931)  -> the cast began; the first action's param is the spell / item id
        8 or 9 with param 28787                           -> interrupted
        4 (magic) or 5 (item)                             -> the cast landed

    UNVERIFIED against a live client (the constants are the ones other Ashita and Windower addons use). If the layout
    is wrong, nothing here matches and casting.lua keeps using its estimate and the game's cast bar, as before.
]]--

local spells = require('ch.spells')
local ids    = require('ch.spell_ids')

local castpacket = {}

castpacket.CAST_BEGIN, castpacket.CAST_BROKE = 0x6163, 28787

local floor = math.floor

--- `n` bits from bit position `pos` (0 = least significant bit of the first byte), or nil past the end of the data.
local function bits(data, pos, n)
    if pos + n > #data * 8 then return nil end
    local v, scale = 0, 1
    for k = pos, pos + n - 1 do
        local byte = data:byte(floor(k / 8) + 1)
        if floor(byte / 2 ^ (k % 8)) % 2 == 1 then v = v + scale end
        scale = scale * 2
    end
    return v
end
castpacket.bits = bits

--- Who acted: the 32 bits at bit 40 are four whole bytes, so this is cheap. Action packets arrive for everything that
-- happens nearby, and almost all of them are not ours.
function castpacket.actor(data)
    if type(data) ~= 'string' or #data < 9 then return nil end
    local a, b, c, d = data:byte(6, 9)
    return a + 256 * b + 65536 * c + 16777216 * d
end

--- { actor, category, param, first } for an action packet, or nil when it is too short to read.
-- `first` is the first action's param (the spell id when a cast begins), nil when the packet has no target.
function castpacket.parse(data)
    if type(data) ~= 'string' then return nil end
    local actor = castpacket.actor(data)
    local ntargets = bits(data, 72, 10)
    local category = bits(data, 82, 4)
    if not (actor and ntargets and category) then return nil end
    local param = bits(data, 86, (category == 8 or category == 9) and 16 or 32)
    if not param then return nil end
    local first
    if ntargets > 0 and (bits(data, 182, 4) or 0) > 0 then first = bits(data, 213, 17) end
    return { actor = actor, category = category, param = param, first = first }
end

local key_by_spell
--- The spell key for a game spell id (nil when ClickHeal has no such spell).
function castpacket.key_for(spell_id)
    if not key_by_spell then
        key_by_spell = {}
        for key, v in pairs(ids) do
            if v.spell and spells.defs[key] then key_by_spell[v.spell] = key end
        end
    end
    return key_by_spell[spell_id]
end

--- What a parsed packet means for `my_id`'s casting: 'begin' (with a spell def when known), 'broke', 'landed' or nil.
function castpacket.classify(p, my_id)
    if not p or not my_id or p.actor ~= my_id then return nil end
    local c = p.category
    if (c == 8 or c == 9) and p.param == castpacket.CAST_BEGIN then
        local key = (c == 8 and p.first) and castpacket.key_for(p.first) or nil
        return 'begin', key and spells.defs[key] or nil
    elseif (c == 8 or c == 9) and p.param == castpacket.CAST_BROKE then
        return 'broke'
    elseif c == 4 or c == 5 then
        return 'landed'
    end
    return nil
end

return castpacket
