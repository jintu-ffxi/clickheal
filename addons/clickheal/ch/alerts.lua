--[[
    ClickHeal - alerts.lua
    Builds the priority notification list: debuffs that need curing, critical HP, and KO'd members.
    Alerts only SUGGEST. Nothing is ever cast unless the user clicks.

    Alert shape:
      { id, kind = 'debuff'|'hp'|'dead', slot, name, text, spell = key|nil, sev = 1..3, in_range, hpp }
]]--

local debuffs = require('ch.debuffs')
local spells  = require('ch.spells')

local alerts = {}

--- roster    : array of member tables
--- cfg       : settings
--- preset    : spell preset for the player (used to pick the best cure for HP alerts)
--- now       : seconds
--- dismissed : table id -> expire time (right-click dismiss)
function alerts.build(roster, cfg, preset, now, dismissed)
    local a = cfg.alerts
    local out = {}
    if not a.enabled then return out end
    dismissed = dismissed or {}

    -- Best (highest) cure the preset offers for the "low HP" suggestion.
    local best_cure
    for _, key in ipairs(preset.base or {}) do
        local def = spells.defs[key]
        if def and def.kind == 'cure' then best_cure = key; break end
    end

    for _, m in ipairs(roster) do
        if m.active and not m.zone_diff then
            local in_range = not (m.dist and m.dist > cfg.max_range)

            if m.dead then
                if a.raise_alert then
                    out[#out + 1] = {
                        id = m.slot .. ':dead', kind = 'dead', slot = m.slot, name = m.name,
                        text = 'is KO', spell = 'raise1', sev = 3, in_range = in_range, hpp = 0,
                    }
                end
            else
                if m.has_buff_data and m.debuffs then
                    for _, key in ipairs(m.debuffs) do
                        local info = debuffs.info[key]
                        if info and not a.muted[key] then
                            out[#out + 1] = {
                                id = m.slot .. ':' .. key, kind = 'debuff', slot = m.slot, name = m.name,
                                text = info.label, spell = info.spell or info.suggest, sev = info.sev,
                                in_range = in_range, hpp = m.hpp,
                            }
                        end
                    end
                end
                if a.hp_alert and m.hpp and m.hpp <= cfg.hp_crit then
                    out[#out + 1] = {
                        id = m.slot .. ':hp', kind = 'hp', slot = m.slot, name = m.name,
                        text = string.format('HP %d%%', math.floor(m.hpp)), spell = best_cure, sev = 2,
                        in_range = in_range, hpp = m.hpp,
                    }
                end
            end
        end
    end

    -- Drop dismissed alerts that have not expired yet.
    local kept = {}
    for _, al in ipairs(out) do
        local exp = dismissed[al.id]
        if not (exp and exp > now) then kept[#kept + 1] = al end
    end

    -- Most severe first, in-range before out-of-range, lower HP first, then slot for stability.
    table.sort(kept, function(x, y)
        if x.sev ~= y.sev then return x.sev < y.sev end
        if x.in_range ~= y.in_range then return x.in_range end
        local hx, hy = x.hpp or 100, y.hpp or 100
        if hx ~= hy then return hx < hy end
        if x.slot ~= y.slot then return x.slot < y.slot end
        return x.id < y.id
    end)

    local limited = {}
    for i = 1, math.min(#kept, a.max) do limited[i] = kept[i] end
    return limited, #kept
end

return alerts
