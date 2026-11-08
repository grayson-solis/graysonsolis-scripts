-- @description Contextual Rename
-- @author Grayson Solis
-- @version 1.0
-- @about Renames tons of stuff in Reaper just by hovering over it

local LANE_BUTTON_ZONE_WIDTH = 50

local function rename()
  local window, segment = reaper.BR_GetMouseCursorContext()
  local mouseX, mouseY = reaper.GetMousePosition()

  local function get_arrange_left()
    local hwnd = reaper.GetMainHwnd()
    local arrangeHwnd = reaper.JS_Window_FindChildByID(hwnd, 1000)
    if not arrangeHwnd then return nil end
    local _, left = reaper.JS_Window_GetRect(arrangeHwnd)
    return left
  end

  local function get_mouse_time()
    local startTime, endTime = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local hwnd = reaper.GetMainHwnd()
    local arrangeHwnd = reaper.JS_Window_FindChildByID(hwnd, 1000)
    local arrangeLeft, arrangeWidth = 0, 1000
    if arrangeHwnd then
      local _, left, _, right = reaper.JS_Window_GetRect(arrangeHwnd)
      arrangeWidth = right - left
      arrangeLeft = left
    end
    local timePerPixel = (endTime - startTime) / arrangeWidth
    return startTime + ((mouseX - arrangeLeft) * timePerPixel), timePerPixel
  end

  local function set_track_param_alias(track, fxIdx, paramIdx, newAlias)
    local _, chunk = reaper.GetTrackStateChunk(track, "", false)
    if not chunk or chunk == "" then return false end

    local lines = {}
    for line in chunk:gmatch("([^\n]*)\n?") do
      lines[#lines + 1] = line
    end

    if lines[#lines] == "" then lines[#lines] = nil end

    local fxBlockLabels = {
      VST = true, JS = true, DX = true, AU = true,
      CLAP = true, LV2 = true, CONTAINER = true, AUi = true, VST3 = true
    }

    local depth = 0
    local fxchainBaseDepth = -1  
    local inFxchain = false
    local fxCount = 0
    local targetStart, targetEnd = nil, nil
    local inTarget = false

    for i, line in ipairs(lines) do
      local first = line:match("^%s*(.)")

      if first == "<" then
        local label = line:match("^%s*<([%w_]+)")
        if label == "FXCHAIN" and not inFxchain then
          inFxchain = true
          fxchainBaseDepth = depth
        elseif inFxchain and depth == fxchainBaseDepth + 1 and fxBlockLabels[label] then

          if fxCount == fxIdx then
            targetStart = i
            inTarget = true
          end
          fxCount = fxCount + 1
        end
        depth = depth + 1
      elseif first == ">" then
        depth = depth - 1
        if inTarget and depth == fxchainBaseDepth + 1 then
          targetEnd = i
          inTarget = false
        end
        if inFxchain and depth == fxchainBaseDepth then
          inFxchain = false
        end
      end
    end

    if not targetStart or not targetEnd then return false end

    local existingIdx = nil
    for i = targetStart + 1, targetEnd - 1 do
      local idxStr = lines[i]:match("^%s*PARMALIAS%s+(%d+)")
      if idxStr and tonumber(idxStr) == paramIdx then
        existingIdx = i
        break
      end
    end

    local newLine = nil
    if newAlias and newAlias ~= "" then
      local needsQuote = newAlias:find("[%s\"#]") ~= nil or newAlias == ""
      local valuePart
      if newAlias:find('"') then
        valuePart = "`" .. newAlias .. "`"
      elseif needsQuote then
        valuePart = '"' .. newAlias .. '"'
      else
        valuePart = newAlias
      end
      local indent = lines[targetStart + 1] and lines[targetStart + 1]:match("^(%s*)") or "      "
      newLine = indent .. "PARMALIAS " .. paramIdx .. " " .. valuePart
    end

    if existingIdx then
      if newLine then
        lines[existingIdx] = newLine
      else
        table.remove(lines, existingIdx)
      end
    elseif newLine then
      table.insert(lines, targetEnd, newLine)
    end

    local newChunk = table.concat(lines, "\n")
    return reaper.SetTrackStateChunk(track, newChunk, false)
  end

  local function set_take_param_alias(take, fxIdx, paramIdx, newAlias)
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return false end
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    if not chunk or chunk == "" then return false end

    local lines = {}
    for line in chunk:gmatch("([^\n]*)\n?") do
      lines[#lines + 1] = line
    end
    if lines[#lines] == "" then lines[#lines] = nil end

    local fxBlockLabels = {
      VST = true, JS = true, DX = true, AU = true,
      CLAP = true, LV2 = true, CONTAINER = true, AUi = true, VST3 = true
    }
    local takeIdx = reaper.GetMediaItemTakeInfo_Value(take, "IP_TAKENUMBER")
    local activeTakeIdx = -1

    local depth = 0
    local takefxBaseDepth = -1
    local inTakeFx = false
    local fxCount = 0
    local targetStart, targetEnd = nil, nil
    local inTarget = false
    local takeFxBlockSeen = 0 

    for i, line in ipairs(lines) do
      local first = line:match("^%s*(.)")
      if first == "<" then
        local label = line:match("^%s*<([%w_]+)")
        if label == "TAKEFX" and not inTakeFx then
          inTakeFx = true
          takefxBaseDepth = depth
          fxCount = 0
        elseif inTakeFx and depth == takefxBaseDepth + 1 and fxBlockLabels[label] then
          if fxCount == fxIdx then
            targetStart = i
            inTarget = true
          end
          fxCount = fxCount + 1
        end
        depth = depth + 1
      elseif first == ">" then
        depth = depth - 1
        if inTarget and depth == takefxBaseDepth + 1 then
          targetEnd = i
          inTarget = false
        end
        if inTakeFx and depth == takefxBaseDepth then
          inTakeFx = false
          if targetStart then break end  
        end
      end
    end

    if not targetStart or not targetEnd then return false end

    local existingIdx = nil
    for i = targetStart + 1, targetEnd - 1 do
      local idxStr = lines[i]:match("^%s*PARMALIAS%s+(%d+)")
      if idxStr and tonumber(idxStr) == paramIdx then
        existingIdx = i
        break
      end
    end

    local newLine = nil
    if newAlias and newAlias ~= "" then
      local needsQuote = newAlias:find("[%s\"#]") ~= nil
      local valuePart
      if newAlias:find('"') then
        valuePart = "`" .. newAlias .. "`"
      elseif needsQuote then
        valuePart = '"' .. newAlias .. '"'
      else
        valuePart = newAlias
      end
      local indent = lines[targetStart + 1] and lines[targetStart + 1]:match("^(%s*)") or "      "
      newLine = indent .. "PARMALIAS " .. paramIdx .. " " .. valuePart
    end

    if existingIdx then
      if newLine then lines[existingIdx] = newLine
      else table.remove(lines, existingIdx) end
    elseif newLine then
      table.insert(lines, targetEnd, newLine)
    end

    return reaper.SetItemStateChunk(item, table.concat(lines, "\n"), false)
  end

  local function rename_envelope(env)
    local track, fxIdx, paramIdx = reaper.Envelope_GetParentTrack(env)
    if track and fxIdx and fxIdx >= 0 and paramIdx and paramIdx >= 0 then
      local _, paramName = reaper.TrackFX_GetParamName(track, fxIdx, paramIdx, "")
      paramName = paramName or "parameter"

      local _, currentAlias = reaper.GetEnvelopeName(env)
      if currentAlias == paramName then currentAlias = "" end 

      local ok, newAlias = reaper.GetUserInputs("Rename parameter: " .. paramName, 1,
        "New name (blank to remove):,extrawidth=200", currentAlias or "")
      if not ok then return end

      if not set_track_param_alias(track, fxIdx, paramIdx, newAlias) then
        reaper.MB("Failed to set parameter alias - couldn't locate the FX in the track chunk.",
          "Rename failed", 0)
      end
      return
    end

    local take, tFxIdx, tParamIdx = reaper.Envelope_GetParentTake(env)
    if take and tFxIdx and tFxIdx >= 0 and tParamIdx and tParamIdx >= 0 then
      local _, paramName = reaper.TakeFX_GetParamName(take, tFxIdx, tParamIdx, "")
      paramName = paramName or "parameter"

      local _, currentAlias = reaper.GetEnvelopeName(env)
      if currentAlias == paramName then currentAlias = "" end

      local ok, newAlias = reaper.GetUserInputs("Rename parameter: " .. paramName, 1,
        "New name (blank to remove):,extrawidth=200", currentAlias or "")
      if not ok then return end

      if not set_take_param_alias(take, tFxIdx, tParamIdx, newAlias) then
        reaper.MB("Failed to set parameter alias - couldn't locate the take FX in the item chunk.",
          "Rename failed", 0)
      end
      return
    end

    local _, name = reaper.GetEnvelopeName(env)
    reaper.MB(string.format(
      "'%s' is a built-in envelope. REAPER doesn't allow aliasing Volume/Pan/Width/Mute.",
      name or "this envelope"), "Cannot rename envelope", 0)
  end

  local function get_fixed_lane(track)
    if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") ~= 2 then return nil end
    local numLanes = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
    if numLanes <= 0 then return nil end

    local arrangeLeft = get_arrange_left()
    if not arrangeLeft then return nil end

    if mouseX < arrangeLeft - LANE_BUTTON_ZONE_WIDTH or mouseX >= arrangeLeft then
      return nil
    end

    local hwnd = reaper.GetMainHwnd()
    local arrangeHwnd = reaper.JS_Window_FindChildByID(hwnd, 1000)
    if not arrangeHwnd then return nil end
    local _, _, top = reaper.JS_Window_GetRect(arrangeHwnd)

    local trackY = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
    local trackH = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
    local relY = mouseY - top - trackY
    if relY < 0 or relY >= trackH then return nil end

    local laneIdx = math.floor(relY / (trackH / numLanes))
    if laneIdx < 0 then laneIdx = 0 end
    if laneIdx >= numLanes then laneIdx = numLanes - 1 end
    return laneIdx
  end

  local function rename_fixed_lane(track, laneIdx)
    local _, currentName = reaper.GetSetMediaTrackInfo_String(track,
      "P_LANENAME:" .. laneIdx, "", false)
    local ok, newName = reaper.GetUserInputs("Rename Lane " .. (laneIdx + 1), 1,
      "Lane name:,extrawidth=200", currentName or "")
    if not ok then return end
    reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. laneIdx, newName, true)
  end

  local function detect_tcp_fx()
    if not reaper.JS_Window_FromPoint then return nil end
    local hwnd = reaper.JS_Window_FromPoint(mouseX, mouseY)
    if not hwnd then return nil end

    local track = reaper.BR_GetMouseCursorContext_Track()
    if not track then return nil end

    local title = reaper.JS_Window_GetTitle(hwnd) or ""
    local fxIdx = title:match("^(%d+):")
    if fxIdx then return track, tonumber(fxIdx) end

    local fxName = title:match("^FX:%s*(.+)$") or title
    if fxName and fxName ~= "" then
      local count = reaper.TrackFX_GetCount(track)
      for i = 0, count - 1 do
        local _, name = reaper.TrackFX_GetFXName(track, i, "")
        if name and (name == fxName or name:find(fxName, 1, true)) then
          return track, i
        end
      end
    end
    return nil
  end

  local function rename_tcp_fx(track, fxIdx)
    local _, currentName = reaper.TrackFX_GetNamedConfigParm(track, fxIdx, "renamed_name")
    if not currentName or currentName == "" then
      local _, fxName = reaper.TrackFX_GetFXName(track, fxIdx, "")
      currentName = fxName or ""
    end
    local ok, newName = reaper.GetUserInputs("Rename FX", 1,
      "Name (blank to restore original):,extrawidth=200", currentName)
    if not ok then return end
    reaper.TrackFX_SetNamedConfigParm(track, fxIdx, "renamed_name", newName)
  end

  if window == "tcp" and segment == "envelope" then
    local env = reaper.BR_GetMouseCursorContext_Envelope()
    if env then rename_envelope(env); return end
  end

  if window == "arrange" and segment == "envelope" then
    local env = reaper.BR_GetMouseCursorContext_Envelope()
    if env then
      local mouseTime = get_mouse_time()
      local aiCount = reaper.CountAutomationItems(env)
      for i = 0, aiCount - 1 do
        local aiPos = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
        local aiLen = reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH",   0, false)
        if mouseTime >= aiPos and mouseTime < aiPos + aiLen then
          reaper.GetSetAutomationItemInfo(env, i, "D_UISEL", 1, true)
          return reaper.Main_OnCommand(42091, 0)
        end
      end
      rename_envelope(env)
      return
    end
  end

  local item = reaper.BR_GetMouseCursorContext_Item()
  if item then
    reaper.SetMediaItemSelected(item, true)
    return reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_RENMTAKE"), 0)
  end

  if window == "tcp" then
    local track = reaper.BR_GetMouseCursorContext_Track()
    if track then
      local laneIdx = get_fixed_lane(track)
      if laneIdx then
        rename_fixed_lane(track, laneIdx)
        return
      end

      local fxTrack, fxIdx = detect_tcp_fx()
      if fxTrack and fxIdx then
        rename_tcp_fx(fxTrack, fxIdx)
        return
      end

      reaper.SetOnlyTrackSelected(track)
      return reaper.Main_OnCommand(40696, 0)
    end
  end

  if window == "ruler" or (window == "arrange" and segment == "marker_lane") then
    local mouseTime, timePerPixel = get_mouse_time()

    local regionsAtPos = {}
    local markersAtPos = {}
    local numMarkers, numRegions = reaper.CountProjectMarkers(0)

    for i = 0, numMarkers + numRegions - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
      if isrgn then
        if mouseTime >= pos and mouseTime <= rgnend then
          table.insert(regionsAtPos, { idx = markrgnindexnumber, pos = pos, rgnend = rgnend,
            name = name, color = color, enumIdx = i, length = rgnend - pos })
        end
      else
        local timeThreshold = 20 * timePerPixel
        local dist = math.abs(mouseTime - pos)
        if dist < timeThreshold then
          table.insert(markersAtPos, { idx = markrgnindexnumber, pos = pos, name = name,
            color = color, dist = dist, enumIdx = i })
        end
      end
    end

    local selectedItem = nil
    if #regionsAtPos > 0 then
      local nameTimeThreshold = 80 * timePerPixel
      local nameHoverCandidates = {}
      for _, region in ipairs(regionsAtPos) do
        local timeFromStart = mouseTime - region.pos
        if timeFromStart >= 0 and timeFromStart <= nameTimeThreshold then
          table.insert(nameHoverCandidates, region)
        end
      end
      if #nameHoverCandidates > 0 then
        table.sort(nameHoverCandidates, function(a, b) return a.enumIdx > b.enumIdx end)
        selectedItem = nameHoverCandidates[1]
      else
        table.sort(regionsAtPos, function(a, b) return a.enumIdx > b.enumIdx end)
        selectedItem = regionsAtPos[1]
      end
    elseif #markersAtPos > 0 then
      table.sort(markersAtPos, function(a, b) return a.dist < b.dist end)
      selectedItem = markersAtPos[1]
    end

    if selectedItem then
      local name = selectedItem.name or ""
      local isRegion = selectedItem.rgnend ~= nil
      local ok, newName = reaper.GetUserInputs("Rename " .. (isRegion and "Region" or "Marker"),
        1, "Name:", name)
      if ok and newName then
        reaper.SetProjectMarker3(0, selectedItem.idx, isRegion, selectedItem.pos,
          selectedItem.rgnend or selectedItem.pos, newName, selectedItem.color)
        return reaper.Undo_EndBlock("Rename " .. (isRegion and "Region" or "Marker"), -1)
      end
    end
  end

  if window == "arrange" and segment == "track" then
    local track = reaper.BR_GetMouseCursorContext_Track()
    if track then
      reaper.SetOnlyTrackSelected(track)
      return reaper.Main_OnCommand(42472, 0)
    end
  end
end

reaper.Undo_BeginBlock()
rename()
reaper.Undo_EndBlock("Contextual Rename", -1)
