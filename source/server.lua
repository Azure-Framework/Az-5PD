-- Helper DB wrapper to support both oxmysql and mysql-async
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

-- Extract Discord identifier from a player's identifiers array
-- Returns string like "discord:123456789012345678" if present, or nil
local function getDiscordIdentifierFromIds(ids)
  if not ids then return nil end
  for _, id in ipairs(ids) do
    if type(id) == "string" and id:match("^discord:") then
      return id -- returns the full "discord:..." string
    end
  end
  return nil
end

-- Helper to return a normalized discord id without the prefix, or nil
local function getDiscordId(src)
  local ids = GetPlayerIdentifiers(src)
  local d = getDiscordIdentifierFromIds(ids)
  if not d then return nil end
  return d:gsub("^discord:", "")
end

-- NOTE:
-- The raw Discord ID (snowflake) is stored. If you want the human-friendly
-- username#discriminator you'll need to resolve via your Discord bot's API
-- (example: call your bot endpoint that maps discordId -> username#1234).
-- That is intentionally left out (requires bot credentials / HTTP) — but raw ID
-- is enough to link back to the user or to resolve later.

-- Create tables function: runs all CREATE TABLE IF NOT EXISTS
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS plate_records (
      id INT AUTO_INCREMENT PRIMARY KEY,
      plate VARCHAR(16),
      identifier VARCHAR(64),
      first_name VARCHAR(32),
      last_name VARCHAR(32),
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS plates (
      plate VARCHAR(16) PRIMARY KEY,
      status ENUM('VALID','SUSPENDED','REVOKED') NOT NULL DEFAULT 'VALID'
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]]
  }

  local function runIndex(i)
    if i > #creates then
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

-- Run on resource start (ensures creation even if onMySQLReady not fired)
AddEventHandler('onResourceStart', function(resourceName)
  if GetCurrentResourceName() == resourceName then
    print("[mdt] Resource started — creating MDT tables (if needed).")
    createTables()
  end
end)

-- Some MySQL libs emit onMySQLReady; try that too
AddEventHandler('onMySQLReady', function()
  print("[mdt] MySQL ready event — creating MDT tables (if needed).")
  createTables()
end)

-- Utility to split name into first/last
local function splitName(full)
  if not full then return "", "" end
  local first, last = full:match("^(%S+)%s+(.+)$")
  return first or full, last or ""
end

-- Log a new ID record (generic helper)
local function logID(netId, identifier, fullName, evType)
  local first, last = splitName(fullName)
  dbExecute([[
    INSERT INTO id_records (netId, identifier, first_name, last_name, type)
    VALUES (@netId, @identifier, @first, @last, @type)
  ]], {
    ['@netId']      = tostring(netId),
    ['@identifier'] = identifier,
    ['@first']      = first,
    ['@last']       = last,
    ['@type']       = evType
  }, function() end)
end

-- Citation logging
RegisterNetEvent('police:issueCitation', function(netId, reason, fine, fullName)
  local src        = source
  local ids        = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or ("player:"..tostring(src))
  local displayName = GetPlayerName(src) or identifier

  dbExecute([[
    INSERT INTO citations (netId, identifier, reason, fine)
    VALUES (@netId, @identifier, @reason, @fine)
  ]], {
    ['@netId']      = tostring(netId),
    ['@identifier'] = displayName,
    ['@reason']     = reason,
    ['@fine']       = fine
  }, function() end)

  logID(netId, displayName, fullName, 'Citation')
end)

-- Arrest logging
RegisterNetEvent('police:arrestPed', function(netId, fullName, dob)
  local src        = source
  local ids        = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or ("player:"..tostring(src))
  local displayName = GetPlayerName(src) or identifier

  local first, last = splitName(fullName)

  dbExecute([[
    INSERT INTO arrests (netId, identifier, first_name, last_name, dob)
    VALUES (@netId, @identifier, @first, @last, @dob)
  ]], {
    ['@netId']      = tostring(netId),
    ['@identifier'] = displayName,
    ['@first']      = first,
    ['@last']       = last,
    ['@dob']        = dob or ""
  }, function() end)

  logID(netId, displayName, fullName, 'Arrest')
end)

