AzServices = AzServices or {}
AzServices.Debug = AzServices.Debug ~= false  -- keep debug on unless explicitly false

AzServices.Models = AzServices.Models or {
  EMS_VEH   = 'ambulance',
  EMS_PED   = 's_m_m_paramedic_01',
  CORONER_V = 'rumpo',
  CORONER_P = 's_m_m_doctor_01',
  ANIMAL_V  = 'rebel',
  ANIMAL_P  = 's_m_m_paramedic_01',
  TOW_VEH   = 'flatbed',
  TOW_PED   = 's_m_m_dockwork_01'
}

AzServices.Params = AzServices.Params or {
  EMS      = { stop=28.0, exit=30.0, onfoot=3.2, driveSpeed=12.0 },
  Coroner  = { stop=26.0, exit=28.0, onfoot=3.2, driveSpeed=10.0 },
  Animal   = { stop=26.0, exit=28.0, onfoot=3.2, driveSpeed=10.0 },
  Tow      = { stop=16.0, exit=18.0, attachRange=8.0, driveSpeed=9.0, behindOffset=7.0 },
  Tick     = { short=60, med=120, long=220 },
  MaxDriveMs = 35000
}

local function dprint(...)
  if not AzServices.Debug then return end
  local t = {}
  for i=1,select("#", ...) do t[i] = tostring(select(i, ...)) end
  print("[Az-Services]", table.concat(t, " "))
end

local function notify(id, title, desc, typ, icon, iconColor)
  if lib and lib.notify then
    lib.notify({
      id=id, title=title, description=desc,
      type=typ or 'inform', icon=icon, iconColor=iconColor,
      position='top-right', duration=3500, showDuration=true
    })
  else
    print(('[Az-Services][%s] %s - %s'):format(typ or 'info', title or '', desc or ''))
  end
end

local function num(v)
  if v == nil then return nil end
  if type(v) == "number" then return v end
  local ok, r = pcall(function() return tonumber(v) end)
  if ok then return r end
  return nil
end

local function toXYZ(v)
  if not v then return nil,nil,nil end
  if type(v) == 'vector3' then return v.x, v.y, v.z end
  if type(v) == 'table' then
    if v.x then return num(v.x), num(v.y), num(v.z) end
    if #v >= 3 then return num(v[1]), num(v[2]), num(v[3]) end
  end
  local s = tostring(v)
  local out = {}
  for token in s:gmatch('[-%d%.eE]+') do
    local n = tonumber(token); if n then out[#out+1] = n end
    if #out >= 3 then break end
  end
  if #out >= 3 then return out[1], out[2], out[3] end
  return nil,nil,nil
end

local function v3(v) local x,y,z=toXYZ(v); return (x and vector3(x,y,z)) or nil end

local function requestModelSync(hashOrName)
  local hash = (type(hashOrName)=='number') and hashOrName or GetHashKey(hashOrName)
  if not HasModelLoaded(hash) then
    RequestModel(hash)
    local t = GetGameTimer()+6000
    while not HasModelLoaded(hash) and GetGameTimer()<t do Wait(10) end
  end
  return HasModelLoaded(hash) and hash or nil
end

local function requestControl(ent, timeout)
  timeout = timeout or 1200
  if not ent or not DoesEntityExist(ent) then return false end
  if NetworkGetEntityIsNetworked(ent) then
    NetworkRequestControlOfEntity(ent)
  else
    SetEntityAsMissionEntity(ent, true, true)
    return true
  end
  local deadline = GetGameTimer()+timeout
  while not NetworkHasControlOfEntity(ent) and GetGameTimer()<deadline do
    NetworkRequestControlOfEntity(ent); Wait(10)
  end
  return NetworkHasControlOfEntity(ent)
end

local function createServiceBlip(veh, text)
  if not veh or veh==0 or not DoesEntityExist(veh) then return nil end
  local b = AddBlipForEntity(veh)
  SetBlipSprite(b, 198)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString(text or 'Service'); EndTextCommandSetBlipName(b)
  SetBlipColour(b, 3); SetBlipAsShortRange(b, true)
  return b
end

local function cleanupLater(entities, delayMs, minDistFromPlayer)
  CreateThread(function()
    local delay = delayMs or 45000
    local minDist = minDistFromPlayer or 140.0
    local t0 = GetGameTimer()
    while GetGameTimer() - t0 < delay do
      Wait(250)
    end
    local player = PlayerPedId()
    local ppos = DoesEntityExist(player) and GetEntityCoords(player) or nil
    local deadline = GetGameTimer() + 20000
    while ppos and GetGameTimer() < deadline do
      local far = true
      for _,e in ipairs(entities or {}) do
        if e and DoesEntityExist(e) then
          local d = #(GetEntityCoords(e) - ppos)
          if d < minDist then
            far = false
            break
          end
        end
      end
      if far then break
      Wait(400)
    end
    for _,e in ipairs(entities or {}) do
      if e and DoesEntityExist(e) then
        SetEntityAsMissionEntity(e, true, true)
        if IsEntityAVehicle(e) then
          DeleteVehicle(e)
        else
          DeleteEntity(e)
        end
      end
    end
  end)
end

local function headingTo(from, to)
  local dx,dy = to.x-from.x, to.y-from.y
  local hdg = math.deg(math.atan2(dy, dx))
  if hdg < 0 then hdg = hdg + 360.0 end
  return hdg
end

local function parkVehicleNear(driver, veh, target, stopDist, hdg)
  if not DoesEntityExist(veh) then return end
  local fx = GetEntityCoords(veh)
  local dist = #(fx - target)
  if dist > stopDist then
    TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, 10.0, 0, GetEntityModel(veh), 16777216, 5.0, true)
    local deadline = GetGameTimer() + AzServices.Params.MaxDriveMs
    while GetGameTimer() < deadline do
      if not DoesEntityExist(veh) then break end
      local here = GetEntityCoords(veh)
      local d = #(here - target)
      if d <= stopDist then break end
      Wait(AzServices.Params.Tick.med)
    end
  end
  if TaskVehiclePark then
    TaskVehiclePark(driver, veh, target.x, target.y, target.z, hdg or GetEntityHeading(veh), 0, 20.0, true)
    Wait(1200)
  else
    TaskVehicleTempAction(driver, veh, 27, 1500) -- brake
    Wait(800)
  end
