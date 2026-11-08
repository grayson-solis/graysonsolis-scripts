-- @description Move Selected Envelope Lane Up
-- @author Grayson Solis
-- @version 1.0
-- @about Moves the selected FX parameter envelope lane up one visible lane among its plugin's envelopes
-- REAPER orders FX envelope lanes by plugin, then by their position in the track state, so this reorders that state

local DIRECTION = -1
local PLUGIN_TAGS = { VST = true, JS = true, AU = true, CLAP = true, DX = true, VIDEO_EFFECT = true, CONTAINER = true }

local function tooltip(text)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(text, x + 15, y + 15, true)
end

local function split_lines(chunk)
  if chunk:sub(-1) ~= "\n" then chunk = chunk .. "\n" end
  local eol = chunk:find("\r\n", 1, true) and "\r\n" or "\n"
  local lines = {}
  for line in chunk:gmatch("([^\n]*)\n") do lines[#lines + 1] = (line:gsub("\r$", "")) end
  return lines, eol
end

local function fx_param_blocks(lines, fx_index)
  local blocks, current = {}, nil
  local depth, in_chain, fx_count = 0, false, -1
  for i, line in ipairs(lines) do
    local text = line:match("^%s*(.-)%s*$")
    if text:sub(1, 1) == "<" then
      local tag = text:match("^<([%w_]+)")
      if depth == 1 and tag == "FXCHAIN" then
        in_chain = true
      elseif in_chain and depth == 2 then
        if PLUGIN_TAGS[tag] then
          fx_count = fx_count + 1
        elseif tag == "PARMENV" and fx_count == fx_index then
          current = { first = i, param = tonumber(text:match("^<PARMENV%s+(%d+)")), visible = false }
          blocks[#blocks + 1] = current
        end
      end
      depth = depth + 1
    elseif text == ">" then
      depth = depth - 1
      if current and depth == 2 then
        current.last = i
        current = nil
      end
      if in_chain and depth == 1 then in_chain = false end
    elseif current and depth == 3 then
      local vis = text:match("^VIS%s+(%d+)")
      if vis then current.visible = vis == "1" end
    end
  end
  return blocks
end

local function move_block(lines, moved, target)
  local out = {}
  local function copy(from, to)
    for i = from, to do out[#out + 1] = lines[i] end
  end
  if DIRECTION < 0 then
    copy(1, target.first - 1)
    copy(moved.first, moved.last)
    copy(target.first, moved.first - 1)
    copy(moved.last + 1, #lines)
  else
    copy(1, moved.first - 1)
    copy(moved.last + 1, target.last)
    copy(moved.first, moved.last)
    copy(target.last + 1, #lines)
  end
  return out
end

local function param_order(blocks)
  local order = {}
  for _, b in ipairs(blocks) do order[#order + 1] = b.param end
  return table.concat(order, ",")
end

local function main()
  local env = reaper.GetSelectedEnvelope(0)
  if not env then return tooltip("Select an FX parameter envelope lane first") end

  local track, fx, param = reaper.Envelope_GetParentTrack(env)
  if not track or not fx or fx < 0 or fx >= 0x1000000 then
    return tooltip("Only track FX parameter envelopes can be reordered")
  end

  local _, chunk = reaper.GetTrackStateChunk(track, "", false)
  local lines, eol = split_lines(chunk)
  local blocks = fx_param_blocks(lines, fx)

  local from
  for i, b in ipairs(blocks) do
    if b.param == param then from = i end
  end
  if not from then return tooltip("Couldn't find this envelope in the track state") end

  local to = from + DIRECTION
  while blocks[to] and not blocks[to].visible do to = to + DIRECTION end
  if not blocks[to] then
    return tooltip("Already at the " .. (DIRECTION < 0 and "top" or "bottom") .. " of this plugin's envelopes")
  end

  local new_lines = move_block(lines, blocks[from], blocks[to])
  local expected = param_order(fx_param_blocks(new_lines, fx))

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.SetTrackStateChunk(track, table.concat(new_lines, eol) .. eol, false)
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  local moved_env = reaper.GetFXEnvelope(track, fx, param, false)
  if moved_env then reaper.SetCursorContext(2, moved_env) end
  reaper.Undo_EndBlock("Move envelope lane up", -1)

  local _, check = reaper.GetTrackStateChunk(track, "", false)
  if param_order(fx_param_blocks((split_lines(check)), fx)) ~= expected then
    tooltip("REAPER did not keep the new envelope order")
  end
end

main()
