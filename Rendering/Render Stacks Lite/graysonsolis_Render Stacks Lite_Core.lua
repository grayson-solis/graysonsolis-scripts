-- @name RenderStacks Core Library Lite
-- @noindex
-- @version 1.1
-- @author Grayson Solis
-- @description Shared RenderStacks tools

local RenderStacks = {}

RenderStacks.VERSION = "2.31.0"
RenderStacks.SETTINGS_KEY = "RenderStacksProLite"

local COLOR_KEY = "P_EXT:RenderStacksLite_color"
local APPLIED_KEY = "P_EXT:RenderStacksLite_applied"

local ALL_DEFAULTS = {
    gap_tolerance = 0.001,
    highlight_tracks_with_regions = true,
    highlight_level = -0.4,
    color_regions_track_color = true,
}

function RenderStacks.isActuallyMuted(tr)
    while tr do
        if reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then return true end
        tr = reaper.GetParentTrack(tr)
    end
    return false
end

function RenderStacks.is_video_item(item)
    local take = reaper.GetActiveTake(item)
    if not take then return false end
    local source = reaper.GetMediaItemTake_Source(take)
    if not source then return false end
    return reaper.GetMediaSourceType(source, ""):match("VIDEO") ~= nil
end

function RenderStacks.get_track_color(track)
    local _, orig = reaper.GetSetMediaTrackInfo_String(track, COLOR_KEY, "", false)
    if orig ~= "" then return tonumber(orig) end
    return reaper.GetTrackColor(track)
end

function RenderStacks.loadSettings(defaults)
    local settings = {}
    for k, v in pairs(defaults) do settings[k] = v end
    for key, default_value in pairs(settings) do
        local val = reaper.GetExtState(RenderStacks.SETTINGS_KEY, key)
        if val ~= "" then
            if type(default_value) == "boolean" then
                settings[key] = (val == "true")
            elseif type(default_value) == "number" then
                settings[key] = tonumber(val) or default_value
            else
                settings[key] = val
            end
        end
    end
    return settings
end

function RenderStacks.darken_color(color, amount)
    local r = color & 0xFF
    local g = (color >> 8) & 0xFF
    local b = (color >> 16) & 0xFF
    r = math.floor(r * amount)
    g = math.floor(g * amount)
    b = math.floor(b * amount)
    return r | (g << 8) | (b << 16)
end

function RenderStacks.brighten_color(color, amount)
    local r = color & 0xFF
    local g = (color >> 8) & 0xFF
    local b = (color >> 16) & 0xFF
    r = math.floor(r + (255 - r) * amount)
    g = math.floor(g + (255 - g) * amount)
    b = math.floor(b + (255 - b) * amount)
    return r | (g << 8) | (b << 16)
end

function RenderStacks.compute_highlight_color(orig, settings)
    if settings.highlight_level < 0 then
        return RenderStacks.darken_color(orig, 1.0 + settings.highlight_level)
    elseif settings.highlight_level > 0 then
        return RenderStacks.brighten_color(orig, settings.highlight_level)
    end
    return orig
end

function RenderStacks.gather_all_items(track)
    local all_items = {}
    local function add_items(source_track)
        for i = 0, reaper.CountTrackMediaItems(source_track) - 1 do
            local item = reaper.GetTrackMediaItem(source_track, i)
            local is_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
            if not is_muted and not RenderStacks.is_video_item(item) then table.insert(all_items, item) end
        end
    end
    add_items(track)
    local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    for i = track_idx, reaper.CountTracks(0) - 1 do
        local child = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(child) <= reaper.GetTrackDepth(track) then break end
        if not RenderStacks.isActuallyMuted(child) then add_items(child) end
    end
    return all_items
end

