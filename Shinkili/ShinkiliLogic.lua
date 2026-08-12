-- Pure domain for Shinkili (no WoW API). TOC loads before Shinkili.lua; tests dofile this file.

ShinkiliLogic = ShinkiliLogic or {}
local Logic = ShinkiliLogic

function Logic.clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function Logic.trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end

function Logic.normalizeLocale(locale)
    local raw = tostring(locale or "en")
    if raw == "ko" or raw == "kr" or raw == "koKR" or raw:find("ko") then
        return "ko"
    end
    return "en"
end

local VALID_FRAME_STRATA = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

function Logic.sanitizeFrameStrata(strata, defaultStrata)
    if type(strata) == "string" and VALID_FRAME_STRATA[strata] then
        return strata
    end
    if type(defaultStrata) == "string" and VALID_FRAME_STRATA[defaultStrata] then
        return defaultStrata
    end
    return "FULLSCREEN_DIALOG"
end

function Logic.sanitizeFrameLevel(level, defaultLevel)
    local numeric = tonumber(level)
    if not numeric then
        numeric = tonumber(defaultLevel) or 100
    end
    return Logic.clamp(math.floor(numeric + 0.5), 1, 10000)
end

function Logic.parseInteger(text)
    local value = tonumber(text)
    if not value then
        return nil
    end
    return math.floor(value + 0.5)
end

function Logic.isColorUsedByOtherMapping(mappings, mappingIndex, colorIndex)
    for index, mapping in ipairs(mappings) do
        if index ~= mappingIndex and tonumber(mapping.colorIndex) == colorIndex then
            return true
        end
    end
    return false
end

function Logic.getSuggestedMarkerIndex(mappings, mappingIndex, markerPaletteSize)
    local counts = {}
    for index = 1, markerPaletteSize do
        counts[index] = 0
    end

    for index, mapping in ipairs(mappings) do
        if index ~= mappingIndex then
            local markerIndex = tonumber(mapping.markerIndex)
            if markerIndex and counts[markerIndex] ~= nil then
                counts[markerIndex] = counts[markerIndex] + 1
            end
        end
    end

    local bestIndex = 1
    local bestCount = counts[1]
    for markerIndex = 1, markerPaletteSize do
        if counts[markerIndex] < bestCount then
            bestIndex = markerIndex
            bestCount = counts[markerIndex]
        end
        if counts[markerIndex] == 0 then
            return markerIndex
        end
    end

    return bestIndex
end

function Logic.matchesSearch(spellId, spellName, searchText)
    local query = Logic.trim(searchText):lower()
    if query == "" then
        return true
    end

    local name = (spellName or ""):lower()
    if name:find(query, 1, true) then
        return true
    end

    return tostring(spellId):find(query, 1, true) ~= nil
end

function Logic.copyDefaultOverrides(defaultOverrides)
    local overrides = {}
    for stateKey, config in pairs(defaultOverrides) do
        overrides[stateKey] = {
            enabled = config.enabled,
            colorIndex = config.colorIndex,
        }
    end
    return overrides
end

--- KeySim needs real Show/Hide. Only show when cast is known-interruptible.
--- notInterruptibleAccessible: false when value is secret/unreadable (then always hide).
function Logic.shouldShowInterruptIndicator(isCasting, notInterruptible, notInterruptibleAccessible)
    if not isCasting then
        return false
    end
    if not notInterruptibleAccessible then
        return false
    end
    return notInterruptible == false
end

--- Layout for interrupt box anchored above the main indicator.
--- Returns width, height, gapAboveMain.
function Logic.interruptBoxLayout(mainSize)
    local size = Logic.clamp(tonumber(mainSize) or 64, 24, 300)
    local height = math.max(12, math.floor(size * 0.35 + 0.5))
    local gap = math.max(4, math.floor(size * 0.08 + 0.5))
    return size, height, gap
end

--- First free mapping color index from top of palette (2..colorPaletteSize). Index 1 is Unassigned.
function Logic.getFirstFreeColorIndex(mappings, mappingIndex, colorPaletteSize)
    if type(colorPaletteSize) ~= "number" or colorPaletteSize < 2 then
        return nil
    end
    for colorIndex = 2, colorPaletteSize do
        if not Logic.isColorUsedByOtherMapping(mappings, mappingIndex, colorIndex) then
            return colorIndex
        end
    end
    return nil
end

function Logic.normalizeRealmName(realm)
    if type(realm) ~= "string" then
        return ""
    end
    return (realm:gsub("%s+", ""))
end

--- Stable character key "Name-Realm" (spaces stripped from realm).
--- Returns nil when name or realm is missing so migration can defer until login.
function Logic.characterKey(name, realm)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local normalizedRealm = Logic.normalizeRealmName(realm)
    if normalizedRealm == "" then
        return nil
    end
    return name .. "-" .. normalizedRealm
end

--- "Name" prefix of a "Name-Realm" key, or nil.
function Logic.characterNameFromKey(characterKey)
    if type(characterKey) ~= "string" or characterKey == "" then
        return nil
    end
    local name = characterKey:match("^(.-)%-")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function mappingListHasEntries(mappings)
    if type(mappings) ~= "table" then
        return false
    end
    for _, mapping in ipairs(mappings) do
        if type(mapping) == "table" and tonumber(mapping.spellId) then
            return true
        end
    end
    return false
end

Logic.mappingListHasEntries = mappingListHasEntries

