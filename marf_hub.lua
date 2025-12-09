--[[
    ╔══════════════════════════════════════════════════════════╗
    ║                      MARF HUB v1.0                       ║
    ║            Grow a Garden - Auto Leveling Tool            ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Features:                                               ║
    ║  • Auto Leveling with pet queue system                   ║
    ║  • Auto Nightmare farming with auto-cleanse              ║
    ║  • Real-time age & mutation tracking                     ║
    ║  • Smart slot switching based on Mimic cooldown          ║
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

-- Mutation detection via Notification
local lastMutationResult = nil  -- nil = waiting, "Nightmare" = success, "Other" = wrong mutation
local lastMutationName = nil    -- Store the actual mutation name

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
    Title = "Leveling",
    Icon = "trending-up",
})

local NightmareTab = Window:Tab({
    Title = "Auto Nightmare",
    Icon = "moon",
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
        -- Check if this is a mutation notification
        -- Format: "💀 Mimic Octopus's power twisted your [Pet] into a level 1 <font color='#...'>MutationName</font> mutation!"
        if message and type(message) == "string" and message:find("twisted your") and message:find("mutation") then
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
    end)
end

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
        return {
            type = petInfo.PetType or "Unknown",
            name = petInfo.PetData.Name or "",
            age = petInfo.PetData.Level or 1,
            mutationId = mutationType,
            mutation = getMutationName(mutationType),
        }
    end
    
    return nil
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
-- LOGIC: Cooldown Tracking
--==============================================================--
local READY_EPS          = 0.05
local READY_HOLD_SEC     = 0.30
local POLL_SEC           = 2.5
local TICK_SEC           = 0.25

local mimicRemain = nil
local currentSlot = 1
local readyHoldTimer = 0

-- event cooldown
if PetCooldownsUpdated then
    PetCooldownsUpdated.OnClientEvent:Connect(function(a,b)
        -- Check all possible mimic GUIDs
        local lvlKey = lvlSelectedMimic and normGuid(lvlSelectedMimic) or nil
        local nmKey = nmSelectedMimic and normGuid(nmSelectedMimic) or nil
        
        local function try(a_, b_, key)
            if a_ and b_ and normGuid(a_) == key then
                local s = pickSeconds(b_)
                if s~=nil then 
                    mimicRemain=s
                end
                return true
            end
            return false
        end
        
        if lvlKey and try(a, b, lvlKey) then return end
        if nmKey and try(a, b, nmKey) then return end
        
        if type(a)=="table" and not b then
            for k,v in pairs(a) do
                local nk = normGuid(k)
                if nk == lvlKey or nk == nmKey then
                    local s = pickSeconds(v)
                    if s~=nil then 
                        mimicRemain=s
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
            -- Request for both tabs' selected mimic
            if lvlSelectedMimic then
                pcall(function() RequestPetCooldowns:FireServer(lvlSelectedMimic) end)
            end
            if nmSelectedMimic then
                pcall(function() RequestPetCooldowns:FireServer(nmSelectedMimic) end)
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
        local lvlQueueTxt = string.format("%d/%d", lvlCurrentQueueIndex, #lvlLevelingQueue)
        
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
        local queueTxt = string.format("%d/%d", currentQueueIndex, #levelingQueue)
        
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
        -- Auto Switch Logic (Both tabs)
        --==============================================================--
        local isLvlAutoActive = lvlAutoEnabled
        local isNmAutoActive = nmAutoEnabled and nmPhase == "LEVELING"
        
        if not isLvlAutoActive and not isNmAutoActive then
            readyHoldTimer = 0
        else
            local dilopSlot, levelSlot
            if isNmAutoActive then
                dilopSlot = nmMimicDilopSlot
                levelSlot = nmLevelingSlot
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

local ToggleKeybind = SettingsTab:Keybind({
    Title = "Toggle UI Keybind",
    Desc = "Press this key to toggle UI visibility",
    Value = "LeftControl",
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
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
        TimingSlider:Set(0.30)
        PollSlider:Set(2.5)
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
    Title = "Marf Hub v1.0",
    Content = "Script loaded successfully!\nUse Leveling or Nightmare tab to start.",
    Duration = 6,
    Icon = "zap",
})

MainTab:Select()
