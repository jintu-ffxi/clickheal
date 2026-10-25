--[[
    ClickHeal - spells.lua
    Spell button definitions, per-job presets, and click-binding resolution.

    The catalog covers every support spell and job ability that WHM, RDM, SCH, BLM and BRD can use
    at the 75 level cap. Levels, MP costs and recast times (seconds) are taken from the LandSandBoat
    spell_list / abilities tables, which CatsEyeXI is built on. CatsEyeXI may have changed some of
    them: Phase 2 replaces these values with what the game's own resource data reports.

    def.lv       = { JOB = level } for every job in this addon's scope. A spell with no `lv` is always shown.
    def.selfonly = the game only lets you target yourself (Blink, Protectra, songs...). Clicking it on
                   any member casts it on you; the tile still shows on every row so the flyout keeps
                   one shape for everyone.
    def.down     = the next lower tier, used when the player has not learned the spell yet.
]]--

local jobs = require('ch.jobs')

local spells = {}

local ROMAN = { '', ' II', ' III', ' IV', ' V', ' VI' }

spells.defs = {}

local function add(key, def)
    def.key = key
    spells.defs[key] = def
end

--- add() with the usual positional fields. extra is merged last.
local function sp(key, name, short, kind, mp, recast, lv, extra)
    local d = { name = name, short = short, kind = kind, mp = mp, recast = recast, lv = lv }
    for k, v in pairs(extra or {}) do d[k] = v end
    add(key, d)
end

-- ---------------------------------------------------------------------------------------------
-- Healing
-- Cure I-V. Right click = one tier down, Shift = one tier up, Ctrl = the Curaga of the same number.
-- ---------------------------------------------------------------------------------------------
local cure_lv = {
    { WHM = 1,  RDM = 3,  SCH = 5,  PLD = 5 },
    { WHM = 11, RDM = 14, SCH = 17, PLD = 17 },
    { WHM = 21, RDM = 26, SCH = 30, PLD = 30 },
    { WHM = 41, RDM = 48, SCH = 55, PLD = 55 },
    { WHM = 61 },
}
local cure_mp, cure_rc = { 8, 24, 46, 88, 135 }, { 5, 5.5, 6, 8, 10 }
for n = 1, 5 do
    sp('cure' .. n, 'Cure' .. ROMAN[n], 'C' .. n, 'cure', cure_mp[n], cure_rc[n], cure_lv[n], {
        right = (n > 1) and ('cure' .. (n - 1)) or nil,
        shift = (n < 5) and ('cure' .. (n + 1)) or nil,
        ctrl  = 'curaga' .. math.min(n, 4),
        down  = (n > 1) and ('cure' .. (n - 1)) or nil,
    })
end

-- Curaga I-IV: heals everyone near the target, so the clicked member is the centre of the heal.
local curaga_lv, curaga_mp, curaga_rc = { 16, 31, 51, 71 }, { 60, 120, 180, 260 }, { 10, 10.25, 10.5, 10.75 }
for n = 1, 4 do
    sp('curaga' .. n, 'Curaga' .. ROMAN[n], 'Cg' .. n, 'curaga', curaga_mp[n], curaga_rc[n], { WHM = curaga_lv[n] }, {
        area = true,
        right = (n > 1) and ('curaga' .. (n - 1)) or nil,
        shift = (n < 4) and ('curaga' .. (n + 1)) or nil,
        down  = (n > 1) and ('curaga' .. (n - 1)) or nil,
    })
end

-- Regen I-III (RDM only gets the first).
local regen_lv = { { WHM = 21, RDM = 21, SCH = 18 }, { WHM = 44, SCH = 37 }, { WHM = 66, SCH = 59 } }
local regen_mp, regen_rc = { 15, 36, 64 }, { 12, 16, 20 }
for n = 1, 3 do
    sp('regen' .. n, 'Regen' .. ROMAN[n], 'Rg' .. n, 'regen', regen_mp[n], regen_rc[n], regen_lv[n], {
        buff = 'regen',
        right = (n > 1) and ('regen' .. (n - 1)) or nil,
        shift = (n < 3) and ('regen' .. (n + 1)) or nil,
        down  = (n > 1) and ('regen' .. (n - 1)) or nil,
    })
end

-- Cura / Esuna / Auspice only work on yourself and affect people around you: your own ability row.
sp('cura',    'Cura',    'Cur', 'curaga', 30, 30, { WHM = 40 }, { area = true, selfonly = true, group = 'ability' })
sp('esuna',   'Esuna',   'Esu', 'status', 24, 30, { WHM = 61 }, { area = true, selfonly = true, group = 'ability' })
sp('auspice', 'Auspice', 'Aus', 'buff',   48, 10, { WHM = 55 }, { area = true, selfonly = true, group = 'ability' })

