-- @description Create Subproject
-- @author Grayson Solis
-- @version 1.0
-- @about 

local USER_INPUTS = true
local AUTO_NAME   = true

local function MODULE(file)
    local E,A=pcall(dofile,file);if not(E)then;reaper.ShowConsoleMsg("\n\nError - "..debug.getinfo(1,'S').source:match('.*[/\\](.+)')..'\nMISSING FILE / ОТСУТСТВУЕТ ФАЙЛ!\n'..file:gsub('\\','/'))return;end;
    if not A.VersArcFun("2.9.7",file,'')then;A=nil;return;end;return A;
end
local Arc = MODULE((reaper.GetResourcePath()..'/Scripts/Archie-ReaScripts/Functions/Arc_Function_lua.lua'):gsub('\\','/'))
if not Arc then return end

local CountSelTrack = reaper.CountSelectedTracks(0)
if CountSelTrack == 0 then no_undo() return end

local retval,projfn = reaper.EnumProjects(-1)
if projfn == '' then
    local buf = reaper.GetProjectPath('')
    local MB = reaper.MB('Project not saved.\n'..
                         'Recommend clicking cancel and saving the project to avoid losing the subproject in the future\n\n'..
                         'Subproject will be created along way.\n'..buf..'\n'..
                         ('-'):rep(55)..'\n\n\n'..
                         'Проект не сохранен.\n'..
                         'Рекомендую нажать отмена и сохранить проект, чтобы избежать потери подпроекта в дальнейшем.\n\n'..
                         'Подпроект создастся по пути.\n'..buf..'\n'..('-'):rep(55)
                         ,'Warning!',1)
    if MB == 2 then no_undo() return end
end

local FSelTrack = reaper.GetSelectedTrack(0,0)
local _,origName = reaper.GetTrackName(FSelTrack)
local origColor = reaper.GetTrackColor(FSelTrack)

local name = origName
if AUTO_NAME == false and USER_INPUTS == true then
    local x=#name*5
    local ret
    if x > 450 then x=450 end
    ret,name = reaper.GetUserInputs('Move tracks to subproject',1,'Enter folder name in directory,extrawidth='..x,name)
    if not ret then no_undo() return end
end

name = name:gsub('[\\/:*?"<>|+]','_')
if #name:gsub('%s','')==0 then
    name = 'no name (track '..math.ceil(reaper.GetMediaTrackInfo_Value(FSelTrack,'IP_TRACKNUMBER'))..')'
end

buf = reaper.GetProjectPath('')

local nmb = ''
local j
::restDir::
local N_Path = buf..'/'..name..nmb
local Dir = reaper.RecursiveCreateDirectory(N_Path,0)

if Dir <= 0 then
    j = (j or 1)+1
    nmb = '_('..j..')'
    goto restDir
else
    local mediaPath = N_Path..'/Media'
    reaper.RecursiveCreateDirectory(mediaPath, 0)

    local retval,valtrNB = reaper.GetSetProjectInfo_String(0,'RECORD_PATH','',0)
    reaper.GetSetProjectInfo_String(0,'RECORD_PATH',N_Path,1)
    Action(41997)
    reaper.GetSetProjectInfo_String(0,'RECORD_PATH',valtrNB,1)

    local targetName = origName..' - subproject'
    local function findAndRename()
        for i = 0, reaper.CountTracks(0)-1 do
            local track = reaper.GetTrack(0,i)
            local _,tname = reaper.GetTrackName(track)
            if tname == targetName then
                reaper.GetSetMediaTrackInfo_String(track,'P_NAME',origName,true)
                reaper.SetTrackColor(track, origColor)
                return
            end
        end
        reaper.defer(findAndRename)
    end
    reaper.defer(findAndRename)
end

no_undo()
