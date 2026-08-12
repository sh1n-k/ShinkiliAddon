#!/usr/bin/env lua
-- Unit tests for ShinkiliLogic (pure domain, no WoW API).

local root = arg[0]:match("(.*/)")
package.path = root .. "../Shinkili/?.lua;" .. package.path

dofile(root .. "../Shinkili/ShinkiliLogic.lua")
dofile(root .. "../Shinkili/ShinkiliLocale.lua")
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
check("first free color from top", Logic.getFirstFreeColorIndex(mappings, nil, 27) == 4)
check("first free skips used, keeps own", Logic.getFirstFreeColorIndex(mappings, 1, 27) == 2)
check("first free nil when full", Logic.getFirstFreeColorIndex({
    {colorIndex = 2}, {colorIndex = 3},
}, nil, 3) == nil)
check("suggested marker unused", Logic.getSuggestedMarkerIndex(mappings, nil, 8) == 3)

check("interrupt show when kickable", Logic.shouldShowInterruptIndicator(true, false, true) == true)
check("interrupt hide when shielded", Logic.shouldShowInterruptIndicator(true, true, true) == false)
check("interrupt hide when not casting", Logic.shouldShowInterruptIndicator(false, false, true) == false)
check("interrupt hide when secret/inaccessible", Logic.shouldShowInterruptIndicator(true, false, false) == false)
local iw, ih, ig = Logic.interruptBoxLayout(64)
check("interrupt layout width", iw == 64)
check("interrupt layout height", ih == 22)
check("interrupt layout gap", ig == 5)

check("character key with realm", Logic.characterKey("Shindra", "아즈샤라") == "Shindra-아즈샤라")
check("character key strips realm spaces", Logic.characterKey("Foo", "Area 52") == "Foo-Area52")
check("character key defers without realm", Logic.characterKey("Solo", "") == nil)
check("character key nil name", Logic.characterKey(nil, "Realm") == nil)
check("character name from key", Logic.characterNameFromKey("Shindra-아즈샤라") == "Shindra")
check("character name from bad key", Logic.characterNameFromKey("Solo") == nil)