function RenderStacks.detect_stacks(all_items, gap_tolerance)
    table.sort(all_items, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
    local stacks = {}
    local current_stack = {}
    local current_end = 0
    for _, item in ipairs(all_items) do
        local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local end_pos = start_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if start_pos > current_end + gap_tolerance then
            if #current_stack > 0 then table.insert(stacks, current_stack) current_stack = {} end
            current_end = end_pos
        else
            current_end = math.max(current_end, end_pos)
        end
        table.insert(current_stack, item)
    end
    if #current_stack > 0 then table.insert(stacks, current_stack) end
    return stacks
end

function RenderStacks.group_items_with_id(items, group_id)
    if #items == 0 then return end
    for _, item in ipairs(items) do reaper.SetMediaItemInfo_Value(item, "I_GROUPID", group_id) end
end

function RenderStacks.ungroup_items_in_stack(stack_items)
    if #stack_items == 0 then return end
    for _, item in ipairs(stack_items) do reaper.SetMediaItemInfo_Value(item, "I_GROUPID", 0) end
end

function RenderStacks.get_items_in_time_range(track, start_pos, end_pos, include_children)
    local items = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_pos < end_pos and item_end > start_pos then table.insert(items, item) end
    end
    if include_children then
        local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        for i = track_idx, reaper.CountTracks(0) - 1 do
            local child = reaper.GetTrack(0, i)
            if reaper.GetTrackDepth(child) <= reaper.GetTrackDepth(track) then break end
            for j = 0, reaper.CountTrackMediaItems(child) - 1 do
                local item = reaper.GetTrackMediaItem(child, j)
                local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if item_pos < end_pos and item_end > start_pos then table.insert(items, item) end
            end
        end
    end
    return items
end

local NAMES_SECTION, NAMES_KEY = "RenderStacksLite", "region_names"
local names_raw, names_set

local function known_names()
    local _, raw = reaper.GetProjExtState(0, NAMES_SECTION, NAMES_KEY)
    if raw ~= names_raw then
        names_set = {}
        for line in raw:gmatch("[^\n]+") do names_set[line] = true end
        names_raw = raw
    end
    return names_set
end

local function remember_region_name(track, name)
    local key = reaper.GetTrackGUID(track) .. "|" .. name
    if known_names()[key] then return end
    names_raw = (names_raw ~= "" and names_raw .. "\n" or "") .. key
    reaper.SetProjExtState(0, NAMES_SECTION, NAMES_KEY, names_raw)
    names_set[key] = true
end

local function is_renderstacks_region(region_name, track_name, track)
    local escaped_name = track_name:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    if region_name:match("^" .. escaped_name .. "(_?%d*)$") ~= nil then return true end
    return known_names()[reaper.GetTrackGUID(track) .. "|" .. region_name] == true
end

local function get_all_track_regions()
    local by_track = {}
    local i = 0
    while true do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
        if retval == 0 then break end
        if isrgn then
            local track_idx = 0
            while true do
                local enum_track = reaper.EnumRegionRenderMatrix(0, markrgnindexnumber, track_idx)
                if not enum_track then break end
                if reaper.ValidatePtr(enum_track, "MediaTrack*") then
                    local _, track_name = reaper.GetTrackName(enum_track, "")
                    if is_renderstacks_region(name, (track_name:gsub("<.->", "")), enum_track) then
                        local list = by_track[enum_track]
                        if not list then list = {} by_track[enum_track] = list end
                        table.insert(list, { id = markrgnindexnumber, name = name, start = pos, end_pos = rgnend, color = color })
                    end
                end
                track_idx = track_idx + 1
            end
        end
        i = i + 1
    end
    return by_track
end

function RenderStacks.delete_track_regions(tracks, ungroup)
    local by_track = get_all_track_regions()
    local done, count = {}, 0
    for _, track in ipairs(tracks) do
        for _, region in ipairs(by_track[track] or {}) do
            if not done[region.id] then
                done[region.id] = true
                if ungroup then
                    RenderStacks.ungroup_items_in_stack(RenderStacks.get_items_in_time_range(track, region.start, region.end_pos, true))
                end
                reaper.DeleteProjectMarker(0, region.id, true)
                count = count + 1
            end
        end
    end
    return count
end

local function next_group_id()
    local max_group = 0
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local group_id = reaper.GetMediaItemInfo_Value(reaper.GetMediaItem(0, i), "I_GROUPID")
        if group_id > max_group then max_group = group_id end
    end
    return max_group + 1
end

function RenderStacks.rebuild_track_regions(track, settings)
    local new_ids = {}
    if RenderStacks.isActuallyMuted(track) then return new_ids end

    local _, track_name = reaper.GetTrackName(track, "")
    track_name = track_name:gsub("<.->", "")

    for _, region in ipairs(get_all_track_regions()[track] or {}) do
        reaper.DeleteProjectMarker(0, region.id, true)
    end

    local color = settings.color_regions_track_color and RenderStacks.get_track_color(track) or 0
    local valid_count = 0
    for _, stack in ipairs(RenderStacks.detect_stacks(RenderStacks.gather_all_items(track), settings.gap_tolerance)) do
        local stack_start, stack_end = math.huge, 0
        for _, item in ipairs(stack) do
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            stack_start = math.min(stack_start, pos)
            stack_end = math.max(stack_end, pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"))
        end
        if stack_end - stack_start >= settings.min_region_length and stack_start < stack_end then
            local name = valid_count == 0 and track_name or track_name .. "_" .. valid_count
            local region_id = reaper.AddProjectMarker(0, true, stack_start, stack_end, name, -1)
            reaper.SetProjectMarker3(0, region_id, true, stack_start, stack_end, name, color)
            reaper.SetRegionRenderMatrix(0, region_id, track, 1)
            remember_region_name(track, name)
            if settings.group_items then RenderStacks.group_items_with_id(stack, next_group_id()) end
            new_ids[#new_ids + 1] = region_id
            valid_count = valid_count + 1
        end
    end
    return new_ids
end

function RenderStacks.refresh_all_regions(settings)
    local tracks = {}
    for track in pairs(get_all_track_regions()) do tracks[#tracks + 1] = track end
    reaper.PreventUIRefresh(1)
    for _, track in ipairs(tracks) do RenderStacks.rebuild_track_regions(track, settings) end
    reaper.PreventUIRefresh(-1)
end

function RenderStacks.recolor_all_regions(settings)
    reaper.PreventUIRefresh(1)
    for track, regions in pairs(get_all_track_regions()) do
        local color = settings.color_regions_track_color and RenderStacks.get_track_color(track) or 0
        for _, region in ipairs(regions) do
            reaper.SetProjectMarker3(0, region.id, true, region.start, region.end_pos, region.name, color)
        end
    end
    reaper.PreventUIRefresh(-1)
end

local function restore_track_color(track, color)
    if color == 0 then
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", 0)
    else
        reaper.SetTrackColor(track, color)
    end
end

local function user_changed(current, applied)
    applied = tonumber(applied)
    return applied ~= nil and (current & 0xFFFFFF) ~= (applied & 0xFFFFFF)
end

local function restore_highlight_colors()
    local changed = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, orig = reaper.GetSetMediaTrackInfo_String(track, COLOR_KEY, "", false)
        if orig ~= "" then
            local _, applied = reaper.GetSetMediaTrackInfo_String(track, APPLIED_KEY, "", false)
            local cur = reaper.GetTrackColor(track)
            if user_changed(cur, applied) then changed[track] = cur end
        end
    end
    reaper.PreventUIRefresh(1)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, orig = reaper.GetSetMediaTrackInfo_String(track, COLOR_KEY, "", false)
        if orig ~= "" then
            if not changed[track] then
                local ancestor = reaper.GetParentTrack(track)
                while ancestor and not changed[ancestor] do ancestor = reaper.GetParentTrack(ancestor) end
                restore_track_color(track, ancestor and changed[ancestor] or tonumber(orig))
            end
            reaper.GetSetMediaTrackInfo_String(track, COLOR_KEY, "", true)
            reaper.GetSetMediaTrackInfo_String(track, APPLIED_KEY, "", true)
        end
    end
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local _, orig = reaper.GetSetMediaItemInfo_String(item, COLOR_KEY, "", false)
        if orig ~= "" then
            local _, applied = reaper.GetSetMediaItemInfo_String(item, APPLIED_KEY, "", false)
            local cur = math.floor(reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
            if not user_changed(cur, applied) then reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", tonumber(orig)) end
            reaper.GetSetMediaItemInfo_String(item, COLOR_KEY, "", true)
            reaper.GetSetMediaItemInfo_String(item, APPLIED_KEY, "", true)
        end
    end
    reaper.PreventUIRefresh(-1)
end

local function apply_highlight_colors(settings)
    local tracks_to_color = {}
    local region_items = {}
    for track, regions in pairs(get_all_track_regions()) do
        tracks_to_color[track] = true
        local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        for i = track_idx, reaper.CountTracks(0) - 1 do
            local child = reaper.GetTrack(0, i)
            if reaper.GetTrackDepth(child) <= reaper.GetTrackDepth(track) then break end
            if not RenderStacks.isActuallyMuted(child) then tracks_to_color[child] = true end
        end
        local stacks = RenderStacks.detect_stacks(RenderStacks.gather_all_items(track), settings.gap_tolerance)
        for _, stack in ipairs(stacks) do
            local s, e = math.huge, 0
            for _, item in ipairs(stack) do
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                s = math.min(s, pos)
                e = math.max(e, pos + len)
            end
            for _, region in ipairs(regions) do
                if math.abs(s - region.start) < 0.001 and math.abs(e - region.end_pos) < 0.001 then
                    for _, item in ipairs(stack) do
                        region_items[item] = true
                        tracks_to_color[reaper.GetMediaItem_Track(item)] = true
                    end
                    break
                end
            end
        end
    end

    local track_colors = {}
    reaper.PreventUIRefresh(1)
    for track, _ in pairs(tracks_to_color) do
        local orig = reaper.GetTrackColor(track)
        local base = orig == 0 and 0x808080 or orig
        local color = RenderStacks.compute_highlight_color(base, settings)
        if color == 0 then color = 0x010101 end
        track_colors[track] = color
        reaper.GetSetMediaTrackInfo_String(track, COLOR_KEY, tostring(orig), true)
        reaper.GetSetMediaTrackInfo_String(track, APPLIED_KEY, tostring(color), true)
        reaper.SetTrackColor(track, color)
    end
    for item, _ in pairs(region_items) do
        local orig = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
        local applied = track_colors[reaper.GetMediaItem_Track(item)] | 0x1000000
        reaper.GetSetMediaItemInfo_String(item, COLOR_KEY, tostring(math.floor(orig)), true)
        reaper.GetSetMediaItemInfo_String(item, APPLIED_KEY, tostring(applied), true)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", applied)
    end
    reaper.PreventUIRefresh(-1)
end

local function has_live_track(idx)
    local n = 0
    while true do
        local tr = reaper.EnumRegionRenderMatrix(0, idx, n)
        if not tr then return false end
        if reaper.ValidatePtr(tr, "MediaTrack*") then return true end
        n = n + 1
    end
end

function RenderStacks.delete_orphaned_regions()
    local alive = {}
    for i = 0, reaper.CountTracks(0) - 1 do alive[reaper.GetTrackGUID(reaper.GetTrack(0, i))] = true end
    local dead = {}
    for key in pairs(known_names()) do
        local g, name = key:match("^(.-)|(.*)$")
        if g and not alive[g] then dead[name] = true end
    end
    if not next(dead) then return end
    local ids, i = {}, 0
    while true do
        local retval, isrgn, _, _, name, idx = reaper.EnumProjectMarkers3(0, i)
        if retval == 0 then break end
        if isrgn and dead[name] and not has_live_track(idx) then ids[#ids + 1] = idx end
        i = i + 1
    end
    for _, idx in ipairs(ids) do reaper.DeleteProjectMarker(0, idx, true) end
end

function RenderStacks.update_highlight()
    local settings = RenderStacks.loadSettings(ALL_DEFAULTS)
    RenderStacks.delete_orphaned_regions()
    restore_highlight_colors()
    if settings.color_regions_track_color then RenderStacks.recolor_all_regions(settings) end
    if settings.highlight_tracks_with_regions then apply_highlight_colors(settings) end
    reaper.UpdateArrange()
end

local function has_render_matrix_regions()
    local i = 0
    while true do
        local retval, isrgn, _, _, _, idx = reaper.EnumProjectMarkers3(0, i)
        if retval == 0 then return false end
        if isrgn and reaper.EnumRegionRenderMatrix(0, idx, 0) then return true end
        i = i + 1
    end
end

function RenderStacks.setup_render_window()
    if not has_render_matrix_regions() then return end
    local function get(k) return math.floor(reaper.GetSetProjectInfo(0, k, 0, false) or 0) end
    local function set(k, v) reaper.GetSetProjectInfo(0, k, v, true) end
    set("RENDER_SETTINGS", (get("RENDER_SETTINGS") & ~239) | 8)
    set("RENDER_BOUNDSFLAG", 3)
    local _, pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
    if not pattern:find("$region", 1, true) then reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$region", true) end
end

local function open_url(url)
    local os_name = reaper.GetOS()
    local cmd
    if os_name:find("Win") then
        cmd = 'cmd.exe /C start "" "' .. url .. '"'
    elseif os_name:find("OSX") or os_name:find("macOS") then
        cmd = 'open "' .. url .. '"'
    else
        cmd = 'xdg-open "' .. url .. '"'
    end
    reaper.ExecProcess(cmd, 2000)
end

function RenderStacks.ensure_dependencies(product, need_imgui, need_js)
    local missing, filters = {}, {}
    if need_imgui and not reaper.ImGui_CreateContext then
        missing[#missing + 1] = "ReaImGui"
        filters[#filters + 1] = "reaimgui: reascript binding for dear imgui"
    end
    if #missing == 0 then return true end
    local names = table.concat(missing, " and ")
    if not reaper.ReaPack_BrowsePackages then
        local r = reaper.MB(product .. " needs " .. names .. ", which " .. (#missing > 1 and "aren't" or "isn't") .. " installed.\n\n" .. (#missing > 1 and "They install" or "It installs") .. " through ReaPack, which isn't installed either.\n\nOpen the ReaPack download page now? After installing it, restart REAPER and run this script again.", product, 4)
        if r == 6 then open_url("https://reapack.com/") end
        return false
    end
    local steps = "ReaPack will open on " .. missing[1] .. ". Right-click it, choose Install, then click Apply and restart REAPER."
    if #filters > 1 then steps = steps .. " Run this script again afterwards to install " .. missing[2] .. "." end
    local r = reaper.MB(product .. " needs " .. names .. ", which " .. (#missing > 1 and "aren't" or "isn't") .. " installed.\n\nInstall now?\n\n" .. steps, product, 4)
    if r ~= 6 then return false end
    pcall(function()
        if not reaper.ReaPack_GetRepositoryInfo("ReaTeam Extensions") then
            reaper.ReaPack_AddSetRepository("ReaTeam Extensions", "https://github.com/ReaTeam/Extensions/raw/master/index.xml", true, 1)
            reaper.ReaPack_ProcessQueue(true)
        end
        reaper.ReaPack_BrowsePackages(filters[1])
    end)
    return false
end

return RenderStacks
