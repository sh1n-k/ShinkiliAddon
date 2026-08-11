# AGENTS.md

## Scope
- WoW retail addon under `Shinkili/`: color-signal UI on top of Blizzard Assisted Combat.
- Keep changes limited to addon behavior/UI or local scripts/tests in this repo.

## Layout
| Path | Role |
|------|------|
| `Shinkili/Shinkili.toc` | Load order, interface versions, SavedVariables |
| `Shinkili/ShinkiliLocale.lua` | en/ko UI strings (`ShinkiliLocale`) |
| `Shinkili/ShinkiliLogic.lua` | Pure domain (no WoW API): sanitize, priority lists, `pickRecommendation` |
| `Shinkili/ShinkiliSecret.lua` | 12.0 secret-value layer: tri-state reads, DurationObject probe, resources |
| `Shinkili/ShinkiliTrack.lua` | Local cooldown / charge / target-DoT reconstruction |
| `Shinkili/ShinkiliEval.lua` | Display ids, castability verdicts, SimC gate verdicts, per-pass memo |
| `Shinkili/ShinkiliSimcData.lua` | Bundled SimC-derived priority tables (generated) |
| `Shinkili/Shinkili.lua` | Runtime UI, options tabs, indicators, slash, minimap |
| `tools/gen_simc_priority.py` | Regenerates `ShinkiliSimcData.lua` from JustAC/SimC source |
| `tests/test_load.lua` | Every file compiles + TOC load order (catches the 200-local cap) |
| `tests/test_logic.lua` | Unit tests for `ShinkiliLogic` + locale key parity |
| `tests/test_secret.lua` | Tri-state contract of `ShinkiliSecret` against a stubbed API |
| `tests/test_track.lua` | Local cooldown / charge / DoT reconstruction |
| `tests/test_eval.lua` | Castability verdicts, gate verdicts, per-pass memo dedup |
| `scripts/run_tests.sh` | Runs unit tests |
| `scripts/sync_to_wow.sh` | Copies addon into local WoW AddOns |

## SavedVariables
- `ShinkiliDB` (primary). Legacy `BlizzShinDB` is still accepted once at load.
- **Account-wide:** `locale`, minimap fields, cast/channel `overrides`.
- **Per character** (`charProfiles[Name-Realm].placement`): main/defense box size/position/lock/layer, blacklist toggle key.
- **Per character+spec** (`charProfiles[…].specs[CLASS_N]`): `mappings`, `procs.entries`, `defense.entries` (+ enabled), `blacklist.entries` / `cooldowns` / cooldown-filter `enabled`, `simcAssist`.
- Migration: v2 creates `charProfiles`; v3 stops sharing account-wide defense/proc/blacklist seeds across other characters. Spec lists lazy-clone from that character’s `seed`. Unknown-class defense/proc rows are pruned with `IsPlayerSpell` on bind.