-- ---------------------------------------------------------------------------------------------
-- Status removal. RDM has none of these at 75 (and no Erase) in the LandSandBoat data.
-- ---------------------------------------------------------------------------------------------
sp('poisona',  'Poisona',  'Poi', 'status',  8,  5,  { WHM = 6,  SCH = 10 })
sp('paralyna', 'Paralyna', 'Par', 'status', 12,  5,  { WHM = 9,  SCH = 12 })
sp('blindna',  'Blindna',  'Bli', 'status', 16, 10,  { WHM = 14, SCH = 17 })
sp('silena',   'Silena',   'Sil', 'status', 24,  5,  { WHM = 19, SCH = 22 })
sp('cursna',   'Cursna',   'Crs', 'status', 30, 10,  { WHM = 29, SCH = 32 })
sp('viruna',   'Viruna',   'Vir', 'status', 48,  5,  { WHM = 34, SCH = 46 })
sp('stona',    'Stona',    'Sto', 'status', 40,  5,  { WHM = 39, SCH = 50 })
sp('erase',    'Erase',    'Era', 'status', 18, 15,  { WHM = 32, SCH = 39 })
sp('sacrifice','Sacrifice','Sac', 'status', 18, 30,  { WHM = 65 })   -- takes one of the target's debuffs onto you

-- ---------------------------------------------------------------------------------------------
-- Raise / Reraise
-- ---------------------------------------------------------------------------------------------
sp('raise1', 'Raise',     'Ra1', 'raise', 150, 60, { WHM = 25, RDM = 38, SCH = 35, PLD = 50 }, { down = nil })
sp('raise2', 'Raise II',  'Ra2', 'raise', 150, 60, { WHM = 56, SCH = 70 }, { down = 'raise1' })
sp('raise3', 'Raise III', 'Ra3', 'raise', 150, 60, { WHM = 70 },           { down = 'raise2' })
local rr_lv = { { WHM = 25, SCH = 35 }, { WHM = 56, SCH = 70 }, { WHM = 70 } }
for n = 1, 3 do
    sp('reraise' .. n, 'Reraise' .. ROMAN[n], 'RR' .. n, 'buff', 150, 60, rr_lv[n], {
        buff = 'reraise', selfonly = true, group = 'raise', down = (n > 1) and ('reraise' .. (n - 1)) or nil,
    })
end

-- ---------------------------------------------------------------------------------------------
-- Stat buffs
-- ---------------------------------------------------------------------------------------------
local pro_lv   = { { WHM = 7,  RDM = 7,  SCH = 10, PLD = 10 }, { WHM = 27, RDM = 27, SCH = 30, PLD = 30 },
                   { WHM = 47, RDM = 47, SCH = 50, PLD = 50 }, { WHM = 63, RDM = 63, SCH = 66, PLD = 70 } }
local shell_lv = { { WHM = 17, RDM = 17, SCH = 20, PLD = 20 }, { WHM = 37, RDM = 37, SCH = 40, PLD = 40 },
                   { WHM = 57, RDM = 57, SCH = 60, PLD = 60 }, { WHM = 68, RDM = 68, SCH = 71 } }
local protect_mp, shell_mp = { 9, 28, 46, 65, 84 }, { 18, 37, 56, 75, 93 }
local tier_rc = { 5, 5.25, 5.5, 5.75 }
for n = 1, 4 do
    sp('protect' .. n, 'Protect' .. ROMAN[n], 'Pr' .. n, 'buff', protect_mp[n], tier_rc[n], pro_lv[n],
        { buff = 'protect', down = (n > 1) and ('protect' .. (n - 1)) or nil })
    sp('shell' .. n, 'Shell' .. ROMAN[n], 'Sh' .. n, 'buff', shell_mp[n], tier_rc[n], shell_lv[n],
        { buff = 'shell', down = (n > 1) and ('shell' .. (n - 1)) or nil })
end
-- Protectra / Shellra are cast on yourself and cover the party around you.
local pra_lv, sra_lv = { 7, 27, 47, 63, 75 }, { 17, 37, 57, 68, 75 }
for n = 1, 5 do
    sp('protectra' .. n, 'Protectra' .. ROMAN[n], 'Pa' .. n, 'buff', protect_mp[n], 14 + n, { WHM = pra_lv[n] },
        { area = true, selfonly = true, buff = 'protect', down = (n > 1) and ('protectra' .. (n - 1)) or nil })
    sp('shellra' .. n, 'Shellra' .. ROMAN[n], 'Sa' .. n, 'buff', shell_mp[n], 14 + n, { WHM = sra_lv[n] },
        { area = true, selfonly = true, buff = 'shell', down = (n > 1) and ('shellra' .. (n - 1)) or nil })
end

