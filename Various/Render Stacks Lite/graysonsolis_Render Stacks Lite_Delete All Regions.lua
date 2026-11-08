-- @name RenderStacks Delete All Regions Lite
-- @version 1.0
-- @author Grayson Solis
-- @description Deletes all regions in the project
-- @website https://graysonsolis.com

local scriptPath = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = scriptPath .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local defaultSettings = {
    ungroup_on_delete = false,
}

local settings = RenderStacks.loadSettings(defaultSettings)

reaper.Undo_BeginBlock()

local regionsToUngroup = {}

if settings.ungroup_on_delete then
    local idx = 0

    while idx < reaper.CountProjectMarkers(0) do
        local retval, isRegion, pos, regionEnd, name, markerIndex = reaper.EnumProjectMarkers(idx)

        if isRegion then
            table.insert(regionsToUngroup, {
                startPos = pos,
                endPos = regionEnd,
                name = name
            })
        end

        idx = idx + 1
    end

    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)

        for _, regionInfo in ipairs(regionsToUngroup) do
            local items = RenderStacks.get_items_in_time_range(
                track,
                regionInfo.startPos,
                regionInfo.endPos,
                false
            )
            RenderStacks.ungroup_items_in_stack(items)
        end
    end
end

local idx = reaper.CountProjectMarkers(0) - 1
while idx >= 0 do
    local retval, isRegion, pos, regionEnd, name, markerIndex = reaper.EnumProjectMarkers(idx)
    if isRegion then
        reaper.DeleteProjectMarker(0, markerIndex, true)
    end
    idx = idx - 1
end

RenderStacks.update_highlight()

reaper.Undo_EndBlock("RenderStacks: Delete All Regions", -1)
reaper.UpdateArrange()
