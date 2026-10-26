--[[
    ClickHeal - gfx_imgui.lua
    The in-game graphics backend: implements the small gfx interface that ui.lua draws through,
    on top of Ashita v4's ImGui bindings.

    UNVERIFIED AGAINST A LIVE ASHITA BUILD. Everything here is written from knowledge of the
    Ashita v4 Lua ImGui API and could not be run outside the game. Every ImGui call the addon
    relies on is isolated in this file and in configui.lua, and `/ch apicheck` probes them all so
    mismatches on CatsEyeXI's build show up immediately (Phase 0).
]]--

local imgui = require('imgui')
local theme = require('ch.theme')
local icons = require('ch.icons')
local fonts = require('ch.fonts')
local mousefix = require('ch.mousefix')

local M = {}

local floor = math.floor

-- ---------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------

local function flag(name) return _G[name] or 0 end

local function bor(...)
    if bit and bit.bor then return bit.bor(...) end
    local sum = 0
    for _, v in ipairs({ ... }) do sum = sum + v end   -- last-resort: flags are distinct bits
    return sum
end

--- Normalizes the several shapes ImGui vectors can come back in (x, y | {x,y} | userdata .x/.y).
local function xy(a, b)
    local ta = type(a)
    if ta == 'number' then return a, b or 0 end
    if ta == 'table' or ta == 'userdata' then
        local okx, x = pcall(function() return a.x or a[1] end)
        local oky, y = pcall(function() return a.y or a[2] end)
        return (okx and x) or 0, (oky and y) or 0
    end
    return 0, 0
end
M.xy = xy

local function px(v) return floor(v + 0.5) end

-- ---------------------------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------------------------

local font_scale   = 1.0
local mouse_fix    = false   -- stretch the mouse position to match a resized game window
local font_pushed  = false   -- our vector font is on the stack for the current window
local color_cache  = {}
local size_cache   = {}
local draw_list    = nil
local var_pushes   = 0
local rounded_ok   = true

local function u32(c)
    local v = color_cache[c]
    if v == nil then
        local r, g, b, a = theme.unpack(c)
        local ok, res = pcall(imgui.GetColorU32, { r, g, b, a })
        -- Fallback: our packed integer already uses ImGui's IM_COL32 layout.
        v = (ok and res) or c
        color_cache[c] = v
    end
    return v
end

function M.set_mouse_fix(on) mouse_fix = on and true or false end

function M.set_font_scale(s)
    if s ~= font_scale then
        font_scale = s
        size_cache = {}
    end
end

-- ---------------------------------------------------------------------------------------------
-- frame info
-- ---------------------------------------------------------------------------------------------

function M.now()
    local ok, t = pcall(imgui.GetTime)
    if ok and type(t) == 'number' then return t end
    return os.clock()
end

--- Size of the game's drawing area in pixels. Falls back to 1920x1080 if ImGui cannot say.
function M.display_size()
    local ok, io = pcall(imgui.GetIO)
    if ok and io then
        local okd, ds = pcall(function() return io.DisplaySize end)
        if okd and ds then
            local w, h = xy(ds)
            if w and h and w > 0 and h > 0 then return w, h end
        end
    end
    return 1920, 1080
end

--- Mouse state for the current window. Call between begin_surface and end_surface.
function M.input()
    local mx, my = 0, 0
    local okm, a, b = pcall(imgui.GetMousePos)
    if okm then mx, my = xy(a, b) end
    if mouse_fix then
        local dw, dh = M.display_size()
        local fx, fy = mousefix.factors(dw, dh)
        mx, my = mx * fx, my * fy
    end

    local function clicked(btn)
        local ok, v = pcall(imgui.IsMouseClicked, btn)
        return ok and v == true
    end
    local function down(btn)
        local ok, v = pcall(imgui.IsMouseDown, btn)
        return ok and v == true
    end
    local okh, hovered = pcall(imgui.IsWindowHovered)

    local mods = { shift = false, ctrl = false, alt = false }
    local oki, io = pcall(imgui.GetIO)
    if oki and io then
        local function get(name)
            local ok, v = pcall(function() return io[name] end)
            return ok and v == true
        end
        mods.shift, mods.ctrl, mods.alt = get('KeyShift'), get('KeyCtrl'), get('KeyAlt')
    end

    return {
        mx = mx, my = my,
        hovered = okh and hovered == true,
        interactive = true,
        clicked = { left = clicked(0), right = clicked(1), middle = clicked(2) },
        down = { left = down(0) },
        mods = mods,
    }
end

-- ---------------------------------------------------------------------------------------------
-- surfaces (borderless, transparent ImGui windows we draw into)
-- ---------------------------------------------------------------------------------------------

