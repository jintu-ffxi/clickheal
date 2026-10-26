--[[
    ClickHeal - fonts.lua
    ImGui's built-in font is a tiny pixel font; stretched to 4K it turns soft. This loads a real vector
    font from Windows (Segoe UI, else Arial) at several sizes. To draw text at `px` pixels it pushes the
    nearest loaded size at or above it and lets the window font scale make up the small remainder, so
    text stays sharp and still follows the size settings whether or not this ImGui can resize a font on
    the fly. Everything is optional: if no font can be added, the default font is used as before.
]]

local imgui = require('imgui')

local fonts = {}

fonts.FRAME_PX = 15        -- party frame text at 1080p, before the frame text multiplier
fonts.SETUP_PX = 18        -- setup window text at 1080p, before the screen scale and the setup text size

local SIZES = { 14, 18, 24, 32, 44, 60, 84 }
local list, tried = {}, false   -- list: { { font, px }, ... } ascending

--- Adds the fonts. Call from the addon's load event (adding a font in the middle of a frame is not safe).
function fonts.init()
    if tried then return #list > 0 end
    tried = true
    if imgui.AddFontFromFileTTF == nil then return false end
    local dir = (os.getenv('WINDIR') or 'C:/Windows') .. '/Fonts/'
    for _, name in ipairs({ 'segoeui.ttf', 'arial.ttf' }) do
        local f = io.open(dir .. name, 'rb')
        if f then
            f:close()
            for _, px in ipairs(SIZES) do
                local ok, h = pcall(imgui.AddFontFromFileTTF, dir .. name, px)
                if ok and h then list[#list + 1] = { h, px } end
            end
            if #list > 0 then return true end
        end
    end
    return false
end

--- Pushes the best loaded size for `px` pixels. Returns (pushed, k): pushed is true when something was
-- pushed (pass it to fonts.pop); k is the window font scale that makes up the rest (px / loaded size).
-- (false) means our font is not available: use the default font and the plain font scale.
function fonts.push(px)
    if #list == 0 then return false end
    px = px or fonts.FRAME_PX
    local pick = list[#list]
    for _, e in ipairs(list) do
        if e[2] >= px - 0.5 then pick = e; break end
    end
    if not pcall(imgui.PushFont, pick[1], pick[2]) then return false end
    return true, px / pick[2]
end

function fonts.pop(pushed)
    if pushed then pcall(imgui.PopFont) end
end

function fonts.loaded() return #list > 0 end

return fonts
