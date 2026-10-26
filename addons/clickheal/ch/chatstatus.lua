--[[
    ClickHeal - chatstatus.lua
    Tracks other party members' buffs and debuffs from the chat log, for servers that do not send party
    status data (partydump shows serverid=0 there). Pure: clickheal.lua feeds it each incoming line.

    Understood lines:
        "Zeid gains the effect of Shell."        "Zeid's Haste effect wears off."
        "Zeid is no longer afflicted with Flash." "Zeid is poisoned." / "Zeid is no longer poisoned."
    Presence only, no timers: the chat log does not say how long an effect lasts. An entry is dropped
    when its wear-off line arrives, when the member is defeated, or after twice its typical length.
]]--

local buffs   = require('ch.buffs')
local debuffs = require('ch.debuffs')

local chat = {}

chat.seen, chat.last_raw, chat.last_clean, chat.hits = 0, nil, nil, 0

local state = {}   -- name -> { buffs = { key = t }, debuffs = { key = t } }

local BUFF_BY_NAME, DEBUFF_BY_NAME = {}, {}
for key, info in pairs(buffs.info) do BUFF_BY_NAME[info.label:lower()] = key end
for key, info in pairs(debuffs.info) do DEBUFF_BY_NAME[info.label:lower()] = key end
for name, key in pairs({ paralysis = 'paralysis', paralyze = 'paralysis', blindness = 'blindness', blind = 'blindness',
    petrification = 'petrify', petrified = 'petrify', weakness = nil }) do DEBUFF_BY_NAME[name] = key end

-- "is <state>." lines for debuffs that have one.
local IS_STATE = {
    poisoned = 'poison', paralyzed = 'paralysis', blinded = 'blindness', silenced = 'silence',
    petrified = 'petrify', diseased = 'disease', cursed = 'curse', bound = 'bind', slowed = 'slow',
    asleep = 'sleep', terrorized = 'terror', ['weighed down'] = 'weight',
}

local function entry(name)
    local e = state[name]
    if not e then e = { buffs = {}, debuffs = {} }; state[name] = e end
    return e
end

local function norm(s)
    s = s:lower():gsub('%s+[ivx]+$', ''):gsub('%s+%d+$', '')
    return s
end

local function clean(line)
    line = tostring(line or '')
    line = line:gsub('\30.', ''):gsub('\31.', ''):gsub('[%z\1-\29]', '')
    return (line:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Reads one chat line. Returns true when it changed what is tracked.
function chat.feed(line, now)
    chat.seen = chat.seen + 1
    if type(line) == 'string' and line:find('effect', 1, true) then chat.last_raw = line end
    line = clean(line)
    if line == '' then return false end
    if line:find('effect', 1, true) then chat.last_clean = line end
    now = now or os.clock()
    local who, what = line:match("^(.-) gains the effect of (.-)%.$")
    if who then
        local k = norm(what)
        if BUFF_BY_NAME[k] then entry(who).buffs[BUFF_BY_NAME[k]] = now; return true end
        if DEBUFF_BY_NAME[k] then entry(who).debuffs[DEBUFF_BY_NAME[k]] = now; return true end
        return false
    end
    who, what = line:match("^(.-)'s (.-) effect wears off%.$")
    if who then
        local k = norm(what)
        local e = state[who]
        if not e then return false end
        local b, d = BUFF_BY_NAME[k], DEBUFF_BY_NAME[k]
        if b and e.buffs[b] then e.buffs[b] = nil; return true end
        if d and e.debuffs[d] then e.debuffs[d] = nil; return true end
        return false
    end
    who, what = line:match("^(.-) is no longer afflicted with (.-)%.$")
    if not who then who, what = line:match("^(.-) is no longer (.-)%.$") end
    if who then
        local k = norm(what)
        local e = state[who]
        if not e then return false end
        local d = DEBUFF_BY_NAME[k] or IS_STATE[k]
        if d and e.debuffs[d] then e.debuffs[d] = nil; return true end
        return false
    end
    who, what = line:match("^(.-) is (.-)%.$")
    if who and IS_STATE[what] then entry(who).debuffs[IS_STATE[what]] = now; return true end
    who = line:match("^(.-) falls to the ground%.$") or line:match("^(.-) is defeated by .-%.$")
    if who and state[who] then state[who] = nil; return true end
    return false
end

--- Debuff keys and buff list ({ key = ... }) currently known for a member name.
function chat.get(name, now)
    now = now or os.clock()
    local e = state[name]
    local d, b = {}, {}
    if not e then return d, b end
    for key, t in pairs(e.debuffs) do
        if now - t > 600 then e.debuffs[key] = nil else d[#d + 1] = key end
    end
    table.sort(d)
    for _, key in ipairs(buffs.order) do
        local t = e.buffs[key]
        if t then
            if now - t > 2 * (buffs.info[key].total or 300) then e.buffs[key] = nil
            else b[#b + 1] = { key = key } end
        end
    end
    return d, b
end

function chat.reset() state = {}; chat.seen, chat.last_raw, chat.last_clean = 0, nil, nil end

--- How many members have anything tracked (for /ch status).
function chat.count()
    local n = 0
    for _, e in pairs(state) do if next(e.buffs) or next(e.debuffs) then n = n + 1 end end
    return n
end

return chat
