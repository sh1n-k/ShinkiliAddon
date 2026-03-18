local addonName = ...

local LEGACY_MAPPING_SLOTS = 12
local VISIBLE_MAPPING_ROWS = 6
local MAPPING_ROW_HEIGHT = 32
local GCD_SPELL_ID = 61304

local defaults = {
    size = 64,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -120,
    locked = true,
    showMarker = true,
    overrides = {
        casting = {enabled = true, colorIndex = 1},
        channeling = {enabled = true, colorIndex = 2},
        empower = {enabled = true, colorIndex = 3},
    },
    mappings = {},
}

local COLOR_PALETTE = {
    {name = "Unassigned"},
    {name = "Green", rgba = {0.00, 1.00, 0.00, 1.00}},
    {name = "Yellow", rgba = {1.00, 1.00, 0.00, 1.00}},
    {name = "Orange", rgba = {1.00, 0.50, 0.00, 1.00}},
    {name = "Red", rgba = {1.00, 0.00, 0.00, 1.00}},
    {name = "Cyan", rgba = {0.00, 1.00, 1.00, 1.00}},
    {name = "Blue", rgba = {0.00, 0.45, 1.00, 1.00}},
    {name = "Purple", rgba = {0.70, 0.20, 1.00, 1.00}},
    {name = "White", rgba = {1.00, 1.00, 1.00, 1.00}},
    {name = "Pink", rgba = {1.00, 0.35, 0.70, 1.00}},
    {name = "Lime", rgba = {0.65, 1.00, 0.00, 1.00}},
    {name = "Magenta", rgba = {1.00, 0.00, 1.00, 1.00}},
    {name = "Turquoise", rgba = {0.20, 0.90, 0.75, 1.00}},
    {name = "Sky", rgba = {0.40, 0.75, 1.00, 1.00}},
    {name = "Lavender", rgba = {0.72, 0.60, 1.00, 1.00}},
    {name = "Coral", rgba = {1.00, 0.45, 0.35, 1.00}},
    {name = "Amber", rgba = {1.00, 0.75, 0.10, 1.00}},
    {name = "Mint", rgba = {0.55, 1.00, 0.75, 1.00}},
    {name = "Teal", rgba = {0.00, 0.65, 0.65, 1.00}},
    {name = "Navy", rgba = {0.10, 0.20, 0.75, 1.00}},
    {name = "Violet", rgba = {0.55, 0.15, 0.95, 1.00}},
    {name = "Rose", rgba = {0.95, 0.20, 0.45, 1.00}},
    {name = "Gold", rgba = {0.95, 0.80, 0.20, 1.00}},
    {name = "Spring", rgba = {0.30, 0.95, 0.35, 1.00}},
    {name = "Azure", rgba = {0.15, 0.55, 1.00, 1.00}},
    {name = "Plum", rgba = {0.60, 0.15, 0.60, 1.00}},
    {name = "Brown", rgba = {0.55, 0.30, 0.10, 1.00}},
}

local MARKER_PALETTE = {
    {name = "Ivory", rgba = {0.98, 0.96, 0.88, 1.00}},
    {name = "Jet", rgba = {0.08, 0.08, 0.08, 1.00}},
    {name = "Sky", rgba = {0.40, 0.75, 1.00, 1.00}},
    {name = "Amber", rgba = {1.00, 0.72, 0.10, 1.00}},
    {name = "Mint", rgba = {0.55, 1.00, 0.75, 1.00}},
    {name = "Rose", rgba = {0.95, 0.20, 0.45, 1.00}},
    {name = "Violet", rgba = {0.55, 0.15, 0.95, 1.00}},
    {name = "Slate", rgba = {0.45, 0.52, 0.65, 1.00}},
}

local RESERVED_OVERRIDE_PALETTE = {
    {name = "Frost Signal", rgba = {0.78, 0.84, 0.92, 1.00}},
    {name = "Channel Amber", rgba = {1.00, 0.83, 0.38, 1.00}},
    {name = "Empower Violet", rgba = {0.82, 0.66, 1.00, 1.00}},
    {name = "Alert White", rgba = {0.95, 0.95, 0.95, 1.00}},
    {name = "Slate Blue", rgba = {0.56, 0.67, 0.88, 1.00}},
    {name = "Soft Coral", rgba = {0.98, 0.72, 0.66, 1.00}},
}

local state = {
    currentSpellId = nil,
    currentCastState = nil,
    currentCastSpellId = nil,
    optionsOpen = false,
    availableSpells = {},
    searchText = "",
    editorSpellId = nil,
    editorColorIndex = nil,
    editorMoveGlow = false,
    previewSpellId = nil,
    previewColorIndex = nil,
    previewMarkerIndex = nil,
    previewMoveGlow = nil,
    recentCounter = 0,
    recentSpellRanks = {},
}

local addon = CreateFrame("Frame")
addon:RegisterEvent("ADDON_LOADED")

local square = CreateFrame("Frame", "ShinkiliIndicator", UIParent, "BackdropTemplate")
square:SetMovable(true)
square:SetClampedToScreen(true)
square:EnableMouse(false)
square:RegisterForDrag("LeftButton")
square:SetFrameStrata("FULLSCREEN_DIALOG")
square:SetFrameLevel(200)
square:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 2,
})
square:SetBackdropColor(0.2, 0.2, 0.2, 1)
square:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
square:Hide()

local spiral = CreateFrame("Cooldown", nil, square, "CooldownFrameTemplate")
spiral:SetAllPoints(square)
spiral:SetFrameLevel(square:GetFrameLevel() + 10)
if spiral.SetReverse then
    spiral:SetReverse(false)
end
if spiral.SetDrawEdge then
    spiral:SetDrawEdge(false)
end
if spiral.SetDrawBling then
    spiral:SetDrawBling(false)
end
if spiral.SetHideCountdownNumbers then
    spiral:SetHideCountdownNumbers(true)
end
spiral:Hide()

local moveGlowOuter = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
moveGlowOuter:SetPoint("CENTER", square, "CENTER", 0, 0)
moveGlowOuter:SetFrameStrata(square:GetFrameStrata())
moveGlowOuter:SetFrameLevel(square:GetFrameLevel() - 3)
moveGlowOuter:SetBackdrop({
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 6,
})
moveGlowOuter:SetBackdropBorderColor(0.38, 1.00, 0.60, 0.10)
moveGlowOuter:Hide()

local moveGlowMid = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
moveGlowMid:SetPoint("CENTER", square, "CENTER", 0, 0)
moveGlowMid:SetFrameStrata(square:GetFrameStrata())
moveGlowMid:SetFrameLevel(square:GetFrameLevel() - 2)
moveGlowMid:SetBackdrop({
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 4,
})
moveGlowMid:SetBackdropBorderColor(0.38, 1.00, 0.60, 0.22)
moveGlowMid:Hide()

local moveGlowInner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
moveGlowInner:SetPoint("CENTER", square, "CENTER", 0, 0)
moveGlowInner:SetFrameStrata(square:GetFrameStrata())
moveGlowInner:SetFrameLevel(square:GetFrameLevel() - 1)
moveGlowInner:SetBackdrop({
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 2,
})
moveGlowInner:SetBackdropBorderColor(0.38, 1.00, 0.60, 0.48)
moveGlowInner:Hide()

