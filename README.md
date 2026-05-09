# atlas_crimelife

Illegal-life mechanics for the Atlas Framework. A single resource of
self-contained module subfolders covering the full criminal arc: solo
foot crime → vehicle theft → solo logistics → gang protection rackets.

> **Status (2026-05-02).** 8 of 10 planned modules shipped. Police heat
> hooks are stubbed pending the atlas_dispatch build. Voucher / "info
> scrap" cross-tier bridge items are designed but not yet wired.

![FiveM](https://img.shields.io/badge/FiveM-Cerulean-orange)
![Lua](https://img.shields.io/badge/Lua-5.4-purple)
![DB](https://img.shields.io/badge/DB-MongoDB-success)

---

## Quick install

```cfg
ensure oxmysql            # not used directly, but most Atlas deps need it
ensure atlas_mongodb
ensure atlas_core
ensure atlas_inv
ensure atlas_banking      # cash payouts
ensure atlas_target       # all radial UX
ensure atlas_mgmt         # gang lookups
ensure atlas_vehiclekeys  # cloning grants keys via this
ensure atlas_crimelife
```

The fxmanifest loads each module subfolder independently. To disable a
module, comment its two lines (one client, one server) in `fxmanifest.lua`.

---

## Player progression

```
                  ┌───────────────────────────────────────────┐
   no items       │  TIER 1 — Entry crime (foot, solo)        │
   no rank        │  • parkingmeters  (smash with crowbar)    │
                  │  • copperscrap    (strip AC + elec boxes) │
                  └───────────────────────────────────────────┘
                              │  earn cash + mats + rank 0–4
                              ▼
                  ┌───────────────────────────────────────────┐
   needs vehicle  │  TIER 2 — Vehicle theft (solo)            │
   rank 0+        │  • chopshop       (strip whole vehicles)  │
                  │  • vinscratch     (clean a stolen plate)  │
                  │  • cloning        (reflash to a new plate)│
                  └───────────────────────────────────────────┘
                              │  rank 5+ unlocks Distributor tier
                              ▼
                  ┌───────────────────────────────────────────┐
   small inv use  │  TIER 3 — Solo logistics                  │
   any rank       │  • shadowmarket   (mule contraband runs)  │
                  └───────────────────────────────────────────┘
```

> **Tier 4 (gang protection rackets) and the catalytic-converter
> module have been removed pending a rewrite.** A more advanced
> protection / gang-economy system will replace them. The gang vault
> primitive (CreditGangVault / DebitGangVault / GetGangVault) survives
> as `gangvault/` since other features (gang menu, charterer NPC,
> archetype upgrades) depend on it.

Crime XP (`PlayerData.crime.xp`, `PlayerData.crime.rank`) is the single
progression currency. Earned in every module, spent implicitly via
rank-gated content (master_key tier, premium chop parts, etc.). 100 XP
per rank by default (atlas_core.config.CrimeXpPerRank).

### Currency model — `markedbills` only

**Criminals don't deal in clean cash.** Every payout in this resource —
parking meters, copper, scrap, mule runs, chop shop bonuses — pays
out in the inventory item `markedbills`. Every criminal-economy
purchase (gang founding buy-in, gang-vault expenses, etc.) is also
paid in `markedbills`.

The clean-cash conversion path was previously the racketeering
laundering counter; that's gone with the racketeering rewrite. Until
the new system ships there's no in-game conversion of markedbills →
cash, and that's intentional — it keeps the rewrite from leaking
half-functional bridges.

This makes markedbills a meaningful parallel currency rather than
cash-with-extra-steps: street earnings stay street.

---

## Tier 1 — Entry crime (foot)

The "zero-asset" tier. Tutorial for tool-flow + map navigation. All
three modules feed the same shared heat-zone counter (see *Shared
systems / Heat* below) so a hot neighborhood is hot regardless of which
crime you ran there.

### parkingmeters/

Smash parking meters and phone boxes for loose change.

| Tool             | Speed | Payout (markedbills) | Heat | Gate          |
|------------------|-------|----------------------|------|---------------|
| `weapon_crowbar` | 6.5s  | 8–25                 | +30  | none          |
| `master_key`     | 4.0s  | 24–75                | +0   | crime rank 5+ |

- **Targets**: world props `prop_parkingmeter_*`, `prop_phonebox_*` — no
  coordinate seeding, atlas_target's global-model dispatcher handles it.
- **Per-prop cooldown**: 30 min keyed by rounded coords.
- **Per-player throttle**: 8s.
- **Crime XP**: +2 per hit.
- **Heat zones**: 8 LS districts (Downtown, Vinewood, Rockford, Mission
  Row, Davis, Strawberry, Mirror Park, La Mesa). 20-min linear decay.
  Threshold cross at 60 fires `atlas_crimelife:heat:rise` for
  atlas_dispatch (deferred) to consume.
- **Admin**: `/heatmap` dumps current zone heat.

### copperscrap/

Strip AC units and electrical boxes for raw materials.

| Prop group | Models                       | Loot favors |
|------------|------------------------------|-------------|
| AC units   | `prop_air_con_*`             | copper      |
| Elec boxes | `prop_elec_box_*`            | scrap       |

- **Tool**: `wire_cutters` (required to start; 20% chance to break on
  failed skillcheck).
- **Skillcheck**: atlas_core's `SkillCheck('medium', 'medium', { w/a/s/d })`.
  Pass → roll the loot table. Fail → -15 HP electrical shock.
- **Per-prop cooldown**: 30 min.
- **Crime XP**: +4 per success.
- **Heat**: +15 success, +5 failure.
- **Fence NPC**: `s_m_y_dockwork_01` at the LS junkyard
  `vec4(-460.69, -1721.88, 18.79, 175.0)` — buys `copper` @ 12 markedbills,
  `scrap` @ 8 markedbills, batch-capped at 40 per transaction, 30s cooldown.

---

## Tier 2 — Vehicle theft

Stolen-car loop. Each module is independently usable; combining them
lets a player turn a random NPC car into a clean payday.

### chopshop/

Drive a stolen vehicle into the chop-shop zone, strip it for parts.

- **Zone**: `vec3(720.84, -1080.05, 22.16)` (La Mesa industrial), 12m
  radius, red floor marker drawn within 30m.
- **Strip duration**: 30s progress bar.
- **Cooldown**: 8 min per player.
- **Class refusals**: cycles, boats, helis, planes, trains, emergency.
- **Owner refusal**: refused if you own the plate — UNLESS `vinscratch`
  has scratched it (then it goes through, with a payout bonus).
- **Parts table**: tier-gated.
  - **basic** (rank 0+): door, tire, battery, radiator, engine, transmission
  - **premium** (rank 5+ AND class 5/6/7): basic + turbo + ECU
- **Scratched-plate bonus**: parts table re-rolls **twice** on a scratched
  plate — roughly +50% expected yield.
- **Player-owned bonus**: chopping someone *else's* car drops
  $500–$1500 markedbills on top of parts.
- **Crime XP**: +25 per strip.

### vinscratch/

Erase a vehicle's identity so chop shops don't recognize it.

- **Item**: `vin_kit` (single-use, consumed on success).
- **Action**: 12s scrub at any vehicle (player on foot, within 3m).
- **Result**: plate marked in `vin_scratched` MongoDB collection.
- **Effect on chop shop**: bypasses owner-refusal + triggers the bonus
  re-roll above.
- **Cross-module exports**:
  - `IsScratched(plate)` — read.
  - `MarkScratched(plate, citizenid)` — write (cloning calls this).
- **Crime XP**: +8.

### cloning/

Reflash a vehicle's plate to a new identity.

- **Item**: `vin_cloner` (single-use, consumed on success).
- **Action**: 18s reflash at any vehicle. `InputDialog` prompts for the
  new plate text (1–8 chars, A-Z 0-9).
- **Validation**: refuses if the new plate is in the `vehicles` (player-
  owned) collection — can't shadow a registered car.
- **Side effects**:
  - `SetVehicleNumberPlateText(vehicle, newPlate)` — server-side native,
    replicates to all clients.
  - Auto-marks the new plate as `vin_scratched` (fresh identity).
  - Grants the player a vehicle key on the new plate via
    `exports['atlas_vehiclekeys']:GrantOwnerKey` — they can drive it
    without hotwiring.
- **Audit**: row in `vin_cloned` (citizenid, oldPlate, newPlate, ts).
- **Crime XP**: +15.

---

## Tier 3 — Solo logistics

### shadowmarket/

Mule package runs. Pickup at a handler, deliver to a buyer across town.

- **Handlers** (4 NPCs): Pillbox, Mirror Park, Vinewood, Davis.
- **Drops** (10 NPCs): scattered map-wide. Server picks a random buyer
  ≥ 600m from the handler.
- **Item**: `contraband_smallpkg` — single-stack, given on pickup,
  consumed on dropoff.
- **Per-player cooldown**: 5 min between completed runs.
- **Payout**: `markedbills` $800–$1500 + 12 crime XP.
- **Audit**: rows in `crime_runs` collection (started / completed / abandoned).
- **Cross-module exports**: `GetActiveRun(src)`, `GetCooldownRemaining(src)`.

---

## Gang vault primitive

**`gangvault/`** survives the racketeering removal because atlas_mgmt's
gang menu, the charterer NPC's deposit/withdraw, and gang archetype
upgrade purchases all depend on it. Standalone module — no income
source, just a per-gang shared `markedbills` balance with a hard cap.

```lua
exports['atlas_crimelife']:GetGangVault(gang)         -- { balance, lastTick } | nil
exports['atlas_crimelife']:CreditGangVault(gang, n)   -- caps at vaultCap; returns actual added
exports['atlas_crimelife']:DebitGangVault(gang, n)    -- returns true on success
```

Persisted in MongoDB collection `gang_vaults` (one row per gang,
unique on `gang`). Cap defined in `gangvault/config.lua` (75k by
default).

---

## Shared systems

### StreetCred (shared/streetcred.lua, server-only)

Thin reader/writer around `atlas_core`'s `PlayerData.crime`. There is
NO local XP storage in this resource; atlas_core owns it.

```lua
StreetCred.GetCrime(src)   -- { rank, xp }
StreetCred.GetRank(src)    -- int
StreetCred.GetXp(src)      -- int
StreetCred.AddXp(src, n)   -- wraps Player.Functions.AddCrimeXp
```

### Tier helpers (config.lua)

```lua
GetCrimeTier(rank)           -- returns { id='mule'|'distributor'|'kingpin', label, desc, rankMin }
HasCrimeTier(rank, 'distributor')  -- bool, true if rank ≥ tier.rankMin
```

| Tier ID       | Rank min | Used by               |
|---------------|----------|-----------------------|
| `mule`        | 0        | (default — everyone)  |
| `distributor` | 5        | chop-shop premium parts, parkingmeters master_key |
| `kingpin`     | 25       | (reserved for future) |

### Heat zones (parkingmeters/server.lua, exported)

Heat is owned by the parkingmeters module but every entry-tier module
calls into it via the `BumpHeat` export. Effect: a neighborhood gets
hot regardless of WHICH crime you ran there, which keeps the spatial
behavior coherent for atlas_dispatch later.

```lua
exports['atlas_crimelife']:BumpHeat(coords, delta)        -- bump a zone's heat, returns new value
exports['atlas_crimelife']:GetZoneHeat(zoneId)             -- decayed heat for a zone
exports['atlas_crimelife']:GetAllZoneHeat()                -- all zones { id → { label, heat } }
```

#### Heat zones (8)

| ID            | Label             | Center                              | Radius |
|---------------|-------------------|-------------------------------------|--------|
| `downtown`    | Downtown          | `(195, -940, 30)`                   | 350    |
| `vinewood`    | Vinewood          | `(280, 180, 90)`                    | 350    |
| `rockford`    | Rockford Hills    | `(-700, -500, 30)`                  | 400    |
| `mission`     | Mission Row       | `(40, -1500, 30)`                   | 400    |
| `davis`       | Davis             | `(80, -1900, 22)`                   | 400    |
| `strawberry`  | Strawberry        | `(160, -1700, 30)`                  | 350    |
| `mirror_park` | Mirror Park       | `(1100, -650, 60)`                  | 300    |
| `lameaza`     | La Mesa           | `(820, -1100, 25)`                  | 350    |

Zone heat decays linearly to 0 over `heatDecayMs` (20 min). Crossing
the `heatHighThreshold` (60) emits an event:

```lua
AddEventHandler('atlas_crimelife:heat:rise', function(payload)
    -- payload = {
    --   module    = 'parkingmeters' | 'copperscrap',
    --   zoneId    = string,
    --   zoneLabel = string,
    --   center    = vec3,
    --   heat      = number,
    --   threshold = number,
    -- }
end)
```

This is the **single hook atlas_dispatch will subscribe to** for
cop-spawn / NPC-tip / patrol-rerouting reactions. Until atlas_dispatch
ships, this event has no listeners — heat is purely informational.

### Audit log

Every module logs to a single `crime_runs` collection with the schema:

```js
{
  citizenid: string,
  module:    'shadowmarket' | 'chopshop' | 'vinscratch' |
             'cloning' | 'parkingmeters' | 'copperscrap',
  status:    'started' | 'completed' | 'failed' | 'abandoned' |
             'cancelled' | 'fence',
  data:      object,        -- module-specific payload
  timestamp: ISO 8601 string,
}
```

Useful for player crime stats, server analytics, and admin investigations.
Indexed on `citizenid`, `module`, and `timestamp` (descending).

---

## Items used / added

| Item                  | Where added         | Used by                          | Notes                                   |
|-----------------------|---------------------|----------------------------------|-----------------------------------------|
| `weapon_crowbar`      | atlas_inv (existing)| parkingmeters (loud)             | Loud, fast, +heat — must be EQUIPPED    |
| `master_key`          | **new**             | parkingmeters (silent)           | Rank 5+, 3× payout                      |
| `wire_cutters`        | **new**             | copperscrap                      | 20% break chance on fail                |
| `vin_kit`             | **new**             | vinscratch                       | Single-use                              |
| `vin_cloner`          | **new**             | cloning                          | Single-use                              |
| `contraband_smallpkg` | **new**             | shadowmarket                     | Single-stack                            |
| `car_door`            | **new**             | chopshop drop                    | 2×2                                     |
| `car_tire`            | **new**             | chopshop drop                    | 1×1                                     |
| `car_battery`         | **new**             | chopshop drop                    | 1×1                                     |
| `car_radiator`        | **new**             | chopshop drop                    | 2×1                                     |
| `car_engine`          | **new**             | chopshop drop                    | 2×2                                     |
| `car_transmission`    | **new**             | chopshop drop                    | 2×2                                     |
| `car_turbo`           | **new**             | chopshop drop (premium)          | 1×1                                     |
| `car_ecu`             | **new**             | chopshop drop (premium)          | 1×1                                     |
| `copper`              | atlas_inv (existing)| copperscrap drop / fence buy     | $12/ea at fence                         |
| `scrap`               | atlas_inv (existing)| copperscrap drop / fence buy     | $8/ea at fence                          |
| `markedbills`         | atlas_inv (existing)| shadowmarket / chopshop          | "Dirty money" — no in-game launder yet  |

---

## MongoDB collections

All declared in `atlas_mongodb/server/index.js` with schemas + indexes:

| Collection         | Purpose                                                           | Owner module    |
|--------------------|-------------------------------------------------------------------|-----------------|
| `crime_runs`       | Append-only audit log (every module writes here)                  | all             |
| `gang_vaults`      | One row per gang vault balance (unique on `gang`)                 | gangvault       |
| `vin_scratched`    | One row per scrubbed plate (unique on `plate`)                    | vinscratch      |
| `vin_cloned`       | Append-only audit of every clone (citizenid, old/new plate, ts)   | cloning         |

---

## Cross-resource dependencies

| Resource             | What we use                                                                |
|----------------------|----------------------------------------------------------------------------|
| `atlas_core`         | `GetCoreObject`, `GetPlayer`, `GetPlayers`, `Functions.AddCrimeXp`, `Functions.AddMoney`, `CircleProgressBar`, `SkillCheck`, `Notify`, `InputDialog`, `Commands.Add`, `CreateUseableItem` |
| `atlas_inv`          | `HasItem`, `AddItem`, `RemoveItem`, `CanCarry`                              |
| `atlas_mongodb`      | `MongoDB.Game.{insertOne, findOne, findMany, updateOne, deleteOne}`        |
| `atlas_target`       | `addGlobalVehicle`, `AddTargetModel`, `addLocalEntity`, `addSphereZone`    |
| `atlas_mgmt`         | `GetPlayerGang(src)` (gang membership read; consumes gangvault exports)    |
| `atlas_vehiclekeys`  | `GrantOwnerKey(src, plate)` (cloning)                                      |
| `atlas_banking`      | (transitively, via `Player.Functions.AddMoney`)                            |

---

## Future hooks

### atlas_dispatch (planned)

Subscribes to `atlas_crimelife:heat:rise` and reacts:

- Spawn nearby cop NPCs in the affected zone
- Add the player as a 911-tipoff blip on cop minimaps
- Auto-route patrol AI through the hot zone

The event payload already carries `module`, `zoneId`, `center`, and the
heat value, so atlas_dispatch can choose tier of response per crime
type without atlas_crimelife caring.

### Voucher / "info scrap" bridge (planned)

Cross-tier drops from entry crimes that gangs need for higher-tier
operations. Design intent:

| Drop item                 | From                  | Used by                         |
|---------------------------|-----------------------|---------------------------------|
| `info_scrap_meter`        | parkingmeters (rare)  | future protection rework        |
| `info_scrap_industrial`   | copperscrap (rare)    | (future) heist intel            |

Implementation deferred until the protection-rework module ships.

### Gang archetypes (planned)

Mafia / Cartel / Street Gang / MC will have distinct economic
operational philosophies (see design notes). atlas_crimelife is
designed so each archetype can plug into specific modules:

- **MC** → owns the chop-shop premium tier + bonus VIN-scratch success rate
- **Cartel** → owns shadowmarket production (lab module, deferred)
- **Street Gang** → parkingmeters bonus on home turf (homeland_bonus perm already shipped)
- **Mafia** → laundering primary in the protection rework

Will be wired via a gang `archetype` field on `atlas_mgmt`'s org config
once that field exists.

---

## Deferred modules

| Module                | Why deferred                                                  |
|-----------------------|---------------------------------------------------------------|
| Protection rework          | Replaces the removed racketeering / catalytic system; design TBD |
| Phase 4.3 — porch piracy   | Needs NPC homeowner / Ring-camera AI; waits on atlas_dispatch |
| Phase 4.5 — laundromat     | Needs interior NPC crowd-control AI; waits on atlas_dispatch  |
| Cartel "The Lab" production | Bigger crafting module; will hook into atlas_crafting         |
| MC "Formation" buff   | Needs a vehicle-formation detector; small follow-up           |
| Mafia "Backroom" influence | Hook for laundering business fronts; waits on archetypes      |

---

## File map

```
atlas_crimelife/
├── fxmanifest.lua                  -- top-level loader; module list
├── config.lua                       -- shared tier definitions (Mule/Distributor/Kingpin)
├── README.md                        -- this file
├── shared/
│   ├── streetcred.lua               -- thin atlas_core PlayerData.crime wrapper
│   └── perms.lua                    -- gang-perm checks
├── gangvault/                       -- gang shared markedbills balance (server-only)
│   ├── config.lua / server.lua
├── shadowmarket/                    -- TIER 3 — solo logistics
│   ├── config.lua / client.lua / server.lua
├── chopshop/                        -- TIER 2 — vehicle stripping
│   ├── config.lua / client.lua / server.lua
├── vinscratch/                      -- TIER 2 — plate scrub
│   ├── config.lua / client.lua / server.lua
├── cloning/                         -- TIER 2 — plate reflash
│   ├── config.lua / client.lua / server.lua
├── parkingmeters/                   -- TIER 1 — meters/payphones (heat-zone owner)
│   ├── config.lua / client.lua / server.lua
└── copperscrap/                     -- TIER 1 — AC + electrical
    └── config.lua / client.lua / server.lua
```

Each module is independently disablable. None of them depend on
another's runtime — only on shared exports (StreetCred, BumpHeat,
IsScratched, MarkScratched, GrantOwnerKey).

---

## Conventions

- **Player throttle keys** are always `citizenid`, never `source`.
- **Per-prop / per-vehicle keys** are rounded coords (`int*10`) for
  world props, plate text for vehicles. Stable across clients and
  doesn't depend on entity ids.
- **Mongo writes** never use `upsert`. Always `findOne` → `updateOne`
  with explicit `$set` OR `insertOne` if missing. Mirrors atlas_inv /
  atlas_phone / atlas_mechanic patterns to avoid the `upsert`
  silent-error trap.
- **Crime payouts** always go to `markedbills` via
  `exports['atlas_inv']:AddItem(src, 'markedbills', amount, ...)`.
  Players never receive clean cash directly from a crime; the
  in-game launder bridge that converted markedbills → cash was
  removed alongside racketeering and is pending the protection
  rework. There are zero `Player.Functions.AddMoney('cash', ...)`
  calls in this resource today.
- **Cross-module data** flows through exports, never event-listeners,
  unless the receiver wants to react asynchronously (heat:rise).
- **fxmanifest order matters**: `gangvault` BEFORE consumer modules so
  Credit/Debit exports are available; `vinscratch` BEFORE `cloning`
  (cloning calls `MarkScratched`); `parkingmeters` BEFORE `copperscrap`
  (it calls `BumpHeat`).
