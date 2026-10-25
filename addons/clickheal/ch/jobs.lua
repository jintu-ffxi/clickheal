--[[
    ClickHeal - jobs.lua
    Job id -> abbreviation and role (role drives the job chip color).
    Job ids follow FFXI's main job numbering.
]]--

local jobs = {}

jobs.list = {
    [1]  = { abbr = 'WAR', role = 'dd' },
    [2]  = { abbr = 'MNK', role = 'dd' },
    [3]  = { abbr = 'WHM', role = 'healer' },
    [4]  = { abbr = 'BLM', role = 'caster' },
    [5]  = { abbr = 'RDM', role = 'support' },
    [6]  = { abbr = 'THF', role = 'dd' },
    [7]  = { abbr = 'PLD', role = 'tank' },
    [8]  = { abbr = 'DRK', role = 'dd' },
    [9]  = { abbr = 'BST', role = 'dd' },
    [10] = { abbr = 'BRD', role = 'support' },
    [11] = { abbr = 'RNG', role = 'dd' },
    [12] = { abbr = 'SAM', role = 'dd' },
    [13] = { abbr = 'NIN', role = 'tank' },
    [14] = { abbr = 'DRG', role = 'dd' },
    [15] = { abbr = 'SMN', role = 'caster' },
    [16] = { abbr = 'BLU', role = 'caster' },
    [17] = { abbr = 'COR', role = 'support' },
    [18] = { abbr = 'PUP', role = 'dd' },
    [19] = { abbr = 'DNC', role = 'dd' },
    [20] = { abbr = 'SCH', role = 'healer' },
    [21] = { abbr = 'GEO', role = 'support' },
    [22] = { abbr = 'RUN', role = 'tank' },
}

-- Muted per-job hues for the Strip layout's job block (r, g, b in 0..1).
local HUE = {
    [1]  = { 0.80, 0.42, 0.38 }, [2]  = { 0.86, 0.62, 0.32 }, [3]  = { 0.90, 0.90, 0.93 },
    [4]  = { 0.50, 0.52, 0.88 }, [5]  = { 0.82, 0.34, 0.38 }, [6]  = { 0.42, 0.72, 0.46 },
    [7]  = { 0.92, 0.74, 0.30 }, [8]  = { 0.60, 0.36, 0.60 }, [9]  = { 0.62, 0.54, 0.40 },
    [10] = { 0.92, 0.58, 0.72 }, [11] = { 0.52, 0.74, 0.38 }, [12] = { 0.82, 0.58, 0.38 },
    [13] = { 0.48, 0.54, 0.66 }, [14] = { 0.42, 0.58, 0.86 }, [15] = { 0.56, 0.82, 0.76 },
    [16] = { 0.38, 0.62, 0.82 }, [17] = { 0.82, 0.72, 0.48 }, [18] = { 0.66, 0.62, 0.52 },
    [19] = { 0.90, 0.62, 0.64 }, [20] = { 0.66, 0.82, 0.56 }, [21] = { 0.56, 0.76, 0.66 },
    [22] = { 0.62, 0.72, 0.82 },
}
local GREY = { 0.62, 0.65, 0.70 }

--- r, g, b for a job's block color.
function jobs.hue(id)
    return table.unpack(HUE[id] or GREY)
end

local UNKNOWN = { abbr = '???', role = 'dd' }

function jobs.info(id)
    return jobs.list[id] or UNKNOWN
end

function jobs.abbr(id)
    return jobs.info(id).abbr
end

function jobs.role(id)
    return jobs.info(id).role
end

--- "WHM/SCH 99" style label. Sub job and level are optional.
function jobs.label(main, sub, level)
    local s = jobs.abbr(main)
    if sub and sub > 0 then s = s .. '/' .. jobs.abbr(sub) end
    if level and level > 0 then s = s .. ' ' .. tostring(level) end
    return s
end

return jobs
