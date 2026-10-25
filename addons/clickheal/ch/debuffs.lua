--[[
    ClickHeal - debuffs.lua
    Debuffs worth surfacing, their alert severity, and the spell suggested to clear them.

    IMPORTANT: everything here is a DEFAULT. The suggested spells (and the status ids) are meant to
    be verified against CatsEyeXI in Phase 0 and are editable data, not game truth. A debuff with
    spell = nil still raises an alert; it just has no one-click suggestion.

    severity: 1 = critical, 2 = important, 3 = minor
]]--

local debuffs = {}

debuffs.info = {
    doom       = { label = 'DOOM',     short = 'DOM', sev = 1, spell = 'cursna'   },
    petrify    = { label = 'PETRIFY',  short = 'PTR', sev = 1, spell = 'stona'    },
    sleep      = { label = 'SLEEP',    short = 'SLP', sev = 1, spell = nil        },
    terror     = { label = 'TERROR',   short = 'TRR', sev = 1, spell = nil        },
    silence    = { label = 'SILENCE',  short = 'SIL', sev = 2, spell = 'silena'   },
    paralysis  = { label = 'PARALYZE', short = 'PAR', sev = 2, spell = 'paralyna' },
    curse      = { label = 'CURSE',    short = 'CRS', sev = 2, spell = 'cursna'   },
    amnesia    = { label = 'AMNESIA',  short = 'AMN', sev = 2, spell = nil        },
    poison     = { label = 'POISON',   short = 'PSN', sev = 3, spell = 'poisona'  },
    blindness  = { label = 'BLIND',    short = 'BLD', sev = 3, spell = 'blindna'  },
    disease    = { label = 'DISEASE',  short = 'DIS', sev = 3, spell = 'viruna'   },
    slow       = { label = 'SLOW',     short = 'SLW', sev = 3, spell = 'erase'    },
    bind       = { label = 'BIND',     short = 'BND', sev = 3, spell = 'erase'    },
    weight     = { label = 'WEIGHT',   short = 'WGT', sev = 3, spell = 'erase'    },
}

-- Status effect id -> debuff key. Phase 2 reads buff ids from the party packet/memory.
-- UNVERIFIED defaults taken from the usual FFXI status numbering; confirm in Phase 0.
debuffs.by_id = {
    [2]  = 'sleep',
    [3]  = 'poison',
    [4]  = 'paralysis',
    [5]  = 'blindness',
    [6]  = 'silence',
    [7]  = 'petrify',
    [8]  = 'disease',
    [9]  = 'curse',
    [11] = 'bind',
    [12] = 'weight',
    [13] = 'slow',
    [15] = 'doom',
    [16] = 'amnesia',
    [28] = 'terror',
}

-- Reverse lookup: debuff key -> status effect id (the game's icon is found by id).
debuffs.id_of = {}
for id, key in pairs(debuffs.by_id) do
    if not debuffs.id_of[key] or id < debuffs.id_of[key] then debuffs.id_of[key] = id end
end

-- Display order for the setup panel.
debuffs.order = {
    'doom', 'petrify', 'sleep', 'terror', 'silence', 'paralysis', 'curse', 'amnesia',
    'poison', 'blindness', 'disease', 'slow', 'bind', 'weight',
}

--- Sort comparator: more severe first, then by key for stability.
function debuffs.compare(a, b)
    local ia, ib = debuffs.info[a], debuffs.info[b]
    local sa, sb = ia and ia.sev or 9, ib and ib.sev or 9
    if sa ~= sb then return sa < sb end
    return a < b
end

return debuffs
