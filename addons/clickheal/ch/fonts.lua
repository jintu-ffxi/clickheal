--[[
    ClickHeal - fonts.lua
    ImGui's built-in font is a tiny pixel font; stretched to 4K it turns soft. This loads a real vector
    font from Windows (Segoe UI, else Arial) once, and pushes it at a fixed base size inside our windows.
    The window font scale still multiplies that size, and Ashita's ImGui bakes glyphs at the final size.
    Everything is optional: if the font cannot be added, the default font is used as before.
]]

local imgui = require('imgui')

local fonts = {}

local BASE = 16            -- base px at 1080p (the window font scale multiplies it)
local font, tried = nil, false

--- Adds the font. Call from the addon's load event (adding a font in the middle of a frame is not safe).
function fonts.init()
    if tried then return font ~= nil end
    tried = true
    if imgui.AddFontFromFileTTF == nil then return false end
    local dir = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    for _, name in ipairs({ 'segoeui.ttf', 'arial.ttf' }) do
        local f = io.open(dir .. name, 'rb')
        if f then
            f:close()
            local ok, h = pcall(imgui.AddFontFromFileTTF, dir .. name, BASE)
            if ok and h then font = h; return true end
        end
    end
    return false
end

--- Pushes the font; returns true when something was pushed (pass that to fonts.pop).
function fonts.push()
    if not font then return false end
    return (pcall(imgui.PushFont, font, BASE))
end

function fonts.pop(pushed)
    if pushed then pcall(imgui.PopFont) end
end

function fonts.loaded() return font ~= nil end

return fonts
