-- Renders the setup panel (configui.lua) through a layout-modelling stub ImGui and writes what it drew as JSON,
-- one file per page and size, for tools/preview_config.py to turn into PNGs.
--
--   lua tools/dump_config.lua <out_dir>
--
-- The real configui.lua runs; the stub places every widget (x and y) the way ImGui does with the panel's style
-- values, measuring text with the Segoe UI widths from tools/font_widths.lua (the font the panel loads in game).
-- Anything that runs past the edge of its container is recorded as a "flag", and drawn in red in the PNG.
-- This is a model, not a screenshot: ImGui's own rounding and scrollbars are not reproduced.
package.path = 'addons/clickheal/?.lua;' .. package.path

local out_dir = arg[1] or 'preview_config_json'
local W = dofile('tools/font_widths.lua')

local floor, max, min = math.floor, math.max, math.min

-- ---------------------------------------------------------------------------------------------
-- stub imgui
-- ---------------------------------------------------------------------------------------------
local S                       -- the frame being drawn
local sim = { sc = 1, win_w = nil }

local STYLE_VARS = { 'WindowRounding', 'ChildRounding', 'FrameRounding', 'GrabRounding', 'PopupRounding',
    'WindowPadding', 'FramePadding', 'ItemSpacing' }
for i, n in ipairs(STYLE_VARS) do _G['ImGuiStyleVar_' .. n] = n end
local COLORS = { 'WindowBg', 'ChildBg', 'PopupBg', 'Border', 'FrameBg', 'FrameBgHovered', 'FrameBgActive', 'TitleBg',
    'TitleBgActive', 'CheckMark', 'SliderGrab', 'SliderGrabActive', 'Button', 'ButtonHovered', 'ButtonActive', 'Header',
    'HeaderHovered', 'HeaderActive', 'Separator', 'Text', 'TextDisabled' }
for _, n in ipairs(COLORS) do _G['ImGuiCol_' .. n] = n end
_G.ImGuiCond_FirstUseEver = 4
_G.ImGuiWindowFlags_NoCollapse = 32
_G.ImGuiChildFlags_Borders = 1

local function new_frame()
    S = { cmds = {}, regions = {}, flags = {}, col = {}, col_stack = {}, style = {}, style_stack = {}, children = {},
        base = 13, k = 1, req = nil, cons = nil, next_w = nil, win = nil }
end

local function px() return S.base * S.k end
local function tw(text)
    local total = 0
    for i = 1, #tostring(text) do
        total = total + (W.w[tostring(text):byte(i)] or W.avg)
    end
    return total / W.em * px()
end
local function vis(label) return (tostring(label):match('^(.-)##') or tostring(label)) end
local function style(name, fallback)
    local v = S.style[name]
    return v or fallback
end
local function pad_xy(name, fx, fy)
    local v = S.style[name]
    if type(v) == 'table' then return v[1], v[2] end
    return fx, fy
end
local function frame_h() local _, py = pad_xy('FramePadding', 4, 3); return px() + 2 * py end
local function color(name, fallback)
    return S.col[name] or fallback
