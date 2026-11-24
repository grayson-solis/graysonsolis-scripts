-- @description Render Stacks Lite
-- @version 1.3
-- @changelog
--   Renaming a track and running Create Regions again now replaces its old regions instead of leaving duplicates
--   Ungroup items on delete only applies when Group items when creating regions is on
--   Changing a highlighted track's color now keeps the new color, and its regions follow it
--   Regions left behind by deleted tracks are cleaned up
--   Changing a highlighted parent track's color now recolors its child tracks too
-- @author Grayson Solis
-- @website https://graysonsolis.com
-- @about
--   Lite version of Render Stacks that creates render regions from your stacks of items!
--   Requires the ReaImGui extension (ReaTeam Extensions repository).
-- @provides
--   [main] graysonsolis_Render Stacks Lite_Create Regions.lua
--   [main] graysonsolis_Render Stacks Lite_Delete All Regions.lua
--   [main] graysonsolis_Render Stacks Lite_Delete Selected Tracks Regions.lua
--   graysonsolis_Render Stacks Lite_Core.lua

local scriptPath = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = scriptPath .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")
if not RenderStacks.ensure_dependencies("Render Stacks Lite", true, false) then return end

local defaultSettings = {
    gap_tolerance = 0.001,
    min_region_length = 0.0,
    color_regions_track_color = true,
    group_items = false,
    ungroup_on_delete = false,
    highlight_tracks_with_regions = true,
    highlight_level = -0.4,
}

local settings = RenderStacks.loadSettings(defaultSettings)

local lastSavedSettings = {}
for k, v in pairs(settings) do lastSavedSettings[k] = v end

local function settingsDirty()
    for k, v in pairs(settings) do
        if lastSavedSettings[k] ~= v then return true end
    end
    return false
end

local function revertSettings()
    for k, v in pairs(lastSavedSettings) do
        settings[k] = v
    end
end

local REBUILD_KEYS = { "gap_tolerance", "min_region_length", "group_items" }
local HIGHLIGHT_KEYS = { "highlight_tracks_with_regions", "highlight_level" }

local function anyChanged(keys)
    for _, k in ipairs(keys) do
        if settings[k] ~= lastSavedSettings[k] then return true end
    end
    return false
end

local function applyAllSettings()
    local rebuild = anyChanged(REBUILD_KEYS)
    local recolor = settings.color_regions_track_color ~= lastSavedSettings.color_regions_track_color
    local highlight = anyChanged(HIGHLIGHT_KEYS)

    for k, v in pairs(settings) do
        if v ~= lastSavedSettings[k] then
            reaper.SetExtState(RenderStacks.SETTINGS_KEY, k, tostring(v), true)
            lastSavedSettings[k] = v
        end
    end

    if (rebuild or recolor) and reaper.CountProjectMarkers(0) > 0 then
        reaper.Undo_BeginBlock()
        if rebuild then
            RenderStacks.refresh_all_regions(settings)
        else
            RenderStacks.recolor_all_regions(settings)
        end
        RenderStacks.update_highlight()
        reaper.Undo_EndBlock("Render Stacks Lite: Apply settings", -1)
    elseif highlight or rebuild or recolor then
        RenderStacks.update_highlight()
    end
    if rebuild then RenderStacks.setup_render_window() end
end

local function reaper_to_imgui_color(col)
    local r = col & 0xFF
    local g = (col >> 8) & 0xFF
    local b = (col >> 16) & 0xFF
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

local ctx = reaper.ImGui_CreateContext('RenderStacks Settings Lite')

local checkAnim = {}
local TIPS = {
    unit_toggle = "Click to switch between milliseconds and seconds",
    reset = "Hold until the bar fills, then release to reset all settings to their defaults",
    save = "Save",
    gap = "Items within this distance are grouped into the same region",
    min_length = "Regions shorter than this will not be created",
    tail = "Extra time added after each stack for reverb and delay tails to ring out\nSilence at the end is trimmed when rendering",
    mono = "Render to mono if track width is 0, stereo otherwise",
    level = "How bright the highlight is compared to the original color",
    room =
        "While the render window is open, stacks that sit too close to the next one are moved\n" ..
        "later so each region has room for its reverb or delay tail\n" ..
        "They move back when the render finishes or the window is closed\n\n" ..
        "Only stacks that need room move, in whole-bar steps so tempo-synced effects stay in phase\n\n" ..
        "Turn off if your sounds have no tails; regions then end exactly where the stack ends",
    region_color = "Use the track's color for created regions",
    group = "Automatically group all items within each region",
    ungroup = "When deleting regions, also ungroup any items within those regions",
    delete_after =
        "Automatically delete all regions after rendering\n" ..
        "Useful for cleaning up after batch rendering",
    existing = "What to do when track already has regions and you rerun the script on it",
    name_source = "What to use as the base name for regions",
    numbering = "How to number multiple regions from the same track",
    separator = "Character between name and number ('_' makes 'Name_1')",
    child = "Include child tracks when calculating region boundaries\nTo keep a child's audio out of the render, mute it and leave Muted tracks unchecked",
    video = "Include video items when calculating region boundaries\nUseful when rendering sound clips synced to a video item in your project",
    muted_tracks = "Include muted tracks when calculating region boundaries",
    muted_items = "Include muted items when calculating region boundaries",
    instant = "Instant Render renders right away with your last render settings instead of opening the render window",
    setup_window = "Whenever regions are created, sets the render window's\nSource to Region render matrix and Bounds to All project regions\nAdds $region to the file name",
}

local checkCfg = { chk_thick = 135, chk_round = 0, chk_speed = 70, chk_size = 85, anim_section = 130, anim_slide = 60, anim_arrow = 120, anim_slider = 50, anim_tip = 120, anim_guide = 200, anim_bounce = 300, anim_bdamp = 45, anim_bkick = 0, cas_on = 0, cas_delay = 40, cas_dur = 220, fade_on = 1, pop_on = 1, pop_dur = 220, pop_scale = 60, pop_over = 100, sweep_on = 0, sweep_dur = 350, nest_on = 0, nest_dur = 220, nest_dist = 24, inl_on = 1, inl_dur = 140, inl_dist = 24, out_dur = 140, out_dist = 24, rv_on = 1, rv_dur = 80 }

