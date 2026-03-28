Config = Config or {}
Config.Sim = Config.Sim or {}

do
  local S = Config.Sim

  if S.enabled == nil then S.enabled = true end
  if S.menuCommand == nil then S.menuCommand = 'az5pdsim' end
  if S.menuKey == nil then S.menuKey = 'F9' end
  if S.targetDistance == nil then S.targetDistance = 3.0 end
  if S.maxRecentIncidents == nil then S.maxRecentIncidents = 12 end
  if S.maxNoteLength == nil then S.maxNoteLength = 360 end
  if S.maxEvidenceDescription == nil then S.maxEvidenceDescription = 240 end
  if S.maxBackupReason == nil then S.maxBackupReason = 180 end
  if S.defaultCallsign == nil then S.defaultCallsign = 'UNIT' end
  if S.overlayEnabled == nil then S.overlayEnabled = true end
  if S.overlayHints == nil then S.overlayHints = true end
  if S.overlayCard == nil then S.overlayCard = true end
  if S.useTargetShortcuts == nil then S.useTargetShortcuts = true end
  if S.statusPingMs == nil then S.statusPingMs = 12000 end
  if S.openMainFromF6Branch == nil then S.openMainFromF6Branch = true end

  S.Framework = S.Framework or {}
  if S.Framework.requirePoliceJob == nil then S.Framework.requirePoliceJob = true end
  S.Framework.allowedJobs = S.Framework.allowedJobs or { 'police', 'sheriff', 'state', 'trooper', 'leo' }
  S.Framework.supervisorJobs = S.Framework.supervisorJobs or { 'police_supervisor', 'sheriff_supervisor', 'state_supervisor', 'command', 'dispatch' }

  S.MDTBridge = S.MDTBridge or {}
  if S.MDTBridge.enabled == nil then S.MDTBridge.enabled = true end
  if S.MDTBridge.preferExternalTables == nil then S.MDTBridge.preferExternalTables = true end
  if S.MDTBridge.createTablesIfMissing == nil then S.MDTBridge.createTablesIfMissing = true end
  if S.MDTBridge.pollIntervalSeconds == nil then S.MDTBridge.pollIntervalSeconds = 15 end
  if S.MDTBridge.mirrorActionLog == nil then S.MDTBridge.mirrorActionLog = true end
  S.MDTBridge.resourceNames = S.MDTBridge.resourceNames or (((Config or {}).MDT or {}).externalResourceNames) or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
  if S.MDTBridge.callsTable == nil then S.MDTBridge.callsTable = 'mdt_calls' end
  if S.MDTBridge.bolosTable == nil then S.MDTBridge.bolosTable = 'mdt_bolos' end
  if S.MDTBridge.actionLogTable == nil then S.MDTBridge.actionLogTable = 'mdt_action_log' end

  S.Dispatch = S.Dispatch or {}
  if S.Dispatch.autoGenerate == nil then S.Dispatch.autoGenerate = true end
  if S.Dispatch.maxPending == nil then S.Dispatch.maxPending = 4 end
  if S.Dispatch.generationIntervalSeconds == nil then S.Dispatch.generationIntervalSeconds = 95 end
  if S.Dispatch.escalateAfterSeconds == nil then S.Dispatch.escalateAfterSeconds = 75 end
  if S.Dispatch.maxCallerUpdates == nil then S.Dispatch.maxCallerUpdates = 2 end
  if S.Dispatch.autoSuggestUnits == nil then S.Dispatch.autoSuggestUnits = true end
  if S.Dispatch.emergencyTrafficSeconds == nil then S.Dispatch.emergencyTrafficSeconds = 60 end

  S.shiftStatuses = S.shiftStatuses or {
    { key = '10-8', label = '10-8 Available' },
    { key = 'traffic', label = 'Traffic Stop' },
    { key = 'enroute', label = 'En Route' },
    { key = 'onscene', label = 'On Scene' },
    { key = 'investigating', label = 'Investigating' },
    { key = 'transport', label = 'Transport' },
    { key = 'report', label = 'Writing Report' },
    { key = 'panic', label = 'Emergency Traffic' },
    { key = '10-7', label = '10-7 Unavailable' },
  }

  S.incidentStatuses = S.incidentStatuses or {
    { key = 'pending', label = 'Pending / Not Assigned' },
    { key = 'dispatched', label = 'Dispatched' },
    { key = 'enroute', label = 'En Route' },
    { key = 'arrived', label = 'Arrived' },
    { key = 'onscene', label = 'On Scene' },
    { key = 'unsafe', label = 'Scene Unsafe' },
    { key = 'secured', label = 'Scene Secured' },
    { key = 'detention', label = 'Detention / Interview' },
    { key = 'search', label = 'Search / Evidence' },
    { key = 'transport', label = 'Transport Pending' },
    { key = 'report', label = 'Report Pending' },
    { key = 'followup', label = 'Follow-Up' },
    { key = 'cleared', label = 'Cleared / Code 4' },
  }

  S.incidentTypes = S.incidentTypes or {
    { key = 'traffic_stop', label = 'Traffic Stop' },
    { key = 'felony_stop', label = 'Felony Stop' },
    { key = 'suspicious_person', label = 'Suspicious Person' },
    { key = 'suspicious_vehicle', label = 'Suspicious Vehicle' },
    { key = 'disturbance', label = 'Disturbance' },
    { key = 'welfare_check', label = 'Welfare Check' },
    { key = 'followup', label = 'Follow-Up / Supplemental' },
    { key = 'training', label = 'Training Scenario' },
  }

  S.dispositions = S.dispositions or {
    { key = 'warning', label = 'Warning' },
    { key = 'citation', label = 'Citation' },
    { key = 'tow', label = 'Tow / Impound' },
    { key = 'arrest', label = 'Arrest' },
    { key = 'transport', label = 'Transported' },
    { key = 'no_action', label = 'No Action' },
    { key = 'unfounded', label = 'Unfounded / GOA' },
  }

  S.roles = S.roles or {
    { key = 'primary', label = 'Primary' },
    { key = 'secondary', label = 'Secondary' },
    { key = 'cover', label = 'Cover Officer' },
    { key = 'supervisor', label = 'Supervisor' },
    { key = 'transport', label = 'Transport Unit' },
    { key = 'evidence', label = 'Evidence / Follow-Up' },
  }

  S.cues = S.cues or {
    'Nervous / shaking hands',
    'Avoiding eye contact',
    'Conflicting story',
    'Strong odor of alcohol',
    'Odor of narcotics',
    'Open container visible',
    'Weapon in plain view',
    'Bulge / waistband check',
    'Passenger interrupting',
    'Hands concealed / refusal',
    'Vehicle ownership mismatch',
    'Attempts to leave scene',
    'Confused / possible medical issue',
    'Rapid speech / stimulant indicators',
    'Slow responses / impairment indicators',
    'Refusing to identify',
  }

  S.evidenceTypes = S.evidenceTypes or {
    'Photo Marker',
    'Witness Statement',
    'Officer Observation',
    'Weapon',
    'Weapon Serial Check',
    'Narcotics',
    'Open Container',
    'Shell Casing',
    'Blood / DNA',
    'Property',
    'Vehicle Damage',
    'Bag / Tag',
    'Contraband',
    'Tow / Impound Sheet',
    'Other',
  }

  S.probableCauseOptions = S.probableCauseOptions or {
    'Observed traffic violation',
    'Reasonable suspicion',
    'Probable cause search',
    'Visible contraband',
    'Officer safety frisk',
    'Active warrant / hit',
    'Consent search',
    'Impairment indicators',
    'Owner/driver mismatch',
    'Stolen vehicle indicator',
    'Refusal / obstruction',
  }

  S.stopReasons = S.stopReasons or {
    'Speeding',
    'Reckless driving',
    'Equipment violation',
    'Expired registration',
    'No insurance return',
    'Plate mismatch / switched plate',
    'BOLO / APB match',
    'Suspicious vehicle',
    'DUI indicators',
  }

  S.searchModes = S.searchModes or {
    { key = 'none', label = 'No Search' },
    { key = 'consent_granted', label = 'Consent Search Granted' },
    { key = 'consent_refused', label = 'Consent Refused' },
    { key = 'probable_cause', label = 'Probable Cause Search' },
    { key = 'incident_to_arrest', label = 'Search Incident to Arrest' },
    { key = 'protective_frisk', label = 'Protective Frisk' },
  }

  S.duiTests = S.duiTests or {
    'HGN',
    'Walk and Turn',
    'One Leg Stand',
    'Preliminary Breath Test',
    'Drug Recognition Notes',
  }

  S.contrabandCategories = S.contrabandCategories or {
    'Marijuana',
    'Methamphetamine',
    'Cocaine',
    'Heroin / Opioids',
    'Prescription Pills',
    'Open Alcohol',
    'Burglary Tools',
    'Unserialized Firearm',
    'Illegal Knife',
    'Stolen Property',
    'Cash / Packaging',
  }

  S.interviewPrompts = S.interviewPrompts or {
    'Where are you coming from?',
    'Who owns this vehicle?',
    'Do you know why I stopped you?',
    'Have you had anything to drink tonight?',
    'Any weapons or contraband in the vehicle?',
    'Do you consent to a search?',
  }

  S.forceOptions = S.forceOptions or {
    'Presence / verbal only',
    'Control hold / escort',
    'Taser / less-lethal',
    'Impact / OC',
    'Lethal force',
  }

  S.policyActions = S.policyActions or {
    'Complaint',
    'Commendation',
    'Force Review',
    'Evidence Mishandling',
    'Policy Note',
    'Supervisor Coaching',
  }

  S.trainingScenarios = S.trainingScenarios or {
    { key = 'academy_stop', label = 'Academy Traffic Stop', incidentType = 'traffic_stop', priority = 3 },
    { key = 'academy_dui', label = 'Academy DUI Investigation', incidentType = 'traffic_stop', priority = 2 },
    { key = 'academy_domestic_followup', label = 'Academy Follow-Up', incidentType = 'followup', priority = 3 },
    { key = 'academy_felony_stop', label = 'Academy Felony Stop', incidentType = 'felony_stop', priority = 1 },
  }

  S.patrolGoals = S.patrolGoals or {
    'Complete 3 traffic stops',
    'Complete 1 DUI workflow',
    'Document 2 evidence items',
    'Handle 1 shared scene with another unit',
    'Close all scenes with a finished report preview',
  }

  S.areaProfiles = S.areaProfiles or {
    { key = 'downtown', label = 'Downtown', center = { x = 215.0, y = -920.0 }, radius = 700.0, hotTypes = { 'traffic_stop', 'disturbance', 'suspicious_person' } },
    { key = 'mirror_park', label = 'Mirror Park / East LS', center = { x = 1070.0, y = -450.0 }, radius = 700.0, hotTypes = { 'traffic_stop', 'welfare_check', 'suspicious_vehicle' } },
    { key = 'south_los_santos', label = 'South Los Santos', center = { x = 210.0, y = -1700.0 }, radius = 850.0, hotTypes = { 'disturbance', 'suspicious_person', 'suspicious_vehicle' } },
    { key = 'vinewood', label = 'Vinewood / Hollywood', center = { x = 350.0, y = 250.0 }, radius = 850.0, hotTypes = { 'traffic_stop', 'disturbance', 'welfare_check' } },
    { key = 'county', label = 'Blaine County', center = { x = 1600.0, y = 3600.0 }, radius = 2400.0, hotTypes = { 'traffic_stop', 'suspicious_vehicle', 'welfare_check' } },
  }

  S.dispatchCatalog = S.dispatchCatalog or {
    { title = 'Suspicious Vehicle', type = 'suspicious_vehicle', priorities = { 2, 3 }, updates = { 'Caller says the vehicle has been idling for over 10 minutes.', 'Caller believes occupants are watching nearby houses.' } },
    { title = 'Disturbance', type = 'disturbance', priorities = { 1, 2 }, updates = { 'Caller reports yelling escalating in volume.', 'A second caller reports items being thrown outside.' } },
    { title = 'Welfare Check', type = 'welfare_check', priorities = { 2, 3 }, updates = { 'Caller has not been able to make contact with the subject.', 'Lights are on inside, but no response at the door.' } },
    { title = 'Erratic Driver', type = 'traffic_stop', priorities = { 1, 2 }, updates = { 'Vehicle was seen swerving across lanes.', 'Caller now reports the driver nearly struck a curb.' } },
  }

  S.chargeRecommendations = S.chargeRecommendations or {
    { match = 'alcohol', label = 'DUI / DWI' },
    { match = 'stolen', label = 'Possession of Stolen Vehicle' },
    { match = 'warrant', label = 'Warrant Service / Arrest' },
    { match = 'narcotic', label = 'Possession of Controlled Substance' },
    { match = 'weapon', label = 'Weapons Offense' },
    { match = 'obstruction', label = 'Obstruction / Resisting' },
    { match = 'suspended', label = 'Driving on Suspended License' },
  }

  S.quickHints = S.quickHints or {
    'Record the reason for the stop before escalating.',
    'Add probable cause or consent before searching.',
    'Use a shared note so attached units see the same scene picture.',
    'Generate the report preview before clearing the scene.',
  }
end