end
local function region() return S.regions[#S.regions] end
local function emit(c) S.cmds[#S.cmds + 1] = c; return c end
local function rect(x, y, w, h, c, r, extra)
    local cmd = { op = 'rect', x = x, y = y, w = w, h = h, c = c, r = r or 0 }
    for k, v in pairs(extra or {}) do cmd[k] = v end
    return emit(cmd)
end
local function text(x, y, s, c)
    return emit({ op = 'text', x = x, y = y, s = tostring(s), c = c or color('Text', { 0.9, 0.92, 0.95, 1 }), px = px() })
end

--- Places an item of size w x h at the cursor (or beside the last one after SameLine). Returns x, y.
local function item(w, h, what)
    local r = region()
    local isx, isy = pad_xy('ItemSpacing', 8, 4)
    local x, y
    if r.same then
        x = r.sl_x or (r.last_x + isx)
        y = r.line_y
        r.line_h = max(r.line_h, h)
    else
        x, y = r.x0, r.next_y
        r.line_y, r.line_h = y, h
    end
    r.same, r.sl_x = false, nil
    r.last_x = x + w
    r.next_y = r.line_y + r.line_h + isy
    r.bottom = max(r.bottom, y + h)
    if what and x + w > r.x0 + r.w + 0.5 then
        S.flags[#S.flags + 1] = { x = x, y = y, w = w, h = h, what = what }
    end
    return x, y
end

local function wrap_lines(s, maxw)
    local lines = {}
    for para in (tostring(s) .. '\n'):gmatch('(.-)\n') do
        local cur = ''
        for word in para:gmatch('%S+') do
            local try = (cur == '') and word or (cur .. ' ' .. word)
            if cur ~= '' and tw(try) > maxw then lines[#lines + 1] = cur; cur = word else cur = try end
        end
        lines[#lines + 1] = cur
    end
    return lines
end

local function item_width(frac)
    local r = region()
    local w = S.next_w or (r.w * (frac or 0.65))
    S.next_w = nil
    return w
end

local function pop_colors(n)
    for _ = 1, n do
        local e = table.remove(S.col_stack)
        if e then S.col[e[1]] = e[2] end
    end
end

package.preload['imgui'] = function()
    local im = {}
    local specific = {
        SetNextWindowSize = function(sz) S.req = { sz[1], sz[2] } end,
        SetNextWindowSizeConstraints = function(mn, mxs) S.cons = { mn, mxs } end,
        PushStyleColor = function(id, c)
            S.col_stack[#S.col_stack + 1] = { id, S.col[id] }
            S.col[id] = c
            return true
        end,
        PopStyleColor = function(n) pop_colors(n or 1) end,
        PushStyleVar = function(id, v)
            S.style_stack[#S.style_stack + 1] = { id, S.style[id] }
            S.style[id] = v
            return true
        end,
        PopStyleVar = function(n)
            for _ = 1, n or 1 do
                local e = table.remove(S.style_stack)
                if e then S.style[e[1]] = e[2] end
            end
        end,
        AddFontFromFileTTF = function() return {} end,
        PushFont = function(_, size) S.base_saved = S.base; S.base = size or S.base end,
        PopFont = function() S.base = S.base_saved or 13 end,
        SetWindowFontScale = function(k) S.k = k end,
        CalcTextSize = function(s) return tw(s), px() end,
        Begin = function(title)
            local w = S.req and S.req[1] or 760
            if sim.win_w then w = sim.win_w end
            if S.cons then w = max(S.cons[1][1], min(S.cons[2][1], w)) end
            local wx, wy = pad_xy('WindowPadding', 8, 8)
            S.win = { w = w, h = S.req and S.req[2] or 600 }
            S.win.bg = rect(0, 0, w, 0, color('WindowBg', { 0.07, 0.07, 0.1, 1 }), style('WindowRounding', 0))
            local title_h = px() + 2 * select(2, pad_xy('FramePadding', 4, 3))
            rect(0, 0, w, title_h, color('TitleBgActive', { 0.08, 0.09, 0.12, 1 }), 0)
            text(wx, title_h / 2 - px() / 2, title)
            S.regions[#S.regions + 1] = { x0 = wx, w = w - 2 * wx, next_y = title_h + wy, bottom = title_h + wy,
                line_y = title_h + wy, line_h = 0, last_x = wx }
            return true
        end,
        End = function()
            S.regions[#S.regions] = nil
        end,
        GetContentRegionAvail = function()
            local r = region()
            local x = r.same and (r.sl_x or r.last_x + select(1, pad_xy('ItemSpacing', 8, 4))) or r.x0
            return r.x0 + r.w - x, 400
        end,
        SameLine = function(off) local r = region(); r.same = true; r.sl_x = off and (r.x0 + off) or nil end,
        SetNextItemWidth = function(w) S.next_w = w end,
        Spacing = function() local _, isy = pad_xy('ItemSpacing', 8, 4); item(0, isy) end,
        Separator = function()
            local r = region()
            local x, y = item(r.w, 1)
            rect(x, y, r.w, 1, color('Separator', { 0.2, 0.2, 0.27, 1 }), 0)
        end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        Text = function(s)
            local x, y = item(tw(s), px(), 'Text "' .. tostring(s) .. '"')
            text(x, y, s)
        end,
        TextColored = function(c, s)
            local x, y = item(tw(s), px(), 'Text "' .. tostring(s) .. '"')
            text(x, y, s, c)
        end,
        TextWrapped = function(s)
            local r = region()
            local isx = pad_xy('ItemSpacing', 8, 4)
            local x0 = r.same and (r.sl_x or r.last_x + isx) or r.x0
            s = tostring(s):gsub('%%%%', '%%')
            local lines = wrap_lines(s, r.x0 + r.w - x0)
            local x, y = item(r.x0 + r.w - x0, #lines * px())
            for i, l in ipairs(lines) do text(x, y + (i - 1) * px(), l) end
        end,
        Checkbox = function(l, t)
            local h = frame_h()
            local x, y = item(h, h, 'Checkbox')
            rect(x, y, h, h, color('FrameBg', { 0.12, 0.14, 0.18, 1 }), style('FrameRounding', 0))
            if t[1] then
                emit({ op = 'line', pts = { x + h * 0.25, y + h * 0.52, x + h * 0.43, y + h * 0.72, x + h * 0.76, y + h * 0.30 },
                    c = color('CheckMark', { 0.4, 0.62, 0.95, 1 }), t = max(2, h * 0.1) })
            end
            return false
        end,
        SliderFloat = function(l, t, lo, hi, fmt)
            local w, h = item_width(), frame_h()
            local x, y = item(w, h, 'Slider')
            rect(x, y, w, h, color('FrameBg', { 0.12, 0.14, 0.18, 1 }), style('FrameRounding', 0))
            local f = (hi > lo) and max(0, min(1, (t[1] - lo) / (hi - lo))) or 0
            rect(x + (w - 12) * f, y + 2, 12, h - 4, color('SliderGrab', { 0.4, 0.62, 0.95, 1 }), style('GrabRounding', 0))
            local v = string.format(fmt or '%.2f', t[1])
            text(x + (w - tw(v)) / 2, y + (h - px()) / 2, v)
            return false
        end,
        SliderInt = function(l, t, lo, hi)
            local w, h = item_width(), frame_h()
            local x, y = item(w, h, 'Slider')
            rect(x, y, w, h, color('FrameBg', { 0.12, 0.14, 0.18, 1 }), style('FrameRounding', 0))
            local f = (hi > lo) and max(0, min(1, (t[1] - lo) / (hi - lo))) or 0
            rect(x + (w - 12) * f, y + 2, 12, h - 4, color('SliderGrab', { 0.4, 0.62, 0.95, 1 }), style('GrabRounding', 0))
            local v = tostring(t[1])
            text(x + (w - tw(v)) / 2, y + (h - px()) / 2, v)
            return false
        end,
        Button = function(l)
            local label = vis(l)
            local pxx, _ = pad_xy('FramePadding', 4, 3)
            local w, h = tw(label) + 2 * pxx, frame_h()
            local x, y = item(w, h, 'Button "' .. label .. '"')
            rect(x, y, w, h, color('Button', { 0.15, 0.17, 0.22, 1 }), style('FrameRounding', 0))
            text(x + pxx, y + (h - px()) / 2, label)
            return false
        end,
        Dummy = function(sz) item(sz[1], sz[2]) end,
        SmallButton = function(l)
            local label = vis(l)
            local w, h = tw(label) + 8, px()
            local x, y = item(w, h, 'Button "' .. label .. '"')
            rect(x, y, w, h, color('Button', { 0.15, 0.17, 0.22, 1 }), 3)
            text(x + 4, y, label)
            return false
        end,
        ColorEdit3 = function(l, c)
            local w, h = item_width(), frame_h()
            local x, y = item(w, h, 'Color')
            rect(x, y, w, h, color('FrameBg', { 0.12, 0.14, 0.18, 1 }), style('FrameRounding', 0))
            rect(x + w - h, y + 3, h - 6, h - 6, { c[1], c[2], c[3], 1 }, 3)
            text(x + 8, y + (h - px()) / 2, string.format('%d  %d  %d', floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5)))
            return false
        end,
        CollapsingHeader = function(l)
            local r = region()
            local h = frame_h()
            local x, y = item(r.w, h, (tw(vis(l)) + 40 > r.w) and 'Header' or nil)
            rect(x, y, r.w, h, color('Header', { 0.2, 0.3, 0.5, 0.3 }), style('FrameRounding', 0))
            text(x + 28, y + (h - px()) / 2, vis(l))
            return true   -- shown open so everything inside is checked
        end,
        BeginCombo = function(l, preview)
            local w, h = item_width(), frame_h()
            local x, y = item(w, h, 'Combo')
            rect(x, y, w, h, color('FrameBg', { 0.12, 0.14, 0.18, 1 }), style('FrameRounding', 0))
            local pxx = pad_xy('FramePadding', 4, 3)
            text(x + pxx, y + (h - px()) / 2, preview)
            if tw(preview) + pxx + h > w + 0.5 then S.flags[#S.flags + 1] = { x = x, y = y, w = w, h = h, what = 'Combo text clipped' } end
            text(x + w - h * 0.7, y + (h - px()) / 2, 'v')
            return false
        end,
        EndCombo = function() end,
        Selectable = function(l, selected, flags, size)
            local r = region()
            local h = (type(size) == 'table' and size[2] and size[2] > 0) and size[2] or px()
            local x, y = item(r.w, h)
            if selected then rect(x - 6, y, r.w + 12, h, color('Header', { 0.2, 0.3, 0.5, 0.3 }), 4) end
            text(x, y + (h - px()) / 2, vis(l))
            return false
        end,
        BeginChild = function(id, size)
            local r = region()
            local isx = pad_xy('ItemSpacing', 8, 4)
            local x0 = r.same and (r.sl_x or r.last_x + isx) or r.x0
            local avail = r.x0 + r.w - x0
            local cw = (size[1] and size[1] > 0) and size[1] or avail
            local x, y = item(cw, 0, (cw > avail + 0.5) and ('child ' .. id) or nil)
            local wx, wy = pad_xy('WindowPadding', 8, 8)
            local bg = rect(x, y, cw, 0, color('ChildBg', { 0.09, 0.1, 0.12, 1 }), style('ChildRounding', 0),
                { border = color('Border', { 0.2, 0.2, 0.27, 1 }) })
            S.children[#S.children + 1] = { bg = bg, y = y }
            S.regions[#S.regions + 1] = { x0 = x + wx, w = cw - 2 * wx, next_y = y + wy, bottom = y + wy, line_y = y + wy,
                line_h = 0, last_x = x + wx, child = bg, id = id }
            return true
        end,
        EndChild = function()
            local r = table.remove(S.regions)
            local wx, wy = pad_xy('WindowPadding', 8, 8)
            local parent = region()
            r.child.h = r.bottom + wy - r.child.y
            if r.id == '##nav' then S.nav_bottom = r.child.y + r.child.h end
            parent.bottom = max(parent.bottom, r.child.y + r.child.h)
            parent.line_h = max(parent.line_h, r.child.h)
            parent.next_y = parent.line_y + parent.line_h + select(2, pad_xy('ItemSpacing', 8, 4))
            parent.last_x = r.child.x + r.child.w
        end,
    }
    return setmetatable(im, { __index = function(_, name) return specific[name] or function() return false end end })
end

local configui = require('ch.configui')
local chconfig = require('ch.chconfig')
local spells   = require('ch.spells')
require('ch.fonts').init()

-- ---------------------------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------------------------

local function esc(s)
    return (tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' end
        return string.format('\\u%04x', c:byte())
    end))
end

local function col(c) return string.format('[%d,%d,%d,%d]', floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5), floor((c[4] or 1) * 255 + 0.5)) end

local function to_json(w, h, cmds, flags, title)
    local parts = {}
    for _, c in ipairs(cmds) do
        if c.op == 'rect' then
            parts[#parts + 1] = string.format('{"op":"rect","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"r":%.1f,"c":%s%s}', c.x, c.y, c.w, c.h, c.r, col(c.c),
                c.border and (',"b":' .. col(c.border)) or '')
        elseif c.op == 'text' then
            parts[#parts + 1] = string.format('{"op":"text","x":%.1f,"y":%.1f,"px":%.2f,"c":%s,"s":"%s"}', c.x, c.y, c.px, col(c.c), esc(c.s))
        elseif c.op == 'line' then
            local p = {}
            for _, v in ipairs(c.pts) do p[#p + 1] = string.format('%.1f', v) end
            parts[#parts + 1] = string.format('{"op":"line","p":[%s],"t":%.1f,"c":%s}', table.concat(p, ','), c.t, col(c.c))
        end
    end
    local fl = {}
    for _, f in ipairs(flags) do
        fl[#fl + 1] = string.format('{"x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"what":"%s"}', f.x, f.y, f.w, f.h, esc(f.what))
    end
    return string.format('{"w":%d,"h":%d,"title":"%s","cmds":[%s],"flags":[%s]}', floor(w), floor(h), esc(title), table.concat(parts, ',\n'), table.concat(fl, ','))
end

local function render_page(index, sc, zoom, over, win_w)
    sim.sc, sim.win_w = sc, win_w
    local s = chconfig.sanitize({})
    for k, v in pairs(over or {}) do s[k] = v end
    s.ui_zoom = zoom
    local ctx = {
        geom = { width = 230, height = 288, scale = sc }, disp_w = 1920 * sc, disp_h = 1080 * sc,
        force_pos = function() end, preset = spells.presets.WHM, player = nil,
    }
    configui.open[1] = true
    configui.page = index
    local last
    for _ = 1, 3 do        -- the label column settles after one frame
        new_frame()
        local _, err = configui.draw(s, ctx)
        if err then error(err) end
        last = S
    end
    local H = S.win.h
    -- the sidebar lists every page, so it has to fit the window (the content area scrolls, the sidebar should not)
    if S.nav_bottom and S.nav_bottom > S.win.h - 14 * sc then
        S.flags[#S.flags + 1] = { x = 10, y = S.nav_bottom - 30, w = 150, h = 30, what = 'sidebar taller than the window' }
    end
    for _, c in ipairs(S.children) do H = max(H, c.bg.y + c.bg.h + 14 * sc) end
    -- every child fills the window's remaining height, as in ImGui
    for _, c in ipairs(S.children) do c.bg.h = H - 14 * sc - c.y end
    S.win.bg.h = H
    return S.win.w, H, S.cmds, S.flags
end

os.execute('mkdir "' .. out_dir:gsub('/', '\\') .. '" 2>nul')
local total_flags = 0
local function dump(name, index, sc, zoom, over, win_w)
    local w, h, cmds, flags = render_page(index, sc, zoom, over, win_w)
    local f = assert(io.open(out_dir .. '/' .. name .. '.json', 'wb'))
    f:write(to_json(w, h, cmds, flags, name))
    f:close()
    total_flags = total_flags + #flags
    print(string.format('%-34s %4dx%-4d %d flagged', name, w, h, #flags))
end

for i, page in ipairs(configui.PAGES) do
    local slug = page[1]:lower()
    dump('cfg_' .. slug .. '_1080', i, 1.0, 100, { demo = false })
    dump('cfg_' .. slug .. '_4k', i, 2.0, 100, { demo = false })
end
-- the sizes that used to cut text off: bigger text, narrow window, hairline/triage on
dump('cfg_appearance_1080_text150', 1, 1.0, 150, { demo = false })
dump('cfg_appearance_4k_text250', 1, 2.0, 250, { demo = false })
dump('cfg_alerts_4k_text150', 4, 2.0, 150, { demo = false })
dump('cfg_spells_1080_narrow', 2, 1.0, 100, { demo = false }, 520)
dump('cfg_triage_1080_triageon', 3, 1.0, 100, { demo = false, triage = true })
print(string.format('%d flagged items in total', total_flags))
os.exit(total_flags == 0 and 0 or 1)
