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
    queue_clicks     = true,        -- a click while casting is held and sent when you can act again
    fast_cast        = 0,           -- percent; shortens the estimated cast time (only used when the game's cast bar cannot be read)
    cast_lockout     = 1.0,         -- seconds after a cast or ability before the next one can start
    cast             = false,       -- true = a click really casts (/ma, /ja). Off until you turn it on. Ignored in demo mode.
    demo_alliance_debuffs = false,  -- demo only: pretend alliance debuffs are visible

    mode             = 'party',     -- party (6) | alliance1 (12) | alliance2 (18)
    orientation      = 'columns',   -- columns | stacked | rows
    hide_empty_groups = true,
    show_empty_slots = true,

    auto_scale       = true,        -- scale follows the game window height (1080 = 1.0, 2160 = 2.0)
    scale            = 1.0,         -- user multiplier on top of auto scale (or absolute when auto is off)
    slant            = 0,           -- strip rows: how far the top edge leans (base px). 0 = square, rounded rows
    fly_btn          = 36,          -- hover flyout button size (base px, scales with the game resolution)
    fly_gap          = 6,           -- space between flyout buttons (base px)
    row_w            = 230,         -- member row width (base px, scales with the game resolution)
    row_h            = 42,          -- member row height, i.e. the HP bar (base px)
    debuff_icon      = 14,          -- debuff icon size (base px)
    buff_icon        = 14,          -- buff icon size (base px)
    font_mult        = 1.0,         -- text size multiplier (ImGui's default font differs between setups)
    opacity          = 0.92,

    pos              = { x = 40, y = 260 },
    alert_pos        = nil,         -- nil = centered near the top until the user moves it

    max_range        = 20.0,        -- yalms; beyond this the member counts as out of heal range
    warn_range       = 17.0,        -- yalms; distance turns yellow past this
    hp_crit          = 35,          -- percent; pulsing outline and an alert at or below this
    show_dist        = true,
    skin             = 'solid',     -- row style: solid (filled HP row) or hairline (type and a thin rail)
    triage           = false,       -- one panel for whoever needs healing most, plus a compact list
    pct_scale        = 1.6,         -- hairline: size of the big HP percentage
    show_mp          = true,
    mp_height        = 3,           -- MP bar thickness (base px)
    show_mp_pct      = false,       -- MP percent under the HP percent
    mp_pct_scale     = 0.75,        -- size of that MP percent relative to the HP percent
    job_icon         = false,       -- the job block shows a pictogram instead of the letters (WHM)
    show_buff_bar    = true,        -- second strip of buff icons on each row
    buffs_mine_only  = true,        -- buff bar: only buffs your job can cast
    flyout           = true,        -- hover a member to open their spell flyout
    spell_order      = {},          -- group -> ordered spell keys (same for every member); empty = job default
    spellbar         = false,       -- optional shared spell bar under the rows
    bar_tab          = 'heal',      -- heal | cleanse | buff | raise
    cell_binds       = false,       -- plain clicks on a row cast the bound spell (see bindings)
    buff_mode        = false,       -- spell row shows buffs instead of heals/cleanses

    bindings         = {},          -- click-binding overrides: slot -> spell key | 'cleanse' | '-'

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
    mode        = { 'party', 'alliance1', 'alliance2' },
    orientation = { 'columns', 'stacked', 'rows' },
    colors      = { 'modern', 'job', 'mono', 'colorblind' },
    skin        = { 'solid', 'hairline' },
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
    s.fast_cast  = math.floor(clamp(s.fast_cast, 0, 80, d.fast_cast) + 0.5)
    s.cast_lockout = clamp(s.cast_lockout, 0.3, 3.0, d.cast_lockout)
    s.row_w      = math.floor(clamp(s.row_w, 160, 360, d.row_w) + 0.5)
    s.row_h      = math.floor(clamp(s.row_h, 30, 72, d.row_h) + 0.5)
    s.mp_pct_scale = clamp(s.mp_pct_scale, 0.5, 1.0, d.mp_pct_scale)
    s.pct_scale  = clamp(s.pct_scale, 1.0, 2.2, d.pct_scale)
    s.mp_height  = math.floor(clamp(s.mp_height, 2, 14, d.mp_height) + 0.5)
    s.debuff_icon = math.floor(clamp(s.debuff_icon, 10, 32, d.debuff_icon) + 0.5)
    s.buff_icon  = math.floor(clamp(s.buff_icon, 10, 32, d.buff_icon) + 0.5)
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
    for _, k in ipairs({ 'flyout', 'spellbar', 'cell_binds', 'show_buff_bar', 'buffs_mine_only', 'buff_mode', 'cast', 'queue_clicks', 'job_icon', 'show_mp_pct', 'triage' }) do
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
