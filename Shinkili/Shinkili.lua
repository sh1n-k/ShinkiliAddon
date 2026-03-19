local addonName = ...
local isSecretValue = _G and _G.issecretvalue or nil

local LEGACY_MAPPING_SLOTS = 12
local VISIBLE_MAPPING_ROWS = 6
local VISIBLE_COOLDOWN_MAPPING_ROWS = 4
local MAPPING_ROW_HEIGHT = 32
local GCD_SPELL_ID = 61304

local defaults = {
    locked = true,
    size = 64,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -120,
    showMarker = true,
    overrides = {
        casting = {enabled = true, colorIndex = 1},
        channeling = {enabled = true, colorIndex = 2},
        empower = {enabled = true, colorIndex = 3},
    },
    mappings = {},
    cooldownBox = {
        enabled = true,
        size = 56,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 86,
        y = -120,
        mappings = {},
    },
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
    cooldownSearchText = "",
    cooldownEditorSpellId = nil,
    cooldownEditorColorIndex = nil,
    cooldownEditorPriority = 100,
    cooldownPreviewSpellId = nil,
    cooldownPreviewColorIndex = nil,
    cooldownPreviewPriority = nil,
    cooldownLastActiveSpellId = nil,
    cooldownLastActiveColorIndex = nil,
    cooldownLastActivePriority = nil,
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

local cooldownSquare = CreateFrame("Frame", "ShinkiliCooldownIndicator", UIParent, "BackdropTemplate")
cooldownSquare:SetMovable(true)
cooldownSquare:SetClampedToScreen(true)
cooldownSquare:EnableMouse(false)
cooldownSquare:RegisterForDrag("LeftButton")
cooldownSquare:SetFrameStrata("FULLSCREEN_DIALOG")
cooldownSquare:SetFrameLevel(195)
cooldownSquare:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 2,
})
cooldownSquare:SetBackdropColor(0.2, 0.2, 0.2, 1)
cooldownSquare:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
cooldownSquare:Hide()

local cooldownLabel = cooldownSquare:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cooldownLabel:SetPoint("BOTTOM", cooldownSquare, "TOP", 0, 3)
cooldownLabel:SetText("COOLDOWN")
cooldownLabel:SetTextColor(0.96, 0.94, 0.86, 1)
cooldownLabel:SetShadowOffset(1, -1)
cooldownLabel:SetShadowColor(0, 0, 0, 0.9)

local options
local currentSpellText
local cooldownCurrentSpellText
local searchInput
local cooldownSearchInput
local sizeInput
local xInput
local yInput
local cooldownSizeInput
local cooldownXInput
local cooldownYInput
local editorSpellDropdown
local editorColorDropdown
local editorActionButton
local editorPreviewButton
local cooldownEditorSpellDropdown
local cooldownEditorColorDropdown
local cooldownEditorPriorityInput
local cooldownEditorActionButton
local cooldownEditorPreviewButton
local lockToggleButton
local markerToggleCheck
local cooldownEnabledCheck
local castingOverrideCheck
local castingOverrideDropdown
local channelingOverrideCheck
local channelingOverrideDropdown
local empowerOverrideCheck
local empowerOverrideDropdown
local mappingScrollFrame
local emptyMappingsText
local mappingRows = {}
local cooldownMappingScrollFrame
local emptyCooldownMappingsText
local cooldownMappingRows = {}
local controlId = 0
local updateEditorControls
local updateMappingRows
local syncPlacementControls
local updateCooldownEditorControls
local updateCooldownMappingRows
local syncCooldownPlacementControls
local updateCooldownSpiral

local function db()
    return ShinkiliDB
end

local function cooldownSettings()
    local settings = db()
    settings.cooldownBox = type(settings.cooldownBox) == "table" and settings.cooldownBox or {}
    return settings.cooldownBox
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

local function findCooldownMappingIndexBySpell(spellId)
    if not spellId then
        return nil
    end

    for index, mapping in ipairs(cooldownSettings().mappings) do
        if mapping.spellId == spellId then
            return index
        end
    end

    return nil
end

local function getCooldownMappingBySpell(spellId)
    local index = findCooldownMappingIndexBySpell(spellId)
    if not index then
        return nil, nil
    end

    return cooldownSettings().mappings[index], index
end

local function normalizePriority(value)
    local priority = tonumber(value)
    if priority then
        priority = math.floor(priority + 0.5)
    end

    if not priority or priority < 1 then
        return 100
    end

    return clamp(priority, 1, 999)
end

local function getCooldownPriority(mapping)
    if type(mapping) ~= "table" then
        return 100
    end

    return normalizePriority(mapping.priority)
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

local function matchesCooldownSearch(spellId)
    local query = trim(state.cooldownSearchText):lower()
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

local function getFilteredAvailableCooldownSpells()
    local filtered = {}

    for _, spellInfo in ipairs(state.availableSpells) do
        if matchesCooldownSearch(spellInfo.spellId) then
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

local function compareCooldownEntries(left, right)
    if left.priority ~= right.priority then
        return left.priority > right.priority
    end

    if left.name == right.name then
        return left.spellId < right.spellId
    end

    return left.name < right.name
end

local function buildCooldownMappingEntries()
    local entries = {}

    for index, mapping in ipairs(cooldownSettings().mappings) do
        if mapping.spellId and matchesCooldownSearch(mapping.spellId) then
            table.insert(entries, {
                index = index,
                spellId = mapping.spellId,
                colorIndex = mapping.colorIndex,
                priority = getCooldownPriority(mapping),
                name = getSpellNameSafe(mapping.spellId),
            })
        end
    end

    table.sort(entries, compareCooldownEntries)
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

local function setCooldownPreview(spellId, colorIndex, priority)
    if not spellId or not colorIndex then
        state.cooldownPreviewSpellId = nil
        state.cooldownPreviewColorIndex = nil
        state.cooldownPreviewPriority = nil
        return
    end

    state.cooldownPreviewSpellId = spellId
    state.cooldownPreviewColorIndex = colorIndex
    state.cooldownPreviewPriority = normalizePriority(priority)
end

local function toggleCooldownPreview(spellId, colorIndex, priority)
    if state.cooldownPreviewSpellId == spellId and state.cooldownPreviewColorIndex == colorIndex then
        setCooldownPreview(nil)
    else
        setCooldownPreview(spellId, colorIndex, priority)
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

    if GetSpellCooldown then
        local startTime, duration, enabled, modRate = GetSpellCooldown(spellId)
        return startTime or 0, duration or 0, enabled, modRate or 1
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellId)
        if info then
            return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
        end
    end

    return nil
end

