-- @name RenderStacks Delete Selected Track Regions Lite
-- @noindex
-- @version 1.0
-- @author Grayson Solis
-- @description Deletes regions only from selected tracks

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;" .. package.path
local RenderStacks = require("graysonsolis_Render Stacks Lite_Core")

local default_settings = {
    ungroup_on_delete = false,
}
local settings = RenderStacks.loadSettings(default_settings)

local count_sel = reaper.CountSelectedTracks(0)
if count_sel == 0 then
    return
end

reaper.Undo_BeginBlock()

local track_names = {}
local tracks = {}
for i = 0, count_sel - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local retval, name = reaper.GetTrackName(track, "")
    name = name:gsub("<.->", "")
    track_names[name] = true
    tracks[name] = track
end

local i = 0
local deleted_count = 0

while i < reaper.CountProjectMarkers(0) do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)

    if isrgn then
        local should_delete = false
        local matching_track = nil

        for track_name, _ in pairs(track_names) do
            local escaped_name = track_name:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
            if name:match("^" .. escaped_name .. "(_?%d*)$") then
                should_delete = true
                matching_track = tracks[track_name]
                break
            end
        end

        if should_delete then
            if settings.ungroup_on_delete and matching_track then
                local items = RenderStacks.get_items_in_time_range(matching_track, pos, rgnend, true)
                RenderStacks.ungroup_items_in_stack(items)
            end

            reaper.DeleteProjectMarker(0, markrgnindexnumber, true)
            deleted_count = deleted_count + 1
        else
            i = i + 1
        end
    else
        i = i + 1
    end
end

RenderStacks.update_highlight()

reaper.Undo_EndBlock("RenderStacks: Delete Regions from Selected Tracks", -1)

if deleted_count > 0 then
    reaper.UpdateArrange()
end