local markerDot = CreateFrame("Frame", nil, square, "BackdropTemplate")
markerDot:SetSize(14, 14)
markerDot:SetPoint("TOPRIGHT", square, "TOPRIGHT", 2, 2)
markerDot:SetFrameLevel(square:GetFrameLevel() + 20)
markerDot:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
markerDot:SetBackdropColor(1, 1, 1, 1)
markerDot:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
markerDot:Hide()

local label = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("BOTTOM", square, "TOP", 0, 6)
label:SetText("PREVIEW")
label:SetTextColor(0.96, 0.94, 0.86, 1)
label:SetShadowOffset(1, -1)
label:SetShadowColor(0, 0, 0, 0.9)

local options
local currentSpellText
local searchInput
local sizeInput
local xInput
local yInput
local editorSpellDropdown
local editorColorDropdown
local editorActionButton
local editorPreviewButton
local editorMoveGlowCheck
local lockToggleButton
local markerToggleCheck
local castingOverrideCheck
local castingOverrideDropdown
local channelingOverrideCheck
local channelingOverrideDropdown
local empowerOverrideCheck
local empowerOverrideDropdown
local mappingScrollFrame
local emptyMappingsText
local mappingRows = {}
local controlId = 0
local updateEditorControls
local updateMappingRows
local syncPlacementControls
local updateCooldownSpiral

local function db()
    return ShinkiliDB
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end

local function getSpellNameSafe(spellId)
    if not spellId then
        return "None"
    end

    if C_Spell and C_Spell.GetSpellName then
        local spellName = C_Spell.GetSpellName(spellId)
        if spellName and spellName ~= "" then
            return spellName
        end
    end

    return "Spell " .. tostring(spellId)
end

local function getPaletteColor(colorIndex)
    local entry = COLOR_PALETTE[colorIndex]
    if entry and entry.rgba then
        return unpack(entry.rgba)
    end
    return 0.2, 0.2, 0.2, 1
end

local function getColorName(colorIndex)
    local entry = COLOR_PALETTE[colorIndex]
    return entry and entry.name or "Unknown"
end

local function getMarkerColor(markerIndex)
    local entry = MARKER_PALETTE[markerIndex]
    if entry and entry.rgba then
        return unpack(entry.rgba)
    end
    return 0.08, 0.08, 0.08, 1
end

local function getMarkerName(markerIndex)
    local entry = MARKER_PALETTE[markerIndex]
    return entry and entry.name or "Auto"
end

local function getReservedColor(colorIndex)
    local entry = RESERVED_OVERRIDE_PALETTE[colorIndex]
    if entry and entry.rgba then
        return unpack(entry.rgba)
    end
    return 0.78, 0.84, 0.92, 1.00
end

local function getReservedColorName(colorIndex)
    local entry = RESERVED_OVERRIDE_PALETTE[colorIndex]
    return entry and entry.name or "Reserved"
end

local function getOverrideConfig(stateKey)
    local settings = db()
    settings.overrides = type(settings.overrides) == "table" and settings.overrides or {}
    settings.overrides[stateKey] = type(settings.overrides[stateKey]) == "table" and settings.overrides[stateKey] or {}
    return settings.overrides[stateKey]
end

local function getOverrideEnabled(stateKey)
    return getOverrideConfig(stateKey).enabled ~= false
end

local function getOverrideColorIndex(stateKey)
    local colorIndex = tonumber(getOverrideConfig(stateKey).colorIndex)
    if colorIndex and colorIndex >= 1 and colorIndex <= #RESERVED_OVERRIDE_PALETTE then
        return colorIndex
    end

    return defaults.overrides[stateKey] and defaults.overrides[stateKey].colorIndex or 1
end

local function copyDefaultOverrides()
    local overrides = {}

    for stateKey, config in pairs(defaults.overrides) do
        overrides[stateKey] = {
            enabled = config.enabled,
            colorIndex = config.colorIndex,
        }
    end

    return overrides
end

local function rememberRecommendedSpell(spellId)
    if not spellId then
        return
    end

    state.recentCounter = state.recentCounter + 1
    state.recentSpellRanks[spellId] = state.recentCounter
end

local function refreshAvailableSpells()
    local seen = {}
    local available = {}

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
        local numLines = C_SpellBook.GetNumSpellBookSkillLines()
        for lineIndex = 1, numLines do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
            if skillLineInfo then
                local offset = skillLineInfo.itemIndexOffset or 0
                local numSlots = skillLineInfo.numSpellBookItems or 0
                for slotIndex = offset + 1, offset + numSlots do
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                    if itemInfo and itemInfo.itemType == Enum.SpellBookItemType.Spell and not itemInfo.isPassive and not itemInfo.isOffSpec then
                        local spellId = tonumber(itemInfo.spellID)
                        if spellId and spellId > 0 and not seen[spellId] then
                            table.insert(available, {
                                spellId = spellId,
                                name = getSpellNameSafe(spellId),
                            })
                            seen[spellId] = true
                        end
                    end
                end
            end
        end
    end

    state.availableSpells = available
end

local function findMappingIndexBySpell(spellId)
    if not spellId then
        return nil
    end

    for index, mapping in ipairs(db().mappings) do
        if mapping.spellId == spellId then
            return index
        end
    end

    return nil
end

local function getMappingBySpell(spellId)
    local index = findMappingIndexBySpell(spellId)
    if not index then
        return nil, nil
    end

    return db().mappings[index], index
end

local function getAssignedColorIndex(spellId)
    local mapping = getMappingBySpell(spellId)
    if not mapping then
        return nil
    end
    return mapping.colorIndex
end

local function getAssignedMarkerIndex(spellId)
    local mapping = getMappingBySpell(spellId)
    if not mapping then
        return nil
    end
    return mapping.markerIndex
end

local function getAssignedMoveGlowEnabled(spellId)
    local mapping = getMappingBySpell(spellId)
    if not mapping then
        return false
    end
    return mapping.moveGlow == true
end

local function isColorUsedByOtherMapping(mappingIndex, colorIndex)
    for index, mapping in ipairs(db().mappings) do
        if index ~= mappingIndex and tonumber(mapping.colorIndex) == colorIndex then
            return true
        end
    end
    return false
end

local function getSuggestedMarkerIndex(mappingIndex)
    local counts = {}

    for index = 1, #MARKER_PALETTE do
        counts[index] = 0
    end

    for index, mapping in ipairs(db().mappings) do
        if index ~= mappingIndex then
            local markerIndex = tonumber(mapping.markerIndex)
            if markerIndex and counts[markerIndex] ~= nil then
                counts[markerIndex] = counts[markerIndex] + 1
            end
        end
    end

    local bestIndex = 1
    local bestCount = counts[1]
    for markerIndex = 1, #MARKER_PALETTE do
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

local function matchesSearch(spellId)
    local query = trim(state.searchText):lower()
    if query == "" then
        return true
    end

    local spellName = getSpellNameSafe(spellId):lower()
    if spellName:find(query, 1, true) then
        return true
    end

    return tostring(spellId):find(query, 1, true) ~= nil
end

local function getSpellPriority(spellId)
    local priority = state.recentSpellRanks[spellId] or 0
    if state.currentSpellId and spellId == state.currentSpellId then
        priority = priority + 1000000
    end
    return priority
end

local function compareSpellInfos(left, right)
    local leftPriority = getSpellPriority(left.spellId)
    local rightPriority = getSpellPriority(right.spellId)
    if leftPriority ~= rightPriority then
        return leftPriority > rightPriority
    end
    if left.name == right.name then
        return left.spellId < right.spellId
    end
    return left.name < right.name
end