-- Plate lookup + status, capturing names and returning owner/make fields for the NUI
RegisterNetEvent('mdt:lookupPlate', function(plate, fullName, make, color)
  local src        = source
  local ids        = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or "unknown"
  local displayName = GetPlayerName(src) or (fullName and fullName ~= "" and fullName) or identifier
  local first, last = splitName(fullName or "")

  dbExecute([[
    INSERT INTO plate_records (plate, identifier, first_name, last_name)
    VALUES (@plate, @identifier, @first, @last)
  ]], {
    ['@plate']      = plate,
    ['@identifier'] = displayName,
    ['@first']      = first,
    ['@last']       = last
  }, function()
    dbFetchAll([[ SELECT status FROM plates WHERE plate = @plate ]], { ['@plate'] = plate }, function(res)
      local status = nil
      if res and res[1] and res[1].status then status = res[1].status end
      if not status then
        local opts = { "VALID","SUSPENDED","REVOKED" }
        status = opts[math.random(#opts)]
        dbExecute([[ INSERT INTO plates (plate, status) VALUES (@plate, @status) ]],
          { ['@plate']=plate, ['@status']=status }, function() end)
      end

      dbFetchAll([[
        SELECT id, plate, identifier, first_name, last_name,
               DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
        FROM plate_records
        WHERE plate = @plate
        ORDER BY timestamp DESC
        LIMIT 10
      ]], { ['@plate'] = plate }, function(records)
        local owner = ""
        if records and records[1] and (records[1].first_name or records[1].last_name) then
          owner = (records[1].first_name or "") .. " " .. (records[1].last_name or "")
        end

        TriggerClientEvent('mdt:plateResult', src, {
          plate   = plate,
          status  = status,
          records = records,
          make    = make or "",
          color   = color or "",
          owner   = owner,
          insurance = "Unknown"
        })
      end)
    end)
  end)
end)

-- ID log creation
RegisterNetEvent('mdt:logID', function(netId, data)
  local src        = source
  local ids        = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or "unknown"
  local displayName = GetPlayerName(src) or identifier
  logID(netId, displayName, data.name, 'ID Created')
end)
-- server.lua (mdt:lookupID) - normalises payload (table/string)
RegisterNetEvent('mdt:lookupID', function(payload)
  local src = source

  if type(payload) ~= 'table' then
    if payload == nil then
      payload = {}
    else
      payload = { netId = tostring(payload) }
    end
  end

  if payload.name and tostring(payload.name):match("%S") then
    local full = tostring(payload.name)
    local first, last = full:match("^(%S+)%s+(.+)$")
    if not first then first, last = full, full end

    -- Combined query: grab matching rows from id_records and user_characters,
    -- normalize columns so the client can display them consistently.
    -- Also include `license_status` for each returned row.
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
          'VALID' AS license_status
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
          'UNKNOWN' AS license_status
        FROM user_characters
        WHERE name LIKE @full OR name LIKE @firstLike OR name LIKE @lastLike
      ) AS combined
      ORDER BY timestamp DESC
      LIMIT 20
    ]]

    local params = {
      ['@first']     = first .. '%',
      ['@last']      = last  .. '%',
      ['@full']      = full  .. '%',
      ['@firstLike'] = first .. '%',
      ['@lastLike']  = '% ' .. last .. '%'
    }

    dbFetchAll(combinedQuery, params, function(records)
      local displayName = (first .. " " .. last)
      local topLicense = "UNKNOWN"
      if records and records[1] and records[1].license_status then
        topLicense = records[1].license_status
      end
      TriggerClientEvent('mdt:idResult', src, {
        netId = (records[1] and records[1].netId) or "",
        name = displayName,
        licenseStatus = topLicense,
        records = records
      })
    end)

  elseif payload.netId and tostring(payload.netId):match("%S") then
    local netId = tostring(payload.netId)
    dbFetchAll([[
      SELECT id, type, identifier, netId, first_name, last_name,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
             'VALID' AS license_status
      FROM id_records
      WHERE netId = @netId
      ORDER BY timestamp DESC
      LIMIT 20
    ]], { ['@netId'] = netId }, function(records)
      local name = ""
      if records and records[1] then
        local r = records[1]
        if (r.first_name and r.first_name ~= "") or (r.last_name and r.last_name ~= "") then
          name = ((r.first_name or "") .. " " .. (r.last_name or "")):gsub("^%s+",""):gsub("%s+$","")
        end
      end
      local topLicense = (records and records[1] and records[1].license_status) and records[1].license_status or "UNKNOWN"
      TriggerClientEvent('mdt:idResult', src, {
        netId = netId,
        name = name,
        licenseStatus = topLicense,
        records = records
      })
    end)

  else
    TriggerClientEvent('mdt:idResult', src, {
      netId = "",
      name = "",
      licenseStatus = "UNKNOWN",
      records = {}
    })
  end
end)


-- === New: Status/Record Management APIs ===
RegisterNetEvent('mdt:updatePlateStatus', function(plate, newStatus)
  dbExecute([[ UPDATE plates SET status = @status WHERE plate = @plate ]], { ['@plate']=plate, ['@status']=newStatus }, function() end)
end)

