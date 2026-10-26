-- Prints the screen footprint of the strip in every mode at common resolutions.
-- Run from the repo root:  lua tools/footprint.lua      (or texlua tools/footprint.lua)
package.path = 'addons/clickheal/?.lua;' .. package.path

local layout = require('ch.layout')

local resolutions = { { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 } }
local modes = { { 'party', 6 }, { 'alliance1', 12 }, { 'alliance2', 18 } }

print(string.format('%-8s %-10s %-5s %-11s %-11s %s', 'style', 'mode', 'res', 'px (w x h)', 'scale', 'screen %w x %h'))
for _, style in ipairs({ 'strip' }) do
    for _, m in ipairs(modes) do
        for _, res in ipairs(resolutions) do
            local groups = layout.groups_for(m[1], false)
            local g = layout.compute({ orientation = 'columns', auto_scale = true, scale = 1.0, groups = groups }, res[2])
            local fw, fh = layout.footprint(g, res[1], res[2])
            print(string.format('%-8s %-10s %-5s %-11s %-11.2f %.1f%% x %.1f%%',
                style, m[1] .. '(' .. m[2] .. ')', res[2] .. 'p',
                g.width .. 'x' .. g.height, g.scale, fw * 100, fh * 100))
        end
    end
end