local function getFilteredAvailableSpells()
    local filtered = {}

    for _, spellInfo in ipairs(state.availableSpells) do
        if matchesSearch(spellInfo.spellId) then
            table.insert(filtered, spellInfo)
        end
    end

    table.sort(filtered, compareSpellInfos)
    return filtered
end

local function buildMappingEntries()
    local entries = {}

    for index, mapping in ipairs(db().mappings) do
        if mapping.spellId and matchesSearch(mapping.spellId) then
            table.insert(entries, {
                index = index,
                spellId = mapping.spellId,
                colorIndex = mapping.colorIndex,
                markerIndex = mapping.markerIndex,
                moveGlow = mapping.moveGlow == true,
                name = getSpellNameSafe(mapping.spellId),
            })
        end
    end

    table.sort(entries, function(left, right)
        local leftPriority = getSpellPriority(left.spellId)
        local rightPriority = getSpellPriority(right.spellId)
        if leftPriority ~= rightPriority then
            return leftPriority > rightPriority
        end
        if left.name == right.name then
            return left.spellId < right.spellId
        end
        return left.name < right.name
    end)

    return entries
end

local function setPreview(spellId, colorIndex, markerIndex, moveGlow)
    if not spellId or not colorIndex then
        state.previewSpellId = nil
        state.previewColorIndex = nil
        state.previewMarkerIndex = nil
        state.previewMoveGlow = nil
        return
    end

    state.previewSpellId = spellId
    state.previewColorIndex = colorIndex
    state.previewMarkerIndex = markerIndex or getAssignedMarkerIndex(spellId)
    state.previewMoveGlow = moveGlow == true
end

local function togglePreview(spellId, colorIndex, markerIndex, moveGlow)
    if state.previewSpellId == spellId and state.previewColorIndex == colorIndex then
        setPreview(nil)
    else
        setPreview(spellId, colorIndex, markerIndex, moveGlow)
    end
end

local function getDisplayedSpellId()
    if state.previewSpellId then
        return state.previewSpellId
    end
    return state.currentSpellId
end

local function getDisplayedColorIndex()
    if state.previewColorIndex then
        return state.previewColorIndex
    end
    return getAssignedColorIndex(state.currentSpellId)
end

local function getDisplayedMarkerIndex()
    if state.previewMarkerIndex then
        return state.previewMarkerIndex
    end
    return getAssignedMarkerIndex(state.currentSpellId)
end

local function getDisplayedMoveGlowEnabled()
    if state.previewSpellId then
        return state.previewMoveGlow == true
    end
    return getAssignedMoveGlowEnabled(state.currentSpellId)
end

local function getCurrentRecommendedSpellId()
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable or not C_AssistedCombat.GetNextCastSpell then
        return nil
    end
    if not C_AssistedCombat.IsAvailable() then
        return nil
    end
    return C_AssistedCombat.GetNextCastSpell()
end

local function getCurrentCastState()
    local hasEmpowerDurations = false
    if UnitEmpoweredStageDurations then
        local durations = {UnitEmpoweredStageDurations("player")}
        if #durations == 1 and type(durations[1]) == "table" and durations[1][1] ~= nil then
            durations = durations[1]
        end
        hasEmpowerDurations = #durations > 0
    end

    if UnitChannelInfo then
        local _, _, _, _, _, _, _, channelSpellId, isEmpowered = UnitChannelInfo("player")
        if channelSpellId and channelSpellId > 0 then
            if isEmpowered or hasEmpowerDurations then
                return "empower", channelSpellId
            end
            return "channeling", channelSpellId
        end
    end

    if UnitCastingInfo then
        local _, _, _, _, _, _, _, _, spellId = UnitCastingInfo("player")
        if spellId and spellId > 0 then
            if hasEmpowerDurations then
                return "empower", spellId
            end
            return "casting", spellId
        end
    end

    return nil, nil
end

local function getSpellCooldownInfo(spellId)
    if not spellId then
        return nil
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellId)
        if info then
            return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
        end
    end

    if GetSpellCooldown then
        local startTime, duration, enabled, modRate = GetSpellCooldown(spellId)
        return startTime or 0, duration or 0, enabled, modRate or 1
    end

    return nil
end

