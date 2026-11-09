-- @description Render Stacks Lite
-- @version 1.0
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

if not reaper.ImGui_CreateContext then return end

local scriptPath = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = scriptPath .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local defaultSettings = {
    gap_tolerance = 0.001,
    min_region_length = 0.0,
    color_regions_track_color = true,
    fade_other_regions = true,
    fade_percentage = 50,
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

local function applyAllSettings()
    local rebuild = false
    for _, k in ipairs(REBUILD_KEYS) do
        if settings[k] ~= lastSavedSettings[k] then rebuild = true end
    end
    local recolor = settings.color_regions_track_color ~= lastSavedSettings.color_regions_track_color

    RenderStacks.saveSettings(settings)
    for k, v in pairs(settings) do lastSavedSettings[k] = v end

    reaper.Undo_BeginBlock()
    if rebuild then
        RenderStacks.refresh_all_regions(settings)
    elseif recolor then
        RenderStacks.recolor_all_regions(settings)
    end
    RenderStacks.update_highlight()
    reaper.Undo_EndBlock("Render Stacks Lite: Apply settings", -1)
end

local function reaper_to_imgui_color(col)
    local r = col & 0xFF
    local g = (col >> 8) & 0xFF
    local b = (col >> 16) & 0xFF
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

local ctx = reaper.ImGui_CreateContext('RenderStacks Settings Lite')
local shouldRun = true

local font = reaper.ImGui_CreateFont('Verdana')
local headingFont = reaper.ImGui_CreateFont('Verdana', reaper.ImGui_FontFlags_Bold())
reaper.ImGui_Attach(ctx, font)
reaper.ImGui_Attach(ctx, headingFont)

local tipId, tipSince, tipShownAt = nil, 0, -10
local tipMouseX, tipMouseY = 0, 0
local rowMinX, rowMinY = 0, 0

local function tipReady(id, hovered)
    if not hovered then return false end
    local now = reaper.time_precise()
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
    if tipId ~= id or math.abs(mouseX - tipMouseX) > 1 or math.abs(mouseY - tipMouseY) > 1 then
        tipId, tipSince, tipMouseX, tipMouseY = id, now, mouseX, mouseY
        return false
    end
    if now - tipSince < (now - tipShownAt < 1 and 0.13 or 0.67) then return false end
    tipShownAt = now
    return true
end

local function tip(text, hovered)
    if hovered == nil then hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) end
    if tipReady(text, hovered) then reaper.ImGui_SetTooltip(ctx, text) end
end

local function rowTip(text)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    tip(text, reaper.ImGui_IsMouseHoveringRect(ctx, rowMinX, rowMinY, maxX, maxY) and reaper.ImGui_IsWindowHovered(ctx))
end

local accent = 0x00A2FFFF
local accentPushed = false

local function heading(text, color)
    if accentPushed then reaper.ImGui_PopStyleColor(ctx) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), (color & 0xFFFFFF00) | 0x80)
    reaper.ImGui_PushFont(ctx, headingFont, 14)
    reaper.ImGui_SeparatorText(ctx, text)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, 2)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), color)
    accent = color
    accentPushed = true
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
    { "Unlock everything marked with a ", 0xB0B0B0FF },
    { "lock", 0xE06666FF },
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

local function lockIcon()
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local h = reaper.ImGui_GetFrameHeight(ctx)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    local top = y + (h - 13) / 2
    reaper.ImGui_DrawList_AddRect(dl, x + 3, top, x + 9, top + 8, 0xE06666FF, 3, 0, 1.6)
    reaper.ImGui_DrawList_AddRectFilled(dl, x + 1, top + 5, x + 11, top + 13, 0xE06666FF, 2)
    reaper.ImGui_DrawList_AddCircleFilled(dl, x + 6, top + 9, 1.3, 0x3A1A1AFF)
    reaper.ImGui_Dummy(ctx, 12, h)
end

local function lockedCheckbox(label, value, tooltip)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE07070FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x3A1A1AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xE07070FF)
    reaper.ImGui_BeginDisabled(ctx)
    reaper.ImGui_Checkbox(ctx, label, value)
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
    local hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled())
    reaper.ImGui_SameLine(ctx)
    lockIcon()
    if hovered or reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        if tooltip then reaper.ImGui_Text(ctx, tooltip) end
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE07070FF)
        reaper.ImGui_Text(ctx, "Available in the full version!")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_EndTooltip(ctx)
    end
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