local account = {
    mappings = {
        {spellId = 10, colorIndex = 2},
        {spellId = 20, colorIndex = 3},
    },
    legacyMappingsCharacter = "Shindra-아즈샤라",
}
Logic.migrateLegacyCharMappings(account, "Other-Realm", account.legacyMappingsCharacter)
check("legacy moved to preferred owner", account.charMappings["Shindra-아즈샤라"] ~= nil)
check("legacy owner has two mappings", #account.charMappings["Shindra-아즈샤라"] == 2)
check("root mappings cleared", account.mappings == nil)
check("legacy owner field cleared", account.legacyMappingsCharacter == nil)

local accountCurrent = {
    mappings = {
        {spellId = 99, colorIndex = 4},
    },
}
Logic.migrateLegacyCharMappings(accountCurrent, "Me-Realm", nil)
check("legacy falls back to current character", #accountCurrent.charMappings["Me-Realm"] == 1)

local accountDeferred = {
    mappings = {
        {spellId = 7, colorIndex = 2},
    },
}
Logic.migrateLegacyCharMappings(accountDeferred, nil, nil)
check("legacy defers without character key", accountDeferred.mappings ~= nil and #accountDeferred.mappings == 1)

local liveList = {{spellId = 1, colorIndex = 2}}
local accountLive = {
    charMappings = {["Me-Realm"] = liveList},
    mappings = liveList,
}
Logic.migrateLegacyCharMappings(accountLive, "Me-Realm", nil)
check("live char bucket not treated as legacy", accountLive.mappings == liveList)
check("live char bucket unchanged", #accountLive.charMappings["Me-Realm"] == 1)

local accountOrphan = {
    charMappings = {
        Shindra = {{spellId = 42, colorIndex = 3}},
    },
}
check("rehome name-only bucket", Logic.rehomeNameOnlyCharMappings(accountOrphan, "Shindra-아즈샤라") == true)
check("rehome target filled", #accountOrphan.charMappings["Shindra-아즈샤라"] == 1)
check("rehome orphan cleared", accountOrphan.charMappings.Shindra == nil)

local accountOrphanBlocked = {
    charMappings = {
        Shindra = {{spellId = 1, colorIndex = 2}},
        ["Shindra-아즈샤라"] = {{spellId = 2, colorIndex = 3}},
    },
}
check("rehome skips non-empty target", Logic.rehomeNameOnlyCharMappings(accountOrphanBlocked, "Shindra-아즈샤라") == false)

-- Two-pass bind: migrate once, then live pointer must survive a second migrate.
local cycle = {
    mappings = {{spellId = 10, colorIndex = 2}},
    charMappings = {},
}
Logic.migrateLegacyCharMappings(cycle, "Hero-Realm", nil)
cycle.mappings = cycle.charMappings["Hero-Realm"]
check("cycle after first migrate has one", #cycle.mappings == 1)
cycle.mappings = {{spellId = 10, colorIndex = 2, markerIndex = 1}}
cycle.charMappings["Hero-Realm"] = cycle.mappings
local liveRef = cycle.mappings
Logic.migrateLegacyCharMappings(cycle, "Hero-Realm", nil)
check("cycle second migrate keeps live ref", cycle.mappings == liveRef)
check("cycle second migrate keeps entries", #cycle.charMappings["Hero-Realm"] == 1)

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

local cds = Logic.sanitizeBlacklistEntries({
    {spellId = 6673, enabled = true},
    {spellId = 1160, enabled = false},
})
check("cooldown list unique size", #cds == 2)
check("exclude via cooldown list when filter on", Logic.isSpellExcluded(bl, cds, 6673, true) == true)
check("exclude ignores disabled cooldown entry", Logic.isSpellExcluded(bl, cds, 1160, true) == false)
check("permanent blacklist hits even if cooldown filter off", Logic.isSpellExcluded(bl, cds, 7, false) == true)
check("cooldown list ignored when filter off", Logic.isSpellExcluded({}, cds, 6673, false) == false)
check("cooldown list active when filter on", Logic.isSpellExcluded({}, cds, 6673, true) == true)

-- Legacy DBs predate the permanent/cooldown split: back then `entries` WAS the
-- cooldown list and the master switch controlled it. Adopting it as-is would
-- irreversibly make spells the user had switched off permanently excluded.
local legacyBl = {
    size = 64,
    mappings = {},
    overrides = {},
    blacklist = {
        enabled = false,
        entries = {{spellId = 6673, enabled = true}},
    },
}
Logic.sanitizeSettings(legacyBl, baseConfig())
check("legacy blacklist list moves to cooldowns", #legacyBl.blacklist.cooldowns == 1
    and legacyBl.blacklist.cooldowns[1].spellId == 6673)
check("legacy move empties the permanent list", #legacyBl.blacklist.entries == 0)
-- The move is keyed on `cooldowns == nil`, so a second pass must not swallow
-- entries the user has since added to the permanent list.
legacyBl.blacklist.entries = {{spellId = 1160, enabled = true}}
Logic.sanitizeSettings(legacyBl, baseConfig())
check("second sanitize keeps the permanent list", #legacyBl.blacklist.entries == 1
    and legacyBl.blacklist.entries[1].spellId == 1160)
check("second sanitize keeps the cooldown list", #legacyBl.blacklist.cooldowns == 1)
--------------------------------------------------------------------------------
-- pickRecommendation
--
-- The invariant every case below is protecting: SimC only wins when the host
-- could prove BOTH the gates and that the spell is castable right now. Anything
-- unknown must fall back to Blizzard's Assisted Combat pick.
--------------------------------------------------------------------------------

local READY = "ready"

-- castability stub: everything ready unless listed.
local function castabilityFrom(overrides)
    return function(spellId)
        return (overrides and overrides[spellId]) or READY
    end
end

-- gate stub: verdict per spell id, default "pass".
local function gatesFrom(verdicts)
    return function(entry)
        local id = type(entry) == "table" and entry.id or entry
        return (verdicts and verdicts[id]) or "pass"
    end
end

local simcEntries = {
    {id = 100},
    {id = 200},
    {id = 300},
}

local id, reason

-- Assist-only mode never consults SimC.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = false,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("assist mode keeps AC primary", id == 50 and reason == "ac_primary")

-- SimC entry in the pool, gates proven, castable -> it overrides AC.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("verified SimC entry overrides AC", id == 300 and reason == "simc_verified")

-- Unknown gates (delegated, unreadable buff, ...) must NOT override.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom({[300] = "unknown"}),
})
check("unknown gates defer to AC", id == 50 and reason == "ac_primary")

-- Failed gates must not override either.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom({[300] = "fail"}),
})
check("failed gates defer to AC", id == 50 and reason == "ac_primary")

-- Gates pass but the spell is not castable right now: no override.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom({[300] = "no_resource"}),
    gateVerdict = gatesFrom(),
})
check("resource-starved SimC entry defers to AC", id == 50 and reason == "ac_primary")

-- Unknown castability is not "ready", so it cannot win a SimC override.
id, reason = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom({[300] = "unknown"}),
    gateVerdict = gatesFrom(),
})
check("unknown castability blocks SimC override", id == 50 and reason == "ac_primary")

-- SimC priority order decides which verified entry wins.
id, reason = Logic.pickRecommendation(50, 60, {100, 300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("highest verified SimC entry wins", id == 100 and reason == "simc_verified")

-- ...and a blocked higher entry hands off to the next verified one.
id, reason = Logic.pickRecommendation(50, 60, {100, 300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom({[100] = "on_cd"}),
    gateVerdict = gatesFrom(),
})
check("blocked SimC head falls to next verified", id == 300 and reason == "simc_verified")

-- SimC agreeing with Blizzard reports the simpler reason.
id, reason = Logic.pickRecommendation(100, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("SimC agreeing with AC reports ac_primary", id == 100 and reason == "ac_primary")

-- SimC never invents a spell outside the live AC pool.
id, reason = Logic.pickRecommendation(nil, nil, {}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("no AC pool yields none", id == nil and reason == "none")

id, reason = Logic.pickRecommendation(50, 60, {}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom(),
    gateVerdict = gatesFrom(),
})
check("SimC entries outside the pool are skipped", id == 50 and reason == "ac_primary")

--------------------------------------------------------------------------------
-- Hard castability filter
--------------------------------------------------------------------------------

id, reason = Logic.pickRecommendation(50, 60, {70}, nil, {
    simcAssist = false,
    castability = castabilityFrom({[50] = "on_cd"}),
})
check("uncastable primary hands off to lookahead", id == 60 and reason == "ac_lookahead")

id, reason = Logic.pickRecommendation(50, 60, {70}, nil, {
    simcAssist = false,
    castability = castabilityFrom({[50] = "unusable", [60] = "out_of_range"}),
})
check("uncastable primary and lookahead fall to rotation", id == 70 and reason == "ac_candidate")

-- Resource starvation is transient and must never remove a spell.
id, reason = Logic.pickRecommendation(50, 60, {70}, nil, {
    simcAssist = false,
    castability = castabilityFrom({[50] = "no_resource"}),
})
check("resource starvation keeps the AC primary", id == 50 and reason == "ac_primary")

-- Everything unreadable: keep showing Blizzard's pick rather than blanking.
id, reason = Logic.pickRecommendation(50, 60, {70}, nil, {
    simcAssist = false,
    castability = castabilityFrom({[50] = "unknown", [60] = "unknown", [70] = "unknown"}),
})
check("unknown castability keeps the AC primary", id == 50 and reason == "ac_primary")

-- Everything provably uncastable: still show AC rather than an empty box.
id, reason = Logic.pickRecommendation(50, 60, {70}, nil, {
    simcAssist = false,
    castability = castabilityFrom({[50] = "on_cd", [60] = "on_cd", [70] = "on_cd"}),
})
check("all-blocked pool still shows AC primary", id == 50 and reason == "ac_primary")

--------------------------------------------------------------------------------
-- Blacklist, suppression and display ids
--------------------------------------------------------------------------------

id, reason = Logic.pickRecommendation(10, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = false,
    blacklistEntries = {{spellId = 10, enabled = true}},
    castability = castabilityFrom(),
})
check("permanent blacklist skips primary without cooldown filter", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickRecommendation(6673, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {},
    blacklistCooldowns = {{spellId = 6673, enabled = true}},
    castability = castabilityFrom(),
})
check("cooldown suppress list skips primary when filter on", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickRecommendation(6673, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = false,
    blacklistEntries = {},
    blacklistCooldowns = {{spellId = 6673, enabled = true}},
    castability = castabilityFrom(),
})
check("cooldown suppress ignored when filter off", id == 6673 and reason == "ac_primary")

id, reason = Logic.pickRecommendation(6673, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {},
    blacklistCooldowns = {{spellId = 6673, enabled = false}},
    castability = castabilityFrom(),
})
check("disabled cooldown entry keeps primary", id == 6673 and reason == "ac_primary")

id, reason = Logic.pickRecommendation(9001, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 9999, enabled = true}},
    displayOf = function(spellId)
        return spellId == 9001 and 9999 or spellId
    end,
    castability = castabilityFrom(),
})
check("blacklist matches the display id", id == 20 and reason == "ac_lookahead")

