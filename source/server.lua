-- server.lua (MDT)
-- + Citation reward payout (random $250-$1250) when issuing a citation to an AI

local fw = exports['Az-Framework']
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


local getPlayerNameSafe
local safeTriggerClientEvent
local getPlayerIdentifiersSafe
local getPlayerIdentitySafe
local isOfficerActionBlocked

local function getPlayerJobSafe(src)
    local ok, job = pcall(function()
        return exports['Az-Framework']:getPlayerJob(src)
    end)
    if ok then return job end
    return nil
end

local function isJobAllowed(job)
    if not job then return false end
    if type(Config.AllowedJobs) ~= 'table' then return false end
    for _, allowed in ipairs(Config.AllowedJobs) do
        if job == allowed then return true end
    end
    return false
end

local function ensureAuthorized(src, eventName)
    src = tonumber(src)
    if not src or src <= 0 then
        print(("^1[mdt] blocked invalid/non-player event %s from src=%s^0"):format(tostring(eventName), tostring(src)))
        return false
    end

    local ids, identifier = getPlayerIdentitySafe(src)
    if isOfficerActionBlocked(src, ids, identifier) then
        print(("^1[mdt] blocked accountability-restricted event %s from src=%s^0"):format(tostring(eventName), tostring(src)))
        return false
    end

    local job = getPlayerJobSafe(src)
    if isJobAllowed(job) then return true end
    print(("^1[mdt] blocked unauthorized event %s from src=%s job=%s^0"):format(tostring(eventName), tostring(src), tostring(job)))
    return false
end


-- =========================================================
-- CITATION REWARD CONFIG
-- =========================================================
Config.CitationReward = Config.CitationReward or {
    enabled = true,
    min = 250,
    max = 1250
}

-- Seed RNG once (helps avoid predictable payouts)
CreateThread(function()
    local seed = tonumber(tostring(os.time()):reverse():sub(1, 6)) or os.time()
    math.randomseed(seed)
    math.random(); math.random(); math.random()
end)

local function payCitationReward(src)
    local cfg = Config.CitationReward
    if not cfg or cfg.enabled == false then return end
    if not src or src <= 0 then return end

    local min = tonumber(cfg.min) or 250
    local max = tonumber(cfg.max) or 1250
    if max < min then min, max = max, min end

    local amount = math.random(min, max)

    if not fw or type(fw.addMoney) ~= "function" then
        print("^1[mdt] Az-Framework export missing: cannot pay citation reward.^0")
        return
    end

    local ok = fw:addMoney(src, amount)
    if ok then
        safeTriggerClientEvent("chat:addMessage", src, { args = { "^2MDT", ("Citation bonus: $%d"):format(amount) } })
    else
        print(("[mdt] Failed to pay citation reward (src=%s, amount=%s)"):format(src, amount))
    end
end

