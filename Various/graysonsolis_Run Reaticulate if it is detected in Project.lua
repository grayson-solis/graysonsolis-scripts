-- @description Run Reaticulate if it is detected in Project
-- @author Grayson Solis
-- @version 1.1
-- @about Watches the open project for the Reaticulate JSFX and starts Reaticulate once per project

local INTERVAL, VERIFY_DELAY, MAX_TRIES = 1.0, 10.0, 3
local START_SCRIPT = reaper.GetResourcePath() .. "/Scripts/Reaticulate/actions/Reaticulate_Start.lua"

local function fx_has_reaticulate(track, idx)
  local _, name = reaper.TrackFX_GetFXName(track, idx, "")
  if name:lower():find("reaticulate", 1, true) then return true end
  local ok, count = reaper.TrackFX_GetNamedConfigParm(track, idx, "container_count")
  if ok then
    for c = 0, tonumber(count) - 1 do
      local _, sub = reaper.TrackFX_GetNamedConfigParm(track, idx, "container_item." .. c)
      if fx_has_reaticulate(track, tonumber(sub)) then return true end
    end
  end
  return false
end

local function track_has_reaticulate(track)
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    if fx_has_reaticulate(track, i) then return true end
  end
  for i = 0, reaper.TrackFX_GetRecCount(track) - 1 do
    if fx_has_reaticulate(track, 0x1000000 + i) then return true end
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

local launched, scanned, tries = {}, {}, {}
local pending
local last_check = -INTERVAL

local function launch(key)
  launched[key] = true
  tries[key] = (tries[key] or 0) + 1
  reaper.DeleteExtState("reaticulate", "pong", false)
  local cmd = reaper.AddRemoveReaScript(true, 0, START_SCRIPT, true)
  if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
  pending = { key = key, at = reaper.time_precise() + VERIFY_DELAY }
end

local function verify(now)
  if not pending.token then
    pending.token = tostring(now)
    pending.at = now + 1
    reaper.SetExtState("reaticulate", "command", "ping=" .. pending.token, false)
    return
  end
  if reaper.GetExtState("reaticulate", "pong") ~= pending.token and tries[pending.key] < MAX_TRIES then
    launched[pending.key] = nil
    scanned[pending.key] = nil
  end
  pending = nil
end

local function tick()
  local now = reaper.time_precise()
  if pending and now >= pending.at then verify(now) end
  if now - last_check >= INTERVAL then
    last_check = now
    local proj, path = reaper.EnumProjects(-1)
    local key = tostring(proj) .. "|" .. path
    local state = reaper.GetProjectStateChangeCount(proj)
    if not launched[key] and scanned[key] ~= state then
      scanned[key] = state
      if project_has_reaticulate(proj) then launch(key) end
    end
  end
  reaper.defer(tick)
end

tick()
