-- @description No FX Chain Dialog when Copying FX Chain
-- @author Grayson Solis
-- @version 1.0
local mouse_was_down = false
local mouse_press_x, mouse_press_y = 0, 0
local DRAG_THRESHOLD = 10 

local function check_and_close()
  local hwnd = reaper.JS_Window_Find("FX: Track", false)
  if hwnd then
    reaper.JS_Window_Destroy(hwnd)
  end
end

local function main()
  local mouse_state = reaper.JS_Mouse_GetState(1)
  local mouse_down = (mouse_state & 1) == 1

  if mouse_down and not mouse_was_down then
    mouse_press_x, mouse_press_y = reaper.GetMousePosition()

  elseif not mouse_down and mouse_was_down then
    local x, y = reaper.GetMousePosition()
    local dx = x - mouse_press_x
    local dy = y - mouse_press_y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > DRAG_THRESHOLD then
      reaper.defer(function()
        reaper.defer(check_and_close)
      end)
    end
  end

  mouse_was_down = mouse_down
  reaper.defer(main)
end

if reaper.JS_Window_Find and reaper.JS_Mouse_GetState then
  main()
else
  reaper.ShowMessageBox("Requires js_ReaScriptAPI extension", "Error", 0)
end
