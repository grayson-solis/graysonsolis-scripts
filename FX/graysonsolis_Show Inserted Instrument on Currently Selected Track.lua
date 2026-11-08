-- @description Show Last Inserted Instrument on Currently Selected Track
-- @author Grayson Solis
-- @version 1.0
local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowMessageBox("No track selected. Please select a track and try again.", "Error", 0)
  return
end
local _, tname = reaper.GetTrackName(track)
local clean = tname:gsub("%s+", ""):lower()
if clean == "delay" or clean == "reverb" then
  reaper.TrackFX_Show(track, 0, 3)
  return
end
local last_inst = -1
for i = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, name = reaper.TrackFX_GetFXName(track, i, "")
  if name:match("^VSTi:") or name:match("^VST3i:") or name:match("^CLAPi:") then
    last_inst = i
  end
end
if last_inst >= 0 then
  reaper.TrackFX_Show(track, last_inst, 3)
end
