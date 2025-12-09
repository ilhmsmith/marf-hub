# 🌱 Marf Hub v1.0

> Auto Leveling & Nightmare farming tool for **Grow a Garden** (Roblox)

![Roblox](https://img.shields.io/badge/Roblox-Grow%20a%20Garden-brightgreen)
![Version](https://img.shields.io/badge/Version-1.0-blue)
![UI](https://img.shields.io/badge/UI-WindUI-purple)

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🐾 **Auto Leveling** | Level multiple pets automatically with queue system |
| 🌙 **Auto Nightmare** | Farm Nightmare mutations with auto-cleanse if wrong |
| 📊 **Real-time Tracking** | Live display of age, mutation, cooldown, and status |
| ⚡ **Smart Switching** | Auto slot switch based on Mimic Octopus cooldown |
| 🔍 **Pet Search** | Search and filter pets easily |
| 📋 **Queue System** | Add multiple pets to level one by one |

## 📸 Preview

```
┌─────────────────────────────────────┐
│  🐾 Auto Leveling                   │
│  Level multiple pets automatically! │
│  • Queue system for batch leveling  │
│  • Real-time age tracking           │
│  • Auto equip/unequip on slot switch│
└─────────────────────────────────────┘
```

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

### Leveling Tab
1. Click **Refresh Pet List** to load all your pets
2. Select your **Mimic Octopus** from dropdown
3. Choose **Mimic Dilop Slot** (slot with Mimic + Dilophosaurus)
4. Select a pet and click **➕ Add to Queue**
5. Set **Target Level** (default: 30)
6. Choose **Leveling Slot** (slot with Mimic only)
7. Enable **Auto Switch** to start!

### Nightmare Tab
1. Follow steps 1-6 from Leveling Tab
2. Additionally, set **Mutation Slot** (slot with Mimic + Headless Horseman)
3. Enable **Auto Switch**
4. Script will:
   - Level pet to target → Switch to Mutation Slot
   - Wait for Headless skill → Check mutation
   - If Nightmare ✅ → Move to next pet
   - If wrong mutation ❌ → Auto cleanse & re-level

## ⚙️ Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Ready Hold Time | Delay before switching slots | 0.30s |
| Poll Interval | Cooldown refresh interval | 2.5s |
| Toggle UI Keybind | Key to show/hide UI | Left Control |

## 🎯 Slot Setup Guide

| Slot | Pets | Purpose |
|------|------|---------|
| Mimic Dilop Slot | Mimic + Dilophosaurus | Main farming (cooldown reset) |
| Leveling Slot | Mimic only | Equip leveling pet here |
| Mutation Slot | Mimic + Headless Horseman | Get mutations (Nightmare tab only) |

## 📝 Mutation Abbreviations

| Abbrev | Mutation |
|--------|----------|
| NM | Nightmare |
| RB | Rainbow |
| GD | Golden |
| SN | Shiny |
| MG | Mega |
| FZ | Frozen |
| ... | ... |

## 🛠️ Requirements

- Roblox Executor (Solara, Fluxus, etc.)
- Grow a Garden game access
- Mimic Octopus pet
- Dilophosaurus pet (for cooldown reset)
- Headless Horseman pet (for Nightmare farming)
- Cleansing Pet Shard (for auto-cleanse)

## 📚 UI Library

Built with [WindUI](https://github.com/Footagesus/WindUI) - A modern Roblox UI library

## ⚠️ Disclaimer

This script is for educational purposes only. Use at your own risk. The author is not responsible for any consequences of using this script.

## 👤 Author

Made with ❤️ by **marf**

---

⭐ **Star this repo if you find it useful!**
