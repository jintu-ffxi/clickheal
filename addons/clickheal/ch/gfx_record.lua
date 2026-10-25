--[[
    ClickHeal - gfx_record.lua
    Recording graphics backend. Instead of drawing, it stores every draw command in a list.
    Used by the offline tests and by tools/dump_draw.lua (which feeds the PNG preview renderer).

    Text metrics approximate ImGui's default 13px font: 7px per character, 13px tall, times the
    font scale. (In game, gfx_imgui.lua measures real text with ImGui instead.)
]]--

local M = {}

function M.new(font_scale)
    local g = { cmds = {}, font_scale = font_scale or 1 }

    function g.rect_filled(x, y, w, h, c, r)
        g.cmds[#g.cmds + 1] = { op = 'rect', x = x, y = y, w = w, h = h, c = c, r = r or 0 }
    end

    -- Four corners (clockwise from top-left).
    function g.quad_filled(x1, y1, x2, y2, x3, y3, x4, y4, c)
        g.cmds[#g.cmds + 1] = { op = 'quad', p = { x1, y1, x2, y2, x3, y3, x4, y4 }, c = c, t = 0 }
    end

    function g.quad_outline(x1, y1, x2, y2, x3, y3, x4, y4, c, thickness)
        g.cmds[#g.cmds + 1] = { op = 'quad', p = { x1, y1, x2, y2, x3, y3, x4, y4 }, c = c, t = thickness or 1 }
    end

    function g.text(x, y, c, s)
        g.cmds[#g.cmds + 1] = { op = 'text', x = x, y = y, c = c, s = s }
    end

    function g.text_size(s)
        return #s * 7 * g.font_scale, 13 * g.font_scale
    end

    function g.tooltip(lines, scale)
        g.cmds[#g.cmds + 1] = { op = 'tooltip', lines = lines }
    end

    -- A drag handle: held while the mouse button is down inside the rectangle (tests set input.down).
    function g.hit_area(_, x, y, w, h)
        local i = g.current_input
        return i and i.down and i.down.left and i.mx >= x and i.mx < x + w and i.my >= y and i.my < y + h or false
    end

    -- Game status icons: off by default so tests and previews draw text tags; set g.has_icons = true to
    -- record 'icon' commands instead.
    function g.status_icon(x, y, size, status_id)
        if not g.has_icons then return false end
        g.cmds[#g.cmds + 1] = { op = 'icon', x = x, y = y, w = size, h = size, id = status_id }
        return true
    end

    function g.clear() g.cmds = {} end

    return g
end

--- Builds an input table for tests/previews. Pass nil mx/my for "mouse far away".
function M.input(mx, my, click, mods, interactive)
    local clicked = {}
    if click then clicked[click] = true end
    return {
        mx = mx or -1000, my = my or -1000,
        hovered = mx ~= nil,
        interactive = interactive ~= false,
        clicked = clicked,
        down = { left = click == 'left' },
        mods = mods or {},
    }
end

return M
