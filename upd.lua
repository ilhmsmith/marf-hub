--[[
    ╔══════════════════════════════════════════════════════════╗
    ║                      MARF HUB v1.1                       ║
    ║            Grow a Garden - Auto Leveling Tool            ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Features:                                               ║
    ║  • Auto Leveling with pet queue system                   ║
    ║  • Auto Nightmare farming with auto-cleanse              ║
    ║  • Auto Elephant weight farming (Jumbo Blessing)         ║
    ║  • Real-time age, weight & mutation tracking             ║
    ║  • Smart slot switching based on cooldowns               ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Author: marf                                            ║
    ║  UI Library: WindUI                                      ║
    ╚══════════════════════════════════════════════════════════╝
--]]

-- Wind UI Library
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Services
local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local player   = Players.LocalPlayer
local petsPhysical = workspace:WaitForChild("PetsPhysical")

-- Remotes
local Events               = RS:WaitForChild("GameEvents")
local PetCooldownsUpdated  = Events:FindFirstChild("PetCooldownsUpdated")
local RequestPetCooldowns  = Events:FindFirstChild("RequestPetCooldowns")
local PetsService          = Events:WaitForChild("PetsService")
local PetShardService_RE   = Events:FindFirstChild("PetShardService_RE")  -- For Cleansing Shard
local Notification         = Events:FindFirstChild("Notification")  -- For mutation detection

-- DataService for real-time pet data
local DataService = require(RS.Modules.DataService)

-- Anti-AFK (default ON)
local antiAfkEnabled = true

-- Discord Webhook
local webhookUrl = ""
local webhookEnabled = false

-- Mutation detection via Notification
local lastMutationResult = nil  -- nil = waiting, "Nightmare" = success, "Other" = wrong mutation
local lastMutationName = nil    -- Store the actual mutation name

-- Elephant detection via Notification
local lastElephantResult = nil  -- nil = waiting, "Blessed" = success, "MaxWeight" = cap reached
local lastElephantWeight = nil  -- Total weight from notification

-- Ferret detection via Notification (Leveling V2)
local lastFerretResult = nil    -- nil = waiting, "LevelUp" = +1 level, "MaxLevel" = level 100
local v2TriggerCount = 0        -- Count Ferret triggers
local v2PetEquipped = false     -- Track if V2 pet is equipped (needed for notification check)
local v2AutoEnabled = false     -- Track if V2 auto is enabled

--==============================================================--
-- Window & Tabs
--==============================================================--
local Window = WindUI:CreateWindow({
    Title = "Marf Hub",
    Icon = "zap",
    Author = "by marf",
    Folder = "MarfHub",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    Transparent = true,
})

local MainTab = Window:Tab({
    Title = "Auto Leveling V1",
    Icon = "trending-up",
})

local LevelingV2Tab = Window:Tab({
    Title = "Auto Leveling V2",
    Icon = "flame",
})

local NightmareTab = Window:Tab({
    Title = "Auto Nightmare",
    Icon = "moon",
})

local ElephantTab = Window:Tab({
    Title = "Auto Elephant",
    Icon = "weight",
})

local SettingsTab = Window:Tab({
    Title = "Settings", 
    Icon = "settings",
})

--==============================================================--
-- Helpers
--==============================================================--
local function setcb(s) 
    if typeof(setclipboard)=="function" then 
        setclipboard(s) 
    end 
end

-- Discord Webhook function
local function sendWebhook(title, description, color, fields)
    if not webhookEnabled or webhookUrl == "" then return end
    
    local HttpService = game:GetService("HttpService")
    
    local embed = {
        title = title,
        description = description,
        color = color or 5763719,
        fields = fields or {},
        footer = {text = "Grow a Garden • Marf Hub v1.1"},
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    
    local data = {
        username = "Marf Hub",
        embeds = {embed}
    }
    
    task.spawn(function()
        pcall(function()
            request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode(data)
            })
        end)
    end)
end

local function normGuid(s) 
    return string.lower((tostring(s or "")):gsub("[{}]","")) 
end

local function swapTo(slot) 
    pcall(function() 
        PetsService:FireServer("SwapPetLoadout", slot) 
    end) 
end

-- Convert visual slot to internal slot for SwapPetLoadout
-- Visual 2 = Internal 3, Visual 3 = Internal 2
local function visualToInternal(visualSlot)
    if visualSlot == 2 then return 3
    elseif visualSlot == 3 then return 2
    else return visualSlot
    end
end

-- Find pet in all PetMovers (for cleansing shard)
local function findPetInPetMovers(guid)
    local PetsPhysical = workspace:FindFirstChild("PetsPhysical")
    if not PetsPhysical then return nil end
    
    for _, child in ipairs(PetsPhysical:GetChildren()) do
        if child.Name == "PetMover" then
            local pet = child:FindFirstChild(guid)
            if pet then return pet end
        end
    end
    return nil
end

-- Apply Cleansing Shard to pet (pet must be equipped!)
local function applyCleansingShardToPet(guid)
    local Backpack = player:FindFirstChild("Backpack")
    local Character = player.Character
    
    if not Backpack or not Character then
        return false, "No Backpack/Character"
    end
    
    -- Find shard tool
    local shardTool = nil
    for _, item in ipairs(Backpack:GetChildren()) do
        if item.Name:find("Cleansing Pet Shard") then
            shardTool = item
            break
        end
    end
    
    if not shardTool then
        for _, item in ipairs(Character:GetChildren()) do
            if item.Name:find("Cleansing Pet Shard") then
                shardTool = item
                break
            end
        end
    end
    
    if not shardTool then
        return false, "No Cleansing Shard!"
    end
    
    -- Get pet physical (must be equipped)
    local targetPet = findPetInPetMovers(guid)
    if not targetPet then
        return false, "Pet not equipped!"
    end
    
    -- Equip shard and apply
    shardTool.Parent = Character
    task.wait(0.5)
    
    if PetShardService_RE then
        PetShardService_RE:FireServer("ApplyShard", targetPet)
    end
    
    task.wait(0.5)
    shardTool.Parent = Backpack
    
    return true, "Shard applied!"
end

-- Listen for mutation notification from Headless skill
if Notification then
    Notification.OnClientEvent:Connect(function(message)
        if message and type(message) == "string" then
            -- Check for mutation notification
            -- Format: "💀 Mimic Octopus's power twisted your [Pet] into a level 1 <font color='#...'>MutationName</font> mutation!"
            if message:find("twisted your") and message:find("mutation") then
                -- Extract mutation name from <font color='...'>MutationName</font>
                local mutationName = message:match("<font color='[^']+'>([^<]+)</font>")
                
                if mutationName then
                    lastMutationName = mutationName
                    if mutationName == "Nightmare" then
                        lastMutationResult = "Nightmare"
                    else
                        lastMutationResult = "Other"
                    end
                    
                    print("[Marf Hub] Mutation detected:", mutationName)
                end
            end
            
            -- Check for Elephant blessing notification
            -- Success: "🐘 Elephant blessed your Bunny! Age reset to 1 and gained +0.1 KG (2.06 KG total)!"
            -- Max weight: "🐘 Elephant trumpeted a blessing, but found no old pets below the weight cap!"
            if message:find("Elephant blessed your") then
                -- Extract total weight from "(X.XX KG total)"
                local totalWeight = tonumber(message:match("%(([%d%.]+) KG total%)"))
                lastElephantWeight = totalWeight
                lastElephantResult = "Blessed"
                
                print("[Marf Hub] Elephant blessing! Weight:", totalWeight, "KG")
                
            elseif message:find("found no old pets below the weight cap") then
                lastElephantResult = "MaxWeight"
                
                print("[Marf Hub] Elephant: Max weight reached!")
            end
            
            -- Check for Ferret notification (Leveling V2)
            -- Level +1: "🍟 French Fry Ferret increased a Peacock's level by 1!"
            -- Max level: "🍟 French Fry Ferret couldn't find a pet to increase level..."
            if message:find("French Fry Ferret increased") then
                lastFerretResult = "LevelUp"
                v2TriggerCount = v2TriggerCount + 1
                
                print("[Marf Hub] Ferret +1 level! Triggers:", v2TriggerCount)
                
            elseif message:find("couldn't find a pet to increase level") then
                -- ONLY set MaxLevel if pet is currently equipped (avoid false trigger during pet swap)
                if v2PetEquipped and v2AutoEnabled then
                    lastFerretResult = "MaxLevel"
                    print("[Marf Hub] Ferret: Max level 100 reached!")
                else
                    print("[Marf Hub] Ferret: No pet equipped, ignoring max level notification")
                end
            end
        end
    end)
end

-- Anti-AFK: Prevent idle kick
player.Idled:Connect(function()
    if antiAfkEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        
        WindUI:Notify({
            Title = "🛡️ Anti-AFK",
            Content = "Prevented idle kick!",
            Duration = 3,
            Icon = "shield"
        })
        
        print("[Marf Hub] Anti-AFK: Prevented idle kick")
    end
end)

-- cooldown payload → extract seconds
local function pickSeconds(v)
    if type(v)=="number" then return math.max(0,v) end
    if type(v)=="table" then
        if #v>=1 and type(v[1])=="table" then
            local t=v[1]
            if t.Time then return math.max(0,t.Time) end
            if t.Remaining then return math.max(0,t.Remaining) end
            if t.Ready==true then return 0 end
        end
        if v.Time then return math.max(0,v.Time) end
        if v.Remaining then return math.max(0,v.Remaining) end
        if v.Ready==true then return 0 end
    end
    return nil
end

-- Get current slot from DataService (real-time!)
local function getCurrentSlotFromService()
    local success, data = pcall(function()
        return DataService:GetData()
    end)
    
    if success and data and data.PetsData and data.PetsData.SelectedPetLoadout then
        return data.PetsData.SelectedPetLoadout
    end
    
    return nil
end

-- Mutation EnumId to Name mapping (from PetMutationRegistry)
local MUTATION_MAP = {
    ["a"] = "Shocked",
    ["b"] = "Golden",
    ["c"] = "Rainbow",
    ["d"] = "Shiny",
    ["e"] = "Windy",
    ["f"] = "Frozen",
    ["g"] = "Inverted",
    ["h"] = "Rideable",
    ["i"] = "Mega",
    ["j"] = "Tiny",
    ["k"] = "IronSkin",
    ["l"] = "Radiant",
    ["m"] = "Normal",
    ["n"] = "Ascended",
    ["o"] = "Tranquil",
    ["p"] = "Corrupted",
    ["q"] = "Fried",
    ["r"] = "Aromatic",
    ["s"] = "Silver",
    ["t"] = "GiantBean",
    ["u"] = "Glimmering",
    ["v"] = "Luminous",
    ["w"] = "Nutty",
    ["x"] = "Dreadbound",
    ["y"] = "Soulflame",
    ["z"] = "Spectral",
    ["A"] = "Nightmare",
    ["B"] = "Tethered",
    ["H"] = "Aurora",
    ["I"] = "JUMBO",
    ["J"] = "Oxpecker",
    ["K"] = "Giraffe",
    ["L"] = "Rhino",
    ["M"] = "Crocodile",
    ["N"] = "Lion",
    ["O"] = "Forger",
    ["P"] = "HyperHunger",
    ["Q"] = "Nocturnal",
    ["R"] = "Peppermint",
}

-- Get mutation name from EnumId
local function getMutationName(enumId)
    if not enumId then return "Normal" end
    return MUTATION_MAP[enumId] or "Unknown"
end

-- Get mutation abbreviation for display
local MUTATION_ABBREV = {
    ["Nightmare"] = "NM",
    ["Rainbow"] = "RB",
    ["Golden"] = "GD",
    ["Shiny"] = "SN",
    ["Rideable"] = "RD",
    ["Mega"] = "MG",
    ["Shocked"] = "SK",
    ["Windy"] = "WD",
    ["Frozen"] = "FZ",
    ["Inverted"] = "IV",
    ["Tiny"] = "TN",
    ["IronSkin"] = "IS",
    ["Radiant"] = "RD",
    ["Ascended"] = "AS",
    ["Tranquil"] = "TQ",
    ["Corrupted"] = "CR",
    ["Fried"] = "FR",
    ["Aromatic"] = "AR",
    ["Silver"] = "SV",
    ["GiantBean"] = "GB",
    ["Glimmering"] = "GM",
    ["Luminous"] = "LM",
    ["Nutty"] = "NT",
    ["Dreadbound"] = "DB",
    ["Soulflame"] = "SF",
    ["Spectral"] = "SP",
    ["Tethered"] = "TT",
    ["Aurora"] = "AU",
    ["JUMBO"] = "JB",
    ["Oxpecker"] = "OX",
    ["Giraffe"] = "GF",
    ["Rhino"] = "RH",
    ["Crocodile"] = "CC",
    ["Lion"] = "LN",
    ["Forger"] = "FG",
    ["HyperHunger"] = "HH",
    ["Nocturnal"] = "NC",
    ["Peppermint"] = "PM",
}

