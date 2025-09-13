-- client.lua (full, minus generatePerson())

local stopEnabled, debugEnabled = true, true
local pedData, lastPedNetId = {}, nil
local lastPedEntity = nil          
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

local HOLD_SURRENDER_MS = 1500 
local HOLD_PULL_MS = 800       

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
  local d = pedData[netId]
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
  local d = pedData[netId]
  if not d then
    return notify("no_id","ID Check","No ID data for this ped.",'error','id-badge','#C53030')
  end
  TriggerServerEvent('mdt:lookupID', netId)
  showIDCard(d)
end

local function resolveLastPed()
  dprint("resolveLastPed start", "lastPedNetId=", tostring(lastPedNetId), "lastPedEntity=", tostring(lastPedEntity))
  
  if not lastPedNetId and not lastPedEntity then
    dprint("resolveLastPed: nothing stored")
    return nil, nil
  end

  local nid = tonumber(lastPedNetId) or lastPedNetId
  if nid then
    local ped = NetToPed(nid)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
      lastPedEntity = ped
      lastPedNetId = nid
      dprint("resolveLastPed: resolved via NetToPed", nid, ped)
      return ped, nid
    else
      dprint("resolveLastPed: NetToPed returned nil or invalid for", nid)
    end
  end

  if lastPedEntity and DoesEntityExist(lastPedEntity) then
    local derived = PedToNet(lastPedEntity)
    if derived and derived ~= 0 then
      lastPedNetId = tonumber(derived) or derived
      dprint("resolveLastPed: derived netId from local entity", lastPedNetId)
      return lastPedEntity, lastPedNetId
    else
      dprint("resolveLastPed: PedToNet failed; returning local entity without netId")
      return lastPedEntity, nil
    end
  end

  dprint("resolveLastPed: clearing stale values")
  lastPedNetId = nil
  lastPedEntity = nil
  return nil, nil
end

local function showIDSafely(netId)
  dprint("showIDSafely called with netId=", tostring(netId))
  local ped, nid

  if netId then
    nid = tonumber(netId) or netId
    ped = NetToPed(nid)
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
  
  if pedData[lastPedNetId] or pedData[tostring(lastPedNetId)] then
    showIDCard(pedData[lastPedNetId] or pedData[tostring(lastPedNetId)])
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
  pedData[netId] = pedData[netId] or {}
  pedData[netId].pulledProtected = val and true or false
  pedData[netId].pulledInVehicle = pedData[netId].pulledInVehicle or false
  if not val then
    pedData[netId].forcedStop = nil
  end
  dprint("setPedProtected", tostring(netId), tostring(val))
end

markPulledInVehicle = function(netId, val)
  if not netId then return end
  pedData[netId] = pedData[netId] or {}
  pedData[netId].pulledInVehicle = val and true or false
  if val then
    pedData[netId].pulledProtected = true
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
      local ped = NetToPed(netId)
      if not DoesEntityExist(ped) then break end

      if not IsPedInAnyVehicle(ped, false) then
        NetworkRequestControlOfEntity(ped)
        ClearPedTasksImmediately(ped)
        holdPedAttention(ped, false)
      else
        holdPedAttention(ped, true)
      end

      if GetGameTimer() < fastPhaseEnd then Citizen.Wait(100) else Citizen.Wait(300) end
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

-- ===== AI SERVICE HELPERS & IMPLEMENTATIONS (EMS / Coroner / Animal / Tow) =====
-- ===== AI SERVICE HELPERS & IMPLEMENTATIONS (EMS / Coroner / Animal / Tow) =====

-- safer numeric coercion helper
local function num(v)
  if v == nil then return nil end
  if type(v) == "number" then return v end
  local ok, res = pcall(function() return tonumber(v) end)
  if ok and res ~= nil then return res end
  return nil
end

-- robust extractor: accepts vector3 userdata, {x=..,y=..,z=..}, numeric array, or returns nils.
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

  -- try .x/.y/.z via pcall (for userdata/vector3)
  local ok, x = pcall(function() return v.x end)
  if ok and x ~= nil then
    local ok2, y = pcall(function() return v.y end)
    local ok3, z = pcall(function() return v.z end)
    if ok2 and ok3 and y ~= nil and z ~= nil then
      return num(x), num(y), num(z)
    end
  end

  -- fallback: numeric indices via pcall
  ok, x = pcall(function() return v[1] end)
  if ok and x ~= nil then
    local ok2, y = pcall(function() return v[2] end)
    local ok3, z = pcall(function() return v[3] end)
    if ok2 and ok3 and y ~= nil and z ~= nil then
      return num(x), num(y), num(z)
    end
  end

  -- final fallback: try to parse numbers from tostring(v)
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