local function isCharMappingBucket(accountDb, list)
    if type(accountDb) ~= "table" or type(list) ~= "table" then
        return false
    end
    local charMappings = accountDb.charMappings
    if type(charMappings) ~= "table" then
        return false
    end
    for _, bucket in pairs(charMappings) do
        if bucket == list then
            return true
        end
    end
    return false
end

--- Move account-wide legacy root `mappings` into `charMappings[targetKey]`.
--- No-op when `settings.mappings` is already a per-character bucket (live bind).
--- Defers when no stable target key is known yet.
function Logic.migrateLegacyCharMappings(accountDb, currentCharacterKey, preferredOwnerKey)
    if type(accountDb) ~= "table" then
        return nil
    end

    accountDb.charMappings = type(accountDb.charMappings) == "table" and accountDb.charMappings or {}

    local root = accountDb.mappings
    if isCharMappingBucket(accountDb, root) then
        -- Live bind: root pointer is the active character list — leave it alone.
        return accountDb.charMappings
    end

    if mappingListHasEntries(root) then
        local targetKey = preferredOwnerKey
        if type(targetKey) ~= "string" or targetKey == "" then
            targetKey = accountDb.legacyMappingsCharacter
        end
        if type(targetKey) ~= "string" or targetKey == "" then
            targetKey = currentCharacterKey
        end

        if type(targetKey) ~= "string" or targetKey == "" then
            return accountDb.charMappings
        end

        local existing = accountDb.charMappings[targetKey]
        if not mappingListHasEntries(existing) then
            accountDb.charMappings[targetKey] = root
        end
        accountDb.mappings = nil
        accountDb.legacyMappingsCharacter = nil
    else
        if root ~= nil and not isCharMappingBucket(accountDb, root) then
            accountDb.mappings = nil
        end
        if type(accountDb.legacyMappingsCharacter) == "string" then
            accountDb.legacyMappingsCharacter = nil
        end
    end

    return accountDb.charMappings
end

--- If an unstable name-only bucket exists and the stable key is empty, move it.
function Logic.rehomeNameOnlyCharMappings(accountDb, characterKey)
    if type(accountDb) ~= "table" or type(characterKey) ~= "string" or characterKey == "" then
        return false
    end
    accountDb.charMappings = type(accountDb.charMappings) == "table" and accountDb.charMappings or {}
    local nameOnly = Logic.characterNameFromKey(characterKey)
    if not nameOnly or nameOnly == characterKey then
        return false
    end
    local orphan = accountDb.charMappings[nameOnly]
    if not mappingListHasEntries(orphan) then
        return false
    end
    if mappingListHasEntries(accountDb.charMappings[characterKey]) then
        return false
    end
    accountDb.charMappings[characterKey] = orphan
    accountDb.charMappings[nameOnly] = nil
    return true
end

--- Ensure charMappings[characterKey] is a mapping array; returns that array.
function Logic.ensureCharMappings(accountDb, characterKey)
    if type(accountDb) ~= "table" or type(characterKey) ~= "string" or characterKey == "" then
        return {}
    end
    accountDb.charMappings = type(accountDb.charMappings) == "table" and accountDb.charMappings or {}
    if type(accountDb.charMappings[characterKey]) ~= "table" then
        accountDb.charMappings[characterKey] = {}
    end
    return accountDb.charMappings[characterKey]
end

--------------------------------------------------------------------------------
-- Character + specialization profiles
--
-- Account-wide: locale, minimap, cast/channel overrides.
-- Per character: main/defense box placement, blacklist toggle key.
-- Per character+spec: mappings, procs, defense entries, exclusion lists, simcAssist.
-- Migration copies existing data into each character's seed so every spec starts
-- with the same non-destructive snapshot (lazy clone on first visit).
--------------------------------------------------------------------------------

function Logic.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = Logic.deepCopy(child)
    end
    return copy
end

function Logic.specKey(classFile, specIndex)
    if type(classFile) ~= "string" or classFile == "" then
        return nil
    end
    local index = tonumber(specIndex)
    if not index or index < 1 then
        return nil
    end
    return classFile .. "_" .. tostring(math.floor(index + 0.5))
end

local function emptySpecProfile()
    return {
        mappings = {},
        procs = {entries = {}},
        defense = {enabled = true, entries = {}},
        blacklist = {enabled = false, entries = {}, cooldowns = {}},
        simcAssist = true,
    }
end

function Logic.emptySpecProfile()
    return emptySpecProfile()
end

--- Snapshot of list data that varies by specialization.
function Logic.captureSpecFromSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local defense = type(settings.defense) == "table" and settings.defense or {}
    local procs = type(settings.procs) == "table" and settings.procs or {}
    local blacklist = type(settings.blacklist) == "table" and settings.blacklist or {}
    return {
        mappings = Logic.deepCopy(settings.mappings) or {},
        procs = {entries = Logic.deepCopy(procs.entries) or {}},
        defense = {
            enabled = defense.enabled ~= false,
            entries = Logic.deepCopy(defense.entries) or {},
        },
        blacklist = {
            enabled = blacklist.enabled == true,
            entries = Logic.deepCopy(blacklist.entries) or {},
            cooldowns = Logic.deepCopy(blacklist.cooldowns) or {},
        },
        simcAssist = settings.simcAssist ~= false,
    }
end

