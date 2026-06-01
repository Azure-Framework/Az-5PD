
local function az5pdNormalizeJobName(name)
  return Az5PD.Framework.ExtractName(name)
end

local function az5pdGetAllowedJobs()
  return Az5PD.Framework.GetAllowedJobs()
end

local function az5pdStandaloneEnabled()
  return Az5PD and Az5PD.Framework and Az5PD.Framework.StandaloneEnabled()
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end
  
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(_x, _y)
  end

local function az5pdJobAllowed(jobName)
  return Az5PD.Framework.IsAllowedJob(jobName)
end

active                   = active                   or {}
promptId                 = promptId                 or nil
assignedCalloutsToMe     = assignedCalloutsToMe     or {}
pendingStatusChecks      = pendingStatusChecks      or {}
menuActive               = menuActive               or {}
registeredMenus          = registeredMenus          or {}
acceptingLock            = acceptingLock            or {}
pendingAction            = pendingAction            or {}  
dismissedCallouts       = dismissedCallouts       or {}

local END_DISTANCE_THRESHOLD = 75.0         
local STATUS_CHECK_TIMEOUT   = 30000        
local ACCEPT_LOCK_MS         = 5000         
local FORCE_HOLD_MS          = 5000         
local hHoldStart             = nil

local registerCalloutMenusOnce, openCalloutContextMenu, showActiveListMenu



local LightTester = {
    flash = {
        running = false,
        interval = 250,
        selected = {}
    },
    lightMode = {},
    fullbeam = {},
    indicators = {}
}

local lightModeLabels = {
    [0] = 'Normal',
    [1] = 'Force Off',
    [2] = 'Force On'
}

local showMainMenu, showBaseMenu, showExtrasMenu, showFlashMenu
local buildMainMenu, buildBaseMenu, buildExtrasMenu, buildFlashMenu

local function notify(msg, msgType)
    lib.notify({
        title = 'Light Tester',
        description = msg,
        type = msgType or 'inform'
    })
end

local function getVeh()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        notify('Get in a vehicle first.', 'error')
        return nil
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        notify('No current vehicle found.', 'error')
        return nil
    end

    return veh
end

local function getVehKey(veh)
    return tostring(veh)
end

local function getVehName(veh)
    local model = GetEntityModel(veh)
    local display = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(display)

    if not label or label == 'NULL' or label == '' then
        label = display
    end

    if not label or label == '' then
        label = ('Model %s'):format(model)
    end

    return label
end

