-- @description Monitor On and Change to MIDI Input when MIDI Instrument Loaded
-- @author Grayson Solis
-- @version 1.0

local last_time = reaper.time_precise()
local track_has_inst = {} 
local track_input_type = {} 

local MIDI_ALL = 4096 + 0 + (63 << 5)

function check_monitor()
  local current_time = reaper.time_precise()
  if current_time - last_time < 1 then
    reaper.defer(check_monitor)
    return
  end
  last_time = current_time
  
  local trackCount = reaper.CountTracks(0)
  
  for i = 0, trackCount - 1 do
    local tr = reaper.GetTrack(0, i)
    local guid = reaper.GetTrackGUID(tr)
    local inst = reaper.TrackFX_GetInstrument(tr)
    local has_inst = (inst ~= -1)
    local current_input = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
    
    local input_type
    if current_input >= 4096 then
      input_type = "midi"
    else
      input_type = "audio"  
    end

    if has_inst and not track_has_inst[guid] then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
      reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", MIDI_ALL)
    end
    
    local last_input_type = track_input_type[guid]
    if last_input_type == "midi" and input_type == "audio" then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 0)
    end
    
    if last_input_type == "audio" and input_type == "midi" then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
    end
    
    track_has_inst[guid] = has_inst
    track_input_type[guid] = input_type
  end
  
  reaper.defer(check_monitor)
end

check_monitor()