local function dbExecute(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(query, params, function(affected)
            if cb then cb(affected) end
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.execute then
        MySQL.Async.execute(query, params, function(result)
            if cb then cb(result) end
        end)
    else
        print("^1[mdt] No MySQL library available (dbExecute)^0")
        if cb then cb(nil) end
    end
end

local function dbFetchAll(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(query, params, function(rows)
            if cb then cb(rows) end
        end)
    elseif MySQL and MySQL.Async and MySQL.Async.fetchAll then
        MySQL.Async.fetchAll(query, params, function(rows)
            if cb then cb(rows) end
        end)
    else
        print("^1[mdt] No MySQL library available (dbFetchAll)^0")
        if cb then cb({}) end
    end
end

local function dbFetchScalar(query, params, cb)
    dbFetchAll(query, params, function(rows)
        if not rows or #rows == 0 then
            cb(nil)
        else
            local first = rows[1]
            for k,v in pairs(first) do
                cb(v)
                return
            end
            cb(nil)
        end
    end)
end

local function dbFetchAllAwait(query, params)
    local p = promise.new()
    dbFetchAll(query, params or {}, function(rows)
        p:resolve(rows or {})
    end)
    return Citizen.Await(p)
end

local function dbExecuteAwait(query, params)
    local p = promise.new()
    dbExecute(query, params or {}, function(res)
        p:resolve(res)
    end)
    return Citizen.Await(p)
end

local criticalTablesRepairAttempted = false

local function tableHasColumn(tableName, columnName)
    local rows = dbFetchAllAwait(("SHOW COLUMNS FROM `%s` LIKE @columnName"):format(tostring(tableName)), {
        ['@columnName'] = tostring(columnName)
    })
    return rows and rows[1] ~= nil
end

local function tableHasIndex(tableName, indexName)
    local rows = dbFetchAllAwait(("SHOW INDEX FROM `%s` WHERE Key_name = @indexName"):format(tostring(tableName)), {
        ['@indexName'] = tostring(indexName)
    })
    return rows and rows[1] ~= nil
end

local function addMissingIndex(tableName, indexName, indexSql)
    if tableHasIndex(tableName, indexName) then return false end
    print(("[mdt] repairing table %s: adding missing index %s"):format(tostring(tableName), tostring(indexName)))
    dbExecuteAwait(("ALTER TABLE `%s` ADD %s"):format(tostring(tableName), tostring(indexSql)), {})
    return true
end

local function addMissingColumn(tableName, columnName, columnSql, copyFromColumns)
    if tableHasColumn(tableName, columnName) then return false end
    print(("[mdt] repairing table %s: adding missing column %s"):format(tostring(tableName), tostring(columnName)))
    dbExecuteAwait(("ALTER TABLE `%s` ADD COLUMN %s"):format(tostring(tableName), tostring(columnSql)), {})
    for _, fromColumn in ipairs(copyFromColumns or {}) do
        if tableHasColumn(tableName, fromColumn) then
            dbExecuteAwait(([[
UPDATE `%s`
SET `%s` = `%s`
WHERE COALESCE(`%s`, '') = '' AND COALESCE(`%s`, '') <> ''
]]):format(tostring(tableName), tostring(columnName), tostring(fromColumn), tostring(columnName), tostring(fromColumn)), {})
            break
        end
    end
    return true
end

local function repairCriticalTables()
    if criticalTablesRepairAttempted then return end
    criticalTablesRepairAttempted = true

    dbExecuteAwait([[CREATE TABLE IF NOT EXISTS leo_accountability (
  officer_identifier VARCHAR(128) PRIMARY KEY,
  strikes INT NOT NULL DEFAULT 0,
  cooldown_until BIGINT NOT NULL DEFAULT 0,
  removed TINYINT(1) NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;]], {})

    addMissingColumn('leo_accountability', 'officer_identifier', 'officer_identifier VARCHAR(128) NULL FIRST', {
        'identifier', 'officer_id', 'officer', 'license', 'license_identifier', 'discordid'
    })
    addMissingColumn('leo_accountability', 'strikes', 'strikes INT NOT NULL DEFAULT 0', {})
    addMissingColumn('leo_accountability', 'cooldown_until', 'cooldown_until BIGINT NOT NULL DEFAULT 0', {
        'cooldown', 'cooldown_ms', 'cooldown_expires', 'cooldown_expire_at'
    })
    addMissingColumn('leo_accountability', 'removed', 'removed TINYINT(1) NOT NULL DEFAULT 0', {
        'is_removed', 'blocked'
    })
    addMissingColumn('leo_accountability', 'updated_at', 'updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP', {})
    addMissingIndex('leo_accountability', 'idx_officer_identifier', 'INDEX idx_officer_identifier (`officer_identifier`)')

    dbExecuteAwait([[CREATE TABLE IF NOT EXISTS leo_accountability_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  officer_identifier VARCHAR(128) NOT NULL,
  officer_name VARCHAR(128) NOT NULL,
  officer_source INT NOT NULL DEFAULT 0,
  action_type VARCHAR(32) NOT NULL,
  strike_count INT NOT NULL DEFAULT 0,
  reason VARCHAR(64) NOT NULL,
  arrest_netId VARCHAR(64) NOT NULL,
  target_name VARCHAR(128) NOT NULL,
  details_json LONGTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_officer_identifier (officer_identifier),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;]], {})

    addMissingColumn('leo_accountability_logs', 'officer_identifier', 'officer_identifier VARCHAR(128) NOT NULL AFTER id', {
        'identifier', 'officer_id', 'officer', 'license', 'license_identifier'
    })
    addMissingColumn('leo_accountability_logs', 'officer_name', "officer_name VARCHAR(128) NOT NULL DEFAULT 'Unknown'", {
        'name', 'officer'
    })
    addMissingColumn('leo_accountability_logs', 'officer_source', 'officer_source INT NOT NULL DEFAULT 0', {})
    addMissingColumn('leo_accountability_logs', 'action_type', "action_type VARCHAR(32) NOT NULL DEFAULT 'strike'", {
        'action'
    })
    addMissingColumn('leo_accountability_logs', 'strike_count', 'strike_count INT NOT NULL DEFAULT 0', {
        'strikes'
    })
    addMissingColumn('leo_accountability_logs', 'reason', "reason VARCHAR(64) NOT NULL DEFAULT 'unknown'", {})
    addMissingColumn('leo_accountability_logs', 'arrest_netId', "arrest_netId VARCHAR(64) NOT NULL DEFAULT ''", {
        'netId', 'target_netid'
    })
    addMissingColumn('leo_accountability_logs', 'target_name', "target_name VARCHAR(128) NOT NULL DEFAULT 'Unknown'", {
        'name', 'target'
    })
    addMissingColumn('leo_accountability_logs', 'details_json', 'details_json LONGTEXT NULL', {
        'details', 'meta', 'context_json'
    })
    addMissingColumn('leo_accountability_logs', 'created_at', 'created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP', {
        'timestamp', 'created'
    })
end

local function getDiscordIdentifierFromIds(ids)
    if not ids then return nil end
    for _, id in ipairs(ids) do
        if type(id) == "string" and id:match("^discord:") then
            return id
        end
    end
    return nil
end

getPlayerIdentifiersSafe = function(src)
    src = tonumber(src)
    if not src or src <= 0 then return {} end
    local ok, ids = pcall(GetPlayerIdentifiers, src)
    if ok and type(ids) == "table" then
        return ids
    end
    return {}
end

getPlayerNameSafe = function(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, name = pcall(GetPlayerName, src)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

safeTriggerClientEvent = function(eventName, target, ...)
    if eventName == nil or eventName == '' then
        print('^1[mdt] safeTriggerClientEvent called with empty event name^0')
        return false
    end

    if target == -1 then
        local ok, err = pcall(TriggerClientEvent, eventName, -1, ...)
        if not ok then
            print(("^1[mdt] TriggerClientEvent failed for %s -> -1: %s^0"):format(tostring(eventName), tostring(err)))
            return false
        end
        return true
    end

    target = tonumber(target)
    if not target or target <= 0 then
        print(("^1[mdt] skipped TriggerClientEvent %s for invalid target=%s^0"):format(tostring(eventName), tostring(target)))
        return false
    end

    local targetName = getPlayerNameSafe(target)
    if not targetName then
        print(("^1[mdt] skipped TriggerClientEvent %s because target=%s is no longer valid^0"):format(tostring(eventName), tostring(target)))
        return false
    end

    local ok, err = pcall(TriggerClientEvent, eventName, target, ...)
    if not ok then
        print(("^1[mdt] TriggerClientEvent failed for %s -> %s (%s): %s^0"):format(tostring(eventName), tostring(target), tostring(targetName), tostring(err)))
        return false
    end
    return true
end

getPlayerIdentitySafe = function(src, fallbackName)
    local ids = getPlayerIdentifiersSafe(src)
    local identifier = ids[1] or ("player:" .. tostring(src or "system"))
    local displayName = getPlayerNameSafe(src) or fallbackName or identifier
    return ids, identifier, displayName
end

local function getDiscordId(src)
    local ids = getPlayerIdentifiersSafe(src)
    local d = getDiscordIdentifierFromIds(ids)
    if not d then return nil end
    return d:gsub("^discord:", "")
end

local function _stableStatusRoll(seed)
    seed = tostring(seed or '')
    if seed == '' then seed = ('fallback:%d'):format(os.time() or GetGameTimer() or 0) end
    local total = 0
    for i = 1, #seed do
        total = (total + (string.byte(seed, i) or 0) * i) % 2147483647
    end
    if total <= 0 then total = 1 end
    return (total % 100) + 1
end

local function _normalizeMdtStatus(raw, seed)
    local s = tostring(raw or ''):upper():gsub('%s+', '')

    if s == 'VALID' or s == 'ACTIVE' or s == 'CLEAR' or s == 'CLEARED' then
        return 'VALID'
    end

    if s == 'SUSPENDED' or s == 'SUSPEND' or s == 'SUSP' or s == 'BLOCKED' then
        return 'SUSPENDED'
    end

    if s == 'EXPIRED' or s == 'EXPIRE' or s == 'EXP' or s == 'LAPSED' then
        return 'EXPIRE'
    end

    if s == 'NONE'
        or s == 'N/A'
        or s == 'NA'
        or s == 'UNKNOWN'
        or s == 'UNLICENSED'
        or s == 'NOLICENSE'
        or s == 'NOINSURANCE'
        or s == 'REVOKED'
        or s == 'MISSING'
    then
        return 'NONE'
    end

    local roll = _stableStatusRoll(seed)

    -- Mostly valid, about 2/11 inactive.
    if roll <= 82 then
        return 'VALID'
    end

    return 'NONE'
end

local function normalizeLicenseStatus(raw, seed)
    return _normalizeMdtStatus(raw, 'LIC:' .. tostring(seed or ''))
end

local function normalizeInsuranceStatus(raw, seed)
    return _normalizeMdtStatus(raw, 'INS:' .. tostring(seed or ''))
end

local accountabilityCache = {}
local accountabilityNotifyCooldown = {}

local function getAccountabilityKey(src, ids, fallbackIdentifier)
    ids = ids or getPlayerIdentifiersSafe(src)
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:match('^license:') then return id end
    end
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:match('^discord:') then return id end
    end
    return fallbackIdentifier or ids[1] or ('player:' .. tostring(src or 'unknown'))
end

local function getAccountabilityNowMs()
    return (os.time() or 0) * 1000
end

local function getOfficerAccountabilityRecord(key)
    repairCriticalTables()
    key = tostring(key or '')
    if key == '' then
        return { officer_identifier = key, strikes = 0, cooldown_until = 0, removed = 0 }
    end
    if accountabilityCache[key] then
        return accountabilityCache[key]
    end

    local rows = dbFetchAllAwait([[SELECT officer_identifier, strikes, cooldown_until, removed
FROM leo_accountability
WHERE officer_identifier = @officer_identifier
LIMIT 1]], {
        ['@officer_identifier'] = key
    })

    local rec = rows[1] or {
        officer_identifier = key,
        strikes = 0,
        cooldown_until = 0,
        removed = 0
    }
    rec.officer_identifier = tostring(rec.officer_identifier or key)
    rec.strikes = tonumber(rec.strikes) or 0
    rec.cooldown_until = tonumber(rec.cooldown_until) or 0
    rec.removed = tonumber(rec.removed) or 0
    accountabilityCache[key] = rec
    return rec
end

local function saveOfficerAccountabilityRecord(rec)
    if not rec or not rec.officer_identifier then return end
    rec.strikes = tonumber(rec.strikes) or 0
    rec.cooldown_until = tonumber(rec.cooldown_until) or 0
    rec.removed = tonumber(rec.removed) or 0

    local params = {
        ['@officer_identifier'] = tostring(rec.officer_identifier),
        ['@strikes'] = rec.strikes,
        ['@cooldown_until'] = rec.cooldown_until,
        ['@removed'] = rec.removed
    }

    local updated = dbExecuteAwait([[UPDATE leo_accountability
SET strikes = @strikes,
    cooldown_until = @cooldown_until,
    removed = @removed,
    updated_at = CURRENT_TIMESTAMP
WHERE officer_identifier = @officer_identifier]], params)

    local affected = tonumber(updated) or 0
    if affected <= 0 then
        dbExecuteAwait([[INSERT INTO leo_accountability (officer_identifier, strikes, cooldown_until, removed)
VALUES (@officer_identifier, @strikes, @cooldown_until, @removed)]], params)
    end

    accountabilityCache[tostring(rec.officer_identifier)] = rec
end

local function addOfficerAccountabilityLog(src, accountabilityKey, displayName, actionType, strikeCount, reason, arrestNetId, targetName, details)
    dbExecute([[INSERT INTO leo_accountability_logs (
  officer_identifier, officer_name, officer_source, action_type, strike_count, reason, arrest_netId, target_name, details_json
) VALUES (
  @officer_identifier, @officer_name, @officer_source, @action_type, @strike_count, @reason, @arrest_netId, @target_name, @details_json
)]], {
        ['@officer_identifier'] = tostring(accountabilityKey or ''),
        ['@officer_name'] = tostring(displayName or ''),
        ['@officer_source'] = tonumber(src) or 0,
        ['@action_type'] = tostring(actionType or 'strike'),
        ['@strike_count'] = tonumber(strikeCount) or 0,
        ['@reason'] = tostring(reason or ''),
        ['@arrest_netId'] = tostring(arrestNetId or ''),
        ['@target_name'] = tostring(targetName or ''),
        ['@details_json'] = tostring(details or '{}')
    }, function() end)
end

local function notifyOfficerAccountability(src, level, title, description, icon, iconColor)
    if not src or src <= 0 then return end
    if Config.ArrestAccountability and Config.ArrestAccountability.notifyOfficer == false then return end

    local now = getAccountabilityNowMs()
    local last = accountabilityNotifyCooldown[src] or 0
    if (now - last) < 1250 and level == 'warning' then return end
    accountabilityNotifyCooldown[src] = now

    safeTriggerClientEvent('police:accountabilityNotice', src, {
        level = level or 'inform',
        title = title or 'Officer Accountability',
        description = description or '',
        icon = icon or 'scale-balanced',
        iconColor = iconColor or '#DD6B20'
    })
end

local function getActiveWarrantForTarget(netId, fullName)
    local rows = dbFetchAllAwait([[SELECT id, subject_name, subject_netId, charges
FROM warrants
WHERE active = 1
  AND ((@netId <> '' AND subject_netId = @netId) OR (@fullName <> '' AND subject_name = @fullName))
ORDER BY id DESC
LIMIT 1]], {
        ['@netId'] = tostring(netId or ''),
        ['@fullName'] = tostring(fullName or '')
    })
    return rows[1]
end

local function evaluateArrestGrounds(netId, fullName, arrestContext)
    arrestContext = type(arrestContext) == 'table' and arrestContext or {}
    local groundsCfg = (Config.ArrestAccountability and Config.ArrestAccountability.grounds) or {}
    local matched = {}

    local warrant = nil
    if groundsCfg.activeWarrant ~= false then
        warrant = getActiveWarrantForTarget(netId, fullName)
        if warrant then matched[#matched + 1] = 'active_warrant' end
    end

    if groundsCfg.wantedFlag ~= false and arrestContext.wanted == true then
        matched[#matched + 1] = 'wanted_flag'
    end

    local normalizedLicense = normalizeLicenseStatus(arrestContext.licenseStatus, tostring(netId) .. ':' .. tostring(fullName or ''))
    if groundsCfg.suspendedLicense ~= false and (arrestContext.suspended == true or normalizedLicense == 'SUSPENDED') then
        matched[#matched + 1] = 'suspended_license'
    end
    if groundsCfg.expiredLicense ~= false and normalizedLicense == 'EXPIRE' then
        matched[#matched + 1] = 'expired_license'
    end
    if groundsCfg.noValidLicense ~= false and normalizedLicense == 'NONE' then
        matched[#matched + 1] = 'no_valid_license'
    end
    if groundsCfg.illegalItems ~= false and arrestContext.illegalItems == true then
        matched[#matched + 1] = 'illegal_items'
    end
    if groundsCfg.alcoholImpairment ~= false and arrestContext.drunk == true then
        matched[#matched + 1] = 'alcohol_impairment'
    end
    if groundsCfg.drugImpairment ~= false and arrestContext.high == true then
        matched[#matched + 1] = 'drug_impairment'
    end

    return (#matched > 0), matched, normalizedLicense, warrant
end

local function applyInvalidArrestStrike(src, arrestNetId, targetName, details)
    if not (Config.ArrestAccountability and Config.ArrestAccountability.enabled ~= false) then return end

    local ids, identifier, displayName = getPlayerIdentitySafe(src)
    local accountabilityKey = getAccountabilityKey(src, ids, identifier)
    local rec = getOfficerAccountabilityRecord(accountabilityKey)

    rec.strikes = (tonumber(rec.strikes) or 0) + 1
    local maxStrikes = tonumber(Config.ArrestAccountability.maxStrikes) or 3
    local action = 'strike'
    local message = (Config.ArrestAccountability.messages and Config.ArrestAccountability.messages.invalidArrest) or 'Invalid arrest: strike added.'

    if rec.strikes >= maxStrikes then
        if tostring((Config.ArrestAccountability.action or 'cooldown')) == 'remove' then
            rec.removed = 1
            action = 'remove'
            message = (Config.ArrestAccountability.messages and Config.ArrestAccountability.messages.removed) or 'You have been removed from police actions due to repeated invalid arrests.'
        else
            local cooldownMs = (tonumber(Config.ArrestAccountability.cooldownMinutes) or 30) * 60 * 1000
            rec.cooldown_until = getAccountabilityNowMs() + cooldownMs
            action = 'cooldown'
            message = (Config.ArrestAccountability.messages and Config.ArrestAccountability.messages.cooldown) or 'You have been placed on cooldown from police actions due to repeated invalid arrests.'
        end
    end

    saveOfficerAccountabilityRecord(rec)
    addOfficerAccountabilityLog(src, accountabilityKey, displayName, action, rec.strikes, 'invalid_arrest', arrestNetId, targetName, details)

    local description = ('%s\nStrikes: %d/%d'):format(message, tonumber(rec.strikes) or 0, maxStrikes)
    if action == 'cooldown' then
        local remainingMinutes = math.ceil(math.max(0, (tonumber(rec.cooldown_until) or 0) - getAccountabilityNowMs()) / 60000)
        description = ('%s\nCooldown: %d minute(s) remaining.'):format(description, remainingMinutes)
        notifyOfficerAccountability(src, 'warning', 'Officer Accountability', description, 'hourglass-half', '#DD6B20')
    elseif action == 'remove' then
        notifyOfficerAccountability(src, 'error', 'Officer Accountability', description, 'ban', '#E53E3E')
        if Config.ArrestAccountability.dropOnRemove ~= false then
            DropPlayer(src, message)
        end
    else
        notifyOfficerAccountability(src, 'warning', 'Officer Accountability', description, 'scale-balanced', '#DD6B20')
    end
end

isOfficerActionBlocked = function(src, ids, identifier)
    if not (Config.ArrestAccountability and Config.ArrestAccountability.enabled ~= false) then
        return false
    end

    local accountabilityKey = getAccountabilityKey(src, ids, identifier)
    local rec = getOfficerAccountabilityRecord(accountabilityKey)
    local now = getAccountabilityNowMs()

    if tonumber(rec.removed) == 1 and Config.ArrestAccountability.blockRemovedOfficers ~= false then
        notifyOfficerAccountability(src, 'error', 'Officer Accountability', (Config.ArrestAccountability.messages and Config.ArrestAccountability.messages.removed) or 'You have been removed from police actions due to repeated invalid arrests.', 'ban', '#E53E3E')
        return true
    end

    if tonumber(rec.cooldown_until) > now then
        local remainingMinutes = math.ceil(((tonumber(rec.cooldown_until) or 0) - now) / 60000)
        notifyOfficerAccountability(src, 'warning', 'Officer Accountability', ('Police actions are on cooldown. Remaining: %d minute(s).'):format(remainingMinutes), 'hourglass-half', '#DD6B20')
        return true
    end

    return false
end

local function createTables()
    local creates = {
        [[
CREATE TABLE IF NOT EXISTS citations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  netId VARCHAR(50),
  identifier VARCHAR(64),
  reason TEXT,
  fine INT,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS arrests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  netId VARCHAR(50),
  identifier VARCHAR(64),
  first_name VARCHAR(32),
  last_name VARCHAR(32),
  dob VARCHAR(16),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS plate_records (
  id INT AUTO_INCREMENT PRIMARY KEY,
  plate VARCHAR(16),
  identifier VARCHAR(64),
  first_name VARCHAR(32),
  last_name VARCHAR(32),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS plates (
  plate VARCHAR(16) PRIMARY KEY,
  status ENUM('VALID','SUSPENDED','REVOKED') NOT NULL DEFAULT 'VALID'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS id_records (
  id INT AUTO_INCREMENT PRIMARY KEY,
  netId VARCHAR(50),
  identifier VARCHAR(64),
  first_name VARCHAR(32),
  last_name VARCHAR(32),
  type VARCHAR(64),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  creator_identifier VARCHAR(64),
  creator_discord VARCHAR(128),
  title VARCHAR(128),
  description TEXT,
  rtype VARCHAR(32),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS warrants (
  id INT AUTO_INCREMENT PRIMARY KEY,
  subject_name VARCHAR(128),
  subject_netId VARCHAR(50),
  charges TEXT,
  issued_by VARCHAR(64),
  active TINYINT(1) DEFAULT 1,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS dispatch_calls (
  id INT AUTO_INCREMENT PRIMARY KEY,
  caller_identifier VARCHAR(64),
  caller_name VARCHAR(128),
  caller_discord VARCHAR(128),
  location VARCHAR(128),
  message TEXT,
  status ENUM('ACTIVE','ACK','CLOSED') DEFAULT 'ACTIVE',
  assigned_to VARCHAR(64),
  assigned_discord VARCHAR(128),
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS mdt_id_records (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  target_type VARCHAR(64) NOT NULL,
  target_value VARCHAR(191) NOT NULL,
  rtype VARCHAR(64) NOT NULL,
  title VARCHAR(191) DEFAULT NULL,
  description TEXT DEFAULT NULL,
  creator_identifier VARCHAR(128) DEFAULT NULL,
  creator_discord VARCHAR(128) DEFAULT NULL,
  creator_source INT DEFAULT NULL,
  timestamp BIGINT UNSIGNED NOT NULL DEFAULT 0,
  KEY idx_target (target_type, target_value),
  KEY idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS leo_accountability (
  officer_identifier VARCHAR(128) PRIMARY KEY,
  strikes INT NOT NULL DEFAULT 0,
  cooldown_until BIGINT NOT NULL DEFAULT 0,
  removed TINYINT(1) NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]],
        [[
CREATE TABLE IF NOT EXISTS leo_accountability_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  officer_identifier VARCHAR(128) NOT NULL,
  officer_name VARCHAR(128) NOT NULL,
  officer_source INT NOT NULL DEFAULT 0,
  action_type VARCHAR(32) NOT NULL,
  strike_count INT NOT NULL DEFAULT 0,
  reason VARCHAR(64) NOT NULL,
  arrest_netId VARCHAR(64) NOT NULL,
  target_name VARCHAR(128) NOT NULL,
  details_json LONGTEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_officer_identifier (officer_identifier),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
        ]]
    }

    local function runIndex(i)
        if i > #creates then
            repairCriticalTables()
            print("[mdt] All MDT tables checked/created.")
            return
        end
        dbExecute(creates[i], {}, function(res)
            print(("[mdt] Created/checked table %d"):format(i))
            runIndex(i + 1)
        end)
    end

    runIndex(1)
end

AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("[mdt] Resource started — creating MDT tables (if needed).")
        createTables()
    end
end)

AddEventHandler("onMySQLReady", function()
    print("[mdt] MySQL ready event — creating MDT tables (if needed).")
    createTables()
end)

local function splitName(full)
    if not full then return "", "" end
    local first, last = full:match("^(%S+)%s+(.+)$")
    return first or full, last or ""
end

ServerPedData = ServerPedData or {}

local function _normalizeName(s)
    if not s or s == "" then return "" end
    return string.lower(s):gsub("^%s+",""):gsub("%s+$","")
end

local function getMemIdentityByNetId(netId)
    if not netId then return nil end
    return ServerPedData[tostring(netId)]
end

local function getMemIdentityByName(fullName)
    local look = _normalizeName(fullName)
    if look == "" then return nil, nil end
    for nid, rec in pairs(ServerPedData) do
        local n = rec and rec.name
        if n and _normalizeName(n) == look then
            return rec, nid
        end
    end
    return nil, nil
end

local function logID(netId, identifier, fullName, evType)
    local first, last = splitName(fullName)
    dbExecute(
        [[
INSERT INTO id_records (netId, identifier, first_name, last_name, type)
VALUES (@netId, @identifier, @first, @last, @type);
        ]],
        {
            ["@netId"] = tostring(netId),
            ["@identifier"] = identifier,
            ["@first"] = first,
            ["@last"] = last,
            ["@type"] = evType
        },
        function()
        end
    )
end

RegisterNetEvent("mdt:logID")
AddEventHandler("mdt:logID", function(netIdStr, identity)
    local src = source
    if not ensureAuthorized(src, "mdt:logID") then return end
    if not netIdStr then return end
    netIdStr = tostring(netIdStr)

    ServerPedData[netIdStr] = identity or {}

    print(("SERVER: mdt:logID stored %s -> %s (%s)"):format(
        netIdStr,
        tostring(identity and identity.name or "<no-name>"),
        tostring(identity and identity.dob or "<no-dob>")
    ))

    local _, identifier, displayName = getPlayerIdentitySafe(src)
    identifier = tostring(identifier or ("player:" .. tostring(src or 'system')))
    displayName = tostring(displayName or identifier)

    pcall(function()
        logID(netIdStr, identifier, (identity and identity.name) or "", "ID Created")
    end)

    -- mdt:logID is a server-side seed/log event used during pull-overs.
    -- Only explicit ID lookups should send mdt:idResult back to a client.
end)

RegisterNetEvent("mdt:lookupID")
AddEventHandler("mdt:lookupID", function(payload)
    local src = source
    if not ensureAuthorized(src, "mdt:lookupID") then return end

    if type(payload) ~= "table" then
        if payload == nil then
            payload = {}
        else
            payload = {netId = tostring(payload)}
        end
    end

    if payload.name and tostring(payload.name):match("%S") then
        local full = tostring(payload.name)
        local first, last = full:match("^(%S+)%s+(.+)$")
        if not first then first, last = full, full end

        local combinedQuery = [[
SELECT id, type, identifier, netId, first_name, last_name, timestamp, license_status FROM (
    SELECT
      id,
      type,
      identifier,
      netId,
      first_name,
      last_name,
      DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
      'VALID' AS license_status,
      0 AS prio
    FROM id_records
    WHERE first_name LIKE @first AND last_name LIKE @last

    UNION ALL

    SELECT
      id,
      'character' AS type,
      discordid AS identifier,
      '' AS netId,
      SUBSTRING_INDEX(name, ' ', 1) AS first_name,
      TRIM(
        CASE
          WHEN INSTR(name, ' ') > 0 THEN SUBSTRING(name, INSTR(name, ' ') + 1)
          ELSE ''
        END
      ) AS last_name,
      NULL AS timestamp,
      license_status,
      1 AS prio
    FROM user_characters
    WHERE name LIKE @full OR name LIKE @firstLike OR name LIKE @lastLike
) AS combined
ORDER BY prio DESC, timestamp DESC
LIMIT 20;
        ]]

        local params = {
            ["@first"] = first .. "%",
            ["@last"] = last .. "%",
            ["@full"] = full .. "%",
            ["@firstLike"] = first .. "%",
            ["@lastLike"] = "% " .. last .. "%"
        }

        dbFetchAll(combinedQuery, params, function(records)
            dbFetchAll(
                [[
SELECT id, target_type, target_value, rtype, title, description, creator_identifier,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM mdt_id_records
WHERE target_type = 'name'
  AND (target_value LIKE @full OR target_value LIKE @firstLike OR target_value LIKE @lastLike);
                ]],
                {
                    ["@full"] = full .. "%",
                    ["@firstLike"] = first .. "%",
                    ["@lastLike"] = "% " .. last .. "%"
                },
                function(mdtRecords)
                    local merged = {}
                    if records and #records > 0 then
                        for _, r in ipairs(records) do
                            table.insert(merged, {
                                id = r.id,
                                type = r.type,
                                identifier = r.identifier,
                                netId = r.netId,
                                first_name = r.first_name,
                                last_name = r.last_name,
                                timestamp = r.timestamp,
                                license_status = normalizeLicenseStatus(r.license_status, tostring(r.netId or r.identifier or full or netId or src))
                            })
                        end
                    end

                    if mdtRecords and #mdtRecords > 0 then
                        for _, r in ipairs(mdtRecords) do
                            table.insert(merged, {
                                id = r.id,
                                type = "mdt_record",
                                identifier = r.creator_identifier,
                                netId = "",
                                first_name = r.title or "",
                                last_name = "",
                                timestamp = r.timestamp,
                                license_status = normalizeLicenseStatus(nil, tostring(r.target_value or full or netId or "record")),
                                rtype = r.rtype,
                                description = r.description
                            })
                        end
                    end

                    table.sort(merged, function(a,b)
                        if not a or not a.timestamp then return false end
                        if not b or not b.timestamp then return true end
                        return a.timestamp > b.timestamp
                    end)

                    local memRec, memNetId = getMemIdentityByName(full)

                    local topLicense = normalizeLicenseStatus(nil, tostring(full or netId or src))
                    if merged and merged[1] and merged[1].license_status then
                        topLicense = normalizeLicenseStatus(merged[1].license_status, tostring((merged[1] and (merged[1].netId or merged[1].identifier or merged[1].first_name or merged[1].title)) or full or netId or src))
                    end

                    safeTriggerClientEvent("mdt:idResult", src, {
                        netId = (merged[1] and merged[1].netId) or memNetId or "",
                        name = full,
                        dob = memRec and memRec.dob or "",
                        licenseStatus = normalizeLicenseStatus(topLicense, tostring(full or netId or src)),
                        records = merged
                    })
                end
            )
        end)
        return
    end

    if payload.netId and tostring(payload.netId):match("%S") then
        local netId = tostring(payload.netId)

        local memRec = getMemIdentityByNetId(netId)
        if memRec and memRec.name then
            safeTriggerClientEvent("mdt:idResult", src, {
                netId = netId,
                name = memRec.name or ((memRec.first_name or "").." "..(memRec.last_name or "")),
                dob = memRec.dob or "",
                licenseStatus = normalizeLicenseStatus(memRec and memRec.licenseStatus, tostring(netId) .. ':' .. tostring(memRec and memRec.name or '')),
                records = {}
            })
            return
        end

        dbFetchAll(
            [[
SELECT id, type, identifier, netId, first_name, last_name,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
       'VALID' AS license_status
FROM id_records
WHERE netId = @netId
ORDER BY timestamp DESC
LIMIT 200;
            ]],
            {["@netId"] = netId},
            function(records)
                dbFetchAll(
                    [[
SELECT id, target_type, target_value, rtype, title, description, creator_identifier,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM mdt_id_records
WHERE target_type = 'netid' AND target_value = @netId
ORDER BY timestamp DESC
LIMIT 200;
                    ]],
                    {["@netId"] = netId},
                    function(mdtRecords)
                        local merged = {}
                        if records and #records > 0 then
                            for _, r in ipairs(records) do
                                table.insert(merged, {
                                    id = r.id,
                                    type = r.type,
                                    identifier = r.identifier,
                                    netId = r.netId,
                                    first_name = r.first_name,
                                    last_name = r.last_name,
                                    timestamp = r.timestamp,
                                    license_status = normalizeLicenseStatus(r.license_status, tostring(r.netId or r.identifier or full or netId or src))
                                })
                            end
                        end

                        if mdtRecords and #mdtRecords > 0 then
                            for _, r in ipairs(mdtRecords) do
                                table.insert(merged, {
                                    id = r.id,
                                    type = "mdt_record",
                                    identifier = r.creator_identifier,
                                    netId = r.target_value,
                                    first_name = r.title or "",
                                    last_name = "",
                                    timestamp = r.timestamp,
                                    license_status = normalizeLicenseStatus(nil, tostring(r.target_value or full or netId or "record")),
                                    rtype = r.rtype,
                                    description = r.description
                                })
                            end
                        end

                        table.sort(merged, function(a,b)
                            if not a or not a.timestamp then return false end
                            if not b or not b.timestamp then return true end
                            return a.timestamp > b.timestamp
                        end)

                        local name = ""
                        if merged and merged[1] and ((merged[1].first_name or "") ~= "" or (merged[1].last_name or "") ~= "") then
                            name = ((merged[1].first_name or "") .. " " .. (merged[1].last_name or "")):gsub("^%s+",""):gsub("%s+$","")
                        elseif memRec and memRec.name then
                            name = memRec.name
                        end

                        local topLicense = normalizeLicenseStatus(nil, tostring(full or netId or src))
                        if merged and merged[1] and merged[1].license_status then
                            topLicense = normalizeLicenseStatus(merged[1].license_status, tostring((merged[1] and (merged[1].netId or merged[1].identifier or merged[1].first_name or merged[1].title)) or full or netId or src))
                        end

                        safeTriggerClientEvent("mdt:idResult", src, {
                            netId = netId,
                            name = name,
                            dob = memRec and memRec.dob or "",
                            licenseStatus = normalizeLicenseStatus(topLicense, tostring(full or netId or src)),
                            records = merged
                        })
                    end
                )
            end
        )
        return
    end

    safeTriggerClientEvent("mdt:idResult", src, {
        netId = "",
        name = "",
        dob = "",
        licenseStatus = normalizeLicenseStatus(nil, tostring(src or 'lookup')),
        records = {}
    })
end)

-- =========================================================
-- CITATIONS / ARRESTS
-- =========================================================

RegisterNetEvent("police:issueCitation")
AddEventHandler("police:issueCitation", function(netId, reason, fine, fullName)
    local src = source
    if not ensureAuthorized(src, "police:issueCitation") then return end
    local _, identifier, displayName = getPlayerIdentitySafe(src)

    dbExecute(
        [[
INSERT INTO citations (netId, identifier, reason, fine)
VALUES (@netId, @identifier, @reason, @fine);
        ]],
        {
            ["@netId"] = tostring(netId),
            ["@identifier"] = displayName,
            ["@reason"] = reason,
            ["@fine"] = fine
        },
        function()
            -- ✅ PAY THE PLAYER A RANDOM BONUS FOR CITING AI
            payCitationReward(src)
        end
    )

    logID(netId, displayName, fullName, "Citation")
end)

RegisterNetEvent("police:arrestPed")
AddEventHandler("police:arrestPed", function(netId, fullName, dob, arrestContext)
    local src = source
    if not ensureAuthorized(src, "police:arrestPed") then return end
    local ids, identifier, displayName = getPlayerIdentitySafe(src)

    local first, last = splitName(fullName)

    dbExecute(
        [[
INSERT INTO arrests (netId, identifier, first_name, last_name, dob)
VALUES (@netId, @identifier, @first, @last, @dob);
        ]],
        {
            ["@netId"] = tostring(netId),
            ["@identifier"] = displayName,
            ["@first"] = first,
            ["@last"] = last,
            ["@dob"] = dob or ""
        },
        function() end
    )

    if Config.ArrestAccountability and Config.ArrestAccountability.enabled ~= false then
        local validGrounds, reasons, normalizedLicense, warrant = evaluateArrestGrounds(netId, fullName, arrestContext)
        if not validGrounds then
            local details = json.encode({
                netId = tostring(netId or ''),
                fullName = tostring(fullName or ''),
                dob = tostring(dob or ''),
                normalizedLicense = tostring(normalizedLicense or ''),
                arrestContext = arrestContext,
                reasons = reasons or {},
                warrantId = warrant and warrant.id or nil
            })
            applyInvalidArrestStrike(src, netId, fullName, details)
        else
            local accountabilityKey = getAccountabilityKey(src, ids, identifier)
            local rec = getOfficerAccountabilityRecord(accountabilityKey)
            addOfficerAccountabilityLog(src, accountabilityKey, displayName, 'valid_arrest', tonumber(rec.strikes) or 0, table.concat(reasons or {}, ','), netId, fullName, json.encode({ normalizedLicense = normalizedLicense, arrestContext = arrestContext }))
        end
    end

    logID(netId, displayName, fullName, "Arrest")
end)

RegisterNetEvent("mdt:lookupPlate")
AddEventHandler("mdt:lookupPlate", function(plate, fullName, make, color, statusOverride)
    local src = source
    if not ensureAuthorized(src, "mdt:lookupPlate") then return end
    if not plate then
        safeTriggerClientEvent("mdt:plateResult", src, {
            plate = "",
            status = "VALID",
            records = {},
            make = make or "",
            color = color or "",
            owner = "",
            insurance = normalizeInsuranceStatus(nil, tostring(plate or fullName or src))
        })
        return
    end

    local _, identifier, displayName = getPlayerIdentitySafe(src, (fullName and fullName ~= "" and fullName) or nil)
    local first, last = splitName(fullName or "")

    dbExecute(
        [[
INSERT INTO plate_records (plate, identifier, first_name, last_name)
VALUES (@plate, @identifier, @first, @last);
        ]],
        {
            ["@plate"] = plate,
            ["@identifier"] = displayName,
            ["@first"] = first,
            ["@last"] = last
        },
        function()
            dbFetchAll(
                [[
SELECT status FROM plates WHERE plate = @plate;
                ]],
                {["@plate"] = plate},
                function(res)
                    local status = nil
                    if res and res[1] and res[1].status then
                        status = res[1].status
                    end
                    if not status then
                        local seededStatus = tostring(statusOverride or ""):upper()
                        if seededStatus ~= "VALID" and seededStatus ~= "EXPIRE" and seededStatus ~= "SUSPENDED" and seededStatus ~= "NONE" then
                            -- Default random seed: about 2/11 inactive, 9/11 valid.
                            seededStatus = (math.random(11) <= 2) and "NONE" or "VALID"
                        end
                        status = seededStatus
                        dbExecute(
                            [[
INSERT INTO plates (plate, status) VALUES (@plate, @status);
                            ]],
                            {["@plate"] = plate, ["@status"] = status},
                            function() end
                        )
                    end

                    dbFetchAll(
                        [[
SELECT id, plate, identifier, first_name, last_name,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM plate_records
WHERE plate = @plate;
                        ]],
                        {["@plate"] = plate},
                        function(plateRecords)
                            dbFetchAll(
                                [[
SELECT id, target_type, target_value, rtype, title, description, creator_identifier,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM mdt_id_records
WHERE target_type = 'plate' AND target_value = @plate;
                                ]],
                                {["@plate"] = plate},
                                function(mdtRecords)
                                    local merged = {}

                                    if plateRecords and #plateRecords > 0 then
                                        for _, r in ipairs(plateRecords) do
                                            table.insert(merged, {
                                                id = r.id,
                                                plate = r.plate,
                                                identifier = r.identifier,
                                                first_name = r.first_name,
                                                last_name = r.last_name,
                                                timestamp = r.timestamp,
                                                type = "plate_record"
                                            })
                                        end
                                    end

                                    if mdtRecords and #mdtRecords > 0 then
                                        for _, r in ipairs(mdtRecords) do
                                            table.insert(merged, {
                                                id = r.id,
                                                plate = r.target_value,
                                                identifier = r.creator_identifier,
                                                first_name = r.title or "",
                                                last_name = "",
                                                timestamp = r.timestamp,
                                                type = r.rtype or "mdt_record",
                                                description = r.description or ""
                                            })
                                        end
                                    end

                                    table.sort(merged, function(a,b)
                                        if not a or not a.timestamp then return false end
                                        if not b or not b.timestamp then return true end
                                        return a.timestamp > b.timestamp
                                    end)

                                    local limited = {}
                                    for i=1, math.min(#merged,20) do
                                        limited[i] = merged[i]
                                    end

                                    local owner = ""
                                    if plateRecords and plateRecords[1] and (plateRecords[1].first_name or plateRecords[1].last_name) then
                                        owner = (plateRecords[1].first_name or "").." "..(plateRecords[1].last_name or "")
                                    end

                                    safeTriggerClientEvent("mdt:plateResult", src, {
                                        plate = plate,
                                        status = normalizeInsuranceStatus(status, tostring(plate)),
                                        records = limited,
                                        make = make or "",
                                        color = color or "",
                                        owner = owner,
                                        insurance = normalizeInsuranceStatus(nil, tostring(plate or fullName or src))
                                    })
                                end
                            )
                        end
                    )
                end
            )
        end
    )
end)

RegisterNetEvent("mdt:createRecord")
AddEventHandler("mdt:createRecord", function(data)
    local src = source
    if not ensureAuthorized(src, "mdt:createRecord") then return end
    if not data then return end
    local target_type = tostring(data.target_type or "plate")
    local target_value = tostring(data.target_value or "")
    local rtype = tostring(data.rtype or "note")
    local title = tostring(data.title or "")
    local description = tostring(data.description or "")
    local _, creatorIdentifierRaw, creatorDisplayName = getPlayerIdentitySafe(src)
    local creator_identifier = tostring(creatorDisplayName or creatorIdentifierRaw or data.creator_identifier or "")
    local creator_discord = tostring(getDiscordId(src) or data.creator_discord or "")
    local creator_source = tonumber(src)

    local insertSql = [[
INSERT INTO mdt_id_records
(target_type, target_value, rtype, title, description, creator_identifier, creator_discord, creator_source)
VALUES (@target_type, @target_value, @rtype, @title, @description, @creator_identifier, @creator_discord, @creator_source);
    ]]
    local params = {
        ["@target_type"] = target_type,
        ["@target_value"] = target_value,
        ["@rtype"] = rtype,
        ["@title"] = title,
        ["@description"] = description,
        ["@creator_identifier"] = creator_identifier,
        ["@creator_discord"] = creator_discord,
        ["@creator_source"] = creator_source
    }

    dbExecute(insertSql, params, function(rowsChanged)
        safeTriggerClientEvent("chat:addMessage", src, { args = { "^2MDT", "Record saved." } })
        dbFetchAll(
            "SELECT * FROM mdt_id_records WHERE target_type = @tt AND target_value = @tv ORDER BY timestamp DESC LIMIT 200",
            {["@tt"] = target_type, ["@tv"] = target_value},
            function(result)
                safeTriggerClientEvent("mdt:recordsResult", src, result, target_type, target_value)
            end
        )
    end)
end)

RegisterNetEvent("mdt:listRecords")
AddEventHandler("mdt:listRecords", function(data)
    local src = source
    if not ensureAuthorized(src, "mdt:listRecords") then return end
    if not data or not data.target_type or not data.target_value then
        safeTriggerClientEvent("mdt:recordsResult", src, {}, data and data.target_type or nil, data and data.target_value or nil)
        return
    end
    local target_type = tostring(data.target_type)
    local target_value = tostring(data.target_value)

    dbFetchAll(
        "SELECT * FROM mdt_id_records WHERE target_type = @tt AND target_value = @tv ORDER BY timestamp DESC LIMIT 200",
        {["@tt"] = target_type, ["@tv"] = target_value},
        function(result)
            safeTriggerClientEvent("mdt:recordsResult", src, result, target_type, target_value)
        end
    )
end)

RegisterNetEvent("mdt:createReport")
AddEventHandler("mdt:createReport", function(a,b,c)
    local src = source
    if not ensureAuthorized(src, "mdt:createReport") then return end
    local title, description, rtype

    if type(a) == "table" then
        local payload = a
        title = tostring(payload.title or payload.Title or payload.name or "")
        description = tostring(payload.description or payload.desc or payload.descriptionText or b or "")
        rtype = tostring(payload.rtype or payload.type or payload.t or c or "General")
    else
        title = tostring(a or "")
        description = tostring(b or "")
        rtype = tostring(c or "General")
    end

    if title == "" or description == "" then
        print("[mdt] createReport called with empty title/description; ignoring.")
        return
    end

    local _, identifier, displayName = getPlayerIdentitySafe(src, "unknown")
    local discordId = getDiscordId(src)

    dbExecute(
        [[
INSERT INTO reports (creator_identifier, creator_discord, title, description, rtype)
VALUES (@identifier, @discord, @title, @description, @rtype);
        ]],
        {
            ["@identifier"] = displayName,
            ["@discord"] = discordId or "",
            ["@title"] = title,
            ["@description"] = description,
            ["@rtype"] = rtype
        },
        function() end
    )
end)

RegisterNetEvent("mdt:listReports")
AddEventHandler("mdt:listReports", function()
    local src = source
    if not ensureAuthorized(src, "mdt:listReports") then return end
    dbFetchAll(
        [[
SELECT id, creator_identifier, creator_discord, title, rtype,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp, description
FROM reports
ORDER BY timestamp DESC
LIMIT 50;
        ]],
        {},
        function(records)
            safeTriggerClientEvent("mdt:reportsResult", src, records)
        end
    )
end)

RegisterNetEvent("mdt:deleteReport")
AddEventHandler("mdt:deleteReport", function(reportId)
    local src = source
    if not ensureAuthorized(src, "mdt:deleteReport") then return end
    dbExecute("DELETE FROM reports WHERE id = @id", {["@id"] = reportId}, function() end)
end)

RegisterNetEvent("mdt:createWarrant")
AddEventHandler("mdt:createWarrant", function(subject_name, subject_netId, charges)
    local src = source
    if not ensureAuthorized(src, "mdt:createWarrant") then return end
    local _, issuerIdentifier, issuerName = getPlayerIdentitySafe(src)

    dbExecute(
        [[
INSERT INTO warrants (subject_name, subject_netId, charges, issued_by, active)
VALUES (@name, @netId, @charges, @issuer, 1);
        ]],
        {
            ["@name"] = subject_name,
            ["@netId"] = subject_netId,
            ["@charges"] = charges,
            ["@issuer"] = issuerName
        },
        function()
            dbFetchAll(
                [[
SELECT id, subject_name, subject_netId, charges, issued_by, active,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM warrants
ORDER BY id DESC
LIMIT 1;
                ]],
                {},
                function(records)
                    if records and records[1] then
                        safeTriggerClientEvent("mdt:warrantNotify", -1, records[1])
                    end
                end
            )
        end
    )
end)

RegisterNetEvent("mdt:listWarrants")
AddEventHandler("mdt:listWarrants", function()
    local src = source
    if not ensureAuthorized(src, "mdt:listWarrants") then return end
    dbFetchAll(
        [[
SELECT id, subject_name, subject_netId, charges, issued_by,
       active, DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM warrants
ORDER BY timestamp DESC
LIMIT 50;
        ]],
        {},
        function(records)
            safeTriggerClientEvent("mdt:warrantsResult", src, records)
        end
    )
end)

RegisterNetEvent("mdt:removeWarrant")
AddEventHandler("mdt:removeWarrant", function(warrantId)
    local src = source
    if not ensureAuthorized(src, "mdt:removeWarrant") then return end
    dbExecute(
        "UPDATE warrants SET active = 0 WHERE id = @id",
        {["@id"] = warrantId},
        function()
            dbFetchAll(
                [[
SELECT id, subject_name, subject_netId, charges, issued_by, active,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM warrants
WHERE id = @id
LIMIT 1;
                ]],
                {["@id"] = warrantId},
                function(records)
                    if records and records[1] then
                        safeTriggerClientEvent("mdt:warrantNotify", -1, records[1])
                    end
                end
            )
        end
    )
end)

RegisterNetEvent("mdt:createDispatch")
AddEventHandler("mdt:createDispatch", function(caller_name, location, message)
    local src = source
    if not ensureAuthorized(src, "mdt:createDispatch") then return end
    local _, callerIdentifier, displayName = getPlayerIdentitySafe(src, (caller_name and caller_name ~= "" and caller_name) or nil)
    local callerDiscord = getDiscordId(src)

    dbExecute(
        [[
INSERT INTO dispatch_calls (caller_identifier, caller_name, caller_discord, location, message, status)
VALUES (@caller, @caller_name, @caller_discord, @location, @message, 'ACTIVE');
        ]],
        {
            ["@caller"] = displayName,
            ["@caller_name"] = displayName,
            ["@caller_discord"] = callerDiscord or "",
            ["@location"] = location,
            ["@message"] = message
        },
        function()
            dbFetchAll(
                [[
SELECT id, caller_identifier, caller_name, caller_discord, location, message, status, assigned_to,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM dispatch_calls
ORDER BY timestamp DESC
LIMIT 1;
                ]],
                {},
                function(records)
                    if records and records[1] then
                        safeTriggerClientEvent("mdt:dispatchNotify", -1, records[1])
                    end
                end
            )
        end
    )
end)

RegisterNetEvent("mdt:listDispatch")
AddEventHandler("mdt:listDispatch", function()
    local src = source
    if not ensureAuthorized(src, "mdt:listDispatch") then return end
    dbFetchAll(
        [[
SELECT id, caller_name, location, message, status, assigned_to,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM dispatch_calls
ORDER BY timestamp DESC
LIMIT 50;
        ]],
        {},
        function(records)
            safeTriggerClientEvent("mdt:dispatchResult", src, records)
        end
    )
end)

RegisterNetEvent("mdt:ackDispatch")
AddEventHandler("mdt:ackDispatch", function(callId)
    local src = source
    if not ensureAuthorized(src, "mdt:ackDispatch") then return end
    if not callId then return end

    local _, assignedIdentifier, assignedName = getPlayerIdentitySafe(src)
    local assignedDiscord = getDiscordId(src)

    dbExecute(
        [[
UPDATE dispatch_calls
SET status = 'ACK', assigned_to = @assigned, assigned_discord = @assigned_discord
WHERE id = @id;
        ]],
        {
            ["@assigned"] = assignedName,
            ["@assigned_discord"] = assignedDiscord or "",
            ["@id"] = callId
        },
        function()
            dbFetchAll(
                [[
SELECT id, caller_name, location, message, status, assigned_to,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM dispatch_calls
WHERE id = @id;
                ]],
                {["@id"] = callId},
                function(records)
                    if records and records[1] then
                        safeTriggerClientEvent("mdt:dispatchNotify", -1, records[1])
                    end
                end
            )
        end
    )
end)

RegisterNetEvent("mdt:editIDRecord")
AddEventHandler("mdt:editIDRecord", function(recordId, newType)
    local src = source
    if not ensureAuthorized(src, "mdt:editIDRecord") then return end
    dbExecute("UPDATE id_records SET type = @type WHERE id = @id", {["@id"] = recordId, ["@type"] = newType}, function() end)
end)

RegisterNetEvent("mdt:deleteIDRecord")
AddEventHandler("mdt:deleteIDRecord", function(recordId)
    local src = source
    if not ensureAuthorized(src, "mdt:deleteIDRecord") then return end
    dbExecute("DELETE FROM id_records WHERE id = @id", {["@id"] = recordId}, function() end)
end)

RegisterNetEvent("mdt:deletePlateRecord")
AddEventHandler("mdt:deletePlateRecord", function(recordId)
    local src = source
    if not ensureAuthorized(src, "mdt:deletePlateRecord") then return end
    dbExecute("DELETE FROM plate_records WHERE id = @id", {["@id"] = recordId}, function() end)
end)

RegisterNetEvent("mdt:deleteMDTRecord")
AddEventHandler("mdt:deleteMDTRecord", function(recordId)
    local src = source
    if not ensureAuthorized(src, "mdt:deleteMDTRecord") then return end
    dbExecute("DELETE FROM mdt_id_records WHERE id = @id", {["@id"] = recordId}, function() end)
end)

RegisterNetEvent("mdt:addIDRecord")
AddEventHandler("mdt:addIDRecord", function(netId, fullName, recType)
    local src = source
    if not ensureAuthorized(src, "mdt:addIDRecord") then return end
    local _, identifier, displayName = getPlayerIdentitySafe(src, "unknown")
    logID(netId, displayName, fullName, recType)
end)



local function searchLegacyNamePayload(term)
    term = tostring(term or '')
    local trimmed = term:gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed == '' then return { term = '', citizens = {}, records = {} } end

    local first, last = trimmed:match('^(%S+)%s+(.+)$')
    first = first or trimmed
    last = last or ''
    local fullLower = _normalizeName(trimmed)

    local citizenRows = {}
    local seenCitizen = {}
    for netId, rec in pairs(ServerPedData or {}) do
        local nm = tostring((rec and rec.name) or '')
        local low = _normalizeName(nm)
        if low ~= '' and low:find(fullLower, 1, true) then
            local key = ('mem:%s'):format(tostring(netId))
            if not seenCitizen[key] then
                citizenRows[#citizenRows + 1] = {
                    id = '',
                    name = nm,
                    charid = tostring(netId),
                    discordid = '',
                    license = normalizeLicenseStatus(rec and rec.licenseStatus, tostring(netId) .. ':' .. tostring(nm)),
                    active_department = '5PD',
                    license_status = normalizeLicenseStatus(rec and rec.licenseStatus, tostring(netId) .. ':' .. tostring(nm)),
                    mugshot = '',
                    last_seen = os.date('%Y-%m-%d %H:%M:%S'),
                    flags = { flags = {}, notes = '' },
                    quick_notes = {},
                    legacy_source = 'Az-5PD'
                }
                seenCitizen[key] = true
            end
        end
    end

    local rows = dbFetchAllAwait([[SELECT id, type, identifier, netId, first_name, last_name,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
       'VALID' AS license_status
FROM id_records
WHERE first_name LIKE @first AND last_name LIKE @last
ORDER BY timestamp DESC
LIMIT 50;    ]], {['@first'] = first .. '%', ['@last'] = (last ~= '' and last .. '%') or '%'}) or {}

    for _, r in ipairs(rows) do
        local fullName = (((r.first_name or '') .. ' ' .. (r.last_name or '')):gsub('^%s+', ''):gsub('%s+$', ''))
        if fullName ~= '' then
            local key = ('db:%s'):format(fullName:lower())
            if not seenCitizen[key] then
                citizenRows[#citizenRows + 1] = {
                    id = '',
                    name = fullName,
                    charid = tostring(r.netId or ''),
                    discordid = tostring(r.identifier or ''),
                    license = normalizeLicenseStatus(r.license_status, tostring(r.netId or r.identifier or fullName)),
                    active_department = '5PD',
                    license_status = normalizeLicenseStatus(r.license_status, tostring(r.netId or r.identifier or fullName)),
                    mugshot = '',
                    last_seen = r.timestamp or '',
                    flags = { flags = {}, notes = '' },
                    quick_notes = {},
                    legacy_source = 'Az-5PD'
                }
                seenCitizen[key] = true
            end
        end
    end

    local recordRows = dbFetchAllAwait([[SELECT id, target_type, target_value, rtype, title, description,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM mdt_id_records
WHERE target_type = 'name' AND (LOWER(target_value) LIKE @full OR LOWER(target_value) LIKE @firstLike)
ORDER BY timestamp DESC
LIMIT 100;    ]], {['@full'] = '%' .. fullLower .. '%', ['@firstLike'] = '%' .. _normalizeName(first) .. '%'}) or {}

    local warrantRows = dbFetchAllAwait([[SELECT id, subject_name, charges,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
       active
FROM warrants
WHERE LOWER(subject_name) LIKE @term
ORDER BY timestamp DESC
LIMIT 50;    ]], {['@term'] = '%' .. fullLower .. '%'}) or {}

    local records = {}
    for _, r in ipairs(recordRows) do
        records[#records + 1] = {
            id = r.id,
            target_value = r.target_value,
            rtype = r.rtype or 'record',
            title = r.title or r.rtype or 'Record',
            description = r.description or '',
            timestamp = r.timestamp,
            legacy_source = 'Az-5PD'
        }
    end
    for _, r in ipairs(rows) do
        records[#records + 1] = {
            id = r.id,
            target_value = (((r.first_name or '') .. ' ' .. (r.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')),
            rtype = r.type or '5pd_record',
            title = r.type or '5PD Record',
            description = ('Identifier: %s | NetID: %s'):format(tostring(r.identifier or ''), tostring(r.netId or '')),
            timestamp = r.timestamp,
            legacy_source = 'Az-5PD'
        }
    end
    for _, w in ipairs(warrantRows) do
        records[#records + 1] = {
            id = w.id,
            target_value = w.subject_name,
            rtype = (tonumber(w.active) == 1 or w.active == true) and 'warrant_active' or 'warrant_cleared',
            title = ('Warrant - %s'):format((tonumber(w.active) == 1 or w.active == true) and 'ACTIVE' or 'CLEARED'),
            description = w.charges or '',
            timestamp = w.timestamp,
            legacy_source = 'Az-5PD'
        }
    end
    table.sort(records, function(a, b)
        return tostring(a.timestamp or '') > tostring(b.timestamp or '')
    end)
    return { term = trimmed, citizens = citizenRows, records = records }
end

local function searchLegacyPlatePayload(plate)
    plate = tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
    if plate == '' then return { term = '', vehicles = {}, records = {} } end
    local like = '%' .. plate:lower() .. '%'

    local rows = dbFetchAllAwait([[SELECT plate, identifier, first_name, last_name,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM plate_records
WHERE LOWER(plate) LIKE @plate
ORDER BY timestamp DESC
LIMIT 100;    ]], {['@plate'] = like}) or {}

    local statusRows = dbFetchAllAwait([[SELECT plate, status FROM plates WHERE LOWER(plate) LIKE @plate LIMIT 20;]], {['@plate'] = like}) or {}
    local statusByPlate = {}
    for _, row in ipairs(statusRows) do statusByPlate[tostring(row.plate or ''):upper()] = normalizeInsuranceStatus(row.status, tostring(row.plate or '')) end

    local mdtRows = dbFetchAllAwait([[SELECT id, target_type, target_value, rtype, title, description,
       DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
FROM mdt_id_records
WHERE target_type = 'plate' AND LOWER(target_value) LIKE @plate
ORDER BY timestamp DESC
LIMIT 100;    ]], {['@plate'] = like}) or {}

    local vehicles, seen = {}, {}
    local records = {}
    for _, r in ipairs(rows) do
        local plateKey = tostring(r.plate or ''):upper()
        if plateKey ~= '' and not seen[plateKey] then
            vehicles[#vehicles + 1] = {
                plate = plateKey,
                model = 'Unlisted',
                owner_name = (((r.first_name or '') .. ' ' .. (r.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')),
                discordid = tostring(r.identifier or ''),
                policy_type = normalizeInsuranceStatus(statusByPlate[plateKey], plateKey),
                active = true,
                legacy_source = 'Az-5PD'
            }
            seen[plateKey] = true
        end
        records[#records + 1] = {
            id = #records + 1,
            target_value = plateKey,
            rtype = 'plate_record',
            title = '5PD Plate Record',
            description = ('Identifier: %s | Owner: %s %s'):format(tostring(r.identifier or ''), tostring(r.first_name or ''), tostring(r.last_name or '')),
            timestamp = r.timestamp,
            legacy_source = 'Az-5PD'
        }
    end
    for _, r in ipairs(mdtRows) do
        records[#records + 1] = {
            id = r.id,
            target_value = r.target_value,
            rtype = r.rtype or 'record',
            title = r.title or r.rtype or 'Record',
            description = r.description or '',
            timestamp = r.timestamp,
            legacy_source = 'Az-5PD'
        }
    end
    table.sort(records, function(a, b)
        return tostring(a.timestamp or '') > tostring(b.timestamp or '')
    end)
    return { term = plate, vehicles = vehicles, records = records }
end

exports('SearchMDTName', function(term)
    return searchLegacyNamePayload(term)
end)

exports('SearchMDTPlate', function(plate)
    return searchLegacyPlatePayload(plate)
end)


RegisterNetEvent("mdt:updatePlateStatus")
AddEventHandler("mdt:updatePlateStatus", function(plate, newStatus)
    local src = source
    if not ensureAuthorized(src, "mdt:updatePlateStatus") then return end

    local cleanedPlate = tostring(plate or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if cleanedPlate == "" then return end

    local normalized = normalizeInsuranceStatus(newStatus, tostring(cleanedPlate))
    dbExecute(
        [[
INSERT INTO plates (plate, status) VALUES (@plate, @status)
ON DUPLICATE KEY UPDATE status = VALUES(status);
        ]],
        { ["@plate"] = cleanedPlate, ["@status"] = normalized },
        function() end
    )

    safeTriggerClientEvent("mdt:plateResult", src, {
        plate = cleanedPlate,
        status = normalized,
        records = {},
        make = "",
        color = "",
        owner = "",
        insurance = normalized
    })
end)

RegisterNetEvent("police:cuffPed")
AddEventHandler("police:cuffPed", function(netId, state)
    local src = source
    if not ensureAuthorized(src, "police:cuffPed") then return end
    netId = tostring(netId or "")
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and target ~= src then
            safeTriggerClientEvent("police:syncNpcCuff", target, netId, state == false and false or true)
        end
    end
end)

RegisterNetEvent("mdt:ping")
AddEventHandler("mdt:ping", function()
    local src = source
    if Config.Debug then print(("SERVER DEBUG: got mdt:ping from source=%s"):format(tostring(src))) end
    safeTriggerClientEvent("mdt:pingResult", src, true)
end)

print("[mdt] server.lua loaded and ready.")
