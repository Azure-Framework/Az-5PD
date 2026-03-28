Config = Config or {}


local function az5pdNormalizeJobName(name)
  if name == nil then return nil end
  return string.lower(tostring(name))
end

local function az5pdGetAllowedJobs()
  local cfg = (Config and Config.Jobs and Config.Jobs.allowed) or nil
  if type(cfg) == 'table' and next(cfg) ~= nil then
    return cfg
  end
  return { 'bcso', 'sheriff', 'lspd', 'police', 'sast', 'state', 'trooper', 'leo' }
end

local function az5pdJobAllowed(jobName)
  if not (Config and Config.Jobs and Config.Jobs.requireJob) then return true end
  local normalized = az5pdNormalizeJobName(jobName)
  if not normalized then return false end
  for _, allowed in ipairs(az5pdGetAllowedJobs()) do
    if az5pdNormalizeJobName(allowed) == normalized then
      return true
    end
  end
  return false
end


local function normalizeJobValue(job)
    if type(job) == "table" then
        return job.name or job.job or job.id or nil
    end
    if job == nil then return nil end
    return tostring(job)
end

local function getPlayerJobSafe(src)
    if type(GetResourceState) == "function" and GetResourceState("Az-Framework") ~= "started" then
        return nil
    end

    local ok, job = pcall(function()
        return exports["Az-Framework"]:getPlayerJob(src)
    end)
    if not ok then return nil end
    return normalizeJobValue(job)
end

RegisterNetEvent("AzFR:requestPlayerJob", function()
    local src = source
    local job = getPlayerJobSafe(src)
    TriggerClientEvent("AzFR:responsePlayerJob", src, job)
end)

local function isJobAllowed(job)
    if not job then return false end
    for _, allowed in ipairs(Config.AllowedJobs) do
        if job == allowed then return true end
    end
    return false
end

local function getPlayerJob(src)
    return getPlayerJobSafe(src)
end

local CalloutTemplates = {}
local ActiveCallouts = {}
local pendingPosRequests = {}
local log
math.randomseed(os and os.time() or GetGameTimer())
local mdtBridgeByCallout = {}
local startedStatusLoops = {}

local function getPlayerNameSafe(src)
    return tostring(GetPlayerName(src) or ("Player" .. tostring(src)))
end

local function getAssignedCalloutByPlayer(src)
    for _, inst in pairs(ActiveCallouts) do
        if inst and inst.status == "ASSIGNED" and tostring(inst.assignedTo) == tostring(src) then
            return inst
        end
    end
    return nil
end

local function formatCalloutLocation(coords)
    if not coords or coords.x == nil or coords.y == nil then return "Unknown location" end
    return ("Near %.0f / %.0f"):format(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0)
end

