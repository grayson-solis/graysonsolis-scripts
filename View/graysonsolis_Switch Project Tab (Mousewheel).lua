-- @description Switch Project Tab (Mousewheel)
-- @author Grayson Solis
-- @version 1.0

local SENSITIVITY = 3
local FLIP = true
local _,_,_,_,_,_,val = reaper.get_action_context()
local now = reaper.time_precise()
local last = tonumber(reaper.GetExtState("tab_scroll","t")) or 0
if now - last < SENSITIVITY/10 then return end
reaper.SetExtState("tab_scroll","t",tostring(now),false)
if (val > 0) ~= FLIP then reaper.Main_OnCommand(40862,0) else reaper.Main_OnCommand(40861,0) end