sp('haste',     'Haste',      'Hst', 'buff', 40, 20, { WHM = 40, RDM = 48 }, { buff = 'haste' })
sp('flurry',    'Flurry',     'Flr', 'buff', 40, 20, { RDM = 48 },           { buff = 'flurry' })
sp('refresh',   'Refresh',    'Rfr', 'buff', 40, 18, { RDM = 41 },           { buff = 'refresh' })
sp('phalanx',   'Phalanx',    'Phx', 'buff', 21, 10, { RDM = 33 },           { buff = 'phalanx', selfonly = true })
sp('phalanx2',  'Phalanx II', 'Px2', 'buff', 42, 10, { RDM = 75 },           { buff = 'phalanx', down = 'phalanx' })
sp('stoneskin', 'Stoneskin',  'Ssk', 'buff', 29, 30, { WHM = 28, RDM = 34, SCH = 44 }, { buff = 'stoneskin', selfonly = true })
sp('blink',     'Blink',      'Bnk', 'buff', 20, 10, { WHM = 19, RDM = 23, SCH = 29 }, { buff = 'blink', selfonly = true })
sp('aquaveil',  'Aquaveil',   'Aqv', 'buff', 12, 10, { WHM = 10, RDM = 12, SCH = 13 }, { buff = 'aquaveil', selfonly = true })
sp('sneak',     'Sneak',      'Snk', 'buff', 12, 10, { WHM = 20, RDM = 20, SCH = 20 }, { buff = 'sneak' })
sp('invisible', 'Invisible',  'Inv', 'buff', 15, 10, { WHM = 25, RDM = 25, SCH = 25 }, { buff = 'invisible' })
sp('deodorize', 'Deodorize',  'Deo', 'buff', 10,  8, { WHM = 15, RDM = 15, SCH = 15 }, { buff = 'deodorize' })

-- Bar-elemental and bar-ailment: single (RDM, self only) and the -ra versions (WHM, self only, party-wide).
-- { element, short, level, -ra spell name } (the -ra names are irregular: Barfira, Barstonra...)
local ELEMS = { { 'fire', 'Fi', 17, 'Barfira' }, { 'blizzard', 'Bz', 21, 'Barblizzara' }, { 'aero', 'Ae', 13, 'Baraera' },
                { 'stone', 'St', 5, 'Barstonra' }, { 'thunder', 'Th', 25, 'Barthundra' }, { 'water', 'Wt', 9, 'Barwatera' } }
for _, e in ipairs(ELEMS) do
    local nm = e[1]:sub(1, 1):upper() .. e[1]:sub(2)
    sp('bar' .. e[1], 'Bar' .. nm, 'B' .. e[2], 'buff', 6, 10, { RDM = e[3] }, { selfonly = true })
    sp('bar' .. e[1] .. 'ra', e[4], e[2] .. '*', 'buff', 12, 10, { WHM = e[3] },
        { selfonly = true, area = true })
end
local AILS = { { 'sleep', 'Sl', 7, 7, 14, 'Barsleepra' }, { 'poison', 'Ps', 10, 9, 18, 'Barpoisonra' },
               { 'paralyze', 'Pr', 12, 11, 22, 'Barparalyzra' }, { 'blind', 'Bd', 18, 13, 26, 'Barblindra' },
               { 'silence', 'Si', 23, 15, 30, 'Barsilencera' }, { 'petrify', 'Pt', 43, 20, 40, 'Barpetra' },
               { 'virus', 'Vr', 39, 25, 50, 'Barvira' } }
for _, a in ipairs(AILS) do
    local nm = a[1]:sub(1, 1):upper() .. a[1]:sub(2)
    sp('bar' .. a[1], 'Bar' .. nm, 'B' .. a[2], 'buff', a[4], 10, { RDM = a[3] }, { selfonly = true })
    sp('bar' .. a[1] .. 'ra', a[6], a[2] .. '*', 'buff', a[5], 10, { WHM = a[3] }, { selfonly = true, area = true })
end

-- RDM enspells and the damage spikes (self only). Spikes also belong to BLM.
local ENS = { { 'fire', 'Fi', 24, 58 }, { 'blizzard', 'Bz', 22, 56 }, { 'aero', 'Ae', 20, 54 },
              { 'stone', 'St', 18, 52 }, { 'thunder', 'Th', 16, 50 }, { 'water', 'Wt', 27, 60 } }
for _, e in ipairs(ENS) do
    local nm = e[1]:sub(1, 1):upper() .. e[1]:sub(2)
    sp('en' .. e[1], 'En' .. nm, 'E' .. e[2], 'buff', 12, 10, { RDM = e[3] }, { selfonly = true })
    sp('en' .. e[1] .. '2', 'En' .. nm .. ' II', 'E' .. e[2]:sub(1, 1) .. '2', 'buff', 24, 30, { RDM = e[4] },
        { selfonly = true, down = 'en' .. e[1] })
