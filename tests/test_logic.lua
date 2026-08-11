#!/usr/bin/env lua
-- Unit tests for ShinkiliLogic (shipped pure domain).

local root = arg[0]:match("(.*/)")
package.path = root .. "../Shinkili/?.lua;" .. package.path

dofile(root .. "../Shinkili/ShinkiliLogic.lua")
local Logic = ShinkiliLogic

local failures = 0

local function check(name, condition, detail)
    if condition then
        print("  OK  " .. name)
    else
        failures = failures + 1
        print("  FAIL  " .. name .. (detail and (" — " .. detail) or ""))
    end
end

print("ShinkiliLogic")

check("clamp", Logic.clamp(10, 0, 5) == 5)
check("trim", Logic.trim("  ab  ") == "ab")
check("parseInteger ok", Logic.parseInteger("12.6") == 13)
check("parseInteger nil", Logic.parseInteger("x") == nil)

local mappings = {
    {spellId = 1, colorIndex = 2, markerIndex = 1},
    {spellId = 2, colorIndex = 3, markerIndex = 2},
}
check("color used by other", Logic.isColorUsedByOtherMapping(mappings, 1, 3) == true)
check("color free for self", Logic.isColorUsedByOtherMapping(mappings, 1, 2) == false)
check("suggested marker is unused", Logic.getSuggestedMarkerIndex(mappings, nil, 8) == 3)

check("search by name", Logic.matchesSearch(99, "Avenging Wrath", "wrath") == true)
check("search by id", Logic.matchesSearch(12345, "Foo", "123") == true)
check("search empty matches all", Logic.matchesSearch(1, "Foo", "  ") == true)
check("search miss", Logic.matchesSearch(1, "Foo", "bar") == false)

local defaultOverrides = {
    casting = {enabled = true, colorIndex = 1},
    channeling = {enabled = true, colorIndex = 2},
    empower = {enabled = true, colorIndex = 3},
}

local settings = {
    size = 9999,
    x = nil,
    y = nil,
    mappings = {
        {spellId = 100, colorIndex = 2, markerIndex = 1, moveGlow = true},
        {spellId = 100, colorIndex = 3, markerIndex = 2}, -- duplicate spell dropped
        {spellId = 200, colorIndex = 2, markerIndex = 1}, -- duplicate color dropped → nil color
        {spellId = -1, colorIndex = 4}, -- invalid spell
    },
    trackedSpells = {300},
    spellColors = {["300"] = 5},
    cooldownBox = {leftover = true},
    overrides = {
        casting = {enabled = false, colorIndex = 99},
    },
}

Logic.sanitizeSettings(settings, {
    sizeDefault = 64,
    xDefault = 0,
    yDefault = -120,
    pointDefault = "CENTER",
    relativePointDefault = "CENTER",
    legacyMappingSlots = 12,
    colorPaletteSize = 27,
    markerPaletteSize = 8,
    reservedOverrideSize = 6,
    defaultOverrides = defaultOverrides,
})

check("size clamped", settings.size == 300)
check("y default applied", settings.y == -120)
check("legacy tracked cleared", settings.trackedSpells == nil)
check("spellColors cleared", settings.spellColors == nil)
check("cooldownBox cleared", settings.cooldownBox == nil)
check("duplicate spell not kept twice", #settings.mappings == 2)
check("first mapping kept", settings.mappings[1].spellId == 100 and settings.mappings[1].colorIndex == 2)
check("second mapping color cleared when taken", settings.mappings[2].spellId == 200 and settings.mappings[2].colorIndex == nil)
check("markers assigned uniquely", settings.mappings[1].markerIndex ~= settings.mappings[2].markerIndex)
check("bad override color repaired", settings.overrides.casting.colorIndex == 1)
check("override enabled preserved false", settings.overrides.casting.enabled == false)
check("missing override filled", settings.overrides.channeling.colorIndex == 2)

-- legacy trackedSpells path when mappings empty
local legacy = {
    mappings = {},
    trackedSpells = {42, 43},
    spellColors = {["42"] = 4, ["43"] = 5},
}
Logic.sanitizeSettings(legacy, {
    sizeDefault = 64,
    xDefault = 0,
    yDefault = -120,
    pointDefault = "CENTER",
    relativePointDefault = "CENTER",
    legacyMappingSlots = 0,
    colorPaletteSize = 27,
    markerPaletteSize = 8,
    reservedOverrideSize = 6,
    defaultOverrides = defaultOverrides,
})
check("legacy tracked migrated count", #legacy.mappings == 2)
check("legacy color for 42", legacy.mappings[1].spellId == 42 and legacy.mappings[1].colorIndex == 4)

local priority = Logic.sanitizePriorityEntries({
    {spellId = 10, colorIndex = 3, enabled = true},
    {spellId = 10, colorIndex = 4},
    {spellId = 11, colorIndex = 1}, -- invalid color -> 2
    {spellId = -3},
}, 27)
check("priority unique spells", #priority == 2)
check("priority color repaired", priority[2].colorIndex == 2)
check("priority pick first active", Logic.pickPriorityEntry(priority, {[11] = true}).spellId == 11)
Logic.movePriorityEntry(priority, 2, -1)
check("priority move up", priority[1].spellId == 11)

local withExtras = {
    size = 64,
    mappings = {},
    overrides = {},
    locale = "koKR",
    defense = {
        entries = {{spellId = 55, colorIndex = 5, enabled = false}},
    },
    procs = {
        entries = {{spellId = 66, colorIndex = 99}},
    },
}
Logic.sanitizeSettings(withExtras, {
    sizeDefault = 64,
    xDefault = 0,
    yDefault = -120,
    pointDefault = "CENTER",
    relativePointDefault = "CENTER",
    legacyMappingSlots = 0,
    colorPaletteSize = 27,
    markerPaletteSize = 8,
    reservedOverrideSize = 6,
    defaultOverrides = defaultOverrides,
    defenseDefaults = {size = 48, x = 100, y = -120, point = "CENTER", relativePoint = "CENTER"},
})
check("locale normalized", withExtras.locale == "ko")
check("defense entry kept", #withExtras.defense.entries == 1 and withExtras.defense.entries[1].enabled == false)
check("proc color clamped", withExtras.procs.entries[1].colorIndex == 2)

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