RegisterNetEvent('mdt:addIDRecord', function(netId, fullName, recType)
  local src = source
  local ids = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or "unknown"
  local displayName = GetPlayerName(src) or identifier
  logID(netId, displayName, fullName, recType)
end)

-- server.lua additions: allow dispatching AI to a player by name
RegisterNetEvent('az-police:requestAIDispatch', function(targetName, service)
  local src = source
  if not targetName or not service then
    TriggerClientEvent('chat:addMessage', src, { args = { "Dispatch", "Usage: /dispatchai <playerName> <ems|coroner|animal|tow>" } })
    return
  end

  local targetId = nil
  local targetLower = string.lower(tostring(targetName))
  for _, pid in ipairs(GetPlayers()) do
    local name = GetPlayerName(pid) or ""
    if string.find(string.lower(name), targetLower, 1, true) then
      targetId = tonumber(pid)
      break
    end
  end

  if not targetId then
    TriggerClientEvent('chat:addMessage', src, { args = { "Dispatch", "Player not found: "..tostring(targetName) } })
    return
  end

  -- Tell the target client to run the requested AI service
  TriggerClientEvent('az-police:receiveAIDispatch', targetId, tostring(service), src)

  -- Inform caller
  TriggerClientEvent('chat:addMessage', src, { args = { "Dispatch", "Dispatched '"..tostring(service).."' to "..GetPlayerName(targetId) } })
end)

-- optional convenience command for admins / dispatchers
RegisterCommand('dispatchai', function(source, args)
  local targetName = args[1]
  local service = args[2]
  if not targetName or not service then
    if source ~= 0 then
      TriggerClientEvent('chat:addMessage', source, { args = { "Dispatch", "Usage: /dispatchai <playerName> <ems|coroner|animal|tow>" } })
    end
    return
  end
  -- call the same event so logic is shared
  TriggerEvent('az-police:requestAIDispatch', targetName, service)
end, false)


RegisterNetEvent('mdt:editIDRecord', function(recordId, newType)
  dbExecute([[ UPDATE id_records SET type = @type WHERE id = @id ]], { ['@id']=recordId, ['@type']=newType }, function() end)
end)

RegisterNetEvent('mdt:deleteIDRecord', function(recordId)
  dbExecute("DELETE FROM id_records WHERE id = @id", { ['@id']=recordId }, function() end)
end)

RegisterNetEvent('mdt:deletePlateRecord', function(recordId)
  dbExecute("DELETE FROM plate_records WHERE id = @id", { ['@id'] = recordId }, function() end)
end)

-- ===========================
-- === Reports / Warrants / Dispatch Handlers ===
-- ===========================

-- Reports
-- Accepts either (title, description, rtype) OR a single table payload like { title=..., description=..., type=... }
RegisterNetEvent('mdt:createReport', function(a, b, c)
  local src = source
  local title, description, rtype

  -- normalize args: handle table payload from NUI or classic arg list
  if type(a) == "table" then
    local payload = a
    title = tostring(payload.title or payload.Title or payload.name or "")
    description = tostring(payload.description or payload.desc or payload.descriptionText or b or "")
    -- NUI sometimes uses `type` as key; server used `rtype`
    rtype = tostring(payload.rtype or payload.type or payload.rtype or payload.rtype or payload.t or c or "General")
  else
    title = tostring(a or "")
    description = tostring(b or "")
    rtype = tostring(c or "General")
  end

  if title == "" or description == "" then
    -- simple guard: don't insert empty reports
    print("[mdt] createReport called with empty title/description; ignoring.")
    return
  end

  local ids = GetPlayerIdentifiers(src)
  local identifier = ids and ids[1] or "unknown"
  local displayName = GetPlayerName(src) or identifier
  local discordId = getDiscordId(src) -- raw discord snowflake or nil

  dbExecute([[
    INSERT INTO reports (creator_identifier, creator_discord, title, description, rtype)
    VALUES (@identifier, @discord, @title, @description, @rtype)
  ]], {
    ['@identifier'] = displayName,
    ['@discord']    = discordId or "",
    ['@title']      = title,
    ['@description']= description,
    ['@rtype']      = rtype
  }, function() end)
end)

RegisterNetEvent('mdt:listReports', function()
  local src = source
  dbFetchAll([[
    SELECT id, creator_identifier, creator_discord, title, rtype,
           DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp, description
    FROM reports
    ORDER BY timestamp DESC
    LIMIT 50
  ]], {}, function(records)
    TriggerClientEvent('mdt:reportsResult', src, records)
  end)
end)

RegisterNetEvent('mdt:deleteReport', function(reportId)
  dbExecute("DELETE FROM reports WHERE id = @id", { ['@id'] = reportId }, function() end)
end)

