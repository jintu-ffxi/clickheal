--[[
    ClickHeal - livebuffs.lua
    Other members' status effects, read straight from the packets the server sends (read only: nothing is
    sent, blocked or changed). Pure: clickheal.lua feeds it each incoming packet.

      0x076  party status effects. Five 48-byte entries from offset 4: server id (4), target index (2),
             2 unused, a 64-bit mask (2 extra high bits per effect), 32 effect bytes (255 = empty).
             The effect id is the byte + 256 * its two mask bits.
      0x029  action message. Wear-off messages (64, 204, 206) carry the effect id in param 1, so a
             wearing-off effect disappears at once instead of waiting for the next 0x076.
      0x00A  zone change: everything forgotten.

    This is the preferred source. The game's own party memory is the next choice, then the chat log
    (chatstatus.lua), which is what trusts and anyone the server sends no status packet for still use.
]]--

local live = {}

local state = {}                       -- server id -> { ids = { effect id = true }, t = time }
live.packets = 0                       -- 0x076 packets seen, for /ch status

local WEAR_OFF = { [64] = true, [204] = true, [206] = true }

local function u8(d, i) return d:byte(i + 1) or 0 end
local function u16(d, i) return u8(d, i) + 256 * u8(d, i + 1) end
local function u32(d, i) return u16(d, i) + 65536 * u16(d, i + 2) end

--- Feeds one incoming packet (`id` = packet id, `data` = the raw bytes as a string).
-- Returns true when it changed what is tracked.
function live.feed(id, data, now)
    if type(data) ~= 'string' then return false end
    now = now or os.clock()
    if id == 0x076 then
        if #data < 4 + 48 then return false end
        live.packets = live.packets + 1
        local changed = false
        for n = 0, 4 do
            local base = 4 + n * 48
            if base + 48 > #data then break end
            local uid = u32(data, base)
            if uid ~= 0 then
                local ids = {}
                for i = 0, 31 do
                    local v = u8(data, base + 16 + i)
                    if v ~= 255 then
                        local hi = math.floor(u8(data, base + 8 + math.floor(i / 4)) / 4 ^ (i % 4)) % 4
                        ids[v + 256 * hi] = true
                    end
                end
                state[uid] = { ids = ids, t = now }   -- a new entry also drops the cached list
                changed = true
            end
        end
        return changed
    end
    if id == 0x029 then
        if #data < 0x1A then return false end
        local msg = u16(data, 0x18)
        if not WEAR_OFF[msg] then return false end
        local e = state[u32(data, 0x08)]
        local eff = u32(data, 0x0C)
        if e and e.ids[eff] then e.ids[eff] = nil; e.list = nil; return true end
        return false
    end
    if id == 0x00A then live.reset(); return true end
    return false
end

--- The effect ids known for a server id, as a sorted list, or nil when no status packet has named this member.
-- The list is built once per change and shared between calls: treat it as read-only.
function live.get(uid)
    local e = uid and state[uid]
    if not e then return nil end
    local out = e.list
    if not out then
        out = {}
        for id in pairs(e.ids) do out[#out + 1] = id end
        table.sort(out)
        e.list = out
    end
    return out
end

function live.reset() state = {} end

--- How many members have a packet-fed entry (for /ch status).
function live.count()
    local n = 0
    for _ in pairs(state) do n = n + 1 end
    return n
end

return live