local function animCheckbox(ctx, label, value)
    local mark = reaper.ImGui_GetStyleColor(ctx, reaper.ImGui_Col_CheckMark())
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0)
    local changed, nv = reaper.ImGui_Checkbox(ctx, label, value)
    reaper.ImGui_PopStyleColor(ctx, 1)
    if changed then value = nv end
    local now = reaper.time_precise()
    local a = checkAnim[label]
    if not a then a = { p = value and 1 or 0, t = now }; checkAnim[label] = a end
    local dt = math.min(0.05, now - a.t)
    a.t = now
    if a.prev == nil then a.prev = value end
    if value and not a.prev then a.pt0 = now end
    a.prev = value
    local pm = 1
    if checkCfg.pop_on == 1 and a.pt0 then
        local pt = math.min(1, (now - a.pt0) / (checkCfg.pop_dur / 1000))
        local c1 = 1.70158 * checkCfg.pop_over / 100
        local eb = 1 + (c1 + 1) * (pt - 1) ^ 3 + c1 * (pt - 1) ^ 2
        pm = checkCfg.pop_scale / 100 + (1 - checkCfg.pop_scale / 100) * eb
    end
    a.p = math.max(0, math.min(1, a.p + (value and dt or -dt) / (checkCfg.chk_speed / 1000)))
    if a.p > 0 then
        local x, y = reaper.ImGui_GetItemRectMin(ctx)
        local h = reaper.ImGui_GetFrameHeight(ctx)
        local pad = math.max(1, math.floor(h / 6))
        local sz = h - pad * 2
        local th = math.max(sz / 5, 1) * checkCfg.chk_thick / 100
        sz = sz - th * 0.5
        local px, py = x + pad + th * 0.25, y + pad + th * 0.25
        local third = sz / 3
        local bx, by = px + third, py + sz - third * 0.5
        local x1, y1, x2, y2, x3, y3 = bx - third, by - third, bx, by, bx + third * 2, by - third * 2
        local cx, cy, k = x + h / 2, y + h / 2, checkCfg.chk_size / 100 * pm
        x1, y1, x2, y2, x3, y3 = cx + (x1 - cx) * k, cy + (y1 - cy) * k, cx + (x2 - cx) * k, cy + (y2 - cy) * k, cx + (x3 - cx) * k, cy + (y3 - cy) * k
        local l1 = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local l2 = math.sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2)
        local d = a.p * (l1 + l2)
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_DrawList_PathLineTo(dl, x1, y1)
        if d <= l1 then
            local f = d / l1
            reaper.ImGui_DrawList_PathLineTo(dl, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f)
        else
            local f = (d - l1) / l2
            reaper.ImGui_DrawList_PathLineTo(dl, x2, y2)
            reaper.ImGui_DrawList_PathLineTo(dl, x2 + (x3 - x2) * f, y2 + (y3 - y2) * f)
        end
        reaper.ImGui_DrawList_PathStroke(dl, mark, 0, th)
        local r = th / 2 * checkCfg.chk_round / 100
        if r > 0.1 then
            local f = math.min(1, d / l1)
            local tx, ty = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
            if d > l1 then
                f = (d - l1) / l2
                tx, ty = x2 + (x3 - x2) * f, y2 + (y3 - y2) * f
                reaper.ImGui_DrawList_AddCircleFilled(dl, x2, y2, r, mark)
            end
            reaper.ImGui_DrawList_AddCircleFilled(dl, x1, y1, r, mark)
            reaper.ImGui_DrawList_AddCircleFilled(dl, tx, ty, r, mark)
        end
    end
    return changed, value
end

local shouldRun = true
local FONT_FAMILIES = { 'ProggyClean', 'Verdana', 'Segoe UI', 'Tahoma', 'Arial', 'Calibri', 'Trebuchet MS', 'Consolas' }
local fontRegular, fontBold = {}, {}
for i, name in ipairs(FONT_FAMILIES) do
    if i > 1 then
        fontRegular[i] = reaper.ImGui_CreateFont(name)
        fontBold[i] = reaper.ImGui_CreateFont(name, reaper.ImGui_FontFlags_Bold())
        reaper.ImGui_Attach(ctx, fontRegular[i])
        reaper.ImGui_Attach(ctx, fontBold[i])
    end
end

local function pushFont(font, size)
    return (pcall(reaper.ImGui_PushFont, ctx, font, size))
end

local function popFont(pushed)
    if pushed then reaper.ImGui_PopFont(ctx) end
end

local function storedFontIndex(key)
    local name = reaper.GetExtState(RenderStacks.SETTINGS_KEY, key)
    for i, n in ipairs(FONT_FAMILIES) do
        if n == name then return i end
    end
    return 2
end

local function storedFontSize(key)
    local n = math.floor(tonumber(reaper.GetExtState(RenderStacks.SETTINGS_KEY, key)) or 14)
    return math.max(10, math.min(28, n))
end

local function setFontPref(key, value)
    reaper.SetExtState(RenderStacks.SETTINGS_KEY, key, tostring(value), true)
end

local fontIdx = storedFontIndex('font_name')
local headingIdx = storedFontIndex('heading_font_name')
local fontSize = storedFontSize('font_size')
local headingSize = storedFontSize('heading_font_size')

local function storedSpace(key, default)
    local n = math.floor(tonumber(reaper.GetExtState(RenderStacks.SETTINGS_KEY, key)) or default)
    return math.max(0, math.min(40, n))
end

local compactNumbers = reaper.GetExtState(RenderStacks.SETTINGS_KEY, 'compact_numbers') ~= '0'
for _, k in ipairs({ 'fade_other_regions', 'fade_percentage' }) do reaper.DeleteExtState(RenderStacks.SETTINGS_KEY, k, true) end
local saveColor = 0x2F8F62FF
local exitColor = saveColor
local spaceBefore = storedSpace('heading_space_before', 16)
local spaceAfter = storedSpace('heading_space_after', 12)
local timingLayout = math.max(1, math.min(4, math.floor(tonumber(reaper.GetExtState(RenderStacks.SETTINGS_KEY, 'timing_layout')) or 1)))

local timingUnits = {}

local function unitSeconds(id)
    local u = timingUnits[id]
    if u == nil then
        local v = reaper.GetExtState(RenderStacks.SETTINGS_KEY, 'timing_unit_' .. id)
        if v == "" then v = reaper.GetExtState(RenderStacks.SETTINGS_KEY, 'timing_unit') end
        u = v == 's'
        timingUnits[id] = u
    end
    return u
end

local function gap(n)
    local _, itemY = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    local h = n - itemY
    if h >= 0 then
        reaper.ImGui_Dummy(ctx, 0, h)
    else
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + h)
    end
end

local tipId, tipSince, tipShownAt = nil, 0, -10
local tipMouseX, tipMouseY = 0, 0
local rowMinX, rowMinY = 0, 0
local tipFadeStart, tipFadeLast = 0, -10

local RED = 0xE06666FF
local RED_DARK = 0x8E4B4BFF
local HEAD_RED = 0x7A3C3CFF
local LOCK_TEXT = 0xE07070FF
local LOCK_BG = 0x3A1A1AFF

local function lockGlyph(dl, x, top)
    reaper.ImGui_DrawList_AddRect(dl, x + 3, top, x + 9, top + 8, RED, 3, 0, 1.6)
    reaper.ImGui_DrawList_AddRectFilled(dl, x + 1, top + 5, x + 11, top + 13, RED, 2)
    reaper.ImGui_DrawList_AddCircleFilled(dl, x + 6, top + 9, 1.3, LOCK_BG)
end


local function tipReady(id, hovered)
    local now = reaper.time_precise()
    if reaper.ImGui_IsMouseDown(ctx, 0) or reaper.ImGui_IsMouseDown(ctx, 1) then
        tipId, tipShownAt = nil, -10
        return false
    end
    if not hovered then return false end
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
    if tipId ~= id or math.abs(mouseX - tipMouseX) > 1 or math.abs(mouseY - tipMouseY) > 1 then
        tipId, tipSince, tipMouseX, tipMouseY = id, now, mouseX, mouseY
        return false
    end
    if now - tipSince < (now - tipShownAt < 1 and 0.13 or 0.67) then return false end
    tipShownAt = now
    return true
end

