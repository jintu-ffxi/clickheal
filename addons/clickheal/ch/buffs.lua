--[[
    ClickHeal - buffs.lua
    Buff pips on the member cards: names, which buffs to show, and how urgent a timer is.

    Everything here is display data. Real buff ids and durations are read in Phase 2; the `total`
    values are only used by the demo and as the full length of a shrinking timer line when the game
    does not report one.
]]--

local spells = require('ch.spells')

local buffs = {}

-- key -> short pip label, full label, typical duration in seconds (placeholder).
buffs.info = {
    haste     = { short = 'Hst', label = 'Haste',     total = 180 },
    regen     = { short = 'Rgn', label = 'Regen',     total = 75  },
    refresh   = { short = 'Rfr', label = 'Refresh',   total = 150 },
    flurry    = { short = 'Flr', label = 'Flurry',    total = 180 },
    protect   = { short = 'Pro', label = 'Protect',   total = 1800 },
    shell     = { short = 'Shl', label = 'Shell',     total = 1800 },
    phalanx   = { short = 'Phx', label = 'Phalanx',   total = 180 },
    stoneskin = { short = 'Ssk', label = 'Stoneskin', total = 300 },
    blink     = { short = 'Bnk', label = 'Blink',     total = 300 },
    aquaveil  = { short = 'Aqv', label = 'Aquaveil',  total = 600 },
    sneak     = { short = 'Snk', label = 'Sneak',     total = 300 },
    invisible = { short = 'Inv', label = 'Invisible', total = 300 },
    reraise   = { short = 'RR',  label = 'Reraise',   total = 3600 },
}

-- Status effect ids, for the game's own icons (see source_game.lua; unverified on this server).
buffs.id_of = {
    haste = 33, regen = 42, refresh = 43, flurry = 581, protect = 40, shell = 41, phalanx = 116,
    stoneskin = 37, blink = 36, aquaveil = 39, sneak = 71, invisible = 69, reraise = 113,
}

-- Fixed display order, so pips never jump around when a timer changes.
buffs.order = {
    'haste', 'flurry', 'regen', 'refresh', 'protect', 'shell', 'phalanx', 'stoneskin',
    'blink', 'aquaveil', 'sneak', 'invisible', 'reraise',
}

buffs.SOON   = 30   -- seconds: pip turns amber
buffs.URGENT = 10   -- seconds: pip pulses

--- Set of buff keys the preset's buff spells can apply (the "my buffs" filter).
function buffs.castable_set(preset)
    local set, n = {}, 0
    for _, key in ipairs(preset and preset.buffs or {}) do
        local def = spells.defs[key]
        if def and def.buff then set[def.buff] = true; n = n + 1 end
    end
    return set, n
end

--- The spell a click on a pip recasts: the first matching spell in the preset's buff list.
function buffs.recast_spell(buff_key, preset)
    for _, key in ipairs(preset and preset.buffs or {}) do
        local def = spells.defs[key]
        if def and def.buff == buff_key then return key end
    end
    return nil
end

--- Buffs to draw for a member, in display order: { { key, info, rem, total }, ... }.
-- `mine_only` keeps buffs your job can cast (falls back to all when the job casts none).
function buffs.list(m, cfg, preset)
    local out = {}
    if not m or m.dead or not m.has_buff_data or not m.buffs then return out end
    local mine, n = buffs.castable_set(preset)
    local filter = cfg.buffs_mine_only and n > 0
    local by_key = {}
    for _, b in ipairs(m.buffs) do by_key[b.key] = b end
    for _, key in ipairs(buffs.order) do
        local b = by_key[key]
        if b and buffs.info[key] and (not filter or mine[key]) then
            out[#out + 1] = { key = key, info = buffs.info[key], rem = b.rem, total = b.total or buffs.info[key].total }
        end
    end
    return out
end

--- 'long' | 'soon' | 'urgent' | 'none' (no timer known).
function buffs.urgency(rem)
    if not rem then return 'none' end
    if rem <= buffs.URGENT then return 'urgent' end
    if rem <= buffs.SOON then return 'soon' end
    return 'long'
end

--- 0:42 style time; hours and minutes collapse to "12m" / "1h" for long timers.
function buffs.fmt(sec)
    if not sec then return '' end
    sec = math.max(0, math.ceil(sec))
    if sec >= 3600 then return string.format('%dh', math.floor(sec / 3600)) end
    if sec >= 600 then return string.format('%dm', math.floor(sec / 60)) end
    return string.format('%d:%02d', math.floor(sec / 60), sec % 60)
end

return buffs
