--[[
    ClickHeal - jobicons.lua
    Small original job pictograms drawn from rectangles and quads, so they need no image files, scale
    with the UI and work in previews and tests. Each glyph is a list of shapes in a 0..1 box:

        { 'r', x, y, w, h [, round] }          filled rectangle
        { 'q', x1, y1, x2, y2, x3, y3, x4, y4 } filled quad (a triangle repeats a point)

    If the backend cannot draw quads, only the rectangles are drawn.
]]--

local jobicons = {}

local function frame(x, y, w, h, t)
    return { { 'r', x, y, w, t }, { 'r', x, y + h - t, w, t }, { 'r', x, y + t, t, h - 2 * t }, { 'r', x + w - t, y + t, t, h - 2 * t } }
end

local function cat(...)
    local out = {}
    for _, list in ipairs({ ... }) do for _, v in ipairs(list) do out[#out + 1] = v end end
    return out
end

-- Job id -> shapes. Ids follow jobs.lua.
jobicons.glyphs = {
    [1]  = { { 'r', 0.46, 0.14, 0.08, 0.74 }, { 'q', 0.54, 0.18, 0.86, 0.10, 0.86, 0.56, 0.54, 0.50 } },                       -- WAR: axe
    [2]  = { { 'r', 0.24, 0.32, 0.52, 0.42, 0.10 }, { 'r', 0.24, 0.20, 0.12, 0.14, 0.04 }, { 'r', 0.40, 0.17, 0.12, 0.17, 0.04 },
             { 'r', 0.56, 0.20, 0.12, 0.14, 0.04 } },                                                                           -- MNK: fist
    [3]  = { { 'r', 0.40, 0.12, 0.20, 0.76 }, { 'r', 0.14, 0.38, 0.72, 0.20 } },                                               -- WHM: cross
    [4]  = { { 'q', 0.50, 0.08, 0.50, 0.08, 0.80, 0.72, 0.20, 0.72 }, { 'r', 0.10, 0.70, 0.80, 0.14, 0.05 } },                -- BLM: hat
    [5]  = { { 'r', 0.46, 0.10, 0.08, 0.58 }, { 'r', 0.24, 0.62, 0.52, 0.08 }, { 'r', 0.46, 0.70, 0.08, 0.18 },
             { 'q', 0.56, 0.12, 0.80, 0.06, 0.74, 0.30, 0.56, 0.34 } },                                                         -- RDM: rapier and feather
    [6]  = { { 'q', 0.50, 0.08, 0.50, 0.08, 0.64, 0.58, 0.36, 0.58 }, { 'r', 0.28, 0.58, 0.44, 0.07 }, { 'r', 0.46, 0.65, 0.08, 0.22 } }, -- THF: dagger
    [7]  = { { 'r', 0.20, 0.14, 0.60, 0.38 }, { 'q', 0.20, 0.52, 0.80, 0.52, 0.50, 0.88, 0.50, 0.88 } },                       -- PLD: shield
    [8]  = { { 'q', 0.50, 0.08, 0.86, 0.50, 0.50, 0.92, 0.14, 0.50 } },                                                         -- DRK: dark gem
    [9]  = { { 'r', 0.28, 0.46, 0.44, 0.38, 0.16 }, { 'r', 0.14, 0.30, 0.16, 0.16, 0.06 }, { 'r', 0.34, 0.16, 0.14, 0.16, 0.06 },
             { 'r', 0.52, 0.16, 0.14, 0.16, 0.06 }, { 'r', 0.70, 0.30, 0.16, 0.16, 0.06 } },                                    -- BST: paw
    [10] = { { 'r', 0.58, 0.14, 0.08, 0.60 }, { 'r', 0.28, 0.62, 0.34, 0.24, 0.10 }, { 'q', 0.66, 0.14, 0.86, 0.30, 0.86, 0.42, 0.66, 0.30 } }, -- BRD: note
    [11] = { { 'r', 0.12, 0.46, 0.62, 0.08 }, { 'q', 0.88, 0.50, 0.88, 0.50, 0.66, 0.28, 0.66, 0.72 }, { 'q', 0.12, 0.40, 0.26, 0.40, 0.20, 0.50, 0.08, 0.50 } }, -- RNG: arrow
    [12] = { { 'q', 0.80, 0.08, 0.90, 0.18, 0.30, 0.80, 0.20, 0.70 }, { 'r', 0.14, 0.74, 0.22, 0.10, 0.04 } },                  -- SAM: katana
    [13] = { { 'q', 0.50, 0.06, 0.60, 0.50, 0.50, 0.94, 0.40, 0.50 }, { 'q', 0.06, 0.50, 0.50, 0.40, 0.94, 0.50, 0.50, 0.60 } }, -- NIN: shuriken
    [14] = { { 'r', 0.47, 0.30, 0.06, 0.62 }, { 'q', 0.50, 0.06, 0.50, 0.06, 0.68, 0.34, 0.32, 0.34 } },                       -- DRG: spear
    [15] = { { 'q', 0.50, 0.08, 0.50, 0.08, 0.84, 0.42, 0.16, 0.42 }, { 'q', 0.16, 0.42, 0.84, 0.42, 0.50, 0.92, 0.50, 0.92 } }, -- SMN: crystal
    [16] = { { 'q', 0.50, 0.08, 0.50, 0.08, 0.70, 0.50, 0.30, 0.50 }, { 'r', 0.26, 0.42, 0.48, 0.46, 0.24 } },                 -- BLU: drop
    [17] = frame(0.18, 0.18, 0.64, 0.64, 0.09), -- COR: die (pip added below)
    [18] = { { 'r', 0.28, 0.28, 0.44, 0.44, 0.06 }, { 'r', 0.42, 0.08, 0.16, 0.16 }, { 'r', 0.42, 0.76, 0.16, 0.16 },
             { 'r', 0.08, 0.42, 0.16, 0.16 }, { 'r', 0.76, 0.42, 0.16, 0.16 } },                                                -- PUP: gear
    [19] = { { 'q', 0.50, 0.88, 0.50, 0.88, 0.90, 0.28, 0.10, 0.28 }, { 'r', 0.08, 0.16, 0.84, 0.10, 0.04 } },                  -- DNC: fan
    [20] = { { 'r', 0.14, 0.22, 0.34, 0.56, 0.03 }, { 'r', 0.52, 0.22, 0.34, 0.56, 0.03 } },                                   -- SCH: open book
    [21] = { { 'q', 0.50, 0.10, 0.50, 0.10, 0.82, 0.62, 0.18, 0.62 }, { 'r', 0.40, 0.70, 0.20, 0.20, 0.10 } },                 -- GEO: triangle and orb
    [22] = { { 'r', 0.34, 0.10, 0.10, 0.80 }, { 'q', 0.44, 0.28, 0.78, 0.10, 0.78, 0.24, 0.44, 0.44 },
             { 'q', 0.44, 0.52, 0.78, 0.34, 0.78, 0.48, 0.44, 0.68 } },                                                         -- RUN: rune
}
jobicons.glyphs[17] = cat(jobicons.glyphs[17], { { 'r', 0.44, 0.44, 0.12, 0.12, 0.04 } })

--- True when there is a pictogram for this job id.
function jobicons.has(id) return jobicons.glyphs[id] ~= nil end

--- Draws the pictogram for job `id` into the square (x, y, size). `g` is a gfx backend.
function jobicons.draw(g, id, x, y, size, color)
    local shapes = jobicons.glyphs[id]
    if not shapes then return false end
    for _, sh in ipairs(shapes) do
        if sh[1] == 'r' then
            g.rect_filled(x + sh[2] * size, y + sh[3] * size, sh[4] * size, sh[5] * size, color, (sh[6] or 0) * size)
        elseif g.quad_filled then
            g.quad_filled(x + sh[2] * size, y + sh[3] * size, x + sh[4] * size, y + sh[5] * size,
                x + sh[6] * size, y + sh[7] * size, x + sh[8] * size, y + sh[9] * size, color)
        end
    end
    return true
end

return jobicons
