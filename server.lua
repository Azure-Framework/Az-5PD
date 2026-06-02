Config = Config or {}


local function az5pdStandaloneEnabled()
  return Az5PD and Az5PD.Framework and Az5PD.Framework.StandaloneEnabled()
end

local function az5pdHasFramework()
  return Az5PD and Az5PD.Framework and Az5PD.Framework.ActiveKind() ~= nil
end

local function az5pdAceEntries(key)
  return Az5PD.Framework.AceEntries(key)
end

local function az5pdHasAce(src, key)
  return Az5PD.Framework.HasAce(src, key)
end

local function az5pdHasStandaloneAccess(src)
  return Az5PD.Framework.HasStandaloneAccess(src)
end

local function az5pdStandaloneJobFor(src)
  return Az5PD.Framework.StandaloneJob(src)
end

local function az5pdNormalizeJobName(name)
  return Az5PD.Framework.ExtractName(name)
end

local function az5pdGetAllowedJobs()
  return Az5PD.Framework.GetAllowedJobs()
end

local function az5pdJobAllowed(jobName)
  return Az5PD.Framework.IsAllowedJob(jobName)
end


local function normalizeJobValue(job)
    return Az5PD.Framework.ExtractName(job)
end

local function getPlayerJobSafe(src)
    return Az5PD.Framework.GetPlayerJob(src)
end

local setPlayerUiAccessState

RegisterNetEvent("AzFR:requestPlayerJob", function()
    local src = source
    local job = getPlayerJobSafe(src)
    setPlayerUiAccessState(src)
    TriggerClientEvent("AzFR:responsePlayerJob", src, job)
end)

local function isJobAllowed(job)
    return Az5PD.Framework.IsAllowedJob(job)
end

local function getPlayerJob(src)
    return getPlayerJobSafe(src)
end

local CalloutTemplates = {}
local ActiveCallouts = {}
local getInstance
local pendingPosRequests = {}
local log
math.randomseed(os and os.time() or GetGameTimer())
local mdtBridgeByCallout = {}
local startedStatusLoops = {}
local leoDuty = {}
local leoDutyDepartment = {}

local function getPlayerNameSafe(src)
    return tostring(GetPlayerName(src) or ("Player" .. tostring(src)))
end


setPlayerUiAccessState = function(src)
    src = tonumber(src) or 0
    if src <= 0 then return end
    local ply = Player(src)
    if not (ply and ply.state) then return end
    local job = getPlayerJobSafe(src)
    local hasAccess = Az5PD.Framework.HasAccess(src)
    local kind = Az5PD.Framework.ActiveKind() or 'none'
    ply.state.az5pd_hasAccess = hasAccess == true
    ply.state.az5pd_framework = kind
    if hasAccess and kind == 'standalone' and Az5PD.Framework.StandaloneAutoDuty() then
        leoDuty[src] = true
        leoDutyDepartment[src] = job or Az5PD.Framework.StandaloneDefaultJob() or 'leo'
        ply.state.az5pd_onDuty = true
        ply.state.az5pd_department = leoDutyDepartment[src]
    elseif hasAccess and (kind == 'gimic' or (kind == 'qb' and Az5PD.Framework.RequireDuty())) then
        ply.state.az5pd_onDuty = true
        ply.state.az5pd_department = job or ply.state.az5pd_department or 'police'
    elseif not hasAccess and leoDuty[src] ~= true then
        ply.state.az5pd_onDuty = false
        ply.state.az5pd_department = nil
    end
end

local function setPlayerDutyState(src, onDuty, selectedDepartment)
    local ply = Player(src)
    if ply and ply.state then
        ply.state.az5pd_onDuty = onDuty == true
        ply.state.az5pd_department = selectedDepartment or leoDutyDepartment[src] or nil
    end
    setPlayerUiAccessState(src)
end

local function isCalloutResponder(inst, src)
    src = tonumber(src) or 0
    return src > 0 and inst and inst.responders and inst.responders[src] ~= nil
end

local function ensureCalloutResponder(inst, src, status)
    src = tonumber(src) or 0
    if src <= 0 or not inst then return nil end
    inst.responders = inst.responders or {}
    local entry = inst.responders[src]
    if not entry then
        entry = { joinedAt = os.time(), status = status or 'ENROUTE' }
        inst.responders[src] = entry
    end
    entry.status = status or entry.status or 'ENROUTE'
    entry.lastAt = GetGameTimer()
    return entry
end

local function removeCalloutResponder(inst, src)
    src = tonumber(src) or 0
    if src <= 0 or not inst or not inst.responders or not inst.responders[src] then return false end
    inst.responders[src] = nil
    return true
end

local function countCalloutResponders(inst)
    local count = 0
    for _ in pairs((inst and inst.responders) or {}) do
        count = count + 1
    end
    return count
end

