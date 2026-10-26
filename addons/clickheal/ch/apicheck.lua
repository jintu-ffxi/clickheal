--[[
    ClickHeal - apicheck.lua
    `/ch apicheck` -- Phase 0 helper. Probes every Ashita / ImGui function and constant ClickHeal
    uses and reports what is missing on THIS install (e.g. CatsEyeXI's custom Ashita build),
    so API differences are found in seconds instead of by crashing.

    Returns an array of text lines. Does not draw anything or touch the game.
]]--

local M = {}

local IMGUI_FUNCS = {
    -- windows
    'Begin', 'End', 'SetNextWindowPos', 'SetNextWindowSize', 'SetWindowFontScale',
    'PushStyleVar', 'PopStyleVar', 'GetWindowPos', 'GetWindowDrawList', 'IsWindowHovered',
    -- input / metrics
    'GetMousePos', 'IsMouseClicked', 'GetIO', 'GetTime', 'CalcTextSize', 'GetColorU32',
    -- tooltips
    'BeginTooltip', 'EndTooltip', 'Text',
    -- setup panel widgets
    'BeginTabBar', 'EndTabBar', 'BeginTabItem', 'EndTabItem', 'BeginCombo', 'EndCombo', 'Selectable',
    'Checkbox', 'SliderFloat', 'SliderInt', 'Button', 'SameLine', 'Separator', 'Spacing',
    'TextColored', 'TextWrapped', 'InvisibleButton', 'BeginChild', 'EndChild', 'PushStyleColor',
    'PopStyleColor', 'SetNextItemWidth', 'GetContentRegionAvail', 'CollapsingHeader', 'SmallButton',
    'IsItemHovered', 'SetTooltip', 'SetNextWindowSizeConstraints', 'SetCursorScreenPos', 'IsItemActive', 'IsMouseDown',
}

local GLOBALS = {
    'ImGuiCond_Always', 'ImGuiCond_Once', 'ImGuiCond_FirstUseEver',
    'ImGuiStyleVar_WindowPadding', 'ImGuiStyleVar_WindowBorderSize',
    'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', 'ImGuiWindowFlags_NoScrollbar',
    'ImGuiWindowFlags_NoScrollWithMouse', 'ImGuiWindowFlags_NoCollapse',
    'ImGuiWindowFlags_NoSavedSettings', 'ImGuiWindowFlags_NoFocusOnAppearing',
    'ImGuiWindowFlags_NoNav', 'ImGuiWindowFlags_NoBackground', 'ImGuiWindowFlags_NoMove',
    'ImGuiWindowFlags_NoBringToFrontOnFocus',
}

local function describe(v)
    local t = type(v)
    if t == 'table' or t == 'userdata' then
        local parts = {}
        for _, k in ipairs({ 'x', 'y' }) do
            local ok, val = pcall(function() return v[k] end)
            if ok and val ~= nil then parts[#parts + 1] = k .. '=' .. tostring(val) end
        end
        return t .. (#parts > 0 and (' {' .. table.concat(parts, ', ') .. '}') or '')
    end
    return t .. ' ' .. tostring(v)
end

--- Must be called from inside a draw frame (d3d_present): ImGui calls like GetIO / CalcTextSize crash
-- the game when no frame is active. `emit(line)` (optional) is called per line as it is produced, so
-- if a probe still crashes, the last line shown is the one just before the culprit.
function M.run(imgui, emit)
    local out, missing = {}, 0
    local function add(s) out[#out + 1] = s; if emit then emit(s) end end

    add('--- ClickHeal API check (Phase 0) ---')

    local lines = {}
    for _, name in ipairs(IMGUI_FUNCS) do
        if imgui[name] == nil then
            missing = missing + 1
            lines[#lines + 1] = name
        end
    end
    add(string.format('imgui functions: %d checked, %d missing', #IMGUI_FUNCS, #lines))
    if #lines > 0 then add('  MISSING: ' .. table.concat(lines, ', ')) end

    local gl = {}
    for _, name in ipairs(GLOBALS) do
        if _G[name] == nil then gl[#gl + 1] = name end
    end
    missing = missing + #gl
    add(string.format('imgui constants: %d checked, %d missing', #GLOBALS, #gl))
    if #gl > 0 then add('  MISSING: ' .. table.concat(gl, ', ')) end

    -- Shapes of values we depend on.
    add('probing live values (if the game closes here, the next probe is the culprit)...')
    add('next: imgui.GetIO')
    local ok, io = pcall(imgui.GetIO)
    if ok and io then
        local okd, ds = pcall(function() return io.DisplaySize end)
        add('display size: ' .. (okd and describe(ds) or 'NOT AVAILABLE (will assume 1920x1080)'))
        for _, k in ipairs({ 'DisplayFramebufferScale', 'FontGlobalScale' }) do
            local okk, v = pcall(function() return io[k] end)
            add('io.' .. k .. ': ' .. (okk and describe(v) or 'n/a'))
        end
        for _, k in ipairs({ 'KeyShift', 'KeyCtrl', 'KeyAlt' }) do
            local okk, v = pcall(function() return io[k] end)
            add(string.format('modifier io.%s: %s', k, okk and describe(v) or 'NOT AVAILABLE (modifier clicks will not work)'))
        end
    else
        add('imgui.GetIO(): NOT AVAILABLE')
        missing = missing + 1
    end

    add('next: imgui.GetTime')
    local okt, t = pcall(imgui.GetTime)
    add('imgui.GetTime(): ' .. (okt and describe(t) or 'NOT AVAILABLE'))
    add('next: imgui.GetColorU32')
    local okc, c = pcall(imgui.GetColorU32, { 1, 0, 0, 1 })
    add('imgui.GetColorU32({r,g,b,a}): ' .. (okc and describe(c) or 'FAILED (will use packed ints instead)'))
    add('next: imgui.CalcTextSize')
    local oks, a, b = pcall(imgui.CalcTextSize, 'Ag')
    add('imgui.CalcTextSize: ' .. (oks and (describe(a) .. ' / ' .. describe(b)) or 'FAILED'))

    -- Slanted rows use draw_list:AddQuadFilled / AddQuad. We can only see them on a live draw list.
    add('next: imgui.GetBackgroundDrawList')
    local okw, dl = pcall(imgui.GetBackgroundDrawList)
    if okw and dl then
        for _, m in ipairs({ 'AddQuadFilled', 'AddQuad', 'AddRectFilled', 'AddText' }) do
            local okm, v = pcall(function() return dl[m] end)
            add(string.format('draw list %s: %s', m, (okm and v ~= nil) and 'present' or 'MISSING (slanted rows fall back to square)'))
        end
    else
        add('imgui.GetBackgroundDrawList: not available; cannot probe quad drawing (rows fall back to square if AddQuadFilled is missing)')
    end

    add('next: cast bar (AshitaCore:GetMemoryManager():GetCastBar())')
    local okcb, cb = pcall(function() return AshitaCore:GetMemoryManager():GetCastBar() end)
    if okcb and cb then
        local okp, pc = pcall(function() return cb:GetPercent() end)
        add('cast bar GetPercent(): ' .. (okp and describe(pc) or 'FAILED (cast timing falls back to estimates)'))
    else
        add('cast bar: NOT AVAILABLE (cast timing falls back to estimates)')
    end

    add(string.format('bit library: %s', (bit and bit.bor) and 'present' or 'MISSING'))
    add(string.format('ashita.events.register: %s',
        (ashita and ashita.events and ashita.events.register) and 'present' or 'MISSING'))

    add(missing == 0 and 'Result: everything ClickHeal uses is present.'
        or string.format('Result: %d item(s) missing - send this list back so the backend can be adjusted.', missing))
    return out, missing
end

return M
