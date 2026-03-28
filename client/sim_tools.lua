Config = Config or {}

if Config.Sim and Config.Sim.enabled == false then
  return
end

local SimClient = {
  state = {
    shift = nil,
    incident = nil,
    recent = {},
    dispatch = {},
    bolos = {},
    weekly = nil,
    emergencyTraffic = nil,
    lastTarget = nil,
    pendingMenu = nil,
    pendingStateToken = nil,
    syncMessage = nil,
    hudVisible = (Config.Sim == nil or Config.Sim.overlayEnabled ~= false),
    hudEditorOpen = false,
  }
}

local openMainMenu, openShiftMenu, openDispatchMenu, openSceneMenu, openStopsMenu, openReportsMenu, openTrainingMenu, openPolicyMenu
local openSimUi, closeSimUi, refreshSimUi, requestStateAndOpen, menuToSection, buildRecommendedAction
local SimUi = { open = false, section = 'overview' }

local function openIntegratedSimMdt(section)
  if type(Az5PDOpenIntegratedMDT) == 'function' then
    local ok, opened = pcall(Az5PDOpenIntegratedMDT, { page = 'simTools', section = section or 'overview' })
    if ok and opened then return true end
  end
  return false
end

local function simNotify(title, description, ntype)
  if lib and lib.notify then
    lib.notify({ title = title, description = description, type = ntype or 'inform' })
  end
end