local function tip(text, hovered, locked)
    if hovered == nil then hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) end
    if tipReady(text, hovered) then
        local now = reaper.time_precise()
        if now - tipFadeLast > 0.25 then tipFadeStart = now end
        tipFadeLast = now
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), math.min(1, (now - tipFadeStart) / (checkCfg.anim_tip / 1000)))
        if locked then
            reaper.ImGui_BeginTooltip(ctx)
            if text ~= "" then reaper.ImGui_Text(ctx, text) end
            local lx, ly = reaper.ImGui_GetCursorScreenPos(ctx)
            local lh = reaper.ImGui_GetTextLineHeight(ctx)
            lockGlyph(reaper.ImGui_GetWindowDrawList(ctx), lx, ly + (lh - 13) / 2)
            reaper.ImGui_Dummy(ctx, 12, lh)
            reaper.ImGui_SameLine(ctx, 0, 6)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), LOCK_TEXT)
            reaper.ImGui_Text(ctx, "Available in the full version!")
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_EndTooltip(ctx)
        else
            reaper.ImGui_SetTooltip(ctx, text)
        end
        reaper.ImGui_PopStyleVar(ctx)
    end
end

local function rowTip(text, locked)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    tip(text, reaper.ImGui_IsMouseHoveringRect(ctx, rowMinX, rowMinY, maxX, maxY) and reaper.ImGui_IsWindowHovered(ctx), locked)
end

local accent = 0x00A2FFFF
local accentPushed = false
local sectionOpen = {}
local secAnim, secH = {}, {}

local function heading(text, color, locked, tooltip)
    gap(spaceBefore)
    if accentPushed then reaper.ImGui_PopStyleColor(ctx) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), (color & 0xFFFFFF00) | 0x80)
    local headingPushed = pushFont(fontBold[headingIdx], headingSize)
    reaper.ImGui_SeparatorText(ctx, text)
    local hx1, hy1 = reaper.ImGui_GetItemRectMin(ctx)
    local hx2, hy2 = reaper.ImGui_GetItemRectMax(ctx)
    local sectionKey = 'section_' .. (text:gsub('%W', ''))
    if sectionOpen[text] == nil then
        local stored = reaper.GetExtState(RenderStacks.SETTINGS_KEY, sectionKey)
        sectionOpen[text] = stored == '' and text ~= 'Appearance' or stored == '1'
    end
    local headHover = reaper.ImGui_IsMouseHoveringRect(ctx, hx1, hy1, hx2, hy2) and reaper.ImGui_IsWindowHovered(ctx)
    if headHover then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        if reaper.ImGui_IsMouseClicked(ctx, 0) then
            sectionOpen[text] = not sectionOpen[text]
            setFontPref(sectionKey, sectionOpen[text] and '1' or '0')
        end
    end
    local ax, ay = hx2 - 12, (hy1 + hy2) / 2
    local adl = reaper.ImGui_GetWindowDrawList(ctx)
    if locked then
        local lx = hx1 + 20 + reaper.ImGui_CalcTextSize(ctx, text) + 6
        reaper.ImGui_DrawList_AddRectFilled(adl, lx - 2, hy1, lx + 20, hy2, 0x141414FF)
        lockGlyph(adl, lx, ay - 6.5)
    end
    reaper.ImGui_DrawList_AddRectFilled(adl, ax - 10, hy1, hx2, hy2, 0x141414FF)
    local sa = secAnim[text]
    local sp = sa and sa.p or (sectionOpen[text] and 1 or 0)
    local se = sp * sp * (3 - 2 * sp)
    local th = -(1 - se) * math.pi / 2
    local co, si, k = math.cos(th), math.sin(th), 1
    local function pt(px, py) return ax + (px * co - py * si) * k, ay + (px * si + py * co) * k end
    local p1x, p1y = pt(-5, -3)
    local p2x, p2y = pt(5, -3)
    local p3x, p3y = pt(0, 3)
    reaper.ImGui_DrawList_AddTriangleFilled(adl, p1x, p1y, p2x, p2y, p3x, p3y, color)
    popFont(headingPushed)
    reaper.ImGui_PopStyleColor(ctx, 2)
    if tooltip then tip(tooltip, headHover, locked) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), color)
    accent = color
    accentPushed = true
    gap(spaceAfter)
    return sectionOpen[text]
end

local function shade(c, k)
    local function ch(s) return math.min(255, math.floor(((c >> s) & 255) * k + 0.5)) end
    return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | 0xFF
end

local numberText = {}

local function numberInput(id, value, minV, maxV, width, onSet, secs)
    local frameH = reaper.ImGui_GetFrameHeight(ctx)
    local inputW = math.floor(reaper.ImGui_CalcTextSize(ctx, "00") + 28)
    local text = numberText[id] or (secs and (string.format("%.3f", value / 1000):gsub("%.?0+$", "")) or tostring(value))
    local _, padY = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
    local padX = math.max(10, math.floor((inputW - reaper.ImGui_CalcTextSize(ctx, text)) / 2))
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), padX, padY)
    reaper.ImGui_SetNextItemWidth(ctx, inputW)
    local ok, typed = reaper.ImGui_InputText(ctx, "##" .. id, text)
    reaper.ImGui_PopStyleVar(ctx)
    if ok then
        numberText[id] = typed
        local n
        if secs then
            local t = typed:match("^%d*%.?%d*$") and tonumber(typed)
            n = t and math.floor(t * 1000 + 0.5)
        else
            n = typed:match("^%d+$") and tonumber(typed)
        end
        if n then onSet(math.max(minV, math.min(maxV, n))) end
    end
    if reaper.ImGui_IsItemDeactivated(ctx) then numberText[id] = nil end
    local function step(delta)
        local n = math.max(minV, math.min(maxV, value + delta))
        if n ~= value then numberText[id] = nil; onSet(n) end
    end
    local base, hover, press = accent, shade(accent, 1.1), shade(accent, 0.82)
    reaper.ImGui_PushItemFlag(ctx, reaper.ImGui_ItemFlags_ButtonRepeat(), true)
    if compactNumbers then
        reaper.ImGui_SameLine(ctx, 0, 0)
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 0)
        local half = math.floor(frameH / 2)
        for i, delta in ipairs({ 1, -1 }) do
            local h = i == 1 and half or frameH - half
            local clicked = reaper.ImGui_InvisibleButton(ctx, "##" .. id .. (i == 1 and "up" or "dn"), 18, h)
            local x, y = reaper.ImGui_GetItemRectMin(ctx)
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local fill = reaper.ImGui_IsItemActive(ctx) and press or reaper.ImGui_IsItemHovered(ctx) and hover or base
            reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + 18, y + h, fill, 2)
            local cx, cy, s = x + 9, y + h / 2, i == 1 and 1 or -1
            reaper.ImGui_DrawList_AddTriangleFilled(dl, cx, cy - 2 * s, cx - 4, cy + 2 * s, cx + 4, cy + 2 * s, 0x141414FF)
            if i == 2 then reaper.ImGui_DrawList_AddLine(dl, x, y, x + 18, y, 0x141414FF, 2) end
            if clicked then step(delta) end
        end
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_EndGroup(ctx)
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), base)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), press)
        for i, delta in ipairs({ -1, 1 }) do
            reaper.ImGui_SameLine(ctx, 0, 4)
            if reaper.ImGui_Button(ctx, "##" .. id .. (i == 1 and "dec" or "inc"), frameH, frameH) then step(delta) end
            local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
            local cx, cy = x1 + frameH / 2, y1 + frameH / 2
            local a, thick = frameH * 0.26, math.max(2, frameH * 0.12)
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddLine(dl, cx - a, cy, cx + a, cy, 0x141414FF, thick)
            if i == 2 then reaper.ImGui_DrawList_AddLine(dl, cx, cy - a, cx, cy + a, 0x141414FF, thick) end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
    reaper.ImGui_PopItemFlag(ctx)
end

