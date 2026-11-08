-- @description Unselect Topmost Track in Selection
-- @author Grayson Solis
-- @version 1.0

if reaper.CountSelectedTracks(0) > 1 then
    local topmostTrack = reaper.GetSelectedTrack(0, 0)
    local topmostTrack = reaper.GetSelectedTrack(0, 0)
    reaper.SetTrackSelected(topmostTrack, false)
end
