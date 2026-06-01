Az5PD = Az5PD or {}
Az5PD.Framework = Az5PD.Framework or {}

local Bridge = Az5PD.Framework

local function cfg()
  Config = Config or {}
  Config.Framework = Config.Framework or {}
  Config.Framework.mode = Config.Framework.mode or 'auto'
  Config.Framework.resources = Config.Framework.resources or {}
  Config.Framework.resources.az = Config.Framework.resources.az or 'Az-Framework'
  Config.Framework.resources.qb = Config.Framework.resources.qb or 'qb-core'
  Config.Framework.resources.esx = Config.Framework.resources.esx or 'es_extended'
  Config.Framework.resources.gimic = Config.Framework.resources.gimic or 'gimicCore'
  if Config.Framework.requireDuty == nil then Config.Framework.requireDuty = false end
  if Config.Framework.prefer == nil then Config.Framework.prefer = { 'gimic', 'qb', 'esx', 'az', 'standalone' } end
  return Config.Framework
end

local function resourceName(kind)
  local c = cfg()
  return c.resources and c.resources[kind] or nil
end

local function resourceStarted(name)
  return name and name ~= '' and type(GetResourceState) == 'function' and GetResourceState(name) == 'started'
end

local function modeEnabled(kind)
  local c = cfg()
  local mode = tostring(c.mode or 'auto'):lower()
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
  if Config and Config.Jobs and Config.Jobs.requireJob == false then return true end
  return listContains(Bridge.GetAllowedJobs(), job)
end

function Bridge.IsSupervisorJob(job)
  return listContains(Bridge.GetSupervisorJobs(), job)
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
  if src <= 0 or type(IsPlayerAceAllowed) ~= 'function' then return false end
  for _, perm in ipairs(Bridge.AceEntries(key)) do
    if tostring(perm or '') ~= '' and IsPlayerAceAllowed(src, tostring(perm)) then return true end
  end
  return false
end

function Bridge.StandaloneEnabled()
  return Config and Config.Standalone == true
end

function Bridge.HasStandaloneAccess(src)
  if not Bridge.StandaloneEnabled() then return false end
  return Bridge.HasAce(src, 'open') or Bridge.HasAce(src, 'supervisor') or Bridge.HasAce(src, 'dispatch') or Bridge.HasAce(src, 'admin')
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
  if not QBCore or not QBCore.Functions or type(QBCore.Functions.GetPlayer) ~= 'function' then return nil, false end
  local player = QBCore.Functions.GetPlayer(tonumber(src))
  local job = player and player.PlayerData and player.PlayerData.job
  if not job then return nil, false end
  local name = extractName(job)
  local isLeo = job.type == 'leo' or Bridge.IsAllowedJob(name)
  local requireDuty = cfg().requireDuty == true
  if requireDuty and job.onduty == false then isLeo = false end
  return name, isLeo
end

local function jobFromEsx(src)
  local ESX = esxObject()
  if not ESX or type(ESX.GetPlayerFromId) ~= 'function' then return nil, false end
  local player = ESX.GetPlayerFromId(tonumber(src))
  local job = player and player.job
  local name = extractName(job)
  return name, Bridge.IsAllowedJob(name)
end

local function jobFromAz(src)
  local name = resourceName('az')
  if not resourceStarted(name) then return nil, false end
  local ok, job = pcall(function() return exports[name]:getPlayerJob(src) end)
  job = ok and extractName(job) or nil
  return job, Bridge.IsAllowedJob(job)
end

local function jobFromGimic(src)
  local name = resourceName('gimic')
  if not resourceStarted(name) then return nil, false end
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
  return job or 'leo', onDutyOk and onDuty == true
end

function Bridge.ActiveKind()
  local c = cfg()
  local preferred = c.prefer
  if type(preferred) ~= 'table' then preferred = { 'gimic', 'qb', 'esx', 'az', 'standalone' } end
  for i = 1, #preferred do
    local kind = tostring(preferred[i] or ''):lower()
    if modeEnabled(kind) then
      if kind == 'standalone' and Bridge.StandaloneEnabled() then return kind end
      if kind ~= 'standalone' and resourceStarted(resourceName(kind)) then return kind end
    end
  end
  if Bridge.StandaloneEnabled() then return 'standalone' end
  return nil
