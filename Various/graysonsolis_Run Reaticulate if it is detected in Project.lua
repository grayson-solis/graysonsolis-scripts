-- @description Run Reaticulate if it is detected in Project
-- @author Grayson Solis
-- @version 1.0
-- @about Watches the open project for the Reaticulate JSFX and starts Reaticulate once per project
-- (Reaticulate's own Start action does nothing if it is already running)

local INTERVAL = 1.0
local START_SCRIPT = reaper.GetResourcePath() .. "/Scripts/Reaticulate/actions/Reaticulate_Start.lua"

local function track_has_reaticulate(track)
  for _, base in ipairs({ 0, 0x1000000 }) do
    local count = base == 0 and reaper.TrackFX_GetCount(track) or reaper.TrackFX_GetRecCount(track)
    for i = 0, count - 1 do
      local _, name = reaper.TrackFX_GetFXName(track, base + i, "")
      if name:lower():find("reaticulate", 1, true) then return true end
    end
  end
  return false
end

local function project_has_reaticulate(proj)
  if track_has_reaticulate(reaper.GetMasterTrack(proj)) then return true end
  for i = 0, reaper.CountTracks(proj) - 1 do
    if track_has_reaticulate(reaper.GetTrack(proj, i)) then return true end
  end
  return false
end

local launched, scanned = {}, {}
local last_check = -INTERVAL

local function tick()
  local now = reaper.time_precise()
  if now - last_check >= INTERVAL then
    last_check = now
    local proj, path = reaper.EnumProjects(-1)
    local key = tostring(proj) .. "|" .. path
    local state = reaper.GetProjectStateChangeCount(proj)
    if not launched[key] and scanned[key] ~= state then
      scanned[key] = state
      if project_has_reaticulate(proj) then
        launched[key] = true
        local cmd = reaper.AddRemoveReaScript(true, 0, START_SCRIPT, true)
        if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
      end
    end
  end
  reaper.defer(tick)
end

tick()
