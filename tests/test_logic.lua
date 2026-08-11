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

check("frame strata valid", Logic.sanitizeFrameStrata("DIALOG", "MEDIUM") == "DIALOG")
check("frame strata fallback", Logic.sanitizeFrameStrata("NOPE", "HIGH") == "HIGH")
check("frame level clamp", Logic.sanitizeFrameLevel(0, 50) == 1)

local bl = Logic.sanitizeBlacklistEntries({
    {spellId = 7, enabled = true},
    {spellId = 7, enabled = false},
    {spellId = 8, enabled = false},
    9,
    -1,
})
check("blacklist unique", #bl == 3)
check("blacklist disabled kept", bl[2].enabled == false)
check("blacklist filter off ignores", Logic.isSpellBlacklisted(bl, 7, false) == false)
check("blacklist enabled hits", Logic.isSpellBlacklisted(bl, 7, true) == true)
check("blacklist disabled entry skipped", Logic.isSpellBlacklisted(bl, 8, true) == false)
-- 8 is present but entry.enabled=false → not filtered; chosen over 9
check("pick recommended skips blacklisted", Logic.pickRecommendedSpell(7, {8, 9}, bl, true) == 8)
check("pick recommended when filter off", Logic.pickRecommendedSpell(7, {9}, bl, false) == 7)
check("pick all blacklisted yields nil", Logic.pickRecommendedSpell(7, {7, 9}, bl, true) == nil)

local simcEntries = {
    {id = 100},
    {id = 200, gates = {{t = "proc"}}},
    {id = 300},
}
local function gateOk(entry)
    if type(entry.gates) ~= "table" then
        return true
    end
    for _, g in ipairs(entry.gates) do
        if g.t == "proc" then
            return false
        end
    end
    return true
end

local id, reason = Logic.pickBestRecommendation(50, {300}, simcEntries, {
    simcAssist = false,
    blacklistEnabled = false,
    gateOk = gateOk,
})
check("assist mode AC primary", id == 50 and reason == "ac_primary")

id, reason = Logic.pickBestRecommendation(50, {300}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
})
-- 300 is in SimC list and in AC pool → ranks above bare primary 50
check("simc mode ranks AC pool by SimC", id == 300 and reason == "simc_rank")

id, reason = Logic.pickBestRecommendation(50, {}, {{id = 100}}, {
    simcAssist = true,
    blacklistEnabled = false,
})
check("simc mode keeps sole AC candidate", id == 50 and reason == "ac_primary")

id, reason = Logic.pickBestRecommendation(100, {300}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 100, enabled = true}},
    gateOk = gateOk,
})
check("blacklist drops primary then SimC", id == 300 and reason == "simc_rank")

id, reason = Logic.pickBestRecommendation(nil, {}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
})
-- pool empty without AC → none (SimC alone does not invent outside AC pool)
check("no AC pool yields none", id == nil and reason == "none")

id, reason = Logic.pickBestRecommendation(200, {100, 300}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
    isUsable = function(spellId)
        return spellId ~= 100
    end,
})
check("prefer usable over higher simc unusable", id == 300)

-- gate skips 200; pool is empty of AC so none unless we pass candidates
id, reason = Logic.pickBestRecommendation(200, {100}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
})
check("gate skips proc-gated id in simc pass", id == 100 and reason == "simc_rank")

-- Position-1 core API (primary / lookahead / rotation explicit)
id, reason = Logic.pickPosition1Recommendation(10, 20, {30, 40}, nil, {
    simcAssist = false,
    blacklistEnabled = false,
})
check("p1 primary wins", id == 10 and reason == "ac_primary")

id, reason = Logic.pickPosition1Recommendation(10, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 10, enabled = true}},
})
check("p1 blacklist uses lookahead", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickPosition1Recommendation(10, 20, {30, 40}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {
        {spellId = 10, enabled = true},
        {spellId = 20, enabled = true},
    },
})
check("p1 rotation after primary+lookahead blocked", id == 30 and reason == "ac_candidate")

id, reason = Logic.pickPosition1Recommendation(10, 20, {30, 300}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
})
-- pool {10,20,30,300}; SimC order 100(out),200(gate fail),300 → 300 ranks first among pool
check("p1 simc ranks within pool", id == 300 and reason == "simc_rank")

id, reason = Logic.pickPosition1Recommendation(9001, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 9999, enabled = true}},
    displayOf = function(spellId)
        if spellId == 9001 then
            return 9999
        end
        return spellId
    end,
})
check("p1 blacklist matches display id", id == 20 and reason == "ac_lookahead")

-- BL stores book base; AC supplies override id → still blocked via displayOf(entry)
id, reason = Logic.pickPosition1Recommendation(9001, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 8000, enabled = true}},
    displayOf = function(spellId)
        if spellId == 8000 or spellId == 9001 then
            return 9001
        end
        return spellId
    end,
})
check("p1 blacklist reverse displayOf entry", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickPosition1Recommendation(10, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = false,
    suppressPick = function(spellId)
        return spellId == 10
    end,
})
check("p1 suppress primary uses lookahead", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickPosition1Recommendation(10, 20, {30, 100, 300}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
    isUsable = function(spellId)
        return spellId ~= 100
    end,
})
-- SimC among pool: 100 then 300; 100 unusable → 300
check("p1 simc soft skip unusable", id == 300 and reason == "simc_rank")

-- All unusable → soft fallback to ranked head (do not empty)
id, reason = Logic.pickPosition1Recommendation(10, 20, {100}, simcEntries, {
    simcAssist = true,
    blacklistEnabled = false,
    gateOk = gateOk,
    isUsable = function()
        return false
    end,
})
check("p1 all unusable soft keeps head", id == 100 and reason == "simc_rank")

-- simcAssist on but empty entries → pure AC (no soft usable demotion path needed)
id, reason = Logic.pickPosition1Recommendation(10, 20, {30}, {}, {
    simcAssist = true,
    blacklistEnabled = false,
    isUsable = function()
        return false
    end,
})
check("p1 empty simc stays AC primary", id == 10 and reason == "ac_primary")

-- No SimC pool overlap → ignore isUsable demotion of AC primary
id, reason = Logic.pickPosition1Recommendation(10, 20, {30}, {{id = 999}}, {
    simcAssist = true,
    blacklistEnabled = false,
    isUsable = function(spellId)
        return spellId ~= 10
    end,
})
check("p1 no simc hit skips usable demote", id == 10 and reason == "ac_primary")

check("blacklist nil filter is off", Logic.isSpellBlacklisted(bl, 7, nil) == false)

local fakeData = {
    specs = {
        TEST_1 = {
            st = {{id = 1}, {id = 2}},
            aoe = {{id = 9}},
        },
    },
}
check("simc spec table", Logic.getSimcSpecTable(fakeData, "TEST_1") ~= nil)
check("simc context st", Logic.getSimcContextEntries(fakeData.specs.TEST_1, false)[1].id == 1)
check("simc context aoe", Logic.getSimcContextEntries(fakeData.specs.TEST_1, true)[1].id == 9)

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
