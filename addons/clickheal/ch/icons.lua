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

-- cache[size][status id] -> { tex = cdata, ptr = number } | false. Nested, so a lookup builds no key string.
-- When it fills up (sizes pile up while the scale is dragged) the whole generation is retired, not freed: a texture
-- handed out earlier this frame may still be in the draw list, and releasing it before the frame renders would draw
-- a dead texture. The retired generation is only dropped at the next overflow, and anything still used is promoted back.
local cache, retired = {}, {}
local cached_n = 0
local CACHE_MAX = 400

local D3DX_FILTER_TRIANGLE = 4   -- a proper averaging filter; the default one is much softer when shrinking

--- ImGui texture handle (a number) for a status effect id, or nil when it cannot be loaded.
-- `size` (pixels) asks for the icon resampled to exactly that size, so it is drawn 1:1 instead of being
-- squeezed by the GPU's bilinear filter (the game's icons are 32 px, the frames draw them at 14 to 60).
-- Without `size`, or if the sized load fails, the icon is loaded at its own size. A picture named
-- assets/status/<id>.png (your own larger art) is used instead of the game's icon when it exists.
function icons.texture(status_id, size)
    if not icons.ready or not status_id then return nil end
    size = size and math.max(8, math.min(128, math.floor(size + 0.5))) or nil
    local skey = size or 0
    local bucket = cache[skey]
    if not bucket then bucket = {}; cache[skey] = bucket end
    local hit = bucket[status_id]
    if hit ~= nil then return hit and hit.ptr or nil end
    local old = retired[skey]
    hit = old and old[status_id]
    if hit ~= nil then bucket[status_id] = hit; cached_n = cached_n + 1; return hit and hit.ptr or nil end
    if cached_n > CACHE_MAX then retired, cache, cached_n = cache, {}, 0; bucket = {}; cache[skey] = bucket end

    local custom = icons.file_texture('status', tostring(status_id))
    if custom then
        bucket[status_id] = { ptr = custom }; cached_n = cached_n + 1
        return custom
    end

    local function load(w, h, filter)
        local icon = AshitaCore:GetResourceManager():GetStatusIconById(status_id)
        if icon == nil then return nil end
        local out = ffi.new('IDirect3DTexture8*[1]')
        local hr = C.D3DXCreateTextureFromFileInMemoryEx(dev, icon.Bitmap, icon.ImageSize, w, h, 1, 0,
            C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, filter, filter, 0xFF000000, nil, nil, out)
        if hr ~= C.S_OK then return nil end
        local tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', out[0]))
        return { tex = tex, ptr = tonumber(ffi.cast('uint32_t', tex)) }
    end

    local res
    if size then
        local ok, r = pcall(load, size, size, D3DX_FILTER_TRIANGLE)
        if ok then res = r end
    end
    if not res then
        local ok, r = pcall(load, 0xFFFFFFFF, 0xFFFFFFFF, C.D3DX_DEFAULT)
        if ok then res = r end
    end
    if res then
        bucket[status_id] = res; cached_n = cached_n + 1
        return res.ptr
    end
    bucket[status_id] = false; cached_n = cached_n + 1
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
