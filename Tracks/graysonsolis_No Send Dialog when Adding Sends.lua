-- @description No Send Dialog when Adding Sends
-- @author Grayson Solis
-- @version 1.1
-- @about Bypass the send dialog popup when dragging sends from one track IO to another track / fx
-- can still access send info by clicking respective tracks' IO button

if not reaper.JS_Window_ListAllTop then
  reaper.ShowMessageBox("Requires js_ReaScriptAPI extension", "Error", 0)
  return
end

local DRAG_THRESHOLD = 5
local WATCH_TIME = 1.0
local TITLES = {
  reaper.JS_Localize("Controls for track ", "common"),
  reaper.JS_Localize("Routing for track ", "common"),
}

local was_down, dragging, start_x, start_y, existing, deadline = false, false, 0, 0, {}, 0

local function send_windows()
  local found = {}
  local _, list = reaper.JS_Window_ListAllTop()
  for addr in list:gmatch("[^,]+") do
    local title = reaper.JS_Window_GetTitle(reaper.JS_Window_HandleFromAddress(tonumber(addr)))
    for _, prefix in ipairs(TITLES) do
      if title:sub(1, #prefix) == prefix then found[addr] = true end
    end
  end
  return found
end

local function main()
  local down = reaper.JS_Mouse_GetState(1) == 1
  local x, y = reaper.GetMousePosition()
  local now = reaper.time_precise()

  if down and not was_down then
    start_x, start_y, dragging = x, y, false
    existing = send_windows()
  elseif down then
    if math.abs(x - start_x) > DRAG_THRESHOLD or math.abs(y - start_y) > DRAG_THRESHOLD then dragging = true end
  elseif was_down and dragging then
    deadline = now + WATCH_TIME
  end
  was_down = down

  if now < deadline then
    for addr in pairs(send_windows()) do
      if not existing[addr] then
        reaper.JS_WindowMessage_Send(reaper.JS_Window_HandleFromAddress(tonumber(addr)), "WM_CLOSE", 0, 0, 0, 0)
      end
    end
  end

  reaper.defer(main)
end

main()
