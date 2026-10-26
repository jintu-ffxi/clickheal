-- Renders the demo UI through the recording backend and writes the draw commands as JSON, one
-- file per scenario, for tools/preview.py to turn into PNGs.
--
--   lua tools/dump_draw.lua <out_dir>
--
-- Runs the real ui.lua / frame.lua / layout.lua code; only the final pixels are drawn by Python.
package.path = 'addons/clickheal/?.lua;' .. package.path

local out_dir = arg[1] or 'preview_out'

local chconfig = require('ch.chconfig')
local frame    = require('ch.frame')
local ui       = require('ch.ui')
local demo     = require('ch.source_demo')
local gfx_rec  = require('ch.gfx_record')

local function esc(s)
    return (tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' end
        return string.format('\\u%04x', c:byte())
    end))
end

local function to_json(cmds, w, h, fs)
    local parts = {}
    for _, c in ipairs(cmds) do
        if c.op == 'rect' then
            -- coordinates can be fractional (text widths are), so print them as decimals
            parts[#parts + 1] = string.format('{"op":"rect","x":%.2f,"y":%.2f,"w":%.2f,"h":%.2f,"c":%.0f,"r":%.2f}',
                c.x, c.y, c.w, c.h, c.c, c.r)
        elseif c.op == 'quad' then
            parts[#parts + 1] = string.format('{"op":"quad","p":[%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f],"c":%.0f,"t":%.2f}',
                c.p[1], c.p[2], c.p[3], c.p[4], c.p[5], c.p[6], c.p[7], c.p[8], c.c, c.t or 0)
        elseif c.op == 'text' then
            parts[#parts + 1] = string.format('{"op":"text","x":%.2f,"y":%.2f,"c":%.0f,"k":%.3f,"s":"%s"}', c.x, c.y, c.c, c.k or 1, esc(c.s))
        elseif c.op == 'tooltip' then
            local ls = {}
            for _, l in ipairs(c.lines) do ls[#ls + 1] = '"' .. esc(l) .. '"' end
            parts[#parts + 1] = '{"op":"tooltip","lines":[' .. table.concat(ls, ',') .. ']}'
        end
    end
    return string.format('{"w":%d,"h":%d,"fs":%.4f,"cmds":[%s]}', w, h, fs, table.concat(parts, ','))
end

local function scenario(name, over, disp_w, disp_h, t, mouse)
    local cfg = chconfig.sanitize({})
    for k, v in pairs(over or {}) do cfg[k] = v end
    chconfig.sanitize(cfg)
    demo.reset()
    ui.reset_state()

    local fr = frame.build(cfg, demo, t, disp_w, disp_h, {})
    local g = gfx_rec.new(fr.geom.scale * cfg.font_mult)
    local ox, oy = 0, 0
    local f = {
        gfx = g, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, groups = fr.groups, player = fr.player,
        preset = fr.preset, now = t, ox = ox, oy = oy, events = {}, disp_w = disp_w, disp_h = disp_h,
        input = mouse and gfx_rec.input(mouse[1], mouse[2], nil) or gfx_rec.input(nil, nil, nil),
    }
    ui.draw_roster(f)
    local roster_cmds, rw, rh = g.cmds, fr.geom.width, fr.geom.height

    -- Hover flyout, rendered into its own recording at its own position.
    local plan = ui.flyout_plan(f)
    if plan then
        local g3 = gfx_rec.new(fr.geom.scale * cfg.font_mult)
        local ff = {
            gfx = g3, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, groups = fr.groups, player = fr.player,
            preset = fr.preset, now = t, ox = 0, oy = 0, events = {}, plan = plan,
            input = gfx_rec.input(nil, nil, nil), disp_w = disp_w, disp_h = disp_h,
        }
        ui.draw_flyout(ff)
        local fh3 = io.open(out_dir .. '/' .. name .. '.flyout.json', 'w')
        fh3:write(to_json(g3.cmds, plan.w, plan.h, g3.font_scale)); fh3:close()
        fh3 = io.open(out_dir .. '/' .. name .. '.flyout.pos', 'w')
        fh3:write(string.format('%d %d', plan.x, plan.y)); fh3:close()
    end

    -- Alert bar rendered into its own recording.
    local g2 = gfx_rec.new(fr.geom.scale * cfg.font_mult)
    local fa = {
        gfx = g2, geom = fr.geom, cfg = cfg, pal = fr.pal, roster = fr.roster, groups = fr.groups, player = fr.player,
        preset = fr.preset, now = t, ox = 0, oy = 0, events = {},
        alerts = fr.alerts, abar = fr.abar, more = fr.alert_more,
        input = gfx_rec.input(nil, nil, nil),
    }
    ui.draw_alerts(fa)

    local fh = io.open(out_dir .. '/' .. name .. '.roster.json', 'w')
    fh:write(to_json(roster_cmds, rw, rh, g.font_scale)); fh:close()
    if cfg.alerts.enabled then   -- the optional alert window; skipped (like in game) when it is off
        fh = io.open(out_dir .. '/' .. name .. '.alerts.json', 'w')
        fh:write(to_json(g2.cmds, fr.abar.w, fr.abar.h, g2.font_scale)); fh:close()
    end
    print(string.format('%-26s roster %dx%d  alerts %dx%d (%d shown, %d total)',
        name, rw, rh, fr.abar.w, fr.abar.h, #fr.alerts, fr.alert_total))
end

-- name, settings overrides, display w, h, time, mouse (optional)
scenario('strip_party_1080',      { mode = 'party' },     1920, 1080, 3.0)
scenario('strip_alliance1_1080',  { mode = 'alliance1' }, 1920, 1080, 3.0)
scenario('strip_alliance2_1080',  { mode = 'alliance2', demo_alliance_debuffs = true }, 1920, 1080, 3.0)
scenario('strip_alliance2_1440',  { mode = 'alliance2', demo_alliance_debuffs = true }, 2560, 1440, 3.0)
scenario('strip_rows_alliance1',  { mode = 'alliance1', orientation = 'rows' }, 1920, 1080, 3.0)
scenario('strip_party_4k',        { mode = 'party' },     3840, 2160, 3.0)
scenario('strip_party_colorblind', { mode = 'party', colors = 'colorblind' }, 1920, 1080, 3.0)
scenario('strip_big_rows',        { mode = 'party', row_w = 300, row_h = 60, debuff_icon = 22, buff_icon = 22 }, 1920, 1080, 3.0)
scenario('strip_small_rows',      { mode = 'alliance1', row_w = 190, row_h = 34, debuff_icon = 12, buff_icon = 12 }, 1920, 1080, 3.0)
scenario('strip_no_buff_bar',     { mode = 'party', show_buff_bar = false }, 1920, 1080, 3.0)
scenario('strip_hover_debuffs',   { mode = 'party', flyout = false }, 1920, 1080, 3.0, { 70, 267 })
scenario('strip_with_alert_window', { mode = 'party', alerts = { enabled = true } }, 1920, 1080, 3.0)
scenario('strip_bar_heal',        { mode = 'party', spellbar = true }, 1920, 1080, 3.0)
scenario('strip_bar_cleanse',     { mode = 'party', bar_tab = 'cleanse', spellbar = true }, 1920, 1080, 3.0)
scenario('strip_bar_4k',          { mode = 'party', spellbar = true }, 3840, 2160, 3.0)
scenario('strip_flyout_member',   { mode = 'party' }, 1920, 1080, 3.0, { 120, 70 })
scenario('strip_flyout_you',      { mode = 'party' }, 1920, 1080, 3.0, { 120, 30 })
scenario('strip_flyout_alliance', { mode = 'alliance2', demo_alliance_debuffs = true }, 1920, 1080, 3.0, { 350, 160 })
scenario('strip_flyout_4k',       { mode = 'party' }, 3840, 2160, 3.0, { 240, 140 })
scenario('strip_job_colors',      { mode = 'alliance1', colors = 'job' }, 1920, 1080, 3.0)
scenario('strip_job_icons',       { mode = 'alliance1', colors = 'job', job_icon = true }, 1920, 1080, 3.0)
scenario('hairline_party',         { mode = 'party', skin = 'hairline', colors = 'job' }, 1920, 1080, 3.0)
scenario('hairline_mp_pct',        { mode = 'party', skin = 'hairline', show_mp_pct = true }, 1920, 1080, 3.0)
scenario('hairline_alliance',      { mode = 'alliance1', skin = 'hairline' }, 1920, 1080, 3.0)
scenario('triage_party',           { mode = 'party', triage = true }, 1920, 1080, 3.0)
scenario('triage_alliance',        { mode = 'alliance1', triage = true, skin = 'hairline' }, 1920, 1080, 3.0)
scenario('strip_unlocked',        { mode = 'party', locked = false }, 1920, 1080, 3.0)
