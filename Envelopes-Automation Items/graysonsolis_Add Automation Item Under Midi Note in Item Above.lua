--[[
@ description Add Automation Under Midi Note in Item Above
@author Grayson Solis
@version 1.0
@about Add an Automation item of the length of the current note in the item above your mouse cursor
]]

local x, y = reaper.GetMousePosition()

local item, take
for offset = 1, 500 do
    item, take = reaper.GetItemFromPoint(x, y - offset, true)
    if item and take and reaper.TakeIsMIDI(take) then break end
end
if not item or not take then return end

local env = reaper.GetSelectedEnvelope(0)
if not env then return end

local envTrack = reaper.Envelope_GetParentTrack(env)
local itemTrack = reaper.GetMediaItem_Track(item)
if envTrack ~= itemTrack then return end

reaper.BR_GetMouseCursorContext()
local time_at_mouse = reaper.BR_GetMouseCursorContext_Position()
if not time_at_mouse or time_at_mouse < 0 then return end

local ppq_at_mouse = reaper.MIDI_GetPPQPosFromProjTime(take, time_at_mouse)

local _, note_count = reaper.MIDI_CountEvts(take)
local best_start_ppq, best_end_ppq = nil, nil

for i = 0, note_count - 1 do
    local _, _, _, start_ppq, end_ppq = reaper.MIDI_GetNote(take, i)
    if start_ppq <= ppq_at_mouse and end_ppq >= ppq_at_mouse then
        local len_ppq = end_ppq - start_ppq
        local best_len = best_end_ppq and (best_end_ppq - best_start_ppq) or -1
        if len_ppq > best_len then
            best_start_ppq = start_ppq
            best_end_ppq = end_ppq
        end
    end
end

if not best_start_ppq then return end

local note_start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, best_start_ppq)
local note_end_time   = reaper.MIDI_GetProjTimeFromPPQPos(take, best_end_ppq)

reaper.Undo_BeginBlock()
reaper.InsertAutomationItem(env, -1, note_start_time, note_end_time - note_start_time)
reaper.Undo_EndBlock("Create automation item from MIDI note length", -1)
