-- @description Snap selected item edges to barlines (content stays in place)
-- @version 1.0
-- @author Grayson Solis
-- @about
--   Trims the edges of selected midi items to the nearest barline and resolves
--   slight overlaps or gaps between neighbouring items on the same track
--   Items are never split nor moved, so notes keep their positions

local TOL = 0.25

local function qn(t) return reaper.TimeMap2_timeToQN(0, t) end

local function snap(t)
  local _, m = reaper.TimeMap2_timeToBeats(0, t)
  local a, b = reaper.TimeMap2_beatsToTime(0, 0, m), reaper.TimeMap2_beatsToTime(0, 0, m + 1)
  local bar = math.abs(qn(t) - qn(a)) <= math.abs(qn(t) - qn(b)) and a or b
  return math.abs(qn(bar) - qn(t)) <= TOL and bar or t
end

local tracks = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  local tk = reaper.GetActiveTake(it)
  if tk and reaper.TakeIsMIDI(tk) then
    local tr = reaper.GetMediaItemTrack(it)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    tracks[tr] = tracks[tr] or {}
    table.insert(tracks[tr], { it = it, tk = tk, s = s, e = e, ns = snap(s), ne = snap(e) })
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, list in pairs(tracks) do
  table.sort(list, function(a, b) return a.s < b.s end)
  for i = 2, #list do
    local p, c = list[i - 1], list[i]
    if math.abs(qn(p.e) - qn(c.s)) <= TOL then
      local b = snap(c.s)
      p.ne, c.ns = b, b
    end
  end
  for _, x in ipairs(list) do
    if x.ne > x.ns then
      local offs = reaper.GetMediaItemTakeInfo_Value(x.tk, "D_STARTOFFS")
      local rate = reaper.GetMediaItemTakeInfo_Value(x.tk, "D_PLAYRATE")
      reaper.SetMediaItemTakeInfo_Value(x.tk, "D_STARTOFFS", offs + (x.ns - x.s) * rate)
      reaper.SetMediaItemInfo_Value(x.it, "D_POSITION", x.ns)
      reaper.SetMediaItemInfo_Value(x.it, "D_LENGTH", x.ne - x.ns)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Snap selected MIDI item edges to barlines", -1)

