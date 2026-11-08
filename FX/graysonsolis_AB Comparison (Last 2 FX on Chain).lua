-- @description A/B Compare Last Two FX on Selected Track
-- @author Grayson
-- @version 1.0
-- @about Toggles bypass between the last two FX in the selected tracks FX chain

local track = reaper.GetSelectedTrack(0, 0)
if track then
  local n = reaper.TrackFX_GetCount(track)
  if n >= 2 then
    local a, b = n - 2, n - 1
    local benabled = reaper.TrackFX_GetEnabled(track, b)
    reaper.TrackFX_SetEnabled(track, b, not benabled)
    reaper.TrackFX_SetEnabled(track, a, benabled)
  end
end

