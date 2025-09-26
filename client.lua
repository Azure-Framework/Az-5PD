local active = {}
local promptId = nil
local assignedCalloutsToMe = {}
local pendingStatusChecks = {}
local menuActive = {}
local registeredMenus = {}
local END_DISTANCE_THRESHOLD = 75.0
local STATUS_CHECK_TIMEOUT = 30000

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if ok and s then
        print(("[callouts-client] %s"):format(s))
    else
        print("[callouts-client] (log format error)")
    end
end

local function dumpActive()
    log("DUMP active entries:")
    for k, v in pairs(active) do
        log(
            "   active[%s] title=%s accepted=%s status=%s coords=%s",
            tostring(k),
            (v.data and v.data.title) or "?",
            tostring(v.accepted),
            tostring(v.data and v.data.status or "?"),
            (v.data and v.data.coords) and
                string.format("%.1f,%.1f,%.1f", v.data.coords.x or 0, v.data.coords.y or 0, v.data.coords.z or 0) or
                "nil"
        )
    end
end

local function doNotify(args)
    if type(lib) == "table" and type(lib.notify) == "function" then
        pcall(lib.notify, args)
    else
        local title = args.title or ""
        local desc = args.description or ""
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentString(("[%s] %s"):format(title, desc))
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function createBlip(coords, title)
    if not coords or not coords.x then
        return nil
    end
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

local function removeBlip(b)
    if b and DoesBlipExist(b) then
        RemoveBlip(b)
    end
end

local function genLocalId()
    local tries = 0
    while tries < 10000 do
        local id = tostring(math.random(1000, 9999))
        if not active[id] then
            return id
        end
        tries = tries + 1
    end

    return tostring(GetGameTimer() % 10000)
end

RegisterNetEvent("callouts:request_position")
AddEventHandler(
    "callouts:request_position",
    function(payload)
        local requestId = payload and payload.requestId
        if not requestId then
            return
        end
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local x, y, z = table.unpack(coords)
        TriggerServerEvent("callouts:position_report", requestId, {x = x, y = y, z = z})
        log("CLIENT sent position report for request=%s coords=%.1f,%.1f,%.1f", tostring(requestId), x, y, z)
    end
)

RegisterNetEvent("callouts:new")
AddEventHandler(
    "callouts:new",
    function(smallInst)
        if not smallInst or not smallInst.id then
            return
        end
        local idstr = tostring(smallInst.id)
        log(
            "CLIENT received callouts:new id=%s title=%s template=%s coords=%s",
            idstr,
            tostring(smallInst.title),
            tostring(smallInst.template),
            (smallInst.coords and
                ("%f,%f,%f"):format(smallInst.coords.x or 0, smallInst.coords.y or 0, smallInst.coords.z or 0)) or
                "nil"
        )
        active[idstr] = active[idstr] or {}
        active[idstr].data = smallInst
        active[idstr].data.coords = smallInst.coords or active[idstr].data.coords

        active[idstr].accepted = active[idstr].accepted or false

        if not active[idstr].blip and active[idstr].data.coords then
            active[idstr].blip = createBlip(active[idstr].data.coords, active[idstr].data.title)
        end
        promptId = idstr

        doNotify(
            {
                id = "callout_received_" .. idstr,
                title = "New Callout",
                description = (smallInst.title or "Callout") ..
                    " — Press E to Accept, G to Deny, or open /callout_menu " .. idstr,
                type = "inform",
                position = "top-right",
                duration = 30000,
                icon = "bell"
            }
        )

        Citizen.CreateThread(
            function()
                local waitMs = 30000
                local start = GetGameTimer()
                while GetGameTimer() - start < waitMs do
                    Citizen.Wait(200)

                    if not active[idstr] then
                        return
                    end

                    if active[idstr].accepted then
                        return
                    end
                end

                if active[idstr] and not active[idstr].accepted then
                    local e = active[idstr]
                    if e.cleanup and type(e.cleanup) == "function" then
                        pcall(e.cleanup)
                    end
                    if type(e.entities) == "table" then
                        for _, ent in ipairs(e.entities) do
                            if DoesEntityExist(ent) then
                                DeleteEntity(ent)
                            end
                        end
                    end
                    if e.blip then
                        removeBlip(e.blip)
                    end
                    active[idstr] = nil
                    assignedCalloutsToMe[idstr] = nil
                    pendingStatusChecks[idstr] = nil
                    menuActive[idstr] = nil
                    if promptId == idstr then
                        promptId = nil
                    end

                    doNotify(
                        {
                            id = "callout_expired_local_" .. idstr,
                            title = "Callout",
                            description = ("Callout %s expired (no one accepted within 30s)."):format(idstr),
                            type = "warning",
                            duration = 4000
                        }
                    )
                    log("CLIENT local expiry cleaned up callout id=%s", idstr)
                end
            end
        )
    end
)