local ROW_LABELS = { "Gap tolerance:", "Min region length:", "Existing regions:", "Name source:", "Custom name:", "Numbering:", "Separator:", "Font:", "Font size:", "Heading font:", "Heading size:", "Space before headings:", "Space after headings:", "Timing layout:" }

local function option(label, key)
    local changed, newVal = animCheckbox(ctx, label, settings[key])
    if changed then settings[key] = newVal end
end

local function lockedOption(label, value, tooltip, col)
    if col then reaper.ImGui_SameLine(ctx, col) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), LOCK_TEXT)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), LOCK_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), LOCK_TEXT)
    reaper.ImGui_BeginDisabled(ctx)
    animCheckbox(ctx, label, value)
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
    tip(tooltip or "", nil, true)
end

local function lockedCombo(id, items, width)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), LOCK_TEXT)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), LOCK_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), RED_DARK)
    reaper.ImGui_BeginDisabled(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, width)
    reaper.ImGui_Combo(ctx, "##" .. id, 0, items)
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
end

local function lockedInput(id, text, width)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), LOCK_TEXT)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), LOCK_BG)
    reaper.ImGui_BeginDisabled(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, width)
    reaper.ImGui_InputText(ctx, "##" .. id, text)
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_PopStyleColor(ctx, 2)
end

local function labelButton(label, width, textColor, glow)
    local pressed = reaper.ImGui_Button(ctx, "##" .. label, width)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local textW = reaper.ImGui_CalcTextSize(ctx, label)
    local textY = minY + (maxY - minY - reaper.ImGui_GetTextLineHeight(ctx)) / 2 - 1
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddText(dl, minX + (maxX - minX - textW) / 2, textY, textColor, label)
    if glow then
        local pulse = 0.5 + 0.5 * math.sin(reaper.time_precise() * 4)
        reaper.ImGui_DrawList_AddRect(dl, minX - 1, minY - 1, maxX + 1, maxY + 1, glow | math.floor(70 + 185 * pulse), 4, 0, 2)
    end
    return pressed
end

local function labelText(text)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + reaper.ImGui_GetFrameHeight(ctx) + 8)
    reaper.ImGui_Text(ctx, text)
    rowMinX, rowMinY = reaper.ImGui_GetItemRectMin(ctx)
end

local function timingLabel(label, id, sameLine, colX, chipW)
    if sameLine then reaper.ImGui_SameLine(ctx, 0, 24) end
    if timingLayout >= 3 then
        if not sameLine then reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + reaper.ImGui_GetFrameHeight(ctx) + 8) end
        local h = reaper.ImGui_GetFrameHeight(ctx)
        reaper.ImGui_InvisibleButton(ctx, "##" .. id .. "_lbl", chipW, h)
        local x, y = reaper.ImGui_GetItemRectMin(ctx)
        rowMinX, rowMinY = x, y
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + chipW, y + h, accent, 4, reaper.ImGui_DrawFlags_RoundCornersLeft())
        reaper.ImGui_DrawList_AddText(dl, x + 10, y + (h - reaper.ImGui_GetTextLineHeight(ctx)) / 2, 0x141414FF, label)
        reaper.ImGui_SameLine(ctx, 0, 0)
    elseif sameLine then
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, label .. ":")
        rowMinX, rowMinY = reaper.ImGui_GetItemRectMin(ctx)
        reaper.ImGui_SameLine(ctx)
    else
        labelText(label .. ":")
        reaper.ImGui_SameLine(ctx, colX)
    end
end

local function timingField(label, id, ms, onSet, tipText, sameLine, colX, chipW)
    timingLabel(label, id, sameLine, colX, chipW)
    local secs = unitSeconds(id)
    numberInput(id, ms, 0, 60000, 100, onSet, secs)
    rowTip(tipText)
    reaper.ImGui_SameLine(ctx)
    local unitH = reaper.ImGui_GetFrameHeight(ctx)
    reaper.ImGui_InvisibleButton(ctx, "##unit_" .. id, reaper.ImGui_CalcTextSize(ctx, "ms"), unitH)
    local unitX, unitY = reaper.ImGui_GetItemRectMin(ctx)
    reaper.ImGui_DrawList_AddText(reaper.ImGui_GetWindowDrawList(ctx), unitX, unitY + (unitH - reaper.ImGui_GetTextLineHeight(ctx)) / 2, reaper.ImGui_GetStyleColor(ctx, reaper.ImGui_Col_Text()), secs and "s" or "ms")
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    if hovered then reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand()) end
    if reaper.ImGui_IsItemClicked(ctx, 0) then
        timingUnits[id] = not secs
        numberText[id] = nil
        setFontPref('timing_unit_' .. id, secs and 'ms' or 's')
    end
    tip(TIPS.unit_toggle, hovered)
end

local function guideAnchor()
    local x1 = reaper.ImGui_GetItemRectMin(ctx)
    local _, y2 = reaper.ImGui_GetItemRectMax(ctx)
    return x1 + reaper.ImGui_GetFrameHeight(ctx) / 2, y2
end

local uiAlpha = 1
local guideTrig = {}

local function guideTrigger(key, cond)
    local t = guideTrig[key]
    if not t then guideTrig[key] = { prev = cond, t0 = -10 } return end
    if cond and not t.prev then t.t0 = reaper.time_precise() end
    t.prev = cond
end

local function nestBegin(key)
    local t = guideTrig[key]
    local p = t and checkCfg.nest_on == 1 and math.min(1, (reaper.time_precise() - t.t0) / (checkCfg.nest_dur / 1000)) or 1
    local e = p * p * (3 - 2 * p)
    local off = -(1 - e) * checkCfg.nest_dist
    uiAlpha = e
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), e)
    if off ~= 0 then reaper.ImGui_Indent(ctx, off) end
    return off
end

local function nestEnd(off)
    if off ~= 0 then reaper.ImGui_Unindent(ctx, off) end
    reaper.ImGui_PopStyleVar(ctx)
    uiAlpha = 1
end

local function inlineBegin(...)
    local t0
    for _, k in ipairs({ ... }) do
        local t = guideTrig[k]
        if t and (not t0 or t.t0 > t0) then t0 = t.t0 end
    end
    local p = t0 and checkCfg.inl_on == 1 and math.min(1, (reaper.time_precise() - t0) / (checkCfg.inl_dur / 1000)) or 1
    local e = p * p * (3 - 2 * p)
    local prev = uiAlpha
    uiAlpha = prev * e
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), e)
    return -(1 - e) * checkCfg.inl_dist, prev
end

local function inlineEnd(prev)
    reaper.ImGui_PopStyleVar(ctx)
    uiAlpha = prev
end

local inlineOut = {}

local function inlineShow(key, cond, draw, ...)
    local now = reaper.time_precise()
    local st = inlineOut[key]
    if not st then st = { p = cond and 1 or 0, t = now }; inlineOut[key] = st end
    local dt = math.min(0.05, now - st.t)
    st.t = now
    if cond then
        st.p = 1
        local off, prev = inlineBegin(...)
        draw(off)
        inlineEnd(prev)
        return
    end
    st.p = math.max(0, st.p - dt / (checkCfg.out_dur / 1000))
    if st.p <= 0 then return end
    local e = st.p * st.p * (3 - 2 * st.p)
    local prev = uiAlpha
    uiAlpha = prev * e
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), e)
    draw(-(1 - e) * checkCfg.out_dist)
    reaper.ImGui_PopStyleVar(ctx)
    uiAlpha = prev
end

local revealState = {}
local guideDL, guideLimit

