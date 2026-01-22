Config = Config or {}

Config.RandomEvents = (Config.RandomEvents == nil) and true or Config.RandomEvents

Config.ChanceRate = Config.ChanceRate or 0.01

Config.MinIntervalMs = Config.MinIntervalMs or 15000  -- 15s
Config.MaxIntervalMs = Config.MaxIntervalMs or 30000  -- 30s

Config.MaxActiveEvents = Config.MaxActiveEvents or 3

Config.SpawnDistance = Config.SpawnDistance or { min = 60.0, max = 90.0 }

Config.CleanupDistance = Config.CleanupDistance or 250.0

Config.EventTTL = Config.EventTTL or (10 * 60 * 1000) -- 10 minutes

Config.BlipTTL = Config.BlipTTL or (2 * 60 * 1000) -- 2 minutes

Config.DebugBlips = (Config.DebugBlips == nil) and true or Config.DebugBlips

Config.Debug = (Config.Debug == nil) and true or Config.Debug

Config.PedModels = Config.PedModels or {
    "a_m_m_skidrow_01",
    "a_m_y_business_01",
    "a_m_m_business_01",
    "a_f_y_hipster_01",
    "a_m_m_rurmeth_01",
    "a_m_y_stlat_01",
    "a_m_m_socenlat_01"
}

Config.VehicleModels = Config.VehicleModels or {
    "primo",
    "blista",
    "sultan",
    "asea",
    "stanier",
    "emperor",
    "tailgater",
    "intruder",
    "washington",
    "jackal",
    "oracle",
    "fugitive"
}

Config.RequireJob = Config.RequireJob or false
Config.AllowedJobs = Config.AllowedJobs or { "BCSO", "LSPD", "SAST", "POLICE", "LEO" }

local function getPlayerJob()

    return "LEO" -- fallback default
end

local ActiveEvents = {}  -- [id] = { ... }
local eventIdCounter = 0

local function debugPrint(fmt, ...)
    if not Config.Debug then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if ok then
        print(("[AmbientEvents] %s"):format(msg))
    else
        print("[AmbientEvents] (format error in debugPrint)")
    end
end

local function nextEventId()
    eventIdCounter = eventIdCounter + 1
    return eventIdCounter
end

local function countActiveEvents()
    local n = 0
    for _ in pairs(ActiveEvents) do
        n = n + 1
    end
    return n
end

local function loadModel(modelName)
    local modelHash = modelName
    if type(modelName) == "string" then
        modelHash = GetHashKey(modelName)
    end

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    if not HasModelLoaded(modelHash) then
        debugPrint("Failed to load model %s", tostring(modelName))
        return nil
    end

    return modelHash
end

local function unloadModel(modelHash)
    if modelHash then
        SetModelAsNoLongerNeeded(modelHash)
    end
end

local function ensureAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        local timeout = GetGameTimer() + 5000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
            Wait(0)
        end
    end
    return HasAnimDictLoaded(dict)
end

local function getSpawnPointAhead(dist)
    local plyPed = PlayerPedId()
    local p = GetEntityCoords(plyPed)
    local fw = GetEntityForwardVector(plyPed)

    local tgt = vector3(
        p.x + fw.x * dist,
        p.y + fw.y * dist,
        p.z + fw.z * dist
    )

    local found, groundZ = GetGroundZFor_3dCoord(tgt.x, tgt.y, tgt.z + 10.0, false)
    if found then
        tgt = vector3(tgt.x, tgt.y, groundZ + 0.5)
    end

    return tgt, GetEntityHeading(plyPed)
end

local function createBlipAt(pos, sprite, color, text)
    if not Config.DebugBlips then return nil end
    local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, sprite or 421)    -- hazard triangle default
    SetBlipColour(blip, color or 1)       -- red default
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(text or "Incident")
    EndTextCommandSetBlipName(blip)

    return blip
end

