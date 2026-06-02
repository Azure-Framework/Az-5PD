Az5PD = Az5PD or {}
Az5PD.Framework = Az5PD.Framework or {}

local Bridge = Az5PD.Framework

local function stringify(value, depth)
  depth = depth or 0
  if value == nil then return 'nil' end
  if type(value) ~= 'table' then return tostring(value) end
  if depth > 1 then return '{...}' end
  local parts = {}
  for key, item in pairs(value) do
    parts[#parts + 1] = tostring(key) .. '=' .. stringify(item, depth + 1)
    if #parts >= 8 then
      parts[#parts + 1] = '...'
      break
    end
  end
  return '{' .. table.concat(parts, ', ') .. '}'
end

local function cfg()
  Config = Config or {}
  local raw = Config.Framework
  local legacy = type(raw) == 'table' and raw or {}
  local mode = legacy.mode or raw or 'auto'
  local resources = Config.FrameworkResources or legacy.resources or {}
  local prefer = Config.FrameworkPriority or legacy.prefer or { 'gimic', 'qb', 'esx', 'az', 'standalone' }
  resources.az = resources.az or 'Az-Framework'
  resources.qb = resources.qb or 'qb-core'
  resources.esx = resources.esx or 'es_extended'
  resources.gimic = resources.gimic or 'gimicCore'
  return {
    mode = tostring(mode or 'auto'):lower(),
    resources = resources,
    prefer = prefer,
    requireDuty = Config.FrameworkRequireDuty == true or legacy.requireDuty == true,
    debug = Config.FrameworkDebug == true or Config.DebugFramework == true
  }
end

local function debugEnabled()
  local c = cfg()
  return c.debug == true
end

local function dbg(scope, message, data)
  if not debugEnabled() then return end
  local side = (type(IsDuplicityVersion) == 'function' and IsDuplicityVersion()) and 'server' or 'client'
  local suffix = data ~= nil and (' | ' .. stringify(data)) or ''
  print(('[Az-5PD:%s:%s] %s%s'):format(side, tostring(scope or 'debug'), tostring(message or ''), suffix))
end

function Bridge.Debug(scope, message, data)
  dbg(scope, message, data)
end

function Bridge.RequireDuty()
  return cfg().requireDuty == true
end

function Bridge.ResourceNames()
  return cfg().resources or {}
end

local function resourceName(kind)
  local c = cfg()
  return c.resources and c.resources[kind] or nil
end

local function resourceStarted(name)
  local started = name and name ~= '' and type(GetResourceState) == 'function' and GetResourceState(name) == 'started'
  dbg('resource', 'state check', { resource = name, started = started })
  return started
end

local function modeEnabled(kind)
  local c = cfg()
  local mode = c.mode
  return mode == 'auto' or mode == kind
end

local function extractName(value)
  if value == nil then return nil end
  if type(value) == 'table' then
    local nested = value.name or value.job or value.id or value.label or value.department or value.dept or value.shortName or value.longName or value.code
    if type(nested) == 'table' then
      nested = nested.name or nested.job or nested.id or nested.label or nested.department or nested.dept or nested.shortName or nested.longName or nested.code
    end
    value = nested
  end
  if value == nil then return nil end
  local out = tostring(value)
  if out == '' or out == 'nil' or out:match('^table:') then return nil end
  return out:lower()
end

local function listContains(list, value)
  value = extractName(value)
  if not value or value == '' or type(list) ~= 'table' then return false end
  for i = 1, #list do
    if extractName(list[i]) == value then return true end
  end
  for key, enabled in pairs(list) do
    if enabled == true and extractName(key) == value then return true end
  end
  return false
end

function Bridge.ExtractName(value)
  return extractName(value)
end

function Bridge.GetAllowedJobs()
  local jobs = Config and Config.Jobs and Config.Jobs.allowed
  if type(jobs) == 'table' and next(jobs) ~= nil then return jobs end
  if type(Config and Config.AllowedJobs) == 'table' and next(Config.AllowedJobs) ~= nil then return Config.AllowedJobs end
  return { 'bcso', 'sheriff', 'lspd', 'police', 'sast', 'state', 'trooper', 'leo' }
end

function Bridge.GetSupervisorJobs()
  local jobs = Config and Config.Jobs and Config.Jobs.supervisors
  if type(jobs) == 'table' and next(jobs) ~= nil then return jobs end
  local simJobs = Config and Config.Sim and Config.Sim.Framework and Config.Sim.Framework.supervisorJobs
  if type(simJobs) == 'table' and next(simJobs) ~= nil then return simJobs end
  return { 'bcso_supervisor', 'sheriff_supervisor', 'lspd_supervisor', 'police_supervisor', 'sast_supervisor', 'state_supervisor', 'command', 'dispatch' }
end

function Bridge.IsAllowedJob(job)
  if Config and Config.Jobs and Config.Jobs.requireJob == false then
    dbg('job', 'job requirement disabled', { job = job })
    return true
  end
  local allowed = listContains(Bridge.GetAllowedJobs(), job)
  dbg('job', 'allowed job check', { job = extractName(job), allowed = allowed })
  return allowed
end

function Bridge.IsSupervisorJob(job)
  local allowed = listContains(Bridge.GetSupervisorJobs(), job)
  dbg('job', 'supervisor job check', { job = extractName(job), allowed = allowed })
  return allowed
end

function Bridge.AceEntries(key)
  local value = Config and Config.AcePermissions and Config.AcePermissions[key]
  if type(value) == 'table' then return value end
  value = tostring(value or '')
  if value == '' then return {} end
  return { value }
end

function Bridge.HasAce(src, key)
  src = tonumber(src) or 0
  if src <= 0 or type(IsPlayerAceAllowed) ~= 'function' then
    dbg('ace', 'ace unavailable', { source = src, key = key })
    return false
  end
  for _, perm in ipairs(Bridge.AceEntries(key)) do
    local permission = tostring(perm or '')
    local allowed = permission ~= '' and IsPlayerAceAllowed(src, permission) == true
    dbg('ace', 'permission check', { source = src, key = key, permission = permission, allowed = allowed })
    if allowed then return true end
  end
  return false
end

function Bridge.StandaloneEnabled()
  return Config and Config.Standalone == true
end

function Bridge.HasStandaloneAccess(src)
  if not Bridge.StandaloneEnabled() then
    dbg('standalone', 'standalone disabled', { source = src })
    return false
  end
  local allowed = Bridge.HasAce(src, 'open') or Bridge.HasAce(src, 'supervisor') or Bridge.HasAce(src, 'dispatch') or Bridge.HasAce(src, 'admin')
  dbg('standalone', 'standalone access check', { source = src, allowed = allowed })
  return allowed
end

function Bridge.StandaloneJob(src)
  if not Bridge.HasStandaloneAccess(src) then return nil end
  local fallback = tostring((Config and Config.AcePermissions and Config.AcePermissions.fallbackJob) or 'leo')
  if fallback == '' then fallback = 'leo' end
  return fallback:lower()
end

local function callExport(resource, fn, ...)
  if not resourceStarted(resource) then return false, nil end
  local ok, result = pcall(function(...)
    if not exports or not exports[resource] or type(exports[resource][fn]) ~= 'function' then return nil end
    return exports[resource][fn](...)
  end, ...)
  if ok then return true, result end
  return false, nil
end

local function qbObject()
  local name = resourceName('qb')
  if not resourceStarted(name) then return nil end
  local ok, obj = pcall(function() return exports[name]:GetCoreObject() end)
  if ok and type(obj) == 'table' then return obj end
  return nil
end

local function esxObject()
  local name = resourceName('esx')
  if not resourceStarted(name) then return nil end
  local ok, obj = pcall(function() return exports[name]:getSharedObject() end)
  if ok and type(obj) == 'table' then return obj end
  return nil
end

local function serverId()
  if type(cache) == 'table' and cache.serverId then return cache.serverId end
  if type(GetPlayerServerId) == 'function' and type(PlayerId) == 'function' then return GetPlayerServerId(PlayerId()) end
  return nil
end

local function localState()
  return LocalPlayer and LocalPlayer.state or nil
end

local function jobFromQb(src)
  local QBCore = qbObject()
  if not QBCore or not QBCore.Functions or type(QBCore.Functions.GetPlayer) ~= 'function' then
    dbg('qb', 'QBCore player API unavailable', { source = src })
    return nil, false
  end
  local player = QBCore.Functions.GetPlayer(tonumber(src))
  local job = player and player.PlayerData and player.PlayerData.job
  if not job then
    dbg('qb', 'job missing', { source = src })
    return nil, false
  end
  local name = extractName(job)
  local isLeo = job.type == 'leo' or Bridge.IsAllowedJob(name)
  local requireDuty = cfg().requireDuty == true
  if requireDuty and job.onduty == false then isLeo = false end
  dbg('qb', 'job check', { source = src, job = name, type = job.type, onduty = job.onduty, requireDuty = requireDuty, allowed = isLeo })
  return name, isLeo
end

local function jobFromEsx(src)
  local ESX = esxObject()
  if not ESX or type(ESX.GetPlayerFromId) ~= 'function' then
    dbg('esx', 'ESX player API unavailable', { source = src })
    return nil, false
  end
  local player = ESX.GetPlayerFromId(tonumber(src))
  local job = player and player.job
  local name = extractName(job)
  local allowed = Bridge.IsAllowedJob(name)
  dbg('esx', 'job check', { source = src, job = name, allowed = allowed })
  return name, allowed
end

local function jobFromAz(src)
  local name = resourceName('az')
  if not resourceStarted(name) then
    dbg('az', 'Az framework resource unavailable', { source = src, resource = name })
    return nil, false
  end
  local ok, job = pcall(function() return exports[name]:getPlayerJob(src) end)
  job = ok and extractName(job) or nil
  local allowed = Bridge.IsAllowedJob(job)
  dbg('az', 'job check', { source = src, job = job, exportOk = ok, allowed = allowed })
  return job, allowed
end

local function jobFromGimic(src)
  local name = resourceName('gimic')
  if not resourceStarted(name) then
    dbg('gimic', 'Gimic resource unavailable', { source = src, resource = name })
    return nil, false
  end
  local onDutyOk, onDuty = callExport(name, 'IsOnLEODuty', src)
  local deptOk, dept = callExport(name, 'GetPlayerDepartment', src)
  local job = nil
  if deptOk and type(dept) == 'table' then
    local first = dept[1] or dept
    job = extractName(first and (first.shortName or first.longName or first.name or first.type or first.category) or dept)
  end
  if not job then
    local jobOk, jobGang = callExport(name, 'GetPlayerJobGang', src)
    if jobOk then job = extractName((type(jobGang) == 'table' and (jobGang[1] or jobGang)) or jobGang) end
  end
  local allowed = onDutyOk and onDuty == true
  dbg('gimic', 'duty and department check', { source = src, job = job, onDutyOk = onDutyOk, onDuty = onDuty, deptOk = deptOk, allowed = allowed })
  return job or 'leo', allowed
end

function Bridge.ActiveKind()
  local c = cfg()
  local preferred = c.prefer
  if type(preferred) ~= 'table' then preferred = { 'gimic', 'qb', 'esx', 'az', 'standalone' } end
  dbg('framework', 'resolving framework', { configured = c.mode, standalone = Bridge.StandaloneEnabled(), priority = preferred })
  for i = 1, #preferred do
    local kind = tostring(preferred[i] or ''):lower()
    if modeEnabled(kind) then
      if kind == 'standalone' and Bridge.StandaloneEnabled() then
        dbg('framework', 'selected framework', { kind = kind })
        return kind
      end
      if kind ~= 'standalone' and resourceStarted(resourceName(kind)) then
        dbg('framework', 'selected framework', { kind = kind, resource = resourceName(kind) })
        return kind
      end
    else
      dbg('framework', 'skipped framework by config', { kind = kind, configured = c.mode })
    end
  end
  if Bridge.StandaloneEnabled() then
    dbg('framework', 'selected standalone fallback', {})
    return 'standalone'
  end
  dbg('framework', 'no framework selected', { configured = c.mode })
  return nil
end

function Bridge.GetPlayerJob(src)
  src = tonumber(src) or 0
  if src <= 0 then return nil end
  local kind = Bridge.ActiveKind()
  local job = nil
  if kind == 'gimic' then job = jobFromGimic(src)
  elseif kind == 'qb' then job = jobFromQb(src)
  elseif kind == 'esx' then job = jobFromEsx(src)
  elseif kind == 'az' then job = jobFromAz(src)
  else job = Bridge.StandaloneJob(src) end
  dbg('framework', 'player job result', { source = src, framework = kind or 'none', job = job })
  return job
end

function Bridge.HasAccess(src)
  src = tonumber(src) or 0
  if src <= 0 then return false end
  if Bridge.HasStandaloneAccess(src) then
    dbg('access', 'allowed by standalone ACE', { source = src })
    return true
  end
  local kind = Bridge.ActiveKind()
  local allowed = false
  local job = nil
  if kind == 'gimic' then job, allowed = jobFromGimic(src)
  elseif kind == 'qb' then job, allowed = jobFromQb(src)
  elseif kind == 'esx' then job, allowed = jobFromEsx(src)
  elseif kind == 'az' then job, allowed = jobFromAz(src) end
  dbg('access', 'framework access result', { source = src, framework = kind or 'none', job = job, allowed = allowed == true })
  return allowed == true
end

function Bridge.IsSupervisor(src)
  if Bridge.HasAce(src, 'admin') or Bridge.HasAce(src, 'supervisor') then
    dbg('supervisor', 'allowed by ACE', { source = src })
    return true
  end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local name = resourceName('gimic')
    local ok, perms = callExport(name, 'GetDiscordPermissions', src)
    if ok and type(perms) == 'table' and (perms.IsOwner == true or perms.IsManagement == true or perms.IsStaff == true) then
      dbg('supervisor', 'allowed by Gimic Discord permissions', { source = src, permissions = perms })
      return true
    end
    local ownerOk, owner = callExport(name, 'IsGroup', src, 'owner', 'management')
    if ownerOk and owner == true then
      dbg('supervisor', 'allowed by Gimic group', { source = src })
      return true
    end
  end
  local job = Bridge.GetPlayerJob(src)
  local allowed = Bridge.IsSupervisorJob(job)
  dbg('supervisor', 'supervisor result', { source = src, framework = kind or 'none', job = job, allowed = allowed })
  return allowed
end

function Bridge.AddMoney(src, amount)
  src = tonumber(src) or 0
  amount = tonumber(amount) or 0
  if src <= 0 or amount <= 0 then
    dbg('money', 'invalid reward request', { source = src, amount = amount })
    return false
  end
  local kind = Bridge.ActiveKind()
  if kind == 'qb' then
    local QBCore = qbObject()
    local player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer and QBCore.Functions.GetPlayer(src)
    if player and player.Functions and type(player.Functions.AddMoney) == 'function' then
      local ok = player.Functions.AddMoney('cash', amount, 'az-5pd-citation') == true
      dbg('money', 'QBCore reward', { source = src, amount = amount, success = ok })
      return ok
    end
  elseif kind == 'esx' then
    local ESX = esxObject()
    local player = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if player and type(player.addMoney) == 'function' then
      player.addMoney(amount)
      dbg('money', 'ESX reward', { source = src, amount = amount, success = true })
      return true
    end
  elseif kind == 'az' then
    local name = resourceName('az')
    local ok, result = pcall(function() return exports[name]:addMoney(src, amount) end)
    local success = ok and result ~= false
    dbg('money', 'Az reward', { source = src, amount = amount, exportOk = ok, success = success })
    return success
  end
  dbg('money', 'no money API available', { source = src, amount = amount, framework = kind or 'none' })
  return false
end

function Bridge.ClientJob()
  local state = localState()
  if state then
    local job = extractName(state.department) or extractName(state.job) or extractName(state.PlayerData and state.PlayerData.job)
    if job then
      dbg('client-job', 'statebag job found', { job = job })
      return job
    end
  end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local sid = serverId()
    local name = resourceName('gimic')
    local ok, dept = callExport(name, 'GetPlayerDepartment', sid)
    if ok and type(dept) == 'table' then
      local first = dept[1] or dept
      local job = extractName(first and (first.shortName or first.longName or first.name or first.type or first.category) or dept)
      dbg('client-job', 'Gimic department job', { source = sid, job = job })
      return job
    end
  elseif kind == 'qb' then
    local QBCore = qbObject()
    local data = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData and QBCore.Functions.GetPlayerData()
    local job = extractName(data and data.job)
    dbg('client-job', 'QBCore client job', { job = job })
    return job
  elseif kind == 'esx' then
    local ESX = esxObject()
    local data = ESX and ESX.GetPlayerData and ESX.GetPlayerData()
    local job = extractName(data and data.job)
    dbg('client-job', 'ESX client job', { job = job })
    return job
  end
  dbg('client-job', 'no client job found', { framework = kind or 'none' })
  return nil
end

function Bridge.ClientHasAccess()
  local state = localState()
  if state and state.az5pd_hasAccess ~= nil then
    local allowed = state.az5pd_hasAccess == true
    dbg('client-access', 'statebag access', { allowed = allowed })
    return allowed
  end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local ok, onDuty = callExport(resourceName('gimic'), 'IsOnLEODuty', serverId())
    if ok then
      local allowed = onDuty == true
      dbg('client-access', 'Gimic duty access', { onDuty = onDuty, allowed = allowed })
      return allowed
    end
  elseif kind == 'qb' then
    local QBCore = qbObject()
    local data = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData and QBCore.Functions.GetPlayerData()
    local job = data and data.job
    local name = extractName(job)
    local allowed = (job and job.type == 'leo') or Bridge.IsAllowedJob(name)
    if cfg().requireDuty == true and job and job.onduty == false then allowed = false end
    dbg('client-access', 'QBCore client access', { job = name, type = job and job.type, onduty = job and job.onduty, requireDuty = cfg().requireDuty == true, allowed = allowed == true })
    return allowed == true
  elseif kind == 'esx' then
    local job = Bridge.ClientJob()
    local allowed = Bridge.IsAllowedJob(job)
    dbg('client-access', 'ESX client access', { job = job, allowed = allowed })
    return allowed
  end
  local job = Bridge.ClientJob()
  local allowed = Bridge.IsAllowedJob(job)
  dbg('client-access', 'fallback client access', { framework = kind or 'none', job = job, allowed = allowed })
  return allowed
end
