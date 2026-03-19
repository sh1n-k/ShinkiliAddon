# AGENTS.md

## Scope
- This repo contains a single WoW addon: `Shinkili/Shinkili.lua` and its `.toc`.
- Keep changes focused on addon behavior, addon UI, or local dev tooling for this repo.

## Git Safety
- Small doc or metadata-only changes may be committed directly on `main`.
- Ask before destructive or high-cost work: mass rename, migration, formatter-wide rewrite, binary changes, large dependency updates, or risky deletes.

## Validation
- Prefer the documented local flow first: `luacheck Shinkili/Shinkili.lua`, then `./scripts/sync_to_wow.sh`.
- If runtime verification is needed, use WoW `/reload` and `/sk`.
- If any validation is skipped, report why and leave the exact command.

## WoW Lua Guardrails
- Keep large UI builders split into helper functions. Do not grow a single options-window function into a monolith.
- WoW Lua can fail when one function captures too many locals through nested callbacks. Before adding more controls, move sections into helper builders or shared handlers.
- Reuse reset, refresh, and lifecycle handlers instead of duplicating the same long callback in multiple places.
