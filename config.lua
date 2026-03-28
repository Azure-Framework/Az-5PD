Config = Config or {}

Config.Jobs = Config.Jobs or {}
do
  local J = Config.Jobs
  if J.requireJob == nil then J.requireJob = true end
  J.allowed = J.allowed or {
    'bcso',
    'sheriff',
    'lspd',
    'police',
    'sast',
    'state',
    'trooper',
    'leo'
  }
  J.supervisors = J.supervisors or {
    'bcso_supervisor',
    'sheriff_supervisor',
    'lspd_supervisor',
    'police_supervisor',
    'sast_supervisor',
    'state_supervisor',
    'command',
    'dispatch'
  }
end

Config.Debug = (Config.Debug == true)

Config.AllowedJobs = Config.AllowedJobs or {
  "police",
  "ambulance",
  "fire",
}

Config.Callouts = Config.Callouts or {}
do
  local C = Config.Callouts

  if C.generatorEnabled == nil then C.generatorEnabled = true end

  if C.useServerCreation == nil then C.useServerCreation = true end

  C.calltimeRange = C.calltimeRange or { min = 2, max = 7, unit = "minutes" }
  if C.calltimeRange.min == nil then C.calltimeRange.min = 2 end
  if C.calltimeRange.max == nil then C.calltimeRange.max = 7 end
  if C.calltimeRange.unit == nil then C.calltimeRange.unit = "minutes" end -- "minutes" or "seconds"

  if C.maxSimultaneous == nil then C.maxSimultaneous = 6 end
  if C.cooldownBetweenSpawnsMs == nil then C.cooldownBetweenSpawnsMs = 128000 end

  if C.minDistanceFromPlayer == nil then C.minDistanceFromPlayer = 60.0 end
  if C.maxDistanceFromPlayer == nil then C.maxDistanceFromPlayer = 400.0 end
  if C.minDistanceBetweenCallouts == nil then C.minDistanceBetweenCallouts = 120.0 end

  if C.notifyOnGenerate == nil then C.notifyOnGenerate = true end

  if C.serverExpireSeconds == nil then C.serverExpireSeconds = 180 end
  if C.syncToMDT == nil then C.syncToMDT = true end
  if C.mdtResource == nil then C.mdtResource = '' end
  C.mdtResourceFallbacks = C.mdtResourceFallbacks or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
  if C.syncUnitStatusToMDT == nil then C.syncUnitStatusToMDT = true end

  C.timeOfDay = C.timeOfDay or {}
  C.timeOfDay.byHour = C.timeOfDay.byHour or {
    [0]=1.30,[1]=1.30,[2]=1.30,[3]=1.25,[4]=1.20,
    [5]=1.10,[6]=1.00,[7]=1.00,[8]=0.95,[9]=0.95,[10]=0.95,
    [11]=1.00,[12]=1.00,[13]=1.00,[14]=1.00,[15]=1.05,
    [16]=1.05,[17]=1.10,[18]=1.15,[19]=1.20,[20]=1.25,[21]=1.30,[22]=1.35,[23]=1.35
  }
  if C.timeOfDay.dawn  == nil then C.timeOfDay.dawn  = 1.10 end -- 05–07
  if C.timeOfDay.day   == nil then C.timeOfDay.day   = 1.00 end -- 08–18
  if C.timeOfDay.dusk  == nil then C.timeOfDay.dusk  = 1.15 end -- 19–21
  if C.timeOfDay.night == nil then C.timeOfDay.night = 1.30 end -- 22–04

  C.weatherWeights = C.weatherWeights or {
    EXTRASUNNY=1.00, CLEAR=1.00, CLOUDS=0.95, OVERCAST=0.90,
    SMOG=0.90, FOGGY=0.85, CLEARING=0.95, RAIN=1.15,
    THUNDER=1.30, NEUTRAL=1.00, SNOW=0.70, SNOWLIGHT=0.75,
    BLIZZARD=0.60, XMAS=0.75, HALLOWEEN=1.00
  }

  C.dayOfWeekWeights = C.dayOfWeekWeights or { [0]=1.05, [1]=1.00, [2]=1.00, [3]=1.00, [4]=1.05, [5]=1.20, [6]=1.25 }

  C.quietHours = C.quietHours or {} -- e.g. { [4]=true } to pause at 4am
  C.blacklistWeather = C.blacklistWeather or { BLIZZARD = true } -- skip spawns entirely in these weathers
