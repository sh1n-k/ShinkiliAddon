# ShinkiliAddon

`Shinkili` is a World of Warcraft addon that turns Blizzard Assisted Combat recommendations into configurable visual signals.

## Features

- Maps recommended spells to user-selected colors
- Supports search-first editing instead of preallocated empty slots
- Shows a helper marker, GCD spiral, and optional move glow per saved spell
- Supports reserved color overrides for casting, channeling, and empower states
- Includes indicator size and position controls

## Project Structure

- `Shinkili/Shinkili.toc`
- `Shinkili/Shinkili.lua`
- `scripts/sync_to_wow.sh`

## Local Install Target

The sync script copies files to:

`/Applications/World of Warcraft/_retail_/Interface/AddOns/Shinkili`

## Development

Sync the addon into the WoW AddOns directory:

```bash
./scripts/sync_to_wow.sh
```

Reload the UI in game:

```text
/reload
```

Open the addon settings:

```text
/sk
```

## Notes

- This project tracks only the source addon files and local sync helper.
- The addon is designed around a single visual indicator plus lightweight secondary signals.
- Blizzard Assisted Combat availability determines whether a recommendation can be shown.