end

local function leaveAndApproach(driver, veh, target, approachDist)
  requestControl(driver, 1000); requestControl(veh, 1000)
  TaskLeaveVehicle(driver, veh, 0)
  local t0=GetGameTimer()+5000
  while IsPedInAnyVehicle(driver,false) and GetGameTimer()<t0 do Wait(50) end
  local tx,ty,tz = target.x, target.y, target.z
  TaskGoToCoordAnyMeans(driver, tx,ty,tz, 2.15, 0, false, 786603, 0.0)
  local deadline = GetGameTimer()+8000
  while GetGameTimer()<deadline do
    local d = #(GetEntityCoords(driver)-target)
    if d <= approachDist then break end
    Wait(200)
  end
end

local function tuneDriver(driver)
  if not driver or driver == 0 or not DoesEntityExist(driver) then return end
  SetBlockingOfNonTemporaryEvents(driver, true)
  SetPedKeepTask(driver, true)
  SetDriverAbility(driver, 1.0)
  SetDriverAggressiveness(driver, 0.0)
  SetPedCombatAttributes(driver, 46, true)
end

local function spawnVehicleAndDriver(vehModelName, pedModelName, spawnCoords, heading)
  local vHash = requestModelSync(vehModelName)
  local pHash = requestModelSync(pedModelName)
  if not vHash or not pHash then return nil,nil end
  local x,y,z = toXYZ(spawnCoords); if not x then return nil,nil end
  local veh = CreateVehicle(vHash, x,y,z+0.5, heading or 0.0, true, false)
  if not veh or veh==0 then return nil,nil end
  SetEntityAsMissionEntity(veh, true, true); SetVehicleOnGroundProperly(veh); SetVehicleEngineOn(veh, true, true, true)
  local driver = CreatePedInsideVehicle(veh, 4, pHash, -1, true, false)
  if driver and driver~=0 then
    requestControl(driver, 1200)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)
    tuneDriver(driver)
  end
  return veh, driver
end