end
sp('blaze_spikes', 'Blaze Spikes', 'Bls', 'buff',  8, 10, { BLM = 10, RDM = 20, SCH = 30 }, { selfonly = true, group = 'ability' })
sp('ice_spikes',   'Ice Spikes',   'Ics', 'buff', 16, 10, { BLM = 20, RDM = 40, SCH = 50 }, { selfonly = true, group = 'ability' })
sp('shock_spikes', 'Shock Spikes', 'Shs', 'buff', 24, 10, { BLM = 30, RDM = 60, SCH = 70 }, { selfonly = true, group = 'ability' })

-- Scholar storms (weather on one target).
local STORMS = { { 'sandstorm', 'Snd', 41 }, { 'rainstorm', 'Rai', 42 }, { 'windstorm', 'Wnd', 43 },
                 { 'firestorm', 'Fir', 44 }, { 'hailstorm', 'Hal', 45 }, { 'thunderstorm', 'Thn', 46 },
                 { 'voidstorm', 'Vds', 47 }, { 'aurorastorm', 'Aur', 48 } }
for _, st in ipairs(STORMS) do
    sp(st[1], st[1]:sub(1, 1):upper() .. st[1]:sub(2), st[2], 'buff', 30, 18, { SCH = st[3] })
end

-- ---------------------------------------------------------------------------------------------
-- Bard songs that help the party. They are cast on yourself and reach everyone in range, so they
-- live in the 'song' group of your own row. MP is 0 in the source table; Phase 2 reads the real cost.
-- Songs that hit enemies (Requiem, Lullaby, Threnody, Elegy, Finale) are left out.
-- ---------------------------------------------------------------------------------------------
local SONGS = {
    { 'armys_paeon',   'Army\'s Paeon',    'Pn', { 5, 15, 35, 45, 65 } },
    { 'mages_ballad',  'Mage\'s Ballad',   'Bl', { 25, 55 } },
    { 'knights_minne', 'Knight\'s Minne',  'Mn', { 1, 21, 41, 61 } },
    { 'valor_minuet',  'Valor Minuet',     'Mi', { 3, 23, 43, 63 } },
}
for _, s in ipairs(SONGS) do
    for n, lv in ipairs(s[4]) do
        sp(s[1] .. n, s[2] .. ROMAN[n], s[3] .. n, 'ability', 0, 24, { BRD = lv },
            { song = true, selfonly = true, group = 'song', down = (n > 1) and (s[1] .. (n - 1)) or nil })
    end
end
local function song(key, name, short, lv, down, rc)
    sp(key, name, short, 'ability', 0, rc or 24, { BRD = lv }, { song = true, selfonly = true, group = 'song', down = down })
end
song('sword_madrigal',   'Sword Madrigal',    'Mds', 11)
song('blade_madrigal',   'Blade Madrigal',    'Mdb', 51, 'sword_madrigal')
song('hunters_prelude',  'Hunter\'s Prelude', 'Prh', 31)
song('archers_prelude',  'Archer\'s Prelude', 'Pra', 71, 'hunters_prelude')
song('sheepfoe_mambo',   'Sheepfoe Mambo',    'Msf', 13)
song('dragonfoe_mambo',  'Dragonfoe Mambo',   'Mdf', 53, 'sheepfoe_mambo')
song('advancing_march',  'Advancing March',   'Mch', 29)
song('victory_march',    'Victory March',     'Vmr', 60, 'advancing_march')
song('fowl_aubade',      'Fowl Aubade',       'Aub', 33)
song('herb_pastoral',    'Herb Pastoral',     'Pst', 9)
song('shining_fantasia', 'Shining Fantasia',  'Fnt', 56)
song('scops_operetta',   'Scop\'s Operetta',  'Ops', 19)
song('puppets_operetta', 'Puppet\'s Operetta','Opp', 69)
song('gold_capriccio',   'Gold Capriccio',    'Cpr', 54)
song('warding_round',    'Warding Round',     'Rnd', 73)
song('goblin_gavotte',   'Goblin Gavotte',    'Gav', 49)
song('goddesss_hymnus',  'Goddess\'s Hymnus', 'Hym', 71)
song('raptor_mazurka',   'Raptor Mazurka',    'Rmz', 37)
song('chocobo_mazurka',  'Chocobo Mazurka',   'Cmz', 73, 'raptor_mazurka', 60)
local ETUDES = {
    { 'sinewy', 'Sinewy', 'St', 34, 'herculean', 'Herculean', 74 }, { 'dextrous', 'Dextrous', 'Dx', 32, 'uncanny', 'Uncanny', 72 },
    { 'vivacious', 'Vivacious', 'Vt', 30, 'vital', 'Vital', 70 },    { 'quick', 'Quick', 'Ag', 28, 'swift', 'Swift', 68 },
    { 'learned', 'Learned', 'In', 26, 'sage', 'Sage', 66 },          { 'spirited', 'Spirited', 'Mn', 24, 'logical', 'Logical', 64 },
    { 'enchanting', 'Enchanting', 'Ch', 22, 'bewitching', 'Bewitching', 62 },
}
for _, e in ipairs(ETUDES) do
    song(e[1] .. '_etude', e[2] .. ' Etude', 'E' .. e[3], e[4])
    song(e[5] .. '_etude', e[6] .. ' Etude', e[3] .. '2', e[7], e[1] .. '_etude')