local function getGlobalCooldownDuration()
    local startTime, duration = getSpellCooldownInfo(GCD_SPELL_ID)
    if not startTime or not duration then
        return 0
    end

    return duration or 0
end

local function isSpellKnownForCurrentCharacter(spellId)
    if not spellId then
        return false
    end

    if IsSpellKnownOrOverridesKnown then
        return IsSpellKnownOrOverridesKnown(spellId)
    end

    if IsPlayerSpell then
        return IsPlayerSpell(spellId)
    end

    return true
end

local function isSpellUsableNow(spellId)
    if not spellId or not isSpellKnownForCurrentCharacter(spellId) then
        return false
    end

    local isUsable = true
    if IsUsableSpell then
        local usable = IsUsableSpell(spellId)
        if usable ~= nil then
            isUsable = usable == true
        end
    elseif C_Spell and C_Spell.IsSpellUsable then
        local usable = C_Spell.IsSpellUsable(spellId)
        if usable ~= nil then
            isUsable = usable == true
        end
    end

    if not isUsable then
        return false
    end

    local _, duration, enabled = getSpellCooldownInfo(spellId)

    if isSecretValue then
        if enabled ~= nil and isSecretValue(enabled) then
            return false
        end
        if duration ~= nil and isSecretValue(duration) then
            return false
        end
    end

    if type(enabled) == "boolean" and enabled == false then
        return false
    end

    if type(enabled) == "number" and enabled == 0 then
        return false
    end

    if type(duration) ~= "number" then
        return false
    end

    if duration <= 0 then
        return true
    end

    return duration <= (getGlobalCooldownDuration() + 0.05)
end

local function getActiveCooldownEntry()
    local settings = cooldownSettings()
    if settings.enabled == false then
        return nil
    end

    local bestEntry
    for _, mapping in ipairs(settings.mappings) do
        if mapping.spellId and mapping.colorIndex and isSpellUsableNow(mapping.spellId) then
            local entry = {
                spellId = mapping.spellId,
                colorIndex = mapping.colorIndex,
                priority = getCooldownPriority(mapping),
                name = getSpellNameSafe(mapping.spellId),
            }

            if not bestEntry or compareCooldownEntries(entry, bestEntry) then
                bestEntry = entry
            end
        end
    end

    return bestEntry
end

local function getDisplayedCooldownEntry()
    if state.cooldownPreviewSpellId and state.cooldownPreviewColorIndex then
        return {
            spellId = state.cooldownPreviewSpellId,
            colorIndex = state.cooldownPreviewColorIndex,
            priority = normalizePriority(state.cooldownPreviewPriority),
            name = getSpellNameSafe(state.cooldownPreviewSpellId),
            isPreview = true,
        }
    end

    return getActiveCooldownEntry()
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

    settings.cooldownBox = type(settings.cooldownBox) == "table" and settings.cooldownBox or {}
    local cooldownBox = settings.cooldownBox
    cooldownBox.enabled = cooldownBox.enabled ~= false
    cooldownBox.size = clamp(tonumber(cooldownBox.size) or defaults.cooldownBox.size, 24, 300)
    cooldownBox.x = clamp(math.floor((tonumber(cooldownBox.x) or defaults.cooldownBox.x) + 0.5), -1000, 1000)
    cooldownBox.y = clamp(math.floor((tonumber(cooldownBox.y) or defaults.cooldownBox.y) + 0.5), -1000, 1000)
    cooldownBox.point = type(cooldownBox.point) == "string" and cooldownBox.point or defaults.cooldownBox.point
    cooldownBox.relativePoint = type(cooldownBox.relativePoint) == "string" and cooldownBox.relativePoint or defaults.cooldownBox.relativePoint

    local migratedCooldownMappings = {}
    local usedCooldownSpells = {}

    if type(cooldownBox.mappings) == "table" then
        for _, rawMapping in ipairs(cooldownBox.mappings) do
            if type(rawMapping) == "table" then
                local spellId = tonumber(rawMapping.spellId)
                if spellId then
                    spellId = math.floor(spellId + 0.5)
                end

                if spellId and spellId > 0 and not usedCooldownSpells[spellId] then
                    local colorIndex = tonumber(rawMapping.colorIndex)
                    if colorIndex then
                        colorIndex = math.floor(colorIndex + 0.5)
                    end
                    if not colorIndex or colorIndex < 2 or colorIndex > #COLOR_PALETTE then
                        colorIndex = 2
                    end

                    table.insert(migratedCooldownMappings, {
                        spellId = spellId,
                        colorIndex = colorIndex,
                        priority = normalizePriority(rawMapping.priority),
                    })
                    usedCooldownSpells[spellId] = true
                end
            end
        end
    end

    cooldownBox.mappings = migratedCooldownMappings
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

local function applyCooldownPosition()
    local settings = cooldownSettings()
    cooldownSquare:ClearAllPoints()
    cooldownSquare:SetPoint(settings.point, UIParent, settings.relativePoint, settings.x, settings.y)
end

local function applyCooldownSize()
    cooldownSquare:SetSize(cooldownSettings().size, cooldownSettings().size)
end

function syncPlacementControls()
    if not sizeInput or not xInput or not yInput then
        return
    end

    sizeInput:SetText(tostring(db().size))
    xInput:SetText(tostring(db().x))
    yInput:SetText(tostring(db().y))
end

function syncCooldownPlacementControls()
    if not cooldownSizeInput or not cooldownXInput or not cooldownYInput then
        return
    end

    local settings = cooldownSettings()
    cooldownSizeInput:SetText(tostring(settings.size))
    cooldownXInput:SetText(tostring(settings.x))
    cooldownYInput:SetText(tostring(settings.y))
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

local function syncCooldownEditorSelection()
    local mapping = getCooldownMappingBySpell(state.cooldownEditorSpellId)
    if mapping then
        state.cooldownEditorColorIndex = mapping.colorIndex
        state.cooldownEditorPriority = getCooldownPriority(mapping)
        return
    end

    state.cooldownEditorPriority = normalizePriority(state.cooldownEditorPriority)
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

local function updateCooldownCurrentSpellText()
    if not cooldownCurrentSpellText then
        return
    end

    local settings = cooldownSettings()
    local lines = {}
    local activeEntry = getActiveCooldownEntry()

    if settings.enabled == false then
        table.insert(lines, "Cooldown box: Disabled")
    elseif activeEntry then
        table.insert(lines, "Cooldown signal: " .. activeEntry.name)
        table.insert(lines, "Priority " .. tostring(activeEntry.priority) .. " / " .. getColorName(activeEntry.colorIndex))
    else
        table.insert(lines, "Cooldown signal: None")
    end

    if state.cooldownPreviewSpellId and state.cooldownPreviewColorIndex then
        table.insert(lines, "Preview: " .. getSpellNameSafe(state.cooldownPreviewSpellId) .. " / Priority " .. tostring(normalizePriority(state.cooldownPreviewPriority)) .. " / " .. getColorName(state.cooldownPreviewColorIndex))
    end

    cooldownCurrentSpellText:SetText(table.concat(lines, "\n"))
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

