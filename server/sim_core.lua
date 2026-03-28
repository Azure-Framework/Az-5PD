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


if Config.Sim and Config.Sim.enabled == false then
  return
end

local Sim = {
  shifts = {},
  incidents = {},
  officerRecent = {},
  officerWeekly = {},
  dispatchCalls = {},
  bolos = {},
  warrants = {},
  policy = {},
  personHistory = {},
  vehicleHistory = {},
  commendations = {},
  seq = 1,
  dispatchSeq = 1,
  warrantSeq = 1,
  boloSeq = 1,
  policySeq = 1,
  bridgeDispatchSeq = 1,
  dbReady = false,
  bridge = {
    resource = nil,
    useMdtTables = false,
    lastSyncAt = 0,
  },
}

local function sdebug(...)
  print('[Az-5PD:SIM]', ...)
end

local function simEnabled()
  return not (Config.Sim and Config.Sim.enabled == false)
end

local function getBridgeConfig()
  local cfg = (Config.Sim and Config.Sim.MDTBridge) or {}
  return cfg
end

local function tableIsArray(tbl)
  if type(tbl) ~= 'table' then return false end
  local count = 0
  for k in pairs(tbl) do
    if type(k) ~= 'number' then return false end
    count = count + 1
  end
  return count > 0
end

local function findExternalMdtResource()
  local cfg = getBridgeConfig()
  if cfg.enabled == false or cfg.preferExternalTables == false then return nil end
  local names = cfg.resourceNames or (((Config or {}).MDT or {}).externalResourceNames) or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
  for i = 1, #names do
    local name = tostring(names[i] or '')
    if name ~= '' and name ~= GetCurrentResourceName() and type(GetResourceState) == 'function' then
      local ok, state = pcall(GetResourceState, name)
      if ok and state == 'started' then
        return name
      end
    end
  end
  return nil
end

local function refreshBridgeMode()
  local res = findExternalMdtResource()
  Sim.bridge.resource = res
  Sim.bridge.useMdtTables = res ~= nil
  return Sim.bridge.useMdtTables
end

local function usingMdtTables()
  return refreshBridgeMode()
end

local function trimText(value, maxLen)
  value = tostring(value or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if maxLen and #value > maxLen then value = value:sub(1, maxLen) end
  return value
end

local function shallowCopy(tbl)
  local out = {}
  if type(tbl) ~= 'table' then return out end
  for k, v in pairs(tbl) do out[k] = v end
  return out
end

local function deepCopy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end

local function safeJsonEncode(value)
  local ok, result = pcall(function() return json.encode(value or {}) end)
  return ok and result or '{}'
end

local function safeJsonDecode(value)
  if not value or value == '' then return nil end
  local ok, result = pcall(function() return json.decode(value) end)
  return ok and result or nil
end

local function ensureList(value)
  if type(value) ~= 'table' then return {} end
  if tableIsArray(value) then return value end
  local out = {}
  for _, v in pairs(value) do out[#out + 1] = v end
  return out
end

local function boolish(value)
  return value == true or value == 1 or value == '1' or value == 'true'
end

local function parseSqlDate(value)
  if not value then return os.time() end
  value = tostring(value)
  local y, mo, d, h, mi, s = value:match('^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)$')
  if not y then
    y, mo, d = value:match('^(%d+)%-(%d+)%-(%d+)$')
    h, mi, s = '0', '0', '0'
  end
  if not y then return os.time() end
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
end

local function sqlNowPlus(seconds)
  return os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(seconds) or 0))
end

local function sqlTimestampFromEpoch(ts)
  if not ts then return nil end
  return os.date('%Y-%m-%d %H:%M:%S', tonumber(ts) or os.time())
end

local function extractBracketTag(message)
  local tag = tostring(message or ''):match('%[([^%]]+)%]')
  if not tag or tag == '' then return 'followup' end
  return trimText(tag:lower(), 32)
end

local function normalizeJobValue(job)
  if type(job) == 'table' then
    return job.name or job.job or job.id or nil
  end
  if job == nil then return nil end
  return tostring(job)
end

local function getPlayerJobSafe(src)
  if type(GetResourceState) == 'function' and GetResourceState('Az-Framework') ~= 'started' then
    return nil
  end
  local ok, job = pcall(function()
    return exports['Az-Framework']:getPlayerJob(src)
  end)
  if not ok then return nil end
  return normalizeJobValue(job)
end

local function isAllowedJob(job)
  job = tostring(job or '')
  local cfg = (((Config or {}).Sim or {}).Framework or {}).allowedJobs or (Config.AllowedJobs or {})
  for i = 1, #cfg do
    if tostring(cfg[i]) == job then return true end
  end
  return false
end

local function isSupervisorJob(job)
  job = tostring(job or '')
  local cfg = (((Config or {}).Sim or {}).Framework or {}).supervisorJobs or {}
  for i = 1, #cfg do
    if tostring(cfg[i]) == job then return true end
  end
  return false
end

local function isAuthorized(src)
  if not src or src <= 0 then return false end
  local requireJob = not ((((Config or {}).Sim or {}).Framework or {}).requirePoliceJob == false)
  if not requireJob then return true end
  return isAllowedJob(getPlayerJobSafe(src)) or isSupervisorJob(getPlayerJobSafe(src))
end

local function isSupervisor(src)
  return isSupervisorJob(getPlayerJobSafe(src))
end

local function getIdentifier(src)
  local ids = GetPlayerIdentifiers(src)
  if ids then
    for i = 1, #ids do
      local value = tostring(ids[i])
      if value:find('license:', 1, true) then return value end
    end
    if ids[1] then return tostring(ids[1]) end
  end
  return ('src:%s'):format(tostring(src))
end

local function sanitizeCoords(coords)
  if type(coords) ~= 'table' then return nil end
  local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
  if not x or not y then return nil end
  return { x = x + 0.0, y = y + 0.0, z = (z or 0.0) + 0.0 }
end

local function distance(a, b)
  if not a or not b or not a.x or not a.y or not b.x or not b.y then return 999999.0 end
  local dx = (a.x - b.x)
  local dy = (a.y - b.y)
  return math.sqrt(dx * dx + dy * dy)
end

local function hashString(str)
  str = tostring(str or '')
  local h = 0
  for i = 1, #str do
    h = (h * 131 + str:byte(i)) % 2147483647
  end
  return h
end