## Runtime model
- **Main box (best single pick)** — `Logic.pickRecommendation`, four stages:
  1. **Pool**: AC primary → highlight lookahead → `GetRotationSpells`, normalised to display ids, blacklisted entries removed. The defense and proc boxes are user-curated lists and deliberately ignore the blacklist.
  2. **Hard filter**: drop anything the game *confirms* cannot be cast (`unusable` / `out_of_range` / `on_cd`). `no_resource` is transient and never removes a spell.
  3. **SimC override**: first SimC entry that is in the pool, has **every** gate proven `pass`, and reads `ready`. Reason `simc_verified`.
     - A gateless non-delegated entry is an unconditional APL line and stays promotable, but is vetoed by **self-redundancy** when its own buff is *confirmed* active or its own DoT *confirmed* live. Unreadable reads do not veto, so in combat with auras secret this rarely fires; the DoT half only ever applies to entries a `dot` gate also references (1 of 187 today).
     - A gate whose data cannot express the condition reads `unknown`: `cd` without a reference id (SimC's cooldown conditions name *other* spells), `dot` without polarity (`x.ticking` and `!x.ticking` flatten identically), `execute` without an operator (most upstream lines are `>N`, i.e. *not* execute range). Guessing any of these inverts half the cases.
  4. **Fallback**: AC primary → lookahead → first survivor. If the filter empties the pool, AC primary is still shown rather than blanking.
- **Core invariant**: an unreadable input is `unknown`, and unknown never wins. SimC may only outrank Blizzard on a fully proven entry, so the pick is never worse than plain AC.
- **The one waiver**: if the hard filter empties the pool, AC primary is shown even though it read as uncastable. Every probe reading "blocked" is far more likely to mean our probes are blind than that the whole rotation is down, and a blank box helps nobody. SimC can never exploit this — it still requires `ready`.
- **Defense box** is stricter than the main box: `no_resource` hides an entry there (a defensive you cannot afford is not an answer), while `unknown` still shows it.
- **`delegated` entries** (SimC condition needs a value 12.0 hides) are always `unknown` — they can never override AC. 446 of 682 bundled entries (65%). Of the remaining 236, **207 are promotable** and 29 are blocked by the lossy-gate rule above.
- **Proc** display override still wins on top of everything, and is castability-filtered with the **main-box** policy (`Eval.isPickable`): hidden on `unusable`/`out_of_range`/`on_cd`, shown on `no_resource`. Filtering procs on affordability would blink a procced spender at 20Hz.
- **Layers**: per-box `frameStrata` + `frameLevel` (options on Main / Defense).
- **Blacklist**: tab + filter toggle; capture keybind (key/mouse/wheel) via override binding; center toast on toggle.
- **Options tabs**: Main / Defense / Procs / Blacklist; language + minimap in footer.

## Git Safety
- Small doc/metadata-only changes may land on `main`.
- Ask before destructive or high-cost work (mass rename, formatter-wide rewrite, large dependency drops).

## Known data loss (upstream)
All of this happens in JustAC's `tools/gen_simc_rotations.py`, before our
generator sees anything. The original APLs are in `JustAC/tools/simc-apl/`.

| Atom | What is lost | Consequence here |
|------|--------------|------------------|
| `cooldown.X.remains/ready/up` | the referenced spell id, the operator and the threshold | 45 `cd` gates read `unknown`. 661/676 name a *different* spell, so substituting the entry's own cooldown would be a vacuous pass |
| `dot.X.ticking / .remains / .refreshable` | polarity, and the distinction between the three forms | 43 `dot` gates read `unknown`; guessing "must be missing" inverts every `.ticking` line |
| `target.health.pct` / `time_to_die` | the operator and the threshold | 15 `execute` gates read `unknown`; most upstream lines are `>N`, i.e. *not* execute range |
| `talent. / hero_tree. / set_bonus. / equipped.` | **dropped with no gate and no `delegated` marker** | ~57 lines flatten to gateless and stay promotable while an unchecked build condition applies; 17 of those are negated talents. Not detectable at runtime |
| buff tokens | resolved through a castable-spell index, so an aura whose id differs from its cast id arrives wrong | mitigated at runtime: a negated buff gate only trusts "absent" once that id has actually resolved to a player aura (`Secret.hasObservedAura`) |
| `spell_targets` | collapsed into the ST/AoE tier split | no `targets` gates are emitted; the evaluator branch is forward-compatible only |

Recovering the first three needs `id` **and** `op`/`n` (not just `neg`).
`tools/gen_simc_priority.py` already parses those fields and `ShinkiliEval`
already evaluates them, so nothing in the runtime has to change.

It does **not** require a JustAC change: every entry in
`JustAC/Data/SimcRotations.lua` carries its SimC token as a trailing comment
(`{id=46585,gates={}},  -- raise_dead`) and the raw APLs sit in
`JustAC/tools/simc-apl/*.simc`. Our generator throws the token away at
`tools/gen_simc_priority.py`'s entry regex. Joining on it inside this repo would
recover `dot` polarity, the `execute` operator, and the `cd` reference id (the
referenced token is usually another entry in the same spec list) — and would let
us mark the ~57 dropped-talent lines `delegated=true`, closing that hole
conservatively. The highest-value single change beyond that is emitting `talent`
as a real gate: `IsPlayerSpell` is never secret, so it is fully evaluable.

## Stage C semantics
The override takes the **highest-priority entry it can fully verify**, skipping
unverifiable ones above it rather than aborting. With 65% of entries `delegated`,
aborting at the first unknown would disable the feature outright. So the
guarantee is "nothing unproven ever wins", not "SimC's true first choice always
wins".

## Validation
Prefer in order:
1. `luacheck Shinkili/`
2. `./scripts/run_tests.sh`
3. `./scripts/sync_to_wow.sh` when in-game check is needed (`/reload`, `/sk`)

If a step is skipped, report why and the exact command.

## WoW Lua Guardrails
- **`Shinkili.lua` is one chunk and Lua caps a chunk at 200 locals.** luacheck reports a file over the cap as clean while the game refuses to load the addon. `tests/test_load.lua` guards this — when it trips, move a cohesive block into a module (that is why `ShinkiliEval.lua` exists), do not shave individual locals.
- Split large options UI into helper builders; avoid one monolithic options function.
- Nested callbacks that close over many locals can break WoW Lua — extract helpers before adding more controls.
- Reuse reset/refresh/lifecycle handlers instead of duplicating long callbacks.