local function refreshPrimaryVisibility()
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
end

local function refreshCooldownVisibility()
    local rootSettings = db()
    local settings = cooldownSettings()
    local displayedEntry = getDisplayedCooldownEntry()
    local optionsPreview = state.optionsOpen
    local unlockedPreview = not rootSettings.locked
    local showSquare = settings.enabled ~= false and (displayedEntry ~= nil or optionsPreview or unlockedPreview)

    if showSquare then
        cooldownSquare:Show()
    else
        cooldownSquare:Hide()
    end

    if displayedEntry and displayedEntry.colorIndex then
        cooldownSquare:SetBackdropColor(getPaletteColor(displayedEntry.colorIndex))
        cooldownSquare:SetAlpha(1)
        if displayedEntry.isPreview then
            cooldownLabel:SetText("Preview: " .. displayedEntry.name)
        else
            cooldownLabel:SetText(displayedEntry.name)
        end
    elseif optionsPreview and settings.enabled ~= false then
        cooldownSquare:SetBackdropColor(getPaletteColor(5))
        cooldownSquare:SetAlpha(1)
        cooldownLabel:SetText("COOLDOWN")
    else
        cooldownSquare:SetBackdropColor(0.25, 0.25, 0.25, 0.45)
        cooldownSquare:SetAlpha(unlockedPreview and settings.enabled ~= false and 1 or 0)
        cooldownLabel:SetText("MOVE")
    end

    cooldownSquare:EnableMouse(not rootSettings.locked and settings.enabled ~= false)
end

local function refreshVisibility()
    refreshPrimaryVisibility()
    refreshCooldownVisibility()
    updateCurrentSpellText()
    updateCooldownCurrentSpellText()
end

local function updateCooldownActivityState()
    local activeEntry = getActiveCooldownEntry()
    state.cooldownLastActiveSpellId = activeEntry and activeEntry.spellId or nil
    state.cooldownLastActiveColorIndex = activeEntry and activeEntry.colorIndex or nil
    state.cooldownLastActivePriority = activeEntry and activeEntry.priority or nil
end

local function hasCooldownActivityChanged()
    local activeEntry = getActiveCooldownEntry()
    local spellId = activeEntry and activeEntry.spellId or nil
    local colorIndex = activeEntry and activeEntry.colorIndex or nil
    local priority = activeEntry and activeEntry.priority or nil

    return spellId ~= state.cooldownLastActiveSpellId
        or colorIndex ~= state.cooldownLastActiveColorIndex
        or priority ~= state.cooldownLastActivePriority
end

local function updateSpellState()
    local nextSpellId = getCurrentRecommendedSpellId()
    state.currentCastState, state.currentCastSpellId = getCurrentCastState()
    if nextSpellId and nextSpellId ~= state.currentSpellId then
        rememberRecommendedSpell(nextSpellId)
    end
    state.currentSpellId = nextSpellId
    updateCooldownActivityState()
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

local function onCooldownDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local settings = cooldownSettings()
    settings.point = "CENTER"
    settings.relativePoint = "CENTER"
    settings.x = math.floor((x or 0) + 0.5)
    settings.y = math.floor((y or 0) + 0.5)
    applyCooldownPosition()
    syncCooldownPlacementControls()
end

cooldownSquare:SetScript("OnDragStart", function(self)
    if not db().locked and cooldownSettings().enabled ~= false then
        self:StartMoving()
    end
end)
cooldownSquare:SetScript("OnDragStop", onCooldownDragStop)

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

local function initializeCooldownSpellDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local clearInfo = UIDropDownMenu_CreateInfo()
        clearInfo.text = "Select Spell"
        clearInfo.value = 0
        clearInfo.func = function()
            state.cooldownEditorSpellId = nil
            syncCooldownEditorSelection()
            updateCooldownEditorControls()
            updateCooldownMappingRows()
            refreshVisibility()
        end
        clearInfo.checked = state.cooldownEditorSpellId == nil
        UIDropDownMenu_AddButton(clearInfo, level)

        local filteredSpells = getFilteredAvailableCooldownSpells()
        if #filteredSpells == 0 then
            local emptyInfo = UIDropDownMenu_CreateInfo()
            emptyInfo.text = "No spells match the current search"
            emptyInfo.disabled = true
            UIDropDownMenu_AddButton(emptyInfo, level)
            return
        end

        for _, spellInfo in ipairs(filteredSpells) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spellInfo.name
            info.value = spellInfo.spellId
            info.func = function()
                state.cooldownEditorSpellId = spellInfo.spellId
                syncCooldownEditorSelection()
                updateCooldownEditorControls()
                updateCooldownMappingRows()
                refreshVisibility()
            end
            info.checked = state.cooldownEditorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function initializeCooldownColorDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local clearInfo = UIDropDownMenu_CreateInfo()
        clearInfo.text = "Unassigned"
        clearInfo.value = 1
        clearInfo.func = function()
            state.cooldownEditorColorIndex = nil
            updateCooldownEditorControls()
            refreshVisibility()
        end
        clearInfo.checked = state.cooldownEditorColorIndex == nil
        clearInfo.disabled = state.cooldownEditorSpellId == nil
        UIDropDownMenu_AddButton(clearInfo, level)

        for colorIndex = 2, #COLOR_PALETTE do
            local info = UIDropDownMenu_CreateInfo()
            info.text = getColorName(colorIndex)
            info.value = colorIndex
            info.func = function()
                state.cooldownEditorColorIndex = colorIndex
                updateCooldownEditorControls()
                refreshVisibility()
            end
            info.checked = state.cooldownEditorColorIndex == colorIndex
            info.disabled = state.cooldownEditorSpellId == nil
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
    row:SetSize(550, MAPPING_ROW_HEIGHT)

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
    row.spellText:SetWidth(230)
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
    row.colorText:SetWidth(88)
    row.colorText:SetJustifyH("LEFT")
    row.colorText:SetWordWrap(false)
    row.colorText:SetTextColor(0.92, 0.92, 0.92, 1)
    row.colorText:SetShadowOffset(1, -1)
    row.colorText:SetShadowColor(0, 0, 0, 0.75)
    row.colorText:SetText("Color")

    row.glowCheck = CreateFrame("CheckButton", addonName .. "SavedRowGlow" .. rowIndex, row, "UICheckButtonTemplate")
    row.glowCheck:SetSize(24, 24)
    row.glowCheck:SetPoint("LEFT", row.colorText, "RIGHT", 12, 0)
    row.glowCheck.text:SetText("")

    row.previewButton = CreateFrame("Button", addonName .. "SavedRowShow" .. rowIndex, row, "GameMenuButtonTemplate")
    row.previewButton:SetSize(54, 20)
    row.previewButton:SetPoint("RIGHT", -62, 0)
    row.previewButton:SetText("Show")

    row.deleteButton = CreateFrame("Button", addonName .. "SavedRowDelete" .. rowIndex, row, "GameMenuButtonTemplate")
    row.deleteButton:SetSize(54, 20)
    row.deleteButton:SetPoint("RIGHT", -6, 0)
    row.deleteButton:SetText("Delete")

    return row
