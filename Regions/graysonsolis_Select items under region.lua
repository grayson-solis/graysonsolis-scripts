-- @description Select items under region
-- @author Grayson Solis
-- @version 1.0
-- @description Select items in the region under the mouse (options show when items overlap the region borders)
local TOL = 0.01

reaper.BR_GetMouseCursorContext()
local pos = reaper.BR_GetMouseCursorContext_Position()
if pos < 0 then pos = reaper.GetCursorPosition() end
local _, rgn_idx = reaper.GetLastMarkerAndCurRegion(0, pos)
if rgn_idx < 0 then return end
local _, _, rs, re = reaper.EnumProjectMarkers(rgn_idx)

local function reg(i)
    local m, v = reaper.GetRegionOrMarker(0, i, ""), reaper.GetRegionOrMarkerInfo_Value
    return v(0, m, "B_ISREGION") ~= 0 and v(0, m, "B_UISEL") ~= 0, v(0, m, "D_STARTPOS"), v(0, m, "D_ENDPOS")
end

local n, grew = reaper.GetNumRegionsOrMarkers(0), false
for i = 0, n - 1 do
    local ok, s, e = reg(i)
    if ok and math.abs(s - rs) < TOL and math.abs(e - re) < TOL then grew = true end
end
while grew do
    grew = false
    for i = 0, n - 1 do
        local ok, s, e = reg(i)
        if ok then
            if math.abs(s - re) < TOL and e > re then re = e; grew = true
            elseif math.abs(e - rs) < TOL and s < rs then rs = s; grew = true end
        end
    end
end

local function bounds(it)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    return p, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
end

local items, cut, orig = {}, {}, {}
for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local s, e = bounds(it)
    if s < re - TOL and e > rs + TOL then
        items[#items + 1] = it
        if s < rs - TOL or e > re + TOL then
            cut[#cut + 1] = it
            orig[it] = reaper.GetMediaItemInfo_Value(it, "I_CUSTOMCOLOR")
        end
    end
end

local prev_sel = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do prev_sel[i + 1] = reaper.GetSelectedMediaItem(0, i) end

reaper.SelectAllMediaItems(0, false)
for _, it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
reaper.UpdateArrange()
if #cut == 0 then return end

local function lerp(c, t)
    local r, g, b = c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF
    return math.floor(r + (255 - r) * t) | (math.floor(g + (255 - g) * t) << 8) | (math.floor(b + (255 - b) * t) << 16)
end

local base = {}
for _, it in ipairs(cut) do
    local c = reaper.GetDisplayedMediaItemColor(it) & 0xFFFFFF
    base[it] = c == 0 and 0x808080 or c
end

local function restore()
    for it, c in pairs(orig) do
        if reaper.ValidatePtr(it, "MediaItem*") then reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", c) end
    end
    reaper.UpdateArrange()
end

local function skip()
    for _, it in ipairs(cut) do reaper.SetMediaItemSelected(it, false) end
    reaper.UpdateArrange()
end

local function cancel()
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(prev_sel) do
        if reaper.ValidatePtr(it, "MediaItem*") then reaper.SetMediaItemSelected(it, true) end
    end
    reaper.UpdateArrange()
end

local function split()
    reaper.Undo_BeginBlock()
    for _, it in ipairs(cut) do
        local s = bounds(it)
        local mid = it
        if s < rs - TOL then
            mid = reaper.SplitMediaItem(it, rs)
            reaper.SetMediaItemSelected(it, false)
        end
        if mid and select(2, bounds(mid)) > re + TOL then
            local tail = reaper.SplitMediaItem(mid, re)
            if tail then reaper.SetMediaItemSelected(tail, false) end
        end
    end
    reaper.Undo_EndBlock("Split items at region bounds", -1)
    reaper.UpdateArrange()
end

local ctx = reaper.ImGui_CreateContext("Select in region")
local mx, my = reaper.GetMousePosition()
mx = mx + (re - pos) * reaper.GetHZoomLevel()
if reaper.JS_Window_FindChildByID then
    local arr = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
    local _, _, _, r = reaper.JS_Window_GetClientRect(arr)
    mx = math.min(mx, r - 260)
end
mx, my = reaper.ImGui_PointConvertNative(ctx, mx, my, false)
local new_api = (tonumber(select(3, reaper.ImGui_GetVersion()):match("^%d+%.(%d+)")) or 0) >= 10
local bold
if new_api then
    bold = reaper.ImGui_CreateFont("sans-serif", reaper.ImGui_FontFlags_Bold())
else
    bold = reaper.ImGui_CreateFont("sans-serif", 14, reaper.ImGui_FontFlags_Bold())
    reaper.ImGui_Attach(ctx, bold)
end
reaper.atexit(restore)

local function color_button(label, w, text)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text)
    if new_api then reaper.ImGui_PushFont(ctx, bold, 14) else reaper.ImGui_PushFont(ctx, bold) end
    local clicked = reaper.ImGui_Button(ctx, label, w, 28)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, 1)
    return clicked
end

local function loop()
    local t = (math.sin(reaper.time_precise() * 8) + 1) / 2 * 0.7
    for _, it in ipairs(cut) do
        if reaper.ValidatePtr(it, "MediaItem*") then
            reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", lerp(base[it], t) | 0x1000000)
        end
    end
    reaper.UpdateArrange()

    reaper.ImGui_SetNextWindowPos(ctx, mx + 12, my + 12, reaper.ImGui_Cond_Appearing())
    local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoSavedSettings()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 14, 12)
    local vis, open = reaper.ImGui_Begin(ctx, "Split items?", true, flags)
    local choice
    if vis then
        local msg = #cut .. (#cut == 1 and " item extends" or " items extend") .. " past region."
        local w = reaper.ImGui_CalcTextSize(ctx, msg)
        reaper.ImGui_Text(ctx, msg)
        reaper.ImGui_Spacing(ctx)
        if color_button("Exclude", w, 0xFF5C4DFF) then choice = "skip" end
        if color_button("Cut at edges", w, 0xFFC83DFF) then choice = "split" end
        if color_button("Include", w, 0x40D9B4FF) then choice = "select" end
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)

    if choice or not open then
        restore()
        if choice == "split" then split()
        elseif choice == "skip" then skip()
        elseif not choice then cancel() end
        return
    end
    reaper.defer(loop)
end
loop()