local function revealBegin(key, cond)
    local now = reaper.time_precise()
    local r = revealState[key]
    if not r then r = { p = cond and 1 or 0, t = now }; revealState[key] = r end
    local dt = math.min(0.05, now - r.t)
    r.t = now
    if checkCfg.rv_on == 1 then
        r.p = math.max(0, math.min(1, r.p + (cond and dt or -dt) / (checkCfg.rv_dur / 1000)))
    else
        r.p = cond and 1 or 0
    end
    r.active = r.p > 0
    if not r.active then return false, 0 end
    if r.p >= 1 or not r.h then
        r.mode = "plain"
        r.y0 = reaper.ImGui_GetCursorPosY(ctx)
        return true, 0
    end
    local e = r.p * r.p * (3 - 2 * r.p)
    local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
    local wx = reaper.ImGui_GetWindowPos(ctx)
    local spY = select(2, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing()))
    local ch = math.max(1, r.h * e - spY)
    guideDL = reaper.ImGui_GetWindowDrawList(ctx)
    guideLimit = sy + ch
    local flags = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    reaper.ImGui_BeginChild(ctx, "##rv_" .. key, 0, ch, 0, flags)
    r.mode = "child"
    r.y0 = reaper.ImGui_GetCursorPosY(ctx)
    return true, sx - wx
end

local function revealEnd(key)
    local r = revealState[key]
    if not r or not r.active then return end
    r.h = reaper.ImGui_GetCursorPosY(ctx) - r.y0
    if r.mode == "child" then
        reaper.ImGui_EndChild(ctx)
        guideDL, guideLimit = nil, nil
    end
end

local function guideTo(ax, ay, key)
    local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
    local _, y2 = reaper.ImGui_GetItemRectMax(ctx)
    local my = (y1 + y2) / 2
    local dl = guideDL or reaper.ImGui_GetWindowDrawList(ctx)
    local lim = guideLimit or math.huge
    local c = (accent & 0xFFFFFF00) | 0xB0
    local t = guideTrig[key]
    local p = t and math.min(1, (reaper.time_precise() - t.t0) / (checkCfg.anim_guide / 1000)) or 1
    p = 1 - (1 - p) ^ 2
    local l1, l2 = my - ay, x1 - 3 - ax
    local d = p * (l1 + l2)
    reaper.ImGui_DrawList_AddLine(dl, ax, ay, ax, math.min(ay + math.min(d, l1), lim), c, 2)
    if d > l1 and my <= lim then reaper.ImGui_DrawList_AddLine(dl, ax, my, ax + d - l1, my, c, 2) end
end

local RESET_HOLD_SECONDS = 0.9
local holdStart, pulseAt, fill, lastNow = nil, -10, 0, 0
local savePulseAt, exitPulseAt, exitAt = -10, -10, nil
local exitFade = { p = 0, t = 0 }

local function mixColor(c1, c2, t)
    local function ch(sh) return math.floor(((c1 >> sh) & 255) * (1 - t) + ((c2 >> sh) & 255) * t + 0.5) end
    return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | 0xFF
end

local function pulseRing(startedAt, minX, minY, maxX, maxY, rgb)
    local t = (reaper.time_precise() - startedAt) / 0.6
    if t >= 0 and t < 1 then
        local grow = 2 + 14 * t
        reaper.ImGui_DrawList_AddRect(reaper.ImGui_GetForegroundDrawList(ctx), minX - grow, minY - grow, maxX + grow, maxY + grow, rgb | math.floor(255 * (1 - t)), 4 + grow, 0, 2)
    end
end

local function holdButton(label, width, seconds)
    reaper.ImGui_Button(ctx, "##" .. label, width)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local now = reaper.time_precise()
    local dt = now - lastNow
    lastNow = now
    local fired = false
    if reaper.ImGui_IsItemActive(ctx) then
        holdStart = holdStart or (now - fill * seconds)
        fill = math.min(1, (now - holdStart) / seconds)
    elseif holdStart and fill >= 1 then
        fired, pulseAt, fill, holdStart = true, now, 0, nil
    else
        holdStart = nil
        fill = math.max(0, fill - dt / 0.25)
    end
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    if fill > 0 then
        reaper.ImGui_DrawList_AddRectFilled(dl, minX, minY, minX + (maxX - minX) * fill, maxY, fill >= 1 and 0xE05555FF or 0xCB4A4AFF, 4)
    end
    local textW = reaper.ImGui_CalcTextSize(ctx, label)
    local textY = minY + (maxY - minY - reaper.ImGui_GetTextLineHeight(ctx)) / 2 - 1
    reaper.ImGui_DrawList_AddText(dl, minX + (maxX - minX - textW) / 2, textY, 0xE6E6E6FF, label)
    pulseRing(pulseAt, minX, minY, maxX, maxY, 0xCB4A4A00)
    return fired
end

local PREVIEW_BASE = 0xE16182

local sliderResetHeld = {}
local sliderStart = {}
local sliderGlow = {}
local sliderSpring = {}
local sliderSweep = {}
local function fadeCol(c)
    return (c & 0xFFFFFF00) | math.floor((c & 255) * uiAlpha + 0.5)
end