local function trimText(value, maxLen)
  value = tostring(value or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if maxLen and #value > maxLen then value = value:sub(1, maxLen) end
  return value
end

local function myServerId()
  return GetPlayerServerId(PlayerId())
end

local function safeNetId(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return 0 end
  local ok, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
  if ok and netId and netId ~= 0 then return netId end
  return 0
end

local function hashToWeatherLabel(hash)
  local map = {
    [GetHashKey('EXTRASUNNY')] = 'EXTRASUNNY',
    [GetHashKey('CLEAR')] = 'CLEAR',
    [GetHashKey('CLOUDS')] = 'CLOUDS',
    [GetHashKey('OVERCAST')] = 'OVERCAST',
    [GetHashKey('RAIN')] = 'RAIN',
    [GetHashKey('THUNDER')] = 'THUNDER',
    [GetHashKey('FOGGY')] = 'FOGGY',
    [GetHashKey('SMOG')] = 'SMOG',
    [GetHashKey('XMAS')] = 'XMAS',
    [GetHashKey('HALLOWEEN')] = 'HALLOWEEN',
    [GetHashKey('SNOW')] = 'SNOW',
  }
  return map[hash] or 'UNKNOWN'
end

local function currentWeatherLabel()
  local ok, hash = pcall(GetPrevWeatherTypeHashName)
  if ok and hash then return hashToWeatherLabel(hash) end
  return 'UNKNOWN'
end

local function getStreetAt(coords)
  local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local street = GetStreetNameFromHashKey(streetHash)
  local cross = crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or ''
  if cross and cross ~= '' then
    return ('%s / %s'):format(street, cross)
  end
  return street ~= '' and street or 'Unknown Street'
end

local function getEntityLabel(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return 'Unknown' end
  if IsEntityAVehicle(entity) then
    local model = GetEntityModel(entity)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(model))
    if not name or name == 'NULL' or name == '' then name = GetDisplayNameFromVehicleModel(model) end
    return trimText(name, 64)
  elseif IsEntityAPed(entity) then
    return trimText(('Ped %s'):format(GetEntityModel(entity)), 64)
  end
  return ('Entity %s'):format(entity)
end

local function captureTarget(entity, targetType)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
  local coords = GetEntityCoords(entity)
  local target = {
    entity = entity,
    targetType = targetType or (IsEntityAVehicle(entity) and 'vehicle' or 'ped'),
    targetNetId = IsEntityAPed(entity) and safeNetId(entity) or 0,
    vehicleNetId = IsEntityAVehicle(entity) and safeNetId(entity) or 0,
    coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
    subjectLabel = getEntityLabel(entity),
    subjectModel = tostring(GetEntityModel(entity) or 0),
    street = getStreetAt(coords),
    weather = currentWeatherLabel(),
    hour = GetClockHours(),
  }
  if IsEntityAVehicle(entity) then
    target.plate = trimText(GetVehicleNumberPlateText(entity), 24)
  elseif IsEntityAPed(entity) and IsPedInAnyVehicle(entity, false) then
    local veh = GetVehiclePedIsIn(entity, false)
    if veh and veh ~= 0 then
      target.vehicleNetId = safeNetId(veh)
      target.plate = trimText(GetVehicleNumberPlateText(veh), 24)
    end
  end
  SimClient.state.lastTarget = target
  return target
end

local function getClosestPed(radius)
  local player = PlayerPedId()
  local playerCoords = GetEntityCoords(player)
  local handle, ped = FindFirstPed()
  local success = true
  local bestPed, bestDist
  repeat
    if ped ~= player and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
      local coords = GetEntityCoords(ped)
      local dist = #(coords - playerCoords)
      if dist <= radius and (not bestDist or dist < bestDist) then
        bestPed, bestDist = ped, dist
      end
    end
    success, ped = FindNextPed(handle)
  until not success
  EndFindPed(handle)
  return bestPed, bestDist
end

local function getClosestVehicle(radius)
  local player = PlayerPedId()
  local playerCoords = GetEntityCoords(player)
  local handle, veh = FindFirstVehicle()
  local success = true
  local bestVeh, bestDist
  repeat
    if veh ~= 0 and DoesEntityExist(veh) then
      local coords = GetEntityCoords(veh)
      local dist = #(coords - playerCoords)
      if dist <= radius and (not bestDist or dist < bestDist) then
        bestVeh, bestDist = veh, dist
      end
    end
    success, veh = FindNextVehicle(handle)
  until not success
  EndFindVehicle(handle)
  return bestVeh, bestDist
end

local function getWorkingTarget(preferred)
  local last = SimClient.state.lastTarget
  if last and last.entity and DoesEntityExist(last.entity) then
    return captureTarget(last.entity, last.targetType)
  end
  if preferred == 'vehicle' then
    local veh = getClosestVehicle(10.0)
    if veh then return captureTarget(veh, 'vehicle') end
  end
  local ped = getClosestPed(8.0)
  if ped then return captureTarget(ped, 'ped') end
  local veh = getClosestVehicle(10.0)
  if veh then return captureTarget(veh, 'vehicle') end
  return nil
end

local function statusLabel(key)
  local list = (Config.Sim and Config.Sim.shiftStatuses) or {}
  for i = 1, #list do if list[i].key == key then return list[i].label end end
  return tostring(key or 'Unknown')
end

local function incidentStatusLabel(key)
  local list = (Config.Sim and Config.Sim.incidentStatuses) or {}
  for i = 1, #list do if list[i].key == key then return list[i].label end end
  return tostring(key or 'Unknown')
end

local function incidentTypeLabel(key)
  local list = (Config.Sim and Config.Sim.incidentTypes) or {}
  for i = 1, #list do if list[i].key == key then return list[i].label end end
  return tostring(key or 'Unknown')
end

local function roleLabel(key)
  local list = (Config.Sim and Config.Sim.roles) or {}
  for i = 1, #list do if list[i].key == key then return list[i].label end end
  return tostring(key or 'Unit')
end

requestStateAndOpen = function(menu)
  local targetSection = menuToSection and menuToSection(menu) or (menu or 'overview')
  SimClient.state.pendingMenu = menu or 'overview'
  SimClient.state.section = targetSection
  SimClient.state.pendingStateToken = GetGameTimer()
  SimClient.state.syncMessage = 'Syncing state from server...'
  if openIntegratedSimMdt(targetSection) then
    TriggerEvent('az_mdt:client:simState', {
      section = targetSection,
      shift = SimClient.state.shift,
      incident = SimClient.state.incident,
      recent = SimClient.state.recent or {},
      dispatch = SimClient.state.dispatch or {},
      bolos = SimClient.state.bolos or {},
      weekly = SimClient.state.weekly or {},
      emergencyTraffic = SimClient.state.emergencyTraffic or nil,
      syncMessage = SimClient.state.syncMessage or nil,
      recommendedAction = buildRecommendedAction(),
    })
    TriggerServerEvent('az5pd:sim:requestState')
    return
  end
  if openSimUi then
    openSimUi(targetSection)
  end
  TriggerServerEvent('az5pd:sim:requestState')
end

local function getMyRoleOnIncident(incident)
  if not incident or not incident.roles then return nil end
  local sid = myServerId()
  for i = 1, #incident.roles do
    if tonumber(incident.roles[i].src) == sid then
      return incident.roles[i]
    end
  end
  return nil
end

buildRecommendedAction = function()
  local shift = SimClient.state.shift
  local incident = SimClient.state.incident
  if not shift then return 'Start your shift.' end
  if not incident then
    if SimClient.state.dispatch and #SimClient.state.dispatch > 0 then
      return 'Claim or open a dispatch call.'
    end
    return 'Open a new scene from a ped or vehicle.'
  end
  if not incident.stop or not incident.stop.reason or incident.stop.reason == '' then return 'Record the stop or contact reason.' end
  if incident.context and incident.context.targetType == 'vehicle' and (not incident.vehicle or (incident.vehicle.plateStatus or 'unknown') == 'unknown') then return 'Run vehicle return / VIN check.' end
  if not incident.stop or incident.stop.idOutcome == 'pending' then return 'Run identity / license check.' end
  if incident.search and incident.search.mode ~= 'none' and (not incident.probableCause or #incident.probableCause == 0) and incident.search.mode ~= 'consent_granted' then return 'Document your legal basis before searching.' end
  if incident.scene and incident.scene.safe == false then return 'Mark the scene safe or unsafe.' end
  if not incident.reportPreview then return 'Generate the report preview before closeout.' end
  if incident.scene and incident.scene.reportPending then return 'Finish the report and close the scene.' end
  return 'Scene looks documented. Close it when ready.'
end

menuToSection = function(menu)
  local map = {
    main = 'overview',
    overview = 'overview',
    shift = 'shift',
    dispatch = 'dispatch',
    scene = 'scene',
    stops = 'stops',
    reports = 'reports',
    training = 'training',
    policy = 'policy',
  }
  return map[tostring(menu or 'overview')] or 'overview'
end

local function buildSimUiPayload()
  return {
    section = SimClient.state.pendingMenu and menuToSection(SimClient.state.pendingMenu) or (SimClient.state.section or 'overview'),
    shift = SimClient.state.shift,
    incident = SimClient.state.incident,
    recent = SimClient.state.recent or {},
    dispatch = SimClient.state.dispatch or {},
    bolos = SimClient.state.bolos or {},
    weekly = SimClient.state.weekly or {},
    emergencyTraffic = SimClient.state.emergencyTraffic or nil,
    syncMessage = SimClient.state.syncMessage or nil,
    recommendedAction = buildRecommendedAction(),
  }
end

local function syncMdtBridge()
  TriggerEvent('az_mdt:client:simState', buildSimUiPayload())
end

local function sendSimUiMessage(action)
  SendNUIMessage({ action = action, payload = buildSimUiPayload() })
end

local function refreshSimHud()
  SendNUIMessage({ action = 'sim:hud', payload = { hide = true, remove = true } })
end

openSimUi = function(section)
  SimClient.state.section = menuToSection(section)
  SimUi = SimUi or { open = false, section = 'overview' }
  SimUi.section = SimClient.state.section
  SimUi.open = true
  SetNuiFocus(true, true)
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
  sendSimUiMessage('sim:open')
end

closeSimUi = function()
  SimUi = SimUi or { open = false, section = 'overview' }
  if not SimUi.open then return end
  SimUi.open = false
  SetNuiFocus(false, false)
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
  SendNUIMessage({ action = 'sim:close' })
end

refreshSimUi = function()
  SimUi = SimUi or { open = false, section = 'overview' }
  if SimUi.open then
    sendSimUiMessage('sim:update')
  end
  syncMdtBridge()
end

local function drawText(x, y, scale, text, center)
  SetTextFont(4)
  SetTextScale(scale, scale)
  SetTextColour(255, 255, 255, 230)
  SetTextEntry('STRING')
  SetTextOutline()
  if center then SetTextCentre(true) end
  AddTextComponentString(text)
  DrawText(x, y)
end

local function drawOverlay()
  return
end

local function menuInputText(title, label, required, default)
  local res = lib.inputDialog(title, {{ type = 'textarea', label = label, required = required == true, default = default or '' }})
  if not res then return nil end
  return trimText(res[1], 400)
end


local function openChecklist(kind)
  local lines = {}
  if kind == 'scene' then
    lines = {
      '1. Confirm the call reason or scene purpose.',
      '2. Mark the scene safe or unsafe.',
      '3. Attach roles: primary, cover, supervisor, transport.',
      '4. Add shared notes so all units see the same picture.',
      '5. Record witnesses, evidence, and legal basis.',
      '6. Generate the report preview before code 4.',
    }
  else
    lines = {
      '1. Articulate the stop reason.',
      '2. Run vehicle and ID returns.',
      '3. Note cues and interview responses.',
      '4. Document consent or probable cause before searching.',
      '5. Add evidence / plain-view findings.',
      '6. Select disposition and finish the report preview.',
    }
  end
  lib.alertDialog({ header = kind == 'scene' and 'Scene Checklist' or 'Stop / Arrest Checklist', content = table.concat(lines, '\\n\\n'), centered = true, cancel = true })
end

local function openGuide()
  if lib and lib.alertDialog then
    lib.alertDialog({
      header = 'Az-5PD Simulation Guide',
      content = table.concat({
        '1. Start your shift and pick your patrol zone.',
        '2. Use existing F6 police actions as normal.',
        '3. Record the reason for the stop or contact.',
        '4. Run ID and vehicle returns before escalating.',
        '5. Add shared notes, witnesses, evidence, and legal basis.',
        '6. Generate the report preview before clearing the scene.'
      }, '\n\n'),
      centered = true,
      cancel = true,
    })
  end
end

openMainMenu = function()
  local shift = SimClient.state.shift
  local incident = SimClient.state.incident
  local dispatchCount = SimClient.state.dispatch and #SimClient.state.dispatch or 0
  local boloCount = SimClient.state.bolos and #SimClient.state.bolos or 0
  local options = {
    {
      title = shift and ('Shift Active: %s'):format(statusLabel(shift.status)) or 'Start Shift / Duty',
      description = shift and (('Callsign %s | %s'):format(shift.callsign or 'UNIT', shift.zone or 'General Patrol')) or 'Create or manage your patrol shift.',
      icon = 'shield-halved',
      arrow = true,
      onSelect = function() requestStateAndOpen('shift') end,
    },
    {
      title = ('Dispatch / BOLO Board (%s / %s)'):format(tostring(dispatchCount), tostring(boloCount)),
      description = 'Priority calls, BOLO / APB board, panic, and radio actions.',
      icon = 'tower-broadcast',
      arrow = true,
      onSelect = function() requestStateAndOpen('dispatch') end,
    },
    {
      title = incident and ('Scene Tools • %s'):format(incident.id or '') or 'Scene / Incident Tools',
      description = incident and ('%s | %s'):format(incidentTypeLabel(incident.incidentType), incidentStatusLabel(incident.status)) or 'Open, manage, or close a stop / investigation scene.',
      icon = 'clipboard-list',
      arrow = true,
      onSelect = function() requestStateAndOpen('scene') end,
    },
    {
      title = 'Traffic Stop / Contact Workflow',
      description = 'Reason for stop, returns, DUI, search basis, witness, and tow workflow.',
      icon = 'car-side',
      arrow = true,
      onSelect = function() requestStateAndOpen('stops') end,
    },
    {
      title = 'Reports / Court / Detective',
      description = 'Charges, warrant requests, report preview, and case reopen.',
      icon = 'file-lines',
      arrow = true,
      onSelect = function() requestStateAndOpen('reports') end,
    },
    {
      title = 'Training / Scorecards',
      description = 'Academy scenarios, pass/fail grading, and weekly reviews.',
      icon = 'graduation-cap',
      arrow = true,
      onSelect = function() requestStateAndOpen('training') end,
    },
    {
      title = 'Policy / IA / Commendations',
      description = 'Complaint logging, force review, evidence review, and commendations.',
      icon = 'scale-balanced',
      arrow = true,
      onSelect = function() requestStateAndOpen('policy') end,
    },
    {
      title = 'Quick Guide',
      description = 'Player learning hints and the recommended workflow.',
      icon = 'circle-info',
      onSelect = openGuide,
    },
  }

  local target = SimClient.state.lastTarget
  if target then
    options[#options + 1] = {
      title = ('Last Target • %s'):format(trimText(target.subjectLabel or target.targetType or 'Target', 44)),
      description = ('Plate: %s | Street: %s'):format(target.plate or 'N/A', trimText(target.street or 'Unknown', 54)),
      icon = target.targetType == 'vehicle' and 'car' or 'user',
      disabled = true,
    }
  end

  lib.registerContext({ id = 'az5pd_sim_main', title = 'Simulation / Scene Tools', menu = 'police_mainai', canClose = true, options = options })
  lib.showContext('az5pd_sim_main')
end

openShiftMenu = function()
  local shift = SimClient.state.shift
  local statuses = (Config.Sim and Config.Sim.shiftStatuses) or {}
  local options = {}
  if not shift then
    options[#options + 1] = {
      title = 'Start Shift',
      icon = 'play',
      onSelect = function()
        local res = lib.inputDialog('Start Shift', {
          { type = 'input', label = 'Callsign', default = (Config.Sim and Config.Sim.defaultCallsign) or 'UNIT', required = true },
          { type = 'input', label = 'Patrol Zone', default = 'General Patrol', required = true },
          { type = 'checkbox', label = 'Training / Academy Mode', checked = false },
          { type = 'checkbox', label = 'FTO / Supervisor Mode', checked = false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:startShift', { callsign = res[1], zone = res[2], trainingMode = res[3] == true, ftoMode = res[4] == true })
      end,
    }
  else
    options[#options + 1] = { title = ('Callsign: %s'):format(shift.callsign or 'UNIT'), icon = 'id-badge', disabled = true }
    options[#options + 1] = { title = ('Zone: %s'):format(shift.zone or 'General Patrol'), icon = 'map-pin', disabled = true }
    options[#options + 1] = { title = ('Patrol Goal: %s'):format(trimText(shift.patrolGoal or 'Patrol', 80)), icon = 'bullseye', disabled = true }
    options[#options + 1] = {
      title = 'Change Duty Status',
      icon = 'radio',
      onSelect = function()
        local opts = {}
        for i = 1, #statuses do opts[#opts + 1] = { label = statuses[i].label, value = statuses[i].key } end
        local res = lib.inputDialog('Duty Status', {{ type = 'select', label = 'Status', options = opts, default = shift.status, required = true }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:setStatus', res[1])
      end,
    }
    options[#options + 1] = {
      title = 'End Shift',
      icon = 'stop',
      onSelect = function() TriggerServerEvent('az5pd:sim:endShift') end,
    }
  end
  lib.registerContext({ id = 'az5pd_sim_shift', title = 'Shift / Duty', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_shift')
end

openDispatchMenu = function()
  local options = {
    {
      title = 'Panic / Emergency Traffic',
      icon = 'triangle-exclamation',
      onSelect = function()
        local msg = menuInputText('Emergency Traffic', 'Short panic traffic', false, 'Officer needs immediate backup')
        TriggerServerEvent('az5pd:sim:panic', SimClient.state.incident and SimClient.state.incident.id or '', msg or 'Officer emergency traffic')
      end,
    },
    {
      title = 'Add BOLO / APB',
      icon = 'bullhorn',
      onSelect = function()
        local res = lib.inputDialog('New BOLO / APB', {
          { type = 'select', label = 'Category', required = true, options = { { label = 'Vehicle', value = 'Vehicle' }, { label = 'Person', value = 'Person' }, { label = 'Property', value = 'Property' } } },
          { type = 'input', label = 'Label', required = true },
          { type = 'textarea', label = 'Reason', required = true },
          { type = 'number', label = 'Expires in Hours', required = false, default = 6, min = 1, max = 72 },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:addBolo', { category = res[1], label = res[2], reason = res[3], expiresHours = tonumber(res[4]) or 6 })
      end,
    },
  }

  if SimClient.state.emergencyTraffic then
    local traffic = SimClient.state.emergencyTraffic
    options[#options + 1] = { title = ('Emergency Traffic • %s'):format(traffic.callsign or traffic.officer or 'Unit'), description = trimText(traffic.message or '', 120), icon = 'siren-on', disabled = true }
  end

  local dispatch = SimClient.state.dispatch or {}
  for i = 1, #dispatch do
    local call = dispatch[i]
    options[#options + 1] = {
      title = ('%s • P%s • %s'):format(call.id or 'CALL', tostring(call.priority or 3), trimText(call.title or 'Dispatch Call', 40)),
      description = trimText((call.callerUpdate or '') .. ' | ' .. (call.zone or 'Unknown'), 120),
      icon = 'phone-volume',
      arrow = true,
      onSelect = function()
        local sub = {
          { title = ('Status: %s'):format(call.status or 'pending'), icon = 'circle-info', disabled = true },
        }
        if call.suggestedUnits and #call.suggestedUnits > 0 then
          local sug = call.suggestedUnits[1]
          sub[#sub + 1] = { title = ('Suggested: %s (%sm)'):format(sug.callsign or sug.name or 'Unit', tostring(sug.distance or '?')), icon = 'route', disabled = true }
        end
        sub[#sub + 1] = {
          title = 'Claim Call as Secondary',
          icon = 'user-plus',
          onSelect = function() TriggerServerEvent('az5pd:sim:attachDispatchCall', call.id, 'secondary') end,
        }
        sub[#sub + 1] = {
          title = 'Open Call as Scene / Primary',
          icon = 'folder-open',
          onSelect = function() TriggerServerEvent('az5pd:sim:openDispatchIncident', call.id, 'primary') end,
        }
        lib.registerContext({ id = 'az5pd_sim_dispatch_call', title = call.id or 'Dispatch Call', menu = 'az5pd_sim_dispatch', options = sub })
        lib.showContext('az5pd_sim_dispatch_call')
      end,
    }
  end

  local bolos = SimClient.state.bolos or {}
  if #bolos > 0 then
    options[#options + 1] = { title = 'Active BOLO / APB Board', icon = 'list', disabled = true }
    for i = 1, #bolos do
      local bolo = bolos[i]
      options[#options + 1] = {
        title = ('%s • %s'):format(bolo.id or 'BOLO', trimText(bolo.label or '', 42)),
        description = trimText(('%s | %s'):format(bolo.category or 'General', bolo.reason or ''), 120),
        icon = 'bullhorn',
        onSelect = function() TriggerServerEvent('az5pd:sim:clearBolo', bolo.id) end,
      }
    end
  end

  if #dispatch == 0 and #bolos == 0 then
    options[#options + 1] = { title = 'No active dispatch calls or BOLOs.', icon = 'circle-info', disabled = true }
  end

  lib.registerContext({ id = 'az5pd_sim_dispatch', title = 'Dispatch / BOLO / Radio', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_dispatch')
end

local function ensureIncident(targetPreference)
  local incident = SimClient.state.incident
  if incident then return incident end
  local target = getWorkingTarget(targetPreference)
  if not target then
    simNotify('Az-5PD', 'No target nearby. Face a ped or vehicle first.', 'warning')
    return nil
  end
  TriggerServerEvent('az5pd:sim:createOrOpenIncident', target)
  return nil
end

openSceneMenu = function()
  local incident = SimClient.state.incident
  local options = {}
  if not incident then
    options[#options + 1] = {
      title = 'Open New Scene from Nearby Ped',
      icon = 'user',
      onSelect = function()
        local target = getWorkingTarget('ped')
        if not target then return simNotify('Az-5PD', 'No nearby ped found.', 'warning') end
        local types = {}
        for i = 1, #(Config.Sim and Config.Sim.incidentTypes or {}) do
          local item = Config.Sim.incidentTypes[i]
          types[#types + 1] = { label = item.label, value = item.key }
        end
        local res = lib.inputDialog('Open Scene', {
          { type = 'select', label = 'Incident Type', options = types, default = 'suspicious_person', required = true },
          { type = 'number', label = 'Priority (1 high, 4 low)', default = 3, min = 1, max = 4 },
          { type = 'textarea', label = 'Opening Note', required = false },
        })
        if not res then return end
        target.incidentType = res[1]
        target.priority = tonumber(res[2]) or 3
        target.note = res[3] or ''
        TriggerServerEvent('az5pd:sim:createOrOpenIncident', target)
      end,
    }
    options[#options + 1] = {
      title = 'Open New Scene from Nearby Vehicle',
      icon = 'car',
      onSelect = function()
        local target = getWorkingTarget('vehicle')
        if not target then return simNotify('Az-5PD', 'No nearby vehicle found.', 'warning') end
        local res = lib.inputDialog('Open Vehicle Scene', {
          { type = 'select', label = 'Incident Type', options = { { label = 'Traffic Stop', value = 'traffic_stop' }, { label = 'Felony Stop', value = 'felony_stop' }, { label = 'Suspicious Vehicle', value = 'suspicious_vehicle' } }, default = 'traffic_stop', required = true },
          { type = 'number', label = 'Priority', default = 3, min = 1, max = 4 },
          { type = 'input', label = 'Reason for Stop', required = false },
        })
        if not res then return end
        target.incidentType = res[1]
        target.priority = tonumber(res[2]) or 3
        target.reason = res[3] or ''
        TriggerServerEvent('az5pd:sim:createOrOpenIncident', target)
      end,
    }
    options[#options + 1] = { title = 'No active scene.', description = 'Create one from a nearby target or claim a dispatch call.', icon = 'circle-info', disabled = true }
  else
    local myRole = getMyRoleOnIncident(incident)
    options[#options + 1] = { title = ('Scene %s • %s'):format(incident.id or '', incidentStatusLabel(incident.status)), description = ('Role: %s | Priority %s'):format(myRole and roleLabel(myRole.role) or 'Unknown', tostring(incident.priority or 3)), icon = 'clipboard-list', disabled = true }
    options[#options + 1] = { title = ('Area: %s'):format(trimText(incident.context and incident.context.areaLabel or 'Unknown', 80)), description = trimText(incident.context and incident.context.street or '', 120), icon = 'map-pin', disabled = true }
    if incident.alerts and #incident.alerts > 0 then
      options[#options + 1] = { title = 'Scene Alerts', description = trimText(table.concat(incident.alerts, ', '), 120), icon = 'triangle-exclamation', disabled = true }
    end
    if incident.roles and #incident.roles > 0 then
      for i = 1, #incident.roles do
        local unit = incident.roles[i]
        options[#options + 1] = { title = ('Unit: %s'):format(unit.callsign or unit.name or ('Unit ' .. tostring(unit.src or '?'))), description = ('Role: %s | Status: %s'):format(roleLabel(unit.role), trimText(unit.status or '', 40)), icon = 'user-group', disabled = true }
      end
    end

    options[#options + 1] = {
      title = 'Set Scene Status',
      icon = 'traffic-light',
      onSelect = function()
        local opts = {}
        for i = 1, #(Config.Sim and Config.Sim.incidentStatuses or {}) do
          local item = Config.Sim.incidentStatuses[i]
          opts[#opts + 1] = { label = item.label, value = item.key }
        end
        local res = lib.inputDialog('Scene Status', {{ type = 'select', label = 'Status', options = opts, default = incident.status, required = true }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:setIncidentStatus', incident.id, res[1])
      end,
    }
    options[#options + 1] = {
      title = 'Scene Safe / Unsafe / Flags',
      icon = 'road-barrier',
      onSelect = function()
        local res = lib.inputDialog('Scene Flags', {
          { type = 'checkbox', label = 'Scene Safe / Secure', checked = incident.scene and incident.scene.safe == true },
          { type = 'checkbox', label = 'Perimeter Control Active', checked = incident.scene and incident.scene.perimeter == true },
          { type = 'checkbox', label = 'Transport Pending', checked = incident.scene and incident.scene.transportPending == true },
          { type = 'checkbox', label = 'Report Pending', checked = incident.scene and incident.scene.reportPending ~= false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'safe', res[1] == true)
        TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'perimeter', res[2] == true)
        TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'transportPending', res[3] == true)
        TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'reportPending', res[4] == true)
      end,
    }
    options[#options + 1] = {
      title = 'Attach Another Role to Scene',
      icon = 'users',
      onSelect = function()
        local roles = {}
        for i = 1, #(Config.Sim and Config.Sim.roles or {}) do
          local item = Config.Sim.roles[i]
          roles[#roles + 1] = { label = item.label, value = item.key }
        end
        local res = lib.inputDialog('Attach Yourself to Role', {{ type = 'select', label = 'Role', options = roles, default = 'secondary', required = true }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:attachCurrentIncident', incident.id, res[1])
      end,
    }
    options[#options + 1] = {
      title = 'Add Shared Note',
      icon = 'note-sticky',
      onSelect = function()
        local text = menuInputText('Shared Note', 'Shared note for attached units', true)
        if not text then return end
        TriggerServerEvent('az5pd:sim:addSharedNote', incident.id, text)
      end,
    }
    options[#options + 1] = {
      title = 'Add Witness Statement',
      icon = 'person-circle-question',
      onSelect = function()
        local res = lib.inputDialog('Witness Statement', {
          { type = 'input', label = 'Witness Name', required = false },
          { type = 'textarea', label = 'Statement', required = true },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:addWitness', incident.id, res[1] or '', res[2] or '')
      end,
    }
    options[#options + 1] = {
      title = 'Add Officer Observation',
      icon = 'eye',
      onSelect = function()
        local text = menuInputText('Officer Observation', 'Observation', true)
        if not text then return end
        TriggerServerEvent('az5pd:sim:addObservation', incident.id, text)
      end,
    }
    options[#options + 1] = {
      title = 'Request Backup / Cover',
      icon = 'user-group',
      onSelect = function()
        local res = lib.inputDialog('Backup Request', {
          { type = 'select', label = 'Requested Role', required = true, options = { { label = 'General Backup', value = 'backup' }, { label = 'Supervisor', value = 'supervisor' }, { label = 'Cover Officer', value = 'cover' }, { label = 'Transport Unit', value = 'transport' } } },
          { type = 'textarea', label = 'Reason / traffic', required = false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:requestBackup', incident.id, res[2] or '', res[1] or 'backup')
      end,
    }
    options[#options + 1] = {
      title = 'K9 Integration Request',
      icon = 'paw',
      onSelect = function()
        local text = menuInputText('K9 Request', 'K9 reason / track', false, 'Vehicle sniff / track request')
        TriggerServerEvent('az5pd:sim:k9Request', incident.id, text or 'K9 requested')
      end,
    }
    options[#options + 1] = {
      title = 'Scene Checklist',
      icon = 'list-check',
      onSelect = function() openChecklist('scene') end,
    }
    options[#options + 1] = {
      title = 'Generate Narrative Summary',
      icon = 'file-lines',
      onSelect = function() TriggerServerEvent('az5pd:sim:generateSummary', incident.id) end,
    }
    options[#options + 1] = {
      title = 'Close Scene',
      icon = 'circle-check',
      onSelect = function()
        local dispositions = {}
        for i = 1, #(Config.Sim and Config.Sim.dispositions or {}) do
          local item = Config.Sim.dispositions[i]
          dispositions[#dispositions + 1] = { label = item.label, value = item.key }
        end
        local res = lib.inputDialog('Close Scene', {
          { type = 'select', label = 'Disposition', options = dispositions, required = true },
          { type = 'textarea', label = 'Final Narrative / Outcome', required = false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:closeIncident', incident.id, { disposition = res[1], narrative = res[2] or '' })
      end,
    }
  end
  lib.registerContext({ id = 'az5pd_sim_scene', title = 'Scene / Incident Tools', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_scene')
end

openStopsMenu = function()
  local incident = SimClient.state.incident
  local options = {}
  if not incident then
    options[#options + 1] = { title = 'No active incident.', description = 'Open a traffic stop or contact first.', icon = 'circle-info', disabled = true }
  else
    options[#options + 1] = { title = ('Target: %s'):format(trimText(incident.context and incident.context.subjectLabel or 'Unknown', 44)), description = ('Plate: %s | Demeanor: %s'):format(incident.context and incident.context.plate or 'N/A', incident.suspect and incident.suspect.demeanor or 'Unknown'), icon = 'user-secret', disabled = true }
    options[#options + 1] = { title = 'Profile', description = ('Answer style: %s | Passenger: %s | Bystander: %s'):format(trimText(incident.suspect and incident.suspect.answerStyle or 'Unknown', 22), trimText(incident.suspect and incident.suspect.passengerBehavior or 'Unknown', 22), trimText(incident.suspect and incident.suspect.bystanderBehavior or 'Unknown', 22)), icon = 'masks-theater', disabled = true }
    options[#options + 1] = { title = 'Stop / Arrest Checklist', icon = 'list-check', onSelect = function() openChecklist('stop') end }
    options[#options + 1] = {
      title = 'Reason for Stop / Contact',
      icon = 'clipboard-question',
      onSelect = function()
        local defaults = {}
        local cfg = (Config.Sim and Config.Sim.stopReasons) or {}
        for i = 1, #cfg do defaults[#defaults + 1] = { label = cfg[i], value = cfg[i] } end
        local res = lib.inputDialog('Reason for Stop / Contact', {{ type = 'select', label = 'Reason', options = defaults, default = incident.stop and incident.stop.reason or nil, required = true }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:recordStopReason', incident.id, res[1])
      end,
    }
    options[#options + 1] = {
      title = 'Run Vehicle Return / VIN Check',
      description = ('Plate: %s | Current return: %s'):format(incident.context and incident.context.plate or 'N/A', incident.vehicle and incident.vehicle.plateStatus or 'unknown'),
      icon = 'car-burst',
      onSelect = function() TriggerServerEvent('az5pd:sim:runVehicleCheck', incident.id) end,
    }
    options[#options + 1] = {
      title = 'Run ID / License Check',
      description = ('Current ID outcome: %s'):format(incident.stop and incident.stop.idOutcome or 'pending'),
      icon = 'id-card',
      onSelect = function() TriggerServerEvent('az5pd:sim:runIdentityCheck', incident.id) end,
    }
    options[#options + 1] = {
      title = 'Interview Prompt / Response',
      icon = 'comments',
      onSelect = function()
        local opts = {}
        local prompts = (Config.Sim and Config.Sim.interviewPrompts) or {}
        for i = 1, #prompts do opts[#opts + 1] = { label = prompts[i], value = prompts[i] } end
        opts[#opts + 1] = { label = 'Custom', value = '__custom' }
        local res = lib.inputDialog('Interview Prompt', {
          { type = 'select', label = 'Prompt', options = opts, required = true },
          { type = 'textarea', label = 'Subject response / answer', required = true },
        })
        if not res then return end
        local prompt = res[1] == '__custom' and (menuInputText('Custom Prompt', 'Prompt', true) or 'Custom prompt') or res[1]
        TriggerServerEvent('az5pd:sim:recordInterview', incident.id, prompt, res[2] or '')
      end,
    }
    options[#options + 1] = {
      title = 'Observed Cue / Behavior',
      icon = 'triangle-exclamation',
      onSelect = function()
        local opts = {}
        local cues = (Config.Sim and Config.Sim.cues) or {}
        for i = 1, #cues do opts[#opts + 1] = { label = cues[i], value = cues[i] } end
        opts[#opts + 1] = { label = 'Custom', value = '__custom' }
        local res = lib.inputDialog('Observed Cue', {{ type = 'select', label = 'Cue', options = opts, required = true }})
        if not res then return end
        local cue = res[1] == '__custom' and menuInputText('Custom Cue', 'Cue', true) or res[1]
        if not cue then return end
        TriggerServerEvent('az5pd:sim:addCue', incident.id, cue)
      end,
    }
    options[#options + 1] = {
      title = 'DUI / Sobriety Workflow',
      icon = 'wine-glass',
      onSelect = function()
        local tests = {}
        local cfg = (Config.Sim and Config.Sim.duiTests) or {}
        for i = 1, #cfg do tests[#tests + 1] = { label = cfg[i], value = cfg[i] } end
        local res = lib.inputDialog('DUI / Sobriety', {
          { type = 'select', label = 'Test', options = tests, required = true },
          { type = 'textarea', label = 'Result / clues', required = true },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:recordDui', incident.id, { test = res[1], result = res[2] })
      end,
    }
    options[#options + 1] = {
      title = 'Search Consent / Legal Basis',
      icon = 'magnifying-glass',
      onSelect = function()
        local modes = {}
        local cfg = (Config.Sim and Config.Sim.searchModes) or {}
        for i = 1, #cfg do modes[#modes + 1] = { label = cfg[i].label, value = cfg[i].key } end
        local res = lib.inputDialog('Search Decision', {
          { type = 'select', label = 'Mode', options = modes, default = incident.search and incident.search.mode or 'none', required = true },
          { type = 'textarea', label = 'Legal basis / consent notes', required = false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:setSearchDecision', incident.id, res[1], res[2] or '')
      end,
    }
    options[#options + 1] = {
      title = 'Add Probable Cause / Legal Basis',
      icon = 'gavel',
      onSelect = function()
        local opts = {}
        local cfg = (Config.Sim and Config.Sim.probableCauseOptions) or {}
        for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i], value = cfg[i] } end
        opts[#opts + 1] = { label = 'Custom', value = '__custom' }
        local res = lib.inputDialog('Legal Basis', {{ type = 'select', label = 'Basis', options = opts, required = true }})
        if not res then return end
        local cause = res[1] == '__custom' and menuInputText('Custom Legal Basis', 'Basis', true) or res[1]
        if not cause then return end
        TriggerServerEvent('az5pd:sim:addProbableCause', incident.id, cause)
      end,
    }
    options[#options + 1] = {
      title = 'Plain View / Contraband / Evidence',
      icon = 'box-open',
      onSelect = function()
        local categories = {}
        for i = 1, #((Config.Sim and Config.Sim.contrabandCategories) or {}) do
          local item = Config.Sim.contrabandCategories[i]
          categories[#categories + 1] = { label = item, value = item }
        end
        local res = lib.inputDialog('Plain View / Evidence', {
          { type = 'textarea', label = 'Plain-view observation', required = false },
          { type = 'select', label = 'Contraband / category', required = false, options = categories },
          { type = 'input', label = 'Tag / bag number', required = false },
        })
        if not res then return end
        if res[1] and res[1] ~= '' then TriggerServerEvent('az5pd:sim:plainViewObservation', incident.id, res[1]) end
        if res[2] and res[2] ~= '' then
          TriggerServerEvent('az5pd:sim:addEvidence', incident.id, { type = 'Contraband', category = res[2], description = res[2], tag = res[3] or '' })
        end
      end,
    }
    options[#options + 1] = {
      title = 'Felony Stop / Transport / Tow',
      icon = 'truck-ramp-box',
      onSelect = function()
        local res = lib.inputDialog('Felony Stop / Tow', {
          { type = 'checkbox', label = 'Mark as felony stop', checked = incident.incidentType == 'felony_stop' },
          { type = 'checkbox', label = 'Transport pending', checked = incident.scene and incident.scene.transportPending == true },
          { type = 'checkbox', label = 'Tow / impound requested', checked = incident.vehicle and incident.vehicle.impound ~= nil },
          { type = 'textarea', label = 'Tow / impound note', required = false },
        })
        if not res then return end
        if res[1] == true then TriggerServerEvent('az5pd:sim:setIncidentStatus', incident.id, 'detention') end
        TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'transportPending', res[2] == true)
        if res[3] == true then
          TriggerServerEvent('az5pd:sim:addEvidence', incident.id, { type = 'Tow / Impound Sheet', description = res[4] ~= '' and res[4] or 'Vehicle marked for tow / impound' })
        end
      end,
    }
    options[#options + 1] = {
      title = 'Behavior / De-escalation / Medical',
      icon = 'hand',
      onSelect = function()
        local res = lib.inputDialog('Officer Action', {{ type = 'select', label = 'Action', required = true, options = {
          { label = 'De-escalate / calm contact', value = 'deescalate' },
          { label = 'Challenge inconsistent story', value = 'challenge' },
          { label = 'Escalate / command presence', value = 'escalate' },
          { label = 'Document possible medical issue', value = 'medical' },
        } }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:recordBehaviorAction', incident.id, res[1])
      end,
    }
  end
  lib.registerContext({ id = 'az5pd_sim_stops', title = 'Traffic Stop / Contact Workflow', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_stops')
end

openReportsMenu = function()
  local incident = SimClient.state.incident
  local options = {}
  if incident then
    options[#options + 1] = { title = ('Scene %s Report / Court'):format(incident.id or ''), icon = 'file-lines', disabled = true }
    options[#options + 1] = {
      title = 'Add Charge',
      icon = 'plus',
      onSelect = function()
        local text = menuInputText('Add Charge', 'Charge / recommendation', true)
        if not text then return end
        TriggerServerEvent('az5pd:sim:addCharge', incident.id, text)
      end,
    }
    options[#options + 1] = {
      title = 'Auto Recommend Charges',
      icon = 'wand-magic-sparkles',
      onSelect = function() TriggerServerEvent('az5pd:sim:autoRecommendCharges', incident.id) end,
    }
    options[#options + 1] = {
      title = 'Request Warrant',
      icon = 'gavel',
      onSelect = function()
        local res = lib.inputDialog('Warrant Request', {
          { type = 'textarea', label = 'Notes / probable cause summary', required = false },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:requestWarrant', incident.id, { notes = res[1] or '', charges = incident.charges or {} })
      end,
    }
    options[#options + 1] = {
      title = 'Generate Report Preview',
      icon = 'file-circle-check',
      onSelect = function() TriggerServerEvent('az5pd:sim:generateReportPreview', incident.id) end,
    }
    if incident.charges and #incident.charges > 0 then
      options[#options + 1] = { title = ('Charges: %s'):format(table.concat(incident.charges, ', ')), icon = 'list-ul', disabled = true }
    end
    if incident.reportPreview and incident.reportPreview.narrative then
      options[#options + 1] = { title = 'Preview is ready', description = trimText(incident.reportPreview.narrative, 120), icon = 'eye', disabled = true }
    end
  else
    options[#options + 1] = { title = 'No active scene report.', icon = 'circle-info', disabled = true }
  end

  local recent = SimClient.state.recent or {}
  if #recent > 0 then
    options[#options + 1] = { title = 'Detective / Follow-Up Layer', icon = 'magnifying-glass-location', disabled = true }
    for i = #recent, 1, -1 do
      local item = recent[i]
      options[#options + 1] = {
        title = ('Reopen %s • %s'):format(item.id or 'Scene', incidentTypeLabel(item.type)),
        description = item.score and (('Score %s / %s'):format(item.score.total or '?', item.score.rating or '')) or (item.status or 'Pending'),
        icon = 'clock-rotate-left',
        onSelect = function() TriggerServerEvent('az5pd:sim:reopenIncident', item.id) end,
      }
    end
  end

  lib.registerContext({ id = 'az5pd_sim_reports', title = 'Reports / Court / Detective', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_reports')
end

openTrainingMenu = function()
  local shift = SimClient.state.shift or {}
  local weekly = SimClient.state.weekly or {}
  local recent = SimClient.state.recent or {}
  local options = {
    { title = ('Shift Incidents: %s'):format(tostring(shift.stats and shift.stats.incidents or 0)), icon = 'road', disabled = true },
    { title = ('Average Score: %.1f'):format(tonumber(shift.stats and shift.stats.averageScore or 0)), icon = 'chart-line', disabled = true },
    { title = ('Weekly Reviews: %s | Weekly Avg: %.1f'):format(tostring(weekly.reviews or 0), tonumber(weekly.averageScore or 0)), icon = 'calendar-week', disabled = true },
    {
      title = 'Start Training Scenario',
      icon = 'person-chalkboard',
      onSelect = function()
        local opts = {}
        local cfg = (Config.Sim and Config.Sim.trainingScenarios) or {}
        for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i].label, value = cfg[i].key } end
        local res = lib.inputDialog('Training Scenario', {{ type = 'select', label = 'Scenario', options = opts, required = true }})
        if not res then return end
        TriggerServerEvent('az5pd:sim:startTrainingScenario', res[1])
      end,
    },
  }
  for i = #recent, 1, -1 do
    local item = recent[i]
    options[#options + 1] = {
      title = ('%s • %s'):format(item.id or 'Scene', incidentTypeLabel(item.type)),
      description = item.score and (('Score %s (%s)'):format(item.score.total or '?', item.score.rating or '')) or tostring(item.status or 'Pending'),
      icon = 'clipboard-check',
      disabled = true,
    }
  end
  lib.registerContext({ id = 'az5pd_sim_training', title = 'Training / Scorecards', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_training')
end

openPolicyMenu = function()
  local incident = SimClient.state.incident
  local shift = SimClient.state.shift or {}
  local options = {
    { title = ('Complaints: %s | Commendations: %s'):format(tostring(shift.stats and shift.stats.complaints or 0), tostring(shift.stats and shift.stats.commendations or 0)), icon = 'scale-balanced', disabled = true },
  }
  if incident then
    options[#options + 1] = {
      title = 'Supervisor Note / IA Action',
      icon = 'pen-ruler',
      onSelect = function()
        local opts = {}
        local cfg = (Config.Sim and Config.Sim.policyActions) or {}
        for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i], value = cfg[i] } end
        local res = lib.inputDialog('Policy / IA Action', {
          { type = 'select', label = 'Action Type', options = opts, required = true },
          { type = 'textarea', label = 'Summary', required = true },
        })
        if not res then return end
        TriggerServerEvent('az5pd:sim:policyAction', incident.id, { actionType = res[1], summary = res[2] })
      end,
    }
  else
    options[#options + 1] = { title = 'No active incident for policy action.', icon = 'circle-info', disabled = true }
  end
  lib.registerContext({ id = 'az5pd_sim_policy', title = 'Policy / IA / Commendations', menu = 'az5pd_sim_main', canClose = true, options = options })
  lib.showContext('az5pd_sim_policy')
end

RegisterNetEvent('az5pd:sim:state', function(payload)
  payload = type(payload) == 'table' and payload or {}
  SimClient.state.pendingStateToken = nil
  SimClient.state.pendingMenu = nil
  SimClient.state.syncMessage = nil
  SimClient.state.shift = payload.shift
  SimClient.state.incident = payload.incident
  SimClient.state.recent = payload.recent or {}
  SimClient.state.dispatch = payload.dispatch or {}
  SimClient.state.bolos = payload.bolos or {}
  SimClient.state.weekly = payload.weekly or {}
  SimClient.state.emergencyTraffic = payload.emergencyTraffic or nil
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
end)

RegisterNetEvent('az5pd:sim:shiftState', function(shift)
  SimClient.state.shift = shift
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
end)

RegisterNetEvent('az5pd:sim:incidentSync', function(incident)
  SimClient.state.incident = incident
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
end)

RegisterNetEvent('az5pd:sim:notify', function(payload)
  payload = type(payload) == 'table' and payload or {}
  simNotify(payload.title or 'Az-5PD', payload.description or '', payload.type or 'inform')
end)

RegisterNetEvent('az5pd:sim:summary', function(id, narrative)
  lib.alertDialog({ header = ('Scene Summary • %s'):format(tostring(id or 'Active')), content = trimText(narrative, 4000), centered = true, cancel = true })
end)

RegisterNetEvent('az5pd:sim:reportPreview', function(id, preview)
  preview = type(preview) == 'table' and preview or {}
  local text = table.concat({
    ('Incident: %s'):format(tostring(id or '')), 
    ('Units: %s'):format(preview.units and tostring(#preview.units) or '0'),
    ('Time on scene: %s minute(s)'):format(tostring(preview.timeOnSceneMinutes or 0)),
    ('Evidence: %s'):format(tostring(preview.evidenceCount or 0)),
    ('Charges: %s'):format(preview.charges and (#preview.charges > 0 and table.concat(preview.charges, ', ') or 'None') or 'None'),
    '',
    trimText(preview.narrative or 'No narrative generated.', 5000),
  }, '\n')
  lib.alertDialog({ header = ('Report Preview • %s'):format(tostring(id or 'Scene')), content = text, centered = true, cancel = true })
end)

RegisterNetEvent('az5pd:sim:incidentOpened', function(incident, created)
  SimClient.state.incident = incident
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
  simNotify('Scene Tools', created and ('Opened new scene %s'):format(incident.id or '') or ('Attached to scene %s'):format(incident.id or ''), 'success')
end)

RegisterNetEvent('az5pd:sim:incidentClosed', function(incident)
  SimClient.state.incident = nil
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
  if incident and incident.score then
    simNotify('Scene Closed', ('%s | score %s (%s)'):format(tostring(incident.id or 'Scene'), tostring(incident.score.total or '?'), tostring(incident.score.rating or '')), 'success')
  else
    simNotify('Scene Closed', 'Scene closed out successfully.', 'success')
  end
end)

RegisterNetEvent('az5pd:sim:denied', function(message)
  SimClient.state.pendingStateToken = nil
  SimClient.state.syncMessage = nil
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
  simNotify('Scene Tools', message or 'Access denied.', 'error')
end)

RegisterNetEvent('az5pd:sim:dispatchCall', function(call)
  call = type(call) == 'table' and call or nil
  if not call then return end
  SimClient.state.dispatch = SimClient.state.dispatch or {}
  local replaced = false
  for i = 1, #SimClient.state.dispatch do
    if SimClient.state.dispatch[i] and SimClient.state.dispatch[i].id == call.id then
      SimClient.state.dispatch[i] = call
      replaced = true
      break
    end
  end
  if not replaced then SimClient.state.dispatch[#SimClient.state.dispatch + 1] = call end
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
  simNotify('Dispatch', ('P%s %s'):format(tostring(call.priority or 3), call.title or 'Call'), 'inform')
end)

RegisterNetEvent('az5pd:sim:panicBroadcast', function(data)
  SimClient.state.emergencyTraffic = data
  refreshSimUi()
  refreshSimHud()
  syncMdtBridge()
  if data and data.callsign then
    simNotify('Emergency Traffic', ('%s - %s'):format(data.callsign, data.message or 'Officer emergency traffic'), 'error')
  end
end)

RegisterNetEvent('az5pd:sim:openMenu', function()
  requestStateAndOpen('overview')
end)

RegisterCommand(tostring((Config.Sim and Config.Sim.menuCommand) or 'az5pdsim'), function()
  requestStateAndOpen('overview')
end, false)
RegisterKeyMapping(tostring((Config.Sim and Config.Sim.menuCommand) or 'az5pdsim'), 'Open Az-5PD scene simulation tools', 'keyboard', tostring((Config.Sim and Config.Sim.menuKey) or 'F9'))

CreateThread(function()
  while not lib or not lib.registerContext do Wait(500) end
  lib.registerContext({
    id = 'az5pd_sim_main',
    title = 'Simulation / Scene Tools',
    menu = 'police_mainai',
    canClose = true,
    options = {{ title = 'Loading...', icon = 'spinner', disabled = true }},
  })
end)

RegisterNUICallback('simClose', function(_, cb)
  closeSimUi()
  cb({ ok = true })
end)

RegisterNUICallback('simHudEditor', function(data, cb)
  requestStateAndOpen('overview')
  simNotify('Az-5PD', 'The separate HUD has been removed. Use the integrated Simulation / Scene Tools panel instead.', 'inform')
  cb({ ok = true })
end)

local function handleSimAction(data)
  data = type(data) == 'table' and data or {}
  local action = tostring(data.action or '')
  local incident = SimClient.state.incident

  if action == 'refreshState' then
    TriggerServerEvent('az5pd:sim:requestState')
  elseif action == 'startShift' then
    local res = lib.inputDialog('Start Shift', {
      { type = 'input', label = 'Callsign', default = (Config.Sim and Config.Sim.defaultCallsign) or 'UNIT', required = true },
      { type = 'input', label = 'Patrol Zone', default = 'General Patrol', required = true },
      { type = 'checkbox', label = 'Training / Academy Mode', checked = false },
      { type = 'checkbox', label = 'FTO / Supervisor Mode', checked = false },
    })
    if res then TriggerServerEvent('az5pd:sim:startShift', { callsign = res[1], zone = res[2], trainingMode = res[3] == true, ftoMode = res[4] == true }) end
  elseif action == 'changeStatus' and SimClient.state.shift then
    local opts = {}
    for i = 1, #((Config.Sim and Config.Sim.shiftStatuses) or {}) do
      local item = Config.Sim.shiftStatuses[i]
      opts[#opts + 1] = { label = item.label, value = item.key }
    end
    local res = lib.inputDialog('Duty Status', {{ type = 'select', label = 'Status', options = opts, default = SimClient.state.shift.status, required = true }})
    if res then TriggerServerEvent('az5pd:sim:setStatus', res[1]) end
  elseif action == 'endShift' and SimClient.state.shift then
    TriggerServerEvent('az5pd:sim:endShift')
  elseif action == 'panic' then
    local msg = menuInputText('Emergency Traffic', 'Short panic traffic', false, 'Officer needs immediate backup')
    TriggerServerEvent('az5pd:sim:panic', incident and incident.id or '', msg or 'Officer emergency traffic')
  elseif action == 'addBolo' then
    local res = lib.inputDialog('New BOLO / APB', {
      { type = 'select', label = 'Category', required = true, options = { { label = 'Vehicle', value = 'Vehicle' }, { label = 'Person', value = 'Person' }, { label = 'Property', value = 'Property' } } },
      { type = 'input', label = 'Label', required = true },
      { type = 'textarea', label = 'Reason', required = true },
      { type = 'number', label = 'Expires in Hours', required = false, default = 6, min = 1, max = 72 },
    })
    if res then TriggerServerEvent('az5pd:sim:addBolo', { category = res[1], label = res[2], reason = res[3], expiresHours = tonumber(res[4]) or 6 }) end
  elseif action == 'clearBolo' and data.id then
    TriggerServerEvent('az5pd:sim:clearBolo', data.id)
  elseif action == 'claimDispatch' and data.id then
    TriggerServerEvent('az5pd:sim:attachDispatchCall', data.id, 'secondary')
  elseif action == 'openDispatchScene' and data.id then
    TriggerServerEvent('az5pd:sim:openDispatchIncident', data.id, 'primary')
  elseif action == 'openPedScene' then
    local target = getWorkingTarget('ped')
    if not target then simNotify('Az-5PD', 'No nearby ped found.', 'warning') else
      local types = {}
      for i = 1, #((Config.Sim and Config.Sim.incidentTypes) or {}) do
        local item = Config.Sim.incidentTypes[i]
        types[#types + 1] = { label = item.label, value = item.key }
      end
      local res = lib.inputDialog('Open Scene', {
        { type = 'select', label = 'Incident Type', options = types, default = 'suspicious_person', required = true },
        { type = 'number', label = 'Priority (1 high, 4 low)', default = 3, min = 1, max = 4 },
        { type = 'textarea', label = 'Opening Note', required = false },
      })
      if res then target.incidentType = res[1]; target.priority = tonumber(res[2]) or 3; target.note = res[3] or ''; TriggerServerEvent('az5pd:sim:createOrOpenIncident', target) end
    end
  elseif action == 'openVehicleScene' then
    local target = getWorkingTarget('vehicle')
    if not target then simNotify('Az-5PD', 'No nearby vehicle found.', 'warning') else
      local res = lib.inputDialog('Open Vehicle Scene', {
        { type = 'select', label = 'Incident Type', options = { { label = 'Traffic Stop', value = 'traffic_stop' }, { label = 'Felony Stop', value = 'felony_stop' }, { label = 'Suspicious Vehicle', value = 'suspicious_vehicle' } }, default = 'traffic_stop', required = true },
        { type = 'number', label = 'Priority', default = 3, min = 1, max = 4 },
        { type = 'input', label = 'Reason for Stop', required = false },
      })
      if res then target.incidentType = res[1]; target.priority = tonumber(res[2]) or 3; target.reason = res[3] or ''; TriggerServerEvent('az5pd:sim:createOrOpenIncident', target) end
    end
  elseif action == 'setSceneStatus' and incident then
    local opts = {}
    for i = 1, #((Config.Sim and Config.Sim.incidentStatuses) or {}) do
      local item = Config.Sim.incidentStatuses[i]
      opts[#opts + 1] = { label = item.label, value = item.key }
    end
    local res = lib.inputDialog('Scene Status', {{ type = 'select', label = 'Status', options = opts, default = incident.status, required = true }})
    if res then TriggerServerEvent('az5pd:sim:setIncidentStatus', incident.id, res[1]) end
  elseif action == 'sceneFlags' and incident then
    local res = lib.inputDialog('Scene Flags', {
      { type = 'checkbox', label = 'Scene Safe / Secure', checked = incident.scene and incident.scene.safe == true },
      { type = 'checkbox', label = 'Perimeter Control Active', checked = incident.scene and incident.scene.perimeter == true },
      { type = 'checkbox', label = 'Transport Pending', checked = incident.scene and incident.scene.transportPending == true },
      { type = 'checkbox', label = 'Report Pending', checked = incident.scene and incident.scene.reportPending ~= false },
    })
    if res then
      TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'safe', res[1] == true)
      TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'perimeter', res[2] == true)
      TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'transportPending', res[3] == true)
      TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'reportPending', res[4] == true)
    end
  elseif action == 'attachRole' and incident then
    local roles = {}
    for i = 1, #((Config.Sim and Config.Sim.roles) or {}) do
      local item = Config.Sim.roles[i]
      roles[#roles + 1] = { label = item.label, value = item.key }
    end
    local res = lib.inputDialog('Attach Yourself to Role', {{ type = 'select', label = 'Role', options = roles, default = 'secondary', required = true }})
    if res then TriggerServerEvent('az5pd:sim:attachCurrentIncident', incident.id, res[1]) end
  elseif action == 'sharedNote' and incident then
    local text = menuInputText('Shared Note', 'Shared note for attached units', true)
    if text then TriggerServerEvent('az5pd:sim:addSharedNote', incident.id, text) end
  elseif action == 'witness' and incident then
    local res = lib.inputDialog('Witness Statement', {
      { type = 'input', label = 'Witness Name', required = false },
      { type = 'textarea', label = 'Statement', required = true },
    })
    if res then TriggerServerEvent('az5pd:sim:addWitness', incident.id, res[1] or '', res[2] or '') end
  elseif action == 'observation' and incident then
    local text = menuInputText('Officer Observation', 'Observation', true)
    if text then TriggerServerEvent('az5pd:sim:addObservation', incident.id, text) end
  elseif action == 'backup' and incident then
    local res = lib.inputDialog('Backup Request', {
      { type = 'select', label = 'Requested Role', required = true, options = { { label = 'General Backup', value = 'backup' }, { label = 'Supervisor', value = 'supervisor' }, { label = 'Cover Officer', value = 'cover' }, { label = 'Transport Unit', value = 'transport' } } },
      { type = 'textarea', label = 'Reason / traffic', required = false },
    })
    if res then TriggerServerEvent('az5pd:sim:requestBackup', incident.id, res[2] or '', res[1] or 'backup') end
  elseif action == 'k9' and incident then
    local text = menuInputText('K9 Request', 'K9 reason / track', false, 'Vehicle sniff / track request')
    TriggerServerEvent('az5pd:sim:k9Request', incident.id, text or 'K9 requested')
  elseif action == 'sceneChecklist' then
    openChecklist('scene')
  elseif action == 'generateSummary' and incident then
    TriggerServerEvent('az5pd:sim:generateSummary', incident.id)
  elseif action == 'closeScene' and incident then
    local dispositions = {}
    for i = 1, #((Config.Sim and Config.Sim.dispositions) or {}) do
      local item = Config.Sim.dispositions[i]
      dispositions[#dispositions + 1] = { label = item.label, value = item.key }
    end
    local res = lib.inputDialog('Close Scene', {
      { type = 'select', label = 'Disposition', options = dispositions, required = true },
      { type = 'textarea', label = 'Final Narrative / Outcome', required = false },
    })
    if res then TriggerServerEvent('az5pd:sim:closeIncident', incident.id, { disposition = res[1], narrative = res[2] or '' }) end
  elseif action == 'recordReason' and incident then
    local defaults = {}
    local cfg = (Config.Sim and Config.Sim.stopReasons) or {}
    for i = 1, #cfg do defaults[#defaults + 1] = { label = cfg[i], value = cfg[i] } end
    local res = lib.inputDialog('Reason for Stop / Contact', {{ type = 'select', label = 'Reason', options = defaults, default = incident.stop and incident.stop.reason or nil, required = true }})
    if res then TriggerServerEvent('az5pd:sim:recordStopReason', incident.id, res[1]) end
  elseif action == 'vehicleCheck' and incident then
    TriggerServerEvent('az5pd:sim:runVehicleCheck', incident.id)
  elseif action == 'idCheck' and incident then
    TriggerServerEvent('az5pd:sim:runIdentityCheck', incident.id)
  elseif action == 'interview' and incident then
    local opts = {}
    local prompts = (Config.Sim and Config.Sim.interviewPrompts) or {}
    for i = 1, #prompts do opts[#opts + 1] = { label = prompts[i], value = prompts[i] } end
    opts[#opts + 1] = { label = 'Custom', value = '__custom' }
    local res = lib.inputDialog('Interview Prompt', {
      { type = 'select', label = 'Prompt', options = opts, required = true },
      { type = 'textarea', label = 'Subject response / answer', required = true },
    })
    if res then
      local prompt = res[1] == '__custom' and (menuInputText('Custom Prompt', 'Prompt', true) or 'Custom prompt') or res[1]
      TriggerServerEvent('az5pd:sim:recordInterview', incident.id, prompt, res[2] or '')
    end
  elseif action == 'cue' and incident then
    local opts = {}
    local cues = (Config.Sim and Config.Sim.cues) or {}
    for i = 1, #cues do opts[#opts + 1] = { label = cues[i], value = cues[i] } end
    opts[#opts + 1] = { label = 'Custom', value = '__custom' }
    local res = lib.inputDialog('Observed Cue', {{ type = 'select', label = 'Cue', options = opts, required = true }})
    if res then
      local cue = res[1] == '__custom' and menuInputText('Custom Cue', 'Cue', true) or res[1]
      if cue then TriggerServerEvent('az5pd:sim:addCue', incident.id, cue) end
    end
  elseif action == 'dui' and incident then
    local tests = {}
    local cfg = (Config.Sim and Config.Sim.duiTests) or {}
    for i = 1, #cfg do tests[#tests + 1] = { label = cfg[i], value = cfg[i] } end
    local res = lib.inputDialog('DUI / Sobriety', {
      { type = 'select', label = 'Test', options = tests, required = true },
      { type = 'textarea', label = 'Result / clues', required = true },
    })
    if res then TriggerServerEvent('az5pd:sim:recordDui', incident.id, { test = res[1], result = res[2] }) end
  elseif action == 'searchDecision' and incident then
    local modes = {}
    local cfg = (Config.Sim and Config.Sim.searchModes) or {}
    for i = 1, #cfg do modes[#modes + 1] = { label = cfg[i].label, value = cfg[i].key } end
    local res = lib.inputDialog('Search Decision', {
      { type = 'select', label = 'Mode', options = modes, default = incident.search and incident.search.mode or 'none', required = true },
      { type = 'textarea', label = 'Legal basis / consent notes', required = false },
    })
    if res then TriggerServerEvent('az5pd:sim:setSearchDecision', incident.id, res[1], res[2] or '') end
  elseif action == 'probableCause' and incident then
    local opts = {}
    local cfg = (Config.Sim and Config.Sim.probableCauseOptions) or {}
    for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i], value = cfg[i] } end
    opts[#opts + 1] = { label = 'Custom', value = '__custom' }
    local res = lib.inputDialog('Legal Basis', {{ type = 'select', label = 'Basis', options = opts, required = true }})
    if res then
      local cause = res[1] == '__custom' and menuInputText('Custom Legal Basis', 'Basis', true) or res[1]
      if cause then TriggerServerEvent('az5pd:sim:addProbableCause', incident.id, cause) end
    end
  elseif action == 'plainViewEvidence' and incident then
    local categories = {}
    for i = 1, #((Config.Sim and Config.Sim.contrabandCategories) or {}) do
      local item = Config.Sim.contrabandCategories[i]
      categories[#categories + 1] = { label = item, value = item }
    end
    local res = lib.inputDialog('Plain View / Evidence', {
      { type = 'textarea', label = 'Plain-view observation', required = false },
      { type = 'select', label = 'Contraband / category', required = false, options = categories },
      { type = 'input', label = 'Tag / bag number', required = false },
    })
    if res then
      if res[1] and res[1] ~= '' then TriggerServerEvent('az5pd:sim:plainViewObservation', incident.id, res[1]) end
      if res[2] and res[2] ~= '' then TriggerServerEvent('az5pd:sim:addEvidence', incident.id, { type = 'Contraband', category = res[2], description = res[2], tag = res[3] or '' }) end
    end
  elseif action == 'felonyTow' and incident then
    local res = lib.inputDialog('Felony Stop / Tow', {
      { type = 'checkbox', label = 'Mark as felony stop', checked = incident.incidentType == 'felony_stop' },
      { type = 'checkbox', label = 'Transport pending', checked = incident.scene and incident.scene.transportPending == true },
      { type = 'checkbox', label = 'Tow / impound requested', checked = incident.vehicle and incident.vehicle.impound ~= nil },
      { type = 'textarea', label = 'Tow / impound note', required = false },
    })
    if res then
      if res[1] == true then TriggerServerEvent('az5pd:sim:setIncidentStatus', incident.id, 'detention') end
      TriggerServerEvent('az5pd:sim:setSceneFlag', incident.id, 'transportPending', res[2] == true)
      if res[3] == true then TriggerServerEvent('az5pd:sim:addEvidence', incident.id, { type = 'Tow / Impound Sheet', description = res[4] ~= '' and res[4] or 'Vehicle marked for tow / impound' }) end
    end
  elseif action == 'behaviorAction' and incident then
    local res = lib.inputDialog('Officer Action', {{ type = 'select', label = 'Action', required = true, options = {
      { label = 'De-escalate / calm contact', value = 'deescalate' },
      { label = 'Challenge inconsistent story', value = 'challenge' },
      { label = 'Escalate / command presence', value = 'escalate' },
      { label = 'Document possible medical issue', value = 'medical' },
    } }})
    if res then TriggerServerEvent('az5pd:sim:recordBehaviorAction', incident.id, res[1]) end
  elseif action == 'stopChecklist' then
    openChecklist('stop')
  elseif action == 'addCharge' and incident then
    local text = menuInputText('Add Charge', 'Charge / recommendation', true)
    if text then TriggerServerEvent('az5pd:sim:addCharge', incident.id, text) end
  elseif action == 'autoCharges' and incident then
    TriggerServerEvent('az5pd:sim:autoRecommendCharges', incident.id)
  elseif action == 'requestWarrant' and incident then
    local res = lib.inputDialog('Warrant Request', {
      { type = 'textarea', label = 'Notes / probable cause summary', required = false },
    })
    if res then TriggerServerEvent('az5pd:sim:requestWarrant', incident.id, { notes = res[1] or '', charges = incident.charges or {} }) end
  elseif action == 'reportPreview' and incident then
    TriggerServerEvent('az5pd:sim:generateReportPreview', incident.id)
  elseif action == 'reopenIncident' and data.id then
    TriggerServerEvent('az5pd:sim:reopenIncident', data.id)
  elseif action == 'startTraining' then
    local opts = {}
    local cfg = (Config.Sim and Config.Sim.trainingScenarios) or {}
    for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i].label, value = cfg[i].key } end
    local res = lib.inputDialog('Training Scenario', {{ type = 'select', label = 'Scenario', options = opts, required = true }})
    if res then TriggerServerEvent('az5pd:sim:startTrainingScenario', res[1]) end
  elseif action == 'policyAction' and incident then
    local opts = {}
    local cfg = (Config.Sim and Config.Sim.policyActions) or {}
    for i = 1, #cfg do opts[#opts + 1] = { label = cfg[i], value = cfg[i] } end
    local res = lib.inputDialog('Policy / IA Action', {
      { type = 'select', label = 'Action Type', options = opts, required = true },
      { type = 'textarea', label = 'Summary', required = true },
    })
    if res then TriggerServerEvent('az5pd:sim:policyAction', incident.id, { actionType = res[1], summary = res[2] }) end
  end

end

RegisterNUICallback('simAction', function(data, cb)
  handleSimAction(data)
  cb({ ok = true })
end)

RegisterNetEvent('az5pd:sim:mdtAction', function(data)
  handleSimAction(data)
end)

RegisterCommand('az5pdhud', function()
  requestStateAndOpen('overview')
  simNotify('Az-5PD', 'The separate HUD has been removed. Use the integrated Simulation / Scene Tools panel instead.', 'inform')
end, false)

RegisterCommand('az5pdhudreset', function()
  requestStateAndOpen('overview')
  simNotify('Az-5PD', 'The separate HUD has been removed. Your scene tools now live inside the main Simulation panel.', 'inform')
end, false)

RegisterCommand('az5pdhudtoggle', function()
  requestStateAndOpen('overview')
  simNotify('Az-5PD', 'The separate HUD has been removed. Use the integrated Simulation / Scene Tools panel instead.', 'inform')
end, false)

CreateThread(function()
  Wait(1500)
  if Config.Sim and Config.Sim.useTargetShortcuts ~= false and exports and exports.ox_target then
    local dist = tonumber((Config.Sim and Config.Sim.targetDistance) or 3.0) or 3.0
    pcall(function()
      exports.ox_target:addGlobalPed({
        {
          name = 'az5pd_sim_tools_ped',
          label = 'Open Scene / Stop Log',
          icon = 'fa-solid fa-clipboard-list',
          distance = dist,
          onSelect = function(data)
            local entity = data and data.entity
            if entity and entity ~= 0 and not IsPedAPlayer(entity) then
              captureTarget(entity, 'ped')
              requestStateAndOpen('scene')
            end
          end,
        }
      })
      exports.ox_target:addGlobalVehicle({
        {
          name = 'az5pd_sim_tools_vehicle',
          label = 'Open Traffic Stop / Scene',
          icon = 'fa-solid fa-car-side',
          distance = dist,
          onSelect = function(data)
            local entity = data and data.entity
            if entity and entity ~= 0 then
              captureTarget(entity, 'vehicle')
              requestStateAndOpen('scene')
            end
          end,
        }
      })
    end)
  end
end)

CreateThread(function()
  while true do
    Wait(tonumber((Config.Sim and Config.Sim.statusPingMs) or 12000) or 12000)
    local shift = SimClient.state.shift
    if shift then
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)
      TriggerServerEvent('az5pd:sim:heartbeat', {
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        street = getStreetAt(coords),
        weather = currentWeatherLabel(),
        hour = GetClockHours(),
        inVehicle = IsPedInAnyVehicle(ped, false),
        zone = shift.zone,
      })
    end
  end
end)

CreateThread(function()
  while true do
    Wait(1000)
    drawOverlay()
    refreshSimHud()
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  SendNUIMessage({ action = 'sim:close' })
  SendNUIMessage({ action = 'sim:hud', payload = { hide = true } })
  if exports and exports.ox_target then
    pcall(function() exports.ox_target:removeGlobalPed({'az5pd_sim_tools_ped'}) end)
    pcall(function() exports.ox_target:removeGlobalVehicle({'az5pd_sim_tools_vehicle'}) end)
  end
end)