--- Snapshot of placement that is shared across a character's specs.
function Logic.captureCharPlacementFromSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local defense = type(settings.defense) == "table" and settings.defense or {}
    local blacklist = type(settings.blacklist) == "table" and settings.blacklist or {}
    return {
        size = settings.size,
        x = settings.x,
        y = settings.y,
        point = settings.point,
        relativePoint = settings.relativePoint,
        locked = settings.locked ~= false,
        showMarker = settings.showMarker ~= false,
        frameStrata = settings.frameStrata,
        frameLevel = settings.frameLevel,
        defense = {
            size = defense.size,
            x = defense.x,
            y = defense.y,
            point = defense.point,
            relativePoint = defense.relativePoint,
            locked = defense.locked ~= false,
            frameStrata = defense.frameStrata,
            frameLevel = defense.frameLevel,
        },
        blacklistToggleKey = type(blacklist.toggleKey) == "string" and blacklist.toggleKey or nil,
    }
end

function Logic.applySpecToSettings(settings, spec)
    if type(settings) ~= "table" or type(spec) ~= "table" then
        return settings
    end
    settings.mappings = Logic.deepCopy(spec.mappings) or {}
    settings.procs = type(settings.procs) == "table" and settings.procs or {}
    settings.procs.entries = Logic.deepCopy(spec.procs and spec.procs.entries) or {}
    settings.defense = type(settings.defense) == "table" and settings.defense or {}
    settings.defense.enabled = not (spec.defense and spec.defense.enabled == false)
    settings.defense.entries = Logic.deepCopy(spec.defense and spec.defense.entries) or {}
    settings.blacklist = type(settings.blacklist) == "table" and settings.blacklist or {}
    settings.blacklist.enabled = spec.blacklist and spec.blacklist.enabled == true
    settings.blacklist.entries = Logic.deepCopy(spec.blacklist and spec.blacklist.entries) or {}
    settings.blacklist.cooldowns = Logic.deepCopy(spec.blacklist and spec.blacklist.cooldowns) or {}
    settings.simcAssist = spec.simcAssist ~= false
    return settings
end

function Logic.applyCharPlacementToSettings(settings, placement)
    if type(settings) ~= "table" or type(placement) ~= "table" then
        return settings
    end
    if placement.size ~= nil then
        settings.size = placement.size
    end
    if placement.x ~= nil then
        settings.x = placement.x
    end
    if placement.y ~= nil then
        settings.y = placement.y
    end
    if placement.point ~= nil then
        settings.point = placement.point
    end
    if placement.relativePoint ~= nil then
        settings.relativePoint = placement.relativePoint
    end
    if placement.locked ~= nil then
        settings.locked = placement.locked ~= false
    end
    if placement.showMarker ~= nil then
        settings.showMarker = placement.showMarker ~= false
    end
    if placement.frameStrata ~= nil then
        settings.frameStrata = placement.frameStrata
    end
    if placement.frameLevel ~= nil then
        settings.frameLevel = placement.frameLevel
    end
    settings.defense = type(settings.defense) == "table" and settings.defense or {}
    local defPlace = type(placement.defense) == "table" and placement.defense or {}
    if defPlace.size ~= nil then
        settings.defense.size = defPlace.size
    end
    if defPlace.x ~= nil then
        settings.defense.x = defPlace.x
    end
    if defPlace.y ~= nil then
        settings.defense.y = defPlace.y
    end
    if defPlace.point ~= nil then
        settings.defense.point = defPlace.point
    end
    if defPlace.relativePoint ~= nil then
        settings.defense.relativePoint = defPlace.relativePoint
    end
    if defPlace.locked ~= nil then
        settings.defense.locked = defPlace.locked ~= false
    end
    if defPlace.frameStrata ~= nil then
        settings.defense.frameStrata = defPlace.frameStrata
    end
    if defPlace.frameLevel ~= nil then
        settings.defense.frameLevel = defPlace.frameLevel
    end
    settings.blacklist = type(settings.blacklist) == "table" and settings.blacklist or {}
    if placement.blacklistToggleKey == nil or placement.blacklistToggleKey == "" then
        settings.blacklist.toggleKey = nil
    else
        settings.blacklist.toggleKey = placement.blacklistToggleKey
    end
    return settings
end

local function seedFromAccountRoot(accountDb, mappings, includeSharedLists)
    accountDb = type(accountDb) == "table" and accountDb or {}
    local defense = type(accountDb.defense) == "table" and accountDb.defense or {}
    local procs = type(accountDb.procs) == "table" and accountDb.procs or {}
    local blacklist = type(accountDb.blacklist) == "table" and accountDb.blacklist or {}
    if includeSharedLists == false then
        return {
            mappings = Logic.deepCopy(mappings) or {},
            procs = {entries = {}},
            defense = {enabled = true, entries = {}},
            blacklist = {enabled = false, entries = {}, cooldowns = {}},
            simcAssist = true,
        }
    end
    return {
        mappings = Logic.deepCopy(mappings) or {},
        procs = {entries = Logic.deepCopy(procs.entries) or {}},
        defense = {
            enabled = defense.enabled ~= false,
            entries = Logic.deepCopy(defense.entries) or {},
        },
        blacklist = {
            enabled = blacklist.enabled == true,
            entries = Logic.deepCopy(blacklist.entries) or {},
            cooldowns = Logic.deepCopy(blacklist.cooldowns) or {},
        },
        simcAssist = accountDb.simcAssist ~= false,
    }
end