local function drawSlider(id, value, min, max, default, step, leftLabel, rightLabel, tint, suffix, hardMax)
    local width = 200
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local h = reaper.ImGui_GetFrameHeight(ctx)
    reaper.ImGui_InvisibleButton(ctx, "##" .. id, width, h)
    local active = reaper.ImGui_IsItemActive(ctx)
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    local rightClicked = reaper.ImGui_IsItemClicked(ctx, 1)
    local pad = 6
    local left, span = x + pad, width - pad * 2

    local resetNow = false
    if hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
        value = default
        sliderResetHeld[id] = true
        resetNow = true
    end
    if not active then sliderResetHeld[id] = false end
    if active and not sliderResetHeld[id] then
        local mouseX = reaper.ImGui_GetMousePos(ctx)
        local raw = (mouseX - left) / span * (max - min) + min
        if hardMax and raw > max then raw = max + (mouseX - (left + span)) / 200 * (hardMax - max) end
        local fine = (reaper.ImGui_GetKeyMods(ctx) & (reaper.ImGui_Mod_Ctrl() | reaper.ImGui_Mod_Alt() | reaper.ImGui_Mod_Shift())) ~= 0
        local unit = hardMax and fine and 0.1 or 1
        value = math.floor(raw / unit + 0.5) * unit
        value = math.max(min, math.min(hardMax or max, value))
        if step and not fine then
            value = math.floor(value / step + 0.5) * step
        end
        if hardMax then value = tonumber(string.format("%.1f", value)) end
    end

    local now = reaper.time_precise()
    local gl = sliderGlow[id] or { g = 0, t = now }
    sliderGlow[id] = gl
    gl.g = gl.g + (((active or hovered) and 1 or 0) - gl.g) * math.min(1, (now - gl.t) * (1000 / checkCfg.anim_slider))
    gl.t = now
    local sp = sliderSpring[id]
    if not sp then sp = { x = value, v = 0, on = false, t = now }; sliderSpring[id] = sp end
    if resetNow then
        sp.on = true
        sp.v = (value - sp.x) * 2 * math.pi / (checkCfg.anim_bounce / 1000) * checkCfg.anim_bkick / 100
    end
    if active and not sliderResetHeld[id] then sp.on = false end
    local sdt = math.min(0.033, now - sp.t)
    sp.t = now
    if sp.on then
        local w = 2 * math.pi / (checkCfg.anim_bounce / 1000)
        sp.v = sp.v + (w * w * (value - sp.x) - 2 * (checkCfg.anim_bdamp / 100) * w * sp.v) * sdt
        sp.x = sp.x + sp.v * sdt
        if math.abs(value - sp.x) < (max - min) * 0.002 and math.abs(sp.v) < (max - min) * 0.02 then sp.on = false; sp.x = value end
    else
        sp.x = value
    end
    local sw = sliderSweep[id]
    if not sw or now - sw.last > 0.25 then sw = { t0 = now }; sliderSweep[id] = sw end
    sw.last = now
    local swp = 1
    if checkCfg.sweep_on == 1 then
        swp = 1 - (1 - math.min(1, (now - sw.t0) / (checkCfg.sweep_dur / 1000))) ^ 3
    end
    local shown = math.max(min, 0) + (sp.x - math.max(min, 0)) * swp
    local live = active or hovered
    if live then sliderStart[id] = sliderStart[id] or now else sliderStart[id] = nil end
    local tinted = tint and tint(value, live, now - (sliderStart[id] or now))
    local fillColor = tinted or accent
    local handleX = left + (math.max(min, math.min(shown, max)) - min) / (max - min) * span
    local originX = left + (math.max(min, 0) - min) / (max - min) * span
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + h, fadeCol(active and 0x3C3C3CFF or hovered and 0x323232FF or 0x282828FF), 4)
    reaper.ImGui_DrawList_AddRectFilled(dl, math.min(originX, handleX), y + 2, math.max(originX, handleX), y + h - 2, fadeCol(fillColor), 2)
    if min < 0 then
        reaper.ImGui_DrawList_AddLine(dl, originX, y + 2, originX, y + h - 2, fadeCol(0x808080FF))
    end
    reaper.ImGui_DrawList_AddRectFilled(dl, handleX - 2 - gl.g * 1.5, y + 2 - gl.g, handleX + 2 + gl.g * 1.5, y + h - 2 + gl.g, fadeCol(0xE6E6E6FF), 2)
    local label = min < 0 and (value == 0 and "0%" or string.format("%+d%%", value)) or (hardMax and value ~= math.floor(value) and string.format("%.1f", value) or string.format("%d", value)) .. (suffix or "%")
    local textW = reaper.ImGui_CalcTextSize(ctx, label)
    local textY = y + (h - reaper.ImGui_GetTextLineHeight(ctx)) / 2
    local outRight = min >= 0 or handleX >= originX
    local tx = outRight and handleX + 7 or handleX - 7 - textW
    local ink = 0xFFFFFFFF
    if tx < x + 4 or tx + textW > x + width - 4 then
        tx = outRight and handleX - 7 - textW or handleX + 7
        local lum = (((fillColor >> 24) & 255) * 299 + ((fillColor >> 16) & 255) * 587 + ((fillColor >> 8) & 255) * 114) / 1000
        ink = lum > 140 and 0x141414FF or 0xFFFFFFFF
    end
    ink = (ink & 0xFFFFFF00) | math.floor(0xA0 + gl.g * 0x5F)
    reaper.ImGui_DrawList_AddText(dl, tx, textY, fadeCol(ink), label)

    if rightClicked then reaper.ImGui_OpenPopup(ctx, "##" .. id .. "_input") end
    if reaper.ImGui_BeginPopup(ctx, "##" .. id .. "_input") then
        if reaper.ImGui_IsWindowAppearing(ctx) then reaper.ImGui_SetKeyboardFocusHere(ctx) end
        local chars = #tostring(math.floor(hardMax or max)) + (hardMax and 2 or 0) + (min < 0 and 1 or 0)
        reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_CalcTextSize(ctx, "0") * chars + reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding()) * 2 + 4)
        local typed
        if hardMax then
            _, typed = reaper.ImGui_InputDouble(ctx, "##value", value, 0, 0, "%.1f")
        else
            _, typed = reaper.ImGui_InputInt(ctx, "##value", value, 0, 0)
        end
        value = math.max(min, math.min(hardMax or max, typed))
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter()) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
    return value
end

local function saveIconButton(width, ink, glow)
    local pressed = reaper.ImGui_Button(ctx, "##saveicon", width)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
    local s = (maxY - minY) * 0.3
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect(dl, cx - s, cy - s, cx + s, cy + s, ink, 1.5, 0, 1.5)
    reaper.ImGui_DrawList_AddRectFilled(dl, cx - s * 0.55, cy - s, cx + s * 0.55, cy - s * 0.2, ink)
    reaper.ImGui_DrawList_AddRect(dl, cx - s * 0.55, cy + s * 0.25, cx + s * 0.55, cy + s, ink, 0, 0, 1.5)
    if glow then
        local pulse = 0.5 + 0.5 * math.sin(reaper.time_precise() * 4)
        reaper.ImGui_DrawList_AddRect(dl, minX - 1, minY - 1, maxX + 1, maxY + 1, glow | math.floor(70 + 185 * pulse), 4, 0, 2)
    end
    return pressed
end

local function sectionBegin(open, name)
    local now = reaper.time_precise()
    local a = secAnim[name]
    if not a then a = { p = open and 1 or 0, t = now }; secAnim[name] = a end
    local dt = math.min(0.05, now - a.t)
    a.t = now
    a.p = math.max(0, math.min(1, a.p + (open and dt or -dt) / (checkCfg.anim_section / 1000)))
    if a.prevOpen == nil then a.prevOpen = open end
    if open and not a.prevOpen then a.t0 = now end
    a.prevOpen = open
    if a.p <= 0 then a.mode = nil return false, 0 end
    if a.p >= 1 or not secH[name] then
        a.mode = "plain"
        a.y0 = reaper.ImGui_GetCursorPosY(ctx)
        a.sy = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
        return true, 0
    end
    local e = a.p * a.p * (3 - 2 * a.p)
    local flags = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    reaper.ImGui_BeginChild(ctx, "##sec_" .. name, 0, math.max(1, secH[name] * e - select(2, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing()))), 0, flags)
    a.mode = "child"
    a.y0 = reaper.ImGui_GetCursorPosY(ctx)
    a.sy = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
    return true, select(1, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding()))
end

local function sectionEnd(name)
    local a = secAnim[name]
    if not a or not a.mode then return end
    secH[name] = reaper.ImGui_GetCursorPosY(ctx) - a.y0
    local cas, fade = checkCfg.cas_on == 1 and a.t0, checkCfg.fade_on == 1
    if (cas or fade) and a.sy then
        local now = reaper.time_precise()
        local wx = reaper.ImGui_GetWindowPos(ctx)
        local ww = reaper.ImGui_GetWindowWidth(ctx)
        local by = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
        local bandH = reaper.ImGui_GetFrameHeightWithSpacing(ctx)
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local fp = a.p * a.p * (3 - 2 * a.p)
        for k = 0, math.ceil((by - a.sy) / bandH) - 1 do
            local prog = 1
            if cas then
                local t = math.max(0, math.min(1, (now - a.t0 - k * checkCfg.cas_delay / 1000) / (checkCfg.cas_dur / 1000)))
                prog = t * t * (3 - 2 * t)
            end
            if fade then prog = prog * fp end
            if prog < 0.999 then
                reaper.ImGui_DrawList_AddRectFilled(dl, wx, a.sy + k * bandH, wx + ww, math.min(by, a.sy + (k + 1) * bandH), 0x14141400 | math.floor((1 - prog) * 255 + 0.5))
            end
        end
    end
    if a.mode == "child" then reaper.ImGui_EndChild(ctx) end
end