local function sanitizeSettings()
    local settings = db()
    settings.size = clamp(tonumber(settings.size) or defaults.size, 24, 300)
    settings.x = clamp(math.floor((tonumber(settings.x) or defaults.x) + 0.5), -1000, 1000)
    settings.y = clamp(math.floor((tonumber(settings.y) or defaults.y) + 0.5), -1000, 1000)
    settings.point = type(settings.point) == "string" and settings.point or defaults.point
    settings.relativePoint = type(settings.relativePoint) == "string" and settings.relativePoint or defaults.relativePoint
    settings.locked = settings.locked ~= false
    settings.showMarker = settings.showMarker ~= false
    settings.overrides = type(settings.overrides) == "table" and settings.overrides or {}

    for stateKey, defaultConfig in pairs(defaults.overrides) do
        local overrideConfig = type(settings.overrides[stateKey]) == "table" and settings.overrides[stateKey] or {}
        overrideConfig.enabled = overrideConfig.enabled ~= false

        local colorIndex = tonumber(overrideConfig.colorIndex)
        if colorIndex then
            colorIndex = math.floor(colorIndex + 0.5)
        end
        if not colorIndex or colorIndex < 1 or colorIndex > #RESERVED_OVERRIDE_PALETTE then
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
        if not colorIndex or colorIndex < 2 or colorIndex > #COLOR_PALETTE or usedColor[colorIndex] then
            colorIndex = nil
        end

        local markerIndex = tonumber(rawMapping.markerIndex)
        if markerIndex then
            markerIndex = math.floor(markerIndex + 0.5)
        end
        if not markerIndex or markerIndex < 1 or markerIndex > #MARKER_PALETTE then
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
        local mappingCount = math.max(#settings.mappings, LEGACY_MAPPING_SLOTS)
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
            while markerInUse[markerIndex] and markerIndex < #MARKER_PALETTE do
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
end

local function applyPosition()
    local settings = db()
    square:ClearAllPoints()
    square:SetPoint(settings.point, UIParent, settings.relativePoint, settings.x, settings.y)
end

local function applySize()
    square:SetSize(db().size, db().size)
    moveGlowOuter:SetSize(db().size + 20, db().size + 20)
    moveGlowMid:SetSize(db().size + 12, db().size + 12)
    moveGlowInner:SetSize(db().size + 6, db().size + 6)
end

function syncPlacementControls()
    if not sizeInput or not xInput or not yInput then
        return
    end

    sizeInput:SetText(tostring(db().size))
    xInput:SetText(tostring(db().x))
    yInput:SetText(tostring(db().y))
end

local function syncEditorSelection()
    local mapping = getMappingBySpell(state.editorSpellId)
    if mapping then
        state.editorColorIndex = mapping.colorIndex
        state.editorMoveGlow = mapping.moveGlow == true
        return
    end

    if state.editorColorIndex and isColorUsedByOtherMapping(nil, state.editorColorIndex) then
        state.editorColorIndex = nil
    end

    state.editorMoveGlow = false
end

local function updateCurrentSpellText()
    if not currentSpellText then
        return
    end

    local lines = {}

    if state.currentSpellId then
        table.insert(lines, "Current recommendation: " .. getSpellNameSafe(state.currentSpellId))
    else
        table.insert(lines, "Current recommendation: None")
    end

    if state.previewSpellId and state.previewColorIndex then
        local markerName = state.previewMarkerIndex and getMarkerName(state.previewMarkerIndex) or "Auto"
        local previewLine = "Preview: " .. getSpellNameSafe(state.previewSpellId) .. " / " .. getColorName(state.previewColorIndex) .. " + " .. markerName .. " dot"
        if state.previewMoveGlow then
            previewLine = previewLine .. " / Move Glow"
        end
        table.insert(lines, previewLine)
    end

    currentSpellText:SetText(table.concat(lines, "\n"))
end

local function getActiveOverrideColorIndex(displayedSpellId)
    if state.previewSpellId then
        return nil
    end

    if displayedSpellId == nil or displayedSpellId ~= state.currentCastSpellId then
        return nil
    end

    if not state.currentCastState or not getOverrideEnabled(state.currentCastState) then
        return nil
    end

    return getOverrideColorIndex(state.currentCastState)
end

function updateCooldownSpiral()
    local displayedSpellId = getDisplayedSpellId()
    if not displayedSpellId then
        spiral:Hide()
        spiral:SetCooldown(0, 0, 1)
        return
    end

    local startTime, duration, enabled, modRate = getSpellCooldownInfo(GCD_SPELL_ID)
    if not startTime or not duration or enabled == false or enabled == 0 or duration <= 0 then
        spiral:Hide()
        spiral:SetCooldown(0, 0, 1)
        return
    end

    spiral:SetCooldown(startTime, duration, modRate or 1)
    spiral:Show()
end

local function refreshVisibility()
    local settings = db()
    local displayedSpellId = getDisplayedSpellId()
    local displayedColorIndex = getDisplayedColorIndex()
    local displayedMarkerIndex = getDisplayedMarkerIndex()
    local displayedMoveGlow = getDisplayedMoveGlowEnabled()
    local overrideColorIndex = getActiveOverrideColorIndex(displayedSpellId)
    local optionsPreview = state.optionsOpen
    local unlockedPreview = not settings.locked
    local showSquare = displayedSpellId ~= nil or optionsPreview or unlockedPreview

    if showSquare then
        square:Show()
    else
        square:Hide()
    end

    if displayedSpellId and displayedColorIndex ~= nil then
        if overrideColorIndex then
            square:SetBackdropColor(getReservedColor(overrideColorIndex))
        else
            square:SetBackdropColor(getPaletteColor(displayedColorIndex))
        end
        square:SetAlpha(1)
        if settings.showMarker then
            markerDot:SetBackdropColor(getMarkerColor(displayedMarkerIndex))
            markerDot:Show()
        else
            markerDot:Hide()
        end
        if state.previewSpellId then
            label:SetText("Preview: " .. getSpellNameSafe(displayedSpellId))
        else
            label:SetText(getSpellNameSafe(displayedSpellId))
        end
    elseif displayedSpellId then
        square:SetBackdropColor(0.2, 0.2, 0.2, 1)
        square:SetAlpha(1)
        markerDot:Hide()
        label:SetText("Unassigned: " .. getSpellNameSafe(displayedSpellId))
    elseif optionsPreview then
        square:SetBackdropColor(getPaletteColor(2))
        square:SetAlpha(1)
        if settings.showMarker then
            markerDot:SetBackdropColor(getMarkerColor(1))
            markerDot:Show()
        else
            markerDot:Hide()
        end
        if state.currentSpellId then
            label:SetText("Preview: " .. getSpellNameSafe(state.currentSpellId))
        else
            label:SetText("PREVIEW")
        end
    else
        square:SetBackdropColor(0.25, 0.25, 0.25, 0.45)
        square:SetAlpha(unlockedPreview and 1 or 0)
        markerDot:Hide()
        label:SetText("MOVE")
    end

    if showSquare and displayedSpellId and displayedMoveGlow then
        moveGlowOuter:Show()
        moveGlowMid:Show()
        moveGlowInner:Show()
    else
        moveGlowOuter:Hide()
        moveGlowMid:Hide()
        moveGlowInner:Hide()
    end

    square:EnableMouse(not settings.locked)
    updateCooldownSpiral()
    updateCurrentSpellText()
end

local function updateSpellState()
    local nextSpellId = getCurrentRecommendedSpellId()
    state.currentCastState, state.currentCastSpellId = getCurrentCastState()
    if nextSpellId and nextSpellId ~= state.currentSpellId then
        rememberRecommendedSpell(nextSpellId)
    end
    state.currentSpellId = nextSpellId
    refreshVisibility()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local settings = db()
    settings.point = "CENTER"
    settings.relativePoint = "CENTER"
    settings.x = math.floor((x or 0) + 0.5)
    settings.y = math.floor((y or 0) + 0.5)
    applyPosition()
    syncPlacementControls()
end

square:SetScript("OnDragStart", function(self)
    if not db().locked then
        self:StartMoving()
    end
end)
square:SetScript("OnDragStop", onDragStop)

local function getEditorMode()
    if state.editorSpellId and findMappingIndexBySpell(state.editorSpellId) then
        return "Save"
    end
    return "Add"
end

local function getEditorPreviewState()
    if not state.editorSpellId then
        return nil, nil, nil, false
    end

    local mapping, mappingIndex = getMappingBySpell(state.editorSpellId)
    local colorIndex = state.editorColorIndex
    local markerIndex = mapping and mapping.markerIndex or getSuggestedMarkerIndex(mappingIndex)

    if not colorIndex and mapping then
        colorIndex = mapping.colorIndex
    end

    if not colorIndex then
        return state.editorSpellId, nil, markerIndex, state.editorMoveGlow
    end

    return state.editorSpellId, colorIndex, markerIndex, state.editorMoveGlow
end

local function setEditorSpellId(spellId)
    state.editorSpellId = spellId
    syncEditorSelection()
end

local function initializeSpellDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local clearInfo = UIDropDownMenu_CreateInfo()
        clearInfo.text = "Select Spell"
        clearInfo.value = 0
        clearInfo.func = function()
            setEditorSpellId(nil)
            updateEditorControls()
            updateMappingRows()
            refreshVisibility()
        end
        clearInfo.checked = state.editorSpellId == nil
        UIDropDownMenu_AddButton(clearInfo, level)

        local filteredSpells = getFilteredAvailableSpells()
        if #filteredSpells == 0 then
            local emptyInfo = UIDropDownMenu_CreateInfo()
            emptyInfo.text = "No spells match the current search"
            emptyInfo.disabled = true
            UIDropDownMenu_AddButton(emptyInfo, level)
            return
        end

        for _, spellInfo in ipairs(filteredSpells) do
            local info = UIDropDownMenu_CreateInfo()
            local text = spellInfo.name
            if spellInfo.spellId == state.currentSpellId then
                text = text .. " |cff88ff88(Now)|r"
            elseif (state.recentSpellRanks[spellInfo.spellId] or 0) > 0 then
                text = text .. " |cffd6c16b(Recent)|r"
            end

            info.text = text
            info.value = spellInfo.spellId
            info.func = function()
                setEditorSpellId(spellInfo.spellId)
                updateEditorControls()
                updateMappingRows()
                refreshVisibility()
            end
            info.checked = state.editorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function initializeColorDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local mappingIndex = findMappingIndexBySpell(state.editorSpellId)

        local clearInfo = UIDropDownMenu_CreateInfo()
        clearInfo.text = "Unassigned"
        clearInfo.value = 1
        clearInfo.func = function()
            state.editorColorIndex = nil
            updateEditorControls()
            refreshVisibility()
        end
        clearInfo.checked = state.editorColorIndex == nil
        clearInfo.disabled = state.editorSpellId == nil
        UIDropDownMenu_AddButton(clearInfo, level)

        for colorIndex = 2, #COLOR_PALETTE do
            local info = UIDropDownMenu_CreateInfo()
            info.text = getColorName(colorIndex)
            info.value = colorIndex
            info.func = function()
                state.editorColorIndex = colorIndex
                updateEditorControls()
                refreshVisibility()
            end
            info.checked = state.editorColorIndex == colorIndex
            info.disabled = state.editorSpellId == nil or isColorUsedByOtherMapping(mappingIndex, colorIndex)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function initializeOverrideDropdown(dropdown, stateKey)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        for colorIndex = 1, #RESERVED_OVERRIDE_PALETTE do
            local info = UIDropDownMenu_CreateInfo()
            info.text = getReservedColorName(colorIndex)
            info.value = colorIndex
            info.func = function()
                local overrideConfig = getOverrideConfig(stateKey)
                overrideConfig.colorIndex = colorIndex
                updateEditorControls()
                refreshVisibility()
            end
            info.checked = getOverrideColorIndex(stateKey) == colorIndex
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function createSavedMappingRow(parent, rowIndex)
    local row = CreateFrame("Frame", addonName .. "SavedRow" .. rowIndex, parent)
    row:SetSize(700, MAPPING_ROW_HEIGHT)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    if rowIndex % 2 == 0 then
        row.background:SetColorTexture(1, 1, 1, 0.06)
    else
        row.background:SetColorTexture(1, 1, 1, 0.12)
    end

    row.markerSwatch = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.markerSwatch:SetSize(10, 10)
    row.markerSwatch:SetPoint("LEFT", 8, 0)
    row.markerSwatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    row.markerSwatch:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)

    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.spellText:SetPoint("LEFT", row.markerSwatch, "RIGHT", 12, 0)
    row.spellText:SetWidth(278)
    row.spellText:SetJustifyH("LEFT")
    row.spellText:SetWordWrap(false)
    row.spellText:SetTextColor(0.96, 0.94, 0.86, 1)
    row.spellText:SetShadowOffset(1, -1)
    row.spellText:SetShadowColor(0, 0, 0, 0.85)
    row.spellText:SetText("Spell")

    row.colorSwatch = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.colorSwatch:SetSize(14, 14)
    row.colorSwatch:SetPoint("LEFT", row.spellText, "RIGHT", 12, 0)
    row.colorSwatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    row.colorSwatch:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)

    row.colorText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.colorText:SetPoint("LEFT", row.colorSwatch, "RIGHT", 8, 0)
    row.colorText:SetWidth(86)
    row.colorText:SetJustifyH("LEFT")
    row.colorText:SetWordWrap(false)
    row.colorText:SetTextColor(0.92, 0.92, 0.92, 1)
    row.colorText:SetShadowOffset(1, -1)
    row.colorText:SetShadowColor(0, 0, 0, 0.75)
    row.colorText:SetText("Color")

    row.glowCheck = CreateFrame("CheckButton", addonName .. "SavedRowGlow" .. rowIndex, row, "UICheckButtonTemplate")
    row.glowCheck:SetSize(24, 24)
    row.glowCheck:SetPoint("LEFT", row.colorText, "RIGHT", 46, 0)
    row.glowCheck.text:SetText("")

    row.previewButton = CreateFrame("Button", addonName .. "SavedRowShow" .. rowIndex, row, "GameMenuButtonTemplate")
    row.previewButton:SetSize(68, 20)
    row.previewButton:SetPoint("RIGHT", -78, 0)
    row.previewButton:SetText("Show")

    row.deleteButton = CreateFrame("Button", addonName .. "SavedRowDelete" .. rowIndex, row, "GameMenuButtonTemplate")
    row.deleteButton:SetSize(68, 20)
    row.deleteButton:SetPoint("RIGHT", -6, 0)
    row.deleteButton:SetText("Delete")

    return row
