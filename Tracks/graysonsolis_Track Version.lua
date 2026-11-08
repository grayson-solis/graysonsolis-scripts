reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local orig = reaper.GetSelectedTrack(0, 0)
if not orig then return end

local orig_idx = reaper.GetMediaTrackInfo_Value(orig, "IP_TRACKNUMBER") - 1

reaper.Main_OnCommand(40057, 0)

local track_count = reaper.CountTracks(0)
local last_track = reaper.GetTrack(0, track_count - 1)
reaper.SetOnlyTrackSelected(last_track)
reaper.Main_OnCommand(40058, 0)

reaper.ReorderSelectedTracks(orig_idx, 0)

local dup = reaper.GetTrack(0, orig_idx)
if dup then
  local is_dup_folder = reaper.GetMediaTrackInfo_Value(dup, "I_FOLDERDEPTH") == 1
  if is_dup_folder then
    reaper.SetMediaTrackInfo_Value(dup, "I_FOLDERCOMPACT", 2)
  end
end

local _, name = reaper.GetSetMediaTrackInfo_String(dup, "P_NAME", "", false)
local base = name:match("^(.-)%s*v%d+$") or name
local version = 1
local parent = reaper.GetParentTrack(orig)
for i = 0, reaper.CountTracks(0) - 1 do
  local t = reaper.GetTrack(0, i)
  if reaper.GetParentTrack(t) == parent then
    local _, tname = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
    local b, v = tname:match("^(.-)%s*v(%d+)$")
    if b == base then
      local vi = tonumber(v)
      if vi and vi >= version then version = vi + 1 end
    end
  end
end
reaper.GetSetMediaTrackInfo_String(dup, "P_NAME", base .. " v" .. version, true)
reaper.SetMediaTrackInfo_Value(dup, "B_MUTE", 1)
reaper.SetMediaTrackInfo_Value(dup, "I_HEIGHTOVERRIDE", 24)
reaper.SetMediaTrackInfo_Value(dup, "B_HEIGHTLOCK", 1)
reaper.TrackList_AdjustWindows(false)

local function delete_versioned_children(parent)
  local _, pname = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
  if not pname:match("v%d+$") then return end
  local p_depth = reaper.GetTrackDepth(parent)
  local p_idx = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
  for i = reaper.CountTracks(0) - 1, p_idx, -1 do
    local t = reaper.GetTrack(0, i)
    if reaper.GetTrackDepth(t) <= p_depth then break end
    local _, cn = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
    if cn:match("v%d+$") then reaper.DeleteTrack(t) end
  end
end
delete_versioned_children(dup)

local function delete_nested_versions(parent)
  local p_depth = reaper.GetTrackDepth(parent)
  local p_idx = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER") - 1
  local total = reaper.CountTracks(0)
  local i = p_idx + 1
  while i < total do
    local t = reaper.GetTrack(0, i)
    local t_depth = reaper.GetTrackDepth(t)
    if t_depth <= p_depth then break end
    local _, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
    local depth_val = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    if depth_val == 1 and name:match("v%d+$") then
      local j = i + 1
      while j < total do
        local sub_t = reaper.GetTrack(0, j)
        if reaper.GetTrackDepth(sub_t) <= t_depth then break end
        j = j + 1
      end
      for del_i = j - 1, i, -1 do
        reaper.DeleteTrack(reaper.GetTrack(0, del_i))
      end
      total = reaper.CountTracks(0)
      i = i - 1
    end
    i = i + 1
  end
end
delete_nested_versions(dup)

reaper.SetOnlyTrackSelected(orig)
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("graysonsolis_Track_Versions", -1)

