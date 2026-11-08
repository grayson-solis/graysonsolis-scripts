-- @description Export selected MIDI items as .mid files into <project>/Exported MIDI (CC curves baked to points)
-- @version 2.2
local r = reaper
local OUT_DIR, STEP = 'Exported MIDI', 1
local TRACK_FOLDERS = 1
local dir = r.GetProjectPath() .. '/' .. OUT_DIR
local function clean(s) return (s:gsub('[\\/:*?"<>|]', '_')) end
local function vlq(n)
  local s = string.char(n & 0x7F)
  n = n >> 7
  while n > 0 do s = string.char((n & 0x7F) | 0x80) .. s; n = n >> 7 end
  return s
end
local shapes = {
  [1] = function(t) return t end,
  [2] = function(t) return t * t * (3 - 2 * t) end,
  [3] = function(t) return 1 - (1 - t) ^ 2 end,
  [4] = function(t) return t * t end,
  [5] = function(t, b) return t ^ (2 ^ b) end,
}
local function build(item)
  local take = r.GetActiveTake(item)
  if not (take and r.TakeIsMIDI(take)) then return end
  local ipos = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local qn = r.TimeMap2_timeToQN(0, ipos)
  local ppq = math.floor(r.MIDI_GetPPQPosFromProjQN(take, qn + 1) - r.MIDI_GetPPQPosFromProjQN(take, qn) + 0.5)
  local s0 = r.MIDI_GetPPQPosFromProjTime(take, ipos)
  local s1 = r.MIDI_GetPPQPosFromProjTime(take, ipos + r.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  local ev = {}
  local function add(pos, prio, ...) ev[#ev + 1] = {math.floor(pos - s0 + 0.5), prio, string.char(...), #ev} end
  local _, nn, nc = r.MIDI_CountEvts(take)
  for i = 0, nn - 1 do
    local _, _, mute, s, e, ch, p, v = r.MIDI_GetNote(take, i)
    if not mute and e > s0 and s < s1 then add(math.max(s, s0), 2, 0x90 | ch, p, v); add(math.min(e, s1), 0, 0x80 | ch, p, 0) end
  end
  local lanes = {}
  for i = 0, nc - 1 do
    local _, _, mute, pos, msg, ch, m2, m3 = r.MIDI_GetCC(take, i)
    if not mute and pos >= s0 and pos < s1 then
      local _, shape, tens = r.MIDI_GetCCShape(take, i)
      local hi = msg & 0xF0
      local key = hi .. ':' .. ch .. ':' .. ((hi == 0xB0 or hi == 0xA0) and m2 or 0)
      local val = hi == 0xE0 and (m2 | (m3 << 7)) or hi == 0xD0 and m2 or m3
      lanes[key] = lanes[key] or {}
      table.insert(lanes[key], {pos = pos, val = val, shape = shape, tens = tens, hi = hi, ch = ch, m2 = m2})
    end
  end
  local function cc(p, l, v)
    if l.hi == 0xE0 then add(p, 1, 0xE0 | l.ch, v & 0x7F, v >> 7)
    elseif l.hi == 0xD0 then add(p, 1, 0xD0 | l.ch, v)
    else add(p, 1, l.hi | l.ch, l.m2, v) end
  end
  for _, pts in pairs(lanes) do
    for i, a in ipairs(pts) do
      cc(a.pos, a, a.val)
      local b, f = pts[i + 1], shapes[a.shape]
      if b and f then
        local last, span = a.val, b.pos - a.pos
        for p = a.pos + STEP, b.pos - 1, STEP do
          local v = math.floor(a.val + (b.val - a.val) * f((p - a.pos) / span, a.tens) + 0.5)
          if v ~= last then cc(p, a, v); last = v end
        end
      end
    end
  end
  table.sort(ev, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[4] < b[4]
  end)
  local bpm = r.TimeMap_GetDividedBpmAtTime(ipos)
  local t, last = {vlq(0) .. '\xFF\x51\x03' .. string.pack('>I3', math.floor(60000000 / bpm + 0.5))}, 0
  for _, e in ipairs(ev) do t[#t + 1] = vlq(e[1] - last) .. e[3]; last = e[1] end
  t[#t + 1] = vlq(0) .. '\xFF\x2F\x00'
  local body = table.concat(t)
  local name = r.GetTakeName(take)
  if name == '' then name = select(2, r.GetTrackName(r.GetMediaItemTrack(item))) end
  name = clean(name)
  if name == '' then name = 'midi' end
  local folder = dir
  if TRACK_FOLDERS == 1 then folder = dir .. '/' .. clean(select(2, r.GetTrackName(r.GetMediaItemTrack(item)))) end
  return folder .. '/' .. name, folder, 'MThd' .. string.pack('>I4I2I2I2', 6, 0, 1, ppq) .. 'MTrk' .. string.pack('>I4', #body) .. body
end

local jobs = {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local base, folder, chunk = build(r.GetSelectedMediaItem(0, i))
  if base then jobs[#jobs + 1] = {base, chunk, folder} end
end
if #jobs == 0 then return r.MB('No MIDI items selected.', 'Export MIDI', 0) end

local conflicts = 0
for _, j in ipairs(jobs) do if r.file_exists(j[1] .. '.mid') then conflicts = conflicts + 1 end end
local overwrite = false
if conflicts > 0 then
  local ret = r.MB(conflicts .. ' file(s) already exist in:\n' .. dir .. '\n\nYes = Overwrite\nNo = Keep both (add number)\nCancel = Abort export', 'Export MIDI', 3)
  if ret == 2 then return end
  overwrite = ret == 6
end

local ok, failed, used = 0, 0, {}
for _, j in ipairs(jobs) do
  r.RecursiveCreateDirectory(j[3], 0)
  local fp, n = j[1] .. '.mid', 0
  while used[fp] or (not overwrite and r.file_exists(fp)) do n = n + 1; fp = ('%s(%d).mid'):format(j[1], n) end
  used[fp] = true
  local f = io.open(fp, 'wb')
  if f then f:write(j[2]); f:close(); ok = ok + 1 else failed = failed + 1 end
end
r.MB(ok .. ' MIDI file(s) exported to:\n' .. dir .. (failed > 0 and ('\n\n' .. failed .. ' file(s) failed to write.') or ''), 'Export MIDI', 0)

