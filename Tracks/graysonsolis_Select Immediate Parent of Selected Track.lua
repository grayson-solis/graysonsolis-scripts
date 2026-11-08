-- @description Select Immediate Parent of Selected Track
-- @author Grayson Solis
-- @version 1.0

local track = reaper.GetSelectedTrack(0, 0)
if track then
  local parent = reaper.GetParentTrack(track)
  if parent then
    reaper.SetOnlyTrackSelected(parent)
  end
end

