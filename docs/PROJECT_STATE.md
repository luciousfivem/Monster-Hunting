# Project State

Running summary, updated at the end of every phase so context never drifts.
**Last updated:** end of Phase 1 (data layer).

| Phase | Status |
| --- | --- |
| 1. Data layer | **done** (this document) |
| 2. Persistence and sessions | next |
| 3-12 | not started |

## Locked decisions

1. **Toolchain:** Rojo project, `.luau` files, `--!strict` + full annotations everywhere (`.luaurc` sets `languageMode: strict`). No Wally/runtime dependencies yet.
2. **Layout:** `ReplicatedStorage.Shared` <- `src/shared`; `ServerScriptService.Bootstrap` + `.Services` <- `src/server`; `StarterPlayerScripts` <- `src/client` (`Controllers/`, `UI/`); `ServerStorage.Tests` <- `tests`.
3. **One types file.** Every shared type is declared in `Shared/Types.luau`; other modules say `Types.Foo` and never re-declare. (Also what makes the offline type-linker work.)
4. **Ids** are `lower_snake_case` strings; the only cross-reference mechanism.
5. **Content is data.** One module per kind under `Shared/Data/`. `Species.luau` stays a single file until ~50 species, then becomes a folder behind the same registry (consumers unaffected).
6. **Abilities and status effects are data naming a `behavior`** (a hook module the battle engine implements in Phase 3) plus `params`. *Deviation from the spec's "hook-based modules" wording:* the hooks stay code, the data stays serializable and validatable. New ability reusing a behavior = zero code; new behavior = one new module, never an edit to the engine core. `DataValidator.validate(raw, { behaviors = registry })` verifies references and `paramsCheck` schemas once Phase 3 supplies the registry; until then it emits one `behaviors_unverified` warning.
7. **Moves are declarative** (`effects[]` over a closed set of kinds: `inflictStatus`, `statStage`, `recoil`, `drain`, `heal`). New kind = engine change; new move = zero code.
8. **Progression:** `xp` (total) is the source of truth; `level` is a cached copy that must agree with xp on the species' growth curve. Level 1 always costs exactly 0 xp (validator-enforced). Curves are integer polynomials with a divisor (bit-exact everywhere).
9. **Stats are never stored.** Derived from species + level + IVs + nature by `StatCalculator`. Formula: HP `floor((2b+iv)*L/100)+L+10`; others `floor((2b+iv)*L/100)+5`, nature +-10% via integer math. No EVs.
10. **Persistence scope on OwnedMonster:** HP persists (`currentHp`, nil = full); PP and status effects are battle-scoped. *`currentHp` is an addition to the spec's field list* (without it every battle starts at full HP and healing items/economy are meaningless). Adding it later would have needed a v2 migration.
11. **Own PRNG** (`Utils/Rng`: xoshiro128**, splitmix32 seeding) instead of Roblox `Random`, so battle replays are reproducible regardless of engine updates. Verified against an independent BigInt implementation.
12. **Fail closed.** Invalid content = the server refuses to boot (Studio: error; live: kick everyone and error). A server running bad data can corrupt saves.
13. **Names/art are original.** Asset ids are `0` = unassigned; reported as one aggregated warning.
14. **Trade eligibility, MVP:** species-level `tradeable` and item-level `tradeable` flags exist. A per-monster lock flag is deferred (additive via migration).

## Files (Phase 1)

| Path | Purpose |
| --- | --- |
| `default.project.json`, `.luaurc`, `stylua.toml`, `.gitignore` | project config |
| `src/shared/Types.luau` | all shared types |
| `src/shared/Constants.luau` | rule constants + closed vocabularies (frozen) |
| `src/shared/Utils/Table.luau` | `isArray`, `deepFreeze`, `deepCopy`, `toSet`, `countKeys`, `sortedKeys` |
| `src/shared/Utils/Rng.luau` | seeded PRNG |
| `src/shared/Utils/Schema.luau` | composable runtime validation of untrusted data |
| `src/shared/Monster/Growth.luau` | xp <-> level |
| `src/shared/Monster/StatCalculator.luau` | stat formula |
| `src/shared/Monster/Nickname.luau` | structural nickname rules (not moderation) |
| `src/shared/Monster/MonsterSchema.luau` | strict validation of one OwnedMonster |
| `src/shared/Monster/MonsterFactory.luau` | creates legal OwnedMonsters (RNG/GUID/clock injected) |
| `src/shared/Data/init.luau` | `require(Shared.Data)` -> frozen `GameData` |
| `src/shared/Data/{Species,Moves,Abilities,Items,StatusEffects,Natures,GrowthCurves,TypeChart,EncounterTables}.luau` | content (15 species, 25 moves, 9 abilities, 10 items, 5 statuses, 25 natures, 4 curves, 8 elements, 3 encounter tables) |
| `src/shared/Data/Registry.luau` | raw lists -> id maps, sorted lists, reverse evolution index (never throws) |
| `src/shared/Data/DataValidator.luau` | startup validation (shape + semantics + graph rules) |
| `src/server/Bootstrap.server.luau` | single entry point; ordered service start; fail-closed |
| `src/server/Services/DataValidationService.luau` | runs the validator at boot |
| `tests/{TestKit,Run}.luau`, `tests/*.spec.luau` | dependency-free specs, run in Studio |
| `tools/verify/*` | optional offline verification (Node) |