local function stripSharedListsFromSeed(seed, keepMappings)
    seed = type(seed) == "table" and seed or emptySpecProfile()
    local maps = keepMappings and (Logic.deepCopy(seed.mappings) or {}) or {}
    return {
        mappings = maps,
        procs = {entries = {}},
        defense = {enabled = true, entries = {}},
        blacklist = {enabled = false, entries = {}, cooldowns = {}},
        simcAssist = seed.simcAssist ~= false,
    }
end

--- One-time migration to charProfiles. Existing data seeds every future spec
--- of the *current* character; other characters keep mappings only (no shared
--- account-wide defense/proc/blacklist lists).
function Logic.migrateCharSpecProfiles(accountDb, currentCharacterKey)
    if type(accountDb) ~= "table" then
        return
    end
    local version = tonumber(accountDb.profileSchemaVersion) or 0

    accountDb.charProfiles = type(accountDb.charProfiles) == "table" and accountDb.charProfiles or {}
    local placement = Logic.captureCharPlacementFromSettings(accountDb)

    if version < 2 then
        local charKeys = {}
        if type(accountDb.charMappings) == "table" then
            for key in pairs(accountDb.charMappings) do
                if type(key) == "string" and key ~= "" then
                    charKeys[key] = true
                end
            end
        end
        if type(currentCharacterKey) == "string" and currentCharacterKey ~= "" then
            charKeys[currentCharacterKey] = true
        end

        if not next(charKeys) then
            accountDb._pendingProfileSeed = seedFromAccountRoot(
                accountDb,
                mappingListHasEntries(accountDb.mappings) and accountDb.mappings or {},
                true
            )
            accountDb._pendingPlacement = Logic.deepCopy(placement)
        else
            for charKey in pairs(charKeys) do
                if type(accountDb.charProfiles[charKey]) ~= "table" then
                    local maps = nil
                    if type(accountDb.charMappings) == "table" and mappingListHasEntries(accountDb.charMappings[charKey]) then
                        maps = accountDb.charMappings[charKey]
                    elseif charKey == currentCharacterKey and mappingListHasEntries(accountDb.mappings) then
                        maps = accountDb.mappings
                    end
                    local fullLists = charKey == currentCharacterKey
                    accountDb.charProfiles[charKey] = {
                        placement = Logic.deepCopy(placement),
                        seed = seedFromAccountRoot(accountDb, maps or {}, fullLists),
                        specs = {},
                    }
                end
            end
        end
        version = 2
        accountDb.profileSchemaVersion = 2
    end

    -- v3: earlier v2 seeded account-wide defense/procs onto every character.
    -- Only "not the current character" is stripped, so without a character key
    -- every profile looks foreign and the logged-in character's own lists would
    -- be wiped -- and the version bump would make it unrepeatable. Defer.
    if version < 3 and type(currentCharacterKey) == "string" and currentCharacterKey ~= "" then
        for charKey, profile in pairs(accountDb.charProfiles) do
            if type(charKey) == "string" and type(profile) == "table" and charKey ~= currentCharacterKey then
                local keepMaps = profile.seed and profile.seed.mappings
                profile.seed = stripSharedListsFromSeed(profile.seed, true)
                if keepMaps then
                    profile.seed.mappings = Logic.deepCopy(keepMaps)
                end
                if type(profile.specs) == "table" then
                    for specKey, spec in pairs(profile.specs) do
                        if type(spec) == "table" then
                            local maps = spec.mappings
                            profile.specs[specKey] = stripSharedListsFromSeed(spec, true)
                            if maps then
                                profile.specs[specKey].mappings = Logic.deepCopy(maps)
                            end
                        end
                    end
                end
            end
        end
        accountDb.profileSchemaVersion = 3
    end
end

function Logic.ensureCharProfile(accountDb, characterKey)
    if type(accountDb) ~= "table" or type(characterKey) ~= "string" or characterKey == "" then
        return nil
    end
    accountDb.charProfiles = type(accountDb.charProfiles) == "table" and accountDb.charProfiles or {}
    local profile = accountDb.charProfiles[characterKey]
    if type(profile) ~= "table" then
        local maps = nil
        if type(accountDb.charMappings) == "table" and mappingListHasEntries(accountDb.charMappings[characterKey]) then
            maps = accountDb.charMappings[characterKey]
        end
        local seed = accountDb._pendingProfileSeed
        if type(seed) ~= "table" then
            -- Do not copy another character's live defense/proc lists from root.
            seed = seedFromAccountRoot(accountDb, maps or {}, false)
        elseif maps then
            seed = Logic.deepCopy(seed)
            seed.mappings = Logic.deepCopy(maps)
        else
            seed = Logic.deepCopy(seed)
        end
        local placement = accountDb._pendingPlacement
        if type(placement) ~= "table" then
            placement = Logic.captureCharPlacementFromSettings(accountDb)
        else
            placement = Logic.deepCopy(placement)
        end
        profile = {
            placement = placement,
            seed = seed,
            specs = {},
        }
        accountDb.charProfiles[characterKey] = profile
        -- The pending seed exists to hand the pre-v2 account-root snapshot to the
        -- FIRST character whose key becomes known. Leaving it set makes every
        -- alt created afterwards inherit that character's defense/proc/blacklist
        -- lists, which is exactly what the v3 migration removes.
        accountDb._pendingProfileSeed = nil
        accountDb._pendingPlacement = nil
    end
    profile.specs = type(profile.specs) == "table" and profile.specs or {}
    if type(profile.seed) ~= "table" then
        profile.seed = emptySpecProfile()
    end
    if type(profile.placement) ~= "table" then
        profile.placement = Logic.captureCharPlacementFromSettings(accountDb)
    end
    return profile
