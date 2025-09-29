Config = Config or {}

Config.AllowedJobs = {
    "police",
    "ambulance",
    "fire"
}


Config.Wander = Config.Wander or {
  driveSpeed = 20.0,
  driveStyle = 786603,
  driveToCoordSpeed = 25.0,
}

Config.Timings = Config.Timings or {
  shortWait = 50,
  attackDelay = 300,
  checkDelay = 600,
  keepTaskResetDelay = 800,
  cleanupDelay = 400,
  defaultWait = 1000,
  postPullCheck = 600,
}
Config.Flee = Config.Flee or {
  enable = true,
  baseFleeChance = 0.20,
  warrantFleeChance = 0.60,
  suspendedFleeChance = 0.50,
  attackChanceIfWarrant = 0.25,
  attackChanceIfSuspended = 0.15,
  fleeDriveSpeed = 40.0,
  fleeDriveStyle = 786603,
  driverAbility = 1.0,
  driverAggressiveness = 1.0,
  weaponName = "WEAPON_PISTOL",
  attackAmmo = 45,
  attackNotify = true,

  -- new options for blip/countdown:
  blipSprite = 225,   -- default blip icon (225 is vehicle)
  blipColour = 1,     -- blip colour
  chaseDistance = 120.0, -- meters before countdown starts
  chaseTimeout = 15,     -- seconds until chase stops once target is out of range
}

Config.Messages = Config.Messages or {
  pull_fail = { title = "Pull-Over", text = "Driver fled!", style = "error" },
  npc_attack = { title = "Threat", text = "Driver is attacking!", style = "error" },
  rel_ok = { title = "Released", text = "Ped is free.", style = "success" },
}

Config.Enable = Config.Enable or {
  fleeSystem = true,
}

-- ======= CALLOUT / GENERATOR SETTINGS =======
-- Defaults: calltimeRange uses MINUTES by default (min/max are treated as minutes).
Config.Callouts = Config.Callouts or {
  -- master toggle for the local generator (set false if server drives callouts)
  generatorEnabled = true,

  -- If true, the client will ask the server to create a broadcast callout
  -- instead of creating purely-local test callouts. Adapt your server events accordingly.
  useServerCreation = false,

  -- Range to wait between generated callouts. Default numbers are in minutes.
  -- You can set unit = "seconds" to treat min/max as seconds instead.
  calltimeRange = {
    min = 1,        -- 1 minute (default)
    max = 3,        -- 3 minutes (default)
    unit = "minutes" -- "minutes" or "seconds"
  },



  -- spawn behavior for local generator (client chooses coords around player)
  minDistanceFromPlayer = 60.0,   -- meters (ensure callouts don't spawn on top of player)
  maxDistanceFromPlayer = 400.0,  -- meters

  -- Whether the client shows a notify when it generates a local callout.
  notifyOnGenerate = true,
}

-- Helper: how to convert calltimeRange to milliseconds in your client thread:
-- local r = Config.Callouts.calltimeRange
-- local unitMultiplier = (r.unit == "seconds") and 1000 or 60000 -- minutes -> ms by default
-- local waitMs = math.random(r.min, r.max) * unitMultiplier
-- Citizen.Wait(waitMs) -- use waitMs in your generator thread
