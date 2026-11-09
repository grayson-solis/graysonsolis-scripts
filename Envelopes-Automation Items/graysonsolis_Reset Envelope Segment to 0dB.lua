-- @description Set envelope segment under mouse to 0 dB
-- @author Grayson Solis
-- @version 1.0
-- Functions on envelope segment under mouse, resets it to 0dB

local function GetResetValue(env)
  local _, name = reaper.GetEnvelopeName(env)
  if name:find('Volume') then
    return reaper.GetEnvelopeScalingMode(env) == 1 and 716.21785031263 or 1.0
  end
  local br_env = reaper.BR_EnvAlloc(env, true)
  local center = select(9, reaper.BR_EnvGetProperties(br_env))
  reaper.BR_EnvFree(br_env, false)
  return center
end

local function main()
  if not reaper.APIExists('BR_GetMouseCursorContext') then
    reaper.ShowMessageBox('Please install SWS extension!', 'Missing SWS', 0)
    return
  end

  reaper.BR_GetMouseCursorContext()
  local env = reaper.BR_GetMouseCursorContext_Envelope()
  if not env then env = reaper.GetSelectedEnvelope(0) end
  if not env then return end

  local mousePos = reaper.BR_PositionAtMouseCursor(false)
  if mousePos < 0 then return end

  local aiIdx = -1
  for i = 0, reaper.CountAutomationItems(env) - 1 do
    local aiPos = reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', 0, false)
    local aiLen = reaper.GetSetAutomationItemInfo(env, i, 'D_LENGTH',   0, false)
    if mousePos >= aiPos and mousePos < aiPos + aiLen then
      aiIdx = i
      break
    end
  end

  local leftIdx = reaper.GetEnvelopePointByTimeEx(env, aiIdx, mousePos)
  local rightIdx = leftIdx + 1
  if leftIdx < 0 or rightIdx >= reaper.CountEnvelopePointsEx(env, aiIdx) then return end

  local value = GetResetValue(env)

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  reaper.SetEnvelopePointEx(env, aiIdx, leftIdx,  nil, value, nil, nil, nil, false)
  reaper.SetEnvelopePointEx(env, aiIdx, rightIdx, nil, value, nil, nil, nil, false)
  reaper.Envelope_SortPointsEx(env, aiIdx)
  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, 'Set envelope segment to 0 dB', -1)
end

main()