end
local CAROLS = { { 'fire', 'Fi', 44 }, { 'ice', 'Ic', 46 }, { 'wind', 'Wn', 42 }, { 'earth', 'Er', 38 },
                 { 'lightning', 'Lt', 48 }, { 'water', 'Wt', 40 }, { 'light', 'Lg', 36 }, { 'dark', 'Dk', 50 } }
for _, c in ipairs(CAROLS) do
    song(c[1] .. '_carol', c[1]:sub(1, 1):upper() .. c[1]:sub(2) .. ' Carol', 'C' .. c[2], c[3])
end

-- ---------------------------------------------------------------------------------------------
-- Job abilities. `self` = acts on you, no target click needed; `target` = needs a member.
-- Levels and recasts (seconds) from the abilities table. 2-hour abilities are main-job only.
-- ---------------------------------------------------------------------------------------------
local function ja(key, name, short, job, lvl, extra)
    local d = { name = name, short = short, kind = 'ability', ja = true, job = job, lvl = lvl,
                lv = { [job] = lvl }, mp = 0, recast = 60.0, self = true, group = 'ability' }
    for k, v in pairs(extra or {}) do d[k] = v end
    add(key, d)
end
ja('divine_seal',     'Divine Seal',     'DSl', 'WHM', 15, { recast = 600.0 })
ja('benediction',     'Benediction',     'Ben', 'WHM', 1,  { recast = 3600.0, main_only = true })
ja('afflatus_solace', 'Afflatus Solace', 'AfS', 'WHM', 40, { recast = 60.0 })
ja('afflatus_misery', 'Afflatus Misery', 'AfM', 'WHM', 40, { recast = 60.0 })
ja('devotion',        'Devotion',        'Dev', 'WHM', 75, { self = false, target = true, recast = 600.0 })
ja('martyr',          'Martyr',          'Mrt', 'WHM', 75, { self = false, target = true, recast = 600.0 })
ja('light_arts',      'Light Arts',      'LA',  'SCH', 10)
ja('addendum_white',  'Addendum: White', 'AdW', 'SCH', 10, { recast = 1.0 })
ja('sublimation',     'Sublimation',     'Sub', 'SCH', 35, { recast = 30.0 })
ja('accession',       'Accession',       'Acc', 'SCH', 40, { recast = 1.0 })
ja('celerity',        'Celerity',        'Cel', 'SCH', 25, { recast = 1.0 })
ja('penury',          'Penury',          'Pen', 'SCH', 10, { recast = 1.0 })
ja('rapture',         'Rapture',         'Rap', 'SCH', 55, { recast = 1.0 })
ja('tabula_rasa',     'Tabula Rasa',     'Tab', 'SCH', 1,  { recast = 3600.0, main_only = true })
ja('convert',         'Convert',         'Cnv', 'RDM', 40, { recast = 600.0 })
ja('composure',       'Composure',       'Cmp', 'RDM', 50, { recast = 300.0 })
ja('chainspell',      'Chainspell',      'Chn', 'RDM', 1,  { recast = 3600.0, main_only = true })
ja('manafont',        'Manafont',        'Mnf', 'BLM', 1,  { recast = 3600.0, main_only = true })
ja('elemental_seal',  'Elemental Seal',  'ESl', 'BLM', 15, { recast = 600.0 })
ja('soul_voice',      'Soul Voice',      'SVc', 'BRD', 1,  { recast = 3600.0, main_only = true })
ja('pianissimo',      'Pianissimo',      'Pia', 'BRD', 20, { recast = 5.0 })
ja('nightingale',     'Nightingale',     'Ngl', 'BRD', 75, { recast = 600.0 })
ja('troubadour',      'Troubadour',      'Trb', 'BRD', 75, { recast = 600.0 })

-- ---------------------------------------------------------------------------------------------
-- Groups, tabs, ordering
-- ---------------------------------------------------------------------------------------------

-- Tabs of the shared spell bar (Grid / Strip layouts), in display order.
spells.BAR_TABS = { { 'heal', 'HEAL' }, { 'cleanse', 'CLEAN' }, { 'buff', 'BUFF' }, { 'raise', 'RAISE' } }

--- The preset's non-empty bar tabs: { { id, label, keys }, ... }.
function spells.bar_tabs(preset)
    local out = {}
    for _, t in ipairs(spells.BAR_TABS) do
        local keys = preset.bar and preset.bar[t[1]] or {}
        if #keys > 0 then out[#out + 1] = { id = t[1], label = t[2], keys = keys } end
    end
    return out
