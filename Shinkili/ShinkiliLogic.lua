-- Pure domain helpers for Shinkili (no WoW API dependency).
-- Loaded before Shinkili.lua in-game; dofile()'d by unit tests.

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

--- Migrate and sanitize mapping list + placement fields on a settings table (mutates).
--- config fields:
---   legacyMappingSlots, colorPaletteSize, markerPaletteSize, reservedOverrideSize,
---   defaultOverrides (table), sizeDefault, xDefault, yDefault, pointDefault, relativePointDefault
function Logic.sanitizeSettings(settings, config)
    settings.size = Logic.clamp(tonumber(settings.size) or config.sizeDefault, 24, 300)
    settings.x = Logic.clamp(math.floor((tonumber(settings.x) or config.xDefault or 0) + 0.5), -1000, 1000)
    settings.y = Logic.clamp(math.floor((tonumber(settings.y) or config.yDefault or 0) + 0.5), -1000, 1000)
    settings.point = type(settings.point) == "string" and settings.point or (config.pointDefault or "CENTER")
    settings.relativePoint = type(settings.relativePoint) == "string" and settings.relativePoint
        or (config.relativePointDefault or "CENTER")
    settings.locked = settings.locked ~= false
    settings.showMarker = settings.showMarker ~= false
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

    if ShinkiliLocale and ShinkiliLocale.normalize then
        settings.locale = ShinkiliLocale.normalize(settings.locale)
    else
        local raw = tostring(settings.locale or "en")
        if raw == "ko" or raw == "kr" or raw:find("ko") then
            settings.locale = "ko"
        else
            settings.locale = "en"
        end
    end

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

return Logic
