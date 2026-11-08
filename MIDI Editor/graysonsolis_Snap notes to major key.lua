local TARGET       = "major"
local MINOR_FLAVOR = "natural"
local FORCE_TONIC  = nil
local SHOW_RESULT  = false

local NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local KS_MAJOR = {6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88}
local KS_MINOR = {6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17}

local MAPS = {
  major          = {[0]=0,0,2,4,4,5,5,7,9,9,11,11},
  minor_natural  = {[0]=0,0,2,3,3,5,5,7,8,8,10,10},
  minor_harmonic = {[0]=0,0,2,3,3,5,5,7,8,8,11,11},
}

local function pearson(a, b)
  local n, sa, sb = #a, 0, 0
  for i = 1, n do sa = sa + a[i]; sb = sb + b[i] end
  local ma, mb = sa / n, sb / n
  local num, da, db = 0, 0, 0
  for i = 1, n do
    local x, y = a[i] - ma, b[i] - mb
    num = num + x * y; da = da + x * x; db = db + y * y
  end
  if da == 0 or db == 0 then return 0 end
  return num / math.sqrt(da * db)
end

local function detect_key(take, notecnt)
  local hist = {}
  for i = 1, 12 do hist[i] = 0 end
  for i = 0, notecnt - 1 do
    local _, _, _, s, e, _, pitch = reaper.MIDI_GetNote(take, i)
    hist[pitch % 12 + 1] = hist[pitch % 12 + 1] + (e - s)
  end
  local best, bt, bm = -2, 0, "major"
  for t = 0, 11 do
    local rot = {}
    for i = 0, 11 do rot[i + 1] = hist[(t + i) % 12 + 1] end
    local cM, cm = pearson(rot, KS_MAJOR), pearson(rot, KS_MINOR)
    if cM > best then best, bt, bm = cM, t, "major" end
    if cm > best then best, bt, bm = cm, t, "minor" end
  end
  return bt, bm
end

local function main()
  local editor = reaper.MIDIEditor_GetActive()
  if not editor then
    reaper.MB("Run this from the MIDI editor.", "Snap to scale", 0)
    return
  end
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.TakeIsMIDI(take) then return end
  local _, notecnt = reaper.MIDI_CountEvts(take)
  if notecnt == 0 then return end

  local tonic, mode = FORCE_TONIC, "forced"
  if not tonic then tonic, mode = detect_key(take, notecnt) end

  local map = (TARGET == "major") and MAPS.major
              or MAPS["minor_" .. MINOR_FLAVOR] or MAPS.minor_natural

  local any_sel = false
  for i = 0, notecnt - 1 do
    local _, sel = reaper.MIDI_GetNote(take, i)
    if sel then any_sel = true; break end
  end

  reaper.Undo_BeginBlock()
  local moved = 0
  for i = 0, notecnt - 1 do
    local _, sel, _, _, _, _, pitch = reaper.MIDI_GetNote(take, i)
    if sel or not any_sel then
      local rel = (pitch - tonic) % 12
      local newp = pitch + (map[rel] - rel)
      if newp < 0 then newp = 0 elseif newp > 127 then newp = 127 end
      if newp ~= pitch then
        reaper.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, newp, nil, true)
        moved = moved + 1
      end
    end
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("Snap notes to major scale", -1)

  if SHOW_RESULT then
    reaper.ShowConsoleMsg(string.format("Detected: %s %s | target: %s %s | notes moved: %d\n",
      NAMES[tonic + 1], mode, NAMES[tonic + 1], TARGET, moved))
  end
end

main()
