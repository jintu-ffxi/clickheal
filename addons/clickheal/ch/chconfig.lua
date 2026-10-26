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
    demo             = false,       -- true = fake roster; false = your real party (read-only)
    queue_clicks     = true,        -- a click while casting is held and sent when you can act again
    fast_cast        = 0,           -- percent; shortens the estimated cast time (only used when the game's cast bar cannot be read)
    cast_lockout     = 1.0,         -- seconds after a cast or ability before the next one can start
    cast             = false,       -- true = a click really casts (/ma, /ja). Off until you turn it on. Ignored in demo mode.
    demo_fill        = false,       -- live data, but empty alliance slots are filled with demo members (log-only clicks)
    demo_alliance_debuffs = false,  -- demo only: pretend alliance debuffs are visible

    mode             = 'party',     -- party (6) | alliance1 (12) | alliance2 (18)
    orientation      = 'columns',   -- columns | stacked | rows
    hide_empty_groups = true,
    show_empty_slots = true,

    auto_scale       = true,        -- scale follows the game window height (1080 = 1.0, 2160 = 2.0)
    scale            = 1.0,         -- user multiplier on top of auto scale (or absolute when auto is off)
    fly_btn          = 36,          -- hover flyout button size (base px, scales with the game resolution)
    fly_gap          = 6,           -- space between flyout buttons (base px)
    row_w            = 230,         -- member row width (base px, scales with the game resolution)
    hl_row_h         = 54,          -- row height for the Hairline style (base px)
    row_h            = 42,          -- member row height, i.e. the HP bar (base px)
    debuff_icon      = 14,          -- debuff icon size (base px)
    buff_icon        = 14,          -- buff icon size (base px)
    mouse_fix        = false,       -- stretch the mouse to a resized game window (party frames only)
    ui_zoom          = 100,         -- setup window zoom, percent
    font_mult        = 1.1,         -- text size multiplier (ImGui's default font differs between setups)
    opacity          = 0.92,        -- member row background
    opacity_panel    = 0.74,        -- panel background and header strip
    opacity_hp       = 0.96,        -- HP fill / rail
    opacity_mp       = 0.95,        -- MP bar
    opacity_flyout   = 0.97,        -- hover flyout background

    pos              = { x = 40, y = 260 },
    alert_pos        = nil,         -- nil = centered near the top until the user moves it

    max_range        = 20.0,        -- yalms; beyond this the member counts as out of heal range
    warn_range       = 17.0,        -- yalms; distance turns yellow past this
    hp_crit          = 35,          -- percent; pulsing outline and an alert at or below this
    show_dist        = true,
    triage_opts      = {
        debuffs   = true,           -- debuffs you can remove raise a member's priority
        crit      = true,           -- HP at or below the critical threshold raises priority
        tiles     = 4,              -- number of spell tiles (3-5)
        list_icons = false,         -- the list of other members shows buff/debuff icons under each name
        list_h    = 18,             -- height of each row in that list (base px)
        spells    = {},             -- ordered spell keys to offer first for the featured member (empty = automatic)
        levels    = {},             -- debuff key -> 'urgent' | 'important' | 'off' (default by severity)
    },
    debug            = {            -- developer / testing switches (Debug page)
        force_debuffs = false,      -- give every member sample debuffs
        force_buffs   = false,      -- give every member sample buffs
        cursor        = false,      -- crosshair at the mouse position ImGui sees
        input         = false,      -- log where each click lands
    },
    group_colors     = {            -- background color of the party, alliance 1 and alliance 2 (r, g, b)
        { 0.40, 0.60, 1.00 }, { 0.35, 0.82, 0.66 }, { 0.92, 0.68, 0.30 },
    },
    group_alpha      = 0.12,        -- how strong those backgrounds are
    group_frames     = true,        -- a border and tint around each party (party, alliance 1, alliance 2)
    show_header      = true,        -- the CLICKHEAL / MOVE / CFG bar above the rows (shown anyway while unlocked)
    skin             = 'solid',     -- row style: solid (filled HP row) or hairline (type and a thin rail)
    triage           = false,       -- one panel for whoever needs healing most, plus a compact list
    hl_pct           = 2.0,         -- hairline: size of the big HP percentage
    show_mp          = true,
    mp_height        = 3,           -- MP bar thickness (base px)
    show_mp_pct      = false,       -- MP percent under the HP percent
    name_scale       = 1.0,         -- size of the player names
    mp_pct_scale     = 0.75,        -- size of that MP percent relative to the HP percent
    show_buff_bar    = true,        -- second strip of buff icons on each row
    buffs_mine_only  = true,        -- buff bar: only buffs your job can cast
    flyout_icons     = false,       -- flyout buttons show the spell's game icon (status icon / your own PNG) instead of text
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
    s.ui_zoom    = math.floor(clamp(s.ui_zoom, 60, 300, d.ui_zoom) + 0.5)
    s.font_mult  = clamp(s.font_mult, 0.6, 2.0, d.font_mult)
    s.slant = nil; s.job_icon = nil   -- options that no longer exist
    s.fly_btn    = math.floor(clamp(s.fly_btn, 24, 64, d.fly_btn) + 0.5)
    s.fly_gap    = math.floor(clamp(s.fly_gap, 2, 16, d.fly_gap) + 0.5)
    s.fast_cast  = math.floor(clamp(s.fast_cast, 0, 80, d.fast_cast) + 0.5)
    s.cast_lockout = clamp(s.cast_lockout, 0.3, 3.0, d.cast_lockout)
    s.row_w      = math.floor(clamp(s.row_w, 160, 360, d.row_w) + 0.5)
    s.row_h      = math.floor(clamp(s.row_h, 24, 72, d.row_h) + 0.5)
    s.hl_row_h   = math.floor(clamp(s.hl_row_h, 28, 90, d.hl_row_h) + 0.5)
    s.name_scale = clamp(s.name_scale, 0.8, 2.0, d.name_scale)
    s.mp_pct_scale = clamp(s.mp_pct_scale, 0.5, 1.0, d.mp_pct_scale)
    s.hl_pct     = clamp(s.hl_pct, 1.0, 3.0, d.hl_pct)
    s.mp_height  = math.floor(clamp(s.mp_height, 2, 14, d.mp_height) + 0.5)
    s.debuff_icon = math.floor(clamp(s.debuff_icon, 10, 32, d.debuff_icon) + 0.5)
    s.buff_icon  = math.floor(clamp(s.buff_icon, 10, 32, d.buff_icon) + 0.5)
    s.opacity    = clamp(s.opacity, 0.2, 1.0, d.opacity)
    s.opacity_panel  = clamp(s.opacity_panel, 0.0, 1.0, d.opacity_panel)
    s.opacity_hp     = clamp(s.opacity_hp, 0.2, 1.0, d.opacity_hp)
    s.opacity_mp     = clamp(s.opacity_mp, 0.2, 1.0, d.opacity_mp)
    s.opacity_flyout = clamp(s.opacity_flyout, 0.3, 1.0, d.opacity_flyout)
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
    do
        local d = chconfig.defaults.triage_opts
        local o = type(s.triage_opts) == 'table' and s.triage_opts or {}
        o.debuffs = (o.debuffs == nil) and d.debuffs or (o.debuffs and true or false)
        o.crit = (o.crit == nil) and d.crit or (o.crit and true or false)
        o.tiles = math.floor(clamp(o.tiles, 3, 5, d.tiles) + 0.5)
        o.list_icons = (o.list_icons == nil) and d.list_icons or (o.list_icons and true or false)
        o.list_h = math.floor(clamp(o.list_h, 14, 48, d.list_h) + 0.5)
        local list, seen = {}, {}
        for _, k in ipairs(type(o.spells) == 'table' and o.spells or {}) do
            if type(k) == 'string' and spells.defs[k] and not seen[k] then list[#list + 1] = k; seen[k] = true end
        end
        o.spells = list
        local lv = {}
        for k, v in pairs(type(o.levels) == 'table' and o.levels or {}) do
            if type(k) == 'string' and (v == 'urgent' or v == 'important' or v == 'off') then lv[k] = v end
        end
        o.levels = lv
        s.triage_opts = o
    end
    do
        local d = chconfig.defaults.debug
        local o = type(s.debug) == 'table' and s.debug or {}
        for k, v in pairs(d) do o[k] = (o[k] == nil) and v or (o[k] and true or false) end
        s.debug = o
    end
    do
        local d = chconfig.defaults.group_colors
        local o = type(s.group_colors) == 'table' and s.group_colors or {}
        local out = {}
        for i = 1, 3 do
            local c = type(o[i]) == 'table' and o[i] or {}
            out[i] = { clamp(c[1], 0, 1, d[i][1]), clamp(c[2], 0, 1, d[i][2]), clamp(c[3], 0, 1, d[i][3]) }
        end
        s.group_colors = out
        s.group_alpha = clamp(s.group_alpha, 0.03, 0.5, chconfig.defaults.group_alpha)
    end
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
    for _, k in ipairs({ 'flyout', 'spellbar', 'cell_binds', 'show_buff_bar', 'buffs_mine_only', 'buff_mode', 'cast', 'queue_clicks', 'show_mp_pct', 'mouse_fix', 'triage', 'demo_fill', 'flyout_icons', 'show_header', 'group_frames' }) do
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