id, reason = Logic.pickRecommendation(9001, 20, {30}, nil, {
    simcAssist = false,
    blacklistEnabled = true,
    blacklistEntries = {{spellId = 8000, enabled = true}},
    displayOf = function(spellId)
        return (spellId == 8000 or spellId == 9001) and 9001 or spellId
    end,
    castability = castabilityFrom(),
})
check("blacklist entry resolves through displayOf", id == 20 and reason == "ac_lookahead")

-- The pool is keyed by display id, so a base id must not shadow a candidate
-- that merely happens to display as that base id.
local collapseDetail
id, reason, collapseDetail = Logic.pickRecommendation(400, 500, {600}, nil, {
    simcAssist = false,
    displayOf = function(spellId)
        if spellId == 400 then
            return 500
        end
        return spellId
    end,
    castability = castabilityFrom(),
    collectDetail = true,
})
check("primary and lookahead sharing a display id collapse",
    id == 500 and reason == "ac_primary" and collapseDetail.poolSize == 2)

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

local detail
id, reason, detail = Logic.pickRecommendation(50, 60, {300}, simcEntries, {
    simcAssist = true,
    castability = castabilityFrom({[300] = "on_cd"}),
    gateVerdict = gatesFrom(),
    collectDetail = true,
})
check("detail reports pool size", detail ~= nil and detail.poolSize == 3)
check("detail reports castable size", detail ~= nil and detail.castableSize == 2)
check("detail records the blocked entry", (function()
    if not detail then
        return false
    end
    for _, row in ipairs(detail.pool) do
        if row.id == 300 and row.castability == "on_cd" then
            return true
        end
    end
    return false
end)())
check("detail omitted unless requested", select(3, Logic.pickRecommendation(50, 60, {}, nil, {
    simcAssist = false,
    castability = castabilityFrom(),
})) == nil)

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