end

function updateEditorControls()
    if not options then
        return
    end

    local editorMapping = getMappingBySpell(state.editorSpellId)
    local previewSpellId, previewColorIndex = getEditorPreviewState()

    UIDropDownMenu_SetSelectedValue(editorSpellDropdown, state.editorSpellId or 0)
    UIDropDownMenu_SetText(editorSpellDropdown, state.editorSpellId and getSpellNameSafe(state.editorSpellId) or "Select Spell")

    UIDropDownMenu_SetSelectedValue(editorColorDropdown, state.editorColorIndex or 1)
    UIDropDownMenu_SetText(editorColorDropdown, getColorName(state.editorColorIndex or 1))

    editorActionButton:SetText(getEditorMode())
    editorActionButton:SetEnabled(state.editorSpellId ~= nil and state.editorColorIndex ~= nil)

    editorPreviewButton:SetEnabled(previewSpellId ~= nil and previewColorIndex ~= nil)
    if previewSpellId and previewColorIndex and state.previewSpellId == previewSpellId and state.previewColorIndex == previewColorIndex then
        editorPreviewButton:SetText("Hide")
    else
        editorPreviewButton:SetText("Show")
    end

    if editorMapping and not state.editorColorIndex then
        UIDropDownMenu_SetText(editorColorDropdown, "Unassigned")
    end

    if editorMoveGlowCheck then
        editorMoveGlowCheck:SetChecked(state.editorMoveGlow == true)
        editorMoveGlowCheck:SetEnabled(state.editorSpellId ~= nil)
        if editorMoveGlowCheck.text and editorMoveGlowCheck.text.SetTextColor then
            if state.editorSpellId then
                editorMoveGlowCheck.text:SetTextColor(1.00, 0.82, 0.00)
            else
                editorMoveGlowCheck.text:SetTextColor(0.55, 0.55, 0.55)
            end
        end
    end

    if lockToggleButton then
        if db().locked then
            lockToggleButton:SetText("Unlock")
        else
            lockToggleButton:SetText("Lock")
        end
    end

    if markerToggleCheck then
        markerToggleCheck:SetChecked(db().showMarker)
    end

    if castingOverrideCheck then
        castingOverrideCheck:SetChecked(getOverrideEnabled("casting"))
    end
    if channelingOverrideCheck then
        channelingOverrideCheck:SetChecked(getOverrideEnabled("channeling"))
    end
    if empowerOverrideCheck then
        empowerOverrideCheck:SetChecked(getOverrideEnabled("empower"))
    end

    if castingOverrideDropdown then
        UIDropDownMenu_SetSelectedValue(castingOverrideDropdown, getOverrideColorIndex("casting"))
        UIDropDownMenu_SetText(castingOverrideDropdown, getReservedColorName(getOverrideColorIndex("casting")))
    end
    if channelingOverrideDropdown then
        UIDropDownMenu_SetSelectedValue(channelingOverrideDropdown, getOverrideColorIndex("channeling"))
        UIDropDownMenu_SetText(channelingOverrideDropdown, getReservedColorName(getOverrideColorIndex("channeling")))
    end
    if empowerOverrideDropdown then
        UIDropDownMenu_SetSelectedValue(empowerOverrideDropdown, getOverrideColorIndex("empower"))
        UIDropDownMenu_SetText(empowerOverrideDropdown, getReservedColorName(getOverrideColorIndex("empower")))
    end
end