-- Normalizer: try many combinations to return numeric triple (x,y,z).
-- Accepts either (a,b,c) where any may be vector3/table/number, or a single vector-like.
local function normalizeToXYZTriple(a,b,c, fallbackX, fallbackY, fallbackZ)
  -- 1) If 'a' is vector-like, prefer it
  local ax,ay,az = toXYZ(a)
  if ax and ay and az then return ax, ay, az end

  -- 2) If 'b' is vector-like
  local bx,by,bz = toXYZ(b)
  if bx and by and bz then return bx, by, bz end

  -- 3) If 'c' is vector-like
  local cx,cy,cz = toXYZ(c)
  if cx and cy and cz then return cx, cy, cz end

  -- 4) Fallback to numeric values from a,b,c
  local nx, ny, nz = num(a), num(b), num(c)

  -- 5) Fill missing from fallbacks if provided
  nx = nx or num(fallbackX)
  ny = ny or num(fallbackY)
  nz = nz or num(fallbackZ)

  if nx and ny and nz then return nx, ny, nz end

  -- 6) If 'a' was vector-like but toXYZ failed earlier (rare), try parsing tostring again explicitly
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

-- safeVector3 factory: returns a plain table {x=..., y=..., z=...} if resolvable, otherwise nil.
-- Use normalizeToXYZTriple when you want to accept mixed args and fallbacks.
local function safeVector3(a,b,c, fallbackX, fallbackY, fallbackZ)
  local x,y,z = normalizeToXYZTriple(a,b,c, fallbackX, fallbackY, fallbackZ)
  if not x or not y or not z then
    dprint("safeVector3: invalid components", "a=", tostring(a), "b=", tostring(b), "c=", tostring(c), "-> resolved:", tostring(x), tostring(y), tostring(z))
    return nil
  end
  -- return plain table so other helpers that call toXYZ will accept it reliably
  return { x = x, y = y, z = z }
end

-- Request model, wait briefly for sync
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

-- Spawn a vehicle and optional driver at a safe spawnCoords (table/vector3 allowed)
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

-- Find dead peds (humanOnly = true -> humans only; false -> animals only; nil -> any)
local function getNearbyDeadPeds(center, radius, humanOnly)
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

-- Find nearby non-player vehicle to tow, returns vehicle entity or nil
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

-- Drive driver/veh towards targetVec (accepts vector3/table/numeric triple)
local function driveToTarget(driver, veh, targetVec, speed, arriveRadius, driveMode)
  speed = speed or 8.0
  arriveRadius = arriveRadius or 6.0
  driveMode = driveMode or 786603

  if not driver or driver == 0 or not veh or veh == 0 then return end

  -- Resolve target vector safely
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

-- AI EMS
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

  local deadPeds = getNearbyDeadPeds(targetVec, 8.0, true)
  if #deadPeds == 0 then
    notify("ai_ems_none","No Casualties","EMS arrived but found no dead humans nearby.",'warning','heartbeat','#DD6B20')
  else
    notify("ai_ems_work","EMS Arrived","EMS tending to casualties.",'success','heartbeat','#38A169')
    for _, ped in ipairs(deadPeds) do
      if DoesEntityExist(ped) then
        NetworkRequestControlOfEntity(ped)
        SetEntityAsMissionEntity(ped, true, true)
        local maxHp = GetEntityMaxHealth(ped) or 200
        SetEntityHealth(ped, maxHp > 50 and maxHp or 200)
        ClearPedTasksImmediately(ped)
        TaskStandStill(ped, 2000)
        if DoesEntityExist(driver) then
          NetworkRequestControlOfEntity(driver)
          TaskLeaveVehicle(driver, veh, 0)
          Citizen.Wait(600)
          TaskGoToEntity(driver, ped, -1, 2.0, 2.0, 0, 0)
          Citizen.Wait(800)
          RequestAnimDict("mini@triathlon")
          if HasAnimDictLoaded("mini@triathlon") then
            TaskPlayAnim(driver, "mini@triathlon", "idle_a", 8.0, -8, 4000, 49, 0, false, false, false)
            Citizen.Wait(1500)
          end
          TaskEnterVehicle(driver, veh, -1, -1, 2.0, 1, 0)
        end
        notify("ai_ems_revived","Revived","An NPC casualty was revived by EMS.",'success','heartbeat','#38A169')
      end
    end
  end

  cleanupServiceEntities({veh, driver})
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