end

Config.Wander = Config.Wander or {}
do
  local W = Config.Wander
  if W.driveSpeed == nil then W.driveSpeed = 20.0 end
  if W.driveStyle == nil then W.driveStyle = 786603 end
  if W.driveToCoordSpeed == nil then W.driveToCoordSpeed = 25.0 end
end

Config.Timings = Config.Timings or {}
do
  local T = Config.Timings
  if T.shortWait == nil then T.shortWait = 50 end
  if T.attackDelay == nil then T.attackDelay = 300 end
  if T.checkDelay == nil then T.checkDelay = 600 end
  if T.keepTaskResetDelay == nil then T.keepTaskResetDelay = 800 end
  if T.cleanupDelay == nil then T.cleanupDelay = 400 end
  if T.defaultWait == nil then T.defaultWait = 1000 end
  if T.postPullCheck == nil then T.postPullCheck = 600 end
end

Config.Flee = Config.Flee or {}
do
  local F = Config.Flee

  if F.enable == nil then F.enable = true end

  if F.baseFleeChance == nil then F.baseFleeChance = 0.05 end
  if F.warrantFleeChance == nil then F.warrantFleeChance = 0.08 end
  if F.suspendedFleeChance == nil then F.suspendedFleeChance = 0.04 end

  if F.attackChance == nil then
    F.attackChance = tonumber(F.attackChanceIfWarrant) or tonumber(F.attackChanceIfSuspended) or 0.06
  end

  if F.fleeDriveSpeed == nil then F.fleeDriveSpeed = 100.0 end
  if F.fleeDriveStyle == nil then F.fleeDriveStyle = 786603 end
  if F.driverAbility == nil then F.driverAbility = 1.0 end
  if F.driverAggressiveness == nil then F.driverAggressiveness = 1.0 end

  if F.weaponName == nil then F.weaponName = "WEAPON_PISTOL" end
  if F.attackAmmo == nil then F.attackAmmo = 45 end
  if F.attackNotify == nil then F.attackNotify = true end

  if F.blipSprite == nil then F.blipSprite = 225 end
  if F.blipColour == nil then F.blipColour = 1 end
  if F.chaseDistance == nil then F.chaseDistance = 120.0 end
  if F.chaseTimeout == nil then F.chaseTimeout = 15 end
end

Config.Messages = Config.Messages or {}
do
  local M = Config.Messages

  M.pull_fail = M.pull_fail or { title = "Pull-Over", text = "Driver fled!", style = "error" }

  M.npc_attack = M.npc_attack or { title = "Threat", text = "Driver is attacking!", style = "error" }
  M.rel_ok     = M.rel_ok     or { title = "Released", text = "Ped is free.", style = "success" }
end

Config.Enable = Config.Enable or {}
do
  local E = Config.Enable
  if E.fleeSystem == nil then E.fleeSystem = true end
end


Config.MDT = Config.MDT or {}
do
  local M = Config.MDT
  if M.preferExternalWhenAvailable == nil then M.preferExternalWhenAvailable = true end
  if M.openExternalOnCheckId == nil then M.openExternalOnCheckId = false end
  M.externalResourceNames = M.externalResourceNames or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
end