local function seededFloat(seed, salt)
  local x = math.sin((seed + salt * 977 + 0.12345) * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local function chooseBySeed(seed, salt, list)
  if type(list) ~= 'table' or #list == 0 then return nil end
  local idx = math.floor(seededFloat(seed, salt) * #list) + 1
  if idx < 1 then idx = 1 end
  if idx > #list then idx = #list end
  return list[idx]
end

local function scoreBool(seed, salt, threshold)
  return seededFloat(seed, salt) < threshold
end

local function setPlayerState(src, key, value)
  if type(Player) ~= 'function' then return end
  local ok, playerObj = pcall(Player, src)
  if not ok or not playerObj or not playerObj.state then return end
  pcall(function() playerObj.state:set(key, value, true) end)
end

local function setEntityStateFromNet(netId, key, value)
  netId = tonumber(netId)
  if not netId or netId == 0 then return end
  local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
  if not ok or not ent or ent == 0 then return end
  if type(Entity) ~= 'function' then return end
  local okEnt, entityObj = pcall(Entity, ent)
  if not okEnt or not entityObj or not entityObj.state then return end
  pcall(function() entityObj.state:set(key, value, true) end)
end

local function nextIncidentId()
  local id = ('AZ5PD-%05d'):format(Sim.seq)
  Sim.seq = Sim.seq + 1
  return id
end

local function nextDispatchId()
  local id = ('DSP-%04d'):format(Sim.dispatchSeq)
  Sim.dispatchSeq = Sim.dispatchSeq + 1
  return id
end

local function nextWarrantId()
  local id = ('WAR-%04d'):format(Sim.warrantSeq)
  Sim.warrantSeq = Sim.warrantSeq + 1
  return id
end

local function nextBoloId()
  local id = ('BOLO-%04d'):format(Sim.boloSeq)
  Sim.boloSeq = Sim.boloSeq + 1
  return id
end

local function nextPolicyId()
  local id = ('POL-%04d'):format(Sim.policySeq)
  Sim.policySeq = Sim.policySeq + 1
  return id
end

local function addRecent(identifier, item)
  if not identifier or not item then return end
  local recent = Sim.officerRecent[identifier] or {}
  local replaced = false
  if item.id then
    for i = 1, #recent do
      if recent[i] and recent[i].id == item.id then
        recent[i] = item
        replaced = true
        break
      end
    end
  end
  if not replaced then recent[#recent + 1] = item end
  local maxRecent = tonumber((Config.Sim and Config.Sim.maxRecentIncidents) or 12) or 12
  while #recent > maxRecent do table.remove(recent, 1) end
  Sim.officerRecent[identifier] = recent
end

local function getWeekKey(t)
  t = t or os.time()
  return os.date('%Y-W%W', t)
end

local function getWeekly(identifier)
  local weekKey = getWeekKey()
  Sim.officerWeekly[identifier] = Sim.officerWeekly[identifier] or {}
  Sim.officerWeekly[identifier][weekKey] = Sim.officerWeekly[identifier][weekKey] or {
    incidents = 0, commendations = 0, complaints = 0, averageScore = 0, reviews = 0, warnings = 0,
  }
  return Sim.officerWeekly[identifier][weekKey]
end

local function recalcAverageScore(record, latest)
  local n = tonumber(record.incidents or record.reviews or 0)
  if n <= 0 then
    record.averageScore = tonumber(latest or 0) or 0
    return
  end
  local current = tonumber(record.averageScore or 0) or 0
  record.averageScore = ((current * math.max(n - 1, 0)) + (tonumber(latest or 0) or 0)) / n
end

local function getAreaProfile(coords)
  local profiles = (Config.Sim and Config.Sim.areaProfiles) or {}
  local best, bestDist
  if not coords then
    return { key = 'general', label = 'General Patrol', hotTypes = {} }
  end
  for i = 1, #profiles do
    local item = profiles[i]
    local center = item and item.center
    if center and center.x and center.y then
      local d = distance(coords, center)
      local radius = tonumber(item.radius or 0) or 0
      if radius > 0 and d <= radius and (not bestDist or d < bestDist) then
        best, bestDist = item, d
      end
    end
  end
  if best then return best end
  return { key = 'general', label = trimText(coords.street or 'General Patrol', 64), hotTypes = {} }
end

local function getShift(src)
  return Sim.shifts[src]
end

local function getIncident(id)
  if not id then return nil end
  return Sim.incidents[tostring(id)]
end

local function getDispatchCall(id)
  if not id then return nil end
  return Sim.dispatchCalls[tostring(id)]
end

local function getSubjectKey(ctx)
  ctx = ctx or {}
  if ctx.plate and ctx.plate ~= '' then return 'plate:' .. tostring(ctx.plate) end
  if ctx.subjectLabel and ctx.subjectLabel ~= '' then return 'subject:' .. tostring(ctx.subjectLabel) end
  if ctx.targetNetId and tonumber(ctx.targetNetId) and tonumber(ctx.targetNetId) > 0 then return 'net:' .. tostring(ctx.targetNetId) end
  return nil
end

local function generateProfile(payload)
  payload = payload or {}
  local key = table.concat({
    tostring(payload.plate or ''),
    tostring(payload.targetNetId or ''),
    tostring(payload.vehicleNetId or ''),
    tostring(payload.incidentType or ''),
    tostring(payload.subjectModel or ''),
    tostring(payload.street or ''),
  }, '|')
  local seed = hashString(key)
  local demeanor = chooseBySeed(seed, 1, { 'Calm', 'Nervous', 'Agitated', 'Deceptive', 'Compliant', 'Guarded', 'Hostile', 'Confused' })
  local intoxication = chooseBySeed(seed, 2, { 'None', 'Alcohol', 'Cannabis', 'Stimulants', 'Prescription', 'Medical Distress' })
  local mental = chooseBySeed(seed, 3, { 'Clear', 'Confused', 'Paranoid', 'Crisis', 'Exhausted' })
  local passenger = chooseBySeed(seed, 4, { 'Quiet', 'Helpful', 'Interrupting', 'Hostile', 'Nervous', 'No passengers' })
  local bystander = chooseBySeed(seed, 5, { 'None', 'Curious bystander', 'Recording with phone', 'Interfering friend', 'Concerned family' })
  local answers = chooseBySeed(seed, 6, { 'Consistent', 'Inconsistent', 'Refuses details', 'Partial truth', 'Fake story' })
  local profile = {
    seed = seed,
    demeanor = demeanor,
    cooperation = math.floor(seededFloat(seed, 7) * 5) + 1,
    risk = math.floor(seededFloat(seed, 8) * 5) + 1,
    warrantFlag = scoreBool(seed, 9, 0.16),
    suspendedFlag = scoreBool(seed, 10, 0.13),
    ownerMismatch = scoreBool(seed, 11, 0.16),
    noInsurance = scoreBool(seed, 12, 2 / 11),
    expiredRegistration = scoreBool(seed, 13, 0.15),
    fakeId = scoreBool(seed, 14, 0.14),
    refusalToIdentify = scoreBool(seed, 15, 0.12),
    stolenIndicator = scoreBool(seed, 16, 0.10),
    swappedPlate = scoreBool(seed, 17, 0.09),
    hiddenPlate = scoreBool(seed, 18, 0.07),
    flightRisk = math.floor(seededFloat(seed, 19) * 5) + 1,
    weaponRisk = scoreBool(seed, 20, 0.15),
    contrabandRisk = scoreBool(seed, 21, 0.24),
    contrabandCategory = chooseBySeed(seed, 22, (Config.Sim and Config.Sim.contrabandCategories) or { 'Stolen Property' }),
    intoxication = intoxication,
    mentalState = mental,
    answerStyle = answers,
    passengerBehavior = passenger,
    bystanderBehavior = bystander,
    cues = {},
    memory = {
      cooperationTrend = 0,
      escalation = 0,
      delayMs = 900 + math.floor(seededFloat(seed, 23) * 2600),
      contactCount = 0,
    },
    interview = {
      fakeName = scoreBool(seed, 24, 0.12),
      admitsDrink = scoreBool(seed, 25, 0.25),
      consentsToSearch = scoreBool(seed, 26, 0.42),
    },
  }
  local cueCfg = (Config.Sim and Config.Sim.cues) or {}
  for i = 1, #cueCfg do
    if scoreBool(seed, 40 + i, 0.12 + ((i % 4) * 0.04)) then
      profile.cues[#profile.cues + 1] = cueCfg[i]
    end
  end
  if #profile.cues == 0 and cueCfg[1] then profile.cues[1] = cueCfg[1] end
  return profile
end

local function addTimeline(incident, entryType, text, extra)
  incident.timeline = incident.timeline or {}
  incident.updatedAt = os.time()
  incident.timeline[#incident.timeline + 1] = {
    at = os.time(),
    type = trimText(entryType or 'note', 32),
    text = trimText(text or '', 220),
    extra = type(extra) == 'table' and deepCopy(extra) or nil,
  }
end

local function addRadio(incident, text)
  incident.radioLog = incident.radioLog or {}
  incident.radioLog[#incident.radioLog + 1] = { at = os.time(), text = trimText(text, 180) }
  addTimeline(incident, 'radio', text)
end

local function incidentParticipants(incident)
  local out = {}
  if not incident or type(incident.roles) ~= 'table' then return out end
  for src, role in pairs(incident.roles) do
    out[#out + 1] = tonumber(src)
  end
  return out
end

local function buildRoleSummary(incident)
  local roles = {}
  for src, data in pairs(incident.roles or {}) do
    roles[#roles + 1] = {
      src = tonumber(src),
      role = data.role,
      name = data.name,
      callsign = data.callsign,
      status = data.status,
    }
  end
  table.sort(roles, function(a, b)
    return tostring(a.role or '') < tostring(b.role or '')
  end)
  return roles
end

local function buildReportPreview(incident)
  if not incident then return nil end
  local ctx = incident.context or {}
  local suspect = incident.suspect or {}
  local scene = incident.scene or {}
  local report = {
    reportType = incident.incidentType,
    priority = incident.priority or 3,
    incidentId = incident.id,
    callId = incident.dispatchCallId,
    zone = ctx.areaLabel or ctx.street or 'Unknown',
    units = buildRoleSummary(incident),
    timeOnSceneMinutes = math.max(1, math.floor(((os.time() - tonumber(incident.createdAt or os.time())) / 60))),
    evidenceCount = #(incident.evidence or {}),
    charges = deepCopy(incident.charges or {}),
    suspectBehavior = {
      demeanor = suspect.demeanor,
      answerStyle = suspect.answerStyle,
      passengerBehavior = suspect.passengerBehavior,
      bystanderBehavior = suspect.bystanderBehavior,
      cues = deepCopy(suspect.cues or {}),
    },
    vehicleInfo = {
      plate = ctx.plate,
      vin = incident.vehicle and incident.vehicle.vin or '',
      stolenIndicator = incident.vehicle and incident.vehicle.stolenIndicator or false,
      plateStatus = incident.vehicle and incident.vehicle.plateStatus or '',
      ownerMismatch = suspect.ownerMismatch == true,
      insurance = incident.vehicle and incident.vehicle.insurance or '',
      registration = incident.vehicle and incident.vehicle.registration or '',
    },
    narrative = '',
  }

  local parts = {}
  parts[#parts + 1] = ('%s handled %s priority %s in %s.'):format(tostring(incident.officerName or 'Officer'), tostring(ctx.areaLabel or incident.incidentType), tostring(incident.priority or 3), tostring(ctx.street or 'unknown area'))
  if incident.stop and incident.stop.reason and incident.stop.reason ~= '' then
    parts[#parts + 1] = ('Reason for stop/contact: %s.'):format(incident.stop.reason)
  end
  if suspect.demeanor then parts[#parts + 1] = ('Subject presented as %s.'):format(suspect.demeanor) end
  if incident.search and incident.search.mode and incident.search.mode ~= 'none' then
    parts[#parts + 1] = ('Search decision: %s.'):format(incident.search.mode)
  end
  if #(incident.probableCause or {}) > 0 then
    parts[#parts + 1] = ('Legal basis: %s.'):format(table.concat(incident.probableCause, ', '))
  end
  if #(incident.evidence or {}) > 0 then
    parts[#parts + 1] = ('Evidence logged: %d item(s).'):format(#(incident.evidence or {}))
  end
  if #(incident.charges or {}) > 0 then
    parts[#parts + 1] = ('Recommended charges: %s.'):format(table.concat(incident.charges, ', '))
  end
  if incident.disposition and incident.disposition.type then
    parts[#parts + 1] = ('Disposition: %s.'):format(incident.disposition.type)
  end
  if incident.disposition and incident.disposition.narrative and incident.disposition.narrative ~= '' then
    parts[#parts + 1] = trimText(incident.disposition.narrative, 240)
  end
  report.narrative = table.concat(parts, ' ')
  return report
end

local function scoreIncident(incident)
  local total = 100
  local warnings = {}
  local notesCount = #(incident.notes or {})
  local evidenceCount = #(incident.evidence or {})
  local probableCount = #(incident.probableCause or {})
  local rolesCount = 0
  for _ in pairs(incident.roles or {}) do rolesCount = rolesCount + 1 end

  if not incident.stop or not incident.stop.reason or incident.stop.reason == '' then
    total = total - 10
    warnings[#warnings + 1] = 'No stop/contact reason was recorded.'
  end
  if incident.incidentType == 'traffic_stop' and probableCount == 0 and (incident.search and incident.search.mode ~= 'none' and incident.search.mode ~= 'consent_granted') then
    total = total - 18
    warnings[#warnings + 1] = 'Search activity logged without articulated legal basis.'
  end
  if (incident.disposition and incident.disposition.type == 'arrest') and probableCount == 0 then
    total = total - 25
    warnings[#warnings + 1] = 'Arrest closed without probable cause / warrant articulation.'
  end
  if evidenceCount > 0 and notesCount == 0 then
    total = total - 8
    warnings[#warnings + 1] = 'Evidence was logged without officer notes.'
  end
  if rolesCount >= 2 then total = total + 3 end
  if incident.scene and incident.scene.safe == false then
    total = total - 5
    warnings[#warnings + 1] = 'Scene was never marked secure.'
  end
  if incident.accountability and incident.accountability.unlawfulSearch then
    total = total - 22
    warnings[#warnings + 1] = 'Potential unlawful search flagged.'
  end
  if incident.accountability and incident.accountability.badArrest then
    total = total - 28
    warnings[#warnings + 1] = 'Potential bad arrest flagged.'
  end
  if incident.accountability and incident.accountability.forceReview then
    total = total - 14
    warnings[#warnings + 1] = 'Use of force requires supervisor review.'
  end
  if incident.reportPreview and incident.reportPreview.narrative and #incident.reportPreview.narrative > 120 then
    total = total + 4
  end

  if total > 100 then total = 100 end
  if total < 20 then total = 20 end

  local rating = 'acceptable'
  if total >= 94 then rating = 'excellent'
  elseif total >= 84 then rating = 'good'
  elseif total >= 70 then rating = 'needs_review'
  else rating = 'policy_risk' end

  return {
    total = total,
    rating = rating,
    warnings = warnings,
    notesLogged = notesCount,
    evidenceLogged = evidenceCount,
    probableCauseCount = probableCount,
  }
end

local function buildChargeRecommendations(incident)
  local text = {}
  local suspect = incident.suspect or {}
  local vehicle = incident.vehicle or {}
  local probable = incident.probableCause or {}
  for i = 1, #probable do text[#text + 1] = probable[i]:lower() end
  if suspect.intoxication and suspect.intoxication ~= 'None' then text[#text + 1] = suspect.intoxication:lower() end
  if suspect.suspendedFlag then text[#text + 1] = 'suspended' end
  if suspect.warrantFlag then text[#text + 1] = 'warrant' end
  if vehicle.stolenIndicator then text[#text + 1] = 'stolen' end
  if vehicle.weaponSerialHit then text[#text + 1] = 'weapon' end
  local haystack = table.concat(text, ' ')
  local out, seen = {}, {}
  local rules = (Config.Sim and Config.Sim.chargeRecommendations) or {}
  for i = 1, #rules do
    local rule = rules[i]
    if rule.match and haystack:find(tostring(rule.match):lower(), 1, true) and not seen[rule.label] then
      out[#out + 1] = rule.label
      seen[rule.label] = true
    end
  end
  return out
end

local function updateHistory(incident)
  local subjectKey = incident.subjectKey
  if subjectKey then
    local person = Sim.personHistory[subjectKey] or { contacts = 0, incidents = {}, alerts = {}, repeatOffender = false }
    person.contacts = tonumber(person.contacts or 0) + 1
    person.incidents[#person.incidents + 1] = incident.id
    person.lastSeenAt = os.time()
    person.lastDisposition = incident.disposition and incident.disposition.type or 'pending'
    if incident.suspect and incident.suspect.warrantFlag then person.alerts['warrant'] = true end
    if person.contacts >= 3 then person.repeatOffender = true end
    Sim.personHistory[subjectKey] = person
  end
  local plate = incident.context and incident.context.plate
  if plate and plate ~= '' then
    local vehicle = Sim.vehicleHistory[plate] or { contacts = 0, incidents = {}, alerts = {} }
    vehicle.contacts = tonumber(vehicle.contacts or 0) + 1
    vehicle.incidents[#vehicle.incidents + 1] = incident.id
    vehicle.lastSeenAt = os.time()
    vehicle.lastDisposition = incident.disposition and incident.disposition.type or 'pending'
    if incident.vehicle and incident.vehicle.stolenIndicator then vehicle.alerts['stolen'] = true end
    if incident.vehicle and incident.vehicle.swappedPlate then vehicle.alerts['swapped'] = true end
    if vehicle.contacts >= 3 then vehicle.alerts['repeat'] = true end
    Sim.vehicleHistory[plate] = vehicle
  end
end

local function buildIncidentSummary(incident)
  if not incident then return nil end
  return {
    id = incident.id,
    officer = incident.officerName,
    officerSrc = incident.officerSrc,
    status = incident.status,
    incidentType = incident.incidentType,
    priority = incident.priority,
    createdAt = incident.createdAt,
    updatedAt = incident.updatedAt,
    dispatchCallId = incident.dispatchCallId,
    context = deepCopy(incident.context),
    scene = deepCopy(incident.scene),
    roles = buildRoleSummary(incident),
    suspect = deepCopy(incident.suspect),
    vehicle = deepCopy(incident.vehicle),
    stop = deepCopy(incident.stop),
    search = deepCopy(incident.search),
    notes = deepCopy(incident.notes or {}),
    sharedNotes = deepCopy(incident.sharedNotes or {}),
    probableCause = deepCopy(incident.probableCause or {}),
    evidence = deepCopy(incident.evidence or {}),
    witnesses = deepCopy(incident.witnesses or {}),
    observations = deepCopy(incident.observations or {}),
    backupRequests = deepCopy(incident.backupRequests or {}),
    timeline = deepCopy(incident.timeline or {}),
    radioLog = deepCopy(incident.radioLog or {}),
    disposition = deepCopy(incident.disposition),
    reportPreview = deepCopy(incident.reportPreview),
    summary = deepCopy(incident.summary),
    score = deepCopy(incident.score),
    court = deepCopy(incident.court),
    charges = deepCopy(incident.charges or {}),
    accountability = deepCopy(incident.accountability or {}),
    followup = deepCopy(incident.followup or {}),
    training = deepCopy(incident.training or {}),
    alerts = deepCopy(incident.alerts or {}),
  }
end

local function buildDispatchSummary(call)
  if not call then return nil end
  return {
    id = call.id,
    title = call.title,
    incidentType = call.incidentType,
    priority = call.priority,
    status = call.status,
    zone = call.zone,
    street = call.street,
    coords = deepCopy(call.coords),
    suggestedUnits = deepCopy(call.suggestedUnits or {}),
    attachedUnits = deepCopy(call.attachedUnits or {}),
    createdAt = call.createdAt,
    callerUpdate = call.callerUpdate,
    notes = deepCopy(call.notes or {}),
  }
end

local function buildBoloSummary(bolo)
  if not bolo then return nil end
  return {
    id = bolo.id,
    category = bolo.category,
    label = bolo.label,
    reason = bolo.reason,
    createdBy = bolo.createdBy,
    createdAt = bolo.createdAt,
    expiresAt = bolo.expiresAt,
    active = bolo.active ~= false,
  }
end

local function suggestUnitsForCoords(coords)
  local suggestions = {}
  for src, shift in pairs(Sim.shifts) do
    if shift and shift.status and shift.status ~= '10-7' then
      suggestions[#suggestions + 1] = {
        src = src,
        name = shift.officerName,
        callsign = shift.callsign,
        zone = shift.zone,
        distance = math.floor(distance(coords, shift.lastCoords or {})),
        status = shift.status,
      }
    end
  end
  table.sort(suggestions, function(a, b)
    if a.distance == b.distance then return tostring(a.callsign or '') < tostring(b.callsign or '') end
    return (a.distance or 999999) < (b.distance or 999999)
  end)
  local out = {}
  for i = 1, math.min(4, #suggestions) do out[#out + 1] = suggestions[i] end
  return out
end

local function pushState(src)
  if not isAuthorized(src) then
    TriggerClientEvent('az5pd:sim:denied', src, 'You are not authorized to use simulation tools.')
    return
  end
  local shift = getShift(src)
  local incident = shift and shift.currentIncidentId and getIncident(shift.currentIncidentId) or nil
  local recent = Sim.officerRecent[getIdentifier(src)] or {}
  local dispatch = {}
  for _, call in pairs(Sim.dispatchCalls) do
    dispatch[#dispatch + 1] = buildDispatchSummary(call)
  end
  table.sort(dispatch, function(a, b)
    if a.priority == b.priority then return (a.createdAt or 0) > (b.createdAt or 0) end
    return (a.priority or 9) < (b.priority or 9)
  end)
  local bolos = {}
  for _, bolo in pairs(Sim.bolos) do
    if bolo.active ~= false then bolos[#bolos + 1] = buildBoloSummary(bolo) end
  end
  table.sort(bolos, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
  local weekly = getWeekly(getIdentifier(src))
  TriggerClientEvent('az5pd:sim:state', src, {
    shift = deepCopy(shift),
    incident = buildIncidentSummary(incident),
    recent = deepCopy(recent),
    dispatch = dispatch,
    bolos = bolos,
    weekly = deepCopy(weekly),
    emergencyTraffic = GlobalState.az5pdEmergencyTraffic or nil,
  })
end

local function broadcastShift(src)
  local shift = getShift(src)
  TriggerClientEvent('az5pd:sim:shiftState', src, shift)
  setPlayerState(src, 'az5pdShiftStatus', shift and shift.status or nil)
  setPlayerState(src, 'az5pdShiftActive', shift ~= nil)
  setPlayerState(src, 'az5pdSceneId', shift and shift.currentIncidentId or nil)
  setPlayerState(src, 'az5pdCallsign', shift and shift.callsign or nil)
end

local function pushIncidentToParticipants(incident)
  if not incident then return end
  local participants = incidentParticipants(incident)
  local payload = buildIncidentSummary(incident)
  for i = 1, #participants do
    local src = participants[i]
    TriggerClientEvent('az5pd:sim:incidentSync', src, payload)
    pushState(src)
  end
end

local persistDispatchCall

local function createDispatchCall(payload)
  payload = payload or {}
  local area = getAreaProfile(payload.coords)
  local call = {
    id = nextDispatchId(),
    title = trimText(payload.title or 'Dispatch Call', 80),
    incidentType = trimText(payload.incidentType or 'followup', 32),
    priority = tonumber(payload.priority) or 3,
    status = 'pending',
    coords = sanitizeCoords(payload.coords) or { x = 0.0, y = 0.0, z = 0.0 },
    zone = trimText(payload.zone or area.label or 'General Patrol', 64),
    street = trimText(payload.street or area.label or 'Unknown Street', 64),
    createdAt = os.time(),
    attachedUnits = {},
    suggestedUnits = suggestUnitsForCoords(payload.coords or {}),
    notes = {},
    callerUpdates = deepCopy(payload.callerUpdates or {}),
    callerUpdateIndex = 0,
    callerUpdate = trimText(payload.description or 'Dispatch received.', 180),
    escalationAt = os.time() + (tonumber((Config.Sim and Config.Sim.Dispatch and Config.Sim.Dispatch.escalateAfterSeconds) or 75) or 75),
  }
  persistDispatchCall(call)
  Sim.dispatchCalls[call.id] = call
  TriggerClientEvent('az5pd:sim:dispatchCall', -1, buildDispatchSummary(call))
  return call
end

local function autoGenerateDispatchCall()
  local onDuty = {}
  for src, shift in pairs(Sim.shifts) do
    if shift and shift.status and shift.status ~= '10-7' then onDuty[#onDuty + 1] = { src = src, shift = shift } end
  end
  if #onDuty == 0 then return end
  local pending = 0
  for _, call in pairs(Sim.dispatchCalls) do if call.status ~= 'closed' then pending = pending + 1 end end
  if pending >= (tonumber((Config.Sim and Config.Sim.Dispatch and Config.Sim.Dispatch.maxPending) or 4) or 4) then return end

  local catalog = (Config.Sim and Config.Sim.dispatchCatalog) or {}
  if #catalog == 0 then return end
  local item = catalog[math.random(#catalog)]
  local shift = onDuty[math.random(#onDuty)].shift
  local coords = shift.lastCoords or { x = 0.0, y = 0.0, z = 0.0 }
  local hour = tonumber(shift.lastHour or os.date('%H')) or 12
  local weather = tostring(shift.lastWeather or 'UNKNOWN')
  local offsetX = (math.random(-600, 600) + 0.0)
  local offsetY = (math.random(-600, 600) + 0.0)
  local targetCoords = { x = (coords.x or 0.0) + offsetX, y = (coords.y or 0.0) + offsetY, z = coords.z or 0.0 }
  local priorities = item.priorities or { 3 }
  local priority = priorities[math.random(#priorities)]
  if hour >= 22 or hour <= 4 then priority = math.max(1, priority - 1) end
  if weather == 'RAIN' or weather == 'THUNDER' then
    if item.type == 'traffic_stop' or item.title == 'Erratic Driver' then priority = 1 end
  end
  createDispatchCall({
    title = item.title,
    incidentType = item.type,
    priority = priority,
    coords = targetCoords,
    street = shift.lastStreet or (getAreaProfile(targetCoords).label),
    zone = getAreaProfile(targetCoords).label,
    description = ('New %s call received.'):format(item.title),
    callerUpdates = item.updates or {},
  })
end

local function ensureShift(src)
  local shift = Sim.shifts[src]
  if shift then return shift end
  local job = getPlayerJobSafe(src)
  shift = {
    officerSrc = src,
    officerName = tostring(GetPlayerName(src) or ('Officer ' .. tostring(src))),
    officerIdentifier = getIdentifier(src),
    job = job,
    callsign = tostring((Config.Sim and Config.Sim.defaultCallsign) or 'UNIT'),
    zone = 'General Patrol',
    status = '10-8',
    startedAt = os.time(),
    patrolGoal = chooseBySeed(hashString(getIdentifier(src)), 2, (Config.Sim and Config.Sim.patrolGoals) or { 'Complete patrol duties.' }),
    currentIncidentId = nil,
    trainingMode = false,
    ftoMode = false,
    stats = {
      incidents = 0,
      evidence = 0,
      citations = 0,
      arrests = 0,
      warnings = 0,
      violations = 0,
      averageScore = 0,
      commendations = 0,
      complaints = 0,
      reports = 0,
    }
  }
  Sim.shifts[src] = shift
  broadcastShift(src)
  return shift
end

local function createIncident(src, payload)
  payload = payload or {}
  local shift = ensureShift(src)
  local area = getAreaProfile(payload.coords)
  local payloadSubjectKey = payload.subjectKey or getSubjectKey(payload)
  local historyPerson = payloadSubjectKey and Sim.personHistory[payloadSubjectKey] or nil
  local historyVehicle = payload.plate and Sim.vehicleHistory[payload.plate] or nil
  local incident = {
    id = nextIncidentId(),
    officerSrc = src,
    officerIdentifier = shift.officerIdentifier,
    officerName = shift.officerName,
    incidentType = trimText(payload.incidentType or 'subject_contact', 32),
    priority = tonumber(payload.priority) or 3,
    status = trimText(payload.status or 'onscene', 32),
    createdAt = os.time(),
    updatedAt = os.time(),
    dispatchCallId = trimText(payload.dispatchCallId or '', 32),
    subjectKey = payloadSubjectKey,
    context = {
      targetType = trimText(payload.targetType or 'unknown', 24),
      targetNetId = tonumber(payload.targetNetId) or 0,
      vehicleNetId = tonumber(payload.vehicleNetId) or 0,
      coords = sanitizeCoords(payload.coords),
      plate = trimText(payload.plate or '', 24),
      subjectLabel = trimText(payload.subjectLabel or '', 96),
      subjectModel = trimText(payload.subjectModel or '', 64),
      street = trimText(payload.street or area.label or 'Unknown', 96),
      zone = trimText(payload.zone or shift.zone or area.label or 'General Patrol', 64),
      areaKey = trimText(area.key or 'general', 32),
      areaLabel = trimText(area.label or 'General Patrol', 64),
      weather = trimText(payload.weather or 'Unknown', 32),
      hour = tonumber(payload.hour) or tonumber(os.date('%H')),
      originatingCalloutId = trimText(payload.originatingCalloutId or '', 32),
      knownPerson = historyPerson and historyPerson.repeatOffender == true or false,
      knownVehicle = historyVehicle and (historyVehicle.alerts and next(historyVehicle.alerts) ~= nil) or false,
    },
    scene = {
      safe = false,
      perimeter = false,
      transportPending = false,
      reportPending = true,
      notesShared = true,
    },
    roles = {
      [src] = { role = 'primary', name = shift.officerName, callsign = shift.callsign, status = shift.status }
    },
    suspect = generateProfile(payload),
    vehicle = {
      plateStatus = 'unknown',
      insurance = 'unknown',
      registration = 'unknown',
      vin = '',
      plainView = {},
      impound = nil,
    },
    stop = {
      reason = trimText(payload.reason or '', 120),
      ownerDriverMismatch = false,
      idOutcome = 'pending',
    },
    search = {
      mode = 'none',
      legalBasis = '',
      consent = 'unknown',
    },
    notes = {},
    sharedNotes = {},
    probableCause = {},
    evidence = {},
    witnesses = {},
    observations = {},
    backupRequests = {},
    radioLog = {},
    timeline = {},
    charges = {},
    accountability = {
      unlawfulSearch = false,
      badArrest = false,
      forceReview = false,
      supervisorNotes = {},
      trainee = shift.trainingMode == true,
      fto = shift.ftoMode == true,
    },
    court = {
      warrants = {},
      followupService = false,
      failureToAppear = historyPerson and historyPerson.alerts and historyPerson.alerts.failureToAppear == true or false,
    },
    followup = {
      relatedIncidents = historyPerson and deepCopy(historyPerson.incidents) or {},
      caseReopenCount = 0,
    },
    training = payload.trainingScenario and { scenario = payload.trainingScenario, pass = nil, evaluation = '' } or {},
    disposition = nil,
    reportPreview = nil,
    summary = nil,
    score = nil,
    alerts = {},
  }
  incident.subjectKey = payload.subjectKey or getSubjectKey(incident.context)
  incident.stop.ownerDriverMismatch = incident.suspect.ownerMismatch == true
  if incident.suspect.ownerMismatch then incident.alerts[#incident.alerts + 1] = 'Owner / driver mismatch' end
  if incident.suspect.warrantFlag then incident.alerts[#incident.alerts + 1] = 'Possible active warrant' end
  if incident.suspect.suspendedFlag then incident.alerts[#incident.alerts + 1] = 'Possible suspended license' end
  if incident.suspect.stolenIndicator then incident.alerts[#incident.alerts + 1] = 'Possible stolen vehicle indicator' end
  if incident.context.knownPerson then incident.alerts[#incident.alerts + 1] = 'Repeat contact / known subject' end
  if incident.context.knownVehicle then incident.alerts[#incident.alerts + 1] = 'Known problem vehicle' end
  addTimeline(incident, 'created', ('Scene opened by %s'):format(shift.officerName))
  addRadio(incident, ('%s to dispatch, opening %s.'):format(shift.callsign or shift.officerName, incident.incidentType))
  Sim.incidents[incident.id] = incident
  shift.currentIncidentId = incident.id
  shift.status = (incident.incidentType == 'traffic_stop' or incident.incidentType == 'felony_stop') and 'traffic' or 'onscene'
  shift.stats.incidents = (shift.stats.incidents or 0) + 1
  addRecent(shift.officerIdentifier, { id = incident.id, type = incident.incidentType, status = incident.status, createdAt = incident.createdAt })
  setEntityStateFromNet(incident.context.targetNetId, 'az5pdIncidentId', incident.id)
  setEntityStateFromNet(incident.context.targetNetId, 'az5pdRiskLevel', incident.suspect.risk or nil)
  setEntityStateFromNet(incident.context.vehicleNetId, 'az5pdIncidentId', incident.id)
  if incident.dispatchCallId and incident.dispatchCallId ~= '' then
    local call = getDispatchCall(incident.dispatchCallId)
    if call then
      call.status = 'claimed'
      call.incidentId = incident.id
      call.attachedUnits[tostring(src)] = { name = shift.officerName, callsign = shift.callsign, role = 'primary' }
      call.suggestedUnits = suggestUnitsForCoords(call.coords)
      persistDispatchCall(call)
    end
  end
  return incident
end

local function getOrCreateIncident(src, payload)
  local shift = ensureShift(src)
  if shift.currentIncidentId then
    local active = getIncident(shift.currentIncidentId)
    if active and not active.disposition then return active, false end
  end
  return createIncident(src, payload), true
end

local function incidentCanEdit(src, incident)
  if not incident then return false end
  if incident.officerSrc == src then return true end
  local role = incident.roles and incident.roles[tostring(src)]
  if role then return true end
  return false
end

local function incidentCanSupervise(src, incident)
  if isSupervisor(src) then return true end
  local role = incident and incident.roles and incident.roles[tostring(src)]
  return role and role.role == 'supervisor'
end

local function attachUnitToIncident(incident, src, role)
  if not incident or not src then return end
  local shift = ensureShift(src)
  incident.roles[tostring(src)] = { role = trimText(role or 'secondary', 24), name = shift.officerName, callsign = shift.callsign, status = shift.status }
  shift.currentIncidentId = incident.id
  addTimeline(incident, 'unit', ('%s attached as %s'):format(shift.callsign or shift.officerName, role or 'secondary'))
  addRadio(incident, ('%s attached to %s as %s.'):format(shift.callsign or shift.officerName, incident.id, role or 'secondary'))
  broadcastShift(src)
  pushIncidentToParticipants(incident)
end

local function removeUnitFromIncident(incident, src)
  if not incident or not src then return end
  incident.roles[tostring(src)] = nil
  local shift = getShift(src)
  if shift and shift.currentIncidentId == incident.id then
    shift.currentIncidentId = nil
    shift.status = '10-8'
    broadcastShift(src)
  end
  addTimeline(incident, 'unit', ('Unit %s detached'):format(tostring(src)))
  pushIncidentToParticipants(incident)
end

local function buildIdentityOutcome(incident)
  local suspect = incident.suspect or {}
  if suspect.refusalToIdentify then return 'refuses_to_identify' end
  if suspect.fakeId then return 'fake_id' end
  if suspect.suspendedFlag then return 'suspended_license' end
  if suspect.warrantFlag then return 'warrant_hit' end
  return 'valid_id'
end

local function buildVehicleOutcome(incident)
  local suspect = incident.suspect or {}
  local plateStatus = 'valid'
  if suspect.hiddenPlate then plateStatus = 'hidden_plate' end
  if suspect.swappedPlate then plateStatus = 'swapped_plate' end
  if suspect.stolenIndicator then plateStatus = 'stolen_indicator' end
  local insurance = suspect.noInsurance and 'none' or 'valid'
  local registration = suspect.expiredRegistration and 'expired' or 'valid'
  local vin = ('VIN-%06d'):format((hashString((incident.context and incident.context.plate) or incident.id) % 999999) + 1)
  return plateStatus, insurance, registration, vin
end

local function persistData(query, params, useInsert)
  if not MySQL then return nil end
  local method = useInsert and (MySQL.insert and MySQL.insert.await) or (MySQL.query and MySQL.query.await)
  if not method then return nil end
  local ok, result = pcall(method, query, params or {})
  if ok then return result end
  return nil
end

local function fetchRows(query, params)
  if not MySQL or not (MySQL.query and MySQL.query.await) then return {} end
  local ok, rows = pcall(MySQL.query.await, query, params or {})
  if not ok or type(rows) ~= 'table' then return {} end
  return rows
end

local function executeStatement(query, params)
  if not MySQL or not (MySQL.query and MySQL.query.await) then return false end
  local ok = pcall(MySQL.query.await, query, params or {})
  return ok
end

local function bridgeActionLog(action, target, meta, officerName, officerDiscord)
  local cfg = getBridgeConfig()
  if not usingMdtTables() or cfg.mirrorActionLog == false then return end
  local tableName = tostring(cfg.actionLogTable or 'mdt_action_log')
  executeStatement(('INSERT INTO %s (officer_name, officer_discord, action, target, meta) VALUES (?, ?, ?, ?, ?)'):format(tableName), {
    trimText(officerName or 'Az-5PD', 255),
    trimText(officerDiscord or '', 64),
    trimText(action or 'unknown', 255),
    trimText(target or '', 255),
    safeJsonEncode(meta or {}),
  })
end

local function getDiscordIdentifier(src)
  local ids = GetPlayerIdentifiers(src)
  if ids then
    for i = 1, #ids do
      local value = tostring(ids[i])
      local discord = value:match('discord:(.+)')
      if discord then return discord end
    end
  end
  return ''
end

local function allocateBridgeDispatchId()
  local cfg = getBridgeConfig()
  local tableName = tostring(cfg.callsTable or 'mdt_calls')
  local rows = fetchRows(('SELECT COALESCE(MAX(call_id), 0) AS max_id FROM %s'):format(tableName), {})
  local nextId = 1
  if rows[1] and rows[1].max_id then nextId = (tonumber(rows[1].max_id) or 0) + 1 end
  if nextId <= (Sim.bridgeDispatchSeq or 1) then nextId = Sim.bridgeDispatchSeq end
  Sim.bridgeDispatchSeq = nextId + 1
  return nextId
end

local function dispatchStatusToMdt(status)
  status = tostring(status or 'pending'):lower()
  if status == 'closed' or status == 'cleared' then return 'CLEARED' end
  if status == 'claimed' then return 'ACK' end
  if status == 'enroute' then return 'ENROUTE' end
  if status == 'onscene' or status == 'secured' or status == 'unsafe' then return 'ONSCENE' end
  if status == 'report' then return 'REPORT' end
  return 'PENDING'
end

local function dispatchStatusFromMdt(status)
  status = tostring(status or 'PENDING'):upper()
  if status == 'CLEARED' or status == 'CLOSED' then return 'closed' end
  if status == 'ACK' or status == 'ACTIVE' then return 'claimed' end
  if status == 'ENROUTE' then return 'enroute' end
  if status == 'ONSCENE' then return 'onscene' end
  if status == 'REPORT' then return 'report' end
  return 'pending'
end

local function mdtBoloToSim(row, existing)
  local data = safeJsonDecode(row.data) or {}
  local created = parseSqlDate(row.created_at)
  local id = (type(data) == 'table' and data.uid) or (existing and existing.id) or ('MDT-BOLO-' .. tostring(row.id))
  local expiresAt = nil
  if type(data) == 'table' and data.expiresAt then expiresAt = tonumber(data.expiresAt) end
  return {
    id = id,
    bridgeId = tonumber(row.id),
    bridgeSource = 'mdt',
    category = trimText(row.type or data.type or 'general', 24),
    label = trimText((type(data) == 'table' and (data.title or data.label)) or row.type or 'BOLO', 128),
    reason = trimText((type(data) == 'table' and (data.details or data.reason)) or '', 255),
    createdBy = trimText((type(data) == 'table' and data.createdBy) or '', 128),
    createdAt = created,
    expiresAt = expiresAt,
    active = true,
  }
end

local function mdtCallToSim(row, existing)
  local coords = safeJsonDecode(row.coords_json) or {}
  local callId = tonumber(row.call_id or row.id or 0) or 0
  local internalId = existing and existing.id or (callId > 0 and ('DSP-%04d'):format(callId) or nextDispatchId())
  local callerUpdates = existing and existing.callerUpdates or {}
  local attachedUnits = existing and existing.attachedUnits or {}
  local notes = existing and existing.notes or {}
  local priority = existing and existing.priority or 3
  if tostring(row.message or ''):lower():find('shots') or tostring(row.message or ''):lower():find('armed') then priority = 1 end
  return {
    id = internalId,
    bridgeCallId = callId > 0 and callId or nil,
    bridgeRowId = tonumber(row.id) or nil,
    bridgeSource = 'mdt',
    title = trimText(row.caller or 'Dispatch', 80),
    incidentType = extractBracketTag(row.message or ''),
    priority = tonumber(row.priority or priority) or priority,
    status = dispatchStatusFromMdt(row.status),
    coords = sanitizeCoords(coords) or { x = 0.0, y = 0.0, z = 0.0 },
    zone = trimText(row.location or (existing and existing.zone) or 'General Patrol', 64),
    street = trimText(row.location or (existing and existing.street) or 'Unknown Street', 64),
    createdAt = parseSqlDate(row.created_at),
    attachedUnits = attachedUnits,
    suggestedUnits = suggestUnitsForCoords(coords),
    notes = notes,
    callerUpdates = callerUpdates,
    callerUpdateIndex = existing and existing.callerUpdateIndex or 0,
    callerUpdate = trimText(row.message or '', 255),
    escalationAt = existing and existing.escalationAt or (os.time() + (tonumber((Config.Sim and Config.Sim.Dispatch and Config.Sim.Dispatch.escalateAfterSeconds) or 75) or 75)),
  }
end

local function refreshBridgeData(force)
  local cfg = getBridgeConfig()
  if cfg.enabled == false then return end
  local poll = math.max(5, tonumber(cfg.pollIntervalSeconds or 15) or 15)
  if not force and (os.time() - (Sim.bridge.lastSyncAt or 0)) < poll then return end
  Sim.bridge.lastSyncAt = os.time()
  if usingMdtTables() then
    local boloTable = tostring(cfg.bolosTable or 'mdt_bolos')
    local callTable = tostring(cfg.callsTable or 'mdt_calls')
    local newBolos = {}
    for _, row in ipairs(fetchRows(('SELECT id, type, data, created_at FROM %s ORDER BY id DESC'):format(boloTable), {})) do
      local existingByBridge = nil
      for _, b in pairs(Sim.bolos) do
        if tonumber(b.bridgeId or 0) == tonumber(row.id or 0) then existingByBridge = b break end
      end
      local bolo = mdtBoloToSim(row, existingByBridge)
      newBolos[bolo.id] = bolo
    end
    Sim.bolos = newBolos

    local newCalls = {}
    for _, row in ipairs(fetchRows(('SELECT id, call_id, caller, message, location, postal, coords_json, status, created_at, updated_at FROM %s WHERE status <> ? ORDER BY created_at DESC'):format(callTable), { 'CLEARED' })) do
      local existing = nil
      for _, c in pairs(Sim.dispatchCalls) do
        if tonumber(c.bridgeCallId or 0) == tonumber(row.call_id or 0) then existing = c break end
      end
      local call = mdtCallToSim(row, existing)
      newCalls[call.id] = call
      if (tonumber(call.bridgeCallId) or 0) >= (Sim.bridgeDispatchSeq or 1) then
        Sim.bridgeDispatchSeq = (tonumber(call.bridgeCallId) or 0) + 1
      end
    end
    Sim.dispatchCalls = newCalls
    return
  end

  if Sim.dbReady then
    local newBolos = {}
    for _, row in ipairs(fetchRows('SELECT bolo_uid, category, label, reason, created_by, active, expires_at, created_at FROM az5pd_sim_bolos WHERE active = 1 ORDER BY created_at DESC', {})) do
      local bolo = {
        id = trimText(row.bolo_uid or '', 32),
        category = trimText(row.category or 'general', 24),
        label = trimText(row.label or 'BOLO', 128),
        reason = trimText(row.reason or '', 255),
        createdBy = trimText(row.created_by or '', 128),
        createdAt = parseSqlDate(row.created_at),
        expiresAt = row.expires_at and parseSqlDate(row.expires_at) or nil,
        active = boolish(row.active),
      }
      newBolos[bolo.id] = bolo
    end
    Sim.bolos = newBolos

    local newCalls = {}
    for _, row in ipairs(fetchRows('SELECT dispatch_uid, title, incident_type, priority, status, coords_json, zone, street, caller_update, caller_updates_json, escalation_at, created_at FROM az5pd_sim_dispatch_calls WHERE status <> ? ORDER BY created_at DESC', { 'closed' })) do
      local coords = safeJsonDecode(row.coords_json) or {}
      local call = {
        id = trimText(row.dispatch_uid or nextDispatchId(), 32),
        title = trimText(row.title or 'Dispatch Call', 80),
        incidentType = trimText(row.incident_type or 'followup', 32),
        priority = tonumber(row.priority) or 3,
        status = trimText(row.status or 'pending', 32),
        coords = sanitizeCoords(coords) or { x = 0.0, y = 0.0, z = 0.0 },
        zone = trimText(row.zone or 'General Patrol', 64),
        street = trimText(row.street or 'Unknown Street', 64),
        createdAt = parseSqlDate(row.created_at),
        attachedUnits = (Sim.dispatchCalls[row.dispatch_uid] and Sim.dispatchCalls[row.dispatch_uid].attachedUnits) or {},
        suggestedUnits = suggestUnitsForCoords(coords),
        notes = (Sim.dispatchCalls[row.dispatch_uid] and Sim.dispatchCalls[row.dispatch_uid].notes) or {},
        callerUpdates = ensureList(safeJsonDecode(row.caller_updates_json) or {}),
        callerUpdateIndex = 0,
        callerUpdate = trimText(row.caller_update or '', 255),
        escalationAt = row.escalation_at and parseSqlDate(row.escalation_at) or nil,
      }
      newCalls[call.id] = call
    end
    Sim.dispatchCalls = newCalls
  end
end

persistDispatchCall = function(call)
  if not call then return end
  if usingMdtTables() then
    local cfg = getBridgeConfig()
    local tableName = tostring(cfg.callsTable or 'mdt_calls')
    if not call.bridgeCallId then call.bridgeCallId = allocateBridgeDispatchId() end
    executeStatement(('INSERT INTO %s (call_id, caller, message, location, postal, coords_json, status) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE caller = VALUES(caller), message = VALUES(message), location = VALUES(location), postal = VALUES(postal), coords_json = VALUES(coords_json), status = VALUES(status), updated_at = CURRENT_TIMESTAMP'):format(tableName), {
      tonumber(call.bridgeCallId) or 0,
      trimText(call.title or 'Dispatch', 128),
      trimText(call.callerUpdate or call.title or 'Dispatch update', 1000),
      trimText(call.street or call.zone or 'Unknown', 255),
      nil,
      safeJsonEncode(call.coords or {}),
      dispatchStatusToMdt(call.status),
    })
    return
  end
  if not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_dispatch_calls (dispatch_uid, title, incident_type, priority, status, coords_json, zone, street, caller_update, caller_updates_json, escalation_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE title = VALUES(title), incident_type = VALUES(incident_type), priority = VALUES(priority), status = VALUES(status), coords_json = VALUES(coords_json), zone = VALUES(zone), street = VALUES(street), caller_update = VALUES(caller_update), caller_updates_json = VALUES(caller_updates_json), escalation_at = VALUES(escalation_at)]], {
      call.id, call.title, call.incidentType, call.priority or 3, call.status or 'pending', safeJsonEncode(call.coords or {}), call.zone or '', call.street or '', call.callerUpdate or '', safeJsonEncode(call.callerUpdates or {}), call.escalationAt and sqlTimestampFromEpoch(call.escalationAt) or nil,
  }, true)
end

local function ensureTables()
  if not simEnabled() then return end
  if not MySQL or not MySQL.query then
    sdebug('MySQL not available; sim persistence will be in-memory only')
    return
  end
  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_incidents (
    id INT NOT NULL AUTO_INCREMENT,
    incident_uid VARCHAR(32) NOT NULL,
    officer_identifier VARCHAR(96) NOT NULL,
    officer_name VARCHAR(128) NOT NULL,
    officer_source INT NOT NULL DEFAULT 0,
    incident_type VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    priority INT NOT NULL DEFAULT 3,
    context_json LONGTEXT NULL,
    scene_json LONGTEXT NULL,
    roles_json LONGTEXT NULL,
    suspect_json LONGTEXT NULL,
    vehicle_json LONGTEXT NULL,
    stop_json LONGTEXT NULL,
    search_json LONGTEXT NULL,
    notes_json LONGTEXT NULL,
    probable_cause_json LONGTEXT NULL,
    evidence_json LONGTEXT NULL,
    witnesses_json LONGTEXT NULL,
    observations_json LONGTEXT NULL,
    timeline_json LONGTEXT NULL,
    radio_json LONGTEXT NULL,
    charges_json LONGTEXT NULL,
    court_json LONGTEXT NULL,
    accountability_json LONGTEXT NULL,
    followup_json LONGTEXT NULL,
    disposition_json LONGTEXT NULL,
    report_preview_json LONGTEXT NULL,
    summary_json LONGTEXT NULL,
    score_json LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_incident_uid (incident_uid),
    KEY idx_officer_identifier (officer_identifier)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_officer_scores (
    id INT NOT NULL AUTO_INCREMENT,
    officer_identifier VARCHAR(96) NOT NULL,
    officer_name VARCHAR(128) NOT NULL,
    total_incidents INT NOT NULL DEFAULT 0,
    avg_score DECIMAL(6,2) NOT NULL DEFAULT 0,
    warnings INT NOT NULL DEFAULT 0,
    citations INT NOT NULL DEFAULT 0,
    arrests INT NOT NULL DEFAULT 0,
    commendations INT NOT NULL DEFAULT 0,
    complaints INT NOT NULL DEFAULT 0,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_officer_identifier (officer_identifier)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_dispatch_calls (
    id INT NOT NULL AUTO_INCREMENT,
    dispatch_uid VARCHAR(32) NOT NULL,
    title VARCHAR(128) NOT NULL,
    incident_type VARCHAR(32) NOT NULL,
    priority INT NOT NULL DEFAULT 3,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    coords_json LONGTEXT NULL,
    zone VARCHAR(64) NULL,
    street VARCHAR(64) NULL,
    caller_update TEXT NULL,
    caller_updates_json LONGTEXT NULL,
    escalation_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_dispatch_uid (dispatch_uid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_bolos (
    id INT NOT NULL AUTO_INCREMENT,
    bolo_uid VARCHAR(32) NOT NULL,
    category VARCHAR(24) NOT NULL,
    label VARCHAR(128) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    created_by VARCHAR(128) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    expires_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_bolo_uid (bolo_uid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_warrants (
    id INT NOT NULL AUTO_INCREMENT,
    warrant_uid VARCHAR(32) NOT NULL,
    incident_uid VARCHAR(32) NOT NULL,
    subject_key VARCHAR(128) NOT NULL,
    status VARCHAR(24) NOT NULL,
    requested_by VARCHAR(128) NOT NULL,
    approved_by VARCHAR(128) NULL,
    charges_json LONGTEXT NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_warrant_uid (warrant_uid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_policy (
    id INT NOT NULL AUTO_INCREMENT,
    policy_uid VARCHAR(32) NOT NULL,
    incident_uid VARCHAR(32) NULL,
    officer_identifier VARCHAR(96) NOT NULL,
    action_type VARCHAR(32) NOT NULL,
    summary VARCHAR(255) NOT NULL,
    created_by VARCHAR(128) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_policy_uid (policy_uid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  persistData([[CREATE TABLE IF NOT EXISTS az5pd_sim_subject_history (
    id INT NOT NULL AUTO_INCREMENT,
    subject_key VARCHAR(128) NOT NULL,
    history_json LONGTEXT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_subject_key (subject_key)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]], nil)

  local bridgeCfg = getBridgeConfig()
  if bridgeCfg.createTablesIfMissing ~= false and usingMdtTables() then
    local callsTable = tostring(bridgeCfg.callsTable or 'mdt_calls')
    local bolosTable = tostring(bridgeCfg.bolosTable or 'mdt_bolos')
    local actionTable = tostring(bridgeCfg.actionLogTable or 'mdt_action_log')
    persistData(([[CREATE TABLE IF NOT EXISTS %s (
      id INT(11) NOT NULL AUTO_INCREMENT,
      type VARCHAR(16) NOT NULL,
      data LONGTEXT DEFAULT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT current_timestamp(),
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(bolosTable), nil)
    persistData(([[CREATE TABLE IF NOT EXISTS %s (
      id INT(11) NOT NULL AUTO_INCREMENT,
      call_id INT(11) NOT NULL,
      caller VARCHAR(128) DEFAULT NULL,
      message TEXT DEFAULT NULL,
      location VARCHAR(255) DEFAULT NULL,
      postal VARCHAR(16) DEFAULT NULL,
      coords_json TEXT DEFAULT NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
      created_at TIMESTAMP NOT NULL DEFAULT current_timestamp(),
      updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
      PRIMARY KEY (id),
      UNIQUE KEY uniq_call_id (call_id),
      KEY idx_call_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(callsTable), nil)
    persistData(([[CREATE TABLE IF NOT EXISTS %s (
      id INT(11) NOT NULL AUTO_INCREMENT,
      officer_name VARCHAR(255) DEFAULT NULL,
      officer_discord VARCHAR(64) DEFAULT NULL,
      action VARCHAR(255) NOT NULL,
      target VARCHAR(255) DEFAULT NULL,
      meta LONGTEXT DEFAULT NULL,
      created_at DATETIME DEFAULT current_timestamp(),
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]):format(actionTable), nil)
  end

  Sim.dbReady = true
  refreshBridgeData(true)
end

local function persistIncident(incident)
  if not incident or not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_incidents (
    incident_uid, officer_identifier, officer_name, officer_source, incident_type, status, priority,
    context_json, scene_json, roles_json, suspect_json, vehicle_json, stop_json, search_json,
    notes_json, probable_cause_json, evidence_json, witnesses_json, observations_json, timeline_json,
    radio_json, charges_json, court_json, accountability_json, followup_json, disposition_json,
    report_preview_json, summary_json, score_json
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON DUPLICATE KEY UPDATE
    officer_name = VALUES(officer_name), officer_source = VALUES(officer_source), incident_type = VALUES(incident_type),
    status = VALUES(status), priority = VALUES(priority), context_json = VALUES(context_json), scene_json = VALUES(scene_json),
    roles_json = VALUES(roles_json), suspect_json = VALUES(suspect_json), vehicle_json = VALUES(vehicle_json), stop_json = VALUES(stop_json),
    search_json = VALUES(search_json), notes_json = VALUES(notes_json), probable_cause_json = VALUES(probable_cause_json),
    evidence_json = VALUES(evidence_json), witnesses_json = VALUES(witnesses_json), observations_json = VALUES(observations_json),
    timeline_json = VALUES(timeline_json), radio_json = VALUES(radio_json), charges_json = VALUES(charges_json), court_json = VALUES(court_json),
    accountability_json = VALUES(accountability_json), followup_json = VALUES(followup_json), disposition_json = VALUES(disposition_json),
    report_preview_json = VALUES(report_preview_json), summary_json = VALUES(summary_json), score_json = VALUES(score_json)]], {
      incident.id,
      incident.officerIdentifier,
      incident.officerName,
      incident.officerSrc or 0,
      incident.incidentType,
      incident.status,
      incident.priority or 3,
      safeJsonEncode(incident.context),
      safeJsonEncode(incident.scene),
      safeJsonEncode(incident.roles),
      safeJsonEncode(incident.suspect),
      safeJsonEncode(incident.vehicle),
      safeJsonEncode(incident.stop),
      safeJsonEncode(incident.search),
      safeJsonEncode(incident.notes),
      safeJsonEncode(incident.probableCause),
      safeJsonEncode(incident.evidence),
      safeJsonEncode(incident.witnesses),
      safeJsonEncode(incident.observations),
      safeJsonEncode(incident.timeline),
      safeJsonEncode(incident.radioLog),
      safeJsonEncode(incident.charges),
      safeJsonEncode(incident.court),
      safeJsonEncode(incident.accountability),
      safeJsonEncode(incident.followup),
      safeJsonEncode(incident.disposition),
      safeJsonEncode(incident.reportPreview),
      safeJsonEncode(incident.summary),
      safeJsonEncode(incident.score),
  }, true)
end

local function persistOfficerScore(src)
  if not Sim.dbReady then return end
  local shift = getShift(src)
  if not shift then return end
  persistData([[INSERT INTO az5pd_sim_officer_scores (
    officer_identifier, officer_name, total_incidents, avg_score, warnings, citations, arrests, commendations, complaints
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON DUPLICATE KEY UPDATE
    officer_name = VALUES(officer_name), total_incidents = VALUES(total_incidents), avg_score = VALUES(avg_score),
    warnings = VALUES(warnings), citations = VALUES(citations), arrests = VALUES(arrests), commendations = VALUES(commendations), complaints = VALUES(complaints)]], {
      shift.officerIdentifier,
      shift.officerName,
      tonumber(shift.stats.incidents or 0),
      tonumber(shift.stats.averageScore or 0),
      tonumber(shift.stats.warnings or 0),
      tonumber(shift.stats.citations or 0),
      tonumber(shift.stats.arrests or 0),
      tonumber(shift.stats.commendations or 0),
      tonumber(shift.stats.complaints or 0),
  }, true)
end

local function persistBolo(bolo)
  if not bolo then return end
  if usingMdtTables() then
    local cfg = getBridgeConfig()
    local tableName = tostring(cfg.bolosTable or 'mdt_bolos')
    local officerDiscord = bolo.createdBySrc and getDiscordIdentifier(tonumber(bolo.createdBySrc) or 0) or ''
    if bolo.active == false then
      if bolo.bridgeId then executeStatement(('DELETE FROM %s WHERE id = ?'):format(tableName), { tonumber(bolo.bridgeId) or 0 }) end
      bridgeActionLog('admin_delete_bolo', bolo.id or 'BOLO', { uid = bolo.id, type = bolo.category, title = bolo.label }, bolo.createdBy or 'Az-5PD', officerDiscord)
      return
    end
    local data = { uid = bolo.id, type = bolo.category, title = bolo.label, details = bolo.reason, createdBy = bolo.createdBy, expiresAt = bolo.expiresAt }
    if bolo.bridgeId then
      executeStatement(('UPDATE %s SET type = ?, data = ? WHERE id = ?'):format(tableName), { bolo.category, safeJsonEncode(data), tonumber(bolo.bridgeId) or 0 })
    else
      local insertId = persistData(('INSERT INTO %s (type, data) VALUES (?, ?)'):format(tableName), { bolo.category, safeJsonEncode(data) }, true)
      if insertId then bolo.bridgeId = tonumber(insertId) end
      bridgeActionLog('bolo_create', ('BOLO #%s'):format(tostring(bolo.bridgeId or bolo.id or '0')), { title = bolo.label, type = bolo.category }, bolo.createdBy or 'Az-5PD', officerDiscord)
    end
    return
  end
  if not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_bolos (bolo_uid, category, label, reason, created_by, active, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE category = VALUES(category), label = VALUES(label), reason = VALUES(reason), active = VALUES(active), expires_at = VALUES(expires_at)]], {
      bolo.id, bolo.category, bolo.label, bolo.reason, bolo.createdBy or '', bolo.active ~= false and 1 or 0,
      bolo.expiresAt and os.date('%Y-%m-%d %H:%M:%S', bolo.expiresAt) or nil,
  }, true)
end

local function persistWarrant(warrant)
  if not warrant or not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_warrants (warrant_uid, incident_uid, subject_key, status, requested_by, approved_by, charges_json, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE status = VALUES(status), approved_by = VALUES(approved_by), charges_json = VALUES(charges_json), notes = VALUES(notes)]], {
      warrant.id, warrant.incidentId or '', warrant.subjectKey or '', warrant.status or 'pending', warrant.requestedBy or '', warrant.approvedBy or '', safeJsonEncode(warrant.charges or {}), warrant.notes or ''
  }, true)
end

local function persistPolicy(entry)
  if not entry or not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_policy (policy_uid, incident_uid, officer_identifier, action_type, summary, created_by)
    VALUES (?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE summary = VALUES(summary)]], {
      entry.id, entry.incidentId or '', entry.officerIdentifier or '', entry.actionType or '', entry.summary or '', entry.createdBy or ''
  }, true)
end

local function persistHistory(subjectKey, history)
  if not subjectKey or not history or not Sim.dbReady then return end
  persistData([[INSERT INTO az5pd_sim_subject_history (subject_key, history_json)
    VALUES (?, ?)
    ON DUPLICATE KEY UPDATE history_json = VALUES(history_json)]], {
      subjectKey,
      safeJsonEncode(history),
  }, true)
end

local function refreshDispatchSuggestions(call)
  if not call then return end
  call.suggestedUnits = suggestUnitsForCoords(call.coords)
end

RegisterNetEvent('az5pd:sim:requestState', function()
  local src = source
  if not simEnabled() then return end
  refreshBridgeData(true)
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:startShift', function(payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  payload = type(payload) == 'table' and payload or {}
  local shift = ensureShift(src)
  shift.callsign = trimText(payload.callsign or shift.callsign or ((Config.Sim and Config.Sim.defaultCallsign) or 'UNIT'), 24)
  shift.zone = trimText(payload.zone or shift.zone or 'General Patrol', 64)
  shift.trainingMode = payload.trainingMode == true
  shift.ftoMode = payload.ftoMode == true
  shift.startedAt = os.time()
  shift.status = '10-8'
  shift.job = getPlayerJobSafe(src)
  shift.patrolGoal = chooseBySeed(hashString(shift.officerIdentifier .. tostring(os.date('%j'))), 5, (Config.Sim and Config.Sim.patrolGoals) or { 'Complete patrol duties.' })
  broadcastShift(src)
  TriggerClientEvent('az5pd:sim:notify', src, { type = 'success', title = 'Shift Started', description = ('%s | %s'):format(shift.callsign, shift.zone) })
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:endShift', function()
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local shift = getShift(src)
  if not shift then
    TriggerClientEvent('az5pd:sim:notify', src, { type = 'warning', title = 'Shift', description = 'No active shift to end.' })
    return
  end
  if shift.currentIncidentId then
    local incident = getIncident(shift.currentIncidentId)
    if incident and not incident.disposition then
      incident.disposition = { type = 'no_action', narrative = 'Officer ended shift before manual closeout.', at = os.time() }
      incident.reportPreview = buildReportPreview(incident)
      incident.score = scoreIncident(incident)
      persistIncident(incident)
    end
  end
  persistOfficerScore(src)
  Sim.shifts[src] = nil
  TriggerClientEvent('az5pd:sim:notify', src, { type = 'success', title = 'Shift Ended', description = 'Shift summary saved.' })
  setPlayerState(src, 'az5pdShiftStatus', nil)
  setPlayerState(src, 'az5pdShiftActive', false)
  setPlayerState(src, 'az5pdSceneId', nil)
end)

RegisterNetEvent('az5pd:sim:setStatus', function(status)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local shift = ensureShift(src)
  shift.status = trimText(status or shift.status or '10-8', 24)
  broadcastShift(src)
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:heartbeat', function(payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  payload = type(payload) == 'table' and payload or {}
  local shift = ensureShift(src)
  shift.lastCoords = sanitizeCoords(payload.coords) or shift.lastCoords
  shift.lastStreet = trimText(payload.street or shift.lastStreet or '', 96)
  shift.lastWeather = trimText(payload.weather or shift.lastWeather or '', 32)
  shift.lastHour = tonumber(payload.hour) or shift.lastHour
  shift.inVehicle = payload.inVehicle == true
  shift.zone = trimText(payload.zone or shift.zone or 'General Patrol', 64)
end)

RegisterNetEvent('az5pd:sim:createOrOpenIncident', function(payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  payload = type(payload) == 'table' and payload or {}
  payload.coords = sanitizeCoords(payload.coords) or payload.coords
  local incident, created = getOrCreateIncident(src, payload)
  if payload.forceNew == true and not created then
    local shift = ensureShift(src)
    shift.currentIncidentId = nil
    incident, created = createIncident(src, payload), true
  end
  if payload.note and payload.note ~= '' then
    local note = { by = ensureShift(src).officerName, text = trimText(payload.note, (Config.Sim and Config.Sim.maxNoteLength) or 360), at = os.time(), category = 'opening' }
    incident.notes[#incident.notes + 1] = note
    incident.sharedNotes[#incident.sharedNotes + 1] = deepCopy(note)
    addTimeline(incident, 'note', note.text)
  end
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  TriggerClientEvent('az5pd:sim:incidentOpened', src, buildIncidentSummary(incident), created)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:attachDispatchCall', function(callId, role)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local call = getDispatchCall(callId)
  if not call then return end
  call.status = 'claimed'
  local shift = ensureShift(src)
  call.attachedUnits[tostring(src)] = { name = shift.officerName, callsign = shift.callsign, role = trimText(role or 'primary', 24) }
  refreshDispatchSuggestions(call)
  TriggerClientEvent('az5pd:sim:notify', src, { type = 'success', title = 'Dispatch', description = ('Attached to %s'):format(call.id) })
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:openDispatchIncident', function(callId, role)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local call = getDispatchCall(callId)
  if not call then return end
  local incident = createIncident(src, {
    incidentType = call.incidentType,
    priority = call.priority,
    dispatchCallId = call.id,
    coords = call.coords,
    zone = call.zone,
    street = call.street,
    reason = call.title,
  })
  attachUnitToIncident(incident, src, role or 'primary')
  incident.status = 'enroute'
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:attachCurrentIncident', function(incidentId, role)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident then return end
  attachUnitToIncident(incident, src, role or 'secondary')
end)

RegisterNetEvent('az5pd:sim:assignRole', function(incidentId, targetSrc, role)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanSupervise(src, incident) then return end
  targetSrc = tonumber(targetSrc)
  if not targetSrc or targetSrc <= 0 then return end
  attachUnitToIncident(incident, targetSrc, role or 'secondary')
  TriggerClientEvent('az5pd:sim:notify', targetSrc, { type = 'inform', title = 'Scene Role', description = ('Assigned as %s on %s'):format(role or 'secondary', incident.id) })
  persistIncident(incident)
end)

RegisterNetEvent('az5pd:sim:setIncidentStatus', function(incidentId, status)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.status = trimText(status or incident.status, 32)
  addTimeline(incident, 'status', ('Status set to %s'):format(incident.status))
  if incident.dispatchCallId and incident.dispatchCallId ~= '' then
    local call = getDispatchCall(incident.dispatchCallId)
    if call then
      call.status = incident.status == 'cleared' and 'closed' or incident.status
      persistDispatchCall(call)
    end
  end
  local shift = ensureShift(src)
  shift.status = (incident.status == 'report' and 'report') or (incident.status == 'transport' and 'transport') or (incident.status == 'enroute' and 'enroute') or (incident.status == 'cleared' and '10-8') or shift.status
  persistIncident(incident)
  broadcastShift(src)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:setSceneFlag', function(incidentId, flag, value)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.scene = incident.scene or {}
  flag = trimText(flag, 32)
  if flag == '' then return end
  incident.scene[flag] = value == true
  addTimeline(incident, 'scene', ('%s set to %s'):format(flag, tostring(value == true)))
  if flag == 'safe' and value == true then incident.status = 'secured' end
  if flag == 'reportPending' and value == true then incident.status = 'report' end
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:recordStopReason', function(incidentId, reason)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.stop.reason = trimText(reason, 120)
  addTimeline(incident, 'stop', ('Reason: %s'):format(incident.stop.reason))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:runIdentityCheck', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.suspect.memory.contactCount = (incident.suspect.memory.contactCount or 0) + 1
  incident.stop.idOutcome = buildIdentityOutcome(incident)
  local outcome = incident.stop.idOutcome
  if outcome == 'fake_id' then incident.alerts[#incident.alerts + 1] = 'Subject may be using a false identity' end
  if outcome == 'refuses_to_identify' then incident.alerts[#incident.alerts + 1] = 'Subject is refusing to identify' end
  if outcome == 'suspended_license' then incident.alerts[#incident.alerts + 1] = 'Possible suspended license return' end
  if outcome == 'warrant_hit' then
    incident.probableCause[#incident.probableCause + 1] = 'Active warrant / hit'
    incident.court.failureToAppear = incident.court.failureToAppear or true
  end
  addTimeline(incident, 'idcheck', ('ID check result: %s'):format(outcome))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:runVehicleCheck', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local plateStatus, insurance, registration, vin = buildVehicleOutcome(incident)
  incident.vehicle.plateStatus = plateStatus
  incident.vehicle.insurance = insurance
  incident.vehicle.registration = registration
  incident.vehicle.vin = vin
  incident.vehicle.stolenIndicator = plateStatus == 'stolen_indicator'
  incident.vehicle.swappedPlate = plateStatus == 'swapped_plate'
  incident.vehicle.hiddenPlate = plateStatus == 'hidden_plate'
  incident.vehicle.ownerMismatch = incident.suspect.ownerMismatch == true
  if incident.suspect.ownerMismatch then incident.probableCause[#incident.probableCause + 1] = 'Owner / driver mismatch' end
  if incident.vehicle.stolenIndicator then incident.probableCause[#incident.probableCause + 1] = 'Stolen vehicle indicator' end
  addTimeline(incident, 'vehicle', ('Vehicle return: plate=%s insurance=%s registration=%s vin=%s'):format(plateStatus, insurance, registration, vin))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addCue', function(incidentId, cue)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  cue = trimText(cue, 100)
  if cue == '' then return end
  incident.suspect.cues = incident.suspect.cues or {}
  incident.suspect.cues[#incident.suspect.cues + 1] = cue
  incident.notes[#incident.notes + 1] = { by = ensureShift(src).officerName, text = ('Observed cue: %s'):format(cue), at = os.time(), category = 'cue' }
  addTimeline(incident, 'cue', cue)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addProbableCause', function(incidentId, cause)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  cause = trimText(cause, 120)
  if cause == '' then return end
  incident.probableCause[#incident.probableCause + 1] = cause
  addTimeline(incident, 'pc', cause)
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:setSearchDecision', function(incidentId, mode, legalBasis)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.search.mode = trimText(mode or 'none', 32)
  incident.search.legalBasis = trimText(legalBasis or '', 160)
  incident.search.consent = (incident.search.mode == 'consent_granted' and 'granted') or (incident.search.mode == 'consent_refused' and 'refused') or incident.search.consent
  if incident.search.mode ~= 'none' and incident.search.mode ~= 'consent_granted' and incident.search.legalBasis == '' and #(incident.probableCause or {}) == 0 then
    incident.accountability.unlawfulSearch = true
  end
  addTimeline(incident, 'search', ('Search mode %s'):format(incident.search.mode))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:recordInterview', function(incidentId, prompt, answer)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local entry = {
    by = ensureShift(src).officerName,
    prompt = trimText(prompt, 100),
    answer = trimText(answer, 200),
    at = os.time(),
  }
  incident.notes[#incident.notes + 1] = { by = entry.by, text = ('Interview: %s -> %s'):format(entry.prompt, entry.answer), at = entry.at, category = 'interview' }
  addTimeline(incident, 'interview', ('%s -> %s'):format(entry.prompt, entry.answer))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:recordBehaviorAction', function(incidentId, action)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  action = trimText(action, 32)
  local mem = incident.suspect.memory or {}
  if action == 'escalate' then
    mem.escalation = (mem.escalation or 0) + 1
    mem.cooperationTrend = (mem.cooperationTrend or 0) - 1
    incident.suspect.flightRisk = math.min(5, (incident.suspect.flightRisk or 1) + 1)
  elseif action == 'deescalate' then
    mem.escalation = math.max(0, (mem.escalation or 0) - 1)
    mem.cooperationTrend = (mem.cooperationTrend or 0) + 1
    incident.suspect.cooperation = math.min(5, (incident.suspect.cooperation or 1) + 1)
  elseif action == 'challenge' then
    incident.suspect.answerStyle = 'Inconsistent'
  elseif action == 'medical' then
    incident.suspect.mentalState = 'Medical Distress'
    incident.notes[#incident.notes + 1] = { by = ensureShift(src).officerName, text = 'Subject may be experiencing medical distress mistaken for intoxication.', at = os.time(), category = 'medical' }
  end
  incident.suspect.memory = mem
  addTimeline(incident, 'behavior', ('Officer action: %s'):format(action))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:recordDui', function(incidentId, payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  payload = type(payload) == 'table' and payload or {}
  incident.suspect.dui = incident.suspect.dui or {}
  incident.suspect.dui[#incident.suspect.dui + 1] = {
    test = trimText(payload.test or 'Unknown', 64),
    result = trimText(payload.result or 'Not recorded', 120),
    at = os.time(),
  }
  if tostring(payload.result or ''):lower():find('fail', 1, true) or tostring(payload.result or ''):lower():find('clue', 1, true) then
    incident.probableCause[#incident.probableCause + 1] = 'Impairment indicators'
  end
  addTimeline(incident, 'dui', ('%s: %s'):format(trimText(payload.test, 64), trimText(payload.result, 120)))
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addSharedNote', function(incidentId, text)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local note = { by = ensureShift(src).officerName, text = trimText(text, (Config.Sim and Config.Sim.maxNoteLength) or 360), at = os.time(), category = 'shared' }
  if note.text == '' then return end
  incident.sharedNotes[#incident.sharedNotes + 1] = note
  incident.notes[#incident.notes + 1] = deepCopy(note)
  addTimeline(incident, 'shared', note.text)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addObservation', function(incidentId, text)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local item = { by = ensureShift(src).officerName, text = trimText(text, 220), at = os.time() }
  if item.text == '' then return end
  incident.observations[#incident.observations + 1] = item
  addTimeline(incident, 'observation', item.text)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addWitness', function(incidentId, name, statement)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local witness = { name = trimText(name, 80), statement = trimText(statement, 220), at = os.time(), by = ensureShift(src).officerName }
  if witness.statement == '' then return end
  incident.witnesses[#incident.witnesses + 1] = witness
  addTimeline(incident, 'witness', ('%s: %s'):format(witness.name ~= '' and witness.name or 'Witness', witness.statement))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:addEvidence', function(incidentId, payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  payload = type(payload) == 'table' and payload or {}
  local item = {
    type = trimText(payload.type or 'Other', 48),
    description = trimText(payload.description or '', (Config.Sim and Config.Sim.maxEvidenceDescription) or 240),
    tag = trimText(payload.tag or '', 32),
    photo = payload.photo == true,
    serial = trimText(payload.serial or '', 64),
    category = trimText(payload.category or '', 64),
    at = os.time(),
    by = ensureShift(src).officerName,
  }
  if item.description == '' then item.description = item.type end
  incident.evidence[#incident.evidence + 1] = item
  if item.serial ~= '' then incident.vehicle.weaponSerialHit = item.serial end
  addTimeline(incident, 'evidence', ('%s logged'):format(item.type), item)
  local shift = ensureShift(src)
  shift.stats.evidence = (shift.stats.evidence or 0) + 1
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  broadcastShift(src)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:plainViewObservation', function(incidentId, text)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local plain = trimText(text, 140)
  if plain == '' then return end
  incident.vehicle.plainView = incident.vehicle.plainView or {}
  incident.vehicle.plainView[#incident.vehicle.plainView + 1] = plain
  addTimeline(incident, 'plainview', plain)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:requestBackup', function(incidentId, reason, role)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  local entry = { by = ensureShift(src).officerName, at = os.time(), reason = trimText(reason, (Config.Sim and Config.Sim.maxBackupReason) or 180), requestedRole = trimText(role or 'backup', 32) }
  incident.backupRequests[#incident.backupRequests + 1] = entry
  addTimeline(incident, 'backup', entry.reason ~= '' and entry.reason or 'Backup requested', entry)
  addRadio(incident, ('%s requests %s: %s'):format(ensureShift(src).callsign or ensureShift(src).officerName, entry.requestedRole, entry.reason ~= '' and entry.reason or 'No extra traffic'))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:panic', function(incidentId, message)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local shift = ensureShift(src)
  shift.status = 'panic'
  broadcastShift(src)
  GlobalState.az5pdEmergencyTraffic = {
    src = src,
    callsign = shift.callsign,
    officer = shift.officerName,
    incidentId = incidentId,
    message = trimText(message or 'Officer emergency traffic', 180),
    expiresAt = os.time() + (tonumber(((Config.Sim or {}).Dispatch or {}).emergencyTrafficSeconds or 60) or 60),
  }
  if incidentId and incidentId ~= '' then
    local incident = getIncident(incidentId)
    if incident then
      addTimeline(incident, 'panic', GlobalState.az5pdEmergencyTraffic.message)
      addRadio(incident, ('%s emergency traffic: %s'):format(shift.callsign or shift.officerName, GlobalState.az5pdEmergencyTraffic.message))
      persistIncident(incident)
      pushIncidentToParticipants(incident)
    end
  end
  TriggerClientEvent('az5pd:sim:panicBroadcast', -1, deepCopy(GlobalState.az5pdEmergencyTraffic))
end)

RegisterNetEvent('az5pd:sim:addBolo', function(payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  payload = type(payload) == 'table' and payload or {}
  local shift = ensureShift(src)
  local bolo = {
    id = nextBoloId(),
    category = trimText(payload.category or 'Vehicle', 24),
    label = trimText(payload.label or 'Unknown', 128),
    reason = trimText(payload.reason or 'Investigative interest', 255),
    createdBy = shift.callsign or shift.officerName,
    createdBySrc = src,
    createdAt = os.time(),
    expiresAt = payload.expiresHours and (os.time() + math.floor(tonumber(payload.expiresHours) * 3600)) or nil,
    active = true,
  }
  Sim.bolos[bolo.id] = bolo
  persistBolo(bolo)
  TriggerClientEvent('az5pd:sim:notify', -1, { type = 'inform', title = 'BOLO / APB', description = ('%s - %s'):format(bolo.category, bolo.label) })
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:clearBolo', function(boloId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local bolo = Sim.bolos[tostring(boloId)]
  if not bolo then return end
  bolo.active = false
  bolo.createdBySrc = src
  bolo.createdBy = bolo.createdBy or (ensureShift(src).callsign or ensureShift(src).officerName)
  persistBolo(bolo)
  refreshBridgeData(true)
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:requestWarrant', function(incidentId, payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  payload = type(payload) == 'table' and payload or {}
  local shift = ensureShift(src)
  local warrant = {
    id = nextWarrantId(),
    incidentId = incident.id,
    subjectKey = incident.subjectKey or getSubjectKey(incident.context),
    status = 'pending',
    requestedBy = shift.callsign or shift.officerName,
    approvedBy = '',
    charges = deepCopy(payload.charges or incident.charges or {}),
    notes = trimText(payload.notes or '', 220),
    createdAt = os.time(),
  }
  Sim.warrants[warrant.id] = warrant
  incident.court.warrants[#incident.court.warrants + 1] = warrant.id
  addTimeline(incident, 'warrant', ('Warrant requested: %s'):format(warrant.id))
  persistWarrant(warrant)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
  SetTimeout(20000, function()
    local existing = Sim.warrants[warrant.id]
    if not existing or existing.status ~= 'pending' then return end
    if #(incident.probableCause or {}) >= 1 or (incident.suspect and incident.suspect.warrantFlag) then
      existing.status = 'approved'
      existing.approvedBy = 'Judicial Review Sim'
    else
      existing.status = 'denied'
      existing.approvedBy = 'Judicial Review Sim'
    end
    persistWarrant(existing)
    TriggerClientEvent('az5pd:sim:notify', src, { type = existing.status == 'approved' and 'success' or 'warning', title = 'Warrant Review', description = ('%s %s'):format(existing.id, existing.status) })
    pushState(src)
  end)
end)

RegisterNetEvent('az5pd:sim:warrantDecision', function(warrantId, approved, notes)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  if not isSupervisor(src) then return end
  local warrant = Sim.warrants[tostring(warrantId)]
  if not warrant then return end
  local shift = ensureShift(src)
  warrant.status = approved == true and 'approved' or 'denied'
  warrant.approvedBy = shift.callsign or shift.officerName
  warrant.notes = trimText(notes or warrant.notes or '', 220)
  persistWarrant(warrant)
  pushState(src)
end)

RegisterNetEvent('az5pd:sim:addCharge', function(incidentId, charge)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  charge = trimText(charge, 120)
  if charge == '' then return end
  incident.charges[#incident.charges + 1] = charge
  addTimeline(incident, 'charge', charge)
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:autoRecommendCharges', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.charges = buildChargeRecommendations(incident)
  addTimeline(incident, 'charge', 'Charge recommendations refreshed')
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:generateReportPreview', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
  TriggerClientEvent('az5pd:sim:reportPreview', src, incident.id, deepCopy(incident.reportPreview))
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:generateSummary', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  incident.reportPreview = buildReportPreview(incident)
  incident.summary = { narrative = incident.reportPreview and incident.reportPreview.narrative or '' }
  persistIncident(incident)
  TriggerClientEvent('az5pd:sim:summary', src, incident.id, incident.summary.narrative)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:policyAction', function(incidentId, payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  payload = type(payload) == 'table' and payload or {}
  local incident = getIncident(incidentId)
  if not incident or not incidentCanSupervise(src, incident) then return end
  local entry = {
    id = nextPolicyId(),
    incidentId = incident.id,
    officerIdentifier = incident.officerIdentifier,
    actionType = trimText(payload.actionType or 'Policy Note', 32),
    summary = trimText(payload.summary or '', 220),
    createdBy = ensureShift(src).callsign or ensureShift(src).officerName,
    createdAt = os.time(),
  }
  Sim.policy[entry.id] = entry
  incident.accountability.supervisorNotes[#incident.accountability.supervisorNotes + 1] = entry
  if entry.actionType == 'Complaint' then
    local shift = getShift(incident.officerSrc)
    if shift then shift.stats.complaints = (shift.stats.complaints or 0) + 1 end
  elseif entry.actionType == 'Commendation' then
    local shift = getShift(incident.officerSrc)
    if shift then shift.stats.commendations = (shift.stats.commendations or 0) + 1 end
  elseif entry.actionType == 'Force Review' then
    incident.accountability.forceReview = true
  elseif entry.actionType == 'Evidence Mishandling' then
    incident.accountability.evidenceIssue = true
  end
  persistPolicy(entry)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:k9Request', function(incidentId, note)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  note = trimText(note or 'K9 requested', 160)
  addTimeline(incident, 'k9', note)
  TriggerEvent('az5pd:sim:k9Hook', incident.id, src, note)
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:handoffTransport', function(incidentId, targetSrc)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  targetSrc = tonumber(targetSrc)
  if not targetSrc or targetSrc <= 0 then return end
  attachUnitToIncident(incident, targetSrc, 'transport')
  incident.scene.transportPending = false
  addTimeline(incident, 'handoff', ('Transport handed to unit %s'):format(tostring(targetSrc)))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:startTrainingScenario', function(key)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local scenarios = (Config.Sim and Config.Sim.trainingScenarios) or {}
  local selected
  for i = 1, #scenarios do if scenarios[i].key == key then selected = scenarios[i] break end end
  if not selected then return end
  local shift = ensureShift(src)
  shift.trainingMode = true
  local incident = createIncident(src, {
    incidentType = selected.incidentType or 'training',
    priority = selected.priority or 3,
    reason = selected.label,
    trainingScenario = selected.key,
    zone = shift.zone,
    street = shift.lastStreet or shift.zone,
    coords = shift.lastCoords,
  })
  incident.training = { scenario = selected.key, label = selected.label, pass = nil, evaluation = '' }
  addTimeline(incident, 'training', ('Training scenario started: %s'):format(selected.label))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:reopenIncident', function(incidentId)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local old = getIncident(incidentId)
  if not old then return end
  local payload = {
    incidentType = old.incidentType,
    priority = old.priority,
    reason = old.stop and old.stop.reason or 'Follow-up',
    targetType = old.context and old.context.targetType,
    targetNetId = old.context and old.context.targetNetId,
    vehicleNetId = old.context and old.context.vehicleNetId,
    coords = old.context and old.context.coords,
    plate = old.context and old.context.plate,
    subjectLabel = old.context and old.context.subjectLabel,
    subjectModel = old.context and old.context.subjectModel,
    street = old.context and old.context.street,
    zone = old.context and old.context.zone,
  }
  local incident = createIncident(src, payload)
  incident.followup.relatedIncidents[#incident.followup.relatedIncidents + 1] = old.id
  incident.followup.caseReopenCount = tonumber(old.followup and old.followup.caseReopenCount or 0) + 1
  incident.incidentType = 'followup'
  addTimeline(incident, 'followup', ('Reopened from %s'):format(old.id))
  persistIncident(incident)
  pushIncidentToParticipants(incident)
end)

RegisterNetEvent('az5pd:sim:closeIncident', function(incidentId, payload)
  local src = source
  if not simEnabled() or not isAuthorized(src) then return end
  local incident = getIncident(incidentId)
  if not incident or not incidentCanEdit(src, incident) then return end
  payload = type(payload) == 'table' and payload or {}
  incident.status = 'cleared'
  incident.disposition = {
    type = trimText(payload.disposition or 'no_action', 32),
    narrative = trimText(payload.narrative or '', (Config.Sim and Config.Sim.maxNoteLength) or 360),
    at = os.time(),
  }
  if incident.disposition.type == 'arrest' and #(incident.probableCause or {}) == 0 and not (incident.court and incident.court.warrants and #incident.court.warrants > 0) then
    incident.accountability.badArrest = true
  end
  if incident.disposition.type == 'tow' then
    incident.scene.transportPending = false
  end
  incident.charges = (#(incident.charges or {}) == 0) and buildChargeRecommendations(incident) or incident.charges
  incident.reportPreview = buildReportPreview(incident)
  incident.summary = { narrative = incident.reportPreview and incident.reportPreview.narrative or '' }
  incident.score = scoreIncident(incident)
  addTimeline(incident, 'closed', incident.disposition.type)
  local shift = ensureShift(src)
  shift.currentIncidentId = nil
  shift.status = '10-8'
  if incident.disposition.type == 'warning' then shift.stats.warnings = (shift.stats.warnings or 0) + 1 end
  if incident.disposition.type == 'citation' then shift.stats.citations = (shift.stats.citations or 0) + 1 end
  if incident.disposition.type == 'arrest' then shift.stats.arrests = (shift.stats.arrests or 0) + 1 end
  shift.stats.violations = (shift.stats.violations or 0) + #(incident.score.warnings or {})
  shift.stats.reports = (shift.stats.reports or 0) + 1
  recalcAverageScore(shift.stats, incident.score.total)
  local weekly = getWeekly(shift.officerIdentifier)
  weekly.incidents = (weekly.incidents or 0) + 1
  weekly.reviews = (weekly.reviews or 0) + 1
  weekly.warnings = (weekly.warnings or 0) + #(incident.score.warnings or {})
  recalcAverageScore(weekly, incident.score.total)
  updateHistory(incident)
  if incident.subjectKey and Sim.personHistory[incident.subjectKey] then persistHistory(incident.subjectKey, Sim.personHistory[incident.subjectKey]) end
  if incident.context and incident.context.plate and Sim.vehicleHistory[incident.context.plate] then persistHistory('veh:' .. incident.context.plate, Sim.vehicleHistory[incident.context.plate]) end
  persistIncident(incident)
  persistOfficerScore(src)
  addRecent(shift.officerIdentifier, { id = incident.id, type = incident.incidentType, status = incident.status, createdAt = incident.createdAt, score = incident.score })
  if incident.dispatchCallId and incident.dispatchCallId ~= '' then
    local call = getDispatchCall(incident.dispatchCallId)
    if call then
      call.status = 'closed'
      persistDispatchCall(call)
    end
  end
  if incident.training and incident.training.scenario then
    incident.training.pass = incident.score.total >= 80 and incident.accountability.badArrest ~= true and incident.accountability.unlawfulSearch ~= true
    incident.training.evaluation = incident.training.pass and 'Pass' or 'Needs remediation'
  end
  broadcastShift(src)
  TriggerClientEvent('az5pd:sim:incidentClosed', src, buildIncidentSummary(incident))
  pushIncidentToParticipants(incident)
end)

AddEventHandler('playerDropped', function()
  local src = source
  if not src then return end
  local shift = Sim.shifts[src]
  if shift and shift.currentIncidentId then
    local incident = getIncident(shift.currentIncidentId)
    if incident and not incident.disposition then
      incident.disposition = { type = 'no_action', narrative = 'Officer disconnected before closeout.', at = os.time() }
      incident.reportPreview = buildReportPreview(incident)
      incident.score = scoreIncident(incident)
      persistIncident(incident)
    end
  end
  Sim.shifts[src] = nil
end)

AddEventHandler('police:issueCitation', function(netId, reason, fine, fullName)
  local src = source
  local shift = getShift(src)
  if not shift or not shift.currentIncidentId then return end
  local incident = getIncident(shift.currentIncidentId)
  if not incident then return end
  incident.notes[#incident.notes + 1] = { by = shift.officerName, text = ('Citation issued: %s ($%s)'):format(trimText(reason, 100), tostring(fine or 0)), at = os.time(), category = 'citation' }
  incident.charges[#incident.charges + 1] = trimText(reason, 100)
  addTimeline(incident, 'citation', trimText(reason, 100), { subject = trimText(fullName, 80), targetNetId = tostring(netId or '') })
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
end)

AddEventHandler('police:arrestPed', function(netId, fullName, dob, arrestContext)
  local src = source
  local shift = getShift(src)
  if not shift or not shift.currentIncidentId then return end
  local incident = getIncident(shift.currentIncidentId)
  if not incident then return end
  local ctx = type(arrestContext) == 'table' and arrestContext or {}
  incident.notes[#incident.notes + 1] = { by = shift.officerName, text = ('Arrest made for %s'):format(trimText(fullName, 80)), at = os.time(), category = 'arrest' }
  if ctx.reason and ctx.reason ~= '' then incident.probableCause[#incident.probableCause + 1] = trimText(ctx.reason, 100) end
  addTimeline(incident, 'arrest', ('Arrest made for %s'):format(trimText(fullName, 80)), { targetNetId = tostring(netId or ''), dob = trimText(dob, 32) })
  incident.reportPreview = buildReportPreview(incident)
  persistIncident(incident)
end)

CreateThread(function()
  ensureTables()
  refreshBridgeData(true)
  sdebug('expanded sim core loaded')
end)

CreateThread(function()
  while true do
    Wait(math.max(5, tonumber((getBridgeConfig().pollIntervalSeconds or 15)) or 15) * 1000)
    if simEnabled() then
      refreshBridgeData(true)
      for src, _ in pairs(Sim.shifts) do
        if GetPlayerName(src) then pushState(src) end
      end
    end
  end
end)

CreateThread(function()
  while true do
    Wait(10000)
    if GlobalState.az5pdEmergencyTraffic and GlobalState.az5pdEmergencyTraffic.expiresAt and os.time() >= GlobalState.az5pdEmergencyTraffic.expiresAt then
      GlobalState.az5pdEmergencyTraffic = nil
    end
    for id, call in pairs(Sim.dispatchCalls) do
      if call.status == 'pending' and call.escalationAt and os.time() >= call.escalationAt then
        call.priority = math.max(1, (call.priority or 3) - 1)
        call.escalationAt = os.time() + (tonumber(((Config.Sim or {}).Dispatch or {}).escalateAfterSeconds or 75) or 75)
        local updates = call.callerUpdates or {}
        call.callerUpdateIndex = math.min((call.callerUpdateIndex or 0) + 1, #updates)
        call.callerUpdate = updates[call.callerUpdateIndex] or ('Caller update on ' .. call.title)
        refreshDispatchSuggestions(call)
        persistDispatchCall(call)
      elseif call.status == 'claimed' and (call.callerUpdateIndex or 0) < #((call.callerUpdates or {})) then
        if not call.nextCallerUpdateAt then call.nextCallerUpdateAt = os.time() + 35 end
        if os.time() >= call.nextCallerUpdateAt then
          call.callerUpdateIndex = call.callerUpdateIndex + 1
          call.callerUpdate = (call.callerUpdates or {})[call.callerUpdateIndex] or call.callerUpdate
          call.nextCallerUpdateAt = os.time() + 35
          persistDispatchCall(call)
        end
      elseif call.status == 'closed' and os.time() - (call.createdAt or os.time()) > 300 then
        Sim.dispatchCalls[id] = nil
      end
    end
  end
end)

CreateThread(function()
  while true do
    Wait(math.max(30, tonumber((((Config.Sim or {}).Dispatch or {}).generationIntervalSeconds or 95))) * 1000)
    if simEnabled() and (((Config.Sim or {}).Dispatch or {}).autoGenerate ~= false) then
      autoGenerateDispatchCall()
    end
  end
end)
