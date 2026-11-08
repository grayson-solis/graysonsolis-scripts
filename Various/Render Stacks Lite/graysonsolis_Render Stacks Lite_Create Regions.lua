-- @name RenderStacks Create Regions Lite
-- @version 1.0
-- @author Grayson Solis
-- @description Creates renderable regions from track items based on settings script
-- @website https://graysonsolis.com

local scriptPath = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = scriptPath .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local defaultSettings = {
    gap_tolerance = 0.01,
    min_region_length = 0.0,
    color_regions_track_color = true,
    fade_other_regions = true,
    fade_percentage = 50,
    group_items = false,
}

local settings = RenderStacks.loadSettings(defaultSettings)
local newRegionIds = {}

function fadeColor(color, fadePct)
    local r = color & 0xFF
    local g = (color >> 8) & 0xFF
    local b = (color >> 16) & 0xFF

    local factor = 1.0 - (fadePct / 100.0)
    r = math.floor(r * factor + 200 * (1 - factor))
    g = math.floor(g * factor + 200 * (1 - factor))
    b = math.floor(b * factor + 200 * (1 - factor))

    return r | (g << 8) | (b << 16)
end

function regionRendersTrack(regionIndex, track)
    local trackIdx = 0

    while true do
        local enumTrack = reaper.EnumRegionRenderMatrix(0, regionIndex, trackIdx)
        if not enumTrack then break end

        if enumTrack == track then
            return true
        end

        trackIdx = trackIdx + 1
    end

    return false
end

function deleteExistingRegionsForTrack(track, trackName)
    local idx = 0
    local escapedName = trackName:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")

    while idx < reaper.CountProjectMarkers(0) do
        local retval, isRegion, pos, regionEnd, name, markerIndex = reaper.EnumProjectMarkers(idx)

        if isRegion and name:match("^" .. escapedName .. "(_?%d*)$") and regionRendersTrack(markerIndex, track) then
            reaper.DeleteProjectMarker(0, markerIndex, true)
        else
            idx = idx + 1
        end
    end
end

function getRegionColor(track, stackIndex)
    if settings.color_regions_track_color then
        return RenderStacks.get_track_color(track)
    else
        return 0
    end
end

function getRegionName(baseName, index)
    if index == 0 then
        return baseName
    end

    return baseName .. "_" .. index
end

function getNextGroupId()
    local maxGroup = 0

    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local groupId = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
        if groupId > maxGroup then
            maxGroup = groupId
        end
    end

    return maxGroup + 1
end

function processTrack(track)
    if RenderStacks.isActuallyMuted(track) then
        return
    end

    local retval, parentName = reaper.GetTrackName(track, "")
    parentName = parentName:gsub("<.->", "")

    deleteExistingRegionsForTrack(track, parentName)

    local allItems = RenderStacks.gather_all_items(track)
    local stacks = RenderStacks.detect_stacks(allItems, settings.gap_tolerance)

    local validCount = 0

    for stackIdx, stack in ipairs(stacks) do
        local stackStart = math.huge
        local stackEnd = 0

        for _, item in ipairs(stack) do
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            stackStart = math.min(stackStart, pos)
            stackEnd = math.max(stackEnd, pos + len)
        end

        local regionLength = stackEnd - stackStart

        if regionLength >= settings.min_region_length and stackStart < stackEnd then
            local regionName = getRegionName(parentName, validCount)
            local regionColor = getRegionColor(track, stackIdx)

            local regionId = reaper.AddProjectMarker(0, true, stackStart, stackEnd, regionName, -1)
            reaper.SetProjectMarker3(0, regionId, true, stackStart, stackEnd, regionName, regionColor)
            reaper.SetRegionRenderMatrix(0, regionId, track, 1)

            if settings.group_items then
                local groupId = getNextGroupId()
                RenderStacks.group_items_with_id(stack, groupId)
            end

            table.insert(newRegionIds, regionId)
            validCount = validCount + 1
        end
    end
end

function fadeAllOtherRegions()
    if not settings.fade_other_regions then
        return
    end

    local newRegions = {}
    for _, id in ipairs(newRegionIds) do
        newRegions[id] = true
    end

    local idx = 0

    while idx < reaper.CountProjectMarkers(0) do
        local retval, isRegion, pos, regionEnd, name, markerIndex, color = reaper.EnumProjectMarkers3(0, idx)

        if isRegion and not newRegions[markerIndex] then
            local fadedColor = fadeColor(color, settings.fade_percentage)
            reaper.SetProjectMarker3(0, markerIndex, true, pos, regionEnd, name, fadedColor)
        end

        idx = idx + 1
    end
end

local selectionCount = reaper.CountSelectedTracks(0)
if selectionCount == 0 then return end

reaper.Undo_BeginBlock()

newRegionIds = {}

for i = 0, selectionCount - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    processTrack(track)
end

fadeAllOtherRegions()
RenderStacks.update_highlight()

reaper.Undo_EndBlock("RenderStacks: Create Regions", -1)
reaper.UpdateArrange()