end

local function createCooldownMappingRow(parent, rowIndex)
    local row = CreateFrame("Frame", addonName .. "CooldownSavedRow" .. rowIndex, parent)
    row:SetSize(540, MAPPING_ROW_HEIGHT)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    if rowIndex % 2 == 0 then
        row.background:SetColorTexture(1, 1, 1, 0.06)
    else
        row.background:SetColorTexture(1, 1, 1, 0.12)
    end

    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.spellText:SetPoint("LEFT", 8, 0)
    row.spellText:SetWidth(240)
    row.spellText:SetJustifyH("LEFT")
    row.spellText:SetWordWrap(false)
    row.spellText:SetTextColor(0.96, 0.94, 0.86, 1)
    row.spellText:SetShadowOffset(1, -1)
    row.spellText:SetShadowColor(0, 0, 0, 0.85)
    row.spellText:SetText("Spell")

    row.colorSwatch = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.colorSwatch:SetSize(14, 14)
    row.colorSwatch:SetPoint("LEFT", row.spellText, "RIGHT", 10, 0)
    row.colorSwatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    row.colorSwatch:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)

    row.colorText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.colorText:SetPoint("LEFT", row.colorSwatch, "RIGHT", 6, 0)
    row.colorText:SetWidth(78)
    row.colorText:SetJustifyH("LEFT")
    row.colorText:SetWordWrap(false)
    row.colorText:SetTextColor(0.92, 0.92, 0.92, 1)
    row.colorText:SetShadowOffset(1, -1)
    row.colorText:SetShadowColor(0, 0, 0, 0.75)

    row.priorityInput = CreateFrame("EditBox", addonName .. "CooldownPriorityRowInput" .. rowIndex, row, "InputBoxTemplate")
    row.priorityInput:SetSize(48, 20)
    row.priorityInput:SetPoint("LEFT", row.colorText, "RIGHT", 10, 0)
    row.priorityInput:SetAutoFocus(false)
    row.priorityInput:SetMaxLetters(3)

    row.previewButton = CreateFrame("Button", addonName .. "CooldownSavedRowShow" .. rowIndex, row, "GameMenuButtonTemplate")
    row.previewButton:SetSize(54, 20)
    row.previewButton:SetPoint("RIGHT", -62, 0)
    row.previewButton:SetText("Show")

    row.deleteButton = CreateFrame("Button", addonName .. "CooldownSavedRowDelete" .. rowIndex, row, "GameMenuButtonTemplate")
    row.deleteButton:SetSize(54, 20)
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

function updateCooldownEditorControls()
    if not options then
        return
    end

    local editorMapping = getCooldownMappingBySpell(state.cooldownEditorSpellId)
    local previewSpellId = state.cooldownEditorSpellId
    local previewColorIndex = state.cooldownEditorColorIndex
    local previewPriority = normalizePriority(state.cooldownEditorPriority)

    UIDropDownMenu_SetSelectedValue(cooldownEditorSpellDropdown, state.cooldownEditorSpellId or 0)
    UIDropDownMenu_SetText(cooldownEditorSpellDropdown, state.cooldownEditorSpellId and getSpellNameSafe(state.cooldownEditorSpellId) or "Select Spell")

    UIDropDownMenu_SetSelectedValue(cooldownEditorColorDropdown, state.cooldownEditorColorIndex or 1)
    UIDropDownMenu_SetText(cooldownEditorColorDropdown, getColorName(state.cooldownEditorColorIndex or 1))

    if cooldownEditorPriorityInput and not cooldownEditorPriorityInput:HasFocus() then
        local desiredText = tostring(previewPriority)
        if cooldownEditorPriorityInput:GetText() ~= desiredText then
            cooldownEditorPriorityInput:SetText(desiredText)
        end
    end

    if editorMapping and not state.cooldownEditorColorIndex then
        UIDropDownMenu_SetText(cooldownEditorColorDropdown, "Unassigned")
    end

    if cooldownEditorActionButton then
        if state.cooldownEditorSpellId and editorMapping then
            cooldownEditorActionButton:SetText("Save")
        else
            cooldownEditorActionButton:SetText("Add")
        end
        cooldownEditorActionButton:SetEnabled(state.cooldownEditorSpellId ~= nil and state.cooldownEditorColorIndex ~= nil)
    end

    if cooldownEditorPreviewButton then
        cooldownEditorPreviewButton:SetEnabled(previewSpellId ~= nil and previewColorIndex ~= nil)
        if previewSpellId and previewColorIndex
            and state.cooldownPreviewSpellId == previewSpellId
            and state.cooldownPreviewColorIndex == previewColorIndex
            and normalizePriority(state.cooldownPreviewPriority) == previewPriority then
            cooldownEditorPreviewButton:SetText("Hide")
        else
            cooldownEditorPreviewButton:SetText("Show")
        end
    end

    if cooldownEnabledCheck then
        cooldownEnabledCheck:SetChecked(cooldownSettings().enabled ~= false)
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

local function deleteCooldownMappingByIndex(mappingIndex)
    local mapping = cooldownSettings().mappings[mappingIndex]
    if not mapping then
        return
    end

    if state.cooldownPreviewSpellId == mapping.spellId then
        setCooldownPreview(nil)
    end

    table.remove(cooldownSettings().mappings, mappingIndex)

    if state.cooldownEditorSpellId == mapping.spellId then
        state.cooldownEditorColorIndex = nil
        state.cooldownEditorPriority = 100
    end

    sanitizeSettings()
    syncCooldownEditorSelection()
    updateCooldownActivityState()
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

