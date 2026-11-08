local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
if not take then return end

local _, noteCount = reaper.MIDI_CountEvts(take)
local minStart = nil
local maxLen = 0
local notes = {}

for i = 0, noteCount - 1 do
  local _, sel, _, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
  if sel then
    if not minStart or startppq < minStart then minStart = startppq end
    local len = endppq - startppq
    if len > maxLen then maxLen = len end
    notes[#notes+1] = {idx=i}
  end
end

if not minStart then return end

reaper.Undo_BeginBlock()
for _, n in ipairs(notes) do
  reaper.MIDI_SetNote(take, n.idx, nil, nil, minStart, minStart + maxLen, nil, nil, nil, true)
end
reaper.MIDI_Sort(take)
reaper.Undo_EndBlock("Collapse selected notes to chord (extend to longest)", -1)
