local TOLERANCE = 30

local function invert_take(take)
  local all_notes = {}
  local i = 0
  while true do
    local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if not ok then break end
    all_notes[#all_notes + 1] = {
      idx = i, sel = sel, muted = muted,
      startppq = sppq, endppq = eppq,
      chan = chan, pitch = pitch, vel = vel,
    }
    i = i + 1
  end
  local idx_to_note = {}
  for _, n in ipairs(all_notes) do idx_to_note[n.idx] = n end

  local selected = {}
  for _, n in ipairs(all_notes) do selected[#selected + 1] = n end
  if #selected < 2 then return end
  table.sort(selected, function(a, b) return a.startppq < b.startppq end)

  local clusters = {}
  local cur = { selected[1] }
  for k = 2, #selected do
    if selected[k].startppq - cur[1].startppq <= TOLERANCE then
      cur[#cur + 1] = selected[k]
    else
      clusters[#clusters + 1] = cur
      cur = { selected[k] }
    end
  end
  clusters[#clusters + 1] = cur

  local chords = {}
  for _, cluster in ipairs(clusters) do
    local counts = {}
    for _, n in ipairs(cluster) do
      counts[n.startppq] = (counts[n.startppq] or 0) + 1
    end
    local cstart, cmax = cluster[1].startppq, 0
    for sp, c in pairs(counts) do
      if c > cmax or (c == cmax and sp < cstart) then
        cstart, cmax = sp, c
      end
    end
    chords[#chords + 1] = { notes = cluster, start = cstart }
  end

  local drone = {}
  for _, ch in ipairs(chords) do
    if #ch.notes == 1 then drone[ch.notes[1].idx] = true end
  end

  local chord_mods = {}
  local spanner_mods = {}

  for _, ch in ipairs(chords) do
    local chord, cstart = ch.notes, ch.start
    if #chord >= 2 then
      local cend = math.huge
      for _, n in ipairs(chord) do
        if n.endppq < cend then cend = n.endppq end
      end

      local member = {}
      for _, n in ipairs(chord) do member[n.idx] = true end

      local snapshot, occupied, pclass = {}, {}, {}
      for _, n in ipairs(chord) do
        snapshot[#snapshot + 1] = { pitch = n.pitch, kind = "chord", idx = n.idx }
        occupied[n.pitch] = true
        pclass[n.pitch % 12] = true
      end
      for _, n in ipairs(all_notes) do
        if not member[n.idx]
           and n.startppq <= cstart
           and n.endppq   >  cstart then
          occupied[n.pitch] = true
          if drone[n.idx] then
            pclass[n.pitch % 12] = true
            snapshot[#snapshot + 1] = {
              pitch = n.pitch, kind = "spanner", idx = n.idx,
              seg_start = cstart, seg_end = math.min(cend, n.endppq),
            }
          end
        end
      end

      table.sort(snapshot, function(a, b) return a.pitch < b.pitch end)
      local top = snapshot[#snapshot]
      local bottom_pitch = snapshot[1].pitch
      local own_class = top.pitch % 12

      local doubled = false
      for k = 1, #snapshot - 1 do
        if snapshot[k].pitch % 12 == own_class then doubled = true break end
      end

      local newp
      if doubled then
        for p = top.pitch - 1, 0, -1 do
          if pclass[p % 12] and not occupied[p] then
            newp = p; break
          end
        end
      else
        for p = bottom_pitch - 1, 0, -1 do
          if p % 12 == own_class and not occupied[p] then
            newp = p; break
          end
        end
        if not newp then
          for p = top.pitch - 1, 0, -1 do
            if p % 12 == own_class and not occupied[p] then
              newp = p; break
            end
          end
        end
      end

      if newp then
        if top.kind == "chord" then
          chord_mods[#chord_mods + 1] = { idx = top.idx, new_pitch = newp }
          idx_to_note[top.idx].pitch = newp
        else
          local list = spanner_mods[top.idx] or {}
          list[#list + 1] = {
            seg_start = top.seg_start, seg_end = top.seg_end, new_pitch = newp,
          }
          spanner_mods[top.idx] = list
        end
      end
    end
  end

  for _, m in ipairs(chord_mods) do
    reaper.MIDI_SetNote(take, m.idx, nil, nil, nil, nil, nil, m.new_pitch, nil, true)
  end

  local sorted = {}
  for sidx in pairs(spanner_mods) do sorted[#sorted + 1] = sidx end
  table.sort(sorted, function(a, b) return a > b end)

  for _, sidx in ipairs(sorted) do
    local sp = idx_to_note[sidx]
    local mods = spanner_mods[sidx]
    table.sort(mods, function(a, b) return a.seg_start < b.seg_start end)

    local clean = { mods[1] }
    for k = 2, #mods do
      if mods[k].seg_start >= clean[#clean].seg_end then
        clean[#clean + 1] = mods[k]
      end
    end
    mods = clean

    reaper.MIDI_DeleteNote(take, sidx)

    local cursor = sp.startppq
    for _, m in ipairs(mods) do
      if m.seg_start > cursor then
        reaper.MIDI_InsertNote(take, sp.sel, sp.muted,
          cursor, m.seg_start, sp.chan, sp.pitch, sp.vel, true)
      end
      reaper.MIDI_InsertNote(take, sp.sel, sp.muted,
        m.seg_start, m.seg_end, sp.chan, m.new_pitch, sp.vel, true)
      cursor = m.seg_end
    end
    if cursor < sp.endppq then
      reaper.MIDI_InsertNote(take, sp.sel, sp.muted,
        cursor, sp.endppq, sp.chan, sp.pitch, sp.vel, true)
    end
  end
  reaper.MIDI_Sort(take)
  if reaper.APIExists('ReaFruit_Refresh') then reaper.ReaFruit_Refresh() end
end

local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for k = 0, item_count - 1 do
  local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, k))
  if take and reaper.TakeIsMIDI(take) then invert_take(take) end
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Chord Inversion Down (Arrange)", -1)
