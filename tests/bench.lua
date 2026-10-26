-- Performance and leak benchmark for the in-game draw path.
--
--   luajit tests/bench.lua [label]            timing + allocation per frame, saved to bench/<label>.txt
--   luajit tests/bench.lua --leak [label]     long soak: heap after a full GC at checkpoints, must stay flat
--   luajit tests/bench.lua --compare a b      side by side of two saved runs
--   luajit tests/bench.lua --alloc [scenario] where the garbage comes from: top source lines by KB allocated per frame
--
-- Run from the repository root. It runs the real addon (clickheal.lua) against STUB ashita / imgui and a fake
-- game memory (18 party members whose HP, distance, status and recasts keep changing), so it measures the Lua
-- side only: our code, the garbage it makes and the memory it keeps. Real ImGui and game-memory cost is not in
-- the numbers, but fewer calls and fewer allocations here is fewer of them there. Use LuaJIT (what Ashita runs).
package.path = 'addons/clickheal/?.lua;' .. package.path

local real_print = print
local mode, label = 'bench', nil
if arg[1] == '--compare' then
    local function load(name)
        local t = {}
        local f = assert(io.open('bench/' .. name .. '.txt', 'r'))
        for line in f:lines() do
            local k, ms, kb, rd = line:match('^(%S+)\t(%S+)\t(%S+)\t(%S+)$')
            if k then t[#t + 1] = { k = k, ms = tonumber(ms), kb = tonumber(kb), rd = tonumber(rd) } end
        end
        f:close(); return t
    end
    local a, b = load(arg[2]), load(arg[3])
    real_print(string.format('%-34s %9s %9s %7s | %9s %9s %7s | %8s', 'scenario', 'ms/f A', 'ms/f B', 'delta', 'KB/f A', 'KB/f B', 'delta', 'reads/f'))
    for i, x in ipairs(a) do
        local y = b[i]
        if y then
            real_print(string.format('%-34s %9.4f %9.4f %6.0f%% | %9.2f %9.2f %6.0f%% | %4.0f>%-4.0f', x.k, x.ms, y.ms,
                (y.ms / x.ms - 1) * 100, x.kb, y.kb, (y.kb / math.max(x.kb, 1e-9) - 1) * 100, x.rd, y.rd))
        end
    end
    os.exit(0)
end
if arg[1] == '--leak' then mode, label = 'leak', arg[2]
elseif arg[1] == '--alloc' then mode, label = 'alloc', arg[2]
else label = arg[1] end

-- ---------------------------------------------------------------------------------------------
-- stubs (same shape as tests/smoke_ashita.lua)
-- ---------------------------------------------------------------------------------------------
local sim = { clock = 100, hover = false, mouse = { 0, 0 } }
_G.print = function() end

_G.ImGuiCond_Always, _G.ImGuiCond_Once = 1, 2
_G.ImGuiStyleVar_WindowPadding, _G.ImGuiStyleVar_WindowBorderSize = 2, 28
do
    local b = 1
    for _, n in ipairs({ 'NoTitleBar', 'NoResize', 'NoMove', 'NoScrollbar', 'NoScrollWithMouse', 'NoCollapse',
                         'NoBackground', 'NoSavedSettings', 'NoFocusOnAppearing', 'NoNav' }) do
        _G['ImGuiWindowFlags_' .. n] = b; b = b * 2
    end
end
_G.addon = {}
local handlers = {}
_G.ashita = { events = { register = function(name, _, fn) handlers[name] = fn end } }
string.args = function(s) local t = {} for w in s:gmatch('%S+') do t[#t + 1] = w end return t end

local cfg_holder = {}
local function deep_copy(v)
    if type(v) ~= 'table' then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deep_copy(x) end
    return c
end
package.preload['common'] = function() return true end
package.preload['chat'] = function()
    return { header = function() return setmetatable({}, { __index = { append = function(s) return s end } }) end, message = function(t) return t end }
end
package.preload['settings'] = function()
    return {
        load = function(d) cfg_holder.cfg = deep_copy(d); return cfg_holder.cfg end,
        register = function() end, save = function() end,
    }
end

local noop = function() end
local draw_list = {
    AddRectFilled = noop, AddText = noop, AddQuadFilled = noop, AddQuad = noop, AddImage = noop, AddRect = noop,
}
local DISPLAY = { x = 1920, y = 1080 }
local IO = { DisplaySize = DISPLAY, KeyShift = false, KeyCtrl = false, KeyAlt = false }
package.preload['imgui'] = function()
    local specific = {
        Begin = function() return true end,
        GetWindowPos = function() return 100, 100 end,
        GetWindowDrawList = function() return draw_list end,
        IsWindowHovered = function() return sim.hover end,
        GetMousePos = function() return sim.mouse[1], sim.mouse[2] end,
        GetIO = function() return IO end,
        GetTime = function() return sim.clock end,
        CalcTextSize = function(s) return #s * 7, 13 end,
        GetColorU32 = function() return 123456 end,
        BeginChild = function() return true end,
        BeginTabBar = function() return true end,
        BeginTabItem = function() return true end,
        PushStyleColor = function() return true end,
        GetContentRegionAvail = function() return 560, 400 end,
        BeginCombo = function() return true end,
        CollapsingHeader = function() return true end,
    }
    return setmetatable({}, { __index = function(_, name) return specific[name] or noop end })
end

-- ---------------------------------------------------------------------------------------------
-- fake game memory: 18 party members that keep changing, plus recasts, buffs and a cast bar
-- ---------------------------------------------------------------------------------------------
local reads = 0
local fake = { frame = 0 }
local NSLOT = 18
local function mk(count_as_read)
    return function(f) return function(...) reads = reads + 1; return f(...) end end
end
local rd = mk()

local function hp_of(slot) return math.floor(50 + 50 * math.sin(fake.frame / 37 + slot * 1.7)) end
local party = {
    GetMemberIsActive = rd(function(_, s) return (s < fake.active) and 1 or 0 end),
    GetMemberName     = rd(function(_, s) return 'Member' .. s end),
    GetMemberHP       = rd(function(_, s) return hp_of(s) * 20 end),
    GetMemberHPPercent = rd(function(_, s) return hp_of(s) end),
    GetMemberMP       = rd(function(_, s) return 300 - (fake.frame + s * 13) % 300 end),
    GetMemberMPPercent = rd(function(_, s) return math.floor(100 - ((fake.frame + s * 13) % 300) / 3) end),
    GetMemberZone     = rd(function(_, s) return (s == 7) and 99 or 100 end),
    GetMemberMainJob  = rd(function(_, s) return (s == 0) and 3 or (s % 20) + 1 end),
    GetMemberSubJob   = rd(function(_, s) return 5 end),
    GetMemberMainJobLevel = rd(function() return 99 end),
    GetMemberTargetIndex = rd(function(_, s) return 100 + s end),
    GetMemberServerId = rd(function(_, s) return 1000 + s end),
    GetStatusIconsServerId = rd(function() return 0 end),
}
local player = {
    GetBuffs = rd(function() local t = {}; for i = 0, 31 do t[i] = (i < 5) and (30 + i * 3) or 255 end; return t end),
    GetHPMax = rd(function() return 2000 end), GetMPMax = rd(function() return 600 end),
    GetMainJob = rd(function() return 3 end), GetSubJob = rd(function() return 5 end),
    GetMainJobLevel = rd(function() return 99 end), GetSubJobLevel = rd(function() return 49 end),
    HasSpell = rd(function() return true end),
}
local entity = { GetDistance = rd(function(_, i) local d = 3 + (i * 3 + fake.frame / 9) % 30; return d * d end) }
local recast = {
    GetAbilityTimerId = rd(function(_, x) return x end),
    GetAbilityTimer = rd(function(_, x) return (x % 5 == 0) and (600 - fake.frame % 600) or 0 end),
    GetSpellTimer = rd(function(_, id) return (id % 7 == 0) and (300 - fake.frame % 300) or 0 end),
}
local castbar = { GetPercent = rd(function() return (fake.frame % 90) / 90 end) }
local memory = {
    GetParty = function() return party end, GetPlayer = function() return player end,
    GetEntity = function() return entity end, GetRecast = function() return recast end,
    GetCastBar = function() return castbar end,
}
_G.AshitaCore = {
    GetMemoryManager = function() return memory end,
    GetChatManager = function() return { QueueCommand = noop } end,
    GetResourceManager = function() return { GetStatusIconById = function() return nil end } end,
}

local function status_packet()
    local parts = { string.char(0, 0, 0, 0) }
    for n = 0, 4 do
        local uid = 1000 + ((math.floor(fake.frame / 10) + n) % NSLOT)
        local e = { string.char(uid % 256, math.floor(uid / 256) % 256, 0, 0), string.rep('\0', 12) }
        for i = 0, 31 do e[#e + 1] = string.char((i < 6 and (math.floor(fake.frame / 7) + i) % 3 == 0) and (3 + i) or 255) end
        parts[#parts + 1] = table.concat(e)
    end
    return table.concat(parts)
end

-- ---------------------------------------------------------------------------------------------
-- run the real addon
-- ---------------------------------------------------------------------------------------------
dofile('addons/clickheal/clickheal.lua')
handlers.load()
local cfg = cfg_holder.cfg

local function setup(s)
    local d = require('ch.chconfig').defaults
    for k, v in pairs(d) do
        if type(v) ~= 'table' then cfg[k] = v end
    end
    cfg.demo, cfg.locked, cfg.visible = s.demo or false, true, true
    cfg.mode, cfg.skin = s.mode or 'party', s.skin or 'hairline'
    cfg.alerts.enabled = s.alerts or false
    cfg.flyout = true
    cfg.scale = 1.0
    fake.active = s.members or 6
    sim.hover = s.hover or false
    sim.mouse = s.hover and { 100 + 60, 100 + 140 } or { 1900, 1050 }
end

local selftest_leak = {}   -- BENCH_SELFTEST_LEAK=1 retains a little every frame, to prove the soak can fail
local function one_frame(s)
    if os.getenv('BENCH_SELFTEST_LEAK') then selftest_leak[#selftest_leak + 1] = { fake.frame } end
    fake.frame = fake.frame + 1
    sim.clock = sim.clock + 1 / 60
    if s.packets and fake.frame % 10 == 0 then handlers.packet_in({ id = 0x076, data = status_packet() }) end
    if s.chat and fake.frame % 25 == 0 then
        handlers.text_in({ message = 'Member' .. (fake.frame % 6) .. ' gains the effect of Haste.' })
        handlers.text_in({ message = 'Member' .. (fake.frame % 6) .. "'s Haste effect wears off." })
        handlers.text_in({ message = 'You hit the Goblin for 55 points of damage.' })
    end
    handlers.d3d_present()
end

local SCENARIOS = {
    { k = 'party6_hairline_game',          members = 6,  mode = 'party',     packets = true },
    { k = 'alliance18_hairline_game',      members = 18, mode = 'alliance2', packets = true },
    { k = 'alliance18_solid_game',         members = 18, mode = 'alliance2', skin = 'solid', packets = true },
    { k = 'alliance18_hairline_flyout',    members = 18, mode = 'alliance2', packets = true, hover = true },
    { k = 'alliance18_alerts_chat',        members = 18, mode = 'alliance2', packets = true, chat = true, alerts = true },
    { k = 'alliance18_hairline_demo',      members = 18, mode = 'alliance2', demo = true },
}

local function median(t) table.sort(t); return t[math.ceil(#t / 2)] end

if mode == 'alloc' then
    local pick = SCENARIOS[2]
    for _, s in ipairs(SCENARIOS) do if s.k == label then pick = s end end
    setup(pick)
    for _ = 1, 300 do one_frame(pick) end
    local FR = 100
    local acc, order, cur = {}, {}, '?'
    local getinfo, count = debug.getinfo, collectgarbage
    jit.off(); collectgarbage('collect'); collectgarbage('stop')
    local last = count('count')
    debug.sethook(function()
        local c = count('count')
        if c > last then acc[cur] = (acc[cur] or 0) + (c - last) end
        local i = getinfo(2, 'Sl')
        cur = (i.short_src:gsub('^.*[/\\]', '')) .. ':' .. i.currentline
        last = count('count')       -- the bookkeeping above is not ours
    end, 'l')
    for _ = 1, FR do one_frame(pick) end
    debug.sethook()
    local list = {}
    for k, v in pairs(acc) do list[#list + 1] = { k, v / FR } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    real_print(string.format('%s: %.1f KB/frame attributed to source lines (top 25)', pick.k, total))
    for i = 1, math.min(25, #list) do real_print(string.format('  %-28s %7.2f KB', list[i][1], list[i][2])) end
    os.exit(0)
end

if mode == 'bench' then
    local FRAMES, RUNS = 1000, 7
    local out = {}
    real_print(string.format('%-34s %10s %10s %9s', 'scenario', 'ms/frame', 'KB/frame', 'reads/f'))
    for _, s in ipairs(SCENARIOS) do
        setup(s)
        for _ = 1, 300 do one_frame(s) end                       -- warm up the JIT and every cache
        local times = {}
        for _ = 1, RUNS do
            collectgarbage('collect')
            local t0 = os.clock()
            for _ = 1, FRAMES do one_frame(s) end
            times[#times + 1] = (os.clock() - t0) * 1000 / FRAMES
        end
        collectgarbage('collect'); collectgarbage('stop')
        local m0, r0 = collectgarbage('count'), reads
        for _ = 1, 500 do one_frame(s) end
        local kb = (collectgarbage('count') - m0) / 500
        local rf = (reads - r0) / 500
        collectgarbage('restart')
        local ms = median(times)
        out[#out + 1] = string.format('%s\t%.5f\t%.3f\t%.1f', s.k, ms, kb, rf)
        real_print(string.format('%-34s %10.4f %10.2f %9.0f', s.k, ms, kb, rf))
    end
    if label then
        os.execute('mkdir bench 2>nul')
        local f = assert(io.open('bench/' .. label .. '.txt', 'w'))
        f:write(table.concat(out, '\n'), '\n'); f:close()
        real_print('saved bench/' .. label .. '.txt')
    end
else
    -- Soak: a worst-case churn of everything that could be cached (many colours, scales, text, packets, chat),
    -- with a full GC at every checkpoint. A leak shows as heap that keeps climbing; a bounded cache as a plateau.
    local s = { members = 18, mode = 'alliance2', packets = true, chat = true, alerts = true, hover = true }
    setup(s)
    local CHECK, N, LIMIT_KB = 10000, 8, 64
    local heaps = {}
    local last, first
    real_print(string.format('%-12s %12s %12s', 'frames', 'heap KB', 'growth KB'))
    for c = 1, N do
        for i = 1, CHECK do
            if i % 200 == 0 then
                cfg.scale = 0.6 + (math.floor(fake.frame / 200) % 40) * 0.05            -- dragging the scale
                cfg.opacity = 0.3 + (math.floor(fake.frame / 7) % 70) / 100              -- many alpha variants
                cfg.opacity_panel = 0.3 + (math.floor(fake.frame / 11) % 70) / 100
                cfg.hp_crit = 20 + math.floor(fake.frame / 13) % 40
                cfg.skin = (math.floor(fake.frame / 200) % 2 == 0) and 'hairline' or 'solid'
                cfg.colors = ({ 'modern', 'job', 'mono', 'colorblind' })[math.floor(fake.frame / 400) % 4 + 1]
                sim.mouse = { 100 + 60, 100 + 40 + (math.floor(fake.frame / 200) % 6) * 50 }
            end
            one_frame(s)
        end
        collectgarbage('collect'); collectgarbage('collect')
        local kb = collectgarbage('count')
        first = first or kb
        heaps[c] = kb
        real_print(string.format('%-12d %12.0f %12s', c * CHECK, kb, last and string.format('%+.0f', kb - last) or '-'))
        last = kb
    end
    -- Warm-up growth (caches filling) is allowed in the first half. The second half must stay flat: a cache that
    -- is not bounded, or something retained per frame, keeps climbing there.
    local second = last - heaps[N / 2]
    real_print(string.format('second half growth %+.0f KB over %d frames (limit %d KB)', second, N * CHECK / 2, LIMIT_KB))
    if second > LIMIT_KB then real_print('LEAK SUSPECTED'); os.exit(1) end
    real_print('no leak: heap is flat')
    os.exit(0)
end
