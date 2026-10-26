--[[
    icondump - a throw-away helper, NOT part of ClickHeal.
    Saves the game's own status icons to <this addon>/out/<id>.bmp so tools/make_media.py can use them in
    local screenshots. The icons are the game's art: keep them on your machine and do not commit them.

    Copy this folder to Ashita/addons/icondump, then in game: /addon load icondump   and   /icondump
]]--

addon.name    = 'icondump'
addon.author  = 'local'
addon.version = '1.1'
addon.desc    = 'Saves status icons to disk for ClickHeal preview renders.'

require('common')
local ffi = require('ffi')

local function say(msg) print('[icondump] ' .. msg) end

local function dump()
    local base = (addon and addon.path) or (AshitaCore:GetInstallPath() .. 'addons/icondump/')
    if base:sub(-1) ~= '/' and base:sub(-1) ~= '/' then base = base .. '/' end
    local dir = base .. 'out/'
    say('writing to ' .. dir)
    pcall(function() ashita.fs.create_dir(dir) end)

    local res = AshitaCore:GetResourceManager()
    local saved, none, failed = 0, 0, 0
    for id = 0, 700 do
        local ok, icon = pcall(function() return res:GetStatusIconById(id) end)
        if ok and icon ~= nil and (icon.ImageSize or 0) > 0 then
            local ok2, bytes = pcall(function() return ffi.string(ffi.cast('uint8_t*', icon.Bitmap), icon.ImageSize) end)
            local f = ok2 and io.open(dir .. id .. '.bmp', 'wb')
            if f then f:write(bytes); f:close(); saved = saved + 1 else failed = failed + 1 end
        else
            none = none + 1
        end
    end
    say(string.format('saved %d icons (%d ids without an icon, %d failed to write)', saved, none, failed))
end

ashita.events.register('load', 'icondump_load', function()
    say('loaded. Type /icondump to save the status icons.')
end)

ashita.events.register('command', 'icondump_cmd', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/icondump' then return end
    e.blocked = true
    local ok, err = pcall(dump)
    if not ok then say('error: ' .. tostring(err)) end
end)
