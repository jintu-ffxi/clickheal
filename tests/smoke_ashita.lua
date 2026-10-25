-- Smoke test for the Ashita-facing glue (clickheal.lua, gfx_imgui.lua, configui.lua, apicheck.lua).
--
--   lua tests/smoke_ashita.lua       (run from the repository root)
--
-- It runs the real addon entry file against STUB versions of ashita / imgui / settings / chat.
-- That proves the control flow (load -> frames -> commands -> clicks -> save), that every
-- Begin/End and Push/Pop pair stays balanced even when a call throws, and that errors are
-- reported once instead of every frame.
--
-- It does NOT prove the stubs match the real Ashita API. Use `/ch apicheck` in game for that.
package.path = 'addons/clickheal/?.lua;' .. package.path

local passed, failed, failures = 0, 0, {}
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; failures[#failures + 1] = name .. '\n      ' .. tostring(err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or 'differ') .. ': got ' .. tostring(a) .. ', expected ' .. tostring(b), 2) end end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

-- ---------------------------------------------------------------------------------------------
-- stubs
-- ---------------------------------------------------------------------------------------------
local calls = setmetatable({}, { __index = function() return 0 end })
local function bump(name, n) calls[name] = calls[name] + (n or 1) end

local sim = {
    clock = 100, hover = false, click = nil, mouse = { 0, 0 },
    interact = false,       -- widgets report "changed"
    throw_in_begin = false, -- imgui.Begin raises
    throw_in_text = false,  -- imgui.Text raises (used inside tooltips and the setup panel)
}

local real_print = print          -- the addon's print() is captured below; reporting uses this one
local printed = {}
_G.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, ' ')
end

-- Constants and helpers Ashita provides as globals. Without these the addon would skip the
-- style-stack code entirely and the balance checks below would pass vacuously.
_G.ImGuiCond_Always, _G.ImGuiCond_Once, _G.ImGuiCond_FirstUseEver = 1, 2, 4
_G.ImGuiStyleVar_WindowPadding, _G.ImGuiStyleVar_WindowBorderSize = 2, 28
do
    local bit_value = 1
    for _, name in ipairs({ 'NoTitleBar', 'NoResize', 'NoMove', 'NoScrollbar', 'NoScrollWithMouse', 'NoCollapse',
                            'NoBackground', 'NoSavedSettings', 'NoFocusOnAppearing', 'NoNav' }) do
        _G['ImGuiWindowFlags_' .. name] = bit_value
        bit_value = bit_value * 2
    end
end
_G.bit = { bor = function(...) local sum = 0 for _, v in ipairs({ ... }) do sum = sum + v end return sum end }