local function getExtras(veh)
    local extras = {}

    for extraId = 1, 20 do
        if DoesExtraExist(veh, extraId) then
            extras[#extras + 1] = extraId
        end
    end

    return extras
end

local function hasSelectedFlashExtras()
    return next(LightTester.flash.selected) ~= nil
end

local function getFlashExtrasForVehicle(veh)
    local extras = {}

    if hasSelectedFlashExtras() then
        for extraId, enabled in pairs(LightTester.flash.selected) do
            if enabled and DoesExtraExist(veh, extraId) then
                extras[#extras + 1] = extraId
            end
        end
    else
        extras = getExtras(veh)
    end

    table.sort(extras)
    return extras
end

local function setExtraEnabled(veh, extraId, enabled)
    if not DoesExtraExist(veh, extraId) then
        return
    end

    
    SetVehicleExtra(veh, extraId, not enabled)
end

local function setAllExtras(veh, enabled)
    for _, extraId in ipairs(getExtras(veh)) do
        setExtraEnabled(veh, extraId, enabled)
    end
end

local function reopenMenu(menuFn)
    CreateThread(function()
        Wait(75)
        menuFn()
    end)
end

local function cycleLightMode(veh)
    local key = getVehKey(veh)
    local current = LightTester.lightMode[key] or 0
    local newMode = (current + 1) % 3

    LightTester.lightMode[key] = newMode
    SetVehicleLights(veh, newMode)

    return newMode
end

local function ensureIndicatorState(veh)
    local key = getVehKey(veh)

    if not LightTester.indicators[key] then
        LightTester.indicators[key] = {
            left = false,
            right = false
        }
    end

    return LightTester.indicators[key]
end

local function stopFlasher(veh)
    LightTester.flash.running = false

    if veh and DoesEntityExist(veh) then
        for _, extraId in ipairs(getFlashExtrasForVehicle(veh)) do
            setExtraEnabled(veh, extraId, true)
        end
    end
end

local function startFlasher(veh)
    if LightTester.flash.running then
        notify('Flasher is already running.', 'error')
        return
    end

    local extras = getFlashExtrasForVehicle(veh)
    if #extras == 0 then
        notify('No extras found on this vehicle.', 'error')
        return
    end

    LightTester.flash.running = true

    CreateThread(function()
        local phase = false

        while LightTester.flash.running do
            if not DoesEntityExist(veh) then
                break
            end

            if GetVehiclePedIsIn(PlayerPedId(), false) ~= veh then
                break
            end

            extras = getFlashExtrasForVehicle(veh)
            if #extras == 0 then
                break
            end

            phase = not phase

            if #extras == 1 then
                setExtraEnabled(veh, extras[1], phase)
            else
                for index, extraId in ipairs(extras) do
                    local enable = (index % 2 == 1) and phase or not phase
                    setExtraEnabled(veh, extraId, enable)
                end
            end

            Wait(LightTester.flash.interval)
        end

        LightTester.flash.running = false

        if DoesEntityExist(veh) then
            for _, extraId in ipairs(extras) do
                setExtraEnabled(veh, extraId, true)
            end
        end
    end)
end

local function configureFlasher()
    local veh = getVeh()
    if not veh then return end

    local extras = getExtras(veh)
    local options = {}
    local defaults = {}

    for _, extraId in ipairs(extras) do
        local value = tostring(extraId)

        options[#options + 1] = {
            value = value,
            label = ('Extra %d'):format(extraId)
        }

        if LightTester.flash.selected[extraId] then
            defaults[#defaults + 1] = value
        end
    end

    local input = lib.inputDialog('Flasher Settings', {
        {
            type = 'number',
            label = 'Flash interval (ms)',
            description = 'Lower = faster',
            default = LightTester.flash.interval,
            min = 50,
            max = 2000,
            required = true
        },
        {
            type = 'multi-select',
            label = 'Flash extras',
            description = 'Leave empty to use all detected extras',
            options = options,
            default = defaults
        }
    })

    if not input then
        return
    end

    local interval = tonumber(input[1])
    if interval then
        LightTester.flash.interval = math.floor(interval)
    end

    LightTester.flash.selected = {}

    local selected = input[2] or {}
    for _, value in ipairs(selected) do
        local extraId = tonumber(value)
        if extraId then
            LightTester.flash.selected[extraId] = true
        end
    end

    notify(('Updated flasher interval to %sms.'):format(LightTester.flash.interval), 'success')
end

buildBaseMenu = function(veh)
    local key = getVehKey(veh)
    local indicators = ensureIndicatorState(veh)
    local fullbeam = LightTester.fullbeam[key] or false
    local lightMode = LightTester.lightMode[key] or 0

    lib.registerContext({
        id = 'light_tester_base',
        title = ('Base Lights • %s'):format(getVehName(veh)),
        menu = 'light_tester_main',
        options = {
            {
                title = 'Toggle siren state',
                description = IsVehicleSirenOn(veh) and 'Currently ON' or 'Currently OFF',
                icon = 'bullhorn',
                onSelect = function()
                    SetVehicleSiren(veh, not IsVehicleSirenOn(veh))
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle siren audio',
                description = IsVehicleSirenAudioOn(veh) and 'Audio ON' or 'Audio MUTED',
                icon = 'volume-high',
                onSelect = function()
                    local audioOn = IsVehicleSirenAudioOn(veh)
                    SetVehicleHasMutedSirens(veh, audioOn)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Emergency lights only',
                description = 'Turns siren lights on and mutes the siren sound',
                icon = 'triangle-exclamation',
                onSelect = function()
                    SetVehicleSiren(veh, true)
                    SetVehicleHasMutedSirens(veh, true)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = ('Cycle light mode: %s'):format(lightModeLabels[lightMode]),
                description = 'Normal / Force Off / Force On',
                icon = 'lightbulb',
                onSelect = function()
                    local newMode = cycleLightMode(veh)
                    notify(('Light mode: %s'):format(lightModeLabels[newMode]), 'success')
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle interior light',
                description = IsVehicleInteriorLightOn(veh) and 'Currently ON' or 'Currently OFF',
                icon = 'car-side',
                onSelect = function()
                    SetVehicleInteriorlight(veh, not IsVehicleInteriorLightOn(veh))
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle full beam',
                description = fullbeam and 'Currently ON' or 'Currently OFF',
                icon = 'sun',
                onSelect = function()
                    local newState = not (LightTester.fullbeam[key] or false)
                    LightTester.fullbeam[key] = newState
                    SetVehicleFullbeam(veh, newState)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle left indicator',
                description = indicators.left and 'Currently ON' or 'Currently OFF',
                icon = 'arrow-left',
                onSelect = function()
                    indicators.left = not indicators.left
                    SetVehicleIndicatorLights(veh, 1, indicators.left)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle right indicator',
                description = indicators.right and 'Currently ON' or 'Currently OFF',
                icon = 'arrow-right',
                onSelect = function()
                    indicators.right = not indicators.right
                    SetVehicleIndicatorLights(veh, 0, indicators.right)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle hazards',
                description = (indicators.left and indicators.right) and 'Currently ON' or 'Currently OFF',
                icon = 'car-burst',
                onSelect = function()
                    local toggle = not (indicators.left and indicators.right)
                    indicators.left = toggle
                    indicators.right = toggle
                    SetVehicleIndicatorLights(veh, 1, toggle)
                    SetVehicleIndicatorLights(veh, 0, toggle)
                    reopenMenu(showBaseMenu)
                end
            },
            {
                title = 'Toggle searchlight',
                description = IsVehicleSearchlightOn(veh) and 'Currently ON' or 'Currently OFF',
                icon = 'magnifying-glass',
                onSelect = function()
                    SetVehicleSearchlight(veh, not IsVehicleSearchlightOn(veh), false)
                    reopenMenu(showBaseMenu)
                end
            }
        }
    })
end

buildExtrasMenu = function(veh)
    local options = {
        {
            title = 'Enable all extras',
            description = 'Turns every detected extra ON',
            icon = 'power-off',
            onSelect = function()
                setAllExtras(veh, true)
                reopenMenu(showExtrasMenu)
            end
        },
        {
            title = 'Disable all extras',
            description = 'Turns every detected extra OFF',
            icon = 'ban',
            onSelect = function()
                setAllExtras(veh, false)
                reopenMenu(showExtrasMenu)
            end
        }
    }

    local extras = getExtras(veh)

    if #extras == 0 then
        options[#options + 1] = {
            title = 'No extras found',
            description = 'This model does not appear to expose extras 1-20',
            icon = 'circle-info',
            readOnly = true
        }
    else
        for _, extraId in ipairs(extras) do
            local isOn = IsVehicleExtraTurnedOn(veh, extraId)
            local isSelected = LightTester.flash.selected[extraId] == true

            options[#options + 1] = {
                title = ('Extra %d'):format(extraId),
                description = ('State: %s • Flasher: %s'):format(
                    isOn and 'ON' or 'OFF',
                    isSelected and 'Selected' or 'Not selected'
                ),
                icon = 'toggle-on',
                progress = isOn and 100 or 0,
                colorScheme = isOn and 'green' or 'gray',
                metadata = {
                    { label = 'Extra ID', value = extraId },
                    { label = 'Current state', value = isOn and 'ON' or 'OFF' },
                    { label = 'Flasher selection', value = isSelected and 'Yes' or 'No' }
                },
                onSelect = function()
                    setExtraEnabled(veh, extraId, not isOn)
                    reopenMenu(showExtrasMenu)
                end
            }
        end
    end

    lib.registerContext({
        id = 'light_tester_extras',
        title = ('Extras • %s'):format(getVehName(veh)),
        menu = 'light_tester_main',
        options = options
    })
end

buildFlashMenu = function(veh)
    local selectedExtras = getFlashExtrasForVehicle(veh)
    local selectedText

    if hasSelectedFlashExtras() then
        if #selectedExtras > 0 then
            selectedText = table.concat(selectedExtras, ', ')
        else
            selectedText = 'None'
        end
    else
        selectedText = 'All available extras'
    end

    lib.registerContext({
        id = 'light_tester_flash',
        title = ('Flasher • %s'):format(getVehName(veh)),
        menu = 'light_tester_main',
        options = {
            {
                title = 'Start flasher',
                description = ('Interval: %sms'):format(LightTester.flash.interval),
                icon = 'play',
                onSelect = function()
                    startFlasher(veh)
                    reopenMenu(showFlashMenu)
                end
            },
            {
                title = 'Stop flasher',
                description = 'Stops flashing and leaves involved extras ON',
                icon = 'stop',
                onSelect = function()
                    stopFlasher(veh)
                    reopenMenu(showFlashMenu)
                end
            },
            {
                title = 'Configure flasher',
                description = 'Set speed and choose which extras flash',
                icon = 'sliders',
                metadata = {
                    { label = 'Interval', value = ('%sms'):format(LightTester.flash.interval) },
                    { label = 'Selected extras', value = selectedText }
                },
                onSelect = function()
                    configureFlasher()
                    reopenMenu(showFlashMenu)
                end
            },
            {
                title = 'Clear flash-extra selection',
                description = 'Reverts flashing to all detected extras',
                icon = 'eraser',
                onSelect = function()
                    LightTester.flash.selected = {}
                    notify('Flash-extra selection cleared. Using all extras.', 'success')
                    reopenMenu(showFlashMenu)
                end
            }
        }
    })
end

buildMainMenu = function(veh)
    buildBaseMenu(veh)
    buildExtrasMenu(veh)
    buildFlashMenu(veh)

    local extras = getExtras(veh)
    local flashExtras = getFlashExtrasForVehicle(veh)
    local flashText = hasSelectedFlashExtras()
        and (#flashExtras > 0 and table.concat(flashExtras, ', ') or 'None')
        or 'All available extras'

    lib.registerContext({
        id = 'light_tester_main',
        title = ('Light Tester • %s'):format(getVehName(veh)),
        options = {
            {
                title = ('Plate: %s'):format((GetVehicleNumberPlateText(veh) or ''):gsub('^%s*(.-)%s*$', '%1')),
                description = 'Current vehicle info',
                icon = 'car',
                readOnly = true,
                metadata = {
                    { label = 'Vehicle', value = getVehName(veh) },
                    { label = 'Detected extras', value = #extras },
                    { label = 'Flasher interval', value = ('%sms'):format(LightTester.flash.interval) },
                    { label = 'Flasher extras', value = flashText }
                }
            },
            {
                title = 'Base vehicle lights',
                description = 'Siren, light mode, interior, indicators, searchlight',
                menu = 'light_tester_base',
                icon = 'lightbulb'
            },
            {
                title = 'Vehicle extras',
                description = (#extras > 0)
                    and ('Found %d extra(s)'):format(#extras)
                    or 'No extras detected',
                menu = 'light_tester_extras',
                icon = 'sitemap'
            },
            {
                title = 'Flasher',
                description = 'Test wigwag/flash speed using selected extras',
                menu = 'light_tester_flash',
                icon = 'bolt'
            },
            {
                title = 'Reset tester state',
                description = 'Stops flasher and clears tester-side states',
                icon = 'rotate-left',
                onSelect = function()
                    local key = getVehKey(veh)

                    stopFlasher(veh)

                    LightTester.lightMode[key] = 0
                    LightTester.fullbeam[key] = false
                    LightTester.indicators[key] = {
                        left = false,
                        right = false
                    }

                    SetVehicleLights(veh, 0)
                    SetVehicleFullbeam(veh, false)
                    SetVehicleIndicatorLights(veh, 1, false)
                    SetVehicleIndicatorLights(veh, 0, false)
                    SetVehicleHasMutedSirens(veh, false)
                    SetVehicleInteriorlight(veh, false)

                    notify('Tester state reset for this vehicle.', 'success')
                    reopenMenu(showMainMenu)
                end
            }
        }
    })
end

showMainMenu = function()
    local veh = getVeh()
    if not veh then return end

    buildMainMenu(veh)
    lib.showContext('light_tester_main')
end

showBaseMenu = function()
    local veh = getVeh()
    if not veh then return end

    buildBaseMenu(veh)
    lib.showContext('light_tester_base')
end

showExtrasMenu = function()
    local veh = getVeh()
    if not veh then return end

    buildExtrasMenu(veh)
    lib.showContext('light_tester_extras')
end

showFlashMenu = function()
    local veh = getVeh()
    if not veh then return end

    buildFlashMenu(veh)
    lib.showContext('light_tester_flash')
end

RegisterCommand('lighttest', function()
    showMainMenu()
end, false)

RegisterKeyMapping('lighttest', 'Open vehicle light tester', 'keyboard', 'F7')

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh and veh ~= 0 then
        stopFlasher(veh)
    else
        LightTester.flash.running = false
    end
end)

local function isJobAllowed(job)
    return Az5PD.Framework.IsAllowedJob(job)
end

local function keyReleased(ctrl)
    return IsControlJustReleased(0, ctrl) or IsDisabledControlJustReleased(0, ctrl)
end

local function keyPressed(ctrl)
    return IsControlJustPressed(0, ctrl) or IsDisabledControlJustPressed(0, ctrl)
end

local function wantInput()

    local havePrompt = (promptId ~= nil)
    local haveStatus = false
    local now = GetGameTimer()
    if type(pendingStatusChecks) == "table" then
        for _, expiry in pairs(pendingStatusChecks) do
            if expiry and now <= expiry then haveStatus = true; break end
        end
    end
    return havePrompt or haveStatus
end

local function getPlayerJobFromServer(cb)
    assert(type(cb) == "function", "getPlayerJobFromServer requires callback")

    local instantJob = Az5PD.Framework.ClientJob()
    if instantJob and tostring(instantJob) ~= '' then
      cb(az5pdNormalizeJobName(instantJob))
      return
    end

    local evtName = "AzFR:responsePlayerJob"
    RegisterNetEvent(evtName)
    local handlerId
    local done = false
    handlerId = AddEventHandler(evtName, function(job)
        if done then return end
        done = true
        if handlerId then RemoveEventHandler(handlerId) end
        cb(az5pdNormalizeJobName(job))
    end)

    TriggerServerEvent("AzFR:requestPlayerJob")
    CreateThread(function()
      Wait(1500)
      if done then return end
      local fallbackJob = Az5PD.Framework.ClientJob()
      if fallbackJob and tostring(fallbackJob) ~= '' then
        done = true
        if handlerId then RemoveEventHandler(handlerId) end
        cb(az5pdNormalizeJobName(fallbackJob))
      end
    end)
end

local az5pdAuthState = false
local az5pdTargetState = false
local function az5pdCurrentClientJob()
  return Az5PD.Framework.ClientJob()
end

local function az5pdHasUiAccess()
  return Az5PD.Framework.ClientHasAccess()
end
local function az5pdSetAuthorized(state)
  az5pdAuthState = state == true
end

local function az5pdIsOnDutyState()
  local state = LocalPlayer and LocalPlayer.state or nil
  if state and state.az5pd_onDuty ~= nil then
    return state.az5pd_onDuty == true
  end
  return false
end

local function az5pdMDTAvailable()
  local names = ((Config and Config.MDT and Config.MDT.externalResourceNames) or (Config and Config.Callouts and Config.Callouts.mdtResourceFallbacks) or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' })
  for _, name in ipairs(names) do
    if name and name ~= '' then
      local state = GetResourceState(name)
      if state == 'started' or state == 'starting' then
        return true
      end
    end
  end
  return false
end

local function az5pdDutyNotify(kind, text)
  if type(lib) == 'table' and type(lib.notify) == 'function' then
    lib.notify({ title = 'Police', description = text, type = kind or 'inform', position = 'top-right' })
  else
    TriggerEvent('chat:addMessage', { args = { 'Police', text } })
  end
end

local function az5pdPrettyDeptLabel(name)
  local s = tostring(name or ''):gsub('_', ' ')
  return (s:gsub("(%a)([%w_']*)", function(a, b) return string.upper(a) .. string.lower(b) end))
end

local function az5pdOpenDutyDialog()
  local currentJob = az5pdCurrentClientJob()
  if not Az5PD.Framework.ClientHasAccess() and not az5pdJobAllowed(currentJob) then
    az5pdDutyNotify('error', 'You are not allowed to use Police duty.')
    return
  end
  if az5pdMDTAvailable() then
    az5pdDutyNotify('inform', 'Use Az-MDT to go on/off duty for Police.')
    return
  end
  if az5pdIsOnDutyState() then
    TriggerServerEvent('az5pd:setDutyState', false)
    return
  end
  local options, seen = {}, {}
  for _, jobName in ipairs((Config.AllowedJobs or az5pdGetAllowedJobs())) do
    local key = tostring(jobName):lower()
    if key ~= '' and not seen[key] then
      seen[key] = true
      options[#options + 1] = { value = key, label = az5pdPrettyDeptLabel(key) }
    end
  end
  if type(lib) ~= 'table' or type(lib.inputDialog) ~= 'function' or #options <= 1 then
    TriggerServerEvent('az5pd:setDutyState', true, currentJob or 'police')
    return
  end
  local input = lib.inputDialog('Select On-Duty Department', {{ type = 'select', label = 'Department', options = options, required = true }}, { allowCancel = true })
  if not input then return end
  TriggerServerEvent('az5pd:setDutyState', true, input[1])
end

RegisterNetEvent('az5pd:dutyNotify', function(kind, text)
  az5pdDutyNotify(kind == 'error' and 'error' or 'inform', text)
end)

local az5pdHudState = {
  focus = 'Stand by for dispatch',
  distance = '—',
  callCount = 0,
  actions = 'B MDT • F6 Police Menu • /policeduty'
}

local function az5pdPushStatusHud()
  local currentJob = az5pdCurrentClientJob() or 'police'
  local onDuty = az5pdIsOnDutyState()
  local show = az5pdHasUiAccess()
  if not show then
    SendNUIMessage({ action = 'status_hide' })
    return
  end

  local focus = az5pdHudState.focus
  if onDuty then
    focus = az5pdPrettyDeptLabel(LocalPlayer.state.az5pd_department or currentJob) .. ' • Await dispatch'
  elseif az5pdMDTAvailable() then
    focus = 'Open MDT and go on duty'
  else
    focus = 'Use /policeduty to go on duty'
  end

  local actions = az5pdHudState.actions
  if az5pdMDTAvailable() then
    actions = 'B MDT • F6 Police Menu • MDT Duty'
  end

  SendNUIMessage({
    action = 'status_update',
    show = true,
    duty = onDuty,
    callCount = tonumber(az5pdHudState.callCount or 0) or 0,
    focus = focus,
    distance = az5pdHudState.distance or '—',
    actions = actions
  })
end

RegisterNetEvent('az5pd:dutyStateUpdated', function(onDuty, department)
  if onDuty then
    az5pdDutyNotify('success', 'You are now on duty as ' .. az5pdPrettyDeptLabel(department or 'police') .. '.')
  else
    az5pdDutyNotify('inform', 'You are now off duty.')
  end
  az5pdPushStatusHud()
end)

CreateThread(function()
  while true do
    Wait(1500)
    az5pdPushStatusHud()
  end
end)

RegisterCommand('policeduty', function()
  az5pdOpenDutyDialog()
end, false)

local function az5pdIsAuthorizedNow()
  az5pdAuthState = Az5PD.Framework.ClientHasAccess() and az5pdIsOnDutyState()
  return az5pdAuthState == true
end

Citizen.CreateThread(function()
    local function __az5pd_init(job)

        print("[Az-FR | Core System] Access granted for job: " .. tostring(job))

        local contextOpenCount = 0
        local blockedControlsWhileMenu = {38,47,74,249,244,289,246}

        local function log(fmt, ...)
            local ok, s = pcall(string.format, fmt, ...)
            if ok and s then
                print(("[callouts-client] %s"):format(s))
            else
                print("[callouts-client] (log format error)")
            end
        end


        local function shouldUseMDTCalloutNotifications()
            local names = { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
            for _, name in ipairs(names) do
                if name and name ~= '' then
                    local state = GetResourceState(name)
                    if state == 'started' or state == 'starting' then
                        return true
                    end
                end
            end
            return false
        end

        local function doNotify(args)
            args = args or {}
            if type(lib) == "table" and type(lib.notify) == "function" then
                local payload = {
                    id = args.id,
                    title = args.title or "Callout",
                    description = args.description or "",
                    type = args.type or "inform",
                    icon = args.icon,
                    iconColor = args.iconColor,
                    position = args.position or "top-right",
                    duration = tonumber(args.duration) or 4500,
                    showDuration = args.showDuration ~= false,
                    style = {
                        backgroundColor = '#111827',
                        color = '#f9fafb',
                        boxShadow = 'none',
                        border = '1px solid rgba(255,255,255,0.08)',
                        ['.description'] = { color = '#d1d5db' },
                        ['.title'] = { color = '#ffffff' }
                    }
                }
                pcall(lib.notify, payload)
            else
                local title = args.title or ""
                local desc = args.description or ""
                BeginTextCommandThefeedPost("STRING")
                AddTextComponentString(("[%s] %s"):format(title, desc))
                EndTextCommandThefeedPostTicker(false, false)
            end
        end

        local function createBlip(coords, title)
            if not coords or not coords.x then return nil end
            local b = AddBlipForCoord(coords.x, coords.y, coords.z or 0.0)
            SetBlipSprite(b, 161)
            SetBlipAsShortRange(b, false)
            SetBlipScale(b, 0.9)
            SetBlipColour(b, 1)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(title or "Callout")
            EndTextCommandSetBlipName(b)
            return b
        end

        local function moveBlipToCoords(blip, coords)
            if blip and DoesBlipExist(blip) and coords and coords.x then
                SetBlipCoords(blip, coords.x + 0.0, coords.y + 0.0, coords.z or 0.0)
            end
        end

        local function removeBlip(b)
            if b and DoesBlipExist(b) then
                SetBlipRoute(b, false)
                SetBlipFlashes(b, false)
                RemoveBlip(b)
            end
        end

        local function genLocalId()
            local tries = 0
            while tries < 10000 do
                local id = tostring(math.random(1000, 9999))
                if not active[id] then return id end
                tries = tries + 1
            end
            return tostring(GetGameTimer() % 10000)
        end

        local function DrawText3D(x, y, z, text)
            local onScreen, _x, _y = World3dToScreen2d(x, y, z)
            if not onScreen then return end
            SetTextScale(0.35, 0.35)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 255, 255, 215)
            SetTextCentre(1)
            SetTextEntry("STRING")
            AddTextComponentString(text)
            DrawText(_x, _y)
        end

        local function getVehicleInFront(distance)
            local ped = PlayerPedId()
            local px, py, pz = table.unpack(GetEntityCoords(ped))
            local fwd = GetEntityForwardVector(ped)
            local toX, toY, toZ = px + fwd.x * distance, py + fwd.y * distance, pz + fwd.z * distance
            local ray = StartShapeTestRay(px, py, pz + 0.5, toX, toY, toZ, 10, ped, 0)
            local _, hit, _, _, entity = GetShapeTestResult(ray)
            if hit == 1 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
                return entity
            end
            return nil
        end

        local function cleanupLocalCallout(idstr)
            local e = active[idstr]
            if e then
                if e.cleanup and type(e.cleanup) == "function" then pcall(e.cleanup) end
                if type(e.entities) == "table" then
                    for _, ent in ipairs(e.entities) do
                        if DoesEntityExist(ent) then DeleteEntity(ent) end
                    end
                end
                if e.blip then removeBlip(e.blip) end
                e.sceneSpawned = nil
                active[idstr] = nil
            end
            assignedCalloutsToMe[idstr] = nil
            pendingStatusChecks[idstr] = nil
            menuActive[idstr] = nil
            dismissedCallouts[idstr] = nil
            if promptId == idstr then promptId = nil end
        end

        local function dismissLocalCallout(idstr, why)
            local e = active[idstr]
            if e then
                e.dismissed = true
                e.acceptPending = nil
                if e.blip and DoesBlipExist(e.blip) then
                    SetBlipRoute(e.blip, false)
                    SetBlipFlashes(e.blip, false)
                    SetBlipColour(e.blip, 5)
                end
            end
            dismissedCallouts[idstr] = why or true
            if promptId == idstr then promptId = nil end
            menuActive[idstr] = nil
        end

        local function forceEndCallout(idstr)
            if not idstr then return end
            pendingAction[idstr] = "end"
            cleanupLocalCallout(idstr)
            TriggerServerEvent("az5pd:callouts:end", idstr)
        end

        local function startEndAckFallback(idstr, timeoutMs)
            Citizen.CreateThread(function()
                local t0 = GetGameTimer()
                while pendingAction[idstr] == "end" and GetGameTimer() - t0 < (timeoutMs or 4000) do
                    Citizen.Wait(50)
                end
                if pendingAction[idstr] == "end" then
                    pendingAction[idstr] = nil
                    cleanupLocalCallout(idstr)
                    doNotify({
                        id = "callout_end_timeout_" .. idstr,
                        title = "Callout",
                        description = "No server response; ended locally.",
                        type = "warning",
                        duration = 4000
                    })
                    log("END fallback: cleaned up %s locally (server did not respond)", idstr)
                end
            end)
        end

        Citizen.CreateThread(function()
            Citizen.Wait(1000)
            if type(lib) == "table" then
                if type(lib.showContext) == "function" and not lib.__wrapped_showContext then
                    lib.__wrapped_showContext = lib.showContext
                    lib.showContext = function(id, ...)
                        contextOpenCount = contextOpenCount + 1
                        pcall(function() log("lib.showContext id=%s count=%d", tostring(id), contextOpenCount) end)
                        return lib.__wrapped_showContext(id, ...)
                    end
                end
                if type(lib.hideContext) == "function" and not lib.__wrapped_hideContext then
                    lib.__wrapped_hideContext = lib.hideContext
                    lib.hideContext = function(force, ...)
                        contextOpenCount = math.max(0, contextOpenCount - 1)
                        pcall(function() log("lib.hideContext count=%d", contextOpenCount) end)
                        return lib.__wrapped_hideContext(force, ...)
                    end
                end
            end
        end)

        local function hasAssignedCallout()
            for _, v in pairs(assignedCalloutsToMe) do if v then return true end end
            return false
        end

        local function acceptCallout(idstr)
            if not idstr then return end
            local now = GetGameTimer()
            if acceptingLock[idstr] and acceptingLock[idstr] > now then
                doNotify({ id = "callout_accept_lock_" .. idstr, title = "Callout", description = "Accept already in progress.", type = "warning", duration = 3000 })
                log("acceptCallout: already sending accept for id=%s, skipping", idstr)
                return
            end
            if hasAssignedCallout() then
                doNotify({ id = "callout_accept_blocked", title = "Callout", description = "You are already assigned to a callout — finish or end it first.", type = "warning", duration = 5000 })
                log("acceptCallout: blocked accept for %s because player already assigned", idstr)
                return
            end
            acceptingLock[idstr] = now + ACCEPT_LOCK_MS

            local e = active[idstr]
            pendingAction[idstr] = "accept"
            if e and e.data and e.data._localGenerated then
                e.data._originLocalId = idstr
                log("acceptCallout: sending accept_local for local-generated id=%s", idstr)
                TriggerServerEvent("az5pd:callouts:accept_local", e.data)
            else
                log("acceptCallout: sending accept for id=%s", idstr)
                TriggerServerEvent("az5pd:callouts:accept", idstr)
            end

            dismissedCallouts[idstr] = nil
            active[idstr] = active[idstr] or {}
            active[idstr].acceptPending = true

            doNotify({ id = "callout_accept_sent_" .. idstr, title = "Callout", description = "Requesting assignment for " .. tostring(idstr), type = "inform", duration = 3000 })
            if promptId == idstr then promptId = nil end
        end

        RegisterNetEvent("az5pd:callouts:request_position")
        AddEventHandler("az5pd:callouts:request_position", function(payload)
            local requestId = payload and payload.requestId
            if not requestId then return end
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local x, y, z = table.unpack(coords)
            TriggerServerEvent("az5pd:callouts:position_report", requestId, {x = x, y = y, z = z})
            log("CLIENT sent position report request=%s coords=%.1f,%.1f,%.1f", tostring(requestId), x, y, z)
        end)

        RegisterNetEvent("az5pd:callouts:new")
        AddEventHandler("az5pd:callouts:new", function(smallInst)
            if not smallInst or not smallInst.id then return end
            local idstr = tostring(smallInst.id)
            log("CLIENT az5pd:callouts:new id=%s title=%s template=%s", idstr, tostring(smallInst.title), tostring(smallInst.template))

            active[idstr] = active[idstr] or {}
            active[idstr].data = smallInst
            active[idstr].data.coords = smallInst.coords or active[idstr].data.coords
            active[idstr].accepted = active[idstr].accepted or false

            if not active[idstr].blip and active[idstr].data.coords then
                active[idstr].blip = createBlip(active[idstr].data.coords, active[idstr].data.title)
            end
            promptId = idstr

            if not shouldUseMDTCalloutNotifications() then
                doNotify({
                    id = "callout_received_" .. idstr,
                    title = "New Callout",
                    description = (smallInst.title or "Callout") .. " — Press E to accept, G to deny, or use /calls.",
                    type = "inform", position = "top-right", duration = 30000, icon = "bell"
                })
            end

            Citizen.CreateThread(function()
                local start = GetGameTimer()
                while GetGameTimer() - start < 30000 do
                    Citizen.Wait(200)
                    if not active[idstr] then return end
                    if active[idstr].accepted then return end
                end
                if active[idstr] and not active[idstr].accepted then
                    if promptId == idstr then promptId = nil end
                    doNotify({ id = "callout_prompt_expired_" .. idstr, title = "Callout", description = ("Prompt for callout %s timed out. It remains active in /calls until dispatch clears it."):format(idstr), type = "warning", duration = 5000 })
                    log("CLIENT prompt timeout for callout id=%s; keeping active until server clears it", idstr)
                end
            end)
        end)

        RegisterNetEvent("az5pd:callouts:accepted")
        AddEventHandler("az5pd:callouts:accepted", function(payload)
            if not payload or not payload.id then return end
            local idstr = tostring(payload.id)

            if payload.origLocalId then
                local old = tostring(payload.origLocalId)
                if active[old] then
                    log("accepted: cleaning up old local callout id=%s (now server id=%s)", old, idstr)
                    cleanupLocalCallout(old)
                end
                assignedCalloutsToMe[old] = nil
                pendingAction[old] = nil
                if promptId == old then promptId = nil end
            end

            dismissedCallouts[idstr] = nil
            active[idstr] = active[idstr] or {}
            active[idstr].data = active[idstr].data or {}
            active[idstr].data.assignedTo = payload.assignedTo
            active[idstr].data.responders = payload.responders or active[idstr].data.responders or {}
            active[idstr].data.myAttached = payload.myAttached == true
            if payload.title then active[idstr].data.title = payload.title end
            if payload.template then active[idstr].data.template = payload.template end
            if payload.coords then active[idstr].data.coords = payload.coords end
            active[idstr].accepted = true
            active[idstr].acceptPending = nil

            if active[idstr].blip and DoesBlipExist(active[idstr].blip) then
                SetBlipColour(active[idstr].blip, 3)
                SetBlipFlashes(active[idstr].blip, true)
                SetBlipRoute(active[idstr].blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(("[ASSIGNED] %s"):format(payload.title or "Callout"))
                EndTextCommandSetBlipName(active[idstr].blip)
            end

            local myServerId = GetPlayerServerId(PlayerId())
            local amAttached = payload.myAttached == true
            if not amAttached and type(payload.responders) == 'table' then
                for _, responder in ipairs(payload.responders) do
                    if responder and tostring(responder.id) == tostring(myServerId) then
                        amAttached = true
                        break
                    end
                end
            end
            if amAttached then
                for otherId, _ in pairs(assignedCalloutsToMe) do
                    if tostring(otherId) ~= idstr then
                        assignedCalloutsToMe[otherId] = nil
                    end
                end
                assignedCalloutsToMe[idstr] = true
                doNotify({
                    id = "callout_assigned_" .. idstr,
                    title = payload.joinedBy and tostring(payload.joinedBy) == tostring(myServerId) and "Callout Joined" or "Callout Assigned",
                    description = (payload.joinedBy and tostring(payload.joinedBy) == tostring(myServerId)) and ("You joined " .. tostring(payload.title or idstr) .. " as an attached unit. Use /call " .. idstr .. " or /calls, and press H to end when near the scene.") or ("You were assigned to " .. tostring(payload.title or idstr) .. ". Use /call " .. idstr .. " or /calls, and press H to end when near the scene."),
                    type = "inform", position = "top-right", duration = 8000, icon = "user-check"
                })
                pcall(function()
                    if registerCalloutMenusOnce(idstr) then
                        openCalloutContextMenu(idstr)
                        menuActive[idstr] = GetGameTimer() + 10000
                    end
                end)
            else
                assignedCalloutsToMe[idstr] = nil
                doNotify({
                    id = "callout_assigned_broadcast_" .. idstr,
                    title = "Callout Assigned",
                    description = ("Callout %s assigned to player %s"):format(payload.title or payload.id, tostring(payload.assignedTo)),
                    type = "inform", position = "top-right", duration = 5000
                })
            end

            if promptId == idstr then promptId = nil end
            pendingAction[idstr] = nil
            log("CLIENT received az5pd:callouts:accepted id=%s assignedTo=%s title=%s", idstr, tostring(payload.assignedTo), tostring(payload.title))
        end)

        RegisterNetEvent("az5pd:callouts:open_menu")
        AddEventHandler("az5pd:callouts:open_menu", function(calloutId)
            if not calloutId then return end
            local idstr = tostring(calloutId)
            active[idstr] = active[idstr] or { data = { id = idstr, title = "Callout " .. idstr } }
            active[idstr].data = active[idstr].data or {}
            active[idstr].data.id = idstr
            active[idstr].data.myAttached = true
            assignedCalloutsToMe[idstr] = true
            pcall(function() registerCalloutMenusOnce(idstr) end)
            pcall(function() openCalloutContextMenu(idstr) end)
            log("CLIENT received open_menu id=%s", tostring(calloutId))
        end)

        RegisterNetEvent("az5pd:callouts:cancelled")
        AddEventHandler("az5pd:callouts:cancelled", function(payload)
            if not payload or not payload.id then return end
            local idstr = tostring(payload.id)
            cleanupLocalCallout(idstr)
            doNotify({ id = "callout_cancel_" .. idstr, title = "Callout Cancelled", description = payload.title or idstr, type = "warning", position = "top-right", duration = 5000 })
            log("CLIENT received az5pd:callouts:cancelled id=%s", idstr)
        end)

        RegisterNetEvent("az5pd:callouts:denied_feedback")
        AddEventHandler("az5pd:callouts:denied_feedback", function(calloutId)
            if not calloutId then return end
            local idstr = tostring(calloutId)
            dismissLocalCallout(idstr, 'denied')
            doNotify({ id = "callout_denied_" .. idstr, title = "Callout", description = "Dismissed callout " .. idstr .. ". It stays active in /calls until it is taken or cleared.", type = "inform", duration = 3500 })
            log("CLIENT received az5pd:callouts:denied_feedback id=%s", idstr)
        end)

        RegisterNetEvent("az5pd:callouts:action_failed")
        AddEventHandler("az5pd:callouts:action_failed", function(calloutId, reason)
            local idstr = tostring(calloutId or "")
            local act   = pendingAction[idstr]; pendingAction[idstr] = nil
            if active[idstr] then
                active[idstr].acceptPending = nil
                if act == "accept" then
                    active[idstr].accepted = false
                end
            end
            assignedCalloutsToMe[idstr] = nil

            local friendly = tostring(reason or "unknown")
            if friendly == "ALREADY_ASSIGNED" then friendly = "You already have an assigned callout." end
            if friendly == "ALREADY_TAKEN" then friendly = "Another unit already took this callout." end
            if friendly == "NOT_ASSIGNED_TO_YOU" then friendly = "You are not assigned to that callout." end
            doNotify({ id = "callout_fail_" .. idstr, title = "Callout Error", description = friendly, type = "error", duration = 5000 })
            log("CLIENT action_failed id=%s reason=%s (pendingAction=%s)", idstr, tostring(reason), tostring(act))

            if tostring(reason) == "NOT_FOUND" and act == "accept" then
                local localEntry = active[idstr]
                if localEntry and localEntry.data then
                    local smallInst = {
                        template = localEntry.data.template,
                        coords   = localEntry.data.coords,
                        title    = localEntry.data.title,
                        _originLocalId = idstr
                    }
                    log("CLIENT fallback: accept_local for id=%s (template=%s)", idstr, tostring(smallInst.template))
                    TriggerServerEvent("az5pd:callouts:accept_local", smallInst)
                end

            elseif tostring(reason) == "NOT_FOUND" and act == "end" then

                log("CLIENT: end NOT_FOUND for id=%s -> cleaning up locally", idstr)
                cleanupLocalCallout(idstr)
                doNotify({ id = "callout_end_cleanup_" .. idstr, title = "Callout", description = "Callout not found server-side; cleaned up locally.", type = "inform", duration = 3000 })
            end
        end)


        local function calloutFindGroundZ(x, y, zHint)
            local startZ = (tonumber(zHint) or 30.0) + 25.0
            RequestCollisionAtCoord(x + 0.0, y + 0.0, startZ)
            local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, startZ, false)
            if found then return gz end
            for i = 1, 5 do
                Wait(0)
                RequestCollisionAtCoord(x + 0.0, y + 0.0, startZ + i)
                found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, startZ + i, false)
                if found then return gz end
            end
            return tonumber(zHint) or 30.0
        end

        local function calloutTemplatePrefersRoad(templateName)
            local name = tostring(templateName or ''):lower()
            return name:find('traffic', 1, true) ~= nil
                or name:find('vehicle', 1, true) ~= nil
                or name:find('driver', 1, true) ~= nil
                or name:find('collision', 1, true) ~= nil
                or name:find('hazard', 1, true) ~= nil
                or name:find('stolen', 1, true) ~= nil
                or name:find('reckless', 1, true) ~= nil
                or name:find('dui', 1, true) ~= nil
                or name:find('drunk', 1, true) ~= nil
                or name:find('pursuit', 1, true) ~= nil
                or name:find('asleep', 1, true) ~= nil
        end

        local function calloutGetClosestVehicleNodePosHeading(x, y, z)
            local r1, r2, r3, r4 = GetClosestVehicleNodeWithHeading(x + 0.0, y + 0.0, z + 0.0, 1, 3.0, 0)
            if type(r1) == 'boolean' then
                if not r1 then return nil, nil end
                if type(r2) == 'vector3' or type(r2) == 'table' then
                    return { x = (r2.x or x) + 0.0, y = (r2.y or y) + 0.0, z = (r2.z or z) + 0.0 }, tonumber(r3) or 0.0
                end
                return { x = tonumber(r2) or x, y = tonumber(r3) or y, z = tonumber(r4) or z }, 0.0
            end
            if type(r1) == 'vector3' or type(r1) == 'table' then
                return { x = (r1.x or x) + 0.0, y = (r1.y or y) + 0.0, z = (r1.z or z) + 0.0 }, tonumber(r2) or 0.0
            end
            return { x = tonumber(r1) or x, y = tonumber(r2) or y, z = tonumber(r3) or z }, tonumber(r4) or 0.0
        end

        local function calloutPickSidewalkishSpot(nodePos, heading, original)
            if not nodePos then return nil end
            local best, bestScore = nil, nil
            for _, side in ipairs({ 1.0, -1.0 }) do
                local ang = math.rad((tonumber(heading) or 0.0) + (90.0 * side))
                for _, dist in ipairs({ 3.0, 4.5, 6.0 }) do
                    local sx = nodePos.x + (math.cos(ang) * dist)
                    local sy = nodePos.y + (math.sin(ang) * dist)
                    local sz = calloutFindGroundZ(sx, sy, nodePos.z)
                    local dz = math.abs((sz or nodePos.z) - (nodePos.z or 0.0))
                    local dx, dy = sx - (original.x or sx), sy - (original.y or sy)
                    local score = (dz * 10.0) + math.sqrt((dx * dx) + (dy * dy))
                    if bestScore == nil or score < bestScore then
                        bestScore = score
                        best = { x = sx, y = sy, z = sz }
                    end
                end
            end
            return best
        end

        local function calloutFindLowerNearbyGround(x, y, z, radii)
            local current = calloutFindGroundZ(x, y, z)
            local best = { x = x, y = y, z = current }
            local scanRadii = radii or { 3.0, 6.0, 9.0, 12.0, 16.0, 22.0, 28.0, 36.0 }
            for _, radius in ipairs(scanRadii) do
                for ang = 0, 330, 30 do
                    local rad = math.rad(ang)
                    local sx = x + math.cos(rad) * radius
                    local sy = y + math.sin(rad) * radius
                    local sz = calloutFindGroundZ(sx, sy, z)
                    if sz and (not best or sz < (best.z or sz)) then
                        best = { x = sx, y = sy, z = sz }
                    end
                end
            end
            return best
        end

        local function calloutFindRoofEscapeSpot(x, y, z)
            local lower = calloutFindLowerNearbyGround(x, y, z, { 4.0, 8.0, 12.0, 18.0, 24.0, 32.0, 40.0 })
            if lower and ((z or 0.0) - (lower.z or z)) >= 1.85 then
                return lower
            end
            return nil
        end

        local function sanitizeCalloutCoords(templateName, coords)
            if type(coords) ~= 'table' or not coords.x then return coords end
            local original = { x = coords.x + 0.0, y = coords.y + 0.0, z = tonumber(coords.z) or 30.0 }
            local prefersRoad = calloutTemplatePrefersRoad(templateName)
            local groundZ = calloutFindGroundZ(original.x, original.y, original.z)
            local nodePos, nodeHeading = calloutGetClosestVehicleNodePosHeading(original.x, original.y, groundZ)
            local x, y, z = original.x, original.y, groundZ

            local nodeDx = nodePos and ((nodePos.x or original.x) - original.x) or 0.0
            local nodeDy = nodePos and ((nodePos.y or original.y) - original.y) or 0.0
            local nodeDist = nodePos and math.sqrt((nodeDx * nodeDx) + (nodeDy * nodeDy)) or 9999.0

            if prefersRoad and nodePos then
                x, y, z = nodePos.x, nodePos.y, calloutFindGroundZ(nodePos.x, nodePos.y, nodePos.z)
            else
                if nodePos and math.abs((groundZ or 0.0) - (nodePos.z or groundZ)) >= 2.0 and nodeDist <= 40.0 then
                    local sidewalk = calloutPickSidewalkishSpot(nodePos, nodeHeading, original)
                    if sidewalk then
                        x, y, z = sidewalk.x, sidewalk.y, sidewalk.z
                    else
                        x, y, z = nodePos.x, nodePos.y, calloutFindGroundZ(nodePos.x, nodePos.y, nodePos.z)
                    end
                else
                    local lower = calloutFindLowerNearbyGround(original.x, original.y, groundZ)
                    if lower and ((groundZ - (lower.z or groundZ)) >= 2.25) then
                        x, y, z = lower.x, lower.y, lower.z
                    end
                end
            end

            local escape = calloutFindRoofEscapeSpot(x, y, z)
            if escape then
                x, y, z = escape.x, escape.y, escape.z
            end

            return { x = x, y = y, z = z }
        end

        local function correctNearbyCalloutEntities(center, radius)
            if not center or not center.x then return end
            local r = tonumber(radius) or 16.0
            local function within(entity)
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                local c = GetEntityCoords(entity)
                local dx, dy, dz = c.x - center.x, c.y - center.y, c.z - center.z
                return ((dx * dx) + (dy * dy) + (dz * dz)) <= (r * r)
            end
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and within(ped) then
                    local c = GetEntityCoords(ped)
                    local fix = calloutFindRoofEscapeSpot(c.x, c.y, c.z)
                    if fix then
                        SetEntityCoordsNoOffset(ped, fix.x, fix.y, (fix.z or c.z) + 0.05, false, false, false)
                    else
                        local gz = calloutFindGroundZ(c.x, c.y, c.z)
                        if gz and math.abs((c.z or 0.0) - gz) > 0.75 then
                            SetEntityCoordsNoOffset(ped, c.x, c.y, gz + 0.05, false, false, false)
                        end
                    end
                end
            end
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if within(veh) then
                    local c = GetEntityCoords(veh)
                    local fix = calloutFindRoofEscapeSpot(c.x, c.y, c.z)
                    if fix then
                        SetEntityCoordsNoOffset(veh, fix.x, fix.y, (fix.z or c.z) + 0.4, false, false, false)
                    end
                    SetVehicleOnGroundProperly(veh)
                end
            end
            for _, obj in ipairs(GetGamePool('CObject')) do
                if within(obj) then
                    local c = GetEntityCoords(obj)
                    local fix = calloutFindRoofEscapeSpot(c.x, c.y, c.z)
                    if fix then
                        SetEntityCoordsNoOffset(obj, fix.x, fix.y, (fix.z or c.z) + 0.05, false, false, false)
                    end
                    PlaceObjectOnGroundProperly(obj)
                end
            end
        end

        RegisterNetEvent("az5pd:callouts:spawn_entities")
        AddEventHandler("az5pd:callouts:spawn_entities", function(spawnPacket)
            if not spawnPacket or not spawnPacket.id then return end

            local myServerId = GetPlayerServerId(PlayerId())
            if spawnPacket.assignedTo and tostring(spawnPacket.assignedTo) ~= tostring(myServerId) then
                log("CLIENT ignoring spawn_entities for id=%s assignedTo=%s (me=%s)", tostring(spawnPacket.id), tostring(spawnPacket.assignedTo), tostring(myServerId))
                return
            end

            local idstr = tostring(spawnPacket.id)
            active[idstr] = active[idstr] or {}
            if active[idstr].sceneSpawned then
                log("CLIENT ignoring duplicate spawn_entities for id=%s", idstr)
                return
            end
            active[idstr].data = active[idstr].data or {}
            active[idstr].data.status = "SPAWNED"
            active[idstr].data.id = idstr
            if spawnPacket.title then active[idstr].data.title = spawnPacket.title end
            if spawnPacket.template then active[idstr].data.template = spawnPacket.template end
            active[idstr].data.coords = active[idstr].data.coords or spawnPacket.coords

            if type(spawnPacket.clientScript) ~= "string" then
                doNotify({ id = "callout_spawn_no_script_" .. idstr, title = "Callout Spawn", description = "No client script available for " .. tostring(idstr), type = "error", duration = 5000 })
                log("CLIENT spawn_entities: no clientScript for id=%s", idstr)
                return
            end

            local chunk, err = load(spawnPacket.clientScript, "callout_client:" .. tostring(spawnPacket.template))
            if not chunk then
                log("clientScript compile error: %s", tostring(err))
                doNotify({ id = "callout_spawn_compile_error_" .. idstr, title = "Callout", description = "Client script compile error", type = "error", duration = 5000 })
                return
            end
            local ok, scenarioFunc = pcall(chunk)
            if not ok then
                log("clientScript runtime error: %s", tostring(scenarioFunc))
                doNotify({ id = "callout_spawn_runtime_error_" .. idstr, title = "Callout", description = "Client script runtime error", type = "error", duration = 5000 })
                return
            end
            if type(scenarioFunc) ~= "function" then
                doNotify({ id = "callout_spawn_badfunc_" .. idstr, title = "Callout", description = "Client script must return function(coords)", type = "error", duration = 5000 })
                log("CLIENT spawn_entities bad return type for id=%s", idstr)
                return
            end

            local spawnCoords = sanitizeCalloutCoords(spawnPacket.template, spawnPacket.coords)
            active[idstr].data.coords = spawnCoords or active[idstr].data.coords
            moveBlipToCoords(active[idstr].blip, active[idstr].data.coords)
            local ok2, result = pcall(scenarioFunc, spawnCoords or spawnPacket.coords)
            if not ok2 then
                log("scenario execution error: %s", tostring(result))
                doNotify({ id = "callout_spawn_exec_error_" .. idstr, title = "Callout", description = "Scenario execution error", type = "error", duration = 5000 })
                return
            end

            active[idstr].cleanup = nil
            active[idstr].entities = nil
            active[idstr].sceneSpawned = true
            if type(result) == "function" then
                active[idstr].cleanup = result
            elseif type(result) == "table" then
                active[idstr].entities = result
                active[idstr].cleanup = function()
                    if type(result) == "table" then
                        for _, ent in ipairs(result) do
                            if DoesEntityExist(ent) then DeleteEntity(ent) end
                        end
                    end
                end
            end

            CreateThread(function()
                Wait(350)
                correctNearbyCalloutEntities(spawnCoords or spawnPacket.coords, 18.0)
                Wait(850)
                correctNearbyCalloutEntities(spawnCoords or spawnPacket.coords, 18.0)
            end)

            doNotify({ id = "callout_spawned_" .. idstr, title = "Callout", description = "Scenario spawned: " .. tostring(spawnPacket.title or idstr), type = "inform", duration = 5000 })
            log("CLIENT spawn_entities completed for id=%s", idstr)
        end)

        RegisterNetEvent("az5pd:callouts:ended")
        AddEventHandler("az5pd:callouts:ended", function(payload)
            if not payload or not payload.id then return end
            local idstr = tostring(payload.id)
            cleanupLocalCallout(idstr)
            pendingAction[idstr] = nil
            doNotify({ id = "callout_ended_" .. idstr, title = "Callout Ended", description = ("Callout %s ended by %s"):format(payload.template or idstr, tostring(payload.endedBy)), type = "success", duration = 5000 })
            log("CLIENT received az5pd:callouts:ended id=%s endedBy=%s", idstr, tostring(payload.endedBy))
        end)

        RegisterNetEvent("az5pd:callouts:status_check")
        AddEventHandler("az5pd:callouts:status_check", function(pkt)
            if not pkt or not pkt.id then return end
            local idstr = tostring(pkt.id)
            active[idstr] = active[idstr] or { data = { id = idstr, title = pkt.title or ("Callout " .. idstr) } }
            active[idstr].data = active[idstr].data or {}
            active[idstr].data.myAttached = true
            assignedCalloutsToMe[idstr] = true
            pendingStatusChecks[idstr] = GetGameTimer() + STATUS_CHECK_TIMEOUT
            doNotify({
                id = "callout_status_" .. idstr,
                title = "Dispatch Status Check",
                description = ("Dispatch: Are you on scene for '%s'? Open /call %s or press E to confirm."):format(pkt.title or idstr, idstr),
                type = "inform", position = "top", duration = STATUS_CHECK_TIMEOUT, icon = "bell"
            })
            log("CLIENT pending status check set for id=%s", idstr)
        end)

        RegisterNetEvent("az5pd:callouts:status_response_ack")
        AddEventHandler("az5pd:callouts:status_response_ack", function(pkt)
            if not pkt or not pkt.id then return end
            local idstr = tostring(pkt.id)
            pendingStatusChecks[idstr] = nil
            doNotify({ id = "callout_status_ack_" .. idstr, title = "Dispatch", description = "Status response received.", type = "success", position = "top", duration = 4000 })
            log("CLIENT received status_response_ack for id=%s", idstr)
        end)

        RegisterNetEvent("az5pd:callouts:player_update")
        AddEventHandler("az5pd:callouts:player_update", function(pkt)
            if not pkt or not pkt.id then return end
            local idstr = tostring(pkt.id)
            local entry = active[idstr]
            if entry and type(pkt.responders) == 'table' then
                entry.data = entry.data or {}
                entry.data.responders = pkt.responders
            end
            if entry and pkt.assignedTo then
                entry.data = entry.data or {}
                entry.data.assignedTo = pkt.assignedTo
            end
            local action = pkt.action or ""
            local name = pkt.name or ("Player" .. tostring(pkt.player or "unknown"))
            if action == "backup_requested" then
                local coords = pkt.payload and pkt.payload.coords
                local coordStr = coords and ((" @ %.1f, %.1f"):format(coords.x or 0, coords.y or 0)) or ""
                doNotify({ id = "callout_backup_req_" .. idstr, title = "Backup Requested", description = ("Backup requested for %s by %s%s"):format(idstr, name, coordStr), type = "warning", duration = 8000, icon = "shield" })
            else
                doNotify({ id = "callout_player_update_" .. idstr, title = "Callout Update", description = ("%s: %s"):format(name, tostring(action)), type = "inform", duration = 5000 })
            end
            log("CLIENT player_update id=%s action=%s from=%s", idstr, tostring(action), tostring(name))
        end)

        local function distToCallout(idstr)
            local e = active and active[idstr]
            if not e or not e.data or not e.data.coords then return 999999 end
            local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
            local cx, cy, cz = e.data.coords.x, e.data.coords.y, e.data.coords.z
            local dx, dy, dz = px - cx, py - cy, pz - cz
            return math.sqrt(dx * dx + dy * dy + dz * dz)
        end

        local isCalloutOwnedByMe

        function registerCalloutMenusOnce(idstr)
            if type(lib) ~= "table" or type(lib.registerContext) ~= "function" then
                log("ox_lib not available; cannot register context menu for %s", idstr)
                return false
            end

            local entry = active[idstr]
            if not entry or not entry.data then
                log("cannot register menu for missing callout %s", tostring(idstr))
                return false
            end

            local title = ("Callout %s - %s"):format(idstr, entry.data.title or "unknown")
            local assignedToMe = isCalloutOwnedByMe(idstr)
            local isAccepted = entry.accepted == true or assignedToMe
            local joinAsBackup = isAccepted and not assignedToMe

            local ok, err = pcall(function()
                lib.registerContext({
                    id = "callout_menu_" .. idstr,
                    title = title,
                    options = {
                        {
                            title = joinAsBackup and "Join Callout" or "Accept Callout",
                            description = assignedToMe and "You are already attached to this callout." or (joinAsBackup and "Attach as a second unit so your completion clears with the primary." or "Take this callout if it is still active."),
                            icon = "check",
                            disabled = assignedToMe,
                            onSelect = function()
                                log("CLIENT menu Accept selected for id=%s", idstr)
                                acceptCallout(idstr)
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Deny Callout",
                            description = assignedToMe and "Use End Callout if you are clearing the scene." or "Decline this callout.",
                            icon = "times",
                            disabled = assignedToMe,
                            onSelect = function()
                                log("CLIENT menu Deny selected for id=%s", idstr)
                                TriggerServerEvent("az5pd:callouts:deny", idstr)
                                dismissLocalCallout(idstr, 'denied')
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Status Reply",
                            description = "Send a status reply (On Scene / En Route / Need Assistance).",
                            icon = "bell",
                            disabled = not assignedToMe,
                            menu = "callout_status_" .. idstr,
                            arrow = true
                        },
                        {
                            title = "Request Backup",
                            description = "Request backup at your current position.",
                            icon = "shield",
                            disabled = not assignedToMe,
                            onSelect = function()
                                local ped = PlayerPedId()
                                local coords = GetEntityCoords(ped)
                                local x, y, z = table.unpack(coords)
                                local myName = tostring(GetPlayerName(PlayerId()) or ("Player" .. tostring(GetPlayerServerId(PlayerId()))))
                                log("CLIENT menu Request Backup for id=%s coords=%.1f,%.1f,%.1f by=%s", idstr, x, y, z, myName)
                                TriggerServerEvent("az5pd:callouts:request_backup", idstr, {
                                    coords = {x = x, y = y, z = z},
                                    fromName = myName,
                                    message = "Officer " .. myName .. " requests backup at the scene."
                                })
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "End Callout",
                            description = "End this callout for every attached unit.",
                            icon = "flag-checkered",
                            disabled = not assignedToMe,
                            onSelect = function()
                                log("CLIENT menu End Callout selected for id=%s", idstr)
                                pendingAction[idstr] = "end"
                                TriggerServerEvent("az5pd:callouts:end", idstr)
                                startEndAckFallback(idstr, 4000)
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Force End Callout",
                            description = "Force clear this callout from your menu immediately.",
                            icon = "triangle-exclamation",
                            disabled = not assignedToMe and not isAccepted,
                            onSelect = function()
                                log("CLIENT menu Force End Callout selected for id=%s", idstr)
                                forceEndCallout(idstr)
                                doNotify({ id = "callout_force_end_menu_" .. idstr, title = "Callout", description = "Force-ended callout " .. tostring(idstr), type = "warning", duration = 4000 })
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "List Active Callouts",
                            description = "See every active callout and jump to one.",
                            icon = "list",
                            arrow = true,
                            onSelect = function()
                                showActiveListMenu(idstr) 
                            end
                        },
                        {
                            title = "Close",
                            description = "Close the menu.",
                            icon = "times",
                            onSelect = function() lib.hideContext(true) end
                        }
                    }
                })

                lib.registerContext({
                    id = "callout_status_" .. idstr,
                    title = "Status - " .. (entry.data.title or idstr),
                    menu = "callout_menu_" .. idstr,
                    options = {
                        {
                            title = "On Scene",
                            description = "Confirm you are on scene.",
                            icon = "map-marker-alt",
                            onSelect = function()
                                log("CLIENT menu Status On Scene for id=%s", idstr)
                                TriggerServerEvent("az5pd:callouts:status_response", idstr, {response = "ON_SCENE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "En Route",
                            description = "You're en route to the callout.",
                            icon = "route",
                            onSelect = function()
                                log("CLIENT menu Status En Route for id=%s", idstr)
                                TriggerServerEvent("az5pd:callouts:status_response", idstr, {response = "EN_ROUTE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Need Assistance",
                            description = "Request immediate assistance.",
                            icon = "exclamation-triangle",
                            onSelect = function()
                                log("CLIENT menu Status Need Assistance for id=%s", idstr)
                                TriggerServerEvent("az5pd:callouts:status_response", idstr, {response = "NEED_ASSISTANCE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Back",
                            description = "Go back to callout menu.",
                            icon = "arrow-left",
                            onSelect = function() lib.showContext("callout_menu_" .. idstr) end
                        }
                    }
                })
            end)

            if not ok then
                log("error registering menus for %s: %s", idstr, tostring(err))
                return false
            end
            registeredMenus[idstr] = GetGameTimer()
            return true
        end

        function openCalloutContextMenu(idstr)
            if not registerCalloutMenusOnce(idstr) then
                doNotify({ id = "callout_menu_no_lib", title = "Callout Menu", description = "Context menu library not available or registration failed.", type = "warning", duration = 5000 })
                return
            end
            if type(lib) ~= "table" or type(lib.showContext) ~= "function" then
                doNotify({ id = "callout_menu_no_show", title = "Callout Menu", description = "lib.showContext not available.", type = "error", duration = 5000 })
                return
            end
            local ok, err = pcall(function() lib.showContext("callout_menu_" .. idstr) end)
            if not ok then
                log("lib.showContext failed for %s: %s", idstr, tostring(err))
                doNotify({ id = "callout_menu_show_err", title = "Callout Menu", description = "Failed to open context menu: " .. tostring(err), type = "error", duration = 5000 })
            else
                log("CLIENT opened context menu for id=%s", idstr)
            end
        end

        local function _buildActiveListOptions(backId)
            local opts, count = {}, 0
            for id, v in pairs(active) do
                count = count + 1
                local ttl = ("[%s] %s"):format(tostring(id), (v.data and v.data.title) or "unknown")
                local desc = dismissedCallouts[tostring(id)] and "Dismissed locally" or (v.accepted and "Accepted" or "Unassigned")
                table.insert(opts, {
                    title = ttl,
                    description = desc,
                    icon = v.accepted and "user-check" or "bell",
                    onSelect = function() openCalloutContextMenu(tostring(id)) end
                })
            end
            if count == 0 then
                table.insert(opts, { title = "No active callouts", icon = "minus", disabled = true })
            end
            if backId then
                table.insert(opts, {
                    title = "Back",
                    description = "Return to callout " .. tostring(backId),
                    icon = "arrow-left",
                    onSelect = function() lib.showContext("callout_menu_" .. tostring(backId)) end
                })
            end
            table.insert(opts, { title = "Refresh", icon = "rotate", onSelect = function() showActiveListMenu(backId) end })
            table.insert(opts, { title = "Close",   icon = "times",  onSelect = function() lib.hideContext(true) end })
            return opts
        end

        function showActiveListMenu(backId)
            if type(lib) ~= "table" or type(lib.registerContext) ~= "function" then
                doNotify({ id = "callout_list_no_lib", title = "Callout Menu", description = "Context menu library not available.", type = "error", duration = 4000 })
                return
            end
            local ok, err = pcall(function()
                lib.registerContext({
                    id = "callout_list_menu",
                    title = "Active Callouts",
                    options = _buildActiveListOptions(backId)
                })
                lib.showContext("callout_list_menu")
            end)
            if not ok then
                log("showActiveListMenu error: %s", tostring(err))
                doNotify({ id = "callout_list_err", title = "Callout Menu", description = "Failed to open list: " .. tostring(err), type = "error", duration = 4000 })
            end
        end

        isCalloutOwnedByMe = function(idstr)
            if not idstr then return false end
            if assignedCalloutsToMe[idstr] == true then return true end
            local myServerId = tostring(GetPlayerServerId(PlayerId()))
            local entry = active[idstr]
            if entry and entry.data then
                if entry.data.myAttached == true then return true end
                if tostring(entry.data.assignedTo or '') == myServerId then return true end
                if type(entry.data.responders) == 'table' then
                    for _, responder in ipairs(entry.data.responders) do
                        if responder and tostring(responder.id) == myServerId then
                            return true
                        end
                    end
                end
            end
            return false
        end

        local function getAssignedCalloutId()
            for id, entry in pairs(active) do
                if isCalloutOwnedByMe(tostring(id)) then return tostring(id) end
            end
            for k, v in pairs(assignedCalloutsToMe) do if v then return k end end
            return nil
        end

        local function resolveCommandCalloutId(raw)
            local idarg = raw and tostring(raw) or nil
            if idarg and idarg ~= "" then return idarg end
            if promptId then return tostring(promptId) end
            local assignedId = getAssignedCalloutId()
            if assignedId then return tostring(assignedId) end
            for id, entry in pairs(active) do
                if entry and isCalloutOwnedByMe(tostring(id)) then return tostring(id) end
            end
            for id, entry in pairs(active) do
                if entry and entry.accepted then return tostring(id) end
            end
            return nil
        end

        local function sendCalloutStatusFromCommand(response)
            local id = getAssignedCalloutId()
            if not id then
                doNotify({ id = "callout_status_no_assigned", title = "Callout", description = "You do not have an assigned callout.", type = "warning", duration = 3500 })
                return
            end
            TriggerServerEvent("az5pd:callouts:status_response", id, { response = response })
            doNotify({ id = "callout_status_cmd_" .. tostring(id), title = "Callout", description = "Sent status " .. tostring(response) .. " for " .. tostring(id), type = "success", duration = 3000 })
        end

        RegisterCommand("callout_menu", function(source, args)
            local idarg = args[1]

            if idarg and (idarg == "list" or idarg == "all") then
                showActiveListMenu(nil)
                return
            end

            if not idarg then
                local assignedId = getAssignedCalloutId()
                if assignedId then openCalloutContextMenu(assignedId); return end
                local lines = {}
                for k, v in pairs(active) do
                    table.insert(lines, ("ID %s: %s"):format(k, (v.data and v.data.title) or "unknown"))
                end
                if #lines == 0 then
                    doNotify({ id = "callout_menu_none", title = "Callout Menu", description = "No active callouts.", type = "inform", duration = 4000 })
                else
                    doNotify({ id = "callout_menu_list", title = "Callout Menu", description = table.concat(lines, " / "), type = "inform", duration = 8000 })
                end
                log("CLIENT /callout_menu listed %d entries", #lines)
                return
            end

            openCalloutContextMenu(tostring(idarg))
        end, false)

        RegisterCommand("calls", function(_, args)
            local idarg = args and args[1] or nil
            if idarg and (idarg == "list" or idarg == "all") then
                showActiveListMenu(nil)
                return
            end
            if idarg and active[tostring(idarg)] then
                openCalloutContextMenu(tostring(idarg))
                return
            end
            local assignedId = getAssignedCalloutId()
            if assignedId then
                openCalloutContextMenu(assignedId)
                return
            end
            showActiveListMenu(nil)
        end, false)

        RegisterCommand("call", function(_, args)
            local id = resolveCommandCalloutId(args and args[1] or nil)
            if not id then
                doNotify({ id = "callout_call_none", title = "Callout", description = "No active callout to open.", type = "warning", duration = 3500 })
                return
            end
            openCalloutContextMenu(tostring(id))
        end, false)

        RegisterCommand("acceptcall", function(_, args)
            local id = resolveCommandCalloutId(args and args[1] or nil)
            if not id then
                doNotify({ id = "callout_accept_none", title = "Callout", description = "No callout available to accept.", type = "warning", duration = 3500 })
                return
            end
            acceptCallout(tostring(id))
        end, false)

        RegisterCommand("denycall", function(_, args)
            local id = resolveCommandCalloutId(args and args[1] or nil)
            if not id then
                doNotify({ id = "callout_deny_none", title = "Callout", description = "No callout available to deny.", type = "warning", duration = 3500 })
                return
            end
            TriggerServerEvent("az5pd:callouts:deny", tostring(id))
            dismissLocalCallout(tostring(id), 'denied')
        end, false)

        RegisterCommand("endcall", function(_, args)
            local id = resolveCommandCalloutId(args and args[1] or nil)
            if not id then
                doNotify({ id = "callout_end_none", title = "Callout", description = "No assigned callout to end.", type = "warning", duration = 3500 })
                return
            end
            pendingAction[tostring(id)] = "end"
            TriggerServerEvent("az5pd:callouts:end", tostring(id))
            startEndAckFallback(tostring(id), 4000)
        end, false)

        RegisterCommand("backupcall", function(_, args)
            local id = resolveCommandCalloutId(args and args[1] or nil)
            if not id then
                doNotify({ id = "callout_backup_none", title = "Callout", description = "No assigned callout to request backup for.", type = "warning", duration = 3500 })
                return
            end
            local coords = GetEntityCoords(PlayerPedId())
            local x, y, z = table.unpack(coords)
            local myName = tostring(GetPlayerName(PlayerId()) or ("Player" .. tostring(GetPlayerServerId(PlayerId()))))
            TriggerServerEvent("az5pd:callouts:request_backup", tostring(id), {
                coords = { x = x, y = y, z = z },
                fromName = myName,
                message = "Officer " .. myName .. " requests backup at the scene."
            })
        end, false)

        RegisterCommand("callstatus", function(_, args)
            local raw = tostring((args and args[1]) or "")
            local normalized = raw:gsub("%s+", ""):upper()
            if normalized == "SCENE" or normalized == "ONSCENE" or normalized == "OS" then
                sendCalloutStatusFromCommand("ON_SCENE")
                return
            end
            if normalized == "ENROUTE" or normalized == "ER" then
                sendCalloutStatusFromCommand("EN_ROUTE")
                return
            end
            if normalized == "ASSIST" or normalized == "HELP" or normalized == "BACKUP" then
                sendCalloutStatusFromCommand("NEED_ASSISTANCE")
                return
            end
            doNotify({ id = "callout_status_usage", title = "Callout", description = "Usage: /callstatus scene, /callstatus enroute, or /callstatus assist.", type = "inform", duration = 4500 })
        end, false)

        Citizen.CreateThread(function()
            while true do
                local menuOpen = (contextOpenCount > 0) or IsNuiFocused()
                local hasPendingStatus = next(pendingStatusChecks) ~= nil
                local activePrompt = promptId ~= nil
                local authorized = az5pdIsAuthorizedNow()
                if not authorized and not menuOpen and not hasPendingStatus and not activePrompt then
                    Citizen.Wait(500)
                else
                    Citizen.Wait(0)
                end

                local readingInputs = (not menuOpen) or wantInput()

                if menuOpen then
                    for _, ctrl in ipairs(blockedControlsWhileMenu) do
                        DisableControlAction(0, ctrl, true)
                    end
                end

                if readingInputs then

                    if keyReleased(38) then
                        local answered = false
                        for id, expiry in pairs(pendingStatusChecks) do
                            if expiry and GetGameTimer() <= expiry then
                                TriggerServerEvent("az5pd:callouts:status_response", id, {response = "ON_SCENE"})
                                pendingStatusChecks[id] = nil
                                doNotify({ id = "callout_status_resp_sent_" .. id, title = "Status", description = "Confirmed on-scene for " .. id, type = "success", duration = 3000 })
                                log("E: replied ON_SCENE for id=%s", tostring(id))
                                answered = true
                                break
                            else
                                pendingStatusChecks[id] = nil
                            end
                        end
                        if not answered and promptId then
                            local idstr = tostring(promptId)
                            log("E: accepting promptId=%s", idstr)
                            acceptCallout(idstr)
                            promptId = nil
                        end
                    end

                    if keyReleased(47) then
                        if promptId then
                            local idstr = tostring(promptId)
                            log("G: denying promptId=%s", idstr)
                            TriggerServerEvent("az5pd:callouts:deny", idstr)
                            dismissLocalCallout(idstr, 'denied')
                            doNotify({ id = "callout_deny_sent_" .. idstr, title = "Callout", description = "Dismissed callout " .. idstr .. ". It remains active in /calls.", type = "inform", duration = 3500 })
                            promptId = nil
                        end
                    end

                    if keyPressed(74) and hHoldStart == nil then
                        hHoldStart = GetGameTimer()
                    end
                    if keyReleased(74) then
                        local heldFor = hHoldStart and (GetGameTimer() - hHoldStart) or 0
                        hHoldStart = nil
                        if heldFor >= FORCE_HOLD_MS then

                            for id, assigned in pairs(assignedCalloutsToMe) do
                                if assigned then
                                    log("H held: force ending id=%s", id)
                                    forceEndCallout(id)
                                    doNotify({ id = "callout_force_end_" .. id, title = "Callout", description = "Force-ended callout " .. tostring(id), type = "warning", duration = 4000 })
                                end
                            end
                        else

                            for id, assigned in pairs(assignedCalloutsToMe) do
                                if assigned then
                                    if distToCallout(id) <= END_DISTANCE_THRESHOLD then
                                        log("H: requesting end for id=%s", id)
                                        pendingAction[id] = "end"
                                        TriggerServerEvent("az5pd:callouts:end", id)
                                        startEndAckFallback(id, 4000)
                                        doNotify({ id = "callout_end_sent_" .. id, title = "Callout", description = "Requested end for " .. tostring(id), type = "inform", duration = 3000 })
                                    else
                                        doNotify({ id = "callout_end_too_far", title = "Callout", description = "Too far from callout " .. tostring(id) .. " to end.", type = "warning", duration = 3000 })
                                    end
                                end
                            end
                        end
                    end
                end

                local now = GetGameTimer()
                for id, expiry in pairs(menuActive) do
                    if now > expiry then
                        menuActive[id] = nil
                        if promptId == id then promptId = nil end
                    end
                end
                for id, expiry in pairs(pendingStatusChecks) do
                    if expiry and now > expiry then
                        pendingStatusChecks[id] = nil
                        doNotify({ id = "callout_status_expired_" .. id, title = "Dispatch", description = "Status check expired for " .. tostring(id), type = "warning", duration = 3000 })
                        log("status check expired for id=%s", tostring(id))
                    end
                end

                if IsControlPressed(0, 21) then
                    local veh = getVehicleInFront(12.0)
                    if veh and DoesEntityExist(veh) and IsEntityAVehicle(veh) then
                        local vx, vy, vz = table.unpack(GetEntityCoords(veh))
                        DrawMarker(2, vx, vy, vz + 1.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.6, 255, 255, 0, 150, false, false, 2, false, nil, nil, false)
                        local model = GetEntityModel(veh)
                        local display = GetDisplayNameFromVehicleModel(model) or "VEH"
                        local plate = GetVehicleNumberPlateText(veh) or ""
                        DrawText3D(vx, vy, vz + 1.5, string.format("%s [%s]", display, plate))
                    end
                end
            end
        end)

        do
            local cfg = Config and Config.Callouts
            local function titleCase(s) return s:gsub("(%S+)", function(word) return word:sub(1,1):upper() .. (word:sub(2) or "") end) end

            if not cfg then
                log("Config.Callouts not found; local callout generator disabled. Add a Config.Callouts table in your config.lua.")
            else
                local range = cfg.calltimeRange
                local minT = range and tonumber(range.min)
                local maxT = range and tonumber(range.max)
                local unit = (range and range.unit) and tostring(range.unit) or "minutes"
                if not cfg.generatorEnabled then
                    log("Config.Callouts.generatorEnabled is false; generator disabled.")
                elseif not minT or not maxT or minT <= 0 or maxT < minT then
                    log("Invalid Config.Callouts.calltimeRange; generator disabled.")
                else
                    local minDist = tonumber(cfg.minDistanceFromPlayer) or 60.0
                    local maxDist = tonumber(cfg.maxDistanceFromPlayer) or 400.0
                    local minBetween = tonumber(cfg.minDistanceBetweenCallouts or 120.0)
                    local notifyOnGenerate = cfg.notifyOnGenerate ~= false
                    local useServer = cfg.useServerCreation == true or cfg.useServer == true

                    local WEATHER_HASH = {}
                    for _, n in ipairs({
                        "EXTRASUNNY","CLEAR","CLOUDS","SMOG","FOGGY","OVERCAST",
                        "RAIN","THUNDER","CLEARING","NEUTRAL","SNOW","SNOWLIGHT","BLIZZARD","XMAS","HALLOWEEN"
                    }) do WEATHER_HASH[GetHashKey(n)] = n end

                    local function rangeToMs(minv, maxv, unitv)
                        local mult = (unitv == "seconds") and 1000 or 60000
                        local rmin = math.floor(minv)
                        local rmax = math.floor(maxv)
                        local base = (rmax == rmin) and rmin or math.random(rmin, rmax)
                        return base * mult
                    end

                    local function isQuietHour()
                        local q = cfg.quietHours
                        if not q then return false end
                        local h = GetClockHours() or 0
                        return q[h] == true
                    end

                    local function weatherBlacklisted()
                        local bl = cfg.blacklistWeather
                        if not bl or next(bl) == nil then return false end
                        local w1, w2 = GetWeatherTypeTransition()
                        local n1 = WEATHER_HASH[w1] or "NEUTRAL"
                        local n2 = WEATHER_HASH[w2] or n1
                        return bl[n1] or bl[n2] or false
                    end

                    local function getTimeOfDayWeight()
                        local tcfg = cfg.timeOfDay or {}
                        local hour = GetClockHours() or 12
                        if tcfg.byHour and tcfg.byHour[hour] then
                            return tonumber(tcfg.byHour[hour]) or 1.0
                        end
                        if hour >= 5 and hour <= 7  then return tcfg.dawn  or 1.0 end
                        if hour >= 8 and hour <= 18 then return tcfg.day   or 1.0 end
                        if hour >= 19 and hour <= 21 then return tcfg.dusk  or 1.0 end
                        return tcfg.night or 1.0
                    end

                    local function getWeatherWeight()
                        local w1, w2, pct = GetWeatherTypeTransition()
                        local n1 = WEATHER_HASH[w1] or "NEUTRAL"
                        local n2 = WEATHER_HASH[w2] or n1
                        local ww = cfg.weatherWeights or {}
                        local a  = tonumber(ww[n1]) or 1.0
                        local b  = tonumber(ww[n2]) or a
                        pct = tonumber(pct) or 0.0
                        return (a * (1.0 - pct)) + (b * pct)
                    end

                    local function getDayOfWeekWeight()
                        local dow = GetClockDayOfWeek() or 0
                        dow = dow % 7  
                        local map = cfg.dayOfWeekWeights or {}
                        return tonumber(map[dow]) or 1.0
                    end

                    local function countActive()
                        local c = 0
                        for _ in pairs(active or {}) do c = c + 1 end
                        return c
                    end

                    local function tooCloseToExisting(pos, minD)
                        if not active then return false end
                        for _, e in pairs(active) do
                            local d = e.data and e.data.coords
                            if d and d.x then
                                local dx, dy = pos.x - d.x, pos.y - d.y
                                if (dx*dx + dy*dy) <= (minD*minD) then return true end
                            end
                        end
                        return false
                    end

                    local function templateWantsRoadSpawn(templateId)
                        local name = tostring(templateId or ''):lower()
                        return name:find('traffic', 1, true) ~= nil
                            or name:find('vehicle', 1, true) ~= nil
                            or name:find('driver', 1, true) ~= nil
                            or name:find('collision', 1, true) ~= nil
                            or name:find('hazard', 1, true) ~= nil
                            or name:find('stolen', 1, true) ~= nil
                            or name:find('reckless', 1, true) ~= nil
                            or name:find('drunk', 1, true) ~= nil
                            or name:find('pursuit', 1, true) ~= nil
                            or name:find('asleep', 1, true) ~= nil
                    end

                    local function pickSpawnCoords(templateId)
                        local ped = PlayerPedId()
                        local px, py, pz = table.unpack(GetEntityCoords(ped))
                        local last = { x = px + 50.0, y = py + 50.0, z = pz }

                        local maxAttempts = 24

                        for i = 1, maxAttempts do
                            local dist = math.random(math.floor(minDist), math.floor(maxDist))
                            local ang  = math.rad(math.random(0, 359))
                            local nx   = px + (dist * math.cos(ang))
                            local ny   = py + (dist * math.sin(ang))
                            local ok, gz = GetGroundZFor_3dCoord(nx, ny, pz + 50.0, 0)
                            local nz   = (ok and gz) or pz
                            local pos  = { x = nx, y = ny, z = nz }
                            last = pos

                            if not tooCloseToExisting(pos, minBetween) then

                                local waterFound, waterZ = GetWaterHeight(pos.x, pos.y, pos.z)
                                if waterFound then

                                    goto continue_try
                                end

                                local wantsRoad = templateWantsRoadSpawn(templateId)
                                local streetHash, crossingHash = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
                                if wantsRoad then
                                    local okNode, nx2, ny2, nz2 = GetClosestVehicleNode(pos.x, pos.y, pos.z, 1, 3.0, 0)
                                    if okNode then
                                        local nodePos = { x = nx2, y = ny2, z = nz2 }
                                        local roadStreetHash = select(1, GetStreetNameAtCoord(nodePos.x, nodePos.y, nodePos.z))
                                        if roadStreetHash and roadStreetHash ~= 0 and not tooCloseToExisting(nodePos, minBetween) then
                                            return nodePos
                                        end
                                    end
                                elseif streetHash and streetHash ~= 0 then
                                    return pos
                                end

                                local okSafe, sx, sy, sz = GetSafeCoordForPed(pos.x, pos.y, pos.z, true, 16)
                                if okSafe and sx and not tooCloseToExisting({ x = sx, y = sy, z = sz }, minBetween) then
                                    return { x = sx, y = sy, z = sz }
                                end

                            end

                            ::continue_try::
                        end

                        return last
                    end

                    local function loadTemplatesFromManifest()
                        local resource = GetCurrentResourceName()
                        local ok, data = pcall(LoadResourceFile, resource, "manifest.json")
                        if not ok or not data then
                            local ok2, data2 = pcall(LoadResourceFile, resource, "callouts/manifest.json")
                            if ok2 and data2 then data = data2 end
                        end
                        if not data then return nil end
                        local success, parsed = pcall(json.decode, data)
                        if not success or type(parsed) ~= "table" then return nil end
                        local arr = {}
                        if #parsed > 0 then
                            for _, v in ipairs(parsed) do if type(v) == "string" then table.insert(arr, v) end end
                        elseif parsed["callouts"] and type(parsed["callouts"]) == "table" then
                            for _, v in ipairs(parsed["callouts"]) do if type(v) == "string" then table.insert(arr, v) end end
                        elseif parsed["files"] and type(parsed["files"]) == "table" then
                            for _, v in ipairs(parsed["files"]) do if type(v) == "string" then table.insert(arr, v) end end
                        end
                        return (#arr > 0) and arr or nil
                    end

                    local function buildTemplatesFromList(list)
                        local out = {}
                        for _, v in ipairs(list) do
                            local id = tostring(v)
                            local ttitle = id:gsub("%.callout$", ""):gsub("[._%-]+", " "):gsub("^%s*(.-)%s*$", "%1")
                            ttitle = titleCase(ttitle)
                            table.insert(out, {id = id, title = ttitle})
                        end
                        return out
                    end

                    local templatesRaw = loadTemplatesFromManifest() or {"Suspicious Activity"}
                    local templates = buildTemplatesFromList(templatesRaw)

                    local function pickTemplate()
                        local t = templates[math.random(1, #templates)]
                        return t.id, t.title
                    end

                    local lastSpawnAt = 0

                    Citizen.CreateThread(function()
                        log("Local callout generator enabled (global weighted, no per-.callout config).")
                        while true do

                            if (Config and Config.Jobs and Config.Jobs.requireJob) and not az5pdIsAuthorizedNow() then
                                Citizen.Wait(5000)
                            elseif isQuietHour() or weatherBlacklisted() then
                                Citizen.Wait(5000)
                            else

                                local baseWait = rangeToMs(minT, maxT, unit)
                                local mul = (getTimeOfDayWeight() * getWeatherWeight() * getDayOfWeekWeight())
                                mul = math.max(0.25, math.min(mul, 5.0)) 
                                local waitMs = math.floor(baseWait / mul)

                                local gap   = tonumber(cfg.cooldownBetweenSpawnsMs) or 0
                                local now   = GetGameTimer()
                                local since = now - (lastSpawnAt or 0)
                                local need  = math.max(waitMs, gap)
                                local extra = math.max(0, need - since)
                                Citizen.Wait(extra)

                                if not (Config and Config.Callouts and Config.Callouts.generatorEnabled) then
                                    log("Generator toggled off; stopping.")
                                    return
                                end

                                if (function()
                                    local c=0; for _ in pairs(active or {}) do c=c+1 end; return c
                                end)() >= (cfg.maxSimultaneous or 5) then
                                    Citizen.Wait(2000)
                                else
                                    local templateId, title = pickTemplate()
                                    local coords = pickSpawnCoords(templateId)
                                    local idstr = genLocalId()
                                    local playerPos = GetEntityCoords(PlayerPedId())
                                    local smallInst = {
                                        id = idstr,
                                        title = title,
                                        coords = coords,
                                        template = templateId,
                                        playerCoords = { x = playerPos.x + 0.0, y = playerPos.y + 0.0, z = playerPos.z + 0.0 }
                                    }

                                    if notifyOnGenerate then
                                        doNotify({
                                            id = "callout_gen_" .. idstr,
                                            title = "Generated Callout",
                                            description = ("Generated '%s' @ %.0f, %.0f"):format(title, coords.x or 0, coords.y or 0),
                                            type = "inform", duration = 4000
                                        })
                                    end

                                    if useServer then
                                        TriggerServerEvent("az5pd:callouts:request_generate", smallInst)
                                        log("CLIENT requested server to create callout: %s (%s)", tostring(title), tostring(templateId))
                                    else
                                        smallInst._localGenerated = true
                                        TriggerEvent("az5pd:callouts:new", smallInst)
                                        log("CLIENT locally generated callout: %s (%s) id=%s", tostring(title), tostring(templateId), idstr)
                                    end

                                    lastSpawnAt = GetGameTimer()
                                end
                            end
                        end
                    end)
                end
            end
        end

        AddEventHandler("onResourceStop", function(name)
            if name == GetCurrentResourceName() then
                for _, e in pairs(active) do
                    if e and e.blip then removeBlip(e.blip) end
                    if e and e.cleanup and type(e.cleanup) == "function" then pcall(e.cleanup) end
                end
                active = {}
                promptId = nil
                assignedCalloutsToMe = {}
                pendingStatusChecks = {}
                menuActive = {}
                registeredMenus = {}
                contextOpenCount = 0
                log("resource stopped, cleaned up")
            end
        end)

        log("callouts client loaded (complete).")
    end

    local function waitForFrameworkReady(timeoutMs)
        if Az5PD.Framework.ActiveKind() ~= nil then return true end
        local untilT = GetGameTimer() + (timeoutMs or 15000)
        while GetGameTimer() < untilT do
            if Az5PD.Framework.ActiveKind() ~= nil then
                return true
            end
            Wait(250)
        end
        return false
    end

    if not waitForFrameworkReady(15000) then
        print("[Az-5PD] No supported framework detected yet; continuing to wait for job sync...")
    end

    Wait(200) 

    local function getJobSync(timeoutMs)
        local job, done = nil, false
        getPlayerJobFromServer(function(j)
            job = j
            done = true
        end)
        local untilT = GetGameTimer() + (timeoutMs or 4000)
        while (not done) and (GetGameTimer() < untilT) do
            Wait(25)
        end
        return job
    end

    local tries = 0
    while true do
        tries = tries + 1
        local job = getJobSync(5000)

        if job == nil then
            if (tries % 10) == 1 then
                print("[Az-FR | Core System] Waiting for framework job (join-in-progress)... attempt " .. tostring(tries))
            end
        elseif Az5PD.Framework.ClientHasAccess() or isJobAllowed(job) then
            __az5pd_init(job)
            return
        else
            if (tries % 30) == 1 then
                print("[Az-FR | Core System] Restricted mode idle; waiting for an allowed job. current=" .. tostring(job))
            end
            az5pdSetAuthorized(false)
        end

        Wait(1000)
    end
end)