local function saveCooldownEditorMapping()
    if not state.cooldownEditorSpellId or not state.cooldownEditorColorIndex then
        return
    end

    local mapping = getCooldownMappingBySpell(state.cooldownEditorSpellId)
    if mapping then
        mapping.colorIndex = state.cooldownEditorColorIndex
        mapping.priority = normalizePriority(state.cooldownEditorPriority)
    else
        table.insert(cooldownSettings().mappings, {
            spellId = state.cooldownEditorSpellId,
            colorIndex = state.cooldownEditorColorIndex,
            priority = normalizePriority(state.cooldownEditorPriority),
        })
    end

    if state.cooldownPreviewSpellId == state.cooldownEditorSpellId then
        state.cooldownPreviewColorIndex = state.cooldownEditorColorIndex
        state.cooldownPreviewPriority = normalizePriority(state.cooldownEditorPriority)
    end

    sanitizeSettings()
    syncCooldownEditorSelection()
    updateCooldownActivityState()
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

function updateCooldownMappingRows()
    if not options then
        return
    end

    local entries = buildCooldownMappingEntries()
    local totalRows = #entries
    local offset = 0

    if cooldownMappingScrollFrame then
        FauxScrollFrame_Update(cooldownMappingScrollFrame, totalRows, VISIBLE_COOLDOWN_MAPPING_ROWS, MAPPING_ROW_HEIGHT)
        offset = FauxScrollFrame_GetOffset(cooldownMappingScrollFrame)
    end

    for rowIndex = 1, VISIBLE_COOLDOWN_MAPPING_ROWS do
        local row = cooldownMappingRows[rowIndex]
        local entry = entries[offset + rowIndex]

        if entry then
            row:Show()
            row.spellText:SetText(entry.name)
            row.colorText:SetText(getColorName(entry.colorIndex))
            row.colorSwatch:SetBackdropColor(getPaletteColor(entry.colorIndex))
            if not row.priorityInput:HasFocus() then
                local desiredPriority = tostring(entry.priority)
                if row.priorityInput:GetText() ~= desiredPriority then
                    row.priorityInput:SetText(desiredPriority)
                end
            end

            local function applyPriorityChange()
                local mapping = cooldownSettings().mappings[entry.index]
                if not mapping then
                    return
                end

                local nextPriority = normalizePriority(row.priorityInput:GetText())
                mapping.priority = nextPriority

                if state.cooldownEditorSpellId == entry.spellId then
                    state.cooldownEditorPriority = nextPriority
                end
                if state.cooldownPreviewSpellId == entry.spellId then
                    state.cooldownPreviewPriority = nextPriority
                end

                sanitizeSettings()
                updateCooldownActivityState()
                updateCooldownEditorControls()
                updateCooldownMappingRows()
                refreshVisibility()
            end

            row.priorityInput:SetScript("OnEnterPressed", function(self)
                applyPriorityChange()
                self:ClearFocus()
            end)
            row.priorityInput:SetScript("OnEditFocusLost", applyPriorityChange)
            row.priorityInput:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(entry.priority))
                self:ClearFocus()
            end)

            if state.cooldownPreviewSpellId == entry.spellId
                and state.cooldownPreviewColorIndex == entry.colorIndex
                and normalizePriority(state.cooldownPreviewPriority) == entry.priority then
                row.previewButton:SetText("Hide")
            else
                row.previewButton:SetText("Show")
            end

            row.previewButton:SetScript("OnClick", function()
                toggleCooldownPreview(entry.spellId, entry.colorIndex, entry.priority)
                updateCooldownEditorControls()
                updateCooldownMappingRows()
                refreshVisibility()
            end)

            row.deleteButton:SetScript("OnClick", function()
                deleteCooldownMappingByIndex(entry.index)
                updateCooldownEditorControls()
                updateCooldownMappingRows()
                refreshVisibility()
            end)
        else
            row:Hide()
        end
    end

    if emptyCooldownMappingsText then
        if totalRows == 0 then
            emptyCooldownMappingsText:Show()
        else
            emptyCooldownMappingsText:Hide()
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

local function parseInteger(text)
    local value = tonumber(text)
    if not value then
        return nil
    end
    return math.floor(value + 0.5)
end

local function refreshAllEditorViews()
    syncPlacementControls()
    syncCooldownPlacementControls()
    updateEditorControls()
    updateMappingRows()
    updateCooldownEditorControls()
    updateCooldownMappingRows()
end

local function resetToDefaults()
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
    settings.cooldownBox = {
        enabled = defaults.cooldownBox.enabled,
        size = defaults.cooldownBox.size,
        point = defaults.cooldownBox.point,
        relativePoint = defaults.cooldownBox.relativePoint,
        x = defaults.cooldownBox.x,
        y = defaults.cooldownBox.y,
        mappings = {},
    }

    state.editorSpellId = nil
    state.editorColorIndex = nil
    state.editorMoveGlow = false
    state.searchText = ""
    state.cooldownEditorSpellId = nil
    state.cooldownEditorColorIndex = nil
    state.cooldownEditorPriority = 100
    state.cooldownSearchText = ""
    setPreview(nil)
    setCooldownPreview(nil)

    if searchInput then
        searchInput:SetText("")
    end
    if cooldownSearchInput then
        cooldownSearchInput:SetText("")
    end

    applySize()
    applyPosition()
    applyCooldownSize()
    applyCooldownPosition()
    sanitizeSettings()
    updateSpellState()
    refreshAllEditorViews()
    refreshVisibility()
end

