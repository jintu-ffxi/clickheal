--[[
    ClickHeal - source_mixed.lua
    Live data for your real party, plus demo members in the alliance slots (6..17) that the game leaves empty.
    Lets you see and test the alliance layout without being in an alliance. Demo members carry `demo = true`;
    actions.lua never sends a command for a click on one.
]]--

local game = require('ch.source_game')
local demo = require('ch.source_demo')

local mixed = {}

--- Real roster, with demo members added for every empty alliance slot.
function mixed.roster(t, cfg)
    local out = game.roster(t, cfg)
    local taken = {}
    for _, m in ipairs(out) do taken[m.slot] = true end
    for _, m in ipairs(demo.roster(t, cfg)) do
        if m.slot >= 6 and not taken[m.slot] then
            m.demo = true
            out[#out + 1] = m
        end
    end
    return out
end

function mixed.player(t) return game.player(t) end

function mixed.castbar()
    if game.castbar then return game.castbar() end
    return nil
end

return mixed