local function deleteMappingByIndex(mappingIndex)
    local mapping = db().mappings[mappingIndex]
    if not mapping then
        return
    end

    if state.previewSpellId == mapping.spellId then
        setPreview(nil)
    end

    table.remove(db().mappings, mappingIndex)

    if state.editorSpellId == mapping.spellId then
        state.editorColorIndex = nil
    end

    sanitizeSettings()
    syncEditorSelection()
end

local function saveEditorMapping()
    if not state.editorSpellId or not state.editorColorIndex then
        return
    end

    local mapping, mappingIndex = getMappingBySpell(state.editorSpellId)
    if mapping then
        mapping.colorIndex = state.editorColorIndex
        mapping.moveGlow = state.editorMoveGlow == true
        if not mapping.markerIndex then
            mapping.markerIndex = getSuggestedMarkerIndex(mappingIndex)
        end
    else
        table.insert(db().mappings, {
            spellId = state.editorSpellId,
            colorIndex = state.editorColorIndex,
            markerIndex = getSuggestedMarkerIndex(nil),
            moveGlow = state.editorMoveGlow == true,
        })
    end

    if state.previewSpellId == state.editorSpellId then
        state.previewMoveGlow = state.editorMoveGlow == true
    end

    sanitizeSettings()
    syncEditorSelection()
end

function updateMappingRows()
    if not options then
        return
    end

    local entries = buildMappingEntries()
    local totalRows = #entries
    local offset = 0

    if mappingScrollFrame then
        FauxScrollFrame_Update(mappingScrollFrame, totalRows, VISIBLE_MAPPING_ROWS, MAPPING_ROW_HEIGHT)
        offset = FauxScrollFrame_GetOffset(mappingScrollFrame)
    end

    for rowIndex = 1, VISIBLE_MAPPING_ROWS do
        local row = mappingRows[rowIndex]
        local entry = entries[offset + rowIndex]

        if entry then
            row:Show()
            row.spellText:SetText(entry.name)
            row.colorText:SetText(entry.colorIndex and getColorName(entry.colorIndex) or "Unassigned")
            if entry.colorIndex then
                row.colorSwatch:SetBackdropColor(getPaletteColor(entry.colorIndex))
            else
                row.colorSwatch:SetBackdropColor(0.15, 0.15, 0.15, 1)
            end
            row.markerSwatch:SetBackdropColor(getMarkerColor(entry.markerIndex))
            row.glowCheck:SetChecked(entry.moveGlow == true)
            row.glowCheck:SetScript("OnClick", function(self)
                local mapping = db().mappings[entry.index]
                if not mapping then
                    return
                end
                mapping.moveGlow = self:GetChecked() and true or false
                if state.editorSpellId == entry.spellId then
                    state.editorMoveGlow = mapping.moveGlow == true
                end
                if state.previewSpellId == entry.spellId then
                    state.previewMoveGlow = mapping.moveGlow == true
                end
                updateEditorControls()
                updateMappingRows()
                refreshVisibility()
            end)

            row.previewButton:SetEnabled(entry.colorIndex ~= nil)
            if entry.colorIndex and state.previewSpellId == entry.spellId and state.previewColorIndex == entry.colorIndex then
                row.previewButton:SetText("Hide")
            else
                row.previewButton:SetText("Show")
            end

            row.previewButton:SetScript("OnClick", function()
                togglePreview(entry.spellId, entry.colorIndex, entry.markerIndex, entry.moveGlow)
                updateEditorControls()
                updateMappingRows()
                refreshVisibility()
            end)

            row.deleteButton:SetScript("OnClick", function()
                deleteMappingByIndex(entry.index)
                updateEditorControls()
                updateMappingRows()
                refreshVisibility()
            end)
        else
            row:Hide()
        end
    end

    if emptyMappingsText then
        if totalRows == 0 then
            emptyMappingsText:Show()
        else
            emptyMappingsText:Hide()
        end
    end
end

local function createSearchInput(parent, width)
    controlId = controlId + 1

    local holder = CreateFrame("Frame", addonName .. "SearchHolder" .. controlId, parent)
    holder:SetSize(width, 32)

    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText("Search")

    holder.input = CreateFrame("EditBox", addonName .. "SearchInput" .. controlId, holder, "InputBoxTemplate")
    holder.input:SetSize(width, 24)
    holder.input:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -3)
    holder.input:SetAutoFocus(false)
    holder.input:SetMaxLetters(40)

    holder.input:SetScript("OnTextChanged", function(self)
        state.searchText = self:GetText() or ""
        updateEditorControls()
        updateMappingRows()
    end)
    holder.input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return holder
end

local function createPlacementInput(parent, labelText, width, onApply)
    controlId = controlId + 1

    local holder = CreateFrame("Frame", addonName .. "PlacementInput" .. controlId, parent)
    holder:SetSize(width, 40)

    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText(labelText)

    holder.input = CreateFrame("EditBox", addonName .. "PlacementValue" .. controlId, holder, "InputBoxTemplate")
    holder.input:SetSize(width, 22)
    holder.input:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -4)
    holder.input:SetAutoFocus(false)
    holder.input:SetMaxLetters(8)

    local function apply()
        onApply(holder.input:GetText())
    end

    holder.input:SetScript("OnEnterPressed", function(self)
        apply()
        self:ClearFocus()
    end)
    holder.input:SetScript("OnEditFocusLost", apply)
    holder.input:SetScript("OnEscapePressed", function(self)
        syncPlacementControls()
        self:ClearFocus()
    end)

    return holder
end

local function createOverrideControl(parent, labelText, stateKey)
    controlId = controlId + 1

    local holder = CreateFrame("Frame", addonName .. "OverrideRow" .. controlId, parent)
    holder:SetSize(320, 28)

    holder.check = CreateFrame("CheckButton", addonName .. "OverrideCheck" .. controlId, holder, "UICheckButtonTemplate")
    holder.check:SetPoint("LEFT", 0, 0)
    holder.check.text:SetText(labelText)
    holder.check:SetScript("OnClick", function(self)
        local overrideConfig = getOverrideConfig(stateKey)
        overrideConfig.enabled = self:GetChecked() and true or false
        updateEditorControls()
        refreshVisibility()
    end)

    holder.dropdown = CreateFrame("Frame", addonName .. "OverrideDropdown" .. controlId, holder, "UIDropDownMenuTemplate")
    holder.dropdown:SetPoint("LEFT", holder, "LEFT", 145, -2)
    UIDropDownMenu_SetWidth(holder.dropdown, 120)
    UIDropDownMenu_JustifyText(holder.dropdown, "LEFT")
    initializeOverrideDropdown(holder.dropdown, stateKey)

    return holder
end

