# Monster Hunting

A monster-taming RPG for Roblox, written in Luau: capture, raise, breed, trade, battle, guilds, ranked PvP.
Server-authoritative. Cosmetic-first monetization. No sold stat advantages.

**Status:** Phase 1 (data layer) complete. See [`docs/PROJECT_STATE.md`](docs/PROJECT_STATE.md) for files, public APIs and decisions.

## Requirements

| Tool | Why | Notes |
| --- | --- | --- |
| [Rojo](https://rojo.space) 7.x + Studio plugin | sync `src/` into Studio, build `.rbxl` | Needs `.luau` file support. Believed to be Rojo 7.3+ (**verify** against the Rojo changelog). |
| Roblox Studio | run the game and the in-Studio tests | |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) (optional) | formatting; config in `stylua.toml` | |
| [Luau LSP](https://github.com/JohnnyMorganz/luau-lsp) (recommended) | strict type checking against Roblox's API in your editor | `.luaurc` already sets `strict`. |
| Node 18+ (optional) | the offline verifier in `tools/verify` | not needed to run the game |

There are **no runtime dependencies** in Phase 1. Phase 2 will add a profile-store library (see PROJECT_STATE).

Install the toolchain with whatever manager you prefer (Rokit, Aftman, or direct downloads), then:

```sh
rojo serve            # then press "Connect" in the Rojo Studio plugin
# or, to produce a place file:
rojo build -o MonsterHunting.rbxl
```

## Layout

```
default.project.json                 Rojo project (the tree below)
src/
  shared/            -> ReplicatedStorage.Shared
    Types.luau                       every shared type, in one file
    Constants.luau                   rule constants + closed vocabularies (frozen)
    Utils/           Table, Rng (seeded PRNG), Schema (runtime validation)
    Monster/         Growth, StatCalculator, Nickname, MonsterSchema, MonsterFactory
    Data/            (init.luau = `require(Shared.Data)`)
                     Species, Moves, Abilities, Items, StatusEffects, Natures,
                     GrowthCurves, TypeChart, EncounterTables   <- the content
                     Registry (index + derive), DataValidator (startup checks)
  server/
    Bootstrap.server.luau  -> ServerScriptService.Bootstrap   (single entry point)
    Services/              -> ServerScriptService.Services    (ModuleScripts, started in order)
  client/            -> StarterPlayer.StarterPlayerScripts
    Controllers/  UI/                (empty until Phase 8)
tests/               -> ServerStorage.Tests                   (specs, run in Studio)
tools/verify/                        optional offline verification (Node)
docs/PROJECT_STATE.md                running project summary
```

## Adding a monster

Append one record to `src/shared/Data/Species.luau` (and any new moves/abilities it references).
No logic changes. On the next server start the validator checks every reference, range, learnset
and evolution chain, and the server refuses to boot if anything is wrong.

## Testing

**In Studio** (the real Roblox runtime; run this at least once, it exercises behavior the offline
runner cannot, such as `bit32` in Roblox's VM):

```lua
-- Server command bar (Studio, while in a Play/Run session or edit mode)
local passed, failed, report = require(game.ServerStorage.Tests.Run)(game.ReplicatedStorage.Shared)
print(report)
```

**Offline** (optional; third-party Luau-in-WebAssembly builds, not Roblox):

```sh
cd tools/verify
npm ci
npm run verify      # tests + strict type-check + server bootstrap smoke test
```

See `tools/verify/*.mjs` headers for exactly what each script does and does not prove.

## Conventions

- `--!strict` and full type annotations on every module. Shared types live in `Types.luau`.
- Server is authoritative. Clients send intent only. (No Remotes exist yet.)
- All content is data in ModuleScripts under `Data/`; code never special-cases a species, move or item.
- Ids are `lower_snake_case` strings and are the only way records reference each other.
- Game data is deep-frozen at load. Mutating it is a bug and throws.