local function getMutationAbbrev(mutationName)
    if not mutationName or mutationName == "Normal" or mutationName == "Unknown" then
        return nil
    end
    return MUTATION_ABBREV[mutationName]
end

-- Get pet data from DataService (real-time Age + Mutation!)
local function getPetDataFromService(guid)
    if not guid then return nil end
    
    local success, data = pcall(function()
        return DataService:GetData()
    end)
    
    if not success or not data or not data.PetsData then
        return nil
    end
    
    local petInventory = data.PetsData.PetInventory
    if not petInventory or not petInventory.Data then
        return nil
    end
    
    local petInfo = petInventory.Data[guid]
    if petInfo and petInfo.PetData then
        local mutationType = petInfo.PetData.MutationType
        local baseWeight = petInfo.PetData.BaseWeight or 0
        local age = petInfo.PetData.Level or 1
        return {
            type = petInfo.PetType or "Unknown",
            name = petInfo.PetData.Name or "",
            age = age,
            mutationId = mutationType,
            mutation = getMutationName(mutationType),
            baseWeight = baseWeight,
            currentWeight = baseWeight * (1 + age / 10),  -- Formula: BaseWeight × (1 + Age/10)
        }
    end
    
    return nil
end

-- Calculate current weight from base weight and age
local function getCurrentWeight(baseWeight, age)
    return baseWeight * (1 + age / 10)
end

-- Get all pets from DataService (filter out PetTemplate)
local function getAllPetsFromService()
    local pets = {}
    
    local success, data = pcall(function()
        return DataService:GetData()
    end)
    
    if not success or not data or not data.PetsData then
        return pets
    end
    
    local petInventory = data.PetsData.PetInventory
    if not petInventory or not petInventory.Data then
        return pets
    end
    
    for guid, petInfo in pairs(petInventory.Data) do
        -- Filter: only valid GUID, skip PetTemplate
        if guid:match("^{.*}$") and not guid:find("PetTemplate") and petInfo.PetData then
            local mutationType = petInfo.PetData.MutationType
            local mutationName = getMutationName(mutationType)
            table.insert(pets, {
                guid = guid,
                type = petInfo.PetType or "Unknown",
                name = petInfo.PetData.Name or "",
                age = petInfo.PetData.Level or 1,
                mutation = mutationName,
                mutationAbbrev = getMutationAbbrev(mutationName),
            })
        end
    end
    
    table.sort(pets, function(a, b)
        if a.type == b.type then
            return a.name < b.name
        end
        return a.type < b.type
    end)
    
    return pets
end

-- Format pet for dropdown display
local function formatPetForDropdown(pet)
    local displayName = pet.name ~= "" and pet.name or pet.type
    local typeWithMutation = pet.type
    
    -- Add mutation abbreviation prefix if exists
    if pet.mutationAbbrev then
        typeWithMutation = pet.mutationAbbrev .. " " .. pet.type
    end
    
    return string.format("%s (%s) [Age %d] %s", displayName, typeWithMutation, pet.age, pet.guid)
end

--==============================================================--
-- LEVELING TAB (Enhanced - Same as Auto Nightmare without mutation)
--==============================================================--
MainTab:Paragraph({
    Title = "🐾 Auto Leveling",
    Desc = "Level multiple pets automatically!\n• Queue system for batch leveling\n• Real-time age tracking\n• Auto equip/unequip on slot switch",
})

MainTab:Divider()

-- Leveling Tab Variables
local lvlSelectedMimic = nil
local lvlSelectedLeveling = nil
local lvlSelectedPetToAdd = nil  -- For single dropdown selection
local lvlLevelingQueue = {}  -- Store all selected pets for multi-leveling
local lvlCurrentQueueIndex = 1  -- Track current pet in queue
local lvlMimicDilopSlot = 1  -- Default slot 1
local lvlLevelingSlot = 2    -- Default slot 2
local lvlTargetLevel = 30    -- Default target level
local lvlAutoEnabled = false
local lvlPetEquipped = false  -- Track if leveling pet is currently equipped
local lvlCompletedPets = {}  -- Pets that reached target level

-- Mimic Selection
local LvlMimicDropdown = MainTab:Dropdown({
    Title = "Select Mimic",
    Desc = "Select Mimic Octopus to track cooldown",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v == "(Select Pet)" or v == "(Refresh to load)" or v == "(No pets found)" then
            lvlSelectedMimic = nil
            return
        end
        lvlSelectedMimic = v:match("({.+})$")
    end
})

MainTab:Dropdown({
    Title = "Mimic Dilop Slot",
    Desc = "Slot containing Mimic + Dilophosaurus",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 1",
    Callback = function(v)
        lvlMimicDilopSlot = tonumber(v:match("%d"))
    end
})

MainTab:Divider()

-- Leveling Pet Selection (Single + Queue system)
local LvlLevelingDropdown = MainTab:Dropdown({
    Title = "Select Leveling Pet",
    Desc = "Select pet to add to leveling queue",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v ~= "(Select Pet)" and v ~= "(Refresh to load)" and v ~= "(No pets found)" then
            lvlSelectedPetToAdd = v
        else
            lvlSelectedPetToAdd = nil
        end
    end
})

-- Queue display
local LvlQueueParagraph = MainTab:Paragraph({
    Title = "Queue (0 pets)",
    Desc = "(Empty - add pets above)",
    Color = "Green",
})

