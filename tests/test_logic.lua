#!/usr/bin/env lua
-- Unit tests for ShinkiliLogic (pure domain, no WoW API).

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

local defaultOverrides = {
    casting = {enabled = true, colorIndex = 1},
    channeling = {enabled = true, colorIndex = 2},
    empower = {enabled = true, colorIndex = 3},
}

local function baseConfig(extra)
    local config = {
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
    }
    if extra then
        for key, value in pairs(extra) do
            config[key] = value
        end
    end
    return config
end

print("ShinkiliLogic")

-- primitives
check("clamp high", Logic.clamp(10, 0, 5) == 5)
check("clamp low", Logic.clamp(-1, 0, 5) == 0)
check("trim", Logic.trim("  ab  ") == "ab")
check("parseInteger ok", Logic.parseInteger("12.6") == 13)
check("parseInteger nil", Logic.parseInteger("x") == nil)
check("normalizeLocale en", Logic.normalizeLocale("enUS") == "en")
check("normalizeLocale koKR", Logic.normalizeLocale("koKR") == "ko")
check("normalizeLocale ko", Logic.normalizeLocale("ko") == "ko")

-- mapping helpers
local mappings = {
    {spellId = 1, colorIndex = 2, markerIndex = 1},
    {spellId = 2, colorIndex = 3, markerIndex = 2},
}
check("color used by other", Logic.isColorUsedByOtherMapping(mappings, 1, 3) == true)
check("color free for self", Logic.isColorUsedByOtherMapping(mappings, 1, 2) == false)
check("suggested marker unused", Logic.getSuggestedMarkerIndex(mappings, nil, 8) == 3)
check("search by name", Logic.matchesSearch(99, "Avenging Wrath", "wrath") == true)
check("search by id", Logic.matchesSearch(12345, "Foo", "123") == true)
check("search empty matches all", Logic.matchesSearch(1, "Foo", "  ") == true)
check("search miss", Logic.matchesSearch(1, "Foo", "bar") == false)

-- sanitize mappings + overrides + legacy cleanup
local settings = {
    size = 9999,
    x = nil,
    y = nil,
    mappings = {
        {spellId = 100, colorIndex = 2, markerIndex = 1, moveGlow = true},
        {spellId = 100, colorIndex = 3, markerIndex = 2},
        {spellId = 200, colorIndex = 2, markerIndex = 1},
        {spellId = -1, colorIndex = 4},
    },
    trackedSpells = {300},
    spellColors = {["300"] = 5},
    cooldownBox = {leftover = true},
    overrides = {
        casting = {enabled = false, colorIndex = 99},
    },
}
Logic.sanitizeSettings(settings, baseConfig({legacyMappingSlots = 12}))
check("size clamped", settings.size == 300)
check("y default applied", settings.y == -120)
check("legacy tracked cleared", settings.trackedSpells == nil)
check("spellColors cleared", settings.spellColors == nil)
check("cooldownBox cleared", settings.cooldownBox == nil)
check("duplicate spell dropped", #settings.mappings == 2)
check("first mapping kept", settings.mappings[1].spellId == 100 and settings.mappings[1].colorIndex == 2)
check("duplicate color cleared", settings.mappings[2].spellId == 200 and settings.mappings[2].colorIndex == nil)
check("markers unique", settings.mappings[1].markerIndex ~= settings.mappings[2].markerIndex)
check("override color repaired", settings.overrides.casting.colorIndex == 1)
check("override enabled false kept", settings.overrides.casting.enabled == false)
check("missing override filled", settings.overrides.channeling.colorIndex == 2)

-- legacy migration when mappings empty
local legacy = {
    mappings = {},
    trackedSpells = {42, 43},
    spellColors = {["42"] = 4, ["43"] = 5},
}
Logic.sanitizeSettings(legacy, baseConfig())
check("legacy migrated count", #legacy.mappings == 2)
check("legacy color 42", legacy.mappings[1].spellId == 42 and legacy.mappings[1].colorIndex == 4)

-- priority lists
local priority = Logic.sanitizePriorityEntries({
    {spellId = 10, colorIndex = 3, enabled = true},
    {spellId = 10, colorIndex = 4},
    {spellId = 11, colorIndex = 1},
    {spellId = -3},
    {spellId = 12, colorIndex = 5, enabled = false},
}, 27)
check("priority unique spells", #priority == 3)
check("priority color repaired", priority[2].colorIndex == 2)
check("priority disabled preserved", priority[3].enabled == false)
check("pick skips disabled", Logic.pickPriorityEntry(priority, {[12] = true}) == nil)
check("pick first active", Logic.pickPriorityEntry(priority, {[11] = true, [10] = true}).spellId == 10)
check("pick empty set", Logic.pickPriorityEntry(priority, {}) == nil)
check("move up", Logic.movePriorityEntry(priority, 2, -1) == true and priority[1].spellId == 11)
check("move out of bounds", Logic.movePriorityEntry(priority, 1, -1) == false)
check("move nil list", Logic.movePriorityEntry(nil, 1, 1) == false)

-- defense / procs / locale via sanitizeSettings
local withExtras = {
    size = 64,
    mappings = {},
    overrides = {},
    locale = "koKR",
    defense = {
        size = 10,
        entries = {{spellId = 55, colorIndex = 5, enabled = false}},
    },
    procs = {
        entries = {{spellId = 66, colorIndex = 99}},
    },
}
Logic.sanitizeSettings(withExtras, baseConfig())
check("locale normalized", withExtras.locale == "ko")
check("defense size clamped", withExtras.defense.size == 24)
check("defense entry kept", #withExtras.defense.entries == 1 and withExtras.defense.entries[1].enabled == false)
check("proc color clamped", withExtras.procs.entries[1].colorIndex == 2)
check("copyDefaultOverrides independent", (function()
    local a = Logic.copyDefaultOverrides(defaultOverrides)
    a.casting.enabled = false
    return defaultOverrides.casting.enabled == true
end)())

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
