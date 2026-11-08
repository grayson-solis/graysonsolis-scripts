-- @description Fade Shape Cycle (MIDI Editor)
-- @author Grayson Solis
-- @version 1.0
-- @about Mousewheel over a fade curve, envelope segment, automation item segment, or MIDI CC lane to cycle its shape

local function get_wheel_direction()
    local is_new, _, midi_val = reaper.MIDI_GetRecentInputEvent(0)
    if is_new then
        if midi_val == 1 then return 1
        elseif midi_val == 127 then return -1 end
    end
    local _, _, _, _, _, _, val = reaper.get_action_context()
    if val > 0 then return 1
    elseif val < 0 then return -1 end
    return 0
end

local function get_project_time_at_mouse(mouse_x)
    local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local arrange_left, arrange_width = 0, 1000
    local arrange_hwnd = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
    if arrange_hwnd then
        local _, left, _, right = reaper.JS_Window_GetRect(arrange_hwnd)
        arrange_width = right - left
        arrange_left = left
    end
    local time_per_pixel = (end_time - start_time) / arrange_width
    return start_time + (mouse_x - arrange_left) * time_per_pixel, time_per_pixel
end

local function cycle_shape(current_shape, direction, max_shape)
    local new_shape = current_shape + direction
    if new_shape > max_shape then new_shape = 0 end
    if new_shape < 0 then new_shape = max_shape end
    return new_shape
end

local function handle_midi_cc(mouse_x, mouse_y, wheel_dir, window, segment)
    if window ~= "midi_editor" or segment ~= "cc_lane" or not reaper.BR_GetMouseCursorContext_MIDI then return false end

    local _, _, ccLane = reaper.BR_GetMouseCursorContext_MIDI()
    if not ccLane or ccLane < 0 then return false end

    local editor = reaper.MIDIEditor_GetActive()
    if not editor then return false end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take then return false end

    local proj_time = reaper.BR_PositionAtMouseCursor(false)
    if not proj_time or proj_time < 0 then return false end
    local ppq_at_mouse = reaper.MIDI_GetPPQPosFromProjTime(take, proj_time)

    local function cc_matches_lane(chanmsg, msg2)
        if ccLane >= 0 and ccLane <= 127 then return chanmsg == 0xB0 and msg2 == ccLane end
        if ccLane == 129 then return chanmsg == 0xE0 end
        if ccLane == 131 then return chanmsg == 0xD0 end
        if ccLane == 130 then return chanmsg == 0xC0 end
        return false
    end

    local _, _, cc_count = reaper.MIDI_CountEvts(take)
    local best_idx, best_ppq, has_next = -1, -math.huge, false

    for j = 0, cc_count - 1 do
        local ok, _, _, ppqpos, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, j)
        if ok and cc_matches_lane(chanmsg, msg2) then
            if ppqpos <= ppq_at_mouse and ppqpos > best_ppq then
                best_ppq, best_idx = ppqpos, j
            end
            if ppqpos > ppq_at_mouse then has_next = true end
        end
    end
    if best_idx < 0 or not has_next then return false end

    local shape, tension = reaper.MIDI_GetCCShape(take, best_idx)
    reaper.Undo_BeginBlock()
    reaper.MIDI_SetCCShape(take, best_idx, cycle_shape(shape, wheel_dir, 5), tension, false)
    reaper.MIDI_Sort(take)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Change MIDI CC shape", -1)
    return true
end

