# AGENTS.md

## Scope
- WoW retail addon under `Shinkili/`: color-signal UI on top of Blizzard Assisted Combat.
- Keep changes limited to addon behavior/UI or local scripts/tests in this repo.

## Layout
| Path | Role |
|------|------|
| `Shinkili/Shinkili.toc` | Load order, interface versions, SavedVariables |
| `Shinkili/ShinkiliLocale.lua` | en/ko UI strings (`ShinkiliLocale`) |
| `Shinkili/ShinkiliLogic.lua` | Pure domain (no WoW API): sanitize, priority lists, helpers |
| `Shinkili/Shinkili.lua` | Runtime UI, options tabs, indicators, slash, minimap |
| `tests/test_logic.lua` | Unit tests for `ShinkiliLogic` |
| `scripts/run_tests.sh` | Runs unit tests |
| `scripts/sync_to_wow.sh` | Copies addon into local WoW AddOns |

## SavedVariables
- `ShinkiliDB` (primary). Legacy `BlizzShinDB` is still accepted once at load.
- Important keys: `mappings`, `overrides`, `defense` (entries + box placement), `procs.entries`, `locale` (`en`/`ko`), minimap fields, main indicator placement.

## Runtime model
- **Main box**: AC `GetNextCastSpell` → mapping color; active **proc** (priority list + overlay) overrides spell/color; cast/channel/empower reserved overrides apply when not on proc/preview.
- **Defense box**: separate frame; shows highest-priority **usable** defense entry color.
- **Options**: tabs Main / Defense / Procs; language on Main; minimap button toggles options.

## Git Safety
- Small doc/metadata-only changes may land on `main`.
- Ask before destructive or high-cost work (mass rename, formatter-wide rewrite, large dependency drops).

## Validation
Prefer in order:
1. `luacheck Shinkili/`
2. `./scripts/run_tests.sh`
3. `./scripts/sync_to_wow.sh` when in-game check is needed (`/reload`, `/sk`)

If a step is skipped, report why and the exact command.

## WoW Lua Guardrails
- Split large options UI into helper builders; avoid one monolithic options function.
- Nested callbacks that close over many locals can break WoW Lua — extract helpers before adding more controls.
- Reuse reset/refresh/lifecycle handlers instead of duplicating long callbacks.