-- AI Coroner
callAICoroner = function()
  local player = PlayerPedId()
  local px,py,pz = toXYZ(GetEntityCoords(player))
  if not px then
    return notify("ai_coroner_fail","Coroner","Could not determine player position.",'error','skull-crossbones','#DD6B20')
  end

  local nx,ny,nz,nodeH = GetClosestVehicleNodeWithHeading(px + 50.0, py + 50.0, pz)
  local sx, sy, sz = normalizeToXYZTriple(nx, ny, nz, px+30.0, py+30.0, pz)
  if not sx then
    dprint("callAICoroner: invalid spawnPos", nx,ny,nz,px,py,pz)
    return notify("ai_coroner_fail","Coroner","Invalid spawn position.",'error','skull-crossbones','#DD6B20')
  end
  local spawnPos = { x = sx, y = sy, z = sz }

  local veh, driver = spawnVehicleAndDriver("rumpo", "s_m_m_doctor_01", spawnPos, nodeH or 0.0)
  if not veh or not driver then return notify("ai_coroner_fail","Coroner","Failed to spawn coroner vehicle.",'error','skull-crossbones','#DD6B20') end

  local blip = createServiceBlip(veh, "Coroner")
  notify("ai_coroner_called","Coroner","Coroner van dispatched. ETA shortly.",'inform','skull-crossbones','#38A169')

  driveToTarget(driver, veh, GetEntityCoords(player), 8.0, 6.0)

  local deadPeds = getNearbyDeadPeds(GetEntityCoords(player), 8.0, true)
  if #deadPeds == 0 then
    notify("ai_coroner_none","No Bodies","No dead humans found for Coroner to pick up.",'warning','skull-crossbones','#DD6B20')
  else
    notify("ai_coroner_work","Coroner Arrived","Coroner picking up bodies.",'success','skull-crossbones','#38A169')
    for _, ped in ipairs(deadPeds) do
      if DoesEntityExist(ped) then
        NetworkRequestControlOfEntity(ped)
        SetEntityAsMissionEntity(ped, true, true)
        ClearPedTasksImmediately(ped)
        Citizen.Wait(500)
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
        if DoesEntityExist(ped) then DeletePed(ped) end
      end
    end
    notify("ai_coroner_done","Bodies Removed","Coroner removed the deceased.",'success','skull-crossbones','#38A169')
  end

  cleanupServiceEntities({veh, driver})
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

-- AI Animal Control
callAIAnimalControl = function()
  local player = PlayerPedId()
  local px,py,pz = toXYZ(GetEntityCoords(player))
  if not px then
    return notify("ai_animal_fail","Animal Ctrl","Could not determine player position.",'error','paw','#DD6B20')
  end

  local nx,ny,nz,nodeH = GetClosestVehicleNodeWithHeading(px + 50.0, py - 50.0, pz)
  local sx, sy, sz = normalizeToXYZTriple(nx, ny, nz, px+30.0, py-30.0, pz)
  if not sx then
    dprint("callAIAnimalControl: invalid spawnPos", nx,ny,nz,px,py,pz)
    return notify("ai_animal_fail","Animal Ctrl","Invalid spawn position.",'error','paw','#DD6B20')
  end
  local spawnPos = { x = sx, y = sy, z = sz }

  local veh, driver = spawnVehicleAndDriver("boxville", "s_m_m_gardener_01", spawnPos, nodeH or 0.0)
  if not veh or not driver then return notify("ai_animal_fail","Animal Ctrl","Failed to spawn animal control van.",'error','paw','#DD6B20') end

  local blip = createServiceBlip(veh, "Animal Control")
  notify("ai_animal_called","Animal Control","Animal Control dispatched. ETA shortly.",'inform','paw','#38A169')

  driveToTarget(driver, veh, GetEntityCoords(player), 8.0, 6.0)

  local deadAnimals = getNearbyDeadPeds(GetEntityCoords(player), 10.0, false)
  local actualAnimals = {}
  for _, ped in ipairs(deadAnimals) do
    local isHuman = true
    if type(IsPedHuman) == "function" then isHuman = IsPedHuman(ped) end
    if not isHuman then table.insert(actualAnimals, ped) end
  end

  if #actualAnimals == 0 then
    notify("ai_animal_none","None Found","No dead animals found nearby.",'warning','paw','#DD6B20')
  else
    notify("ai_animal_work","Animal Control","Animal Control collecting animals.",'success','paw','#38A169')
    for _, ped in ipairs(actualAnimals) do
      if DoesEntityExist(ped) then
        NetworkRequestControlOfEntity(ped)
        SetEntityAsMissionEntity(ped, true, true)
        ClearPedTasksImmediately(ped)
        Citizen.Wait(300)
        DeleteEntity(ped)
        if DoesEntityExist(ped) then DeletePed(ped) end
      end
    end
    notify("ai_animal_done","Collected","Animals removed by Animal Control.",'success','paw','#38A169')
  end

  cleanupServiceEntities({veh, driver})
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

-- AI Tow
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
    Citizen.Wait(800)
    if driver and driver ~= 0 then
      TaskVehicleDriveWander(driver, towVeh, 20.0, 786603)
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

