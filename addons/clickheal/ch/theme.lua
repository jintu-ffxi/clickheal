--[[
    ClickHeal - theme.lua
    Colors are stored as packed integers in ImGui's IM_COL32 layout (A<<24 | B<<16 | G<<8 | R)
    so they can be cached, compared and alpha-adjusted without allocating tables every frame.
    Pure Lua: no Ashita or ImGui dependencies.

    Design rule for every preset: the base UI is neutral (greys + one cool accent) and COLOR MEANS
    SOMETHING. Amber and red appear only when a member is hurt, out of range, debuffed or in an
    alert, so when color does show up it is worth looking at.
]]--

local theme = {}

local floor = math.floor

local function q(x)
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    return floor(x * 255 + 0.5)
end

--- Packs float components (0..1) into one integer.
function theme.pack(r, g, b, a)
    if a == nil then a = 1 end
    return q(a) * 16777216 + q(b) * 65536 + q(g) * 256 + q(r)
end

--- Unpacks into float components (0..1): r, g, b, a
function theme.unpack(c)
    local r = c % 256
    local g = floor(c / 256) % 256
    local b = floor(c / 65536) % 256
    local a = floor(c / 16777216) % 256
    return r / 255, g / 255, b / 255, a / 255
end

--- Multiplies the alpha of a packed color.
function theme.alpha(c, mult)
    local r, g, b, a = theme.unpack(c)
    return theme.pack(r, g, b, a * mult)
end

--- Replaces the alpha of a packed color.
function theme.with_alpha(c, a)
    local r, g, b = theme.unpack(c)
    return theme.pack(r, g, b, a)
end

--- Linear blend between two packed colors.
function theme.mix(c1, c2, t)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local r1, g1, b1, a1 = theme.unpack(c1)
    local r2, g2, b2, a2 = theme.unpack(c2)
    return theme.pack(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, a1 + (a2 - a1) * t)
end

local P = theme.pack

local presets = {}

-- Neutral slate with a single cool accent. HP reads as a muted mint that warms to amber and red.
local NEUTRAL = {
    bg       = P(0.050, 0.055, 0.066, 1.0),
    card     = P(0.092, 0.099, 0.115, 1.0),
    card_hot = P(0.130, 0.140, 0.160, 1.0),
    border   = P(0.160, 0.172, 0.200, 1.0),
    btn      = P(0.135, 0.145, 0.168, 1.0),
    btn_hot  = P(0.200, 0.214, 0.246, 1.0),
    text     = P(0.945, 0.952, 0.965, 1.0),
    text_dim = P(0.520, 0.552, 0.612, 1.0),
    dead     = P(0.300, 0.095, 0.105, 1.0),
}

presets.modern = {
    bg = NEUTRAL.bg, card = NEUTRAL.card, card_hot = NEUTRAL.card_hot, border = NEUTRAL.border,
    btn = NEUTRAL.btn, btn_hot = NEUTRAL.btn_hot, text = NEUTRAL.text, text_dim = NEUTRAL.text_dim,
    dead = NEUTRAL.dead,
    good   = P(0.600, 0.820, 0.760, 1.0),   -- muted mint (healthy HP)
    -- Full-row HP fill: deep, saturated enough to carry white text. Healthy green -> yellow -> orange -> red.
    hp_stops = { P(0.16, 0.56, 0.38, 1.0), P(0.80, 0.66, 0.16, 1.0), P(0.86, 0.45, 0.14, 1.0), P(0.80, 0.20, 0.20, 1.0) },
    bar_hi = P(0.930, 0.950, 0.975, 1.0),   -- soft white HP bar (Strip look)
    warn   = P(0.950, 0.720, 0.300, 1.0),   -- amber
    bad    = P(0.930, 0.330, 0.330, 1.0),   -- red
    mp     = P(0.420, 0.560, 0.800, 1.0),   -- muted blue
    accent = P(0.420, 0.800, 0.900, 1.0),   -- the one accent: hover, priority cure, title
    -- Job text stays quiet; only healers stand out (you want to know where the other healers are).
    role = {
        healer = P(0.420, 0.800, 0.900, 1.0), tank = NEUTRAL.text_dim, dd = NEUTRAL.text_dim,
        caster = NEUTRAL.text_dim, support = NEUTRAL.text_dim,
    },
    -- Thin underline on ability tiles; deliberately low-key.
    kind = {
        cure   = P(0.450, 0.780, 0.620, 1.0),
        curaga = P(0.380, 0.860, 0.700, 1.0),
        ability = P(0.850, 0.800, 0.500, 1.0),
        regen  = P(0.450, 0.700, 0.800, 1.0),
        status = P(0.680, 0.600, 0.850, 1.0),
        raise  = P(0.900, 0.750, 0.400, 1.0),
        buff   = P(0.550, 0.650, 0.850, 1.0),
    },
}

