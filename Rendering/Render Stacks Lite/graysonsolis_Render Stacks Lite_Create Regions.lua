-- @name RenderStacks Create Regions Lite
-- @noindex
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

function processTrack(track)
    for _, id in ipairs(RenderStacks.rebuild_track_regions(track, settings)) do
        table.insert(newRegionIds, id)
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
