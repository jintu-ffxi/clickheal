-- Test helpers that build the server packets the addon reads. Shared by tests/run.lua and tests/smoke_ashita.lua.
local packets = {}

--- Builds an action packet bit by bit (least significant bit first), laid out like the real one.
function packets.action_packet(actor, category, param, first)
    local bitsout = {}
    local function put(value, n) for k = 0, n - 1 do bitsout[#bitsout + 1] = math.floor(value / 2 ^ k) % 2 end end
    for _ = 1, 40 do bitsout[#bitsout + 1] = 0 end            -- packet header
    put(actor, 32)
    put(first and 1 or 0, 10)                                  -- target count
    put(category, 4)
    if category == 8 or category == 9 then put(param, 16); put(0, 16) else put(param, 32) end
    put(0, 32)                                                 -- recast
    if first then
        put(0x01020304, 32)                                    -- target id
        put(1, 4)                                              -- action count
        put(0, 27)                                             -- reaction, animation, effect, knockback
        put(first, 17); put(0, 10); put(0, 31); put(0, 1); put(0, 1)
    end
    while #bitsout % 8 ~= 0 do bitsout[#bitsout + 1] = 0 end
    local bytes = {}
    for b = 0, #bitsout / 8 - 1 do
        local v = 0
        for k = 0, 7 do v = v + bitsout[b * 8 + k + 1] * 2 ^ k end
        bytes[#bytes + 1] = string.char(v)
    end
    return table.concat(bytes)
end

return packets