local function createMainOptionsPanel(frame)
    local leftTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 18, -34)
    leftTitle:SetText("Main Highlight")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(560)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Blizzard Assisted Combat recommendation is shown here. Search current-spec spells and manage only the mappings you save.")

    currentSpellText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentSpellText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    currentSpellText:SetWidth(560)
    currentSpellText:SetHeight(32)
    currentSpellText:SetJustifyH("LEFT")
    currentSpellText:SetWordWrap(false)
    currentSpellText:SetText("Current recommendation: None")

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", currentSpellText, "BOTTOMLEFT", 0, -16)
    editorLabel:SetText("Quick Editor")

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(560, 72)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -8)

    local searchHolder = createSearchInput(editorRow, 90)
    searchHolder:SetPoint("LEFT", 0, -2)
    searchInput = searchHolder.input

    editorSpellDropdown = CreateFrame("Frame", addonName .. "EditorSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    editorSpellDropdown:SetPoint("LEFT", searchHolder, "RIGHT", -10, -8)
    UIDropDownMenu_SetWidth(editorSpellDropdown, 170)
    UIDropDownMenu_JustifyText(editorSpellDropdown, "LEFT")
    initializeSpellDropdown(editorSpellDropdown)

    editorColorDropdown = CreateFrame("Frame", addonName .. "EditorColorDropdown", editorRow, "UIDropDownMenuTemplate")
    editorColorDropdown:SetPoint("LEFT", editorSpellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(editorColorDropdown, 92)
    UIDropDownMenu_JustifyText(editorColorDropdown, "LEFT")
    initializeColorDropdown(editorColorDropdown)

    editorActionButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorActionButton:SetSize(52, 22)
    editorActionButton:SetPoint("LEFT", editorColorDropdown, "RIGHT", -2, 0)
    editorActionButton:SetText("Add")
    editorActionButton:SetScript("OnClick", function()
        saveEditorMapping()
        updateEditorControls()
        updateMappingRows()
        updateCooldownEditorControls()
        refreshVisibility()
    end)

    editorPreviewButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorPreviewButton:SetSize(52, 22)
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

    local searchHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchHint:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -8)
    searchHint:SetWidth(540)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetText("Search filters the selector and the saved list. Current spec only, with current/recent recommendations shown first.")

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", searchHint, "BOTTOMLEFT", 0, -16)
    listLabel:SetText("Saved Mappings")

    local listHeaders = CreateFrame("Frame", nil, frame)
    listHeaders:SetSize(550, 18)
    listHeaders:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -10)

    local spellHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellHeader:SetPoint("LEFT", 32, 0)
    spellHeader:SetText("Spell")

    local colorHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorHeader:SetPoint("LEFT", 270, 0)
    colorHeader:SetText("Color")

    local glowHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowHeader:SetPoint("LEFT", 402, 0)
    glowHeader:SetText("Glow")

    local showHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showHeader:SetPoint("LEFT", 452, 0)
    showHeader:SetText("Show")

    local deleteHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deleteHeader:SetPoint("LEFT", 508, 0)
    deleteHeader:SetText("Delete")

    mappingScrollFrame = CreateFrame("ScrollFrame", addonName .. "MappingsScrollFrame", frame, "FauxScrollFrameTemplate")
    mappingScrollFrame:SetPoint("TOPLEFT", listHeaders, "BOTTOMLEFT", 0, -4)
    mappingScrollFrame:SetSize(550, VISIBLE_MAPPING_ROWS * MAPPING_ROW_HEIGHT)
    mappingScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, MAPPING_ROW_HEIGHT, updateMappingRows)
    end)

    for rowIndex = 1, VISIBLE_MAPPING_ROWS do
        local row = createSavedMappingRow(frame, rowIndex)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", mappingRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        mappingRows[rowIndex] = row
    end

    emptyMappingsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMappingsText:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 10, -40)
    emptyMappingsText:SetWidth(510)
    emptyMappingsText:SetJustifyH("LEFT")
    emptyMappingsText:SetText("No saved mappings yet. Pick one spell above, choose a color, then add it.")
    emptyMappingsText:Hide()

    local overridesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overridesLabel:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 0, -20)
    overridesLabel:SetText("State Overrides")

    local overridesHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overridesHint:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -4)
    overridesHint:SetWidth(340)
    overridesHint:SetJustifyH("LEFT")
    overridesHint:SetText("Reserved colors below are separate from spell colors and cannot be assigned to mappings.")

    local castingOverrideRow = createOverrideControl(frame, "Casting", "casting")
    castingOverrideRow:SetPoint("TOPLEFT", overridesHint, "BOTTOMLEFT", 0, -12)
    castingOverrideCheck = castingOverrideRow.check
    castingOverrideDropdown = castingOverrideRow.dropdown

    local channelingOverrideRow = createOverrideControl(frame, "Channeling", "channeling")
    channelingOverrideRow:SetPoint("TOPLEFT", castingOverrideRow, "BOTTOMLEFT", 0, -8)
    channelingOverrideCheck = channelingOverrideRow.check
    channelingOverrideDropdown = channelingOverrideRow.dropdown

    local empowerOverrideRow = createOverrideControl(frame, "Empower", "empower")
    empowerOverrideRow:SetPoint("TOPLEFT", channelingOverrideRow, "BOTTOMLEFT", 0, -8)
    empowerOverrideCheck = empowerOverrideRow.check
    empowerOverrideDropdown = empowerOverrideRow.dropdown

    local placementColumn = CreateFrame("Frame", nil, frame)
    placementColumn:SetSize(170, 160)
    placementColumn:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 380, -20)

    local placementLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placementLabel:SetPoint("TOPLEFT", placementColumn, "TOPLEFT", 0, 0)
    placementLabel:SetText("Indicator")

    local sizeHolder = createPlacementInput(placementColumn, "Size", 56, function(text)
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

    local xHolder = createPlacementInput(placementColumn, "X", 56, function(text)
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

    local yHolder = createPlacementInput(placementColumn, "Y", 56, function(text)
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

    markerToggleCheck = CreateFrame("CheckButton", addonName .. "MarkerToggle", placementColumn, "UICheckButtonTemplate")
    markerToggleCheck:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -12)
    markerToggleCheck.text:SetText("Show Marker")
    markerToggleCheck:SetScript("OnClick", function(self)
        db().showMarker = self:GetChecked() and true or false
        refreshVisibility()
    end)
end

local function createCooldownOptionsPanel(frame)
    local rightTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", 635, -34)
    rightTitle:SetText("Cooldown Box")

    local rightSubtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rightSubtitle:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -4)
    rightSubtitle:SetWidth(540)
    rightSubtitle:SetJustifyH("LEFT")
    rightSubtitle:SetText("Register major cooldown spells with colors and priorities. The highest-priority ready spell paints the cooldown box.")

    cooldownCurrentSpellText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cooldownCurrentSpellText:SetPoint("TOPLEFT", rightSubtitle, "BOTTOMLEFT", 0, -10)
    cooldownCurrentSpellText:SetWidth(540)
    cooldownCurrentSpellText:SetHeight(32)
    cooldownCurrentSpellText:SetJustifyH("LEFT")
    cooldownCurrentSpellText:SetWordWrap(false)
    cooldownCurrentSpellText:SetText("Cooldown signal: None")

    local cooldownEditorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownEditorLabel:SetPoint("TOPLEFT", cooldownCurrentSpellText, "BOTTOMLEFT", 0, -16)
    cooldownEditorLabel:SetText("Cooldown Editor")

    local cooldownEditorRow = CreateFrame("Frame", nil, frame)
    cooldownEditorRow:SetSize(540, 104)
    cooldownEditorRow:SetPoint("TOPLEFT", cooldownEditorLabel, "BOTTOMLEFT", 0, -8)

    local cooldownSearchHolder = createSearchInput(cooldownEditorRow, 90)
    cooldownSearchHolder:SetPoint("LEFT", 0, -2)
    cooldownSearchInput = cooldownSearchHolder.input
    cooldownSearchInput:SetScript("OnTextChanged", function(self)
        state.cooldownSearchText = self:GetText() or ""
        updateCooldownEditorControls()
        updateCooldownMappingRows()
    end)

    cooldownEditorSpellDropdown = CreateFrame("Frame", addonName .. "CooldownEditorSpellDropdown", cooldownEditorRow, "UIDropDownMenuTemplate")
    cooldownEditorSpellDropdown:SetPoint("LEFT", cooldownSearchHolder, "RIGHT", -10, -8)
    UIDropDownMenu_SetWidth(cooldownEditorSpellDropdown, 170)
    UIDropDownMenu_JustifyText(cooldownEditorSpellDropdown, "LEFT")
    initializeCooldownSpellDropdown(cooldownEditorSpellDropdown)

    cooldownEditorColorDropdown = CreateFrame("Frame", addonName .. "CooldownEditorColorDropdown", cooldownEditorRow, "UIDropDownMenuTemplate")
    cooldownEditorColorDropdown:SetPoint("LEFT", cooldownEditorSpellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(cooldownEditorColorDropdown, 86)
    UIDropDownMenu_JustifyText(cooldownEditorColorDropdown, "LEFT")
    initializeCooldownColorDropdown(cooldownEditorColorDropdown)

    local priorityHolder = createPlacementInput(cooldownEditorRow, "Priority", 64, function(text)
        state.cooldownEditorPriority = normalizePriority(text)
        updateCooldownEditorControls()
        refreshVisibility()
    end)
    priorityHolder:SetPoint("TOPLEFT", cooldownSearchHolder, "BOTTOMLEFT", 0, -10)
    cooldownEditorPriorityInput = priorityHolder.input
    cooldownEditorPriorityInput:SetMaxLetters(3)

    cooldownEditorActionButton = CreateFrame("Button", nil, cooldownEditorRow, "GameMenuButtonTemplate")
    cooldownEditorActionButton:SetSize(52, 22)
    cooldownEditorActionButton:SetPoint("LEFT", priorityHolder.input, "RIGHT", 12, 0)
    cooldownEditorActionButton:SetText("Add")
    cooldownEditorActionButton:SetScript("OnClick", function()
        saveCooldownEditorMapping()
        updateCooldownEditorControls()
        updateCooldownMappingRows()
        refreshVisibility()
    end)

    cooldownEditorPreviewButton = CreateFrame("Button", nil, cooldownEditorRow, "GameMenuButtonTemplate")
    cooldownEditorPreviewButton:SetSize(52, 22)
    cooldownEditorPreviewButton:SetPoint("LEFT", cooldownEditorActionButton, "RIGHT", 6, 0)
    cooldownEditorPreviewButton:SetText("Show")
    cooldownEditorPreviewButton:SetScript("OnClick", function()
        if not state.cooldownEditorSpellId or not state.cooldownEditorColorIndex then
            return
        end
        toggleCooldownPreview(state.cooldownEditorSpellId, state.cooldownEditorColorIndex, state.cooldownEditorPriority)
        updateCooldownEditorControls()
        updateCooldownMappingRows()
        refreshVisibility()
    end)

    local cooldownSearchHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownSearchHint:SetPoint("TOPLEFT", cooldownEditorRow, "BOTTOMLEFT", 0, -8)
    cooldownSearchHint:SetWidth(520)
    cooldownSearchHint:SetJustifyH("LEFT")
    cooldownSearchHint:SetText("Higher priority wins. Spells with secret Blizzard cooldown values are skipped.")

    local cooldownListLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownListLabel:SetPoint("TOPLEFT", cooldownSearchHint, "BOTTOMLEFT", 0, -16)
    cooldownListLabel:SetText("Saved Cooldowns")

    local cooldownListHeaders = CreateFrame("Frame", nil, frame)
    cooldownListHeaders:SetSize(540, 18)
    cooldownListHeaders:SetPoint("TOPLEFT", cooldownListLabel, "BOTTOMLEFT", 0, -10)

    local cooldownSpellHeader = cooldownListHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownSpellHeader:SetPoint("LEFT", 8, 0)
    cooldownSpellHeader:SetText("Spell")

    local cooldownColorHeader = cooldownListHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownColorHeader:SetPoint("LEFT", 290, 0)
    cooldownColorHeader:SetText("Color")

    local cooldownPriorityHeader = cooldownListHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownPriorityHeader:SetPoint("LEFT", 398, 0)
    cooldownPriorityHeader:SetText("Priority")

    local cooldownShowHeader = cooldownListHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownShowHeader:SetPoint("LEFT", 462, 0)
    cooldownShowHeader:SetText("Show")

    local cooldownDeleteHeader = cooldownListHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownDeleteHeader:SetPoint("LEFT", 518, 0)
    cooldownDeleteHeader:SetText("Delete")

    cooldownMappingScrollFrame = CreateFrame("ScrollFrame", addonName .. "CooldownMappingsScrollFrame", frame, "FauxScrollFrameTemplate")
    cooldownMappingScrollFrame:SetPoint("TOPLEFT", cooldownListHeaders, "BOTTOMLEFT", 0, -4)
    cooldownMappingScrollFrame:SetSize(540, VISIBLE_COOLDOWN_MAPPING_ROWS * MAPPING_ROW_HEIGHT)
    cooldownMappingScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, MAPPING_ROW_HEIGHT, updateCooldownMappingRows)
    end)

    for rowIndex = 1, VISIBLE_COOLDOWN_MAPPING_ROWS do
        local row = createCooldownMappingRow(frame, rowIndex)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", cooldownMappingScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", cooldownMappingRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        cooldownMappingRows[rowIndex] = row
    end

    emptyCooldownMappingsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyCooldownMappingsText:SetPoint("TOPLEFT", cooldownMappingScrollFrame, "TOPLEFT", 10, -40)
    emptyCooldownMappingsText:SetWidth(500)
    emptyCooldownMappingsText:SetJustifyH("LEFT")
    emptyCooldownMappingsText:SetText("No cooldowns saved yet. Pick one spell, a color, and a priority.")
    emptyCooldownMappingsText:Hide()

    local cooldownPlacementLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cooldownPlacementLabel:SetPoint("TOPLEFT", cooldownMappingScrollFrame, "BOTTOMLEFT", 0, -20)
    cooldownPlacementLabel:SetText("Cooldown Indicator")

    cooldownEnabledCheck = CreateFrame("CheckButton", addonName .. "CooldownEnabled", frame, "UICheckButtonTemplate")
    cooldownEnabledCheck:SetPoint("TOPLEFT", cooldownPlacementLabel, "BOTTOMLEFT", 0, -8)
    cooldownEnabledCheck.text:SetText("Enable Cooldown Box")
    cooldownEnabledCheck:SetScript("OnClick", function(self)
        cooldownSettings().enabled = self:GetChecked() and true or false
        refreshVisibility()
        updateCooldownCurrentSpellText()
    end)

    local cooldownSizeHolder = createPlacementInput(frame, "Size", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncCooldownPlacementControls()
            return
        end
        cooldownSettings().size = clamp(value, 24, 300)
        applyCooldownSize()
        syncCooldownPlacementControls()
        refreshVisibility()
    end)
    cooldownSizeHolder:SetPoint("TOPLEFT", cooldownEnabledCheck, "BOTTOMLEFT", 4, -12)
    cooldownSizeInput = cooldownSizeHolder.input

    local cooldownXHolder = createPlacementInput(frame, "X", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncCooldownPlacementControls()
            return
        end
        cooldownSettings().x = clamp(value, -1000, 1000)
        applyCooldownPosition()
        syncCooldownPlacementControls()
    end)
    cooldownXHolder:SetPoint("LEFT", cooldownSizeHolder, "RIGHT", 10, 0)
    cooldownXInput = cooldownXHolder.input

    local cooldownYHolder = createPlacementInput(frame, "Y", 56, function(text)
        local value = parseInteger(text)
        if not value then
            syncCooldownPlacementControls()
            return
        end
        cooldownSettings().y = clamp(value, -1000, 1000)
        applyCooldownPosition()
        syncCooldownPlacementControls()
    end)
    cooldownYHolder:SetPoint("LEFT", cooldownXHolder, "RIGHT", 10, 0)
    cooldownYInput = cooldownYHolder.input
