-- @description Move all selected items to project start
-- @author Grayson Solis
-- @version 1.0
-- @about Moves selected items to the start of the project, per track. Spacing between items is kept!

reaper.Undo_BeginBlock()
reaper.SetEditCurPos(0, false, false)
local tracks = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    if not tracks[track] then tracks[track] = {} end
    table.insert(tracks[track], item)
end
for track, items in pairs(tracks) do
    table.sort(items, function(a, b) return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION") end)
    local offset = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
    for _, item in ipairs(items) do
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", reaper.GetMediaItemInfo_Value(item, "D_POSITION") - offset)
    end
end
reaper.UpdateArrange()
reaper.Undo_EndBlock("Move selected items to start", -1)
