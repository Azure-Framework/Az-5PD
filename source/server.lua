local function dbExecute(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(
            query,
            params,
            function(affected)
                if cb then
                    cb(affected)
                end
            end
        )
    elseif MySQL and MySQL.Async and MySQL.Async.execute then
        MySQL.Async.execute(
            query,
            params,
            function(result)
                if cb then
                    cb(result)
                end
            end
        )
    else
        print("^1[mdt] No MySQL library available (dbExecute)^0")
        if cb then
            cb(nil)
        end
    end
end

local function dbFetchAll(query, params, cb)
    params = params or {}
    if exports and exports.oxmysql and exports.oxmysql.execute then
        exports.oxmysql:execute(
            query,
            params,
            function(rows)
                if cb then
                    cb(rows)
                end
            end
        )
    elseif MySQL and MySQL.Async and MySQL.Async.fetchAll then
        MySQL.Async.fetchAll(
            query,
            params,
            function(rows)
                if cb then
                    cb(rows)
                end
            end
        )
    else
        print("^1[mdt] No MySQL library available (dbFetchAll)^0")
        if cb then
            cb({})
        end
    end
end

local function dbFetchScalar(query, params, cb)
    dbFetchAll(
        query,
        params,
        function(rows)
            if not rows or #rows == 0 then
                cb(nil)
            else
                local first = rows[1]
                for k, v in pairs(first) do
                    cb(v)
                    return
                end
                cb(nil)
            end
        end
    )
end

local function getDiscordIdentifierFromIds(ids)
    if not ids then
        return nil
    end
    for _, id in ipairs(ids) do
        if type(id) == "string" and id:match("^discord:") then
            return id
        end
    end
    return nil
end

local function getDiscordId(src)
    local ids = GetPlayerIdentifiers(src)
    local d = getDiscordIdentifierFromIds(ids)
    if not d then
        return nil
    end
    return d:gsub("^discord:", "")
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
    ]],
        -- improved mdt_id_records table (matches recommended schema)
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
    ]]
    }

    local function runIndex(i)
        if i > #creates then
            print("[mdt] All MDT tables checked/created.")
            return
        end
        dbExecute(
            creates[i],
            {},
            function(res)
                print(("[mdt] Created/checked table %d"):format(i))
                runIndex(i + 1)
            end
        )
    end

    runIndex(1)
end


AddEventHandler(
    "onResourceStart",
    function(resourceName)
        if GetCurrentResourceName() == resourceName then
            print("[mdt] Resource started — creating MDT tables (if needed).")
            createTables()
        end
    end
)

AddEventHandler(
    "onMySQLReady",
    function()
        print("[mdt] MySQL ready event — creating MDT tables (if needed).")
        createTables()
    end
)

local function splitName(full)
    if not full then
        return "", ""
    end
    local first, last = full:match("^(%S+)%s+(.+)$")
    return first or full, last or ""
end