local function cycle_segment_shape_on_layer(envelope, ai_idx, local_time, wheel_dir, undo_label)
    local n = ai_idx == -1 and reaper.CountEnvelopePoints(envelope) or reaper.CountEnvelopePointsEx(envelope, ai_idx)
    if n < 2 then return false end

    local function get_point(idx)
        if ai_idx == -1 then return reaper.GetEnvelopePoint(envelope, idx) end
        return reaper.GetEnvelopePointEx(envelope, ai_idx, idx)
    end

    local left_idx
    for j = 0, n - 1 do
        local _, t = get_point(j)
        if t <= local_time then left_idx = j else break end
    end
    if left_idx == nil or left_idx >= n - 1 then return false end

    local _, t1, v1, sh1, tn1, sel1 = get_point(left_idx)
    local new_sh = cycle_shape(sh1, wheel_dir, 5)

    reaper.Undo_BeginBlock()
    if ai_idx == -1 then
        reaper.SetEnvelopePoint(envelope, left_idx, t1, v1, new_sh, tn1, sel1, true)
        reaper.Envelope_SortPoints(envelope)
    else
        reaper.SetEnvelopePointEx(envelope, ai_idx, left_idx, t1, v1, new_sh, tn1, sel1, true)
        reaper.Envelope_SortPointsEx(envelope, ai_idx)
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(undo_label, -1)
    return true
end

local function handle_envelope(mouse_x, mouse_y, wheel_dir, window)
    if window ~= "arrange" then return false end

    local envelope = reaper.BR_GetMouseCursorContext_Envelope()
    local project_time = get_project_time_at_mouse(mouse_x)

    if not envelope then
        local track = reaper.GetTrackFromPoint(mouse_x, mouse_y)
        if track then
            for e = 0, reaper.CountTrackEnvelopes(track) - 1 do
                local env = reaper.GetTrackEnvelope(track, e)
                for k = 0, reaper.CountAutomationItems(env) - 1 do
                    local ai_pos = reaper.GetSetAutomationItemInfo(env, k, "D_POSITION", 0, false)
                    local ai_len = reaper.GetSetAutomationItemInfo(env, k, "D_LENGTH", 0, false)
                    if project_time >= ai_pos and project_time < ai_pos + ai_len then
                        envelope = env
                        break
                    end
                end
                if envelope then break end
            end
        end
    end

    if not envelope then
        local tempo_env = reaper.GetTrackEnvelopeByName(reaper.GetMasterTrack(0), "Tempo map")
        if tempo_env then
            local retval, chunk = reaper.GetEnvelopeStateChunk(tempo_env, "", false)
            if retval and chunk:match("VIS 1") and reaper.GetTrackFromPoint(mouse_x, mouse_y) == reaper.GetMasterTrack(0) then
                envelope = tempo_env
            end
        end
    end
    if not envelope then return false end

    local ai_count = reaper.CountAutomationItems(envelope)
    for k = 0, ai_count - 1 do
        local ai_pos = reaper.GetSetAutomationItemInfo(envelope, k, "D_POSITION", 0, false)
        local ai_len = reaper.GetSetAutomationItemInfo(envelope, k, "D_LENGTH", 0, false)
        if project_time >= ai_pos and project_time < ai_pos + ai_len then
            local offs = reaper.GetSetAutomationItemInfo(envelope, k, "D_STARTOFFS", 0, false) or 0
            local rate = reaper.GetSetAutomationItemInfo(envelope, k, "D_PLAYRATE", 0, false)
            if not rate or rate == 0 then rate = 1 end
            local local_time = (project_time - ai_pos) * rate + offs
            return cycle_segment_shape_on_layer(envelope, k, local_time, wheel_dir, "Change automation item point shape")
        end
    end

    return cycle_segment_shape_on_layer(envelope, -1, project_time, wheel_dir, "Change envelope point shape")
end