local RESET_HOLD_SECONDS = 0.9
local holdStart, pulseAt, fill, lastNow = nil, -10, 0, 0
local kofiPulseAt = -10

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
local levelResetHeld = false

local function levelSlider(width)
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local h = reaper.ImGui_GetFrameHeight(ctx)
    reaper.ImGui_InvisibleButton(ctx, "##highlight_level", width, h)
    local active = reaper.ImGui_IsItemActive(ctx)
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    local pad = 6
    local left, span = x + pad, width - pad * 2

    if hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
        settings.highlight_level = defaultSettings.highlight_level
        levelResetHeld = true
    end
    if not active then levelResetHeld = false end
    if active and not levelResetHeld then
        local mouseX = reaper.ImGui_GetMousePos(ctx)
        local value = math.floor((mouseX - left) / span * 200 - 100 + 0.5)
        value = math.max(-100, math.min(100, value))
        if (reaper.ImGui_GetKeyMods(ctx) & (reaper.ImGui_Mod_Ctrl() | reaper.ImGui_Mod_Alt() | reaper.ImGui_Mod_Shift())) == 0 then
            value = math.floor(value / 10 + 0.5) * 10
        end
        settings.highlight_level = value / 100.0
    end

    local level = math.floor(settings.highlight_level * 100 + 0.5)
    local handleX = left + (level + 100) / 200 * span
    local centerX = left + span / 2
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + h, active and 0x3C3C3CFF or hovered and 0x323232FF or 0x282828FF, 4)
    for i = -100, 100, 10 do
        local tickX = left + (i + 100) / 200 * span
        reaper.ImGui_DrawList_AddLine(dl, tickX, y + h - 5, tickX, y + h - 2, 0x505050FF)
    end
    reaper.ImGui_DrawList_AddRectFilled(dl, math.min(centerX, handleX), y + 2, math.max(centerX, handleX), y + h - 2, (accent & 0xFFFFFF00) | 0x55, 2)
    reaper.ImGui_DrawList_AddLine(dl, centerX, y + 2, centerX, y + h - 2, 0x808080FF)
    reaper.ImGui_DrawList_AddRectFilled(dl, handleX - 3, y + 2, handleX + 3, y + h - 2, accent, 2)
    local label = level == 0 and "0%" or string.format("%+d%%", level)
    local textW = reaper.ImGui_CalcTextSize(ctx, label)
    local textY = y + (h - reaper.ImGui_GetTextLineHeight(ctx)) / 2
    reaper.ImGui_DrawList_AddText(dl, x + 12, textY, 0x808080FF, "Dark")
    reaper.ImGui_DrawList_AddText(dl, x + width - 12 - reaper.ImGui_CalcTextSize(ctx, "Bright"), textY, 0x808080FF, "Bright")
    reaper.ImGui_DrawList_AddText(dl, x + (width - textW) / 2, textY, 0xFFFFFFFF, label)
end

local function valuePopup(id, value, min, max)
    local result = value
    if reaper.ImGui_IsItemClicked(ctx, 1) then reaper.ImGui_OpenPopup(ctx, id) end
    if reaper.ImGui_BeginPopup(ctx, id) then
        if reaper.ImGui_IsWindowAppearing(ctx) then reaper.ImGui_SetKeyboardFocusHere(ctx) end
        reaper.ImGui_SetNextItemWidth(ctx, 100)
        local _, typed = reaper.ImGui_InputInt(ctx, "##value", value, 0, 0)
        result = math.max(min, math.min(max, typed))
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter()) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
    return result
end

local function drawPreview()
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    local after = RenderStacks.compute_highlight_color(PREVIEW_BASE, settings)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + 36, y + 18, reaper_to_imgui_color(PREVIEW_BASE), 3)
    reaper.ImGui_DrawList_AddRect(dl, x, y, x + 36, y + 18, 0x505050FF, 3)
    reaper.ImGui_DrawList_AddTriangleFilled(dl, x + 42, y + 4, x + 42, y + 14, x + 50, y + 9, 0x808080FF)
    reaper.ImGui_DrawList_AddRectFilled(dl, x + 56, y, x + 92, y + 18, reaper_to_imgui_color(after), 3)
    reaper.ImGui_DrawList_AddRect(dl, x + 56, y, x + 92, y + 18, 0x505050FF, 3)
    reaper.ImGui_Dummy(ctx, 92, 18)
    tip("Sample color before and after the highlight")
