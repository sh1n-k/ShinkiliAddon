# ShinkiliAddon

WoW retail addon: turns Blizzard Assisted Combat recommendations into configurable color signals.

## Features
- Map recommended spells to colors (main box)
- **Position-1 core** (JustAC-style): AC primary → highlight lookahead → rotation pool; optional SimC ranks inside that live pool for one best color signal
- Defense tab: separate priority color box for usable defensive skills
- Procs tab: active spell overlays override the main box
- Blacklist tab with keybind toggle + center toast
- Frame layer (strata/level) for main and defense boxes
- English / Korean UI language (saved)
- Minimap button and `/sk` for settings

## Layout
```
Shinkili/
  Shinkili.toc
  ShinkiliLocale.lua   # en/ko strings
  ShinkiliLogic.lua    # pure domain (tested)
  ShinkiliSimcData.lua # SimC-derived priority tables (generated)
  Shinkili.lua         # UI + runtime
tools/gen_simc_priority.py
tests/test_logic.lua
scripts/run_tests.sh
scripts/sync_to_wow.sh
```

## Local install
`./scripts/sync_to_wow.sh` copies into:

`/Applications/World of Warcraft/_retail_/Interface/AddOns/Shinkili`

## Development
```bash
luacheck Shinkili/
./scripts/run_tests.sh
./scripts/sync_to_wow.sh
```

In game: `/reload`, then `/sk` (or minimap left-click).  
Language: Main tab buttons or `/sk lang en|ko`.  
Restore minimap button: `/sk minimap on`.

## Notes
- Display depends on Assisted Combat being available.
- Defense usability and proc overlays use client APIs that may be limited in combat (fail-closed when unreadable).
- Repo tracks addon sources, tests, and local helper scripts only.
