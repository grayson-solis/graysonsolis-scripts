-- @description Select All Tracks (Ignore Collapsed State)
-- @author Grayson Solis
-- @version 1.0
-- @about Selects every track, including collapsed ones.

reaper.PreventUIRefresh(1)
for i = 0, reaper.CountTracks(0) - 1 do
  reaper.SetTrackSelected(reaper.GetTrack(0, i), true)
end
reaper.PreventUIRefresh(-1)