## Public API

```lua
-- Shared/Data  (frozen)
GameData.species[id] / .speciesList          -- ordered by dexNumber
GameData.moves / .abilities / .items / .statusEffects / .natures / .growthCurves / .encounterTables   (+ *List)
GameData.elementTypes[id], GameData.typeChart, GameData.evolvesFrom[speciesId] -> {speciesId}
GameData.raw, GameData.buildIssues           -- inputs to the validator

-- Shared/Data/DataValidator
validate(raw: any, options: ValidateOptions?) -> ValidationReport   -- never throws
formatReport(report) -> string ; assertValid(report)                -- throws once with the whole report

-- Shared/Monster
Growth.xpForLevel(curve, level) -> number ; Growth.levelForXp(curve, xp) -> number
StatCalculator.computeStat(statId, base, iv, level, nature?) -> number ; .computeAll(species, monster, nature?) -> StatBlock
Nickname.normalize(raw) -> string ; Nickname.validate(any) -> (boolean, reason?)
MonsterSchema.validate(data, monster: any, rootPath?) -> {Issue}    -- never throws, reports only
MonsterFactory.create(data, params: MonsterCreateParams, deps: MonsterFactoryDeps) -> (OwnedMonster?, err?)
MonsterFactory.defaultMoveset(species, level) -> {string}

-- Shared/Utils
Rng.new(seed) / Rng.fromState(seed, state) -> Rng{ nextU32, nextFloat, nextInt(min,max), chance(pct), getState }
Rng.pickWeighted(rng, entries, weightOf) -> entry?
Schema.{integer,number,boolean,string,identifier,oneOf,optional,custom,array,map,object}; Schema.check(check, value, path) -> {Issue}; Schema.add(...)
Table.{isArray,deepFreeze,deepCopy,toSet,countKeys,sortedKeys}
```

## OwnedMonster v1 (`Constants.MONSTER_SCHEMA_VERSION = 1`)

`guid, speciesId, nickname?, level, xp, ivs{hp,attack,defense,spAttack,spDefense,speed}, natureId, moveset[1..4], abilityId, originalTrainerUserId, caughtAt, caughtMethod, tradeCount, currentHp?, schemaVersion`

## Verification record (end of Phase 1)

Run with third-party Luau-in-WASM builds (`luau-web` 1.5.1 VM, `@luau2ts/analyzer` 0.1.0), **not** Roblox's runtime:

- 85 specs pass; mutation check: 17/18 injected faults detected (the survivor is an equivalent mutant).
- `--!strict` analysis of 27 modules: 0 errors, 0 warnings. Negative control confirmed it flags wrong types and arity across `require` boundaries.
- Server bootstrap smoke test against a mock `game`: 5/5 scenarios; 5/5 injected faults detected.

**Never run or checked:** anything in real Roblox/Studio; Roblox-API usage in `src/server`; Rojo behavior (project file, `.luau` extension, `init.luau` mapping, `StarterPlayerScripts` class); `rojo build`.

## Open items to verify (do not rely on until checked)

- Rojo version required for `.luau` + `.server.luau` + `init.luau`; that `StarterPlayerScripts` is built as the right class.
- `HttpService:GenerateGUID(false)` output format (the schema accepts 16-64 chars of `[A-Za-z0-9-]`).
- Studio-emulated players' `UserId` range (schema allows negatives down to int32 min).
- Run `tests/Run` in Studio once: confirms PRNG vectors and everything else in the real VM.
- Current DataStore per-key size limit (believed 4 MB) and request budgets; ProfileStore API/version.
- TextService filtering and storage requirements for nicknames.

## Inputs for Phase 2

- `OwnedMonster` shape, `MonsterSchema.validate` (repair/quarantine logic builds on it), `Schema` (profile sanitization).
- Decide profile layout; recommendation: `monsters: { [guid]: OwnedMonster }` + `party: { guid }` + `box: { guid }` (O(1) ownership checks, atomic moves, no array holes), with a hard cap on total monsters to bound profile size.
- Library: **ProfileStore** (the successor to ProfileService by the same author) vendored under `src/server/Vendor/`; verify its current API and license before use.
- Replace `print`/`warn` in `DataValidationService` with the structured logger introduced in Phase 2.
- Trainer/NPC party data is not in the Phase 1 type list; needed by Phase 3 (wild and trainer battles).
