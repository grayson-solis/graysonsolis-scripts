-- @name RenderStacks Delete Selected Track Regions Lite
-- @noindex
-- @version 1.1
-- @author Grayson Solis
-- @description Deletes regions only from selected tracks

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local default_settings = {
    ungroup_on_delete = false,
    group_items = false,
}
local settings = RenderStacks.loadSettings(default_settings)

local count_sel = reaper.CountSelectedTracks(0)
if count_sel == 0 then
    return
end

reaper.Undo_BeginBlock()

local tracks = {}
for i = 0, count_sel - 1 do tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i) end

local deleted_count = RenderStacks.delete_track_regions(tracks, settings.ungroup_on_delete and settings.group_items)

RenderStacks.update_highlight()

reaper.Undo_EndBlock("RenderStacks: Delete Regions from Selected Tracks", -1)

if deleted_count > 0 then
    reaper.UpdateArrange()
end