end

--- Returns the spec bucket, cloning the character seed on first visit.
function Logic.ensureSpecProfile(charProfile, specKey)
    if type(charProfile) ~= "table" or type(specKey) ~= "string" or specKey == "" then
        return emptySpecProfile()
    end
    charProfile.specs = type(charProfile.specs) == "table" and charProfile.specs or {}
    if type(charProfile.specs[specKey]) ~= "table" then
        local seed = type(charProfile.seed) == "table" and charProfile.seed or emptySpecProfile()
        charProfile.specs[specKey] = Logic.deepCopy(seed)
    end
    local spec = charProfile.specs[specKey]
    if type(spec.mappings) ~= "table" then
        spec.mappings = {}
    end
    if type(spec.procs) ~= "table" then
        spec.procs = {entries = {}}
    end
    if type(spec.procs.entries) ~= "table" then
        spec.procs.entries = {}
    end
    if type(spec.defense) ~= "table" then
        spec.defense = {enabled = true, entries = {}}
    end
    if type(spec.defense.entries) ~= "table" then
        spec.defense.entries = {}
    end
    if type(spec.blacklist) ~= "table" then
        spec.blacklist = {enabled = false, entries = {}, cooldowns = {}}
    end
    if type(spec.blacklist.entries) ~= "table" then
        spec.blacklist.entries = {}
    end
    if type(spec.blacklist.cooldowns) ~= "table" then
        spec.blacklist.cooldowns = {}
    end
    if spec.simcAssist == nil then
        spec.simcAssist = true
    end
    return spec
end