local function attemptStopOnFoot(forceImmediate)
  dprint("attemptStopOnFoot called, forceImmediate=", tostring(forceImmediate))
  local player = PlayerPedId()
  local coords = GetEntityCoords(player)
  local ped, pedCoords

  if lib and lib.getClosestPed then
    ped, pedCoords = lib.getClosestPed(coords, 6.5)
    if type(ped) == "table" and ped.ped then ped = ped.ped end 
  else
    local handle, candidate = FindFirstPed()
    local ok = true
    local bestDist, bestPed, bestCoords = 1e9, nil, nil
    while ok do
      if DoesEntityExist(candidate) and not IsPedAPlayer(candidate) then
        local ccoords = GetEntityCoords(candidate)
        local d = #(ccoords - coords)
        if d < bestDist and d <= 6.5 then bestDist = d; bestPed = candidate; bestCoords = ccoords end
      end
      ok, candidate = FindNextPed(handle)
    end
    EndFindPed(handle)
    ped, pedCoords = bestPed, bestCoords
  end

  if not ped or ped == 0 or DoesEntityExist(ped) == false then
    dprint("attemptStopOnFoot: no ped found")
    return notify("stop_no","Stop Failed","No nearby ped to stop.", 'error','person','')
  end
  if IsPedAPlayer(ped) then
    dprint("attemptStopOnFoot: ped is player")
    return notify("stop_player","Stop Failed","Target is a player. Use caution.", 'warning','person','')
  end

  local netId = PedToNet(ped)
  if not netId then
    dprint("attemptStopOnFoot: PedToNet returned nil; using tostring(ped)")
    netId = tostring(ped)
  end

  if not pedData[netId] then
    pedData[netId] = generatePerson()
    TriggerServerEvent('mdt:logID', netId, pedData[netId])
  end

  lastPedNetId = netId
  lastPedEntity = ped   

  setPedProtected(netId, true)
  pedData[netId].forcedStop = forceImmediate and true or false
  pedData[netId].pulledInVehicle = false

  NetworkRequestControlOfEntity(ped)
  SetEntityAsMissionEntity(ped, true, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  holdPedAttention(ped, false)

  notify("stop_done","Stop","Ped stopped and detained on-foot." .. (forceImmediate and " (forced)" or ""), 'success','person','')
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

  if math.random() < 0.2 then
    local drv = GetPedInVehicleSeat(pullVeh,-1)
    if drv and drv ~= 0 then
      TaskVehicleDriveWander(drv, pullVeh, 20.0, 786603)
    end
    notify("pull_fail","Pull-Over","Driver fled!",'error')
    pullVeh = nil
    return
  end

  local driver = GetPedInVehicleSeat(pullVeh, -1)
  NetworkRequestControlOfEntity(pullVeh)
  if driver and driver ~= 0 then NetworkRequestControlOfEntity(driver) end

  if driver and driver ~= 0 and not IsPedAPlayer(driver) then
    local netId = PedToNet(driver) or tostring(driver)
    if not pedData[netId] then
      pedData[netId] = generatePerson()
      TriggerServerEvent('mdt:logID', netId, pedData[netId])
    end
    lastPedNetId = netId
    lastPedEntity = driver   

    setPedProtected(netId, true)
    pedData[netId].forcedStop = forceImmediate and true or false
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
        local occNet = PedToNet(occupant) or tostring(occupant)
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
        notify("pull_done","Pull-Over","Vehicle slowed and pulled over. Occupant detained in-vehicle. Use vehicle menu to eject if needed.",'success','car-side','#38A169')
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

-- interactive reposition helper (arrow keys to move, ENTER to confirm, ESC to cancel)
local function repositionInteractive(veh)
  if not veh or not DoesEntityExist(veh) then
    return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
  end

  -- request network control
  NetworkRequestControlOfEntity(veh)
  local start = GetGameTimer()
  while not NetworkHasControlOfEntity(veh) and (GetGameTimer() - start) < 1000 do
    NetworkRequestControlOfEntity(veh)
    Citizen.Wait(10)
  end

  -- store original transform so we can cancel
  local origCoords = GetEntityCoords(veh)
  local origHeading = GetEntityHeading(veh)

  -- prepare vehicle for reposition
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleEngineOn(veh, false, true, true)
  SetVehicleHandbrake(veh, true)
  SetVehicleDoorsLocked(veh, 2)

  notify("pull_repos_start","Reposition Mode",
    "Use ARROW KEYS to move vehicle. HOLD LEFT SHIFT for fine moves. PRESS ENTER to confirm. PRESS ESC to cancel.",
    'inform','arrows-spin','#4299E1')

  local step = 0.25         -- meters per tick when holding arrow
  local fineStep = 0.06     -- smaller step when holding shift
  local running = true
  local cancelled = false

  while running do
    Citizen.Wait(0)

    if not DoesEntityExist(veh) then
      notify("pull_repos_fail","Reposition Failed","Vehicle no longer exists.",'error','arrows-spin','#E53E3E')
      return
    end

    -- determine step size (hold left shift for fine adjustments)
    local curStep = step
    if IsControlPressed(0,21) then -- LEFT SHIFT for fine movement
      curStep = fineStep
    end

    local pos = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local right = vector3(fwd.y, -fwd.x, 0)

    -- arrow keys: 172=UP, 173=DOWN, 174=LEFT, 175=RIGHT
    if IsControlPressed(0,172) then -- UP
      SetEntityCoordsNoOffset(veh, pos + fwd * curStep, false, false, false)
    end
    if IsControlPressed(0,173) then -- DOWN
      SetEntityCoordsNoOffset(veh, pos - fwd * curStep, false, false, false)
    end
    if IsControlPressed(0,174) then -- LEFT (strafe left)
      SetEntityCoordsNoOffset(veh, pos - right * curStep, false, false, false)
    end
    if IsControlPressed(0,175) then -- RIGHT (strafe right)
      SetEntityCoordsNoOffset(veh, pos + right * curStep, false, false, false)
    end

    -- confirm with ENTER (191 = FRONTEND_ACCEPT / ENTER)
    if IsControlJustReleased(0,191) then
      -- finalize position
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

    -- cancel with ESC / BACK (200 = ESC / BACK)
    if IsControlJustReleased(0,200) then
      cancelled = true
      running = false
      break
    end
  end

  if cancelled then
    -- restore original transform
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

-- prompt-and-start reposition: ask "Do you want to reposition vehicle? (Y/N)" then call repositionInteractive on Yes
local function repositionPullVeh()
  -- try pullVeh first, otherwise try to find vehicle ahead (no dependency on ensureTargetVehicle)
  local veh = pullVeh
  if not veh or not DoesEntityExist(veh) then
    veh = findVehicleAhead(20, 0.5)
  end

  if not veh or not DoesEntityExist(veh) then
    return notify("no_vehicle","No Vehicle","No pulled vehicle found.",'error','car-side','#E53E3E')
  end

  -- Primary: use lib.showContext if available for a quick Yes/No menu
  if lib and lib.showContext and lib.registerContext then
    local ctx = {
      id = 'reposition_confirm',
      title = 'Reposition Pulled Vehicle?',
      canClose = true,
      options = {
        { title = 'Yes — Reposition', icon = 'arrows-spin', onSelect = function() repositionInteractive(veh) end },
        { title = 'No — Cancel', icon = 'ban', onSelect = function() notify("pull_repos_no","Cancelled","Reposition cancelled.",'inform','ban','#DD6B20') end },
      }
    }
    pcall(function() lib.registerContext(ctx) end)
    lib.showContext('reposition_confirm')
    return
  end

  -- Secondary: if lib.inputDialog is available, ask for Y/N there
  if lib and lib.inputDialog then
    local dlg = lib.inputDialog("Reposition Vehicle?", {
      { type='input', label='Enter Y to reposition or N to cancel', default='Y/N' }
    })
    if dlg and type(dlg) == 'table' then
      local val = tostring(dlg[1] or ""):lower()
      if val:match("^%s*y") then
        repositionInteractive(veh)
      else
        notify("pull_repos_no","Cancelled","Reposition cancelled.",'inform','ban','#DD6B20')
      end
      return
    end
  end

  -- Fallback: onscreen keyboard Y/N
  DisplayOnscreenKeyboard(1, "FMMC_MPM_NA", "", "Reposition vehicle? (Y/N)", "", "", "", 1)
  local tick = GetGameTimer() + 20000
  while UpdateOnscreenKeyboard() == 0 and GetGameTimer() < tick do
    Citizen.Wait(0)
  end
  local result = ""
  if UpdateOnscreenKeyboard() ~= 2 then
    local ok, res = pcall(function() return GetOnscreenKeyboardResult() end)
    if ok and res then result = tostring(res) end
  end
  result = (result or ""):gsub("^%s+",""):gsub("%s+$",""):lower()
  if result:match("^y") then
    repositionInteractive(veh)
  else
    notify("pull_repos_no","Cancelled","Reposition cancelled.",'inform','ban','#DD6B20')
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

  local netId = PedToNet(ped)
  if netId and pedData[netId] and (pedData[netId].pulledProtected or pedData[netId].pulledInVehicle) then
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
      Citizen.Wait(50)
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

  local dNet = PedToNet(driver)
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
      local n = PedToNet(ped)
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
    local n = PedToNet(driver)
    if n then setPedProtected(n, false); markPulledInVehicle(n, false); if pedData[n] then pedData[n].forcedStop=nil end end
    if forcePedExitFromVehicle(driver, veh) then any = true end
  end

  for seat = 0, 15 do
    local ped = GetPedInVehicleSeat(veh, seat)
    if ped and ped ~= 0 and not IsPedAPlayer(ped) then
      local n = PedToNet(ped)
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
-- ===== First Aid (Revive) =====
local function attemptFirstAid()
  dprint("attemptFirstAid called")
  local player = PlayerPedId()
  local px,py,pz = toXYZ(GetEntityCoords(player))
  if not px then
    return notify("fa_fail_pos","First Aid","Could not determine player position.", 'error','heartbeat','#DD6B20')
  end

  -- 1) Prefer last stopped ped if it's dead
  local targetPed = nil
  if lastPedNetId then
    local maybe = NetToPed( tonumber(lastPedNetId) or lastPedNetId )
    if maybe and DoesEntityExist(maybe) and IsPedDeadOrDying(maybe, true) then
      targetPed = maybe
      dprint("attemptFirstAid: using lastPedNetId ped as target")
    end
  end

  -- 2) Fallback: try lib.getClosestPed(coords, maxDistance) if available
  if not targetPed and lib and type(lib.getClosestPed) == "function" then
    local ok, ped, pedCoords = pcall(function()
      return lib.getClosestPed(vector3(px,py,pz), 8.0)
    end)

    if ok then
      -- lib.getClosestPed returns (ped?, coords?)
      -- handle both return styles (direct returns or table)
      local foundPed = nil
      if type(ped) == "number" then
        foundPed = ped
      elseif type(ped) == "table" and ped.ped then
        foundPed = ped.ped
      end

      if foundPed and DoesEntityExist(foundPed) and IsPedDeadOrDying(foundPed, true) then
        -- ensure it's human if IsPedHuman is available
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

  -- 3) Final fallback: find nearest dead NPC using existing getNearbyDeadPeds()
  if not targetPed then
    local deadList = getNearbyDeadPeds(vector3(px,py,pz), 8.0, true) -- humanOnly = true
    if #deadList > 0 then
      -- pick closest
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

  -- Lock and mission the ped for safety
  NetworkRequestControlOfEntity(targetPed)
  local start = GetGameTimer()
  while not NetworkHasControlOfEntity(targetPed) and (GetGameTimer() - start) < 1000 do
    NetworkRequestControlOfEntity(targetPed); Citizen.Wait(10)
  end
  SetEntityAsMissionEntity(targetPed, true, true)
  SetBlockingOfNonTemporaryEvents(targetPed, true)

  -- Start action (notify + progress)
  notify("fa_start","First Aid","Applying first aid. Please wait...", 'inform','heartbeat','#4299E1')

  -- play a simple anim if available (falls back silently)
  local animDict = "mini@triathlon"
  RequestAnimDict(animDict)
  local loadStart = GetGameTimer()
  while not HasAnimDictLoaded(animDict) and (GetGameTimer() - loadStart) < 800 do Citizen.Wait(10) end
  if HasAnimDictLoaded(animDict) then
    TaskPlayAnim(PlayerPedId(), animDict, "idle_a", 8.0, -8.0, 4000, 49, 0, false, false, false)
  end

  -- Use safeProgressBar to respect existing lib or fallback wait
  local ok = safeProgressBar({ duration = 4000, label = "Applying First Aid" })
  if not ok then
    notify("fa_cancel","Cancelled","First aid action cancelled.", 'warning','ban','#DD6B20')
    -- cleanup
    SetBlockingOfNonTemporaryEvents(targetPed, false)
    SetEntityAsMissionEntity(targetPed, false, false)
    return
  end

  -- Determine success chance (adjustable)
  local successChance = 0.75 -- 75% base chance
  local success = (math.random() < successChance)

  if success then
    -- revive and heal
    NetworkRequestControlOfEntity(targetPed)
    SetEntityAsMissionEntity(targetPed, true, true)
    ClearPedTasksImmediately(targetPed)

    local maxHp = GetEntityMaxHealth(targetPed) or 200
    local restoreHp = math.min(maxHp, 140) -- revive to moderate health (tweak as desired)
    SetEntityHealth(targetPed, restoreHp)

    -- small delay then let them walk away
    Citizen.Wait(200)

    SetBlockingOfNonTemporaryEvents(targetPed, false)
    SetPedCanRagdoll(targetPed, true)
    SetPedKeepTask(targetPed, false)
    TaskWanderStandard(targetPed, 10.0, 10)
    notify("fa_ok","Revived","First aid successful. NPC revived.", 'success','heartbeat','#38A169')

    dprint("attemptFirstAid: revive SUCCESS for ped=", tostring(targetPed))
  else
    -- failure: optional effects, notify player
    notify("fa_fail","Failed","First aid failed. Casualty not revived.", 'error','heartbeat','#E53E3E')
    dprint("attemptFirstAid: revive FAILED for ped=", tostring(targetPed))
    -- leave ped as-is, restore mission state so ped can be cleaned up later by coroner/ems
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
            -- NEW: First Aid / Revive dead NPC
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
      local n = PedToNet(occ)
      if n then
        setPedProtected(n, false)
        markPulledInVehicle(n, false)
        if pedData[n] then pedData[n].forcedStop = nil end
      end

      -- Basic vehicle unblocking
      SetVehicleEngineOn(pullVeh, true, true, true)
      SetVehicleHandbrake(pullVeh, false)
      SetVehicleDoorsLocked(pullVeh, 1)
      SetVehicleUndriveable(pullVeh, false)

      -- restore ped state
      releasePedAttention(occ)
      SetBlockingOfNonTemporaryEvents(occ, false)

      -- Request network control for reliability
      NetworkRequestControlOfEntity(occ)
      NetworkRequestControlOfEntity(pullVeh)

      -- wait briefly for control (with timeout)
      local start = GetGameTimer()
      while not NetworkHasControlOfEntity(occ) and (GetGameTimer() - start) < 1000 do
        NetworkRequestControlOfEntity(occ); Citizen.Wait(10)
      end
      start = GetGameTimer()
      while not NetworkHasControlOfEntity(pullVeh) and (GetGameTimer() - start) < 1000 do
        NetworkRequestControlOfEntity(pullVeh); Citizen.Wait(10)
      end

      -- Ensure the ped is in the driver seat; warp them in if necessary
      if not IsPedInVehicle(occ, pullVeh, true) or GetPedInVehicleSeat(pullVeh, -1) ~= occ then
        TaskWarpPedIntoVehicle(occ, pullVeh, -1) -- -1 = driver
        Citizen.Wait(150)
      end

      -- Make the ped a capable driver and keep their task so they don't bail
      SetDriverAbility(occ, 1.0)        -- higher = better handling
      SetDriverAggressiveness(occ, 0.7) -- moderate aggression so they drive off
      SetPedKeepTask(occ, true)

      -- Try the easy approach first: drive wander
      TaskVehicleDriveWander(occ, pullVeh, 20.0, 786603)

      -- After a short delay check if the vehicle actually started moving; if not, fallback to drive-to-coord
      Citizen.CreateThread(function()
        Citizen.Wait(600) -- give the ped some time to start driving

        if DoesEntityExist(occ) and DoesEntityExist(pullVeh) then
          local speed = GetEntitySpeed(pullVeh)
          dprint(("Finish Pull-Over: speed after wander check = %.2f"):format(speed))
          if speed < 1.0 then
            dprint("Finish Pull-Over: wander didn't start — using drive-to-coord fallback")

            -- compute a far-away point in front of the vehicle
            local dest = GetOffsetFromEntityInWorldCoords(pullVeh, 0.0, 200.0, 0.0)
            -- signature: TaskVehicleDriveToCoord(ped, vehicle, x,y,z, speed, p6, vehicleModelHash, drivingStyle, stopRange, p10)
            -- p6 = 1.0, stopRange=5.0, p10 = true (use common pattern)
            local model = GetEntityModel(pullVeh)
            TaskVehicleDriveToCoord(occ, pullVeh, dest.x, dest.y, dest.z, 20.0, 1.0, model, 786603, 5.0, true)

            -- allow it some time and then remove forced keep-task so AI can resume normal behavior
            Citizen.Wait(8000)
            if DoesEntityExist(occ) then SetPedKeepTask(occ, false) end
          else
            -- driving started; clear keep task after a little while so AI returns to normal
            Citizen.Wait(5000)
            if DoesEntityExist(occ) then SetPedKeepTask(occ, false) end
          end
        end
      end)
    else
      -- no occupant: just un-hold the vehicle so it can leave
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
      { title='Let Ped Go', icon='unlock', description='Release stopped ped', onSelect=function() dprint("Context: Let Ped Go selected"); releasePed() end },
    }
  })