--------------------------------------------------------------------------------
-- Character + specialization profiles
--------------------------------------------------------------------------------

check("specKey builds CLASS_N", Logic.specKey("WARRIOR", 3) == "WARRIOR_3")
check("specKey rejects bad index", Logic.specKey("WARRIOR", 0) == nil)

local deepSrc = {a = {b = 1}}
local deepDst = Logic.deepCopy(deepSrc)
deepDst.a.b = 9
check("deepCopy independence", deepSrc.a.b == 1 and deepDst.a.b == 9)

local profileAccount = {
    size = 40,
    x = 1,
    y = 2,
    point = "CENTER",
    relativePoint = "CENTER",
    locked = true,
    showMarker = true,
    frameStrata = "HIGH",
    frameLevel = 50,
    simcAssist = true,
    mappings = {},
    procs = {entries = {{spellId = 100, colorIndex = 2, enabled = true}}},
    defense = {
        enabled = true,
        size = 48,
        x = 10,
        y = -10,
        point = "CENTER",
        relativePoint = "CENTER",
        locked = true,
        frameStrata = "HIGH",
        frameLevel = 40,
        entries = {{spellId = 200, colorIndex = 3, enabled = true}},
    },
    blacklist = {
        enabled = true,
        toggleKey = "F9",
        entries = {{spellId = 7, enabled = true}},
        cooldowns = {{spellId = 6673, enabled = true}},
    },
    charMappings = {
        ["Hero-Realm"] = {{spellId = 50, colorIndex = 2, markerIndex = 1, moveGlow = false}},
    },
}

