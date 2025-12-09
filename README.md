# 🌱 Marf Hub v1.2

> Auto Leveling, Nightmare & Elephant farming tool for **Grow a Garden** (Roblox)

![Roblox](https://img.shields.io/badge/Roblox-Grow%20a%20Garden-brightgreen)
![Version](https://img.shields.io/badge/Version-1.2-blue)
![UI](https://img.shields.io/badge/UI-WindUI-purple)

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🐾 **Auto Leveling V1** | Level with Mimic + Dilop (best for 1-50) |
| 🍟 **Auto Leveling V2** | Level with French Fry Ferret (best for 50-100) |
| 🌙 **Auto Nightmare** | Farm Nightmare mutations with auto-cleanse |
| 🐘 **Auto Elephant** | Farm weight with Jumbo Blessing until max cap |
| 📊 **Real-time Tracking** | Live display of age, weight, mutation, and cooldown |
| ⚡ **Smart Switching** | Auto slot switch based on pet cooldowns |
| 🛡️ **Anti-AFK** | Prevent idle kick while farming |
| 📢 **Discord Webhook** | Get notified on Discord when events happen |

## 📸 Tabs Overview

### 🐾 Auto Leveling V1
- Level with Mimic + Dilophosaurus
- Best for level 1-50
- Auto slot switching for fast leveling

### 🍟 Auto Leveling V2
- Level with French Fry Ferret
- Best for level 50-100
- Stay in one slot, AFK friendly

### 📊 V1 vs V2 Comparison

| | V1 (Mimic + Dilop) | V2 (Ferret) |
|---|---|---|
| **Best for** | Level 1-50 | Level 50-100 |
| **Speed** | Fast | Slow but steady |
| **AFK** | Need slot switching | ✅ Full AFK |
| **Pets needed** | Mimic + Dilop | French Fry Ferret (2-3x) |
| **Slots used** | 2 slots | 1 slot |

### 🌙 Auto Nightmare
- Level → Mutate → Cleanse if wrong
- Auto detect Nightmare mutation
- Auto cleanse with Cleansing Shard

### 🐘 Auto Elephant
- Level → Elephant Blessing → Repeat
- Auto detect Jumbo Blessing
- Auto stop when max weight cap reached

### ⚙️ Settings
- Ready Hold Time / Poll Interval
- Anti-AFK toggle
- Discord Webhook configuration
- Toggle UI Keybind

## 🚀 Installation

### Method 1: Direct Execute
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ilhmsmith/marf-hub/main/marf_hub.lua"))()
```

### Method 2: Manual
1. Download `marf_hub.lua` from this repository
2. Copy the script content
3. Execute with your preferred executor

## 📖 How to Use

### 🐾 Auto Leveling V1
1. Click **Refresh Pet List** to load all your pets
2. Select your **Mimic Octopus** from dropdown
3. Choose **Mimic Dilop Slot** (slot with Mimic + Dilophosaurus)
4. Select a pet and click **Add to Queue**
5. Set **Target Level** (default: 30)
6. Choose **Leveling Slot** (slot with Mimic only)
7. Enable **Auto Switch** to start!

### 🍟 Auto Leveling V2
1. Click **Refresh Pet List** to load all your pets
2. Select **Ferret Slot** (default: Slot 4, use 2-3 French Fry Ferret)
3. Set **Target Level** (default: 100)
4. Select a pet and click **Add to Queue**
5. Enable **Auto Level** to start!
6. Script will:
   - Switch to Ferret slot
   - Equip pet from queue
   - Wait for Friendly Frier skill (+1 level)
   - When target level reached → Move to next pet
   - When all done → Notification + Webhook

### 🌙 Auto Nightmare
1. Follow steps 1-6 from Leveling V1
2. Set **Mutation Slot** (slot with Mimic + Headless Horseman)
3. Enable **Auto Switch**
4. Script will:
   - Level pet to target → Switch to Mutation Slot
   - Wait for Headless skill → Check mutation
   - If Nightmare ✅ → Move to next pet
   - If wrong mutation ❌ → Auto cleanse & re-level

### 🐘 Auto Elephant
1. Select **Mimic Octopus** for leveling phase
2. Select **Elephant** for blessing phase
3. Set slots: Mimic Dilop, Leveling, Elephant
4. Add pets to queue
5. Set **Target Level** (default: 40)
6. Enable **Auto Switch**
7. Script will:
   - Level pet to target → Switch to Elephant Slot
   - Wait for Jumbo Blessing
   - If blessed → Back to leveling (repeat)
   - If max weight cap → Move to next pet

## ⚙️ Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Ready Hold Time | Delay before switching slots | 0.30s |
| Poll Interval | Cooldown refresh interval | 2.5s |
| Anti-AFK | Prevent idle kick | ON |
| Discord Webhook | Send notifications to Discord | OFF |
| Toggle UI Keybind | Key to show/hide UI | Left Control |

## 📢 Discord Webhook

Get notified on Discord when:
- ✅ Pet reaches target level
- 🌙 Pet gets Nightmare mutation
- 🐘 Pet reaches max weight cap
- 🎉 All pets in queue completed

### Setup:
1. Create webhook in Discord (Server Settings → Integrations → Webhooks)
2. Copy webhook URL
3. Paste in Settings → Webhook URL
4. Enable webhook toggle
5. Click "Test Webhook" to verify

## 🎯 Slot Setup Guide

| Slot | Pets | Purpose |
|------|------|---------|
| Slot 1 | Mimic + Dilophosaurus | Main farming V1 (cooldown reset) |
| Slot 2 | Mimic only | Equip leveling pet here |
| Slot 3 | Mimic + Headless Horseman | Get mutations (Nightmare tab) |
| Slot 4 | French Fry Ferret (2-3x) | Leveling V2 (default, best for 50-100) |
| Slot 5 | Elephant only | Get Jumbo Blessing (Elephant tab) |
| Slot 6 | (Optional) | Extra slot |

> 💡 **Tip:** Use 2-3 French Fry Ferret in one slot for faster leveling (multiple Ferrets = less cooldown wait)

## 📝 Mutation Abbreviations

| Abbrev | Mutation |
|--------|----------|
| NM | Nightmare |
| RB | Rainbow |
| GD | Golden |
| SN | Shiny |
| MG | Mega |
| FZ | Frozen |

## ⚖️ Weight Formula

```
Current Weight = Base Weight × (1 + Age / 10)
```

Example: Base 4.36 KG at Age 100 = 4.36 × 11 = **47.96 KG**

## 🛠️ Requirements

- Roblox Executor (Solara, Fluxus, etc.)
- Grow a Garden game access
- **Pets needed:**
  - Mimic Octopus (for cooldown tracking)
  - Dilophosaurus (for cooldown reset)
  - French Fry Ferret (for Leveling V2)
  - Headless Horseman (for Nightmare farming)
  - Elephant (for weight farming)
- Cleansing Pet Shard (for auto-cleanse)

## 📚 UI Library

Built with [WindUI](https://github.com/Footagesus/WindUI) - A modern Roblox UI library

## ⚠️ Disclaimer

This script is for educational purposes only. Use at your own risk. The author is not responsible for any consequences of using this script.

## 📜 Changelog

### v1.2
- ✨ Added Auto Leveling V2 tab (French Fry Ferret)
- 🔄 Renamed Leveling to Auto Leveling V1
- 🍟 Best for level 50-100, AFK friendly
- 🐛 Fixed: Ferret "max level" false trigger during pet swap
- 🔧 Default Ferret Slot changed to Slot 4
- 🔧 Updated tab order (V1 → V2 → Nightmare → Elephant → Settings)

### v1.1
- ✨ Added Auto Elephant tab (weight farming)
- ✨ Added Discord Webhook notifications
- ✨ Added Anti-AFK feature
- ✨ Added real-time weight tracking
- 🔧 Improved slot switching logic

### v1.0
- 🎉 Initial release
- 🐾 Auto Leveling tab
- 🌙 Auto Nightmare tab
- ⚙️ Settings tab

## 👤 Author

Made with ❤️ by **marf**

---

⭐ **Star this repo if you find it useful!**
