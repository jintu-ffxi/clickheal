--[[
    ClickHeal - mousefix.lua
    When the game window is resized, the picture is stretched to the new window but ImGui keeps its old
    drawing size, so the mouse position it reports no longer matches what is on screen. This reads the real
    client size of the game window and returns how much to stretch the mouse position to match the picture.
    Everything is protected: any failure just means "no correction" (1, 1).
]]

local mousefix = {}

local ffi_ok, ffi = pcall(require, 'ffi')
local ready = false

local function setup()
    if ready then return ffi_ok end
    ready = true
    if not ffi_ok then return false end
    pcall(ffi.cdef, [[
        typedef struct { long l, t, r, b; } CHF_RECT;
        int GetClientRect(void* hwnd, CHF_RECT* r);
    ]])
    return true
end

--- The game window's client size in pixels, or nil.
function mousefix.client_size()
    if not setup() then return nil end
    local ok, w, h = pcall(function()
        local hwnd = AshitaCore:GetProperties():GetPlayOnlineHwnd()
        if not hwnd or hwnd == 0 then return nil end
        local r = ffi.new('CHF_RECT[1]')
        if ffi.C.GetClientRect(ffi.cast('void*', hwnd), r) == 0 then return nil end
        return tonumber(r[0].r - r[0].l), tonumber(r[0].b - r[0].t)
    end)
    if ok and w and h and w > 0 and h > 0 then return w, h end
    return nil
end

--- (fx, fy): multiply the mouse position by these to land on what is drawn. (1, 1) when nothing is off.
function mousefix.factors(disp_w, disp_h)
    local cw, ch = mousefix.client_size()
    if not cw then return 1, 1 end
    local fx, fy = disp_w / cw, disp_h / ch
    if math.abs(fx - 1) < 0.002 then fx = 1 end
    if math.abs(fy - 1) < 0.002 then fy = 1 end
    return fx, fy
end

return mousefix
