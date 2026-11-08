local item = reaper.GetSelectedMediaItem(0, 0)
local take = item and reaper.GetActiveTake(item)

if not take then
  local editor = reaper.MIDIEditor_GetActive()
  if editor then
    take = reaper.MIDIEditor_GetTake(editor)
    item = take and reaper.GetMediaItemTake_Item(take)
  end
end

if not take or not item then return end

local melodyShift = math.floor(reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH") + 0.5)

local chordTracks = {}
for i = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, i)
  for j = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(track, j, "")
    if fxName:find("Chord Track Marker") then
      table.insert(chordTracks, track)
    end
  end
end

if #chordTracks == 0 then return end

reaper.Undo_BeginBlock()

local _, cnt = reaper.MIDI_CountEvts(take)
local noteGroups = {}

for i = 0, cnt - 1 do
  local _, sel, mute, sppq, eppq, ch, pitch, vel = reaper.MIDI_GetNote(take, i)
  if sel and not mute then
    if not noteGroups[sppq] then noteGroups[sppq] = {} end
    table.insert(noteGroups[sppq], {sppq=sppq, eppq=eppq, ch=ch, pitch=pitch, vel=vel})
  end
end

for sppq, notes in pairs(noteGroups) do
  local lowestNote = notes[1]
  for _, note in ipairs(notes) do
    if note.pitch < lowestNote.pitch then lowestNote = note end
  end
  
  local noteTime = reaper.MIDI_GetProjTimeFromPPQPos(take, lowestNote.sppq)
  local allChordStarts = {}
  
  for _, chordTrack in ipairs(chordTracks) do
    for j = 0, reaper.CountTrackMediaItems(chordTrack) - 1 do
      local chordItem = reaper.GetTrackMediaItem(chordTrack, j)
      local chordTake = reaper.GetActiveTake(chordItem)
      if chordTake and reaper.TakeIsMIDI(chordTake) then
        local pitchShift = math.floor(reaper.GetMediaItemTakeInfo_Value(chordTake, "D_PITCH") + 0.5) - melodyShift
        local _, noteCnt = reaper.MIDI_CountEvts(chordTake)
        for k = 0, noteCnt - 1 do
          local _, _, m, s, _, _, p = reaper.MIDI_GetNote(chordTake, k)
          if not m then
            local t1 = reaper.MIDI_GetProjTimeFromPPQPos(chordTake, s)
            if t1 <= noteTime then
              if not allChordStarts[t1] then allChordStarts[t1] = {} end
              table.insert(allChordStarts[t1], p + pitchShift)
            end
          end
        end
      end
    end
  end
  
  local sortedStarts = {}
  for t, _ in pairs(allChordStarts) do
    table.insert(sortedStarts, t)
  end
  table.sort(sortedStarts, function(a, b) return a > b end)
  
  local chordPitchClasses = {}
  if #sortedStarts > 0 then
    local latestTime = sortedStarts[1]
    for t, pitches in pairs(allChordStarts) do
      if math.abs(t - latestTime) < 0.15 then
        for _, p in ipairs(pitches) do
          chordPitchClasses[p % 12] = true
        end
      end
    end
  end
  
  local melodyPC = lowestNote.pitch % 12
  local firstHarmony = nil
  local secondHarmony = nil
  
  for distance = 1, 24 do
    local testPitch = lowestNote.pitch - distance
    if testPitch >= 0 then
      local testPC = testPitch % 12
      if chordPitchClasses[testPC] and testPC ~= melodyPC then
        if not firstHarmony then
          firstHarmony = testPitch
        else
          secondHarmony = testPitch
          break
        end
      end
    end
  end
  
  if not secondHarmony and firstHarmony then
    for distance = 1, 24 do
      local testPitch = lowestNote.pitch - distance
      if testPitch >= 0 and chordPitchClasses[testPitch % 12] and testPitch ~= firstHarmony then
        secondHarmony = testPitch
        break
      end
    end
  end
  
  if secondHarmony then
    reaper.MIDI_InsertNote(take, false, false, lowestNote.sppq, lowestNote.eppq, lowestNote.ch, secondHarmony, lowestNote.vel, false)
  end
end

reaper.MIDI_Sort(take)
reaper.UpdateItemInProject(item)
reaper.Undo_EndBlock("Add Harmony Below Skip", -1)