local function getSupportedMDTResourceNames()
    local out, seen = {}, {}
    local function add(name)
        name = tostring(name or '')
        if name == '' or seen[name] then return end
        seen[name] = true
        out[#out + 1] = name
    end

    local cfg = Config and Config.Callouts or {}
    add(cfg.mdtResource)
    if type(cfg.mdtResourceFallbacks) == 'table' then
        for _, name in ipairs(cfg.mdtResourceFallbacks) do add(name) end
    end
    add('az_mdt')
    add('Az-MDT')
    add('Az-Mdt-Standalone')
    return out
end

local function resolveMDTResourceName()
    if not (Config and Config.Callouts) or Config.Callouts.syncToMDT == false or not GetResourceState then return nil end
    for _, name in ipairs(getSupportedMDTResourceNames()) do
        if name ~= '' and GetResourceState(name) == 'started' then
            return name
        end
    end
    if GetNumResources and GetResourceByFindIndex then
        for i = 0, GetNumResources() - 1 do
            local name = GetResourceByFindIndex(i)
            local low = tostring(name or ''):lower()
            if low ~= '' and (low:find('az%-mdt', 1, false) or low:find('az_mdt', 1, true)) and GetResourceState(name) == 'started' then
                return name
            end
        end
    end
    return nil
end

local function isMDTResourceName(name)
    name = tostring(name or '')
    for _, candidate in ipairs(getSupportedMDTResourceNames()) do
        if candidate == name then return true end
    end
    return false
end

local function hasMDTBridge()
    return resolveMDTResourceName() ~= nil
end

local function syncCalloutCreateToMDT(inst)
    if not inst or inst.mdtCallId then return end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, result = pcall(function()
        return exports[mdtResource]:CreateExternalCall({
            caller = 'Dispatch',
            message = ('[%s] %s'):format(tostring(inst.template or 'callout'), tostring(inst.description or inst.title or 'Callout')),
            location = formatCalloutLocation(inst.coords),
            coords = inst.coords,
            status = inst.mdtStatus or (inst.status == 'ASSIGNED' and 'ENROUTE' or 'PENDING'),
            type = '5PD',
            source = 'Az-5PD',
            externalResource = GetCurrentResourceName(),
            metadata = { calloutId = tostring(inst.id), template = tostring(inst.template or ''), title = tostring(inst.title or 'Callout') }
        })
    end)
    if ok and result then
        inst.mdtCallId = tonumber(result) or result
        mdtBridgeByCallout[tostring(inst.id)] = inst.mdtCallId
        log('MDT bridge create ok callout=%s mdt=%s resource=%s', tostring(inst.id), tostring(inst.mdtCallId), tostring(mdtResource))
    elseif not ok then
        log('MDT bridge create failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(result))
    end
end

local function syncCalloutUpdateToMDT(inst, status)
    if not inst or not inst.mdtCallId then return end
    inst.mdtStatus = status or inst.mdtStatus or (inst.status == 'ASSIGNED' and 'ENROUTE' or 'PENDING')
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, err = pcall(function()
        exports[mdtResource]:UpdateExternalCall(inst.mdtCallId, {
            caller = inst.assignedTo and getPlayerNameSafe(inst.assignedTo) or 'Dispatch',
            message = ('[%s] %s'):format(tostring(inst.template or 'callout'), tostring(inst.description or inst.title or 'Callout')),
            location = formatCalloutLocation(inst.coords),
            coords = inst.coords,
            status = inst.mdtStatus
        })
    end)
    if not ok then log('MDT bridge update failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(err)) end
end

local function syncCalloutAttachToMDT(inst, src)
    if not inst or not inst.mdtCallId or not src then return end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, err = pcall(function() exports[mdtResource]:AttachUnitToExternalCall(inst.mdtCallId, src, true) end)
    if not ok then log('MDT bridge attach failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(err)) end
end

local function syncUnitStatusToMDT(src, status)
    if not src or src == 0 or not (Config and Config.Callouts) or Config.Callouts.syncUnitStatusToMDT == false then return end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, err = pcall(function()
        return exports[mdtResource]:SetUnitStatusFromExternal(src, status, {})
    end)
    if not ok then log('MDT bridge unit status failed for src=%s via %s: %s', tostring(src), tostring(mdtResource), tostring(err)) end
end

local function syncCalloutDeleteFromMDT(inst)
    if not inst or not inst.mdtCallId then return end
    if inst.assignedTo then
        syncUnitStatusToMDT(inst.assignedTo, 'AVAILABLE')
    end
    local mdtResource = resolveMDTResourceName()
    if mdtResource then
        local ok, err = pcall(function() exports[mdtResource]:DeleteExternalCall(inst.mdtCallId) end)
        if not ok then log('MDT bridge delete failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(err)) end
    end
    mdtBridgeByCallout[tostring(inst.id)] = nil
    inst.mdtCallId = nil
end

local function resyncAllCalloutsToMDT()
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    for _, inst in pairs(ActiveCallouts) do
        if inst then
            inst.mdtCallId = nil
            mdtBridgeByCallout[tostring(inst.id)] = nil
            syncCalloutCreateToMDT(inst)
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or (inst.status == 'ASSIGNED' and 'ENROUTE' or 'PENDING'))
            if inst.status == 'ASSIGNED' and inst.assignedTo then
                syncCalloutAttachToMDT(inst, inst.assignedTo)
            end
        end
    end
    log('MDT bridge resynced %s active callout(s) to %s', tostring((function() local n=0 for _ in pairs(ActiveCallouts) do n=n+1 end return n end)()), tostring(mdtResource))
end

log = function(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if ok and s then print(("[callouts] %s"):format(s)) else print("[callouts] (log format error)") end
end

local function dumpActiveServer()
    log("DUMP ActiveCallouts:")
    for k, v in pairs(ActiveCallouts) do
        log("   ActiveCallout[%s] template=%s status=%s assignedTo=%s coords=%s",
            tostring(k),
            tostring(v.template or "?"),
            tostring(v.status or "?"),
            tostring(v.assignedTo or "?"),
            (v.coords and ("%f,%f,%f"):format(v.coords.x or 0, v.coords.y or 0, v.coords.z or 0)) or "nil")
    end
end

local function getInstance(id) if id == nil then return nil end return ActiveCallouts[tostring(id)] end

local function genId()
    for i = 1, 10000 do
        local id = tostring(math.random(1000, 9999))
        if not ActiveCallouts[id] then return id end
    end
    return tostring(GetGameTimer() % 10000)
end

local function loadManifest()
    local manifestPath = "callouts/manifest.json"
    if LoadResourceFile then
        local raw = LoadResourceFile(GetCurrentResourceName(), manifestPath)
        if raw and raw ~= "" then
            local ok, parsed = pcall(function() return json.decode(raw) end)
            if ok and type(parsed) == "table" then return parsed end
        end
        local raw2 = LoadResourceFile(GetCurrentResourceName(), "manifest.json")
        if raw2 and raw2 ~= "" then
            local ok2, parsed2 = pcall(function() return json.decode(raw2) end)
            if ok2 and type(parsed2) == "table" then return parsed2 end
        end
    end
    return nil
end

local function loadCalloutFile(filename)
    local path = "callouts/" .. filename
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if not raw or raw == "" then
        log("missing or empty: %s", path)
        return nil
    end
    local chunk, err = load(raw, "=" .. path)
    if not chunk then
        log("failed to compile %s : %s", path, tostring(err))
        return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
        log("error running %s : %s", path, tostring(result))
        return nil
    end
    if type(result) ~= "table" then
        log("%s must return a table", path)
        return nil
    end
    local name = filename:gsub("%.callout$", "")
    result._filename = filename
    result._name = name
    CalloutTemplates[name] = result
    log("loaded template: %s", name)
    return result
end

local function loadAllTemplates()
    local manifest = loadManifest()
    local toLoad = {}
    if manifest and type(manifest) == "table" then
        for _, fname in ipairs(manifest) do table.insert(toLoad, fname) end
    else
        toLoad = {"drunk_driver.callout", "dog_attack.callout", "shots_fired.callout"}
        log("no manifest found; attempting fallback files")
    end
    for _, fname in ipairs(toLoad) do pcall(function() loadCalloutFile(fname) end) end
end

local function makeInstanceFromTemplate(template, coords)
    if not template then return nil end
    local finalCoords = coords
    if not finalCoords then
        if template.server then
            if type(template.server.getCoords) == "function" then
                local ok, c = pcall(template.server.getCoords)
                if ok and type(c) == "table" and c.x then finalCoords = c end
            elseif type(template.server.coords) == "table" and template.server.coords.x then
                finalCoords = template.server.coords
            end
        end
    end
    if not finalCoords then finalCoords = {x = 215.76, y = -810.12, z = 30.73} end

    local inst = {
        id = genId(),
        template = template._name,
        title = template.title or ("Callout: " .. (template._name or "unknown")),
        description = template.description or "",
        coords = finalCoords,
        createdAt = GetGameTimer(),
        status = "ACTIVE",
        assignedTo = nil,
        clientScript = nil,
        awaitingStatus = false,
        lastStatusResponse = nil,
        backupRequests = {},
        mdtStatus = 'PENDING'
    }

    if template.client and type(template.client.script) == "string" then
        inst.clientScript = template.client.script
    else
        log("template %s has no client.script string (client-side logic may be missing)", template._name)
    end

    return inst
end

local function broadcastInstance(inst)
    ActiveCallouts[inst.id] = inst
    syncCalloutCreateToMDT(inst)
    TriggerClientEvent("callouts:new", -1, {
        id = inst.id,
        template = inst.template,
        title = inst.title,
        description = inst.description,
        coords = inst.coords,
        createdAt = inst.createdAt
    })
    log("SERVER broadcast instance %s (%s) near %.2f, %.2f, %.2f", inst.id, inst.template, inst.coords.x, inst.coords.y, inst.coords.z)
    dumpActiveServer()
end

local function requestPlayerPosition(playerServerId, templateName)
    if not playerServerId then return false end
    local requestId = genId() .. "_req"
    pendingPosRequests[requestId] = { src = playerServerId, templateName = templateName, timeoutTick = GetGameTimer() + 5000 }
    TriggerClientEvent("callouts:request_position", playerServerId, {requestId = requestId})
    log("SERVER requested position from player %s for template %s (requestId=%s)", tostring(playerServerId), tostring(templateName), tostring(requestId))
    return requestId
end

RegisterNetEvent("callouts:position_report")
AddEventHandler("callouts:position_report", function(requestId, coords)
    local src = source
    local entry = pendingPosRequests[requestId]
    if not entry then log("received position_report for unknown request %s from %d", tostring(requestId), src); return end
    if tostring(entry.src) ~= tostring(src) then
        log("position_report src mismatch: expected %s got %s", tostring(entry.src), tostring(src))
        pendingPosRequests[requestId] = nil
        return
    end
    local templateName = entry.templateName
    local tmpl = CalloutTemplates[templateName]
    if not tmpl then log("template not found for position_report: %s", tostring(templateName)); pendingPosRequests[requestId] = nil; return end

    local rx = coords.x + math.random(-25, 25)
    local ry = coords.y + math.random(-25, 25)
    local rz = coords.z
    local inst = makeInstanceFromTemplate(tmpl, {x = rx, y = ry, z = rz})
    if inst then broadcastInstance(inst) end

    pendingPosRequests[requestId] = nil
    log("SERVER position_report processed requestId=%s from=%d produced id=%s", tostring(requestId), src, inst and inst.id or "nil")
end)

RegisterCommand("callout_spawn_random", function(source, args, raw)
    local names = {}
    for k, _ in pairs(CalloutTemplates) do table.insert(names, k) end
    if #names == 0 then log("no templates loaded"); return end
    local pick = names[math.random(#names)]
    local players = GetPlayers() or {}
    if #players > 0 then
        local idx = math.random(#players)
        local serverId = tonumber(players[idx]) or players[idx]
        requestPlayerPosition(serverId, pick)
        log("requested position from player %s for template %s", tostring(serverId), pick)
    else
        local tmpl = CalloutTemplates[pick]
        local inst = makeInstanceFromTemplate(tmpl)
        if inst then broadcastInstance(inst) end
    end
end, false)

RegisterCommand("callout_spawn", function(source, args)
    local name = args[1]
    if not name then log("usage: callout_spawn <templateName>"); return end
    local tmpl = CalloutTemplates[name]
    if not tmpl then log("No such template: %s", name); return end
    if source and source > 0 then
        requestPlayerPosition(source, name)
        log("requested position from player %s for template %s", tostring(source), name)
    else
        local players = GetPlayers() or {}
        if #players > 0 then
            local serverId = tonumber(players[math.random(#players)]) or players[math.random(#players)]
            requestPlayerPosition(serverId, name)
            log("requested position from random player %s for template %s", tostring(serverId), name)
        else
            local inst = makeInstanceFromTemplate(tmpl)
            if inst then broadcastInstance(inst) end
        end
    end
end, false)

RegisterCommand("callout_list", function()
    log("loaded templates:")
    for k, _ in pairs(CalloutTemplates) do print(" - " .. k) end
end, false)

local function startStatusLoopForCallout(calloutId)
    local key = tostring(calloutId or '')
    if key == '' or startedStatusLoops[key] then return end
    startedStatusLoops[key] = true
    Citizen.CreateThread(function()
        while ActiveCallouts[key] and ActiveCallouts[key].status == "ASSIGNED" do
            local inst = ActiveCallouts[key]
            local tick = GetGameTimer()
            while GetGameTimer() - tick < 60000 do
                Citizen.Wait(500)
                if not ActiveCallouts[key] or ActiveCallouts[key].status ~= "ASSIGNED" then startedStatusLoops[key] = nil return end
            end
            inst = ActiveCallouts[key]
            if not inst or inst.status ~= "ASSIGNED" then startedStatusLoops[key] = nil return end
            inst.awaitingStatus = true
            log("sending status_check for callout %s to player %s", inst.id, tostring(inst.assignedTo))
            while ActiveCallouts[key] and ActiveCallouts[key].status == "ASSIGNED" and ActiveCallouts[key].awaitingStatus do
                TriggerClientEvent("callouts:status_check", inst.assignedTo, {id = inst.id, title = inst.title, description = inst.description})
                Citizen.Wait(10000)
            end
            if not ActiveCallouts[key] then startedStatusLoops[key] = nil return end
            ActiveCallouts[key].awaitingStatus = false
        end
        startedStatusLoops[key] = nil
    end)
end

local function finalizeAssignment(inst, src, extra)
    if not inst or not src then return false end
    extra = extra or {}
    inst.status = "ASSIGNED"
    inst.assignedTo = src
    inst.assignedAt = GetGameTimer()
    inst.mdtStatus = extra.mdtStatus or inst.mdtStatus or 'ENROUTE'

    local acceptedPayload = { id = inst.id, template = inst.template, title = inst.title, assignedTo = inst.assignedTo, coords = inst.coords }
    if extra.origLocalId then acceptedPayload.origLocalId = extra.origLocalId end
    TriggerClientEvent("callouts:accepted", -1, acceptedPayload)
    TriggerClientEvent("callouts:open_menu", inst.assignedTo, inst.id)

    local spawnPacket = { id = inst.id, template = inst.template, title = inst.title, description = inst.description, coords = inst.coords, clientScript = inst.clientScript }
    TriggerClientEvent("callouts:spawn_entities", -1, spawnPacket)
    local acceptName = getPlayerNameSafe(src)
    TriggerClientEvent("callouts:player_update", -1, { id = inst.id, action = "accepted", player = src, name = acceptName, timestamp = GetGameTimer() })
    if not inst.mdtCallId then syncCalloutCreateToMDT(inst) end
    syncCalloutUpdateToMDT(inst, extra.mdtStatus or 'ENROUTE')
    syncCalloutAttachToMDT(inst, src)
    syncUnitStatusToMDT(src, extra.mdtStatus or 'ENROUTE')
    startStatusLoopForCallout(inst.id)
    log("instance %s assigned to %d and spawn packet sent", inst.id, src)
    dumpActiveServer()
    return true
end

RegisterNetEvent("callouts:accept")
AddEventHandler("callouts:accept", function(calloutIdArg)
    local src = source
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED") return end
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_FOUND") dumpActiveServer() return end
    if inst.status == "ASSIGNED" then
        if tostring(inst.assignedTo) == tostring(src) then
            TriggerClientEvent("callouts:accepted", src, { id = inst.id, template = inst.template, title = inst.title, assignedTo = inst.assignedTo, coords = inst.coords })
            TriggerClientEvent("callouts:open_menu", src, inst.id)
            if not inst.mdtCallId then syncCalloutCreateToMDT(inst) end
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
            syncCalloutAttachToMDT(inst, src)
            syncUnitStatusToMDT(src, inst.mdtStatus or 'ENROUTE')
            return
        end
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "ALREADY_TAKEN")
        return
    end
    if inst.status ~= "ACTIVE" then TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_ACTIVE") dumpActiveServer() return end
    local existing = getAssignedCalloutByPlayer(src)
    if existing and tostring(existing.id) ~= calloutId then
        TriggerClientEvent("callouts:accepted", src, { id = existing.id, template = existing.template, title = existing.title, assignedTo = existing.assignedTo, coords = existing.coords })
        TriggerClientEvent("callouts:open_menu", src, existing.id)
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "ALREADY_ASSIGNED")
        return
    end
    finalizeAssignment(inst, src, { mdtStatus = 'ENROUTE' })
end)

RegisterNetEvent("callouts:accept_local")
AddEventHandler("callouts:accept_local", function(smallInst)
    local src = source
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then TriggerClientEvent("callouts:action_failed", src, smallInst and smallInst._originLocalId or "local", "NOT_AUTHORIZED") return end
    if not smallInst or not smallInst.template then return end
    local existing = getAssignedCalloutByPlayer(src)
    if existing then
        TriggerClientEvent("callouts:accepted", src, { id = existing.id, template = existing.template, title = existing.title, assignedTo = existing.assignedTo, coords = existing.coords })
        TriggerClientEvent("callouts:open_menu", src, existing.id)
        TriggerClientEvent("callouts:action_failed", src, smallInst and smallInst._originLocalId or "local", "ALREADY_ASSIGNED")
        return
    end
    local tmplName = tostring(smallInst.template):gsub("%.callout$", "")
    local tmpl = CalloutTemplates[tmplName]
    if not tmpl then return end
    local inst = makeInstanceFromTemplate(tmpl, smallInst.coords)
    if not inst then return end
    ActiveCallouts[inst.id] = inst
    syncCalloutCreateToMDT(inst)
    finalizeAssignment(inst, src, { origLocalId = smallInst._originLocalId, mdtStatus = 'ENROUTE' })
end)

RegisterNetEvent("callouts:end")
AddEventHandler("callouts:end", function(calloutIdArg)
    local src = source
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED")
        return
    end

    local calloutId = tostring(calloutIdArg)
    log("SERVER player %d attempted to end callout %s", src, calloutId)
    local inst = getInstance(calloutId)
    if not inst then
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_FOUND")
        log("player %d attempted to end non-existing callout %s", src, tostring(calloutIdArg))
        dumpActiveServer()
        return
    end
    if tostring(inst.assignedTo) ~= tostring(src) and tonumber(src) ~= 0 then
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_ASSIGNED_TO_YOU")
        log("player %d not assigned to callout %s attempted to end it", src, calloutId)
        return
    end

    inst.status = "COMPLETED"
    local releasedUnit = tonumber(inst.assignedTo) or tonumber(src) or 0
    TriggerClientEvent("callouts:ended", -1, {id = inst.id, template = inst.template, endedBy = src})
    if releasedUnit > 0 then
        syncUnitStatusToMDT(releasedUnit, 'AVAILABLE')
    end
    syncCalloutDeleteFromMDT(inst)
    ActiveCallouts[calloutId] = nil
    startedStatusLoops[calloutId] = nil
    log("callout %s ended by %s", calloutId, tostring(src))
end)

RegisterNetEvent("callouts:deny")
AddEventHandler("callouts:deny", function(calloutIdArg)
    local src = source
    TriggerClientEvent("callouts:denied_feedback", src, calloutIdArg)
    log("%d denied callout %s", src, tostring(calloutIdArg))
end)

RegisterNetEvent("callouts:status_response")
AddEventHandler("callouts:status_response", function(calloutIdArg, responseData)
    local src = source
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then log("received status_response for unknown callout %s from %d", tostring(calloutIdArg), src); return end
    if tostring(inst.assignedTo) ~= tostring(src) then
        log("received status_response for callout %s from non-assigned player %d (assigned %s)", tostring(calloutId), src, tostring(inst.assignedTo))
        return
    end
    inst.awaitingStatus = false
    inst.lastStatusResponse = {at = GetGameTimer(), data = responseData}
    log("callout %s status_response received from %d (response: %s)", tostring(calloutId), src, tostring(responseData and responseData.response or "nil"))
    TriggerClientEvent("callouts:status_response_ack", inst.assignedTo, {id = inst.id})
    local pName = tostring(GetPlayerName(src) or ("Player" .. tostring(src)))
    local responseKey = tostring(responseData and responseData.response or "")
    local mdtStatus = ({ ON_SCENE = 'ONSCENE', EN_ROUTE = 'ENROUTE', NEED_ASSISTANCE = 'ASSISTANCE' })[responseKey] or 'ENROUTE'
    local unitStatus = ({ ON_SCENE = 'ONSCENE', EN_ROUTE = 'ENROUTE', NEED_ASSISTANCE = 'ONSCENE' })[responseKey] or 'ENROUTE'
    inst.mdtStatus = mdtStatus
    if not inst.mdtCallId then syncCalloutCreateToMDT(inst) end
    syncCalloutUpdateToMDT(inst, mdtStatus)
    syncUnitStatusToMDT(src, unitStatus)
    TriggerClientEvent("callouts:player_update", -1, { id = inst.id, action = responseData and responseData.response or "status_update", player = src, name = pName, payload = responseData, timestamp = GetGameTimer() })
end)

RegisterNetEvent("callouts:request_backup")
AddEventHandler("callouts:request_backup", function(calloutIdArg, data)
    local src = source
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED")
        return
    end
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then
        TriggerClientEvent("callouts:action_failed", src, calloutIdArg, "NOT_FOUND")
        log("player %d requested backup for unknown callout %s", src, tostring(calloutIdArg))
        return
    end
    inst.backupRequests = inst.backupRequests or {}
    table.insert(inst.backupRequests, {by = src, payload = data, at = GetGameTimer()})
    TriggerClientEvent("callouts:player_update", -1, { id = inst.id, action = "backup_requested", player = src, name = tostring(GetPlayerName(src) or ("Player" .. tostring(src))), payload = data, timestamp = GetGameTimer() })
    log("player %d requested backup for callout %s", src, calloutId)
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        local now = GetGameTimer()
        for k, v in pairs(pendingPosRequests) do
            if v.timeoutTick and now > v.timeoutTick then
                log("pending position request %s timed out", k)
                pendingPosRequests[k] = nil
            end
        end
    end
end)

RegisterNetEvent("callouts:request_generate")
AddEventHandler("callouts:request_generate", function(smallInst)
    local src = source
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then
        TriggerClientEvent("callouts:action_failed", src, smallInst and smallInst.template or "req", "NOT_AUTHORIZED")
        return
    end
    if not smallInst or not smallInst.template then log("request_generate missing template from %d", src); return end

    local tmplName = tostring(smallInst.template):gsub("%.callout$", "")
    local tmpl = CalloutTemplates[tmplName]
    if not tmpl then log("request_generate unknown template '%s' from %d", tostring(smallInst.template), src); return end

    local coords = smallInst.coords or nil
    local inst = makeInstanceFromTemplate(tmpl, coords)
    if inst then
        inst.requestedBy = src
        broadcastInstance(inst)
        log("generated callout %s from client %d (template %s)", inst.id, src, tmplName)
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        local now = GetGameTimer()
        local expireMs = (tonumber(Config and Config.Callouts and Config.Callouts.serverExpireSeconds) or 180) * 1000
        for id, inst in pairs(ActiveCallouts) do
            if inst and inst.status == 'ACTIVE' and inst.createdAt and (now - inst.createdAt) >= expireMs then
                TriggerClientEvent('callouts:cancelled', -1, { id = inst.id, title = inst.title or ('Callout ' .. tostring(id)) })
                syncCalloutDeleteFromMDT(inst)
                ActiveCallouts[id] = nil
                log('expired unassigned callout %s after %d ms', tostring(id), now - inst.createdAt)
            end
        end
    end
end)

exports('AssignCalloutFromMDT', function(calloutId, src)
    src = tonumber(src) or 0
    if src <= 0 then return false, 'INVALID_SOURCE' end
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then return false, 'NOT_AUTHORIZED' end
    local inst = getInstance(calloutId)
    if not inst then return false, 'NOT_FOUND' end
    if inst.status == 'ASSIGNED' then
        if tostring(inst.assignedTo) == tostring(src) then
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
            syncCalloutAttachToMDT(inst, src)
            syncUnitStatusToMDT(src, inst.mdtStatus or 'ENROUTE')
            return true, inst.id
        end
        return false, 'ALREADY_TAKEN'
    end
    local existing = getAssignedCalloutByPlayer(src)
    if existing and tostring(existing.id) ~= tostring(calloutId) then finalizeAssignment(existing, src, { mdtStatus = 'ENROUTE' }) return false, 'ALREADY_ASSIGNED' end
    finalizeAssignment(inst, src, { mdtStatus = 'ENROUTE' })
    return true, inst.id
end)

AddEventHandler("onResourceStart", function(res)
    if res == GetCurrentResourceName() then
        math.randomseed(GetGameTimer() + (os and os.time() or 0))
        loadAllTemplates()
        log("ready. Use callout_spawn_random or callout_spawn <name> to test.")
        return
    end

    if isMDTResourceName(res) then
        CreateThread(function()
            Wait(1500)
            resyncAllCalloutsToMDT()
        end)
    end
end)

local DEFAULT_EMERGENCY_ID = "911"
local function normalizeArgs(arg1, ...)
    if type(arg1) == "table" then
        local t = arg1
        return {
            caller_identifier = tostring(t.caller_identifier or t.caller_id or t.caller or DEFAULT_EMERGENCY_ID),
            caller_name = tostring(t.caller_name or t.caller or t.name or "Unknown"),
            location = tostring(t.location or t.loc or "Unknown location"),
            message = tostring(t.message or t.msg or ""),
            status = tostring(t.status or "ACTIVE"),
            assigned_to = t.assigned_to and tostring(t.assigned_to) or nil,
            assigned_discord = t.assigned_discord and tostring(t.assigned_discord) or nil,
            emergency = t.emergency == true or nil
        }
    else
        local caller_identifier, caller_name, location, message, status, assigned_to, assigned_discord =
            tostring(arg1 or DEFAULT_EMERGENCY_ID),
            tostring((select(1, ...) or caller_identifier) and select(1, ...) or "Unknown"),
            tostring((select(2, ...) or location) and select(2, ...) or "Unknown location"),
            tostring((select(3, ...) or message) and select(3, ...) or ""),
            tostring((select(4, ...) or status) and select(4, ...) or "ACTIVE"),
            (select(5, ...)) and tostring(select(5, ...)) or nil,
            (select(6, ...)) and tostring(select(6, ...)) or nil
        return {
            caller_identifier = caller_identifier,
            caller_name = caller_name,
            location = location,
            message = message,
            status = status,
            assigned_to = assigned_to,
            assigned_discord = assigned_discord
        }
    end
end

local function insertDispatchCall(payload, cb)
    if payload.emergency then
        payload.caller_identifier = DEFAULT_EMERGENCY_ID
        payload.assigned_discord = payload.assigned_discord or DEFAULT_EMERGENCY_ID
    end

    local caller_identifier = payload.caller_identifier or DEFAULT_EMERGENCY_ID
    local caller_name = payload.caller_name or caller_identifier
    local location = payload.location or "Unknown location"
    local message = payload.message or ""
    local status = payload.status or "ACTIVE"
    local assigned_to = payload.assigned_to
    local assigned_discord = payload.assigned_discord

    local insertSql = [[
        INSERT INTO dispatch_calls
          (caller_identifier, caller_name, location, message, status, assigned_to, assigned_discord)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]]
    local params = { caller_identifier, caller_name, location, message, status, assigned_to, assigned_discord }

    exports.oxmysql:execute(insertSql, params, function(result)
        if not result then if cb then cb(false, "db_error") end return end
        exports.oxmysql:execute("SELECT LAST_INSERT_ID() AS id", {}, function(rows)
            local insertId = (rows and rows[1] and rows[1].id) and rows[1].id or nil
            if cb then cb(true, insertId) end
        end)
    end)
end

RegisterNetEvent("mdt:addCall", function(arg1, ...)
    local src = source
    local payload = normalizeArgs(arg1, ...)
    if payload.caller_identifier == nil or payload.caller_identifier == "" then payload.caller_identifier = DEFAULT_EMERGENCY_ID end
    insertDispatchCall(payload, function(success, insertIdOrErr)
        if success then
            print(("[mdt] new dispatch inserted id=%s caller=%s"):format(tostring(insertIdOrErr or "?"), tostring(payload.caller_identifier)))
            TriggerClientEvent("mdt:addCallResult", src, true, insertIdOrErr)
        else
            print(("[mdt] failed to insert dispatch: %s"):format(tostring(insertIdOrErr)))
            TriggerClientEvent("mdt:addCallResult", src, false, insertIdOrErr)
        end
    end)
end)

exports("AddDispatchCall", function(payloadOrArgs)
    if type(payloadOrArgs) == "table" then
        local finished = promise.new()
        insertDispatchCall(payloadOrArgs, function(success, idOrErr)
            if success then finished:resolve({true, idOrErr}) else finished:resolve({false, idOrErr}) end
        end)
        local res = Citizen.Await(finished)
        return table.unpack(res)
    else
        return false, "invalid_args"
    end
end)

RegisterNetEvent('mdt:requestRecords')
AddEventHandler('mdt:requestRecords', function(targetType, targetValue)
  local src = source
  exports.oxmysql:execute(
    'SELECT id, target_type, target_value, rtype, title, description, creator_identifier, creator_discord, timestamp FROM mdt_id_records WHERE target_type = ? AND target_value = ? ORDER BY timestamp DESC',
    { targetType, targetValue },
    function(rows)
      TriggerClientEvent('mdt:recordsResult', src, rows, targetType)
    end
  )
end)