local KOFI_URL = "https://ko-fi.com/s/6f3b7ddc65"

local function openUrl(url)
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(url)
        return
    end
    local os_name = reaper.GetOS()
    if os_name:find("Win") then
        reaper.ExecProcess('cmd.exe /C start "" "' .. url .. '"', -1)
    elseif os_name:find("OSX") or os_name:find("macOS") then
        reaper.ExecProcess('/usr/bin/open "' .. url .. '"', -1)
    else
        reaper.ExecProcess('xdg-open "' .. url .. '"', -1)
    end
end

local PITCH = {
    { "Unlock everything marked in ", 0xB0B0B0FF },
    { "red", 0xE06666FF },
    { ", enable live editing of regions, and support the development of more scripts by me! :)", 0xB0B0B0FF },
}

local function wrappedPitch(width)
    local x, glued = 0, false
    for _, segment in ipairs(PITCH) do
        for word in segment[1]:gmatch("%S+%s*") do
            local w = reaper.ImGui_CalcTextSize(ctx, (word:gsub("%s+$", "")))
            if x > 0 and not glued and x + w > width then
                x = 0
            elseif x > 0 then
                reaper.ImGui_SameLine(ctx, 0, 0)
            end
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), segment[2])
            reaper.ImGui_Text(ctx, word)
            reaper.ImGui_PopStyleColor(ctx)
            x = x + reaper.ImGui_CalcTextSize(ctx, word)
            glued = not word:find("%s$")
        end
    end
end

local kofiPulseAt = -10