local function logID(netId, identifier, fullName, evType)
    local first, last = splitName(fullName)
    dbExecute(
        [[
    INSERT INTO id_records (netId, identifier, first_name, last_name, type)
    VALUES (@netId, @identifier, @first, @last, @type)
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

RegisterNetEvent(
    "police:issueCitation",
    function(netId, reason, fine, fullName)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or ("player:" .. tostring(src))
        local displayName = GetPlayerName(src) or identifier

        dbExecute(
            [[
    INSERT INTO citations (netId, identifier, reason, fine)
    VALUES (@netId, @identifier, @reason, @fine)
  ]],
            {
                ["@netId"] = tostring(netId),
                ["@identifier"] = displayName,
                ["@reason"] = reason,
                ["@fine"] = fine
            },
            function()
            end
        )

        logID(netId, displayName, fullName, "Citation")
    end
)

RegisterNetEvent(
    "police:arrestPed",
    function(netId, fullName, dob)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or ("player:" .. tostring(src))
        local displayName = GetPlayerName(src) or identifier

        local first, last = splitName(fullName)

        dbExecute(
            [[
    INSERT INTO arrests (netId, identifier, first_name, last_name, dob)
    VALUES (@netId, @identifier, @first, @last, @dob)
  ]],
            {
                ["@netId"] = tostring(netId),
                ["@identifier"] = displayName,
                ["@first"] = first,
                ["@last"] = last,
                ["@dob"] = dob or ""
            },
            function()
            end
        )

        logID(netId, displayName, fullName, "Arrest")
    end
)

RegisterNetEvent(
    "mdt:lookupPlate",
    function(plate, fullName, make, color)
        local src = source
        if not plate then
            TriggerClientEvent(
                "mdt:plateResult",
                src,
                {
                    plate = "",
                    status = "VALID",
                    records = {},
                    make = make or "",
                    color = color or "",
                    owner = "",
                    insurance = "Unknown"
                }
            )
            return
        end

        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or "unknown"
        local displayName = GetPlayerName(src) or (fullName and fullName ~= "" and fullName) or identifier
        local first, last = splitName(fullName or "")

        dbExecute(
            [[
    INSERT INTO plate_records (plate, identifier, first_name, last_name)
    VALUES (@plate, @identifier, @first, @last)
  ]],
            {
                ["@plate"] = plate,
                ["@identifier"] = displayName,
                ["@first"] = first,
                ["@last"] = last
            },
            function()
                dbFetchAll(
                    [[ SELECT status FROM plates WHERE plate = @plate ]],
                    {["@plate"] = plate},
                    function(res)
                        local status = nil
                        if res and res[1] and res[1].status then
                            status = res[1].status
                        end
                        if not status then
                            local opts = {"VALID", "SUSPENDED", "REVOKED"}
                            status = opts[math.random(#opts)]
                            dbExecute(
                                [[ INSERT INTO plates (plate, status) VALUES (@plate, @status) ]],
                                {["@plate"] = plate, ["@status"] = status},
                                function()
                                end
                            )
                        end

                        dbFetchAll(
                            [[
        SELECT id, plate, identifier, first_name, last_name,
               DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
        FROM plate_records
        WHERE plate = @plate
      ]],
                            {["@plate"] = plate},
                            function(plateRecords)
                                dbFetchAll(
                                    [[
          SELECT id, target_type, target_value, rtype, title, description, creator_identifier,
                 DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
          FROM mdt_id_records
          WHERE target_type = 'plate' AND target_value = @plate
        ]],
                                    {["@plate"] = plate},
                                    function(mdtRecords)
                                        local merged = {}

                                        if plateRecords and #plateRecords > 0 then
                                            for _, r in ipairs(plateRecords) do
                                                table.insert(
                                                    merged,
                                                    {
                                                        id = r.id,
                                                        plate = r.plate,
                                                        identifier = r.identifier,
                                                        first_name = r.first_name,
                                                        last_name = r.last_name,
                                                        timestamp = r.timestamp,
                                                        type = "plate_record"
                                                    }
                                                )
                                            end
                                        end

                                        if mdtRecords and #mdtRecords > 0 then
                                            for _, r in ipairs(mdtRecords) do
                                                table.insert(
                                                    merged,
                                                    {
                                                        id = r.id,
                                                        plate = r.target_value,
                                                        identifier = r.creator_identifier,
                                                        first_name = r.title or "",
                                                        last_name = "",
                                                        timestamp = r.timestamp,
                                                        type = r.rtype or "mdt_record",
                                                        description = r.description or ""
                                                    }
                                                )
                                            end
                                        end

                                        table.sort(
                                            merged,
                                            function(a, b)
                                                if not a or not a.timestamp then
                                                    return false
                                                end
                                                if not b or not b.timestamp then
                                                    return true
                                                end
                                                return a.timestamp > b.timestamp
                                            end
                                        )

                                        local limited = {}
                                        for i = 1, math.min(#merged, 20) do
                                            limited[i] = merged[i]
                                        end

                                        local owner = ""
                                        if
                                            plateRecords and plateRecords[1] and
                                                (plateRecords[1].first_name or plateRecords[1].last_name)
                                         then
                                            owner =
                                                (plateRecords[1].first_name or "") ..
                                                " " .. (plateRecords[1].last_name or "")
                                        end

                                        TriggerClientEvent(
                                            "mdt:plateResult",
                                            src,
                                            {
                                                plate = plate,
                                                status = status,
                                                records = limited,
                                                make = make or "",
                                                color = color or "",
                                                owner = owner,
                                                insurance = "Unknown"
                                            }
                                        )
                                    end
                                )
                            end
                        )
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:logID",
    function(netId, data)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or "unknown"
        local displayName = GetPlayerName(src) or identifier
        logID(netId, displayName, data.name, "ID Created")
    end
)

RegisterNetEvent(
    "mdt:lookupID",
    function(payload)
        local src = source

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
            if not first then
                first, last = full, full
            end

            local combinedQuery =
                [[
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
      LIMIT 20
    ]]

            local params = {
                ["@first"] = first .. "%",
                ["@last"] = last .. "%",
                ["@full"] = full .. "%",
                ["@firstLike"] = first .. "%",
                ["@lastLike"] = "% " .. last .. "%"
            }

            dbFetchAll(
                combinedQuery,
                params,
                function(records)
                    dbFetchAll(
                        [[
        SELECT id, target_type, target_value, rtype, title, description, creator_identifier,
               DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
        FROM mdt_id_records
        WHERE target_type = 'name' AND (target_value LIKE @full OR target_value LIKE @firstLike OR target_value LIKE @lastLike)
      ]],
                        {["@full"] = full .. "%", ["@firstLike"] = first .. "%", ["@lastLike"] = "% " .. last .. "%"},
                        function(mdtRecords)
                            local merged = {}
                            if records and #records > 0 then
                                for _, r in ipairs(records) do
                                    table.insert(
                                        merged,
                                        {
                                            id = r.id,
                                            type = r.type,
                                            identifier = r.identifier,
                                            netId = r.netId,
                                            first_name = r.first_name,
                                            last_name = r.last_name,
                                            timestamp = r.timestamp,
                                            license_status = r.license_status or "UNKNOWN"
                                        }
                                    )
                                end
                            end

                            if mdtRecords and #mdtRecords > 0 then
                                for _, r in ipairs(mdtRecords) do
                                    table.insert(
                                        merged,
                                        {
                                            id = r.id,
                                            type = "mdt_record",
                                            identifier = r.creator_identifier,
                                            netId = "",
                                            first_name = r.title or "",
                                            last_name = "",
                                            timestamp = r.timestamp,
                                            license_status = "UNKNOWN",
                                            rtype = r.rtype,
                                            description = r.description
                                        }
                                    )
                                end
                            end

                            table.sort(
                                merged,
                                function(a, b)
                                    if not a or not a.timestamp then
                                        return false
                                    end
                                    if not b or not b.timestamp then
                                        return true
                                    end
                                    return a.timestamp > b.timestamp
                                end
                            )

                            local topLicense = "UNKNOWN"
                            if merged and merged[1] and merged[1].license_status then
                                topLicense = merged[1].license_status
                            end

                            TriggerClientEvent(
                                "mdt:idResult",
                                src,
                                {
                                    netId = (merged[1] and merged[1].netId) or "",
                                    name = full,
                                    licenseStatus = topLicense,
                                    records = merged
                                }
                            )
                        end
                    )
                end
            )
        elseif payload.netId and tostring(payload.netId):match("%S") then
            local netId = tostring(payload.netId)
            dbFetchAll(
                [[
      SELECT id, type, identifier, netId, first_name, last_name,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
             'VALID' AS license_status
      FROM id_records
      WHERE netId = @netId
      ORDER BY timestamp DESC
      LIMIT 200
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
        LIMIT 200
      ]],
                        {["@netId"] = netId},
                        function(mdtRecords)
                            local merged = {}
                            if records and #records > 0 then
                                for _, r in ipairs(records) do
                                    table.insert(
                                        merged,
                                        {
                                            id = r.id,
                                            type = r.type,
                                            identifier = r.identifier,
                                            netId = r.netId,
                                            first_name = r.first_name,
                                            last_name = r.last_name,
                                            timestamp = r.timestamp,
                                            license_status = r.license_status or "UNKNOWN"
                                        }
                                    )
                                end
                            end

                            if mdtRecords and #mdtRecords > 0 then
                                for _, r in ipairs(mdtRecords) do
                                    table.insert(
                                        merged,
                                        {
                                            id = r.id,
                                            type = "mdt_record",
                                            identifier = r.creator_identifier,
                                            netId = r.target_value,
                                            first_name = r.title or "",
                                            last_name = "",
                                            timestamp = r.timestamp,
                                            license_status = "UNKNOWN",
                                            rtype = r.rtype,
                                            description = r.description
                                        }
                                    )
                                end
                            end

                            table.sort(
                                merged,
                                function(a, b)
                                    if not a or not a.timestamp then
                                        return false
                                    end
                                    if not b or not b.timestamp then
                                        return true
                                    end
                                    return a.timestamp > b.timestamp
                                end
                            )

                            local name = ""
                            if merged and merged[1] and (merged[1].first_name ~= "" or merged[1].last_name ~= "") then
                                name =
                                    ((merged[1].first_name or "") .. " " .. (merged[1].last_name or "")):gsub(
                                    "^%s+",
                                    ""
                                ):gsub("%s+$", "")
                            end
                            local topLicense =
                                (merged and merged[1] and merged[1].license_status) and merged[1].license_status or
                                "UNKNOWN"

                            TriggerClientEvent(
                                "mdt:idResult",
                                src,
                                {
                                    netId = netId,
                                    name = name,
                                    licenseStatus = topLicense,
                                    records = merged
                                }
                            )
                        end
                    )
                end
            )
        else
            TriggerClientEvent(
                "mdt:idResult",
                src,
                {
                    netId = "",
                    name = "",
                    licenseStatus = "UNKNOWN",
                    records = {}
                }
            )
        end
    end
)

RegisterNetEvent(
    "mdt:updatePlateStatus",
    function(plate, newStatus)
        dbExecute(
            [[ UPDATE plates SET status = @status WHERE plate = @plate ]],
            {["@plate"] = plate, ["@status"] = newStatus},
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:addIDRecord",
    function(netId, fullName, recType)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or "unknown"
        local displayName = GetPlayerName(src) or identifier
        logID(netId, displayName, fullName, recType)
    end
)

RegisterNetEvent(
    "mdt:createRecord",
    function(data)
        local src = source
        if not data then
            return
        end
        local target_type = tostring(data.target_type or "plate")
        local target_value = tostring(data.target_value or "")
        local rtype = tostring(data.rtype or "note")
        local title = tostring(data.title or "")
        local description = tostring(data.description or "")
        local creator_identifier = tostring(data.creator_identifier or "")
        local creator_discord = tostring(data.creator_discord or "")
        local creator_source = tonumber(src)

        local insertSql =
            [[
    INSERT INTO mdt_id_records (target_type, target_value, rtype, title, description, creator_identifier, creator_discord, creator_source)
    VALUES (@target_type, @target_value, @rtype, @title, @description, @creator_identifier, @creator_discord, @creator_source)
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

        dbExecute(
            insertSql,
            params,
            function(rowsChanged)
                TriggerClientEvent("chat:addMessage", src, {args = {"^2MDT", "Record saved."}})

                dbFetchAll(
                    "SELECT * FROM mdt_id_records WHERE target_type = @tt AND target_value = @tv ORDER BY timestamp DESC LIMIT 200",
                    {
                        ["@tt"] = target_type,
                        ["@tv"] = target_value
                    },
                    function(result)
                        TriggerClientEvent("mdt:recordsResult", src, result, target_type, target_value)
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:listRecords",
    function(data)
        local src = source
        if not data or not data.target_type or not data.target_value then
            TriggerClientEvent(
                "mdt:recordsResult",
                src,
                {},
                data and data.target_type or nil,
                data and data.target_value or nil
            )
            return
        end
        local target_type = tostring(data.target_type)
        local target_value = tostring(data.target_value)

        dbFetchAll(
            "SELECT * FROM mdt_id_records WHERE target_type = @tt AND target_value = @tv ORDER BY timestamp DESC LIMIT 200",
            {
                ["@tt"] = target_type,
                ["@tv"] = target_value
            },
            function(result)
                TriggerClientEvent("mdt:recordsResult", src, result, target_type, target_value)
            end
        )
    end
)

RegisterNetEvent(
    "mdt:createReport",
    function(a, b, c)
        local src = source
        local title, description, rtype

        if type(a) == "table" then
            local payload = a
            title = tostring(payload.title or payload.Title or payload.name or "")
            description = tostring(payload.description or payload.desc or payload.descriptionText or b or "")
            rtype =
                tostring(payload.rtype or payload.type or payload.rtype or payload.rtype or payload.t or c or "General")
        else
            title = tostring(a or "")
            description = tostring(b or "")
            rtype = tostring(c or "General")
        end

        if title == "" or description == "" then
            print("[mdt] createReport called with empty title/description; ignoring.")
            return
        end

        local ids = GetPlayerIdentifiers(src)
        local identifier = ids and ids[1] or "unknown"
        local displayName = GetPlayerName(src) or identifier
        local discordId = getDiscordId(src)

        dbExecute(
            [[
    INSERT INTO reports (creator_identifier, creator_discord, title, description, rtype)
    VALUES (@identifier, @discord, @title, @description, @rtype)
  ]],
            {
                ["@identifier"] = displayName,
                ["@discord"] = discordId or "",
                ["@title"] = title,
                ["@description"] = description,
                ["@rtype"] = rtype
            },
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:listReports",
    function()
        local src = source
        dbFetchAll(
            [[
    SELECT id, creator_identifier, creator_discord, title, rtype,
           DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp, description
    FROM reports
    ORDER BY timestamp DESC
    LIMIT 50
  ]],
            {},
            function(records)
                TriggerClientEvent("mdt:reportsResult", src, records)
            end
        )
    end
)

RegisterNetEvent(
    "mdt:deleteReport",
    function(reportId)
        dbExecute(
            "DELETE FROM reports WHERE id = @id",
            {["@id"] = reportId},
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:createWarrant",
    function(subject_name, subject_netId, charges)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local issuerIdentifier = ids and ids[1] or ("player:" .. tostring(src))
        local issuerName = GetPlayerName(src) or issuerIdentifier

        dbExecute(
            [[ INSERT INTO warrants (subject_name, subject_netId, charges, issued_by, active)
                VALUES (@name, @netId, @charges, @issuer, 1) ]],
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
      LIMIT 1
    ]],
                    {},
                    function(records)
                        if records and records[1] then
                            TriggerClientEvent("mdt:warrantNotify", -1, records[1])
                        end
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:listWarrants",
    function()
        local src = source
        dbFetchAll(
            [[
    SELECT id, subject_name, subject_netId, charges, issued_by,
           active, DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
    FROM warrants
    ORDER BY timestamp DESC
    LIMIT 50
  ]],
            {},
            function(records)
                TriggerClientEvent("mdt:warrantsResult", src, records)
            end
        )
    end
)

RegisterNetEvent(
    "mdt:removeWarrant",
    function(warrantId)
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
      LIMIT 1
    ]],
                    {["@id"] = warrantId},
                    function(records)
                        if records and records[1] then
                            TriggerClientEvent("mdt:warrantNotify", -1, records[1])
                        end
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:createDispatch",
    function(caller_name, location, message)
        local src = source
        local ids = GetPlayerIdentifiers(src)
        local callerIdentifier = ids and ids[1] or ("player:" .. tostring(src))
        local displayName =
            GetPlayerName(src) or (caller_name and caller_name ~= "" and caller_name) or callerIdentifier
        local callerDiscord = getDiscordId(src)

        dbExecute(
            [[
    INSERT INTO dispatch_calls (caller_identifier, caller_name, caller_discord, location, message, status)
    VALUES (@caller, @caller_name, @caller_discord, @location, @message, 'ACTIVE')
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
      LIMIT 1
    ]],
                    {},
                    function(records)
                        if records and records[1] then
                            TriggerClientEvent("mdt:dispatchNotify", -1, records[1])
                        end
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:listDispatch",
    function()
        local src = source
        dbFetchAll(
            [[
    SELECT id, caller_name, location, message, status, assigned_to,
           DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
    FROM dispatch_calls
    ORDER BY timestamp DESC
    LIMIT 50
  ]],
            {},
            function(records)
                TriggerClientEvent("mdt:dispatchResult", src, records)
            end
        )
    end
)

RegisterNetEvent(
    "mdt:ackDispatch",
    function(callId)
        local src = source
        if not callId then
            return
        end
        local ids = GetPlayerIdentifiers(src)
        local assignedIdentifier = ids and ids[1] or tostring(src)
        local assignedName = GetPlayerName(src) or assignedIdentifier
        local assignedDiscord = getDiscordId(src)

        dbExecute(
            [[
    UPDATE dispatch_calls
    SET status = 'ACK', assigned_to = @assigned, assigned_discord = @assigned_discord
    WHERE id = @id
  ]],
            {["@assigned"] = assignedName, ["@assigned_discord"] = assignedDiscord or "", ["@id"] = callId},
            function()
                dbFetchAll(
                    [[
      SELECT id, caller_name, location, message, status, assigned_to,
             DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp
      FROM dispatch_calls WHERE id = @id
    ]],
                    {["@id"] = callId},
                    function(records)
                        if records and records[1] then
                            TriggerClientEvent("mdt:dispatchNotify", -1, records[1])
                        end
                    end
                )
            end
        )
    end
)

RegisterNetEvent(
    "mdt:editIDRecord",
    function(recordId, newType)
        dbExecute(
            [[ UPDATE id_records SET type = @type WHERE id = @id ]],
            {["@id"] = recordId, ["@type"] = newType},
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:deleteIDRecord",
    function(recordId)
        dbExecute(
            "DELETE FROM id_records WHERE id = @id",
            {["@id"] = recordId},
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:deletePlateRecord",
    function(recordId)
        dbExecute(
            "DELETE FROM plate_records WHERE id = @id",
            {["@id"] = recordId},
            function()
            end
        )
    end
)

RegisterNetEvent(
    "mdt:deleteMDTRecord",
    function(recordId)
        dbExecute(
            "DELETE FROM mdt_id_records WHERE id = @id",
            {["@id"] = recordId},
            function()
            end
        )
    end
)
