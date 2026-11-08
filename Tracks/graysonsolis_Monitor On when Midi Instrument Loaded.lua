-- @description Monitor On when Midi Instrument Loaded
-- @author Grayson Solis
-- @version 1.0
-- @about Keeps Record Monitoring on for any track with a VSTi loaded. Bind as a global startup action!!!

function check_monitor()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.TrackFX_GetInstrument(tr) ~= -1 and reaper.GetMediaTrackInfo_Value(tr, "I_RECMON") ~= 1 then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
    end
  end
  reaper.defer(check_monitor)
end

check_monitor()