Config.Immersion = Config.Immersion or {}
do
  local I = Config.Immersion
  if I.enabled == nil then I.enabled = true end
  if I.requirePoliceJob == nil then I.requirePoliceJob = true end
  if I.scanRadius == nil then I.scanRadius = 55.0 end
  if I.scanIntervalMs == nil then I.scanIntervalMs = 2500 end
  if I.maxNearbyPeds == nil then I.maxNearbyPeds = 18 end
  if I.debugNotify == nil then I.debugNotify = false end

  I.suspicion = I.suspicion or {}
  if I.suspicion.baseChance == nil then I.suspicion.baseChance = 0.02 end
  if I.suspicion.onFootMultiplier == nil then I.suspicion.onFootMultiplier = 0.02 end
  if I.suspicion.vehicleMultiplier == nil then I.suspicion.vehicleMultiplier = 0.02 end
  if I.suspicion.nightMultiplier == nil then I.suspicion.nightMultiplier = 0.05 end
  if I.suspicion.weaponDrawnMultiplier == nil then I.suspicion.weaponDrawnMultiplier = 0.01 end
  if I.suspicion.maxChance == nil then I.suspicion.maxChance = 0.22 end

  I.traits = I.traits or {}
  if I.traits.illegalItemsChance == nil then I.traits.illegalItemsChance = 0.48 end
  if I.traits.warrantChance == nil then I.traits.warrantChance = 0.22 end
  if I.traits.suspendedChance == nil then I.traits.suspendedChance = 0.14 end
  if I.traits.drunkChance == nil then I.traits.drunkChance = 0.20 end
  if I.traits.highChance == nil then I.traits.highChance = 0.24 end
  if I.traits.nervousChance == nil then I.traits.nervousChance = 0.40 end
  if I.traits.runChance == nil then I.traits.runChance = 0.44 end
  if I.traits.hideChance == nil then I.traits.hideChance = 0.28 end
  if I.traits.driveAwayChance == nil then I.traits.driveAwayChance = 0.65 end
  if I.traits.attackChanceBoost == nil then I.traits.attackChanceBoost = 0.15 end

  I.behavior = I.behavior or {}
  if I.behavior.reactionDistanceOnFoot == nil then I.behavior.reactionDistanceOnFoot = 18.0 end
  if I.behavior.reactionDistanceVehicle == nil then I.behavior.reactionDistanceVehicle = 28.0 end
  if I.behavior.cooldownMs == nil then I.behavior.cooldownMs = 20000 end
  if I.behavior.hideDistance == nil then I.behavior.hideDistance = 20.0 end
  if I.behavior.enableAmbientReactions == nil then I.behavior.enableAmbientReactions = true end
  if I.behavior.enableDrunkClipset == nil then I.behavior.enableDrunkClipset = true end
  if I.behavior.drunkClipset == nil then I.behavior.drunkClipset = 'move_m@drunk@verydrunk' end

  I.vehicleContext = I.vehicleContext or {}
  if I.vehicleContext.ownerMismatchBase == nil then I.vehicleContext.ownerMismatchBase = 0.12 end
  if I.vehicleContext.ownerMismatchWanted == nil then I.vehicleContext.ownerMismatchWanted = 0.40 end
  if I.vehicleContext.ownerMismatchIllegalItems == nil then I.vehicleContext.ownerMismatchIllegalItems = 0.28 end
  if I.vehicleContext.ownerMismatchSuspended == nil then I.vehicleContext.ownerMismatchSuspended = 0.22 end
  if I.vehicleContext.ownerMismatchImpaired == nil then I.vehicleContext.ownerMismatchImpaired = 0.18 end
  if I.vehicleContext.noRegistrationBase == nil then I.vehicleContext.noRegistrationBase = 0.03 end
  if I.vehicleContext.noRegistrationWanted == nil then I.vehicleContext.noRegistrationWanted = 0.18 end
  if I.vehicleContext.noRegistrationIllegalItems == nil then I.vehicleContext.noRegistrationIllegalItems = 0.12 end
  if I.vehicleContext.suspendedRegistrationBase == nil then I.vehicleContext.suspendedRegistrationBase = 0.02 end
  if I.vehicleContext.suspendedRegistrationSuspended == nil then I.vehicleContext.suspendedRegistrationSuspended = 0.18 end
  if I.vehicleContext.expiredRegistrationBase == nil then I.vehicleContext.expiredRegistrationBase = 0.08 end
  if I.vehicleContext.expiredRegistrationWanted == nil then I.vehicleContext.expiredRegistrationWanted = 0.14 end
  if I.vehicleContext.expiredRegistrationIllegalItems == nil then I.vehicleContext.expiredRegistrationIllegalItems = 0.12 end
end


