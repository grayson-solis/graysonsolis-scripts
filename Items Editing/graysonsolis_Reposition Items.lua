-- @description Reposition Items
-- @author Grayson Solis
-- @version 1.0
-- @about Space items by the amount below ("spacing" variable)! Automatically!

local spacing = 0.5

local function move_env_points(track, old_pos, old_end, delta)
  for ei = 0, reaper.CountTrackEnvelopes(track) - 1 do
    local env = reaper.GetTrackEnvelope(track, ei)
    local changed = false
    for pi = 0, reaper.CountEnvelopePoints(env) - 1 do
      local _, t, v, shape, tension, sel = reaper.GetEnvelopePoint(env, pi)
      if t >= old_pos and t <= old_end then
        reaper.SetEnvelopePoint(env, pi, t + delta, v, shape, tension, sel, true)
        changed = true
      end
    end
    if changed then reaper.Envelope_SortPoints(env) end
  end
end

local function main()
  local move_envs = reaper.GetToggleCommandState(1156) == 1

  local items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end

  local groups, seen = {}, 0
  for _, item in ipairs(items) do
    local gid = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
    if gid == 0 then seen = seen - 1; gid = seen end
    if not groups[gid] then groups[gid] = {} end
    groups[gid][#groups[gid]+1] = item
  end

  local sorted = {}
  for _, g in pairs(groups) do
    local earliest = math.huge
    for _, item in ipairs(g) do
      earliest = math.min(earliest, reaper.GetMediaItemInfo_Value(item, "D_POSITION"))
    end
    sorted[#sorted+1] = {items=g, start=earliest}
  end
  table.sort(sorted, function(a, b) return a.start < b.start end)

  reaper.Undo_BeginBlock()
  for i = 2, #sorted do
    local prev_end = 0
    for _, item in ipairs(sorted[i-1].items) do
      prev_end = math.max(prev_end, reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"))
    end
    local delta = (prev_end + spacing) - sorted[i].start
    for _, item in ipairs(sorted[i].items) do
      local old_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local old_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", old_pos + delta)
      if move_envs then
        move_env_points(reaper.GetMediaItemTrack(item), old_pos, old_pos + old_len, delta)
      end
    end
    sorted[i].start = sorted[i].start + delta
  end
  reaper.Undo_EndBlock("Reposition items with spacing", -1)
  reaper.UpdateArrange()
end
main()