-- Warrants
RegisterNetEvent('mdt:createWarrant', function(subject_name, subject_netId, charges)
  local src = source
  local ids = GetPlayerIdentifiers(src)
  local issuerIdentifier = ids and ids[1] or ("player:"..tostring(src))
  local issuerName = GetPlayerName(src) or issuerIdentifier

  dbExecute([[
    INSERT INTO warrants (subject_name, subject_netId, charges, issued_by, active)
    VALUES (@name, @netId, @charges, @issuer, 1)
  ]], {
    ['@name']    = subject_name,
    ['@netId']   = subject_netId,
    ['@charges'] = charges,
    ['@issuer']  = issuerName
  }, function()
    -- fetch the latest warrant we just created and broadcast to all players
    dbFetchAll([[
      SELECT id, subject_name, subject_netId, charges, issued_by, active,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
      FROM warrants
      ORDER BY id DESC
      LIMIT 1
    ]], {}, function(records)
      if records and records[1] then
        TriggerClientEvent('mdt:warrantNotify', -1, records[1])
      end
    end)
  end)
end)

RegisterNetEvent('mdt:listWarrants', function()
  local src = source
  dbFetchAll([[
    SELECT id, subject_name, subject_netId, charges, issued_by,
           active, DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
    FROM warrants
    ORDER BY timestamp DESC
    LIMIT 50
  ]], {}, function(records)
    TriggerClientEvent('mdt:warrantsResult', src, records)
  end)
end)

RegisterNetEvent('mdt:removeWarrant', function(warrantId)
  local src = source
  dbExecute("UPDATE warrants SET active = 0 WHERE id = @id", { ['@id']=warrantId }, function()
    -- fetch the warrant and broadcast that it was cleared
    dbFetchAll([[
      SELECT id, subject_name, subject_netId, charges, issued_by, active,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
      FROM warrants
      WHERE id = @id
      LIMIT 1
    ]], { ['@id'] = warrantId }, function(records)
      if records and records[1] then
        TriggerClientEvent('mdt:warrantNotify', -1, records[1])
      end
    end)
  end)
end)

-- Dispatch
RegisterNetEvent('mdt:createDispatch', function(caller_name, location, message)
  local src = source
  local ids = GetPlayerIdentifiers(src)
  local callerIdentifier = ids and ids[1] or ("player:"..tostring(src))
  local displayName = GetPlayerName(src) or (caller_name and caller_name ~= "" and caller_name) or callerIdentifier
  local callerDiscord = getDiscordId(src)

  dbExecute([[
    INSERT INTO dispatch_calls (caller_identifier, caller_name, caller_discord, location, message, status)
    VALUES (@caller, @caller_name, @caller_discord, @location, @message, 'ACTIVE')
  ]], {
    ['@caller']      = displayName,
    ['@caller_name'] = displayName,
    ['@caller_discord'] = callerDiscord or "",
    ['@location']    = location,
    ['@message']     = message
  }, function()
    dbFetchAll([[
      SELECT id, caller_identifier, caller_name, caller_discord, location, message, status, assigned_to,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
      FROM dispatch_calls
      ORDER BY timestamp DESC
      LIMIT 1
    ]], {}, function(records)
      if records and records[1] then
        TriggerClientEvent('mdt:dispatchNotify', -1, records[1])
      end
    end)
  end)
end)

RegisterNetEvent('mdt:listDispatch', function()
  local src = source
  dbFetchAll([[
    SELECT id, caller_name, location, message, status, assigned_to,
           DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
    FROM dispatch_calls
    ORDER BY timestamp DESC
    LIMIT 50
  ]], {}, function(records)
    TriggerClientEvent('mdt:dispatchResult', src, records)
  end)
end)

-- FIXED: server-side ack handler now derives the identifier from `source` (server context)
RegisterNetEvent('mdt:ackDispatch', function(callId)
  local src = source
  if not callId then return end
  local ids = GetPlayerIdentifiers(src)
  local assignedIdentifier = ids and ids[1] or tostring(src)
  local assignedName = GetPlayerName(src) or assignedIdentifier
  local assignedDiscord = getDiscordId(src)

  dbExecute([[
    UPDATE dispatch_calls
    SET status = 'ACK', assigned_to = @assigned, assigned_discord = @assigned_discord
    WHERE id = @id
  ]], { ['@assigned'] = assignedName, ['@assigned_discord'] = assignedDiscord or "", ['@id'] = callId }, function()
    dbFetchAll([[
      SELECT id, caller_name, location, message, status, assigned_to,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
      FROM dispatch_calls WHERE id = @id
    ]], { ['@id'] = callId }, function(records)
      if records and records[1] then
        TriggerClientEvent('mdt:dispatchNotify', -1, records[1])
      end
    end)
  end)
end)