else
  dprint("lib.registerContext not available; context menus not registered")
end

AddEventHandler('__clientRequestPopulate', function()
  local lastName = nil
  if lastPedNetId and pedData[lastPedNetId] and pedData[lastPedNetId].name then
    lastName = pedData[lastPedNetId].name
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


-- client.lua additions: receive a server dispatch and call the existing AI function locally
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
    -- use your notify wrapper if available
    if notify then notify("ai_dispatch_bad","Dispatch","Unknown service: "..tostring(service), 'error') end
    return
  end

  -- small safety delay so player's ped & coords are stable
  Citizen.CreateThread(function()
    Citizen.Wait(400) -- tweak if needed
    if notify then notify("ai_dispatch_recv","Dispatch","AI "..s.." requested; responding now.", 'inform') end
    pcall(fn) -- call the existing local function (callAIEMS, callAICoroner, etc.)
  end)
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
      local ped = NetToPed(tonumber(netId) or netId)
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

-- STOP / TRAFFIC STOP (require LEFT SHIFT + E)
RegisterCommand('stopAI', function()
  -- require LEFT SHIFT (control 21) as a modifier
  if not IsControlPressed(0, 21) then
    notify("stop_require", "Hold Modifier", "You must hold LEFT SHIFT + E to initiate a stop.", 'warning', 'ban', '#DD6B20')
    return
  end

  local player = PlayerPedId()
  local inVeh = IsPedInAnyVehicle(player, false)
  if inVeh and inEmergencyVehicle() then
    attemptPullOverAI(false)
  else
    attemptStopOnFoot(false)
  end
end)
RegisterKeyMapping('stopAI', 'Stop/Traffic Stop (LEFT SHIFT + E)', 'keyboard', 'E')


-- CANCEL NON-FORCED STOPS (moved to LEFT CTRL to avoid conflicting with modifier)
RegisterCommand('cancelStopsCmd', function()
  cancelNonForcedStops()
end)
RegisterKeyMapping('cancelStopsCmd', 'Cancel stops (LEFT CTRL)', 'keyboard', 'LEFTCTRL')
RegisterCommand('repositionVeh', repositionPullVeh)
RegisterKeyMapping('repositionVeh','Reposition Pulled Vehicle','keyboard','Y')
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
  if lastPedNetId and pedData[lastPedNetId] then
    fullName = pedData[lastPedNetId].name
    dob = pedData[lastPedNetId].dob or ""
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

    if lastPedNetId then pedData[lastPedNetId] = nil end
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

  local netId = PedToNet(ped)
  if netId then
    setPedProtected(netId, false)
    markPulledInVehicle(netId, false)
    if pedData[netId] then pedData[netId].forcedStop = nil end
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
        TaskVehicleDriveWander(ped, veh, 20.0, 786603)
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

  -- Try to obtain network control (with timeout)
  NetworkRequestControlOfEntity(ped)
  local ctrlStart = GetGameTimer()
  while not NetworkHasControlOfEntity(ped) and (GetGameTimer() - ctrlStart) < 1000 do
    NetworkRequestControlOfEntity(ped)
    Citizen.Wait(10)
  end
  if not NetworkHasControlOfEntity(ped) then
    dprint("tryCuffPed: WARNING - could not obtain network control of ped, continuing anyway")
  end

  -- Load anim dict (with timeout)
  local dict = "mp_arresting"
  RequestAnimDict(dict)
  local loadStart = GetGameTimer()
  while not HasAnimDictLoaded(dict) and (GetGameTimer() - loadStart) < 1000 do
    Citizen.Wait(0)
  end
  if not HasAnimDictLoaded(dict) then
    dprint("tryCuffPed: failed to load anim dict " .. tostring(dict))
  end

  -- If in vehicle, try to make them exit briefly
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

  -- Clear interfering tasks and give a moment
  ClearPedTasksImmediately(ped)
  ClearPedSecondaryTask(ped)
  Citizen.Wait(50)

  -- Attempt to play a looping cuff animation; retry a few times if it doesn't actually start
  local played = false
  for attempt = 1, 3 do
    TaskPlayAnim(ped, dict, "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
    Citizen.Wait(150) -- give animation a moment
    if IsEntityPlayingAnim(ped, dict, "idle", 3) then
      played = true
      break
    else
      dprint(("tryCuffPed: anim play attempt %d failed, retrying"):format(attempt))
      Citizen.Wait(50)
    end
  end

  if not played then
    dprint("tryCuffPed: WARNING - animation didn't start; will still apply cuff state")
    -- you may choose to abort here if you prefer
    -- return notify("cuff_fail_anim","Failed","Couldn't start cuff animation.",'error','ban','#E53E3E')
  end

  -- Apply cuff state after animation started (or even if it didn't)
  SetEnableHandcuffs(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)

  notify("cuff_ok","Cuffed","Ped is handcuffed.",'success','lock','#38A169')

  draggedPed = ped
  isDragging = false

  -- Prepare network id to send to server
  local sendNet = nil
  if lastPedNetId then
    sendNet = lastPedNetId
  else
    local maybe = PedToNet(ped)
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

-- client.lua (give all peds a target option to open police menu)

local SCAN_INTERVAL = 5000 -- ms between full scans (tweak if you want faster/slower)
local TARGET_DISTANCE = 2.5

-- store registered network IDs so we don't re-register repeatedly
local registeredNetIds = {}

-- helper: get all peds using native FindFirstPed / FindNextPed
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

-- helper: check if a network id corresponds to a valid entity
local function netIdExists(netId)
    if not netId or netId == 0 then return false end
    local ent = NetworkGetEntityFromNetworkId(netId)
    return ent and ent ~= 0 and DoesEntityExist(ent)
end

-- client event that opens the police menu context
RegisterNetEvent('az-police:openMenu', function()
    if lib and lib.showContext then
        lib.showContext('police_mainai')
    else
        print("^1[az-police]^7 lib.showContext missing")
    end
end)

-- preserve your command
RegisterCommand('policemenu', function()
    if lib and lib.showContext then
        lib.showContext('police_mainai')
    else
        print("^1[policemenu]^7 lib.showContext missing")
    end
end, false)

-- main scanner thread: register new peds with ox_target
CreateThread(function()
    while true do
        local peds = getAllPeds()
        local playerPed = PlayerPedId()

        -- cleanup registeredNetIds for netIds that no longer exist
        for nid, _ in pairs(registeredNetIds) do
            if not netIdExists(nid) then
                registeredNetIds[nid] = nil
            end
        end

        -- attempt registering new ped net ids
        for _, ped in ipairs(peds) do
            -- skip player ped
            if ped ~= playerPed then
                -- skip if ped is a player (in MP this could be a remote player ped)
                if not IsPedAPlayer(ped) then
                    local netId = NetworkGetNetworkIdFromEntity(ped)
                    if netId and netId ~= 0 and not registeredNetIds[netId] then
                        -- register with ox_target
                        -- options use a simple event call to keep payload minimal
                        -- register with ox_target: pass an array of option objects as the second param
                        local ok, err = pcall(function()
                            exports.ox_target:addEntity(netId, {
                                {
                                    event = 'az-police:openMenu',
                                    icon  = 'user-shield',
                                    label = 'Open Police Menu',
                                    distance = TARGET_DISTANCE
                                }
                            })
                        end)

                        if ok then
                            registeredNetIds[netId] = true
                        else
                            print(("^1[az-police]^7 failed to addEntity for netId %s: %s"):format(tostring(netId), tostring(err)))
                        end
                    end
                else
                    -- it's a player ped (remote player) — if you *also* want remote players to be targetable,
                    -- remove the IsPedAPlayer check above.
                end
            end
        end

        Wait(SCAN_INTERVAL)
    end
end)


AddEventHandler("onResourceStop", function(resName)
  if GetCurrentResourceName() ~= resName then return end
  if pullVeh and DoesEntityExist(pullVeh) then
    local occ = getPrimaryOccupant(pullVeh)
    if occ and occ ~= 0 then
      local n = PedToNet(occ)
      if n then setPedProtected(n, false); markPulledInVehicle(n, false) end
      releasePedAttention(occ)
    end
    SetVehicleEngineOn(pullVeh, true, true, true)
    SetVehicleHandbrake(pullVeh, false)
    SetVehicleDoorsLocked(pullVeh, 1)
    pullVeh = nil
  end
end)