local function driveAway(driver, veh, fromPos, speed)
  if not driver or driver == 0 or not DoesEntityExist(driver) then return end
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  tuneDriver(driver)
  ClearPedTasks(driver)

  if not IsPedInVehicle(driver, veh, false) then
    TaskGoToEntity(driver, veh, -1, 4.0, 2.0, 1073741824, 0)
    local t = GetGameTimer() + 8000
    while GetGameTimer() < t and not IsPedInVehicle(driver, veh, false) do
      TaskEnterVehicle(driver, veh, 5000, -1, 2.0, 1, 0)
      Wait(250)
    end
  end

  if not IsPedInVehicle(driver, veh, false) then return end

  local here = GetEntityCoords(veh)
  local away = (fromPos and (here - fromPos)) or GetEntityForwardVector(veh)
  local mag = math.sqrt(away.x*away.x + away.y*away.y + away.z*away.z)
  if mag < 0.001 then away = GetEntityForwardVector(veh); mag = 1.0 end
  local dest = vector3(here.x + (away.x/mag)*260.0, here.y + (away.y/mag)*260.0, here.z)

  TaskVehicleDriveToCoordLongrange(driver, veh, dest.x, dest.y, dest.z, speed or 14.0, 786603, 10.0)
  SetTimeout(6500, function()
    if DoesEntityExist(driver) and DoesEntityExist(veh) and IsPedInVehicle(driver, veh, false) then
      TaskVehicleDriveWander(driver, veh, speed or 14.0, 786603)
    end
  end)
end

local function getBehindPosition(entity, offsetBack, lateral)
  local pos = GetEntityCoords(entity)
  local fw  = GetEntityForwardVector(entity)
  local rt  = vector3(fw.y, -fw.x, 0.0) -- right vector
  return pos - fw * (offsetBack or 6.0) + rt * (lateral or 0.0)
end