local function handle_crossfade(mouse_x, mouse_y, wheel_dir)
    local project_time, time_per_pixel = get_project_time_at_mouse(mouse_x)
    local track = reaper.GetTrackFromPoint(mouse_x, mouse_y)
    if not track then return false end

    local item_count = reaper.CountTrackMediaItems(track)
    local crossfades = {}

    for i = 0, item_count - 1 do
        local item1 = reaper.GetTrackMediaItem(track, i)
        local item1_pos = reaper.GetMediaItemInfo_Value(item1, "D_POSITION")
        local item1_end = item1_pos + reaper.GetMediaItemInfo_Value(item1, "D_LENGTH")

        for j = 0, item_count - 1 do
            if i ~= j then
                local item2 = reaper.GetTrackMediaItem(track, j)
                local item2_pos = reaper.GetMediaItemInfo_Value(item2, "D_POSITION")
                local item2_end = item2_pos + reaper.GetMediaItemInfo_Value(item2, "D_LENGTH")

                local overlap_start = math.max(item1_pos, item2_pos)
                local overlap_end   = math.min(item1_end, item2_end)

                if overlap_start < overlap_end then
                    local pixel_threshold = 5 * time_per_pixel
                    if project_time >= overlap_start - pixel_threshold and project_time <= overlap_end + pixel_threshold then
                        local top_item    = i > j and item1 or item2
                        local bottom_item = i > j and item2 or item1
                        table.insert(crossfades, {
                            overlap_start = overlap_start,
                            overlap_end   = overlap_end,
                            top_item      = top_item,
                            bottom_item   = bottom_item,
                            is_left       = reaper.GetMediaItemInfo_Value(top_item, "D_POSITION") <
                                             reaper.GetMediaItemInfo_Value(bottom_item, "D_POSITION"),
                        })
                    end
                end
            end
        end
    end

    if #crossfades == 0 or not reaper.GetItemFromPoint(mouse_x, mouse_y, false) then return false end

    local xf = crossfades[1]
    local xfade_mid = (xf.overlap_start + xf.overlap_end) / 2
    local before_mid = project_time <= xfade_mid
    local target_item, fade_type

    if xf.is_left then
        target_item = before_mid and xf.bottom_item or xf.top_item
    else
        target_item = before_mid and xf.top_item or xf.bottom_item
    end
    fade_type = before_mid and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"

    local new_shape = cycle_shape(reaper.GetMediaItemInfo_Value(target_item, fade_type), wheel_dir, 6)
    reaper.Undo_BeginBlock()
    reaper.SetMediaItemInfo_Value(target_item, fade_type, new_shape)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Change crossfade " .. (fade_type == "C_FADEINSHAPE" and "fade in" or "fade out") .. " shape", -1)
    return true
end

local function handle_item_fades(mouse_x, mouse_y, wheel_dir)
    local item = reaper.GetItemFromPoint(mouse_x, mouse_y, true)
    if not item then return false end

    local project_time, time_per_pixel = get_project_time_at_mouse(mouse_x)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local fadein_len  = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    local fadeout_len = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
    local pixel_threshold = 5 * time_per_pixel

    local is_over_fadein  = fadein_len  > 0 and project_time >= item_pos - pixel_threshold and project_time <= item_pos + fadein_len + pixel_threshold
    local is_over_fadeout = fadeout_len > 0 and project_time >= item_end - fadeout_len - pixel_threshold and project_time <= item_end + pixel_threshold
    if not (is_over_fadein or is_over_fadeout) then return false end

    reaper.Undo_BeginBlock()
    if is_over_fadein then
        local new_shape = cycle_shape(reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"), wheel_dir, 6)
        reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", new_shape)
        reaper.Undo_EndBlock("Change fade in shape", -1)
    else
        local new_shape = cycle_shape(reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"), wheel_dir, 6)
        reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", new_shape)
        reaper.Undo_EndBlock("Change fade out shape", -1)
    end
    reaper.UpdateArrange()
    return true
end

local function main()
    local wheel_dir = get_wheel_direction()
    if wheel_dir == 0 then return end

    local mouse_x, mouse_y = reaper.GetMousePosition()
    local window, segment = reaper.BR_GetMouseCursorContext()

    if handle_midi_cc(mouse_x, mouse_y, wheel_dir, window, segment) then return end
    if handle_envelope(mouse_x, mouse_y, wheel_dir, window) then return end
    if handle_crossfade(mouse_x, mouse_y, wheel_dir) then return end
    handle_item_fades(mouse_x, mouse_y, wheel_dir)
end

main()
