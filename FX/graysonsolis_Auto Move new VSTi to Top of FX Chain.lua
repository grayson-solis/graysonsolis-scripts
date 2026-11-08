--[[
@description Auto Arrange FX Chain
@version 1.0
@author Grayson Solis
@about
  Enforces FX chain order on all tracks every second:
    1. Prioritize midi fx (Humanizer, Swing Thing, Reaticulate,
       ReaControlMIDI, MB Note Quantize, note_quantizer) FIRST, in any order amongst themselves
    2. VST instruments directly after in order added
    3. All other FX: after instruments, in their original order
]]

local PRIORITY_PATTERNS = {
  "MIDI Velocity and Timing Humanizer",
  "Humanizer",
  "Swing Thing",
  "Reaticulate",
  "ReaControlMIDI",
  "MB Note Quantize",
  "note_quantizer",
  "Keytracker",
  "Humanizer Pro",
  "NAD Global MIDI Swing",
  "Swing",
}

local function is_priority(name)
  for _, pat in ipairs(PRIORITY_PATTERNS) do
    if name:find(pat, 1, true) then return true end
  end
  return false
end


local function is_instrument(name)
  return name:match("^VSTi:")  ~= nil
      or name:match("^VST3i:") ~= nil
      or name:match("^AUi:")   ~= nil
end

local function process_track(tr)
  local count = reaper.TrackFX_GetCount(tr)
  if count < 2 then return end

  local priority_list, instrument_list, other_list = {}, {}, {}
  for i = 0, count - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, i, "")
    local guid     = reaper.TrackFX_GetFXGUID(tr, i)
    local entry    = { guid = guid }
    if is_priority(name) then
      table.insert(priority_list,   entry)
    elseif is_instrument(name) then
      table.insert(instrument_list, entry)
    else
      table.insert(other_list,      entry)
    end
  end

  if #instrument_list == 0 then return end

  local desired = {}
  for _, e in ipairs(priority_list)   do table.insert(desired, e.guid) end
  for _, e in ipairs(instrument_list) do table.insert(desired, e.guid) end
  for _, e in ipairs(other_list)      do table.insert(desired, e.guid) end

  local already_ok = true
  for pos, guid in ipairs(desired) do
    if reaper.TrackFX_GetFXGUID(tr, pos - 1) ~= guid then
      already_ok = false
      break
    end
  end
  if already_ok then return end

  reaper.PreventUIRefresh(1)
  for target_pos = 0, #desired - 1 do
    local want_guid = desired[target_pos + 1]
    for cur_pos = 0, reaper.TrackFX_GetCount(tr) - 1 do
      if reaper.TrackFX_GetFXGUID(tr, cur_pos) == want_guid then
        if cur_pos ~= target_pos then
          reaper.TrackFX_CopyToTrack(tr, cur_pos, tr, target_pos, true)
        end
        break
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
end

local last_time = reaper.time_precise()

local function auto_reposition()
  if reaper.time_precise() - last_time >= 1 then
    last_time = reaper.time_precise()
    for ti = 0, reaper.CountTracks(0) - 1 do
      process_track(reaper.GetTrack(0, ti))
    end
  end
  reaper.defer(auto_reposition)
end

auto_reposition()
