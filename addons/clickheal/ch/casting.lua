--[[
    ClickHeal - casting.lua
    Tracks "the player is busy" so clicks do not collide with a spell that is still being cast, and holds
    one click in a queue until the player can act again. Pure: time comes in as an argument.

    FFXI has no global cooldown, but you cannot start a spell or ability while another is being cast or
    right after it finishes. How long that takes is:

        cast time (the spell's own, shortened by Fast Cast)  +  a short delay after the action

    Best source, when the server's action packets are readable (ch/castpacket.lua): the packet that says your cast
    began starts the bar, the one that says it was interrupted or landed ends it, and the fill is the game's own
    cast-bar percentage. No guessing about when it started or ended, so the bar neither runs ahead of the game's
    nor resets under high latency. Until a start packet has been seen, the click-time estimate below is used.

    Haste does not shorten spell casting (it speeds melee); Fast Cast does. Spell *recast* timers already
    come from the game (and include any magic haste), so they are not estimated here.

    When the game's cast bar can be read (`observe`), it overrides the estimate: the busy time ends
    when the bar ends, and a cast whose bar never appears (out of range, interrupted at once) is released
    early. Until the bar has been seen working once, only the estimate is used.
]]--

local casting = {}

local STALE = 5.0        -- seconds a queued click stays valid
local BAR_GRACE = 0.6    -- seconds to wait for the cast bar to appear before assuming the cast failed (no packets)
local PENDING_MAX = 1.5  -- with packets: seconds to wait for the server to start a cast before assuming it never will

local st

casting.stats = { begin = 0, broke = 0, landed = 0 }   -- server cast packets seen (for /ch status)

function casting.reset()
    st = { started = 0, cast_end = 0, until_ = 0, total = 0, key = nil, name = nil, lockout = 1.0,
           bar_seen = false, bar_works = false, queued = nil,
           packets = false,     -- a cast-begin packet has been seen, so the packets can be trusted for start and end
           pending = false,     -- clicked, waiting for the server to confirm the cast began
           broke = false, frozen = nil, cfg = nil }
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
    st.bar_t0, st.pct, st.pct_at = nil, nil, nil
    st.pending, st.broke, st.frozen, st.cfg = (cast_s > 0), false, nil, cfg
end

-- ---------------------------------------------------------------------------------------------
-- the server's word (ch/castpacket.lua): when your cast began, was interrupted or landed
-- ---------------------------------------------------------------------------------------------

local function active(now) return now < st.until_ end

--- Your cast began. `def` is the spell when its id is known. A cast not started from a click (a macro, the game's own
-- menu) gets a bar too, as long as the spell is one we know.
function casting.server_begin(now, def)
    if not active(now) or (def and st.key ~= def.key) then
        if not def then return end
        casting.start(def, now, st.cfg)
    end
    st.packets = true
    casting.stats.begin = casting.stats.begin + 1
    st.pending, st.broke, st.frozen = false, false, nil
    st.started, st.bar_t0 = now, now                       -- the bar is at 0% exactly now
    st.pct, st.pct_at = nil, nil
    st.cast_end = now + (st.total or 0)
    st.until_ = st.cast_end + st.lockout
end

--- Your cast was interrupted: the bar stops where it was and the busy time ends shortly.
function casting.server_broke(now)
    if not active(now) then return end
    local info = casting.info(now)
    casting.stats.broke = casting.stats.broke + 1
    st.broke, st.pending = true, false
    st.frozen = info and info.frac or 0
    st.cast_end = math.min(st.cast_end, now)
    st.until_ = math.min(st.until_, now + 0.5)
end

--- Your cast landed: the bar is full, and only the short delay after the action is left.
function casting.server_landed(now)
    if not active(now) then return end
    casting.stats.landed = casting.stats.landed + 1
    st.pending, st.pct = false, nil
    st.cast_end = math.min(st.cast_end, now)
    st.until_ = now + st.lockout
end

--- Called every frame: gives up on a click the server never started (out of range, not enough MP, ...).
function casting.expire(now)
    if st.pending and active(now) and (st.total or 0) > 0 then
        local limit = st.packets and PENDING_MAX or nil
        if limit and now > st.started + limit then
            st.pending = false
            st.until_ = math.min(st.until_, now + 0.3)
            st.cast_end = now
        end
    end
end

--- Feeds the game's cast bar (progress 0..1, or nil when it cannot be read).
function casting.observe(now, pct)
    if pct == nil or now >= st.until_ then return end
    if pct > 0 and pct < 1 then
        st.bar_seen, st.bar_works = true, true
        st.pct, st.pct_at = pct, now
        st.pending = false
        -- The game's bar starts after the click (the server has to answer first), so time the cast from when the bar
        -- began, not from the click. Measured from the click, the first readings would stretch the cast out and
        -- the bar would jump backwards.
        if not st.bar_t0 then st.bar_t0 = now - pct * (st.total or 0) end
        local total = st.total or 0
        if pct > 0.15 or total <= 0 then total = (now - st.bar_t0) / pct end   -- measured length of this cast
        st.total = total
        st.cast_end = st.bar_t0 + total
        st.until_ = st.cast_end + st.lockout
    elseif st.bar_works and not st.packets then            -- with packets, the server says when it ends
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
    if st.broke then
        frac = st.frozen or frac                           -- interrupted: stays where it stopped
    elseif st.pct and now - st.pct_at < 0.25 then
        frac = st.pct                                      -- the game's own bar, while it is showing
    elseif st.pending and cast_left > 0 and (st.packets or st.bar_works or now < st.started + PENDING_MAX) then
        -- The bar starts once the server answers: do not run ahead of it. Even the first cast after a reload (nothing
        -- is known yet about packets or the game's bar) waits a moment; if nothing answers, the estimate takes over.
        frac = 0
    end
    return { left = left, cast_left = cast_left, total = st.total, frac = frac, key = st.key, name = st.name,
             broke = st.broke or nil }
end

--- Adds busy/casting/queued to a player table (what spellstate and the UI read).
function casting.decorate(player, now)
    casting.expire(now)
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
