# Az-FirstResponse (v2.0)

A compact **first-response / policing toolbox** for FiveM that bundles:

- **Callouts / dispatch** (with an optional local callout generator + 20+ templates)
- A lightweight **MDT / NCIC terminal** (NUI) with **plates, IDs, reports, warrants, dispatch**
- **AI traffic stops** + NPC interactions (cuff, search, arrest, citations, dragging/seating)
- **AI services** (EMS, coroner, animal control, tow)
- Optional **random-world events** (accidents, drunk drivers, street fights)

> Built to work with **ox_lib**, **ox_target**, **oxmysql**, and **Az-Framework** job checks.

---

## Features

### 1) Callouts / Dispatch System
- Loads callout templates from `/callouts/*.callout`
- Creates callout instances server-side and broadcasts to eligible departments
- Per-callout context menu (ox_lib) for:
  - Accept / Deny
  - Status replies (On Scene / En Route / Need Assistance)
  - Request backup at your location
  - End callout (with distance checks + force-end)
- Callout blips, routing, and cleanup safety (client fail-safe cleanup if denied)

**Included callout templates**
- Dog Attack
- Domestic Violence
- Drunk Driver
- Fight In Progress
- Missing Person
- Noise Complaint
- Overdose / Medical
- Person In Crisis
- Person With Knife
- Public Intox
- Reckless Driver
- Residential Alarm
- Residential Burglary
- Road Hazard
- Robbery In Progress
- Shoplifter Detained
- Shots Fired
- Suspicious Person
- Suspicious Vehicle
- Traffic Collision
- Vehicle Burglary
- Welfare Check
- Yelling Person

> You can add more by dropping new `.callout` files and listing them in `callouts/manifest.json`.

---

### 2) MDT / NCIC Terminal (NUI)
Accessible in-game via `/toggleMDT` (default **B**), with these sections:

- **Plate lookup**
  - Pulls recent plate lookups + any attached MDT plate records
  - Plate “status” stored in DB (`VALID / SUSPENDED / REVOKED`)
  - Can update plate status from the MDT UI
- **ID lookup**
  - Lookup/log an ID record
  - Add/edit/delete MDT ID records attached to that ID
- **Reports**
  - Create/list/delete reports
- **Warrants**
  - Create/list/remove warrants
  - In-game warrant notifications
- **Dispatch**
  - Create/list/ack/close dispatch calls

**Database-backed** (tables are auto-created on resource start).

---

### 3) Police Actions Menu (ox_lib context + ox_target)
Open a unified **Police Actions** menu that includes:

- **MDT shortcuts** (plate lookup, ID lookup, open Reports/Warrants/Dispatch tabs)
- **AI Services** (EMS / Coroner / Animal Control / Tow)
- **Ped Interaction**
  - Check ID
  - Search ped
  - Issue citation
  - Cuff / Release
  - Arrest (logs it + removes NPC)
  - Drag / Undrag
  - Seat left / right (from drag)
  - First Aid (attempt revive a dead NPC)
- **Vehicle Interaction**
  - Finish pull-over
  - Eject driver / passengers / all (NPC)

Also adds an **ox_target** option on nearby peds:
- **Open Police Menu**

---

### 4) AI Traffic Stops
- “Stop AI” flow supports:
  - In-vehicle stops (pull-over)
  - On-foot stops
- Includes stop confirmation safety (hold modifier for 3 seconds)
- Supports canceling stops + releasing the pulled driver/vehicle
- Vehicle reposition helper for pulled vehicles (interactive mode)

---

### 5) AI Services (Client)
Quickly spawn responders to the scene:
- **EMS** (medic response behavior)
- **Coroner** (dead-body pickup behavior)
- **Animal Control**
- **Tow Truck**

---

### 6) Random Events (Optional)
An optional ambient system that can spawn:
- **Traffic accidents**
- **Drunk driver events**
- **Street fights**

> Note: the random-events file currently includes a placeholder job check (defaults to `LEO`). If you want job-gating, wire it to your framework/job export.

---

## Commands & Keybinds

### Main
| Command | Default Key | What it does |
|---|---:|---|
| `/toggleMDT` | **B** | Opens/closes the MDT terminal (requires being in an emergency-class vehicle). |
| `/policemenu` | — | Opens the Police Actions menu (job-gated by `Config.PoliceMenuJobs`). |
| `/aipolicemenu` | **F6** | Same as `/policemenu`. |
| `/stopAI` | **E** (hold **Left Shift** for 3s) | Initiate an AI stop (vehicle pull-over or on-foot). |
| `/cancelStopsCmd` | **Left Ctrl** | Cancels non-forced stops / clears stop state. |
| `/showid` | **J** | Shows the last stopped ped’s ID info (if available). |
| `/repositionVeh` | **Y** | Interactive repositioning of the currently pulled vehicle (arrow keys + Q/E rotate). |

### Callouts (Client)
| Action | Default |
|---|---|
| Accept prompted callout | **E** |
| Deny prompted callout | **G** |
| End callout (must be near) | **H** |
| Force-end callout (any distance) | **Hold H for 5s** |
| Open callout menu | `/callout_menu` |
| List active callouts | `/callout_menu list` |

### Callouts (Server / Console / Admin)
| Command | What it does |
|---|---|
| `/callout_list` | Prints all loaded callout templates in server console. |
| `/callout_spawn <templateName>` | Spawns a specific callout instance using a player’s position (or a random player if run from console). |
| `/callout_spawn_random` | Picks a random template and spawns it. |

### Random Events (Optional)
| Command | What it does |
|---|---|
| `/forceevent <accident\|drunk\|fight>` | Forces a specific random event type. |

### Debug (Optional)
| Command | What it does |
|---|---|
| `/forceAIMedicResponse` | Debug: forces a nearby driver to “tend” a nearby casualty. |
| `/debugDownedSearch` | Debug: lists downed peds near player (no default key bound in config). |

> ⚠️ There is also a “quick cuff” hotkey wired to **control 249** inside the client logic. In FiveM this often overlaps with voice/push-to-talk depending on your setup—adjust/remove if needed.

---

## Configuration

Edit `config.lua`:

### Department / job gating
- **Callouts access:** `Config.AllowedJobs`
  - Default: `police`, `ambulance`, `fire`
- **Police menu access:** `Config.PoliceMenuJobs`
  - Default: `{ 'police' }`

### Target / interaction
- `Config.TargetDistance` – how close you must be for ox_target options (default ~2.5m)
- `Config.Debug` – enables debug prints

---

## Database

This resource auto-creates these tables on start (oxmysql):

- `citations`
- `arrests`
- `plate_records`
- `plates`
- `id_records`
- `reports`
- `warrants`
- `dispatch_calls`
- `mdt_id_records`

No manual SQL import required.

---

## Installation

1. Place the folder in your resources directory:
   - `resources/[az]/Az-FirstResponse`
2. Ensure dependencies are started **before** this resource:
   - `ox_lib`
   - `ox_target`
   - `oxmysql`
   - `Az-Framework`
3. Add to your `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure ox_target
   ensure oxmysql
   ensure Az-Framework
   ensure Az-FirstResponse