end

-- Groups shown in the hover flyout, top to bottom. 'song' and 'ability' appear only on your own row.
spells.GROUPS = { { 'heal', 'HEAL' }, { 'cleanse', 'CLEAN' }, { 'buff', 'BUFF' }, { 'raise', 'RAISE' },
                  { 'song', 'SONG' }, { 'ability', 'ABIL' } }
spells.SELF_GROUPS = { song = true, ability = true }

--- Which flyout group a spell naturally belongs to.
function spells.group_of(def)
    if def.group then return def.group end
    if def.kind == 'cure' or def.kind == 'curaga' or def.kind == 'regen' then return 'heal' end
    if def.kind == 'status' then return 'cleanse' end
    if def.kind == 'raise' then return 'raise' end
    if def.kind == 'ability' then return 'ability' end
    return 'buff'
end

-- ---------------------------------------------------------------------------------------------
-- What the player has learned
-- ---------------------------------------------------------------------------------------------

--- The most a sub job can reach: half the main level (37 at the 75 cap).
local function sub_level(who)
    local cap = math.floor((who.level or 0) / 2)
    return math.min(who.sublevel or cap, cap)
end

--- True when the player's main job (or sub job at its reduced level) has the spell or ability.
-- `who` = { job, sub, level, sublevel? }. With no level information everything counts as known.
function spells.known(key, who)
    local def = spells.defs[key]
    if not def then return false end
    if not who or not who.level or not def.lv then return true end
    local need = def.lv[jobs.abbr(who.job or 0)]
    if need and need <= who.level then return true end
    if def.main_only then return false end
    need = who.sub and who.sub > 0 and def.lv[jobs.abbr(who.sub)] or nil
    return need ~= nil and need <= sub_level(who)
end

--- The key itself, or the highest lower tier the player knows, or nil.
function spells.best(key, who)
    local seen = 0
    while key and seen < 8 do
        if spells.known(key, who) then return key end
        local def = spells.defs[key]
        key = def and def.down or nil
        seen = seen + 1
    end
    return nil
end