-- Even calmer: greyscale everywhere except the amber/red that carries meaning.
local mono_line = P(0.640, 0.665, 0.720, 1.0)
presets.mono = {
    bg = NEUTRAL.bg, card = NEUTRAL.card, card_hot = NEUTRAL.card_hot, border = NEUTRAL.border,
    btn = NEUTRAL.btn, btn_hot = NEUTRAL.btn_hot, text = NEUTRAL.text, text_dim = NEUTRAL.text_dim,
    dead = NEUTRAL.dead,
    good   = P(0.800, 0.820, 0.850, 1.0),
    warn   = presets.modern.warn,
    bad    = presets.modern.bad,
    mp     = P(0.560, 0.600, 0.680, 1.0),
    accent = P(0.930, 0.940, 0.960, 1.0),
    role = presets.modern.role,
    kind = { cure = mono_line, curaga = mono_line, ability = mono_line, regen = mono_line, status = mono_line, raise = presets.modern.warn, buff = mono_line },
}

-- Okabe-Ito based accents/states: distinguishable with the common forms of color blindness.
presets.colorblind = {
    bg = NEUTRAL.bg, card = NEUTRAL.card, card_hot = NEUTRAL.card_hot, border = NEUTRAL.border,
    btn = NEUTRAL.btn, btn_hot = NEUTRAL.btn_hot, text = NEUTRAL.text, text_dim = NEUTRAL.text_dim,
    dead = P(0.300, 0.150, 0.000, 1.0),
    good   = P(0.340, 0.710, 0.910, 1.0),   -- sky blue
    warn   = P(0.940, 0.890, 0.260, 1.0),   -- yellow
    bad    = P(0.840, 0.370, 0.000, 1.0),   -- vermillion
    mp     = P(0.000, 0.450, 0.700, 1.0),   -- blue
    accent = P(0.800, 0.470, 0.650, 1.0),   -- reddish purple
    role = presets.modern.role,
    kind = {
        cure   = P(0.340, 0.710, 0.910, 1.0),
        curaga = P(0.340, 0.710, 0.910, 1.0),
        ability = P(0.900, 0.620, 0.000, 1.0),
        regen  = P(0.000, 0.620, 0.450, 1.0),
        status = P(0.800, 0.470, 0.650, 1.0),
        raise  = P(0.900, 0.620, 0.000, 1.0),
        buff   = P(0.000, 0.450, 0.700, 1.0),
    },
}

theme.preset_names = { 'modern', 'mono', 'colorblind' }

--- Returns the palette table for a preset name (falls back to modern).
function theme.get(name)
    return presets[name] or presets.modern
end

--- HP bar color for a 0..1 fraction: red -> amber -> mint, using the palette's own colors.
--- Strip-look HP bar: soft white while healthy, amber then red as it drops (thin bars, glow added by ui).
function theme.hp_bar(pal, frac)
    local hi = pal.bar_hi or pal.text
    if frac >= 0.6 then return hi end
    if frac >= 0.35 then return theme.mix(pal.warn, hi, (frac - 0.35) / 0.25 * 0.5) end
    return theme.mix(pal.bad, pal.warn, frac / 0.35 * 0.5)
end

--- Fill color for a full-row HP bar: healthy color, then yellow, orange, red as HP drops.
-- Uses the palette's own good / warn / bad so the colorblind and mono palettes keep working.
function theme.hp_fill(pal, frac)
    frac = math.max(0, math.min(1, frac or 0))
    local st = pal.hp_stops
    if st then
        -- Four fixed stops: full, yellow, orange, red. Anchors at 100% / 55% / 30% / 12% HP.
        if frac >= 0.55 then return theme.mix(st[2], st[1], (frac - 0.55) / 0.45) end
        if frac >= 0.30 then return theme.mix(st[3], st[2], (frac - 0.30) / 0.25) end
        if frac >= 0.12 then return theme.mix(st[4], st[3], (frac - 0.12) / 0.18) end
        return st[4]
    end
    local orange = theme.mix(pal.warn, pal.bad, 0.55)
    if frac >= 0.55 then return theme.mix(pal.warn, pal.good, (frac - 0.55) / 0.45) end
    if frac >= 0.30 then return theme.mix(orange, pal.warn, (frac - 0.30) / 0.25) end
    if frac >= 0.12 then return theme.mix(pal.bad, orange, (frac - 0.12) / 0.18) end
    return pal.bad
end

function theme.hp_color(pal, frac)
    if frac >= 0.5 then
        return theme.mix(pal.warn, pal.good, (frac - 0.5) / 0.5)
    end
    return theme.mix(pal.bad, pal.warn, frac / 0.5)
end

return theme