end

function Bridge.GetPlayerJob(src)
  src = tonumber(src) or 0
  if src <= 0 then return nil end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then local job = jobFromGimic(src); return job end
  if kind == 'qb' then local job = jobFromQb(src); return job end
  if kind == 'esx' then local job = jobFromEsx(src); return job end
  if kind == 'az' then local job = jobFromAz(src); return job end
  return Bridge.StandaloneJob(src)
end

function Bridge.HasAccess(src)
  src = tonumber(src) or 0
  if src <= 0 then return false end
  if Bridge.HasStandaloneAccess(src) then return true end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then local _, allowed = jobFromGimic(src); return allowed == true end
  if kind == 'qb' then local _, allowed = jobFromQb(src); return allowed == true end
  if kind == 'esx' then local _, allowed = jobFromEsx(src); return allowed == true end
  if kind == 'az' then local _, allowed = jobFromAz(src); return allowed == true end
  return false
end

function Bridge.IsSupervisor(src)
  if Bridge.HasAce(src, 'admin') or Bridge.HasAce(src, 'supervisor') then return true end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local name = resourceName('gimic')
    local ok, perms = callExport(name, 'GetDiscordPermissions', src)
    if ok and type(perms) == 'table' and (perms.IsOwner == true or perms.IsManagement == true or perms.IsStaff == true) then return true end
    local ownerOk, owner = callExport(name, 'IsGroup', src, 'owner', 'management')
    if ownerOk and owner == true then return true end
  end
  return Bridge.IsSupervisorJob(Bridge.GetPlayerJob(src))
end

function Bridge.AddMoney(src, amount)
  src = tonumber(src) or 0
  amount = tonumber(amount) or 0
  if src <= 0 or amount <= 0 then return false end
  local kind = Bridge.ActiveKind()
  if kind == 'qb' then
    local QBCore = qbObject()
    local player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer and QBCore.Functions.GetPlayer(src)
    if player and player.Functions and type(player.Functions.AddMoney) == 'function' then
      return player.Functions.AddMoney('cash', amount, 'az-5pd-citation') == true
    end
  elseif kind == 'esx' then
    local ESX = esxObject()
    local player = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if player and type(player.addMoney) == 'function' then player.addMoney(amount); return true end
  elseif kind == 'az' then
    local name = resourceName('az')
    local ok, result = pcall(function() return exports[name]:addMoney(src, amount) end)
    return ok and result ~= false
  end
  return false
end

function Bridge.ClientJob()
  local state = localState()
  if state then
    local job = extractName(state.department) or extractName(state.job) or extractName(state.PlayerData and state.PlayerData.job)
    if job then return job end
  end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local sid = serverId()
    local name = resourceName('gimic')
    local ok, dept = callExport(name, 'GetPlayerDepartment', sid)
    if ok and type(dept) == 'table' then
      local first = dept[1] or dept
      return extractName(first and (first.shortName or first.longName or first.name or first.type or first.category) or dept)
    end
  elseif kind == 'qb' then
    local QBCore = qbObject()
    local data = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData and QBCore.Functions.GetPlayerData()
    return extractName(data and data.job)
  elseif kind == 'esx' then
    local ESX = esxObject()
    local data = ESX and ESX.GetPlayerData and ESX.GetPlayerData()
    return extractName(data and data.job)
  end
  return nil
end

function Bridge.ClientHasAccess()
  local state = localState()
  if state and state.az5pd_hasAccess ~= nil then return state.az5pd_hasAccess == true end
  local kind = Bridge.ActiveKind()
  if kind == 'gimic' then
    local ok, onDuty = callExport(resourceName('gimic'), 'IsOnLEODuty', serverId())
    if ok then return onDuty == true end
  elseif kind == 'qb' then
    local QBCore = qbObject()
    local data = QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData and QBCore.Functions.GetPlayerData()
    local job = data and data.job
    local name = extractName(job)
    local allowed = (job and job.type == 'leo') or Bridge.IsAllowedJob(name)
    if cfg().requireDuty == true and job and job.onduty == false then allowed = false end
    return allowed == true
  elseif kind == 'esx' then
    return Bridge.IsAllowedJob(Bridge.ClientJob())
  end
  return Bridge.IsAllowedJob(Bridge.ClientJob())
end