_G.addon = {}
local handlers = {}
_G.ashita = { events = { register = function(name, id, fn) handlers[name] = fn end } }
string.args = function(s) local t = {} for w in s:gmatch('%S+') do t[#t + 1] = w end return t end

local function deep_copy(v)
    if type(v) ~= 'table' then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deep_copy(x) end
    return c
end

local settings_state = { saves = 0, callbacks = {} }
package.preload['common'] = function() return true end
package.preload['chat'] = function()
    return {
        header = function(name)
            local o = { text = '[' .. name .. '] ' }
            return setmetatable(o, { __index = { append = function(self, s) self.text = self.text .. tostring(s); return self end },
                                     __tostring = function(self) return self.text end })
        end,
        message = function(t) return t end,
    }
end
package.preload['settings'] = function()
    return {
        load = function(defaults) return deep_copy(defaults) end,
        register = function(key, id, fn) settings_state.callbacks[id] = fn end,
        save = function() settings_state.saves = settings_state.saves + 1 end,
    }
end

local draw_list = {
    AddRectFilled = function() bump('rect') end,
    AddText = function() bump('text') end,
}
local widget_value_flips = 0
package.preload['imgui'] = function()
    local im = {}
    local specific = {
        Begin = function(name)
            if sim.throw_in_begin then error('simulated: Begin failed') end
            bump('Begin'); sim.begun = sim.begun or {}; sim.begun[name] = (sim.begun[name] or 0) + 1; return true
        end,
        End = function() bump('End') end,
        PushStyleVar = function() bump('PushStyleVar') end,
        PopStyleVar = function(n) bump('PopStyleVar', n or 1) end,
        GetWindowPos = function() return 100, 100 end,
        GetWindowDrawList = function() return draw_list end,
        IsWindowHovered = function() return sim.hover end,
        GetMousePos = function() return sim.mouse[1], sim.mouse[2] end,
        IsMouseClicked = function(b) return sim.click == b end,
        GetIO = function() return { DisplaySize = { x = 1920, y = 1080 }, KeyShift = false, KeyCtrl = false, KeyAlt = false } end,
        GetTime = function() return sim.clock end,
        CalcTextSize = function(s) return #s * 7, 13 end,
        GetColorU32 = function() return 123456 end,
        BeginTooltip = function() bump('BeginTooltip') end,
        EndTooltip = function() bump('EndTooltip') end,
        Text = function() if sim.throw_in_text then error('simulated: Text failed') end bump('Text') end,
        BeginTabBar = function() bump('BeginTabBar'); return true end,
        EndTabBar = function() bump('EndTabBar') end,
        BeginTabItem = function() bump('BeginTabItem'); return true end,
        EndTabItem = function() bump('EndTabItem') end,
        BeginCombo = function() bump('BeginCombo'); return true end,
        EndCombo = function() bump('EndCombo') end,
        Selectable = function() return sim.interact end,
        Checkbox = function(_, t) if sim.interact then t[1] = not t[1]; widget_value_flips = widget_value_flips + 1; return true end return false end,
        SliderFloat = function(_, t, lo, hi) if sim.interact then t[1] = hi; return true end return false end,
        SliderInt = function(_, t, lo, hi) if sim.interact then t[1] = hi; return true end return false end,
        Button = function() return sim.interact end,
    }
    return setmetatable(im, { __index = function(_, name)
        return specific[name] or function() return false end
    end })
end

-- ---------------------------------------------------------------------------------------------
-- load the real addon
-- ---------------------------------------------------------------------------------------------
dofile('addons/clickheal/clickheal.lua')

local function frame_tick()
    sim.clock = sim.clock + 0.1
    handlers.d3d_present()
end

local function run_command(line)
    local e = { command = line, blocked = false }
    handlers.command(e)
    return e
end

local function errors_logged()
    local n = 0
    for _, p in ipairs(printed) do if p:find('Error in', 1, true) then n = n + 1 end end
    return n
end

local function balanced()
    eq(calls.Begin, calls.End, 'Begin/End')
    eq(calls.PushStyleVar, calls.PopStyleVar, 'PushStyleVar/PopStyleVar')
    eq(calls.BeginTabBar, calls.EndTabBar, 'BeginTabBar/EndTabBar')
    eq(calls.BeginTabItem, calls.EndTabItem, 'BeginTabItem/EndTabItem')
    eq(calls.BeginTooltip, calls.EndTooltip, 'BeginTooltip/EndTooltip')
    eq(calls.BeginCombo, calls.EndCombo, 'BeginCombo/EndCombo')
end

-- ---------------------------------------------------------------------------------------------
-- tests
-- ---------------------------------------------------------------------------------------------
test('registers load, unload, command and d3d_present handlers', function()
    for _, name in ipairs({ 'load', 'unload', 'command', 'd3d_present' }) do
        truthy(handlers[name], 'missing handler: ' .. name)
    end
    eq(addon.name, 'clickheal')
end)

test('load announces Phase 1 and that nothing is sent to the game', function()
    handlers.load()
    local joined = table.concat(printed, '\n')
    truthy(joined:find('Phase 1', 1, true))
    truthy(joined:find('nothing is sent to the game', 1, true))
end)

test('default frames draw both windows, balanced, with no errors', function()
    run_command('/ch alerts on')    -- the alert window is optional (off by default)
    for _ = 1, 30 do frame_tick() end
    truthy(calls.rect > 500 and calls.text > 100, 'expected real drawing, got ' .. calls.rect .. ' rects / ' .. calls.text .. ' texts')
    truthy(calls.Begin >= 60, 'roster + alert windows each frame (got ' .. calls.Begin .. ')')
    truthy(calls.PushStyleVar >= 60, 'style vars must actually be pushed, or the balance check proves nothing')
    balanced()
    eq(errors_logged(), 0)
end)

test('commands: /ch is consumed, other commands are left alone', function()
    local e = run_command('/ch scale 1.5');   truthy(e.blocked)
    local e2 = run_command('/clickheal help'); truthy(e2.blocked)
    local e3 = run_command('/wave');           eq(e3.blocked, false)
    local e4 = run_command('');                eq(e4.blocked, false)
    run_command('/ch scale auto')
    truthy(settings_state.saves > 0, 'changing a setting saves')
end)

test('grid and strip with the spell bar draw balanced and error-free in every mode', function()
    run_command('/ch reset confirm'); run_command('/ch lock')
    for _, style in ipairs({ 'grid', 'strip' }) do
        for _, mode in ipairs({ 'alliance2', 'party' }) do
            run_command('/ch layout ' .. style); run_command('/ch mode ' .. mode)
            for _, tab in ipairs({ 'heal', 'cleanse', 'buff', 'raise' }) do
                run_command('/ch tab ' .. tab)
                for _ = 1, 3 do frame_tick() end
            end
        end
    end
    balanced()
    eq(errors_logged(), 0)
end)

test('hovering a Strip row opens the flyout window, clicking a tile logs a cast, and it all stays balanced', function()
    run_command('/ch reset confirm'); run_command('/ch lock'); run_command('/ch layout strip')
    local layout = require('ch.layout')
    local g = layout.compute({ style = 'strip', orientation = 'columns', groups = { 0 }, auto_scale = true, scale = 1.0 }, 1080)
    local c = g.cards[1]
    sim.begun = {}
    sim.mouse, sim.hover, sim.click = { 100 + c.x + 60, 100 + c.y + 8 }, true, nil
    for _ = 1, 4 do frame_tick() end
    truthy((sim.begun['ClickHeal Flyout'] or 0) >= 1, 'flyout window was opened while hovering a row')
    sim.hover = false; sim.mouse = { 1900, 1050 }
    sim.begun = {}
    for _ = 1, 600 do frame_tick() end    -- long enough for the close grace period to pass
    sim.begun = {}
    frame_tick()
    eq(sim.begun['ClickHeal Flyout'] or 0, 0, 'flyout closes after the mouse leaves')
    balanced()
    eq(errors_logged(), 0)
end)

test('/ch layout and mode changes take effect on the next frame without errors', function()
    for _, style in ipairs({ 'compact', 'minimal', 'full' }) do
        for _, mode in ipairs({ 'alliance2', 'alliance1', 'party' }) do
            run_command('/ch layout ' .. style); run_command('/ch mode ' .. mode)
            for _ = 1, 3 do frame_tick() end
        end
    end
    balanced(); eq(errors_logged(), 0)
end)

test('setup panel: opens, every widget path runs, stays balanced', function()
    run_command('/ch')                       -- toggles the panel open
    for _ = 1, 5 do frame_tick() end
    truthy(calls.BeginTabItem >= 20, 'tabs should have been drawn')
    sim.interact = true                      -- every widget reports "changed" and flips its value
    for _ = 1, 30 do frame_tick() end
    sim.interact = false
    truthy(widget_value_flips > 0, 'checkboxes should have flipped')
    balanced(); eq(errors_logged(), 0)
end)

test('debounced save fires after changes settle', function()
    local before = settings_state.saves
    sim.interact = true; for _ = 1, 3 do frame_tick() end; sim.interact = false
    for _ = 1, 25 do frame_tick() end        -- 2.5 simulated seconds with no changes
    truthy(settings_state.saves > before, 'expected a debounced save')
end)

test('/ch apicheck runs and reports', function()
    local n = #printed
    run_command('/ch apicheck')
    eq(table.concat(printed, '\n', n + 1):find('Result:', 1, true), nil, 'nothing probed outside a draw frame')
    frame_tick()
    local joined = table.concat(printed, '\n', n + 1)
    truthy(joined:find('API check', 1, true) and joined:find('Result:', 1, true))
end)

test('clicking a spell button logs the cast and sends nothing to the game', function()
    run_command('/ch reset confirm')
    run_command('/ch layout full')   -- default is Strip; this test clicks a Full-layout tile
    run_command('/ch lock')
    for _ = 1, 3 do frame_tick() end
    -- Brannoch (slot 1), first button (Cure IV). The window is stubbed to sit at (100,100).
    local layout = require('ch.layout')
    local g = layout.compute({ style = 'full', orientation = 'columns', groups = { 0 }, auto_scale = true, scale = 1.0 }, 1080)
    local c = g.cards[1]
    local bx = 100 + c.x + g.pad + g.btn / 2
    local by = 100 + c.y + g.btn_y + g.btn / 2
    sim.mouse, sim.hover, sim.click = { bx, by }, true, 0
    local n = #printed
    frame_tick()
    sim.click = nil; sim.hover = false
    local joined = table.concat(printed, '\n', n + 1)
    truthy(joined:find('Cure IV -> Brannoch (<p1>)', 1, true), 'cast log missing; got: ' .. joined)
    truthy(joined:find('Nothing was sent to the game', 1, true))
end)

test('unlocked frames do not cast on click', function()
    run_command('/ch layout full')
    run_command('/ch unlock')
    local layout = require('ch.layout')
    local g = layout.compute({ style = 'full', orientation = 'columns', groups = { 0 }, auto_scale = true, scale = 1.0 }, 1080)
    local c = g.cards[1]
    sim.mouse = { 100 + c.x + g.pad + g.btn / 2, 100 + c.y + g.btn_y + g.btn / 2 }
    sim.hover, sim.click = true, 0
    local n = #printed
    frame_tick()
    sim.click = nil; sim.hover = false
    truthy(not table.concat(printed, '\n', n + 1):find('Cure', 1, true), 'unlocked click must not cast')
    run_command('/ch lock')
end)

test('a throwing ImGui call is reported once and leaves the style stack balanced', function()
    local errs_before = errors_logged()
    sim.throw_in_begin = true
    for _ = 1, 10 do frame_tick() end
    sim.throw_in_begin = false
    eq(errors_logged() - errs_before, 1, 'the same error must be reported once, not every frame')
    balanced()
    for _ = 1, 5 do frame_tick() end         -- and the addon keeps working afterwards
    balanced()
end)

test('a throwing tooltip call still ends the tooltip', function()
    run_command('/ch reset confirm'); run_command('/ch lock')
    local layout = require('ch.layout')
    local g = layout.compute({ style = 'full', orientation = 'columns', groups = { 0 }, auto_scale = true, scale = 1.0 }, 1080)
    local c = g.cards[1]
    sim.mouse = { 100 + c.x + g.pad + g.btn / 2, 100 + c.y + g.btn_y + g.btn / 2 }
    sim.hover = true
    sim.throw_in_text = true
    frame_tick()
    sim.throw_in_text = false; sim.hover = false
    truthy(calls.BeginTooltip > 0, 'tooltip should have been attempted')
    balanced()
end)

test('unload saves settings', function()
    local before = settings_state.saves
    handlers.unload()
    eq(settings_state.saves, before + 1)
end)

real_print(string.format('\n%d passed, %d failed', passed, failed))
for _, f in ipairs(failures) do real_print('  FAIL: ' .. f) end
os.exit(failed == 0 and 0 or 1)