local PRESET_CALLER_ID = "911"

RegisterNetEvent("callouts:accepted")
AddEventHandler(
    "callouts:accepted",
    function(payload)
        if not payload or not payload.id then
            return
        end
        local idstr = tostring(payload.id)
        active[idstr] = active[idstr] or {}
        active[idstr].data = active[idstr].data or {}
        if payload.coords then
            active[idstr].data.coords = payload.coords
        end

        if active[idstr] then
            active[idstr].accepted = true
        end

        if active[idstr].blip and DoesBlipExist(active[idstr].blip) then
            SetBlipColour(active[idstr].blip, 3)
            SetBlipFlashes(active[idstr].blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(("[ASSIGNED] %s"):format(payload.title or "Callout"))
            EndTextCommandSetBlipName(active[idstr].blip)
        end

        log(
            "CLIENT received callouts:accepted id=%s assignedTo=%s title=%s",
            idstr,
            tostring(payload.assignedTo),
            tostring(payload.title)
        )
        dumpActive()

        local myServerId = GetPlayerServerId(PlayerId())
        if payload.assignedTo and tostring(payload.assignedTo) == tostring(myServerId) then
            assignedCalloutsToMe[idstr] = true
            doNotify(
                {
                    id = "callout_assigned_" .. idstr,
                    title = "Callout Assigned",
                    description = "You were assigned to " ..
                        tostring(payload.title or idstr) ..
                            ". Use /callout_menu " .. idstr .. " or press H to End when near the scene.",
                    type = "inform",
                    position = "top-right",
                    duration = 8000,
                    icon = "user-check"
                }
            )

            pcall(
                function()
                    if registerCalloutMenusOnce(idstr) then
                        openCalloutContextMenu(idstr)
                        menuActive[idstr] = GetGameTimer() + 10000
                    end
                end
            )
        else
            doNotify(
                {
                    id = "callout_assigned_broadcast_" .. idstr,
                    title = "Callout Assigned",
                    description = ("Callout %s assigned to player %s"):format(
                        payload.title or payload.id,
                        tostring(payload.assignedTo)
                    ),
                    type = "inform",
                    position = "top-right",
                    duration = 5000
                }
            )
        end

        pcall(
            function()
                local caller_name = payload.title or payload.template or ("Callout " .. idstr)

                local location_str = ""
                if payload.coords and payload.coords.x and payload.coords.y and payload.coords.z then
                    local cx, cy, cz =
                        tonumber(payload.coords.x) or 0,
                        tonumber(payload.coords.y) or 0,
                        tonumber(payload.coords.z) or 0
                    local streetHash, crossingHash = GetStreetNameAtCoord(cx, cy, cz)
                    if streetHash and streetHash ~= 0 then
                        local street = GetStreetNameFromHashKey(streetHash)
                        location_str = street or string.format("%.1f, %.1f", cx, cy)
                    else
                        location_str = string.format("%.1f, %.1f", cx, cy)
                    end
                else
                    location_str = "Unknown location"
                end

                local assignedInfo =
                    payload.assignedTo and ("Assigned to ID " .. tostring(payload.assignedTo)) or "Assigned"
                local templateInfo = payload.template and ("Template: " .. tostring(payload.template)) or ""
                local extra = payload.title and ("Title: " .. tostring(payload.title)) or ""
                local messageParts = {}
                if assignedInfo ~= "" then
                    table.insert(messageParts, assignedInfo)
                end
                if templateInfo ~= "" then
                    table.insert(messageParts, templateInfo)
                end
                if extra ~= "" then
                    table.insert(messageParts, extra)
                end
                if payload.notes then
                    table.insert(messageParts, "Notes: " .. tostring(payload.notes))
                end
                local message = table.concat(messageParts, " | ")
                if message == "" then
                    message = ("Callout %s accepted"):format(idstr)
                end

                local callPayload = {
                    caller_identifier = PRESET_CALLER_ID,
                    caller_name = caller_name,
                    location = location_str,
                    message = message,
                    status = "ACTIVE",
                    assigned_to = payload.assignedTo and tostring(payload.assignedTo) or nil,
                    assigned_discord = PRESET_CALLER_ID,
                    emergency = true
                }

                TriggerServerEvent("mdt:addCall", callPayload)
                log("CLIENT triggered mdt:addCall for id=%s payload=%s", idstr, tostring(message))
            end
        )

        if promptId == idstr then
            promptId = nil
        end
    end
)

RegisterNetEvent("callouts:open_menu")
AddEventHandler(
    "callouts:open_menu",
    function(calloutId)
        if not calloutId then
            return
        end
        pcall(
            function()
                registerCalloutMenusOnce(tostring(calloutId))
            end
        )
        pcall(
            function()
                openCalloutContextMenu(tostring(calloutId))
            end
        )
        log("CLIENT received open_menu for id=%s", tostring(calloutId))
    end
)

RegisterNetEvent("callouts:cancelled")
AddEventHandler(
    "callouts:cancelled",
    function(payload)
        if not payload or not payload.id then
            return
        end
        local idstr = tostring(payload.id)
        local e = active[idstr]
        if e then
            if e.cleanup and type(e.cleanup) == "function" then
                pcall(e.cleanup)
            end
            if type(e.entities) == "table" then
                for _, ent in ipairs(e.entities) do
                    if DoesEntityExist(ent) then
                        DeleteEntity(ent)
                    end
                end
            end
            if e.blip then
                removeBlip(e.blip)
            end
            active[idstr] = nil
        end
        assignedCalloutsToMe[idstr] = nil
        pendingStatusChecks[idstr] = nil
        menuActive[idstr] = nil
        doNotify(
            {
                id = "callout_cancel_" .. idstr,
                title = "Callout Cancelled",
                description = payload.title or idstr,
                type = "warning",
                position = "top-right",
                duration = 5000
            }
        )
        log("CLIENT received callouts:cancelled id=%s", idstr)
    end
)

RegisterNetEvent("callouts:denied_feedback")
AddEventHandler(
    "callouts:denied_feedback",
    function(calloutId)
        if not calloutId then
            return
        end
        local idstr = tostring(calloutId)
        local e = active[idstr]
        if e then
            if e.cleanup and type(e.cleanup) == "function" then
                pcall(e.cleanup)
            end
            if type(e.entities) == "table" then
                for _, ent in ipairs(e.entities) do
                    if DoesEntityExist(ent) then
                        DeleteEntity(ent)
                    end
                end
            end
            if e.blip then
                removeBlip(e.blip)
            end
            active[idstr] = nil
        end

        assignedCalloutsToMe[idstr] = nil
        pendingStatusChecks[idstr] = nil
        menuActive[idstr] = nil

        doNotify(
            {
                id = "callout_denied_" .. idstr,
                title = "Callout",
                description = "You denied callout " .. idstr,
                type = "inform",
                duration = 3000
            }
        )
        log("CLIENT received callouts:denied_feedback id=%s", idstr)
    end
)

RegisterNetEvent("callouts:action_failed")
AddEventHandler(
    "callouts:action_failed",
    function(calloutId, reason)
        doNotify(
            {
                id = "callout_fail_" .. tostring(calloutId),
                title = "Callout Error",
                description = tostring(reason or "unknown"),
                type = "error",
                duration = 5000
            }
        )
        log("CLIENT action_failed id=%s reason=%s", tostring(calloutId), tostring(reason))
        dumpActive()

        if tostring(reason) == "NOT_FOUND" then
            local idstr = tostring(calloutId)
            local localEntry = active[idstr]
            if localEntry and localEntry.data then
                local smallInst = {
                    template = localEntry.data.template,
                    coords = localEntry.data.coords,
                    title = localEntry.data.title
                }
                log(
                    "CLIENT fallback: server NOT_FOUND for id=%s; requesting server create+assign from local data (template=%s)",
                    idstr,
                    tostring(smallInst.template)
                )
                TriggerServerEvent("callouts:accept_local", smallInst)
            else
                log("CLIENT fallback: no local data to send for id=%s", idstr)
            end
        end
    end
)

RegisterNetEvent("callouts:spawn_entities")
AddEventHandler(
    "callouts:spawn_entities",
    function(spawnPacket)
        if not spawnPacket or not spawnPacket.id then
            return
        end
        local idstr = tostring(spawnPacket.id)
        active[idstr] = active[idstr] or {}
        active[idstr].data = active[idstr].data or {}
        active[idstr].data.status = "SPAWNED"
        active[idstr].data.coords = active[idstr].data.coords or spawnPacket.coords

        if type(spawnPacket.clientScript) ~= "string" then
            doNotify(
                {
                    id = "callout_spawn_no_script_" .. idstr,
                    title = "Callout Spawn",
                    description = "No client script available for " .. tostring(idstr),
                    type = "error",
                    duration = 5000
                }
            )
            log("CLIENT spawn_entities: no clientScript for id=%s", idstr)
            return
        end

        local chunk, err = load(spawnPacket.clientScript, "callout_client:" .. tostring(spawnPacket.template))
        if not chunk then
            log("clientScript compile error: %s", tostring(err))
            doNotify(
                {
                    id = "callout_spawn_compile_error_" .. idstr,
                    title = "Callout",
                    description = "Client script compile error",
                    type = "error",
                    duration = 5000
                }
            )
            return
        end

        local ok, scenarioFunc = pcall(chunk)
        if not ok then
            log("clientScript runtime error: %s", tostring(scenarioFunc))
            doNotify(
                {
                    id = "callout_spawn_runtime_error_" .. idstr,
                    title = "Callout",
                    description = "Client script runtime error",
                    type = "error",
                    duration = 5000
                }
            )
            return
        end

        if type(scenarioFunc) ~= "function" then
            doNotify(
                {
                    id = "callout_spawn_badfunc_" .. idstr,
                    title = "Callout",
                    description = "Client script must return function(coords)",
                    type = "error",
                    duration = 5000
                }
            )
            log("CLIENT spawn_entities bad return type for id=%s", idstr)
            return
        end

        local ok2, result = pcall(scenarioFunc, spawnPacket.coords)
        if not ok2 then
            log("scenario execution error: %s", tostring(result))
            doNotify(
                {
                    id = "callout_spawn_exec_error_" .. idstr,
                    title = "Callout",
                    description = "Scenario execution error",
                    type = "error",
                    duration = 5000
                }
            )
            return
        end

        active[idstr].cleanup = nil
        active[idstr].entities = nil

        if type(result) == "function" then
            active[idstr].cleanup = result
        elseif type(result) == "table" then
            active[idstr].entities = result
            active[idstr].cleanup = function()
                if type(result) == "table" then
                    for _, ent in ipairs(result) do
                        if DoesEntityExist(ent) then
                            DeleteEntity(ent)
                        end
                    end
                end
            end
        end

        doNotify(
            {
                id = "callout_spawned_" .. idstr,
                title = "Callout",
                description = "Scenario spawned: " .. tostring(spawnPacket.title or idstr),
                type = "inform",
                duration = 5000
            }
        )
        log("CLIENT spawn_entities completed for id=%s", idstr)
    end
)

RegisterNetEvent("callouts:ended")
AddEventHandler(
    "callouts:ended",
    function(payload)
        if not payload or not payload.id then
            return
        end
        local idstr = tostring(payload.id)
        local e = active[idstr]
        if e then
            if e.cleanup and type(e.cleanup) == "function" then
                pcall(e.cleanup)
            end
            if type(e.entities) == "table" then
                for _, ent in ipairs(e.entities) do
                    if DoesEntityExist(ent) then
                        DeleteEntity(ent)
                    end
                end
            end
            if e.blip then
                removeBlip(e.blip)
            end
            active[idstr] = nil
        end
        assignedCalloutsToMe[idstr] = nil
        pendingStatusChecks[idstr] = nil
        menuActive[idstr] = nil
        doNotify(
            {
                id = "callout_ended_" .. idstr,
                title = "Callout Ended",
                description = ("Callout %s ended by %s"):format(payload.template or idstr, tostring(payload.endedBy)),
                type = "success",
                duration = 5000
            }
        )
        log("CLIENT received callouts:ended id=%s endedBy=%s", idstr, tostring(payload.endedBy))
        dumpActive()
    end
)

RegisterNetEvent("callouts:status_check")
AddEventHandler(
    "callouts:status_check",
    function(pkt)
        if not pkt or not pkt.id then
            return
        end
        local idstr = tostring(pkt.id)
        pendingStatusChecks[idstr] = GetGameTimer() + STATUS_CHECK_TIMEOUT

        doNotify(
            {
                id = "callout_status_" .. idstr,
                title = "Dispatch Status Check",
                description = ("Dispatch: Are you on scene for '%s'? Open /callout_menu %s or press E to confirm."):format(
                    pkt.title or idstr,
                    idstr
                ),
                type = "inform",
                position = "top",
                duration = STATUS_CHECK_TIMEOUT,
                icon = "bell"
            }
        )
        log("CLIENT pending status check set for id=%s expires=%d", idstr, pendingStatusChecks[idstr])
    end
)

RegisterNetEvent("callouts:status_response_ack")
AddEventHandler(
    "callouts:status_response_ack",
    function(pkt)
        if not pkt or not pkt.id then
            return
        end
        local idstr = tostring(pkt.id)
        pendingStatusChecks[idstr] = nil
        doNotify(
            {
                id = "callout_status_ack_" .. idstr,
                title = "Dispatch",
                description = "Status response received.",
                type = "success",
                position = "top",
                duration = 4000
            }
        )
        log("CLIENT received status_response_ack for id=%s", idstr)
    end
)

RegisterNetEvent("callouts:player_update")
AddEventHandler(
    "callouts:player_update",
    function(pkt)
        if not pkt or not pkt.id then
            return
        end
        local idstr = tostring(pkt.id)
        local action = pkt.action or ""
        local name = pkt.name or ("Player" .. tostring(pkt.player or "unknown"))
        if action == "backup_requested" then
            local coords = pkt.payload and pkt.payload.coords
            local coordStr = coords and ((" @ %.1f, %.1f"):format(coords.x or 0, coords.y or 0)) or ""
            doNotify(
                {
                    id = "callout_backup_req_" .. idstr,
                    title = "Backup Requested",
                    description = ("Backup requested for %s by %s%s"):format(idstr, name, coordStr),
                    type = "warning",
                    duration = 8000,
                    icon = "shield"
                }
            )
        else
            doNotify(
                {
                    id = "callout_player_update_" .. idstr,
                    title = "Callout Update",
                    description = ("%s: %s"):format(name, tostring(action)),
                    type = "inform",
                    duration = 5000
                }
            )
        end
        log("CLIENT player_update id=%s action=%s from=%s", idstr, tostring(action), tostring(name))
    end
)

local function distToCallout(idstr)
    local e = active and active[idstr]
    if not e or not e.data or not e.data.coords then
        return 999999
    end
    local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
    local cx, cy, cz = e.data.coords.x, e.data.coords.y, e.data.coords.z
    local dx, dy, dz = px - cx, py - cy, pz - cz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function registerCalloutMenusOnce(idstr)
    if registeredMenus[idstr] then
        return true
    end
    if type(lib) ~= "table" or type(lib.registerContext) ~= "function" then
        log("ox_lib (lib.registerContext) not available; cannot register context menu for %s", idstr)
        return false
    end

    local entry = active[idstr]
    if not entry or not entry.data then
        log("cannot register menu for missing callout %s", tostring(idstr))
        return false
    end

    local title = ("Callout %s - %s"):format(idstr, entry.data.title or "unknown")
    local assignedToMe = assignedCalloutsToMe[idstr] == true

    local ok, err =
        pcall(
        function()
            lib.registerContext(
                {
                    id = "callout_menu_" .. idstr,
                    title = title,
                    options = {
                        {
                            title = "Accept Callout",
                            description = "Take this callout (if it's still active).",
                            icon = "check",
                            onSelect = function()
                                log("CLIENT menu Accept selected for id=%s", idstr)
                                TriggerServerEvent("callouts:accept", idstr)
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Deny Callout",
                            description = "Decline this callout.",
                            icon = "times",
                            onSelect = function()
                                log("CLIENT menu Deny selected for id=%s", idstr)
                                TriggerServerEvent("callouts:deny", idstr)
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Status Reply",
                            description = "Send a status reply (On Scene / En Route / Need Assistance).",
                            icon = "bell",
                            menu = "callout_status_" .. idstr,
                            arrow = true
                        },
                        {
                            title = "Request Backup",
                            description = "Request backup at your current position.",
                            icon = "shield",
                            onSelect = function()
                                local ped = PlayerPedId()
                                local coords = GetEntityCoords(ped)
                                local x, y, z = table.unpack(coords)
                                local myName =
                                    tostring(
                                    GetPlayerName(PlayerId()) or ("Player" .. tostring(GetPlayerServerId(PlayerId())))
                                )
                                log(
                                    "CLIENT menu Request Backup for id=%s coords=%.1f,%.1f,%.1f by=%s",
                                    idstr,
                                    x,
                                    y,
                                    z,
                                    myName
                                )
                                TriggerServerEvent(
                                    "callouts:request_backup",
                                    idstr,
                                    {
                                        coords = {x = x, y = y, z = z},
                                        fromName = myName,
                                        message = "Officer " .. myName .. " requests backup at the scene."
                                    }
                                )
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "End Callout",
                            description = "End this callout (must be assigned to you and be near the scene).",
                            icon = "flag-checkered",
                            disabled = not assignedToMe,
                            onSelect = function()
                                log("CLIENT menu End Callout selected for id=%s", idstr)
                                TriggerServerEvent("callouts:end", idstr)
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Close",
                            description = "Close the menu.",
                            icon = "times",
                            onSelect = function()
                                lib.hideContext(true)
                            end
                        }
                    }
                }
            )

            lib.registerContext(
                {
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
                                TriggerServerEvent("callouts:status_response", idstr, {response = "ON_SCENE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "En Route",
                            description = "You're en route to the callout.",
                            icon = "route",
                            onSelect = function()
                                log("CLIENT menu Status En Route for id=%s", idstr)
                                TriggerServerEvent("callouts:status_response", idstr, {response = "EN_ROUTE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Need Assistance",
                            description = "Request immediate assistance.",
                            icon = "exclamation-triangle",
                            onSelect = function()
                                log("CLIENT menu Status Need Assistance for id=%s", idstr)
                                TriggerServerEvent("callouts:status_response", idstr, {response = "NEED_ASSISTANCE"})
                                lib.hideContext(true)
                            end
                        },
                        {
                            title = "Back",
                            description = "Go back to callout menu.",
                            icon = "arrow-left",
                            onSelect = function()
                                lib.showContext("callout_menu_" .. idstr)
                            end
                        }
                    }
                }
            )
        end
    )

    if not ok then
        log("error registering menus for %s: %s", idstr, tostring(err))
        return false
    end

    registeredMenus[idstr] = true
    return true
end

local function openCalloutContextMenu(idstr)
    if not registerCalloutMenusOnce(idstr) then
        doNotify(
            {
                id = "callout_menu_no_lib",
                title = "Callout Menu",
                description = "Context menu library not available or registration failed.",
                type = "warning",
                duration = 5000
            }
        )
        return
    end

    if type(lib) ~= "table" or type(lib.showContext) ~= "function" then
        doNotify(
            {
                id = "callout_menu_no_show",
                title = "Callout Menu",
                description = "lib.showContext not available.",
                type = "error",
                duration = 5000
            }
        )
        return
    end

    local ok, err =
        pcall(
        function()
            lib.showContext("callout_menu_" .. idstr)
        end
    )
    if not ok then
        log("lib.showContext failed for %s: %s", idstr, tostring(err))
        doNotify(
            {
                id = "callout_menu_show_err",
                title = "Callout Menu",
                description = "Failed to open context menu: " .. tostring(err),
                type = "error",
                duration = 5000
            }
        )
    else
        log("CLIENT opened context menu for id=%s", idstr)
    end
end

RegisterCommand(
    "callout_menu",
    function(source, args)
        local idarg = args[1]
        if not idarg then
            local lines = {}
            for k, v in pairs(active) do
                table.insert(lines, ("ID %s: %s"):format(k, (v.data and v.data.title) or "unknown"))
            end
            if #lines == 0 then
                doNotify(
                    {
                        id = "callout_menu_none",
                        title = "Callout Menu",
                        description = "No active callouts.",
                        type = "inform",
                        duration = 4000
                    }
                )
            else
                doNotify(
                    {
                        id = "callout_menu_list",
                        title = "Callout Menu",
                        description = table.concat(lines, " / "),
                        type = "inform",
                        duration = 8000
                    }
                )
            end
            log("CLIENT /callout_menu listed %d entries", #lines)
            return
        end

        local idstr = tostring(idarg)
        openCalloutContextMenu(idstr)
    end,
    false
)

Citizen.CreateThread(
    function()
        while true do
            Citizen.Wait(0)
            if IsControlJustReleased(0, 38) then
                local answered = false
                for id, expiry in pairs(pendingStatusChecks) do
                    if expiry and GetGameTimer() <= expiry then
                        TriggerServerEvent("callouts:status_response", id, {response = "ON_SCENE"})
                        pendingStatusChecks[id] = nil
                        doNotify(
                            {
                                id = "callout_status_resp_sent_" .. id,
                                title = "Status",
                                description = "Confirmed on-scene for " .. id,
                                type = "success",
                                duration = 3000
                            }
                        )
                        log("CLIENT E pressed: replied ON_SCENE for id=%s", tostring(id))
                        answered = true
                        break
                    else
                        pendingStatusChecks[id] = nil
                    end
                end
                if answered then
                    goto continue_e
                end

                if promptId then
                    log("CLIENT E pressed: accepting promptId=%s", tostring(promptId))
                    TriggerServerEvent("callouts:accept", promptId)
                    doNotify(
                        {
                            id = "callout_accept_sent_" .. promptId,
                            title = "Callout",
                            description = "Accepting callout " .. tostring(promptId),
                            type = "inform",
                            duration = 3000
                        }
                    )
                    promptId = nil
                end
            end
            ::continue_e::

            if IsControlJustReleased(0, 47) then
                if promptId then
                    local idstr = tostring(promptId)
                    log("CLIENT G pressed: denying promptId=%s", idstr)
                    TriggerServerEvent("callouts:deny", idstr)
                    doNotify(
                        {
                            id = "callout_deny_sent_" .. idstr,
                            title = "Callout",
                            description = "Denied callout " .. idstr,
                            type = "inform",
                            duration = 3000
                        }
                    )

                    local e = active[idstr]
                    if e then
                        if e.cleanup and type(e.cleanup) == "function" then
                            pcall(e.cleanup)
                        end
                        if type(e.entities) == "table" then
                            for _, ent in ipairs(e.entities) do
                                if DoesEntityExist(ent) then
                                    DeleteEntity(ent)
                                end
                            end
                        end
                        if e.blip then
                            removeBlip(e.blip)
                        end
                        active[idstr] = nil
                    end

                    assignedCalloutsToMe[idstr] = nil
                    pendingStatusChecks[idstr] = nil
                    menuActive[idstr] = nil

                    promptId = nil
                end
            end

            if IsControlJustReleased(0, 74) then
                for id, _ in pairs(assignedCalloutsToMe) do
                    if distToCallout(id) <= END_DISTANCE_THRESHOLD then
                        log("CLIENT H pressed: requesting end for id=%s", id)
                        TriggerServerEvent("callouts:end", id)
                        doNotify(
                            {
                                id = "callout_end_sent_" .. id,
                                title = "Callout",
                                description = "Requested end for " .. tostring(id),
                                type = "inform",
                                duration = 3000
                            }
                        )
                        assignedCalloutsToMe[id] = nil
                        break
                    else
                        doNotify(
                            {
                                id = "callout_end_too_far",
                                title = "Callout",
                                description = "You are too far from callout " .. tostring(id) .. " to end it.",
                                type = "warning",
                                duration = 3000
                            }
                        )
                    end
                end
            end

            local now = GetGameTimer()
            for id, expiry in pairs(menuActive) do
                if now > expiry then
                    menuActive[id] = nil
                    if promptId == id then
                        promptId = nil
                    end
                end
            end
            for id, expiry in pairs(pendingStatusChecks) do
                if expiry and now > expiry then
                    pendingStatusChecks[id] = nil
                    doNotify(
                        {
                            id = "callout_status_expired_" .. id,
                            title = "Dispatch",
                            description = "Status check expired for " .. tostring(id),
                            type = "warning",
                            duration = 3000
                        }
                    )
                    log("CLIENT status check expired for id=%s", tostring(id))
                end
            end
        end
    end
)

do
    local cfg = Config and Config.Callouts
    if not cfg then
        log(
            "Config.Callouts not found; local callout generator disabled. Add a Config.Callouts table in your config.lua."
        )
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
            local notifyOnGenerate = cfg.notifyOnGenerate ~= false
            local useServer = cfg.useServerCreation == true or cfg.useServer == true

            local function loadTemplatesFromManifest()
                local resource = GetCurrentResourceName()
                local ok, data = pcall(LoadResourceFile, resource, "manifest.json")
                if not ok or not data then
                    local ok2, data2 = pcall(LoadResourceFile, resource, "callouts/manifest.json")
                    if not ok2 or not data2 then
                        return nil
                    end
                    ok = ok2
                    data = data2
                end
                if not data then
                    return nil
                end
                local success, parsed = pcall(json.decode, data)
                if not success or type(parsed) ~= "table" then
                    return nil
                end

                local arr = {}

                if #parsed > 0 then
                    for i, v in ipairs(parsed) do
                        if type(v) == "string" then
                            table.insert(arr, v)
                        end
                    end
                else
                    if parsed["callouts"] and type(parsed["callouts"]) == "table" then
                        for i, v in ipairs(parsed["callouts"]) do
                            if type(v) == "string" then
                                table.insert(arr, v)
                            end
                        end
                    elseif parsed["files"] and type(parsed["files"]) == "table" then
                        for i, v in ipairs(parsed["files"]) do
                            if type(v) == "string" then
                                table.insert(arr, v)
                            end
                        end
                    else
                        for k, v in pairs(parsed) do
                            if type(k) == "number" and type(v) == "string" then
                                table.insert(arr, v)
                            end
                        end
                    end
                end

                if #arr == 0 then
                    return nil
                end
                return arr
            end

            local function titleCase(s)
                return s:gsub(
                    "(%S+)",
                    function(word)
                        return word:sub(1, 1):upper() .. (word:sub(2) or "")
                    end
                )
            end

            local function buildTemplatesFromList(list)
                local out = {}
                for i, v in ipairs(list) do
                    local id = tostring(v)
                    local ttitle = id

                    ttitle = ttitle:gsub("%.callout$", "")
                    ttitle = ttitle:gsub("[._%-]+", " ")
                    ttitle = ttitle:gsub("^%s*(.-)%s*$", "%1")
                    ttitle = titleCase(ttitle)
                    table.insert(out, {id = id, title = ttitle})
                end
                return out
            end

            local templatesRaw = nil
            if cfg.templates and type(cfg.templates) == "table" and #cfg.templates > 0 then
                templatesRaw = cfg.templates
            else
                templatesRaw = loadTemplatesFromManifest() or {"Suspicious Activity"}
            end

            local templates = nil

            if type(templatesRaw[1]) == "table" and templatesRaw[1].id and templatesRaw[1].title then
                templates = templatesRaw
            else
                templates = buildTemplatesFromList(templatesRaw)
            end

            local function rangeToMs(minv, maxv, unitv)
                local mult = (unitv == "seconds") and 1000 or 60000
                local rmin = math.floor(minv)
                local rmax = math.floor(maxv)
                if rmax == rmin then
                    return rmin * mult
                end
                return math.random(rmin, rmax) * mult
            end

            local function pickTemplate()
                local t = templates[math.random(1, #templates)]
                return t.id, t.title
            end

            local function pickSpawnCoords()
                local ped = PlayerPedId()
                local px, py, pz = table.unpack(GetEntityCoords(ped))
                local dist = math.random(math.floor(minDist), math.floor(maxDist))
                local angle = math.rad(math.random(0, 359))
                local nx = px + (dist * math.cos(angle))
                local ny = py + (dist * math.sin(angle))

                local found, gz = GetGroundZFor_3dCoord(nx, ny, pz + 50.0, 0)
                local nz = pz
                if found and gz then
                    nz = gz
                end
                return {x = nx, y = ny, z = nz}
            end

            Citizen.CreateThread(
                function()
                    log("Local callout generator enabled (reading Config.Callouts / manifest.json).")
                    while true do
                        local waitMs = rangeToMs(minT, maxT, unit)
                        Citizen.Wait(waitMs)

                        if not (Config and Config.Callouts and Config.Callouts.generatorEnabled) then
                            log("Generator toggled off in Config.Callouts; stopping generator thread.")
                            return
                        end

                        local coords = pickSpawnCoords()
                        local templateId, title = pickTemplate()
                        local idstr = genLocalId()
                        local smallInst = {
                            id = idstr,
                            title = title,
                            coords = coords,
                            template = templateId
                        }

                        if notifyOnGenerate then
                            doNotify(
                                {
                                    id = "callout_gen_" .. idstr,
                                    title = "Generated Callout",
                                    description = ("Generated '%s' @ %.0f, %.0f"):format(
                                        title,
                                        coords.x or 0,
                                        coords.y or 0
                                    ),
                                    type = "inform",
                                    duration = 4000
                                }
                            )
                        end

                        if useServer then
                            TriggerServerEvent("callouts:request_generate", smallInst)
                            log(
                                "CLIENT requested server to create callout: %s (%s)",
                                tostring(title),
                                tostring(templateId)
                            )
                        else
                            TriggerEvent("callouts:new", smallInst)
                            log(
                                "CLIENT locally generated callout: %s (%s) id=%s",
                                tostring(title),
                                tostring(templateId),
                                idstr
                            )
                        end
                    end
                end
            )
        end
    end
end

AddEventHandler(
    "onResourceStop",
    function(name)
        if name == GetCurrentResourceName() then
            for id, e in pairs(active) do
                if e and e.blip then
                    removeBlip(e.blip)
                end
                if e and e.cleanup and type(e.cleanup) == "function" then
                    pcall(e.cleanup)
                end
            end
            active = {}
            promptId = nil
            assignedCalloutsToMe = {}
            pendingStatusChecks = {}
            menuActive = {}
            registeredMenus = {}
            log("resource stopped, cleaned up")
        end
    end
)
