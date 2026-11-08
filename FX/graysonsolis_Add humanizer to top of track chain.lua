-- @description Add Humanizer to top of Track Chain
-- @author Grayson Solis
-- @version 1.0
-- @about Inserts the built-in JS humanizer at slot 1 on the selected track’s FX chain.

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then return end

reaper.Undo_BeginBlock()
  local fx = reaper.TrackFX_AddByName(
    tr,
    "JS: Humanizer",
    false, 
    -1     
  )
  if fx >= 0 then
    reaper.TrackFX_CopyToTrack(tr, fx, tr, 0, true)
  end
reaper.Undo_EndBlock("Add JS MIDI Velocity and Timing Humanizer to top", -1)