--- Filters a key list to what the player knows (tiers fall back), no duplicates, order kept.
function spells.fit_list(list, who)
    local out, seen = {}, {}
    for _, k in ipairs(list or {}) do
        local b = spells.defs[k] and spells.best(k, who)
        if b and not seen[b] then seen[b] = true; out[#out + 1] = b end
    end
    return out
end

local function fit_bindings(map, who)
    if not map then return nil end
    local out = {}
    for slot, v in pairs(map) do
        if v == '-' or v == 'cleanse' then out[slot] = v
        else
            local b = spells.best(v, who)
            if b then out[slot] = b end
        end
    end
    return out
end

--- A copy of the preset with every list cut down to what the player can cast right now.
function spells.fit(preset, who)
    if not who or not who.level then return preset end
    local out = {}
    for k, v in pairs(preset) do out[k] = v end
    for _, name in ipairs({ 'base', 'raise', 'buffs', 'self', 'songs' }) do
        if preset[name] then out[name] = spells.fit_list(preset[name], who) end
    end
    if preset.bar then
        out.bar = {}
        for g, list in pairs(preset.bar) do out.bar[g] = spells.fit_list(list, who) end
    end
    out.bindings = fit_bindings(preset.bindings, who)
    out.buff_bindings = fit_bindings(preset.buff_bindings, who)
    return out
end

--- Spell keys for a group: the user's order (cfg.spell_order) if set, else the job preset's.
-- The same order is used for every party member. Pass `who` to hide what is not learned yet.
function spells.group_keys(cfg, preset, group, who)
    local custom = cfg and cfg.spell_order and cfg.spell_order[group]
    if custom and #custom > 0 then
        local out = {}
        for _, k in ipairs(custom) do if spells.defs[k] then out[#out + 1] = k end end
        if who and who.level then
            local kept = {}
            for _, k in ipairs(out) do if spells.known(k, who) then kept[#kept + 1] = k end end
            return kept
        end
        return out
    end
    if group == 'ability' then return preset.self or {} end
    if group == 'song' then return preset.songs or {} end
    return (preset.bar and preset.bar[group]) or {}
end

--- Cure and Curaga stay armed after a cast (you usually heal several people in a row);
-- everything else is one-shot.
function spells.sticky(def) return def ~= nil and (def.kind == 'cure' or def.kind == 'curaga') end

-- ---------------------------------------------------------------------------------------------
-- Presets
-- base  = the always-visible heal/cleanse row     raise = what a KO'd member shows
-- buffs = a second set for "buff mode"
-- self  = abilities for your own row              songs = bard songs for your own row
-- Lists name the strongest spell wanted; spells.fit() swaps in lower tiers (and drops what a
-- sub job or low level can't cast) so the same preset works at any level.
-- ---------------------------------------------------------------------------------------------

-- White magic a caster main job can borrow through a WHM / RDM / SCH sub job (BLM, BRD).
local function sub_support(extra_self, songs)
    return {
        base  = { 'cure4', 'cure3', 'cure2', 'cure1', 'erase', 'poisona', 'paralyna', 'blindna', 'silena' },
        raise = { 'raise2', 'raise1' },
        buffs = { 'haste', 'stoneskin', 'protect4', 'shell4', 'blink', 'aquaveil', 'sneak', 'invisible' },
        self  = extra_self,
        songs = songs,
        bar = {
            heal    = { 'cure1', 'cure2', 'cure3', 'cure4', 'curaga1', 'curaga2', 'curaga3', 'curaga4', 'regen3' },
            cleanse = { 'poisona', 'paralyna', 'blindna', 'silena', 'cursna', 'erase', 'viruna', 'stona' },
            buff    = { 'haste', 'regen3', 'stoneskin', 'protect4', 'shell4', 'blink', 'aquaveil', 'sneak', 'invisible' },
            raise   = { 'raise1', 'raise2', 'reraise1', 'reraise2' },
        },
        bindings = { left = 'cure4', right = 'cure2', middle = 'cleanse',
            shift_left = 'cure3', shift_right = 'cure1', ctrl_left = 'curaga2', ctrl_right = 'curaga1' },
        buff_bindings = { left = 'haste', right = 'regen3', middle = 'stoneskin',
            shift_left = 'protect4', shift_right = 'shell4', ctrl_left = 'blink', ctrl_right = 'aquaveil',
            alt_left = 'sneak', alt_right = 'invisible' },
    }
end

spells.presets = {
    WHM = {
        base  = { 'cure4', 'cure3', 'cure2', 'cure1', 'erase', 'poisona', 'paralyna', 'blindna', 'silena' },
        raise = { 'raise3', 'raise2', 'raise1' },
        buffs = { 'haste', 'regen3', 'stoneskin', 'protectra4', 'shellra4', 'blink', 'aquaveil', 'sneak', 'invisible' },
        self  = { 'divine_seal', 'benediction', 'afflatus_solace', 'afflatus_misery', 'cura', 'esuna', 'auspice' },
        bar = {
            heal    = { 'cure1', 'cure2', 'cure3', 'cure4', 'cure5', 'curaga1', 'curaga2', 'curaga3', 'curaga4' },
            cleanse = { 'poisona', 'paralyna', 'blindna', 'silena', 'cursna', 'erase', 'viruna', 'stona', 'sacrifice' },
            buff    = { 'haste', 'regen3', 'stoneskin', 'protectra4', 'shellra4', 'blink', 'aquaveil', 'sneak', 'invisible' },
            raise   = { 'raise1', 'raise2', 'raise3', 'reraise3' },
        },
        bindings = { left = 'cure4', right = 'cure2', middle = 'cleanse',
            shift_left = 'cure5', shift_right = 'cure1', ctrl_left = 'curaga3', ctrl_right = 'curaga1',
            alt_left = 'haste', alt_right = 'regen3' },
        buff_bindings = { left = 'haste', right = 'regen3', middle = 'stoneskin',
            shift_left = 'protectra4', shift_right = 'shellra4', ctrl_left = 'blink', ctrl_right = 'aquaveil',
            alt_left = 'sneak', alt_right = 'invisible' },
    },
    SCH = {
        base  = { 'cure4', 'cure3', 'cure2', 'cure1', 'erase', 'regen3', 'poisona', 'paralyna' },
        raise = { 'raise2', 'raise1' },
        buffs = { 'regen3', 'regen2', 'stoneskin', 'protect4', 'shell4', 'aquaveil', 'sneak', 'invisible' },
        self  = { 'light_arts', 'addendum_white', 'celerity', 'penury', 'accession', 'rapture', 'sublimation', 'tabula_rasa' },
        bar = {
            heal    = { 'cure1', 'cure2', 'cure3', 'cure4', 'regen1', 'regen2', 'regen3' },
            cleanse = { 'poisona', 'paralyna', 'blindna', 'silena', 'cursna', 'erase', 'viruna', 'stona' },
            buff    = { 'stoneskin', 'protect4', 'shell4', 'blink', 'aquaveil', 'sneak', 'invisible' },
            raise   = { 'raise1', 'raise2', 'reraise1', 'reraise2' },
        },
        bindings = { left = 'cure4', right = 'cure2', middle = 'cleanse',
            shift_left = 'cure3', shift_right = 'cure1', alt_left = 'regen3', alt_right = 'regen2' },
        buff_bindings = { left = 'regen3', right = 'regen2', middle = 'stoneskin',
            shift_left = 'protect4', shift_right = 'shell4', ctrl_left = 'aquaveil',
            alt_left = 'sneak', alt_right = 'invisible' },
    },
    RDM = {
        base  = { 'cure4', 'cure3', 'cure2', 'cure1' },
        raise = { 'raise1' },
        buffs = { 'haste', 'refresh', 'flurry', 'phalanx2', 'phalanx', 'stoneskin', 'protect4', 'shell4', 'blink' },
        self  = { 'convert', 'composure', 'chainspell' },
        bar = {
            heal    = { 'cure1', 'cure2', 'cure3', 'cure4' },
            cleanse = {},
            buff    = { 'haste', 'refresh', 'flurry', 'phalanx2', 'phalanx', 'stoneskin', 'protect4', 'shell4', 'blink' },
            raise   = { 'raise1' },
        },
        bindings = { left = 'cure4', right = 'cure2',
            shift_left = 'cure3', shift_right = 'cure1', alt_left = 'haste', alt_right = 'refresh' },
        buff_bindings = { left = 'haste', right = 'refresh', middle = 'stoneskin',
            shift_left = 'phalanx2', shift_right = 'protect4', ctrl_left = 'shell4', ctrl_right = 'blink',
            alt_left = 'flurry' },
    },
    BLM = sub_support({ 'manafont', 'elemental_seal', 'blaze_spikes', 'ice_spikes', 'shock_spikes' }, {}),
    BRD = sub_support({ 'soul_voice', 'pianissimo', 'nightingale', 'troubadour' }, {
        'valor_minuet4', 'valor_minuet3', 'victory_march', 'advancing_march', 'blade_madrigal',
        'mages_ballad2', 'knights_minne4', 'archers_prelude', 'dragonfoe_mambo', 'armys_paeon5',
    }),
    PLD = {
        base  = { 'cure4', 'cure3', 'cure2', 'cure1' },
        raise = {},
        bar = { heal = { 'cure1', 'cure2', 'cure3', 'cure4' } },
        bindings = { left = 'cure4', right = 'cure2', shift_left = 'cure3', shift_right = 'cure1' },
        buffs = {},
        self  = {},
    },
    generic = {
        base  = { 'cure3', 'cure2', 'cure1' },
        raise = {},
        bar = { heal = { 'cure1', 'cure2', 'cure3' } },
        bindings = { left = 'cure3', right = 'cure2', shift_left = 'cure1' },
        buffs = {},
        self  = {},
    },
}

-- Job id -> preset name (ids match jobs.lua).
local preset_by_job = { [3] = 'WHM', [20] = 'SCH', [5] = 'RDM', [7] = 'PLD', [4] = 'BLM', [10] = 'BRD' }

--- Picks the preset for the player's main job, then sub job, then generic.
function spells.preset_for(main, sub)
    local name = preset_by_job[main] or preset_by_job[sub] or 'generic'
    return spells.presets[name], name
end

--- Maps a click to the spell it should cast: modifier first, then mouse button.
-- button: 'left' | 'right' | 'middle'      mods: { shift=, ctrl=, alt= } (may be nil)
function spells.resolve(def, button, mods)
    if not def then return nil end
    mods = mods or {}
    if mods.shift and def.shift then return def.shift end
    if mods.ctrl and def.ctrl then return def.ctrl end
    if mods.alt and def.alt then return def.alt end
    if button == 'right' and def.right then return def.right end
    if button == 'middle' and def.middle then return def.middle end
    return def.key
end

--- Builds the row of buttons shown for a member.
-- Debuff cures jump to the front (flagged priority), then the preset fills the remaining slots.
-- A KO'd member shows the raise spells instead.
function spells.build_row(member, preset, debuff_info, max_buttons)
    local row, seen = {}, {}

    local function push(key, priority)
        if #row >= max_buttons or seen[key] then return end
        local def = spells.defs[key]
        if def then
            seen[key] = true
            row[#row + 1] = { def = def, priority = priority or false }
        end
    end

    if member.dead then
        for _, key in ipairs(preset.raise or {}) do push(key, true) end
        return row
    end

    if member.debuffs and debuff_info then
        local keys = {}
        for _, k in ipairs(member.debuffs) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ia, ib = debuff_info[a], debuff_info[b]
            local sa, sb = ia and ia.sev or 9, ib and ib.sev or 9
            if sa ~= sb then return sa < sb end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local info = debuff_info[k]
            if info and info.spell then push(info.spell, true) end
        end
    end

    for _, key in ipairs(preset.base) do push(key, false) end
    return row
end

--- Short human text for the tooltip's binding line.
function spells.binding_lines(def)
    local lines = { 'LMB: ' .. def.name }
    local function nm(k) return spells.defs[k] and spells.defs[k].name or k end
    if def.right then lines[#lines + 1] = 'RMB: ' .. nm(def.right) end
    if def.shift then lines[#lines + 1] = 'Shift: ' .. nm(def.shift) end
    return table.concat(lines, '   ')
end

return spells