--- Starts a window. Returns its screen position (x, y), or nil when ImGui says it is not visible.
-- opts: { movable = bool, force_pos = bool }
-- ALWAYS pair with end_surface(), even when this returns nil.
function M.begin_surface(id, x, y, w, h, opts)
    opts = opts or {}
    draw_list = nil

    local function pop_styles()
        if var_pushes > 0 then
            pcall(imgui.PopStyleVar, var_pushes)
            var_pushes = 0
        end
    end

    -- Everything up to and including Begin runs protected: if any call throws (for example a
    -- function missing on this build) the style stack is restored and the error is re-raised.
    -- No Begin has happened at that point, so the caller must NOT call end_surface().
    local flags
    local ok, err = pcall(function()
        local cond_always = flag('ImGuiCond_Always'); if cond_always == 0 then cond_always = 1 end
        local cond_once   = flag('ImGuiCond_Once');   if cond_once == 0 then cond_once = 2 end

        if opts.movable and not opts.force_pos then
            imgui.SetNextWindowPos({ x, y }, cond_once)
        else
            imgui.SetNextWindowPos({ x, y }, cond_always)
        end
        imgui.SetNextWindowSize({ w, h }, cond_always)

        var_pushes = 0
        if _G.ImGuiStyleVar_WindowPadding then
            imgui.PushStyleVar(_G.ImGuiStyleVar_WindowPadding, { 0, 0 }); var_pushes = var_pushes + 1
        end
        if _G.ImGuiStyleVar_WindowBorderSize then
            imgui.PushStyleVar(_G.ImGuiStyleVar_WindowBorderSize, 0); var_pushes = var_pushes + 1
        end

        flags = bor(
            flag('ImGuiWindowFlags_NoTitleBar'), flag('ImGuiWindowFlags_NoResize'),
            flag('ImGuiWindowFlags_NoScrollbar'), flag('ImGuiWindowFlags_NoScrollWithMouse'),
            flag('ImGuiWindowFlags_NoCollapse'), flag('ImGuiWindowFlags_NoSavedSettings'),
            flag('ImGuiWindowFlags_NoFocusOnAppearing'), flag('ImGuiWindowFlags_NoNav'),
            flag('ImGuiWindowFlags_NoBackground'),
            opts.back and flag('ImGuiWindowFlags_NoBringToFrontOnFocus') or 0,
            opts.movable and 0 or flag('ImGuiWindowFlags_NoMove')
        )
    end)
    if not ok then
        pop_styles()
        error(err, 0)
    end

    local okb, visible = pcall(imgui.Begin, id, true, flags)
    if not okb then
        pop_styles()
        error(visible, 0)
    end

    -- From here on Begin has happened: the caller MUST call end_surface() whatever we return.
    if not visible then return nil end

    local fk
    font_pushed, fk = fonts.push(fonts.FRAME_PX * font_scale)
    local okp, px_, py_ = pcall(function()
        pcall(imgui.SetWindowFontScale, font_pushed and fk or font_scale)
        draw_list = imgui.GetWindowDrawList()
        local a, b = imgui.GetWindowPos()
        return xy(a, b)
    end)
    if not okp then
        draw_list = nil
        return nil
    end
    return px_, py_
end

--- An invisible drag handle. Returns true while the mouse button is held on it. Because it is a real
-- ImGui item, pressing on it does not start dragging the window. UNVERIFIED on this build: returns
-- false (handle does nothing) if InvisibleButton / SetCursorScreenPos are missing.
function M.hit_area(id, x, y, w, h)
    local ok, active = pcall(function()
        imgui.SetCursorScreenPos({ px(x), px(y) })
        imgui.InvisibleButton(id, { math.max(1, px(w)), math.max(1, px(h)) })
        return imgui.IsItemActive()
    end)
    return ok and active == true
end

function M.end_surface()
    fonts.pop(font_pushed); font_pushed = false
    imgui.End()
    if var_pushes > 0 then
        imgui.PopStyleVar(var_pushes)
        var_pushes = 0
    end
    draw_list = nil
end

-- ---------------------------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------------------------

function M.rect_filled(x, y, w, h, c, rounding)
    if not draw_list or w <= 0 or h <= 0 then return end
    local x1, y1 = px(x), px(y)
    local p1, p2 = { x1, y1 }, { px(x + w), px(y + h) }
    if rounded_ok and rounding and rounding > 0 then
        local ok = pcall(draw_list.AddRectFilled, draw_list, p1, p2, u32(c), rounding)
        if ok then return end
        rounded_ok = false   -- this build does not accept the rounding argument
    end
    draw_list:AddRectFilled(p1, p2, u32(c))
end

-- Slanted shapes. UNVERIFIED: needs draw_list:AddQuadFilled / AddQuad. If the build lacks them (or
-- they throw) we fall back to the shape's bounding rectangle, so the layout still works, just square.
local quad_ok = true

