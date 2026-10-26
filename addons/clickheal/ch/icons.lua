--[[
    ClickHeal - icons.lua
    Loads the game's own status-effect icons as Direct3D textures so ImGui can draw them.
    Ashita only (needs ffi and the d3d8 library); everything is protected, and if anything is
    missing `icons.texture()` returns nil and the UI draws text tags instead.

    UNVERIFIED on a live client. The calls follow the pattern the stock `equipmon` addon uses for
    item icons: GetResourceManager():GetStatusIconById -> D3DXCreateTextureFromFileInMemoryEx.
]]--

local icons = { ready = false, failed = 0 }

local ffi, d3d, C, dev
do
    local ok = pcall(function()
        ffi = require('ffi')
        d3d = require('d3d8')
        C = ffi.C
        dev = d3d.get_device()
    end)
    icons.ready = ok and dev ~= nil
end

local cache = {}   -- status id -> { tex = cdata, ptr = number } | false

--- ImGui texture handle (a number) for a status effect id, or nil when it cannot be loaded.
function icons.texture(status_id)
    if not icons.ready or not status_id then return nil end
    local hit = cache[status_id]
    if hit ~= nil then return hit and hit.ptr or nil end

    local ok, res = pcall(function()
        local icon = AshitaCore:GetResourceManager():GetStatusIconById(status_id)
        if icon == nil then return nil end
        local out = ffi.new('IDirect3DTexture8*[1]')
        local hr = C.D3DXCreateTextureFromFileInMemoryEx(dev, icon.Bitmap, icon.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0xFF000000, nil, nil, out)
        if hr ~= C.S_OK then return nil end
        local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', out[0]))
        return { tex = tex, ptr = tonumber(ffi.cast('uint32_t', tex)) }
    end)
    if ok and res then
        cache[status_id] = res
        return res.ptr
    end
    cache[status_id] = false
    icons.failed = icons.failed + 1
    return nil
end

local files = {}   -- "dir/name" -> { tex, ptr } | false

--- Texture handle for assets/<dir>/<name>.png inside the addon folder (user-supplied art), or nil when the
--- file is missing or cannot be loaded. UNVERIFIED on a live client (D3DXCreateTextureFromFileA).
function icons.file_texture(dir, name)
    if not icons.ready or not name then return nil end
    local id = dir .. '/' .. name
    local hit = files[id]
    if hit ~= nil then return hit and hit.ptr or nil end
    local ok, res = pcall(function()
        local base = (addon and addon.path) or ''
        local path = base .. 'assets/' .. id .. '.png'
        local f = io.open(path, 'rb')
        if not f then return nil end
        f:close()
        local out = ffi.new('IDirect3DTexture8*[1]')
        if C.D3DXCreateTextureFromFileA(dev, path, out) ~= C.S_OK then return nil end
        local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', out[0]))
        return { tex = tex, ptr = tonumber(ffi.cast('uint32_t', tex)) }
    end)
    files[id] = (ok and res) or false
    return (ok and res) and res.ptr or nil
end

function icons.spell_texture(key) return icons.file_texture('spells', key) end

return icons
