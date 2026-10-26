--[[
    ClickHeal - bindings.lua
    Click-casting bindings for the Grid layout (a click anywhere on a member's cell casts).

    A binding slot is a mouse button plus an optional modifier: left, right, middle, shift_left,
    shift_right, ctrl_left, ctrl_right, alt_left, alt_right. Its value is a spell key
    ('cure4'), 'cleanse' (the spell that fixes that member's worst debuff) or '-' (nothing).

    Heal mode uses preset.bindings overridden by cfg.bindings. Buff mode uses preset.buff_bindings.
    A KO'd member always gets a Raise instead (left = strongest, right = cheapest).
]]--

local spells  = require('ch.spells')
local debuffs = require('ch.debuffs')

local bindings = {}

bindings.SLOTS = {
    'left', 'right', 'middle',
    'shift_left', 'shift_right', 'ctrl_left', 'ctrl_right', 'alt_left', 'alt_right',
}

bindings.SHORT = {
    left = 'LMB', right = 'RMB', middle = 'MMB',
    shift_left = 'Shift+LMB', shift_right = 'Shift+RMB',
    ctrl_left = 'Ctrl+LMB', ctrl_right = 'Ctrl+RMB',
    alt_left = 'Alt+LMB', alt_right = 'Alt+RMB',
}

bindings.LABEL = {
    left = 'Left click', right = 'Right click', middle = 'Middle click',
    shift_left = 'Shift + left', shift_right = 'Shift + right',
    ctrl_left = 'Ctrl + left', ctrl_right = 'Ctrl + right',
    alt_left = 'Alt + left', alt_right = 'Alt + right',
}

local valid_slot = {}
for _, s in ipairs(bindings.SLOTS) do valid_slot[s] = true end

function bindings.is_slot(name) return valid_slot[name] == true end

--- True for '-', 'cleanse' or a known spell key.
function bindings.valid_value(v)
    if v == '-' or v == 'cleanse' then return true end
    return type(v) == 'string' and spells.defs[v] ~= nil
end

--- Parses what a user types: "lmb", "shift+rmb", "ctrl+left" -> slot name, or nil.
function bindings.parse_slot(text)
    if not text then return nil end
    local s = tostring(text):lower():gsub('%s', '')
    local mod, btn = s:match('^(%a+)[%+%-_](%a+)$')
    if not mod then mod, btn = '', s end
    local B = { lmb = 'left', left = 'left', l = 'left', rmb = 'right', right = 'right', r = 'right',
                mmb = 'middle', middle = 'middle', m = 'middle' }
    btn = B[btn]
    if not btn then return nil end
    if mod == '' then return btn end
    if mod ~= 'shift' and mod ~= 'ctrl' and mod ~= 'alt' then return nil end
    if btn == 'middle' then return nil end
    return mod .. '_' .. btn
end

--- Slot for a click: modifier first (ctrl, alt, shift), then the button.
function bindings.slot_name(button, mods)
    mods = mods or {}
    if button == 'middle' then return 'middle' end
    if button ~= 'left' and button ~= 'right' then return nil end
    if mods.ctrl then return 'ctrl_' .. button end
    if mods.alt then return 'alt_' .. button end
    if mods.shift then return 'shift_' .. button end
    return button
end

--- Effective bindings table for the current mode.
function bindings.effective(cfg, preset)
    local out = {}
    if cfg.buff_mode and preset.buff_bindings and next(preset.buff_bindings) then
        for k, v in pairs(preset.buff_bindings) do out[k] = v end
        return out
    end
    for k, v in pairs(preset.bindings or {}) do out[k] = v end
    for k, v in pairs(cfg.bindings or {}) do out[k] = v end
    return out
end

--- The spell that fixes the member's worst debuff, or nil.
function bindings.cleanse_spell(m)
    if not m or not m.has_buff_data or not m.debuffs then return nil end
    local list = {}
    for _, k in ipairs(m.debuffs) do
        local info = debuffs.info[k]
        if info and info.spell and spells.defs[info.spell] then list[#list + 1] = k end
    end
    table.sort(list, debuffs.compare)
    if #list == 0 then return nil end
    return debuffs.info[list[1]].spell
end

--- value -> spell key (or nil, reason). Handles KO'd members and 'cleanse'.
function bindings.resolve(value, m, preset, button)
    if m.dead then
        local r = preset.raise or {}
        if #r == 0 then return nil, 'No raise spell for this job' end
        if button == 'right' then return r[#r] end
        return r[1]
    end
    if not value or value == '-' then return nil end
    if value == 'cleanse' then
        local k = bindings.cleanse_spell(m)
        if k then return k end
        return nil, 'Nothing to cleanse on ' .. m.name
    end
    if spells.defs[value] then return value end
    return nil
end

local function label_for(value, m, preset, button)
    local key = bindings.resolve(value, m, preset, button)
    if key then return spells.defs[key].name end
    if value == 'cleanse' then return 'Cleanse' end
    if not value or value == '-' then return '-' end
    return value
end

--- Tooltip lines describing what each click does on this member.
function bindings.describe(eff, m, preset)
    local function L(slot, button) return label_for(eff[slot], m, preset, button) end
    if m.dead then
        return { 'KO   LMB: ' .. L('left', 'left') .. '   RMB: ' .. L('right', 'right') }
    end
    local out = {
        string.format('LMB: %s   RMB: %s   MMB: %s', L('left', 'left'), L('right', 'right'), L('middle', 'middle')),
    }
    for _, mod in ipairs({ 'shift', 'ctrl', 'alt' }) do
        local l, r = eff[mod .. '_left'], eff[mod .. '_right']
        if (l and l ~= '-') or (r and r ~= '-') then
            out[#out + 1] = string.format('%s: %s / %s', mod:sub(1, 1):upper() .. mod:sub(2),
                L(mod .. '_left', 'left'), L(mod .. '_right', 'right'))
        end
    end
    return out
end

--- One line per slot, (unused now that the Bindings page is gone).
function bindings.list_lines(cfg, preset)
    local eff = bindings.effective(cfg, preset)
    local out = {}
    for _, slot in ipairs(bindings.SLOTS) do
        local v = eff[slot] or '-'
        local shown = v
        if spells.defs[v] then shown = spells.defs[v].name .. ' (' .. v .. ')' end
        out[#out + 1] = string.format('%-10s %s', bindings.SHORT[slot], shown)
    end
    return out
end

return bindings
