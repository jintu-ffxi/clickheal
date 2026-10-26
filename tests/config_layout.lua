-- Layout test for the setup panel (configui.lua).
--
--   lua tests/config_layout.lua       (run from the repository root)
--
-- Runs the real panel against a stub ImGui that models cursor placement and text width, then checks
-- that nothing is drawn past the edge of its container: labels, widgets, combo text, list rows.
-- It does not prove the stub's metrics match the real ImGui; it proves the panel never relies on a
-- fixed width, so overruns would have to come from a font far outside the tested range.
package.path = 'addons/clickheal/?.lua;' .. package.path

local passed, failed, failures = 0, 0, {}
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; failures[#failures + 1] = name .. '\n      ' .. tostring(err) end
end

-- ---------------------------------------------------------------------------------------------
-- stub imgui with a cursor model
-- ---------------------------------------------------------------------------------------------
local sim = { char_w = 7, win_w = nil, sc = 1, interact = false }
local S                      -- per-frame state
local violations

local function reset_frame()
    S = { regions = {}, font = 1, next_w = nil, same = false, sl_x = nil, last_end = 0, combo_w = nil, req = nil, cons = nil }
    violations = {}
end

local function vis(label)
    label = tostring(label)
    local v = label:match('^(.-)##') or label
    return v
end
local function tw(text) return #tostring(text) * sim.char_w * S.font end
local function region() return S.regions[#S.regions] end
local function spacing() return 10 * sim.sc end

local function cursor_x()
    local r = region()
    if S.same then return S.sl_x or (S.last_end + spacing()) end
    return r.x0
end

local function violate(what, x, w)
    local r = region()
    violations[#violations + 1] = string.format('%s: x=%.0f w=%.0f limit=%.0f', what, x, w, r.x0 + r.w)
end

local function place(w, what)
    local r = region()
    local x = cursor_x()
    if x + w > r.x0 + r.w + 0.5 then violate(what, x, w) end
    S.last_end = x + w
    S.same, S.sl_x = false, nil
    return x
end

local function take_width(default_frac)
    local r = region()
    local w = S.next_w or (r.w * (default_frac or 0.65))
    S.next_w = nil
    return w
end

local function label_w(label)
    local v = vis(label)
    return v == '' and 0 or (spacing() * 0.6 + tw(v))
end

package.preload['imgui'] = function()
    local im = {}
    local specific = {
        SetNextWindowSize = function(sz) S.req = { sz[1], sz[2] } end,
        SetNextWindowSizeConstraints = function(mn, mx) S.cons = { mn, mx } end,
        Begin = function()
            local w = S.req and S.req[1] or 760
            if sim.win_w then w = sim.win_w end
            if S.cons then w = math.max(S.cons[1][1], math.min(S.cons[2][1], w)) end
            local pad = 16 * sim.sc
            S.win = { w = w }
            S.regions[#S.regions + 1] = { x0 = pad, w = w - 2 * pad }
            S.last_end = pad
            return true
        end,
        End = function() S.regions[#S.regions] = nil end,
        SetWindowFontScale = function(f) S.font = f end,
        PushStyleVar = function() end, PopStyleVar = function() end,
        PushStyleColor = function() return true end, PopStyleColor = function() end,
        CalcTextSize = function(s) return tw(s), 13 end,
        GetContentRegionAvail = function()
            local r = region()
            return r.x0 + r.w - cursor_x(), 400
        end,
        SameLine = function(off) S.same = true; S.sl_x = off and (region().x0 + off) or nil end,
        SetNextItemWidth = function(w) S.next_w = w end,
        Spacing = function() S.same = false end,
        Separator = function() S.same = false end,
        IsItemHovered = function() return false end,
        Text = function(s) place(tw(s), 'Text "' .. tostring(s) .. '"') end,
        TextColored = function(_, s) place(tw(s), 'TextColored "' .. tostring(s) .. '"') end,
        TextWrapped = function() place(1, 'TextWrapped') end,
        Checkbox = function(l, t)
            place(20 * sim.sc + label_w(l), 'Checkbox ' .. vis(l))
            if sim.interact then t[1] = not t[1]; return true end
            return false
        end,
        SliderFloat = function(l, t, lo, hi) place(take_width() + label_w(l), 'SliderFloat ' .. l); if sim.interact then t[1] = hi; return true end return false end,
        SliderInt = function(l, t, lo, hi) place(take_width() + label_w(l), 'SliderInt ' .. l); if sim.interact then t[1] = hi; return true end return false end,
        Button = function(l) place(tw(vis(l)) + 20 * sim.sc, 'Button ' .. vis(l)); return sim.interact end,
        SmallButton = function(l) place(tw(vis(l)) + 20 * sim.sc, 'SmallButton ' .. vis(l)); return false end,
        CollapsingHeader = function(l)
            local r = region()
            if tw(vis(l)) + 40 * sim.sc > r.w then violate('CollapsingHeader ' .. vis(l), r.x0, tw(vis(l)) + 40 * sim.sc) end
            S.same = false
            return true
        end,
        BeginCombo = function(l, preview)
            local w = take_width()
            place(w + label_w(l), 'Combo ' .. l)
            if tw(preview) + 30 * sim.sc > w then violate('Combo preview clipped "' .. tostring(preview) .. '"', 0, tw(preview) + 30 * sim.sc) end
            S.combo_w = w
            return true
        end,
        EndCombo = function() S.combo_w = nil end,
        Selectable = function(l)
            local text = vis(l)
            local limit = S.combo_w or region().w
            local pad = S.combo_w and 16 * sim.sc or 2 * sim.sc    -- popup items carry padding; nav items fill the child
            if tw(text) + pad > limit then violate('Selectable clipped "' .. text .. '"', 0, tw(text) + pad) end
            return false
        end,
        BeginChild = function(id, size)
            local r = region()
            local start = cursor_x()
            local avail = r.x0 + r.w - start
            local cw = (size[1] and size[1] > 0) and size[1] or avail
            if cw > avail + 0.5 then violate('child ' .. id, start, cw) end
            local pad = 16 * sim.sc
            S.regions[#S.regions + 1] = { x0 = pad, w = cw - 2 * pad - 14 * sim.sc, outer = { start = start, w = cw } }
            S.child_saved = S.child_saved or {}
            S.child_saved[#S.child_saved + 1] = { last_end = S.last_end, same = S.same, sl_x = S.sl_x }
            S.last_end = pad; S.same = false; S.sl_x = nil
            return true
        end,
        EndChild = function()
            local r = table.remove(S.regions)
            local saved = table.remove(S.child_saved)
            S.last_end = r.outer.start + r.outer.w
            S.same, S.sl_x = false, nil
            local _ = saved
        end,
    }
    return setmetatable(im, { __index = function(_, name) return specific[name] or function() return false end end })
end

_G.ImGuiCond_FirstUseEver = 4
_G.ImGuiWindowFlags_NoCollapse = 32
_G.ImGuiChildFlags_Borders = 1
_G.ImGuiTreeNodeFlags_DefaultOpen = 32

local configui = require('ch.configui')
local chconfig = require('ch.chconfig')
local spells = require('ch.spells')

local function run_page(i, sc, char_w, win_w, over)
    sim.sc, sim.char_w, sim.win_w = sc, char_w, win_w
    local s = chconfig.sanitize({})
    for k, v in pairs(over or {}) do s[k] = v end
    local ctx = {
        geom = { width = 230, height = 288, scale = sc }, disp_w = 1920 * sc, disp_h = 1080 * sc,
        force_pos = function() end, preset = spells.presets.WHM, player = nil,
    }
    configui.open[1] = true
    configui.page = i
    local last
    for _ = 1, 3 do        -- the label column settles after one frame
        reset_frame()
        local _, err = configui.draw(s, ctx)
        if err then error(err) end
        last = violations
    end
    return last
end

local widths = { 'default', 'min', 'wide' }
for i, page in ipairs(configui.PAGES) do
    test('setup panel page "' .. page[1] .. '" never overruns (scales, font widths, window sizes)', function()
        for _, sc in ipairs({ 1.0, 1.5, 2.0 }) do
            for _, char_w in ipairs({ 6, 7, 9 }) do
                for _, wname in ipairs(widths) do
                    local win_w = ({ default = nil, min = 1, wide = 1400 * sc })[wname]
                    local v = run_page(i, sc, char_w, win_w, { demo = false, cast = true })
                    if #v > 0 then
                        error(string.format('scale %.1f, char %d, window %s: %s (+%d more)', sc, char_w, wname, v[1], #v - 1))
                    end
                end
            end
        end
    end)
end

test('setup panel drops labels above their controls when the window is narrow', function()
    -- A label that cannot sit beside its control must not collide with it: no violations at the minimum width.
    for i = 1, #configui.PAGES do
        local v = run_page(i, 1.0, 9, 1, {})
        if #v > 0 then error('page ' .. i .. ': ' .. v[1]) end
    end
end)

print(string.format('\n%d passed, %d failed', passed, failed))
for _, f in ipairs(failures) do print('  FAIL: ' .. f) end
os.exit(failed == 0 and 0 or 1)
