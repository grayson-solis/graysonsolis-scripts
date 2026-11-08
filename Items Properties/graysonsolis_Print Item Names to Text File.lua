local function items_in_order(track)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    items[#items+1] = reaper.GetTrackMediaItem(track, i)
  end
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)
  local names = {}
  for _, item in ipairs(items) do
    local take = reaper.GetActiveTake(item)
    names[#names+1] = take and reaper.GetTakeName(take) or "(no take)"
  end
  return names
end

local lines = {}
for t = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, t)
  local _, track_name = reaper.GetTrackName(track)
  local names = items_in_order(track)

  lines[#lines+1] = track_name
  if #names == 0 then
    lines[#lines+1] = "    (no items)"
  else
    for i, name in ipairs(names) do
      lines[#lines+1] = "    " .. i .. ". " .. name
    end
  end
  lines[#lines+1] = ""
end

local path = reaper.GetProjectPath("") .. "/track_items.txt"
local f = io.open(path, "w")
f:write(table.concat(lines, "\n"))
f:close()

reaper.ShowMessageBox("Saved to:\n" .. path, "Done", 0)