function drawGui()
    local windowFlags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_MenuBar()
    reaper.ImGui_SetNextWindowSize(ctx, 455, 720, reaper.ImGui_Cond_FirstUseEver())

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       0x141414FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(),        0x303030FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(),  0x303030FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x282828FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x323232FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),  0x3C3C3CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0x00A2FFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x3C3C3CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x464646FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0x505050FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),         0x3C3C3CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),  0x464646FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),   0x505050FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(),      0x3C3C3CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(),      0x141414FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xFFFFFFFF)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),   6, 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    8, 8)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16, 16)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(),  8)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),   4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(),    4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemInnerSpacing(), 8, 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(),    8)

    local mainPushed = pushFont(fontRegular[fontIdx], fontSize)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 8)
    local visible, openWindow = reaper.ImGui_Begin(ctx, 'Render Stacks Settings Lite', true, windowFlags)
    reaper.ImGui_PopStyleVar(ctx)

    if not openWindow then
        revertSettings()
        shouldRun = false
    end

    if visible then
        local colX = 0
        for _, label in ipairs(ROW_LABELS) do colX = math.max(colX, (reaper.ImGui_CalcTextSize(ctx, label))) end
        colX = math.floor(colX + reaper.ImGui_GetFrameHeight(ctx) + 40)
        local colXBase, secOpen, secShift = colX
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) and reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
            and not reaper.ImGui_IsAnyItemActive(ctx) and not reaper.ImGui_IsPopupOpen(ctx, "", reaper.ImGui_PopupFlags_AnyPopupId()) then
            revertSettings()
            shouldRun = false
        end
        local dividerY
        if reaper.ImGui_BeginMenuBar(ctx) then
            dividerY = select(2, reaper.ImGui_GetCursorScreenPos(ctx)) + reaper.ImGui_GetFontSize(ctx) + 24
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 8)
            local dirty = settingsDirty()

            reaper.ImGui_AlignTextToFramePadding(ctx)

            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, math.max(0, (18 - reaper.ImGui_GetFontSize(ctx)) / 2))

            local resetLabel = "Reset Defaults"
            local exitLabel = "Save and Exit"
            local resetBtnW = reaper.ImGui_CalcTextSize(ctx, resetLabel) + 32
            local saveBtnW = 34
            local exitBtnW = reaper.ImGui_CalcTextSize(ctx, exitLabel) + 32
            local winW = select(1, reaper.ImGui_GetWindowSize(ctx))

            if holdButton(resetLabel, resetBtnW, RESET_HOLD_SECONDS) then
                for k, v in pairs(defaultSettings) do settings[k] = v end
            end
            if not reaper.ImGui_IsItemActive(ctx) then tip(TIPS.reset) end

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPosX(ctx, math.max(resetBtnW + 32, winW - saveBtnW - exitBtnW - 24))

            local sBase, sHover, sPress = saveColor, shade(saveColor, 1.1), shade(saveColor, 0.82)
            local sInk = 0xFFFFFFFF
            local enow = reaper.time_precise()
            exitFade.p = math.max(0, math.min(1, exitFade.p + (dirty and 1 or -1) * math.min(0.05, enow - exitFade.t) / 0.15))
            exitFade.t = enow
            local ep = exitFade.p
            local eBase = mixColor(0x303030FF, exitColor, ep)
            local eHover = mixColor(0x3A3A3AFF, shade(exitColor, 1.1), ep)
            local ePress = mixColor(0x282828FF, shade(exitColor, 0.82), ep)
            local eInk = mixColor(0x909090FF, 0xFFFFFFFF, ep)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        dirty and sBase or 0x303030FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), dirty and sHover or 0x303030FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  dirty and sPress or 0x303030FF)
            if saveIconButton(saveBtnW, dirty and sInk or 0x606060FF, dirty and (saveColor & 0xFFFFFF00) or nil) and dirty and not exitAt then
                applyAllSettings()
                savePulseAt = reaper.time_precise()
            end
            local saveMinX, saveMinY = reaper.ImGui_GetItemRectMin(ctx)
            local saveMaxX, saveMaxY = reaper.ImGui_GetItemRectMax(ctx)
            pulseRing(savePulseAt, saveMinX, saveMinY, saveMaxX, saveMaxY, saveColor & 0xFFFFFF00)
            tip(TIPS.save)
            reaper.ImGui_PopStyleColor(ctx, 3)

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        eBase)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), eHover)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  ePress)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          eInk)
            if labelButton(exitLabel, exitBtnW, eInk) and not exitAt then
                applyAllSettings()
                exitPulseAt = reaper.time_precise()
                exitAt = exitPulseAt + 0.3
            end
            local exitMinX, exitMinY = reaper.ImGui_GetItemRectMin(ctx)
            local exitMaxX, exitMaxY = reaper.ImGui_GetItemRectMax(ctx)
            pulseRing(exitPulseAt, exitMinX, exitMinY, exitMaxX, exitMaxY, exitColor & 0xFFFFFF00)
            if exitAt and reaper.time_precise() >= exitAt then shouldRun = false end
            reaper.ImGui_PopStyleColor(ctx, 4)

            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_EndMenuBar(ctx)
        end

        reaper.ImGui_PushItemWidth(ctx, 200)

        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 4)
        lockedOption("Start automatically when REAPER launches", false)

        secOpen, secShift = sectionBegin(heading("Get the Full Version", 0xCE70B6FF), "Get the Full Version")
        if secOpen then
            wrappedPitch((reaper.ImGui_GetContentRegionAvail(ctx)))
            reaper.ImGui_Dummy(ctx, 0, 4)

            local kofiLabel = "Get Render Stacks on Ko-fi"
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        0xCE70B6FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE47CCAFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  0xA55A92FF)
            if labelButton(kofiLabel, reaper.ImGui_CalcTextSize(ctx, kofiLabel) + 32, 0x141414FF) then
                openUrl(KOFI_URL)
                kofiPulseAt = reaper.time_precise()
            end
            local kofiMinX, kofiMinY = reaper.ImGui_GetItemRectMin(ctx)
            local kofiMaxX, kofiMaxY = reaper.ImGui_GetItemRectMax(ctx)
            pulseRing(kofiPulseAt, kofiMinX, kofiMinY, kofiMaxX, kofiMaxY, 0xCE70B600)
            reaper.ImGui_PopStyleColor(ctx, 3)
            sectionEnd("Get the Full Version")
        end

        secOpen, secShift = sectionBegin(heading("Stack Detection", 0xDB6E4AFF), "Stack Detection")
        if secOpen then
        colX = colXBase - secShift

        local chipW = (reaper.ImGui_CalcTextSize(ctx, "Min region length")) + 20
        timingField("Gap tolerance", "gap_tolerance", math.floor(settings.gap_tolerance * 1000 + 0.5), function(n) settings.gap_tolerance = n / 1000.0 end, TIPS.gap, false, colX, chipW)
        timingField("Min region length", "min_region_length", math.floor(settings.min_region_length * 1000 + 0.5), function(n) settings.min_region_length = n / 1000.0 end, TIPS.min_length, timingLayout % 2 == 0, colX, chipW)

        sectionEnd("Stack Detection")
        colX = colXBase
        end

        secOpen, secShift = sectionBegin(heading("Tracks & Items", 0x8261E1FF), "Tracks & Items")
        if secOpen then
        colX = colXBase - secShift

        lockedOption("Auto-detect mono/stereo from width", false, TIPS.mono)

        option("Highlight tracks / items", "highlight_tracks_with_regions")
        local hax, hay = guideAnchor()
        guideTrigger("hl", settings.highlight_tracks_with_regions)

        inlineShow("hl", settings.highlight_tracks_with_regions, function(off)
            reaper.ImGui_SameLine(ctx, colX + off)
            local currentLevel = math.floor(settings.highlight_level * 100 + 0.5)
            local newLevel = drawSlider("highlight_level", currentLevel, -100, 100, math.floor(defaultSettings.highlight_level * 100 + 0.5), 10, "Dark", "Bright", function(v, active, t)
                local bright = RenderStacks.compute_highlight_color(PREVIEW_BASE, setmetatable({ highlight_level = v / 100 }, { __index = settings }))
                return reaper_to_imgui_color(bright)
            end)
            if newLevel ~= currentLevel then settings.highlight_level = newLevel / 100.0 end
            tip(TIPS.level)
        end, "hl")

        reaper.ImGui_Indent(ctx, 20)
        if revealBegin("hl", settings.highlight_tracks_with_regions) then
            local nestHl = nestBegin("hl")
            lockedOption("Flashing", false)
            guideTo(hax, hay, "hl")
            nestEnd(nestHl)
            revealEnd("hl")
        end
        reaper.ImGui_Unindent(ctx, 20)

        sectionEnd("Tracks & Items")
        colX = colXBase
        end

        secOpen, secShift = sectionBegin(heading("Regions", 0xE0BD4BFF), "Regions")
        if secOpen then
        colX = colXBase - secShift

        lockedOption("Make room for tails", false, TIPS.room)

        option("Color regions the selected track color", "color_regions_track_color")
        tip(TIPS.region_color)

        option("Group items when creating regions", "group_items")
        tip(TIPS.group)
        local gax, gay = guideAnchor()
        guideTrigger("grp", settings.group_items)

        reaper.ImGui_Indent(ctx, 20)
        if revealBegin("grp", settings.group_items) then
            local nestGrp = nestBegin("grp")
            option("Ungroup items on delete", "ungroup_on_delete")
            guideTo(gax, gay, "grp")
            tip(TIPS.ungroup)
            nestEnd(nestGrp)
            revealEnd("grp")
        end
        reaper.ImGui_Unindent(ctx, 20)

        lockedOption("Delete all regions after rendering", false, TIPS.delete_after)

        reaper.ImGui_Dummy(ctx, 0, 4)

        labelText("Existing regions:", RED_DARK)
        reaper.ImGui_SameLine(ctx, colX)
        lockedCombo("delete_behavior", "Replace\0Ask confirmation\0Ignore\0", 200)
        rowTip(TIPS.existing, true)

        reaper.ImGui_Dummy(ctx, 0, 8)
        reaper.ImGui_Indent(ctx, 34)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), RED_DARK)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), 0x8E4B4BA0)
        reaper.ImGui_Text(ctx, "Naming")
        reaper.ImGui_SameLine(ctx, colX)
        reaper.ImGui_TextColored(ctx, 0x888888FF, "Track, Track_1, Track_2")
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_PopStyleColor(ctx, 2)
        reaper.ImGui_Unindent(ctx, 14)
        reaper.ImGui_Dummy(ctx, 0, 4)

        labelText("Name source:", RED_DARK)
        reaper.ImGui_SameLine(ctx, colX)
        lockedCombo("name_source", "Track\0Item\0Custom\0", 200)
        rowTip(TIPS.name_source, true)

        labelText("Numbering:", RED_DARK)
        reaper.ImGui_SameLine(ctx, colX)
        lockedCombo("naming_pattern", "Name, Name_1, Name_2\0Name_1, Name_2, Name_3\0", 200)
        rowTip(TIPS.numbering, true)

        labelText("Separator:", RED_DARK)
        reaper.ImGui_SameLine(ctx, colX)
        lockedInput("name_separator", "_", 50)
        rowTip(TIPS.separator, true)
        reaper.ImGui_Unindent(ctx, 20)

        sectionEnd("Regions")
        colX = colXBase
        end

        secOpen, secShift = sectionBegin(heading("Inclusion", HEAD_RED, true), "Inclusion")
        if secOpen then
        colX = colXBase - secShift

        lockedOption("Child tracks", true, TIPS.child)
        lockedOption("Video items", false, TIPS.video, colX)
        lockedOption("Muted tracks", false, TIPS.muted_tracks)
        lockedOption("Muted items", false, TIPS.muted_items, colX)

        sectionEnd("Inclusion")
        colX = colXBase
        end

        secOpen, secShift = sectionBegin(heading("Rendering", HEAD_RED, true), "Rendering")
        if secOpen then
        colX = colXBase - secShift

        lockedOption("Skip render dialog during Instant Render", true, TIPS.instant)
        lockedOption("Edit render window to work with Render Stacks", true, TIPS.setup_window)

        sectionEnd("Rendering")
        colX = colXBase
        end

        reaper.ImGui_Dummy(ctx, 0, 8)

        if accentPushed then
            reaper.ImGui_PopStyleColor(ctx)
            accentPushed = false
        end

        if dividerY then
            local winX = reaper.ImGui_GetWindowPos(ctx)
            local winW = reaper.ImGui_GetWindowWidth(ctx)
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddRectFilled(dl, winX, dividerY - 8, winX + winW, dividerY, 0x141414FF)
            reaper.ImGui_DrawList_AddLine(dl, winX, dividerY, winX + winW, dividerY, 0x808080FF)
        end

        reaper.ImGui_PopItemWidth(ctx)
    end

    reaper.ImGui_End(ctx)
    popFont(mainPushed)

    reaper.ImGui_PopStyleVar(ctx, 8)
    reaper.ImGui_PopStyleColor(ctx, 16)
end

function mainLoop()
    if shouldRun then
        local ok, err = xpcall(drawGui, debug.traceback)
        if not ok then
            reaper.ShowConsoleMsg(tostring(err) .. "\n")
            shouldRun = false
        end
        if shouldRun then reaper.defer(mainLoop) end
    end
end

mainLoop()