Config.PedCustody = Config.PedCustody or {}
do
  local P = Config.PedCustody

  P.cuffReapplyIntervalMs = tonumber(P.cuffReapplyIntervalMs) or 250
  P.groundHoldMs = tonumber(P.groundHoldMs) or 1500
  P.groundHoldCooldownMs = tonumber(P.groundHoldCooldownMs) or 900

  P.drag = P.drag or {}
  if P.drag.offsetX == nil then P.drag.offsetX = 0.22 end
  if P.drag.offsetY == nil then P.drag.offsetY = 0.54 end
  if P.drag.offsetZ == nil then P.drag.offsetZ = -0.02 end
  if P.drag.rotX == nil then P.drag.rotX = 0.0 end
  if P.drag.rotY == nil then P.drag.rotY = 0.0 end
  if P.drag.rotZ == nil then P.drag.rotZ = 0.0 end
  if P.drag.useBone == nil then P.drag.useBone = 0 end
  if P.drag.disableCollision == nil then P.drag.disableCollision = true end

  P.seating = P.seating or {}
  if P.seating.preferTaskEnterWarp == nil then P.seating.preferTaskEnterWarp = true end
  if P.seating.fallbackToTaskWarp == nil then P.seating.fallbackToTaskWarp = true end
  if P.seating.fallbackToSetPedIntoVehicle == nil then P.seating.fallbackToSetPedIntoVehicle = true end
  if P.seating.directEnterWaitMs == nil then P.seating.directEnterWaitMs = 350 end
end

Config.GunpointCompliance = Config.GunpointCompliance or {}
do
  local G = Config.GunpointCompliance

  if G.enabled == nil then G.enabled = true end
  if G.groupRadius == nil then G.groupRadius = 12.0 end
  if G.maxGroupSize == nil then G.maxGroupSize = 5 end
  if G.maxNearbyCandidates == nil then G.maxNearbyCandidates = 10 end
  if G.includePassengers == nil then G.includePassengers = true end
  if G.includeNearbyCombatants == nil then G.includeNearbyCombatants = true end
  if G.baseSingleResistChance == nil then G.baseSingleResistChance = 0.14 end
  if G.groupOneFightsChance == nil then G.groupOneFightsChance = 0.42 end
  if G.delayMinMs == nil then G.delayMinMs = 120 end
  if G.delayMaxMs == nil then G.delayMaxMs = 520 end
  if G.cooldownMs == nil then G.cooldownMs = 4500 end
end

Config.ArrestAccountability = Config.ArrestAccountability or {}
do
  local A = Config.ArrestAccountability

  if A.enabled == nil then A.enabled = true end
  if A.maxStrikes == nil then A.maxStrikes = 3 end
  if A.action == nil then A.action = 'cooldown' end -- cooldown | remove
  if A.cooldownMinutes == nil then A.cooldownMinutes = 30 end
  if A.dropOnRemove == nil then A.dropOnRemove = true end
  if A.blockRemovedOfficers == nil then A.blockRemovedOfficers = true end
  if A.notifyOfficer == nil then A.notifyOfficer = true end

  A.grounds = A.grounds or {}
  if A.grounds.activeWarrant == nil then A.grounds.activeWarrant = true end
  if A.grounds.wantedFlag == nil then A.grounds.wantedFlag = true end
  if A.grounds.suspendedLicense == nil then A.grounds.suspendedLicense = true end
  if A.grounds.expiredLicense == nil then A.grounds.expiredLicense = true end
  if A.grounds.noValidLicense == nil then A.grounds.noValidLicense = true end
  if A.grounds.illegalItems == nil then A.grounds.illegalItems = true end
  if A.grounds.alcoholImpairment == nil then A.grounds.alcoholImpairment = true end
  if A.grounds.drugImpairment == nil then A.grounds.drugImpairment = true end

  A.messages = A.messages or {}
  A.messages.invalidArrest = A.messages.invalidArrest or 'Invalid arrest: no configured arrest grounds were found. Strike added.'
  A.messages.cooldown = A.messages.cooldown or 'You have been placed on cooldown from police actions due to repeated invalid arrests.'
  A.messages.removed = A.messages.removed or 'You have been removed from police actions due to repeated invalid arrests.'
end
