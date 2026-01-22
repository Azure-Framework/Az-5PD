Config = Config or {}

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
  if C.cooldownBetweenSpawnsMs == nil then C.cooldownBetweenSpawnsMs = 45000 end

  if C.minDistanceFromPlayer == nil then C.minDistanceFromPlayer = 60.0 end
  if C.maxDistanceFromPlayer == nil then C.maxDistanceFromPlayer = 400.0 end
  if C.minDistanceBetweenCallouts == nil then C.minDistanceBetweenCallouts = 120.0 end

  if C.notifyOnGenerate == nil then C.notifyOnGenerate = true end

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

  if F.baseFleeChance == nil then F.baseFleeChance = 0.10 end
  if F.warrantFleeChance == nil then F.warrantFleeChance = 0.20 end
  if F.suspendedFleeChance == nil then F.suspendedFleeChance = 0.10 end

  if F.attackChance == nil then
    F.attackChance = tonumber(F.attackChanceIfWarrant) or tonumber(F.attackChanceIfSuspended) or 0.25
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
