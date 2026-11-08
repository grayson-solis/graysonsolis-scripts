-- @description Add Track (Smart)
-- @author Grayson Solis
-- @version 1.2
-- @about Changes how tracks are added:
  --[[
  - 2 or more selected tracks that are consecutive get placed into a new folder track in same order
  - Nothing selected: adds at the very bottom of track list
  - Non-Folder track selected: adds below it
  - Expanded folder selected: adds inside it (first child)
  - Collapsed folder selected: adds after the entire folder
  ]]

local function get_contiguous_selection()
  local count = reaper.CountSelectedTracks(0)
  if count < 2 then return nil end

  local indices = {}
  for i = 0, count - 1 do
    local tr = reaper.GetSelectedTrack(0, i)
    local num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
    indices[#indices + 1] = num
  end
  table.sort(indices)

  for i = 2, #indices do
    if indices[i] ~= indices[i - 1] + 1 then
      return nil
    end
  end

  return indices
end

local function wrap_in_folder(indices)
  local first_idx = indices[1]
  local last_idx = indices[#indices]

  reaper.InsertTrackAtIndex(first_idx, true)
  local folder_track = reaper.GetTrack(0, first_idx)
  reaper.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)

  local after_group_idx = last_idx + 1 + 1 
  local track_count = reaper.CountTracks(0)

  if after_group_idx <= track_count - 1 then
    local closing_track = reaper.GetTrack(0, after_group_idx)
    local fd = reaper.GetMediaTrackInfo_Value(closing_track, "I_FOLDERDEPTH")
    reaper.SetMediaTrackInfo_Value(closing_track, "I_FOLDERDEPTH", fd - 1)
  end

  return folder_track
end

local function main()
  local group_indices = get_contiguous_selection()
  if group_indices then
    local folder_track = wrap_in_folder(group_indices)
    reaper.SetOnlyTrackSelected(folder_track)
    return
  end

  local sel_track = reaper.GetSelectedTrack(0, 0)
  local new_track
  if not sel_track then
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    new_track = reaper.GetTrack(0, idx)
    reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
  else
    local idx = reaper.GetMediaTrackInfo_Value(sel_track, "IP_TRACKNUMBER") - 1
    local folderdepth = reaper.GetMediaTrackInfo_Value(sel_track, "I_FOLDERDEPTH")
    if folderdepth == 1 then
      local compact = reaper.GetMediaTrackInfo_Value(sel_track, "I_FOLDERCOMPACT")
      if compact ~= 2 then
        reaper.InsertTrackAtIndex(idx + 1, true)
        new_track = reaper.GetTrack(0, idx + 1)
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
      else
        local own_depth = reaper.GetTrackDepth(sel_track)
        local total = reaper.CountTracks(0)
        local insert_idx = total
        for i = idx + 1, total - 1 do
          if reaper.GetTrackDepth(reaper.GetTrack(0, i)) <= own_depth then
            insert_idx = i
            break
          end
        end
        local prev_track  = reaper.GetTrack(0, insert_idx - 1)
        local fd_prev     = reaper.GetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH")
        local depth_after = reaper.GetTrackDepth(prev_track) + fd_prev
        local delta       = own_depth - depth_after
        reaper.InsertTrackAtIndex(insert_idx, true)
        new_track = reaper.GetTrack(0, insert_idx)
        if delta > 0 then
          reaper.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", fd_prev + delta)
          reaper.SetMediaTrackInfo_Value(new_track,  "I_FOLDERDEPTH", -delta)
        else
          reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
        end
      end
    else
      reaper.InsertTrackAtIndex(idx + 1, true)
      new_track = reaper.GetTrack(0, idx + 1)
      if folderdepth < 0 then
        reaper.SetMediaTrackInfo_Value(sel_track, "I_FOLDERDEPTH", 0)
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", folderdepth)
      else
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
      end
    end
  end
  reaper.SetOnlyTrackSelected(new_track)
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Smart Add Track", -1)
reaper.UpdateArrange()