local function getNearbyDownedPeds(center, radius, humanOnly)
  local found = {}
  local handle, ped = FindFirstPed()
  local ok = true
  while ok do
    if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
      local dead = (type(IsPedDeadOrDying)=='function') and IsPedDeadOrDying(ped, true) or ((GetEntityHealth(ped) or 0) <= 0)
      local human = (type(IsPedHuman)=='function') and IsPedHuman(ped) or true
      if dead and #(GetEntityCoords(ped)-center) <= radius and (humanOnly==nil or humanOnly==human) then
        found[#found+1] = ped
      end
    end
    ok, ped = FindNextPed(handle)
  end
  EndFindPed(handle)
  return found
end

local function getNearbyVehicleToTow(center, radius)
  local best, bestD = nil, 1e9
  local handle, veh = FindFirstVehicle()
  local ok = true
  while ok do
    if DoesEntityExist(veh) then
      local d = #(GetEntityCoords(veh) - center)
      if d <= radius then
        local driver = GetPedInVehicleSeat(veh, -1)
        if not driver or driver==0 or not IsPedAPlayer(driver) then
          if d < bestD then bestD, best = d, veh end
        end
      end
    end
    ok, veh = FindNextVehicle(handle)
  end
  EndFindVehicle(handle)
  return best
end

AzServices.EMS = function()
  local P = AzServices.Params.EMS
  local player = PlayerPedId()
  local ppos = GetEntityCoords(player)
  local nx,ny,nz, hdg = GetClosestVehicleNodeWithHeading(ppos.x+40.0, ppos.y+40.0, ppos.z)
  local spawn = vector3(nx or (ppos.x+25.0), ny or (ppos.y+25.0), nz or ppos.z)

  local veh, driver = spawnVehicleAndDriver(AzServices.Models.EMS_VEH, AzServices.Models.EMS_PED, spawn, hdg or 0.0)
  if not veh then return notify('svc_ems_fail','EMS','Could not spawn ambulance.','error','heartbeat','#DD6B20') end
  SetVehicleSiren(veh, true)
  local blip = createServiceBlip(veh, 'AI EMS')
  notify('svc_ems_called','EMS','Ambulance dispatched.','inform','heartbeat','#38A169')

  local target = ppos
  TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, P.driveSpeed, 0, GetEntityModel(veh), 16777216, 5.0, true)
  local deadline = GetGameTimer()+AzServices.Params.MaxDriveMs
  while GetGameTimer()<deadline do
    local d = #(GetEntityCoords(veh)-target)
    if d <= P.stop then break end
    Wait(AzServices.Params.Tick.med)
  end

  parkVehicleNear(driver, veh, target, P.stop, headingTo(GetEntityCoords(veh), target))
  leaveAndApproach(driver, veh, target, P.onfoot)

  local nearDeadOrDying = getNearbyDownedPeds(target, 15.0, nil)
  if #nearDeadOrDying == 0 then
    notify('svc_ems_none','EMS','No casualties nearby.','warning','heartbeat','#DD6B20')
  else
    local casualty = nearDeadOrDying[1]
    requestControl(casualty, 800)
    TaskStartScenarioInPlace(driver, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
    Wait(1800)
    ClearPedTasksImmediately(driver)
  end

  driveAway(driver, veh, target, (P.driveSpeed or 14.0) + 6.0)
  cleanupLater({veh, driver}, 45000, 160.0)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

AzServices.Coroner = function()
  local P = AzServices.Params.Coroner
  local player = PlayerPedId()
  local ppos = GetEntityCoords(player)
  local nx,ny,nz, hdg = GetClosestVehicleNodeWithHeading(ppos.x+35.0, ppos.y+35.0, ppos.z)
  local spawn = vector3(nx or (ppos.x+20.0), ny or (ppos.y+20.0), nz or ppos.z)

  local veh, driver = spawnVehicleAndDriver(AzServices.Models.CORONER_V, AzServices.Models.CORONER_P, spawn, hdg or 0.0)
  if not veh then return notify('svc_cor_fail','Coroner','Could not spawn coroner van.','error','skull-crossbones','#DD6B20') end
  local blip = createServiceBlip(veh, 'Coroner')
  notify('svc_cor_called','Coroner','Coroner dispatched.','inform','skull-crossbones','#38A169')

  local target = ppos
  TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, P.driveSpeed, 0, GetEntityModel(veh), 16777216, 5.0, true)
  local deadline = GetGameTimer()+AzServices.Params.MaxDriveMs
  while GetGameTimer()<deadline do
    local d = #(GetEntityCoords(veh)-target)
    if d <= P.stop then break end
    Wait(AzServices.Params.Tick.med)
  end

  parkVehicleNear(driver, veh, target, P.stop, headingTo(GetEntityCoords(veh), target))
  leaveAndApproach(driver, veh, target, P.onfoot)

  local bodies = getNearbyDownedPeds(target, 25.0, nil)
  if #bodies == 0 then
    notify('svc_cor_none','Coroner','No bodies to collect.','warning','skull-crossbones','#DD6B20')
  else
    local victim = bodies[1]
    requestControl(victim, 800)
    ClearPedTasksImmediately(victim); Wait(100)
    SetEntityHealth(victim, 0); Wait(50)
    DeleteEntity(victim)
    notify('svc_cor_done','Coroner','Body collected.','success','skull-crossbones','#38A169')
  end

  driveAway(driver, veh, target, (P.driveSpeed or 14.0) + 6.0)
  cleanupLater({veh, driver}, 45000, 160.0)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

AzServices.AnimalControl = function()
  local P = AzServices.Params.Animal
  local player = PlayerPedId()
  local ppos = GetEntityCoords(player)
  local nx,ny,nz, hdg = GetClosestVehicleNodeWithHeading(ppos.x+35.0, ppos.y+35.0, ppos.z)
  local spawn = vector3(nx or (ppos.x+20.0), ny or (ppos.y+20.0), nz or ppos.z)

  local veh, driver = spawnVehicleAndDriver(AzServices.Models.ANIMAL_V, AzServices.Models.ANIMAL_P, spawn, hdg or 0.0)
  if not veh then return notify('svc_an_fail','Animal Control','Could not spawn vehicle.','error','paw','#DD6B20') end
  local blip = createServiceBlip(veh, 'Animal Control')
  notify('svc_an_called','Animal Control','Dispatched.','inform','paw','#38A169')

  local target = ppos
  TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, P.driveSpeed, 0, GetEntityModel(veh), 16777216, 5.0, true)
  local deadline = GetGameTimer()+AzServices.Params.MaxDriveMs
  while GetGameTimer()<deadline do
    local d = #(GetEntityCoords(veh)-target)
    if d <= P.stop then break end
    Wait(AzServices.Params.Tick.med)
  end

  parkVehicleNear(driver, veh, target, P.stop, headingTo(GetEntityCoords(veh), target))
  leaveAndApproach(driver, veh, target, P.onfoot)

  local animals = getNearbyDownedPeds(target, 25.0, false)
  if #animals == 0 then
    notify('svc_an_none','Animal Control','No animals to collect.','warning','paw','#DD6B20')
  else
    local a = animals[1]
    requestControl(a, 800)
    ClearPedTasksImmediately(a); Wait(50)
    SetEntityHealth(a, 0); Wait(50)
    DeleteEntity(a)
    notify('svc_an_done','Animal Control','Animal collected.','success','paw','#38A169')
  end

  driveAway(driver, veh, target, (P.driveSpeed or 14.0) + 6.0)
  cleanupLater({veh, driver}, 45000, 160.0)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