end

local function createOptionsFooter(frame)
    lockToggleButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    lockToggleButton:SetPoint("BOTTOMLEFT", 18, 20)
    lockToggleButton:SetSize(100, 24)
    lockToggleButton:SetText("Unlock")
    lockToggleButton:SetScript("OnClick", function()
        db().locked = not db().locked
        updateEditorControls()
        refreshVisibility()
    end)

    local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", -18, 20)
    resetButton:SetSize(140, 24)
    resetButton:SetText("Reset Defaults")
    resetButton:SetScript("OnClick", resetToDefaults)

    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetPoint("RIGHT", resetButton, "LEFT", -10, 0)
    closeButton:SetSize(120, 24)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
end

local function attachOptionsLifecycle(frame)
    frame:SetScript("OnShow", function()
        state.optionsOpen = true
        refreshAvailableSpells()
        sanitizeSettings()
        syncEditorSelection()
        syncCooldownEditorSelection()
        updateSpellState()
        refreshAllEditorViews()
        refreshVisibility()
    end)

    frame:SetScript("OnHide", function()
        state.optionsOpen = false
        setPreview(nil)
        setCooldownPreview(nil)
        refreshVisibility()
    end)
end

local function createOptionsWindow()
    options = CreateFrame("Frame", "ShinkiliOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    options:SetSize(1220, 790)
    options:SetPoint("CENTER")
    options:SetMovable(true)
    options:SetClampedToScreen(true)
    options:EnableMouse(true)
    options:RegisterForDrag("LeftButton")
    options:SetScript("OnDragStart", options.StartMoving)
    options:SetScript("OnDragStop", options.StopMovingOrSizing)
    options:Hide()

    options.TitleText:SetText("Shinkili")

    local divider = options:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetPoint("TOP", 0, -34)
    divider:SetPoint("BOTTOM", 0, 46)
    divider:SetWidth(1)

    createMainOptionsPanel(options)
    createCooldownOptionsPanel(options)
    createOptionsFooter(options)
    attachOptionsLifecycle(options)
end

local function printUsage()
    print("|cff33ff99Shinkili|r commands:")
    print("/shinkili or /sk - Open settings")
    print("/sk lock - Lock the square")
    print("/sk unlock - Unlock and show move preview")
    print("/sk marker on|off - Show or hide the helper marker")
    print("/sk size <number> - Set main square size")
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
        resetToDefaults()
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
    ShinkiliDB.cooldownBox = type(ShinkiliDB.cooldownBox) == "table" and ShinkiliDB.cooldownBox or {
        enabled = defaults.cooldownBox.enabled,
        size = defaults.cooldownBox.size,
        point = defaults.cooldownBox.point,
        relativePoint = defaults.cooldownBox.relativePoint,
        x = defaults.cooldownBox.x,
        y = defaults.cooldownBox.y,
        mappings = {},
    }

    refreshAvailableSpells()
    sanitizeSettings()
    applySize()
    applyPosition()
    applyCooldownSize()
    applyCooldownPosition()
    syncPlacementControls()
    syncCooldownPlacementControls()
    updateSpellState()

    addon:RegisterEvent("PLAYER_ENTERING_WORLD")
    addon:RegisterEvent("PLAYER_REGEN_ENABLED")
    addon:RegisterEvent("PLAYER_REGEN_DISABLED")
    addon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    addon:RegisterEvent("SPELLS_CHANGED")
    addon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    addon:RegisterEvent("SPELL_UPDATE_CHARGES")

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.05, function()
            if db() then
                local previousSpellId = state.currentSpellId
                local previousCastState = state.currentCastState
                local previousCastSpellId = state.currentCastSpellId
                local cooldownChanged = hasCooldownActivityChanged()
                local nextSpellId = getCurrentRecommendedSpellId()
                local nextCastState, nextCastSpellId = getCurrentCastState()
                if nextSpellId ~= previousSpellId or nextCastState ~= previousCastState or nextCastSpellId ~= previousCastSpellId or cooldownChanged then
                    if nextSpellId and nextSpellId ~= previousSpellId then
                        rememberRecommendedSpell(nextSpellId)
                    end
                    state.currentSpellId = nextSpellId
                    state.currentCastState = nextCastState
                    state.currentCastSpellId = nextCastSpellId
                    updateCooldownActivityState()
                    refreshVisibility()
                    if state.optionsOpen then
                        updateEditorControls()
                        updateMappingRows()
                        updateCooldownEditorControls()
                        updateCooldownMappingRows()
                    end
                elseif state.optionsOpen then
                    updateCurrentSpellText()
                    updateCooldownCurrentSpellText()
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
        updateCooldownEditorControls()
        updateCooldownMappingRows()
    end
end)