--- Sanitize saved settings in place (mappings, overrides, defense/procs, locale, placement).
function Logic.sanitizeSettings(settings, config)
    settings.size = Logic.clamp(tonumber(settings.size) or config.sizeDefault, 24, 300)
    settings.x = Logic.clamp(math.floor((tonumber(settings.x) or config.xDefault or 0) + 0.5), -1000, 1000)
    settings.y = Logic.clamp(math.floor((tonumber(settings.y) or config.yDefault or 0) + 0.5), -1000, 1000)
    settings.point = type(settings.point) == "string" and settings.point or (config.pointDefault or "CENTER")
    settings.relativePoint = type(settings.relativePoint) == "string" and settings.relativePoint
        or (config.relativePointDefault or "CENTER")
    settings.locked = settings.locked ~= false
    settings.showMarker = settings.showMarker ~= false
    if settings.interruptEnabled == nil then
        settings.interruptEnabled = true
    else
        settings.interruptEnabled = settings.interruptEnabled ~= false
    end
    settings.overrides = type(settings.overrides) == "table" and settings.overrides or {}

    for stateKey, defaultConfig in pairs(config.defaultOverrides) do
        local overrideConfig = type(settings.overrides[stateKey]) == "table" and settings.overrides[stateKey] or {}
        overrideConfig.enabled = overrideConfig.enabled ~= false

        local colorIndex = tonumber(overrideConfig.colorIndex)
        if colorIndex then
            colorIndex = math.floor(colorIndex + 0.5)
        end
        if not colorIndex or colorIndex < 1 or colorIndex > config.reservedOverrideSize then
            colorIndex = defaultConfig.colorIndex
        end

        overrideConfig.colorIndex = colorIndex
        settings.overrides[stateKey] = overrideConfig
    end

    local migratedMappings = {}
    local usedSpell = {}
    local usedColor = {}

    local function appendMapping(rawMapping)
        if type(rawMapping) ~= "table" then
            return
        end

        local spellId = tonumber(rawMapping.spellId)
        if not spellId or spellId <= 0 then
            return
        end

        spellId = math.floor(spellId + 0.5)
        if usedSpell[spellId] then
            return
        end

        local colorIndex = tonumber(rawMapping.colorIndex)
        if colorIndex then
            colorIndex = math.floor(colorIndex + 0.5)
        end
        if not colorIndex or colorIndex < 2 or colorIndex > config.colorPaletteSize or usedColor[colorIndex] then
            colorIndex = nil
        end

        local markerIndex = tonumber(rawMapping.markerIndex)
        if markerIndex then
            markerIndex = math.floor(markerIndex + 0.5)
        end
        if not markerIndex or markerIndex < 1 or markerIndex > config.markerPaletteSize then
            markerIndex = nil
        end

        local mapping = {
            spellId = spellId,
            colorIndex = colorIndex,
            markerIndex = markerIndex,
            moveGlow = rawMapping.moveGlow == true,
        }

        table.insert(migratedMappings, mapping)
        usedSpell[spellId] = true
        if colorIndex then
            usedColor[colorIndex] = true
        end
    end

    if type(settings.mappings) == "table" then
        local mappingCount = math.max(#settings.mappings, config.legacyMappingSlots or 0)
        for index = 1, mappingCount do
            appendMapping(settings.mappings[index])
        end
    end

    if #migratedMappings == 0 and (type(settings.trackedSpells) == "table" or type(settings.spellColors) == "table") then
        local trackedSpells = settings.trackedSpells or {}
        local spellColors = settings.spellColors or {}
        for _, spellId in ipairs(trackedSpells) do
            appendMapping({
                spellId = spellId,
                colorIndex = spellColors[tostring(math.floor((tonumber(spellId) or 0) + 0.5))],
            })
        end
    end

    local markerInUse = {}
    for _, mapping in ipairs(migratedMappings) do
        if mapping.markerIndex and not markerInUse[mapping.markerIndex] then
            markerInUse[mapping.markerIndex] = true
        else
            mapping.markerIndex = nil
        end
    end

    for _, mapping in ipairs(migratedMappings) do
        if not mapping.markerIndex then
            local markerIndex = 1
            while markerInUse[markerIndex] and markerIndex < config.markerPaletteSize do
                markerIndex = markerIndex + 1
            end
            if markerInUse[markerIndex] then
                markerIndex = 1
            end
            mapping.markerIndex = markerIndex
            markerInUse[markerIndex] = true
        end
    end

    settings.mappings = migratedMappings
    settings.trackedSpells = nil
    settings.spellColors = nil
    settings.cooldownBox = nil

    settings.locale = Logic.normalizeLocale(settings.locale)

    settings.defense = type(settings.defense) == "table" and settings.defense or {}
    local defenseDefaults = config.defenseDefaults or {}
    settings.defense.size = Logic.clamp(
        tonumber(settings.defense.size) or defenseDefaults.size or 48,
        24,
        300
    )
    settings.defense.x = Logic.clamp(
        math.floor((tonumber(settings.defense.x) or defenseDefaults.x or 100) + 0.5),
        -1000,
        1000
    )
    settings.defense.y = Logic.clamp(
        math.floor((tonumber(settings.defense.y) or defenseDefaults.y or -120) + 0.5),
        -1000,
        1000
    )
    settings.defense.point = type(settings.defense.point) == "string" and settings.defense.point
        or (defenseDefaults.point or "CENTER")
    settings.defense.relativePoint = type(settings.defense.relativePoint) == "string" and settings.defense.relativePoint
        or (defenseDefaults.relativePoint or "CENTER")
    settings.defense.locked = settings.defense.locked ~= false
    settings.defense.enabled = settings.defense.enabled ~= false
    settings.defense.entries = Logic.sanitizePriorityEntries(
        settings.defense.entries,
        config.colorPaletteSize
    )

    settings.procs = type(settings.procs) == "table" and settings.procs or {}
    settings.procs.entries = Logic.sanitizePriorityEntries(
        settings.procs.entries,
        config.colorPaletteSize
    )

    local frameDefaults = config.frameDefaults or {}
    settings.frameStrata = Logic.sanitizeFrameStrata(settings.frameStrata, frameDefaults.frameStrata)
    settings.frameLevel = Logic.sanitizeFrameLevel(settings.frameLevel, frameDefaults.frameLevel)

    settings.defense.frameStrata = Logic.sanitizeFrameStrata(
        settings.defense.frameStrata,
        frameDefaults.defenseFrameStrata or frameDefaults.frameStrata
    )
    settings.defense.frameLevel = Logic.sanitizeFrameLevel(
        settings.defense.frameLevel,
        frameDefaults.defenseFrameLevel or ((frameDefaults.frameLevel or 200) - 10)
    )

    settings.blacklist = type(settings.blacklist) == "table" and settings.blacklist or {}
    settings.blacklist.enabled = settings.blacklist.enabled == true
    if type(settings.blacklist.toggleKey) ~= "string" or settings.blacklist.toggleKey == "" then
        settings.blacklist.toggleKey = nil
    else
        settings.blacklist.toggleKey = settings.blacklist.toggleKey
    end
    -- Legacy DBs predate the split: back then `entries` WAS the cooldown list and
    -- the master switch controlled it. `entries` is now applied permanently, so
    -- adopting an old list as-is would silently and irreversibly exclude spells
    -- the user had switched off. Move it to `cooldowns` once.
    if settings.blacklist.cooldowns == nil then
        settings.blacklist.cooldowns = settings.blacklist.entries or {}
        settings.blacklist.entries = {}
    end
    settings.blacklist.entries = Logic.sanitizeBlacklistEntries(settings.blacklist.entries)
    -- Cooldown suppress list: same shape as entries, gated by the master switch.
    settings.blacklist.cooldowns = Logic.sanitizeBlacklistEntries(settings.blacklist.cooldowns)
    settings.simcAssist = settings.simcAssist ~= false

    return settings
end

--- Priority list: array of {spellId, colorIndex, enabled}. Order = priority (1 highest).
function Logic.sanitizePriorityEntries(entries, colorPaletteSize)
    local migrated = {}
    local usedSpell = {}
    if type(entries) ~= "table" then
        return migrated
    end

    for index = 1, #entries do
        local raw = entries[index]
        if type(raw) == "table" then
            local spellId = tonumber(raw.spellId)
            if spellId and spellId > 0 then
                spellId = math.floor(spellId + 0.5)
                if not usedSpell[spellId] then
                    local colorIndex = tonumber(raw.colorIndex)
                    if colorIndex then
                        colorIndex = math.floor(colorIndex + 0.5)
                    end
                    if not colorIndex or colorIndex < 2 or colorIndex > (colorPaletteSize or 2) then
                        colorIndex = 2
                    end
                    table.insert(migrated, {
                        spellId = spellId,
                        colorIndex = colorIndex,
                        enabled = raw.enabled ~= false,
                    })
                    usedSpell[spellId] = true
                end
            end
        end
    end

    return migrated
end

function Logic.movePriorityEntry(entries, index, delta)
    if type(entries) ~= "table" then
        return false
    end
    local target = index + delta
    if index < 1 or index > #entries or target < 1 or target > #entries then
        return false
    end
    entries[index], entries[target] = entries[target], entries[index]
    return true
end

--- First enabled entry whose spellId is in activeSet (map spellId -> true).
function Logic.pickPriorityEntry(entries, activeSet)
    if type(entries) ~= "table" or type(activeSet) ~= "table" then
        return nil
    end
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false and entry.spellId and activeSet[entry.spellId] then
            return entry
        end
    end
    return nil
end

--- Blacklist list: {spellId, enabled}. Order preserved, unique spellId.
function Logic.sanitizeBlacklistEntries(entries)
    local migrated = {}
    local usedSpell = {}
    if type(entries) ~= "table" then
        return migrated
    end

    for index = 1, #entries do
        local raw = entries[index]
        if type(raw) == "table" then
            local spellId = tonumber(raw.spellId)
            if spellId and spellId > 0 then
                spellId = math.floor(spellId + 0.5)
                if not usedSpell[spellId] then
                    table.insert(migrated, {
                        spellId = spellId,
                        enabled = raw.enabled ~= false,
                    })
                    usedSpell[spellId] = true
                end
            end
        elseif tonumber(raw) and tonumber(raw) > 0 then
            local spellId = math.floor(tonumber(raw) + 0.5)
            if not usedSpell[spellId] then
                table.insert(migrated, {spellId = spellId, enabled = true})
                usedSpell[spellId] = true
            end
        end
    end

    return migrated
end

--- displaySpellId: candidate's display/override id
--- displayOf: optional (id)->display so book-base BL entries match AC override ids
function Logic.isSpellBlacklisted(entries, spellId, filterEnabled, displaySpellId, displayOf)
    if filterEnabled ~= true then
        return false
    end
    if type(entries) ~= "table" then
        return false
    end
    spellId = tonumber(spellId)
    displaySpellId = tonumber(displaySpellId)
    if not spellId and not displaySpellId then
        return false
    end
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false then
            local blocked = tonumber(entry.spellId)
            if blocked then
                if blocked == spellId or blocked == displaySpellId then
                    return true
                end
                if type(displayOf) == "function" then
                    local blockedDisp = tonumber(displayOf(blocked))
                    if blockedDisp and (blockedDisp == spellId or blockedDisp == displaySpellId) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Permanent blacklist always applies (enabled entries). Cooldown suppress list
--- only applies when cooldownFilterEnabled is true (UI: cooldown section switch).
function Logic.isSpellExcluded(entries, cooldownEntries, spellId, cooldownFilterEnabled, displaySpellId, displayOf)
    if Logic.isSpellBlacklisted(entries, spellId, true, displaySpellId, displayOf) then
        return true
    end
    return Logic.isSpellBlacklisted(
        cooldownEntries,
        spellId,
        cooldownFilterEnabled == true,
        displaySpellId,
        displayOf
    )
end

--- Confirmed-uncastable verdicts from the host's castability probe. Resource
--- starvation is deliberately absent: it refills every GCD, so excluding on it
--- would make the colour churn on every press.
local BLOCKING_CASTABILITY = {
    unusable = true,
    out_of_range = true,
    on_cd = true,
}

--- Single best pick for the colour box.
---
--- The goal is a SimC-faithful recommendation, but only where the client can
--- actually prove SimC's conditions hold. Everything the 12.0 secret-value rules
--- hide reads back as "unknown", and unknown never wins -- it defers to
--- Blizzard's live Assisted Combat pick. That is what keeps the result at least
--- as good as plain AC on specs whose APL conditions are unreadable, while
--- letting SimC take over on the ones where they are not.
---
--- Stages:
---   A) Live pool: AC primary -> highlight lookahead -> rotation list, normalised
---      to display ids, blacklisted entries removed.
---   B) Hard filter: drop everything the game confirms cannot be cast right now.
---   C) SimC override: walk the SimC priority order and take the first entry
---      that is in the pool, has every gate proven, and is castable right now.
---   D) Otherwise Blizzard's own order: primary, lookahead, first survivor.
---
--- options:
---   blacklistEntries (always excluded when entry enabled),
---   blacklistCooldowns + blacklistEnabled (cooldown suppress master switch),
---   simcAssist,
---   displayOf(id) -> displayId
---   castability(id) -> "ready"|"no_resource"|"unusable"|"out_of_range"|"on_cd"|"unknown"
---   gateVerdict(entry) -> "pass"|"fail"|"unknown"
---   collectDetail -> also return a diagnostic table (allocates; /sk why only)
---
--- Returns: spellId|nil, reason, detail|nil
--- reason: "simc_verified" | "ac_primary" | "ac_lookahead" | "ac_candidate" | "none"
function Logic.pickRecommendation(primarySpellId, lookaheadSpellId, rotationList, simcEntries, options)
    options = options or {}
    local blacklistEntries = options.blacklistEntries
    local blacklistCooldowns = options.blacklistCooldowns
    -- Master switch only for the cooldown-suppress list (permanent BL ignores it).
    local cooldownFilterEnabled = options.blacklistEnabled == true
    local simcAssist = options.simcAssist == true
    local displayOf = options.displayOf
    local castabilityOf = options.castability
    local gateVerdict = options.gateVerdict
    local detail = options.collectDetail == true and {pool = {}, simc = {}} or nil

    local primary = tonumber(primarySpellId)
    local lookahead = tonumber(lookaheadSpellId)

    local function displayId(spellId)
        spellId = tonumber(spellId)
        if not spellId then
            return nil
        end
        if type(displayOf) == "function" then
            local resolved = tonumber(displayOf(spellId))
            if resolved and resolved > 0 then
                return resolved
            end
        end
        return spellId
    end

    local function excluded(spellId)
        spellId = tonumber(spellId)
        if not spellId or spellId <= 0 then
            return true
        end
        local disp = displayId(spellId)
        return Logic.isSpellExcluded(
            blacklistEntries,
            blacklistCooldowns,
            spellId,
            cooldownFilterEnabled,
            disp,
            displayOf
        )
    end

    -- Stage A: ordered live pool, keyed only by display id so a base id can never
    -- shadow a different candidate that happens to display as it.
    local pool = {}
    local poolSet = {}
    local function addPool(spellId)
        spellId = tonumber(spellId)
        if not spellId or spellId <= 0 or excluded(spellId) then
            return
        end
        local disp = displayId(spellId)
        if not disp or poolSet[disp] then
            return
        end
        poolSet[disp] = true
        pool[#pool + 1] = disp
    end

    if primary and primary > 0 then
        addPool(primary)
    end
    if lookahead and lookahead > 0 and lookahead ~= primary then
        addPool(lookahead)
    end
    if type(rotationList) == "table" then
        for _, spellId in ipairs(rotationList) do
            addPool(spellId)
        end
    end

    if #pool == 0 then
        return nil, "none", detail
    end

    local primaryDisplay = primary and displayId(primary) or nil
    local lookaheadDisplay = lookahead and displayId(lookahead) or nil

    -- Stage B: hard castability filter.
    local castVerdict = {}
    local castable = {}
    local castableSet = {}
    for _, spellId in ipairs(pool) do
        local verdict = "unknown"
        if type(castabilityOf) == "function" then
            verdict = castabilityOf(spellId) or "unknown"
        end
        castVerdict[spellId] = verdict
        if not BLOCKING_CASTABILITY[verdict] then
            castable[#castable + 1] = spellId
            castableSet[spellId] = true
        end
        if detail then
            detail.pool[#detail.pool + 1] = {id = spellId, castability = verdict}
        end
    end

    -- Everything reads uncastable: far more likely our probes are blind than that
    -- the whole rotation is down, so keep showing Blizzard's opinion.
    local hardFilterEmpty = #castable == 0
    local candidates = hardFilterEmpty and pool or castable
    local candidateSet = hardFilterEmpty and poolSet or castableSet
    if detail then
        detail.hardFilterEmpty = hardFilterEmpty
        detail.poolSize = #pool
        detail.castableSize = #castable
    end

    -- Stage C: SimC may override, but only on a fully proven entry.
    if simcAssist and type(simcEntries) == "table" and #simcEntries > 0
        and type(gateVerdict) == "function" then
        for _, entry in ipairs(simcEntries) do
            local rawId = type(entry) == "table" and entry.id or entry
            local spellId = displayId(rawId)
            if spellId and candidateSet[spellId] then
                local gates = gateVerdict(entry)
                local cast = castVerdict[spellId]
                if detail then
                    detail.simc[#detail.simc + 1] = {
                        id = spellId,
                        gates = gates,
                        castability = cast,
                    }
                end
                if gates == "pass" and cast == "ready" then
                    if primaryDisplay and spellId == primaryDisplay then
                        -- SimC and Blizzard agree; report the simpler reason.
                        return spellId, "ac_primary", detail
                    end
                    return spellId, "simc_verified", detail
                end
            end
        end
    end

    -- Stage D: Blizzard's own order.
    if primaryDisplay and candidateSet[primaryDisplay] then
        return primaryDisplay, "ac_primary", detail
    end
    if lookaheadDisplay and candidateSet[lookaheadDisplay] then
        return lookaheadDisplay, "ac_lookahead", detail
    end

    -- Nobody vouches for this pick: neither Blizzard nor SimC named it. So at
    -- least prefer one the game says is castable right now over one we merely
    -- could not read.
    local first
    for _, spellId in ipairs(candidates) do
        if castVerdict[spellId] == "ready" then
            first = spellId
            break
        end
    end
    first = first or candidates[1]
    if not first then
        return nil, "none", detail
    end
    if primaryDisplay and first == primaryDisplay then
        return first, "ac_primary", detail
    end
    if lookaheadDisplay and first == lookaheadDisplay then
        return first, "ac_lookahead", detail
    end
    return first, "ac_candidate", detail
end

function Logic.getSimcSpecTable(simcData, specKey)
    if type(simcData) ~= "table" or type(simcData.specs) ~= "table" or not specKey then
        return nil
    end
    return simcData.specs[specKey]
end

function Logic.getSimcContextEntries(specTable, useAoe)
    if type(specTable) ~= "table" then
        return nil
    end
    if useAoe and type(specTable.aoe) == "table" and #specTable.aoe > 0 then
        return specTable.aoe
    end
    if type(specTable.st) == "table" and #specTable.st > 0 then
        return specTable.st
    end
    if type(specTable.aoe) == "table" and #specTable.aoe > 0 then
        return specTable.aoe
    end
    return nil
end

return Logic