Logic.migrateCharSpecProfiles(profileAccount, "Hero-Realm")
check("migrate sets schema version 3", profileAccount.profileSchemaVersion == 3)
check("migrate creates char profile", type(profileAccount.charProfiles["Hero-Realm"]) == "table")
check("migrate seed has mapping from charMappings",
    profileAccount.charProfiles["Hero-Realm"].seed.mappings[1]
        and profileAccount.charProfiles["Hero-Realm"].seed.mappings[1].spellId == 50)
check("migrate seed has account proc for current char",
    profileAccount.charProfiles["Hero-Realm"].seed.procs.entries[1]
        and profileAccount.charProfiles["Hero-Realm"].seed.procs.entries[1].spellId == 100)
check("migrate seed has cooldown exclude for current char",
    profileAccount.charProfiles["Hero-Realm"].seed.blacklist.cooldowns[1]
        and profileAccount.charProfiles["Hero-Realm"].seed.blacklist.cooldowns[1].spellId == 6673)
check("migrate placement keeps toggle key",
    profileAccount.charProfiles["Hero-Realm"].placement.blacklistToggleKey == "F9")

-- Other character must not inherit current account defense/proc lists.
profileAccount.charMappings["Other-Realm"] = {{spellId = 1, colorIndex = 2, markerIndex = 1}}
profileAccount.profileSchemaVersion = 2
profileAccount.charProfiles["Other-Realm"] = {
    placement = Logic.deepCopy(profileAccount.charProfiles["Hero-Realm"].placement),
    seed = Logic.deepCopy(profileAccount.charProfiles["Hero-Realm"].seed),
    specs = {},
}
Logic.migrateCharSpecProfiles(profileAccount, "Hero-Realm")
check("v3 strips shared lists from other characters",
    #(profileAccount.charProfiles["Other-Realm"].seed.defense.entries or {}) == 0
        and #(profileAccount.charProfiles["Other-Realm"].seed.procs.entries or {}) == 0)
check("v3 keeps other character mappings",
    profileAccount.charProfiles["Other-Realm"].seed.mappings[1]
        and profileAccount.charProfiles["Other-Realm"].seed.mappings[1].spellId == 50)

local prof = Logic.ensureCharProfile(profileAccount, "Hero-Realm")
local arms = Logic.ensureSpecProfile(prof, "WARRIOR_1")
local fury = Logic.ensureSpecProfile(prof, "WARRIOR_2")
check("first visit clones seed mappings", arms.mappings[1] and arms.mappings[1].spellId == 50)
check("second spec also clones seed", fury.mappings[1] and fury.mappings[1].spellId == 50)
arms.mappings[1].spellId = 999
check("spec buckets diverge after edit", fury.mappings[1].spellId == 50 and arms.mappings[1].spellId == 999)

local live = {
    size = 99,
    defense = {enabled = false, entries = {}, size = 1, x = 0, y = 0},
    procs = {entries = {}},
    blacklist = {enabled = false, entries = {}, cooldowns = {}, toggleKey = nil},
    mappings = {},
    simcAssist = false,
}
Logic.applyCharPlacementToSettings(live, prof.placement)
Logic.applySpecToSettings(live, arms)
check("apply placement size from char profile", live.size == 40)
check("apply diverged mapping from arms", live.mappings[1] and live.mappings[1].spellId == 999)
check("arms keeps seed simcAssist", arms.simcAssist ~= false)

local before = profileAccount.charProfiles["Hero-Realm"].seed.mappings[1].spellId
Logic.migrateCharSpecProfiles(profileAccount, "Hero-Realm")
check("migrate is idempotent", profileAccount.charProfiles["Hero-Realm"].seed.mappings[1].spellId == before)

-- The save half of the bind/persist cycle. Every per-spec list has to survive a
-- capture -> apply round trip, and the captured bucket must not alias the live
-- settings: the stored profile would otherwise mutate with every UI edit.
local captureSource = {
    mappings = {{spellId = 11, colorIndex = 2, markerIndex = 1}},
    procs = {entries = {{spellId = 22, colorIndex = 3, enabled = true}}},
    defense = {enabled = false, entries = {{spellId = 33, colorIndex = 4, enabled = true}}},
    blacklist = {
        enabled = true,
        entries = {{spellId = 44, enabled = true}},
        cooldowns = {{spellId = 55, enabled = false}},
    },
    simcAssist = false,
}
local captured = Logic.captureSpecFromSettings(captureSource)
check("capture keeps every list", #captured.mappings == 1 and #captured.procs.entries == 1
    and #captured.defense.entries == 1 and #captured.blacklist.entries == 1
    and #captured.blacklist.cooldowns == 1)
check("capture keeps the disabled flags",
    captured.defense.enabled == false and captured.blacklist.enabled == true
        and captured.simcAssist == false)
captureSource.mappings[1].spellId = 999
captureSource.defense.entries[1].spellId = 999
check("capture is independent of the live settings",
    captured.mappings[1].spellId == 11 and captured.defense.entries[1].spellId == 33)

local roundTrip = Logic.applySpecToSettings({}, captured)
check("capture round-trips through apply",
    roundTrip.mappings[1].spellId == 11
        and roundTrip.procs.entries[1].spellId == 22
        and roundTrip.defense.entries[1].spellId == 33
        and roundTrip.defense.enabled == false
        and roundTrip.blacklist.cooldowns[1].spellId == 55
        and roundTrip.simcAssist == false)

check("capture of an empty settings root is the empty profile", (function()
    local empty = Logic.captureSpecFromSettings(nil)
    return #empty.mappings == 0 and #empty.procs.entries == 0
        and empty.defense.enabled == true and empty.simcAssist == true
end)())

-- The exclusion keybind lives on the character placement, so a profile without
-- one has to CLEAR the live key rather than leave the previous character's.
local keyed = {blacklist = {toggleKey = "F9"}}
Logic.applyCharPlacementToSettings(keyed, {})
check("placement without a toggle key clears it", keyed.blacklist.toggleKey == nil)
Logic.applyCharPlacementToSettings(keyed, {blacklistToggleKey = "SHIFT-F1"})
check("placement toggle key is applied", keyed.blacklist.toggleKey == "SHIFT-F1")

--------------------------------------------------------------------------------
-- Locale parity: a reason or command string that exists in one language and not
-- the other shows up as a raw key in the UI.
--------------------------------------------------------------------------------

local en = ShinkiliLocale.locales.en
local ko = ShinkiliLocale.locales.ko
local localeGaps = {}
for key in pairs(en) do
    if ko[key] == nil then
        localeGaps[#localeGaps + 1] = "ko:" .. key
    end
end
for key in pairs(ko) do
    if en[key] == nil then
        localeGaps[#localeGaps + 1] = "en:" .. key
    end
end
check("locale keys match across en/ko", #localeGaps == 0, table.concat(localeGaps, ", "))

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
