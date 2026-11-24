-- @name RenderStacks Create Regions Lite
-- @noindex
-- @version 1.1
-- @author Grayson Solis
-- @description Creates renderable regions from track items based on settings script
-- @website https://graysonsolis.com

local scriptPath = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = scriptPath .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local defaultSettings = {
    gap_tolerance = 0.001,
    min_region_length = 0.0,
    color_regions_track_color = true,
    group_items = false,
}

local settings = RenderStacks.loadSettings(defaultSettings)

local selectionCount = reaper.CountSelectedTracks(0)
if selectionCount == 0 then return end

reaper.Undo_BeginBlock()

for i = 0, selectionCount - 1 do
    RenderStacks.rebuild_track_regions(reaper.GetSelectedTrack(0, i), settings)
end

RenderStacks.update_highlight()
RenderStacks.setup_render_window()

reaper.Undo_EndBlock("RenderStacks: Create Regions", -1)
reaper.UpdateArrange()