local function updateLvlQueueDisplay()
    if #lvlLevelingQueue == 0 then
        LvlQueueParagraph:SetTitle("Queue (0 pets)")
        LvlQueueParagraph:SetDesc("(Empty - add pets above)")
    else
        LvlQueueParagraph:SetTitle(string.format("Queue (%d pets)", #lvlLevelingQueue))
        local lines = {}
        for i, guid in ipairs(lvlLevelingQueue) do
            local petData = getPetDataFromService(guid)
            if petData then
                local name = petData.name ~= "" and petData.name or petData.type
                local abbrev = getMutationAbbrev(petData.mutation)
                local typeStr = abbrev and (abbrev .. " " .. petData.type) or petData.type
                table.insert(lines, string.format("%d. %s (%s)", i, name, typeStr))
            else
                table.insert(lines, string.format("%d. %s", i, guid:sub(1, 20) .. "..."))
            end
        end
        LvlQueueParagraph:SetDesc(table.concat(lines, "\n"))
    end
end

MainTab:Button({
    Title = "➕ Add to Queue",
    Desc = "Add selected pet to leveling queue",
    Icon = "plus",
    Callback = function()
        if not lvlSelectedPetToAdd then
            WindUI:Notify({
                Title = "Error",
                Content = "Select a pet first!",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        local guid = lvlSelectedPetToAdd:match("({.+})$")
        if not guid then
            WindUI:Notify({
                Title = "Error",
                Content = "Invalid pet selection",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        -- Check duplicate
        for _, g in ipairs(lvlLevelingQueue) do
            if g == guid then
                WindUI:Notify({
                    Title = "Already in Queue",
                    Content = "This pet is already in the queue",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
                return
            end
        end
        
        table.insert(lvlLevelingQueue, guid)
        lvlSelectedLeveling = lvlLevelingQueue[1]
        lvlCurrentQueueIndex = 1
        updateLvlQueueDisplay()
        
        local petData = getPetDataFromService(guid)
        local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
        
        WindUI:Notify({
            Title = "Added to Queue",
            Content = string.format("%s (#%d)", petName, #lvlLevelingQueue),
            Duration = 3,
            Icon = "plus-circle"
        })
    end
})

MainTab:Button({
    Title = "🗑️ Clear Queue",
    Desc = "Remove all pets from queue",
    Icon = "trash",
    Callback = function()
        lvlLevelingQueue = {}
        lvlSelectedLeveling = nil
        lvlCurrentQueueIndex = 1
        updateLvlQueueDisplay()
        
        WindUI:Notify({
            Title = "Queue Cleared",
            Content = "All pets removed",
            Duration = 3,
            Icon = "trash-2"
        })
    end
})

MainTab:Dropdown({
    Title = "Leveling Slot",
    Desc = "Slot containing Mimic only (for leveling)",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 2",
    Callback = function(v)
        lvlLevelingSlot = tonumber(v:match("%d"))
    end
})

MainTab:Divider()

-- Target Level
MainTab:Input({
    Title = "Target Level",
    Desc = "Stop leveling when pet reaches this level",
    Value = "30",
    Placeholder = "Enter target level (1-100)...",
    Callback = function(input)
        local num = tonumber(input)
        if num and num >= 1 and num <= 100 then
            lvlTargetLevel = num
            WindUI:Notify({
                Title = "Target Set",
                Content = string.format("Will stop at Level %d", lvlTargetLevel),
                Duration = 3,
                Icon = "target"
            })
        else
            WindUI:Notify({
                Title = "Invalid",
                Content = "Enter a number between 1-100",
                Duration = 3,
                Icon = "alert-circle"
            })
        end
    end
})

MainTab:Button({
    Title = "Refresh Pet List",
    Desc = "Load all pets from your inventory",
    Icon = "refresh-cw",
    Callback = function()
        local pets = getAllPetsFromService()
        
        -- Build values list (pets only, no placeholder)
        local values = {}
        for _, pet in ipairs(pets) do
            table.insert(values, formatPetForDropdown(pet))
        end
        
        if #pets == 0 then
            values = {"(No pets found)"}
            LvlMimicDropdown:Refresh(values)
            LvlLevelingDropdown:Refresh(values)
        else
            LvlMimicDropdown:Refresh(values)
            LvlMimicDropdown:Select("(Select Pet)")
            
            LvlLevelingDropdown:Refresh(values)
            LvlLevelingDropdown:Select("(Select Pet)")
        end
        
        lvlSelectedMimic = nil
        lvlSelectedPetToAdd = nil
        -- Don't reset queue on refresh, just update display
        updateLvlQueueDisplay()
        
        WindUI:Notify({
            Title = "Success",
            Content = string.format("Found %d pets!", #pets),
            Duration = 4,
            Icon = "check-circle"
        })
    end
})

MainTab:Divider()

-- Auto Toggle
local LvlAutoToggle = MainTab:Toggle({
    Title = "Auto Switch",
    Desc = "Automatically equip/unequip pet on slot switch",
    Icon = "repeat",
    Value = false,
    Callback = function(state)
        lvlAutoEnabled = state
        
        if state then
            if not lvlSelectedMimic then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Mimic first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                LvlAutoToggle:Set(false)
                lvlAutoEnabled = false
                return
            end
            
            if #lvlLevelingQueue == 0 then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Leveling Pet(s) first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                LvlAutoToggle:Set(false)
                lvlAutoEnabled = false
                return
            end
            
            lvlPetEquipped = false
            lvlCurrentQueueIndex = 1
            lvlSelectedLeveling = lvlLevelingQueue[1]
            
            local petData = getPetDataFromService(lvlSelectedLeveling)
            local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
            
            WindUI:Notify({
                Title = "Leveling Started",
                Content = string.format("Starting: %s (1/%d)", petName, #lvlLevelingQueue),
                Duration = 4,
                Icon = "play"
            })
        else
            if lvlPetEquipped and lvlSelectedLeveling then
                pcall(function()
                    PetsService:FireServer("UnequipPet", lvlSelectedLeveling)
                end)
                lvlPetEquipped = false
                
                WindUI:Notify({
                    Title = "Pet Unequipped",
                    Content = "Leveling pet removed",
                    Duration = 3,
                    Icon = "log-out"
                })
            end
            
            WindUI:Notify({
                Title = "Leveling Stopped",
                Content = "Disabled",
                Duration = 3,
                Icon = "pause"
            })
        end
    end
})

MainTab:Divider()

-- Status Info
local LvlInfoParagraph = MainTab:Paragraph({
    Title = "Status Information",
    Desc = "⏱ Cooldown: —\n📍 Slot: —\n🐾 Pet: —\n🏷 Type: —\n✨ Mutation: —\n📊 Age: 0/30\n📋 Queue: 0/0\n✅ Done: 0\n🔌 Equipped: ❌\n⚡ Mode: OFF",
    Color = "Blue",
})

MainTab:Button({
    Title = "🔄 Reset Progress",
    Desc = "Reset progress and start from first pet",
    Icon = "refresh-cw",
    Callback = function()
        lvlCompletedPets = {}
        lvlCurrentQueueIndex = 1
        if #lvlLevelingQueue > 0 then
            lvlSelectedLeveling = lvlLevelingQueue[1]
        end
        
        WindUI:Notify({
            Title = "Reset Complete",
            Content = "Back to Pet 1",
            Duration = 4,
            Icon = "refresh-cw"
        })
    end
})

MainTab:Button({
    Title = "Copy Selected GUID",
    Desc = "Copy current pet's GUID to clipboard",
    Icon = "copy",
    Callback = function()
        if lvlSelectedLeveling then
            setcb(lvlSelectedLeveling)
            WindUI:Notify({
                Title = "Copied",
                Content = lvlSelectedLeveling,
                Duration = 4,
                Icon = "clipboard-check",
            })
        else
            WindUI:Notify({
                Title = "Error",
                Content = "No pet selected",
                Duration = 3,
                Icon = "alert-triangle",
            })
        end
    end
})

--==============================================================--
-- AUTO LEVELING V2 TAB (Ferret)
--==============================================================--
LevelingV2Tab:Paragraph({
    Title = "🍟 Auto Leveling V2",
    Desc = "Level up with French Fry Ferret!\n• Best for level 50-100\n• Stay in one slot, no switching\n• AFK friendly",
})

LevelingV2Tab:Divider()

-- Leveling V2 Tab Variables
local v2SelectedPetToAdd = nil
local v2SelectedLeveling = nil
local v2LevelingQueue = {}
local v2CurrentQueueIndex = 1
local v2FerretSlot = 5       -- Default slot 5
local v2TargetLevel = 100    -- Default target level
-- v2AutoEnabled and v2PetEquipped declared at top (for notification access)
local v2CompletedPets = {}

-- Pet Selection
local V2LevelingDropdown = LevelingV2Tab:Dropdown({
    Title = "Select Leveling Pet",
    Desc = "Select pet to add to leveling queue",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v == "(Select Pet)" or v == "(Refresh to load)" or v == "(No pets found)" then
            v2SelectedPetToAdd = nil
            return
        end
        v2SelectedPetToAdd = v
    end
})

-- Queue Display (Green like V1)
local V2QueueParagraph = LevelingV2Tab:Paragraph({
    Title = "Queue (0 pets)",
    Desc = "(Empty - add pets above)",
    Color = "Green",
})

local function updateV2QueueDisplay()
    if #v2LevelingQueue == 0 then
        V2QueueParagraph:SetTitle("Queue (0 pets)")
        V2QueueParagraph:SetDesc("(Empty - add pets above)")
    else
        V2QueueParagraph:SetTitle(string.format("Queue (%d pets)", #v2LevelingQueue))
        local lines = {}
        for i, guid in ipairs(v2LevelingQueue) do
            local petData = getPetDataFromService(guid)
            if petData then
                local name = petData.name ~= "" and petData.name or petData.type
                local abbrev = getMutationAbbrev(petData.mutation)
                local typeStr = abbrev and (abbrev .. " " .. petData.type) or petData.type
                table.insert(lines, string.format("%d. %s (%s)", i, name, typeStr))
            else
                table.insert(lines, string.format("%d. %s", i, guid:sub(1, 20) .. "..."))
            end
        end
        V2QueueParagraph:SetDesc(table.concat(lines, "\n"))
    end
end

-- Add to Queue Button (no color, like V1)
LevelingV2Tab:Button({
    Title = "➕ Add to Queue",
    Desc = "Add selected pet to leveling queue",
    Icon = "plus",
    Callback = function()
        if not v2SelectedPetToAdd then
            WindUI:Notify({
                Title = "Error",
                Content = "Select a pet first!",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        local guid = v2SelectedPetToAdd:match("({.+})$")
        if not guid then
            WindUI:Notify({
                Title = "Error",
                Content = "Invalid pet selection",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        -- Check duplicate
        for _, g in ipairs(v2LevelingQueue) do
            if g == guid then
                WindUI:Notify({
                    Title = "Already in Queue",
                    Content = "This pet is already in the queue",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
                return
            end
        end
        
        table.insert(v2LevelingQueue, guid)
        v2SelectedLeveling = v2LevelingQueue[1]
        v2CurrentQueueIndex = 1
        updateV2QueueDisplay()
        
        local petData = getPetDataFromService(guid)
        local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
        
        WindUI:Notify({
            Title = "Added to Queue",
            Content = string.format("%s (#%d)", petName, #v2LevelingQueue),
            Duration = 3,
            Icon = "plus-circle"
        })
    end
})

-- Clear Queue Button (no color, like V1)
LevelingV2Tab:Button({
    Title = "🗑️ Clear Queue",
    Desc = "Remove all pets from queue",
    Icon = "trash",
    Callback = function()
        v2LevelingQueue = {}
        v2SelectedLeveling = nil
        v2CurrentQueueIndex = 1
        v2CompletedPets = {}
        v2TriggerCount = 0
        updateV2QueueDisplay()
        
        WindUI:Notify({
            Title = "Queue Cleared",
            Content = "All pets removed",
            Duration = 3,
            Icon = "trash-2"
        })
    end
})

-- Ferret Slot Selection
LevelingV2Tab:Dropdown({
    Title = "Ferret Slot",
    Desc = "Slot containing French Fry Ferret (2-3 recommended)",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 5",
    Callback = function(v)
        v2FerretSlot = tonumber(v:match("%d"))
    end
})

LevelingV2Tab:Divider()

-- Target Level Input
LevelingV2Tab:Input({
    Title = "Target Level",
    Desc = "Stop leveling when pet reaches this level",
    Value = "100",
    Placeholder = "Enter target level (1-100)...",
    Callback = function(input)
        local num = tonumber(input)
        if num and num >= 1 and num <= 100 then
            v2TargetLevel = num
            WindUI:Notify({
                Title = "Target Set",
                Content = string.format("Will stop at Level %d", v2TargetLevel),
                Duration = 3,
                Icon = "target"
            })
        else
            WindUI:Notify({
                Title = "Invalid",
                Content = "Enter a number between 1-100",
                Duration = 3,
                Icon = "alert-circle"
            })
        end
    end
})

-- Refresh Pet List Button (no emoji, like V1)
LevelingV2Tab:Button({
    Title = "Refresh Pet List",
    Desc = "Load all pets from your inventory",
    Icon = "refresh-cw",
    Callback = function()
        local pets = getAllPetsFromService()
        
        local values = {}
        for _, pet in ipairs(pets) do
            table.insert(values, formatPetForDropdown(pet))
        end
        
        if #pets == 0 then
            values = {"(No pets found)"}
        end
        
        V2LevelingDropdown:Refresh(values)
        V2LevelingDropdown:Select("(Select Pet)")
        
        v2SelectedPetToAdd = nil
        updateV2QueueDisplay()
        
        WindUI:Notify({
            Title = "Success",
            Content = string.format("Found %d pets!", #pets),
            Duration = 4,
            Icon = "check-circle"
        })
    end
})

LevelingV2Tab:Divider()

-- Auto Toggle
local V2AutoToggle = LevelingV2Tab:Toggle({
    Title = "Auto Level",
    Desc = "Start automatic leveling with Ferret",
    Icon = "play",
    Value = false,
    Callback = function(state)
        v2AutoEnabled = state
        
        if state then
            if #v2LevelingQueue == 0 then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Leveling Pet(s) first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                V2AutoToggle:Set(false)
                v2AutoEnabled = false
                return
            end
            
            v2PetEquipped = false
            v2CurrentQueueIndex = 1
            v2SelectedLeveling = v2LevelingQueue[1]
            v2CompletedPets = {}
            v2TriggerCount = 0
            lastFerretResult = nil
            
            -- Switch to Ferret slot
            swapTo(visualToInternal(v2FerretSlot))
            
            local petData = getPetDataFromService(v2SelectedLeveling)
            local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
            
            WindUI:Notify({
                Title = "Leveling Started",
                Content = string.format("Starting: %s (1/%d)", petName, #v2LevelingQueue),
                Duration = 4,
                Icon = "play"
            })
        else
            if v2PetEquipped and v2SelectedLeveling then
                pcall(function()
                    PetsService:FireServer("UnequipPet", v2SelectedLeveling)
                end)
                v2PetEquipped = false
                
                WindUI:Notify({
                    Title = "Pet Unequipped",
                    Content = "Leveling pet removed",
                    Duration = 3,
                    Icon = "log-out"
                })
            end
            
            WindUI:Notify({
                Title = "Leveling Stopped",
                Content = "Disabled",
                Duration = 3,
                Icon = "pause"
            })
        end
    end
})

LevelingV2Tab:Divider()

-- Status Information (Blue like V1)
local V2InfoParagraph = LevelingV2Tab:Paragraph({
    Title = "Status Information",
    Desc = "🍟 Triggers: 0\n📍 Slot: —\n🐾 Pet: —\n🏷 Type: —\n✨ Mutation: —\n📊 Age: 0/100\n📋 Queue: 0/0\n✅ Done: 0\n🔌 Equipped: ❌\n⚡ Mode: OFF",
    Color = "Blue",
})

-- Reset Progress Button (no color, like V1)
LevelingV2Tab:Button({
    Title = "🔄 Reset Progress",
    Desc = "Reset progress and start from first pet",
    Icon = "refresh-cw",
    Callback = function()
        v2CompletedPets = {}
        v2CurrentQueueIndex = 1
        v2TriggerCount = 0
        lastFerretResult = nil
        if #v2LevelingQueue > 0 then
            v2SelectedLeveling = v2LevelingQueue[1]
        end
        
        WindUI:Notify({
            Title = "Reset Complete",
            Content = "Back to Pet 1",
            Duration = 4,
            Icon = "refresh-cw"
        })
    end
})

-- Copy Selected GUID (like V1)
LevelingV2Tab:Button({
    Title = "Copy Selected GUID",
    Desc = "Copy current pet's GUID to clipboard",
    Icon = "copy",
    Callback = function()
        if v2SelectedLeveling then
            setcb(v2SelectedLeveling)
            WindUI:Notify({
                Title = "Copied",
                Content = v2SelectedLeveling,
                Duration = 4,
                Icon = "clipboard-check",
            })
        else
            WindUI:Notify({
                Title = "Error",
                Content = "No pet selected",
                Duration = 3,
                Icon = "alert-triangle",
            })
        end
    end
})

--==============================================================--
-- AUTO NIGHTMARE TAB
--==============================================================--
NightmareTab:Paragraph({
    Title = "🌙 Auto Nightmare",
    Desc = "Farm Nightmare mutations automatically!\n• Level → Mutate → Cleanse if wrong\n• Queue multiple pets\n• Auto slot switching",
})

NightmareTab:Divider()

local nmSelectedMimic = nil
local nmSelectedLeveling = nil
local nmSelectedPetToAdd = nil  -- For single dropdown selection
local levelingQueue = {}  -- Store all selected pets for multi-leveling
local currentQueueIndex = 1  -- Track current pet in queue
local nmMimicDilopSlot = 1  -- Default slot 1
local nmLevelingSlot = 2    -- Default slot 2

local NmMimicDropdown = NightmareTab:Dropdown({
    Title = "Select Mimic",
    Desc = "Select Mimic Octopus to track cooldown",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        -- Ignore placeholder
        if v == "(Select Pet)" or v == "(Refresh to load)" or v == "(No pets found)" then
            nmSelectedMimic = nil
            return
        end
        nmSelectedMimic = v:match("({.+})$")
    end
})

NightmareTab:Dropdown({
    Title = "Mimic Dilop Slot",
    Desc = "Slot containing Mimic + Dilophosaurus",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 1",
    Callback = function(v)
        nmMimicDilopSlot = tonumber(v:match("%d"))
    end
})

NightmareTab:Divider()

-- Leveling Pet Selection (Single + Queue system)
local NmLevelingDropdown = NightmareTab:Dropdown({
    Title = "Select Leveling Pet",
    Desc = "Select pet to add to leveling queue",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v ~= "(Select Pet)" and v ~= "(Refresh to load)" and v ~= "(No pets found)" then
            nmSelectedPetToAdd = v
        else
            nmSelectedPetToAdd = nil
        end
    end
})

-- Queue display
local NmQueueParagraph = NightmareTab:Paragraph({
    Title = "Queue (0 pets)",
    Desc = "(Empty - add pets above)",
    Color = "Green",
})

local function updateNmQueueDisplay()
    if #levelingQueue == 0 then
        NmQueueParagraph:SetTitle("Queue (0 pets)")
        NmQueueParagraph:SetDesc("(Empty - add pets above)")
    else
        NmQueueParagraph:SetTitle(string.format("Queue (%d pets)", #levelingQueue))
        local lines = {}
        for i, guid in ipairs(levelingQueue) do
            local petData = getPetDataFromService(guid)
            if petData then
                local name = petData.name ~= "" and petData.name or petData.type
                local abbrev = getMutationAbbrev(petData.mutation)
                local typeStr = abbrev and (abbrev .. " " .. petData.type) or petData.type
                table.insert(lines, string.format("%d. %s (%s)", i, name, typeStr))
            else
                table.insert(lines, string.format("%d. %s", i, guid:sub(1, 20) .. "..."))
            end
        end
        NmQueueParagraph:SetDesc(table.concat(lines, "\n"))
    end
end

NightmareTab:Button({
    Title = "➕ Add to Queue",
    Desc = "Add selected pet to leveling queue",
    Icon = "plus",
    Callback = function()
        if not nmSelectedPetToAdd then
            WindUI:Notify({
                Title = "Error",
                Content = "Select a pet first!",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        local guid = nmSelectedPetToAdd:match("({.+})$")
        if not guid then
            WindUI:Notify({
                Title = "Error",
                Content = "Invalid pet selection",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        -- Check duplicate
        for _, g in ipairs(levelingQueue) do
            if g == guid then
                WindUI:Notify({
                    Title = "Already in Queue",
                    Content = "This pet is already in the queue",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
                return
            end
        end
        
        table.insert(levelingQueue, guid)
        nmSelectedLeveling = levelingQueue[1]
        currentQueueIndex = 1
        updateNmQueueDisplay()
        
        local petData = getPetDataFromService(guid)
        local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
        
        WindUI:Notify({
            Title = "Added to Queue",
            Content = string.format("%s (#%d)", petName, #levelingQueue),
            Duration = 3,
            Icon = "plus-circle"
        })
    end
})

NightmareTab:Button({
    Title = "🗑️ Clear Queue",
    Desc = "Remove all pets from queue",
    Icon = "trash",
    Callback = function()
        levelingQueue = {}
        nmSelectedLeveling = nil
        currentQueueIndex = 1
        updateNmQueueDisplay()
        
        WindUI:Notify({
            Title = "Queue Cleared",
            Content = "All pets removed",
            Duration = 3,
            Icon = "trash-2"
        })
    end
})

NightmareTab:Dropdown({
    Title = "Leveling Slot",
    Desc = "Slot containing Mimic only (for leveling)",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 2",
    Callback = function(v)
        nmLevelingSlot = tonumber(v:match("%d"))
    end
})

-- Mutation Slot (Mimic + Headless)
local nmMutationSlot = 3  -- Default slot 3

NightmareTab:Dropdown({
    Title = "Mutation Slot",
    Desc = "Slot containing Mimic + Headless Horseman",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 3",
    Callback = function(v)
        nmMutationSlot = tonumber(v:match("%d"))
    end
})

NightmareTab:Divider()

-- Phase tracking: LEVELING → MUTATION → (loop or next pet)
local nmPhase = "LEVELING"  -- "LEVELING" or "MUTATION"
local nmMutationWaitTime = 0
local nmMutationChecked = false  -- Flag to prevent multiple checks
local nmCompletedPets = {}  -- Pets that got Nightmare (DONE!)

-- Target Level Setting
local targetLevel = 30

NightmareTab:Input({
    Title = "Target Level",
    Desc = "Mutate when pet reaches this level",
    Value = "30",
    Placeholder = "Enter target level...",
    Callback = function(input)
        local num = tonumber(input)
        if num and num >= 1 and num <= 100 then
            targetLevel = num
            WindUI:Notify({
                Title = "Target Set",
                Content = string.format("Will stop at Level %d", targetLevel),
                Duration = 3,
                Icon = "target"
            })
        else
            WindUI:Notify({
                Title = "Invalid",
                Content = "Enter a number between 1-100",
                Duration = 3,
                Icon = "alert-circle"
            })
        end
    end
})

NightmareTab:Button({
    Title = "Refresh Pet List",
    Desc = "Load all pets from your inventory",
    Icon = "refresh-cw",
    Callback = function()
        local pets = getAllPetsFromService()
        
        -- Build values list (pets only, no placeholder)
        local values = {}
        for _, pet in ipairs(pets) do
            table.insert(values, formatPetForDropdown(pet))
        end
        
        if #pets == 0 then
            values = {"(No pets found)"}
            NmMimicDropdown:Refresh(values)
            NmLevelingDropdown:Refresh(values)
        else
            NmMimicDropdown:Refresh(values)
            NmMimicDropdown:Select("(Select Pet)")
            
            NmLevelingDropdown:Refresh(values)
            NmLevelingDropdown:Select("(Select Pet)")
        end
        
        -- Reset selections
        nmSelectedMimic = nil
        nmSelectedPetToAdd = nil
        -- Don't reset queue on refresh, just update display
        updateNmQueueDisplay()
        
        WindUI:Notify({
            Title = "Success",
            Content = string.format("Found %d pets!", #pets),
            Duration = 4,
            Icon = "check-circle"
        })
    end
})

NightmareTab:Divider()

local nmAutoEnabled = false
local nmPetEquipped = false  -- Track if leveling pet is currently equipped

local NmAutoToggle = NightmareTab:Toggle({
    Title = "Auto Switch",
    Desc = "Automatically manage pet equip and mutations",
    Icon = "repeat",
    Value = false,
    Callback = function(state)
        nmAutoEnabled = state
        
        if state then
            -- Validate selections
            if not nmSelectedMimic then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Mimic first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                NmAutoToggle:Set(false)
                nmAutoEnabled = false
                return
            end
            
            if #levelingQueue == 0 then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Leveling Pet first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                NmAutoToggle:Set(false)
                nmAutoEnabled = false
                return
            end
            
            nmPetEquipped = false
            currentQueueIndex = 1
            nmSelectedLeveling = levelingQueue[1]
            
            local petData = getPetDataFromService(nmSelectedLeveling)
            local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
            
            WindUI:Notify({
                Title = "Auto Nightmare Started",
                Content = string.format("Starting: %s (1/%d)", petName, #levelingQueue),
                Duration = 4,
                Icon = "play"
            })
        else
            -- Unequip pet when disabled
            if nmPetEquipped and nmSelectedLeveling then
                pcall(function()
                    PetsService:FireServer("UnequipPet", nmSelectedLeveling)
                end)
                nmPetEquipped = false
                
                WindUI:Notify({
                    Title = "Pet Unequipped",
                    Content = "Leveling pet removed",
                    Duration = 3,
                    Icon = "log-out"
                })
            end
            
            WindUI:Notify({
                Title = "Auto Nightmare Stopped",
                Content = "Disabled",
                Duration = 3,
                Icon = "pause"
            })
        end
    end
})

NightmareTab:Divider()

local NmInfoParagraph = NightmareTab:Paragraph({
    Title = "Status Information",
    Desc = "📍 Phase: —\n⏱ Cooldown: —\n📍 Slot: —\n🐾 Pet: —\n🏷 Type: —\n✨ Mutation: —\n📊 Age: 0/30\n📋 Queue: 0/0\n✅ Done: 0\n🔌 Equipped: ❌\n⚡ Mode: OFF",
    Color = "Blue",
})

NightmareTab:Button({
    Title = "🔄 Reset Progress",
    Desc = "Reset progress and start from first pet",
    Icon = "refresh-cw",
    Callback = function()
        nmPhase = "LEVELING"
        nmMutationWaitTime = 0
        nmMutationChecked = false
        nmCompletedPets = {}
        currentQueueIndex = 1
        if #levelingQueue > 0 then
            nmSelectedLeveling = levelingQueue[1]
        end
        
        WindUI:Notify({
            Title = "Reset Complete",
            Content = "Back to Pet 1, Phase: LEVELING",
            Duration = 4,
            Icon = "refresh-cw"
        })
    end
})

--==============================================================--
-- AUTO ELEPHANT TAB
--==============================================================--
ElephantTab:Paragraph({
    Title = "🐘 Auto Elephant",
    Desc = "Farm weight until max cap!\n• Level → Elephant Blessing → Repeat\n• Auto stop when weight cap reached",
})

ElephantTab:Divider()

-- Elephant Tab Variables
local elSelectedMimic = nil
local elSelectedElephant = nil
local elSelectedLeveling = nil
local elSelectedPetToAdd = nil
local elLevelingQueue = {}
local elCurrentQueueIndex = 1
local elMimicDilopSlot = 1
local elLevelingSlot = 2
local elElephantSlot = 4
local elTargetLevel = 40
local elAutoEnabled = false
local elPetEquipped = false
local elCompletedPets = {}
local elPhase = "LEVELING"  -- "LEVELING" or "ELEPHANT"
local elBlessingCount = 0
local elCurrentWeight = 0
local elephantRemain = nil  -- Elephant cooldown

-- Mimic Selection (for leveling)
local ElMimicDropdown = ElephantTab:Dropdown({
    Title = "Select Mimic",
    Desc = "Select Mimic Octopus for leveling phase",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v == "(Select Pet)" or v == "(Refresh to load)" or v == "(No pets found)" then
            elSelectedMimic = nil
            return
        end
        elSelectedMimic = v:match("({.+})$")
    end
})

ElephantTab:Dropdown({
    Title = "Mimic Dilop Slot",
    Desc = "Slot containing Mimic + Dilophosaurus",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 1",
    Callback = function(v)
        elMimicDilopSlot = tonumber(v:match("%d"))
    end
})

ElephantTab:Dropdown({
    Title = "Leveling Slot",
    Desc = "Slot containing Mimic only (for leveling)",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 2",
    Callback = function(v)
        elLevelingSlot = tonumber(v:match("%d"))
    end
})

ElephantTab:Input({
    Title = "Target Level",
    Desc = "Level pet to this age before Elephant blessing",
    Value = "40",
    Placeholder = "Enter target level (1-100)...",
    Callback = function(input)
        local num = tonumber(input)
        if num and num >= 1 and num <= 100 then
            elTargetLevel = num
            WindUI:Notify({
                Title = "Target Set",
                Content = string.format("Will level to %d before blessing", elTargetLevel),
                Duration = 3,
                Icon = "target"
            })
        else
            WindUI:Notify({
                Title = "Invalid",
                Content = "Enter a number between 1-100",
                Duration = 3,
                Icon = "alert-circle"
            })
        end
    end
})

ElephantTab:Divider()

-- Elephant Selection
local ElElephantDropdown = ElephantTab:Dropdown({
    Title = "Select Elephant",
    Desc = "Select Elephant for Jumbo Blessing",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v == "(Select Pet)" or v == "(Refresh to load)" or v == "(No pets found)" then
            elSelectedElephant = nil
            return
        end
        elSelectedElephant = v:match("({.+})$")
    end
})

ElephantTab:Dropdown({
    Title = "Elephant Slot",
    Desc = "Slot containing Elephant only",
    Values = {"Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6"},
    Value = "Slot 4",
    Callback = function(v)
        elElephantSlot = tonumber(v:match("%d"))
    end
})

ElephantTab:Divider()

-- Leveling Pet Selection
local ElLevelingDropdown = ElephantTab:Dropdown({
    Title = "Select Leveling Pet",
    Desc = "Select pet to add to queue",
    Values = {"(Refresh to load)"},
    Value = "(Refresh to load)",
    SearchBarEnabled = true,
    Callback = function(v)
        if v ~= "(Select Pet)" and v ~= "(Refresh to load)" and v ~= "(No pets found)" then
            elSelectedPetToAdd = v
        else
            elSelectedPetToAdd = nil
        end
    end
})

-- Queue display
local ElQueueParagraph = ElephantTab:Paragraph({
    Title = "Queue (0 pets)",
    Desc = "(Empty - add pets above)",
    Color = "Green",
})

local function updateElQueueDisplay()
    if #elLevelingQueue == 0 then
        ElQueueParagraph:SetTitle("Queue (0 pets)")
        ElQueueParagraph:SetDesc("(Empty - add pets above)")
    else
        ElQueueParagraph:SetTitle(string.format("Queue (%d pets)", #elLevelingQueue))
        local lines = {}
        for i, guid in ipairs(elLevelingQueue) do
            local petData = getPetDataFromService(guid)
            if petData then
                local name = petData.name ~= "" and petData.name or petData.type
                local abbrev = getMutationAbbrev(petData.mutation)
                local typeStr = abbrev and (abbrev .. " " .. petData.type) or petData.type
                local weight = string.format("%.2f", petData.currentWeight or 0)
                table.insert(lines, string.format("%d. %s (%s) - %s KG", i, name, typeStr, weight))
            else
                table.insert(lines, string.format("%d. %s", i, guid:sub(1, 20) .. "..."))
            end
        end
        ElQueueParagraph:SetDesc(table.concat(lines, "\n"))
    end
end

ElephantTab:Button({
    Title = "➕ Add to Queue",
    Desc = "Add selected pet to leveling queue",
    Icon = "plus",
    Callback = function()
        if not elSelectedPetToAdd then
            WindUI:Notify({
                Title = "Error",
                Content = "Select a pet first!",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        local guid = elSelectedPetToAdd:match("({.+})$")
        if not guid then
            WindUI:Notify({
                Title = "Error",
                Content = "Invalid pet selection",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        -- Check duplicate
        for _, g in ipairs(elLevelingQueue) do
            if g == guid then
                WindUI:Notify({
                    Title = "Already in Queue",
                    Content = "This pet is already in the queue",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
                return
            end
        end
        
        table.insert(elLevelingQueue, guid)
        elSelectedLeveling = elLevelingQueue[1]
        elCurrentQueueIndex = 1
        updateElQueueDisplay()
        
        local petData = getPetDataFromService(guid)
        local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
        
        WindUI:Notify({
            Title = "Added to Queue",
            Content = string.format("%s (#%d)", petName, #elLevelingQueue),
            Duration = 3,
            Icon = "plus-circle"
        })
    end
})

ElephantTab:Button({
    Title = "🗑️ Clear Queue",
    Desc = "Remove all pets from queue",
    Icon = "trash",
    Callback = function()
        elLevelingQueue = {}
        elSelectedLeveling = nil
        elCurrentQueueIndex = 1
        updateElQueueDisplay()
        
        WindUI:Notify({
            Title = "Queue Cleared",
            Content = "All pets removed",
            Duration = 3,
            Icon = "trash-2"
        })
    end
})

ElephantTab:Divider()

ElephantTab:Button({
    Title = "Refresh Pet List",
    Desc = "Load all pets from your inventory",
    Icon = "refresh-cw",
    Callback = function()
        local pets = getAllPetsFromService()
        
        local values = {}
        for _, pet in ipairs(pets) do
            table.insert(values, formatPetForDropdown(pet))
        end
        
        if #pets == 0 then
            values = {"(No pets found)"}
            ElMimicDropdown:Refresh(values)
            ElElephantDropdown:Refresh(values)
            ElLevelingDropdown:Refresh(values)
        else
            ElMimicDropdown:Refresh(values)
            ElMimicDropdown:Select("(Select Pet)")
            
            ElElephantDropdown:Refresh(values)
            ElElephantDropdown:Select("(Select Pet)")
            
            ElLevelingDropdown:Refresh(values)
            ElLevelingDropdown:Select("(Select Pet)")
        end
        
        elSelectedMimic = nil
        elSelectedElephant = nil
        elSelectedPetToAdd = nil
        updateElQueueDisplay()
        
        WindUI:Notify({
            Title = "Success",
            Content = string.format("Found %d pets!", #pets),
            Duration = 4,
            Icon = "check-circle"
        })
    end
})

ElephantTab:Divider()

local ElAutoToggle = ElephantTab:Toggle({
    Title = "Auto Switch",
    Desc = "Automatically level and get elephant blessings",
    Icon = "repeat",
    Value = false,
    Callback = function(state)
        elAutoEnabled = state
        
        if state then
            if not elSelectedMimic then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Mimic first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                ElAutoToggle:Set(false)
                elAutoEnabled = false
                return
            end
            
            if not elSelectedElephant then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Select Elephant first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                ElAutoToggle:Set(false)
                elAutoEnabled = false
                return
            end
            
            if #elLevelingQueue == 0 then
                WindUI:Notify({
                    Title = "Error",
                    Content = "Add pets to queue first!",
                    Duration = 4,
                    Icon = "alert-circle"
                })
                ElAutoToggle:Set(false)
                elAutoEnabled = false
                return
            end
            
            elPetEquipped = false
            elCurrentQueueIndex = 1
            elSelectedLeveling = elLevelingQueue[1]
            elPhase = "LEVELING"
            elBlessingCount = 0
            
            local petData = getPetDataFromService(elSelectedLeveling)
            local petName = petData and (petData.name ~= "" and petData.name or petData.type) or "Unknown"
            
            WindUI:Notify({
                Title = "Auto Elephant Started",
                Content = string.format("Starting: %s (1/%d)", petName, #elLevelingQueue),
                Duration = 4,
                Icon = "play"
            })
        else
            if elPetEquipped and elSelectedLeveling then
                pcall(function()
                    PetsService:FireServer("UnequipPet", elSelectedLeveling)
                end)
                elPetEquipped = false
                
                WindUI:Notify({
                    Title = "Pet Unequipped",
                    Content = "Pet has been unequipped",
                    Duration = 3,
                    Icon = "log-out"
                })
            end
            
            WindUI:Notify({
                Title = "Auto Elephant Stopped",
                Content = "Disabled",
                Duration = 3,
                Icon = "pause"
            })
        end
    end
})

ElephantTab:Divider()

local ElInfoParagraph = ElephantTab:Paragraph({
    Title = "Status Information",
    Desc = "📍 Phase: —\n⏱ Mimic CD: —\n⏱ Elephant CD: —\n📍 Slot: —\n🐾 Pet: —\n🏷 Type: —\n📊 Age: 0/40\n⚖️ Weight: 0.00 KG\n🔄 Blessings: 0\n📋 Queue: 0/0\n✅ Done: 0\n⚡ Mode: OFF",
    Color = "Blue",
})

ElephantTab:Button({
    Title = "🔄 Reset Progress",
    Desc = "Reset progress and start from first pet",
    Icon = "refresh-cw",
    Callback = function()
        elPhase = "LEVELING"
        elBlessingCount = 0
        elCompletedPets = {}
        elCurrentQueueIndex = 1
        if #elLevelingQueue > 0 then
            elSelectedLeveling = elLevelingQueue[1]
        end
        
        WindUI:Notify({
            Title = "Reset Complete",
            Content = "Back to Pet 1, Phase: LEVELING",
            Duration = 4,
            Icon = "refresh-cw"
        })
    end
})

--==============================================================--
-- LOGIC: Cooldown Tracking
--==============================================================--
local READY_EPS          = 0.05
local READY_HOLD_SEC     = 0.30
local POLL_SEC           = 2.5
local TICK_SEC           = 0.25

local mimicRemain = nil
local elephantRemain = nil  -- Elephant cooldown
local currentSlot = 1
local readyHoldTimer = 0

-- event cooldown
if PetCooldownsUpdated then
    PetCooldownsUpdated.OnClientEvent:Connect(function(a,b)
        -- Check all possible mimic GUIDs
        local lvlKey = lvlSelectedMimic and normGuid(lvlSelectedMimic) or nil
        local nmKey = nmSelectedMimic and normGuid(nmSelectedMimic) or nil
        local elMimicKey = elSelectedMimic and normGuid(elSelectedMimic) or nil
        local elElephantKey = elSelectedElephant and normGuid(elSelectedElephant) or nil
        
        local function tryMimic(a_, b_, key)
            if a_ and b_ and normGuid(a_) == key then
                local s = pickSeconds(b_)
                if s~=nil then 
                    mimicRemain=s
                end
                return true
            end
            return false
        end
        
        local function tryElephant(a_, b_, key)
            if a_ and b_ and normGuid(a_) == key then
                local s = pickSeconds(b_)
                if s~=nil then 
                    elephantRemain=s
                end
                return true
            end
            return false
        end
        
        -- Try matching mimic cooldowns
        if lvlKey and tryMimic(a, b, lvlKey) then end
        if nmKey and tryMimic(a, b, nmKey) then end
        if elMimicKey and tryMimic(a, b, elMimicKey) then end
        
        -- Try matching elephant cooldown
        if elElephantKey and tryElephant(a, b, elElephantKey) then end
        
        if type(a)=="table" and not b then
            for k,v in pairs(a) do
                local nk = normGuid(k)
                -- Check mimic cooldowns
                if nk == lvlKey or nk == nmKey or nk == elMimicKey then
                    local s = pickSeconds(v)
                    if s~=nil then 
                        mimicRemain=s
                    end
                end
                -- Check elephant cooldown
                if nk == elElephantKey then
                    local s = pickSeconds(v)
                    if s~=nil then 
                        elephantRemain=s
                    end
                end
            end
        end
    end)
end

-- polling cooldown periodik
task.spawn(function()
    while true do
        if RequestPetCooldowns then
            pcall(function() RequestPetCooldowns:FireServer() end)
            -- Request for all tabs' selected pets
            if lvlSelectedMimic then
                pcall(function() RequestPetCooldowns:FireServer(lvlSelectedMimic) end)
            end
            if nmSelectedMimic then
                pcall(function() RequestPetCooldowns:FireServer(nmSelectedMimic) end)
            end
            if elSelectedMimic then
                pcall(function() RequestPetCooldowns:FireServer(elSelectedMimic) end)
            end
            if elSelectedElephant then
                pcall(function() RequestPetCooldowns:FireServer(elSelectedElephant) end)
            end
        end
        task.wait(POLL_SEC)
    end
end)

-- Get initial slot from DataService
currentSlot = getCurrentSlotFromService() or 1

-- Main loop
task.spawn(function()
    while true do
        task.wait(TICK_SEC)

        -- decay sederhana
        if type(mimicRemain)=="number" then
            mimicRemain = math.max(0, mimicRemain - TICK_SEC)
        end
        if type(elephantRemain)=="number" then
            elephantRemain = math.max(0, elephantRemain - TICK_SEC)
        end
        
        -- Get REAL-TIME current slot from DataService
        local realSlot = getCurrentSlotFromService()
        if realSlot then
            currentSlot = realSlot
        end
        
        -- Convert DataService slot to visual slot (2 and 3 are swapped)
        local visualSlot = currentSlot
        if currentSlot == 2 then visualSlot = 3
        elseif currentSlot == 3 then visualSlot = 2
        end

        local cdTxt = (mimicRemain and string.format("%.2fs", mimicRemain) or "—")
        local slotTxt = string.format("Slot %d", visualSlot)
        
        --==============================================================--
        -- LEVELING TAB UI Update
        --==============================================================--
        local lvlModeTxt = lvlAutoEnabled and "🟢 ON" or "🔴 OFF"
        local lvlPetData = getPetDataFromService(lvlSelectedLeveling)
        local lvlPetName = lvlPetData and (lvlPetData.name ~= "" and lvlPetData.name or "—") or "—"
        local lvlPetType = lvlPetData and lvlPetData.type or "—"
        local lvlPetAge = lvlPetData and lvlPetData.age or 0
        local lvlPetMutation = lvlPetData and lvlPetData.mutation or "—"
        
        local lvlMutationEmoji = ""
        if lvlPetMutation == "Nightmare" then lvlMutationEmoji = "🌙 "
        elseif lvlPetMutation == "Rainbow" then lvlMutationEmoji = "🌈 "
        elseif lvlPetMutation == "Golden" then lvlMutationEmoji = "✨ "
        elseif lvlPetMutation == "Shiny" then lvlMutationEmoji = "💎 "
        elseif lvlPetMutation == "Normal" or lvlPetMutation == "None" then lvlMutationEmoji = ""
        elseif lvlPetMutation ~= "—" then lvlMutationEmoji = "⚡ "
        end
        
        local lvlEquippedTxt = lvlPetEquipped and "✅ Yes" or "❌ No"
        local lvlQueueTxt = #lvlLevelingQueue > 0 and string.format("%d/%d", lvlCurrentQueueIndex, #lvlLevelingQueue) or "0/0"
        
        LvlInfoParagraph:SetDesc(string.format(
            "⏱ Cooldown: %s\n📍 Slot: %s\n🐾 Pet: %s\n🏷 Type: %s\n✨ Mutation: %s%s\n📊 Age: %d/%d\n📋 Queue: %s\n✅ Done: %d\n🔌 Equipped: %s\n⚡ Mode: %s",
            cdTxt,
            slotTxt,
            lvlPetName,
            lvlPetType,
            lvlMutationEmoji,
            lvlPetMutation,
            lvlPetAge,
            lvlTargetLevel,
            lvlQueueTxt,
            #lvlCompletedPets,
            lvlEquippedTxt,
            lvlModeTxt
        ))
        
        --==============================================================--
        -- LEVELING TAB Logic
        --==============================================================--
        if lvlAutoEnabled and lvlSelectedLeveling then
            -- Auto EQUIP when on Leveling Slot
            if visualSlot == lvlLevelingSlot and not lvlPetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", lvlSelectedLeveling, CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                end)
                lvlPetEquipped = true
                
                WindUI:Notify({
                    Title = "🐾 Pet Equipped",
                    Content = string.format("%s (%d/%d)", lvlPetName, lvlCurrentQueueIndex, #lvlLevelingQueue),
                    Duration = 3,
                    Icon = "plus-circle"
                })
            end
            
            -- Auto UNEQUIP when on Mimic Dilop Slot
            if visualSlot == lvlMimicDilopSlot and lvlPetEquipped then
                pcall(function()
                    PetsService:FireServer("UnequipPet", lvlSelectedLeveling)
                end)
                lvlPetEquipped = false
            end
            
            -- Check if pet reached target level → Move to next pet
            if lvlPetAge >= lvlTargetLevel then
                -- Unequip pet first
                if lvlPetEquipped then
                    pcall(function()
                        PetsService:FireServer("UnequipPet", lvlSelectedLeveling)
                    end)
                    lvlPetEquipped = false
                end
                
                WindUI:Notify({
                    Title = "✅ Level Complete!",
                    Content = string.format("%s reached Level %d!", lvlPetName, lvlTargetLevel),
                    Duration = 5,
                    Icon = "check-circle"
                })
                
                -- Webhook: Level Complete
                sendWebhook(
                    "✅ Level Complete!",
                    "Pet has reached target level",
                    5763719,
                    {
                        {name = "🐾 Pet", value = lvlPetName, inline = true},
                        {name = "🏷 Type", value = lvlPetType, inline = true},
                        {name = "📊 Level", value = tostring(lvlTargetLevel), inline = true},
                        {name = "📋 Queue", value = string.format("%d/%d", lvlCurrentQueueIndex, #lvlLevelingQueue), inline = true},
                    }
                )
                
                -- Add to completed
                table.insert(lvlCompletedPets, lvlSelectedLeveling)
                
                -- Move to next pet in queue
                if lvlCurrentQueueIndex < #lvlLevelingQueue then
                    lvlCurrentQueueIndex = lvlCurrentQueueIndex + 1
                    lvlSelectedLeveling = lvlLevelingQueue[lvlCurrentQueueIndex]
                    
                    local nextPetData = getPetDataFromService(lvlSelectedLeveling)
                    local nextPetName = nextPetData and (nextPetData.name ~= "" and nextPetData.name or nextPetData.type) or "Unknown"
                    
                    WindUI:Notify({
                        Title = "🔄 Next Pet",
                        Content = string.format("Now leveling: %s (%d/%d)", nextPetName, lvlCurrentQueueIndex, #lvlLevelingQueue),
                        Duration = 5,
                        Icon = "arrow-right"
                    })
                else
                    -- ALL DONE!
                    lvlAutoEnabled = false
                    LvlAutoToggle:Set(false)
                    
                    WindUI:Notify({
                        Title = "🎉 ALL COMPLETE!",
                        Content = string.format("All %d pets reached Level %d!", #lvlCompletedPets, lvlTargetLevel),
                        Duration = 15,
                        Icon = "award"
                    })
                    
                    -- Webhook: All Complete (Leveling)
                    sendWebhook(
                        "🎉 ALL COMPLETE!",
                        "All pets in queue have been leveled!",
                        5814783,
                        {
                            {name = "✅ Completed", value = string.format("%d pets", #lvlCompletedPets), inline = true},
                            {name = "📊 Target", value = string.format("Level %d", lvlTargetLevel), inline = true},
                            {name = "📋 Mode", value = "Leveling", inline = true},
                        }
                    )
                end
            end
        end
        
        --==============================================================--
        -- LEVELING V2 TAB UI Update
        --==============================================================--
        local v2ModeTxt = v2AutoEnabled and "🟢 ON" or "🔴 OFF"
        local v2PetData = getPetDataFromService(v2SelectedLeveling)
        local v2PetName = v2PetData and (v2PetData.name ~= "" and v2PetData.name or "—") or "—"
        local v2PetType = v2PetData and v2PetData.type or "—"
        local v2PetAge = v2PetData and v2PetData.age or 0
        local v2PetMutation = v2PetData and v2PetData.mutation or "—"
        
        local v2MutationEmoji = ""
        if v2PetMutation == "Nightmare" then v2MutationEmoji = "🌙 "
        elseif v2PetMutation == "Rainbow" then v2MutationEmoji = "🌈 "
        elseif v2PetMutation == "Golden" then v2MutationEmoji = "✨ "
        elseif v2PetMutation == "Shiny" then v2MutationEmoji = "💎 "
        elseif v2PetMutation == "Normal" or v2PetMutation == "None" then v2MutationEmoji = ""
        elseif v2PetMutation ~= "—" then v2MutationEmoji = "⚡ "
        end
        
        local v2EquipTxt = v2PetEquipped and "✅ Yes" or "❌ No"
        local v2QueueDisplay = #v2LevelingQueue > 0 and string.format("%d/%d", v2CurrentQueueIndex, #v2LevelingQueue) or "0/0"
        
        if V2InfoParagraph then
            V2InfoParagraph:SetDesc(string.format(
                "🍟 Triggers: %d\n📍 Slot: %s\n🐾 Pet: %s\n🏷 Type: %s\n✨ Mutation: %s%s\n📊 Age: %d/%d\n📋 Queue: %s\n✅ Done: %d\n🔌 Equipped: %s\n⚡ Mode: %s",
                v2TriggerCount,
                slotTxt,
                v2PetName,
                v2PetType,
                v2MutationEmoji,
                v2PetMutation,
                v2PetAge,
                v2TargetLevel,
                v2QueueDisplay,
                #v2CompletedPets,
                v2EquipTxt,
                v2ModeTxt
            ))
        end
        
        --==============================================================--
        -- LEVELING V2 TAB Logic
        --==============================================================--
        if v2AutoEnabled and v2SelectedLeveling and #v2LevelingQueue > 0 then
            local v2CurrentPetData = getPetDataFromService(v2SelectedLeveling)
            local v2CurrentAge = v2CurrentPetData and v2CurrentPetData.age or 0
            local v2CurrentName = v2CurrentPetData and (v2CurrentPetData.name ~= "" and v2CurrentPetData.name or v2CurrentPetData.type) or "Unknown"
            local v2CurrentType = v2CurrentPetData and v2CurrentPetData.type or "Unknown"
            
            -- Equip pet if not equipped
            if not v2PetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", v2SelectedLeveling)
                end)
                v2PetEquipped = true
                lastFerretResult = nil
            end
            
            -- Check if pet reached target level OR max level notification
            if v2CurrentAge >= v2TargetLevel or lastFerretResult == "MaxLevel" then
                -- Unequip pet
                if v2PetEquipped then
                    pcall(function()
                        PetsService:FireServer("UnequipPet", v2SelectedLeveling)
                    end)
                    v2PetEquipped = false
                end
                
                local completionReason = lastFerretResult == "MaxLevel" and "Max Level 100!" or string.format("Level %d!", v2TargetLevel)
                
                WindUI:Notify({
                    Title = "✅ Level Complete!",
                    Content = string.format("%s reached %s", v2CurrentName, completionReason),
                    Duration = 5,
                    Icon = "check-circle"
                })
                
                -- Webhook: Level Complete (V2)
                sendWebhook(
                    "✅ Level Complete!",
                    "Pet has reached target level",
                    5763719,
                    {
                        {name = "🐾 Pet", value = v2CurrentName, inline = true},
                        {name = "🏷 Type", value = v2CurrentType, inline = true},
                        {name = "📊 Level", value = tostring(v2CurrentAge), inline = true},
                        {name = "🍟 Triggers", value = tostring(v2TriggerCount), inline = true},
                        {name = "📋 Queue", value = string.format("%d/%d", v2CurrentQueueIndex, #v2LevelingQueue), inline = true},
                        {name = "📍 Mode", value = "Auto Leveling V2", inline = true},
                    }
                )
                
                -- Add to completed
                table.insert(v2CompletedPets, v2SelectedLeveling)
                lastFerretResult = nil
                
                -- Move to next pet in queue
                if v2CurrentQueueIndex < #v2LevelingQueue then
                    v2CurrentQueueIndex = v2CurrentQueueIndex + 1
                    v2SelectedLeveling = v2LevelingQueue[v2CurrentQueueIndex]
                    v2TriggerCount = 0  -- Reset trigger count for new pet
                    
                    local nextPetData = getPetDataFromService(v2SelectedLeveling)
                    local nextPetName = nextPetData and (nextPetData.name ~= "" and nextPetData.name or nextPetData.type) or "Unknown"
                    
                    WindUI:Notify({
                        Title = "🔄 Next Pet",
                        Content = string.format("Now leveling: %s (%d/%d)", nextPetName, v2CurrentQueueIndex, #v2LevelingQueue),
                        Duration = 5,
                        Icon = "arrow-right"
                    })
                else
                    -- ALL DONE!
                    v2AutoEnabled = false
                    V2AutoToggle:Set(false)
                    
                    WindUI:Notify({
                        Title = "🎉 ALL COMPLETE!",
                        Content = string.format("All %d pets reached target level!", #v2CompletedPets),
                        Duration = 15,
                        Icon = "award"
                    })
                    
                    -- Webhook: All Complete (V2)
                    sendWebhook(
                        "🎉 ALL COMPLETE!",
                        "All pets in queue have been leveled!",
                        5814783,
                        {
                            {name = "✅ Completed", value = string.format("%d pets", #v2CompletedPets), inline = true},
                            {name = "📊 Target", value = string.format("Level %d", v2TargetLevel), inline = true},
                            {name = "📍 Mode", value = "Auto Leveling V2", inline = true},
                        }
                    )
                end
            end
        end
        
        --==============================================================--
        -- NIGHTMARE TAB UI Update
        --==============================================================--
        local nmModeTxt = nmAutoEnabled and "🟢 ON" or "🔴 OFF"
        local petData = getPetDataFromService(nmSelectedLeveling)
        local petName = petData and (petData.name ~= "" and petData.name or "—") or "—"
        local petType = petData and petData.type or "—"
        local petAge = petData and petData.age or 0
        local petMutation = petData and petData.mutation or "—"
        
        local mutationEmoji = ""
        if petMutation == "Nightmare" then mutationEmoji = "🌙 "
        elseif petMutation == "Rainbow" then mutationEmoji = "🌈 "
        elseif petMutation == "Golden" then mutationEmoji = "✨ "
        elseif petMutation == "Shiny" then mutationEmoji = "💎 "
        elseif petMutation == "Normal" or petMutation == "None" then mutationEmoji = ""
        elseif petMutation ~= "—" then mutationEmoji = "⚡ "
        end
        
        local phaseTxt = nmPhase == "MUTATION" and "🌙 MUTATION" or "📈 LEVELING"
        local equippedTxt = nmPetEquipped and "✅ Yes" or "❌ No"
        local queueTxt = #levelingQueue > 0 and string.format("%d/%d", currentQueueIndex, #levelingQueue) or "0/0"
        
        NmInfoParagraph:SetDesc(string.format(
            "📍 Phase: %s\n⏱ Cooldown: %s\n📍 Slot: %s\n🐾 Pet: %s\n🏷 Type: %s\n✨ Mutation: %s%s\n📊 Age: %d/%d\n📋 Queue: %s\n✅ Done: %d\n🔌 Equipped: %s\n⚡ Mode: %s",
            phaseTxt,
            cdTxt,
            slotTxt,
            petName,
            petType,
            mutationEmoji,
            petMutation,
            petAge,
            targetLevel,
            queueTxt,
            #nmCompletedPets,
            equippedTxt,
            nmModeTxt
        ))
        
        --==============================================================--
        -- PHASE 1: LEVELING - Level current pet to target
        --==============================================================--
        if nmPhase == "LEVELING" and nmAutoEnabled and nmSelectedLeveling then
            -- Auto EQUIP when on Leveling Slot
            if visualSlot == nmLevelingSlot and not nmPetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", nmSelectedLeveling, CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                end)
                nmPetEquipped = true
                
                WindUI:Notify({
                    Title = "🐾 Pet Equipped",
                    Content = string.format("%s (%d/%d) - Leveling", petName, currentQueueIndex, #levelingQueue),
                    Duration = 3,
                    Icon = "plus-circle"
                })
            end
            
            -- Auto UNEQUIP when on Mimic Dilop Slot
            if visualSlot == nmMimicDilopSlot and nmPetEquipped then
                pcall(function()
                    PetsService:FireServer("UnequipPet", nmSelectedLeveling)
                end)
                nmPetEquipped = false
            end
            
            -- Check if pet reached target level → Switch to MUTATION phase
            if petAge >= targetLevel then
                -- Unequip pet first
                if nmPetEquipped then
                    pcall(function()
                        PetsService:FireServer("UnequipPet", nmSelectedLeveling)
                    end)
                    nmPetEquipped = false
                end
                
                -- Switch to MUTATION phase
                nmPhase = "MUTATION"
                nmMutationWaitTime = 0
                nmMutationChecked = false
                
                WindUI:Notify({
                    Title = "🌙 MUTATION PHASE",
                    Content = string.format("%s reached Lvl %d! Going to mutation...", petName, targetLevel),
                    Duration = 5,
                    Icon = "moon"
                })
                
                -- Swap to Mutation Slot
                task.wait(0.5)
                swapTo(visualToInternal(nmMutationSlot))
            end
        end
        
        --==============================================================--
        -- PHASE 2: MUTATION - Get Nightmare from Headless
        --==============================================================--
        if nmPhase == "MUTATION" and nmAutoEnabled and nmSelectedLeveling then
            -- Make sure we're on Mutation Slot
            if visualSlot ~= nmMutationSlot then
                swapTo(visualToInternal(nmMutationSlot))
            end
            
            -- Auto EQUIP pet on Mutation Slot
            if visualSlot == nmMutationSlot and not nmPetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", nmSelectedLeveling, CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                end)
                nmPetEquipped = true
                lastMutationResult = nil
                lastMutationName = nil
                
                WindUI:Notify({
                    Title = "🐾 Mutation: Pet Equipped",
                    Content = "Waiting for Headless skill...",
                    Duration = 3,
                    Icon = "moon"
                })
            end
            
            -- Check if mutation was detected via Notification
            if nmPetEquipped and lastMutationResult then
                task.wait(1)
                
                local freshPetData = getPetDataFromService(nmSelectedLeveling)
                local freshPetName = freshPetData and (freshPetData.name ~= "" and freshPetData.name or freshPetData.type) or "Unknown"
                
                if lastMutationResult == "Nightmare" then
                    -- ✅ SUCCESS! Got Nightmare!
                    WindUI:Notify({
                        Title = "🌙 NIGHTMARE GET!",
                        Content = string.format("%s got Nightmare! 🌙", freshPetName),
                        Duration = 8,
                        Icon = "check-circle"
                    })
                    
                    -- Webhook: Nightmare Get
                    local freshType = freshPetData and freshPetData.type or "Unknown"
                    sendWebhook(
                        "🌙 Nightmare Get!",
                        "Pet successfully mutated to Nightmare!",
                        9498256,
                        {
                            {name = "🐾 Pet", value = freshPetName, inline = true},
                            {name = "🏷 Type", value = freshType, inline = true},
                            {name = "✨ Mutation", value = "Nightmare", inline = true},
                            {name = "📋 Queue", value = string.format("%d/%d", currentQueueIndex, #levelingQueue), inline = true},
                            {name = "✅ Done", value = string.format("%d pets", #nmCompletedPets + 1), inline = true},
                        }
                    )
                    
                    task.wait(1)
                    
                    pcall(function()
                        PetsService:FireServer("UnequipPet", nmSelectedLeveling)
                    end)
                    nmPetEquipped = false
                    lastMutationResult = nil
                    lastMutationName = nil
                    
                    table.insert(nmCompletedPets, nmSelectedLeveling)
                    
                    if currentQueueIndex < #levelingQueue then
                        currentQueueIndex = currentQueueIndex + 1
                        nmSelectedLeveling = levelingQueue[currentQueueIndex]
                        nmPhase = "LEVELING"
                        
                        local nextPetData = getPetDataFromService(nmSelectedLeveling)
                        local nextPetName = nextPetData and (nextPetData.name ~= "" and nextPetData.name or nextPetData.type) or "Unknown"
                        
                        WindUI:Notify({
                            Title = "🔄 Next Pet",
                            Content = string.format("Now leveling: %s (%d/%d)", nextPetName, currentQueueIndex, #levelingQueue),
                            Duration = 5,
                            Icon = "arrow-right"
                        })
                        
                        task.wait(1)
                        swapTo(visualToInternal(nmMimicDilopSlot))
                    else
                        nmAutoEnabled = false
                        NmAutoToggle:Set(false)
                        nmPhase = "LEVELING"
                        
                        WindUI:Notify({
                            Title = "🎉 ALL COMPLETE!",
                            Content = string.format("All %d pets got Nightmare! 🌙", #nmCompletedPets),
                            Duration = 15,
                            Icon = "award"
                        })
                        
                        -- Webhook: All Complete (Nightmare)
                        sendWebhook(
                            "🎉 ALL COMPLETE!",
                            "All pets got Nightmare mutation!",
                            5814783,
                            {
                                {name = "✅ Completed", value = string.format("%d pets", #nmCompletedPets), inline = true},
                                {name = "✨ Mutation", value = "Nightmare", inline = true},
                                {name = "📋 Mode", value = "Auto Nightmare", inline = true},
                            }
                        )
                    end
                else
                    -- ❌ Wrong mutation, cleanse and re-level
                    WindUI:Notify({
                        Title = "❌ Wrong Mutation",
                        Content = string.format("%s got %s instead. Cleansing...", freshPetName, lastMutationName or "Unknown"),
                        Duration = 5,
                        Icon = "x-circle"
                    })
                    
                    task.wait(2)
                    
                    local success, msg = applyCleansingShardToPet(nmSelectedLeveling)
                    
                    if success then
                        WindUI:Notify({
                            Title = "🧹 Cleansed",
                            Content = string.format("%s cleansed. Back to leveling...", freshPetName),
                            Duration = 5,
                            Icon = "refresh-cw"
                        })
                        
                        task.wait(2)
                        
                        pcall(function()
                            PetsService:FireServer("UnequipPet", nmSelectedLeveling)
                        end)
                        nmPetEquipped = false
                        lastMutationResult = nil
                        lastMutationName = nil
                        
                        nmPhase = "LEVELING"
                        
                        task.wait(1)
                        swapTo(visualToInternal(nmMimicDilopSlot))
                    else
                        WindUI:Notify({
                            Title = "⚠️ Cleanse Failed",
                            Content = msg,
                            Duration = 5,
                            Icon = "alert-triangle"
                        })
                        lastMutationResult = nil
                        lastMutationName = nil
                    end
                end
            end
        end
        
        --==============================================================--
        -- ELEPHANT TAB UI Update
        --==============================================================--
        local elModeTxt = elAutoEnabled and "🟢 ON" or "🔴 OFF"
        local elPetData = getPetDataFromService(elSelectedLeveling)
        local elPetName = elPetData and (elPetData.name ~= "" and elPetData.name or "—") or "—"
        local elPetType = elPetData and elPetData.type or "—"
        local elPetAge = elPetData and elPetData.age or 0
        local elPetWeight = elPetData and elPetData.currentWeight or 0
        
        local elPhaseTxt = elPhase == "ELEPHANT" and "🐘 ELEPHANT" or "📈 LEVELING"
        local elEquippedTxt = elPetEquipped and "✅ Yes" or "❌ No"
        local elQueueTxt = #elLevelingQueue > 0 and string.format("%d/%d", elCurrentQueueIndex, #elLevelingQueue) or "0/0"
        local elMimicCdTxt = (mimicRemain and string.format("%.2fs", mimicRemain) or "—")
        local elElephantCdTxt = (elephantRemain and string.format("%.2fs", elephantRemain) or "—")
        
        ElInfoParagraph:SetDesc(string.format(
            "📍 Phase: %s\n⏱ Mimic CD: %s\n⏱ Elephant CD: %s\n📍 Slot: %s\n🐾 Pet: %s\n🏷 Type: %s\n📊 Age: %d/%d\n⚖️ Weight: %.2f KG\n🔄 Blessings: %d\n📋 Queue: %s\n✅ Done: %d\n🔌 Equipped: %s\n⚡ Mode: %s",
            elPhaseTxt,
            elMimicCdTxt,
            elElephantCdTxt,
            slotTxt,
            elPetName,
            elPetType,
            elPetAge,
            elTargetLevel,
            elPetWeight,
            elBlessingCount,
            elQueueTxt,
            #elCompletedPets,
            elEquippedTxt,
            elModeTxt
        ))
        
        --==============================================================--
        -- ELEPHANT TAB Logic - PHASE 1: LEVELING
        --==============================================================--
        if elPhase == "LEVELING" and elAutoEnabled and elSelectedLeveling then
            -- Auto EQUIP when on Leveling Slot
            if visualSlot == elLevelingSlot and not elPetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", elSelectedLeveling, CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                end)
                elPetEquipped = true
                
                WindUI:Notify({
                    Title = "🐾 Pet Equipped",
                    Content = string.format("%s (%d/%d) - Leveling", elPetName, elCurrentQueueIndex, #elLevelingQueue),
                    Duration = 3,
                    Icon = "plus-circle"
                })
            end
            
            -- Auto UNEQUIP when on Mimic Dilop Slot
            if visualSlot == elMimicDilopSlot and elPetEquipped then
                pcall(function()
                    PetsService:FireServer("UnequipPet", elSelectedLeveling)
                end)
                elPetEquipped = false
            end
            
            -- Check if target level reached
            if elPetAge >= elTargetLevel then
                -- Target reached! Switch to ELEPHANT phase
                elPhase = "ELEPHANT"
                lastElephantResult = nil
                lastElephantWeight = nil
                
                WindUI:Notify({
                    Title = "📈 Level Reached!",
                    Content = string.format("%s reached Level %d! Switching to Elephant...", elPetName, elTargetLevel),
                    Duration = 5,
                    Icon = "trending-up"
                })
                
                -- Unequip first
                if elPetEquipped then
                    pcall(function()
                        PetsService:FireServer("UnequipPet", elSelectedLeveling)
                    end)
                    elPetEquipped = false
                end
                
                task.wait(1)
                swapTo(visualToInternal(elElephantSlot))
            end
        end
        
        --==============================================================--
        -- ELEPHANT TAB Logic - PHASE 2: ELEPHANT
        --==============================================================--
        if elPhase == "ELEPHANT" and elAutoEnabled and elSelectedLeveling then
            -- Switch to Elephant Slot if not already there
            if visualSlot ~= elElephantSlot then
                swapTo(visualToInternal(elElephantSlot))
            end
            
            -- Auto EQUIP pet on Elephant Slot
            if visualSlot == elElephantSlot and not elPetEquipped then
                pcall(function()
                    PetsService:FireServer("EquipPet", elSelectedLeveling, CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                end)
                elPetEquipped = true
                lastElephantResult = nil
                lastElephantWeight = nil
                
                WindUI:Notify({
                    Title = "🐘 Elephant: Pet Equipped",
                    Content = "Waiting for Jumbo Blessing...",
                    Duration = 3,
                    Icon = "zap"
                })
            end
            
            -- Check if blessing was detected via Notification
            if elPetEquipped and lastElephantResult then
                task.wait(1)
                
                local freshPetData = getPetDataFromService(elSelectedLeveling)
                local freshPetName = freshPetData and (freshPetData.name ~= "" and freshPetData.name or freshPetData.type) or "Unknown"
                local freshWeight = freshPetData and freshPetData.currentWeight or 0
                
                if lastElephantResult == "MaxWeight" then
                    -- ✅ MAX WEIGHT REACHED! Pet is done!
                    WindUI:Notify({
                        Title = "🐘 MAX WEIGHT!",
                        Content = string.format("%s reached max weight cap! 🎉", freshPetName),
                        Duration = 8,
                        Icon = "check-circle"
                    })
                    
                    -- Webhook: Max Weight
                    local freshType = freshPetData and freshPetData.type or "Unknown"
                    sendWebhook(
                        "🐘 Max Weight Reached!",
                        "Pet has reached maximum weight cap!",
                        16776960,
                        {
                            {name = "🐾 Pet", value = freshPetName, inline = true},
                            {name = "🏷 Type", value = freshType, inline = true},
                            {name = "⚖️ Weight", value = string.format("%.2f KG", freshWeight), inline = true},
                            {name = "🔄 Blessings", value = tostring(elBlessingCount), inline = true},
                            {name = "📋 Queue", value = string.format("%d/%d", elCurrentQueueIndex, #elLevelingQueue), inline = true},
                            {name = "✅ Done", value = string.format("%d pets", #elCompletedPets + 1), inline = true},
                        }
                    )
                    
                    task.wait(1)
                    
                    pcall(function()
                        PetsService:FireServer("UnequipPet", elSelectedLeveling)
                    end)
                    elPetEquipped = false
                    lastElephantResult = nil
                    lastElephantWeight = nil
                    
                    table.insert(elCompletedPets, elSelectedLeveling)
                    
                    if elCurrentQueueIndex < #elLevelingQueue then
                        elCurrentQueueIndex = elCurrentQueueIndex + 1
                        elSelectedLeveling = elLevelingQueue[elCurrentQueueIndex]
                        elPhase = "LEVELING"
                        elBlessingCount = 0
                        
                        local nextPetData = getPetDataFromService(elSelectedLeveling)
                        local nextPetName = nextPetData and (nextPetData.name ~= "" and nextPetData.name or nextPetData.type) or "Unknown"
                        
                        WindUI:Notify({
                            Title = "🔄 Next Pet",
                            Content = string.format("Now leveling: %s (%d/%d)", nextPetName, elCurrentQueueIndex, #elLevelingQueue),
                            Duration = 5,
                            Icon = "arrow-right"
                        })
                        
                        task.wait(1)
                        swapTo(visualToInternal(elMimicDilopSlot))
                    else
                        elAutoEnabled = false
                        ElAutoToggle:Set(false)
                        elPhase = "LEVELING"
                        
                        WindUI:Notify({
                            Title = "🎉 ALL COMPLETE!",
                            Content = string.format("All %d pets reached max weight!", #elCompletedPets),
                            Duration = 15,
                            Icon = "award"
                        })
                        
                        -- Webhook: All Complete (Elephant)
                        sendWebhook(
                            "🎉 ALL COMPLETE!",
                            "All pets reached max weight cap!",
                            5814783,
                            {
                                {name = "✅ Completed", value = string.format("%d pets", #elCompletedPets), inline = true},
                                {name = "🐘 Mode", value = "Auto Elephant", inline = true},
                            }
                        )
                    end
                    
                elseif lastElephantResult == "Blessed" then
                    -- Blessing success! Back to leveling
                    elBlessingCount = elBlessingCount + 1
                    local weightTxt = lastElephantWeight and string.format("%.2f KG", lastElephantWeight) or "N/A"
                    
                    WindUI:Notify({
                        Title = "🐘 Blessed!",
                        Content = string.format("%s blessed! Weight: %s (Blessing #%d)", freshPetName, weightTxt, elBlessingCount),
                        Duration = 5,
                        Icon = "zap"
                    })
                    
                    task.wait(1)
                    
                    pcall(function()
                        PetsService:FireServer("UnequipPet", elSelectedLeveling)
                    end)
                    elPetEquipped = false
                    lastElephantResult = nil
                    lastElephantWeight = nil
                    
                    -- Back to leveling phase
                    elPhase = "LEVELING"
                    
                    task.wait(1)
                    swapTo(visualToInternal(elMimicDilopSlot))
                end
            end
        end
        
        --==============================================================--
        -- Auto Switch Logic (All tabs)
        --==============================================================--
        local isLvlAutoActive = lvlAutoEnabled
        local isNmAutoActive = nmAutoEnabled and nmPhase == "LEVELING"
        local isElAutoActive = elAutoEnabled and elPhase == "LEVELING"
        
        if not isLvlAutoActive and not isNmAutoActive and not isElAutoActive then
            readyHoldTimer = 0
        else
            local dilopSlot, levelSlot
            if isNmAutoActive then
                dilopSlot = nmMimicDilopSlot
                levelSlot = nmLevelingSlot
            elseif isElAutoActive then
                dilopSlot = elMimicDilopSlot
                levelSlot = elLevelingSlot
            else
                dilopSlot = lvlMimicDilopSlot
                levelSlot = lvlLevelingSlot
            end
            
            if visualSlot == dilopSlot then
                if mimicRemain and mimicRemain <= READY_EPS then
                    readyHoldTimer = readyHoldTimer + TICK_SEC
                    if readyHoldTimer >= READY_HOLD_SEC then
                        swapTo(visualToInternal(levelSlot))
                        readyHoldTimer = 0
                    end
                else
                    readyHoldTimer = 0
                end
            elseif visualSlot == levelSlot then
                if mimicRemain and mimicRemain > READY_EPS then
                    swapTo(visualToInternal(dilopSlot))
                    readyHoldTimer = 0
                end
            end
        end
    end
end)

--==============================================================--
-- Settings Tab
--==============================================================--
SettingsTab:Paragraph({
    Title = "⚙️ Configuration",
    Desc = "Adjust timing and keybind settings",
})

SettingsTab:Divider()

local TimingSlider = SettingsTab:Slider({
    Title = "Ready Hold Time",
    Desc = "Delay before switching slots (seconds)",
    Step = 0.05,
    Value = {
        Min = 0.1,
        Max = 2.0,
        Default = READY_HOLD_SEC,
    },
    Callback = function(value)
        READY_HOLD_SEC = value
    end
})

local PollSlider = SettingsTab:Slider({
    Title = "Poll Interval",
    Desc = "Cooldown refresh interval (seconds)",
    Step = 0.5,
    Value = {
        Min = 1.0,
        Max = 10.0,
        Default = POLL_SEC,
    },
    Callback = function(value)
        POLL_SEC = value
    end
})

SettingsTab:Divider()

local AntiAfkToggle = SettingsTab:Toggle({
    Title = "Anti-AFK",
    Desc = "Prevent idle kick while farming",
    Icon = "shield",
    Value = true,
    Callback = function(state)
        antiAfkEnabled = state
        
        if state then
            WindUI:Notify({
                Title = "Anti-AFK",
                Content = "Enabled - You won't be kicked for idling",
                Duration = 3,
                Icon = "shield"
            })
        else
            WindUI:Notify({
                Title = "Anti-AFK",
                Content = "Disabled - You may be kicked for idling",
                Duration = 3,
                Icon = "shield-off"
            })
        end
    end
})

SettingsTab:Divider()

local ToggleKeybind = SettingsTab:Keybind({
    Title = "Toggle UI Keybind",
    Desc = "Press this key to toggle UI visibility",
    Value = "LeftControl",
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
    end
})

SettingsTab:Divider()

SettingsTab:Paragraph({
    Title = "📢 Discord Webhook",
    Desc = "Get notified on Discord when events happen",
})

SettingsTab:Input({
    Title = "Webhook URL",
    Desc = "Paste your Discord webhook URL",
    Value = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Callback = function(input)
        webhookUrl = input
        if input ~= "" then
            WindUI:Notify({
                Title = "Webhook URL Set",
                Content = "URL saved! Enable webhook to start receiving notifications.",
                Duration = 3,
                Icon = "link"
            })
        end
    end
})

local WebhookToggle = SettingsTab:Toggle({
    Title = "🔔 Enable Webhook",
    Desc = "Send notifications to Discord",
    Icon = "bell",
    Value = false,
    Callback = function(state)
        webhookEnabled = state
        
        if state then
            if webhookUrl == "" then
                WindUI:Notify({
                    Title = "Warning",
                    Content = "Please enter Webhook URL first!",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
                WebhookToggle:Set(false)
                webhookEnabled = false
                return
            end
            
            WindUI:Notify({
                Title = "Webhook Enabled",
                Content = "You will receive Discord notifications",
                Duration = 3,
                Icon = "bell"
            })
        else
            WindUI:Notify({
                Title = "Webhook Disabled",
                Content = "Discord notifications turned off",
                Duration = 3,
                Icon = "bell-off"
            })
        end
    end
})

SettingsTab:Button({
    Title = "📤 Test Webhook",
    Desc = "Send a test message to verify connection",
    Icon = "send",
    Callback = function()
        if webhookUrl == "" then
            WindUI:Notify({
                Title = "Error",
                Content = "Enter Webhook URL first!",
                Duration = 3,
                Icon = "alert-circle"
            })
            return
        end
        
        -- Force send test (bypass enabled check)
        local HttpService = game:GetService("HttpService")
        local embed = {
            title = "🧪 Test Webhook",
            description = "Webhook berhasil terhubung!",
            color = 5763719,
            fields = {
                {name = "🐾 Pet", value = "Jackie", inline = true},
                {name = "🏷 Type", value = "Bald Eagle", inline = true},
                {name = "📊 Level", value = "30", inline = true},
            },
            footer = {text = "Grow a Garden • Marf Hub v1.1"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
        
        local success, err = pcall(function()
            request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode({username = "Marf Hub", embeds = {embed}})
            })
        end)
        
        if success then
            WindUI:Notify({
                Title = "Success",
                Content = "Test message sent! Check Discord",
                Duration = 4,
                Icon = "check-circle"
            })
        else
            WindUI:Notify({
                Title = "Error",
                Content = "Failed to send: " .. tostring(err),
                Duration = 4,
                Icon = "x-circle"
            })
        end
    end
})

SettingsTab:Divider()

SettingsTab:Button({
    Title = "Reset to Default",
    Desc = "Restore default settings",
    Icon = "rotate-ccw",
    Color = Color3.fromRGB(255, 200, 100),
    Callback = function()
        READY_HOLD_SEC = 0.30
        POLL_SEC = 2.5
        antiAfkEnabled = true
        webhookEnabled = false
        TimingSlider:Set(0.30)
        PollSlider:Set(2.5)
        AntiAfkToggle:Set(true)
        WebhookToggle:Set(false)
        WindUI:Notify({
            Title = "Reset",
            Content = "Settings reset to default",
            Duration = 3,
            Icon = "refresh-cw",
        })
    end
})

SettingsTab:Space()

SettingsTab:Button({
    Title = "Unload Script",
    Desc = "Close and unload the script",
    Icon = "x-circle",
    Color = Color3.fromRGB(255, 100, 100),
    Callback = function()
        local Dialog = Window:Dialog({
            Icon = "alert-triangle",
            Title = "Unload Script",
            Content = "Are you sure you want to unload the script?",
            Buttons = {
                {
                    Title = "Yes",
                    Callback = function()
                        WindUI:Notify({
                            Title = "Goodbye",
                            Content = "Script unloaded",
                            Duration = 2,
                            Icon = "log-out",
                        })
                        task.wait(2)
                        Window:Destroy()
                    end,
                },
                {
                    Title = "Cancel",
                    Callback = function()
                        -- do nothing
                    end,
                },
            },
        })
        Dialog:Show()
    end
})

--==============================================================--
-- Initialize
--==============================================================--
WindUI:Notify({
    Title = "Marf Hub v1.1",
    Content = "Script loaded successfully!\nLeveling, Nightmare & Elephant tabs ready.",
    Duration = 6,
    Icon = "zap",
})

MainTab:Select()
