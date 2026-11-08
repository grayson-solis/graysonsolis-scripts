-- @description Split MIDI Chord Voices to Separate Tracks
-- @author Grayson Solis
-- @version 1.0
-- @about 
	-- Run on selected track - duplicates track for each voice level
	-- Topmost notes stay in current track, each voice goes to duplicated track below

function main()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        return
    end

    local item_count = reaper.CountTrackMediaItems(track)
    if item_count == 0 then
        return
    end

    local all_notes = {}
    local midi_items = {}
    
    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        
        if take and reaper.TakeIsMIDI(take) then
            table.insert(midi_items, {item = item, take = take})
            
            local _, notes_count = reaper.MIDI_CountEvts(take)
            for n = 0, notes_count - 1 do
                local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
                table.insert(all_notes, {
                    item_idx = #midi_items,
                    note_idx = n,
                    startppq = startppq,
                    endppq = endppq,
                    chan = chan,
                    pitch = pitch,
                    vel = vel,
                    selected = selected,
                    muted = muted,
                    voice = nil
                })
            end
        end
    end
    
    if #all_notes == 0 then
        return
    end
    
    local remaining = {}
    for i = 1, #all_notes do
        remaining[i] = all_notes[i]
    end
    
    local voice_num = 0
    while next(remaining) do
        local topmost_at_pos = {}
        
        for i, note in pairs(remaining) do
            local found = false
            for j, top_note in ipairs(topmost_at_pos) do
                if math.abs(note.startppq - top_note.startppq) < 10 then
                    found = true
                    if note.pitch > top_note.pitch then
                        topmost_at_pos[j] = note
                    end
                    break
                end
            end
            
            if not found then
                table.insert(topmost_at_pos, note)
            end
        end
        
        for _, note in ipairs(topmost_at_pos) do
            note.voice = voice_num
            for i, rem_note in pairs(remaining) do
                if rem_note == note then
                    remaining[i] = nil
                    break
                end
            end
        end
        
        voice_num = voice_num + 1
        if voice_num > 20 then break end
    end
    
    local max_voice = 0
    for _, note in ipairs(all_notes) do
        if note.voice and note.voice > max_voice then
            max_voice = note.voice
        end
    end
    
    reaper.Undo_BeginBlock()

    local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    
    for v = 1, max_voice do
        reaper.SetOnlyTrackSelected(track)
        reaper.Main_OnCommand(40062, 0)
        
        local new_track = reaper.GetTrack(0, track_idx + v)
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "Voice " .. (v + 1), true)
    end
    
    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        
        if take and reaper.TakeIsMIDI(take) then
            local _, notes_count = reaper.MIDI_CountEvts(take)
            
            for n = notes_count - 1, 0, -1 do
                local _, _, _, sppq, _, _, p, _ = reaper.MIDI_GetNote(take, n)
                local keep = false
                
                for _, note in ipairs(all_notes) do
                    if note.pitch == p and math.abs(note.startppq - sppq) < 10 and note.voice == 0 then
                        keep = true
                        break
                    end
                end
                
                if not keep then
                    reaper.MIDI_DeleteNote(take, n)
                end
            end
            
            reaper.MIDI_Sort(take)
        end
    end
    
    for v = 1, max_voice do
        local dup_track = reaper.GetTrack(0, track_idx + v)
        local dup_item_count = reaper.CountTrackMediaItems(dup_track)
        
        for i = 0, dup_item_count - 1 do
            local item = reaper.GetTrackMediaItem(dup_track, i)
            local take = reaper.GetActiveTake(item)
            
            if take and reaper.TakeIsMIDI(take) then
                local _, notes_count = reaper.MIDI_CountEvts(take)
                
                for n = notes_count - 1, 0, -1 do
                    local _, _, _, sppq, _, _, p, _ = reaper.MIDI_GetNote(take, n)
                    local keep = false
                    
                    for _, note in ipairs(all_notes) do
                        if note.pitch == p and math.abs(note.startppq - sppq) < 10 and note.voice == v then
                            keep = true
                            break
                        end
                    end
                    
                    if not keep then
                        reaper.MIDI_DeleteNote(take, n)
                    end
                end
                
                reaper.MIDI_Sort(take)
            end
        end
    end
    
    reaper.UpdateArrange()
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

