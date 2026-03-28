
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

local function isJobAllowed(job)
    if not job then return false end
    for _, allowed in ipairs(Config.AllowedJobs) do
        if job == allowed then return true end
    end
    return false
end

local function getPlayerJobFromServer(cb)
    assert(type(cb) == "function", "getPlayerJobFromServer requires callback")

    local evtName = "AzFR:responsePlayerJob"
    RegisterNetEvent(evtName)
    local handlerId
    handlerId = AddEventHandler(evtName, function(job)
        RemoveEventHandler(handlerId)
        cb(job)
    end)

    TriggerServerEvent("AzFR:requestPlayerJob")
end

Citizen.CreateThread(function()
    local function __az5pd_init(job)
        if isJobAllowed(job) then

        print("[Az-FR | CALLOUT System] Access granted for job: " .. tostring(job))

            if _G == nil then _G = {} end
            if not _G.__ai_casualty_queue then _G.__ai_casualty_queue = {} end
            if type(_G.handleCasualtyInteraction) ~= 'function' then
              _G.handleCasualtyInteraction = function(responderPed, vehicle, casualty)
                print(" [AI DEBUG] placeholder handleCasualtyInteraction called - queuing call")
                table.insert(_G.__ai_casualty_queue, {responderPed, vehicle, casualty})
              end
            end

            local function safeNetworkGetNetworkIdFromEntity(entity)
              if not entity or entity == 0 then return nil end
              if not DoesEntityExist(entity) then return nil end
              local ok, nid = pcall(NetworkGetNetworkIdFromEntity, entity)
              if ok and nid and nid ~= 0 then return nid end
              return nil
            end

            local function safeNetworkGetEntityFromNetworkId(netId)
              netId = tonumber(netId)
              if not netId or netId == 0 then return nil end
              local exists = false
              local okExists = pcall(function()
                exists = NetworkDoesNetworkIdExist(netId)
              end)
              if not okExists or not exists then return nil end
              local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
              if ok and ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
              return nil
            end

            local function resolvePed(pedOrNetId)
              if pedOrNetId == nil then return nil end
              local n = tonumber(pedOrNetId)
              if not n or n == 0 then return nil end
              if DoesEntityExist(n) then
                return n
              end
              local ent = safeNetworkGetEntityFromNetworkId(n)
              if ent and ent ~= 0 and DoesEntityExist(ent) and IsEntityAPed(ent) then
                return ent
              end
              return nil
            end

            local function safeNetToPed(pedNetId)
              return resolvePed(pedNetId)
            end

            local function safePedToNet(pedOrNetId)
              if pedOrNetId == nil then return nil end
              local n = tonumber(pedOrNetId)
              if not n or n == 0 then return nil end

              if not DoesEntityExist(n) then
                return n
              end

              local ok, isNet = pcall(NetworkGetEntityIsNetworked, n)
              if ok and not isNet then

                return nil
              end

              local ok2, nid = pcall(function() return PedToNet(n) end)
              if ok2 and nid and nid ~= 0 then return nid end

              nid = safeNetworkGetNetworkIdFromEntity(n)
              if nid and nid ~= 0 then return nid end
              return nil
            end

            local function safeNetworkGetEntityFromIdMaybe(id)
              id = tonumber(id)
              if not id or id == 0 then return nil end
              if DoesEntityExist(id) then return id end
              return safeNetworkGetEntityFromNetworkId(id)
            end

            local function safeNetToEntity(netId)
              return safeNetworkGetEntityFromNetworkId(netId)
            end

            local function safeEntityToNet(entity)
              if not entity or entity == 0 then return nil end
              if not DoesEntityExist(entity) then return nil end
              local ok, isNet = pcall(NetworkGetEntityIsNetworked, entity)
              if ok and not isNet then return nil end
              local nid = safeNetworkGetNetworkIdFromEntity(entity)
              if nid and nid ~= 0 then return nid end
              return nil
            end

local stopEnabled, debugEnabled = true, (Config and Config.Debug == true) or false
            local pedData, lastPedNetId = {}, nil
            local ensurePerson -- forward declaration (used before definition)
            local openExternalMDT -- forward declaration (used before definition)
            local lastPedEntity = nil

            local function cacheTargetPedContext(data)
              local pedEntity = nil
              if data and data.entity then pedEntity = data.entity
              elseif data and data.ped then pedEntity = data.ped
              elseif data and data.target then pedEntity = data.target end
              if not pedEntity or pedEntity == 0 or not DoesEntityExist(pedEntity) or not IsEntityAPed(pedEntity) or IsPedAPlayer(pedEntity) then
                return nil, nil
              end
              local pedKey = safePedToNet(pedEntity) or tostring(pedEntity)
              ensurePerson(pedKey)
              lastPedNetId = tostring(pedKey)
              lastPedEntity = pedEntity
              return pedEntity, tostring(pedKey)
            end

            local function stopPedFromTarget(data)
              local pedEntity = nil
              if data and data.entity then pedEntity = data.entity
              elseif data and data.ped then pedEntity = data.ped
              elseif data and data.target then pedEntity = data.target end

              if not pedEntity or not DoesEntityExist(pedEntity) then
                if notify then notify("stop_err","Stop Ped","No valid ped found.",'error') end
                return
              end
              if IsPedAPlayer(pedEntity) then
                if notify then notify("stop_err","Stop Ped","Cannot stop players.",'error') end
                return
              end

              local ok, netId = pcall(function() return PedToNet(pedEntity) end)
              if not ok or not netId or netId == 0 then
                netId = tostring(pedEntity)
              end
              netId = tostring(netId)

              pedData = pedData or {}
              -- Ensure we always have identity data (even if another helper created an empty bucket)
              ensurePerson(netId)

              lastPedNetId = netId
              lastPedEntity = pedEntity

              if setPedProtected then pcall(function() setPedProtected(netId, true) end) end
              pedData[netId].pulledInVehicle = false
              pedData[netId].forcedStop = true

              NetworkRequestControlOfEntity(pedEntity)
              SetEntityAsMissionEntity(pedEntity, true, true)
              SetBlockingOfNonTemporaryEvents(pedEntity, true)
              if holdPedAttention then pcall(function() holdPedAttention(pedEntity, false) end) end

              if notify then
                pcall(function() notify("stop_done","Stop","Ped stopped and detained on-foot.", 'success','person','') end)
              end

              pcall(function() TriggerEvent('__clientRequestPopulate') end)
            end

            local resolveCuffedPed

            if exports and exports.ox_target and exports.ox_target.addGlobalPed then
              pcall(function()
                exports.ox_target:addGlobalPed({
                  name = "az_police_stop_ped",
                  label = "Stop Ped",
                  icon = "hand-paper",
                  onSelect = function(data)
                    stopPedFromTarget(data)
                  end,
                  distance = 3.0
                })
              end)
            end

            if exports and exports.ox_target and exports.ox_target.addGlobalVehicle then
              pcall(function()
                exports.ox_target:addGlobalVehicle({
                  {
                    name = "az_police_seat_cuffed_left",
                    label = "Seat Cuffed Ped (Left Rear)",
                    icon = "car-side",
                    distance = 3.0,
                    canInteract = function(entity, distance)
                      local ped = resolveCuffedPed and select(1, resolveCuffedPed()) or nil
                      return ped and DoesEntityExist(ped) and distance <= 3.0 and IsVehicleSeatFree(entity, 1)
                    end,
                    onSelect = function(data)
                      seatPed(1, data and data.entity or nil)
                    end
                  },
                  {
                    name = "az_police_seat_cuffed_right",
                    label = "Seat Cuffed Ped (Right Rear)",
                    icon = "car-side",
                    distance = 3.0,
                    canInteract = function(entity, distance)
                      local ped = resolveCuffedPed and select(1, resolveCuffedPed()) or nil
                      return ped and DoesEntityExist(ped) and distance <= 3.0 and IsVehicleSeatFree(entity, 2)
                    end,
                    onSelect = function(data)
                      seatPed(2, data and data.entity or nil)
                    end
                  }
                })
              end)
            end

            local isDragging, draggedPed = false, nil
            local lastCuffedPedNetId, lastCuffedPedEntity = nil, nil
            local pullVeh = nil
            local pendingPullVeh = nil
            local pendingPullDeadline = 0
            local pendingPullMonitor = false
            local pullVehBlip = nil

            local function dprint(...)
              if debugEnabled then
                local args = {...}
                for i=1,#args do args[i] = tostring(args[i]) end
                print("[Az-5PD]", table.concat(args, " "))
              end
            end

            local setPedProtected, markPulledInVehicle, monitorKeepInVehicle, holdPedAttention, releasePedAttention

            local callAIEMS, callAICoroner, callAIAnimalControl, callTow

            local lastPlate, lastPlateHistory = nil, {}
            local lastIdHistory = {}
            local lastMake, lastColor = nil, nil

            local HOLD_SURRENDER_MS = 3000
            local HOLD_PULL_MS = 1500

            local citationReasons = {
              "Speeding","Reckless Driving","Illegal Parking",
              "No Insurance","Expired Registration",
              "Failure to Signal","Distracted Driving","Broken Taillight"
            }

            -- upvalues for generated ID data (must be declared before generatePerson)
            local ln, st
            local getImmersionConfig
            local immersionEnabled
            local playerPresenceFeelsThreatening
            local loadAnimSetTimed
            local computeSuspicionChance
            local applyImmersionProfileToPed
            local enrichPedImmersionProfile

            getImmersionConfig = function()
              return (Config and Config.Immersion) or {}
            end

            immersionEnabled = function()
              local cfg = getImmersionConfig()
              return cfg.enabled ~= false
            end

            playerPresenceFeelsThreatening = function()
              local player = PlayerPedId()
              if not player or player == 0 then return false end
              if IsPlayerFreeAiming(PlayerId()) then return true end
              if IsPedArmed(player, 7) then return true end
              local veh = GetVehiclePedIsIn(player, false)
              if veh and veh ~= 0 then
                local sirenOn = false
                local ok, value = pcall(IsVehicleSirenOn, veh)
                if ok and value then sirenOn = true end
                if sirenOn then return true end
              end
              return false
            end

            loadAnimSetTimed = function(animSet, timeout)
              if not animSet or animSet == '' then return false end
              if HasAnimSetLoaded(animSet) then return true end
              RequestAnimSet(animSet)
              local untilAt = GetGameTimer() + (timeout or 1200)
              while not HasAnimSetLoaded(animSet) and GetGameTimer() < untilAt do
                Citizen.Wait(10)
              end
              return HasAnimSetLoaded(animSet)
            end

            computeSuspicionChance = function(ped)
              local cfg = getImmersionConfig()
              local suspicion = cfg.suspicion or {}
              local chance = tonumber(suspicion.baseChance) or 0.18
              local onFoot = not (ped and DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false))
              if onFoot then
                chance = chance * (tonumber(suspicion.onFootMultiplier) or 1.75)
              else
                chance = chance * (tonumber(suspicion.vehicleMultiplier) or 0.75)
              end
              local hour = GetClockHours()
              if hour >= 21 or hour <= 5 then
                chance = chance * (tonumber(suspicion.nightMultiplier) or 1.15)
              end
              if playerPresenceFeelsThreatening() then
                chance = chance * (tonumber(suspicion.weaponDrawnMultiplier) or 1.30)
              end
              return math.max(0.0, math.min(tonumber(suspicion.maxChance) or 0.92, chance))
            end

            applyImmersionProfileToPed = function(ped, info)
              if not ped or ped == 0 or not DoesEntityExist(ped) or type(info) ~= 'table' then return end
              local cfg = getImmersionConfig()
              local behavior = cfg.behavior or {}
              if info.isDrunk then
                pcall(SetPedIsDrunk, ped, true)
                if behavior.enableDrunkClipset ~= false then
                  local clip = tostring(behavior.drunkClipset or 'move_m@drunk@verydrunk')
                  if loadAnimSetTimed(clip, 1200) then
                    pcall(SetPedMovementClipset, ped, clip, 0.35)
                  end
                end
              end
              if info.suspicious then
                pcall(SetPedAlertness, ped, info.wanted and 3 or 2)
              elseif info.isHigh then
                pcall(SetPedAlertness, ped, 1)
              end
            end

            enrichPedImmersionProfile = function(ped, info)
              info = type(info) == 'table' and info or {}
              if info._immersionProfiled then
                applyImmersionProfileToPed(ped, info)
                return info
              end
              local cfg = getImmersionConfig()
              local traits = cfg.traits or {}
              local suspicious = math.random() < computeSuspicionChance(ped)
              local onFoot = not (ped and DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false))

              info.behaviorProfile = onFoot and 'on_foot' or 'vehicle'
              info.suspicious = suspicious
              info.hasIllegalItems = info.hasIllegalItems == true or (suspicious and math.random() < (tonumber(traits.illegalItemsChance) or 0.48)) or false
              info.wanted = info.wanted == true or (suspicious and math.random() < (tonumber(traits.warrantChance) or 0.22)) or false
              info.suspended = info.suspended == true or (suspicious and math.random() < (tonumber(traits.suspendedChance) or 0.14)) or false
              info.isDrunk = info.isDrunk == true or (suspicious and math.random() < (tonumber(traits.drunkChance) or 0.20)) or false
              info.isHigh = info.isHigh == true or (suspicious and math.random() < (tonumber(traits.highChance) or 0.24)) or false
              info.nervous = suspicious and (math.random() < (tonumber(traits.nervousChance) or 0.40)) or false

              local disposition = 'calm'
              if suspicious then
                local roll = math.random()
                local driveChance = tonumber(traits.driveAwayChance) or 0.65
                local runChance = tonumber(traits.runChance) or 0.44
                local hideChance = tonumber(traits.hideChance) or 0.28
                if not onFoot then
                  if roll < driveChance then
                    disposition = 'drive_away'
                  else
                    disposition = 'nervous'
                  end
                elseif roll < runChance then
                  disposition = 'run'
                elseif roll < (runChance + hideChance) then
                  disposition = 'hide'
                else
                  disposition = 'nervous'
                end
              end
              info.disposition = info.disposition or disposition

              if info.suspended then
                info.licenseStatus = info.licenseStatus or 'SUSPENDED'
              elseif info.wanted and not info.licenseStatus then
                info.licenseStatus = 'VALID'
              end

              local refusal = tonumber(info.idRefusalChance) or 0.18
              if info.wanted then refusal = math.max(refusal, 0.55) end
              if info.suspended then refusal = math.max(refusal, 0.35) end
              if info.hasIllegalItems then refusal = math.max(refusal, 0.32) end
              if info.isDrunk or info.isHigh then refusal = math.max(refusal, 0.28) end
              info.idRefusalChance = refusal
              info._immersionProfiled = true
              applyImmersionProfileToPed(ped, info)
              return info
            end

            local function generatePerson(ped)

            local fn = {
              "John", "James", "Robert", "Michael", "William", "David", "Richard", "Joseph",
              "Thomas", "Charles", "Christopher", "Daniel", "Matthew", "Anthony", "Mark", "Donald",
              "Steven", "Paul", "Andrew", "Joshua", "Mary", "Patricia", "Jennifer", "Linda",
              "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen", "Nancy", "Lisa",
              "Margaret", "Betty", "Sandra", "Ashley", "Dorothy", "Kimberly", "Emily", "Donna",
              "Michelle", "Carol", "Amanda", "Melissa", "Deborah", "Stephanie", "Rebecca", "Laura",
              "Sharon", "Cynthia", "Kathleen", "Amy", "Shirley", "Angela", "Helen", "Anna",
              "Brenda", "Pamela", "Nicole", "Samantha", "Katherine", "Emma", "Ruth", "Christine",
              "Catherine", "Debra", "Virginia", "Rachel", "Carolyn", "Janet", "Maria", "Juan",
              "Jose", "Luis", "Carlos", "Jesus", "Miguel", "Angel", "Pedro", "Diego",
              "Manuel", "Francisco", "Antonio", "Jorge", "Ricardo", "Roberto", "Sergio", "Fernando",
              "Eduardo", "Enrique", "Raul", "Isabella", "Sofia", "Camila", "Valentina", "Lucia",
              "Martina", "Mia", "Gabriela", "Julieta", "Sara", "Laura", "Natonn", "Beraha",
              "Sasoner", "Ruleeya", "Seran", "Laliea", "Huneie", "Nimian", "Peielya", "Benaim",
              "Taiasus", "Bebelen", "Resonx", "Yasonek", "Fironah", "Elayaie", "Kaorax", "Qinnain",
              "Moevaya", "Nilias", "Pennax", "Pesonar", "Beayain", "Haciaek", "Filieer", "Beliaon",
              "Naciaie", "Luciao", "Yaricin", "Qimieer", "Celaa", "Elettear", "Beliaen", "Xuetteen",
              "Paumiar", "Paayal", "Darisa", "Qimiia", "Kiiasya", "Ioevaa", "Sakoas", "Lalar",
              "Raciaah", "Seliaar", "Yaayaea", "Daskin", "Kamiim", "Beiner", "Soiasel", "Vanaam",
              "Dakoim", "Vikor", "Naellein", "Hulynl", "Haciaie", "Bonaon", "Ceumin", "Kaevaah",
              "Zirahs", "Lubenx", "Laumix", "Rurisl", "Koskiel", "Dasoon", "Selieie", "Niellear",
              "Paevao", "Boielr", "Lumiex", "Reneya", "Qimieya", "Penax", "Nalaa", "Miraus",
              "Mikoa", "Beumien", "Rurisam", "Xubenas", "Luikoah", "Dilynr", "Mariasek", "Seeuso",
              "Josons", "Ioineah", "Marrahen", "Nimio", "Saiasel", "Beayaa", "Miielah", "Qisons",
              "Pamin", "Larahel", "Diumias", "Noitas", "Taoran", "Yaronah", "Vannaan", "Qiumil",
              "Ninnaen", "Jomis", "Celas", "Kiikoea", "Bocias", "Huleeel", "Miliaer", "Luitar",
              "Xurahya", "Liraon", "Laeuser", "Kibenea", "Ceronen", "Cerahia", "Ioriser", "Paelleo",
              "Celian", "Vabenr", "Mimien", "Huronl", "Filiaa", "Hannael", "Mamiis", "Zison",
              "Qielleer", "Marrisia", "Kasonam", "Qibelia", "Solieis", "Relieer", "Naronea", "Girons",
              "Laiasia", "Elnaus", "Saronel", "Maskiis", "Seskin", "Kaliais", "Ramis", "Haskil",
              "Seriss", "Zievaah", "Elaraen", "Lusonek", "Qieuson", "Rarahel", "Vieusn", "Viineah",
              "Dirahia", "Tasonar", "Elikoa", "Niayaek", "Zimiea", "Allynar", "Rericx", "Bearain",
              "Huitaer", "Ruinen", "Karonel", "Kirons", "Ceiason", "Hutonar", "Xulynia", "Eliasn",
              "Bomier", "Nievaan", "Miineon", "Cetonam", "Zikoio", "Diettear", "Soskil", "Nieuser",
              "Yashaon", "Xuellear", "Qinaio", "Soliean", "Kietteo", "Maieler", "Nokoas", "Taleeio",
              "Huinex", "Luellea", "Nibeln", "Elrahas", "Moliao", "Dibenen", "Yaumiar", "Lubelin",
              "Ansonim", "Semieel", "Boayas", "Qirahr", "Varisah", "Vasoie", "Lietteim", "Makoan",
              "Qiielel", "Koielia", "Luricim", "Boumiin", "Lurico", "Minnaa", "Beineus", "Ruleel",
              "Ramiear", "Raliex", "Dieusus", "Ruayaan", "Joliean", "Yaneim", "Xuoraas", "Anaraio",
              "Yaeusie", "Rumieas", "Perican", "Ginear", "Reitaam", "Taayal", "Momin", "Iobener",
              "Alleein", "Seriso", "Vilaia", "Yaetteen", "Vaetteus", "Yaricim", "Dironx", "Koneam",
              "Rulaek", "Peliaim", "Paraim", "Alrahen", "Albela", "Saikoer", "Kabenen", "Varonim",
              "Haciaon", "Litonim", "Taeller", "Kineio", "Xuoraar", "Niliaya", "Narahr", "Zitonah",
              "Xuraek", "Ruiaser", "Haliaea", "Painen", "Diumir", "Seevain", "Vabelan", "Visoin",
              "Bemiim", "Koayaan", "Kiricus", "Luleeia", "Marahim", "Vabenon", "Yainen", "Gietteel",
              "Gilieek", "Daineia", "Liricie", "Ansoen", "Laraham", "Diumiie", "Luikoin", "Giielah",
              "Alleeio", "Peitais", "Luelleer", "Kievaas", "Qisoek", "Seskius", "Fiayaia", "Zirona",
              "Kalynus", "Vilynen", "Koricam", "Kisoon", "Sosonen", "Somieek", "Viellen", "Rurisia",
              "Ellaie", "Sorisin", "Gisonn", "Xunnaas", "Koielus", "Kotonx", "Ioumix", "Xulal",
              "Rabenio", "Larahr", "Limieim", "Boorao", "Maelleya", "Seelleya", "Molaon", "Marliein",
              "Noroner", "Laciaa", "Viskix", "Tanaan", "Maikoio", "Elmieio", "Soayax", "Peronah",
              "Nalynan", "Kamia", "Pabelia", "Ralias", "Taelleon", "Xunnao", "Kaayais", "Ziitaia",
              "Humias", "Maleeon", "Eliasam", "Ceronn", "Lamieer", "Xuneim", "Bebens", "Viikoea",
              "Paielia", "Viiasin", "Gileeas", "Fieusus", "Cesonel", "Reeusis", "Ginnaer", "Ioskis",
              "Valeeus", "Daetter", "Iokon", "Jolynea", "Haumiin", "Malaen", "Beskil", "Soielis",
              "Gitonn", "Narahis", "Taelleie", "Anskian", "Lamier", "Vatonin", "Raumiis", "Sokois",
              "Beeusas", "Koraho", "Qibelar", "Nikoam", "Saliaia", "Diineah", "Huricn", "Soelleya",
              "Kiumil", "Mamias", "Fiineie", "Ruorao", "Celynis", "Lubenar", "Peeuss", "Ceikois",
              "Yaoraer", "Pabelas", "Elrisea", "Kiiner", "Masonea", "Raeusin", "Raliaas", "Daineon",
              "Ioleeus", "Ruoraus", "Naumiie", "Elliaa", "Nannaa", "Laiasr", "Nasono", "Taellen",
              "Eletteah", "Jonnaek", "Haiasl", "Lusoan", "Xushael", "Vileeon", "Yarahas", "Kibela",
              "Varono", "Danaah", "Vannaer", "Ruciax", "Maaraya", "Ziiasis", "Daayaio", "Nioraas",
              "Marrahar", "Xuaraya", "Sonnan", "Ioricn", "Xulaon", "Ginnaim", "Pearaa", "Nalynon",
              "Darisin", "Marraio", "Maraya", "Harisx", "Soetteam", "Dishaen", "Samiek", "Bokoia",
              "Taronas", "Soineah", "Kaayax", "Ramieer", "Ioskiek", "Laitan", "Damir", "Vaevaer",
              "Daorain", "Hasoner", "Peikon", "Moskius", "Momiein", "Miayais", "Zieusr", "Saras",
              "Ziumir", "Marrahie", "Saorao", "Hamian", "Kibelan", "Pasonas", "Moeusia", "Elevaen",
              "Maiela", "Hamiin", "Filaar", "Belynr", "Valeeer", "Nones", "Rerahl", "Xuliex",
              "Qilieya", "Nomieus", "Ranaia", "Rarisie", "Dashar", "Alrisn", "Firahya", "Ceneel",
              "Dalal", "Disor", "Miikoo", "Hakoya", "Marielea", "Peraam", "Boelleo", "Panes",
              "Koitaan", "Marumiis", "Maliax", "Cebelx", "Saricon", "Naskiis", "Ceoraon", "Bonnao",
              "Huiasr", "Kaskiam", "Noiaso", "Peeusus", "Vaitaan", "Marettean", "Ceronek", "Raikox",
              "Laleex", "Sesonam", "Harisie", "Joskiie", "Retonan", "Fiiasam", "Jonnaon", "Ziarar",
              "Xukoen", "Raikoa", "Mararaie", "Hatonim", "Bebena", "Seskiim", "Moskin", "Liricn",
              "Viricis", "Ziineek", "Anshal", "Xuitax", "Ranex", "Boliear", "Diayaus", "Taevaio",
              "Cebenon", "Lalal", "Talaer", "Larico", "Seumion", "Maeusia", "Nokor", "Fiiasr",
              "Soumiea", "Ziraa", "Iolan", "Noelleen", "Saronio", "Cetonn", "Giiasel", "Saoraie",
              "Pekoie", "Filiaar", "Valiaus", "Xuiasya", "Ioeusio", "Kaitan", "Ceciaah", "Moayais",
              "Haleean", "Marrahan", "Kiitaea", "Laitaio", "Remieus", "Taliaea", "Natonea", "Hulynim",
              "Fiaraam", "Pabela", "Marbelia", "Nishaon", "Raliael", "Naumio", "Xuieler", "Xuettein",
              "Cebelo", "Naelleah", "Belaek", "Huliaio", "Vaiels", "Joevaio", "Mileeon", "Likoar",
              "Vaskiah", "Elielah", "Xulynus", "Liikoea", "Ralao", "Marineis", "Lakoin", "Viraa",
              "Maielea", "Bociaek", "Hannaar", "Diineer", "Lilaah", "Nainex", "Resonie", "Yannaia",
              "Libelus", "Labelek", "Ziital", "Lileeio", "Qiorain", "Reriser", "Boleein", "Sekoek",
              "Alevaio", "Vilieus", "Gilyna", "Sabelx", "Sosonea", "Rusos", "Rerison", "Yabelel",
              "Viciaam", "Maraan", "Haraho", "Monnaim", "Mamieie", "Luelleah", "Kolynek", "Xuielo",
              "Sooraea", "Boeusel", "Nirisia", "Joikoek", "Qisonis", "Botonio", "Laciaia", "Makol",
              "Seleea", "Maaran", "Dilaar", "Huevaa", "Yaleeek", "Peneus", "Marineah", "Rariss",
              "Soikois", "Saikoo", "Monax", "Alronen", "Raskiam", "Lisoan", "Kannaa", "Zitons",
              "Lueusin", "Moayax", "Kaumion", "Runein", "Hubena", "Rannaan", "Anaraa", "Xueusel",
              "Lasoek", "Misoie", "Hukoie", "Aloraas", "Eloraek", "Daneek", "Miaraa", "Nasonim",
              "Kiinel", "Elaraie", "Reshaim", "Vaikoin", "Virisx", "Varaio", "Niraah", "Niraus",
              "Zikoar", "Ruikoia", "Ellynio", "Filain", "Rericr", "Haiasar", "Maoraus", "Viumiis",
              "Gievaah", "Boricah", "Laiasx", "Seshaie", "Soetter", "Laetteer", "Soelleo", "Liiasel",
              "Maarao", "Elaraon", "Sericin", "Joliaer", "Naitaek", "Hucian", "Raiels", "Saliaa",
              "Paevaek", "Yabens", "Libeler", "Maevaek", "Maliaya", "Sasoek", "Ioettein", "Berahr",
              "Alshaas", "Booraie", "Karonim", "Daielen", "Monnais", "Gilynr", "Saliao", "Viielx",
              "Cearais", "Miskiie", "Soelleel", "Nashaah", "Hakoa", "Kalynah", "Sarahah", "Gineek",
              "Qibenek", "Vaskil", "Moleex", "Ziitais", "Kosoan", "Dibenx", "Saettein", "Miielo",
              "Boaral", "Qishaim", "Saiasea", "Jotonea", "Raelleel", "Taetteis", "Pearaea", "Soleeia",
              "Niskiia", "Saelleon", "Ruleeea", "Paciaya", "Kibelel", "Moineya", "Elnex", "Elbenia",
              "Palieim", "Xueuson", "Naneas", "Namiio", "Paelleas", "Luitaio", "Valiais", "Jociao",
              "Diikoo", "Noineon", "Raetteis", "Cearaar", "Saevaea", "Qisonus", "Luayar", "Beiela",
              "Rasons", "Sooraon", "Dirahel", "Cebenam", "Celynim", "Taumiea", "Vaumiio", "Ginex",
              "Iokoo", "Lulieya", "Filas", "Soumion", "Paikoio", "Runar", "Serisia", "Haitaek",
              "Elitas", "Xuskien", "Haskiio", "Mioraea", "Maskiia", "Motonl", "Maritaek", "Reskiek",
              "Ralynon", "Huitaea", "Elras", "Saineah", "Kosoo", "Rakol", "Ceetteel", "Ioelleya",
              "Rekoea", "Ruumiis", "Xuelleas", "Alevaus", "Kaeusya", "Zineon", "Koronin", "Kibena",
              "Joikoel", "Booral", "Luraya", "Kalynn", "Maettean", "Raeusis", "Noeusea", "Moikoam",
              "Jorisea", "Noskius", "Kosoar", "Ceshao", "Ruineie", "Fironon", "Kolyna", "Beskiio",
              "Peelleim", "Gietteas", "Fiskiah", "Bennar", "Xumiar", "Ioaraim", "Rannas", "Soleeek",
              "Maronam", "Kolieen", "Ruricie", "Berisr", "Moraha", "Josoa", "Namies", "Mareusus",
              "Kosoner", "Sanaie", "Taeusin", "Koikoin", "Ninnaus", "Solaim", "Labena", "Rurael",
              "Dishas", "Ioumiel", "Soran", "Zibenon", "Marineio", "Vamiea", "Girisea", "Varicen",
              "Kaineel", "Varonis", "Vinaam", "Rennaya", "Naitaan", "Huettex", "Iosonel", "Saikous",
              "Lunaia", "Yaraho", "Beineio", "Kibenn", "Daevais", "Lulaer", "Kaayaio", "Taitaer",
              "Huelleis", "Kannaek", "Momiea", "Saikol", "Vaevaan", "Qiikoim", "Rulieim", "Luleeea",
              "Masois", "Haliaya", "Kalaie", "Hulynya", "Rubelel", "Cesoo", "Kalieis", "Kiumix",
              "Huielah", "Joayal", "Hueuso", "Xulaie", "Vaelleam", "Alitaia", "Anlieya", "Miraan",
              "Filiaie", "Joliaas", "Elnnaan", "Virisim", "Paeusek", "Yaielar", "Yaleeer", "Rurisin",
              "Fitonel", "Ruitaea", "Samien", "Alelleo", "Ruiasie", "Yamiea", "Vaaral", "Belynam",
              "Karaah", "Dinea", "Noliar", "Lirao", "Lilaa", "Elitao", "Pemien", "Somieam",
              "Xuetteya", "Liettea", "Zibeler", "Bomiean", "Zirics", "Qishain", "Seskias", "Joarain",
              "Yasous", "Dieusl", "Ziorael", "Ruikoa", "Peelleis", "Raayas", "Qieusan", "Qisol",
              "Yarahia", "Noinein", "Laielek", "Lamiam", "Nilaia", "Yarax", "Niskien", "Kolieus",
            }

            ln = {
              "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
              "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas",
              "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
              "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker", "Young",
              "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
              "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell",
              "Carter", "Roberts", "Gomez", "Phillips", "Evans", "Turner", "Diaz", "Parker",
              "Cruz", "Edwards", "Collins", "Reyes", "Stewart", "Morris", "Morales", "Murphy",
              "Cook", "Rogers", "Gutierrez", "Ortiz", "Morgan", "Cooper", "Peterson", "Bailey",
              "Reed", "Kelly", "Howard", "Ramos", "Kim", "Cox", "Ward", "Richardson",
              "Watson", "Brooks", "Chavez", "Wood", "James", "AnWood", "Whitewell", "Blackport",
              "Blueland", "Northside", "Blackbrook", "RuVitch", "DaBurn", "Westview", "KoBridge", "Greenborne",
              "XuField", "Oakburn", "Hollowgrove", "Harborstone", "PeCastle", "Woodport", "Redborne", "GiVitch",
              "Eastman", "Greenman", "RuRow", "Roseford", "Maplemore", "AnCourt", "NaField", "RaSon",
              "VaBurn", "NaEscu", "Brightport", "Oakfield", "Southfield", "BeVale", "Oakridge", "Redcrest",
              "Brightman", "MarMont", "NiHolm", "Highhill", "IoSki", "IoCroft", "Blueside", "LaVitch",
              "Goldencourt", "IoCastle", "KoOv", "Blueman", "SeVitch", "Hollowwell", "Brightford", "XuCaster",
              "MiStone", "Hollowmore", "CeSen", "Hollowstone", "Bluemont", "Harborman", "Hollowmont", "Foxborne",
              "SaSki", "Greenford", "PeOva", "MoDal", "Glenview", "FiGard", "Southman", "Redmont",
              "MoShaw", "Bluewood", "RaCastle", "Goldenstone", "Springhill", "AnTon", "BeIan", "ViHill",
              "QiBourne", "AlSki", "LaDal", "Springmont", "DiCastle", "Whitebury", "Woodgrove", "BeTon",
              "RaOva", "BeCourt", "MiBurn", "LuVich", "MoMan", "SaTon", "IoMore", "Northbridge",
              "Eastborne", "PaDal", "CeDal", "Stoneport", "IoBridge", "NaRow", "Glenside", "BeMark",
              "XuMan", "Foxman", "Foxfield", "Easthaven", "SoOva", "Glenbridge", "GiAkis", "Woodburn",
              "Bluecrest", "Mapleview", "Westgrove", "HuCourt", "Glenhill", "Glenbury", "Brightwood", "LuEscu",
              "Hillshire", "Hollowshire", "Northcourt", "SeIan", "DaField", "Rosebury", "Hollowside", "Hollowhaven",
              "Greenfield", "SoCourt", "Maplewell", "Whitestone", "ReCroft", "Roseport", "MarSide", "ElIdis",
              "ReVitch", "TaFord", "SeCroft", "IoVich", "AlHolm", "Eastgrove", "MiQuist", "RuStein",
              "NiCroft", "GiMont", "Springland", "IoStrom", "FiCroft", "Highmore", "Harborland", "Redstone",
              "LuTon", "HaEscu", "Southland", "YaHill", "NaVale", "Goldenman", "Westbrook", "CeSide",
              "Lowhill", "Weststone", "YaGard", "Westcrest", "Southhaven", "Westman", "AlField", "BeField",
              "Hillcourt", "GiGard", "RuBurn", "Blackford", "Eastbury", "ElSide", "LaSide", "Rivercourt",
              "Stonebridge", "Bluehill", "Silvershire", "MoAkis", "Highton", "Hollowhill", "Silverbury", "SoShaw",
              "Lowridge", "Redwell", "DiOv", "Lowshire", "SaFord", "CeFord", "XuVich", "NaSki",
              "BeBurn", "GiBridge", "Lowcourt", "Maplegate", "Goldenmore", "Lowwood", "Northton", "CeShaw",
              "XuAkis", "Westbridge", "JoEz", "VaSen", "TaSide", "SeMan", "Brightstone", "Fairburn",
              "HaWell", "PaBerg", "NaTon", "Blackside", "LaIan", "KoOva", "PeMont", "Highwell",
              "MiField", "MarIan", "ZiAkis", "SaVitch", "Lakewood", "Oakland", "Easthill", "Goldengate",
              "DiHolm", "Lowton", "MarAkis", "Hollowgate", "SeBridge", "Woodbury", "Whiteland", "AlEscu",
              "Stoneridge", "Stonegate", "PaOv", "KaFord", "LiOva", "Oakhill", "Lakemont", "Hollowcrest",
              "ViCaster", "Blackwood", "MiSon", "ElOv", "Northridge", "Foxland", "LaTon", "NoEscu",
              "Northgrove", "Highshire", "Maplebrook", "Whiteside", "LaHill", "ViIdis", "SaSon", "FiMont",
              "Highgate", "HaAkis", "Lowburn", "Springbridge", "BoOva", "VaBourne", "GiQuist", "TaWell",
              "Fairgrove", "Riverside", "Oakford", "Oakside", "HaCastle", "Hillford", "Brighthaven", "Southside",
              "DiBridge", "HuOv", "BoEz", "QiCroft", "NiShaw", "Harborgate", "Westcourt", "Woodstone",
              "DiSen", "FiVich", "Fairfield", "Oakcourt", "Lowgate", "Riverton", "Woodcrest", "JoEscu",
              "Mapleford", "Fairridge", "HaCroft", "Maplegrove", "SaVich", "Southmore", "Woodbrook", "CeMark",
              "Whiteborne", "NiAkis", "DiIdis", "Blackton", "VaWell", "Mapleman", "Harborhaven", "Pineton",
              "Springstone", "LuLey", "JoTon", "ViSen", "Lowview", "Foxside", "JoField", "IoBurn",
              "Goldenwood", "Portwood", "MiMan", "Eastbridge", "ReIdis", "VaOv", "XuHill", "Northport",
              "SeStein", "ViStone", "RaEz", "Silverside", "Westford", "YaAkis", "PaMont", "RuSen",
              "Glenhaven", "XuBourne", "BeStein", "LiField", "BeOv", "Westridge", "KiField", "Portbury",
              "Brightgate", "PeQuist", "Glenmont", "ViStein", "CeLey", "Oakhaven", "NiRow", "Hillport",
              "ReHolm", "SaMore", "Brightbridge", "Springford", "KiEscu", "Maplehill", "Springbrook", "TaHill",
              "Westshire", "QiHolm", "Woodmore", "Hillmont", "SoAkis", "AnQuist", "XuEz", "CeHolm",
              "XuIan", "Lakeborne", "Woodhill", "Maplehaven", "DaWood", "MiLey", "MarSon", "MaCourt",
              "Faircrest", "YaLey", "Riverport", "Woodman", "ElShaw", "DaIan", "TaCastle", "MiGard",
              "Mapleborne", "Silverport", "Southshire", "SeBerg", "ReWood", "Redbrook", "MarOv", "QiRow",
              "HaSon", "SoEscu", "Westton", "NoBerg", "Mapleport", "Harborbridge", "GiEscu", "PaVale",
              "MaEz", "BeQuist", "MarSki", "Highmont", "Southbury", "IoEz", "Redland", "MaStein",
              "Hillton", "Lakeford", "Portborne", "CeStone", "Brightfield", "Silvergrove", "Southwell", "RaQuist",
              "Blackwell", "Hollowcourt", "SoVale", "PaRow", "IoEscu", "Redhaven", "Pinegate", "ZiTon",
              "GiIan", "MaBridge", "DiDal", "Stoneview", "DiRow", "Rosebridge", "ZiBourne", "BoQuist",
              "NiMan", "Woodford", "HaMan", "KaSen", "GiDal", "KoStrom", "Portgate", "JoBerg",
              "Goldenside", "Portshire", "AlSon", "AnField", "ZiVitch", "NoCroft", "BoHolm", "Redhill",
              "Silverland", "MarCaster", "BeVich", "BeWell", "Fairshire", "RaMont", "Fairford", "Whitefield",
              "Harborburn", "Northmont", "PeVale", "Westmore", "ZiBerg", "Fairbury", "DaGard", "Hillmore",
              "PeTon", "ReBurn", "SoCroft", "Rosewell", "NiMore", "XuCroft", "ViSki", "NaStein",
              "JoSon", "SeVich", "SeCaster", "ElVale", "Blackridge", "AnVich", "Woodhaven", "HuStrom",
              "MiEz", "Silverridge", "Westhill", "Hillbridge", "PeField", "Laketon", "Hollowridge", "HaVitch",
              "Northshire", "RuHolm", "AlOv", "Southview", "QiWell", "RaWood", "Goldenfield", "MarEscu",
              "Silverwell", "MarRow", "NiWell", "Stonehill", "GiWood", "Westborne", "AnEscu", "KaQuist",
              "Eastbrook", "JoIan", "Lowford", "Greenbridge", "Southgate", "ElSon", "Redshire", "FiSide",
              "ReStein", "YaCaster", "Goldenbridge", "SaOv", "Lowman", "KiCaster", "Redview", "Lowmore",
              "GiIdis", "Eastford", "PaBridge", "Roseridge", "LuCaster", "PaCastle", "Westport", "Maplecourt",
              "LuMore", "Pineridge", "LuSki", "XuSide", "GiSide", "IoCourt", "QiSon", "Glenland",
              "Goldenbrook", "Foxton", "Springbury", "Greenhaven", "ReLey", "Glenbrook", "TaRow", "DiIan",
              "IoWood", "DiEz", "Blackview", "KiBourne", "GiSon", "Pinebury", "Highgrove", "HuStein",
              "Hillgate", "Rivermont", "Silverborne", "Northcrest", "Portmont", "Harborview", "Lakecrest", "Fairgate",
              "Highhaven", "Springhaven", "Foxshire", "NoHolm", "Lakehaven", "Hillridge", "Goldenborne", "Blackhill",
              "SeSon", "Oakmont", "JoMan", "TaShaw", "Harborton", "Pinehill", "Riverland", "Whiteshire",
              "Woodridge", "JoCastle", "CeGard", "DaMan", "Brightshire", "Goldenhill", "Foxgate", "Blackgate",
              "MiStein", "Whiteridge", "ElHill", "DaAkis", "DaSon", "NaHolm", "Harborport", "Foxhill",
              "CeMont", "ViMont", "HuBerg", "RuMark", "PeWood", "MoMont", "QiVitch", "PaHolm",
              "SoSen", "Highcourt", "HuSide", "SoVitch", "HuSki", "Oakshire", "NaWood", "Oakview",
              "Pinewood", "ViWell", "Southmont", "IoHill", "YaIdis", "HuIan", "ZiDal", "MaCastle",
              "AlCaster", "PeAkis", "Harborshire", "PaBurn", "Oakbury", "Lakewell", "XuDal", "QiSki",
              "FiWood", "PaBourne", "ViField", "Portton", "XuOv", "Brightbury", "QiOva", "MiWell",
              "KiRow", "Greenstone", "Woodwell", "MaMore", "CeHill", "Bluegate", "Porthill", "ReCaster",
              "FiTon", "MarStein", "Mapleburn", "Lakebury", "NaOva", "Stoneford", "Foxbury", "RaBurn",
              "KiShaw", "HuBourne", "HaBourne", "LuHolm", "TaStein", "Lakegate", "GiField", "HaField",
              "NoMont", "Greenmont", "VaEz", "BoVich", "RuQuist", "PaOva", "Greenhill", "KoDal",
              "SaSide", "MiBourne", "Stonestone", "HaDal", "Rivermore", "KoCaster", "TaVitch", "XuStrom",
              "NaBourne", "XuEscu", "DaStein", "Northland", "Whitemore", "Mapleton", "KiStein", "Roseburn",
              "Mapleside", "SaIan", "BoBourne", "Highstone", "Silverford", "Foxridge", "Fairland", "Southridge",
              "ElMont", "KoCastle", "DaCaster", "RuCourt", "AnSon", "Riverridge", "PaWood", "Springcrest",
              "RaHill", "Portburn", "Southgrove", "QiCaster", "ZiQuist", "IoAkis", "Hillwell", "Silverhaven",
              "Pineman", "NaSon", "LiHill", "LiEz", "Brightmont", "Rosebrook", "Highman", "Eastfield",
              "BoShaw", "LiBourne", "Woodland", "ElBurn", "AnBerg", "IoMark", "Rosefield", "Maplewood",
              "Portside", "Hollowfield", "DiBourne", "KaBourne", "Hollowburn", "Eastmore", "KiSen", "DaOva",
              "Southhill", "ReOva", "NoQuist", "Woodgate", "MarIdis", "Redmore", "AnVale", "Lowport",
              "CeRow", "Brightridge", "BoHill", "RuEz", "Northmore", "Eastwell", "Oakmore", "KiIan",
              "MoWell", "DaFord", "MoMore", "GiHill", "HaBurn", "Portview", "SaQuist", "Lowmont",
              "RaCaster", "Hillcrest", "NaMont", "Pinemont", "TaOv", "Riverview", "LiMan", "Goldenshire",
              "HuRow", "Eastwood", "Lakeman", "Brightborne", "MoQuist", "MiSki", "PeBridge", "SoStone",
              "Northburn", "Roseview", "LaWood", "KoGard", "IoMont", "RaSki", "Fairmont", "LuShaw",
              "SaAkis", "Hillfield", "FiBridge", "Foxview", "Eastshire", "NaVich", "Brighthill", "PeSki",
              "HaCourt", "ZiSon", "SaLey", "RuSon", "AnHill", "QiHill", "YaField", "MoStone",
              "RuStone", "KaVich", "MaStone", "RaOv", "Oakman", "MaSon", "ReCourt", "GiBurn",
              "ElMore", "IoOva", "ZiBridge", "ElGard", "Portport", "Springfield", "BeStrom", "LuSon",
              "Hollowbridge", "LaFord", "LaHolm", "NaOv", "PaEscu", "Glenwell", "Glenshire", "SaWell",
              "Westhaven", "Stonegrove", "Portland", "RaSide", "DaVale", "Whiteman", "Silverhill", "Woodborne",
              "Redbury", "Blackbury", "SoBridge", "CeIdis", "Stonewell", "MarEz", "Roseland", "Portford",
              "NoVitch", "LaCroft", "Whitewood", "Riverwell", "Foxmont", "BoEscu", "Foxcrest", "Blackshire",
              "ViGard", "ReEscu", "LiSide", "Fairborne", "NaHill", "RuWood", "MaSide", "Oakgate",
              "SoDal", "Blueburn", "VaLey", "Woodside", "ZiSki", "Hollowton", "Bluehaven", "Brightwell",
              "Harborford", "JoMore", "SeCourt", "Pinebrook", "Springridge", "Northview", "SeShaw", "Lakestone",
              "KoQuist", "IoBourne", "Springmore", "FiHolm", "Woodton", "Lakecourt", "Lowbrook", "KaTon",
              "AlMore", "BoWell", "Silvergate", "JoShaw", "PaSon", "BeEscu", "Oakbrook", "Goldenmont",
              "YaBourne", "Riverborne", "LiVale", "NiBourne", "Foxhaven", "LuMont", "GiMark", "Greenshire",
              "HuStone", "Goldenburn", "YaMont", "Southbrook", "Springview", "Stoneshire", "RuMan", "Rosestone",
              "RaVitch", "QiVale", "Riverman", "RaSen", "Portstone", "Riverstone", "MoHolm", "XuHolm",
              "Greenwood", "NiField", "AnStone", "Stonecourt", "ViSide", "VaFord", "ElDal", "Northgate",
              "Roseshire", "Glenford", "Eastview", "Pineside", "IoTon", "SoHolm", "Blueridge", "HuIdis",
              "KiVale", "ViCroft", "Blueton", "Riverwood", "MaVich", "BoCastle", "Northbury", "TaMore",
            }

            st = {
              "Grove St","Vinewood Blvd","Vinewood Park Dr","Del Perro Blvd","Del Perro Fwy","Los Santos Freeway",
              "Vespucci Blvd","Vespucci Canals Dr","Mirror Park Blvd","Alta St","Popular St","South Mo Milton Dr",
              "Richman Ave","Rockford Dr","Rockford Hills Dr","Integrity Way","Innocence Blvd","El Rancho Blvd",
              "Palomino Ave","Elgin Ave","Elysian Fields Rd","Elysian Island Rd","La Puerta Ave","La Puerta Fwy",
              "Forum Dr","Bay City Ave","Bay City Expy","Little Bighorn Ave","Great Ocean Hwy","Pacific Bluffs Dr",
              "Harmony Rd","Sawmill Blvd","Morningwood Blvd","North Rockford Dr","South Rockford Dr","Davis Ave",
              "Davis St","Gentry Lane","Gentry Ave","Marina Dr","Marina Blvd","Pillbox Hill Rd","Pillbox North St",
              "Vinewood Hills Rd","Vinewood Terrace","Summit Dr","Mount Haan Rd","Mount Chiliad Rd","Cypress Flats Rd",
              "Carson Ave","Carson St","Carlton Way","Solomons Blvd","Magellan Ave","Singing Sands Blvd","Seaview Ave",
              "Seaview Rd","Seaside Walk","Seashore Blvd","Del Perro Pier Rd","Del Perro Promenade","Jinglebell Way",
              "Los Santos Blvd","Los Santos Ave","Los Santos Eastway","San Andreas Ave","San Andreas Fwy",
              "Willow St","Willow Ln","Willow Ct","Elm St","Maple St","Oak Ave","Pine Rd","Cedar Blvd","Birch Ln",
              "Palm Tree Rd","Sunset Blvd","Sunset Vista Dr","Sunrise Ave","Sunset Strip Rd","Ocean View Dr",
              "Ocean Ave","Seacliff Dr","Seacliff Ave","Harbor Blvd","Harbor View Ln","Portola Dr","Portola Way",
              "Bayview St","Bayview Ave","Boardwalk Ave","Boardwalk Dr","Boardwalk Ln","Civic Center Dr",
              "Civic Center Plaza","Downtown Vinewood Rd","East Vinewood St","West Vinewood St","Little Seoul Rd",
              "Rancho Blvd","Rancho Dr","Rancho St","Rancho Heights Ave","Rancho Horizons Rd","Paleto Blvd",
              "Paleto Dr","Paleto Bay Rd","Great Chaparral Ln","Cholla Ave","Cholla Rd","Grapeseed Main St",
              "Grapeseed Blvd","Rodeo Dr","Rodeo Way","Richards Majestic Rd","Marigold St","Marigold Ave",
              "Boulevard Del Perro","Del Perro Heights","Cypress Ave","Cypress Dr","Chamberlain Hills Blvd",
              "Little Bighorn Ave","Mad Wayne Thunder Dr","Mad Wayne Ln","Eclipse Blvd","Eclipse Way",
              "Carousel Mall Rd","Commerce St","Commerce Blvd","Industrial Rd","Industrial Ave","Factory Ln",
              "Arroyo St","Arroyo Seco Rd","Vinewood Park Ln","Vinewood Circle","Vinewood Dr","Vinewood Heights",
              "Mirror Park Rd","Mirror Park Ln","Alta Pl","Alta Circle","Alta View Dr","Alta Terrace",
              "Portola Way","Portola Blvd","Del Perro Causeway","Del Perro Pass","Brouge Ave","Brouge St",
              "Morningwood Ave","Morningwood Blvd S","Morningwood Blvd N","Strawberry Ave","Strawberry Ln",
              "Strawberry Boulevard","Harmony Lane","Harmony Place","Harmony Court","Elysian Ave",
              "Elysian Terrace","Dorset Dr","Dorset Ave","Dorset Way","Procopio Dr","Procopio Blvd",
              "Procopio Way","Procopio Pass","Zancudo Ave","Zancudo Rd","Zancudo Way","Great Ocean Ave",
              "Great Ocean Rd","Great Ocean Terrace","Burton Blvd","Burton Way","Burton St","Burton Dr",
              "La Mesa Dr","La Mesa Blvd","La Mesa Heights","La Mesa Ave","Temple Dr","Temple St",
              "Rockford Plaza","Rockford Row","Strangeways Alley","Strangeways Rd","Eclipse Tower Rd",
              "Viceroy Rd","Viceroy Way","Canon Dr","Canon Ave","Canon Blvd","Hawick Ave","Hawick Blvd",
              "Hawick Ln","Hawick Way","Little Seoul Blvd","Little Seoul Way","Little Seoul Dr","Vagos St",
              "Rancho Blvd South","Rancho Blvd North","Dunstable Way","Dunstable Dr","Dunstable Ave",
              "Del Perro Heights Dr","Del Perro Heights Ln","Port of Los Santos Rd","Port of Los Santos Way",
              "Palisades Dr","Palisades Ave","Palisades Blvd","Gentry Ave","Gentry Dr","Gentry Row",
              "Vinewood Walk","Vinewood Lane","Vinewood Crescent","West Eclipse Blvd","East Eclipse Blvd",
              "Inland Empire Rd","Inland Way","Vinewood Plaza","Vinewood Terrace South","Vinewood Terrace North",
              "Shoreline Dr","Shoreline Blvd","Shoreline Ave","Marina View Dr","Marina Way","Marina Place",
              "Pillbox Hill Ave","Pillbox Hill Way","Chumash Rd","Chumash Dr","Chumash Ave","Grapeseed Rd",
              "Harmony Heights","Harmony Terrace","Harmony Row","Elysian Heights","Elysian Grove",
              "Del Perro Heights Ave","Del Perro Heights Blvd","North Mirror Park Dr","South Mirror Park Dr",
              "Mt Gordo Rd","Mount Gordo Pass","Mountain View Rd","Mountain View Lane","Vinewood Hills Ave",
              "Vinewood Hills Blvd","Crenshaw Dr","Crenshaw Ave","Pasadena Dr","Pasadena Ave","Viceroy Ave",
              "Viceroy Blvd","Alta Street North","Alta Street South","West Vinewood Ave","East Vinewood Ave",
              "Prosperity St","Prosperity Ave","Prosperity Blvd","Sunbeam Ave","Sunbeam Rd","Sunbeam Drive",
              "Ocean Breeze Dr","Ocean Breeze Ave","Pier View Rd","Pier View Ln","Beacon St","Beacon Ave",
              "Beacon Blvd","Seagull Rd","Seagull Ln","Driftwood Dr","Driftwood Ave","Laguna Blvd",
              "Laguna Ave","Laguna Pl","Bayside Dr","Bayside Ave","Bayside Blvd","Cove Dr","Cove Ave",
              "Cove Court","Seaport Blvd","Seaport Dr","Seaport Lane","Boardwalk Court","Boardwalk Way",
              "Fishermans Wharf Rd","Fishermans Wharf Ln","Dockside Ave","Quayside Dr","Quayside Blvd",
              "Palm Grove Rd","Palm Grove Ln","Palm Grove Ave","Palmyra Ave","Palmyra Dr","Palmyra Blvd",
              "Holloway Ln","Holloway Dr","Holloway Ave","Lampost Row","Lampost Lane","Clayton Rd",
              "Clayton Ave","Clayton St","Banyan St","Banyan Ave","Banyan Blvd","Juniper Dr","Juniper Ave",
              "Juniper Ln","Whittaker Rd","Whittaker Ave","Whittaker Blvd","Ridge Crest Dr","Ridge View Ln",
              "Ridgepoint Ave","Sierra Way","Sierra Rd","Sierra Blvd","Canyon Rd","Canyon Dr","Canyon Ave",
              "Bluffs Dr","Bluffs Ave","Bluffs Ln","Harrows St","Harrows Ave","Harrows Blvd","Kingsway Dr",
              "Kingsway Ave","Kingsway Blvd","Crown St","Crown Ave","Crown Blvd","Regent St","Regent Ave",
              "Regent Blvd","Meridian Dr","Meridian Ave","Front St","Front Ave","Front Blvd","Union St",
              "Union Ave","Union Blvd","Liberty St","Liberty Ave","Liberty Blvd","Chancellor Rd","Chancellor Ave",
              "Beacon Hill Rd","Beacon Hill Ave","Beacon Hill Ln","Maplewood Dr","Maplewood Ave","Maplewood Ln",
              "Old Grove Rd","Old Grove Ln","Old Mill Rd","Old Mill Ln","Founders Way","Founders Ave",
              "Founders Blvd","Vista Point Dr","Vista Point Ave","Vista Point Ln","Harborfront Dr",
              "Harborfront Ave","Seacliff Terrace","Del Perro Terrace","Vinewood Terrace East","Vinewood Terrace West"
            }
              local name = fn[math.random(#fn)].." "..ln[math.random(#ln)]
              local year = 2025 - math.random(18, 60)
              local dob  = string.format("%02d/%02d/%04d",
                            math.random(1,12), math.random(1,28), year)
              local addr = string.format("%d %s", math.random(100,999),
                            st[math.random(#st)])
              local sig = ""
              for i=1,5 do sig = sig .. string.char(math.random(65,90)) end
              local profile = enrichPedImmersionProfile(ped, {
                      name = name, dob = dob, address = addr,
                      signature = sig, idRequests = 0, lastIdOutcome = nil,
                      wanted = false, suspended = false
              })
              return profile
            end


            ensurePerson = function(netId)
              pedData = pedData or {}
              local key = tostring(netId or "")
              if key == "" then return {} end

              local d = pedData[key]
              if type(d) ~= "table" then d = nil end

              -- If entry exists but is empty (common when other helpers create the bucket),
              -- generate a person so ID checks never show nil fields.
              if not d or d.name == nil or d.dob == nil or d.address == nil or d.signature == nil then
                if generatePerson then
                  local ped = safeNetToPed(netId)
                  local ok, p = pcall(generatePerson, ped)
                  if ok and type(p) == "table" then
                    pedData[key] = p
                    d = p
                  else
                    pedData[key] = pedData[key] or {}
                    d = pedData[key]
                  end
                else
                  pedData[key] = pedData[key] or {}
                  d = pedData[key]
                end
              end
              local ped = safeNetToPed(netId)
              if ped and DoesEntityExist(ped) and enrichPedImmersionProfile then
                d = enrichPedImmersionProfile(ped, d or {})
                pedData[key] = d
              end
              return d
            end


            local function notify(id, title, desc, typ, icon, iconColor)
              if lib and lib.notify then
                lib.notify({
                  id           = id,
                  title        = title,
                  description  = desc,
                  type         = typ or 'inform',
                  icon         = icon,
                  iconColor    = iconColor,
                  position     = 'top-right',
                  duration     = 4000,
                  showDuration = true,
                  style        = {
                    backgroundColor = '#1e1e2e',
                    color           = '#e0def4',
                    boxShadow       = 'none',
                    border          = '1px solid rgba(255,255,255,0.08)',
                    ['.description']= { color = '#a6adc8' }
                  },
                  sound = {
                    bank = 'HUD_AWARDS',
                    set  = 'HUD_AWARDS',
                    name = (typ=='error' and 'LOSER' or 'TIMER')
                  }
                })
              else
                dprint("notify:", id, title, desc)
                print(string.format("[Az-5PD][%s] %s - %s", typ or "info", title or "", desc or ""))
              end
            end

            local function safeProgressBar(opts)
              if lib and lib.progressBar then
                return lib.progressBar(opts)
              else
                if opts and opts.duration then Citizen.Wait(opts.duration) end
                return true
              end
            end

            local activeSpeech3D = nil
            local activeFollowPedNet = nil

            local function drawWorldTextAt(coords, text3d)
              if not coords or not text3d or text3d == '' then return end
              local onScreen, sx, sy = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
              if not onScreen then return end
              SetTextScale(0.34, 0.34)
              SetTextFont(4)
              SetTextProportional(1)
              SetTextCentre(true)
              SetTextColour(255,255,255,235)
              SetTextOutline()
              BeginTextCommandDisplayText('STRING')
              AddTextComponentSubstringPlayerName(text3d)
              EndTextCommandDisplayText(sx, sy)
            end

            local function showSpeechBubble3D(ped, label, duration)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              activeSpeech3D = {
                ped = ped,
                text = tostring(label or ''),
                untilAt = GetGameTimer() + (duration or 5500)
              }
            end

            Citizen.CreateThread(function()
              while true do
                if activeSpeech3D and activeSpeech3D.untilAt and GetGameTimer() < activeSpeech3D.untilAt and activeSpeech3D.ped and DoesEntityExist(activeSpeech3D.ped) then
                  local c = GetEntityCoords(activeSpeech3D.ped)
                  drawWorldTextAt(vector3(c.x, c.y, c.z + 1.1), activeSpeech3D.text)
                  Citizen.Wait(0)
                else
                  activeSpeech3D = nil
                  Citizen.Wait(150)
                end
              end
            end)

            local function getCurrentInteractionPed()
              if lastPedNetId then
                local ped = safeNetToPed(tonumber(lastPedNetId) or lastPedNetId)
                if ped and ped ~= 0 and DoesEntityExist(ped) then return ped, tostring(lastPedNetId) end
              end
              if pullVeh and pullVeh ~= 0 and DoesEntityExist(pullVeh) then
                local driver = GetPedInVehicleSeat(pullVeh, -1)
                if driver and driver ~= 0 and DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                  local n = tostring(safePedToNet(driver) or '')
                  if n ~= '' then lastPedNetId = n end
                  return driver, n
                end
              end
              return nil, nil
            end

            local function getQuestionResponse(info, category)
              info = type(info) == 'table' and info or {}
              local cat = tostring(category or 'general')
              local line = ''
              local title = 'Question Response'
              if cat == 'documentation' then
                title = 'Documentation Response'
                if info.suspended then
                  line = "My license should still be okay... the paperwork might just be out of date."
                elseif info.wanted then
                  line = "It's here somewhere. Give me a second, I'm trying to find it."
                elseif info.nervous then
                  line = "Yes, officer. I have it. Sorry, just a little nervous right now."
                else
                  line = "Sure. My license, registration, and insurance are right here."
                end
              elseif cat == 'travel' then
                title = 'Travel Plans'
                if info.isDrunk or info.isHigh then
                  line = "I'm just heading up the road. I think I missed my turn a little bit ago."
                elseif info.wanted then
                  line = "Just trying to get home and be on my way."
                elseif info.hasIllegalItems then
                  line = "Coming from a friend's place. Nothing major, just heading through."
                else
                  line = "Heading home from work and cutting through here to save time."
                end
              elseif cat == 'dui' then
                title = 'DUI Response'
                if info.isDrunk then
                  line = "I'm fine to drive. I only had a couple earlier."
                elseif info.isHigh then
                  line = "No, officer. I'm just tired, that's all."
                elseif info.nervous then
                  line = "No drinking. I'm just anxious right now."
                else
                  line = "No alcohol, no drugs. I'm completely sober."
                end
              elseif cat == 'personal' then
                title = 'Personal Questions'
                if info.wanted then
                  line = "I'd rather keep this as short as possible if that's alright."
                elseif info.nervous then
                  line = "I live nearby. Sorry if I seem off, traffic stops make me nervous."
                elseif info.hasIllegalItems then
                  line = "Nothing much going on. Just trying to finish my day and get home."
                else
                  line = "Name's " .. tostring(info.name or 'Unknown') .. ". I live in the county and work around here."
                end
              end
              return title, line
            end

            local rememberDetainedVehicleState

            local rememberDetainedVehicleState

            local function showPedQuestionHeadText(ped, text, durationMs)
              durationMs = durationMs or 5000
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
            
              CreateThread(function()
                local endAt = GetGameTimer() + durationMs
                while GetGameTimer() < endAt do
                  Wait(0)
                  if not DoesEntityExist(ped) then break end
            
                  local pedCoords = GetEntityCoords(ped)
                  local playerCoords = GetGameplayCamCoord()
                  local dist = #(playerCoords - pedCoords)
            
                  if dist <= 20.0 then
                    DrawText3D(pedCoords.x, pedCoords.y, pedCoords.z + 1.05, text)
                  end
                end
              end)
            end
            
            local function askPedQuestion(category)
              local ped, netId = getCurrentInteractionPed()
              if not ped or not DoesEntityExist(ped) then
                return notify('question_none', 'No Subject', 'No nearby NPC is available for questioning.', 'warning', 'comments', '#DD6B20')
              end
            
              local pedKey = tostring(netId or safePedToNet(ped) or ped)
              local info = ensurePerson(pedKey)
              local inVehicle = IsPedInAnyVehicle(ped, false)
              local veh = inVehicle and GetVehiclePedIsIn(ped, false) or 0
            
              if inVehicle then
                pedData = pedData or {}
                pedData[pedKey] = pedData[pedKey] or {}
                pedData[pedKey].pulledInVehicle = true
                pedData[pedKey].pulledProtected = true
                pedData[pedKey].questioningInVehicle = true
                pedData[pedKey].allowVehicleExitUntil = nil
                pedData[pedKey].preventVehicleReseatUntil = nil
            
                if rememberDetainedVehicleState then
                  rememberDetainedVehicleState(ped, pedKey, veh)
                end
            
                NetworkRequestControlOfEntity(ped)
            
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                  NetworkRequestControlOfEntity(veh)
                  SetVehicleEngineOn(veh, true, true, true)
                  SetVehicleHandbrake(veh, true)
                  SetVehicleDoorsLocked(veh, 4)
            
                  -- keep them seated
                  TaskVehicleTempAction(ped, veh, 27, 1500)
                  SetPedIntoVehicle(ped, veh, -1)
                end
            
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                holdPedAttention(ped, true)
                monitorKeepInVehicle(pedKey, veh, 20000)
              else
                TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1800)
                TaskLookAtEntity(ped, PlayerPedId(), 2500, 2048, 3)
              end
            
              local title, line = getQuestionResponse(info, category)
            
              -- keep ox_lib / notify
              notify('question_' .. tostring(category), title, line, 'inform', 'comments', '#4299E1')
            
              -- add back the floating text above their head
              showPedQuestionHeadText(ped, line, 5000)
            
              if inVehicle and pedData and pedData[pedKey] then
                pedData[pedKey].questioningInVehicle = nil
                monitorKeepInVehicle(pedKey, veh, 12000)
              end
            end

            local function setPedFollowState(enable)
              local ped, netId = getCurrentInteractionPed()
              if not ped or not DoesEntityExist(ped) then
                return notify('follow_none', 'No Subject', 'No nearby NPC available.', 'warning', 'person-walking', '#DD6B20')
              end
              if enable then
                if IsPedInAnyVehicle(ped, false) then
                  return notify('follow_vehicle', 'Still In Vehicle', 'Tell them to exit first if you want them to follow on foot.', 'warning', 'person-walking', '#DD6B20')
                end
                ClearPedTasks(ped)
                SetBlockingOfNonTemporaryEvents(ped, true)
                TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -1.2, 0.0, 2.0, -1, 1.5, true)
                SetPedKeepTask(ped, true)
                activeFollowPedNet = tostring(netId or '')
                notify('follow_on', 'Follow Me', 'Subject is following you on foot.', 'success', 'person-walking', '#38A169')
              else
                ClearPedTasks(ped)
                SetPedKeepTask(ped, false)
                SetBlockingOfNonTemporaryEvents(ped, false)
                TaskStandStill(ped, 1500)
                activeFollowPedNet = nil
                notify('follow_off', 'Stop Follow', 'Subject was told to stop following.', 'inform', 'hand', '#4299E1')
              end
            end

            Citizen.CreateThread(function()
              while true do
                if activeFollowPedNet and activeFollowPedNet ~= '' then
                  local ped = safeNetToPed(tonumber(activeFollowPedNet) or activeFollowPedNet)
                  if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -1.2, 0.0, 2.0, -1, 1.2, true)
                    Citizen.Wait(800)
                  else
                    activeFollowPedNet = nil
                    Citizen.Wait(500)
                  end
                else
                  Citizen.Wait(500)
                end
              end
            end)

            local function getNearbyUsableVehicle(radius)
              local player = PlayerPedId()
              local coords = GetEntityCoords(player)
              if IsPedInAnyVehicle(player, false) then
                local veh = GetVehiclePedIsIn(player, false)
                if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
              end
              if pullVeh and pullVeh ~= 0 and DoesEntityExist(pullVeh) and #(coords - GetEntityCoords(pullVeh)) <= (radius or 8.0) then
                return pullVeh
              end
              if lib and lib.getClosestVehicle then
                local v = lib.getClosestVehicle(coords, radius or 8.0, false)
                if type(v) == 'table' then v = v.vehicle or v end
                if v and v ~= 0 and DoesEntityExist(v) then return v end
              end
              return 0
            end

            local function seatIndexLabel(seat)
              if seat == -1 then return 'Driver' end
              if seat == 0 then return 'Front Passenger' end
              if seat == 1 then return 'Rear Left' end
              if seat == 2 then return 'Rear Right' end
              return 'Seat ' .. tostring(seat)
            end

            local function tellPedEnterVehicle()
              local ped, netId = getCurrentInteractionPed()
              if not ped or not DoesEntityExist(ped) then
                return notify('enter_none', 'No Subject', 'No nearby NPC available.', 'warning', 'car-side', '#DD6B20')
              end
              local veh = getNearbyUsableVehicle(10.0)
              if not veh or veh == 0 or not DoesEntityExist(veh) then
                return notify('enter_noveh', 'No Vehicle', 'No nearby vehicle found for the subject.', 'warning', 'car-side', '#DD6B20')
              end
              local seats = { -1, 0, 1, 2 }
              local options = {}
              for _, seat in ipairs(seats) do
                options[#options + 1] = { value = tostring(seat), label = seatIndexLabel(seat) }
              end
              local input = lib and lib.inputDialog and lib.inputDialog('Tell Subject To Enter Vehicle', {
                { type = 'select', label = 'Seat', options = options, required = true, default = tostring(IsVehicleSeatFree(veh, -1) and -1 or 0) }
              }) or nil
              if not input or not input[1] then return end
              local seat = tonumber(input[1]) or 0
              if not IsVehicleSeatFree(veh, seat) then
                return notify('enter_busy', 'Seat Occupied', seatIndexLabel(seat) .. ' is occupied.', 'warning', 'car-side', '#DD6B20')
              end
              NetworkRequestControlOfEntity(ped)
              NetworkRequestControlOfEntity(veh)
              SetBlockingOfNonTemporaryEvents(ped, true)
              ClearPedTasksImmediately(ped)
              TaskEnterVehicle(ped, veh, 10000, seat, 1.25, 1, 0)
              if netId and pedData and pedData[tostring(netId)] then
                pedData[tostring(netId)].detainedVehicleNet = VehToNet(veh)
                pedData[tostring(netId)].detainedSeat = seat
                pedData[tostring(netId)].pulledInVehicle = true
              end
              notify('enter_start', 'Enter Vehicle', 'Subject was told to get into ' .. seatIndexLabel(seat) .. '.', 'inform', 'car-side', '#4299E1')
            end

            local getPrimaryOccupant

            local function releasePulloverVehicle(veh)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return end
              local occ = getPrimaryOccupant(veh)
              NetworkRequestControlOfEntity(veh)
              if occ and occ ~= 0 then NetworkRequestControlOfEntity(occ) end
              if occ and occ ~= 0 and DoesEntityExist(occ) then
                local occKey = tostring(safePedToNet(occ) or occ)
                if pedData and pedData[occKey] then
                  pedData[occKey].pulledProtected = false
                  pedData[occKey].pulledInVehicle = false
                  pedData[occKey].forcedStop = nil
                  pedData[occKey].detainedVehicleNet = nil
                  pedData[occKey].detainedSeat = nil
                  pedData[occKey].allowVehicleExitUntil = nil
                  pedData[occKey].preventVehicleReseatUntil = nil
                  pedData[occKey].questioningInVehicle = nil
                  pedData[occKey].stopAwaitingId = false
                  pedData[occKey].cuffed = false
                end
                setPedProtected(occKey, false)
                markPulledInVehicle(occKey, false)
                SetEnableHandcuffs(occ, false)
                ClearPedSecondaryTask(occ)
                SetBlockingOfNonTemporaryEvents(occ, false)
                SetPedCanRagdoll(occ, true)
                SetPedKeepTask(occ, false)
                if not IsPedInVehicle(occ, veh, false) or GetPedInVehicleSeat(veh, -1) ~= occ then
                  ClearPedTasksImmediately(occ)
                  TaskWarpPedIntoVehicle(occ, veh, -1)
                  Citizen.Wait(150)
                  if not IsPedInVehicle(occ, veh, false) or GetPedInVehicleSeat(veh, -1) ~= occ then
                    SetPedIntoVehicle(occ, veh, -1)
                    Citizen.Wait(120)
                  end
                end
              end
              SetVehicleEngineOn(veh, true, true, true)
              SetVehicleHandbrake(veh, false)
              SetVehicleUndriveable(veh, false)
              SetVehicleDoorsLocked(veh, 1)
              SetVehicleBrakeLights(veh, false)
              SetVehicleForwardSpeed(veh, math.max(GetEntitySpeed(veh), 2.5))
              if occ and occ ~= 0 and DoesEntityExist(occ) then
                local occKey = tostring(safePedToNet(occ) or occ)
                SetDriverAbility(occ, Config.Flee.driverAbility or 1.0)
                SetDriverAggressiveness(occ, Config.Flee.driverAggressiveness or 0.35)
                SetPedKeepTask(occ, true)
                local function taskDriveAwayNow()
                  if not (DoesEntityExist(veh) and DoesEntityExist(occ)) then return end
                  ClearPedTasks(occ)
                  SetPedKeepTask(occ, true)
                  SetVehicleEngineOn(veh, true, true, true)
                  SetVehicleHandbrake(veh, false)
                  SetVehicleUndriveable(veh, false)
                  SetVehicleDoorsLocked(veh, 1)
                  SetVehicleBrakeLights(veh, false)
                  SetVehicleForwardSpeed(veh, math.max(GetEntitySpeed(veh), 4.5))
                  local base = GetEntityCoords(veh)
                  local heading = math.rad(GetEntityHeading(veh))
                  local tx = base.x - math.sin(heading) * 120.0
                  local ty = base.y + math.cos(heading) * 120.0
                  local tz = base.z + 0.5
                  if type(SetDriveTaskDrivingStyle) == 'function' then pcall(SetDriveTaskDrivingStyle, occ, Config.Wander.driveStyle) end
                  if type(SetDriveTaskCruiseSpeed) == 'function' then pcall(SetDriveTaskCruiseSpeed, occ, math.max(10.0, tonumber(Config.Wander.driveSpeed) or 16.0)) end
                  if type(TaskVehicleDriveToCoordLongrange) == 'function' then
                    TaskVehicleDriveToCoordLongrange(occ, veh, tx, ty, tz, math.max(10.0, tonumber(Config.Wander.driveSpeed) or 16.0), Config.Wander.driveStyle, 10.0)
                  else
                    TaskVehicleDriveWander(occ, veh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                  end
                end

                -- Finishing a pull-over should always release the driver in-place and let them drive away.
                -- Do not convert the release into an attack/flee-on-foot just because the record is suspended/wanted.
                taskDriveAwayNow()
                Citizen.CreateThread(function()
                  local startedAt = GetGameTimer()
                  local startPos = GetEntityCoords(veh)
                  while GetGameTimer() - startedAt < 8000 do
                    if not DoesEntityExist(veh) or not DoesEntityExist(occ) then return end
                    if not IsPedInVehicle(occ, veh, false) or GetPedInVehicleSeat(veh, -1) ~= occ then
                      ClearPedTasksImmediately(occ)
                      TaskWarpPedIntoVehicle(occ, veh, -1)
                      Citizen.Wait(150)
                      if not IsPedInVehicle(occ, veh, false) or GetPedInVehicleSeat(veh, -1) ~= occ then
                        SetPedIntoVehicle(occ, veh, -1)
                      end
                    end
                    if #(GetEntityCoords(veh) - startPos) > 12.0 then return end
                    taskDriveAwayNow()
                    Citizen.Wait(800)
                  end
                  if DoesEntityExist(veh) and DoesEntityExist(occ) then
                    TaskVehicleDriveWander(occ, veh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                    if type(SetDriveTaskCruiseSpeed) == 'function' then pcall(SetDriveTaskCruiseSpeed, occ, math.max(10.0, tonumber(Config.Wander.driveSpeed) or 16.0)) end
                  end
                end)
              end
              pullVeh = nil
              notify('pull_finish', 'Pull-Over', 'Complete. Vehicle released.', 'success', 'car-side', '#38A169')
            end
            local function getPedName(netId)
              local d = pedData[tostring(netId)]
              return (d and d.name) or "Unknown Unknown"
            end

            local function loadAnimDictTimed(dict, timeout)
              timeout = timeout or 1200
              if HasAnimDictLoaded(dict) then return true end
              RequestAnimDict(dict)
              local started = GetGameTimer()
              while not HasAnimDictLoaded(dict) and (GetGameTimer() - started) < timeout do Citizen.Wait(10) end
              return HasAnimDictLoaded(dict)
            end

            local function playSimpleConversationAnim(ped, mode)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local player = PlayerPedId()
              local pedInVehicle = IsPedInAnyVehicle(ped, false)
              if pedInVehicle then
                TaskLookAtEntity(ped, player, 2500, 2048, 3)
                return
              end
              TaskTurnPedToFaceEntity(ped, player, 1200)
              TaskLookAtEntity(ped, player, 2500, 2048, 3)
              local dict = "mp_common"
              if loadAnimDictTimed(dict, 1200) then
                if mode == "handoff" then
                  TaskPlayAnim(player, dict, "givetake1_a", 4.0, -4.0, 1400, 49, 0.0, false, false, false)
                end
                TaskPlayAnim(ped, dict, "givetake1_b", 4.0, -4.0, 1400, 49, 0.0, false, false, false)
              end
            end

            local function getStoredDetainedVehicle(netId, fallbackVeh)
              local veh = fallbackVeh
              if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
              local info = netId and pedData and pedData[tostring(netId)] or nil
              if info and info.detainedVehicleNet then
                local netVeh = safeNetworkGetEntityFromNetworkId(tonumber(info.detainedVehicleNet) or info.detainedVehicleNet)
                if netVeh and netVeh ~= 0 and DoesEntityExist(netVeh) then
                  return netVeh
                end
              end
              if pullVeh and pullVeh ~= 0 and DoesEntityExist(pullVeh) then return pullVeh end
              return 0
            end

            rememberDetainedVehicleState = function(ped, netId, veh)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              if not netId then netId = safePedToNet(ped) or tostring(ped) end
              if not netId then return end
              pedData[tostring(netId)] = pedData[tostring(netId)] or {}
              pedData[tostring(netId)].allowVehicleExitUntil = nil
              pedData[tostring(netId)].preventVehicleReseatUntil = nil
              if veh and veh ~= 0 and DoesEntityExist(veh) then
                pedData[tostring(netId)].detainedVehicleNet = VehToNet(veh)
                for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                  if GetPedInVehicleSeat(veh, seat) == ped then
                    pedData[tostring(netId)].detainedSeat = seat
                    break
                  end
                end
              end
            end

            local function shouldKeepPedSeated(info)
              if not info then return false end
              local now = GetGameTimer()
              local allowExitUntil = tonumber(info.allowVehicleExitUntil or 0) or 0
              local preventReseatUntil = tonumber(info.preventVehicleReseatUntil or 0) or 0
              if allowExitUntil > now or preventReseatUntil > now then
                return false
              end
              if info.pulledInVehicle or info.pulledProtected then
                return true
              end
              if info.cuffed and info.detainedVehicleNet then
                return true
              end
              return false
            end

            local function enforcePedRemainSeated(ped, netId, fallbackVeh)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              local info = netId and pedData and pedData[tostring(netId)] or nil
              if info and not shouldKeepPedSeated(info) and not IsPedInAnyVehicle(ped, false) then
                return false
              end
              if IsPedInAnyVehicle(ped, false) then
                rememberDetainedVehicleState(ped, netId, GetVehiclePedIsIn(ped, false))
                return true
              end

              local veh = getStoredDetainedVehicle(netId, fallbackVeh)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

              local info = netId and pedData and pedData[tostring(netId)] or nil
              local preferredSeat = (info and tonumber(info.detainedSeat)) or -1
              local seat = preferredSeat
              if seat < -1 then seat = -1 end
              if GetPedInVehicleSeat(veh, seat) ~= 0 and GetPedInVehicleSeat(veh, seat) ~= ped then
                local foundFree = false
                for trySeat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                  local occ = GetPedInVehicleSeat(veh, trySeat)
                  if occ == 0 or occ == ped then
                    seat = trySeat
                    foundFree = true
                    break
                  end
                end
                if not foundFree then return false end
              end

              NetworkRequestControlOfEntity(ped)
              NetworkRequestControlOfEntity(veh)
              SetEntityAsMissionEntity(ped, true, true)
              SetEntityAsMissionEntity(veh, true, true)
              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedKeepTask(ped, true)
              TaskWarpPedIntoVehicle(ped, veh, seat)
              Citizen.Wait(50)
              if not (IsPedInVehicle(ped, veh, false) and GetPedInVehicleSeat(veh, seat) == ped) then
                SetPedIntoVehicle(ped, veh, seat)
                Citizen.Wait(50)
              end
              if IsPedInVehicle(ped, veh, false) then
                rememberDetainedVehicleState(ped, netId, veh)
                return true
              end
              return false
            end

            local function requestPedIdentification(ped, netId)
              local pedKey = tostring(netId or safePedToNet(ped) or ped)
              local person = ensurePerson(pedKey)
              person.idRequests = tonumber(person.idRequests or 0) or 0
              person.idRequests = person.idRequests + 1
              local refusalChance = tonumber(person.idRefusalChance or 0.18) or 0.18
              local info = pedData and pedData[pedKey] or nil
              local protectedStop = info and (info.pulledInVehicle or info.pulledProtected)
              local forcedStop = info and info.forcedStop
              if person.idRequests >= 2 then refusalChance = refusalChance * 0.5 end
              if person.hasIllegalItems then refusalChance = math.max(refusalChance, 0.32) end
              if person.isDrunk or person.isHigh then refusalChance = math.max(refusalChance, 0.28) end
              if IsPedInAnyVehicle(ped, false) or protectedStop then refusalChance = math.max(0.05, refusalChance - 0.05) end
              if forcedStop then refusalChance = 0.0 end

              if protectedStop then
                enforcePedRemainSeated(ped, pedKey)
                TaskLookAtEntity(ped, PlayerPedId(), 2500, 2048, 3)
              end

              if math.random() < refusalChance then
                person.lastIdOutcome = "refused"
                if protectedStop then
                  holdPedAttention(ped, true)
                else
                  playSimpleConversationAnim(ped, "refuse")
                  holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
                end
                notify("id_refuse","ID Check","Ped refuses to provide identification.",'warning','triangle-exclamation','#DD6B20')
                return false, person
              end
              person.lastIdOutcome = "provided"
              if protectedStop then
                holdPedAttention(ped, true)
              else
                playSimpleConversationAnim(ped, "handoff")
                holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
              end
              return true, person
            end

            local function showIDCard(d)
              local status = d.wanted and " (WANTED)" or ""
              notify("show_id","ID Card",
                ("Name: %s%s\nDOB: %s\nAddress: %s\nSignature: %s")
                :format(d.name, status, d.dob, d.address, d.signature),
                'success','id-card','#38A169')
            end

            local function splitFullNameForMDT(value)
              local text = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
              if text == '' then return '', '' end
              local parts = {}
              for token in text:gmatch('%S+') do parts[#parts + 1] = token end
              if #parts <= 1 then return text, '' end
              local first = table.remove(parts, 1) or ''
              return first, table.concat(parts, ' ')
            end

local ALT_OWNER_FIRST = { 'Aiden', 'Mason', 'Noah', 'Ethan', 'Lucas', 'Levi', 'Owen', 'Wyatt', 'Nora', 'Layla', 'Ava', 'Mia', 'Ella', 'Zoe', 'Ivy', 'Ruby' }
local ALT_OWNER_LAST = { 'Parker', 'Turner', 'Hayes', 'Brooks', 'Bennett', 'Foster', 'Coleman', 'Reed', 'Sullivan', 'Murphy', 'Fisher', 'Powell', 'Howard', 'Jenkins', 'Bishop', 'Barnes' }

local function randomAlternateVehicleOwnerName(fallback)
  fallback = tostring(fallback or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local candidate = ALT_OWNER_FIRST[math.random(#ALT_OWNER_FIRST)] .. ' ' .. ALT_OWNER_LAST[math.random(#ALT_OWNER_LAST)]
  if fallback ~= '' and candidate == fallback then
    candidate = ALT_OWNER_FIRST[((math.random(#ALT_OWNER_FIRST)) % #ALT_OWNER_FIRST) + 1] .. ' ' .. ALT_OWNER_LAST[((math.random(#ALT_OWNER_LAST)) % #ALT_OWNER_LAST) + 1]
  end
  return candidate
end

local function getVehicleLookupIdentityProfile(pedKey, plate, fallbackOwnerName)
  pedKey = tostring(pedKey or '')
  plate = tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
  fallbackOwnerName = tostring(fallbackOwnerName or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if pedKey == '' or plate == '' then
    return {
      ownerName = fallbackOwnerName,
      status = 'VALID',
      registeredToDriver = fallbackOwnerName ~= ''
    }
  end

  pedData[pedKey] = pedData[pedKey] or {}
  local info = pedData[pedKey]
  info._vehicleLookupProfile = type(info._vehicleLookupProfile) == 'table' and info._vehicleLookupProfile or {}

  if info._vehicleLookupProfile[plate] then
    return info._vehicleLookupProfile[plate]
  end

  local cfg = ((Config and Config.Immersion and Config.Immersion.vehicleContext) or {})

  local mismatchChance = tonumber(cfg.ownerMismatchBase) or 0.12
  if info.wanted then mismatchChance = math.max(mismatchChance, tonumber(cfg.ownerMismatchWanted) or 0.40) end
  if info.hasIllegalItems then mismatchChance = math.max(mismatchChance, tonumber(cfg.ownerMismatchIllegalItems) or 0.28) end
  if info.suspended then mismatchChance = math.max(mismatchChance, tonumber(cfg.ownerMismatchSuspended) or 0.22) end
  if info.isDrunk or info.isHigh then mismatchChance = math.max(mismatchChance, tonumber(cfg.ownerMismatchImpaired) or 0.18) end

  local noneChance = tonumber(cfg.noRegistrationBase) or 0.03
  if info.wanted then noneChance = math.max(noneChance, tonumber(cfg.noRegistrationWanted) or 0.18) end
  if info.hasIllegalItems then noneChance = math.max(noneChance, tonumber(cfg.noRegistrationIllegalItems) or 0.12) end

  local suspendedChance = tonumber(cfg.suspendedRegistrationBase) or 0.02
  if info.suspended then suspendedChance = math.max(suspendedChance, tonumber(cfg.suspendedRegistrationSuspended) or 0.18) end

  local expiredChance = tonumber(cfg.expiredRegistrationBase) or 0.08
  if info.wanted then expiredChance = math.max(expiredChance, tonumber(cfg.expiredRegistrationWanted) or 0.14) end
  if info.hasIllegalItems then expiredChance = math.max(expiredChance, tonumber(cfg.expiredRegistrationIllegalItems) or 0.12) end

  local ownerName = fallbackOwnerName
  local registeredToDriver = true
  if fallbackOwnerName == '' or math.random() < mismatchChance then
    ownerName = randomAlternateVehicleOwnerName(fallbackOwnerName)
    registeredToDriver = false
  end

  local status = 'VALID'
  local roll = math.random()
  if roll < noneChance then
    status = 'NONE'
  elseif roll < (noneChance + suspendedChance) then
    status = 'SUSPENDED'
  elseif roll < (noneChance + suspendedChance + expiredChance) then
    status = 'EXPIRE'
  end

  local profile = {
    ownerName = ownerName ~= '' and ownerName or fallbackOwnerName,
    status = status,
    registeredToDriver = registeredToDriver
  }

  info._vehicleLookupProfile[plate] = profile
  pedData[pedKey] = info
  return profile
end

            local function showID(netId)
              local ped = safeNetToPed(netId)
              local d = pedData[tostring(netId)]
              if not d then
                return notify("no_id","ID Check","No ID data for this ped.",'error','id-badge','#C53030')
              end
              if ped and DoesEntityExist(ped) then
                local okToShow = requestPedIdentification(ped, netId)
                if not okToShow then return end
              end
              local mdtFirst, mdtLast = splitFullNameForMDT((d and d.name) or tostring(netId or ''))
              local shouldOpenExternal = Config and Config.MDT and Config.MDT.openExternalOnCheckId == true
              if shouldOpenExternal and openExternalMDT({
                kind = 'name',
                preservePage = true,
                prefillOnly = true,
                autoSearch = false,
                search = {
                  kind = 'name',
                  value = (d and d.name) or tostring(netId or ''),
                  name = (d and d.name) or tostring(netId or ''),
                  first = mdtFirst,
                  last = mdtLast,
                  netId = tostring(netId or ''),
                  source = 'az5pd',
                  preservePage = true,
                  prefillOnly = true,
                  autoSearch = false
                }
              }) then
                return showIDCard(d)
              end
              TriggerServerEvent('mdt:lookupID', netId)
              showIDCard(d)
            end

            local
            function resolveLastPed()

              dprint("resolveLastPed: start lastPedNetId=", tostring(lastPedNetId), " lastPedEntity=", tostring(lastPedEntity))

              if lastPedEntity and type(lastPedEntity) == "number" and DoesEntityExist(lastPedEntity) then
                local ent = lastPedEntity
                local ok, nid = pcall(function() return PedToNet(ent) end)
                if ok and nid and nid ~= 0 then
                  dprint("resolveLastPed: returning entity with netId", nid)
                  return ent, nid
                end
                dprint("resolveLastPed: returning local entity without netId")
                return ent, nil
              end

              if lastPedNetId then
                local ent, nid = resolvePed(lastPedNetId)
                if ent and DoesEntityExist(ent) then
                  dprint("resolveLastPed: resolved from netId -> entity=", tostring(ent), " nid=", tostring(nid))
                  return ent, nid
                end

                local ent2 = safeNetworkGetEntityFromNetworkId(tonumber(lastPedNetId) or lastPedNetId)
                if ent2 and ent2 ~= 0 and DoesEntityExist(ent2) then
                  local ok2, nid2 = pcall(function() return PedToNet(ent2) end)
                  if ok2 and nid2 and nid2 ~= 0 then
                    dprint("resolveLastPed: secondary resolved entity with netid", nid2)
                    return ent2, nid2
                  end
                  return ent2, nil
                end
              end

              dprint("resolveLastPed: failed to resolve ped")
              return nil, nil
            end

            local function cachePedReference(ped, key)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return tostring(key or '') end
              local pedKey = tostring(key or safePedToNet(ped) or ped)
              ensurePerson(pedKey)
              pedData[pedKey] = pedData[pedKey] or {}
              pedData[pedKey].entity = ped
              local safeNet = safePedToNet(ped)
              if safeNet and safeNet ~= 0 then
                pedData[pedKey].netId = tostring(safeNet)
              else
                pedData[pedKey].netId = pedData[pedKey].netId or tostring(key or '')
              end
              return pedKey
            end

            local function resolveTrackedPedFromKey(key, info)
              local entry = info or pedData[tostring(key)]
              if entry and entry.entity and DoesEntityExist(entry.entity) then
                return entry.entity, tostring((entry.netId and entry.netId ~= '') and entry.netId or key)
              end

              local candidateKey = nil
              if entry and entry.netId and tostring(entry.netId) ~= '' then
                candidateKey = entry.netId
              else
                candidateKey = key
              end

              local ped = safeNetToPed(candidateKey)
              if ped and ped ~= 0 and DoesEntityExist(ped) then
                if entry then entry.entity = ped end
                return ped, tostring(candidateKey)
              end

              return nil, tostring(candidateKey or key or '')
            end

            local function playCuffedIdleAnim(ped)
              if not ped or ped == 0 or not DoesEntityExist(ped) or IsPedInAnyVehicle(ped, false) then return false end
              local dict = "mp_arresting"
              if not loadAnimDictTimed(dict, 800) then return false end
              if not IsEntityPlayingAnim(ped, dict, "idle", 3) then
                TaskPlayAnim(ped, dict, "idle", 8.0, -8.0, -1, 49, 0.0, false, false, false)
              end
              return true
            end

            local function buildPedAliasKeys(ped, pedKey)
              pedData = pedData or {}
              local aliases, seen = {}, {}

              local function remember(key)
                if key == nil then return end
                key = tostring(key)
                if key == '' or seen[key] then return end
                seen[key] = true
                aliases[#aliases + 1] = key
              end

              remember(pedKey)
              if ped and ped ~= 0 and DoesEntityExist(ped) then
                remember(safePedToNet(ped))
                remember(ped)
              end

              local pedNet = (ped and ped ~= 0 and DoesEntityExist(ped)) and tostring(safePedToNet(ped) or '') or ''
              for key, info in pairs(pedData) do
                if info then
                  local sameEntity = ped and info.entity and info.entity == ped
                  local sameNet = pedNet ~= '' and tostring(info.netId or '') == pedNet
                  local sameKey = pedKey and (tostring(key) == tostring(pedKey) or tostring(info.netId or '') == tostring(pedKey) or tostring(info.cuffCanonicalKey or '') == tostring(pedKey))
                  if sameEntity or sameNet or sameKey then
                    remember(key)
                    remember(info.netId)
                    remember(info.cuffCanonicalKey)
                  end
                end
              end

              return aliases
            end

            local function getPedCanonicalCuffKey(ped, pedKey)
              local net = (ped and ped ~= 0 and DoesEntityExist(ped)) and safePedToNet(ped) or nil
              return tostring(net or pedKey or ped or '')
            end

            local function isPedActuallyCuffed(ped, pedKey)
              local canonical = getPedCanonicalCuffKey(ped, pedKey)
              if canonical ~= '' and pedData[canonical] and pedData[canonical].cuffed == true then
                return true, canonical
              end

              local aliases = buildPedAliasKeys(ped, pedKey)
              for _, key in ipairs(aliases) do
                local info = pedData[key]
                if info and info.cuffed == true then
                  return true, tostring(info.cuffCanonicalKey or key)
                end
              end

              return false, canonical ~= '' and canonical or tostring(pedKey or '')
            end

            local function markPedCuffedState(ped, netId, state)
              local canonical = getPedCanonicalCuffKey(ped, netId)
              if canonical == '' then return nil end

              local aliases = buildPedAliasKeys(ped, canonical)
              local seenCanonical = false
              for _, key in ipairs(aliases) do
                if key == canonical then seenCanonical = true break end
              end
              if not seenCanonical then aliases[#aliases + 1] = canonical end

              local cooloffUntil = GetGameTimer() + 2200
              for _, key in ipairs(aliases) do
                ensurePerson(key)
                pedData[key] = pedData[key] or {}
                pedData[key].cuffCanonicalKey = canonical
                pedData[key].cuffed = state and true or false
                pedData[key].entity = (ped and DoesEntityExist(ped)) and ped or pedData[key].entity
                local safeNet = (ped and DoesEntityExist(ped)) and safePedToNet(ped) or nil
                if safeNet and safeNet ~= 0 then
                  pedData[key].netId = tostring(safeNet)
                elseif pedData[key].netId == nil then
                  pedData[key].netId = canonical
                end
                if state then
                  pedData[key].recentlyUncuffedUntil = nil
                  pedData[key].lastCuffAppliedAt = GetGameTimer()
                else
                  pedData[key].recentlyUncuffedUntil = cooloffUntil
                end
              end

              if state then
                lastCuffedPedNetId = canonical
                if ped and DoesEntityExist(ped) then lastCuffedPedEntity = ped end
              else
                if tostring(lastCuffedPedNetId or '') == canonical then lastCuffedPedNetId = nil end
                if ped and lastCuffedPedEntity == ped then lastCuffedPedEntity = nil end
              end

              return canonical
            end

            local function clearTrackedCuffStateForPed(ped, pedKey)
              local canonical = getPedCanonicalCuffKey(ped, pedKey)
              local aliases = buildPedAliasKeys(ped, canonical)
              local seenCanonical = false
              for _, key in ipairs(aliases) do
                if key == canonical then seenCanonical = true break end
              end
              if canonical ~= '' and not seenCanonical then aliases[#aliases + 1] = canonical end

              local cooloffUntil = GetGameTimer() + 2200
              for _, key in ipairs(aliases) do
                ensurePerson(key)
                pedData[key] = pedData[key] or {}
                pedData[key].cuffed = false
                pedData[key].cuffCanonicalKey = canonical ~= '' and canonical or pedData[key].cuffCanonicalKey
                pedData[key].recentlyUncuffedUntil = cooloffUntil
                if ped and DoesEntityExist(ped) then
                  pedData[key].entity = ped
                  local net = safePedToNet(ped)
                  if net and net ~= 0 then
                    pedData[key].netId = tostring(net)
                  end
                end
              end
            end

            local function resetPedCuffPresentation(ped, keepDetained, releaseAttention)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              NetworkRequestControlOfEntity(ped)

              if IsEntityAttached(ped) then
                DetachEntity(ped, true, false)
              end

              for _ = 1, 4 do
                StopAnimTask(ped, "mp_arresting", "idle", 1.0)
                StopAnimTask(ped, "mp_arrest_paired", "crook_p2_back_left", 1.0)
                StopAnimTask(ped, "mp_arrest_paired", "crook_p2_back_right", 1.0)
                ClearPedSecondaryTask(ped)
                if not IsPedInAnyVehicle(ped, false) then
                  ClearPedTasksImmediately(ped)
                  Citizen.Wait(0)
                  ClearPedTasks(ped)
                end
                ResetPedMovementClipset(ped, 0.0)
                ResetPedStrafeClipset(ped)
                ResetPedWeaponMovementClipset(ped)
                SetEnableHandcuffs(ped, false)
                Citizen.Wait(0)
              end

              SetPedCanRagdoll(ped, true)
              SetPedCanPlayAmbientAnims(ped, true)
              SetPedCanPlayAmbientBaseAnims(ped, true)
              SetPedKeepTask(ped, keepDetained and true or false)
              SetBlockingOfNonTemporaryEvents(ped, keepDetained and true or false)

              if keepDetained then
                if IsPedInAnyVehicle(ped, false) then
                  holdPedAttention(ped, true)
                else
                  TaskStandStill(ped, 900)
                  TaskTurnPedToFaceEntity(ped, PlayerPedId(), 900)
                  holdPedAttention(ped, false)
                end
              elseif releaseAttention then
                releasePedAttention(ped, true)
              end

              return true
            end

            local function enforceCuffedPedState(ped, pedKey, info)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              local isCuffed, canonical = isPedActuallyCuffed(ped, pedKey)
              if not isCuffed then return false end

              pedKey = cachePedReference(ped, canonical ~= '' and canonical or pedKey)
              NetworkRequestControlOfEntity(ped)
              SetEnableHandcuffs(ped, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)
              SetPedKeepTask(ped, true)

              if isDragging and draggedPed == ped and IsEntityAttached(ped) then
                return true
              end

              if IsPedInAnyVehicle(ped, false) then
                rememberDetainedVehicleState(ped, pedKey, GetVehiclePedIsIn(ped, false))
                holdPedAttention(ped, true)
                return true
              end

              if shouldKeepPedSeated(info) then
                if enforcePedRemainSeated(ped, pedKey) then
                  holdPedAttention(ped, true)
                  return true
                end
              end

              local now = GetGameTimer()
              info = info or pedData[pedKey] or {}
              info.nextGroundHoldAt = tonumber(info.nextGroundHoldAt or 0) or 0
              if info.nextGroundHoldAt <= now then
                info.nextGroundHoldAt = now + ((Config.PedCustody and Config.PedCustody.groundHoldCooldownMs) or 900)
                TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1200)
                TaskLookAtEntity(ped, PlayerPedId(), 1200, 2048, 3)
                TaskStandStill(ped, ((Config.PedCustody and Config.PedCustody.groundHoldMs) or 1500))
              end
              playCuffedIdleAnim(ped)
              return true
            end

            resolveCuffedPed = function()
              if draggedPed and DoesEntityExist(draggedPed) then
                local isCuffed, canonical = isPedActuallyCuffed(draggedPed, lastCuffedPedNetId or safePedToNet(draggedPed) or draggedPed)
                if isCuffed then
                  cachePedReference(draggedPed, canonical)
                  return draggedPed, tostring(canonical)
                end
              end

              if lastCuffedPedEntity and DoesEntityExist(lastCuffedPedEntity) then
                local isCuffed, canonical = isPedActuallyCuffed(lastCuffedPedEntity, lastCuffedPedNetId or safePedToNet(lastCuffedPedEntity) or lastCuffedPedEntity)
                if isCuffed then
                  cachePedReference(lastCuffedPedEntity, canonical)
                  return lastCuffedPedEntity, tostring(canonical)
                end
              end

              if lastCuffedPedNetId then
                local info = pedData[tostring(lastCuffedPedNetId)]
                local ent = select(1, resolveTrackedPedFromKey(lastCuffedPedNetId, info))
                if ent and ent ~= 0 and DoesEntityExist(ent) then
                  local isCuffed, canonical = isPedActuallyCuffed(ent, lastCuffedPedNetId)
                  if isCuffed then
                    cachePedReference(ent, canonical)
                    return ent, tostring(canonical)
                  end
                end
              end

              local ped, nid = resolveLastPed()
              if ped and DoesEntityExist(ped) then
                local isCuffed, canonical = isPedActuallyCuffed(ped, nid or safePedToNet(ped) or ped)
                if isCuffed then
                  lastCuffedPedNetId = tostring(canonical)
                  lastCuffedPedEntity = ped
                  cachePedReference(ped, canonical)
                  return ped, tostring(canonical)
                end
              end

              local processed = {}
              for key, info in pairs(pedData) do
                local canonical = tostring((info and info.cuffCanonicalKey) or key)
                if not processed[canonical] then
                  processed[canonical] = true
                  local ped = select(1, resolveTrackedPedFromKey(canonical, info))
                  if ped and DoesEntityExist(ped) then
                    local isCuffed = isPedActuallyCuffed(ped, canonical)
                    if isCuffed then
                      lastCuffedPedNetId = canonical
                      lastCuffedPedEntity = ped
                      cachePedReference(ped, canonical)
                      return ped, canonical
                    end
                  end
                end
              end

              return nil, nil
            end

            local function applyCuffedPedState(ped, netId, keepDraggedReference)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              local pedKey = markPedCuffedState(ped, netId, true)
              cachePedReference(ped, pedKey)
              NetworkRequestControlOfEntity(ped)
              SetEnableHandcuffs(ped, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)
              SetPedKeepTask(ped, true)
              if IsPedInAnyVehicle(ped, false) then
                rememberDetainedVehicleState(ped, pedKey, GetVehiclePedIsIn(ped, false))
              end
              if keepDraggedReference then draggedPed = ped end
              lastPedEntity = ped
              lastPedNetId = pedKey
              if holdPedAttention then holdPedAttention(ped, IsPedInAnyVehicle(ped, false)) end
              if not IsPedInAnyVehicle(ped, false) and not (isDragging and draggedPed == ped and IsEntityAttached(ped)) then
                playCuffedIdleAnim(ped)
              end
              return true
            end


            local function sendPedOnReleaseWalk(ped)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              if IsPedInAnyVehicle(ped, false) then return end

              local player = PlayerPedId()
              local pedCoords = GetEntityCoords(ped)
              local playerCoords = GetEntityCoords(player)
              local dir = vector3(pedCoords.x - playerCoords.x, pedCoords.y - playerCoords.y, 0.0)
              local len = math.sqrt((dir.x * dir.x) + (dir.y * dir.y))
              if len < 0.25 then
                local fwd = GetEntityForwardVector(player)
                dir = vector3(-fwd.x, -fwd.y, 0.0)
                len = math.sqrt((dir.x * dir.x) + (dir.y * dir.y))
              end
              if len < 0.25 then len = 1.0 end
              dir = vector3(dir.x / len, dir.y / len, 0.0)
              local walkTo = vector3(pedCoords.x + dir.x * 10.0, pedCoords.y + dir.y * 10.0, pedCoords.z)

              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, false)
              SetPedKeepTask(ped, true)
              TaskGoToCoordAnyMeans(ped, walkTo.x, walkTo.y, walkTo.z, 1.2, 0, false, 786603, 0.0)
              Citizen.CreateThread(function()
                Citizen.Wait(3500)
                if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                  ClearPedTasks(ped)
                  TaskWanderStandard(ped, 10.0, 10)
                end
              end)
            end

            local function uncuffPedOnly(ped, netId, keepDetained)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              local pedKey = tostring(netId or safePedToNet(ped) or ped)
              cachePedReference(ped, pedKey)
              NetworkRequestControlOfEntity(ped)

              if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                  SetVehicleDoorsLocked(veh, 1)
                end
              end

              markPedCuffedState(ped, pedKey, false)
              clearTrackedCuffStateForPed(ped, pedKey)
              resetPedCuffPresentation(ped, keepDetained and true or false, not keepDetained)

              if draggedPed == ped then draggedPed = nil end
              isDragging = false

              local sendNet = safePedToNet(ped) or tonumber(pedKey) or pedKey
              TriggerServerEvent('police:cuffPed', tostring(sendNet or ''), false)
              return true, getPedCanonicalCuffKey(ped, pedKey)
            end

            local function showIDSafely(netId)
              dprint("showIDSafely called with netId=", tostring(netId))
              local ped, nid

              if netId then
                nid = tonumber(netId) or netId
                ped = safeNetToPed(nid)
              end

              if not ped or ped == 0 or not DoesEntityExist(ped) then
                ped, nid = resolveLastPed()
              end

              if not ped or ped == 0 or not DoesEntityExist(ped) then
                lastPedNetId = nil
                lastPedEntity = nil
                return notify("no_id_exist","ID Check","Target no longer exists.",'error','id-badge','#C53030')
              end

              local pedKey = tostring(tonumber(nid) or nid or safePedToNet(ped) or lastPedNetId or ped)
              lastPedNetId = pedKey
              lastPedEntity = ped

              if IsPedInAnyVehicle(ped, false) then
                local detainedVeh = GetVehiclePedIsIn(ped, false)
                setPedProtected(pedKey, true)
                markPulledInVehicle(pedKey, true)
                rememberDetainedVehicleState(ped, pedKey, detainedVeh)

                NetworkRequestControlOfEntity(ped)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                holdPedAttention(ped, true)

                monitorKeepInVehicle(pedKey, detainedVeh, 8000)
              end

              -- Always ensure a local identity exists so the ID card never shows nil fields
              local pdata = ensurePerson(pedKey)
              local canShow = true
              if pdata then canShow = requestPedIdentification(ped, pedKey) end
              if not canShow then return end

              local resolvedName = (pdata and pdata.name) or tostring(pedKey or '')
              local mdtFirst, mdtLast = splitFullNameForMDT(resolvedName)
              local shouldOpenExternal = Config and Config.MDT and Config.MDT.openExternalOnCheckId == true
              if shouldOpenExternal then
                openExternalMDT({
                  kind = 'name',
                  preservePage = true,
                  prefillOnly = true,
                  autoSearch = false,
                  name = resolvedName,
                  first = mdtFirst,
                  last = mdtLast,
                  netId = tostring(pedKey or ''),
                  source = 'az5pd',
                  search = {
                    kind = 'name',
                    value = resolvedName,
                    name = resolvedName,
                    first = mdtFirst,
                    last = mdtLast,
                    netId = tostring(pedKey or ''),
                    source = 'az5pd',
                    preservePage = true,
                    prefillOnly = true,
                    autoSearch = false
                  }
                })
              end

              if pdata then showIDCard(pdata) end
              TriggerServerEvent('mdt:lookupID', pedKey)
            end

            local function getVehicleDisplayName(veh)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return "" end
              local mdl = GetEntityModel(veh)
              local disp = GetDisplayNameFromVehicleModel(mdl) or ""
              local label = GetLabelText(disp) or ""
              if label ~= "" and label ~= "NULL" then
                return label
              end
              return disp
            end

            local function getVehicleColorHint(veh)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return "" end
              local r,g,b = 0,0,0
              pcall(function() r,g,b = GetVehicleCustomPrimaryColour(veh) end)
              if (r and g and b) and (r ~= 0 or g ~= 0 or b ~= 0) then
                return string.format("RGB(%d,%d,%d)", r,g,b)
              end
              local primary, secondary = GetVehicleColours(veh)
              if primary ~= nil then
                return "PrimaryIndex:"..tostring(primary)
              end
              return ""
            end

            local function getVehicleInFrontOfPlayerCar(distance)
              local ped = PlayerPedId()
              distance = tonumber(distance) or 16.0
              if not DoesEntityExist(ped) then return nil end

              local originEntity = ped
              local from = GetEntityCoords(ped)
              local forward = GetEntityForwardVector(ped)

              if IsPedInAnyVehicle(ped, false) then
                local playerVeh = GetVehiclePedIsIn(ped, false)
                if playerVeh and playerVeh ~= 0 and DoesEntityExist(playerVeh) then
                  originEntity = playerVeh
                  from = GetOffsetFromEntityInWorldCoords(playerVeh, 0.0, 2.2, 0.6)
                  forward = GetEntityForwardVector(playerVeh)
                end
              end

              local to = vector3(from.x + forward.x * distance, from.y + forward.y * distance, from.z + forward.z * distance)
              local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 10, originEntity, 0)
              local _, hit, _, _, entity = GetShapeTestResult(ray)
              if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
                return entity
              end
              return nil
            end

            local function getBestMDTLookupVehicle(distance)
              if pullVeh and DoesEntityExist(pullVeh) then return pullVeh end

              local frontVeh = getVehicleInFrontOfPlayerCar(distance or 16.0)
              if frontVeh and DoesEntityExist(frontVeh) then return frontVeh end

              if lib and lib.getClosestVehicle then
                local v = lib.getClosestVehicle(GetEntityCoords(PlayerPedId()), 8.0, false)
                if type(v) == "table" then v = v.vehicle or nil end
                if v and v ~= 0 and DoesEntityExist(v) then return v end
              end

              return nil
            end

            local function buildCurrentAz5PDMDTContext(kind)
              local ctx = { source = 'az5pd' }
              local ped, pedKey = resolveLastPed()
              pedKey = tostring(pedKey or lastPedNetId or '')

              if (not ped or ped == 0 or not DoesEntityExist(ped)) and lastPedEntity and DoesEntityExist(lastPedEntity) then
                ped = lastPedEntity
              end

              if pedKey ~= '' then
                local pdata = ensurePerson and ensurePerson(pedKey) or (pedData and pedData[pedKey]) or nil
                if pdata and pdata.name and pdata.name ~= '' then
                  ctx.name = pdata.name
                  ctx.owner = pdata.name
                  ctx.owner_name = pdata.name
                  ctx.netId = pedKey
                  local first, last = splitFullNameForMDT(pdata.name)
                  ctx.first = first
                  ctx.last = last
                end
              end

              local veh = getBestMDTLookupVehicle(16.0)
              if veh and DoesEntityExist(veh) then
                local plateText = (GetVehicleNumberPlateText(veh) or ""):match("%S+")
                if plateText and plateText ~= "" then
                  ctx.plate = plateText:upper()
                  ctx.lp = ctx.plate
                  ctx.license = ctx.plate
                  lastPlate = ctx.plate
                end
                ctx.model = getVehicleDisplayName(veh)
                ctx.color = getVehicleColorHint(veh)
                if ctx.model and ctx.model ~= '' then lastMake = ctx.model end
                if ctx.color and ctx.color ~= '' then lastColor = ctx.color end
              elseif lastPlate and tostring(lastPlate):match("%S+") then
                ctx.plate = tostring(lastPlate):upper()
                ctx.lp = ctx.plate
                ctx.license = ctx.plate
                ctx.model = lastMake or ''
                ctx.color = lastColor or ''
              end

              if not ctx.owner_name or ctx.owner_name == '' then
                local ownerName = getPedName(lastPedNetId) or ''
                if ownerName ~= '' then
                  ctx.owner = ownerName
                  ctx.owner_name = ownerName
                  if not ctx.name or ctx.name == '' then
                    ctx.name = ownerName
                    local first, last = splitFullNameForMDT(ownerName)
                    ctx.first = ctx.first or first
                    ctx.last = ctx.last or last
                  end
                end
              end

              if ctx.plate and ctx.plate ~= '' then
                local profilePedKey = pedKey ~= '' and pedKey or tostring(lastPedNetId or '')
                local fallbackOwnerName = ctx.owner_name or ctx.owner or ctx.name or ''
                local vehicleProfile = getVehicleLookupIdentityProfile(profilePedKey, ctx.plate, fallbackOwnerName)
                if vehicleProfile then
                  if vehicleProfile.ownerName and vehicleProfile.ownerName ~= '' then
                    ctx.owner = vehicleProfile.ownerName
                    ctx.owner_name = vehicleProfile.ownerName
                  end
                  if vehicleProfile.status and vehicleProfile.status ~= '' then
                    ctx.status = vehicleProfile.status
                  end
                  ctx.registered_to_driver = vehicleProfile.registeredToDriver == true
                end
              end

              local desiredKind = tostring(kind or ''):lower()
              if desiredKind == 'plate' then
                ctx.kind = 'plate'
                ctx.page = 'plateSearch'
                ctx.value = ctx.plate or ''
              elseif desiredKind == 'name' then
                ctx.kind = 'name'
                ctx.page = 'nameSearch'
                ctx.value = ctx.name or ''
              else
                ctx.kind = (ctx.plate and ctx.plate ~= '') and 'plate' or 'name'
                ctx.page = (ctx.kind == 'plate') and 'plateSearch' or 'nameSearch'
                ctx.value = (ctx.kind == 'plate') and (ctx.plate or '') or (ctx.name or '')
              end

              return ctx
            end

            exports('GetCurrentMDTContext', function(kind)
              return buildCurrentAz5PDMDTContext(kind)
            end)

            local function runPlate()
              local plateTxt = lastPlate
              local makeTxt, colorTxt = lastMake, lastColor

              if (not plateTxt or plateTxt == "") then
                local veh = getBestMDTLookupVehicle(16.0)

                if veh and DoesEntityExist(veh) then
                  plateTxt = (GetVehicleNumberPlateText(veh) or ""):match("%S+")
                  makeTxt  = getVehicleDisplayName(veh)
                  colorTxt = getVehicleColorHint(veh)

                  if plateTxt and plateTxt ~= "" then lastPlate = plateTxt:upper() end
                  if makeTxt and makeTxt ~= "" then lastMake = makeTxt end
                  if colorTxt and colorTxt ~= "" then lastColor = colorTxt end
                end
              end

              if plateTxt and plateTxt:match("%S+") then
                lastPlate = plateTxt:upper()
                local stoppedOwnerName = getPedName(lastPedNetId) or ''
                local lookupProfile = getVehicleLookupIdentityProfile(tostring(lastPedNetId or ''), lastPlate, stoppedOwnerName)
                local lookupOwnerName = (lookupProfile and lookupProfile.ownerName) or stoppedOwnerName
                local lookupStatus = (lookupProfile and lookupProfile.status) or 'VALID'

                if openExternalMDT({
                  kind = 'plate',
                  preservePage = true,
                  prefillOnly = true,
                  autoSearch = false,
                  plate = lastPlate,
                  license = lastPlate,
                  lp = lastPlate,
                  owner = lookupOwnerName,
                  owner_name = lookupOwnerName,
                  model = lastMake or '',
                  color = lastColor or '',
                  status = lookupStatus,
                  source = 'az5pd',
                  search = {
                    kind = 'plate',
                    value = lastPlate,
                    plate = lastPlate,
                    license = lastPlate,
                    lp = lastPlate,
                    owner = lookupOwnerName,
                    owner_name = lookupOwnerName,
                    model = lastMake or '',
                    color = lastColor or '',
                    status = lookupStatus,
                    source = 'az5pd',
                    preservePage = true,
                    prefillOnly = true,
                    autoSearch = false
                  }
                }) then return end
                TriggerServerEvent('mdt:lookupPlate', lastPlate, lookupOwnerName, lastMake or "", lastColor or "", lookupStatus)
              else
                notify("plate_failed","Lookup Failed",
                      "No vehicle plate found. Pull someone over first or use the vehicle in front of your car.",
                      'error','ban','#DD6B20')
              end
            end

            local isOpen = false
            local EMERGENCY_CLASSES = { [18]=true, [56]=true }
            local function inEmergencyVehicle()
              local ped = PlayerPedId()
              if not IsPedInAnyVehicle(ped,false) then return false end
              return EMERGENCY_CLASSES[ GetVehicleClass(GetVehiclePedIsIn(ped,false)) ] or false
            end

            local function looksLikeExternalMDTResource(name)
              local low = tostring(name or ''):lower()
              if low == '' then return false end
              return low:find('az%-mdt', 1, false)
                  or low:find('az_mdt', 1, true)
                  or low:find('mdt%-stand', 1, false)
                  or low:find('mdtstand', 1, true)
            end

            local function getExternalMDTResource()
              if not (Config and Config.MDT and Config.MDT.preferExternalWhenAvailable) then return nil end
              local names = (Config and Config.MDT and Config.MDT.externalResourceNames) or { 'Az-MDT', 'az_mdt', 'Az-Mdt-Standalone' }
              for _, name in ipairs(names) do
                if name and name ~= '' and name ~= GetCurrentResourceName() and type(GetResourceState) == 'function' and GetResourceState(name) == 'started' then
                  return name
                end
              end
              if type(GetNumResources) == 'function' and type(GetResourceByFindIndex) == 'function' and type(GetResourceState) == 'function' then
                for i = 0, GetNumResources() - 1 do
                  local name = GetResourceByFindIndex(i)
                  if name and name ~= GetCurrentResourceName() and looksLikeExternalMDTResource(name) and GetResourceState(name) == 'started' then
                    return name
                  end
                end
              end
              return nil
            end

            openExternalMDT = function(payload)
              local res = getExternalMDTResource()
              if not res then return false end
              payload = payload or {}
              local search = type(payload.search) == 'table' and payload.search or {}
              payload.search = search
              if payload.page and (not search.page or search.page == '') then search.page = payload.page end
              if payload.kind and (not search.kind or search.kind == '') then search.kind = payload.kind end
              if payload.value and (not search.value or search.value == '') then search.value = payload.value end
              if payload.first and (not search.first or search.first == '') then search.first = payload.first end
              if payload.last and (not search.last or search.last == '') then search.last = payload.last end
              if payload.name and (not search.name or search.name == '') then search.name = payload.name end
              if payload.plate and (not search.plate or search.plate == '') then search.plate = payload.plate end
              if search.kind == 'name' then
                if (not search.value or search.value == '') and ((search.first or '') ~= '' or (search.last or '') ~= '') then
                  search.value = (tostring(search.first or '') .. ' ' .. tostring(search.last or '')):gsub('^%s+', ''):gsub('%s+$', '')
                end
                if (not payload.first or payload.first == '') then payload.first = search.first or '' end
                if (not payload.last or payload.last == '') then payload.last = search.last or '' end
                if (not payload.name or payload.name == '') then payload.name = search.name or search.value or '' end
              elseif search.kind == 'plate' then
                if (not search.plate or search.plate == '') and (search.value and search.value ~= '') then search.plate = search.value end
                if (not payload.plate or payload.plate == '') then payload.plate = search.plate or search.value or '' end
              end
              if (not payload.kind or payload.kind == '') then payload.kind = search.kind or '' end
              if (not payload.value or payload.value == '') then payload.value = search.value or search.plate or search.name or '' end
              TriggerServerEvent('az_mdt:OpenExternal', payload)
              return true
            end

            Az5PDOpenIntegratedMDT = function(payload)
              return openExternalMDT(payload or {})
            end

            local function toggleMDT()
              if not isOpen then
                if not inEmergencyVehicle() then
                  return notify("mdt_err","MDT","Must be in emergency vehicle.",'error')
                end
                if openExternalMDT({}) then return end
                isOpen = true
                SetNuiFocus(true,true)
                SendNUIMessage({action='open'})
                TriggerEvent('__clientRequestPopulate')
              else
                isOpen = false
                SetNuiFocus(false,false)
                SendNUIMessage({action='close'})
              end
            end

            local function findVehicleAhead(maxRange, forwardDotThreshold)
              maxRange = maxRange or 20.0
              forwardDotThreshold = forwardDotThreshold or 0.5
              local player = PlayerPedId()
              local myVeh = GetVehiclePedIsIn(player, false)
              local myCoords = GetEntityCoords(player)
              local fwd = GetEntityForwardVector(player)
              local best, bd = nil, 1e9

              if lib and lib.getNearbyVehicles then
                for _, e in ipairs(lib.getNearbyVehicles(myCoords, maxRange, false)) do
                  local v, coords = e.vehicle, e.coords
                  if v and v ~= myVeh and DoesEntityExist(v) then
                    local to = coords - myCoords
                    local d = #to
                    if d > 0 then
                      local dir = to / d
                      if (fwd.x*dir.x + fwd.y*dir.y + fwd.z*dir.z) > forwardDotThreshold and d < bd then
                        bd, best = d, v
                      end
                    end
                  end
                end
              else
                local handle, veh = FindFirstVehicle()
                local ok = true
                while ok do
                  if DoesEntityExist(veh) and veh ~= myVeh then
                    local coords = GetEntityCoords(veh)
                    local to = coords - myCoords
                    local d = #to
                    if d > 0 and d < maxRange then
                      local dir = to / d
                      if (fwd.x*dir.x + fwd.y*dir.y + fwd.z*dir.z) > forwardDotThreshold and d < bd then
                        bd, best = d, veh
                      end
                    end
                  end
                  ok, veh = FindNextVehicle(handle)
                end
                EndFindVehicle(handle)
              end

              return best
            end

            setPedProtected = function(netId, val)
              if not netId then return end
              ensurePerson(netId)
              pedData[tostring(netId)].pulledProtected = val and true or false
              pedData[tostring(netId)].pulledInVehicle = pedData[tostring(netId)].pulledInVehicle or false
              if not val then
                pedData[tostring(netId)].forcedStop = nil
              end
              dprint("setPedProtected", tostring(netId), tostring(val))
            end

            markPulledInVehicle = function(netId, val)
              if not netId then return end
              pedData[tostring(netId)] = pedData[tostring(netId)] or {}
              pedData[tostring(netId)].pulledInVehicle = val and true or false
              if val then
                pedData[tostring(netId)].pulledProtected = true
              end
              dprint("markPulledInVehicle", tostring(netId), tostring(val))
            end

            monitorKeepInVehicle = function(netId, veh, durationMs)
              if not netId or not veh then return end
              durationMs = durationMs or 30000
              rememberDetainedVehicleState(safeNetToPed(netId), netId, veh)
              local startTime = GetGameTimer()
              Citizen.CreateThread(function()
                local deadline = startTime + durationMs
                local fastPhaseEnd = startTime + 3000
                while GetGameTimer() < deadline do
                  if not veh or not DoesEntityExist(veh) or not netId then break end
                  local ped = safeNetToPed(netId)
                  if not DoesEntityExist(ped) then break end

                  local info = pedData and pedData[tostring(netId)] or nil
                  local allowExitUntil = info and tonumber(info.allowVehicleExitUntil) or nil
                  local keepSeated = info and shouldKeepPedSeated(info) or false

                  if not keepSeated then
                    break
                  end

                  if allowExitUntil and GetGameTimer() < allowExitUntil then
                    if not IsPedInAnyVehicle(ped, false) then
                      NetworkRequestControlOfEntity(ped)
                      ClearPedTasksImmediately(ped)
                      holdPedAttention(ped, false)
                    else
                      holdPedAttention(ped, true)
                    end
                  elseif not IsPedInAnyVehicle(ped, false) then
                    if enforcePedRemainSeated(ped, netId, veh) then
                      holdPedAttention(ped, true)
                    else
                      NetworkRequestControlOfEntity(ped)
                      ClearPedTasksImmediately(ped)
                      holdPedAttention(ped, false)
                    end
                  else
                    rememberDetainedVehicleState(ped, netId, GetVehiclePedIsIn(ped, false))
                    holdPedAttention(ped, true)
                  end

                  if GetGameTimer() < fastPhaseEnd then Citizen.Wait(100) else Citizen.Wait(Config.Timings.attackDelay) end
                end
              end)
            end

            holdPedAttention = function(ped, inVehicle)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local player = PlayerPedId()
              local pedKey = tostring(safePedToNet(ped) or ped)
              local staySeated = pedData and pedData[pedKey] and shouldKeepPedSeated(pedData[pedKey]) or false

              if (not inVehicle) and staySeated then
                if enforcePedRemainSeated(ped, pedKey) then
                  inVehicle = true
                end
              end

              NetworkRequestControlOfEntity(ped)
              SetEntityAsMissionEntity(ped, true, true)
              SetBlockingOfNonTemporaryEvents(ped, true)

              if not inVehicle then
                ClearPedTasksImmediately(ped)
                TaskTurnPedToFaceEntity(ped, player, 1000)
                TaskLookAtEntity(ped, player, 1000000, 2048, 3)
                TaskStandStill(ped, 1000000)
              else
                TaskLookAtEntity(ped, player, 2500, 2048, 3)
                SetPedKeepTask(ped, true)
              end

              SetPedCanRagdoll(ped, false)
              SetPedKeepTask(ped, true)
              dprint("holdPedAttention", tostring(ped), "inVehicle=", tostring(inVehicle))
            end

            releasePedAttention = function(ped, force)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local pedKey = tostring(safePedToNet(ped) or ped)
              if not force and pedData and pedData[pedKey] and pedData[pedKey].cuffed then
                dprint("releasePedAttention: skipping because ped is cuffed", tostring(ped))
                if holdPedAttention then holdPedAttention(ped, IsPedInAnyVehicle(ped, false)) end
                return
              end
              playSimpleConversationAnim(ped, "handoff")
              NetworkRequestControlOfEntity(ped)
              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, false)
              SetPedCanRagdoll(ped, true)
              SetPedKeepTask(ped, false)
              SetEntityAsMissionEntity(ped, false, false)
              dprint("releasePedAttention", tostring(ped))
            end

            local function num(v)
              if v == nil then return nil end
              if type(v) == "number" then return v end
              local ok, res = pcall(function() return tonumber(v) end)
              if ok and res ~= nil then return res end
              return nil
            end

            local function toXYZ(v)
              if not v then return nil, nil, nil end
              if type(v) == "table" then
                if v.x ~= nil and v.y ~= nil and v.z ~= nil then
                  return num(v.x), num(v.y), num(v.z)
                end
                if #v >= 3 then
                  return num(v[1]), num(v[2]), num(v[3])
                end
              end

              local ok, x = pcall(function() return v.x end)
              if ok and x ~= nil then
                local ok2, y = pcall(function() return v.y end)
                local ok3, z = pcall(function() return v.z end)
                if ok2 and ok3 and y ~= nil and z ~= nil then
                  return num(x), num(y), num(z)
                end
              end

              ok, x = pcall(function() return v[1] end)
              if ok and x ~= nil then
                local ok2, y = pcall(function() return v[2] end)
                local ok3, z = pcall(function() return v[3] end)
                if ok2 and ok3 and y ~= nil and z ~= nil then
                  return num(x), num(y), num(z)
                end
              end

              local s = tostring(v or "")
              if type(s) == "string" and #s > 0 then
                local nums = {}
                for token in s:gmatch("[-%d%.eE]+") do
                  local n = num(token)
                  if n then table.insert(nums, n) end
                  if #nums >= 3 then break end
                end
                if #nums >= 3 then
                  return nums[1], nums[2], nums[3]
                end
              end

              return nil, nil, nil
            end

            local function normalizeToXYZTriple(a,b,c, fallbackX, fallbackY, fallbackZ)

              local ax,ay,az = toXYZ(a)
              if ax and ay and az then return ax, ay, az end

              local bx,by,bz = toXYZ(b)
              if bx and by and bz then return bx, by, bz end

              local cx,cy,cz = toXYZ(c)
              if cx and cy and cz then return cx, cy, cz end

              local nx, ny, nz = num(a), num(b), num(c)

              nx = nx or num(fallbackX)
              ny = ny or num(fallbackY)
              nz = nz or num(fallbackZ)

              if nx and ny and nz then return nx, ny, nz end

              if type(a) ~= "number" then
                local pax,pay,paz = toXYZ(a)
                if pax and pay and paz then return pax, pay, paz end
              end
              if type(b) ~= "number" then
                local pbx,pby,pbz = toXYZ(b)
                if pbx and pby and pbz then return pbx, pby, pbz end
              end
              if type(c) ~= "number" then
                local pcx,pcy,pcz = toXYZ(c)
                if pcx and pcy and pcz then return pcx, pcy, pcz end
              end

              return nil, nil, nil
            end

            local function safeVector3(a,b,c, fallbackX, fallbackY, fallbackZ)
              local x,y,z = normalizeToXYZTriple(a,b,c, fallbackX, fallbackY, fallbackZ)
              if not x or not y or not z then
                dprint("safeVector3: invalid components", "a=", tostring(a), "b=", tostring(b), "c=", tostring(c), "-> resolved:", tostring(x), tostring(y), tostring(z))
                return nil
              end

              return { x = x, y = y, z = z }
            end

            local function getClosestVehicleNodePosHeading(x, y, z, nodeType, p6, p7)
              local r1, r2, r3, r4 = GetClosestVehicleNodeWithHeading(x, y, z, nodeType or 1, p6 or 3.0, p7 or 0)

              if type(r1) == 'boolean' then
                if not r1 then return nil, nil, false end
                local px, py, pz = toXYZ(r2)
                if px and py and pz then
                  return vector3(px, py, pz), num(r3) or 0.0, true
                end
                return nil, nil, false
              end

              local px, py, pz = normalizeToXYZTriple(r1, r2, r3)
              if px and py and pz then
                return vector3(px, py, pz), num(r4) or 0.0, true
              end

              local vx, vy, vz = toXYZ(r1)
              if vx and vy and vz then
                return vector3(vx, vy, vz), num(r2) or 0.0, true
              end

              return nil, nil, false
            end


            local function findRoadSpawnPointNear(target, minDist, maxDist)
              local anchorCoords = nil
              if type(target) == 'number' and target ~= 0 and DoesEntityExist(target) then
                anchorCoords = GetEntityCoords(target)
              else
                local tx, ty, tz = toXYZ(target)
                if tx and ty and tz then
                  anchorCoords = vector3(tx, ty, tz)
                else
                  anchorCoords = GetEntityCoords(PlayerPedId())
                end
              end

              minDist = tonumber(minDist) or 32.0
              maxDist = tonumber(maxDist) or 65.0
              if maxDist < minDist then maxDist = minDist + 10.0 end

              local bestPos, bestHeading, bestScore = nil, nil, nil
              for _ = 1, 18 do
                local dist = minDist + (math.random() * (maxDist - minDist))
                local ang = math.rad(math.random(0, 359))
                local guessX = anchorCoords.x + math.cos(ang) * dist
                local guessY = anchorCoords.y + math.sin(ang) * dist
                local nodePos, nodeH = getClosestVehicleNodePosHeading(guessX, guessY, anchorCoords.z)
                if nodePos then
                  local actualDist = #(nodePos - anchorCoords)
                  local score = math.abs(actualDist - ((minDist + maxDist) * 0.5))
                  if not bestScore or score < bestScore then
                    bestScore = score
                    bestPos = nodePos
                    bestHeading = nodeH
                  end
                  if actualDist >= (minDist - 6.0) and actualDist <= (maxDist + 12.0) then
                    return nodePos, nodeH
                  end
                end
              end

              if bestPos then return bestPos, bestHeading end
              return getClosestVehicleNodePosHeading(anchorCoords.x, anchorCoords.y, anchorCoords.z)
            end

            local function requestModelSync(hash)
              if not HasModelLoaded(hash) then
                RequestModel(hash)
                local tick = GetGameTimer() + 5000
                while not HasModelLoaded(hash) and GetGameTimer() < tick do
                  Citizen.Wait(10)
                end
              end
              return HasModelLoaded(hash)
            end

            function attemptPedAttack(ped, veh, netId)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              if IsPedAPlayer(ped) then return false end

              local attackChance = (Config and Config.Flee and Config.Flee.attackChance) or 0.5
              if netId and pedData and pedData[tostring(netId)] then
                local profile = pedData[tostring(netId)]
                local boost = (((Config and Config.Immersion and Config.Immersion.traits) or {}).attackChanceBoost) or 0.15
                if profile.wanted or profile.hasIllegalItems then attackChance = math.min(0.95, attackChance + boost) end
              end
              if math.random() >= attackChance then return false end

              if NetworkGetEntityIsNetworked(ped) then
                NetworkRequestControlOfEntity(ped)
                local startT = GetGameTimer()
                while not NetworkHasControlOfEntity(ped) and (GetGameTimer() - startT) < 1000 do
                  NetworkRequestControlOfEntity(ped)
                  Citizen.Wait(10)
                end
              else
                SetEntityAsMissionEntity(ped, true, true)
              end

              local playerPed = PlayerPedId()
              local dist = #(GetEntityCoords(ped) - GetEntityCoords(playerPed))
              local engageDistance = 14.0
              if dist > engageDistance then
                dprint(("attemptPedAttack: cancelled, player too far (%s)"):format(tostring(dist)))
                return false
              end

              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)

              local reactionDelay = 900 + math.random(0, 1800)
              Citizen.Wait(reactionDelay)
              if not DoesEntityExist(ped) or not DoesEntityExist(playerPed) then return false end
              if #(GetEntityCoords(ped) - GetEntityCoords(playerPed)) > engageDistance then
                dprint("attemptPedAttack: cancelled after delay, player moved away")
                return false
              end

              if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle and vehicle ~= 0 then
                  TaskLeaveVehicle(ped, vehicle, 256)
                  local timeout = GetGameTimer() + 2200
                  while DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) and GetGameTimer() < timeout do
                    Citizen.Wait(50)
                  end
                end
              end

              if not HasPedGotWeapon(ped, GetHashKey("WEAPON_PISTOL"), false) then
                GiveWeaponToPed(ped, GetHashKey("WEAPON_PISTOL"), 30, false, true)
              end

              TaskCombatPed(ped, playerPed, 0, 16)

              if netId then
                pedData = pedData or {}
                pedData[tostring(netId)] = pedData[tostring(netId)] or {}
                pedData[tostring(netId)].attacked = true
              end

              dprint(("attemptPedAttack: ped=%s attacked after delay (netId=%s)"):format(tostring(ped), tostring(netId)))
              return true
            end

            local function spawnVehicleAndDriver(vehModelName, driverModelName, spawnCoords, heading)
              local vehHash = GetHashKey(vehModelName)
              local driverHash = GetHashKey(driverModelName)

              if not requestModelSync(vehHash) then return nil, nil end
              requestModelSync(driverHash)

              local vx,vy,vz = toXYZ(spawnCoords)
              if not vx or not vy or not vz then
                dprint("spawnVehicleAndDriver: invalid spawnCoords", tostring(spawnCoords))
                return nil, nil
              end

              local nodePos, nodeH = getClosestVehicleNodePosHeading(vx, vy, vz)
              if nodePos then
                vx, vy, vz = nodePos.x, nodePos.y, nodePos.z
                if nodeH then heading = nodeH end
              end
              heading = tonumber(heading) or 0.0

              local veh = CreateVehicle(vehHash, vx, vy, vz + 0.35, heading, true, false)
              if not veh or veh == 0 then return nil, nil end

              SetEntityAsMissionEntity(veh, true, true)
              SetEntityHeading(veh, heading)
              SetVehicleOnGroundProperly(veh)
              SetVehicleEngineOn(veh, true, true, true)
              SetVehicleHandbrake(veh, false)
              SetVehicleDoorsLocked(veh, 1)
              SetVehicleUndriveable(veh, false)
              SetVehicleHasBeenOwnedByPlayer(veh, false)

              local driver = nil
              if driverHash and requestModelSync(driverHash) then
                driver = CreatePedInsideVehicle(veh, 4, driverHash, -1, true, false)
                if driver and driver ~= 0 then
                  NetworkRequestControlOfEntity(driver)
                  SetEntityAsMissionEntity(driver, true, true)
                  SetBlockingOfNonTemporaryEvents(driver, true)
                  SetPedKeepTask(driver, true)
                  SetPedCanRagdoll(driver, false)
                  if type(SetDriverAbility) == "function" then pcall(SetDriverAbility, driver, 1.0) end
                  if type(SetDriverAggressiveness) == "function" then pcall(SetDriverAggressiveness, driver, 0.0) end
                end
              end

              return veh, driver
            end

            local function getNearbyDownedPeds(center, radius, humanOnly)
              local found = {}
              local px,py,pz = toXYZ(center)
              if not px or not py or not pz then
                dprint("getNearbyDeadPeds: invalid center", tostring(center))
                return found
              end
              local centerVec = { x = px, y = py, z = pz }

              local handle, ped = FindFirstPed()
              local ok = true
              while ok do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                  local pcoords = GetEntityCoords(ped)
                  local dist = #(pcoords - vector3(centerVec.x, centerVec.y, centerVec.z))
                  if dist <= radius and IsPedDeadOrDying(ped, true) then
                    local isHuman = true
                    if type(IsPedHuman) == "function" then isHuman = IsPedHuman(ped) end
                    if humanOnly == nil or humanOnly == isHuman then
                      table.insert(found, ped)
                    end
                  end
                end
                ok, ped = FindNextPed(handle)
              end
              EndFindPed(handle)
              return found
            end

            local function getNearbyVehicleToTow(center, radius)
              local px,py,pz = toXYZ(center)
              if not px or not py or not pz then
                dprint("getNearbyVehicleToTow: invalid center", tostring(center))
                return nil
              end
              local centerVec = vector3(px,py,pz)

              local best = nil
              local bestDist = 1e9
              if lib and lib.getNearbyVehicles then
                local vehs = lib.getNearbyVehicles(centerVec, radius, false) or {}
                for _,o in ipairs(vehs) do
                  local v = o.vehicle or o
                  if v and DoesEntityExist(v) then
                    local d = #(GetEntityCoords(v) - centerVec)
                    if d < bestDist then bestDist, best = d, v end
                  end
                end
                return best
              end

              local handle, veh = FindFirstVehicle()
              local ok = true
              while ok do
                if DoesEntityExist(veh) then
                  local d = #(GetEntityCoords(veh) - centerVec)
                  if d <= radius then
                    local driver = GetPedInVehicleSeat(veh, -1)
                    if not driver or driver == 0 or not IsPedAPlayer(driver) then
                      if d < bestDist then bestDist, best = d, veh end
                    end
                  end
                end
                ok, veh = FindNextVehicle(handle)
              end
              EndFindVehicle(handle)
              return best
            end

            local function driveToTarget(driver, veh, targetVec, speed, arriveRadius, driveMode)
              speed = speed or 8.0
              arriveRadius = arriveRadius or 6.0
              driveMode = driveMode or 786603

              if not driver or driver == 0 or not veh or veh == 0 then return end

              local tx,ty,tz = toXYZ(targetVec)
              local targetVec3 = nil
              if type(targetVec) == "table" and targetVec.x ~= nil and targetVec.y ~= nil and targetVec.z ~= nil then
                targetVec3 = targetVec
              elseif tx and ty and tz then
                targetVec3 = vector3(tx,ty,tz)
              else
                dprint("driveToTarget: invalid targetVec (cannot resolve coordinates)", tostring(targetVec))
                return
              end

              NetworkRequestControlOfEntity(driver)
              NetworkRequestControlOfEntity(veh)
              TaskVehicleDriveToCoordLongrange(driver, veh, targetVec3.x, targetVec3.y, targetVec3.z, speed, driveMode, arriveRadius)

              local deadline = GetGameTimer() + 30000
              while GetGameTimer() < deadline do
                if not DoesEntityExist(veh) or not DoesEntityExist(driver) then break end
                local dist = #(GetEntityCoords(veh) - targetVec3)
                if dist <= arriveRadius then break end
                Citizen.Wait(150)
              end
            end

            local function getEntityAnchorVectors(target)
              if target and type(target) == 'number' and target ~= 0 and DoesEntityExist(target) then
                local coords = GetEntityCoords(target)
                local forward = GetEntityForwardVector(target)
                local right = vector3(forward.y, -forward.x, 0.0)
                return coords, forward, right, GetEntityHeading(target)
              end

              local coords = nil
              local tx, ty, tz = toXYZ(target)
              if tx and ty and tz then
                coords = vector3(tx, ty, tz)
              else
                coords = GetEntityCoords(PlayerPedId())
              end

              local player = PlayerPedId()
              local forward = GetEntityForwardVector(player)
              local right = vector3(forward.y, -forward.x, 0.0)
              return coords, forward, right, GetEntityHeading(player)
            end

            local function getSmartServiceParkPoint(target, mode)
              local anchorCoords, forward, right, anchorHeading = getEntityAnchorVectors(target)
              local backDist = (mode == 'tow') and 8.0 or 10.0
              local sideDist = (mode == 'tow') and 3.2 or 4.5
              local desired = vector3(
                anchorCoords.x - (forward.x * backDist) + (right.x * sideDist),
                anchorCoords.y - (forward.y * backDist) + (right.y * sideDist),
                anchorCoords.z
              )
              local nodePos, nodeH = getClosestVehicleNodePosHeading(desired.x, desired.y, desired.z)
              if nodePos then
                return nodePos, (nodeH or anchorHeading or 0.0)
              end
              return desired, (anchorHeading or 0.0)
            end

            local function settleServiceVehicle(driver, veh, keepEngineOn)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return end
              local deadline = GetGameTimer() + 5000
              while DoesEntityExist(veh) and GetGameTimer() < deadline do
                NetworkRequestControlOfEntity(veh)
                if driver and driver ~= 0 and DoesEntityExist(driver) then
                  NetworkRequestControlOfEntity(driver)
                  if GetEntitySpeed(veh) > 0.8 then
                    TaskVehicleTempAction(driver, veh, 27, 250)
                  end
                end
                if GetEntitySpeed(veh) <= 0.8 then break end
                Citizen.Wait(100)
              end
              local vcoords = GetEntityCoords(veh)
              local nodePos, nodeH = getClosestVehicleNodePosHeading(vcoords.x, vcoords.y, vcoords.z)
              if nodePos and #(nodePos - vcoords) <= 10.0 then
                SetEntityCoordsNoOffset(veh, nodePos.x, nodePos.y, nodePos.z + 0.2, false, false, false)
                if nodeH then SetEntityHeading(veh, nodeH) end
              end
              SetVehicleOnGroundProperly(veh)
              SetVehicleHandbrake(veh, true)
              SetVehicleDoorsLocked(veh, 1)
              SetVehicleEngineOn(veh, keepEngineOn and true or false, true, true)
              if driver and driver ~= 0 and DoesEntityExist(driver) then
                ClearPedTasks(driver)
              end
            end

            local function createServiceBlip(veh, text)
              if not veh or veh == 0 then return nil end
              local b = AddBlipForEntity(veh)
              SetBlipSprite(b, 198)
              SetBlipNameToPlayerName(b, text or "Service")
              SetBlipColour(b, 3)
              SetBlipAsShortRange(b, true)
              return b
            end

            local function cleanupServiceEntities(entities, delayMs)
              Citizen.CreateThread(function()
                Citizen.Wait(tonumber(delayMs) or (1000 * 45))
                for _, e in ipairs(entities or {}) do
                  if e and DoesEntityExist(e) then
                    SetEntityAsMissionEntity(e, true, true)
                    if IsEntityAVehicle(e) then
                      DeleteVehicle(e)
                    else
                      DeleteEntity(e)
                    end
                  end
                end
              end)
            end

            callAIEMS = function()
              local player = PlayerPedId()
              local px,py,pz = toXYZ(GetEntityCoords(player))
              if not px then
                return notify("ai_ems_fail","EMS","Could not determine player position.",'error','heartbeat','#DD6B20')
              end

              local incidentCenter = vector3(px, py, pz)
              local deadPeds = getNearbyDownedPeds(incidentCenter, 12.0, nil)
              if #deadPeds > 0 and type(deadPeds[1]) == 'number' then
                local conv = {}
                for _,ph in ipairs(deadPeds) do
                  if DoesEntityExist(ph) then
                    table.insert(conv, { ped = ph, health = GetEntityHealth(ph) or 0 })
                  end
                end
                deadPeds = conv
              end

              local chosenPed = nil
              if #deadPeds > 0 then
                table.sort(deadPeds, function(a,b)
                  local ap = a and a.ped or a
                  local bp = b and b.ped or b
                  if not DoesEntityExist(ap) then return false end
                  if not DoesEntityExist(bp) then return true end
                  return Vdist(GetEntityCoords(ap), incidentCenter) < Vdist(GetEntityCoords(bp), incidentCenter)
                end)
                local chosenEntry = deadPeds[1]
                if type(chosenEntry) == 'number' then
                  chosenPed = chosenEntry
                elseif type(chosenEntry) == 'table' then
                  chosenPed = chosenEntry.ped
                end
              end

              local parkPos, parkHeading = getSmartServiceParkPoint(chosenPed or player, 'ems')
              local nodePos, nodeH = findRoadSpawnPointNear(parkPos or incidentCenter, 38.0, 75.0)
              if not nodePos then
                dprint("callAIEMS: invalid spawnPos", px, py, pz)
                return notify("ai_ems_fail","EMS","Invalid spawn position.",'error','heartbeat','#DD6B20')
              end
              local spawnPos = { x = nodePos.x, y = nodePos.y, z = nodePos.z }

              local veh, driver = spawnVehicleAndDriver("ambulance", "s_m_m_paramedic_01", spawnPos, nodeH or parkHeading or 0.0)
              if not veh or not driver then return notify("ai_ems_fail","EMS","Failed to spawn EMS vehicle/driver.",'error','heartbeat','#DD6B20') end

              SetVehicleSiren(veh, true)
              local blip = createServiceBlip(veh, "AI EMS")
              notify("ai_ems_called","AI EMS","Ambulance dispatched. ETA shortly.",'inform','heartbeat','#38A169')

              driveToTarget(driver, veh, parkPos or incidentCenter, 10.0, 8.0)
              settleServiceVehicle(driver, veh, false)

              if #deadPeds == 0 then
                notify("ai_ems_none","No Casualties","EMS arrived but found no dead humans nearby.",'warning','heartbeat','#DD6B20')
              else
                notify("ai_ems_work","EMS Arrived","EMS tending to casualties.",'success','heartbeat','#38A169')

                if chosenPed and DoesEntityExist(chosenPed) then
                  NetworkRequestControlOfEntity(chosenPed)
                  SetEntityAsMissionEntity(chosenPed, true, true)
                  ClearPedTasksImmediately(chosenPed)
                  TaskStandStill(chosenPed, 2000)

                  local respDriver = driver
                  local medic = nil
                  if DoesEntityExist(veh) then
                    medic = GetPedInVehicleSeat(veh, 0)
                    if medic == 0 then medic = nil end
                  end
                  if not DoesEntityExist(medic) then medic = respDriver end

                  if DoesEntityExist(respDriver) then
                    Citizen.CreateThread(function()
                      handleCasualtyInteraction(respDriver, veh, chosenPed)
                    end)
                  end
                  if DoesEntityExist(medic) and medic ~= respDriver then
                    Citizen.CreateThread(function()
                      Citizen.Wait(Config.Timings.keepTaskResetDelay)
                      handleCasualtyInteraction(medic, veh, chosenPed)
                    end)
                  end
                else
                  print(" [AI DEBUG] EMS: chosenPed invalid or does not exist")
                end
              end

              cleanupServiceEntities({veh, driver}, 120000)
            end

            if type(forcePedExitVehicle) ~= "function" then
              function forcePedExitVehicle(ped, veh)
                if not DoesEntityExist(ped) then return false end

                if not IsPedInAnyVehicle(ped, false) then return true end

                if NetworkGetEntityIsNetworked(ped) then
                  NetworkRequestControlOfEntity(ped)
                end
                if DoesEntityExist(veh) and NetworkGetEntityIsNetworked(veh) then
                  NetworkRequestControlOfEntity(veh)
                end

                TaskLeaveVehicle(ped, veh, 0)

                local deadline = GetGameTimer() + 3000
                while IsPedInAnyVehicle(ped, false) and GetGameTimer() < deadline do
                  Citizen.Wait(100)
                end

                if IsPedInAnyVehicle(ped, false) then
                  ClearPedTasksImmediately(ped)
                  Citizen.Wait(100)
                end

                return not IsPedInAnyVehicle(ped, false)
              end
            end

            local function findDownedPedsEnumerator(center, radius, humanOnly)
              local result = {}
              local handle, ped = FindFirstPed()
              local success = true
              repeat
                if DoesEntityExist(ped) then
                  local pcoords = GetEntityCoords(ped)
                  local dist = #(pcoords - center)
                  if dist <= radius then
                    local deadOrDying = false

                    if type(IsPedDeadOrDying) == "function" then
                      deadOrDying = IsPedDeadOrDying(ped, true)
                    else

                      local hp = GetEntityHealth(ped) or 0
                      deadOrDying = (hp <= 0)
                    end
                    local isHuman = true
                    if type(IsPedHuman) == "function" then isHuman = IsPedHuman(ped) end
                    if deadOrDying and (not humanOnly or isHuman) then
                      table.insert(result, { ped = ped, health = GetEntityHealth(ped) or 0 })
                    end
                  end
                end
                success, ped = FindNextPed(handle)
              until not success
              EndFindPed(handle)
              return result
            end

            local function handleRemovalInteraction(responderPed, vehicle, casualty, isAnimal)
              print((" [AI DEBUG] handleRemovalInteraction: responder=%s vehicle=%s casualty=%s isAnimal=%s"):format(
                tostring(responderPed), tostring(vehicle), tostring(casualty), tostring(isAnimal)))

              if not DoesEntityExist(responderPed) then print(" [AI DEBUG] responder does not exist") return end
              if not DoesEntityExist(casualty) then print(" [AI DEBUG] casualty does not exist") return end

              requestControl(responderPed, 2000)

              if IsPedInAnyVehicle(responderPed, false) then
                print(" [AI DEBUG] removal responder is in vehicle, forcing exit.")
                forcePedExitVehicle(responderPed, vehicle)
                Citizen.Wait(200)
              end

              TaskGoToEntity(responderPed, casualty, -1, 2.0, 2.0, 1073741824, 0)
              local approachStart = GetGameTimer()
              while GetGameTimer() - approachStart < 12000 do
                if not DoesEntityExist(responderPed) or not DoesEntityExist(casualty) then
                  print(" [AI DEBUG] responder or casualty no longer exists while approaching (removal)")
                  return
                end
                local dist = #(GetEntityCoords(responderPed) - GetEntityCoords(casualty))
                if dist <= 2.2 then break end
                Citizen.Wait(200)
              end

              local ccoords = GetEntityCoords(casualty)
              TaskTurnPedToFaceCoord(responderPed, ccoords.x, ccoords.y, ccoords.z, 500)
              if requestControl(responderPed, 500) then

                TaskStartScenarioInPlace(responderPed, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
                Citizen.Wait(1500)
                ClearPedTasksImmediately(responderPed)
              end

              if DoesEntityExist(casualty) then
                requestControl(casualty, 800)
                SetEntityAsMissionEntity(casualty, true, true)
                ClearPedTasksImmediately(casualty)
                Citizen.Wait(200)

                SetEntityHealth(casualty, 0)
                Citizen.Wait(200)
                if DoesEntityExist(casualty) then
                  SetEntityAsMissionEntity(casualty, true, true)
                  DeleteEntity(casualty)
                  Citizen.Wait(200)
                end
                if DoesEntityExist(casualty) then
                  SetEntityAsMissionEntity(casualty, true, true)
                  DeletePed(casualty)
                end
              end

              print((" [AI DEBUG] removal done for casualty=%s exists now? %s"):format(tostring(casualty), tostring(DoesEntityExist(casualty))))

              if type(notify) == "function" then
                if isAnimal then
                  notify("ai_animal_removed","Animal Removed","Animal Control collected the animal.", 'success', 'paw', '#38A169')
                else
                  notify("ai_coroner_removed","Body Removed","Coroner collected the body.", 'success', 'skull-crossbones', '#38A169')
                end
              end
            end

            local function handleRemovalInteraction(responderPed, vehicle, casualty, isAnimal)

              local function safeRequestControl(entity, timeout)
                timeout = timeout or 1000
                if not DoesEntityExist(entity) then return false end
                if type(requestControl) == "function" then

                  local ok, res = pcall(requestControl, entity, timeout)
                  if ok then return res or true end
                end
                local tic = GetGameTimer()
                if NetworkGetEntityIsNetworked(entity) then
                  NetworkRequestControlOfEntity(entity)
                else
                  SetEntityAsMissionEntity(entity, true, true)
                end
                while (GetGameTimer() - tic) < timeout do
                  if not NetworkGetEntityIsNetworked(entity) then
                    return true
                  end
                  if NetworkHasControlOfEntity(entity) then
                    return true
                  end
                  Citizen.Wait(Config.Timings.shortWait)
                  if NetworkGetEntityIsNetworked(entity) then
                    NetworkRequestControlOfEntity(entity)
                  end
                end

                if DoesEntityExist(entity) then SetEntityAsMissionEntity(entity, true, true) end
                return NetworkHasControlOfEntity(entity) or not NetworkGetEntityIsNetworked(entity)
              end

              local function safeForceExit(ped, veh)
                if not DoesEntityExist(ped) then return false end
                if not IsPedInAnyVehicle(ped, false) then return true end
                if type(forcePedExitVehicle) == "function" then
                  pcall(forcePedExitVehicle, ped, veh)
                else
                  TaskLeaveVehicle(ped, veh, 0)
                end
                local deadline = GetGameTimer() + 3000
                while IsPedInAnyVehicle(ped, false) and GetGameTimer() < deadline do
                  Citizen.Wait(100)
                end
                if IsPedInAnyVehicle(ped, false) then
                  ClearPedTasksImmediately(ped)
                  Citizen.Wait(100)
                end
                return not IsPedInAnyVehicle(ped, false)
              end

              if not DoesEntityExist(responderPed) then
                dprint("handleRemovalInteraction: responder does not exist")
                return
              end
              if not DoesEntityExist(casualty) then
                dprint("handleRemovalInteraction: casualty does not exist")
                return
              end

              safeRequestControl(responderPed, 1200)

              if IsPedInAnyVehicle(responderPed, false) then
                safeForceExit(responderPed, vehicle)
                Citizen.Wait(150)
              end

              TaskGoToEntity(responderPed, casualty, -1, 2.0, 2.0, 1073741824, 0)
              local approachStart = GetGameTimer()
              while GetGameTimer() - approachStart < 12000 do
                if not DoesEntityExist(responderPed) or not DoesEntityExist(casualty) then
                  dprint("handleRemovalInteraction: responder or casualty disappeared while approaching")
                  return
                end
                local rc = GetEntityCoords(responderPed)
                local cc = GetEntityCoords(casualty)
                local dist = Vdist(rc.x, rc.y, rc.z, cc.x, cc.y, cc.z)
                if dist <= 2.2 then break end
                Citizen.Wait(200)
              end

              local ccoords = GetEntityCoords(casualty)
              TaskTurnPedToFaceCoord(responderPed, ccoords.x, ccoords.y, ccoords.z, 500)
              if safeRequestControl(responderPed, 500) then
                TaskStartScenarioInPlace(responderPed, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
                Citizen.Wait(1400)
                ClearPedTasksImmediately(responderPed)
              end

              if DoesEntityExist(casualty) then
                safeRequestControl(casualty, 800)
                SetEntityAsMissionEntity(casualty, true, true)
                ClearPedTasksImmediately(casualty)
                Citizen.Wait(150)

                SetEntityHealth(casualty, 0)
                Citizen.Wait(120)
                if DoesEntityExist(casualty) then
                  SetEntityAsMissionEntity(casualty, true, true)
                  DeleteEntity(casualty)
                  Citizen.Wait(120)
                end
                if DoesEntityExist(casualty) then
                  SetEntityAsMissionEntity(casualty, true, true)
                  DeletePed(casualty)
                end
              end

              dprint(("handleRemovalInteraction: removal done for casualty=%s exists now? %s"):format(tostring(casualty), tostring(DoesEntityExist(casualty))))

              if type(notify) == "function" then
                if isAnimal then
                  notify("ai_animal_removed","Animal Removed","Animal Control collected the animal.", 'success', 'paw', '#38A169')
                else
                  notify("ai_coroner_removed","Body Removed","Coroner collected the body.", 'success', 'skull-crossbones', '#38A169')
                end
              end
            end

            callAICoroner = function()
              local function safeRequestControl(entity, timeout)
                timeout = timeout or 1000
                if not DoesEntityExist(entity) then return false end

                if type(requestControl) == "function" then
                  return requestControl(entity, timeout)
                end
                local tic = GetGameTimer()
                if NetworkGetEntityIsNetworked(entity) then
                  NetworkRequestControlOfEntity(entity)
                else
                  SetEntityAsMissionEntity(entity, true, true)
                end
                while (GetGameTimer() - tic) < timeout do
                  if not NetworkGetEntityIsNetworked(entity) then
                    return true
                  end
                  if NetworkHasControlOfEntity(entity) then
                    return true
                  end
                  Citizen.Wait(Config.Timings.shortWait)
                  if NetworkGetEntityIsNetworked(entity) then
                    NetworkRequestControlOfEntity(entity)
                  end
                end

                if DoesEntityExist(entity) then SetEntityAsMissionEntity(entity, true, true) end
                return NetworkHasControlOfEntity(entity) or not NetworkGetEntityIsNetworked(entity)
              end

              local function safeForceExit(ped, veh)
                if not DoesEntityExist(ped) then return false end
                if not IsPedInAnyVehicle(ped, false) then return true end
                if type(forcePedExitVehicle) == "function" then
                  pcall(forcePedExitVehicle, ped, veh)
                else
                  TaskLeaveVehicle(ped, veh, 0)
                end
                local deadline = GetGameTimer() + 3000
                while IsPedInAnyVehicle(ped, false) and GetGameTimer() < deadline do
                  Citizen.Wait(100)
                end
                if IsPedInAnyVehicle(ped, false) then
                  ClearPedTasksImmediately(ped)
                  Citizen.Wait(100)
                end
                return not IsPedInAnyVehicle(ped, false)
              end

              local player = PlayerPedId()
              local px,py,pz = toXYZ(GetEntityCoords(player))
              if not px then
                return notify("ai_coroner_fail","Coroner","Could not determine player position.",'error','skull-crossbones','#DD6B20')
              end

              local nodePos, nodeH = findRoadSpawnPointNear(vector3(px, py, pz), 35.0, 70.0)
              if not nodePos then
                dprint("callAICoroner: spawn point fallback failed for AI service")
                return notify("ai_coroner_fail","Coroner","Could not find spawn position.",'error','skull-crossbones','#DD6B20')
              end
              local spawnPos = { x = nodePos.x, y = nodePos.y, z = nodePos.z }

              local veh, driver = spawnVehicleAndDriver("rumpo", "s_m_m_doctor_01", spawnPos, nodeH or 0.0)
              if not veh or not driver then
                return notify("ai_coroner_fail","Coroner","Failed to spawn coroner vehicle.",'error','skull-crossbones','#DD6B20')
              end

              local blip = createServiceBlip(veh, "Coroner")
              notify("ai_coroner_called","Coroner","Coroner van dispatched. ETA shortly.",'inform','skull-crossbones','#38A169')

              driveToTarget(driver, veh, GetEntityCoords(player), 8.0, 6.0)

              Citizen.Wait(500)

              if type(dprint) == "function" then
                dprint((" [AI DEBUG] callAICoroner: veh=%s driver=%s"):format(tostring(veh), tostring(driver)))
                if DoesEntityExist(driver) then dprint((" [AI DEBUG] callAICoroner: driver coords = %s"):format(tostring(GetEntityCoords(driver)))) end
                dprint((" [AI DEBUG] callAICoroner: driver in vehicle? %s"):format(tostring(IsPedInAnyVehicle(driver, false))))
              end

              if DoesEntityExist(driver) and DoesEntityExist(veh) and IsPedInAnyVehicle(driver, false) then
                if type(dprint) == "function" then dprint(" [AI DEBUG] callAICoroner: keeping driver staged in vehicle until body is selected") end
              end

              local center = vector3(px, py, pz)
              if type(dprint) == "function" then dprint((" [AI DEBUG] callAICoroner: Running downed search at center=%.2f,%.2f,%.2f radius=30.0"):format(center.x, center.y, center.z)) end
              local found = getNearbyDownedPeds(center, 30.0, nil)
              if type(dprint) == "function" then dprint((" [AI DEBUG] callAICoroner: Found %d downed peds (raw)"):format(#found)) end

              local candidates = {}
              for i, info in ipairs(found) do
                if type(info) == "table" and info.ped and DoesEntityExist(info.ped) then
                  table.insert(candidates, info)
                elseif type(info) == "number" and DoesEntityExist(info) then
                  table.insert(candidates, { ped = info, health = GetEntityHealth(info) or 0 })
                end
              end

              if #candidates == 0 then
                notify("ai_coroner_none","No Bodies","No downed peds found for Coroner to pick up.",'warning','skull-crossbones','#DD6B20')
                cleanupServiceEntities({veh, driver})
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end

              table.sort(candidates, function(a,b)
                local ap = a.ped
                local bp = b.ped
                return Vdist(GetEntityCoords(ap), center) < Vdist(GetEntityCoords(bp), center)
              end)
              local chosen = candidates[1]
              local chosenPed = chosen and chosen.ped

              if not chosenPed or not DoesEntityExist(chosenPed) then
                dprint("callAICoroner: chosenPed invalid or missing")
                cleanupServiceEntities({veh, driver})
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end

              local coronerParkPos = getSmartServiceParkPoint(chosenPed, 'coroner')
              driveToTarget(driver, veh, coronerParkPos, 8.0, 8.0)
              settleServiceVehicle(driver, veh, false)
              if DoesEntityExist(driver) and DoesEntityExist(veh) and IsPedInAnyVehicle(driver, false) then
                safeForceExit(driver, veh)
              end

              safeRequestControl(chosenPed, 1000)
              SetEntityAsMissionEntity(chosenPed, true, true)
              ClearPedTasksImmediately(chosenPed)
              TaskStandStill(chosenPed, 2000)

              local passenger = nil
              if DoesEntityExist(veh) then
                passenger = GetPedInVehicleSeat(veh, 0)
                if passenger == 0 then passenger = nil end
              end
              if not DoesEntityExist(passenger) then passenger = driver end

              if DoesEntityExist(driver) then
                Citizen.CreateThread(function()
                  handleRemovalInteraction(driver, veh, chosenPed, false)
                end)
              end
              if DoesEntityExist(passenger) and passenger ~= driver then
                Citizen.CreateThread(function()
                  Citizen.Wait(Config.Timings.keepTaskResetDelay)
                  handleRemovalInteraction(passenger, veh, chosenPed, false)
                end)
              end

              cleanupServiceEntities({veh, driver}, 120000)
              if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
            end

            function startFleeDrive(ped, veh)
              if not ped or ped == 0 or not DoesEntityExist(ped) then
                dprint("startFleeDrive: invalid ped")
                return false
              end

              local playerPed = PlayerPedId()

              local function requestControl(ent, timeout)
                timeout = timeout or 1000
                if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
                if NetworkGetEntityIsNetworked and NetworkGetEntityIsNetworked(ent) then
                  NetworkRequestControlOfEntity(ent)
                  local st = GetGameTimer()
                  while not NetworkHasControlOfEntity(ent) and (GetGameTimer() - st) < timeout do
                    NetworkRequestControlOfEntity(ent)
                    Citizen.Wait(10)
                  end
                  return NetworkHasControlOfEntity(ent)
                else
                  SetEntityAsMissionEntity(ent, true, true)
                  return true
                end
              end

              local pedKey = tostring(NetworkGetNetworkIdFromEntity and NetworkGetNetworkIdFromEntity(ped) or safePedToNet(ped) or ped)
              pedData = pedData or {}
              pedData[pedKey] = pedData[pedKey] or {}
              local info = pedData[pedKey]
              info.fled = true
              local wasStoppedInVehicle = info.pulledInVehicle or info.pulledProtected or info.forcedStop
              info.forcedStop = nil
              info.pulledProtected = false
              info.pulledInVehicle = false
              info.detainedVehicleNet = nil
              info.detainedSeat = nil
              info.preventVehicleReseatUntil = GetGameTimer() + 15000
              setPedProtected(pedKey, false)
              markPulledInVehicle(pedKey, false)
              releasePedAttention(ped, true)

              local function startFleeBlip(entity, isVehicle)
                if pullVehBlip and DoesBlipExist(pullVehBlip) then
                  RemoveBlip(pullVehBlip)
                  pullVehBlip = nil
                end
                if not entity or entity == 0 or not DoesEntityExist(entity) then return end
                pullVehBlip = AddBlipForEntity(entity)
                if not pullVehBlip or not DoesBlipExist(pullVehBlip) then return end
                SetBlipSprite(pullVehBlip, isVehicle and 225 or 280)
                SetBlipScale(pullVehBlip, isVehicle and 1.0 or 0.95)
                SetBlipAsShortRange(pullVehBlip, false)
                SetBlipColour(pullVehBlip, 1)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(isVehicle and "Fleeing Vehicle" or "Fleeing Suspect")
                EndTextCommandSetBlipName(pullVehBlip)
                Citizen.CreateThread(function()
                  local startTime = GetGameTimer()
                  local maxDuration = 60000
                  while pullVehBlip and DoesBlipExist(pullVehBlip) and GetGameTimer() - startTime <= maxDuration do
                    Citizen.Wait(1000)
                    if not DoesEntityExist(entity) then break end
                    local pcoords = GetEntityCoords(PlayerPedId())
                    local ecoords = GetEntityCoords(entity)
                    if #(pcoords - ecoords) > 650.0 then break end
                  end
                  if pullVehBlip and DoesBlipExist(pullVehBlip) then
                    RemoveBlip(pullVehBlip)
                    pullVehBlip = nil
                  end
                end)
              end

              local function startFootFleeNow()
                dprint(("startFleeDrive: ped %s fleeing on foot"):format(tostring(ped)))
                requestControl(ped, 800)
                StopAnimTask(ped, "mp_arresting", "idle", 1.0)
                ClearPedTasksImmediately(ped)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 2, true)
                SetPedCanRagdoll(ped, true)
                SetPedKeepTask(ped, true)
                TaskSmartFleePed(ped, playerPed, 250.0, -1, false, false)
                startFleeBlip(ped, false)
                notify("suspect_flee_foot", "Suspect Running", "Suspect bailed out and is fleeing on foot. Blip placed on suspect.", 'error', 'person-running', '#E53E3E')
                return true
              end

              if veh and veh ~= 0 and DoesEntityExist(veh) and IsPedInAnyVehicle(ped, false) then
                dprint(("startFleeDrive: ped %s in vehicle %s"):format(tostring(ped), tostring(veh)))

                requestControl(veh, 1200)
                requestControl(ped, 800)

                if GetPedInVehicleSeat(veh, -1) ~= ped then
                  dprint("startFleeDrive: ped is not the driver; refusing to assign drive-away task")
                  return false
                end

                if wasStoppedInVehicle then
                  ClearPedTasksImmediately(ped)
                  ClearPedSecondaryTask(ped)
                  SetVehicleEngineOn(veh, true, true, true)
                  SetVehicleUndriveable(veh, false)
                  SetVehicleHandbrake(veh, false)
                  SetVehicleDoorsLocked(veh, 1)
                  SetVehicleForwardSpeed(veh, 12.0)
                end

                SetVehicleEngineOn(veh, true, true, true)
                SetVehicleUndriveable(veh, false)
                SetVehicleHandbrake(veh, false)
                SetVehicleDoorsLocked(veh, 1)
                SetVehicleForwardSpeed(veh, 18.0)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                SetPedCanBeDraggedOut(ped, false)
                SetPedCanRagdoll(ped, false)
                if type(SetDriverAbility) == "function" then pcall(SetDriverAbility, ped, 1.0) end
                if type(SetDriverAggressiveness) == "function" then pcall(SetDriverAggressiveness, ped, 1.0) end
                if type(SetDriveTaskDrivingStyle) == "function" then pcall(SetDriveTaskDrivingStyle, ped, 786603) end
                if type(SetDriveTaskCruiseSpeed) == "function" then pcall(SetDriveTaskCruiseSpeed, ped, 60.0) end

                local pedCoords = GetEntityCoords(ped)
                local plCoords = GetEntityCoords(playerPed)
                local dir = vector3(pedCoords.x - plCoords.x, pedCoords.y - plCoords.y, 0.0)
                local dlen = math.sqrt(dir.x * dir.x + dir.y * dir.y)
                if dlen < 1.0 then
                  local heading = GetEntityHeading(ped)
                  local hr = math.rad(heading)
                  dir = vector3(-math.sin(hr), math.cos(hr), 0.0)
                  dlen = 1.0
                end
                dir = vector3(dir.x / dlen, dir.y / dlen, 0.0)

                local fleeDist = 320.0
                local tx = pedCoords.x + dir.x * fleeDist
                local ty = pedCoords.y + dir.y * fleeDist
                local tz = pedCoords.z + 1.0

                if type(TaskVehicleDriveToCoordLongrange) == "function" then
                  TaskVehicleDriveToCoordLongrange(ped, veh, tx, ty, tz, 60.0, 786603, 8.0)
                else
                  TaskVehicleDriveToCoord(ped, veh, tx, ty, tz, 60.0, 1.0, 786603, 5.0, true)
                end
                Citizen.CreateThread(function()
                  Citizen.Wait(1500)
                  if DoesEntityExist(ped) and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == ped then
                    TaskVehicleDriveWander(ped, veh, 60.0, 786603)
                  end
                end)

                startFleeBlip(veh, true)
                notify("pull_fail_blip", "Traffic Stop Failed", "Suspect is gunning it. Blip placed on vehicle.", 'error', 'car', '#E53E3E')
                dprint(("startFleeDrive: started vehicle flee for ped=%s -> target(%.1f,%.1f,%.1f)"):format(tostring(ped), tx, ty, tz))
                return true
              end

              if not IsPedInAnyVehicle(ped, false) then
                return startFootFleeNow()
              end

              dprint("startFleeDrive: no action taken (ped not in vehicle and not valid)")
              return false
            end

            callTow = function()
              local player = PlayerPedId()
              local px,py,pz = toXYZ(GetEntityCoords(player))
              if not px then
                return notify("ai_tow_fail","Tow","Could not determine player position.",'error','truck','#DD6B20')
              end

              local nodePos, nodeH = findRoadSpawnPointNear(vector3(px, py, pz), 40.0, 80.0)
              if not nodePos then
                dprint("callTow: invalid spawnPos", px, py, pz)
                return notify("ai_tow_fail","Tow","Invalid spawn position.",'error','truck','#DD6B20')
              end
              local spawnPos = { x = nodePos.x, y = nodePos.y, z = nodePos.z }

              local towVeh, driver = spawnVehicleAndDriver("flatbed", "s_m_m_trucker_01", spawnPos, nodeH or 0.0)
              if not towVeh or not driver then return notify("ai_tow_fail","Tow","Failed to spawn tow truck.",'error','truck','#DD6B20') end

              local blip = createServiceBlip(towVeh, "Tow Truck")
              notify("ai_tow_called","Tow Truck","Tow truck en route. ETA shortly.",'inform','truck','#38A169')

              local targetVeh = getNearbyVehicleToTow(GetEntityCoords(player), 12.0)
              if not targetVeh or targetVeh == 0 then
                driveToTarget(driver, towVeh, GetEntityCoords(player), 10.0, 6.0)
                notify("ai_tow_none","No Vehicle","No suitable vehicle nearby to tow.",'warning','truck','#DD6B20')
                cleanupServiceEntities({towVeh, driver}, 90000)
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end

              local targetPosX, targetPosY, targetPosZ = toXYZ(GetEntityCoords(targetVeh))
              if not targetPosX then
                dprint("callTow: invalid targetPos for towing", tostring(targetVeh))
                notify("ai_tow_miss","No Target","Vehicle disappeared before tow arrived.",'warning','truck','#DD6B20')
                cleanupServiceEntities({towVeh, driver}, 90000)
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end
              local targetPos = vector3(targetPosX, targetPosY, targetPosZ)
              local towParkPos = getSmartServiceParkPoint(targetVeh, 'tow')
              driveToTarget(driver, towVeh, towParkPos or targetPos, 10.0, 6.0)

              if DoesEntityExist(targetVeh) then
                NetworkRequestControlOfEntity(targetVeh)
                NetworkRequestControlOfEntity(towVeh)
                SetEntityAsMissionEntity(targetVeh, true, true)
                AttachEntityToEntity(targetVeh, towVeh, GetEntityBoneIndexByName(towVeh, "chassis"), 0.0, -3.0, 0.6, 0.0, 0.0, 0.0, false, false, true, false, 20, true)
                Citizen.Wait(Config.Timings.keepTaskResetDelay)
                if driver and driver ~= 0 then
                  TaskVehicleDriveWander(driver, towVeh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                end
                notify("ai_tow_attached","Vehicle Towed","Tow truck attached vehicle and is leaving.",'success','truck','#38A169')

                Citizen.CreateThread(function()
                  Citizen.Wait(1000 * 12)
                  if DoesEntityExist(targetVeh) then
                    DetachEntity(targetVeh, true, true)
                    SetEntityAsMissionEntity(targetVeh, true, true)
                    DeleteVehicle(targetVeh)
                  end
                end)
              else
                notify("ai_tow_miss","No Target","Vehicle disappeared before tow arrived.",'warning','truck','#DD6B20')
              end

              cleanupServiceEntities({towVeh, driver}, 90000)
              if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
            end

            getPrimaryOccupant = function(veh)
              if not veh or not DoesEntityExist(veh) then return nil end
              local driver = GetPedInVehicleSeat(veh, -1)
              if driver and driver ~= 0 and not IsPedAPlayer(driver) then return driver end
              for seat = 0, 15 do
                local ped = GetPedInVehicleSeat(veh, seat)
                if ped and ped ~= 0 and not IsPedAPlayer(ped) then return ped end
              end
              return nil
            end

            local function findTrafficStopDestination(veh)
              if not veh or veh == 0 or not DoesEntityExist(veh) then return nil, nil end

              local function normalizeHeading(h)
                h = num(h) or 0.0
                h = h % 360.0
                if h < 0.0 then h = h + 360.0 end
                return h
              end

              local function headingDelta(a, b)
                a = normalizeHeading(a)
                b = normalizeHeading(b)
                return ((b - a + 540.0) % 360.0) - 180.0
              end

              local function headingAlignedWithTravel(baseHeading, candidateHeading)
                local cand = normalizeHeading(candidateHeading or baseHeading or 0.0)
                if math.abs(headingDelta(baseHeading or 0.0, cand)) > 90.0 then
                  cand = normalizeHeading(cand + 180.0)
                end
                return cand
              end

              local vehCoords = GetEntityCoords(veh)
              local vehFwd = GetEntityForwardVector(veh)
              local fwdLen = math.sqrt((vehFwd.x * vehFwd.x) + (vehFwd.y * vehFwd.y))
              if fwdLen <= 0.001 then
                return vehCoords, GetEntityHeading(veh)
              end

              vehFwd = vector3(vehFwd.x / fwdLen, vehFwd.y / fwdLen, 0.0)

              -- GTA right-hand shoulder relative to travel direction.
              -- For a forward vector (x, y), the true right vector is (y, -x).
              -- The previous sign order pointed to the left shoulder, which caused AI cars
              -- to pull across/onto the wrong side of the road.
              local vehRight = vector3(vehFwd.y, -vehFwd.x, 0.0)
              local currentHeading = GetEntityHeading(veh)
              local bestPos, bestHeading, bestScore = nil, nil, nil

              for _, ahead in ipairs({12.0, 18.0, 24.0, 30.0}) do
                for _, side in ipairs({3.5, 5.0, 6.5}) do
                  local desired = vector3(
                    vehCoords.x + (vehFwd.x * ahead) + (vehRight.x * side),
                    vehCoords.y + (vehFwd.y * ahead) + (vehRight.y * side),
                    vehCoords.z
                  )

                  local nodePos, nodeH, nodeOk = getClosestVehicleNodePosHeading(desired.x, desired.y, desired.z)
                  local cand = (nodeOk and nodePos) or desired
                  local candHeading = headingAlignedWithTravel(currentHeading, nodeH or currentHeading)
                  local toCandX = cand.x - vehCoords.x
                  local toCandY = cand.y - vehCoords.y
                  local aheadDot = (toCandX * vehFwd.x) + (toCandY * vehFwd.y)
                  local rightDot = (toCandX * vehRight.x) + (toCandY * vehRight.y)

                  if aheadDot > 10.0 and rightDot > 1.5 then
                    local offsetDist = #(cand - desired)
                    local sidePenalty = math.abs(rightDot - side) * 0.35
                    local headingPenalty = math.abs(headingDelta(currentHeading, candHeading)) * 0.05
                    local score = offsetDist + sidePenalty + headingPenalty

                    if not bestScore or score < bestScore then
                      bestScore = score
                      bestPos = cand
                      bestHeading = candHeading
                    end
                  end
                end
              end

              if bestPos then return bestPos, bestHeading end

              local fallback = vector3(
                vehCoords.x + (vehFwd.x * 16.0) + (vehRight.x * 4.5),
                vehCoords.y + (vehFwd.y * 16.0) + (vehRight.y * 4.5),
                vehCoords.z
              )
              return fallback, currentHeading
            end

            local pendingPullState = 'idle'

            local function isPullOverSignalActive(vehicle)
              if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

              local sirenOn = false
              pcall(function() sirenOn = IsVehicleSirenOn(vehicle) and true or false end)
              if sirenOn then return true end

              local sirenAudioOn = false
              pcall(function() sirenAudioOn = IsVehicleSirenAudioOn(vehicle) and true or false end)
              if sirenAudioOn then return true end

              return false
            end

            function attemptPullOverAI(forceImmediate, markedVehicle)
              dprint("attemptPullOverAI called, forceImmediate=", tostring(forceImmediate))
              if not inEmergencyVehicle() then
                return notify("pull_err","Pull-Over","Must be in an emergency vehicle to initiate pull-over.",'error')
              end

              local ped = PlayerPedId()
              local myVeh = GetVehiclePedIsIn(ped,false)
              if not myVeh or myVeh == 0 then
                return notify("pull_err","Pull-Over","You must be in your vehicle to request a pull-over.",'error')
              end

              local best = nil
              if markedVehicle and markedVehicle ~= 0 and DoesEntityExist(markedVehicle) then
                best = markedVehicle
              else
                best = findVehicleAhead(20, 0.5)
              end
              if not best then
                return notify("pull_err","Pull-Over","No vehicle ahead.",'error')
              end

              pullVeh = best
              pendingPullVeh = nil
              pendingPullDeadline = 0
              dprint("attemptPullOverAI: pullVeh set to", tostring(pullVeh))

              if not forceImmediate then
                pendingPullState = 'waiting_for_emergency_signal'
                notify("pull_wait_signal","Traffic Stop","Target marked. Waiting for police lights / sirens before the stop begins.",'inform','siren-on','#4299E1')
              else
                pendingPullState = 'forced'
                notify("pull_info_force","PULL-OVER (FORCED)","Forcing pull-over (no lights required).",'inform','car','')
              end

              local waitDeadline = GetGameTimer() + 4500
              while GetGameTimer() < waitDeadline and not forceImmediate and not isPullOverSignalActive(myVeh) do
                Citizen.Wait(100)
              end
              if not forceImmediate and not isPullOverSignalActive(myVeh) then
                pendingPullState = 'idle'
                notify("pull_err","Traffic Stop","Police lights / sirens are still off. Turn them on to begin the stop.",'warning')
                pullVeh = nil
                return
              end

              pendingPullState = 'initiating_stop'

            do
              local driver = GetPedInVehicleSeat(pullVeh, -1)
              local netId = driver and driver ~= 0 and (safePedToNet(driver) or tostring(driver)) or nil
              local fleeChance = 0.0
              if netId then
                pedData = pedData or {}
                pedData[tostring(netId)] = pedData[tostring(netId)] or {}
                pedData[tostring(netId)].stopAwaitingId = true
                pedData[tostring(netId)].idChecked = pedData[tostring(netId)].idChecked and true or false
              end
              if math.random() < fleeChance then
                if driver and driver ~= 0 then
                  local attacked = attemptPedAttack(driver, pullVeh, netId)
                  if not attacked then
                    startFleeDrive(driver, pullVeh)
                  end
                end

                if DoesEntityExist(pullVeh) then

                  if pullVehBlip and DoesBlipExist(pullVehBlip) then
                    RemoveBlip(pullVehBlip)
                    pullVehBlip = nil
                  end

                  pullVehBlip = AddBlipForEntity(pullVeh)
                  if DoesBlipExist(pullVehBlip) then
                    SetBlipSprite(pullVehBlip, 225)
                    SetBlipScale(pullVehBlip, 1.0)
                    SetBlipAsShortRange(pullVehBlip, false)
                    SetBlipColour(pullVehBlip, 1)
                    BeginTextCommandSetBlipName("STRING")
                    AddTextComponentString("Fleeing Vehicle")
                    EndTextCommandSetBlipName(pullVehBlip)
                  end

                  notify("pull_fail", Config.Messages.pull_fail.title, Config.Messages.pull_fail.text, Config.Messages.pull_fail.style)

                  notify("pull_fail_blip","Pull-Over","Target is fleeing! Blip placed on vehicle.",'error','car','')

                  Citizen.CreateThread(function()
                    local startTime = GetGameTimer()
                    local maxDuration = 60000
                    while true do
                      Citizen.Wait(1000)
                      if not pullVehBlip or not DoesBlipExist(pullVehBlip) then break end
                      if not DoesEntityExist(pullVeh) then
                        if pullVehBlip and DoesBlipExist(pullVehBlip) then
                          RemoveBlip(pullVehBlip)
                          pullVehBlip = nil
                        end
                        notify("pull_blip_removed","Pull-Over","Target vehicle lost (vehicle disappeared). Blip removed.",'inform')
                        break
                      end
                      local pcoords = GetEntityCoords(PlayerPedId())
                      local vcoords = GetEntityCoords(pullVeh)
                      local dist = #(pcoords - vcoords)
                      if dist > 500.0 then
                        if pullVehBlip and DoesBlipExist(pullVehBlip) then
                          RemoveBlip(pullVehBlip)
                          pullVehBlip = nil
                        end
                        notify("pull_blip_removed_far","Pull-Over","Target vehicle too far. Blip removed.",'inform')
                        break
                      end
                      if GetGameTimer() - startTime > maxDuration then
                        if pullVehBlip and DoesBlipExist(pullVehBlip) then
                          RemoveBlip(pullVehBlip)
                          pullVehBlip = nil
                        end
                        break
                      end
                    end
                  end)
                else

                  notify("pull_fail","Pull-Over","Target is fleeing!",'error')
                end

                pullVeh = nil
                return
              end
            end

              local driver = GetPedInVehicleSeat(pullVeh, -1)
              NetworkRequestControlOfEntity(pullVeh)
              if driver and driver ~= 0 then NetworkRequestControlOfEntity(driver) end

              if driver and driver ~= 0 and not IsPedAPlayer(driver) then
                local netId = safePedToNet(driver) or tostring(driver)
                if not pedData[tostring(netId)] then
                  pedData[tostring(netId)] = generatePerson(driver)
                  TriggerServerEvent('mdt:logID', tostring(netId), pedData[tostring(netId)])
                end
                lastPedNetId = tostring(netId)
                lastPedEntity = driver

                setPedProtected(netId, true)
                pedData[tostring(netId)].forcedStop = forceImmediate and true or false
                markPulledInVehicle(netId, true)
                rememberDetainedVehicleState(driver, netId, pullVeh)

                SetEntityAsMissionEntity(driver, true, true)
                SetBlockingOfNonTemporaryEvents(driver, true)
                monitorKeepInVehicle(netId, pullVeh, 30000)
              end

              local targetPos, stopHeading = findTrafficStopDestination(pullVeh)
              local tx, ty, tz = targetPos.x, targetPos.y, targetPos.z

              if driver and driver ~= 0 and not IsPedAPlayer(driver) then
                local currentSpeed = GetEntitySpeed(pullVeh)
                local firstStageSpeed = math.max(8.0, math.min(15.0, math.max(currentSpeed * 0.72, 9.0)))
                local secondStageSpeed = math.max(4.5, math.min(8.5, math.max(currentSpeed * 0.42, 5.5)))
                SetDriverAbility(driver, 0.8)
                SetDriverAggressiveness(driver, 0.0)
                if currentSpeed > 10.0 then
                  TaskVehicleTempAction(driver, pullVeh, 19, 1200)
                  Citizen.Wait(300)
                elseif currentSpeed > 6.0 then
                  TaskVehicleTempAction(driver, pullVeh, 27, 900)
                  Citizen.Wait(200)
                end
                TaskVehicleDriveToCoordLongrange(driver, pullVeh, tx, ty, tz, firstStageSpeed, 786603, 16.0)
                if type(SetDriveTaskCruiseSpeed) == 'function' then pcall(SetDriveTaskCruiseSpeed, driver, firstStageSpeed) end
                notify("pull_slow","Traffic Stop","Vehicle acknowledged your stop, is slowing down gradually, and is starting to pull to the right.",'inform','car-side','#4299E1')

                Citizen.CreateThread(function()
                  local stageDeadline = GetGameTimer() + 2200
                  while GetGameTimer() < stageDeadline do
                    if not DoesEntityExist(pullVeh) or not DoesEntityExist(driver) then break end
                    local dist = #(GetEntityCoords(pullVeh) - vector3(tx,ty,tz))
                    if dist < 20.0 then break end
                    if type(SetDriveTaskCruiseSpeed) == 'function' then pcall(SetDriveTaskCruiseSpeed, driver, firstStageSpeed) end
                    Citizen.Wait(200)
                  end
                  if DoesEntityExist(pullVeh) and DoesEntityExist(driver) then
                    TaskVehicleDriveToCoordLongrange(driver, pullVeh, tx, ty, tz, secondStageSpeed, 786603, 10.0)
                    if type(SetDriveTaskCruiseSpeed) == 'function' then pcall(SetDriveTaskCruiseSpeed, driver, secondStageSpeed) end
                  end
                end)

                Citizen.CreateThread(function()
                  local done = false
                  local monitorDeadline = GetGameTimer() + 9000
                  while not done and GetGameTimer() < monitorDeadline do
                    if not DoesEntityExist(pullVeh) then done = true break end
                    local curPos = GetEntityCoords(pullVeh)
                    local dist = #(curPos - vector3(tx,ty,tz))
                    local speed = GetEntitySpeed(pullVeh)

                    if driver and driver ~= 0 and DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                      if dist < 14.0 then
                        TaskVehicleDriveToCoordLongrange(driver, pullVeh, tx, ty, tz, 6.0, 786603, 6.0)
                      end
                      if dist < 7.0 then
                        TaskVehicleTempAction(driver, pullVeh, 27, 600)
                      end
                      if dist < 3.5 then
                        TaskVehicleTempAction(driver, pullVeh, 27, 1200)
                      end
                    end

                    if dist < 3.5 or (dist < 6.0 and speed < 2.0) then
                      done = true
                      break
                    end
                    Citizen.Wait(200)
                  end

                  if not DoesEntityExist(pullVeh) then
                    pendingPullState = 'idle'
                    pullVeh = nil
                    return
                  end

                  pendingPullState = 'stopped'
                  SetVehicleOnGroundProperly(pullVeh)
                  -- Keep the vehicle's natural final heading. Forcing stopHeading here can snap/rotate the AI vehicle on stop.
                  SetVehicleForwardSpeed(pullVeh, 0.0)
                  SetVehicleEngineOn(pullVeh, false, true, true)
                  SetVehicleHandbrake(pullVeh, true)
                  SetVehicleDoorsLocked(pullVeh, 2)

                  local plateText = (GetVehicleNumberPlateText(pullVeh) or ""):match("%S+")
                  if plateText and plateText ~= "" then lastPlate = plateText:upper() end
                  lastMake = getVehicleDisplayName(pullVeh)
                  lastColor = getVehicleColorHint(pullVeh)

                  local occupant = getPrimaryOccupant(pullVeh)
                  if occupant and occupant ~= 0 then
                    local occNet = safePedToNet(occupant) or tostring(occupant)
                    if not pedData[occNet] then
                      pedData[occNet] = generatePerson(occupant)
                      TriggerServerEvent('mdt:logID', occNet, pedData[occNet])
                    end
                    lastPedNetId = occNet
                    lastPedEntity = occupant

                    setPedProtected(occNet, true)
                    pedData[occNet].forcedStop = forceImmediate and true or false
                    markPulledInVehicle(occNet, true)
                    rememberDetainedVehicleState(occupant, occNet, pullVeh)

                    NetworkRequestControlOfEntity(occupant)
                    SetEntityAsMissionEntity(occupant, true, true)
                    SetBlockingOfNonTemporaryEvents(occupant, true)
                    SetPedKeepTask(occupant, true)
                    holdPedAttention(occupant, true)

                    monitorKeepInVehicle(occNet, pullVeh, 30000)

                    TriggerEvent('__clientRequestPopulate')
                            Citizen.Wait(200)

                  notify(
                    "pull_done",
                    "Pull-Over",
                    "Vehicle yielded, slowed to the shoulder, and stopped. Occupant detained in-vehicle. Press [Y] to reposition. Use vehicle menu to eject if needed.",
                    'success',
                    'car-side',
                    '#38A169',
                    15000
            )

                  else
                    notify("pull_done_empty","Pull-Over","Vehicle pulled over, but no NPC occupant found.",'warning','car-side','#DD6B20')
                  end
                end)

              else
                notify("pull_playerveh","Pull-Over","Target is a player or no NPC driver. Use caution.",'warning','car-side','#DD6B20')
                lastPlate = (GetVehicleNumberPlateText(pullVeh) or ""):match("%S+") or lastPlate
                lastMake  = getVehicleDisplayName(pullVeh) or lastMake
                lastColor = getVehicleColorHint(pullVeh) or lastColor
              end
            end

            local function repositionInteractive(veh)
              if not veh or not DoesEntityExist(veh) then
                return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
              end

              dprint("repositionInteractive: requesting control of vehicle " .. tostring(veh))
              NetworkRequestControlOfEntity(veh)
              local start = GetGameTimer()
              while not NetworkHasControlOfEntity(veh) and (GetGameTimer() - start) < 3000 do
                NetworkRequestControlOfEntity(veh)
                Citizen.Wait(10)
              end
              local hasControl = NetworkHasControlOfEntity(veh)
              if not hasControl then
                notify("pull_repos_nocontrol","Reposition Notice","Could not obtain network control; entering local-only reposition mode. Changes may not persist.",'warning','arrows-spin','#DD6B20')
                dprint("repositionInteractive: proceeding without network control (local-only).")
              else
                dprint("repositionInteractive: obtained network control for vehicle " .. tostring(veh))
              end

              local origCoords = GetEntityCoords(veh)
              local origHeading = GetEntityHeading(veh)

              SetEntityAsMissionEntity(veh, true, true)
              SetVehicleEngineOn(veh, false, true, true)
              SetVehicleHandbrake(veh, true)
              SetVehicleDoorsLocked(veh, 2)

              notify("pull_repos_start","Reposition Mode",
                "Use ARROW KEYS to move vehicle. Q/E rotate. HOLD LEFT SHIFT for fine moves. PRESS ENTER to confirm. PRESS ESC to cancel.",
                'inform','arrows-spin','#4299E1')

              local step = 0.25
              local fineStep = 0.06
              local rotStep = 2.0
              local fineRotStep = 0.5
              local running = true
              local cancelled = false

              local debugState = { up = false, down = false, left = false, right = false }

              while running do
                Citizen.Wait(0)

                if not DoesEntityExist(veh) then
                  notify("pull_repos_fail","Reposition Failed","Vehicle no longer exists.",'error','arrows-spin','#E53E3E')
                  return
                end

                DisableControlAction(0, 44, true) -- Q
                DisableControlAction(0, 46, true) -- E

                local curStep = step
                local curRot = rotStep
                if IsControlPressed(0, 21) then -- LEFT SHIFT
                  curStep = fineStep
                  curRot = fineRotStep
                end

                if not NetworkHasControlOfEntity(veh) then
                  NetworkRequestControlOfEntity(veh)
                end

                local pos = GetEntityCoords(veh)
                local heading = GetEntityHeading(veh)
                local hr = math.rad(heading)
                local flatFwd = vector3(-math.sin(hr), math.cos(hr), 0.0)
                local len = math.sqrt(flatFwd.x*flatFwd.x + flatFwd.y*flatFwd.y)
                if len > 0.000001 then
                  flatFwd = vector3(flatFwd.x/len, flatFwd.y/len, 0.0)
                else
                  flatFwd = vector3(0.0, 1.0, 0.0)
                  len = 1.0
                end
                local right = vector3(flatFwd.y, -flatFwd.x, 0.0)

                local function movedDistance(oldCoords)
                  local now = GetEntityCoords(veh)
                  local dx = now.x - oldCoords.x
                  local dy = now.y - oldCoords.y
                  return math.sqrt(dx*dx + dy*dy)
                end

                local function tryMove(target)

                  SetEntityCoordsNoOffset(veh, target.x, target.y, target.z, false, false, false)
                  Citizen.Wait(0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "SetEntityCoordsNoOffset"
                  end

                  SetEntityCoords(veh, target.x, target.y, target.z, false, false, false, true)
                  Citizen.Wait(0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "SetEntityCoords"
                  end

                  local hadCollision = true

                  SetEntityCollision(veh, false, false)
                  SetEntityCoordsNoOffset(veh, target.x, target.y, target.z, false, false, false)
                  Citizen.Wait(0)
                  local moved = movedDistance(pos) > 0.0005
                  SetEntityCollision(veh, true, true)
                  if moved then
                    return true, "ToggleCollision+SetEntityCoordsNoOffset"
                  end

                  SetEntityVelocity(veh, flatFwd.x * 5.0, flatFwd.y * 5.0, 0.0)
                  Citizen.Wait(50)
                  SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "VelocityNudge"
                  end

                  return false, "AllFailed"
                end

                local upPressed = IsControlPressed(0, 172) or IsDisabledControlPressed(0, 172)
                local downPressed = IsControlPressed(0, 173) or IsDisabledControlPressed(0, 173)
                local leftPressed = IsControlPressed(0, 174) or IsDisabledControlPressed(0, 174)
                local rightPressed = IsControlPressed(0, 175) or IsDisabledControlPressed(0, 175)

                if upPressed then
                  local target = vector3(pos.x + flatFwd.x * curStep, pos.y + flatFwd.y * curStep, pos.z)
                  if not debugState.up then
                    dprint(("reposition: UP pressed | pos=(%.3f,%.3f,%.3f) | fwd=(%.3f,%.3f) | trying move to (%.3f,%.3f)"):format(
                      pos.x, pos.y, pos.z, flatFwd.x, flatFwd.y, target.x, target.y))
                    debugState.up = true
                  end
                  local ok, how = tryMove(target)
                  if ok then
                    dprint(("reposition: UP moved (method=%s)").format or ("reposition: UP moved (method="..tostring(how)..")"))
                  else
                    dprint(("reposition: UP move failed (reason=%s)"):format(tostring(how)))
                  end
                else
                  debugState.up = false
                end

                if downPressed then
                  local target = vector3(pos.x - flatFwd.x * curStep, pos.y - flatFwd.y * curStep, pos.z)
                  if not debugState.down then
                    dprint(("reposition: DOWN pressed | pos=(%.3f,%.3f) | fwd=(%.3f,%.3f)"):format(pos.x, pos.y, flatFwd.x, flatFwd.y))
                    debugState.down = true
                  end
                  local ok, how = tryMove(target)
                  if ok then
                    dprint(("reposition: DOWN moved (method=%s)"):format(tostring(how)))
                  else
                    dprint(("reposition: DOWN move failed (reason=%s)"):format(tostring(how)))
                  end
                else
                  debugState.down = false
                end

                if leftPressed then
                  local target = vector3(pos.x - right.x * curStep, pos.y - right.y * curStep, pos.z)
                  if not debugState.left then
                    dprint(("reposition: LEFT pressed | pos=(%.3f,%.3f) | right=(%.3f,%.3f)"):format(pos.x, pos.y, right.x, right.y))
                    debugState.left = true
                  end
                  local ok, how = tryMove(target)
                  if ok then
                    dprint(("reposition: LEFT moved (method=%s)"):format(tostring(how)))
                  else
                    dprint(("reposition: LEFT move failed (reason=%s)"):format(tostring(how)))
                  end
                else
                  debugState.left = false
                end

                if rightPressed then
                  local target = vector3(pos.x + right.x * curStep, pos.y + right.y * curStep, pos.z)
                  if not debugState.right then
                    dprint(("reposition: RIGHT pressed | pos=(%.3f,%.3f) | right=(%.3f,%.3f)"):format(pos.x, pos.y, right.x, right.y))
                    debugState.right = true
                  end
                  local ok, how = tryMove(target)
                  if ok then
                    dprint(("reposition: RIGHT moved (method=%s)"):format(tostring(how)))
                  else
                    dprint(("reposition: RIGHT move failed (reason=%s)"):format(tostring(how)))
                  end
                else
                  debugState.right = false
                end

                if IsDisabledControlPressed(0, 44) then -- Q
                  local h = GetEntityHeading(veh) - curRot
                  if h < 0 then h = h + 360 end
                  SetEntityHeading(veh, h)
                end
                if IsDisabledControlPressed(0, 46) then -- E
                  local h = GetEntityHeading(veh) + curRot
                  if h >= 360 then h = h - 360 end
                  SetEntityHeading(veh, h)
                end

                if IsControlJustReleased(0,191) or IsControlJustReleased(0,201) then
                  NetworkRequestControlOfEntity(veh)
                  SetEntityAsMissionEntity(veh, true, true)
                  SetVehicleOnGroundProperly(veh)
                  SetVehicleHandbrake(veh, true)
                  SetVehicleEngineOn(veh, false, true, true)
                  SetVehicleDoorsLocked(veh, 2)
                  notify("pull_repos_done","Repositioned","Vehicle position set.",'success','arrows-spin','#38A169')
                  running = false
                  break
                end

                if IsControlJustReleased(0,200) then
                  cancelled = true
                  running = false
                  break
                end
              end

              if cancelled then
                NetworkRequestControlOfEntity(veh)
                local tryStart = GetGameTimer()
                while not NetworkHasControlOfEntity(veh) and (GetGameTimer() - tryStart) < 1000 do
                  NetworkRequestControlOfEntity(veh)
                  Citizen.Wait(10)
                end
                SetEntityCoordsNoOffset(veh, origCoords.x, origCoords.y, origCoords.z, false, false, false)
                SetEntityHeading(veh, origHeading)
                SetVehicleOnGroundProperly(veh)
                SetVehicleHandbrake(veh, true)
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleDoorsLocked(veh, 2)
                notify("pull_repos_cancel","Reposition Cancelled","Vehicle restored to original position.",'warning','arrows-spin','#DD6B20')
              end
            end

            local function notifySimple(title, text)
              notify(("eject_%s"):format(title:gsub("%s","_")), title, text, 'success','car-side','#38A169')
            end

            local function forcePedExitFromVehicle(ped, veh)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              if IsPedAPlayer(ped) then
                notify("cant_eject","Can't eject","Target is a player. Aborting.", 'error','ban','#DD6B20')
                return false
              end

              local netId = safePedToNet(ped)
              local key = netId and tostring(netId) or tostring(ped)
              local isCuffed = isPedActuallyCuffed(ped, key)
              if not isCuffed and netId and pedData[tostring(netId)] and (pedData[tostring(netId)].pulledProtected or pedData[tostring(netId)].pulledInVehicle) then
                notify("protected","Protected","This ped is protected while pulled. Use vehicle eject option to forcibly remove them.", 'warning','ban','#DD6B20')
                return false
              end

              if pedData[key] then
                local now = GetGameTimer()
                pedData[key].allowVehicleExitUntil = now + 7000
                pedData[key].preventVehicleReseatUntil = now + 15000
                pedData[key].detainedVehicleNet = nil
                pedData[key].detainedSeat = nil
                pedData[key].pulledProtected = false
                pedData[key].pulledInVehicle = false
                pedData[key].forcedStop = nil
              end

              NetworkRequestControlOfEntity(ped)
              if veh and veh ~= 0 and DoesEntityExist(veh) then NetworkRequestControlOfEntity(veh) end

              ClearPedTasksImmediately(ped)
              TaskLeaveVehicle(ped, veh, 16)
              SetBlockingOfNonTemporaryEvents(ped, false)

              Citizen.CreateThread(function()
                local deadline = GetGameTimer() + 3500
                while GetGameTimer() < deadline do
                  if not IsPedInAnyVehicle(ped, false) then
                    ClearPedTasksImmediately(ped)
                    if isCuffed then
                      applyCuffedPedState(ped, netId, true)
                      holdPedAttention(ped, false)
                      TaskStandStill(ped, 2500)
                    else
                      holdPedAttention(ped, false)
                      SetPedAsNoLongerNeeded(ped)
                    end
                    if veh and veh ~= 0 and DoesEntityExist(veh) then
                      NetworkRequestControlOfEntity(veh)
                      SetVehicleHandbrake(veh, true)
                      SetVehicleEngineOn(veh, false, true, true)
                      SetVehicleDoorsLocked(veh, 2)
                    end
                    break
                  end
                  Citizen.Wait(Config.Timings.shortWait)
                end
              end)

              return true
            end

            local function ejectDriver(veh)
              if not veh or not DoesEntityExist(veh) then
                return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
              end
              local driver = GetPedInVehicleSeat(veh, -1)
              if not driver or driver == 0 then
                return notify("no_driver","No Driver","No driver present.",'error','car-side','#E53E3E')
              end

              local dNet = safePedToNet(driver)
              if dNet then
                setPedProtected(dNet, false)
                markPulledInVehicle(dNet, false)
                if pedData[dNet] then pedData[dNet].forcedStop = nil end
              end

              if forcePedExitFromVehicle(driver, veh) then
                notifySimple("Driver Ejected","Driver has exited the vehicle.")
              end
            end

            local function ejectPassengers(veh)
              if not veh or not DoesEntityExist(veh) then
                return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
              end

              local any = false
              for seat = 0, 15 do
                local ped = GetPedInVehicleSeat(veh, seat)
                if ped and ped ~= 0 and not IsPedAPlayer(ped) then
                  local n = safePedToNet(ped)
                  if n then setPedProtected(n, false); markPulledInVehicle(n, false); if pedData[n] then pedData[n].forcedStop = nil end end
                  if forcePedExitFromVehicle(ped, veh) then any = true end
                end
              end

              if any then notifySimple("Passengers Ejected","Passengers asked to leave.")
              else notify("no_passengers","No Passengers","No NPC passengers to eject.",'error','car-side','#E53E3E') end
            end

            local function ejectAll(veh)
              if not veh or not DoesEntityExist(veh) then
                return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
              end

              local any = false
              local driver = GetPedInVehicleSeat(veh, -1)
              if driver and driver ~= 0 and not IsPedAPlayer(driver) then
                local n = safePedToNet(driver)
                if n then setPedProtected(n, false); markPulledInVehicle(n, false); if pedData[n] then pedData[n].forcedStop=nil end end
                if forcePedExitFromVehicle(driver, veh) then any = true end
              end

              for seat = 0, 15 do
                local ped = GetPedInVehicleSeat(veh, seat)
                if ped and ped ~= 0 and not IsPedAPlayer(ped) then
                  local n = safePedToNet(ped)
                  if n then setPedProtected(n, false); markPulledInVehicle(n, false); if pedData[n] then pedData[n].forcedStop = nil end end
                  if forcePedExitFromVehicle(ped, veh) then any = true end
                end
              end

              if any then notifySimple("All Ejected","All NPC occupants were made to exit.")
              else notify("none_ejected","Nothing Ejected","No NPC occupants found.",'error','car-side','#E53E3E') end
            end

            local function ensureTargetVehicle()
              if pullVeh and DoesEntityExist(pullVeh) then return pullVeh end
              local v = findVehicleAhead(20, 0.5)
              return v
            end

            local function attemptFirstAid()
              dprint("attemptFirstAid called")
              local player = PlayerPedId()
              local px,py,pz = toXYZ(GetEntityCoords(player))
              if not px then
                return notify("fa_fail_pos","First Aid","Could not determine player position.", 'error','heartbeat','#DD6B20')
              end

              local targetPed = nil
              if lastPedNetId then
                local maybe = safeNetToPed( tonumber(lastPedNetId) or lastPedNetId )
                if maybe and DoesEntityExist(maybe) and IsPedDeadOrDying(maybe, true) then
                  targetPed = maybe
                  dprint("attemptFirstAid: using lastPedNetId ped as target")
                end
              end

              if not targetPed and lib and type(lib.getClosestPed) == "function" then
                local ok, ped, pedCoords = pcall(function()
                  return lib.getClosestPed(vector3(px,py,pz), 8.0)
                end)

                if ok then

                  local foundPed = nil
                  if type(ped) == "number" then
                    foundPed = ped
                  elseif type(ped) == "table" and ped.ped then
                    foundPed = ped.ped
                  end

                  if foundPed and DoesEntityExist(foundPed) and IsPedDeadOrDying(foundPed, true) then

                    local isHuman = true
                    if type(IsPedHuman) == "function" then isHuman = IsPedHuman(foundPed) end
                    if isHuman then
                      targetPed = foundPed
                      dprint("attemptFirstAid: lib.getClosestPed found dead ped", tostring(foundPed))
                    else
                      dprint("attemptFirstAid: lib.getClosestPed returned non-human ped, ignoring")
                    end
                  else
                    dprint("attemptFirstAid: lib.getClosestPed returned no suitable dead ped")
                  end
                else
                  dprint("attemptFirstAid: lib.getClosestPed call errored")
                end
              end

              if not targetPed then
                local deadList = getNearbyDownedPeds(vector3(px,py,pz), 8.0, true)
                if #deadList > 0 then

                  local best, bestd = nil, 1e9
                  for _, ped in ipairs(deadList) do
                    local d = #(GetEntityCoords(ped) - vector3(px,py,pz))
                    if d < bestd then bestd, best = d, ped end
                  end
                  targetPed = best
                  dprint("attemptFirstAid: found nearby dead ped via fallback")
                end
              end

              if not targetPed or not DoesEntityExist(targetPed) then
                return notify("fa_none","No Casualty","No dead NPCs found nearby to revive.", 'warning','heartbeat','#DD6B20')
              end

              if IsPedAPlayer(targetPed) then
                return notify("fa_player","Cannot Revive Player","This function only revives NPCs.", 'error','ban','#E53E3E')
              end

              NetworkRequestControlOfEntity(targetPed)
              local start = GetGameTimer()
              while not NetworkHasControlOfEntity(targetPed) and (GetGameTimer() - start) < 1000 do
                NetworkRequestControlOfEntity(targetPed); Citizen.Wait(10)
              end
              SetEntityAsMissionEntity(targetPed, true, true)
              SetBlockingOfNonTemporaryEvents(targetPed, true)

              notify("fa_start","First Aid","Applying first aid. Please wait...", 'inform','heartbeat','#4299E1')

              local animDict = "mini@triathlon"
              RequestAnimDict(animDict)
              local loadStart = GetGameTimer()
              while not HasAnimDictLoaded(animDict) and (GetGameTimer() - loadStart) < 800 do Citizen.Wait(10) end
              if HasAnimDictLoaded(animDict) then
                TaskPlayAnim(PlayerPedId(), animDict, "idle_a", 8.0, -8.0, 4000, 49, 0, false, false, false)
              end

              local ok = safeProgressBar({ duration = 4000, label = "Applying First Aid" })
              if not ok then
                notify("fa_cancel","Cancelled","First aid action cancelled.", 'warning','ban','#DD6B20')

                SetBlockingOfNonTemporaryEvents(targetPed, false)
                SetEntityAsMissionEntity(targetPed, false, false)
                return
              end

              local successChance = 0.75
              local success = (math.random() < successChance)

              if success then

                NetworkRequestControlOfEntity(targetPed)
                SetEntityAsMissionEntity(targetPed, true, true)
                ClearPedTasksImmediately(targetPed)

                local maxHp = GetEntityMaxHealth(targetPed) or 200
                local restoreHp = math.min(maxHp, 140)
                SetEntityHealth(targetPed, restoreHp)

                Citizen.Wait(200)

                SetBlockingOfNonTemporaryEvents(targetPed, false)
                SetPedCanRagdoll(targetPed, true)
                SetPedKeepTask(targetPed, false)
                TaskWanderStandard(targetPed, 10.0, 10)
                notify("fa_ok","Revived","First aid successful. NPC revived.", 'success','heartbeat','#38A169')

                dprint("attemptFirstAid: revive SUCCESS for ped=", tostring(targetPed))
              else

                notify("fa_fail","Failed","First aid failed. Casualty not revived.", 'error','heartbeat','#E53E3E')
                dprint("attemptFirstAid: revive FAILED for ped=", tostring(targetPed))

                SetBlockingOfNonTemporaryEvents(targetPed, false)
                SetEntityAsMissionEntity(targetPed, false, false)
              end
            end

            local policeActionMenusRegistered = false

            local function registerPoliceActionMenus(force)
              if type(lib) ~= "table" or type(lib.registerContext) ~= "function" then
                return false, "ox_lib context unavailable"
              end
              if policeActionMenusRegistered and not force then
                return true
              end

              lib.registerContext({
                id='police_mainai',
                title='**Police Actions**',
                canClose=true,
                options={
                  { title='MDT (Records & Plate)', icon='search', arrow=true, onSelect=function() lib.showContext('police_mdt') end },
                  { title='AI Services', icon='heartbeat', arrow=true, onSelect=function() lib.showContext('police_ai') end },
                  { title='Ped Interaction', icon='user', arrow=true, onSelect=function() lib.showContext('police_ped') end },
                  { title='Simulation / Scene Tools', icon='clipboard-list', description='Open the integrated scene panel', onSelect=function() if openExternalMDT({ page = 'simTools' }) then TriggerServerEvent('az5pd:sim:requestState') return end TriggerEvent('az5pd:sim:openMenu') end },
                  { title='Vehicle Interaction', icon='car-side', arrow=true, onSelect=function() lib.showContext('vehicle_interact') end },
                  { title='Pull-Over AI', icon='car', onSelect=function() attemptPullOverAI(false) end },
                }
              })

              lib.registerContext({
                id='police_mdt',
                title='🔎 MDT',
                menu='police_mainai',
                canClose=true,
                options={
                  { title='Plate Lookup', icon='search', onSelect=runPlate },
                  { title='ID Lookup', icon='id-card', onSelect=function()
                      if lastPedNetId then showIDSafely(lastPedNetId)
                      else notify("id_err","ID","No ped stopped.",'error') end
                    end },
                  { title='Reports', icon='file-alt', onSelect=function() if openExternalMDT({ page = 'reports' }) then return end SendNUIMessage({ action='openSection', section='reports' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
                  { title='Warrants', icon='gavel', onSelect=function() if openExternalMDT({ page = 'warrants' }) then return end SendNUIMessage({ action='openSection', section='warrants' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
                  { title='Dispatch', icon='broadcast-tower', onSelect=function() if openExternalMDT({ page = 'callsHub' }) then return end SendNUIMessage({ action='openSection', section='dispatch' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
                }
              })

              lib.registerContext({
                id='police_ai',
                title='🤖 AI Services',
                menu='police_mainai',
                canClose=true,
                options={
                  { title='AI EMS', icon='heartbeat', onSelect=callAIEMS },
                  { title='AI Coroner', icon='skull-crossbones', onSelect=callAICoroner },
                  { title='AI Animal Control', icon='paw', onSelect=callAIAnimalControl },
                  { title='Tow Truck', icon='truck', onSelect=callTow },
                }
              })

              lib.registerContext({
                id='police_ped',
                title='👮 Ped Interaction',
                menu='police_mainai',
                canClose=true,
                options={
                  { title='Check ID', icon='id-card', onSelect=function() dprint("Context: Check ID selected"); showIDSafely(lastPedNetId) end },
                  { title='Search Ped', icon='magnifying-glass', onSelect=function() dprint("Context: Search Ped selected"); doSearch() end },
                  { title='Ask Questions', icon='comments', arrow=true, onSelect=function() lib.showContext('police_questions') end },
                  { title='Follow Me', icon='person-walking', onSelect=function() setPedFollowState(true) end },
                  { title='Stop Follow', icon='hand', onSelect=function() setPedFollowState(false) end },
                  { title='Tell Ped Get In Car', icon='car-side', onSelect=function() tellPedEnterVehicle() end },
                  { title='Issue Citation', icon='ticket-alt', onSelect=function() dprint("Context: Issue Citation selected"); doCitation() end },
                  { title='DUI / Field Tests', icon='wine-bottle', arrow=true, onSelect=function() lib.showContext('police_dui') end },
                  { title='Cuff Ped', icon='lock', onSelect=function() dprint("Context: Cuff Ped selected"); tryCuffPed() end },
                  { title='Arrest Ped', icon='handcuffs', onSelect=function() dprint("Context: Arrest Ped selected"); doArrest() end },
                  { title='Release Ped', icon='unlock', onSelect=function() dprint("Context: Release Ped selected"); releasePed() end },
                  { title='Drag/Undrag', icon='arrows-spin', onSelect=function() dprint("Context: Drag/Undrag selected"); toggleDragPed() end },
                  { title='Seat Left (from drag)', icon='car-side', onSelect=function() dprint("Context: Seat Left selected"); seatPed(1) end },
                  { title='Seat Right (from drag)', icon='car-side', onSelect=function() dprint("Context: Seat Right selected"); seatPed(2) end },

                  { title='First Aid (Revive)', icon='heartbeat', description='Attempt to revive a nearby dead NPC', onSelect=function()
                      dprint("Context: First Aid selected")
                      attemptFirstAid()
                    end },
                }
              })

              lib.registerContext({
                id='police_questions',
                title='💬 Ask Questions',
                menu='police_ped',
                canClose=true,
                options={
                  { title='Documentation', icon='id-card', onSelect=function() askPedQuestion('documentation') end },
                  { title='Travel Plans', icon='route', onSelect=function() askPedQuestion('travel') end },
                  { title='DUI / Impairment', icon='wine-bottle', onSelect=function() askPedQuestion('dui') end },
                  { title='Personal', icon='user', onSelect=function() askPedQuestion('personal') end },
                }
              })

              lib.registerContext({
                id='police_dui',
                title='🍺 DUI / Field Sobriety',
                menu='police_ped',
                canClose=true,
                options={
                  { title='Initial Observations', icon='eye', description='Document odor, speech, eyes, balance, and admissions.', onSelect=function() doDuiObservations() end },
                  { title='Walk-and-Turn', icon='person-walking', description='Standardized field sobriety balance test. Requires subject on foot and uncuffed.', onSelect=function() doDuiTest('walk_turn') end },
                  { title='Line Walk', icon='road', description='Simple straight-line balance check. Requires subject on foot and uncuffed.', onSelect=function() doDuiTest('line_walk') end },
                  { title='One-Leg Stand', icon='person', description='Balance test. Requires subject on foot and uncuffed.', onSelect=function() doDuiTest('one_leg') end },
                  { title='Eye Test / HGN', icon='eye', description='Checks eye tracking clues associated with impairment.', onSelect=function() doDuiTest('hgn') end },
                  { title='Breathalyzer (PBT)', icon='wind', description='Roadside preliminary breath test.', onSelect=function() doDuiTest('breathalyzer') end },
                  { title='BAC Test', icon='vial-circle-check', description='Formal evidential alcohol concentration test.', onSelect=function() doDuiTest('bac') end },
                  { title='Drug Test', icon='capsules', description='Oral fluid / roadside drug screen.', onSelect=function() doDuiTest('drug') end },
                  { title='Review DUI Summary', icon='clipboard-check', description='See all observations and test results with probable cause guidance.', onSelect=function() showDuiSummary() end },
                }
              })


              lib.registerContext({
                id='vehicle_interact',
                title='🚗 Vehicle Interaction',
                menu='police_mainai',
                canClose=true,
                options={
            { title='Finish Pull-Over', icon='car', description='Wait for you to get back in your vehicle, then let the stopped car leave', onSelect=function()
                dprint("Context: Finish Pull-Over selected")
                if not pullVeh or not DoesEntityExist(pullVeh) then return end
                local veh = pullVeh
                local function playerReadyToRelease()
                  local player = PlayerPedId()
                  if not IsPedInAnyVehicle(player, false) then return false end
                  local playerVeh = GetVehiclePedIsIn(player, false)
                  return playerVeh and playerVeh ~= 0 and playerVeh ~= veh
                end
                if not playerReadyToRelease() then
                  notify('pull_wait_vehicle', 'Finish Pull-Over', 'Get back into your patrol vehicle and the stopped car will leave once you are inside.', 'inform', 'car-side', '#4299E1')
                  Citizen.CreateThread(function()
                    local waited = 0
                    while waited < 45000 do
                      if playerReadyToRelease() then
                        releasePulloverVehicle(veh)
                        return
                      end
                      Citizen.Wait(300)
                      waited = waited + 300
                    end
                    notify('pull_wait_timeout', 'Finish Pull-Over', 'Release cancelled because you never got back into your vehicle.', 'warning', 'car-side', '#DD6B20')
                  end)
                  return
                end
                releasePulloverVehicle(veh)
              end },

                  { title='Tell Occupant Get In Vehicle', icon='car-side', description='Pick a seat and send the subject back into a vehicle', onSelect=function()
                      tellPedEnterVehicle()
                    end },

                  { title='Eject Driver (NPC)', icon='person', description='Make driver exit', onSelect=function()
                      dprint("Context: Eject Driver selected")
                      local veh = ensureTargetVehicle()
                      ejectDriver(veh)
                    end },
                  { title='Eject Passengers (NPC)', icon='users', description='Make NPC passengers exit', onSelect=function()
                      dprint("Context: Eject Passengers selected")
                      local veh = ensureTargetVehicle()
                      ejectPassengers(veh)
                    end },
                  { title='Eject All (NPC)', icon='people-arrows', description='Make all NPC occupants exit', onSelect=function()
                      dprint("Context: Eject All selected")
                      local veh = ensureTargetVehicle()
                      ejectAll(veh)
                    end },

                }
              })

              policeActionMenusRegistered = true
              return true
            end

            local function ensurePoliceActionMenus(force)
              local ok, err = pcall(function() return registerPoliceActionMenus(force) end)
              if not ok then
                policeActionMenusRegistered = false
                dprint(("registerPoliceActionMenus failed: %s"):format(tostring(err)))
                return false
              end
              return true
            end

            Citizen.CreateThread(function()
              local attempts = 0
              while attempts < 40 do
                attempts = attempts + 1
                if ensurePoliceActionMenus(attempts > 1) then
                  return
                end
                Citizen.Wait(250)
              end
              dprint("Police action menus were not registered after startup retries")
            end)

            AddEventHandler('__clientRequestPopulate', function()
              local lastName = nil
              if lastPedNetId and pedData[tostring(lastPedNetId)] and pedData[tostring(lastPedNetId)].name then
                lastName = pedData[tostring(lastPedNetId)].name
              end

              SendNUIMessage({
                action       = 'populate',
                plate        = lastPlate or "",
                netId        = lastPedNetId or "",
                lastPedName  = lastName or "",
                plateHistory = lastPlateHistory,
                idHistory    = lastIdHistory or {},
                make         = lastMake or "",
                color        = lastColor or ""
              })
            end)

            RegisterNetEvent('az-police:receiveAIDispatch', function(service, callerServerId)
              local s = tostring(service or ""):lower()
              local mapping = {
                ems = callAIEMS,
                coroner = callAICoroner,
                animal = callAIAnimalControl,
                tow = callTow
              }

              local fn = mapping[s]
              if not fn then

                if notify then notify("ai_dispatch_bad","Dispatch","Unknown service: "..tostring(service), 'error') end
                return
              end

              Citizen.CreateThread(function()
                Citizen.Wait(Config.Timings.cleanupDelay)
                if notify then notify("ai_dispatch_recv","Dispatch","AI "..s.." requested; responding now.", 'inform') end
                pcall(fn)
              end)
            end)

            RegisterNUICallback('createRecord', function(data, cb)

              TriggerServerEvent('mdt:createRecord', data)
              cb('ok')
            end)

            RegisterNUICallback('listRecords', function(data, cb)

              TriggerServerEvent('mdt:listRecords', data)
              cb('ok')
            end)

            RegisterNetEvent('mdt:recordsResult', function(records, target_type, target_value)

              if target_type == 'plate' then
                lastPlateHistory = lastPlateHistory or {}

                if target_value and target_value ~= "" then
                  local found = false
                  for _, v in ipairs(lastPlateHistory) do if v == target_value then found = true; break end end
                  if not found then table.insert(lastPlateHistory, 1, target_value) end
                end
              else
                lastIdHistory = lastIdHistory or {}
                if target_value and target_value ~= "" then
                  local found = false
                  for _, v in ipairs(lastIdHistory) do if v == target_value then found = true; break end end
                  if not found then table.insert(lastIdHistory, 1, target_value) end
                end
              end

              SendNUIMessage({
                action       = 'recordsResult',
                records      = records or {},
                target_type  = target_type or '',
                target_value = target_value or ''
              })

              print(('[mdt] forwarded %d MDT record(s) for %s=%s to NUI'):format((records and #records) or 0, tostring(target_type), tostring(target_value)))
            end)

            RegisterNUICallback('lookupPlate', function(data, cb)
              if data.plate and data.plate:match("%S+") then lastPlate = data.plate:upper() end
              runPlate()
              cb('ok')
            end)

            RegisterNUICallback('lookupID', function(data, cb)
              if data and data.name and tostring(data.name):match("%S") then
                TriggerServerEvent('mdt:lookupID', { name = tostring(data.name) })
              elseif lastPedNetId then
                TriggerServerEvent('mdt:lookupID', lastPedNetId)
              elseif data and data.netId and tostring(data.netId):match("%S") then
                TriggerServerEvent('mdt:lookupID', tostring(data.netId))
              else
                notify("id_failed","Lookup Failed",
                      "No ped stopped. Pull someone over or enter a NetID or name.",
                      'error','ban','#DD6B20')
              end
              cb('ok')
            end)

            RegisterNUICallback('escape', function(_, cb)
              isOpen = false
              SetNuiFocus(false,false)
              SendNUIMessage({action='close'})
              cb('ok')
            end)

            RegisterNUICallback('createReport', function(data, cb)
              TriggerServerEvent('mdt:createReport', data.title or "", data.description or "", data.type or "General")
              cb('ok')
            end)
            RegisterNUICallback('listReports', function(_, cb)
              TriggerServerEvent('mdt:listReports')
              cb('ok')
            end)
            RegisterNUICallback('deleteReport', function(data, cb)
              TriggerServerEvent('mdt:deleteReport', data.id)
              cb('ok')
            end)

            RegisterNUICallback('createWarrant', function(data, cb)
              TriggerServerEvent('mdt:createWarrant', data.subject_name or "", data.subject_netId or "", data.charges or "")
              cb('ok')
            end)
            RegisterNUICallback('listWarrants', function(_, cb)
              TriggerServerEvent('mdt:listWarrants')
              cb('ok')
            end)
            RegisterNUICallback('removeWarrant', function(data, cb)
              TriggerServerEvent('mdt:removeWarrant', data.id)
              cb('ok')
            end)

            RegisterNUICallback('createDispatch', function(data, cb)
              TriggerServerEvent('mdt:createDispatch', data.caller_name or "", data.location or "", data.message or "")
              cb('ok')
            end)
            RegisterNUICallback('listDispatch', function(_, cb)
              TriggerServerEvent('mdt:listDispatch')
              cb('ok')
            end)
            RegisterNUICallback('ackDispatch', function(data, cb)
              if data and data.id then
                TriggerServerEvent('mdt:ackDispatch', data.id)
              end
              cb('ok')
            end)


            local function runAmbientSuspiciousReaction(player, ped, pedKey, info, dist)
              local cfg = getImmersionConfig()
              local behavior = cfg.behavior or {}
              if behavior.enableAmbientReactions == false then return end
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              if not info or info.suspicious ~= true then return end
              if info.cuffed or info.forcedStop or info.pulledProtected or info.pulledInVehicle then return end
              local now = GetGameTimer()
              if tonumber(info.reactionLockedUntil or 0) > now then return end
              if IsPedDeadOrDying(ped, true) then return end

              local inVehicle = IsPedInAnyVehicle(ped, false)
              local reactionDistance = inVehicle and (tonumber(behavior.reactionDistanceVehicle) or 28.0) or (tonumber(behavior.reactionDistanceOnFoot) or 18.0)
              local shouldReact = false
              if IsPlayerFreeAimingAtEntity(PlayerId(), ped) then
                shouldReact = true
              elseif playerPresenceFeelsThreatening() and dist <= reactionDistance then
                shouldReact = true
              elseif dist <= (reactionDistance * 0.65) and (info.wanted or info.hasIllegalItems or info.isHigh or info.isDrunk) then
                shouldReact = math.random() < 0.35
              end
              if not shouldReact then return end

              info.reactionLockedUntil = now + (tonumber(behavior.cooldownMs) or 20000)
              pedData[tostring(pedKey)] = info

              NetworkRequestControlOfEntity(ped)
              SetEntityAsMissionEntity(ped, true, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedKeepTask(ped, true)
              pcall(SetPedAlertness, ped, info.wanted and 3 or 2)

              local function triggerSuspiciousVehicleBehavior(driverPed, vehEntity, suspectInfo)
                if not driverPed or driverPed == 0 or not DoesEntityExist(driverPed) then return false end
                if not vehEntity or vehEntity == 0 or not DoesEntityExist(vehEntity) then return false end
                if GetPedInVehicleSeat(vehEntity, -1) ~= driverPed then return false end

                NetworkRequestControlOfEntity(vehEntity)
                SetEntityAsMissionEntity(vehEntity, true, true)
                SetVehicleEngineOn(vehEntity, true, true, true)
                SetVehicleUndriveable(vehEntity, false)
                SetVehicleHandbrake(vehEntity, false)
                SetVehicleDoorsLocked(vehEntity, 1)

                local isImpaired = suspectInfo and (suspectInfo.isDrunk or suspectInfo.isHigh)
                local isSerious = suspectInfo and (suspectInfo.wanted or suspectInfo.hasIllegalItems)
                local driveSpeed = isImpaired and 14.0 or (isSerious and 28.0 or 20.0)
                local driveStyle = isImpaired and 786468 or ((Config and Config.Wander and Config.Wander.driveStyle) or 786603)

                if type(SetDriverAbility) == "function" then pcall(SetDriverAbility, driverPed, isImpaired and 0.45 or 0.85) end
                if type(SetDriverAggressiveness) == "function" then pcall(SetDriverAggressiveness, driverPed, isSerious and 0.85 or 0.45) end
                if type(SetDriveTaskDrivingStyle) == "function" then pcall(SetDriveTaskDrivingStyle, driverPed, driveStyle) end
                if type(SetDriveTaskCruiseSpeed) == "function" then pcall(SetDriveTaskCruiseSpeed, driverPed, driveSpeed) end

                if isImpaired then
                  SetVehicleForwardSpeed(vehEntity, math.max(GetEntitySpeed(vehEntity), 6.0))
                  TaskVehicleDriveWander(driverPed, vehEntity, driveSpeed, driveStyle)
                  Citizen.CreateThread(function()
                    local untilAt = GetGameTimer() + 5000
                    while GetGameTimer() < untilAt and DoesEntityExist(driverPed) and DoesEntityExist(vehEntity) and GetPedInVehicleSeat(vehEntity, -1) == driverPed do
                      StartVehicleHorn(vehEntity, 120, GetHashKey("HELDDOWN"), false)
                      TaskVehicleTempAction(driverPed, vehEntity, math.random(4, 5), math.random(350, 700))
                      Citizen.Wait(math.random(850, 1400))
                    end
                  end)
                elseif isSerious then
                  if not startFleeDrive(driverPed, vehEntity) then
                    TaskVehicleDriveWander(driverPed, vehEntity, driveSpeed, driveStyle)
                    Citizen.CreateThread(function()
                      StartVehicleHorn(vehEntity, 80, GetHashKey("HELDDOWN"), false)
                    end)
                  end
                else
                  TaskVehicleDriveWander(driverPed, vehEntity, driveSpeed, driveStyle)
                  Citizen.CreateThread(function()
                    StartVehicleHorn(vehEntity, 60, GetHashKey("HELDDOWN"), false)
                  end)
                end
                return true
              end

              if inVehicle then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                  local driver = GetPedInVehicleSeat(veh, -1)
                  if driver and driver ~= 0 and DoesEntityExist(driver) then
                    triggerSuspiciousVehicleBehavior(driver, veh, info)
                  end
                  return
                end
              end

              if info.disposition == 'hide' then
                local pedCoords = GetEntityCoords(ped)
                local playerCoords = GetEntityCoords(player)
                local away = pedCoords - playerCoords
                local distLen = #(away)
                if distLen < 0.01 then away = vector3(1.0, 0.0, 0.0) distLen = 1.0 end
                away = away / distLen
                local side = vector3(-away.y, away.x, 0.0)
                local sideMul = (math.random() < 0.5) and -1.0 or 1.0
                local hideDist = tonumber(behavior.hideDistance) or 20.0
                local target = pedCoords + (away * hideDist) + (side * 7.0 * sideMul)
                TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.15, -1, 0.0, 0.0)
                Citizen.CreateThread(function()
                  Citizen.Wait(2500)
                  if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and not IsPedInAnyVehicle(ped, false) then
                    TaskWanderStandard(ped, 10.0, 10)
                  end
                end)
                return
              end

              if info.disposition == 'nervous' and not info.wanted and not info.hasIllegalItems then
                TaskWanderStandard(ped, 10.0, 10)
                return
              end

              if type(TaskReactAndFleePed) == 'function' and math.random() < 0.55 then
                TaskReactAndFleePed(ped, player)
              else
                TaskSmartFleePed(ped, player, 180.0, -1, false, false)
              end
            end

            Citizen.CreateThread(function()
              while true do
                local cfg = getImmersionConfig()
                local waitMs = tonumber(cfg.scanIntervalMs) or 2500
                Citizen.Wait(waitMs)

                if not immersionEnabled() then goto continue end
                if cfg.requirePoliceJob == true and not isJobAllowed(job) then goto continue end
                local player = PlayerPedId()
                if not player or player == 0 then goto continue end
                local playerCoords = GetEntityCoords(player)
                local scanRadius = tonumber(cfg.scanRadius) or 55.0
                local maxNearby = math.max(1, tonumber(cfg.maxNearbyPeds) or 18)
                local nearby = {}
                local pool = GetGamePool('CPed') or {}

                for _, ped in ipairs(pool) do
                  if ped ~= player and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) and IsPedHuman(ped) then
                    local pedCoords = GetEntityCoords(ped)
                    local dist = #(pedCoords - playerCoords)
                    if dist <= scanRadius then
                      nearby[#nearby + 1] = { ped = ped, dist = dist }
                    end
                  end
                end

                table.sort(nearby, function(a, b) return a.dist < b.dist end)
                for i = 1, math.min(#nearby, maxNearby) do
                  local entry = nearby[i]
                  local ped = entry.ped
                  local pedKey = tostring(safePedToNet(ped) or ped)
                  ensurePerson(pedKey)
                  pedData[pedKey] = pedData[pedKey] or {}
                  pedData[pedKey].entity = ped
                  pedData[pedKey] = enrichPedImmersionProfile(ped, pedData[pedKey])
                  runAmbientSuspiciousReaction(player, ped, pedKey, pedData[pedKey], entry.dist)
                end

                ::continue::
              end
            end)

            RegisterNetEvent('mdt:plateResult', function(payload)
              lastPlate        = payload and payload.plate or lastPlate
              lastPlateHistory = payload and payload.records or lastPlateHistory

              SendNUIMessage({
                action    = 'plateResult',
                plate     = payload and payload.plate or "",
                status    = payload and payload.status or "",
                records   = payload and payload.records or {},
                make      = payload and payload.make or lastMake or "",
                color     = payload and payload.color or lastColor or "",
                owner     = payload and payload.owner or "",
                insurance = payload and payload.insurance or ""
              })
            end)

            RegisterNetEvent('mdt:idResult', function(payload)
              lastIdHistory = {}
              if payload and type(payload.records) == 'table' then
                for _, r in ipairs(payload.records) do
                  local display = ""
                  if r.first_name or r.last_name then
                    display = ((r.first_name or "") .. " " .. (r.last_name or "")):gsub("^%s+",""):gsub("%s+$","")
                  else
                    display = tostring(r.netId or r.identifier or "")
                  end
                  if display ~= "" then table.insert(lastIdHistory, display) end
                end
              end

              local payloadNetId = payload and payload.netId or ""
              local payloadKey = tostring(payloadNetId or "")
              if payloadKey ~= "" then
                ensurePerson(payloadKey)
                pedData[payloadKey] = pedData[payloadKey] or {}
                pedData[payloadKey].licenseStatus = payload and payload.licenseStatus or ""
                pedData[payloadKey].lastLookupAt = GetGameTimer()
                pedData[payloadKey].idChecked = true
                pedData[payloadKey].stopAwaitingId = false
              end

              SendNUIMessage({
                action        = 'idResult',
                netId         = payloadNetId,
                name          = payload and payload.name or "",
                licenseStatus = payload and payload.licenseStatus or "",
                records       = payload and payload.records or {}
              })

              -- Do not release the stop or in-vehicle protection after an ID check.
              -- Check ID should leave the target seated until an explicit release/end-stop action happens.
            end)

            RegisterNetEvent('police:syncNpcCuff', function(netId, state)
              local ped = safeNetToPed(tonumber(netId) or netId)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local pedKey = tostring(netId or safePedToNet(ped) or ped)
              cachePedReference(ped, pedKey)
              if state == false then
                markPedCuffedState(ped, pedKey, false)
                clearTrackedCuffStateForPed(ped, pedKey)
                resetPedCuffPresentation(ped, false, false)
                return
              end
              local isCuffed = isPedActuallyCuffed(ped, pedKey)
              if not isCuffed then
                applyCuffedPedState(ped, pedKey, false)
              else
                enforceCuffedPedState(ped, pedKey, pedData[tostring(pedKey)] or {})
              end
            end)

            RegisterNetEvent('police:accountabilityNotice', function(payload)
              payload = payload or {}
              local level = tostring(payload.level or 'inform')
              local title = tostring(payload.title or 'Officer Accountability')
              local description = tostring(payload.description or '')
              local icon = tostring(payload.icon or 'scale-balanced')
              local color = tostring(payload.iconColor or '#DD6B20')
              notify('police_accountability_' .. level, title, description, level, icon, color)
            end)

            RegisterNetEvent('mdt:reportsResult', function(records)
              SendNUIMessage({ action='reportsResult', records = records or {} })
            end)

            RegisterNetEvent('mdt:warrantsResult', function(records)
              SendNUIMessage({ action='warrantsResult', records = records or {} })
            end)

            RegisterNetEvent('mdt:dispatchResult', function(records)
              SendNUIMessage({ action='dispatchResult', records = records or {} })
            end)

            RegisterNetEvent('mdt:dispatchNotify', function(call)
              if call then
                local title = ("Dispatch #%s"):format(tostring(call.id or "?"))
                local desc = ("Caller: %s\nLocation: %s\nMessage: %s\nStatus: %s%s")
                  :format(tostring(call.caller_name or "Unknown"),
                          tostring(call.location or "Unknown"),
                          tostring(call.message or ""),
                          tostring(call.status or "ACTIVE"),
                          call.assigned_to and ("\nAssigned: "..tostring(call.assigned_to)) or "")
                notify(("dispatch_%s"):format(tostring(call.id or "?")), title, desc, 'inform','broadcast-tower','#F6E05E')
                SendNUIMessage({ action='dispatchNotify', call = call })
              end
            end)

            RegisterNetEvent('mdt:warrantNotify', function(warrant)
              if warrant then
                local status = (warrant.active == 1 or warrant.active == true) and "ACTIVE" or "CLEARED"
                local title = ("Warrant #%s — %s"):format(tostring(warrant.id or "?"), status)
                local desc = ("Subject: %s\nNetID: %s\nCharges: %s\nIssued by: %s\nTime: %s")
                  :format(tostring(warrant.subject_name or "Unknown"),
                          tostring(warrant.subject_netId or "N/A"),
                          tostring(warrant.charges or ""),
                          tostring(warrant.issued_by or "Unknown"),
                          tostring(warrant.timestamp or ""))
                notify(("warrant_%s"):format(tostring(warrant.id or "?")), title, desc, (status=="ACTIVE") and 'error' or 'success','gavel','#FF9F43')
                SendNUIMessage({ action='warrantNotify', warrant = warrant })
              end
            end)

            local function cancelNonForcedStops()
              local count = 0
              for netId, info in pairs(pedData) do
                if info and info.pulledProtected and not info.forcedStop and not info.cuffed then
                  local ped = safeNetToPed(tonumber(netId) or netId)
                  if DoesEntityExist(ped) then
                    releasePedAttention(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, false)
                    SetPedKeepTask(ped, false)
                    SetEntityAsMissionEntity(ped, false, false)
                  end
                  info.pulledProtected = false
                  info.pulledInVehicle = false
                  info.forcedStop = nil
                  count = count + 1
                end
              end
              if count > 0 then
                notify("cancel_stops","Stops Cancelled", tostring(count).." non-forced stop(s) released.", 'inform','ban','#DD6B20')
              end
            end

            RegisterNUICallback('updatePlateStatus', function(d,cb)
              TriggerServerEvent('mdt:updatePlateStatus', d.plate, d.newStatus); cb('ok')
            end)
            RegisterNUICallback('addIDRecord', function(d,cb)
              TriggerServerEvent('mdt:addIDRecord', d.netId, d.fullName, d.type); cb('ok')
            end)
            RegisterNUICallback('editIDRecord', function(d,cb)
              TriggerServerEvent('mdt:editIDRecord', d.recordId, d.newType); cb('ok')
            end)
            RegisterNUICallback('deleteIDRecord', function(d,cb)
              TriggerServerEvent('mdt:deleteIDRecord', d.recordId); cb('ok')
            end)
            RegisterNUICallback('deletePlateRecord', function(d,cb)
              TriggerServerEvent('mdt:deletePlateRecord', d.recordId); cb('ok')
            end)

            RegisterCommand('toggleMDT', toggleMDT)
            RegisterKeyMapping('toggleMDT','Open/Close MDT','keyboard','B')

            local policeMenuBusy = false

            local function isPoliceMenuJob(job)
              if not job then return false end
              local list = (Config and Config.PoliceMenuJobs) or { 'police' }
              for _,j in ipairs(list) do
                if job == j then return true end
              end
              return false
            end


            local function getNearbyGunpointGroup(targetPed, player)
              local cfg = (Config and Config.GunpointCompliance) or {}
              local radius = tonumber(cfg.groupRadius) or 12.0
              local maxGroupSize = math.max(1, tonumber(cfg.maxGroupSize) or 5)
              local maxNearbyCandidates = math.max(maxGroupSize, tonumber(cfg.maxNearbyCandidates) or 10)
              local anchorCoords = GetEntityCoords(targetPed)
              local anchorVeh = IsPedInAnyVehicle(targetPed, false) and GetVehiclePedIsIn(targetPed, false) or 0
              local results, seen = {}, {}

              local function considerPed(ped, reason, engaged)
                if not ped or ped == 0 or seen[ped] then return end
                if not DoesEntityExist(ped) or IsPedAPlayer(ped) or IsEntityDead(ped) or not IsPedHuman(ped) then return end
                if ped == player then return end

                local sameVeh = anchorVeh ~= 0 and IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) == anchorVeh
                local dist = #(GetEntityCoords(ped) - anchorCoords)
                if not sameVeh and dist > radius then return end

                local pedKey = tostring(safePedToNet(ped) or ped)
                if isPedActuallyCuffed(ped, pedKey) then return end

                ensurePerson(pedKey)
                seen[ped] = true
                results[#results + 1] = { ped = ped, key = pedKey, dist = dist, reason = reason or 'nearby', engaged = engaged == true }
              end

              considerPed(targetPed, 'target', IsPedInCombat(targetPed, player) or IsPedInMeleeCombat(targetPed))

              if anchorVeh ~= 0 and (cfg.includePassengers ~= false) then
                for seat = -1, GetVehicleMaxNumberOfPassengers(anchorVeh) - 1 do
                  local occ = GetPedInVehicleSeat(anchorVeh, seat)
                  if occ and occ ~= 0 then
                    considerPed(occ, seat == -1 and 'driver' or 'occupant', IsPedInCombat(occ, player) or IsPedInMeleeCombat(occ))
                  end
                end
              end

              if cfg.includeNearbyCombatants ~= false then
                local handle, ped = FindFirstPed()
                local ok = (handle ~= -1)
                local scanned = 0
                while ok do
                  if ped ~= targetPed and DoesEntityExist(ped) then
                    local dist = #(GetEntityCoords(ped) - anchorCoords)
                    if dist <= radius then
                      local engaged = IsPedInCombat(ped, player) or IsPedInCombat(targetPed, ped) or IsPedInCombat(ped, targetPed) or IsPedInMeleeCombat(ped)
                      local closeAssociate = dist <= math.max(4.5, radius * 0.45)
                      if engaged or closeAssociate then
                        considerPed(ped, engaged and 'combatant' or 'associate', engaged)
                      end
                    end
                    scanned = scanned + 1
                    if scanned >= maxNearbyCandidates then break end
                  end
                  ok, ped = FindNextPed(handle)
                end
                EndFindPed(handle)
              end

              table.sort(results, function(a, b)
                if a.reason == 'target' then return true end
                if b.reason == 'target' then return false end
                if a.engaged ~= b.engaged then return a.engaged end
                return a.dist < b.dist
              end)

              while #results > maxGroupSize do
                table.remove(results)
              end

              return results
            end

            local function getGunpointResistanceScore(entry, isPrimary)
              local cfg = (Config and Config.GunpointCompliance) or {}
              local base = tonumber(cfg.baseSingleResistChance) or 0.14
              local person = ensurePerson(entry.key) or {}
              local score = base

              if person.wanted then score = score + 0.20 end
              if person.hasIllegalItems then score = score + 0.12 end
              if person.isDrunk or person.isHigh then score = score + 0.08 end
              if person.nervous then score = score + 0.05 end
              if entry.engaged then score = score + 0.10 end
              if isPrimary then score = score + 0.05 end

              return math.min(0.85, math.max(0.05, score))
            end

            local function applyPedGunpointCompliance(targetPed, player, pedKey, delayMs, promoteLastPed)
              Citizen.CreateThread(function()
                if delayMs and delayMs > 0 then Citizen.Wait(delayMs) end
                if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or IsPedAPlayer(targetPed) then return end

                local targetVeh = IsPedInAnyVehicle(targetPed, false) and GetVehiclePedIsIn(targetPed, false) or 0
                if targetVeh and targetVeh ~= 0 and DoesEntityExist(targetVeh) then
                  NetworkRequestControlOfEntity(targetVeh)
                  SetVehicleDoorsLocked(targetVeh, 1)
                  forcePedExitFromVehicle(targetPed, targetVeh)
                  Citizen.Wait(350)
                end

                NetworkRequestControlOfEntity(targetPed)
                ClearPedTasksImmediately(targetPed)
                SetBlockingOfNonTemporaryEvents(targetPed, true)
                SetPedCanRagdoll(targetPed, false)
                SetPedKeepTask(targetPed, true)
                TaskTurnPedToFaceEntity(targetPed, player, 1200)
                TaskHandsUp(targetPed, 2500, player, -1, true)

                pedData[tostring(pedKey)] = pedData[tostring(pedKey)] or {}
                pedData[tostring(pedKey)].forcedStop = true
                pedData[tostring(pedKey)].pulledProtected = true
                pedData[tostring(pedKey)].gunpointState = 'complied'
                pedData[tostring(pedKey)].gunpointResolvedAt = GetGameTimer()

                if promoteLastPed then
                  lastPedNetId = tostring(pedKey)
                  lastPedEntity = targetPed
                end

                Citizen.CreateThread(function()
                  Citizen.Wait(2200)
                  if not DoesEntityExist(targetPed) then return end
                  ClearPedTasks(targetPed)
                  if loadAnimDictTimed("random@arrests@busted", 800) then
                    TaskPlayAnim(targetPed, "random@arrests@busted", "idle_a", 4.0, -4.0, -1, 1, 0.0, false, false, false)
                  else
                    TaskCower(targetPed, -1)
                  end
                  holdPedAttention(targetPed, false)
                end)
              end)
            end

            local function applyPedGunpointFight(targetPed, player, pedKey, delayMs)
              Citizen.CreateThread(function()
                if delayMs and delayMs > 0 then Citizen.Wait(delayMs) end
                if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or IsPedAPlayer(targetPed) then return end

                local targetVeh = IsPedInAnyVehicle(targetPed, false) and GetVehiclePedIsIn(targetPed, false) or 0
                if targetVeh and targetVeh ~= 0 and DoesEntityExist(targetVeh) then
                  NetworkRequestControlOfEntity(targetVeh)
                  SetVehicleDoorsLocked(targetVeh, 1)
                  forcePedExitFromVehicle(targetPed, targetVeh)
                  Citizen.Wait(350)
                end

                NetworkRequestControlOfEntity(targetPed)
                ClearPedTasksImmediately(targetPed)
                SetBlockingOfNonTemporaryEvents(targetPed, false)
                SetPedCanRagdoll(targetPed, true)
                SetPedKeepTask(targetPed, true)
                SetPedAsEnemy(targetPed, true)
                SetPedFleeAttributes(targetPed, 0, false)
                TaskCombatPed(targetPed, player, 0, 16)

                pedData[tostring(pedKey)] = pedData[tostring(pedKey)] or {}
                pedData[tostring(pedKey)].gunpointState = 'resisted'
                pedData[tostring(pedKey)].gunpointResolvedAt = GetGameTimer()
              end)
            end

            local function commandPedSurrenderAtGunpoint(targetPed)
              if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or IsPedAPlayer(targetPed) then return false end

              local player = PlayerPedId()
              local cfg = (Config and Config.GunpointCompliance) or {}
              local group = getNearbyGunpointGroup(targetPed, player)
              if not group or #group == 0 then return false end

              local fightIndex = nil
              local strongestIndex, strongestScore = nil, -1.0

              for i, entry in ipairs(group) do
                local score = getGunpointResistanceScore(entry, i == 1)
                entry.resistanceScore = score
                if score > strongestScore then
                  strongestScore = score
                  strongestIndex = i
                end
              end

              if #group == 1 then
                if math.random() < (group[1].resistanceScore or 0.14) then
                  fightIndex = 1
                end
              elseif strongestIndex then
                local chance = tonumber(cfg.groupOneFightsChance) or 0.42
                chance = math.min(0.90, chance + math.max(0.0, (strongestScore or 0.0) - 0.24))
                if math.random() < chance then
                  fightIndex = strongestIndex
                end
              end

              lastPedNetId = tostring(group[1].key)
              lastPedEntity = group[1].ped

              local complied, resisted = 0, 0
              local delayMin = tonumber(cfg.delayMinMs) or 120
              local delayMax = tonumber(cfg.delayMaxMs) or 520
              if delayMax < delayMin then delayMax = delayMin end

              for i, entry in ipairs(group) do
                local delay = delayMin
                if delayMax > delayMin then
                  delay = delayMin + math.random(0, delayMax - delayMin)
                end

                if fightIndex and i == fightIndex then
                  resisted = resisted + 1
                  applyPedGunpointFight(entry.ped, player, entry.key, delay)
                else
                  complied = complied + 1
                  applyPedGunpointCompliance(entry.ped, player, entry.key, delay, i == 1)
                end
              end

              return {
                ok = true,
                total = #group,
                complied = complied,
                resisted = resisted,
                primaryFought = fightIndex == 1
              }
            end

            local gunpointHoldStart, gunpointHoldTarget, gunpointLastNotify, gunpointCooldown = 0, 0, 0, 0

            local function isTargetModifierHeld()
              return IsControlPressed(0, 19) or IsDisabledControlPressed(0, 19)
            end

            local function shouldSuppressAltTargetCombat()
              local player = PlayerPedId()
              if not player or player == 0 or not DoesEntityExist(player) then return false end
              if IsEntityDead(player) or IsPauseMenuActive() or IsNuiFocused() then return false end
              if not isTargetModifierHeld() then return false end
              local weapon = GetSelectedPedWeapon(player)
              if not weapon or weapon == 0 or weapon == `WEAPON_UNARMED` then return false end
              return IsPedArmed(player, 6)
            end

            Citizen.CreateThread(function()
              while true do
                if shouldSuppressAltTargetCombat() then
                  DisableControlAction(0, 24, true)
                  DisableControlAction(0, 140, true)
                  DisableControlAction(0, 141, true)
                  DisableControlAction(0, 142, true)
                  DisableControlAction(0, 257, true)
                  DisableControlAction(0, 263, true)
                  DisableControlAction(0, 264, true)
                  Citizen.Wait(0)
                else
                  Citizen.Wait(50)
                end
              end
            end)

            Citizen.CreateThread(function()
              while true do
                Citizen.Wait(0)
                if (GetGameTimer() < gunpointCooldown) or IsPauseMenuActive() or IsNuiFocused() then
                  gunpointHoldStart, gunpointHoldTarget = 0, 0
                else
                  local player = PlayerPedId()
                  local armed = IsPedArmed(player, 6)
                  local aiming = IsPlayerFreeAiming(PlayerId())
                  local _, aimedEntity = GetEntityPlayerIsFreeAimingAt(PlayerId())

                  if armed and aiming and IsControlPressed(0, 21) and aimedEntity and aimedEntity ~= 0 and DoesEntityExist(aimedEntity) then
                    local targetPed = nil
                    if IsEntityAPed(aimedEntity) then
                      targetPed = aimedEntity
                    elseif IsEntityAVehicle(aimedEntity) then
                      local driver = GetPedInVehicleSeat(aimedEntity, -1)
                      if driver and driver ~= 0 and not IsPedAPlayer(driver) then
                        targetPed = driver
                      end
                    end

                    if targetPed and not IsPedAPlayer(targetPed) then
                      if gunpointHoldTarget ~= targetPed then
                        gunpointHoldTarget = targetPed
                        gunpointHoldStart = GetGameTimer()
                        if type(notify) == "function" and (GetGameTimer() - gunpointLastNotify) > 1500 then
                          notify("felony_hold", "Gunpoint Compliance", "Keep holding LEFT SHIFT while aiming to force surrender.", 'inform', 'gun', '#4299E1')
                          gunpointLastNotify = GetGameTimer()
                        end
                      elseif (GetGameTimer() - gunpointHoldStart) >= 3000 then
                        local result = commandPedSurrenderAtGunpoint(targetPed)
                        if result and result.ok then
                          if (result.resisted or 0) > 0 and (result.complied or 0) > 0 then
                            notify("felony_done", "Split Compliance", string.format("%d complied and %d chose to fight.", result.complied or 0, result.resisted or 0), 'warning', 'person-rays', '#DD6B20')
                          elseif (result.resisted or 0) > 0 then
                            notify("felony_done", "Resistance", "The suspect chose to fight instead of complying.", 'warning', 'person-rays', '#DD6B20')
                          elseif (result.total or 0) > 1 then
                            notify("felony_done", "Group Compliance", string.format("%d suspects complied at gunpoint.", result.complied or result.total or 0), 'success', 'person-rays', '#38A169')
                          else
                            notify("felony_done", "Compliance", "Suspect complied at gunpoint.", 'success', 'person-rays', '#38A169')
                          end
                          gunpointCooldown = GetGameTimer() + ((Config and Config.GunpointCompliance and Config.GunpointCompliance.cooldownMs) or 4500)
                        end
                        gunpointHoldStart, gunpointHoldTarget = 0, 0
                      end
                    else
                      gunpointHoldStart, gunpointHoldTarget = 0, 0
                    end
                  else
                    gunpointHoldStart, gunpointHoldTarget = 0, 0
                  end
                end
              end
            end)

            local function tryOpenPoliceMenu()
              if policeMenuBusy then return end
              policeMenuBusy = true
              getPlayerJobFromServer(function(job)
                policeMenuBusy = false
                if not isPoliceMenuJob(job) then return end
                if type(lib) ~= "table" or type(lib.showContext) ~= "function" then
                  return
                end
                if not ensurePoliceActionMenus() then
                  doNotify({ id = "police_menu_missing", title = "Police Actions", description = "The ox_lib police menu was not ready yet. Try again in a moment.", type = "error", duration = 5000 })
                  return
                end
                local ok, err = pcall(function() lib.showContext('police_mainai') end)
                if not ok then
                  policeActionMenusRegistered = false
                  if ensurePoliceActionMenus(true) then
                    ok = pcall(function() lib.showContext('police_mainai') end)
                  end
                end
                if not ok then
                  doNotify({ id = "police_menu_open_failed", title = "Police Actions", description = "Failed to open the ox_lib police menu.", type = "error", duration = 5000 })
                  dprint(("tryOpenPoliceMenu failed: %s"):format(tostring(err)))
                end
              end)
            end
            RegisterCommand('aipolicemenu', function()
              tryOpenPoliceMenu()
            end)
            RegisterKeyMapping('aipolicemenu','Open Police Actions','keyboard','F6')

            local function markTrafficStopVehicle()
              if not inEmergencyVehicle() then
                return notify("pull_err","Traffic Stop","You must be in an emergency vehicle.",'error','car','#E53E3E')
              end

              local best = findVehicleAhead(25, 0.45)
              if not best or not DoesEntityExist(best) then
                return notify("pull_err","Traffic Stop","No vehicle ahead to mark.",'error','car','#E53E3E')
              end

              pendingPullVeh = best
              pendingPullDeadline = GetGameTimer() + 30000
              pullVeh = best

              local plate = (GetVehicleNumberPlateText(best) or ""):match("%S+") or "UNKNOWN"
              pendingPullState = 'waiting_for_emergency_signal'
              notify("pull_marked","Traffic Stop Step 1",("Marked %s. Waiting for police lights / sirens. Once they turn on, the vehicle will slow down and pull right. Press G to cancel."):format(plate),'inform','siren-on','#4299E1')

              if not pendingPullMonitor then
                pendingPullMonitor = true
                Citizen.CreateThread(function()
                  while pendingPullVeh do
                    Citizen.Wait(40)
                    if not DoesEntityExist(pendingPullVeh) then
                      pendingPullVeh = nil
                      break
                    end
                    local player = PlayerPedId()
                    local myVeh = GetVehiclePedIsIn(player, false)
                    if not myVeh or myVeh == 0 or not inEmergencyVehicle() then
                      pendingPullVeh = nil
                      break
                    end
                    if GetGameTimer() > pendingPullDeadline then
                      pendingPullState = 'idle'
                      notify("pull_mark_expire","Marked Vehicle Lost","Marked vehicle timed out. Mark it again with LEFT SHIFT + E.",'warning','ban','#DD6B20')
                      pendingPullVeh = nil
                      break
                    end
                    if isPullOverSignalActive(myVeh) then
                      pendingPullState = 'initiating_stop'
                      local marked = pendingPullVeh
                      pendingPullVeh = nil
                      attemptPullOverAI(false, marked)
                      break
                    end
                  end
                  pendingPullMonitor = false
                end)
              end
            end

            RegisterCommand('stopAI', function()
              local inVeh = IsPedInAnyVehicle(PlayerPedId(), false)
              local holdingShift = IsControlPressed(0, 21) or IsDisabledControlPressed(0, 21)

              if not holdingShift then
                return notify("stop_require", "Hold Modifier", "Hold LEFT SHIFT and press E.", 'warning', 'ban', '#DD6B20')
              end

              if inVeh and type(inEmergencyVehicle) == 'function' and inEmergencyVehicle() then
                markTrafficStopVehicle()
                return
              end

              if type(attemptStopOnFoot) == 'function' then
                attemptStopOnFoot(false)
              end
            end)
            RegisterKeyMapping('stopAI', 'Mark traffic stop / initiate AI stop (LEFT SHIFT + E)', 'keyboard', 'E')

            RegisterCommand('cancelStopsCmd', function()
              cancelNonForcedStops()
            end)
            RegisterKeyMapping('cancelStopsCmd', 'Cancel stops (LEFT CTRL)', 'keyboard', 'LEFTCTRL')

            RegisterCommand('showid', function() if lastPedNetId then showIDSafely(lastPedNetId) else dprint("showid: no lastPedNetId") end end)
            RegisterKeyMapping('showid','Show Last Ped ID','keyboard','J')

            RegisterCommand('cancelMarkedTrafficStop', function()
              if pendingPullVeh and DoesEntityExist(pendingPullVeh) then
                pendingPullState = 'idle'
                pendingPullVeh = nil
                pendingPullDeadline = 0
                notify("pull_mark_cancel","Traffic Stop Canceled","Marked vehicle cleared.",'warning','ban','#DD6B20')
              end
            end)
            RegisterKeyMapping('cancelMarkedTrafficStop', 'Cancel marked traffic stop', 'keyboard', 'G')

            RegisterCommand('toggleNpcCuff', function()
              if pendingPullVeh then
                pendingPullVeh = nil
                pendingPullDeadline = 0
                notify("pull_mark_cancel","Traffic Stop Canceled","Marked vehicle cleared.",'warning','ban','#DD6B20')
              else
                dprint("toggleNpcCuff command -> tryCuffPed")
                tryCuffPed()
              end
            end)
            RegisterKeyMapping('toggleNpcCuff', 'Cuff / uncuff last stopped ped', 'keyboard', 'N')

            Citizen.CreateThread(function()
              while true do
                Citizen.Wait((Config.PedCustody and Config.PedCustody.cuffReapplyIntervalMs) or 250)
                local now = GetGameTimer()
                local processed = {}
                for pedKey, info in pairs(pedData) do
                  local canonical = tostring((info and info.cuffCanonicalKey) or pedKey)
                  if not processed[canonical] then
                    processed[canonical] = true
                    local ped, resolvedKey = resolveTrackedPedFromKey(canonical, pedData[canonical] or info)
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                      local cuffed = isPedActuallyCuffed(ped, resolvedKey or canonical)
                      local entry = pedData[tostring(canonical)] or pedData[tostring(resolvedKey or canonical)] or info
                      local recentlyUncuffedUntil = tonumber((entry and entry.recentlyUncuffedUntil) or 0) or 0
                      if cuffed and recentlyUncuffedUntil <= now then
                        cachePedReference(ped, resolvedKey or canonical)
                        enforceCuffedPedState(ped, tostring(resolvedKey or canonical), entry)
                      end
                    end
                  end
                end
              end
            end)

            function doSearch()
              dprint("doSearch called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("doSearch: no ped resolved")
                return notify("search_no","No Ped","None stopped.",'error','magnifying-glass','#E53E3E')
              end
              if not DoesEntityExist(ped) then
                dprint("doSearch: ped no longer exists")
                lastPedNetId = nil; lastPedEntity = nil
                return notify("search_no_exist","No Ped","Target no longer exists.",'error','magnifying-glass','#E53E3E')
              end

              local searchKey = tostring(tonumber(nid) or nid or safePedToNet(ped) or lastPedNetId or ped)
              local profile = pedData and pedData[searchKey] or nil
              local foundItems = {}
              local contrabandCatalog = {
                "Marijuana baggie",
                "Open alcohol container",
                "Small meth package",
                "Burglary tools",
                "Loose pills",
                "Stolen property receipt",
                "Unserialized handgun",
              }

              playSimpleConversationAnim(ped, "refuse")
              if math.random() < 0.15 then
                notify("search_fail","Interrupted","Search interrupted, but ped remains.",'error','person-running','#E53E3E')
                holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
                return
              end

              if profile and profile.hasIllegalItems then
                foundItems[#foundItems + 1] = contrabandCatalog[math.random(#contrabandCatalog)]
                if math.random() < 0.28 then
                  foundItems[#foundItems + 1] = contrabandCatalog[math.random(#contrabandCatalog)]
                end
              end

              if #foundItems > 0 then
                local summary = table.concat(foundItems, ', ')
                notify("search_hit","Search",summary,'success','magnifying-glass','#38A169')
                local sceneId = LocalPlayer and LocalPlayer.state and LocalPlayer.state.az5pdSceneId or nil
                if sceneId then
                  for i = 1, #foundItems do
                    TriggerServerEvent('az5pd:sim:addEvidence', sceneId, {
                      type = 'Contraband',
                      description = foundItems[i],
                      category = foundItems[i]
                    })
                  end
                end
              else
                notify("search_ok","Search","Nothing found.",'success','magnifying-glass','#38A169')
              end
              holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
            end

            function doCitation()
              dprint("doCitation called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("doCitation: no ped resolved")
                return notify("cite_no","No Ped","None stopped.",'error','ticket','#E53E3E')
              end

              local citationKey = tostring(tonumber(nid) or nid or safePedToNet(ped) or lastPedNetId or ped)
              lastPedNetId = citationKey
              lastPedEntity = ped

              local def = citationReasons[math.random(#citationReasons)]

              local dlg = nil
              if lib and lib.inputDialog then
                dprint("doCitation: using lib.inputDialog")
                dlg = lib.inputDialog("Issue Citation", {
                  { type='input',  label='Reason', default=def },
                  { type='number',label='Fine ($)',default=100,min=0 }
                })
              else
                dprint("doCitation: lib.inputDialog missing - using defaults")
                dlg = { def, 100 }
              end

              local function sendCitation(reason, fine)
                playSimpleConversationAnim(ped, "handoff")
                dprint("sendCitation:", tostring(citationKey), tostring(reason), tostring(fine))
                TriggerServerEvent('police:issueCitation',
                  citationKey, reason, fine, getPedName(citationKey))
                notify("cite_ok","Citation","Reason:"..reason.." Fine:$"..tostring(fine),'success','ticket-alt','#38A169')
                if DoesEntityExist(ped) then holdPedAttention(ped, IsPedInAnyVehicle(ped, false)) end
              end

              if dlg and type(dlg.andThen) == 'function' then
                dlg:andThen(function(res)
                  if not res or not res[1] or not res[2] then
                    dprint("doCitation: inputDialog canceled/no data")
                    return notify("cite_cancel","Canceled","No data.",'warning','ban','#DD6B20')
                  end
                  sendCitation(res[1], res[2])
                end)
              elseif type(dlg) == 'table' and dlg[1] and dlg[2] then
                sendCitation(dlg[1], dlg[2])
              else
                sendCitation(def, 100)
              end
            end


            function duiRound(value, places)
              local mult = 10 ^ (places or 0)
              return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
            end

            function duiClamp(value, minVal, maxVal)
              value = tonumber(value) or 0.0
              if value < minVal then return minVal end
              if value > maxVal then return maxVal end
              return value
            end

            function duiRandomFloat(minVal, maxVal)
              minVal = tonumber(minVal) or 0.0
              maxVal = tonumber(maxVal) or minVal
              if maxVal < minVal then minVal, maxVal = maxVal, minVal end
              return minVal + (math.random() * (maxVal - minVal))
            end

            function duiShuffle(list)
              local arr = {}
              for i = 1, #list do arr[i] = list[i] end
              for i = #arr, 2, -1 do
                local j = math.random(i)
                arr[i], arr[j] = arr[j], arr[i]
              end
              return arr
            end

            function duiPick(list, count)
              local chosen, out = duiShuffle(list), {}
              count = math.max(0, math.min(#chosen, tonumber(count) or 0))
              for i = 1, count do out[#out + 1] = chosen[i] end
              return out
            end

            function duiJoinLines(items, prefix)
              local lines = {}
              prefix = prefix or '- '
              for i = 1, #items do
                lines[#lines + 1] = prefix .. tostring(items[i])
              end
              return table.concat(lines, '\n')
            end

            function duiGetTargetPed(requireExisting)
              local ped, nid = resolveLastPed()
              if not ped then
                notify('dui_no_ped', 'No Ped', 'Stop or select a subject first.', 'error', 'wine-bottle', '#E53E3E')
                return nil
              end
              if not DoesEntityExist(ped) or IsPedAPlayer(ped) then
                notify('dui_bad_ped', 'Invalid Subject', 'Target no longer exists or is player-controlled.', 'error', 'ban', '#E53E3E')
                return nil
              end
              local pedKey = tostring(tonumber(nid) or nid or safePedToNet(ped) or lastPedNetId or ped)
              lastPedNetId = pedKey
              lastPedEntity = ped
              local info = ensurePerson(pedKey) or {}
              if enrichPedImmersionProfile then
                info = enrichPedImmersionProfile(ped, info) or info
                pedData[pedKey] = info
              end
              if requireExisting and not pedData[pedKey] then
                notify('dui_missing_subject', 'No Subject', 'Could not establish subject state for testing.', 'error', 'triangle-exclamation', '#E53E3E')
                return nil
              end
              return ped, pedKey, info
            end

            function duiNow()
              local cloud = type(GetCloudTimeAsInt) == 'function' and GetCloudTimeAsInt() or 0
              if type(cloud) == 'number' and cloud > 0 then return cloud end
              return math.floor(GetGameTimer() / 1000)
            end

            function duiGetCase(info)
              info.duiCase = info.duiCase or {
                createdAt = duiNow(),
                observations = nil,
                notes = {},
                tests = {},
                impliedConsentRead = false,
                lastSummaryAt = nil,
              }
              return info.duiCase
            end

            function duiGetProfile(ped, pedKey, info)
              info = info or ensurePerson(pedKey) or {}
              if info.duiProfile and info.duiProfile.generated then return info.duiProfile end

              local drugCatalog = {
                {
                  name = 'THC',
                  observation = {'odor of marijuana on clothing', 'bloodshot eyes', 'slow deliberate speech'},
                  eye = {'lack of smooth pursuit', 'eyelid tremors', 'slowed pupil reaction'},
                  result = 'Positive for THC'
                },
                {
                  name = 'Methamphetamine',
                  observation = {'rapid speech', 'jaw tension', 'restless body movement'},
                  eye = {'dilated pupils', 'rapid eye movement', 'overly alert gaze'},
                  result = 'Positive for amphetamine / methamphetamine'
                },
                {
                  name = 'Cocaine',
                  observation = {'fast speech', 'clenched jaw', 'sweaty restless presentation'},
                  eye = {'dilated pupils', 'rapid eye movement', 'difficulty focusing'},
                  result = 'Positive for cocaine metabolite'
                },
                {
                  name = 'Opiates',
                  observation = {'droopy eyelids', 'slow sluggish responses', 'drowsy posture'},
                  eye = {'pinpoint pupils', 'slow eye reaction', 'difficulty maintaining attention'},
                  result = 'Positive for opiates'
                },
                {
                  name = 'Benzodiazepines',
                  observation = {'slowed speech', 'poor coordination', 'delayed responses'},
                  eye = {'poor convergence', 'slow tracking', 'drooping eyelids'},
                  result = 'Positive for benzodiazepines'
                }
              }

              local isDrunk = info.isDrunk == true
              local isHigh = info.isHigh == true
              local nervous = info.nervous == true
              local suspicious = info.suspicious == true
              local medicalIssue = (math.random() < (((isDrunk or isHigh) and 0.08) or 0.12))
              local alcoholLevel = 0.0
              if isDrunk then
                alcoholLevel = duiRandomFloat(0.078, 0.168)
                if math.random() < 0.25 then alcoholLevel = duiRandomFloat(0.170, 0.220) end
              elseif isHigh then
                alcoholLevel = duiRandomFloat(0.000, 0.030)
              elseif suspicious then
                alcoholLevel = duiRandomFloat(0.000, 0.050)
              else
                alcoholLevel = duiRandomFloat(0.000, 0.025)
              end
              alcoholLevel = duiClamp(alcoholLevel, 0.0, 0.240)

              local drugEntry = nil
              if isHigh then drugEntry = drugCatalog[math.random(#drugCatalog)] end

              local refusalChance = 0.08
              if isDrunk then refusalChance = refusalChance + 0.16 end
              if isHigh then refusalChance = refusalChance + 0.18 end
              if info.wanted then refusalChance = refusalChance + 0.08 end
              if info.hasIllegalItems then refusalChance = refusalChance + 0.06 end
              if nervous then refusalChance = refusalChance + 0.04 end
              refusalChance = duiClamp(refusalChance, 0.05, 0.82)

              local odor = isDrunk and ({'strong odor of alcoholic beverage', 'moderate odor of alcohol', 'fresh beer odor'})[math.random(3)] or ((drugEntry and drugEntry.name == 'THC') and 'odor of marijuana present' or 'no obvious alcohol odor')
              local speech = isDrunk and ({'slurred speech', 'thick-tongued answers', 'slow delayed responses'})[math.random(3)]
                or (drugEntry and ({'rambling inconsistent answers', 'slow confused responses', 'overly fast pressured speech'})[math.random(3)])
                or (nervous and 'noticeably nervous speech' or 'normal speech pattern')
              local balance = (isDrunk or isHigh) and ({'noticeable sway while standing', 'uses arms for balance', 'unsteady stance'})[math.random(3)]
                or (medicalIssue and 'favors one leg / possible prior injury' or 'steady balance at rest')
              local eyes = isDrunk and ({'bloodshot watery eyes', 'glassy eyes', 'difficulty holding steady gaze'})[math.random(3)]
                or (drugEntry and drugEntry.eye[math.random(#drugEntry.eye)])
                or 'eyes appear normal'

              local profile = {
                generated = true,
                alcoholLevel = alcoholLevel,
                roadsideBrAC = duiClamp(alcoholLevel + duiRandomFloat(-0.008, 0.008), 0.0, 0.240),
                evidentialBAC = duiClamp(alcoholLevel + duiRandomFloat(-0.004, 0.004), 0.0, 0.240),
                drugEntry = drugEntry,
                refusalChance = refusalChance,
                nervous = nervous,
                medicalIssue = medicalIssue,
                suspicious = suspicious,
                odor = odor,
                speech = speech,
                balance = balance,
                eyes = eyes,
                openContainer = isDrunk and math.random() < 0.28,
                admission = isDrunk and ({'admits to having a couple drinks', 'admits to drinking earlier tonight', 'initially denies drinking, then changes story'})[math.random(3)]
                  or (isHigh and ({'admits to smoking earlier', 'admits to taking medication before driving', 'denies use despite impairment clues'})[math.random(3)] or 'denies alcohol or drug use'),
              }
              info.duiProfile = profile
              pedData[pedKey] = info
              return profile
            end

            function duiSaveRecord(pedKey, info, title, description, rtype)
              if not pedKey then return end
              local targetValue = tostring((info and info.name) or ''):gsub('^%s+', ''):gsub('%s+$', '')
              local targetType = 'name'
              if targetValue == '' then
                targetType = 'netId'
                targetValue = tostring(pedKey)
              end
              TriggerServerEvent('mdt:createRecord', {
                target_type = targetType,
                target_value = targetValue,
                rtype = rtype or 'dui',
                title = tostring(title or 'DUI Investigation'),
                description = tostring(description or ''),
              })
            end

            function duiMakeSummaryHeader(info, profile)
              local name = tostring((info and info.name) or 'Unknown Subject')
              local lines = {
                ('Subject: %s'):format(name),
                ('Alcohol profile: %.3f BAC'):format(tonumber((profile and profile.evidentialBAC) or 0.0) or 0.0),
                ('Drug indicator baseline: %s'):format((profile and profile.drugEntry and profile.drugEntry.name) or 'None observed'),
              }
              return table.concat(lines, '\n')
            end

            function duiChemicalRefusal(info, profile, kind)
              local roll = math.random()
              local chance = tonumber((profile and profile.refusalChance) or 0.08) or 0.08
              local duiCase = duiGetCase(info)
              if kind == 'bac' or kind == 'drug' then chance = chance + 0.10 end
              if duiCase and duiCase.refusalCount then chance = chance + (0.08 * duiCase.refusalCount) end
              return roll < duiClamp(chance, 0.05, 0.92)
            end

            function duiRequireOnFootAndUncuffed(ped, info, label)
              if IsPedInAnyVehicle(ped, false) then
                notify('dui_vehicle_required_exit', label or 'Field Sobriety Test', 'Have the subject exit the vehicle before running this test.', 'warning', 'car-side', '#DD6B20')
                return false
              end
              if info and info.cuffed then
                notify('dui_uncuff_required', label or 'Field Sobriety Test', 'Uncuff the subject before running a balancing / movement test.', 'warning', 'unlock', '#DD6B20')
                return false
              end
              return true
            end

            function duiRunProgress(label, duration, animMode)
              local player = PlayerPedId()
              if animMode == 'note' and loadAnimDictTimed('missheistdockssetup1clipboard@base', 1200) then
                TaskPlayAnim(player, 'missheistdockssetup1clipboard@base', 'base', 3.0, -3.0, duration + 200, 49, 0.0, false, false, false)
              end
              local ok = safeProgressBar({
                duration = duration,
                label = label,
                canCancel = true,
                disable = { car = true, move = true, combat = true, mouse = false }
              })
              ClearPedTasks(player)
              return ok
            end


            DUI_IMPAIRED_CLIPSETS = {
              slight = 'MOVE_M@DRUNK@SLIGHTLYDRUNK',
              moderate = 'MOVE_M@DRUNK@MODERATEDRUNK',
              heavy = 'MOVE_M@DRUNK@VERYDRUNK',
            }

            function duiResetMovementVisual(ped)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              ResetPedMovementClipset(ped, 0.25)
            end

            function duiApplyImpairedMovementVisual(ped, profile, result)
              if not ped or ped == 0 or not DoesEntityExist(ped) or IsPedInAnyVehicle(ped, false) then return false end
              local status = result and tostring(result.status or '') or ''
              local clip = nil
              if status == 'FAIL' or status == 'POSITIVE' then
                if profile and ((tonumber(profile.alcoholLevel) or 0.0) >= 0.14 or profile.alcoholHeavy) then
                  clip = DUI_IMPAIRED_CLIPSETS.heavy
                else
                  clip = DUI_IMPAIRED_CLIPSETS.moderate
                end
              elseif status == 'WARN' or status == 'PARTIAL' then
                clip = DUI_IMPAIRED_CLIPSETS.slight
              end
              if clip and loadAnimSetTimed and loadAnimSetTimed(clip, 1200) then
                SetPedMovementClipset(ped, clip, 0.25)
                return true
              end
              return false
            end

            function duiPlayOfficerAnimForTest(kind, duration)
              local player = PlayerPedId()
              duration = tonumber(duration) or 3500
              if kind == 'breathalyzer' or kind == 'drug' then
                if loadAnimDictTimed('mp_common', 1200) then
                  TaskPlayAnim(player, 'mp_common', 'givetake1_a', 4.0, -4.0, duration, 49, 0.0, false, false, false)
                  return true
                end
              end
              if kind == 'bac' or kind == 'observations' then
                if loadAnimDictTimed('missheistdockssetup1clipboard@base', 1200) then
                  TaskPlayAnim(player, 'missheistdockssetup1clipboard@base', 'base', 3.0, -3.0, duration, 49, 0.0, false, false, false)
                  return true
                end
              end
              return false
            end

            function duiPlaySubjectChemicalVisual(kind, ped, duration)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              duration = tonumber(duration) or 4000
              if IsPedInAnyVehicle(ped, false) then
                TaskTurnPedToFaceEntity(ped, PlayerPedId(), 900)
                TaskLookAtEntity(ped, PlayerPedId(), duration, 2048, 3)
                return
              end
              ClearPedTasks(ped)
              TaskTurnPedToFaceEntity(ped, PlayerPedId(), 900)
              TaskLookAtEntity(ped, PlayerPedId(), duration, 2048, 3)
              if kind == 'breathalyzer' or kind == 'drug' then
                if loadAnimDictTimed('mp_common', 1200) then
                  TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 4.0, -4.0, math.floor(duration * 0.8), 49, 0.0, false, false, false)
                  return
                end
              end
              TaskStandStill(ped, duration)
            end

            function duiHeadingForward(heading)
              local hr = math.rad(tonumber(heading) or 0.0)
              return -math.sin(hr), math.cos(hr)
            end

            function duiGetSpotNearOfficer(preferRoadNode)
              local player = PlayerPedId()
              local ox, oy, oz = table.unpack(GetOffsetFromEntityInWorldCoords(player, 1.2, 3.0, 0.0))
              local spot = vector3(ox, oy, oz)
              local heading = GetEntityHeading(player)
              if preferRoadNode then
                local nodePos, nodeHeading, ok = getClosestVehicleNodePosHeading(ox, oy, oz, 1, 3.0, 0)
                if ok and nodePos then
                  spot = vector3(nodePos.x, nodePos.y, nodePos.z)
                  heading = tonumber(nodeHeading) or heading
                end
              end
              local okGround, gz = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 3.0, false)
              if okGround then spot = vector3(spot.x, spot.y, gz + 0.03) end
              return spot, heading
            end

            function duiAwaitPedNear(ped, target, tolerance, timeoutMs)
              local started = GetGameTimer()
              tolerance = tonumber(tolerance) or 1.2
              timeoutMs = tonumber(timeoutMs) or 7000
              while DoesEntityExist(ped) and (GetGameTimer() - started) < timeoutMs do
                local pcoords = GetEntityCoords(ped)
                local dist = #(pcoords - target)
                if dist <= tolerance then return true end
                if IsPedInAnyVehicle(ped, false) then return false end
                Citizen.Wait(100)
              end
              return false
            end

            function duiMovePedToSpot(ped, spot, heading, timeoutMs, allowWarp)
              if not ped or ped == 0 or not DoesEntityExist(ped) or not spot then return false end
              NetworkRequestControlOfEntity(ped)
              SetEntityAsMissionEntity(ped, true, true)
              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedKeepTask(ped, true)
              TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, tonumber(timeoutMs) or 7000, tonumber(heading) or GetEntityHeading(ped), 0.2)
              local reached = duiAwaitPedNear(ped, spot, 1.35, timeoutMs)
              if (not reached) and allowWarp and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
                SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
                reached = true
              end
              if reached and DoesEntityExist(ped) then
                ClearPedTasks(ped)
                SetEntityHeading(ped, tonumber(heading) or GetEntityHeading(ped))
                TaskStandStill(ped, 1500)
              end
              return reached
            end

            function duiEnsureSubjectOnFoot(ped, pedKey)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              if not IsPedInAnyVehicle(ped, false) then return true end
              local info = pedData[pedKey] or {}
              info.allowVehicleExitUntil = GetGameTimer() + 6000
              info.preventVehicleReseatUntil = GetGameTimer() + 10000
              pedData[pedKey] = info
              local veh = GetVehiclePedIsIn(ped, false)
              if veh and veh ~= 0 and DoesEntityExist(veh) then
                NetworkRequestControlOfEntity(veh)
                SetVehicleDoorsLocked(veh, 1)
              end
              if not forcePedExitVehicle(ped, veh) then
                ClearPedTasksImmediately(ped)
                TaskLeaveVehicle(ped, veh or 0, 0)
                Citizen.Wait(1200)
              end
              local started = GetGameTimer()
              while DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) and (GetGameTimer() - started) < 4500 do
                Citizen.Wait(100)
              end
              return DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false)
            end

            function duiPrepareFieldSubject(ped, pedKey, info, label)
              if not duiRequireOnFootAndUncuffed(ped, info, label) then return nil end
              if not duiEnsureSubjectOnFoot(ped, pedKey) then
                notify('dui_exit_fail_' .. tostring(label), label or 'Field Test', 'Could not get the subject out of the vehicle for the field test.', 'error', 'triangle-exclamation', '#E53E3E')
                return nil
              end
              local spot, heading = duiGetSpotNearOfficer(true)
              if not duiMovePedToSpot(ped, spot, heading, 7000, true) then
                notify('dui_move_fail_' .. tostring(label), label or 'Field Test', 'Could not position the subject for the field test.', 'error', 'triangle-exclamation', '#E53E3E')
                return nil
              end
              TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1500)
              TaskStandStill(ped, 2000)
              return { spot = spot, heading = heading }
            end

            function duiPerformMovementTestVisual(ped, prep, kind, result, profile)
              if not ped or ped == 0 or not DoesEntityExist(ped) or not prep or not prep.spot then return false end
              local speed = 1.0
              local status = result and tostring(result.status or '') or ''
              if status == 'FAIL' or status == 'WARN' or status == 'PARTIAL' then speed = 0.72 end
              local usedClip = duiApplyImpairedMovementVisual(ped, profile, result)
              local distance = (kind == 'walk_turn') and 6.0 or 4.0
              local dx, dy = duiHeadingForward(prep.heading)
              local outPos = vector3(prep.spot.x + dx * distance, prep.spot.y + dy * distance, prep.spot.z)
              ClearPedTasksImmediately(ped)
              TaskGoStraightToCoord(ped, outPos.x, outPos.y, outPos.z, speed, 7000, prep.heading, 0.1)
              local reachedOut = duiAwaitPedNear(ped, outPos, 1.35, 7000)
              if kind == 'walk_turn' and reachedOut and DoesEntityExist(ped) then
                ClearPedTasks(ped)
                SetEntityHeading(ped, (prep.heading + 180.0) % 360.0)
                Citizen.Wait(700)
                TaskGoStraightToCoord(ped, prep.spot.x, prep.spot.y, prep.spot.z, speed, 7000, (prep.heading + 180.0) % 360.0, 0.1)
                duiAwaitPedNear(ped, prep.spot, 1.35, 7000)
              end
              if DoesEntityExist(ped) then
                ClearPedTasks(ped)
                SetEntityHeading(ped, prep.heading)
                TaskStandStill(ped, 1500)
                if usedClip then
                  Citizen.Wait(250)
                  duiResetMovementVisual(ped)
                end
              end
              return true
            end

            function duiPerformStationaryTestVisual(ped, prep, kind, durationMs, result, profile)
              if not ped or ped == 0 or not DoesEntityExist(ped) or not prep then return false end
              local usedClip = duiApplyImpairedMovementVisual(ped, profile, result)
              ClearPedTasks(ped)
              SetEntityHeading(ped, prep.heading)
              TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1000)
              if kind == 'one_leg' and loadAnimDictTimed('amb@world_human_stand_impatient@male@no_sign@base', 1200) then
                TaskPlayAnim(ped, 'amb@world_human_stand_impatient@male@no_sign@base', 'base', 4.0, -4.0, tonumber(durationMs) or 5000, 49, 0.0, false, false, false)
              elseif kind == 'hgn' then
                TaskLookAtEntity(ped, PlayerPedId(), tonumber(durationMs) or 5000, 2048, 3)
                TaskStandStill(ped, tonumber(durationMs) or 5000)
              else
                TaskStandStill(ped, tonumber(durationMs) or 5000)
              end
              Citizen.Wait(math.min(tonumber(durationMs) or 5000, 2500))
              if usedClip then duiResetMovementVisual(ped) end
              return true
            end

            function duiPrepareChemicalSubject(ped, pedKey)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              local player = PlayerPedId()
              NetworkRequestControlOfEntity(ped)
              SetEntityAsMissionEntity(ped, true, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedKeepTask(ped, true)
              if IsPedInAnyVehicle(ped, false) then
                local info = pedData[pedKey] or {}
                info.allowVehicleExitUntil = GetGameTimer() + 3000
                pedData[pedKey] = info
                holdPedAttention(ped, true)
                TaskTurnPedToFaceEntity(ped, player, 1000)
                TaskLookAtEntity(ped, player, 3500, 2048, 3)
                return true
              end
              ClearPedTasksImmediately(ped)
              local playerCoords = GetEntityCoords(player)
              local pedCoords = GetEntityCoords(ped)
              local dist = #(pedCoords - playerCoords)
              if dist > 3.0 then
                local spot, heading = duiGetSpotNearOfficer(false)
                if not duiMovePedToSpot(ped, spot, heading, 5000, true) then
                  local fx, fy, fz = table.unpack(GetOffsetFromEntityInWorldCoords(player, 0.65, 1.35, 0.0))
                  local fallback = vector3(fx, fy, fz)
                  local okGround, gz = GetGroundZFor_3dCoord(fallback.x, fallback.y, fallback.z + 3.0, false)
                  if okGround then fallback = vector3(fallback.x, fallback.y, gz + 0.03) end
                  SetEntityCoordsNoOffset(ped, fallback.x, fallback.y, fallback.z, false, false, false)
                  SetEntityHeading(ped, (GetEntityHeading(player) + 180.0) % 360.0)
                end
              else
                TaskTurnPedToFaceEntity(ped, player, 1200)
              end
              TaskLookAtEntity(ped, player, 2500, 2048, 3)
              TaskStandStill(ped, 2500)
              return true
            end

            function duiApplyPostTestControl(ped, pedKey)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local info = pedData[pedKey] or nil
              if info and shouldKeepPedSeated(info) then
                enforcePedRemainSeated(ped, pedKey)
                return
              end
              holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
            end

            function duiUniqueAppend(target, values)
              local seen = {}
              for i = 1, #target do seen[target[i]] = true end
              for i = 1, #values do
                local value = tostring(values[i])
                if not seen[value] then
                  target[#target + 1] = value
                  seen[value] = true
                end
              end
            end

            function duiBuildObservationList(info, profile)
              local observations = {}
              observations[#observations + 1] = profile.odor
              observations[#observations + 1] = profile.speech
              observations[#observations + 1] = profile.eyes
              observations[#observations + 1] = profile.balance
              observations[#observations + 1] = profile.admission
              if profile.openContainer then observations[#observations + 1] = 'open container indicators present in vehicle area' end
              if profile.drugEntry and profile.drugEntry.observation then
                duiUniqueAppend(observations, duiPick(profile.drugEntry.observation, math.random(1, math.min(2, #profile.drugEntry.observation))))
              end
              if profile.medicalIssue then observations[#observations + 1] = 'subject mentions a possible prior injury that could affect balance' end
              return observations
            end

            function duiFieldClueCount(profile, kind)
              local count = 0
              local alcohol = tonumber(profile.alcoholLevel or 0.0) or 0.0
              if kind == 'hgn' then
                if alcohol >= 0.08 then count = count + math.random(4, 6)
                elseif alcohol >= 0.05 then count = count + math.random(2, 4)
                elseif alcohol >= 0.03 then count = count + math.random(1, 2)
                end
                if profile.drugEntry and (profile.drugEntry.name == 'Methamphetamine' or profile.drugEntry.name == 'Cocaine' or profile.drugEntry.name == 'Benzodiazepines') then
                  count = count + math.random(1, 2)
                end
                if count == 0 and profile.nervous and math.random() < 0.20 then count = 1 end
                return math.min(count, 6)
              end

              if alcohol >= 0.12 then count = count + math.random(3, 4)
              elseif alcohol >= 0.08 then count = count + math.random(2, 3)
              elseif alcohol >= 0.05 then count = count + math.random(1, 2)
              elseif alcohol > 0.0 and math.random() < 0.25 then count = 1 end
              if profile.drugEntry then count = count + math.random(1, 2) end
              if profile.medicalIssue and math.random() < 0.70 then count = count + 1 end
              if profile.nervous and count == 0 and math.random() < 0.40 then count = 1 end
              if kind == 'one_leg' then return math.min(count, 4) end
              if kind == 'line_walk' then return math.min(count, 5) end
              return math.min(count, 8)
            end

            function duiEvaluateFieldTest(kind, profile)
              local pools = {
                walk_turn = {
                  'starts before instructions are finished',
                  'misses heel-to-toe on multiple steps',
                  'steps off the line',
                  'uses arms for balance',
                  'makes an improper turn',
                  'takes the wrong number of steps',
                  'stops while walking',
                  'cannot maintain starting position',
                },
                line_walk = {
                  'drifts off the line',
                  'looks down constantly to keep balance',
                  'stumbles during straight-line walk',
                  'uses arms to steady self',
                  'takes uneven short steps',
                },
                one_leg = {
                  'puts foot down early',
                  'sways while balancing',
                  'uses arms for balance',
                  'hops to maintain balance',
                },
                hgn = {
                  'lack of smooth pursuit observed',
                  'distinct nystagmus at maximum deviation',
                  'onset of nystagmus prior to 45 degrees',
                  'poor convergence noted',
                  'unequal tracking between eyes',
                  'delayed pupil response observed',
                }
              }
              local thresholds = {
                walk_turn = { fail = 2, partial = 1, max = 8 },
                line_walk = { fail = 2, partial = 1, max = 5 },
                one_leg = { fail = 2, partial = 1, max = 4 },
                hgn = { fail = 4, partial = 2, max = 6 },
              }
              local labelMap = {
                walk_turn = 'Walk-and-Turn',
                line_walk = 'Line Walk',
                one_leg = 'One-Leg Stand',
                hgn = 'Eye Test / HGN',
              }
              local count = duiFieldClueCount(profile, kind)
              local cfg = thresholds[kind] or thresholds.walk_turn
              local clues = duiPick(pools[kind] or pools.walk_turn, count)
              local status = 'PASS'
              if count >= cfg.fail then status = 'FAIL'
              elseif count >= cfg.partial then status = 'PARTIAL' end
              local summary = string.format('%s: %s (%d clue%s)', labelMap[kind] or kind, status, count, count == 1 and '' or 's')
              if profile.medicalIssue and count > 0 then
                summary = summary .. '. Subject also reports a possible balance-affecting injury.'
              end
              return {
                kind = kind,
                status = status,
                clueCount = count,
                clues = clues,
                summary = summary,
                label = labelMap[kind] or kind,
              }
            end

            function duiEvaluateChemicalTest(kind, profile)
              if kind == 'drug' then
                if profile.drugEntry then
                  return {
                    kind = kind,
                    status = 'POSITIVE',
                    value = profile.drugEntry.name,
                    summary = ('Drug Test: POSITIVE (%s)'):format(profile.drugEntry.result),
                    label = 'Drug Test',
                    detailLines = {
                      profile.drugEntry.result,
                      'Roadside oral fluid result is presumptive only and should be confirmed by lab if needed.'
                    }
                  }
                end
                return {
                  kind = kind,
                  status = 'NEGATIVE',
                  value = 'Negative',
                  summary = 'Drug Test: NEGATIVE',
                  label = 'Drug Test',
                  detailLines = { 'No common roadside drug indicator registered on the screen.' }
                }
              end

              local value = tonumber((kind == 'breathalyzer' and profile.roadsideBrAC) or profile.evidentialBAC or 0.0) or 0.0
              value = duiClamp(value, 0.0, 0.240)
              local status = 'PASS'
              if value >= 0.08 then status = 'FAIL'
              elseif value >= 0.05 then status = 'WARN' end
              local label = (kind == 'breathalyzer') and 'Breathalyzer (PBT)' or 'BAC Test'
              local summary = string.format('%s: %s (%.3f BAC)', label, status, value)
              local detail = {}
              if value >= 0.08 then
                detail[#detail + 1] = 'Result is above the common per se alcohol limit.'
              elseif value >= 0.05 then
                detail[#detail + 1] = 'Alcohol detected below common per se limit but still relevant for impairment.'
              else
                detail[#detail + 1] = 'Low / no measurable alcohol detected.'
              end
              if profile.drugEntry and value < 0.08 then
                detail[#detail + 1] = 'Observed impairment may be better explained by drug indicators than alcohol level alone.'
              end
              return {
                kind = kind,
                status = status,
                value = duiRound(value, 3),
                summary = summary,
                label = label,
                detailLines = detail,
              }
            end

            function duiProbableCause(caseData)
              local points = 0
              local reasons = {}
              if caseData and caseData.observations and #caseData.observations > 0 then
                points = points + 1
                reasons[#reasons + 1] = 'objective roadside observations documented'
              end
              if caseData and caseData.tests then
                for kind, result in pairs(caseData.tests) do
                  if result and (result.status == 'FAIL' or result.status == 'POSITIVE') then
                    points = points + 2
                    reasons[#reasons + 1] = tostring(result.label or kind) .. ' indicated impairment'
                  elseif result and (result.status == 'WARN' or result.status == 'PARTIAL') then
                    points = points + 1
                    reasons[#reasons + 1] = tostring(result.label or kind) .. ' showed concerning clues'
                  elseif result and result.status == 'REFUSED' then
                    points = points + 2
                    reasons[#reasons + 1] = tostring(result.label or kind) .. ' was refused'
                  end
                end
              end
              return points >= 3, reasons, points
            end

            function doDuiObservations()
              local ped, pedKey, info = duiGetTargetPed(true)
              if not ped then return end
              local profile = duiGetProfile(ped, pedKey, info)
              local duiCase = duiGetCase(info)
              local inVehicle = IsPedInAnyVehicle(ped, false)
              if inVehicle then
                holdPedAttention(ped, true)
                notify('dui_obs_vehicle', 'Roadside Observations', 'Observing the subject from the driver window / roadside position.', 'inform', 'car-side', '#4299E1')
              else
                local prep = duiPrepareFieldSubject(ped, pedKey, info, 'Roadside Observations')
                if not prep then return end
              end
              duiPlayOfficerAnimForTest('observations', 4500)
              if not duiRunProgress('Documenting roadside observations', 4500, 'note') then
                return notify('dui_obs_cancel', 'Canceled', 'Roadside observation check canceled.', 'warning', 'ban', '#DD6B20')
              end
              local observations = duiBuildObservationList(info, profile)
              duiCase.observations = observations
              duiCase.notes[#duiCase.notes + 1] = 'Initial observations completed.'
              local summary = table.concat(observations, ' • ')
              notify('dui_obs_done', 'Roadside Observations', summary, 'inform', 'eye', '#4299E1')
              duiSaveRecord(pedKey, info, 'Roadside Observations', duiJoinLines(observations), 'dui_observation')
              duiApplyPostTestControl(ped, pedKey)
            end

            function doDuiTest(kind)
              local ped, pedKey, info = duiGetTargetPed(true)
              if not ped then return end
              local profile = duiGetProfile(ped, pedKey, info)
              local duiCase = duiGetCase(info)
              local labels = {
                walk_turn = 'Walk-and-Turn',
                line_walk = 'Line Walk',
                one_leg = 'One-Leg Stand',
                hgn = 'Eye Test / HGN',
                breathalyzer = 'Breathalyzer (PBT)',
                bac = 'BAC Test',
                drug = 'Drug Test',
              }
              local durations = {
                walk_turn = 6500,
                line_walk = 5000,
                one_leg = 5500,
                hgn = 4500,
                breathalyzer = 4200,
                bac = 6000,
                drug = 6500,
              }
              local label = labels[kind] or tostring(kind)
              local fieldTest = (kind == 'walk_turn' or kind == 'line_walk' or kind == 'one_leg' or kind == 'hgn')
              local chemical = (kind == 'breathalyzer' or kind == 'bac' or kind == 'drug')
              local prep = nil
              local result = nil

              if fieldTest then
                prep = duiPrepareFieldSubject(ped, pedKey, info, label)
                if not prep then return end
                local instructionText = {
                  walk_turn = 'Subject is being positioned for a walk-and-turn test.',
                  line_walk = 'Subject is being positioned for a straight-line walk test.',
                  one_leg = 'Subject is being positioned for a one-leg stand.',
                  hgn = 'Subject is being positioned for the eye tracking test.',
                }
                notify('dui_instr_' .. tostring(kind), label, instructionText[kind] or 'Subject positioned for testing.', 'inform', 'person-walking', '#4299E1')
              elseif chemical then
                if not duiPrepareChemicalSubject(ped, pedKey) then
                  return notify('dui_chem_prep_fail_' .. tostring(kind), label, 'Could not position the subject for this chemical test.', 'error', 'triangle-exclamation', '#E53E3E')
                end
              end

              if chemical and not duiCase.impliedConsentRead then
                duiCase.impliedConsentRead = true
                duiCase.notes[#duiCase.notes + 1] = 'Implied consent warning read before chemical testing.'
                notify('dui_consent_read', 'Implied Consent', 'You advised the subject that refusing a chemical test may be used against them.', 'inform', 'book', '#4299E1')
                Citizen.Wait(300)
              end

              if chemical and duiChemicalRefusal(info, profile, kind) then
                duiCase.refusalCount = (duiCase.refusalCount or 0) + 1
                local refusal = {
                  kind = kind,
                  label = label,
                  status = 'REFUSED',
                  summary = label .. ': REFUSED',
                  detailLines = { 'Subject verbally refused the requested chemical test.' }
                }
                duiCase.tests[kind] = refusal
                playSimpleConversationAnim(ped, 'refuse')
                notify('dui_refused_' .. kind, label, 'Subject refused the test.', 'warning', 'triangle-exclamation', '#DD6B20')
                duiSaveRecord(pedKey, info, label .. ' Refusal', 'Subject refused the requested test after being advised.', 'dui_refusal')
                duiApplyPostTestControl(ped, pedKey)
                return
              end

              if fieldTest then
                result = duiEvaluateFieldTest(kind, profile)
                if kind == 'walk_turn' or kind == 'line_walk' then
                  duiPerformMovementTestVisual(ped, prep, kind, result, profile)
                elseif kind == 'one_leg' then
                  duiPerformStationaryTestVisual(ped, prep, kind, durations[kind] or 5500, result, profile)
                elseif kind == 'hgn' then
                  duiPerformStationaryTestVisual(ped, prep, kind, durations[kind] or 4500, result, profile)
                end
              else
                result = duiEvaluateChemicalTest(kind, profile)
                duiPlayOfficerAnimForTest(kind, durations[kind] or 4500)
                duiPlaySubjectChemicalVisual(kind, ped, (durations[kind] or 4500) + 600)
              end

              if not duiRunProgress('Running ' .. label, durations[kind] or 4500, nil) then
                duiApplyPostTestControl(ped, pedKey)
                return notify('dui_test_cancel_' .. tostring(kind), 'Canceled', label .. ' canceled.', 'warning', 'ban', '#DD6B20')
              end
              duiCase.tests[kind] = result
              duiCase.notes[#duiCase.notes + 1] = result.summary

              local descriptionLines = { result.summary }
              if result.clues and #result.clues > 0 then
                for i = 1, #result.clues do descriptionLines[#descriptionLines + 1] = '- ' .. tostring(result.clues[i]) end
              end
              if result.detailLines and #result.detailLines > 0 then
                for i = 1, #result.detailLines do descriptionLines[#descriptionLines + 1] = '- ' .. tostring(result.detailLines[i]) end
              end

              notify('dui_result_' .. tostring(kind), label, result.summary, (result.status == 'FAIL' or result.status == 'POSITIVE') and 'error' or ((result.status == 'WARN' or result.status == 'PARTIAL') and 'warning' or 'success'), chemical and 'vial-circle-check' or 'clipboard-check', (result.status == 'FAIL' or result.status == 'POSITIVE') and '#E53E3E' or '#38A169')
              duiSaveRecord(pedKey, info, label, table.concat(descriptionLines, '\n'), chemical and 'dui_chemical' or 'dui_field_test')
              duiApplyPostTestControl(ped, pedKey)
            end

            function showDuiSummary()
              local ped, pedKey, info = duiGetTargetPed(true)
              if not ped then return end
              local profile = duiGetProfile(ped, pedKey, info)
              local duiCase = duiGetCase(info)
              local observations = duiCase.observations or {}
              local summaryParts = { duiMakeSummaryHeader(info, profile) }
              if #observations > 0 then
                summaryParts[#summaryParts + 1] = '## Observations\n' .. duiJoinLines(observations)
              else
                summaryParts[#summaryParts + 1] = '## Observations\n- None documented yet.'
              end

              local orderedKeys = {'walk_turn', 'line_walk', 'one_leg', 'hgn', 'breathalyzer', 'bac', 'drug'}
              local testLines = {}
              for i = 1, #orderedKeys do
                local key = orderedKeys[i]
                local result = duiCase.tests[key]
                if result then
                  testLines[#testLines + 1] = '- ' .. tostring(result.summary)
                  if result.clues then
                    for j = 1, #result.clues do testLines[#testLines + 1] = '  • ' .. tostring(result.clues[j]) end
                  end
                  if result.detailLines then
                    for j = 1, #result.detailLines do testLines[#testLines + 1] = '  • ' .. tostring(result.detailLines[j]) end
                  end
                end
              end
              summaryParts[#summaryParts + 1] = '## Test Results\n' .. (#testLines > 0 and table.concat(testLines, '\n') or '- No tests completed yet.')

              local probableCause, reasons, points = duiProbableCause(duiCase)
              summaryParts[#summaryParts + 1] = ('## Probable Cause\n- Assessment: %s\n- Score: %d\n%s'):format(
                probableCause and 'Probable cause for impairment is present.' or 'Current findings are inconclusive / weak.',
                tonumber(points or 0) or 0,
                (#reasons > 0 and duiJoinLines(reasons) or '- No supporting reasons logged yet.')
              )

              local content = table.concat(summaryParts, '\n\n')
              duiCase.lastSummaryAt = duiNow()
              if lib and lib.alertDialog then
                lib.alertDialog({
                  header = 'DUI / SFST Summary',
                  content = content,
                  centered = true,
                  cancel = false,
                })
              else
                notify('dui_summary', 'DUI Summary', content:gsub('\n', ' | '), probableCause and 'warning' or 'inform', 'clipboard-check', '#4299E1')
              end
              duiSaveRecord(pedKey, info, 'DUI Investigation Summary', content, 'dui_summary')
            end

            function doArrest()
              dprint("doArrest called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("doArrest: no ped resolved")
                return notify("arrest_no","No Ped","None stopped.",'error','handcuffs','#E53E3E')
              end

              local arrestKey = tostring(tonumber(nid) or nid or safePedToNet(ped) or lastPedNetId or ped)
              lastPedNetId = arrestKey
              lastPedEntity = ped

              safeProgressBar({ duration=2000, label="Arresting" })

              if not DoesEntityExist(ped) then
                lastPedNetId = nil
                lastPedEntity = nil
                dprint("doArrest: ped no longer exists mid-arrest")
                return notify("arrest_no_exist","No Ped","Target no longer exists.",'error','handcuffs','#E53E3E')
              end

              playSimpleConversationAnim(ped, "refuse")
              NetworkRequestControlOfEntity(ped); SetEntityAsMissionEntity(ped,true,true)
              RequestAnimDict("mp_arresting")
              while not HasAnimDictLoaded("mp_arresting") do Citizen.Wait(0) end
              TaskPlayAnim(ped,"mp_arresting","idle",8.0,-8.0,3000,49,0); Citizen.Wait(3000)

              applyCuffedPedState(ped, arrestKey, false)
              holdPedAttention(ped, IsPedInAnyVehicle(ped, false))

              local fullName = nil
              local dob = ""
              if pedData[arrestKey] then
                fullName = pedData[arrestKey].name
                dob = pedData[arrestKey].dob or ""
              else
                fullName = getPedName(arrestKey)
              end

              local arrestContext = {
                wanted = pedData[arrestKey] and pedData[arrestKey].wanted == true or false,
                suspended = pedData[arrestKey] and pedData[arrestKey].suspended == true or false,
                illegalItems = pedData[arrestKey] and pedData[arrestKey].hasIllegalItems == true or false,
                drunk = pedData[arrestKey] and pedData[arrestKey].isDrunk == true or false,
                high = pedData[arrestKey] and pedData[arrestKey].isHigh == true or false,
                licenseStatus = pedData[arrestKey] and pedData[arrestKey].licenseStatus or '',
                lastIdOutcome = pedData[arrestKey] and pedData[arrestKey].lastIdOutcome or '',
                hadVehicleStop = pedData[arrestKey] and pedData[arrestKey].pulledProtected == true or false
              }
              TriggerServerEvent('police:arrestPed', arrestKey, fullName, dob, arrestContext)

              notify("arrest_ok","Arrest","Ped cuffed. Removing from world and logged.",'success','shield-halved','#38A169')

              Citizen.CreateThread(function()
                Citizen.Wait(500)

                if not DoesEntityExist(ped) then
                  if tostring(lastPedNetId or '') == arrestKey then lastPedNetId = nil end
                  if lastPedEntity == ped then lastPedEntity = nil end
                  dprint("doArrest: ped disappeared before removal")
                  return
                end

                NetworkRequestControlOfEntity(ped)
                SetEntityAsMissionEntity(ped, true, true)
                ClearPedTasksImmediately(ped)
                SetBlockingOfNonTemporaryEvents(ped, false)
                SetPedCanRagdoll(ped, true)
                SetPedKeepTask(ped, false)

                if IsPedInAnyVehicle(ped, false) then
                  local veh = GetVehiclePedIsIn(ped, false)
                  if DoesEntityExist(veh) then
                    TaskLeaveVehicle(ped, veh, 0)
                    Citizen.Wait(200)
                  end
                end

                SetPedAsNoLongerNeeded(ped)
                DeleteEntity(ped)
                if DoesEntityExist(ped) then
                  DeletePed(ped)
                end

                markPedCuffedState(ped, arrestKey, false)
                clearTrackedCuffStateForPed(ped, arrestKey)
                if draggedPed == ped then draggedPed = nil end
                isDragging = false
                local arrestSendNet = safePedToNet(ped) or tonumber(arrestKey) or arrestKey
                if arrestSendNet and tostring(arrestSendNet) ~= '' then
                  TriggerServerEvent('police:cuffPed', tostring(arrestSendNet), false)
                end
                pedData[arrestKey] = nil
                if tostring(lastPedNetId or '') == arrestKey then lastPedNetId = nil end
                if lastPedEntity == ped then lastPedEntity = nil end

                notify("arrest_final","Arrest Complete","Ped removed and arrest logged.",'success','shield-halved','#38A169')
              end)
            end

            function releasePed()
              dprint("releasePed called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("releasePed: no ped resolved")
                return notify("rel_no","No Ped","None stopped.",'error','unlock','#E53E3E')
              end
              if not DoesEntityExist(ped) then
                lastPedNetId = nil
                lastPedEntity = nil
                dprint("releasePed: ped not exist anymore")
                return notify("rel_no_exist","No Ped","Target no longer exists.",'error','unlock','#E53E3E')
              end

              local pedKey = tostring(nid or safePedToNet(ped) or ped)
              uncuffPedOnly(ped, pedKey, false)
              releasePedAttention(ped, true)
              FreezeEntityPosition(ped, false)

              if pedData[pedKey] then
                pedData[pedKey].forcedStop = nil
                pedData[pedKey].pulledProtected = false
                pedData[pedKey].pulledInVehicle = false
              end
              setPedProtected(pedKey, false)
              markPulledInVehicle(pedKey, false)

              SetEntityAsMissionEntity(ped,false,false)

              if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if DoesEntityExist(veh) then
                  NetworkRequestControlOfEntity(ped)
                  NetworkRequestControlOfEntity(veh)
                  SetVehicleEngineOn(veh, true, true, true)
                  SetVehicleHandbrake(veh, false)
                  SetVehicleDoorsLocked(veh, 1)
                  TaskVehicleDriveWander(ped, veh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                end
              else
                sendPedOnReleaseWalk(ped)
              end

              notify("rel_ok","Released","Ped uncuffed and sent on their way.",'success','unlock','#38A169')
              lastPedNetId = nil
              lastPedEntity = nil
            end

            function releasePedDriveAway()
              dprint("releasePedDriveAway called")
              local ped, nid = resolveLastPed()
              if not ped or not DoesEntityExist(ped) then
                dprint("releasePedDriveAway: no ped")
                return notify("rel_no","No Ped","None stopped.",'error','unlock','#E53E3E')
              end

              if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                  local driver = GetPedInVehicleSeat(veh, -1)
                  if driver == ped then

                    NetworkRequestControlOfEntity(veh)
                    NetworkRequestControlOfEntity(ped)
                    local start = GetGameTimer()
                    while not NetworkHasControlOfEntity(veh) and (GetGameTimer() - start) < 1000 do
                      NetworkRequestControlOfEntity(veh)
                      Citizen.Wait(10)
                    end

                    ClearPedTasksImmediately(ped)
                    SetVehicleEngineOn(veh, true, true, true)
                    SetVehicleHandbrake(veh, false)
                    SetVehicleDoorsLocked(veh, 1)
                    SetPedCanRagdoll(ped, true)

                    local netId_local = safePedToNet(ped) or tostring(ped)
                    uncuffPedOnly(ped, netId_local, false)
                    Citizen.Wait(Config.Timings.shortWait)
                    SetPedKeepTask(ped, true)

                    if pedData and pedData[tostring(netId_local)] and (pedData[tostring(netId_local)].wanted or pedData[tostring(netId_local)].suspended) then
                      if not attemptPedAttack(ped, veh, netId_local) then
                        startFleeDrive(ped, veh)
                      end
                    else
                      TaskVehicleDriveWander(ped, veh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                    end

                    SetEntityAsNoLongerNeeded(veh)
                    SetEntityAsNoLongerNeeded(ped)

                    notify("rel_drive","Released (driving)","Ped stays in vehicle and drives away.",'success','unlock','#38A169')
                    lastPedNetId = nil
                    lastPedEntity = nil
                    return
                  else

                    dprint("releasePedDriveAway: target is a passenger; will not warp to driver. Using standard release flow.")
                    return releasePed()
                  end
                end
              end

              dprint("releasePedDriveAway: ped not in vehicle, using standard releasePed()")
              releasePed()
            end

            function tryCuffPed()
              dprint("tryCuffPed called")
              local ped, nid = resolveLastPed()
              dprint("tryCuffPed: resolved ped=", tostring(ped), "nid=", tostring(nid))

              if not ped then
                dprint("tryCuffPed: no ped")
                return notify("cuff_no","No Ped","None stopped.",'error','lock','#E53E3E')
              end

              if not DoesEntityExist(ped) then
                dprint("tryCuffPed: ped does not exist")
                lastPedNetId = nil; lastPedEntity = nil
                return notify("cuff_no_exist","No Ped","Target no longer exists.",'error','lock','#E53E3E')
              end

              if IsPedAPlayer(ped) then
                dprint("tryCuffPed: target is a player - aborting client-side cuff")
                return notify("cuff_player","Cannot Cuff Player","You can't cuff player-controlled characters from this client.",'warning','ban','#DD6B20')
              end

              if #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) > 1.5 then
                dprint("tryCuffPed: too far")
                return notify("cuff_far","Too Far","Get closer.",'error','location-arrow','#E53E3E')
              end

              local existingKey = tostring(nid or lastPedNetId or safePedToNet(ped) or ped)
              local alreadyCuffed, canonicalExistingKey = isPedActuallyCuffed(ped, existingKey)
              if alreadyCuffed then
                uncuffPedOnly(ped, canonicalExistingKey or existingKey, true)
                notify("uncuff_ok","Uncuffed","Ped handcuffs removed.",'success','unlock','#38A169')
                lastPedEntity = ped
                lastPedNetId = canonicalExistingKey or existingKey
                return
              end

              notify("cuff_start","Cuffing…","Please wait.",'inform','handcuffs','#4299E1')

              local ok = false
              if lib and lib.progressBar then
                ok = lib.progressBar({ duration=2000, label="Cuffing" })
              else
                dprint("tryCuffPed: lib.progressBar missing - waiting locally")
                Citizen.Wait(2000)
                ok = true
              end

              if not ok then
                dprint("tryCuffPed: progress canceled")
                return notify("cuff_cancel","Canceled","Aborted.",'warning','ban','#DD6B20')
              end

              NetworkRequestControlOfEntity(ped)
              local ctrlStart = GetGameTimer()
              while not NetworkHasControlOfEntity(ped) and (GetGameTimer() - ctrlStart) < 1000 do
                NetworkRequestControlOfEntity(ped)
                Citizen.Wait(10)
              end
              if not NetworkHasControlOfEntity(ped) then
                dprint("tryCuffPed: WARNING - could not obtain network control of ped, continuing anyway")
              end

              local dict = "mp_arresting"
              RequestAnimDict(dict)
              local loadStart = GetGameTimer()
              while not HasAnimDictLoaded(dict) and (GetGameTimer() - loadStart) < 1000 do
                Citizen.Wait(0)
              end
              if not HasAnimDictLoaded(dict) then
                dprint("tryCuffPed: failed to load anim dict " .. tostring(dict))
              end

              if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                  TaskLeaveVehicle(ped, veh, 0)
                  local leaveStart = GetGameTimer()
                  while IsPedInAnyVehicle(ped, false) and (GetGameTimer() - leaveStart) < 700 do
                    Citizen.Wait(10)
                  end
                end
              end

              ClearPedTasksImmediately(ped)
              ClearPedSecondaryTask(ped)
              Citizen.Wait(Config.Timings.shortWait)

              local played = false
              for attempt = 1, 3 do
                TaskPlayAnim(ped, dict, "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
                Citizen.Wait(150)
                if IsEntityPlayingAnim(ped, dict, "idle", 3) then
                  played = true
                  break
                else
                  dprint(("tryCuffPed: anim play attempt %d failed, retrying"):format(attempt))
                  Citizen.Wait(Config.Timings.shortWait)
                end
              end

              if not played then
                dprint("tryCuffPed: WARNING - animation didn't start; will still apply cuff state")

              end

              local cuffKey = getPedCanonicalCuffKey(ped, nid or lastPedNetId or safePedToNet(ped) or ped)
              applyCuffedPedState(ped, cuffKey, true)
              if IsPedInAnyVehicle(ped, false) then
                rememberDetainedVehicleState(ped, cuffKey, GetVehiclePedIsIn(ped, false))
              else
                pedData[cuffKey] = pedData[cuffKey] or {}
                pedData[cuffKey].detainedVehicleNet = nil
                pedData[cuffKey].detainedSeat = nil
                pedData[cuffKey].pulledInVehicle = false
                pedData[cuffKey].pulledProtected = false
                pedData[cuffKey].forcedStop = nil
                pedData[cuffKey].preventVehicleReseatUntil = GetGameTimer() + 15000
              end

              notify("cuff_ok","Cuffed","Ped is handcuffed.",'success','lock','#38A169')

              draggedPed = ped
              cachePedReference(ped, cuffKey)
              lastPedEntity = ped
              lastPedNetId = cuffKey
              lastCuffedPedEntity = ped
              lastCuffedPedNetId = cuffKey
              isDragging = false

              local sendNet = safePedToNet(ped)
              if not sendNet or sendNet == 0 then
                sendNet = tonumber(lastPedNetId or '') or lastPedNetId
              end

              dprint("tryCuffPed: sending server event police:cuffPed with", tostring(sendNet))
              if sendNet and tostring(sendNet) ~= '' then
                TriggerServerEvent('police:cuffPed', sendNet)
              end
            end


            local function placeCuffedPedIntoVehicle(ped, veh, seatIdx, netId)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
              if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

              NetworkRequestControlOfEntity(ped)
              NetworkRequestControlOfEntity(veh)

              local player = PlayerPedId()
              local driverPed = GetPedInVehicleSeat(veh, -1)
              local playerIsDriver = (driverPed ~= 0 and driverPed == player)
              local engineWasRunning = GetIsVehicleEngineRunning(veh)

              SetVehicleDoorsLocked(veh, 1)

              if isDragging or IsEntityAttached(ped) then
                DetachEntity(ped, true, false)
                isDragging = false
              end

              local pedKey = cachePedReference(ped, netId or safePedToNet(ped) or tostring(ped))
              local seatDoor = (seatIdx == 1) and 2 or ((seatIdx == 2) and 3 or 1)

              ClearPedTasksImmediately(ped)
              ClearPedSecondaryTask(ped)
              SetEntityCollision(ped, true, true)
              FreezeEntityPosition(ped, false)
              applyCuffedPedState(ped, pedKey, true)

              if seatDoor >= 0 then
                SetVehicleDoorOpen(veh, seatDoor, false, false)
              end

              local seatingCfg = (Config and Config.PedCustody and Config.PedCustody.seating) or {}
              if seatingCfg.preferTaskEnterWarp ~= false then
                TaskEnterVehicle(ped, veh, 1000, seatIdx, 2.0, 16, 0)
                Citizen.Wait(tonumber(seatingCfg.directEnterWaitMs) or 350)
              end

              if not (IsPedInVehicle(ped, veh, false) and GetPedInVehicleSeat(veh, seatIdx) == ped) and seatingCfg.fallbackToTaskWarp ~= false then
                ClearPedTasksImmediately(ped)
                TaskWarpPedIntoVehicle(ped, veh, seatIdx)
                Citizen.Wait(75)
              end

              if not (IsPedInVehicle(ped, veh, false) and GetPedInVehicleSeat(veh, seatIdx) == ped) and seatingCfg.fallbackToSetPedIntoVehicle ~= false then
                SetPedIntoVehicle(ped, veh, seatIdx)
                Citizen.Wait(50)
              end

              if seatDoor >= 0 then
                SetVehicleDoorShut(veh, seatDoor, false)
              end

              if not (IsPedInVehicle(ped, veh, false) and GetPedInVehicleSeat(veh, seatIdx) == ped) then
                return false
              end

              pedData[pedKey] = pedData[pedKey] or {}
              pedData[pedKey].entity = ped
              pedData[pedKey].detainedVehicleNet = safeEntityToNet(veh) or pedData[pedKey].detainedVehicleNet
              pedData[pedKey].detainedSeat = seatIdx
              holdPedAttention(ped, true)

              if playerIsDriver or driverPed == 0 then
                SetVehicleUndriveable(veh, false)
                SetVehicleHandbrake(veh, false)
                if engineWasRunning or playerIsDriver then
                  SetVehicleEngineOn(veh, true, true, true)
                end
              end

              return true
            end

            function toggleDragPed()
              local ped, netId = resolveCuffedPed()
              dprint("toggleDragPed called, cuffedPed=", tostring(ped))
              if not ped or not DoesEntityExist(ped) then
                dprint("toggleDragPed: no cuffed ped")
                return notify("drag_no","No Cuffed","No one cuffed.",'error','person-walking','#E53E3E')
              end

              draggedPed = ped
              local player = PlayerPedId()
              NetworkRequestControlOfEntity(ped)

              if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then forcePedExitFromVehicle(ped, veh) end
                Citizen.Wait(250)
              end

              if not isDragging then
                applyCuffedPedState(ped, netId, true)
                ClearPedTasksImmediately(ped)
                local dragCfg = (Config and Config.PedCustody and Config.PedCustody.drag) or {}
                if dragCfg.disableCollision == false then
                  SetEntityCollision(ped, true, true)
                else
                  SetEntityCollision(ped, false, false)
                end
                local dragCfg = (Config and Config.PedCustody and Config.PedCustody.drag) or {}
                AttachEntityToEntity(ped, player, tonumber(dragCfg.useBone) or 0, tonumber(dragCfg.offsetX) or 0.22, tonumber(dragCfg.offsetY) or 0.54, tonumber(dragCfg.offsetZ) or -0.02, tonumber(dragCfg.rotX) or 0.0, tonumber(dragCfg.rotY) or 0.0, tonumber(dragCfg.rotZ) or 0.0, false, false, false, false, 2, true)
                isDragging = true
                notify("drag_start","Dragging","Cuffed ped under escort.",'inform','arrows-spin','#4299E1')
                dprint("toggleDragPed: started dragging", tostring(ped))
              else
                DetachEntity(ped, true, false)
                SetEntityCollision(ped, true, true)
                isDragging = false
                applyCuffedPedState(ped, netId, true)
                local releasePos = GetOffsetFromEntityInWorldCoords(player, 0.0, 0.85, 0.0)
                SetEntityCoordsNoOffset(ped, releasePos.x, releasePos.y, releasePos.z, false, false, false)
                SetEntityHeading(ped, GetEntityHeading(player))
                holdPedAttention(ped, false)
                notify("drag_stop","Released","Cuffed ped released from escort.",'success','arrows-spin','#38A169')
                dprint("toggleDragPed: stopped dragging", tostring(ped))
              end
            end

            function seatPed(idx, explicitVeh)
              dprint("seatPed called idx=", tostring(idx))
              local ped, netId = resolveCuffedPed()
              if not ped or not DoesEntityExist(ped) then
                dprint("seatPed: no cuffed ped")
                return notify("seat_no","No Ped","None to seat.",'error','car-side','#E53E3E')
              end
              local coords = GetEntityCoords(PlayerPedId())
              local veh = explicitVeh
              if (not veh or veh == 0 or not DoesEntityExist(veh)) and lib and lib.getClosestVehicle then
                local v = lib.getClosestVehicle(coords, 6.0, false)
                if type(v) == "table" then veh = v.vehicle or nil else veh = v end
              end
              if not veh or veh == 0 or not DoesEntityExist(veh) then
                local handle, candidate = FindFirstVehicle()
                local ok = true
                local bestDist, bestVeh = 1e9, nil
                while ok do
                  if DoesEntityExist(candidate) then
                    local d = #(GetEntityCoords(candidate) - coords)
                    if d < bestDist and d <= 6.0 then bestDist = d; bestVeh = candidate end
                  end
                  ok, candidate = FindNextVehicle(handle)
                end
                EndFindVehicle(handle)
                veh = bestVeh
              end

              if not veh or veh == 0 then
                dprint("seatPed: no nearby vehicle")
                return notify("seat_noveh","No Vehicle","No vehicle nearby.",'error','car-side','#E53E3E')
              end

              if not IsVehicleSeatFree(veh, idx) then
                return notify("seat_busy","Seat Occupied","That rear seat is occupied.",'warning','car-side','#DD6B20')
              end

              local seatLabel = (idx == 1) and "left rear" or ((idx == 2) and "right rear" or ("seat " .. tostring(idx)))
              local ok = placeCuffedPedIntoVehicle(ped, veh, idx, netId)
              if not ok then
                dprint("seatPed: failed to seat ped into vehicle", tostring(veh), "seat", tostring(idx))
                return notify("seat_fail","Seat Failed","Could not place cuffed ped into the " .. seatLabel .. ".", 'error','car-side','#E53E3E')
              end

              notify("seat_ok","Seated","Placed cuffed ped in the " .. seatLabel .. ".",'success','car-side','#38A169')
              dprint("seatPed: seated ped into vehicle", tostring(veh), "seat", tostring(idx))
            end

            local SCAN_INTERVAL = 5000
            local TARGET_DISTANCE = 2.5

            local registeredNetIds = {}

            local function getAllPeds()
                local peds = {}
                local handle, ped = FindFirstPed()
                if handle ~= -1 then
                    local success = true
                    while success do
                        if DoesEntityExist(ped) then
                            table.insert(peds, ped)
                        end
                        success, ped = FindNextPed(handle)
                    end
                    EndFindPed(handle)
                end
                return peds
            end

            local function netIdExists(netId)
                if not netId or netId == 0 then return false end
                local ent = safeNetworkGetEntityFromNetworkId(netId)
                return ent and ent ~= 0 and DoesEntityExist(ent)
            end

            RegisterNetEvent('az-police:openMenu', function()
                tryOpenPoliceMenu()
            end)

            RegisterCommand('policemenu', function()
                tryOpenPoliceMenu()
            end, false)

            CreateThread(function()
                local options = {
                    {
                        name = 'open_police_menu',
                        label = 'Open Police Menu',
                        icon = 'fa-solid fa-clipboard-list',
                        distance = TARGET_DISTANCE or 2.5,
                        onSelect = function(data)
                            cacheTargetPedContext(data)
                            tryOpenPoliceMenu()
                        end
                    }
                }

                Citizen.Wait(2000)
                pcall(function() exports.ox_target:addGlobalPed(options) end)
            end)

            AddEventHandler('onResourceStop', function(resName)
                if GetCurrentResourceName() ~= resName then return end
                pcall(function() exports.ox_target:removeGlobalPed({'open_police_menu'}) end)
                pcall(function() exports.ox_target:removeGlobalVehicle({'az_police_seat_cuffed_left', 'az_police_seat_cuffed_right'}) end)
            end)

            AddEventHandler("onResourceStop", function(resName)
              if GetCurrentResourceName() ~= resName then return end
              if pullVeh and DoesEntityExist(pullVeh) then
                local occ = getPrimaryOccupant(pullVeh)
                if occ and occ ~= 0 then
                  local n = safePedToNet(occ)
                  if n then setPedProtected(n, false); markPulledInVehicle(n, false) end
                  releasePedAttention(occ)
                end
                SetVehicleEngineOn(pullVeh, true, true, true)
                SetVehicleHandbrake(pullVeh, false)
                SetVehicleDoorsLocked(pullVeh, 1)
                pullVeh = nil
              end
            end)

            local function getNearbyDownedPeds(center, radius, onlyHuman)
              local found = {}
              local cx, cy, cz = toXYZ(center)
              if not cx then
                print("[AI DEBUG] getNearbyDownedPeds: invalid center:", tostring(center))
                return found
              end
              print((" [AI DEBUG] getNearbyDownedPeds: center=%.2f,%.2f,%.2f radius=%.1f"):format(cx, cy, cz, radius))

              local handle, ped = FindFirstPed()
              local success = true
              local checked = 0
              local function distToPed(p)
                local pc = GetEntityCoords(p)
                return Vdist(cx, cy, cz, pc.x, pc.y, pc.z)
              end

              while success do
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                  checked = checked + 1
                  local d = distToPed(ped)
                  if d <= radius then
                    local hp = GetEntityHealth(ped) or 200
                    local deadOrDying = IsPedDeadOrDying(ped, true) or IsEntityDead(ped)
                    local fatally = IsPedDeadOrDying(ped, false) or IsPedFatallyInjured and IsPedFatallyInjured(ped)
                    local ragdoll = IsPedRagdoll(ped)
                    local severelyWounded = (hp > 0 and hp < 140)
                    local isHuman = true
                    if type(IsPedHuman) == "function" then isHuman = IsPedHuman(ped) end

                    print((" [AI DEBUG] checked ped %d: handle=%s dist=%.1f hp=%d deadOrDying=%s fatally=%s ragdoll=%s wounded=%s human=%s"):format(checked, tostring(ped), d, hp, tostring(deadOrDying), tostring(fatally), tostring(ragdoll), tostring(severelyWounded), tostring(isHuman)))

                    if (deadOrDying or fatally or ragdoll or severelyWounded) and (onlyHuman == nil or onlyHuman == isHuman) then
                      print((" [AI DEBUG] -> selecting ped %s as casualty"):format(tostring(ped)))
                      table.insert(found, { ped = ped, health = hp, revivable = true })
                    end
                  end
                end
                success, ped = FindNextPed(handle)
              end
              EndFindPed(handle)
              print((" [AI DEBUG] getNearbyDownedPeds: checked %d peds, found %d casualties"):format(checked, #found))
              return found
            end

            local function requestControl(ent, timeout)
              timeout = timeout or 1000
              local t0 = GetGameTimer()
              NetworkRequestControlOfEntity(ent)
              while not NetworkHasControlOfEntity(ent) and (GetGameTimer() - t0) < timeout do
                NetworkRequestControlOfEntity(ent)
                Citizen.Wait(Config.Timings.shortWait)
              end
              local ok = NetworkHasControlOfEntity(ent)
              print((" [AI DEBUG] requestControl(%s) -> %s (took %dms)"):format(tostring(ent), tostring(ok), GetGameTimer()-t0))
              return ok
            end

            local function forcePedExitVehicle(ped, vehicle)
              if not DoesEntityExist(ped) then return false end
              local attempts = 0
              local ok = false
              while attempts < 5 do
                attempts = attempts + 1
                if IsPedInAnyVehicle(ped, false) then
                  print((" [AI DEBUG] forcePedExitVehicle: attempt %d - ped %s in vehicle, trying TaskLeaveVehicle"):format(attempts, tostring(ped)))
                  ClearPedTasksImmediately(ped)
                  TaskLeaveVehicle(ped, vehicle or 0, 0)
                  Citizen.Wait(500 + attempts * 300)
                else
                  ok = true
                  break
                end
              end
              if not ok then

                if DoesEntityExist(vehicle) then
                  local vcoords = GetEntityCoords(vehicle)
                  local ox, oy, oz = table.unpack(GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0))
                  SetEntityCoordsNoOffset(ped, ox, oy, oz, false, false, false)
                  Citizen.Wait(200)
                  if not IsPedInAnyVehicle(ped, false) then ok = true end
                end
              end
              print((" [AI DEBUG] forcePedExitVehicle: result=%s after %d attempts"):format(tostring(ok), attempts))
              return ok
            end

            local REVIVE_CHANCE = 65
            local SERVICE_TIME_MS = 6000

            local function handleCasualtyInteraction(responderPed, vehicle, casualty)
              print((" [AI DEBUG] handleCasualtyInteraction: responder=%s vehicle=%s casualty=%s"):format(tostring(responderPed), tostring(vehicle), tostring(casualty)))
              if not DoesEntityExist(responderPed) then print(" [AI DEBUG] responder does not exist") return end
              if not DoesEntityExist(casualty) then print(" [AI DEBUG] casualty does not exist") return end

              local function hospitalCoords()
                return vector3(357.43, -593.36, 28.79)
              end

              local function forcePedIntoVehicleSeat(targetPed, veh, seat)
                if not DoesEntityExist(targetPed) or not DoesEntityExist(veh) then return false end
                requestControl(targetPed, 1000)
                requestControl(veh, 1000)
                ClearPedTasksImmediately(targetPed)
                TaskWarpPedIntoVehicle(targetPed, veh, seat)
                Citizen.Wait(200)
                return IsPedInVehicle(targetPed, veh, false)
              end

              local function loadIntoAmbulance(targetPed, ambVeh)
                if not DoesEntityExist(targetPed) or not DoesEntityExist(ambVeh) then return false end
                requestControl(targetPed, 1000)
                requestControl(ambVeh, 1000)
                ClearPedTasksImmediately(targetPed)
                SetBlockingOfNonTemporaryEvents(targetPed, true)
                SetPedKeepTask(targetPed, true)
                FreezeEntityPosition(targetPed, false)

                for _, seat in ipairs({1, 2, 0, 3}) do
                  if IsVehicleSeatFree(ambVeh, seat) then
                    if forcePedIntoVehicleSeat(targetPed, ambVeh, seat) then
                      return true
                    end
                    ClearPedTasksImmediately(targetPed)
                    SetPedIntoVehicle(targetPed, ambVeh, seat)
                    Citizen.Wait(150)
                    if IsPedInVehicle(targetPed, ambVeh, false) then
                      return true
                    end
                  end
                end

                local retryPos = GetOffsetFromEntityInWorldCoords(ambVeh, 0.0, -3.2, 0.0)
                SetEntityCoordsNoOffset(targetPed, retryPos.x, retryPos.y, retryPos.z, false, false, false)
                Citizen.Wait(150)
                for _, seat in ipairs({1, 2, 0, 3}) do
                  if IsVehicleSeatFree(ambVeh, seat) then
                    if forcePedIntoVehicleSeat(targetPed, ambVeh, seat) then
                      return true
                    end
                    ClearPedTasksImmediately(targetPed)
                    SetPedIntoVehicle(targetPed, ambVeh, seat)
                    Citizen.Wait(150)
                    if IsPedInVehicle(targetPed, ambVeh, false) then
                      return true
                    end
                  end
                end

                AttachEntityToEntity(targetPed, ambVeh, -1, 0.0, -1.8, 0.6, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
                SetEntityCollision(targetPed, false, false)
                SetEntityVisible(targetPed, false, false)
                return true
              end

              requestControl(responderPed, 2000)
              requestControl(vehicle, 2000)

              if IsPedInAnyVehicle(responderPed, false) then
                print(" [AI DEBUG] responder is in vehicle, forcing exit...")
                forcePedExitVehicle(responderPed, vehicle)
                Citizen.Wait(350)
              end

              TaskGoToEntity(responderPed, casualty, -1, 2.0, 2.0, 1073741824, 0)
              local approachStart = GetGameTimer()
              while GetGameTimer() - approachStart < 12000 do
                if not DoesEntityExist(responderPed) or not DoesEntityExist(casualty) then
                  print(" [AI DEBUG] responder or casualty no longer exists while approaching")
                  return
                end
                local dist = #(GetEntityCoords(responderPed) - GetEntityCoords(casualty))
                if dist <= 2.2 then break end
                Citizen.Wait(200)
              end

              local ccoords = GetEntityCoords(casualty)
              TaskTurnPedToFaceCoord(responderPed, ccoords.x, ccoords.y, ccoords.z, 500)
              if requestControl(responderPed, 500) then
                TaskStartScenarioInPlace(responderPed, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
              end

              Citizen.Wait(SERVICE_TIME_MS)
              ClearPedTasksImmediately(responderPed)
              print(" [AI DEBUG] finished treatment wait, evaluating outcome...")

              math.randomseed(math.floor(GetGameTimer() + GetEntityCoords(responderPed).x * 1000))
              local roll = math.random(1, 100)
              local outcome = nil
              if roll <= 55 then
                outcome = 'survived'
              elseif roll <= 82 then
                outcome = 'coma'
              else
                outcome = 'died'
              end
              print((" [AI DEBUG] medic outcome roll=%d -> %s"):format(roll, outcome))

              local loaded = false
              if outcome == 'died' then
                if DoesEntityExist(casualty) then
                  requestControl(casualty, 500)
                  SetEntityHealth(casualty, 0)
                  if not IsEntityDead(casualty) then ApplyDamageToPed(casualty, 1000, false) end
                end
                if type(notify) == "function" then
                  notify("ai_medic_report", "EMS Report", "Patient pronounced deceased at the scene.", 'error', 'skull', '#ef4444')
                end
              else
                if DoesEntityExist(casualty) then
                  requestControl(casualty, 500)
                  ClearPedTasksImmediately(casualty)
                  ResurrectPed(casualty)
                  SetEntityHealth(casualty, outcome == 'survived' and 160 or 110)
                  TaskStandStill(casualty, 1200)
                end

                if DoesEntityExist(vehicle) then
                  loaded = loadIntoAmbulance(casualty, vehicle)
                end

                if type(notify) == "function" then
                  if outcome == 'survived' then
                    notify("ai_medic_transport", "EMS Transport", loaded and "Patient loaded into the ambulance and is being transported to the hospital." or "Patient stabilized. EMS is preparing hospital transport.", 'success', 'truck-medical', '#22c55e')
                  else
                    notify("ai_medic_transport", "EMS Transport", loaded and "Patient loaded into the ambulance and is being transported to the hospital in a coma." or "Patient is in a coma. EMS is preparing hospital transport.", 'warning', 'bed-pulse', '#f59e0b')
                  end
                end
              end

              if DoesEntityExist(responderPed) and DoesEntityExist(vehicle) then
                Citizen.CreateThread(function()
                  Citizen.Wait(900)
                  requestControl(responderPed, 1000)
                  requestControl(vehicle, 1000)

                  if not IsPedInAnyVehicle(responderPed, false) then
                    TaskEnterVehicle(responderPed, vehicle, 3500, -1, 1.0, 1, 0)
                    local deadline = GetGameTimer() + 3500
                    while GetGameTimer() < deadline and not IsPedInAnyVehicle(responderPed, false) do
                      Citizen.Wait(100)
                    end
                    if not IsPedInAnyVehicle(responderPed, false) then
                      TaskWarpPedIntoVehicle(responderPed, vehicle, -1)
                      Citizen.Wait(150)
                    end
                  end

                  if outcome ~= 'died' and DoesEntityExist(casualty) and not IsPedInVehicle(casualty, vehicle, false) then
                    loadIntoAmbulance(casualty, vehicle)
                  end

                  if IsPedInAnyVehicle(responderPed, false) and GetPedInVehicleSeat(vehicle, -1) == responderPed then
                    local hospital = hospitalCoords()
                    SetVehicleHandbrake(vehicle, false)
                    SetVehicleEngineOn(vehicle, true, true, true)
                    SetVehicleUndriveable(vehicle, false)
                    if type(SetDriverAbility) == "function" then pcall(SetDriverAbility, responderPed, 1.0) end
                    if type(SetDriverAggressiveness) == "function" then pcall(SetDriverAggressiveness, responderPed, 0.0) end
                    TaskVehicleDriveToCoordLongrange(responderPed, vehicle, hospital.x, hospital.y, hospital.z, 24.0, 786603, 18.0)

                    if outcome ~= 'died' then
                      local deadline = GetGameTimer() + 45000
                      while GetGameTimer() < deadline and DoesEntityExist(vehicle) do
                        local dist = #(GetEntityCoords(vehicle) - hospital)
                        if dist <= 55.0 then break end
                        Citizen.Wait(500)
                      end
                      if DoesEntityExist(casualty) then
                        requestControl(casualty, 500)
                        DetachEntity(casualty, true, true)
                        DeleteEntity(casualty)
                      end
                      if type(notify) == "function" then
                        if outcome == 'survived' then
                          notify("ai_medic_report", "EMS Report", "Patient transported to the hospital and survived.", 'success', 'heart', '#22c55e')
                        else
                          notify("ai_medic_report", "EMS Report", "Patient transported to the hospital and remains in a coma.", 'warning', 'bed-pulse', '#f59e0b')
                        end
                      end
                    end

                    TaskVehicleDriveWander(responderPed, vehicle, 20.0, 786603)
                  end
                end)
              end
            end

            if type(handleCasualtyInteraction) == 'function' then
              _G.handleCasualtyInteraction = handleCasualtyInteraction
              if _G.__ai_casualty_queue and #_G.__ai_casualty_queue > 0 then
                print(" [AI DEBUG] Flushing queued casualty calls:", #_G.__ai_casualty_queue)
                for _, args in ipairs(_G.__ai_casualty_queue) do
                  Citizen.CreateThread(function()
                    handleCasualtyInteraction(table.unpack(args))
                  end)
                end
                _G.__ai_casualty_queue = nil
              end
            end

            RegisterCommand('debugDownedSearch', function()
              local ped = PlayerPedId()
              local coords = GetEntityCoords(ped)
              print(" [AI DEBUG CMD] Running debugDownedSearch at player coords:", coords.x, coords.y, coords.z)
              local found = getNearbyDownedPeds(coords, 30.0, nil)
              print((" [AI DEBUG CMD] Found %d downed peds within 30m"):format(#found))
              for i,info in ipairs(found) do
                local p = info.ped
                local hp = info.health
                local d = Vdist(coords.x, coords.y, coords.z, GetEntityCoords(p).x, GetEntityCoords(p).y, GetEntityCoords(p).z)
                print((" [AI DEBUG CMD] %d) ped=%s hp=%d dist=%.1f"):format(i, tostring(p), hp, d))
              end
            end, false)

            RegisterCommand('forceAIMedicResponse', function()
              local player = PlayerPedId()
              local px,py,pz = table.unpack(GetEntityCoords(player))
              print(" [AI DEBUG CMD] forceAIMedicResponse triggered at:", px,py,pz)

              local handle, veh = FindFirstVehicle()
              local success = true
              local bestVeh = nil
              local bestDist = 9999
              while success do
                if DoesEntityExist(veh) then
                  local d = Vdist(px,py,pz, GetEntityCoords(veh))
                  if d < bestDist and d <= 80.0 then
                    bestDist = d
                    bestVeh = veh
                  end
                end
                success, veh = FindNextVehicle(handle)
              end
              EndFindVehicle(handle)

              if not bestVeh then
                print(" [AI DEBUG CMD] No vehicle found nearby.")
                return
              end
              local driver = GetPedInVehicleSeat(bestVeh, -1)
              if not DoesEntityExist(driver) then print(" [AI DEBUG CMD] No driver in chosen vehicle") end
              print((" [AI DEBUG CMD] Selected vehicle %s at dist=%.1f with driver %s"):format(tostring(bestVeh), bestDist, tostring(driver)))

              local vcoords = GetEntityCoords(bestVeh)
              local casualties = getNearbyDownedPeds(vcoords, 30.0, nil)
              print((" [AI DEBUG CMD] Found %d casualties near vehicle"):format(#casualties))
              if #casualties == 0 then
                print(" [AI DEBUG CMD] Trying larger radius (60m)...")
                casualties = getNearbyDownedPeds(vcoords, 60.0, nil)
                print((" [AI DEBUG CMD] Found %d casualties in larger radius"):format(#casualties))
              end

              if #casualties > 0 then
                local c = casualties[1].ped
                print((" [AI DEBUG CMD] Forcing driver %s to tend casualty %s"):format(tostring(driver), tostring(c)))
                Citizen.CreateThread(function()
                  handleCasualtyInteraction(driver, bestVeh, c)
                end)
              else
                print(" [AI DEBUG CMD] No casualties found to tend.")
              end
            end, false)

            RegisterKeyMapping('debugDownedSearch', 'AI Debug: list downed peds near player', 'keyboard', '')

            RegisterCommand('repositionVeh', function()
              dprint("repositionVeh keybind triggered, pullVeh=" .. tostring(pullVeh))
              if pullVeh and DoesEntityExist(pullVeh) then
                pcall(function() repositionInteractive(pullVeh) end)
              else
                notify("no_vehicle","No Vehicle","No pulled vehicle to reposition.",'error','car-side','#E53E3E')
              end
            end, false)

            RegisterKeyMapping('repositionVeh', 'Reposition pulled vehicle', 'keyboard', 'Y')

        else
            print("[Az-FR | CALLOUT System] You are not an allowed department.")
        end
    end

    local function waitForFrameworkReady(timeoutMs)
        local untilT = GetGameTimer() + (timeoutMs or 15000)
        while GetGameTimer() < untilT do
            if type(GetResourceState) == "function" and GetResourceState("Az-Framework") == "started" then
                return true
            end
            Wait(250)
        end
        return false
    end

    if not waitForFrameworkReady(15000) then
        print("[Az-FR | CALLOUT System] Az-Framework not started yet; continuing to wait for job sync...")
    end

    Wait(200) -- allow exports to init (JIP-safe)

    local function getJobSync(timeoutMs)
        local job, done = nil, false
        getPlayerJobFromServer(function(j)
            job = j
            done = true
        end)
        local untilT = GetGameTimer() + (timeoutMs or 4000)
        while (not done) and (GetGameTimer() < untilT) do
            Wait(25)
        end
        return job
    end

    local tries = 0
    while true do
        tries = tries + 1
        local job = getJobSync(5000)

        if job == nil then
            if (tries % 10) == 1 then
                print("[Az-FR | CALLOUT System] Waiting for framework job (join-in-progress)... attempt " .. tostring(tries))
            end
        elseif not isJobAllowed(job) then
            print("[Az-FR | CALLOUT System] You are not an allowed department (" .. tostring(job) .. ").")
            return
        else
            __az5pd_init(job)
            return
        end

        Wait(1000)
    end
end)