local function bbox(x1, y1, x2, y2, x3, y3, x4, y4)
    local minx, maxx = math.min(x1, x2, x3, x4), math.max(x1, x2, x3, x4)
    local miny, maxy = math.min(y1, y2, y3, y4), math.max(y1, y2, y3, y4)
    return minx, miny, maxx - minx, maxy - miny
end

function M.quad_filled(x1, y1, x2, y2, x3, y3, x4, y4, c)
    if not draw_list then return end
    if quad_ok then
        local ok = pcall(draw_list.AddQuadFilled, draw_list,
            { px(x1), px(y1) }, { px(x2), px(y2) }, { px(x3), px(y3) }, { px(x4), px(y4) }, u32(c))
        if ok then return end
        quad_ok = false
    end
    local x, y, w, h = bbox(x1, y1, x2, y2, x3, y3, x4, y4)
    M.rect_filled(x, y, w, h, c, 0)
end

function M.quad_outline(x1, y1, x2, y2, x3, y3, x4, y4, c, thickness)
    if not draw_list then return end
    if quad_ok then
        local ok = pcall(draw_list.AddQuad, draw_list,
            { px(x1), px(y1) }, { px(x2), px(y2) }, { px(x3), px(y3) }, { px(x4), px(y4) }, u32(c), thickness or 1)
        if ok then return end
        quad_ok = false
    end
    local x, y, w, h = bbox(x1, y1, x2, y2, x3, y3, x4, y4)
    local t = math.max(1, thickness or 1)
    M.rect_filled(x, y, w, t, c, 0); M.rect_filled(x, y + h - t, w, t, c, 0)
    M.rect_filled(x, y + t, t, h - 2 * t, c, 0); M.rect_filled(x + w - t, y + t, t, h - 2 * t, c, 0)
end

-- The game's status icon for a status effect id, drawn size x size. Returns false when the icon
-- cannot be loaded or drawn, so the caller can draw a text tag instead.
local image_ok = true
function M.status_icon(x, y, size, status_id)
    if not draw_list or not image_ok then return false end
    local tex = icons.texture(status_id)
    if not tex then return false end
    local ok = pcall(draw_list.AddImage, draw_list, tex, { px(x), px(y) }, { px(x + size), px(y + size) })
    if not ok then image_ok = false; return false end
    return true
end

-- A user-supplied spell icon (assets/spells/<key>.png). False when there is no such file.
function M.spell_icon(x, y, size, key)
    if not draw_list or not image_ok then return false end
    local tex = icons.spell_texture(key)
    if not tex then return false end
    local ok = pcall(draw_list.AddImage, draw_list, tex, { px(x), px(y) }, { px(x + size), px(y + size) })
    if not ok then image_ok = false; return false end
    return true
end

function M.text(x, y, c, s)
    if not draw_list or s == '' then return end
    draw_list:AddText({ px(x), px(y) }, u32(c), s)
end

-- Smaller text (k < 1) via the draw list's font-size overload. UNVERIFIED in this ImGui binding: if the call
-- fails once, scaled text is turned off and the normal size is used (text_size_scaled follows suit).
local scaled_ok = true
function M.text_scaled(x, y, c, s, k)
    if not draw_list or s == '' then return end
    if math.abs(k - 1) < 0.01 or not scaled_ok then return M.text(x, y, c, s) end
    local ok = pcall(function()
        draw_list:AddText(imgui.GetFont(), imgui.GetFontSize() * k, { px(x), px(y) }, u32(c), s)
    end)
    if not ok then scaled_ok = false; return M.text(x, y, c, s) end
end

function M.text_size_scaled(s, k)
    local w, h = M.text_size(s)
    if math.abs(k - 1) < 0.01 or not scaled_ok then return w, h end
    return w * k, h * k
end

function M.text_size(s)
    local hit = size_cache[s]
    if hit then return hit[1], hit[2] end
    local ok, a, b = pcall(imgui.CalcTextSize, s)
    local w, h
    if ok then w, h = xy(a, b) else w, h = #s * 7 * font_scale, 13 * font_scale end
    size_cache[s] = { w, h }
    return w, h
end

function M.tooltip(lines, scale)
    imgui.BeginTooltip()
    local fp, fk = fonts.push(fonts.FRAME_PX * font_scale)
    -- Protected so EndTooltip always runs, even if a call inside throws.
    pcall(function()
        pcall(imgui.SetWindowFontScale, fp and fk or font_scale)
        for _, line in ipairs(lines) do imgui.Text((tostring(line):gsub('%%', '%%%%'))) end
    end)
    fonts.pop(fp)
    imgui.EndTooltip()
end

return M
