--[[
    ClickHeal - source_demo.lua
    Fake party/alliance data so the whole UI can be designed and tested with no game connection.
    This is also how the addon behaves in Phase 1: it never reads the game and never casts.

    Member shape (the real data source in Phase 2 must return the same shape):
      slot        0..17 (group * 6 + index)
      active      slot occupied
      name, job, sub, level
      hp, hpmax, hpp (0..100), mp, mpmax, mpp
      dist        yalms, or nil when unknown
      zone_diff   true when in a different zone
      dead        true when KO'd
      debuffs     array of debuff keys (see debuffs.lua)
      debuff_rem  debuff key -> seconds left (optional per key)
      buffs       array of { key, rem, total } (see buffs.lua); rem may be nil when unknown
      has_buff_data  false when the game does not expose this member's buffs (alliance parties)
      is_you
]]--

local demo = {}

-- slot, name, job, sub, hpmax, mpmax, dist, hp base %, extras
local ROSTER = {
    -- Your party
    { 0,  'Ayla',      3,  20, 1420, 1380, 0,    100 },
    { 1,  'Brannoch',  7,  1,  2400, 540,  6.2,  82  },
    { 2,  'Kessia',    4,  5,  1250, 1650, 14.1, 64, { debuffs = { 'silence' } } },
    { 3,  'Torvald',   12, 1,  2100, 300,  18.4, 28, { debuffs = { 'doom' } } },
    { 4,  'Miraeth',   10, 3,  1500, 900,  9.0,  91, { debuffs = { 'paralysis' } } },
    { 5,  'Dunstan',   11, 13, 1700, 450,  24.3, 55, { debuffs = { 'poison', 'blindness' } } },
    -- Alliance 1
    { 6,  'Elowen',    5,  4,  1480, 1200, 11.5, 97, { debuffs = { 'slow' } } },
    { 7,  'Garrick',   1,  12, 2300, 250,  15.8, 74, { debuffs = { 'poison' } } },
    { 8,  'Pip',       6,  19, 1550, 400,  21.0, 88 },
    { 9,  'Soraya',    3,  5,  1380, 1320, 8.4,  100 },
    { 10, 'Vexmoor',   8,  12, 2250, 380,  13.0, 0,  { dead = true } },
    { 11, 'Odalys',    15, 3,  1100, 1500, nil,  100, { zone_diff = true } },
    -- Alliance 2
    { 12, 'Hadrik',    2,  1,  2500, 200,  17.2, 69 },
    { 13, 'Lumi',      17, 11, 1450, 520,  10.1, 100 },
    { 14, 'Nox',       13, 1,  1900, 500,  19.4, 45, { debuffs = { 'paralysis' } } },
}

-- Demo buffs per slot: { key, cycle seconds, offset }. The timer counts down and restarts every cycle
-- so expiring pips (amber, then pulsing) can be seen. Alliance members have none (no buff data).
local BUFFS = {
    [0] = { { 'regen', 75, 10 }, { 'protect', 120, 70 }, { 'shell', 120, 70 }, { 'stoneskin', 90, 30 } },
    [1] = { { 'haste', 100, 20 }, { 'regen', 60, 50 }, { 'protect', 120, 5 }, { 'shell', 120, 5 }, { 'stoneskin', 80, 75 } },
    [2] = { { 'haste', 100, 60 }, { 'refresh', 90, 0 }, { 'protect', 120, 40 }, { 'shell', 120, 40 } },
    [3] = { { 'haste', 100, 90 }, { 'regen', 40, 12 }, { 'protect', 120, 100 } },
    [4] = { { 'haste', 100, 35 }, { 'protect', 120, 15 }, { 'shell', 120, 15 }, { 'blink', 90, 12 } },
    [5] = { { 'regen', 50, 20 }, { 'protect', 120, 2 }, { 'shell', 120, 2 } },
}
local DEBUFF_CYCLE = { doom = 12, poison = 60, blindness = 90, silence = 45, paralysis = 50, slow = 70 }

local function cycle(len, offset, t)
    return len - ((t + offset) % len)
end

-- A few alliance debuffs shown only when the "alliance debuffs visible" demo option is on.
local ALLIANCE_DEBUFFS = {}

local function pct_wobble(base, slot, t)
    -- Gentle, deterministic HP movement so bars and pulses visibly change.
    if base >= 100 or base <= 0 then return base end
    local v = base + 6 * math.sin(t * 0.6 + slot * 1.7)
    if v < 3 then v = 3 elseif v > 100 then v = 100 end
    return math.floor(v + 0.5)
end

--- Returns the roster as an array (only occupied slots) for time `t`.
function demo.roster(t, cfg)
    local out = {}
    for _, r in ipairs(ROSTER) do
        local slot, name, job, sub, hpmax, mpmax, dist, base, extra = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] or {}
        local hpp = extra.dead and 0 or pct_wobble(base, slot, t)
        local in_party = slot < 6
        local visible_debuffs = in_party or (cfg and cfg.demo_alliance_debuffs)
        local m = {
            slot = slot, active = true, name = name, job = job, sub = sub, level = 75,
            hp = math.floor(hpmax * hpp / 100), hpmax = hpmax, hpp = hpp,
            mp = mpmax, mpmax = mpmax, mpp = 100,
            dist = dist, zone_diff = extra.zone_diff or false, dead = extra.dead or false,
            debuffs = visible_debuffs and (extra.debuffs or {}) or {},
            has_buff_data = visible_debuffs and true or false,
            is_you = (slot == 0),
            buffs = {}, debuff_rem = {},
        }
        if in_party then
            for _, b in ipairs(BUFFS[slot] or {}) do
                m.buffs[#m.buffs + 1] = { key = b[1], rem = cycle(b[2], b[3], t), total = b[2] }
            end
        end
        for _, k in ipairs(m.debuffs) do
            local len = DEBUFF_CYCLE[k]
            if len then m.debuff_rem[k] = cycle(len, slot * 7, t) end
        end
        out[#out + 1] = m
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Player state: MP, recasts, silence. Clicking in demo mode starts a fake recast so the cooldown
-- overlay and the "not enough MP" state can be seen working.
-- ---------------------------------------------------------------------------------------------
local state = { mp_spent = 0, cast_at = {}, last_t = 0, recast_len = {} }

function demo.reset()
    state.mp_spent, state.cast_at, state.last_t, state.recast_len = 0, {}, 0, {}
end

--- Player state at time t.
function demo.player(t)
    -- MP slowly regenerates; spent MP decays back.
    local dt = t - state.last_t
    if dt > 0 then
        state.mp_spent = math.max(0, state.mp_spent - dt * 6)
        state.last_t = t
    end
    local recast = {}
    for key, at in pairs(state.cast_at) do
        local left = (state.recast_len[key] or 5) - (t - at)
        if left > 0 then recast[key] = left else state.cast_at[key] = nil end
    end
    return {
        name = 'Ayla', job = 3, sub = 20, level = 75, sublevel = 37,
        mp = math.max(0, 1380 - state.mp_spent), mpmax = 1380,
        silenced = false, incapacitated = false,
        recast = recast, recast_total = state.recast_len,
    }
end

--- Called by actions.lua instead of casting. Starts a fake recast and spends MP.
function demo.cast(def, t)
    state.cast_at[def.key] = t
    state.recast_len[def.key] = def.recast or 5
    state.mp_spent = state.mp_spent + (def.mp or 0)
end

return demo
