--[[
    ClickHeal - chconfig.lua
    Default settings and validation. (Named chconfig rather than "settings" so it can never be
    confused with Ashita's own `settings` library.)
]]--

local bindings = require('ch.bindings')
local spells   = require('ch.spells')

local chconfig = {}

chconfig.defaults = {
    visible          = true,
    locked           = true,        -- locked = clickable and fixed in place; unlocked = drag to move, clicks off
    demo             = true,        -- true = fake roster; false = your real party (read-only)
    cast             = false,       -- true = a click really casts (/ma, /ja). Off until you turn it on. Ignored in demo mode.
    demo_alliance_debuffs = false,  -- demo only: pretend alliance debuffs are visible

    style            = 'strip',      -- full | compact | minimal | grid | strip
    mode             = 'party',     -- party (6) | alliance1 (12) | alliance2 (18)
    orientation      = 'columns',   -- columns | stacked | rows
    hide_empty_groups = true,
    show_empty_slots = true,

    auto_scale       = true,        -- scale follows the game window height (1080 = 1.0, 2160 = 2.0)
    scale            = 1.0,         -- user multiplier on top of auto scale (or absolute when auto is off)
    slant            = 0,           -- strip rows: how far the top edge leans (base px). 0 = square, rounded rows
    fly_btn          = 36,          -- hover flyout button size (base px, scales with the game resolution)
    fly_gap          = 6,           -- space between flyout buttons (base px)
    font_mult        = 1.0,         -- text size multiplier (ImGui's default font differs between setups)
    opacity          = 0.92,

    pos              = { x = 40, y = 260 },
    alert_pos        = nil,         -- nil = centered near the top until the user moves it

    max_range        = 20.0,        -- yalms; beyond this the member counts as out of heal range
    warn_range       = 17.0,        -- yalms; distance turns yellow past this
    hp_crit          = 35,          -- percent; pulsing outline and an alert at or below this
    show_dist        = true,
    show_job         = true,
    show_mp          = true,
    show_buffs       = true,        -- buff pip strip on full cards
    buffs_mine_only  = true,        -- only buffs your job can cast
    show_timers      = true,        -- seconds left on debuff chips and buff pips
    job_style        = 'text',      -- text (WHM/SCH 99) | tag (chip + sub job)
    flyout           = true,        -- Grid / Strip: hover a member to open their spell flyout
    spell_order      = {},          -- group -> ordered spell keys (same for every member); empty = job default
    spellbar         = false,       -- optional shared spell bar under the Grid / Strip cells
    bar_tab          = 'heal',      -- heal | cleanse | buff | raise
    cell_binds       = false,       -- Grid / Strip: plain clicks on a cell cast the bound spell (see bindings)
    buff_mode        = false,       -- spell row shows buffs instead of heals/cleanses

    bindings         = {},          -- Grid layout overrides: slot -> spell key | 'cleanse' | '-'

    colors           = 'modern',    -- modern | mono | colorblind

    alerts = {
        enabled   = false,          -- the separate alert window is optional; debuffs live on the cards
        max       = 4,
        pulse     = true,
        hp_alert  = true,
        raise_alert = true,
        muted     = {},             -- debuff key -> true to silence its alert
    },
}

chconfig.enums = {
    style       = { 'full', 'compact', 'minimal', 'grid', 'strip' },
    mode        = { 'party', 'alliance1', 'alliance2' },
    orientation = { 'columns', 'stacked', 'rows' },
    colors      = { 'modern', 'mono', 'colorblind' },
    job_style   = { 'text', 'tag' },
    bar_tab     = { 'heal', 'cleanse', 'buff', 'raise' },
}

local function contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function clamp(v, lo, hi, fallback)
    if type(v) ~= 'number' or v ~= v then return fallback end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Fills missing keys from `defaults` (deep) without touching values that already exist.
function chconfig.fill(dst, defaults)
    for k, v in pairs(defaults) do
        if dst[k] == nil then
            if type(v) == 'table' then
                dst[k] = {}
                chconfig.fill(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == 'table' and type(dst[k]) == 'table' then
            chconfig.fill(dst[k], v)
        end
    end
    return dst
end

--- Repairs bad values (hand-edited files, old versions). Safe to call repeatedly.
function chconfig.sanitize(s)
    local d = chconfig.defaults
    chconfig.fill(s, d)

    for key, list in pairs(chconfig.enums) do
        if not contains(list, s[key]) then s[key] = d[key] end
    end

    s.scale      = clamp(s.scale, 0.5, 4.0, d.scale)
    s.font_mult  = clamp(s.font_mult, 0.6, 2.0, d.font_mult)
    s.slant      = math.floor(clamp(s.slant, 0, 16, d.slant) + 0.5)
    s.fly_btn    = math.floor(clamp(s.fly_btn, 24, 64, d.fly_btn) + 0.5)
    s.fly_gap    = math.floor(clamp(s.fly_gap, 2, 16, d.fly_gap) + 0.5)
    s.opacity    = clamp(s.opacity, 0.2, 1.0, d.opacity)
    s.max_range  = clamp(s.max_range, 5, 50, d.max_range)
    s.warn_range = clamp(s.warn_range, 1, s.max_range, d.warn_range)
    s.hp_crit    = clamp(s.hp_crit, 5, 95, d.hp_crit)
    s.alerts.max = math.floor(clamp(s.alerts.max, 1, 8, d.alerts.max))

    if type(s.pos) ~= 'table' or type(s.pos.x) ~= 'number' or type(s.pos.y) ~= 'number' then
        s.pos = { x = d.pos.x, y = d.pos.y }
    end
    if s.alert_pos ~= nil and (type(s.alert_pos) ~= 'table'
        or type(s.alert_pos.x) ~= 'number' or type(s.alert_pos.y) ~= 'number') then
        s.alert_pos = nil
    end
    if type(s.alerts.muted) ~= 'table' then s.alerts.muted = {} end
    if type(s.spell_order) ~= 'table' then s.spell_order = {} end
    local groups = { heal = true, cleanse = true, buff = true, raise = true, song = true, ability = true }
    for group, list in pairs(s.spell_order) do
        if not groups[group] or type(list) ~= 'table' then
            s.spell_order[group] = nil
        else
            local clean, seen = {}, {}
            for _, k in ipairs(list) do
                if type(k) == 'string' and spells.defs[k] and not seen[k] then clean[#clean + 1] = k; seen[k] = true end
            end
            s.spell_order[group] = (#clean > 0) and clean or nil
        end
    end
    if type(s.bindings) ~= 'table' then s.bindings = {} end
    for slot, v in pairs(s.bindings) do
        if not bindings.is_slot(slot) or not bindings.valid_value(v) then s.bindings[slot] = nil end
    end
    for _, k in ipairs({ 'flyout', 'spellbar', 'cell_binds', 'show_buffs', 'buffs_mine_only', 'show_timers', 'buff_mode', 'cast' }) do
        s[k] = s[k] and true or false
    end
    return s
end

--- Restores every setting to its default, in place (keeps the same table so references stay valid).
function chconfig.reset(s)
    for k in pairs(s) do s[k] = nil end
    chconfig.fill(s, chconfig.defaults)
    return chconfig.sanitize(s)
end

--- Number of party groups each mode shows.
chconfig.group_count = { party = 1, alliance1 = 2, alliance2 = 3 }

return chconfig