local function removeBlipHandle(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

local function deleteEntityIfExists(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function notifyDispatch(msg)

    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

local function cleanupEvent(e)
    if not e or e.deleted then return end
    debugPrint("Cleaning ENTIRE event #%s (%s)", tostring(e.id), tostring(e.type))

    if e.blip then
        removeBlipHandle(e.blip)
        e.blip = nil
    end

    if e.entities and e.entities.peds then
        for _, ped in ipairs(e.entities.peds) do
            if DoesEntityExist(ped) then
                ClearPedTasksImmediately(ped)
            end
            deleteEntityIfExists(ped)
        end
    end

    if e.entities and e.entities.vehicles then
        for _, veh in ipairs(e.entities.vehicles) do
            deleteEntityIfExists(veh)
        end
    end

    e.deleted = true
    ActiveEvents[e.id] = nil
end

local function cleanupBlipIfExpired(e, now)
    if not e or e.deleted then return end
    if not e.blip then return end

    local blipAge = now - (e.blipCreatedAt or e.createdAt or now)
    if blipAge > e.blipTTL then
        debugPrint("Removing BLIP for event #%s (%s)", tostring(e.id), tostring(e.type))
        removeBlipHandle(e.blip)
        e.blip = nil
    end
end

local function createTrafficAccident(spawnPos, spawnHeading)
    local vehModel1 = Config.VehicleModels[math.random(#Config.VehicleModels)]
    local vehModel2 = Config.VehicleModels[math.random(#Config.VehicleModels)]
    local pedModel1 = Config.PedModels[math.random(#Config.PedModels)]
    local pedModel2 = Config.PedModels[math.random(#Config.PedModels)]

    local hVeh1 = loadModel(vehModel1)
    local hVeh2 = loadModel(vehModel2)
    local hPed1 = loadModel(pedModel1)
    local hPed2 = loadModel(pedModel2)
    if not (hVeh1 and hVeh2 and hPed1 and hPed2) then
        unloadModel(hVeh1); unloadModel(hVeh2); unloadModel(hPed1); unloadModel(hPed2)
        debugPrint("TrafficAccident: model load fail")
        return nil
    end

    local offsetA = vector3(spawnPos.x + 2.0,  spawnPos.y,        spawnPos.z)
    local offsetB = vector3(spawnPos.x - 2.5, spawnPos.y + 1.5,  spawnPos.z)

    local vehA = CreateVehicle(hVeh1, offsetA.x, offsetA.y, offsetA.z, spawnHeading + 20.0, true, true)
    local vehB = CreateVehicle(hVeh2, offsetB.x, offsetB.y, offsetB.z, spawnHeading - 70.0, true, true)

    if not (vehA and vehB and DoesEntityExist(vehA) and DoesEntityExist(vehB)) then
        debugPrint("TrafficAccident: vehicle spawn fail")
        deleteEntityIfExists(vehA)
        deleteEntityIfExists(vehB)
        unloadModel(hVeh1); unloadModel(hVeh2); unloadModel(hPed1); unloadModel(hPed2)
        return nil
    end

    SetVehicleOnGroundProperly(vehA)
    SetVehicleOnGroundProperly(vehB)
    SetEntityAsMissionEntity(vehA, true, true)
    SetEntityAsMissionEntity(vehB, true, true)

    SetVehicleEngineHealth(vehA, 200.0)
    SetVehicleEngineHealth(vehB, 200.0)
    SetVehicleUndriveable(vehA, true)
    SetVehicleUndriveable(vehB, true)
    SmashVehicleWindow(vehA, 0)
    SmashVehicleWindow(vehB, 1)

    local pedA = CreatePedInsideVehicle(vehA, 26, hPed1, -1, true, true)
    local pedB = CreatePedInsideVehicle(vehB, 26, hPed2, -1, true, true)

    unloadModel(hVeh1); unloadModel(hVeh2); unloadModel(hPed1); unloadModel(hPed2)

    if pedA and DoesEntityExist(pedA) then
        SetEntityAsMissionEntity(pedA, true, true)
        SetBlockingOfNonTemporaryEvents(pedA, true)
        if ensureAnimDict("amb@code_human_cower@male@base") then
            TaskPlayAnim(pedA, "amb@code_human_cower@male@base", "base", 8.0, -8.0, -1, 1, 0.0, false, false, false)
        end
    end

    if pedB and DoesEntityExist(pedB) then
        SetEntityAsMissionEntity(pedB, true, true)
        SetBlockingOfNonTemporaryEvents(pedB, true)
        if ensureAnimDict("random@crash_rescue@car_driver") then
            TaskPlayAnim(pedB, "random@crash_rescue@car_driver", "pull_out_ped_panic_loop", 8.0, -8.0, -1, 1, 0.0, false, false, false)
        end
    end

    local e = {
        id = nextEventId(),
        type = "TrafficAccident",
        createdAt = GetGameTimer(),
        origin = spawnPos,
        entities = { peds = {pedA, pedB}, vehicles = {vehA, vehB} },
        blipTTL = Config.BlipTTL,
        blipCreatedAt = GetGameTimer(),
        blip = createBlipAt(spawnPos, 421, 1, "10-50 Traffic Accident"),
        deleted = false
    }

    ActiveEvents[e.id] = e
    notifyDispatch("Dispatch: 10-50 reported ~r~Traffic Accident~s~. Check GPS.")
    debugPrint("Spawned TrafficAccident #%s", tostring(e.id))
    return e
end

local function drunkDriverBehaviorLoop(e)

    CreateThread(function()
        while e and not e.deleted do
            Wait(math.random(2000, 4000))
            if e.deleted then break end
            if not e.entities or not e.entities.peds or not e.entities.vehicles then break end

            local drv = e.entities.peds[1]
            local car = e.entities.vehicles[1]
            if not (drv and car) then break end
            if not (DoesEntityExist(drv) and DoesEntityExist(car)) then break end
            if IsPedDeadOrDying(drv, true) or IsEntityDead(car) then break end

            TaskVehicleTempAction(drv, car, math.random(1, 3), math.random(500, 1500))
        end
    end)
end

local function createDrunkDriver(spawnPos, heading)
    local vehModel = Config.VehicleModels[math.random(#Config.VehicleModels)]
    local pedModel = Config.PedModels[math.random(#Config.PedModels)]

    local hVeh = loadModel(vehModel)
    local hPed = loadModel(pedModel)
    if not (hVeh and hPed) then
        unloadModel(hVeh); unloadModel(hPed)
        debugPrint("DrunkDriver: model load fail")
        return nil
    end

    local veh = CreateVehicle(hVeh, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, true)
    unloadModel(hVeh)
    if not veh or not DoesEntityExist(veh) then
        unloadModel(hPed)
        debugPrint("DrunkDriver: veh spawn fail")
        return nil
    end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)

    local drv = CreatePedInsideVehicle(veh, 26, hPed, -1, true, true)
    unloadModel(hPed)
    if not drv or not DoesEntityExist(drv) then
        debugPrint("DrunkDriver: ped spawn fail")
        deleteEntityIfExists(veh)
        return nil
    end

    SetEntityAsMissionEntity(drv, true, true)
    SetBlockingOfNonTemporaryEvents(drv, true)

    SetPedIsDrunk(drv, true)
    RequestAnimSet("move_m@drunk@verydrunk")
    while not HasAnimSetLoaded("move_m@drunk@verydrunk") do
        Wait(0)
    end
    SetPedMovementClipset(drv, "move_m@drunk@verydrunk", 1.0)

    TaskVehicleDriveWander(drv, veh, 12.0, 786603)
    SetDriveTaskDrivingStyle(drv, 786603)
    SetDriveTaskMaxCruiseSpeed(drv, 12.0)

    local e = {
        id = nextEventId(),
        type = "DrunkDriver",
        createdAt = GetGameTimer(),
        origin = spawnPos,
        entities = { peds = {drv}, vehicles = {veh} },
        blipTTL = Config.BlipTTL,
        blipCreatedAt = GetGameTimer(),
        blip = createBlipAt(spawnPos, 56, 5, "Possible DUI Driver"),
        deleted = false
    }

    ActiveEvents[e.id] = e
    drunkDriverBehaviorLoop(e)

    notifyDispatch("Dispatch: Possible ~y~DUI/Suspicious Driver~s~. BOLO in your area.")
    debugPrint("Spawned DrunkDriver #%s", tostring(e.id))
    return e
end

local function createStreetFight(spawnPos, _heading)
    local pedModel1 = Config.PedModels[math.random(#Config.PedModels)]
    local pedModel2 = Config.PedModels[math.random(#Config.PedModels)]

    local hPed1 = loadModel(pedModel1)
    local hPed2 = loadModel(pedModel2)
    if not (hPed1 and hPed2) then
        unloadModel(hPed1); unloadModel(hPed2)
        debugPrint("StreetFight: model load fail")
        return nil
    end

    local p1 = vector3(spawnPos.x + 0.5, spawnPos.y, spawnPos.z)
    local p2 = vector3(spawnPos.x - 0.5, spawnPos.y, spawnPos.z)

    local pedA = CreatePed(4, hPed1, p1.x, p1.y, p1.z, math.random(0, 360) + 0.0, true, true)
    local pedB = CreatePed(4, hPed2, p2.x, p2.y, p2.z, math.random(0, 360) + 0.0, true, true)
    unloadModel(hPed1); unloadModel(hPed2)

    if not (pedA and pedB and DoesEntityExist(pedA) and DoesEntityExist(pedB)) then
        debugPrint("StreetFight: ped spawn fail")
        deleteEntityIfExists(pedA)
        deleteEntityIfExists(pedB)
        return nil
    end

    SetEntityAsMissionEntity(pedA, true, true)
    SetEntityAsMissionEntity(pedB, true, true)

    SetBlockingOfNonTemporaryEvents(pedA, true)
    SetBlockingOfNonTemporaryEvents(pedB, true)
    SetPedFleeAttributes(pedA, 0, false)
    SetPedFleeAttributes(pedB, 0, false)
    SetPedCombatAttributes(pedA, 5, true) -- will fight
    SetPedCombatAttributes(pedB, 5, true)
    SetPedCanRagdoll(pedA, true)
    SetPedCanRagdoll(pedB, true)

    TaskCombatPed(pedA, pedB, 0, 16)
    TaskCombatPed(pedB, pedA, 0, 16)

    local e = {
        id = nextEventId(),
        type = "StreetFight",
        createdAt = GetGameTimer(),
        origin = spawnPos,
        entities = { peds = {pedA, pedB}, vehicles = {} },
        blipTTL = Config.BlipTTL,
        blipCreatedAt = GetGameTimer(),
        blip = createBlipAt(spawnPos, 458, 1, "Fight in Progress"),
        deleted = false
    }

    ActiveEvents[e.id] = e
    notifyDispatch("Dispatch: ~r~Fight in progress~s~ reported. Units respond.")
    debugPrint("Spawned StreetFight #%s", tostring(e.id))
    return e
end

local function spawnSpecific(typeName)
    if not Config.RandomEvents then
        debugPrint("RandomEvents disabled")
        return
    end
    if countActiveEvents() >= Config.MaxActiveEvents then
        debugPrint("Max events reached (%d)", countActiveEvents())
        return
    end

    local dist = Config.SpawnDistance.min + math.random() * (Config.SpawnDistance.max - Config.SpawnDistance.min)
    local pos, hdg = getSpawnPointAhead(dist)

    if typeName == "accident" then
        return createTrafficAccident(pos, hdg)
    elseif typeName == "drunk" then
        return createDrunkDriver(pos, hdg)
    elseif typeName == "fight" then
        return createStreetFight(pos, hdg)
    else
        debugPrint("Unknown type '%s' (accident|drunk|fight)", tostring(typeName))
    end
end

local function spawnRandomEvent()
    if not Config.RandomEvents then
        debugPrint("RandomEvents disabled")
        return
    end
    if countActiveEvents() >= Config.MaxActiveEvents then
        debugPrint("Max events reached (%d)", countActiveEvents())
        return
    end

    local dist = Config.SpawnDistance.min + math.random() * (Config.SpawnDistance.max - Config.SpawnDistance.min)
    local pos, hdg = getSpawnPointAhead(dist)

    local eventChoices = { "TrafficAccident", "DrunkDriver", "StreetFight" }
    local pick = eventChoices[math.random(#eventChoices)]

    if pick == "TrafficAccident" then
        return createTrafficAccident(pos, hdg)
    elseif pick == "DrunkDriver" then
        return createDrunkDriver(pos, hdg)
    elseif pick == "StreetFight" then
        return createStreetFight(pos, hdg)
    end
end

CreateThread(function()
    while true do
        Wait(5000)

        local now = GetGameTimer()
        local plyPos = GetEntityCoords(PlayerPedId())

        for id, e in pairs(ActiveEvents) do
            if e and not e.deleted then

                cleanupBlipIfExpired(e, now)

                local age = now - (e.createdAt or now)
                local dist = #(plyPos - e.origin)

                local stillExists = false
                if e.entities then
                    if e.entities.peds then
                        for _, ped in ipairs(e.entities.peds) do
                            if DoesEntityExist(ped) then
                                stillExists = true
                                break
                            end
                        end
                    end
                    if (not stillExists) and e.entities.vehicles then
                        for _, veh in ipairs(e.entities.vehicles) do
                            if DoesEntityExist(veh) then
                                stillExists = true
                                break
                            end
                        end
                    end
                end

                if age > Config.EventTTL or dist > Config.CleanupDistance or (not stillExists) then
                    cleanupEvent(e)
                end
            end
        end
    end
end)

CreateThread(function()
    math.randomseed(GetGameTimer() % 2147483646)

    while true do
        local delay = Config.MinIntervalMs + math.random(0, math.max(0, Config.MaxIntervalMs - Config.MinIntervalMs))
        Wait(delay)

        if not Config.RandomEvents then
            goto continue
        end

        if Config.RequireJob then
            local job = tostring(getPlayerJob() or "CIV")
            local allowed = false
            for _, j in ipairs(Config.AllowedJobs) do
                if job:upper() == tostring(j):upper() then
                    allowed = true
                    break
                end
            end
            if not allowed then
                goto continue
            end
        end

        local plyPed = PlayerPedId()
        if IsPedInAnyVehicle(plyPed, false) then
            local veh = GetVehiclePedIsIn(plyPed, false)
            if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == plyPed then
                local speed = GetEntitySpeed(veh) -- m/s
                if speed > 6.0 then -- ~13.4 mph
                    local roll = math.random()
                    debugPrint("Roll=%.3f vs ChanceRate=%.3f", roll, Config.ChanceRate)
                    if roll <= Config.ChanceRate then
                        spawnRandomEvent()
                    end
                end
            end
        end

        ::continue::
    end
end)

RegisterCommand("forceevent", function(_, args)
    local t = args[1]
    if not t then
        debugPrint("Usage: /forceevent <accident|drunk|fight>")
        return
    end
    spawnSpecific(string.lower(t))
end, false)
