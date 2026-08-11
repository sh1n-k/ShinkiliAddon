# ShinkiliAddon

WoW retail addon: turns Blizzard Assisted Combat recommendations into configurable color signals.

## Features
- Map recommended spells to colors (main box)
- **SimC-verified pick**: reads what WoW 12.0 still exposes (secret-safe cooldown/buff probes, secondary resources, range, action-bar usability, locally reconstructed cooldowns/charges/DoTs) and lets the SimC priority override Blizzard's Assisted Combat pick only when every condition **that survived into the bundled data** is proven and the spell is castable right now — otherwise it defers to AC, so the signal is never worse than plain Assist. See `AGENTS.md` for what the upstream flattener drops.
- `/sk why` explains the current pick: reason, secret-probe health, tracker state, the candidate pool with castability, and per-gate verdicts
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
  ShinkiliLogic.lua    # pure domain: the pick pipeline (tested)
  ShinkiliSecret.lua   # 12.0 secret-value layer: tri-state reads, duration probe
  ShinkiliTrack.lua    # local cooldown / charge / target-DoT reconstruction
  ShinkiliEval.lua     # castability + SimC gate verdicts, per-pass memo
  ShinkiliSimcData.lua # SimC-derived priority tables (generated)
  Shinkili.lua         # UI + runtime
tools/gen_simc_priority.py
tests/test_load.lua    # every file compiles; TOC order (200-local cap guard)
tests/test_logic.lua
tests/test_secret.lua
tests/test_track.lua
tests/test_eval.lua
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
- Defense entries hide when the game confirms the spell is unusable, out of range, on cooldown, or unaffordable. Proc overlays hide on the first three but not on affordability — resources refill every GCD, so filtering on them would blink the box. Both stay visible when the client will not say: a dark box helps nobody.
- SimC can only override Assist on 207 of the 682 bundled entries: 446 carry conditions WoW 12.0 hides outright, and 29 more use gate kinds whose upstream data lost the operator, polarity or referenced spell. Some talent/set-bonus conjuncts are dropped upstream without any marker at all, so a promoted entry can still carry an unchecked build condition — see "Known data loss" in `AGENTS.md`.
- Repo tracks addon sources, tests, and local helper scripts only.
