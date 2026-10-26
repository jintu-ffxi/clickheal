--[[
    ClickHeal - casting.lua
    Tracks "the player is busy" so clicks do not collide with a spell that is still being cast, and holds
    one click in a queue until the player can act again. Pure: time comes in as an argument.

    FFXI has no global cooldown, but you cannot start a spell or ability while another is being cast or
    right after it finishes. How long that takes is:

        cast time (the spell's own, shortened by Fast Cast)  +  a short delay after the action

    Haste does not shorten spell casting (it speeds melee); Fast Cast does. Spell *recast* timers already
    come from the game (and include any magic haste), so they are not estimated here.

    When the game's cast bar can be read (`observe`), it overrides the estimate: the busy time ends
    when the bar ends, and a cast whose bar never appears (out of range, interrupted at once) is released
    early. Until the bar has been seen working once, only the estimate is used.
]]--

local casting = {}

local STALE = 5.0        -- seconds a queued click stays valid
local BAR_GRACE = 0.6    -- seconds to wait for the cast bar to appear before assuming the cast failed

local st

function casting.reset()
    st = { started = 0, cast_end = 0, until_ = 0, total = 0, key = nil, name = nil, lockout = 1.0,
           bar_seen = false, bar_works = false, queued = nil }
end
casting.reset()

--- Starts the busy period for a spell or ability just sent.
-- cfg: { fast_cast = percent, cast_lockout = seconds }
function casting.start(def, now, cfg)
    cfg = cfg or {}
    local lockout = cfg.cast_lockout or 1.0
    local fc = math.max(0, math.min(80, cfg.fast_cast or 0)) / 100
    local cast_s = def.ja and 0 or (def.cast or 0) * (1 - fc)
    st.started = now
    st.cast_end = now + cast_s
    st.until_ = now + cast_s + lockout
    st.total = cast_s
    st.key, st.name = def.key, def.name
    st.lockout = lockout
    st.bar_seen = false
end

--- Feeds the game's cast bar (progress 0..1, or nil when it cannot be read).
function casting.observe(now, pct)
    if pct == nil or now >= st.until_ then return end
    if pct > 0 and pct < 1 then
        st.bar_seen, st.bar_works = true, true
        if pct > 0.05 then
            local total = (now - st.started) / pct          -- real length of this cast
            st.total = total
            st.cast_end = st.started + total
            st.until_ = st.cast_end + st.lockout
        end
    elseif st.bar_works then
        if st.bar_seen then
            -- The bar was running and is gone: the cast is over, only the short delay remains.
            st.cast_end = math.min(st.cast_end, now)
            st.until_ = math.min(st.until_, now + st.lockout)
        elseif (st.total or 0) > 0 and now > st.started + BAR_GRACE then
            -- A spell with a cast time whose bar never showed: it failed or was cancelled.
            st.until_ = math.min(st.until_, now + 0.3)
            st.cast_end = now
        end
    end
end

--- Seconds until the player can act again (0 when free).
function casting.left(now)
    return math.max(0, st.until_ - now)
end

--- What to show: nil when idle, else { left, total, frac, key, name }.
function casting.info(now)
    local left = casting.left(now)
    if left <= 0 then return nil end
    local cast_left = math.max(0, st.cast_end - now)
    local frac = (st.total or 0) > 0 and math.max(0, math.min(1, 1 - cast_left / st.total)) or 1
    return { left = left, cast_left = cast_left, total = st.total, frac = frac, key = st.key, name = st.name }
end

--- Adds busy/casting/queued to a player table (what spellstate and the UI read).
function casting.decorate(player, now)
    player.busy_left = casting.left(now)
    player.casting = casting.info(now)
    player.queued = st.queued and st.queued.ev.spell or nil
    return player
end

--- Holds one click until the player is free (a newer click replaces it).
function casting.queue(ev, now)
    st.queued = { ev = ev, at = now }
end

--- The queued click once the player can act, or nil. Stale clicks are dropped.
function casting.take(now)
    local q = st.queued
    if not q then return nil end
    if now - q.at > STALE then st.queued = nil; return nil end
    if casting.left(now) > 0 then return nil end
    st.queued = nil
    return q.ev
end

function casting.clear_queue() st.queued = nil end

return casting