local function buildCalloutRespondersPayload(inst)
    local responders = {}
    for responderSrc, info in pairs((inst and inst.responders) or {}) do
        responders[#responders + 1] = {
            id = tonumber(responderSrc) or 0,
            name = getPlayerNameSafe(responderSrc),
            status = tostring((info and info.status) or 'ENROUTE')
        }
    end
    table.sort(responders, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return responders
end

local function isAttachedToCallout(inst, src)
    return inst and (tostring(inst.assignedTo or '') == tostring(src) or isCalloutResponder(inst, src)) or false
end

local function getAssignedCalloutByPlayer(src)
    for _, inst in pairs(ActiveCallouts) do
        if inst and inst.status == "ASSIGNED" and isAttachedToCallout(inst, src) then
            return inst
        end
    end
    return nil
end

local function buildMDTUnitContext(src)
    return {
        department = leoDutyDepartment[src] or 'police',
        role = 'leo',
        isLEO = true,
        name = getPlayerNameSafe(src),
        callsign = ('L-%s'):format(tostring(src)),
        source = src,
        playerSource = src
    }
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


local function isSourceOnDuty(src)
    src = tonumber(src) or 0
    return src > 0 and leoDuty[src] == true
end

local function isSourceAuthorized(src)
    local job = getPlayerJob(src)
    if not isJobAllowed(job) then return false end
    return isSourceOnDuty(src)
end

local function syncCalloutCreateToMDT(inst, notifyUsers)
    if not inst or inst.mdtCallId then return end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, result = pcall(function()
        return exports[mdtResource]:CreateExternalCall({
            caller = 'Dispatch',
            message = tostring(inst.description or inst.title or 'Callout'),
            location = formatCalloutLocation(inst.coords),
            coords = inst.coords,
            status = inst.mdtStatus or (inst.status == 'ASSIGNED' and 'ENROUTE' or 'PENDING'),
            type = 'Police',
            kind = '911',
            source = 'Az-5PD',
            sourceResource = GetCurrentResourceName(),
            externalResource = GetCurrentResourceName(),
            metadata = { calloutId = tostring(inst.id), template = tostring(inst.template or ''), title = tostring(inst.title or 'Callout') },
            notify = notifyUsers == true,
            notificationTitle = 'Police Dispatch',
            notificationType = 'call',
            notificationMessage = ('%s • %s'):format(tostring(inst.title or 'Callout'), tostring(formatCalloutLocation(inst.coords) or 'Unknown location'))
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
            message = tostring(inst.description or inst.title or 'Callout'),
            location = formatCalloutLocation(inst.coords),
            coords = inst.coords,
            status = inst.mdtStatus,
            sourceResource = GetCurrentResourceName(),
            externalResource = GetCurrentResourceName()
        })
    end)
    if not ok then log('MDT bridge update failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(err)) end
end

local function syncCalloutAttachToMDT(inst, src)
    src = tonumber(src) or 0
    if not inst or src <= 0 then return false end
    if not inst.mdtCallId then
        syncCalloutCreateToMDT(inst, false)
    end
    if not inst.mdtCallId then
        log('MDT bridge attach skipped for %s; no mdtCallId', tostring(inst.id))
        return false
    end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return false end
    local ok, result = pcall(function() return exports[mdtResource]:AttachUnitToExternalCall(inst.mdtCallId, src, true) end)
    if not ok or result == false then
        log('MDT bridge attach failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(result))
        return false
    end
    return true
end

local function syncCalloutDetachFromMDT(inst, src)
    src = tonumber(src) or 0
    if not inst or src <= 0 or not inst.mdtCallId then return false end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return false end
    local ok, result = pcall(function() return exports[mdtResource]:DetachUnitFromExternalCall(inst.mdtCallId, src) end)
    if not ok or result == false then
        log('MDT bridge detach failed for %s via %s: %s', tostring(inst.id), tostring(mdtResource), tostring(result))
        return false
    end
    return true
end

local syncUnitStatusToMDT

local function queueCalloutMDTReconcile(calloutId, src, delayMs)
    src = tonumber(src) or 0
    local waitMs = math.max(100, tonumber(delayMs) or 500)
    if src <= 0 then return end
    SetTimeout(waitMs, function()
        if GetPlayerPing(src) <= 0 then return end
        local inst = calloutId ~= nil and ActiveCallouts[tostring(calloutId)] or nil
        if inst and isAttachedToCallout(inst, src) then
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
            syncCalloutAttachToMDT(inst, src)
            syncUnitStatusToMDT(src, inst.mdtStatus or 'ENROUTE')
        end
    end)
end

syncUnitStatusToMDT = function(src, status)
    if not src or src == 0 or not (Config and Config.Callouts) or Config.Callouts.syncUnitStatusToMDT == false then return end
    local mdtResource = resolveMDTResourceName()
    if not mdtResource then return end
    local ok, err = pcall(function()
        return exports[mdtResource]:SetUnitStatusFromExternal(src, status, buildMDTUnitContext(src))
    end)
    if not ok then log('MDT bridge unit status failed for src=%s via %s: %s', tostring(src), tostring(mdtResource), tostring(err)) end
end


local function detachPlayerFromCallouts(src, reason)
    src = tonumber(src) or 0
    if src <= 0 then return end

    for id, inst in pairs(ActiveCallouts) do
        if inst and isAttachedToCallout(inst, src) then
            syncCalloutDetachFromMDT(inst, src)
            syncUnitStatusToMDT(src, 'AVAILABLE')
            removeCalloutResponder(inst, src)

            if tostring(inst.assignedTo or '') == tostring(src) then
                inst.assignedTo = nil
                local responders = buildCalloutRespondersPayload(inst)
                if responders[1] and responders[1].id then
                    inst.assignedTo = responders[1].id
                end
            end

            if countCalloutResponders(inst) <= 0 then
                TriggerClientEvent('az5pd:callouts:ended', -1, { id = inst.id, template = inst.template, endedBy = src, reason = reason or 'cleared' })
                syncCalloutDeleteFromMDT(inst)
                ActiveCallouts[tostring(id)] = nil
                startedStatusLoops[tostring(id)] = nil
            else
                local responders = buildCalloutRespondersPayload(inst)
                TriggerClientEvent('az5pd:callouts:player_update', -1, {
                    id = inst.id,
                    action = 'unit_detached',
                    player = src,
                    name = getPlayerNameSafe(src),
                    responders = responders,
                    assignedTo = inst.assignedTo,
                    timestamp = GetGameTimer()
                })
                syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
                for _, responder in ipairs(responders) do
                    syncCalloutAttachToMDT(inst, responder.id)
                end
            end
        end
    end
end

local function setDutyStateInternal(src, desiredState, silent, selectedDepartment)
    src = tonumber(src) or 0
    if src <= 0 then return false end
    if not (Az5PD.Framework.HasAccess(src) or isJobAllowed(getPlayerJob(src))) then
        TriggerClientEvent('az5pd:dutyNotify', src, 'error', 'You are not allowed to use Police duty.')
        return false
    end
    if Az5PD.Framework.ActiveKind() == 'standalone' and Az5PD.Framework.StandaloneAutoDuty() then
        desiredState = true
        selectedDepartment = selectedDepartment or getPlayerJob(src) or Az5PD.Framework.StandaloneDefaultJob() or 'leo'
    else
        desiredState = desiredState == true
    end
    leoDuty[src] = desiredState
    if desiredState then
        local chosen = tostring(selectedDepartment or leoDutyDepartment[src] or getPlayerJob(src) or 'police'):lower()
        if chosen == '' then chosen = 'police' end
        leoDutyDepartment[src] = chosen
        syncUnitStatusToMDT(src, 'AVAILABLE')
    else
        detachPlayerFromCallouts(src, 'went_off_duty')
        leoDutyDepartment[src] = nil
        syncUnitStatusToMDT(src, 'OFFDUTY')
    end
    setPlayerDutyState(src, desiredState, leoDutyDepartment[src])
    TriggerClientEvent('az5pd:dutyStateUpdated', src, desiredState, leoDutyDepartment[src])
    return true
end

RegisterCommand('policeduty', function(src)
    if src == 0 then return end
    if resolveMDTResourceName() then
        TriggerClientEvent('az5pd:dutyNotify', src, 'info', 'Use Az-MDT to go on/off duty for Police.')
        return
    end
    setDutyStateInternal(src, not leoDuty[src], false)
end, false)

RegisterNetEvent('az5pd:setDutyState', function(desiredState, selectedDepartment)
    local src = source
    if resolveMDTResourceName() then
        TriggerClientEvent('az5pd:dutyNotify', src, 'info', 'Use Az-MDT to go on/off duty for Police.')
        return
    end
    setDutyStateInternal(src, desiredState == true, true, selectedDepartment)
end)

exports('SetDutyStateFromExternal', function(src, desiredState, ctxOrSilent)
    local silent = ctxOrSilent == true
    local selectedDepartment = nil
    if type(ctxOrSilent) == 'table' then
        selectedDepartment = ctxOrSilent.department or ctxOrSilent.job or ctxOrSilent.role
        silent = ctxOrSilent.silent == true
    end
    return setDutyStateInternal(src, desiredState == true, silent, selectedDepartment)
end)

exports('IsOnDuty', function(src)
    src = tonumber(src) or 0
    return src > 0 and leoDuty[src] == true
end)

local function syncCalloutDeleteFromMDT(inst)
    if not inst or not inst.mdtCallId then return end
    for responderSrc in pairs((inst and inst.responders) or {}) do
        syncUnitStatusToMDT(responderSrc, 'AVAILABLE')
    end
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
            syncCalloutCreateToMDT(inst, false)
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or (inst.status == 'ASSIGNED' and 'ENROUTE' or 'PENDING'))
            if inst.status == 'ASSIGNED' then
                for responderSrc in pairs((inst and inst.responders) or {}) do
                    syncCalloutAttachToMDT(inst, responderSrc)
                end
                if inst.assignedTo then
                    syncCalloutAttachToMDT(inst, inst.assignedTo)
                end
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

getInstance = function(id) if id == nil then return nil end return ActiveCallouts[tostring(id)] end

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


local function coord(x, y, z)
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local CuratedCalloutPools = {
    los_santos = {
        retail = {
            coord(28.07, -1339.12, 29.50),
            coord(373.04, 326.45, 103.57),
            coord(-707.41, -914.61, 19.22),
            coord(1135.73, -982.89, 46.42),
            coord(1159.51, -323.98, 69.21),
            coord(-1487.73, -379.52, 40.16),
            coord(-1223.74, -907.19, 12.33),
            coord(-1819.11, 793.64, 138.09)
        },
        residential = {
            coord(-1065.22, -1150.41, 2.16),
            coord(-1535.61, -425.62, 35.44),
            coord(312.44, -218.86, 54.22),
            coord(-614.44, 46.71, 43.59),
            coord(126.62, -1930.01, 21.38),
            coord(414.59, -2050.91, 22.10),
            coord(-36.13, -1447.27, 31.42),
            coord(-818.77, -1079.20, 11.13)
        },
        roadside = {
            coord(402.07, -1020.31, 29.32),
            coord(830.11, -1292.41, 26.27),
            coord(289.64, -584.72, 43.19),
            coord(-521.14, -220.12, 36.75),
            coord(1073.56, -775.29, 58.24),
            coord(-734.37, -2453.12, 13.95),
            coord(1198.44, -1408.21, 35.23),
            coord(-211.36, -1167.59, 23.04)
        },
        parking = {
            coord(116.35, -1060.24, 29.19),
            coord(257.11, -786.84, 30.52),
            coord(437.23, -980.18, 30.69),
            coord(-334.85, -781.64, 33.97),
            coord(-1183.91, -884.13, 13.76),
            coord(-55.21, -1096.87, 26.42),
            coord(274.11, -343.23, 44.92),
            coord(-3185.35, 1100.82, 20.85)
        },
        bar = {
            coord(1987.56, 3054.88, 47.22),
            coord(-560.34, 286.91, 82.18),
            coord(126.19, -1286.11, 29.28),
            coord(-1392.92, -606.23, 30.32),
            coord(378.94, -327.89, 46.95)
        },
        bridge = {
            coord(436.45, -981.75, 30.69),
            coord(-248.91, -1002.22, 29.26),
            coord(299.43, -1443.37, 29.80),
            coord(-1363.77, -471.69, 31.60)
        },
        medical = {
            coord(307.86, -595.15, 43.28),
            coord(1839.47, 3672.51, 34.28),
            coord(-247.18, 6331.26, 32.43)
        },
        overdose = {
            coord(312.44, -218.86, 54.22),
            coord(414.59, -2050.91, 22.10),
            coord(-36.13, -1447.27, 31.42),
            coord(116.35, -1060.24, 29.19),
            coord(-334.85, -781.64, 33.97),
            coord(274.11, -343.23, 44.92)
        }
    },
    sandy = {
        retail = {
            coord(1963.98, 3741.78, 32.34),
            coord(1392.64, 3604.55, 34.98),
            coord(1698.10, 4924.46, 42.06),
            coord(2678.95, 3280.67, 55.24),
            coord(1166.19, 2709.19, 38.16),
            coord(546.55, 2663.34, 42.16)
        },
        residential = {
            coord(1776.44, 3737.12, 34.66),
            coord(1726.84, 3851.15, 34.79),
            coord(1869.54, 3690.42, 33.55),
            coord(1665.90, 4764.62, 42.01),
            coord(2478.72, 4954.78, 45.03),
            coord(1447.52, 3655.71, 34.42)
        },
        roadside = {
            coord(1788.42, 3326.85, 41.43),
            coord(1407.19, 3600.42, 34.92),
            coord(2712.89, 3457.21, 56.04),
            coord(2498.84, 4102.31, 38.10),
            coord(1694.08, 3271.11, 41.15),
            coord(724.12, 4188.39, 40.71)
        },
        parking = {
            coord(1736.15, 3710.87, 34.14),
            coord(1855.64, 3683.17, 34.27),
            coord(2771.46, 3470.42, 55.66),
            coord(1706.81, 4800.57, 41.79),
            coord(1200.18, 2662.86, 37.81)
        },
        bar = {
            coord(1981.61, 3052.91, 47.22),
            coord(1993.47, 3046.13, 47.21),
            coord(1384.56, 3611.19, 34.89)
        },
        bridge = {
            coord(1662.83, 0.0, 0.0)
        },
        medical = {
            coord(1839.47, 3672.51, 34.28)
        },
        overdose = {
            coord(1776.44, 3737.12, 34.66),
            coord(1726.84, 3851.15, 34.79),
            coord(1855.64, 3683.17, 34.27),
            coord(1384.56, 3611.19, 34.89),
            coord(1706.81, 4800.57, 41.79)
        }
    },
    paleto = {
        retail = {
            coord(1735.55, 6416.29, 35.04),
            coord(1728.62, 6415.14, 35.04),
            coord(1702.18, 6425.12, 32.77),
            coord(-324.32, 6225.51, 31.49),
            coord(-48.84, 6524.41, 31.49)
        },
        residential = {
            coord(-96.23, 6325.11, 31.58),
            coord(-231.54, 6355.96, 31.49),
            coord(-301.80, 6329.34, 32.49),
            coord(-7.29, 6653.48, 31.11),
            coord(-112.81, 6470.84, 31.63),
            coord(-368.83, 6187.74, 31.49)
        },
        roadside = {
            coord(-111.64, 6389.57, 31.48),
            coord(-31.92, 6445.87, 31.43),
            coord(154.82, 6637.92, 31.57),
            coord(-275.44, 6042.76, 31.59),
            coord(-49.71, 6511.91, 31.49),
            coord(-439.12, 6025.87, 31.49),
            coord(-149.63, 6370.88, 31.49),
            coord(-58.96, 6321.76, 31.49),
            coord(73.81, 6505.84, 31.43),
            coord(-250.53, 6129.22, 31.51)
        },
        parking = {
            coord(-116.42, 6468.22, 31.47),
            coord(-243.37, 6211.63, 31.49),
            coord(-71.44, 6328.19, 31.49),
            coord(76.01, 6491.28, 31.43),
            coord(-329.82, 6248.48, 31.49),
            coord(-87.55, 6462.63, 31.49),
            coord(168.92, 6631.54, 31.70)
        },
        bar = {
            coord(-296.45, 6267.61, 31.49),
            coord(-258.88, 6246.47, 31.49)
        },
        bridge = {
            coord(-61.98, 6458.11, 31.46),
            coord(-430.02, 6030.55, 31.49)
        },
        medical = {
            coord(-247.18, 6331.26, 32.43)
        },
        overdose = {
            coord(-96.23, 6325.11, 31.58),
            coord(-231.54, 6355.96, 31.49),
            coord(-116.42, 6468.22, 31.47),
            coord(-71.44, 6328.19, 31.49),
            coord(-87.55, 6462.63, 31.49)
        }
    }
}


CuratedCalloutPools.sandy.bridge = {
    coord(2514.62, 4125.33, 38.59),
    coord(1709.66, 3337.19, 41.22)
}

local TemplateSpawnProfiles = {
    bar_fight = { category = 'bar' },
    civil_standby = { category = 'residential' },
    dog_attack = { category = 'residential' },
    domestic_violence = { category = 'residential' },
    drunk_driver = { category = 'roadside' },
    fight_in_progress = { category = 'parking' },
    hit_and_run_report = { category = 'roadside' },
    missing_person = { category = 'residential' },
    noise_complaint = { category = 'residential' },
    overdose_medical = { category = 'overdose', fallbackCategory = 'parking', minDistance = 90.0, maxDistance = 650.0, jitter = 1.25 },
    parking_lot_drug_activity = { category = 'parking' },
    person_in_crisis = { category = 'residential' },
    person_with_knife = { category = 'parking' },
    prowler_reported = { category = 'residential' },
    public_intox = { category = 'bar' },
    reckless_driver = { category = 'roadside' },
    residential_alarm = { category = 'residential' },
    residential_burglary = { category = 'residential' },
    road_hazard = { category = 'roadside' },
    robbery_in_progress = { category = 'retail' },
    shoplifter_detained = { category = 'retail' },
    shots_fired = { category = 'parking' },
    stolen_vehicle_occupied = { category = 'roadside' },
    subject_asleep_at_wheel = { category = 'roadside' },
    suicidal_subject_bridge = { category = 'bridge' },
    suspicious_person = { category = 'parking' },
    suspicious_vehicle = { category = 'parking' },
    test_1_attack = { category = 'parking' },
    traffic_collision = { category = 'roadside' },
    trespasser_refusing_to_leave = { category = 'retail' },
    vehicle_burglary = { category = 'parking' },
    vehicle_into_pole = { category = 'roadside' },
    welfare_check = { category = 'residential' },
    yelling_person = { category = 'residential' }
}

local CategorySpawnProfiles = {
    roadside = { min = 150.0, max = 950.0, hardMax = 1800.0, jitter = 4.0 },
    parking = { min = 90.0, max = 700.0, hardMax = 1500.0, jitter = 2.5 },
    residential = { min = 110.0, max = 650.0, hardMax = 1300.0, jitter = 2.5 },
    retail = { min = 120.0, max = 760.0, hardMax = 1500.0, jitter = 2.5 },
    bar = { min = 120.0, max = 760.0, hardMax = 1500.0, jitter = 2.5 },
    bridge = { min = 160.0, max = 1100.0, hardMax = 1900.0, jitter = 3.0 },
    medical = { min = 120.0, max = 800.0, hardMax = 1500.0, jitter = 2.5 },
    overdose = { min = 90.0, max = 650.0, hardMax = 1300.0, jitter = 1.25 },
    pursuit = { min = 220.0, max = 1400.0, hardMax = 2400.0, jitter = 5.0 }
}

local function distSqCoords(a, b)
    if not a or not b then return 999999999.0 end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function shallowCloneCoord(c)
    if not c then return nil end
    return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
end

local function jitterCoord(c, spread)
    if not c then return nil end
    local radius = tonumber(spread) or 3.0
    local dx = (math.random() * 2.0 - 1.0) * radius
    local dy = (math.random() * 2.0 - 1.0) * radius
    return { x = (c.x or 0.0) + dx, y = (c.y or 0.0) + dy, z = c.z or 0.0 }
end

local function getRegionCenter(name)
    if name == 'paleto' then return { x = -99.0, y = 6416.0, z = 31.5 } end
    if name == 'sandy' then return { x = 1847.0, y = 3690.0, z = 33.5 } end
    return { x = 216.0, y = -925.0, z = 30.0 }
end

local function chooseRegionNearCoords(playerCoords)
    local bestName, bestDist = 'los_santos', nil
    for regionName, _ in pairs(CuratedCalloutPools) do
        local center = getRegionCenter(regionName)
        local d = distSqCoords(playerCoords or center, center)
        if not bestDist or d < bestDist then
            bestDist = d
            bestName = regionName
        end
    end
    return bestName
end

local function getTemplateSpawnProfile(name)
    if not name then return nil end
    local key = tostring(name):gsub('%.callout$', '')
    return TemplateSpawnProfiles[key]
end

local function getPoolList(regionName, category)
    local region = CuratedCalloutPools[regionName or 'los_santos'] or CuratedCalloutPools.los_santos
    local list = region and region[category or 'parking'] or nil
    if type(list) == 'table' and #list > 0 then return list end
    if category ~= 'parking' then
        list = region and region.parking or nil
        if type(list) == 'table' and #list > 0 then return list end
    end
    local ls = CuratedCalloutPools.los_santos
    return (ls and (ls[category] or ls.parking)) or {}
end

local function distCoords(a, b)
    return math.sqrt(distSqCoords(a, b))
end

local function getSpawnProfileSettings(category, templateProfile)
    local cfg = (Config and Config.Callouts) or {}
    local base = CategorySpawnProfiles[category or 'parking'] or CategorySpawnProfiles.parking or {}
    local out = {
        min = tonumber(base.min) or 90.0,
        max = tonumber(base.max) or 700.0,
        hardMax = tonumber(base.hardMax) or 1500.0,
        jitter = tonumber(base.jitter) or 2.5,
    }
    out.min = tonumber(cfg.curatedMinDistanceFromPlayer) or out.min
    out.max = tonumber(cfg.curatedMaxDistanceFromPlayer) or out.max
    out.hardMax = tonumber(cfg.curatedHardMaxDistance) or out.hardMax
    if type(templateProfile) == 'table' then
        if templateProfile.minDistance then out.min = tonumber(templateProfile.minDistance) or out.min end
        if templateProfile.maxDistance then out.max = tonumber(templateProfile.maxDistance) or out.max end
        if templateProfile.hardMaxDistance then out.hardMax = tonumber(templateProfile.hardMaxDistance) or out.hardMax end
        if templateProfile.jitter then out.jitter = tonumber(templateProfile.jitter) or out.jitter end
    end
    if out.max < out.min then out.max = out.min end
    if out.hardMax < out.max then out.hardMax = out.max end
    return out
end

local function coordTooCloseToActive(point, minDist)
    local minD = tonumber(minDist) or 120.0
    for _, inst in pairs(ActiveCallouts) do
        if inst and inst.coords and inst.status ~= 'ENDED' then
            local d = distCoords(point, inst.coords)
            if d <= minD then
                return true
            end
        end
    end
    return false
end

local function collectPoolCandidates(category, fallbackCategory)
    local out = {}
    local seen = {}
    local function addList(list)
        if type(list) ~= 'table' then return end
        for _, point in ipairs(list) do
            if type(point) == 'table' and point.x and point.y then
                local key = ('%.2f:%.2f:%.2f'):format(point.x or 0.0, point.y or 0.0, point.z or 0.0)
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = point
                end
            end
        end
    end
    for _, region in pairs(CuratedCalloutPools) do
        addList(region[category])
    end
    if #out == 0 and fallbackCategory and fallbackCategory ~= category then
        for _, region in pairs(CuratedCalloutPools) do
            addList(region[fallbackCategory])
        end
    end
    return out
end

local function scoreSpawnPoint(point, playerCoords, settings)
    if not playerCoords or not playerCoords.x then
        return math.random() * 1000.0
    end
    local d = distCoords(playerCoords, point)
    if d > (settings.hardMax or 1500.0) then return nil end
    if d < math.max(45.0, (settings.min or 90.0) * 0.55) then return nil end
    local score = d * 0.02
    if d < settings.min then
        score = score + ((settings.min - d) * 4.0)
    elseif d > settings.max then
        score = score + ((d - settings.max) * 1.75)
    else
        score = score + math.abs(d - ((settings.min + settings.max) * 0.5)) * 0.015
    end
    return score, d
end

local function pickCuratedSpawnForTemplate(templateName, playerCoords)
    local profile = getTemplateSpawnProfile(templateName) or {}
    local category = profile.category or 'parking'
    local fallbackCategory = profile.fallbackCategory or (category ~= 'parking' and 'parking' or nil)
    local settings = getSpawnProfileSettings(category, profile)
    local list = collectPoolCandidates(category, fallbackCategory)
    if not list or #list == 0 then
        local regionName = chooseRegionNearCoords(playerCoords)
        list = getPoolList(regionName, category)
    end
    if not list or #list == 0 then
        return nil
    end

    local minBetween = tonumber((Config and Config.Callouts and Config.Callouts.minDistanceBetweenCallouts) or 120.0) or 120.0
    local scored = {}
    for _, point in ipairs(list) do
        if not coordTooCloseToActive(point, minBetween) then
            local score, dist = scoreSpawnPoint(point, playerCoords, settings)
            if score ~= nil then
                scored[#scored + 1] = { point = point, score = score, dist = dist or 0.0 }
            end
        end
    end

    if #scored == 0 then
        for _, point in ipairs(list) do
            local score, dist = scoreSpawnPoint(point, playerCoords, settings)
            if score ~= nil then
                scored[#scored + 1] = { point = point, score = score + 250.0, dist = dist or 0.0 }
            end
        end
    end

    if #scored == 0 then
        return jitterCoord(shallowCloneCoord(list[math.random(#list)]), settings.jitter)
    end

    table.sort(scored, function(a, b)
        if a.score == b.score then return a.dist < b.dist end
        return a.score < b.score
    end)

    local topN = math.max(1, math.min(#scored, tonumber((Config and Config.Callouts and Config.Callouts.curatedTopChoices) or 4) or 4))
    local choice = scored[math.random(topN)]
    return jitterCoord(shallowCloneCoord(choice.point), settings.jitter)
end

local function makeInstanceFromTemplate(template, coords)
    if not template then return nil end
    local finalCoords = coords
    if not finalCoords and template and template._name then
        finalCoords = pickCuratedSpawnForTemplate(template._name, nil)
    end
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
        responders = {},
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
    syncCalloutCreateToMDT(inst, true)
    TriggerClientEvent("az5pd:callouts:new", -1, {
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
    TriggerClientEvent("az5pd:callouts:request_position", playerServerId, {requestId = requestId})
    log("SERVER requested position from player %s for template %s (requestId=%s)", tostring(playerServerId), tostring(templateName), tostring(requestId))
    return requestId
end

RegisterNetEvent("az5pd:callouts:position_report")
AddEventHandler("az5pd:callouts:position_report", function(requestId, coords)
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

    local chosenCoords = pickCuratedSpawnForTemplate(templateName, coords)
    if not chosenCoords then
        local rx = coords.x + math.random(-25, 25)
        local ry = coords.y + math.random(-25, 25)
        local rz = coords.z
        chosenCoords = {x = rx, y = ry, z = rz}
    end
    local inst = makeInstanceFromTemplate(tmpl, chosenCoords)
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
                TriggerClientEvent("az5pd:callouts:status_check", inst.assignedTo, {id = inst.id, title = inst.title, description = inst.description})
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
    ensureCalloutResponder(inst, src, extra.mdtStatus or 'ENROUTE')

    local acceptedPayload = {
        id = inst.id,
        template = inst.template,
        title = inst.title,
        assignedTo = inst.assignedTo,
        coords = inst.coords,
        responders = buildCalloutRespondersPayload(inst),
        myAttached = true,
        primaryResponder = inst.assignedTo
    }
    if extra.origLocalId then acceptedPayload.origLocalId = extra.origLocalId end
    TriggerClientEvent("az5pd:callouts:accepted", -1, acceptedPayload)
    TriggerClientEvent("az5pd:callouts:open_menu", inst.assignedTo, inst.id)

    local spawnPacket = {
        id = inst.id,
        template = inst.template,
        title = inst.title,
        description = inst.description,
        coords = inst.coords,
        clientScript = inst.clientScript,
        assignedTo = inst.assignedTo
    }
    TriggerClientEvent("az5pd:callouts:spawn_entities", inst.assignedTo, spawnPacket)
    local acceptName = getPlayerNameSafe(src)
    TriggerClientEvent("az5pd:callouts:player_update", -1, {
        id = inst.id,
        action = "accepted",
        player = src,
        name = acceptName,
        responders = buildCalloutRespondersPayload(inst),
        assignedTo = inst.assignedTo,
        timestamp = GetGameTimer()
    })
    if not inst.mdtCallId then syncCalloutCreateToMDT(inst, false) end
    syncCalloutUpdateToMDT(inst, extra.mdtStatus or 'ENROUTE')
    syncCalloutAttachToMDT(inst, src)
    syncUnitStatusToMDT(src, extra.mdtStatus or 'ENROUTE')
    queueCalloutMDTReconcile(inst.id, src, 350)
    queueCalloutMDTReconcile(inst.id, src, 1200)
    queueCalloutMDTReconcile(inst.id, src, 2500)
    queueCalloutMDTReconcile(inst.id, src, 5000)
    queueCalloutMDTReconcile(inst.id, src, 8000)
    startStatusLoopForCallout(inst.id)
    log("instance %s assigned to %d and spawn packet sent", inst.id, src)
    dumpActiveServer()
    return true
end

local function joinAssignedCallout(inst, src, extra)
    if not inst or not src then return false end
    extra = extra or {}
    local status = extra.mdtStatus or inst.mdtStatus or 'ENROUTE'
    ensureCalloutResponder(inst, src, status)

    TriggerClientEvent("az5pd:callouts:accepted", src, {
        id = inst.id,
        template = inst.template,
        title = inst.title,
        assignedTo = inst.assignedTo,
        coords = inst.coords,
        responders = buildCalloutRespondersPayload(inst),
        myAttached = true,
        primaryResponder = inst.assignedTo,
        joinedBy = src
    })
    TriggerClientEvent("az5pd:callouts:open_menu", src, inst.id)
    TriggerClientEvent("az5pd:callouts:player_update", -1, {
        id = inst.id,
        action = 'joined',
        player = src,
        name = getPlayerNameSafe(src),
        responders = buildCalloutRespondersPayload(inst),
        assignedTo = inst.assignedTo,
        timestamp = GetGameTimer()
    })
    if not inst.mdtCallId then syncCalloutCreateToMDT(inst, false) end
    syncCalloutUpdateToMDT(inst, status)
    syncCalloutAttachToMDT(inst, src)
    syncUnitStatusToMDT(src, status)
    queueCalloutMDTReconcile(inst.id, src, 350)
    queueCalloutMDTReconcile(inst.id, src, 1200)
    queueCalloutMDTReconcile(inst.id, src, 2500)
    queueCalloutMDTReconcile(inst.id, src, 5000)
    queueCalloutMDTReconcile(inst.id, src, 8000)
    return true
end

RegisterNetEvent("az5pd:callouts:accept")
AddEventHandler("az5pd:callouts:accept", function(calloutIdArg)
    local src = source
    if not isSourceAuthorized(src) then TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED") return end
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_FOUND") dumpActiveServer() return end
    if inst.status == "ASSIGNED" then
        if isAttachedToCallout(inst, src) then
            TriggerClientEvent("az5pd:callouts:accepted", src, {
                id = inst.id,
                template = inst.template,
                title = inst.title,
                assignedTo = inst.assignedTo,
                coords = inst.coords,
                responders = buildCalloutRespondersPayload(inst),
                myAttached = true,
                primaryResponder = inst.assignedTo
            })
            TriggerClientEvent("az5pd:callouts:open_menu", src, inst.id)
            if not inst.mdtCallId then syncCalloutCreateToMDT(inst, false) end
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
            syncCalloutAttachToMDT(inst, src)
            syncUnitStatusToMDT(src, inst.mdtStatus or 'ENROUTE')
            queueCalloutMDTReconcile(inst.id, src, 350)
            queueCalloutMDTReconcile(inst.id, src, 1200)
            queueCalloutMDTReconcile(inst.id, src, 2500)
            queueCalloutMDTReconcile(inst.id, src, 5000)
            queueCalloutMDTReconcile(inst.id, src, 8000)
            return
        end
        local existingAssigned = getAssignedCalloutByPlayer(src)
        if existingAssigned and tostring(existingAssigned.id) ~= calloutId then
            TriggerClientEvent("az5pd:callouts:accepted", src, { id = existingAssigned.id, template = existingAssigned.template, title = existingAssigned.title, assignedTo = existingAssigned.assignedTo, coords = existingAssigned.coords, responders = buildCalloutRespondersPayload(existingAssigned), myAttached = true, primaryResponder = existingAssigned.assignedTo })
            TriggerClientEvent("az5pd:callouts:open_menu", src, existingAssigned.id)
            TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "ALREADY_ASSIGNED")
            return
        end
        joinAssignedCallout(inst, src, { mdtStatus = inst.mdtStatus or 'ENROUTE' })
        return
    end
    if inst.status ~= "ACTIVE" then TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_ACTIVE") dumpActiveServer() return end
    local existing = getAssignedCalloutByPlayer(src)
    if existing and tostring(existing.id) ~= calloutId then
        TriggerClientEvent("az5pd:callouts:accepted", src, { id = existing.id, template = existing.template, title = existing.title, assignedTo = existing.assignedTo, coords = existing.coords, responders = buildCalloutRespondersPayload(existing), myAttached = true, primaryResponder = existing.assignedTo })
        TriggerClientEvent("az5pd:callouts:open_menu", src, existing.id)
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "ALREADY_ASSIGNED")
        return
    end
    finalizeAssignment(inst, src, { mdtStatus = 'ENROUTE' })
end)

RegisterNetEvent("az5pd:callouts:accept_local")
AddEventHandler("az5pd:callouts:accept_local", function(smallInst)
    local src = source
    if not isSourceAuthorized(src) then TriggerClientEvent("az5pd:callouts:action_failed", src, smallInst and smallInst._originLocalId or "local", "NOT_AUTHORIZED") return end
    if not smallInst or not smallInst.template then return end
    local existing = getAssignedCalloutByPlayer(src)
    if existing then
        TriggerClientEvent("az5pd:callouts:accepted", src, { id = existing.id, template = existing.template, title = existing.title, assignedTo = existing.assignedTo, coords = existing.coords, responders = buildCalloutRespondersPayload(existing), myAttached = true, primaryResponder = existing.assignedTo })
        TriggerClientEvent("az5pd:callouts:open_menu", src, existing.id)
        TriggerClientEvent("az5pd:callouts:action_failed", src, smallInst and smallInst._originLocalId or "local", "ALREADY_ASSIGNED")
        return
    end
    local tmplName = tostring(smallInst.template):gsub("%.callout$", "")
    local tmpl = CalloutTemplates[tmplName]
    if not tmpl then return end
    local inst = makeInstanceFromTemplate(tmpl, smallInst.coords)
    if not inst then return end
    ActiveCallouts[inst.id] = inst
    syncCalloutCreateToMDT(inst, false)
    finalizeAssignment(inst, src, { origLocalId = smallInst._originLocalId, mdtStatus = 'ENROUTE' })
end)

RegisterNetEvent("az5pd:callouts:end")
AddEventHandler("az5pd:callouts:end", function(calloutIdArg)
    local src = source
    if not isSourceAuthorized(src) then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED")
        return
    end

    local calloutId = tostring(calloutIdArg)
    log("SERVER player %d attempted to end callout %s", src, calloutId)
    local inst = getInstance(calloutId)
    if not inst then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_FOUND")
        log("player %d attempted to end non-existing callout %s", src, tostring(calloutIdArg))
        dumpActiveServer()
        return
    end
    if not isAttachedToCallout(inst, src) and tonumber(src) ~= 0 then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_ASSIGNED_TO_YOU")
        log("player %d not attached to callout %s attempted to end it", src, calloutId)
        return
    end

    inst.status = "COMPLETED"
    TriggerClientEvent("az5pd:callouts:ended", -1, {id = inst.id, template = inst.template, endedBy = src})
    for responderSrc in pairs((inst and inst.responders) or {}) do
        syncCalloutDetachFromMDT(inst, responderSrc)
        syncUnitStatusToMDT(responderSrc, 'AVAILABLE')
    end
    syncCalloutDeleteFromMDT(inst)
    ActiveCallouts[calloutId] = nil
    startedStatusLoops[calloutId] = nil
    log("callout %s ended by %s for %s attached unit(s)", calloutId, tostring(src), tostring(countCalloutResponders(inst)))
end)

RegisterNetEvent("az5pd:callouts:deny")
AddEventHandler("az5pd:callouts:deny", function(calloutIdArg)
    local src = source
    TriggerClientEvent("az5pd:callouts:denied_feedback", src, calloutIdArg)
    log("%d denied callout %s", src, tostring(calloutIdArg))
end)

RegisterNetEvent("az5pd:callouts:status_response")
AddEventHandler("az5pd:callouts:status_response", function(calloutIdArg, responseData)
    local src = source
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then log("received status_response for unknown callout %s from %d", tostring(calloutIdArg), src); return end
    if not isAttachedToCallout(inst, src) then
        log("received status_response for callout %s from non-attached player %d (assigned %s)", tostring(calloutId), src, tostring(inst.assignedTo))
        return
    end
    inst.awaitingStatus = false
    inst.lastStatusResponse = {at = GetGameTimer(), data = responseData}
    log("callout %s status_response received from %d (response: %s)", tostring(calloutId), src, tostring(responseData and responseData.response or "nil"))
    TriggerClientEvent("az5pd:callouts:status_response_ack", src, {id = inst.id})
    local pName = tostring(GetPlayerName(src) or ("Player" .. tostring(src)))
    local responseKey = tostring(responseData and responseData.response or "")
    local mdtStatus = ({ ON_SCENE = 'ONSCENE', EN_ROUTE = 'ENROUTE', NEED_ASSISTANCE = 'ASSISTANCE' })[responseKey] or 'ENROUTE'
    local unitStatus = ({ ON_SCENE = 'ONSCENE', EN_ROUTE = 'ENROUTE', NEED_ASSISTANCE = 'ONSCENE' })[responseKey] or 'ENROUTE'
    inst.mdtStatus = mdtStatus
    local responderEntry = ensureCalloutResponder(inst, src, unitStatus)
    if responderEntry then responderEntry.status = unitStatus end
    if not inst.mdtCallId then syncCalloutCreateToMDT(inst, false) end
    syncCalloutUpdateToMDT(inst, mdtStatus)
    syncUnitStatusToMDT(src, unitStatus)
    TriggerClientEvent("az5pd:callouts:player_update", -1, { id = inst.id, action = responseData and responseData.response or "status_update", player = src, name = pName, payload = responseData, timestamp = GetGameTimer() })
end)

RegisterNetEvent("az5pd:callouts:request_backup")
AddEventHandler("az5pd:callouts:request_backup", function(calloutIdArg, data)
    local src = source
    if not isSourceAuthorized(src) then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_AUTHORIZED")
        return
    end
    local calloutId = tostring(calloutIdArg)
    local inst = getInstance(calloutId)
    if not inst then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_FOUND")
        log("player %d requested backup for unknown callout %s", src, tostring(calloutIdArg))
        return
    end
    if not isAttachedToCallout(inst, src) then
        TriggerClientEvent("az5pd:callouts:action_failed", src, calloutIdArg, "NOT_ASSIGNED_TO_YOU")
        log("player %d requested backup for unattached callout %s", src, tostring(calloutIdArg))
        return
    end
    inst.backupRequests = inst.backupRequests or {}
    table.insert(inst.backupRequests, {by = src, payload = data, at = GetGameTimer()})
    TriggerClientEvent("az5pd:callouts:player_update", -1, { id = inst.id, action = "backup_requested", player = src, name = tostring(GetPlayerName(src) or ("Player" .. tostring(src))), payload = data, timestamp = GetGameTimer() })
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


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        for _, src in ipairs(GetPlayers()) do
            setPlayerUiAccessState(src)
        end
    end
end)

RegisterNetEvent("az5pd:callouts:request_generate")
AddEventHandler("az5pd:callouts:request_generate", function(smallInst)
    local src = source
    if not isSourceAuthorized(src) then
        TriggerClientEvent("az5pd:callouts:action_failed", src, smallInst and smallInst.template or "req", "NOT_AUTHORIZED")
        return
    end
    if not smallInst or not smallInst.template then log("request_generate missing template from %d", src); return end

    local tmplName = tostring(smallInst.template):gsub("%.callout$", "")
    local tmpl = CalloutTemplates[tmplName]
    if not tmpl then log("request_generate unknown template '%s' from %d", tostring(smallInst.template), src); return end

    local useCurated = not (Config and Config.Callouts and Config.Callouts.useCuratedSpawner == false)
    local playerCoords = nil
    if type(smallInst.playerCoords) == 'table' and smallInst.playerCoords.x then
        playerCoords = { x = tonumber(smallInst.playerCoords.x) or 0.0, y = tonumber(smallInst.playerCoords.y) or 0.0, z = tonumber(smallInst.playerCoords.z) or 0.0 }
    elseif type(smallInst.origin) == 'table' and smallInst.origin.x then
        playerCoords = { x = tonumber(smallInst.origin.x) or 0.0, y = tonumber(smallInst.origin.y) or 0.0, z = tonumber(smallInst.origin.z) or 0.0 }
    end

    local coords = nil
    if useCurated and playerCoords then
        coords = pickCuratedSpawnForTemplate(tmplName, playerCoords)
    end
    if not coords then
        coords = smallInst.coords or nil
    end

    local inst = makeInstanceFromTemplate(tmpl, coords)
    if inst then
        inst.requestedBy = src
        inst.requestedNear = playerCoords
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
                TriggerClientEvent('az5pd:callouts:cancelled', -1, { id = inst.id, title = inst.title or ('Callout ' .. tostring(id)) })
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
    if not isSourceAuthorized(src) then return false, 'NOT_AUTHORIZED' end
    local inst = getInstance(calloutId)
    if not inst then return false, 'NOT_FOUND' end
    if inst.status == 'ASSIGNED' then
        if isAttachedToCallout(inst, src) then
            syncCalloutUpdateToMDT(inst, inst.mdtStatus or 'ENROUTE')
            syncCalloutAttachToMDT(inst, src)
            syncUnitStatusToMDT(src, inst.mdtStatus or 'ENROUTE')
            return true, inst.id
        end
        local existingAssigned = getAssignedCalloutByPlayer(src)
        if existingAssigned and tostring(existingAssigned.id) ~= tostring(calloutId) then
            return false, 'ALREADY_ASSIGNED'
        end
        joinAssignedCallout(inst, src, { mdtStatus = inst.mdtStatus or 'ENROUTE' })
        return true, inst.id
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


AddEventHandler('playerDropped', function()
    local src = source
    detachPlayerFromCallouts(src, 'disconnected')
    leoDuty[src] = nil
    leoDutyDepartment[src] = nil
end)

RegisterNetEvent('Az-Framework:jobChanged', function(changedSrc)
    local src = tonumber(changedSrc) or tonumber(source)
    if not src or src <= 0 then return end
    setPlayerUiAccessState(src)
    if leoDuty[src] and not isJobAllowed(getPlayerJob(src)) then
        setDutyStateInternal(src, false, true)
    end
end) 

local function refreshPlayerAccess(src)
    src = tonumber(src) or tonumber(source)
    if not src or src <= 0 then return end
    setPlayerUiAccessState(src)
    if leoDuty[src] and not Az5PD.Framework.HasAccess(src) and not isJobAllowed(getPlayerJob(src)) then
        setDutyStateInternal(src, false, true)
    end
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function() refreshPlayerAccess(source) end)
RegisterNetEvent('QBCore:Server:OnJobUpdate', function(src) refreshPlayerAccess(src or source) end)
RegisterNetEvent('esx:playerLoaded', function(src) refreshPlayerAccess(src or source) end)
RegisterNetEvent('esx:setJob', function(src) refreshPlayerAccess(src or source) end)
RegisterNetEvent('gimicCore:server:playerDutyChanged', function(src) refreshPlayerAccess(src or source) end)
RegisterNetEvent('gimicCore:playerDutyChanged', function(src) refreshPlayerAccess(src or source) end)
AddEventHandler('playerJoining', function() refreshPlayerAccess(source) end)
AddEventHandler('onResourceStart', function(resourceName)
    local resources = Az5PD.Framework.ResourceNames()
    if resourceName ~= resources.qb and resourceName ~= resources.esx and resourceName ~= resources.gimic and resourceName ~= resources.az then return end
    SetTimeout(1000, function()
        for _, playerId in ipairs(GetPlayers() or {}) do
            refreshPlayerAccess(tonumber(playerId))
        end
    end)
end)