end

function drawGui()
    local windowFlags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_MenuBar()
    reaper.ImGui_SetNextWindowSize(ctx, 520, 720, reaper.ImGui_Cond_FirstUseEver())

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

    reaper.ImGui_PushFont(ctx, font, 14)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 8)
    local visible, openWindow = reaper.ImGui_Begin(ctx, 'Render Stacks Settings Lite', true, windowFlags)
    reaper.ImGui_PopStyleVar(ctx)

    if not openWindow then
        revertSettings()
        shouldRun = false
    end

    if visible then
        local dividerY
        if reaper.ImGui_BeginMenuBar(ctx) then
            dividerY = select(2, reaper.ImGui_GetCursorScreenPos(ctx)) + reaper.ImGui_GetFontSize(ctx) + 24
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 8)
            local dirty = settingsDirty()

            reaper.ImGui_AlignTextToFramePadding(ctx)

            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 2)

            local resetLabel = "Reset Defaults"
            local saveLabel = "Save"
            local exitLabel = "Save and Exit"
            local resetBtnW = reaper.ImGui_CalcTextSize(ctx, resetLabel) + 32
            local saveBtnW = reaper.ImGui_CalcTextSize(ctx, saveLabel) + 16
            local exitBtnW = reaper.ImGui_CalcTextSize(ctx, exitLabel) + 32
            local winW = select(1, reaper.ImGui_GetWindowSize(ctx))

            if holdButton(resetLabel, resetBtnW, RESET_HOLD_SECONDS) then
                for k, v in pairs(defaultSettings) do settings[k] = v end
            end
            if not reaper.ImGui_IsItemActive(ctx) then tip("Hold until the bar fills, then release to reset all settings to their defaults") end

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPosX(ctx, math.max(resetBtnW + 32, winW - saveBtnW - exitBtnW - 24))

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        dirty and 0x45B24BFF or 0x303030FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), dirty and 0x4DC553FF or 0x303030FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  dirty and 0x3E9343FF or 0x303030FF)
            if labelButton(saveLabel, saveBtnW, dirty and 0x141414FF or 0x606060FF, dirty and 0x8DF29A00 or nil) and dirty then
                applyAllSettings()
            end
            reaper.ImGui_PopStyleColor(ctx, 3)

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        0x46B9FEFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x67C6FEFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  0x3894CBFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          0x141414FF)
            if labelButton(exitLabel, exitBtnW, 0x141414FF) then
                applyAllSettings()
                shouldRun = false
            end
            reaper.ImGui_PopStyleColor(ctx, 4)

            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_EndMenuBar(ctx)
        end

        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 4)
        lockedCheckbox("Start automatically when REAPER launches", false)

        heading("Get the Full Version", 0xCE70B6FF)
        reaper.ImGui_Dummy(ctx, 0, 4)
        wrappedPitch(250 + 200 - reaper.ImGui_GetCursorPosX(ctx))
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

        reaper.ImGui_Dummy(ctx, 0, 8)

        reaper.ImGui_PushItemWidth(ctx, 200)

        heading("Render Stacks Run", 0x34A4E1FF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        lockedCheckbox("Create reverb tails", false, "When running Render Stacks Run, add reverb tails to stacks first")
        lockedCheckbox("Create regions", false, "When running Render Stacks Run, create regions from stacks")
        lockedCheckbox("Open render dialog", false, "When running Render Stacks Run, open the render dialog after processing")

        reaper.ImGui_Dummy(ctx, 0, 8)

        heading("Timing & Length", 0xDB6E4AFF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        labelText("Gap tolerance:")
        reaper.ImGui_SameLine(ctx, 250)
        reaper.ImGui_SetNextItemWidth(ctx, 100)
        local currentGapMs = math.floor(settings.gap_tolerance * 1000 + 0.5)
        local changed, newGap = reaper.ImGui_InputInt(ctx, "##gap_tolerance", currentGapMs)
        if changed then settings.gap_tolerance = math.max(0, newGap) / 1000.0 end
        rowTip("Items within this distance are grouped into the same region")
        reaper.ImGui_SameLine(ctx) reaper.ImGui_Text(ctx, "ms")

        labelText("Min region length:")
        reaper.ImGui_SameLine(ctx, 250)
        reaper.ImGui_SetNextItemWidth(ctx, 100)
        local currentMinMs = math.floor(settings.min_region_length * 1000 + 0.5)
        local changed, newMin = reaper.ImGui_InputInt(ctx, "##min_region_length", currentMinMs)
        if changed then settings.min_region_length = math.max(0, newMin) / 1000.0 end
        rowTip("Regions shorter than this will not be created")
        reaper.ImGui_SameLine(ctx) reaper.ImGui_Text(ctx, "ms")

        reaper.ImGui_Dummy(ctx, 0, 8)

        heading("Tracks", 0x8261E1FF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        lockedCheckbox("Auto-detect mono/stereo from width", false, "Render to mono if track width is 0, stereo otherwise")

        local changed, newVal = reaper.ImGui_Checkbox(ctx, "Highlight tracks and items", settings.highlight_tracks_with_regions)
        if changed then settings.highlight_tracks_with_regions = newVal end
        tip("Change the color of tracks and items that have regions so they stand out")

        if settings.highlight_tracks_with_regions then
            reaper.ImGui_Indent(ctx, 20)

            labelText("Preview:")
            reaper.ImGui_SameLine(ctx, 250)
            drawPreview()

            labelText("Brightness:")
            reaper.ImGui_SameLine(ctx, 250)
            levelSlider(200)
            local currentLevel = math.floor(settings.highlight_level * 100 + 0.5)
            local typedLevel = valuePopup("##level_input", currentLevel, -100, 100)
            if typedLevel ~= currentLevel then settings.highlight_level = typedLevel / 100.0 end

            lockedCheckbox("Flashing", false, "Flash the highlight instead of keeping it solid")

            reaper.ImGui_Unindent(ctx, 20)
        end

        reaper.ImGui_Dummy(ctx, 0, 8)

        heading("Regions", 0xE0BD4BFF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        local changed, newVal = reaper.ImGui_Checkbox(ctx, "Color regions the selected track color", settings.color_regions_track_color)
        if changed then settings.color_regions_track_color = newVal end
        tip("Use the track's color for created regions")

        local changed, newVal = reaper.ImGui_Checkbox(ctx, "Group items when creating regions", settings.group_items)
        if changed then settings.group_items = newVal end
        tip("Automatically group all items within each region")

        if settings.group_items then
            reaper.ImGui_Indent(ctx, 20)
            local changed, newVal = reaper.ImGui_Checkbox(ctx, "Ungroup items on delete", settings.ungroup_on_delete)
            if changed then settings.ungroup_on_delete = newVal end
            tip("When deleting regions, also ungroup any items within those regions")
            reaper.ImGui_Unindent(ctx, 20)
        end

        lockedCheckbox("Delete all regions after rendering", false,
            "Automatically delete all regions after rendering.\n" ..
            "Useful for cleaning up after batch rendering")

        reaper.ImGui_Dummy(ctx, 0, 8)

        heading("Inclusion", 0x45B24BFF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        lockedCheckbox("Child tracks", true, "Include child tracks when calculating region boundaries")
        reaper.ImGui_SameLine(ctx, 250)
        lockedCheckbox("Video items", false, "Include video items when calculating region boundaries")
        lockedCheckbox("Muted tracks", false, "Include muted tracks when calculating region boundaries")
        reaper.ImGui_SameLine(ctx, 250)
        lockedCheckbox("Muted items", false, "Include muted items when calculating region boundaries")

        reaper.ImGui_Dummy(ctx, 0, 8)

        heading("Create Reverb Tails", 0xE6E6E6FF)
        reaper.ImGui_Dummy(ctx, 0, 4)

        lockedCheckbox("Move video items when adding tails", true,
            "When Add Tails shifts stacks apart to make room for reverb tails,\n" ..
            "any video items that overlap a stack will also be moved by the same\n" ..
            "offset as that stack's audio items\n\n" ..
            "Useful when your video items are synced to specific audio stacks and\n" ..
            "you want them to stay in sync after spacing is applied\n\n" ..
            "Note: this is independent of the 'Video items' inclusion setting above")

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
    reaper.ImGui_PopFont(ctx)

    reaper.ImGui_PopStyleVar(ctx, 7)
    reaper.ImGui_PopStyleColor(ctx, 16)
end

function mainLoop()
    if shouldRun then
        drawGui()
        reaper.defer(mainLoop)
    end
end

mainLoop()