AzServices.Tow = function()
  local P = AzServices.Params.Tow
  local player = PlayerPedId()
  local ppos = GetEntityCoords(player)
  local nx,ny,nz, hdg = GetClosestVehicleNodeWithHeading(ppos.x+45.0, ppos.y+45.0, ppos.z)
  local spawn = vector3(nx or (ppos.x+30.0), ny or (ppos.y+30.0), nz or ppos.z)

  local veh, driver = spawnVehicleAndDriver(AzServices.Models.TOW_VEH, AzServices.Models.TOW_PED, spawn, hdg or 0.0)
  if not veh then return notify('svc_tow_fail','Tow','Could not spawn truck.','error','truck','#DD6B20') end
  local blip = createServiceBlip(veh, 'Tow')
  notify('svc_tow_called','Tow','Tow truck dispatched.','inform','truck','#38A169')

  local victim = getNearbyVehicleToTow(ppos, 25.0)
  if not victim then
    TaskVehicleDriveToCoord(driver, veh, ppos.x, ppos.y, ppos.z, P.driveSpeed, 0, GetEntityModel(veh), 16777216, 5.0, true)
    local deadline = GetGameTimer()+AzServices.Params.MaxDriveMs
    while GetGameTimer()<deadline do
      local d = #(GetEntityCoords(veh)-ppos)
      if d <= P.stop then break end
      Wait(AzServices.Params.Tick.med)
    end
    victim = getNearbyVehicleToTow(ppos, 25.0)
  end

  if not victim then
    notify('svc_tow_none','Tow','No vehicle nearby to tow.','warning','truck','#DD6B20')
    driveAway(driver, veh, ppos, (P.driveSpeed or 12.0) + 6.0)
    cleanupLater({veh, driver}, 25000, 160.0)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    return
  end

  local parkAt = getBehindPosition(victim, P.behindOffset, 0.0)
  local hdgToVictim = headingTo(parkAt, GetEntityCoords(victim))
  parkVehicleNear(driver, veh, parkAt, P.stop, hdgToVictim)

  leaveAndApproach(driver, veh, GetEntityCoords(victim), math.min(P.attachRange, 6.0))

  requestControl(victim, 800); requestControl(driver, 800); requestControl(veh, 800)
  if #(GetEntityCoords(veh) - GetEntityCoords(victim)) <= (P.attachRange + 2.0) then
    AttachEntityToEntity(victim, veh, 0, 0.0, -4.2, 1.1, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
    notify('svc_tow_done','Tow','Vehicle loaded.','success','truck','#38A169')
  else
    notify('svc_tow_close','Tow','Unable to reach vehicle; move closer and retry.','warning','truck','#DD6B20')
  end

  driveAway(driver, veh, ppos, (P.driveSpeed or 12.0) + 6.0)
  cleanupLater({veh, driver}, 45000, 160.0)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

function callAIEMS(...) AzServices.EMS(...) end
function callAICoroner(...) AzServices.Coroner(...) end
function callAIAnimalControl(...) AzServices.AnimalControl(...) end
function callTow(...) AzServices.Tow(...) end

RegisterNetEvent('AzServices:EMS', function() AzServices.EMS() end)
RegisterNetEvent('AzServices:Coroner', function() AzServices.Coroner() end)
RegisterNetEvent('AzServices:Animal', function() AzServices.AnimalControl() end)
RegisterNetEvent('AzServices:Tow', function() AzServices.Tow() end)