local function createOptionsWindow()
    options = CreateFrame("Frame", "ShinkiliOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    options:SetSize(760, 708)
    options:SetPoint("CENTER")
    options:SetMovable(true)
    options:SetClampedToScreen(true)
    options:EnableMouse(true)
    options:RegisterForDrag("LeftButton")
    options:SetScript("OnDragStart", options.StartMoving)
    options:SetScript("OnDragStop", options.StopMovingOrSizing)
    options:Hide()

    options.TitleText:SetText("Shinkili")

    local subtitle = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, -32)
    subtitle:SetWidth(720)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Search current-spec spells, assign one color, and manage only the mappings you actually saved.")

    currentSpellText = options:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentSpellText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    currentSpellText:SetWidth(720)
    currentSpellText:SetHeight(28)
    currentSpellText:SetJustifyH("LEFT")
    currentSpellText:SetWordWrap(false)
    currentSpellText:SetText("Current recommendation: None")

    local editorLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", currentSpellText, "BOTTOMLEFT", 0, -16)
    editorLabel:SetText("Quick Editor")

    local editorRow = CreateFrame("Frame", nil, options)
    editorRow:SetSize(720, 68)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -8)

    local searchHolder = createSearchInput(editorRow, 120)
    searchHolder:SetPoint("LEFT", 0, -2)
    searchInput = searchHolder.input

    editorSpellDropdown = CreateFrame("Frame", addonName .. "EditorSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    editorSpellDropdown:SetPoint("LEFT", searchHolder, "RIGHT", -10, -8)
    UIDropDownMenu_SetWidth(editorSpellDropdown, 220)
    UIDropDownMenu_JustifyText(editorSpellDropdown, "LEFT")
    initializeSpellDropdown(editorSpellDropdown)

    editorColorDropdown = CreateFrame("Frame", addonName .. "EditorColorDropdown", editorRow, "UIDropDownMenuTemplate")
    editorColorDropdown:SetPoint("LEFT", editorSpellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(editorColorDropdown, 120)
    UIDropDownMenu_JustifyText(editorColorDropdown, "LEFT")
    initializeColorDropdown(editorColorDropdown)

    editorActionButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorActionButton:SetSize(84, 22)
    editorActionButton:SetPoint("LEFT", editorColorDropdown, "RIGHT", 0, 1)
    editorActionButton:SetText("Add")
    editorActionButton:SetScript("OnClick", function()
        saveEditorMapping()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    editorPreviewButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorPreviewButton:SetSize(84, 22)
    editorPreviewButton:SetPoint("LEFT", editorActionButton, "RIGHT", 8, 0)
    editorPreviewButton:SetText("Show")
    editorPreviewButton:SetScript("OnClick", function()
        local spellId, colorIndex, markerIndex, moveGlow = getEditorPreviewState()
        if not spellId or not colorIndex then
            return
        end
        togglePreview(spellId, colorIndex, markerIndex, moveGlow)
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    editorMoveGlowCheck = CreateFrame("CheckButton", addonName .. "EditorMoveGlow", editorRow, "UICheckButtonTemplate")
    editorMoveGlowCheck:SetPoint("BOTTOMLEFT", editorRow, "BOTTOMLEFT", 488, 4)
    editorMoveGlowCheck.text:ClearAllPoints()
    editorMoveGlowCheck.text:SetPoint("LEFT", editorMoveGlowCheck, "RIGHT", 4, 0)
    editorMoveGlowCheck.text:SetWidth(140)
    editorMoveGlowCheck.text:SetJustifyH("LEFT")
    editorMoveGlowCheck.text:SetText("Selected Spell Glow")
    editorMoveGlowCheck:SetScript("OnClick", function(self)
        state.editorMoveGlow = self:GetChecked() and true or false
        if state.previewSpellId == state.editorSpellId then
            state.previewMoveGlow = state.editorMoveGlow == true
        end
        refreshVisibility()
        updateCurrentSpellText()
    end)

    local searchHint = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchHint:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -4)
    searchHint:SetWidth(720)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetText("Search filters the selector and the saved list. Current spec only, with current/recent recommendations shown first.")

    local listLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", searchHint, "BOTTOMLEFT", 0, -16)
    listLabel:SetText("Saved Mappings")

    local listHeaders = CreateFrame("Frame", nil, options)
    listHeaders:SetSize(700, 18)
    listHeaders:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -10)

    local spellHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellHeader:SetPoint("LEFT", 8, 0)
    spellHeader:SetText("Spell")

    local colorHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorHeader:SetPoint("LEFT", 342, 0)
    colorHeader:SetText("Color")

    local glowHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowHeader:SetPoint("LEFT", 486, 0)
    glowHeader:SetText("Glow")

    local showHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showHeader:SetPoint("LEFT", 590, 0)
    showHeader:SetText("Show")

    local deleteHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deleteHeader:SetPoint("LEFT", 660, 0)
    deleteHeader:SetText("Delete")

    mappingScrollFrame = CreateFrame("ScrollFrame", addonName .. "MappingsScrollFrame", options, "FauxScrollFrameTemplate")
    mappingScrollFrame:SetPoint("TOPLEFT", listHeaders, "BOTTOMLEFT", 0, -4)
    mappingScrollFrame:SetSize(700, VISIBLE_MAPPING_ROWS * MAPPING_ROW_HEIGHT)
    mappingScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, MAPPING_ROW_HEIGHT, updateMappingRows)
    end)

    for rowIndex = 1, VISIBLE_MAPPING_ROWS do
        local row = createSavedMappingRow(options, rowIndex)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", mappingRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        mappingRows[rowIndex] = row
    end

    emptyMappingsText = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMappingsText:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 10, -40)
    emptyMappingsText:SetWidth(660)
    emptyMappingsText:SetJustifyH("LEFT")
    emptyMappingsText:SetText("No saved mappings yet. Pick one spell above, choose a color, then add it.")
    emptyMappingsText:Hide()

    local overridesLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overridesLabel:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 0, -20)
    overridesLabel:SetText("State Overrides")

    local overridesHint = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overridesHint:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -4)
    overridesHint:SetWidth(320)
    overridesHint:SetJustifyH("LEFT")
    overridesHint:SetText("Reserved colors below are separate from spell colors and cannot be assigned to mappings.")

    local castingOverrideRow = createOverrideControl(options, "Casting", "casting")
    castingOverrideRow:SetPoint("TOPLEFT", overridesHint, "BOTTOMLEFT", 0, -12)
    castingOverrideCheck = castingOverrideRow.check
    castingOverrideDropdown = castingOverrideRow.dropdown

    local channelingOverrideRow = createOverrideControl(options, "Channeling", "channeling")
    channelingOverrideRow:SetPoint("TOPLEFT", castingOverrideRow, "BOTTOMLEFT", 0, -8)
    channelingOverrideCheck = channelingOverrideRow.check
    channelingOverrideDropdown = channelingOverrideRow.dropdown

    local empowerOverrideRow = createOverrideControl(options, "Empower", "empower")
    empowerOverrideRow:SetPoint("TOPLEFT", channelingOverrideRow, "BOTTOMLEFT", 0, -8)
    empowerOverrideCheck = empowerOverrideRow.check
    empowerOverrideDropdown = empowerOverrideRow.dropdown

    local placementLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placementLabel:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 430, -20)
    placementLabel:SetText("Indicator")

    local function parseInteger(text)
        local value = tonumber(text)
        if not value then
            return nil
        end
        return math.floor(value + 0.5)
    end

    local sizeHolder = createPlacementInput(options, "Size", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().size = clamp(value, 24, 300)
        applySize()
        syncPlacementControls()
        refreshVisibility()
    end)
    sizeHolder:SetPoint("TOPLEFT", placementLabel, "BOTTOMLEFT", 0, -12)
    sizeInput = sizeHolder.input

    local xHolder = createPlacementInput(options, "X", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().x = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 10, 0)
    xInput = xHolder.input

    local yHolder = createPlacementInput(options, "Y", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().y = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 10, 0)
    yInput = yHolder.input

    markerToggleCheck = CreateFrame("CheckButton", addonName .. "MarkerToggle", options, "UICheckButtonTemplate")
    markerToggleCheck:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -12)
    markerToggleCheck.text:SetText("Show Marker")
    markerToggleCheck:SetScript("OnClick", function(self)
        db().showMarker = self:GetChecked() and true or false
        refreshVisibility()
    end)

    lockToggleButton = CreateFrame("Button", nil, options, "GameMenuButtonTemplate")
    lockToggleButton:SetPoint("BOTTOMLEFT", 18, 20)
    lockToggleButton:SetSize(100, 24)
    lockToggleButton:SetText("Unlock")
    lockToggleButton:SetScript("OnClick", function()
        db().locked = not db().locked
        updateEditorControls()
        refreshVisibility()
    end)

    local resetButton = CreateFrame("Button", nil, options, "GameMenuButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", -18, 20)
    resetButton:SetSize(140, 24)
    resetButton:SetText("Reset Defaults")
    resetButton:SetScript("OnClick", function()
        local settings = db()
        settings.point = defaults.point
        settings.relativePoint = defaults.relativePoint
        settings.x = defaults.x
        settings.y = defaults.y
        settings.size = defaults.size
        settings.locked = defaults.locked
        settings.showMarker = defaults.showMarker
        settings.overrides = copyDefaultOverrides()
        settings.mappings = {}
        state.editorSpellId = nil
        state.editorColorIndex = nil
        state.editorMoveGlow = false
        state.searchText = ""
        setPreview(nil)
        if searchInput then
            searchInput:SetText("")
        end
        applySize()
        applyPosition()
        sanitizeSettings()
        updateSpellState()
        syncPlacementControls()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    local closeButton = CreateFrame("Button", nil, options, "GameMenuButtonTemplate")
    closeButton:SetPoint("RIGHT", resetButton, "LEFT", -10, 0)
    closeButton:SetSize(120, 24)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        options:Hide()
    end)

    options:SetScript("OnShow", function()
        state.optionsOpen = true
        refreshAvailableSpells()
        sanitizeSettings()
        syncEditorSelection()
        updateSpellState()
        syncPlacementControls()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    options:SetScript("OnHide", function()
        state.optionsOpen = false
        setPreview(nil)
        refreshVisibility()
    end)
end

local function printUsage()
    print("|cff33ff99Shinkili|r commands:")
    print("/shinkili or /sk - Open settings")
    print("/sk lock - Lock the square")
    print("/sk unlock - Unlock and show move preview")
    print("/sk marker on|off - Show or hide the helper marker")
    print("/sk size <number> - Set square size")
    print("/sk reset - Reset defaults")
end

SLASH_SHINKILI1 = "/shinkili"
SLASH_SHINKILI2 = "/sk"
SlashCmdList.SHINKILI = function(msg)
    local input = trim(msg)
    local command, value = input:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "" then
        if not options then
            createOptionsWindow()
        end
        if options:IsShown() then
            options:Hide()
        else
            options:Show()
        end
        return
    end

    if command == "lock" then
        db().locked = true
        updateEditorControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r locked.")
        return
    end

    if command == "unlock" then
        db().locked = false
        updateEditorControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r unlocked.")
        return
    end

    if command == "size" then
        local numeric = tonumber(value)
        if not numeric then
            print("|cff33ff99Shinkili|r size must be a number.")
            return
        end
        db().size = clamp(math.floor(numeric + 0.5), 24, 300)
        applySize()
        syncPlacementControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r size set to " .. db().size .. ".")
        return
    end

    if command == "marker" then
        local normalized = trim(value):lower()
        if normalized == "on" then
            db().showMarker = true
            updateEditorControls()
            refreshVisibility()
            print("|cff33ff99Shinkili|r helper marker shown.")
            return
        end
        if normalized == "off" then
            db().showMarker = false
            updateEditorControls()
            refreshVisibility()
            print("|cff33ff99Shinkili|r helper marker hidden.")
            return
        end
        print("|cff33ff99Shinkili|r usage: /sk marker on|off")
        return
    end

    if command == "reset" then
        local settings = db()
        settings.point = defaults.point
        settings.relativePoint = defaults.relativePoint
        settings.x = defaults.x
        settings.y = defaults.y
        settings.size = defaults.size
        settings.locked = defaults.locked
        settings.showMarker = defaults.showMarker
        settings.overrides = copyDefaultOverrides()
        settings.mappings = {}
        state.editorSpellId = nil
        state.editorColorIndex = nil
        state.editorMoveGlow = false
        state.searchText = ""
        setPreview(nil)
        if searchInput then
            searchInput:SetText("")
        end
        applySize()
        applyPosition()
        sanitizeSettings()
        updateSpellState()
        syncPlacementControls()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
        print("|cff33ff99Shinkili|r reset to defaults.")
        return
    end

    printUsage()
end

local function initialize()
    if not ShinkiliDB and type(BlizzShinDB) == "table" then
        ShinkiliDB = BlizzShinDB
    end

    ShinkiliDB = ShinkiliDB or {}
    ShinkiliDB.size = ShinkiliDB.size == nil and defaults.size or ShinkiliDB.size
    ShinkiliDB.point = ShinkiliDB.point == nil and defaults.point or ShinkiliDB.point
    ShinkiliDB.relativePoint = ShinkiliDB.relativePoint == nil and defaults.relativePoint or ShinkiliDB.relativePoint
    ShinkiliDB.x = ShinkiliDB.x == nil and defaults.x or ShinkiliDB.x
    ShinkiliDB.y = ShinkiliDB.y == nil and defaults.y or ShinkiliDB.y
    ShinkiliDB.locked = ShinkiliDB.locked == nil and defaults.locked or ShinkiliDB.locked
    ShinkiliDB.showMarker = ShinkiliDB.showMarker == nil and defaults.showMarker or ShinkiliDB.showMarker
    ShinkiliDB.overrides = type(ShinkiliDB.overrides) == "table" and ShinkiliDB.overrides or copyDefaultOverrides()
    ShinkiliDB.mappings = type(ShinkiliDB.mappings) == "table" and ShinkiliDB.mappings or {}

    refreshAvailableSpells()
    sanitizeSettings()
    applySize()
    applyPosition()
    syncPlacementControls()
    updateSpellState()

    addon:RegisterEvent("PLAYER_ENTERING_WORLD")
    addon:RegisterEvent("PLAYER_REGEN_ENABLED")
    addon:RegisterEvent("PLAYER_REGEN_DISABLED")
    addon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    addon:RegisterEvent("SPELLS_CHANGED")

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.05, function()
            if db() then
                local previousSpellId = state.currentSpellId
                local previousCastState = state.currentCastState
                local previousCastSpellId = state.currentCastSpellId
                local nextSpellId = getCurrentRecommendedSpellId()
                local nextCastState, nextCastSpellId = getCurrentCastState()
                if nextSpellId ~= previousSpellId or nextCastState ~= previousCastState or nextCastSpellId ~= previousCastSpellId then
                    if nextSpellId and nextSpellId ~= previousSpellId then
                        rememberRecommendedSpell(nextSpellId)
                    end
                    state.currentSpellId = nextSpellId
                    state.currentCastState = nextCastState
                    state.currentCastSpellId = nextCastSpellId
                    refreshVisibility()
                    if state.optionsOpen then
                        updateEditorControls()
                        updateMappingRows()
                    end
                elseif state.optionsOpen then
                    updateCurrentSpellText()
                end
                updateCooldownSpiral()
            end
        end)
    end
end

addon:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            initialize()
        end
        return
    end

    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshAvailableSpells()
    end

    updateSpellState()
    if state.optionsOpen then
        updateEditorControls()
        updateMappingRows()
    end
end)
