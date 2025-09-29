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
    Wait(200) -- allow exports to initialize
    getPlayerJobFromServer(function(job)
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
              local ok, nid = pcall(function() return safeNetworkGetNetworkIdFromEntity(entity) end)
              if not ok or not nid or nid == 0 then return nil end
              return nid
            end

            local function safeNetworkGetEntityFromNetworkId(nid)
              if not nid then return nil end
              local n = tonumber(nid) or nid
              if type(n) ~= "number" then return nil end
              local ok, ent = pcall(function() return safeNetworkGetEntityFromNetworkId(n) end)
              if not ok or not ent or ent == 0 then return nil end
              if not DoesEntityExist(ent) then return nil end
              return ent
            end




            local function resolvePed(idOrEntity)
              if not idOrEntity then return nil, nil end
              
              if type(idOrEntity) == "number" and DoesEntityExist(idOrEntity) then
                local ent = idOrEntity
                local ok, nid = pcall(function() return PedToNet(ent) end)
                if ok and nid and nid ~= 0 then
                  return ent, nid
                else
                  return ent, nil
                end
              end
              
              local nid = tonumber(idOrEntity)
              if nid then
                local ok, ent = pcall(function() return NetworkGetEntityFromNetworkId(nid) end)
                if ok and ent and ent ~= 0 and DoesEntityExist(ent) then
                  return ent, nid
                end
                
                
                local ok2, exists = pcall(function() return NetworkDoesEntityExistWithNetworkId and NetworkDoesEntityExistWithNetworkId(nid) end)
                if ok2 and exists then
                  local ok3, ent2 = pcall(function() return NetworkGetEntityFromNetworkId(nid) end)
                  if ok3 and ent2 and ent2 ~= 0 and DoesEntityExist(ent2) then
                    return ent2, nid
                  end
                end
              end
              return nil, nil
            end

            local function safeNetToPed(netIdOrEntity)
              
              local ent, nid = resolvePed(netIdOrEntity)
              if ent and DoesEntityExist(ent) then return ent end
              return nil
            end

            local function safePedToNet(pedOrNetId)
              
              if not pedOrNetId then return nil end
              
              if type(pedOrNetId) == "number" and DoesEntityExist(pedOrNetId) then
                local ok, nid = pcall(function() return PedToNet(pedOrNetId) end)
                if ok and nid and nid ~= 0 then return nid end
                return nil
              end
              
              local nid = tonumber(pedOrNetId)
              if nid then
                local ok, exists = pcall(function() return NetworkDoesEntityExistWithNetworkId and NetworkDoesEntityExistWithNetworkId(nid) end)
                if ok and exists then return nid end
              end
              return nil
            end

            local function safeNetworkGetEntityFromIdMaybe(n)
              if not n then return nil end
              local nn = tonumber(n) or n
              if type(nn) ~= "number" then return nil end
              local ok, ent = pcall(function() return NetworkGetEntityFromNetworkId(nn) end)
              if ok and ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
              return nil
            end



            local function safeNetToEntity(netId)
              return safeNetworkGetEntityFromNetworkId(netId)
            end

            local function safePedToNet(ped)
              if not ped or ped == 0 then return nil end
              if not DoesEntityExist(ped) then return nil end
              local ok, isNet = pcall(function() return NetworkGetEntityIsNetworked(ped) end)
              if not ok or not isNet then return nil end
              local ok2, nid = pcall(function() return safePedToNet(ped) end)
              if ok2 and nid and nid ~= 0 then return nid end
              return nil
            end

            local function safeEntityToNet(entity)
              if not entity or entity == 0 then return nil end
              if not DoesEntityExist(entity) then return nil end
              local ok, isNet = pcall(function() return NetworkGetEntityIsNetworked(entity) end)
              if not ok or not isNet then return nil end
              local ok2, nid = pcall(function() return safeNetworkGetNetworkIdFromEntity(entity) end)
              if ok2 and nid and nid ~= 0 then return nid end
              return nil
            end



            local stopEnabled, debugEnabled = true, true
            local pedData, lastPedNetId = {}, nil
            local lastPedEntity = nil          


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
              if not pedData[netId] then
                if generatePerson then
                  local ok2, p = pcall(generatePerson)
                  if ok2 and p then pedData[netId] = p else pedData[netId] = {} end
                else
                  pedData[netId] = {}
                end
              end

              lastPedNetId = netId
              lastPedEntity = pedEntity

              
              if setPedProtected then pcall(function() setPedProtected(netId, true) end) end
              pedData[netId].pulledInVehicle = false
              pedData[netId].forcedStop = false

              
              NetworkRequestControlOfEntity(pedEntity)
              SetEntityAsMissionEntity(pedEntity, true, true)
              SetBlockingOfNonTemporaryEvents(pedEntity, true)
              if holdPedAttention then pcall(function() holdPedAttention(pedEntity, false) end) end

              if notify then
                pcall(function() notify("stop_done","Stop","Ped stopped and detained on-foot.", 'success','person','') end)
              end

              
              pcall(function() TriggerEvent('__clientRequestPopulate') end)
            end


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


            local isDragging, draggedPed = false, nil
            local pullVeh = nil

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


            local function generatePerson()

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

            local ln = {
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

            local st = {
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
              local wanted = math.random() < 0.2
              return { name = name, dob = dob, address = addr,
                      signature = sig, wanted = wanted }
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

            local function getPedName(netId)
              local d = pedData[tostring(netId)]
              return (d and d.name) or "Unknown Unknown"
            end

            local function showIDCard(d)
              local status = d.wanted and " (WANTED)" or ""
              notify("show_id","ID Card",
                ("Name: %s%s\nDOB: %s\nAddress: %s\nSignature: %s")
                :format(d.name, status, d.dob, d.address, d.signature),
                'success','id-card','#38A169')
            end

            local function showID(netId)
              local d = pedData[tostring(netId)]
              if not d then
                return notify("no_id","ID Check","No ID data for this ped.",'error','id-badge','#C53030')
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
                
                local ok, ent2 = pcall(function() return NetworkGetEntityFromNetworkId(tonumber(lastPedNetId) or lastPedNetId) end)
                if ok and ent2 and ent2 ~= 0 and DoesEntityExist(ent2) then
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

              lastPedNetId = tonumber(nid) or nid
              lastPedEntity = ped

              if IsPedInAnyVehicle(ped, false) then
                setPedProtected(lastPedNetId, true)
                markPulledInVehicle(lastPedNetId, true)

                NetworkRequestControlOfEntity(ped)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                holdPedAttention(ped, true)

                monitorKeepInVehicle(lastPedNetId, GetVehiclePedIsIn(ped, false), 8000)
              end

              TriggerServerEvent('mdt:lookupID', lastPedNetId)
              
              if pedData[tostring(lastPedNetId)] or pedData[tostring(lastPedNetId)] then
                showIDCard(pedData[tostring(lastPedNetId)] or pedData[tostring(lastPedNetId)])
              end
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

            local function runPlate()
              local plateTxt = lastPlate
              local makeTxt, colorTxt = lastMake, lastColor

              if (not plateTxt or plateTxt == "") then
                local veh = nil
                if pullVeh and DoesEntityExist(pullVeh) then
                  veh = pullVeh
                else
                  if lib and lib.getClosestVehicle then
                    local v = lib.getClosestVehicle(GetEntityCoords(PlayerPedId()),6.0,false)
                    if type(v) == "table" then veh = v.vehicle or nil else veh = v end
                  end
                end

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
                
                TriggerServerEvent('mdt:lookupPlate', lastPlate, getPedName(lastPedNetId), lastMake or "", lastColor or "")
              else
                notify("plate_failed","Lookup Failed",
                      "No vehicle plate found. Pull someone over first or type one.",
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

            local function toggleMDT()
              if not isOpen then
                if not inEmergencyVehicle() then
                  return notify("mdt_err","MDT","Must be in emergency vehicle.",'error')
                end
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
              pedData[tostring(netId)] = pedData[tostring(netId)] or {}
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
              local startTime = GetGameTimer()
              Citizen.CreateThread(function()
                local deadline = startTime + durationMs
                local fastPhaseEnd = startTime + 3000
                while GetGameTimer() < deadline do
                  if not veh or not DoesEntityExist(veh) or not netId then break end
                  local ped = safeNetToPed(netId)
                  if not DoesEntityExist(ped) then break end

                  if not IsPedInAnyVehicle(ped, false) then
                    NetworkRequestControlOfEntity(ped)
                    ClearPedTasksImmediately(ped)
                    holdPedAttention(ped, false)
                  else
                    holdPedAttention(ped, true)
                  end

                  if GetGameTimer() < fastPhaseEnd then Citizen.Wait(100) else Citizen.Wait(Config.Timings.attackDelay) end
                end
              end)
            end

            holdPedAttention = function(ped, inVehicle)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
              local player = PlayerPedId()

              NetworkRequestControlOfEntity(ped)
              SetEntityAsMissionEntity(ped, true, true)
              SetBlockingOfNonTemporaryEvents(ped, true)

              if not inVehicle then
                ClearPedTasksImmediately(ped)
                TaskTurnPedToFaceEntity(ped, player, 1000)
                TaskLookAtEntity(ped, player, 1000000, 2048, 3)
                TaskStandStill(ped, 1000000)
              else
                SetPedKeepTask(ped, true)
              end

              SetPedCanRagdoll(ped, false)
              SetPedKeepTask(ped, true)
              dprint("holdPedAttention", tostring(ped), "inVehicle=", tostring(inVehicle))
            end

            releasePedAttention = function(ped)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return end
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

            -- attemptPedAttack(pedEntity, vehicleEntity, netId)
            -- returns true if the ped started an attack, false otherwise
            function attemptPedAttack(ped, veh, netId)
              if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

              -- if it's player-controlled, don't try to force an attack
              if IsPedAPlayer(ped) then return false end

              -- get configurable attack chance (fallback to 0.5)
              local attackChance = (Config and Config.Flee and Config.Flee.attackChance) or 0.5
              if math.random() >= attackChance then
                return false
              end

              -- try to obtain control of the ped
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

              -- clear tasks and prepare the ped
              ClearPedTasksImmediately(ped)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)

              local playerPed = PlayerPedId()

              -- If ped is in a vehicle, prefer shooting from vehicle for a short time
              if IsPedInAnyVehicle(ped, false) then
                -- try to equip a weapon if ped has none (best-effort, doesn't create new weapon)
                if not HasPedGotWeapon(ped, GetHashKey("WEAPON_PISTOL"), false) then
                  GiveWeaponToPed(ped, GetHashKey("WEAPON_PISTOL"), 30, false, true)
                end
                -- attempt to make them shoot at the player for a short duration
                TaskShootAtEntity(ped, playerPed, 8000, 0) -- 8 seconds
              else
                -- on foot: make them attack the player
                GiveWeaponToPed(ped, GetHashKey("WEAPON_PISTOL"), 30, false, true)
                TaskCombatPed(ped, playerPed, 0, 16)
              end

              -- mark in pedData that this ped attacked (helps other logic)
              if netId then
                pedData = pedData or {}
                pedData[tostring(netId)] = pedData[tostring(netId)] or {}
                pedData[tostring(netId)].attacked = true
              end

              dprint(("attemptPedAttack: ped=%s attacked (netId=%s)"):format(tostring(ped), tostring(netId)))
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

              local veh = CreateVehicle(vehHash, vx, vy, vz + 0.5, heading or 0.0, true, false)
              if not veh or veh == 0 then return nil, nil end

              SetEntityAsMissionEntity(veh, true, true)
              SetVehicleOnGroundProperly(veh)
              SetVehicleEngineOn(veh, true, true, true)
              SetVehicleDoorsLocked(veh, 1)

              local driver = nil
              if driverHash and requestModelSync(driverHash) then
                driver = CreatePedInsideVehicle(veh, 4, driverHash, -1, true, false)
                if driver and driver ~= 0 then
                  NetworkRequestControlOfEntity(driver)
                  SetEntityAsMissionEntity(driver, true, true)
                  SetBlockingOfNonTemporaryEvents(driver, true)
                  SetPedKeepTask(driver, true)
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

            local function createServiceBlip(veh, text)
              if not veh or veh == 0 then return nil end
              local b = AddBlipForEntity(veh)
              SetBlipSprite(b, 198)
              SetBlipNameToPlayerName(b, text or "Service")
              SetBlipColour(b, 3)
              SetBlipAsShortRange(b, true)
              return b
            end

            local function cleanupServiceEntities(entities)
              Citizen.CreateThread(function()
                Citizen.Wait(1000 * 45)
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

              local nx,ny,nz = px + 40.0, py + 40.0, pz
              local nodeX, nodeY, nodeZ, nodeH = GetClosestVehicleNodeWithHeading(nx, ny, nz)

              local sx, sy, sz = normalizeToXYZTriple(nodeX, nodeY, nodeZ, px+20.0, py+20.0, pz)
              if not sx then
                dprint("callAIEMS: invalid spawnPos", nodeX, nodeY, nodeZ, px,py,pz)
                return notify("ai_ems_fail","EMS","Invalid spawn position.",'error','heartbeat','#DD6B20')
              end
              local spawnPos = { x = sx, y = sy, z = sz }

              local veh, driver = spawnVehicleAndDriver("ambulance", "s_m_m_paramedic_01", spawnPos, nodeH or 0.0)
              if not veh or not driver then return notify("ai_ems_fail","EMS","Failed to spawn EMS vehicle/driver.",'error','heartbeat','#DD6B20') end

              SetVehicleSiren(veh, true)
              local blip = createServiceBlip(veh, "AI EMS")
              notify("ai_ems_called","AI EMS","Ambulance dispatched. ETA shortly.",'inform','heartbeat','#38A169')

              local targetVec = GetEntityCoords(player)
              driveToTarget(driver, veh, targetVec, 10.0, 6.0)

              
              
              local deadPeds = getNearbyDownedPeds(targetVec, 12.0, nil) 
              
              if #deadPeds > 0 and type(deadPeds[1]) == 'number' then
                local conv = {}
                for _,ph in ipairs(deadPeds) do
                  if DoesEntityExist(ph) then
                    table.insert(conv, { ped = ph, health = GetEntityHealth(ph) or 0 })
                  end
                end
                deadPeds = conv
              end

              if #deadPeds == 0 then
                notify("ai_ems_none","No Casualties","EMS arrived but found no dead humans nearby.",'warning','heartbeat','#DD6B20')
              else
                notify("ai_ems_work","EMS Arrived","EMS tending to casualties.",'success','heartbeat','#38A169')
                
                table.sort(deadPeds, function(a,b)
                  local ap = a and a.ped or a
                  local bp = b and b.ped or b
                  if not DoesEntityExist(ap) then return false end
                  if not DoesEntityExist(bp) then return true end
                  return Vdist(GetEntityCoords(ap), targetVec) < Vdist(GetEntityCoords(bp), targetVec)
                end)
                local chosenEntry = deadPeds[1]
                local chosenPed = nil
                if chosenEntry then
                  if type(chosenEntry) == 'number' then
                    chosenPed = chosenEntry
                  elseif type(chosenEntry) == 'table' then
                    chosenPed = chosenEntry.ped
                  end
                end

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



              cleanupServiceEntities({veh, driver})
              if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
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

              
              math.randomseed(GetGameTimer() + GetPlayerServerId(PlayerId()))
              local spawnDist = math.random(30, 50)
              local spawnAng = math.rad(math.random(0, 359))
              local sx_guess = px + math.cos(spawnAng) * spawnDist
              local sy_guess = py + math.sin(spawnAng) * spawnDist
              local nx, ny, nz, nodeH = GetClosestVehicleNodeWithHeading(sx_guess, sy_guess, pz)
              local sx, sy, sz = normalizeToXYZTriple(nx, ny, nz, sx_guess, sy_guess, pz)
              if not sx then
                nx,ny,nz,nodeH = GetClosestVehicleNodeWithHeading(px + 50.0, py + 50.0, pz)
                sx, sy, sz = normalizeToXYZTriple(nx, ny, nz, px+30.0, py+30.0, pz)
              end
              if not sx then
                dprint("callAICoroner: spawn point fallback failed for AI service")
                return notify("ai_coroner_fail","Coroner","Could not find spawn position.",'error','skull-crossbones','#DD6B20')
              end
              local spawnPos = { x = sx, y = sy, z = sz }

              
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
                safeForceExit(driver, veh)
                if type(dprint) == "function" then dprint((" [AI DEBUG] callAICoroner: driver in vehicle after force? %s"):format(tostring(IsPedInAnyVehicle(driver, false)))) end
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

              cleanupServiceEntities({veh, driver})
              if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
            end

            -- startFleeDrive(ped, veh)
            -- Makes `ped` drive away if they're in `veh`, otherwise makes them flee on foot.
            -- Returns true if a flee task was started, false if not.
            function startFleeDrive(ped, veh)
              if not ped or ped == 0 or not DoesEntityExist(ped) then
                dprint("startFleeDrive: invalid ped")
                return false
              end

              local playerPed = PlayerPedId()

              -- helper to request network control of an entity (best-effort)
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
                  -- locally owned entity: ensure it's mission entity so we can task it
                  SetEntityAsMissionEntity(ent, true, true)
                  return true
                end
              end

              -- On-vehicle flee
              if veh and veh ~= 0 and DoesEntityExist(veh) and IsPedInAnyVehicle(ped, false) then
                dprint(("startFleeDrive: ped %s in vehicle %s - attempting drive away"):format(tostring(ped), tostring(veh)))

                -- try to control vehicle and ped
                requestControl(veh, 1200)
                requestControl(ped, 800)

                -- ensure vehicle is driveable for the task
                SetVehicleEngineOn(veh, true, true, true)
                SetVehicleUndriveable(veh, false)

                -- Clear ped tasks then set keep task
                ClearPedTasksImmediately(ped)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)

                -- compute a target coord roughly away from player to give the ped somewhere to drive to
                local pedCoords = GetEntityCoords(ped)
                local plCoords = GetEntityCoords(playerPed)
                local dir = vector3(pedCoords.x - plCoords.x, pedCoords.y - plCoords.y, 0.0)
                local dlen = math.sqrt(dir.x * dir.x + dir.y * dir.y)
                if dlen < 1.0 then
                  -- if too close or same point, pick a forward vector from ped heading
                  local heading = GetEntityHeading(ped)
                  local hr = math.rad(heading)
                  dir = vector3(-math.sin(hr), math.cos(hr), 0.0)
                  dlen = 1.0
                end
                dir = vector3(dir.x / dlen, dir.y / dlen, 0.0)

                -- compute distant target point (200m away) and a slight Z raise to avoid ground issues
                local fleeDist = 200.0
                local tx = pedCoords.x + dir.x * fleeDist
                local ty = pedCoords.y + dir.y * fleeDist
                local tz = pedCoords.z + 1.0

                -- Task the ped to drive to the coord. Use a longrange variant if available.
                local speed = 45.0   -- target cruising speed (tweak as desired)
                local driveStyle = 786603 -- driving style flags (best-effort; tweak if you want calmer/aggressive)

                -- Best-effort use TaskVehicleDriveToCoordLongrange if present, otherwise fallback to TaskVehicleDriveToCoord
                if type(TaskVehicleDriveToCoordLongrange) == "function" then
                  TaskVehicleDriveToCoordLongrange(ped, veh, tx, ty, tz, speed, driveStyle, 1.0)
                else
                  TaskVehicleDriveToCoord(ped, veh, tx, ty, tz, speed, 1.0, driveStyle, 5.0, true)
                end

                -- mark pedData so other logic knows this ped fled
                pedData = pedData or {}
                local nid = tostring(NetworkGetNetworkIdFromEntity and NetworkGetNetworkIdFromEntity(ped) or ped)
                pedData[nid] = pedData[nid] or {}
                pedData[nid].fled = true

                dprint(("startFleeDrive: started vehicle flee for ped=%s -> target(%.1f,%.1f,%.1f)"):format(tostring(ped), tx, ty, tz))
                return true
              end

              -- On-foot flee
              if not IsPedInAnyVehicle(ped, false) then
                dprint(("startFleeDrive: ped %s fleeing on foot"):format(tostring(ped)))

                -- request control of ped
                requestControl(ped, 800)

                -- clear tasks and set flee attributes
                ClearPedTasksImmediately(ped)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 2, true) -- keep fleeing
                SetPedCanRagdoll(ped, true)
                SetPedKeepTask(ped, true)

                -- Prefer TaskSmartFleePed so ped runs away from player for a long time
                local fleeDistance = 200.0
                TaskSmartFleePed(ped, playerPed, fleeDistance, -1, false, false)

                -- Mark pedData as fled
                pedData = pedData or {}
                local nid = tostring(NetworkGetNetworkIdFromEntity and NetworkGetNetworkIdFromEntity(ped) or ped)
                pedData[nid] = pedData[nid] or {}
                pedData[nid].fled = true

                dprint(("startFleeDrive: started on-foot flee for ped=%s"):format(tostring(ped)))
                return true
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

              local nx,ny,nz,nodeH = GetClosestVehicleNodeWithHeading(px - 50.0, py + 10.0, pz)
              local sx, sy, sz = normalizeToXYZTriple(nx, ny, nz, px-30.0, py+10.0, pz)
              if not sx then
                dprint("callTow: invalid spawnPos", nx,ny,nz,px,py,pz)
                return notify("ai_tow_fail","Tow","Invalid spawn position.",'error','truck','#DD6B20')
              end
              local spawnPos = { x = sx, y = sy, z = sz }

              local towVeh, driver = spawnVehicleAndDriver("flatbed", "s_m_m_trucker_01", spawnPos, nodeH or 0.0)
              if not towVeh or not driver then return notify("ai_tow_fail","Tow","Failed to spawn tow truck.",'error','truck','#DD6B20') end

              local blip = createServiceBlip(towVeh, "Tow Truck")
              notify("ai_tow_called","Tow Truck","Tow truck en route. ETA shortly.",'inform','truck','#38A169')

              local targetVeh = getNearbyVehicleToTow(GetEntityCoords(player), 12.0)
              if not targetVeh or targetVeh == 0 then
                driveToTarget(driver, towVeh, GetEntityCoords(player), 10.0, 6.0)
                notify("ai_tow_none","No Vehicle","No suitable vehicle nearby to tow.",'warning','truck','#DD6B20')
                cleanupServiceEntities({towVeh, driver})
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end

              local targetPosX, targetPosY, targetPosZ = toXYZ(GetEntityCoords(targetVeh))
              if not targetPosX then
                dprint("callTow: invalid targetPos for towing", tostring(targetVeh))
                notify("ai_tow_miss","No Target","Vehicle disappeared before tow arrived.",'warning','truck','#DD6B20')
                cleanupServiceEntities({towVeh, driver})
                if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                return
              end
              local targetPos = vector3(targetPosX, targetPosY, targetPosZ)
              driveToTarget(driver, towVeh, targetPos, 10.0, 4.0)

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

              cleanupServiceEntities({towVeh, driver})
              if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
            end




            local function getPrimaryOccupant(veh)
              if not veh or not DoesEntityExist(veh) then return nil end
              local driver = GetPedInVehicleSeat(veh, -1)
              if driver and driver ~= 0 and not IsPedAPlayer(driver) then return driver end
              for seat = 0, 15 do
                local ped = GetPedInVehicleSeat(veh, seat)
                if ped and ped ~= 0 and not IsPedAPlayer(ped) then return ped end
              end
              return nil
            end

            function attemptPullOverAI(forceImmediate)
              dprint("attemptPullOverAI called, forceImmediate=", tostring(forceImmediate))
              if not inEmergencyVehicle() then
                return notify("pull_err","Pull-Over","Must be in an emergency vehicle to initiate pull-over.",'error')
              end

              local ped = PlayerPedId()
              local myVeh = GetVehiclePedIsIn(ped,false)
              if not myVeh or myVeh == 0 then
                return notify("pull_err","Pull-Over","You must be in your vehicle to request a pull-over.",'error')
              end

              local best = findVehicleAhead(20, 0.5)
              if not best then
                return notify("pull_err","Pull-Over","No vehicle ahead.",'error')
              end

              pullVeh = best
              dprint("attemptPullOverAI: pullVeh set to", tostring(pullVeh))

              if not forceImmediate then
                notify("pull_info","PULL-OVER","TURN ON EMERGENCY LIGHTS TO PULL VEHICLE OVER",'inform','car','')
              else
                notify("pull_info_force","PULL-OVER (FORCED)","Forcing pull-over (no lights required).",'inform','car','')
              end

              local waitDeadline = GetGameTimer() + 8000
              while GetGameTimer() < waitDeadline and not forceImmediate and not IsVehicleSirenOn(myVeh) do
                Citizen.Wait(100)
              end
              if not forceImmediate and not IsVehicleSirenOn(myVeh) then
                notify("pull_err","Pull-Over","Timed out waiting for lights/siren.",'error')
                pullVeh = nil
                return
              end

              

            do
              local driver = GetPedInVehicleSeat(pullVeh, -1)
              local netId = driver and driver ~= 0 and (safePedToNet(driver) or tostring(driver)) or nil
              local fleeChance = (Config and Config.Flee and Config.Flee.baseFleeChance) or 0.2
              if netId and pedData and pedData[tostring(netId)] then
                if pedData[tostring(netId)].wanted then fleeChance = math.max(fleeChance, (Config.Flee and Config.Flee.warrantFleeChance) or 0.6) end
                if pedData[tostring(netId)].suspended then fleeChance = math.max(fleeChance, (Config.Flee and Config.Flee.suspendedFleeChance) or 0.5) end
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
                  pedData[tostring(netId)] = generatePerson()
                  TriggerServerEvent('mdt:logID', tostring(netId), pedData[tostring(netId)])
                end
                lastPedNetId = tostring(netId)
                lastPedEntity = driver   

                setPedProtected(netId, true)
                pedData[tostring(netId)].forcedStop = forceImmediate and true or false
                markPulledInVehicle(netId, true)

                SetEntityAsMissionEntity(driver, true, true)
                SetBlockingOfNonTemporaryEvents(driver, true)
                monitorKeepInVehicle(netId, pullVeh, 30000)
              end

              local vehCoords = GetEntityCoords(pullVeh)
              local vehFwd = GetEntityForwardVector(pullVeh)
              local vehRight = vector3(vehFwd.y, -vehFwd.x, 0)
              local targetPos = vehCoords + vehFwd * 3.0 + vehRight * 1.5 
              local tx, ty, tz = targetPos.x, targetPos.y, targetPos.z

              if driver and driver ~= 0 and not IsPedAPlayer(driver) then
                local slowSpeed = 3.0 
                TaskVehicleDriveToCoordLongrange(driver, pullVeh, tx, ty, tz, slowSpeed, 786603, 3.0)
                notify("pull_slow","Pull-Over","Vehicle slowing down to pull over...",'inform','car-side','#4299E1')

                Citizen.CreateThread(function()
                  local done = false
                  local monitorDeadline = GetGameTimer() + 8000 
                  while not done and GetGameTimer() < monitorDeadline do
                    if not DoesEntityExist(pullVeh) then done = true break end
                    local curPos = GetEntityCoords(pullVeh)
                    local dist = #(curPos - vector3(tx,ty,tz))
                    local speed = GetEntitySpeed(pullVeh)
                    if dist < 2.0 or speed < 0.6 then
                      done = true
                      break
                    end
                    Citizen.Wait(150)
                  end

                  if not DoesEntityExist(pullVeh) then
                    pullVeh = nil
                    return
                  end

                  SetVehicleOnGroundProperly(pullVeh)
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
                      pedData[occNet] = generatePerson()
                      TriggerServerEvent('mdt:logID', occNet, pedData[occNet])
                    end
                    lastPedNetId = occNet
                    lastPedEntity = occupant

                    setPedProtected(occNet, true)
                    pedData[occNet].forcedStop = forceImmediate and true or false
                    markPulledInVehicle(occNet, true)

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
                    "Vehicle slowed and pulled over. Occupant detained in-vehicle. Press [Y] to reposition. Use vehicle menu to eject if needed.",
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


            -- Robust repositionInteractive with diagnostics + multiple move attempts
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

              -- debug state so we only log once per press
              local debugState = { up = false, down = false, left = false, right = false }

              while running do
                Citizen.Wait(0)

                if not DoesEntityExist(veh) then
                  notify("pull_repos_fail","Reposition Failed","Vehicle no longer exists.",'error','arrows-spin','#E53E3E')
                  return
                end

                -- block Q/E from other scripts but still detect them via IsDisabledControlPressed
                DisableControlAction(0, 44, true) -- Q
                DisableControlAction(0, 46, true) -- E

                local curStep = step
                local curRot = rotStep
                if IsControlPressed(0, 21) then -- LEFT SHIFT
                  curStep = fineStep
                  curRot = fineRotStep
                end

                -- ensure we have control before moving each tick (best-effort)
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

                -- helper to check if the vehicle actually moved (returns distance moved)
                local function movedDistance(oldCoords)
                  local now = GetEntityCoords(veh)
                  local dx = now.x - oldCoords.x
                  local dy = now.y - oldCoords.y
                  return math.sqrt(dx*dx + dy*dy)
                end

                -- function that tries multiple move methods and returns true if moved
                local function tryMove(target)
                  -- 1) Try SetEntityCoordsNoOffset
                  SetEntityCoordsNoOffset(veh, target.x, target.y, target.z, false, false, false)
                  Citizen.Wait(0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "SetEntityCoordsNoOffset"
                  end

                  -- 2) Try SetEntityCoords (with physics)
                  SetEntityCoords(veh, target.x, target.y, target.z, false, false, false, true)
                  Citizen.Wait(0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "SetEntityCoords"
                  end

                  -- 3) Try toggling collision and move (last resort)
                  local hadCollision = true
                  -- best-effort read: assume it has collision
                  SetEntityCollision(veh, false, false)
                  SetEntityCoordsNoOffset(veh, target.x, target.y, target.z, false, false, false)
                  Citizen.Wait(0)
                  local moved = movedDistance(pos) > 0.0005
                  SetEntityCollision(veh, true, true)
                  if moved then
                    return true, "ToggleCollision+SetEntityCoordsNoOffset"
                  end

                  -- 4) As a final physics nudge, set a short velocity in direction, then zero it
                  SetEntityVelocity(veh, flatFwd.x * 5.0, flatFwd.y * 5.0, 0.0)
                  Citizen.Wait(50)
                  SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                  if movedDistance(pos) > 0.0005 then
                    return true, "VelocityNudge"
                  end

                  return false, "AllFailed"
                end

                -- Movement input detection: check both normal and disabled controls so we catch input either way
                local upPressed = IsControlPressed(0, 172) or IsDisabledControlPressed(0, 172)
                local downPressed = IsControlPressed(0, 173) or IsDisabledControlPressed(0, 173)
                local leftPressed = IsControlPressed(0, 174) or IsDisabledControlPressed(0, 174)
                local rightPressed = IsControlPressed(0, 175) or IsDisabledControlPressed(0, 175)

                -- UP
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

                -- DOWN
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

                -- LEFT / RIGHT strafing
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

                -- Rotation handling (Q / E). Detect via disabled control so other scripts don't catch it
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

                -- Confirm (ENTER) or alternative accept
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

                -- Cancel (ESC)
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
              if netId and pedData[tostring(netId)] and (pedData[tostring(netId)].pulledProtected or pedData[tostring(netId)].pulledInVehicle) then
                notify("protected","Protected","This ped is protected while pulled. Use vehicle eject option to forcibly remove them.", 'warning','ban','#DD6B20')
                return false
              end

              NetworkRequestControlOfEntity(ped)
              NetworkRequestControlOfEntity(veh)

              ClearPedTasksImmediately(ped)
              TaskLeaveVehicle(ped, veh, 0)
              SetBlockingOfNonTemporaryEvents(ped, false)

              Citizen.CreateThread(function()
                local deadline = GetGameTimer() + 3000
                while GetGameTimer() < deadline do
                  if not IsPedInAnyVehicle(ped, false) then
                    ClearPedTasksImmediately(ped)
                    holdPedAttention(ped, false)
                    SetPedAsNoLongerNeeded(ped)
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


            if lib and lib.registerContext then
              lib.registerContext({
                id='police_mainai',
                title='**Police Actions**',
                canClose=true,
                options={
                  { title='MDT (Records & Plate)', icon='search', arrow=true, onSelect=function() lib.showContext('police_mdt') end },
                  { title='AI Services', icon='heartbeat', arrow=true, onSelect=function() lib.showContext('police_ai') end },
                  { title='Ped Interaction', icon='user', arrow=true, onSelect=function() lib.showContext('police_ped') end },
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
                  { title='Reports', icon='file-alt', onSelect=function() SendNUIMessage({ action='openSection', section='reports' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
                  { title='Warrants', icon='gavel', onSelect=function() SendNUIMessage({ action='openSection', section='warrants' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
                  { title='Dispatch', icon='broadcast-tower', onSelect=function() SendNUIMessage({ action='openSection', section='dispatch' }); if not isOpen then isOpen=true; SetNuiFocus(true,true); SendNUIMessage({action='open'}) end end },
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
                  { title='Issue Citation', icon='ticket-alt', onSelect=function() dprint("Context: Issue Citation selected"); doCitation() end },
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
                id='vehicle_interact',
                title='🚗 Vehicle Interaction',
                menu='police_mainai',
                canClose=true,
                options={
            { title='Finish Pull-Over', icon='car', description='Let AI car go', onSelect=function()
                dprint("Context: Finish Pull-Over selected")
                if not pullVeh or not DoesEntityExist(pullVeh) then return end

                local occ = getPrimaryOccupant(pullVeh)
                if occ and occ ~= 0 then
                  local n = safePedToNet(occ)
                  if n then
                    setPedProtected(n, false)
                    markPulledInVehicle(n, false)
                    if pedData[n] then pedData[n].forcedStop = nil end
                  end

                  
                  SetVehicleEngineOn(pullVeh, true, true, true)
                  SetVehicleHandbrake(pullVeh, false)
                  SetVehicleDoorsLocked(pullVeh, 1)
                  SetVehicleUndriveable(pullVeh, false)

                  
                  releasePedAttention(occ)
                  SetBlockingOfNonTemporaryEvents(occ, false)

                  
                  NetworkRequestControlOfEntity(occ)
                  NetworkRequestControlOfEntity(pullVeh)

                  
                  local start = GetGameTimer()
                  while not NetworkHasControlOfEntity(occ) and (GetGameTimer() - start) < 1000 do
                    NetworkRequestControlOfEntity(occ); Citizen.Wait(10)
                  end
                  start = GetGameTimer()
                  while not NetworkHasControlOfEntity(pullVeh) and (GetGameTimer() - start) < 1000 do
                    NetworkRequestControlOfEntity(pullVeh); Citizen.Wait(10)
                  end

                  
                  if not IsPedInVehicle(occ, pullVeh, true) or GetPedInVehicleSeat(pullVeh, -1) ~= occ then
                    TaskWarpPedIntoVehicle(occ, pullVeh, -1) 
                    Citizen.Wait(150)
                  end

                  
                  SetDriverAbility(occ, Config.Flee.driverAbility or 1.0)        
                  SetDriverAggressiveness(occ, Config.Flee.driverAggressiveness or 0.7) 
                  SetPedKeepTask(occ, true)

                  
                  
                  local occNet_local = safePedToNet(occ) or tostring(occ)
                  if pedData and pedData[tostring(occNet_local)] and (pedData[tostring(occNet_local)].wanted or pedData[tostring(occNet_local)].suspended) then
                    if not attemptPedAttack(occ, pullVeh, occNet_local) then
                      startFleeDrive(occ, pullVeh)
                    end
                  else
                    TaskVehicleDriveWander(occ, pullVeh, Config.Wander.driveSpeed, Config.Wander.driveStyle)
                  end
                

                  
                  Citizen.CreateThread(function()
                    Citizen.Wait(Config.Timings.postPullCheck) 

                    if DoesEntityExist(occ) and DoesEntityExist(pullVeh) then
                      local speed = GetEntitySpeed(pullVeh)
                      dprint(("Finish Pull-Over: speed after wander check = %.2f"):format(speed))
                      if speed < 1.0 then
                        dprint("Finish Pull-Over: wander didn't start — using drive-to-coord fallback")

                        
                        local dest = GetOffsetFromEntityInWorldCoords(pullVeh, 0.0, 200.0, 0.0)
                        
                        
                        local model = GetEntityModel(pullVeh)
                        TaskVehicleDriveToCoord(occ, pullVeh, dest.x, dest.y, dest.z, 20.0, 1.0, model, 786603, 5.0, true)

                        
                        Citizen.Wait(8000)
                        if DoesEntityExist(occ) then SetPedKeepTask(occ, false) end
                      else
                        
                        Citizen.Wait(5000)
                        if DoesEntityExist(occ) then SetPedKeepTask(occ, false) end
                      end
                    end
                  end)
                else
                  
                  SetVehicleEngineOn(pullVeh, true, true, true)
                  SetVehicleHandbrake(pullVeh, false)
                  SetVehicleDoorsLocked(pullVeh, 1)
                end

                pullVeh = nil
                notify("pull_finish","Pull-Over","Complete. Vehicle may leave.",'success')
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
            else
              dprint("lib.registerContext not available; context menus not registered")
            end

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

              SendNUIMessage({
                action        = 'idResult',
                netId         = payload and payload.netId or "",
                name          = payload and payload.name or "",
                licenseStatus = payload and payload.licenseStatus or "",
                records       = payload and payload.records or {}
              })

              if payload and payload.netId then
                local nid = tonumber(payload.netId) or payload.netId
                Citizen.CreateThread(function()
                  Citizen.Wait(3000)
                  if nid and pedData[nid] and not pedData[nid].forcedStop then
                    setPedProtected(nid, false)
                    markPulledInVehicle(nid, false)
                  end
                end)
              end
            end)

            RegisterNetEvent('mdt:recordsResult')
            AddEventHandler('mdt:recordsResult', function(rows, targetType)
              
              SendNUIMessage({
                action = 'recordsResult',
                records = rows,
                target_type = targetType
              })
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
                if info and info.pulledProtected and not info.forcedStop then
                  local ped = safeNetToPed(tonumber(netId) or netId)
                  if DoesEntityExist(ped) then
                    releasePedAttention(ped)
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
            RegisterCommand('aipolicemenu', function() if lib and lib.showContext then lib.showContext('police_mainai') else dprint("policemenu: lib.showContext missing") end end)
            RegisterKeyMapping('aipolicemenu','Open Police Actions','keyboard','F6')


            RegisterCommand('stopAI', function()
              local player = PlayerPedId()
              if not IsControlPressed(0, 21) then 
                if type(notify) == "function" then
                  notify("stop_require", "Hold Modifier", "You must start holding LEFT SHIFT while pressing E to initiate a stop.", 'warning', 'ban', '#DD6B20')
                end
                return
              end

              local holdStart = GetGameTimer()
              local holdDuration = 3000 

              if type(notify) == "function" then
                notify("stop_hold", "Preparing Stop", "Keep holding LEFT SHIFT for 3 seconds to confirm the stop...", 'inform', 'hourglass', '#4299E1')
              end

              while (GetGameTimer() - holdStart) < holdDuration do
                if not IsControlPressed(0, 21) then
                  if type(notify) == "function" then
                    notify("stop_hold_fail", "Hold Aborted", "You released LEFT SHIFT too early. Stop cancelled.", 'error', 'ban', '#E53E3E')
                  end
                  return
                end
                Citizen.Wait(Config.Timings.shortWait)
              end

              
              local inVeh = IsPedInAnyVehicle(player, false)
              if inVeh and type(inEmergencyVehicle) == 'function' and inEmergencyVehicle() then
                if type(attemptPullOverAI) == 'function' then
                  attemptPullOverAI(false)
                end
              else
                if type(attemptStopOnFoot) == 'function' then
                  attemptStopOnFoot(false)
                end
              end
            end)
            RegisterKeyMapping('stopAI', 'Stop/Traffic Stop (Hold LEFT SHIFT + E for 3s)', 'keyboard', 'E')RegisterKeyMapping('stopAI', 'Stop/Traffic Stop (LEFT SHIFT + E)', 'keyboard', 'E')



            RegisterCommand('cancelStopsCmd', function()
              cancelNonForcedStops()
            end)
            RegisterKeyMapping('cancelStopsCmd', 'Cancel stops (LEFT CTRL)', 'keyboard', 'LEFTCTRL')

            RegisterCommand('showid', function() if lastPedNetId then showIDSafely(lastPedNetId) else dprint("showid: no lastPedNetId") end end)
            RegisterKeyMapping('showid','Show Last Ped ID','keyboard','J')

            Citizen.CreateThread(function()
              while true do
                Citizen.Wait(0)
                if IsControlJustReleased(0,249) then 
                  dprint("G pressed -> tryCuffPed")
                  tryCuffPed()
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
              if math.random() < 0.2 then
                notify("search_fail","Interrupted","Search interrupted, but ped remains.",'error','person-running','#E53E3E')
                holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
              else
                notify("search_ok","Search","Nothing found.",'success','magnifying-glass','#38A169')
                holdPedAttention(ped, IsPedInAnyVehicle(ped, false))
              end
            end

            function doCitation()
              dprint("doCitation called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("doCitation: no ped resolved")
                return notify("cite_no","No Ped","None stopped.",'error','ticket','#E53E3E')
              end

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
                dprint("sendCitation:", tostring(lastPedNetId), tostring(reason), tostring(fine))
                TriggerServerEvent('police:issueCitation',
                  lastPedNetId, reason, fine, getPedName(lastPedNetId))
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

            function doArrest()
              dprint("doArrest called")
              local ped, nid = resolveLastPed()
              if not ped then
                dprint("doArrest: no ped resolved")
                return notify("arrest_no","No Ped","None stopped.",'error','handcuffs','#E53E3E')
              end

              safeProgressBar({ duration=2000, label="Arresting" })

              if not DoesEntityExist(ped) then
                lastPedNetId = nil
                lastPedEntity = nil
                dprint("doArrest: ped no longer exists mid-arrest")
                return notify("arrest_no_exist","No Ped","Target no longer exists.",'error','handcuffs','#E53E3E')
              end

              NetworkRequestControlOfEntity(ped); SetEntityAsMissionEntity(ped,true,true)
              RequestAnimDict("mp_arresting")
              while not HasAnimDictLoaded("mp_arresting") do Citizen.Wait(0) end
              TaskPlayAnim(ped,"mp_arresting","idle",8.0,-8.0,3000,49,0); Citizen.Wait(3000)

              SetEnableHandcuffs(ped, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)
              holdPedAttention(ped, IsPedInAnyVehicle(ped, false))

              local fullName = nil
              local dob = ""
              if lastPedNetId and pedData[tostring(lastPedNetId)] then
                fullName = pedData[tostring(lastPedNetId)].name
                dob = pedData[tostring(lastPedNetId)].dob or ""
              else
                fullName = getPedName(lastPedNetId)
              end

              TriggerServerEvent('police:arrestPed', lastPedNetId, fullName, dob)

              notify("arrest_ok","Arrest","Ped cuffed. Removing from world and logged.",'success','police-badge','#38A169')

              Citizen.CreateThread(function()
                Citizen.Wait(500)

                if not DoesEntityExist(ped) then
                  lastPedNetId = nil
                  lastPedEntity = nil
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

                if lastPedNetId then pedData[tostring(lastPedNetId)] = nil end
                lastPedNetId = nil
                lastPedEntity = nil

                notify("arrest_final","Arrest Complete","Ped removed and arrest logged.",'success','police-badge','#38A169')
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

              NetworkRequestControlOfEntity(ped)
              ClearPedTasksImmediately(ped)
              releasePedAttention(ped)

              local netId = safePedToNet(ped)
              if netId then
                setPedProtected(netId, false)
                markPulledInVehicle(netId, false)
                if pedData[tostring(netId)] then pedData[tostring(netId)].forcedStop = nil end
              end

              SetEntityAsMissionEntity(ped,false,false)

              if IsPedInAnyVehicle(ped, false) then
                SetBlockingOfNonTemporaryEvents(ped, false)
                SetPedKeepTask(ped, false)
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
                end
              else
                TaskWanderStandard(ped, 10.0, 10)
              end

              SetEnableHandcuffs(ped, false)
              SetPedCanRagdoll(ped, true)
              SetPedKeepTask(ped, false)

              notify("rel_ok","Released","Ped is free.",'success','unlock','#38A169')
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
                    
                    SetEnableHandcuffs(ped, false)
                    SetBlockingOfNonTemporaryEvents(ped, false)
                    SetPedCanRagdoll(ped, true)
                    SetPedKeepTask(ped, false)
                    Citizen.Wait(Config.Timings.shortWait)
                    SetPedKeepTask(ped, true)
                    
                    local netId_local = safePedToNet(ped) or tostring(ped)
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

              
              SetEnableHandcuffs(ped, true)
              SetBlockingOfNonTemporaryEvents(ped, true)
              SetPedCanRagdoll(ped, false)

              notify("cuff_ok","Cuffed","Ped is handcuffed.",'success','lock','#38A169')

              draggedPed = ped
              isDragging = false

              
              local sendNet = nil
              if lastPedNetId then
                sendNet = lastPedNetId
              else
                local maybe = safePedToNet(ped)
                if maybe and maybe ~= 0 then sendNet = maybe end
              end

              dprint("tryCuffPed: sending server event police:cuffPed with", tostring(sendNet))
              TriggerServerEvent('police:cuffPed', sendNet)
            end


            function toggleDragPed()
              dprint("toggleDragPed called, draggedPed=", tostring(draggedPed))
              if not draggedPed or not DoesEntityExist(draggedPed) then
                dprint("toggleDragPed: no dragged ped")
                return notify("drag_no","No Cuffed","No one cuffed.",'error','person-walking','#E53E3E')
              end
              local player = PlayerPedId()
              NetworkRequestControlOfEntity(draggedPed)
              if not isDragging then
                AttachEntityToEntity(draggedPed,player,0,0.0,0.6,-0.5,
                  0,0,0,false,false,false,false,2,true)
                isDragging = true
                notify("drag_start","Dragging","Ped in front.",'inform','arrows-spin','#4299E1')
                dprint("toggleDragPed: started dragging", tostring(draggedPed))
              else
                DetachEntity(draggedPed,true,false)
                isDragging = false
                notify("drag_stop","Released","Ped released.",'success','arrows-spin','#38A169')
                holdPedAttention(draggedPed, IsPedInAnyVehicle(draggedPed, false))
                dprint("toggleDragPed: stopped dragging", tostring(draggedPed))
              end
            end

            function seatPed(idx)
              dprint("seatPed called idx=", tostring(idx))
              if not draggedPed or not DoesEntityExist(draggedPed) then
                dprint("seatPed: no draggedPed")
                return notify("seat_no","No Ped","None to seat.",'error','car-side','#E53E3E')
              end
              local coords = GetEntityCoords(PlayerPedId())
              local veh = nil
              if lib and lib.getClosestVehicle then
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

              NetworkRequestControlOfEntity(draggedPed)
              TaskWarpPedIntoVehicle(draggedPed,veh,idx)
              isDragging = false; draggedPed = nil
              notify("seat_ok","Seated","Seat "..idx..".",'success','car-side','#38A169')
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
                if lib and lib.showContext then
                    lib.showContext('police_mainai')
                else
                    print("^1[az-police]^7 lib.showContext missing")
                end
            end)


            RegisterCommand('policemenu', function()
                if lib and lib.showContext then
                    lib.showContext('police_mainai')
                else
                    print("^1[policemenu]^7 lib.showContext missing")
                end
            end, false)

            CreateThread(function()
                local options = {
                    {
                        name = 'open_police_menu',
                        label = 'Open Police Menu',
                        icon = 'fa-solid fa-clipboard-list',
                        distance = TARGET_DISTANCE or 2.5,
                        onSelect = function(data)
                            if lib and lib.showContext then
                                lib.showContext('police_mainai')
                            else
                                dprint("policemenu: lib.showContext missing")
                            end
                        end
                    }
                }

                
                Citizen.Wait(2000)
                pcall(function() exports.ox_target:addGlobalPed(options) end)
            end)


            AddEventHandler('onResourceStop', function(resName)
                if GetCurrentResourceName() ~= resName then return end
                pcall(function() exports.ox_target:removeGlobalPed({'open_police_menu'}) end)
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

              
              requestControl(responderPed, 2000)

              
              if IsPedInAnyVehicle(responderPed, false) then
                print(" [AI DEBUG] responder is in vehicle, forcing exit...")
                forcePedExitVehicle(responderPed, vehicle)
                Citizen.Wait(200)
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
              print(" [AI DEBUG] responder reached casualty (or timed out) distance:", #(GetEntityCoords(responderPed) - GetEntityCoords(casualty)))

              
              local ccoords = GetEntityCoords(casualty)
              TaskTurnPedToFaceCoord(responderPed, ccoords.x, ccoords.y, ccoords.z, 500)
              if requestControl(responderPed, 500) then
                TaskStartScenarioInPlace(responderPed, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
                print(" [AI DEBUG] started medic scenario")
              end

              Citizen.Wait(SERVICE_TIME_MS)
              ClearPedTasksImmediately(responderPed)
              print(" [AI DEBUG] finished treatment wait, evaluating outcome...")

              
              math.randomseed(math.floor(GetGameTimer() + GetEntityCoords(responderPed).x * 1000))
              local roll = math.random(1, 100)
              print((" [AI DEBUG] revive roll=%d (need <= %d to revive)"):format(roll, REVIVE_CHANCE))
              if roll <= REVIVE_CHANCE then
                if DoesEntityExist(casualty) then
                  requestControl(casualty, 500)
                  ClearPedTasksImmediately(casualty)
                  ResurrectPed(casualty)
                  SetEntityHealth(casualty, 200)
                  TaskStandStill(casualty, 1000)
                  print(" [AI DEBUG] casualty revived and healed.")
                end
                if type(notify) == "function" then
                  notify("ai_medic", "Revived", "Patient stabilized by AI medic.", 'success', 'heart', '#22c55e')
                end
              else
                if DoesEntityExist(casualty) then
                  requestControl(casualty, 500)
                  SetEntityHealth(casualty, 0)
                  if not IsEntityDead(casualty) then ApplyDamageToPed(casualty, 1000, false) end
                  print(" [AI DEBUG] casualty set to dead.")
                end
                if type(notify) == "function" then
                  notify("ai_medic", "Patient Deceased", "AI medic could not revive the patient.", 'error', 'skull', '#ef4444')
                end
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



            -- put this once (near the bottom, after repositionInteractive is defined)
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
    end)
end)
