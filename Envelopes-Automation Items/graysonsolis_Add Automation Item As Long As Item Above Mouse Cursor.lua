--[[
@ description Add Automation Item As Long As Item Above Mouse Cursor
@author Grayson Solis
@version 1.0
@about Add an automation item of the length of the current item above the mouse cursor
]]

local x, y = reaper.GetMousePosition()
local item, _ = reaper.GetItemFromPoint(x, y - 1, true)

if not item then
    for offset = 2, 200 do
        item, _ = reaper.GetItemFromPoint(x, y - offset, true)
        if item then break end
    end
end

if not item then return end

local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
local track = reaper.GetMediaItem_Track(item)

local env = reaper.GetSelectedEnvelope(0)
if not env then return end

local envTrack = reaper.Envelope_GetParentTrack(env)
if envTrack ~= track then return end

reaper.Undo_BeginBlock()
reaper.InsertAutomationItem(env, -1, pos, len)
reaper.Undo_EndBlock("Create automation item from item above", -1)
