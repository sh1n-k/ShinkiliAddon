local addonName = ...

local LEGACY_MAPPING_SLOTS = 12
local VISIBLE_MAPPING_ROWS = 6
local MAPPING_ROW_HEIGHT = 30
local PRIORITY_VISIBLE_ROWS = 6
local PRIORITY_ROW_HEIGHT = 30
local GCD_SPELL_ID = 61304
local OPTIONS_WIDTH = 820
local OPTIONS_HEIGHT = 640

local Logic = ShinkiliLogic
local Locale = ShinkiliLocale

local defaults = {
    locale = "en",
    locked = true,
    size = 64,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -120,
    showMarker = true,
    showMinimapButton = true,
    minimapAngle = 220,
    overrides = {
        casting = {enabled = true, colorIndex = 1},
        channeling = {enabled = true, colorIndex = 2},
        empower = {enabled = true, colorIndex = 3},
    },
    mappings = {},
    defense = {
        enabled = true,
        locked = true,
        size = 48,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 100,
        y = -120,
        entries = {},
    },
    procs = {
        entries = {},
    },
}

local function L(key)
    local code = defaults.locale
    if ShinkiliDB and type(ShinkiliDB.locale) == "string" then
        code = ShinkiliDB.locale
    end
    if Locale and Locale.get then
        return Locale.get(code, key)
    end
    return key
end

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
    activeProcSpellId = nil,
    defenseSpellId = nil,
    optionsOpen = false,
    optionsTab = "main",
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
    defenseEditorSpellId = nil,
    defenseEditorColorIndex = 2,
    procEditorSpellId = nil,
    procEditorColorIndex = 2,
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

local defenseBox = CreateFrame("Frame", "ShinkiliDefenseBox", UIParent, "BackdropTemplate")
defenseBox:SetMovable(true)
defenseBox:SetClampedToScreen(true)
defenseBox:EnableMouse(false)
defenseBox:RegisterForDrag("LeftButton")
defenseBox:SetFrameStrata("FULLSCREEN_DIALOG")
defenseBox:SetFrameLevel(190)
defenseBox:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 2,
})
defenseBox:SetBackdropColor(0.2, 0.2, 0.2, 1)
defenseBox:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
defenseBox:Hide()

local defenseLabel = defenseBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
defenseLabel:SetPoint("BOTTOM", defenseBox, "TOP", 0, 4)
defenseLabel:SetTextColor(0.96, 0.94, 0.86, 1)
defenseLabel:SetShadowOffset(1, -1)
defenseLabel:SetShadowColor(0, 0, 0, 0.9)

local options
local optionsTabs = {}
local optionsPanels = {}
local minimapButton
local minimapSizeHooked = false
local currentSpellText
local searchInput
local sizeInput
local xInput
local yInput
local editorSpellDropdown
local editorColorDropdown
local editorActionButton
local editorPreviewButton
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
local defenseRows = {}
local defenseScrollFrame
local emptyDefenseText
local procRows = {}
local procScrollFrame
local emptyProcText
local optionsLayout
local controlId = 0
local updateEditorControls
local updateMappingRows
local updateDefenseRows
local updateProcRows
local syncPlacementControls
local updateCooldownSpiral
local refreshMinimapButton
local refreshDefenseBox
local selectOptionsTab
local refreshOptionsLocale

local function db()
    return ShinkiliDB
end

local function clamp(value, minimum, maximum)
    return Logic.clamp(value, minimum, maximum)
end

local function trim(text)
    return Logic.trim(text)
end

local function sanitizeConfig()
    return {
        sizeDefault = defaults.size,
        xDefault = defaults.x,
        yDefault = defaults.y,
        pointDefault = defaults.point,
        relativePointDefault = defaults.relativePoint,
        legacyMappingSlots = LEGACY_MAPPING_SLOTS,
        colorPaletteSize = #COLOR_PALETTE,
        markerPaletteSize = #MARKER_PALETTE,
        reservedOverrideSize = #RESERVED_OVERRIDE_PALETTE,
        defaultOverrides = defaults.overrides,
        defenseDefaults = defaults.defense,
    }
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
    return Logic.copyDefaultOverrides(defaults.overrides)
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
    return Logic.isColorUsedByOtherMapping(db().mappings, mappingIndex, colorIndex)
end

local function getSuggestedMarkerIndex(mappingIndex)
    return Logic.getSuggestedMarkerIndex(db().mappings, mappingIndex, #MARKER_PALETTE)
end

local function matchesSearch(spellId)
    return Logic.matchesSearch(spellId, getSpellNameSafe(spellId), state.searchText)
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

local function isSpellUsableNow(spellId)
    if not spellId then
        return false
    end

    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, spellId)
        if ok then
            return usable and true or false
        end
    end

    if IsUsableSpell then
        local ok, usable = pcall(IsUsableSpell, spellId)
        if ok then
            return usable and true or false
        end
    end

    return false
end

local function isProcActive(spellId)
    if not spellId then
        return false
    end

    if IsSpellOverlayed then
        local ok, active = pcall(IsSpellOverlayed, spellId)
        if ok and active then
            return true
        end
    end

    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, active = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellId)
        if ok and active then
            return true
        end
    end

    return false
end

local function getActiveProcEntry()
    local entries = db().procs and db().procs.entries
    if type(entries) ~= "table" then
        return nil
    end

    local activeSet = {}
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false and entry.spellId and isProcActive(entry.spellId) then
            activeSet[entry.spellId] = true
        end
    end

    return Logic.pickPriorityEntry(entries, activeSet)
end

local function getActiveDefenseEntry()
    local defense = db().defense
    if not defense or defense.enabled == false then
        return nil
    end
    local entries = defense.entries
    if type(entries) ~= "table" then
        return nil
    end

    local activeSet = {}
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false and entry.spellId and isSpellUsableNow(entry.spellId) then
            activeSet[entry.spellId] = true
        end
    end

    return Logic.pickPriorityEntry(entries, activeSet)
end

local function getDisplayedSpellId()
    if state.previewSpellId then
        return state.previewSpellId
    end
    if state.activeProcSpellId then
        return state.activeProcSpellId
    end
    return state.currentSpellId
end

local function getDisplayedColorIndex()
    if state.previewColorIndex then
        return state.previewColorIndex
    end
    if state.activeProcSpellId then
        local entry = getActiveProcEntry()
        if entry and entry.spellId == state.activeProcSpellId then
            return entry.colorIndex
        end
        local entries = db().procs and db().procs.entries
        if type(entries) == "table" then
            for _, procEntry in ipairs(entries) do
                if procEntry.spellId == state.activeProcSpellId then
                    return procEntry.colorIndex
                end
            end
        end
    end
    return getAssignedColorIndex(state.currentSpellId)
end

local function getDisplayedMarkerIndex()
    if state.previewMarkerIndex then
        return state.previewMarkerIndex
    end
    if state.activeProcSpellId then
        return getAssignedMarkerIndex(state.activeProcSpellId) or 1
    end
    return getAssignedMarkerIndex(state.currentSpellId)
end

local function getDisplayedMoveGlowEnabled()
    if state.previewSpellId then
        return state.previewMoveGlow == true
    end
    if state.activeProcSpellId then
        return getAssignedMoveGlowEnabled(state.activeProcSpellId)
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

local function sanitizeSettings()
    Logic.sanitizeSettings(db(), sanitizeConfig())
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

local function applyDefensePosition()
    local defense = db().defense
    if not defense then
        return
    end
    defenseBox:ClearAllPoints()
    defenseBox:SetPoint(defense.point or "CENTER", UIParent, defense.relativePoint or "CENTER", defense.x or 100, defense.y or -120)
end

local function applyDefenseSize()
    local defense = db().defense
    local size = defense and defense.size or defaults.defense.size
    defenseBox:SetSize(size, size)
end

local function onDefenseDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local defense = db().defense
    defense.point = "CENTER"
    defense.relativePoint = "CENTER"
    defense.x = math.floor((x or 0) + 0.5)
    defense.y = math.floor((y or 0) + 0.5)
    applyDefensePosition()
end

defenseBox:SetScript("OnDragStart", function(self)
    if db().defense and not db().defense.locked then
        self:StartMoving()
    end
end)
defenseBox:SetScript("OnDragStop", onDefenseDragStop)

refreshDefenseBox = function()
    local defense = db().defense
    local entry = getActiveDefenseEntry()
    state.defenseSpellId = entry and entry.spellId or nil

    local showForEdit = state.optionsOpen and defense and defense.enabled ~= false and defense.locked == false
    if not defense or defense.enabled == false then
        defenseBox:Hide()
        return
    end

    applyDefenseSize()
    applyDefensePosition()

    if entry then
        defenseBox:Show()
        defenseBox:SetBackdropColor(getPaletteColor(entry.colorIndex))
        defenseBox:SetAlpha(1)
        defenseLabel:SetText(getSpellNameSafe(entry.spellId))
        defenseLabel:Show()
    elseif showForEdit or (state.optionsOpen and defense.enabled ~= false) then
        defenseBox:Show()
        defenseBox:SetBackdropColor(0.25, 0.25, 0.25, 0.55)
        defenseBox:SetAlpha(1)
        defenseLabel:SetText(L("DEFENSE_BOX_LABEL"))
        defenseLabel:Show()
    else
        defenseBox:Hide()
    end

    defenseBox:EnableMouse(defense.locked == false)
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
    local shown = state.activeProcSpellId or state.currentSpellId
    if shown then
        local text = string.format(L("CURRENT_RECOMMENDATION"), getSpellNameSafe(shown))
        if state.activeProcSpellId then
            text = text .. " [Proc]"
        end
        table.insert(lines, text)
    else
        table.insert(lines, string.format(L("CURRENT_RECOMMENDATION"), L("CURRENT_NONE")))
    end

    if state.previewSpellId and state.previewColorIndex then
        local markerName = state.previewMarkerIndex and getMarkerName(state.previewMarkerIndex) or "Auto"
        local previewLine = string.format(L("PREVIEW_SPELL"), getSpellNameSafe(state.previewSpellId))
            .. " / " .. getColorName(state.previewColorIndex) .. " + " .. markerName
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
        if overrideColorIndex and not state.activeProcSpellId and not state.previewSpellId then
            square:SetBackdropColor(getReservedColor(overrideColorIndex))
        else
            square:SetBackdropColor(getPaletteColor(displayedColorIndex))
        end
        square:SetAlpha(1)
        if settings.showMarker then
            markerDot:SetBackdropColor(getMarkerColor(displayedMarkerIndex or 1))
            markerDot:Show()
        else
            markerDot:Hide()
        end
        if state.previewSpellId then
            label:SetText(string.format(L("PREVIEW_SPELL"), getSpellNameSafe(displayedSpellId)))
        else
            label:SetText(getSpellNameSafe(displayedSpellId))
        end
    elseif displayedSpellId then
        square:SetBackdropColor(0.2, 0.2, 0.2, 1)
        square:SetAlpha(1)
        markerDot:Hide()
        label:SetText(string.format(L("UNASSIGNED_SPELL"), getSpellNameSafe(displayedSpellId)))
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
            label:SetText(string.format(L("PREVIEW_SPELL"), getSpellNameSafe(state.currentSpellId)))
        else
            label:SetText(L("PREVIEW_LABEL"))
        end
    else
        square:SetBackdropColor(0.25, 0.25, 0.25, 0.45)
        square:SetAlpha(unlockedPreview and 1 or 0)
        markerDot:Hide()
        label:SetText(L("MOVE_LABEL"))
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

local function refreshVisibility()
    refreshPrimaryVisibility()
    refreshDefenseBox()
    updateCurrentSpellText()
end

local function updateSpellState()
    local nextSpellId = getCurrentRecommendedSpellId()
    state.currentCastState, state.currentCastSpellId = getCurrentCastState()
    if nextSpellId and nextSpellId ~= state.currentSpellId then
        rememberRecommendedSpell(nextSpellId)
    end
    state.currentSpellId = nextSpellId

    local procEntry = getActiveProcEntry()
    state.activeProcSpellId = procEntry and procEntry.spellId or nil

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

local function createSavedMappingRow(parent, rowIndex, layout)
    local row = CreateFrame("Frame", addonName .. "SavedRow" .. rowIndex, parent)
    row:SetSize(layout.listWidth, MAPPING_ROW_HEIGHT)

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
    row.spellText:SetWidth(layout.spellTextWidth)
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
    row.colorText:SetWidth(layout.colorTextWidth)
    row.colorText:SetJustifyH("LEFT")
    row.colorText:SetWordWrap(false)
    row.colorText:SetTextColor(0.92, 0.92, 0.92, 1)
    row.colorText:SetShadowOffset(1, -1)
    row.colorText:SetShadowColor(0, 0, 0, 0.75)
    row.colorText:SetText("Color")

    row.glowCheck = CreateFrame("CheckButton", addonName .. "SavedRowGlow" .. rowIndex, row, "UICheckButtonTemplate")
    row.glowCheck:SetSize(24, 24)
    row.glowCheck:SetPoint("LEFT", row, "LEFT", layout.glowLeft, 0)
    row.glowCheck.text:SetText("")

    row.previewButton = CreateFrame("Button", addonName .. "SavedRowShow" .. rowIndex, row, "GameMenuButtonTemplate")
    row.previewButton:SetSize(layout.previewButtonWidth, 20)
    row.previewButton:SetPoint("LEFT", row, "LEFT", layout.previewButtonLeft, 0)
    row.previewButton:SetText("Show")

    row.deleteButton = CreateFrame("Button", addonName .. "SavedRowDelete" .. rowIndex, row, "GameMenuButtonTemplate")
    row.deleteButton:SetSize(layout.deleteButtonWidth, 20)
    row.deleteButton:SetPoint("LEFT", row, "LEFT", layout.deleteButtonLeft, 0)
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
            lockToggleButton:SetText(L("UNLOCK"))
        else
            lockToggleButton:SetText(L("LOCK"))
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

local function createOverrideControl(parent, labelText, stateKey, holderWidth, dropdownWidth)
    controlId = controlId + 1
    holderWidth = holderWidth or 320
    dropdownWidth = dropdownWidth or 120

    local holder = CreateFrame("Frame", addonName .. "OverrideRow" .. controlId, parent)
    holder:SetSize(holderWidth, 28)

    holder.check = CreateFrame("CheckButton", addonName .. "OverrideCheck" .. controlId, holder, "UICheckButtonTemplate")
    holder.check:SetPoint("LEFT", 0, 0)
    holder.check.text:SetText(labelText)
    holder.check.text:SetWidth(holderWidth - dropdownWidth - 54)
    holder.check.text:SetJustifyH("LEFT")
    holder.check:SetScript("OnClick", function(self)
        local overrideConfig = getOverrideConfig(stateKey)
        overrideConfig.enabled = self:GetChecked() and true or false
        updateEditorControls()
        refreshVisibility()
    end)

    local dropdownOffset = math.max(145, holderWidth - dropdownWidth - 28)
    holder.dropdown = CreateFrame("Frame", addonName .. "OverrideDropdown" .. controlId, holder, "UIDropDownMenuTemplate")
    holder.dropdown:SetPoint("LEFT", holder, "LEFT", dropdownOffset, -2)
    UIDropDownMenu_SetWidth(holder.dropdown, dropdownWidth)
    UIDropDownMenu_JustifyText(holder.dropdown, "LEFT")
    initializeOverrideDropdown(holder.dropdown, stateKey)

    return holder
end

local function parseInteger(text)
    return Logic.parseInteger(text)
end

local function refreshAllEditorViews()
    syncPlacementControls()
    updateEditorControls()
    updateMappingRows()
    if updateDefenseRows then
        updateDefenseRows()
    end
    if updateProcRows then
        updateProcRows()
    end
end

local function resetToDefaults()
    local settings = db()
    settings.locale = defaults.locale
    settings.point = defaults.point
    settings.relativePoint = defaults.relativePoint
    settings.x = defaults.x
    settings.y = defaults.y
    settings.size = defaults.size
    settings.locked = defaults.locked
    settings.showMarker = defaults.showMarker
    settings.showMinimapButton = defaults.showMinimapButton
    settings.minimapAngle = defaults.minimapAngle
    settings.overrides = copyDefaultOverrides()
    settings.mappings = {}
    settings.defense = {
        enabled = defaults.defense.enabled,
        locked = defaults.defense.locked,
        size = defaults.defense.size,
        point = defaults.defense.point,
        relativePoint = defaults.defense.relativePoint,
        x = defaults.defense.x,
        y = defaults.defense.y,
        entries = {},
    }
    settings.procs = {entries = {}}
    settings.cooldownBox = nil

    state.editorSpellId = nil
    state.editorColorIndex = nil
    state.editorMoveGlow = false
    state.defenseEditorSpellId = nil
    state.defenseEditorColorIndex = 2
    state.procEditorSpellId = nil
    state.procEditorColorIndex = 2
    state.searchText = ""
    setPreview(nil)

    if searchInput then
        searchInput:SetText("")
    end

    applySize()
    applyPosition()
    applyDefenseSize()
    applyDefensePosition()
    sanitizeSettings()
    updateSpellState()
    refreshAllEditorViews()
    if refreshOptionsLocale then
        refreshOptionsLocale()
    end
    refreshVisibility()
    refreshMinimapButton()
end

local function createMainOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24
    local listWidth = contentWidth - 20
    local spellTextWidth = 300
    local colorTextWidth = 150
    local previewButtonWidth = 64
    local deleteButtonWidth = 64
    local deleteButtonLeft = listWidth - deleteButtonWidth - 8
    local previewButtonLeft = deleteButtonLeft - previewButtonWidth - 8
    local glowLeft = previewButtonLeft - 40

    optionsLayout = {
        listWidth = listWidth,
        spellTextWidth = spellTextWidth,
        colorTextWidth = colorTextWidth,
        glowLeft = glowLeft,
        previewButtonLeft = previewButtonLeft,
        deleteButtonLeft = deleteButtonLeft,
        previewButtonWidth = previewButtonWidth,
        deleteButtonWidth = deleteButtonWidth,
        colorHeaderX = 340,
        glowHeaderX = glowLeft + 4,
        showHeaderX = previewButtonLeft + 8,
        deleteHeaderX = deleteButtonLeft + 4,
    }

    local leftTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 8, -8)
    leftTitle:SetText(L("MAIN_TITLE"))
    frame.mainTitle = leftTitle

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("MAIN_SUBTITLE"))
    frame.mainSubtitle = subtitle

    currentSpellText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentSpellText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    currentSpellText:SetWidth(contentWidth)
    currentSpellText:SetHeight(24)
    currentSpellText:SetJustifyH("LEFT")
    currentSpellText:SetWordWrap(false)
    currentSpellText:SetText(string.format(L("CURRENT_RECOMMENDATION"), L("CURRENT_NONE")))

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", currentSpellText, "BOTTOMLEFT", 0, -10)
    editorLabel:SetText(L("QUICK_EDITOR"))
    frame.editorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 44)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -6)

    local searchHolder = createSearchInput(editorRow, 110)
    searchHolder:SetPoint("LEFT", 0, -2)
    searchInput = searchHolder.input

    editorSpellDropdown = CreateFrame("Frame", addonName .. "EditorSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    editorSpellDropdown:SetPoint("LEFT", searchHolder, "RIGHT", -10, -8)
    UIDropDownMenu_SetWidth(editorSpellDropdown, 260)
    UIDropDownMenu_JustifyText(editorSpellDropdown, "LEFT")
    initializeSpellDropdown(editorSpellDropdown)

    editorColorDropdown = CreateFrame("Frame", addonName .. "EditorColorDropdown", editorRow, "UIDropDownMenuTemplate")
    editorColorDropdown:SetPoint("LEFT", editorSpellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(editorColorDropdown, 140)
    UIDropDownMenu_JustifyText(editorColorDropdown, "LEFT")
    initializeColorDropdown(editorColorDropdown)

    editorActionButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorActionButton:SetSize(76, 22)
    editorActionButton:SetPoint("LEFT", editorColorDropdown, "RIGHT", -2, 0)
    editorActionButton:SetText(L("ADD"))
    editorActionButton:SetScript("OnClick", function()
        saveEditorMapping()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    editorPreviewButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    editorPreviewButton:SetSize(76, 22)
    editorPreviewButton:SetPoint("LEFT", editorActionButton, "RIGHT", 8, 0)
    editorPreviewButton:SetText(L("SHOW"))
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
    searchHint:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -4)
    searchHint:SetWidth(contentWidth)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetText(L("SEARCH_HINT"))
    frame.searchHint = searchHint

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", searchHint, "BOTTOMLEFT", 0, -10)
    listLabel:SetText(L("SAVED_MAPPINGS"))
    frame.listLabel = listLabel

    local listHeaders = CreateFrame("Frame", nil, frame)
    listHeaders:SetSize(listWidth, 18)
    listHeaders:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -10)

    local spellHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellHeader:SetPoint("LEFT", 32, 0)
    spellHeader:SetText("Spell")

    local colorHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorHeader:SetPoint("LEFT", optionsLayout.colorHeaderX, 0)
    colorHeader:SetText("Color")

    local glowHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowHeader:SetPoint("LEFT", optionsLayout.glowHeaderX, 0)
    glowHeader:SetText("Glow")

    local showHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showHeader:SetPoint("LEFT", optionsLayout.showHeaderX, 0)
    showHeader:SetText("Show")

    local deleteHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deleteHeader:SetPoint("LEFT", optionsLayout.deleteHeaderX, 0)
    deleteHeader:SetText("Delete")

    mappingScrollFrame = CreateFrame("ScrollFrame", addonName .. "MappingsScrollFrame", frame, "FauxScrollFrameTemplate")
    mappingScrollFrame:SetPoint("TOPLEFT", listHeaders, "BOTTOMLEFT", 0, -4)
    mappingScrollFrame:SetSize(listWidth, VISIBLE_MAPPING_ROWS * MAPPING_ROW_HEIGHT)
    mappingScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, MAPPING_ROW_HEIGHT, updateMappingRows)
    end)

    for rowIndex = 1, VISIBLE_MAPPING_ROWS do
        local row = createSavedMappingRow(frame, rowIndex, optionsLayout)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", mappingRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        mappingRows[rowIndex] = row
    end

    emptyMappingsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMappingsText:SetPoint("TOPLEFT", mappingScrollFrame, "TOPLEFT", 10, -40)
    emptyMappingsText:SetWidth(listWidth - 40)
    emptyMappingsText:SetJustifyH("LEFT")
    emptyMappingsText:SetText(L("NO_MAPPINGS"))
    emptyMappingsText:Hide()

    local overridesColumnWidth = math.floor((contentWidth - 20) * 0.58)
    local placementColumnWidth = contentWidth - overridesColumnWidth - 20

    local overridesColumn = CreateFrame("Frame", nil, frame)
    overridesColumn:SetSize(overridesColumnWidth, 150)
    overridesColumn:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 0, -12)

    local overridesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overridesLabel:SetPoint("TOPLEFT", overridesColumn, "TOPLEFT", 0, 0)
    overridesLabel:SetText(L("STATE_OVERRIDES"))
    frame.overridesLabel = overridesLabel

    local overridesHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overridesHint:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -4)
    overridesHint:SetWidth(overridesColumnWidth - 10)
    overridesHint:SetJustifyH("LEFT")
    overridesHint:SetText(L("STATE_OVERRIDES_HINT"))
    frame.overridesHint = overridesHint

    local castingOverrideRow = createOverrideControl(overridesColumn, L("CASTING"), "casting", overridesColumnWidth, 160)
    castingOverrideRow:SetPoint("TOPLEFT", overridesHint, "BOTTOMLEFT", 0, -10)
    castingOverrideCheck = castingOverrideRow.check
    castingOverrideDropdown = castingOverrideRow.dropdown

    local channelingOverrideRow = createOverrideControl(overridesColumn, L("CHANNELING"), "channeling", overridesColumnWidth, 160)
    channelingOverrideRow:SetPoint("TOPLEFT", castingOverrideRow, "BOTTOMLEFT", 0, -6)
    channelingOverrideCheck = channelingOverrideRow.check
    channelingOverrideDropdown = channelingOverrideRow.dropdown

    local empowerOverrideRow = createOverrideControl(overridesColumn, L("EMPOWER"), "empower", overridesColumnWidth, 160)
    empowerOverrideRow:SetPoint("TOPLEFT", channelingOverrideRow, "BOTTOMLEFT", 0, -6)
    empowerOverrideCheck = empowerOverrideRow.check
    empowerOverrideDropdown = empowerOverrideRow.dropdown

    local placementColumn = CreateFrame("Frame", nil, frame)
    placementColumn:SetSize(placementColumnWidth, 150)
    placementColumn:SetPoint("TOPLEFT", overridesColumn, "TOPRIGHT", 20, 0)

    local placementLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placementLabel:SetPoint("TOPLEFT", placementColumn, "TOPLEFT", 0, 0)
    placementLabel:SetText(L("INDICATOR"))
    frame.placementLabel = placementLabel

    local sizeHolder = createPlacementInput(placementColumn, L("SIZE"), 72, function(text)
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

    local xHolder = createPlacementInput(placementColumn, "X", 72, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().x = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 14, 0)
    xInput = xHolder.input

    local yHolder = createPlacementInput(placementColumn, "Y", 72, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().y = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 14, 0)
    yInput = yHolder.input

    markerToggleCheck = CreateFrame("CheckButton", addonName .. "MarkerToggle", placementColumn, "UICheckButtonTemplate")
    markerToggleCheck:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -12)
    markerToggleCheck.text:SetText(L("SHOW_MARKER"))
    markerToggleCheck:SetScript("OnClick", function(self)
        db().showMarker = self:GetChecked() and true or false
        refreshVisibility()
    end)

    lockToggleButton = CreateFrame("Button", nil, placementColumn, "GameMenuButtonTemplate")
    lockToggleButton:SetPoint("TOPLEFT", markerToggleCheck, "BOTTOMLEFT", 4, -10)
    lockToggleButton:SetSize(150, 24)
    lockToggleButton:SetText(L("UNLOCK"))
    lockToggleButton:SetScript("OnClick", function()
        db().locked = not db().locked
        updateEditorControls()
        refreshVisibility()
    end)

    local languageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    languageLabel:SetPoint("TOPLEFT", lockToggleButton, "BOTTOMLEFT", 0, -14)
    languageLabel:SetText(L("LANGUAGE"))
    frame.languageLabel = languageLabel

    local langEn = CreateFrame("Button", nil, placementColumn, "GameMenuButtonTemplate")
    langEn:SetSize(80, 22)
    langEn:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", 0, -6)
    langEn:SetText(L("LANG_EN"))
    langEn:SetScript("OnClick", function()
        db().locale = "en"
        refreshOptionsLocale()
        refreshAllEditorViews()
        refreshVisibility()
    end)

    local langKo = CreateFrame("Button", nil, placementColumn, "GameMenuButtonTemplate")
    langKo:SetSize(80, 22)
    langKo:SetPoint("LEFT", langEn, "RIGHT", 8, 0)
    langKo:SetText(L("LANG_KO"))
    langKo:SetScript("OnClick", function()
        db().locale = "ko"
        refreshOptionsLocale()
        refreshAllEditorViews()
        refreshVisibility()
    end)
    frame.langEn = langEn
    frame.langKo = langKo
end

local function upsertPriorityEntry(listKey, spellId, colorIndex)
    if not spellId or not colorIndex then
        return
    end
    local root = db()[listKey]
    if type(root) ~= "table" then
        db()[listKey] = {entries = {}}
        root = db()[listKey]
    end
    root.entries = type(root.entries) == "table" and root.entries or {}
    for _, entry in ipairs(root.entries) do
        if entry.spellId == spellId then
            entry.colorIndex = colorIndex
            entry.enabled = true
            sanitizeSettings()
            return
        end
    end
    table.insert(root.entries, {
        spellId = spellId,
        colorIndex = colorIndex,
        enabled = true,
    })
    sanitizeSettings()
end

local function createPriorityRow(parent, _)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(math.max((parent:GetWidth() or 700) - 24, 600), PRIORITY_ROW_HEIGHT)

    row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.enable:SetPoint("LEFT", 0, 0)
    row.enable:SetSize(24, 24)

    row.priorityText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.priorityText:SetPoint("LEFT", row.enable, "RIGHT", 2, 0)
    row.priorityText:SetWidth(24)

    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.spellText:SetPoint("LEFT", row.priorityText, "RIGHT", 6, 0)
    row.spellText:SetWidth(220)
    row.spellText:SetJustifyH("LEFT")

    row.swatch = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.swatch:SetSize(16, 16)
    row.swatch:SetPoint("LEFT", row.spellText, "RIGHT", 8, 0)
    row.swatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })

    row.colorText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.colorText:SetPoint("LEFT", row.swatch, "RIGHT", 6, 0)
    row.colorText:SetWidth(90)

    row.upButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    row.upButton:SetSize(44, 20)
    row.upButton:SetPoint("LEFT", row.colorText, "RIGHT", 8, 0)
    row.upButton:SetText(L("UP"))

    row.downButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    row.downButton:SetSize(50, 20)
    row.downButton:SetPoint("LEFT", row.upButton, "RIGHT", 4, 0)
    row.downButton:SetText(L("DOWN"))

    row.deleteButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    row.deleteButton:SetSize(56, 20)
    row.deleteButton:SetPoint("LEFT", row.downButton, "RIGHT", 4, 0)
    row.deleteButton:SetText(L("DELETE"))

    row:Hide()
    return row
end

local function bindPriorityRows(rows, scrollFrame, emptyText, listKey, refreshFn)
    local root = db()[listKey]
    local entries = root and root.entries or {}
    local total = #entries
    local offset = 0
    if scrollFrame then
        FauxScrollFrame_Update(scrollFrame, total, PRIORITY_VISIBLE_ROWS, PRIORITY_ROW_HEIGHT)
        offset = FauxScrollFrame_GetOffset(scrollFrame)
    end

    for rowIndex = 1, PRIORITY_VISIBLE_ROWS do
        local row = rows[rowIndex]
        local entry = entries[offset + rowIndex]
        if entry then
            local entryIndex = offset + rowIndex
            row:Show()
            row.enable:SetChecked(entry.enabled ~= false)
            row.priorityText:SetText(tostring(entryIndex))
            row.spellText:SetText(getSpellNameSafe(entry.spellId))
            row.colorText:SetText(getColorName(entry.colorIndex))
            row.swatch:SetBackdropColor(getPaletteColor(entry.colorIndex))
            row.upButton:SetEnabled(entryIndex > 1)
            row.downButton:SetEnabled(entryIndex < total)
            row.enable:SetScript("OnClick", function(self)
                entry.enabled = self:GetChecked() and true or false
                refreshFn()
                refreshVisibility()
            end)
            row.upButton:SetScript("OnClick", function()
                Logic.movePriorityEntry(entries, entryIndex, -1)
                refreshFn()
                refreshVisibility()
            end)
            row.downButton:SetScript("OnClick", function()
                Logic.movePriorityEntry(entries, entryIndex, 1)
                refreshFn()
                refreshVisibility()
            end)
            row.deleteButton:SetScript("OnClick", function()
                table.remove(entries, entryIndex)
                refreshFn()
                refreshVisibility()
            end)
        else
            row:Hide()
        end
    end

    if emptyText then
        if total == 0 then
            emptyText:Show()
        else
            emptyText:Hide()
        end
    end
end

local function createDefenseOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(L("DEFENSE_TITLE"))
    frame.defenseTitle = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("DEFENSE_SUBTITLE"))
    frame.defenseSubtitle = subtitle

    local enableCheck = CreateFrame("CheckButton", addonName .. "DefenseEnable", frame, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    enableCheck.text:SetText(L("DEFENSE_ENABLE"))
    enableCheck:SetScript("OnClick", function(self)
        db().defense.enabled = self:GetChecked() and true or false
        refreshDefenseBox()
    end)
    frame.defenseEnable = enableCheck

    local lockCheck = CreateFrame("CheckButton", addonName .. "DefenseLock", frame, "UICheckButtonTemplate")
    lockCheck:SetPoint("LEFT", enableCheck, "RIGHT", 160, 0)
    lockCheck.text:SetText(L("DEFENSE_LOCKED"))
    lockCheck:SetScript("OnClick", function(self)
        db().defense.locked = self:GetChecked() and true or false
        refreshDefenseBox()
    end)
    frame.defenseLock = lockCheck

    local sizeHolder = createPlacementInput(frame, L("DEFENSE_SIZE"), 72, function(text)
        local value = parseInteger(text)
        if not value then
            return
        end
        db().defense.size = clamp(value, 24, 300)
        applyDefenseSize()
        refreshDefenseBox()
    end)
    sizeHolder:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -8)
    frame.defenseSizeInput = sizeHolder.input

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -12)
    editorLabel:SetText(L("DEFENSE_ADD"))
    frame.defenseEditorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 40)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -6)

    local spellDropdown = CreateFrame("Frame", addonName .. "DefenseSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    spellDropdown:SetPoint("LEFT", -12, -4)
    UIDropDownMenu_SetWidth(spellDropdown, 280)
    UIDropDownMenu_JustifyText(spellDropdown, "LEFT")
    UIDropDownMenu_Initialize(spellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells()) do
            info.text = spellInfo.name
            info.value = spellInfo.spellId
            info.func = function()
                state.defenseEditorSpellId = spellInfo.spellId
                UIDropDownMenu_SetSelectedValue(spellDropdown, spellInfo.spellId)
                UIDropDownMenu_SetText(spellDropdown, spellInfo.name)
            end
            info.checked = state.defenseEditorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local colorDropdown = CreateFrame("Frame", addonName .. "DefenseColorDropdown", editorRow, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("LEFT", spellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(colorDropdown, 140)
    UIDropDownMenu_Initialize(colorDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for index = 2, #COLOR_PALETTE do
            info.text = COLOR_PALETTE[index].name
            info.value = index
            info.func = function()
                state.defenseEditorColorIndex = index
                UIDropDownMenu_SetSelectedValue(colorDropdown, index)
                UIDropDownMenu_SetText(colorDropdown, COLOR_PALETTE[index].name)
            end
            info.checked = state.defenseEditorColorIndex == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(colorDropdown, state.defenseEditorColorIndex or 2)
    UIDropDownMenu_SetText(colorDropdown, getColorName(state.defenseEditorColorIndex or 2))

    local addButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addButton:SetSize(90, 22)
    addButton:SetPoint("LEFT", colorDropdown, "RIGHT", 0, 0)
    addButton:SetText(L("ADD"))
    addButton:SetScript("OnClick", function()
        upsertPriorityEntry("defense", state.defenseEditorSpellId, state.defenseEditorColorIndex or 2)
        updateDefenseRows()
        refreshDefenseBox()
    end)
    frame.defenseAddButton = addButton

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -12)
    listLabel:SetText(L("DEFENSE_LIST"))
    frame.defenseListLabel = listLabel

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(contentWidth)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("DEFENSE_HINT"))
    frame.defenseHint = hint

    defenseScrollFrame = CreateFrame("ScrollFrame", addonName .. "DefenseScroll", frame, "FauxScrollFrameTemplate")
    defenseScrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    defenseScrollFrame:SetSize(contentWidth - 10, PRIORITY_VISIBLE_ROWS * PRIORITY_ROW_HEIGHT)
    defenseScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PRIORITY_ROW_HEIGHT, updateDefenseRows)
    end)

    for rowIndex = 1, PRIORITY_VISIBLE_ROWS do
        local row = createPriorityRow(frame, rowIndex)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", defenseScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", defenseRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        defenseRows[rowIndex] = row
    end

    emptyDefenseText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyDefenseText:SetPoint("TOPLEFT", defenseScrollFrame, "TOPLEFT", 8, -30)
    emptyDefenseText:SetWidth(contentWidth - 40)
    emptyDefenseText:SetJustifyH("LEFT")
    emptyDefenseText:SetText(L("DEFENSE_EMPTY"))
    emptyDefenseText:Hide()

    updateDefenseRows = function()
        if frame.defenseEnable then
            frame.defenseEnable:SetChecked(db().defense.enabled ~= false)
            frame.defenseLock:SetChecked(db().defense.locked ~= false)
            if frame.defenseSizeInput then
                frame.defenseSizeInput:SetText(tostring(db().defense.size or defaults.defense.size))
            end
        end
        bindPriorityRows(defenseRows, defenseScrollFrame, emptyDefenseText, "defense", updateDefenseRows)
    end
end

local function createProcOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(L("PROCS_TITLE"))
    frame.procTitle = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("PROCS_SUBTITLE"))
    frame.procSubtitle = subtitle

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    editorLabel:SetText(L("PROCS_ADD"))
    frame.procEditorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 40)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -6)

    local spellDropdown = CreateFrame("Frame", addonName .. "ProcSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    spellDropdown:SetPoint("LEFT", -12, -4)
    UIDropDownMenu_SetWidth(spellDropdown, 280)
    UIDropDownMenu_Initialize(spellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells()) do
            info.text = spellInfo.name
            info.value = spellInfo.spellId
            info.func = function()
                state.procEditorSpellId = spellInfo.spellId
                UIDropDownMenu_SetSelectedValue(spellDropdown, spellInfo.spellId)
                UIDropDownMenu_SetText(spellDropdown, spellInfo.name)
            end
            info.checked = state.procEditorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local colorDropdown = CreateFrame("Frame", addonName .. "ProcColorDropdown", editorRow, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("LEFT", spellDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(colorDropdown, 140)
    UIDropDownMenu_Initialize(colorDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for index = 2, #COLOR_PALETTE do
            info.text = COLOR_PALETTE[index].name
            info.value = index
            info.func = function()
                state.procEditorColorIndex = index
                UIDropDownMenu_SetSelectedValue(colorDropdown, index)
                UIDropDownMenu_SetText(colorDropdown, COLOR_PALETTE[index].name)
            end
            info.checked = state.procEditorColorIndex == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(colorDropdown, state.procEditorColorIndex or 2)
    UIDropDownMenu_SetText(colorDropdown, getColorName(state.procEditorColorIndex or 2))

    local addButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addButton:SetSize(90, 22)
    addButton:SetPoint("LEFT", colorDropdown, "RIGHT", 0, 0)
    addButton:SetText(L("ADD"))
    addButton:SetScript("OnClick", function()
        upsertPriorityEntry("procs", state.procEditorSpellId, state.procEditorColorIndex or 2)
        updateProcRows()
        updateSpellState()
    end)
    frame.procAddButton = addButton

    local suggestButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    suggestButton:SetSize(170, 22)
    suggestButton:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -10)
    suggestButton:SetText(L("PROCS_SUGGEST"))
    suggestButton:SetScript("OnClick", function()
        refreshAvailableSpells()
        local known = {}
        for _, entry in ipairs(db().procs.entries or {}) do
            known[entry.spellId] = true
        end
        local added = 0
        for _, spellInfo in ipairs(state.availableSpells) do
            if isProcActive(spellInfo.spellId) and not known[spellInfo.spellId] then
                upsertPriorityEntry("procs", spellInfo.spellId, state.procEditorColorIndex or 2)
                known[spellInfo.spellId] = true
                added = added + 1
            end
        end
        if added == 0 then
            print("|cff33ff99Shinkili|r " .. L("PROCS_SUGGEST_NONE"))
        else
            print("|cff33ff99Shinkili|r " .. string.format(L("PROCS_SUGGEST_ADDED"), added))
        end
        updateProcRows()
        updateSpellState()
    end)
    frame.procSuggestButton = suggestButton

    local suggestHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suggestHint:SetPoint("LEFT", suggestButton, "RIGHT", 10, 0)
    suggestHint:SetWidth(contentWidth - 200)
    suggestHint:SetJustifyH("LEFT")
    suggestHint:SetText(L("PROCS_SUGGEST_HINT"))
    frame.procSuggestHint = suggestHint

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", suggestButton, "BOTTOMLEFT", 0, -14)
    listLabel:SetText(L("PROCS_LIST"))
    frame.procListLabel = listLabel

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(contentWidth)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("PROCS_HINT"))
    frame.procHint = hint

    procScrollFrame = CreateFrame("ScrollFrame", addonName .. "ProcScroll", frame, "FauxScrollFrameTemplate")
    procScrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    procScrollFrame:SetSize(contentWidth - 10, PRIORITY_VISIBLE_ROWS * PRIORITY_ROW_HEIGHT)
    procScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PRIORITY_ROW_HEIGHT, updateProcRows)
    end)

    for rowIndex = 1, PRIORITY_VISIBLE_ROWS do
        local row = createPriorityRow(frame, rowIndex)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", procScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", procRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        procRows[rowIndex] = row
    end

    emptyProcText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyProcText:SetPoint("TOPLEFT", procScrollFrame, "TOPLEFT", 8, -30)
    emptyProcText:SetWidth(contentWidth - 40)
    emptyProcText:SetJustifyH("LEFT")
    emptyProcText:SetText(L("PROCS_EMPTY"))
    emptyProcText:Hide()

    updateProcRows = function()
        bindPriorityRows(procRows, procScrollFrame, emptyProcText, "procs", updateProcRows)
    end
end

selectOptionsTab = function(tabKey)
    state.optionsTab = tabKey
    for key, panel in pairs(optionsPanels) do
        if key == tabKey then
            panel:Show()
        else
            panel:Hide()
        end
    end
    for key, button in pairs(optionsTabs) do
        if key == tabKey then
            button:Disable()
        else
            button:Enable()
        end
    end
    if tabKey == "defense" and updateDefenseRows then
        updateDefenseRows()
    elseif tabKey == "procs" and updateProcRows then
        updateProcRows()
    elseif tabKey == "main" then
        updateMappingRows()
        updateEditorControls()
    end
end

refreshOptionsLocale = function()
    if not options then
        return
    end
    options.TitleText:SetText(L("ADDON_NAME"))
    if optionsTabs.main then
        optionsTabs.main:SetText(L("TAB_MAIN"))
        optionsTabs.defense:SetText(L("TAB_DEFENSE"))
        optionsTabs.procs:SetText(L("TAB_PROCS"))
    end
    if options.resetButton then
        options.resetButton:SetText(L("RESET_DEFAULTS"))
    end
    if options.closeButton then
        options.closeButton:SetText(L("CLOSE"))
    end

    local main = optionsPanels.main
    if main then
        if main.mainTitle then main.mainTitle:SetText(L("MAIN_TITLE")) end
        if main.mainSubtitle then main.mainSubtitle:SetText(L("MAIN_SUBTITLE")) end
        if main.editorLabel then main.editorLabel:SetText(L("QUICK_EDITOR")) end
        if main.searchHint then main.searchHint:SetText(L("SEARCH_HINT")) end
        if main.listLabel then main.listLabel:SetText(L("SAVED_MAPPINGS")) end
        if main.overridesLabel then main.overridesLabel:SetText(L("STATE_OVERRIDES")) end
        if main.overridesHint then main.overridesHint:SetText(L("STATE_OVERRIDES_HINT")) end
        if main.placementLabel then main.placementLabel:SetText(L("INDICATOR")) end
        if main.languageLabel then main.languageLabel:SetText(L("LANGUAGE")) end
        if main.langEn then main.langEn:SetText(L("LANG_EN")) end
        if main.langKo then main.langKo:SetText(L("LANG_KO")) end
        if markerToggleCheck and markerToggleCheck.text then
            markerToggleCheck.text:SetText(L("SHOW_MARKER"))
        end
        if emptyMappingsText then
            emptyMappingsText:SetText(L("NO_MAPPINGS"))
        end
    end

    local defense = optionsPanels.defense
    if defense then
        if defense.defenseTitle then defense.defenseTitle:SetText(L("DEFENSE_TITLE")) end
        if defense.defenseSubtitle then defense.defenseSubtitle:SetText(L("DEFENSE_SUBTITLE")) end
        if defense.defenseEnable and defense.defenseEnable.text then
            defense.defenseEnable.text:SetText(L("DEFENSE_ENABLE"))
        end
        if defense.defenseLock and defense.defenseLock.text then
            defense.defenseLock.text:SetText(L("DEFENSE_LOCKED"))
        end
        if defense.defenseEditorLabel then defense.defenseEditorLabel:SetText(L("DEFENSE_ADD")) end
        if defense.defenseListLabel then defense.defenseListLabel:SetText(L("DEFENSE_LIST")) end
        if defense.defenseHint then defense.defenseHint:SetText(L("DEFENSE_HINT")) end
        if defense.defenseAddButton then defense.defenseAddButton:SetText(L("ADD")) end
        if emptyDefenseText then emptyDefenseText:SetText(L("DEFENSE_EMPTY")) end
    end

    local procs = optionsPanels.procs
    if procs then
        if procs.procTitle then procs.procTitle:SetText(L("PROCS_TITLE")) end
        if procs.procSubtitle then procs.procSubtitle:SetText(L("PROCS_SUBTITLE")) end
        if procs.procEditorLabel then procs.procEditorLabel:SetText(L("PROCS_ADD")) end
        if procs.procListLabel then procs.procListLabel:SetText(L("PROCS_LIST")) end
        if procs.procHint then procs.procHint:SetText(L("PROCS_HINT")) end
        if procs.procAddButton then procs.procAddButton:SetText(L("ADD")) end
        if procs.procSuggestButton then procs.procSuggestButton:SetText(L("PROCS_SUGGEST")) end
        if procs.procSuggestHint then procs.procSuggestHint:SetText(L("PROCS_SUGGEST_HINT")) end
        if emptyProcText then emptyProcText:SetText(L("PROCS_EMPTY")) end
    end

    updateCurrentSpellText()
end

local function createOptionsFooter(frame)
    local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", -16, 14)
    resetButton:SetSize(140, 24)
    resetButton:SetText(L("RESET_DEFAULTS"))
    resetButton:SetScript("OnClick", resetToDefaults)
    frame.resetButton = resetButton

    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetPoint("RIGHT", resetButton, "LEFT", -8, 0)
    closeButton:SetSize(110, 24)
    closeButton:SetText(L("CLOSE"))
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.closeButton = closeButton
end

local function attachOptionsLifecycle(frame)
    frame:SetScript("OnShow", function()
        state.optionsOpen = true
        refreshAvailableSpells()
        sanitizeSettings()
        syncEditorSelection()
        updateSpellState()
        refreshOptionsLocale()
        refreshAllEditorViews()
        selectOptionsTab(state.optionsTab or "main")
        refreshVisibility()
    end)

    frame:SetScript("OnHide", function()
        state.optionsOpen = false
        setPreview(nil)
        refreshVisibility()
    end)
end

local function createOptionsWindow()
    options = CreateFrame("Frame", "ShinkiliOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    options:SetSize(OPTIONS_WIDTH, OPTIONS_HEIGHT)
    options:SetPoint("CENTER")
    options:SetMovable(true)
    options:SetClampedToScreen(true)
    options:EnableMouse(true)
    options:RegisterForDrag("LeftButton")
    options:SetScript("OnDragStart", options.StartMoving)
    options:SetScript("OnDragStop", options.StopMovingOrSizing)
    options:Hide()

    options.TitleText:SetText(L("ADDON_NAME"))
    if options.CloseButton then
        options.CloseButton:SetScript("OnClick", function()
            options:Hide()
        end)
    end

    local tabY = -28
    local tabWidth = 100
    local function makeTab(key, labelKey, x)
        local button = CreateFrame("Button", nil, options, "GameMenuButtonTemplate")
        button:SetSize(tabWidth, 22)
        button:SetPoint("TOPLEFT", 14 + x, tabY)
        button:SetText(L(labelKey))
        button:SetScript("OnClick", function()
            selectOptionsTab(key)
        end)
        optionsTabs[key] = button
        return button
    end
    makeTab("main", "TAB_MAIN", 0)
    makeTab("defense", "TAB_DEFENSE", tabWidth + 6)
    makeTab("procs", "TAB_PROCS", (tabWidth + 6) * 2)

    local panelTop = -56
    local panelHeight = OPTIONS_HEIGHT - 100
    local panelWidth = OPTIONS_WIDTH - 28

    local mainPanel = CreateFrame("Frame", nil, options)
    mainPanel:SetPoint("TOPLEFT", 14, panelTop)
    mainPanel:SetSize(panelWidth, panelHeight)
    createMainOptionsPanel(mainPanel)
    optionsPanels.main = mainPanel

    local defensePanel = CreateFrame("Frame", nil, options)
    defensePanel:SetPoint("TOPLEFT", 14, panelTop)
    defensePanel:SetSize(panelWidth, panelHeight)
    createDefenseOptionsPanel(defensePanel)
    defensePanel:Hide()
    optionsPanels.defense = defensePanel

    local procPanel = CreateFrame("Frame", nil, options)
    procPanel:SetPoint("TOPLEFT", 14, panelTop)
    procPanel:SetSize(panelWidth, panelHeight)
    createProcOptionsPanel(procPanel)
    procPanel:Hide()
    optionsPanels.procs = procPanel

    createOptionsFooter(options)
    attachOptionsLifecycle(options)
    selectOptionsTab("main")
end

local function toggleOptionsWindow()
    if not options then
        createOptionsWindow()
    end
    if options:IsShown() then
        options:Hide()
    else
        options:Show()
    end
end

local function normalizeMinimapAngle(angle)
    local numeric = tonumber(angle)
    if not numeric then
        return defaults.minimapAngle
    end
    numeric = numeric % 360
    if numeric < 0 then
        numeric = numeric + 360
    end
    return numeric
end

local function angleFromDelta(dx, dy)
    -- WoW exposes math.atan2; pure Lua 5.3+ uses math.atan(y, x).
    local atan2 = rawget(math, "atan2")
    if atan2 then
        return atan2(dy, dx)
    end
    return math.atan(dy, dx)
end

local function applyMinimapButtonPosition()
    if not minimapButton or not Minimap then
        return
    end

    local angle = math.rad(normalizeMinimapAngle(db().minimapAngle))
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function createMinimapButton()
    if minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "ShinkiliMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(18, 18)
    background:SetPoint("CENTER", 0, 1)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Signal-square identity (matches main indicator look) without an extra mouse frame.
    local iconBorder = button:CreateTexture(nil, "ARTWORK")
    iconBorder:SetSize(16, 16)
    iconBorder:SetPoint("CENTER", 0, 1)
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconBorder:SetVertexColor(0.05, 0.05, 0.05, 0.95)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    icon:SetVertexColor(0.00, 0.85, 0.25, 1)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", -10, 10)

    button.isDragging = false

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("MINIMAP_TITLE"), 0.2, 1.0, 0.6)
        GameTooltip:AddLine(L("MINIMAP_TOGGLE"), 1, 1, 1)
        GameTooltip:AddLine(L("MINIMAP_DRAG"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("MINIMAP_HIDE"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("MINIMAP_RESTORE"), 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:LockHighlight()
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            if not Minimap then
                return
            end
            local scale = Minimap:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            cursorX = cursorX / scale
            cursorY = cursorY / scale
            local centerX, centerY = Minimap:GetCenter()
            if not centerX or not centerY then
                return
            end
            db().minimapAngle = normalizeMinimapAngle(math.deg(angleFromDelta(cursorX - centerX, cursorY - centerY)))
            applyMinimapButtonPosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        applyMinimapButtonPosition()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                self.isDragging = false
            end)
        else
            self.isDragging = false
        end
    end)

    button:SetScript("OnClick", function(self, mouseButton)
        if self.isDragging then
            return
        end
        if mouseButton == "LeftButton" then
            toggleOptionsWindow()
            return
        end
        if mouseButton == "RightButton" then
            db().showMinimapButton = false
            refreshMinimapButton()
            print("|cff33ff99Shinkili|r " .. L("MSG_MINIMAP_HIDDEN"))
        end
    end)

    minimapButton = button

    if not minimapSizeHooked then
        minimapSizeHooked = true
        Minimap:HookScript("OnSizeChanged", function()
            applyMinimapButtonPosition()
        end)
    end
end

refreshMinimapButton = function()
    local settings = db()
    if not settings then
        return
    end

    settings.minimapAngle = normalizeMinimapAngle(settings.minimapAngle)
    settings.showMinimapButton = settings.showMinimapButton ~= false

    if not settings.showMinimapButton then
        if minimapButton then
            minimapButton:Hide()
        end
        return
    end

    createMinimapButton()
    if not minimapButton then
        return
    end

    applyMinimapButtonPosition()
    minimapButton:Show()
end

local function printUsage()
    print("|cff33ff99Shinkili|r " .. L("CMD_USAGE"))
    print(L("CMD_OPEN"))
    print(L("CMD_LOCK"))
    print(L("CMD_UNLOCK"))
    print(L("CMD_MARKER"))
    print(L("CMD_MINIMAP"))
    print(L("CMD_SIZE"))
    print(L("CMD_RESET"))
    print(L("CMD_LANG"))
end

SLASH_SHINKILI1 = "/shinkili"
SLASH_SHINKILI2 = "/sk"
SlashCmdList.SHINKILI = function(msg)
    local input = trim(msg)
    local command, value = input:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "" then
        toggleOptionsWindow()
        return
    end

    if command == "lock" then
        db().locked = true
        updateEditorControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r " .. L("MSG_LOCKED"))
        return
    end

    if command == "unlock" then
        db().locked = false
        updateEditorControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r " .. L("MSG_UNLOCKED"))
        return
    end

    if command == "size" then
        local numeric = tonumber(value)
        if not numeric then
            print("|cff33ff99Shinkili|r " .. L("MSG_SIZE_BAD"))
            return
        end
        db().size = clamp(math.floor(numeric + 0.5), 24, 300)
        applySize()
        syncPlacementControls()
        refreshVisibility()
        print("|cff33ff99Shinkili|r " .. string.format(L("MSG_SIZE"), tostring(db().size)))
        return
    end

    if command == "marker" then
        local normalized = trim(value):lower()
        if normalized == "on" then
            db().showMarker = true
            updateEditorControls()
            refreshVisibility()
            print("|cff33ff99Shinkili|r " .. L("MSG_MARKER_ON"))
            return
        end
        if normalized == "off" then
            db().showMarker = false
            updateEditorControls()
            refreshVisibility()
            print("|cff33ff99Shinkili|r " .. L("MSG_MARKER_OFF"))
            return
        end
        print("|cff33ff99Shinkili|r " .. L("MSG_MARKER_USAGE"))
        return
    end

    if command == "minimap" then
        local normalized = trim(value):lower()
        if normalized == "on" then
            db().showMinimapButton = true
            refreshMinimapButton()
            print("|cff33ff99Shinkili|r " .. L("MSG_MINIMAP_ON"))
            return
        end
        if normalized == "off" then
            db().showMinimapButton = false
            refreshMinimapButton()
            print("|cff33ff99Shinkili|r " .. L("MSG_MINIMAP_OFF"))
            return
        end
        print("|cff33ff99Shinkili|r " .. L("MSG_MINIMAP_USAGE"))
        return
    end

    if command == "lang" or command == "locale" then
        local normalized = Locale and Locale.normalize(trim(value):lower()) or trim(value):lower()
        if normalized ~= "en" and normalized ~= "ko" then
            print("|cff33ff99Shinkili|r " .. L("MSG_LANG_USAGE"))
            return
        end
        db().locale = normalized
        if refreshOptionsLocale then
            refreshOptionsLocale()
        end
        refreshAllEditorViews()
        refreshVisibility()
        print("|cff33ff99Shinkili|r " .. string.format(L("MSG_LANG"), normalized))
        return
    end

    if command == "reset" then
        resetToDefaults()
        print("|cff33ff99Shinkili|r " .. L("MSG_RESET"))
        return
    end

    printUsage()
end

local function initialize()
    if not ShinkiliDB and type(BlizzShinDB) == "table" then
        ShinkiliDB = BlizzShinDB
    end

    ShinkiliDB = ShinkiliDB or {}
    ShinkiliDB.locale = ShinkiliDB.locale == nil and defaults.locale or ShinkiliDB.locale
    ShinkiliDB.size = ShinkiliDB.size == nil and defaults.size or ShinkiliDB.size
    ShinkiliDB.point = ShinkiliDB.point == nil and defaults.point or ShinkiliDB.point
    ShinkiliDB.relativePoint = ShinkiliDB.relativePoint == nil and defaults.relativePoint or ShinkiliDB.relativePoint
    ShinkiliDB.x = ShinkiliDB.x == nil and defaults.x or ShinkiliDB.x
    ShinkiliDB.y = ShinkiliDB.y == nil and defaults.y or ShinkiliDB.y
    ShinkiliDB.locked = ShinkiliDB.locked == nil and defaults.locked or ShinkiliDB.locked
    ShinkiliDB.showMarker = ShinkiliDB.showMarker == nil and defaults.showMarker or ShinkiliDB.showMarker
    ShinkiliDB.showMinimapButton = ShinkiliDB.showMinimapButton == nil and defaults.showMinimapButton or ShinkiliDB.showMinimapButton
    ShinkiliDB.minimapAngle = ShinkiliDB.minimapAngle == nil and defaults.minimapAngle or ShinkiliDB.minimapAngle
    ShinkiliDB.overrides = type(ShinkiliDB.overrides) == "table" and ShinkiliDB.overrides or copyDefaultOverrides()
    ShinkiliDB.mappings = type(ShinkiliDB.mappings) == "table" and ShinkiliDB.mappings or {}
    ShinkiliDB.defense = type(ShinkiliDB.defense) == "table" and ShinkiliDB.defense or {
        enabled = defaults.defense.enabled,
        locked = defaults.defense.locked,
        size = defaults.defense.size,
        point = defaults.defense.point,
        relativePoint = defaults.defense.relativePoint,
        x = defaults.defense.x,
        y = defaults.defense.y,
        entries = {},
    }
    ShinkiliDB.procs = type(ShinkiliDB.procs) == "table" and ShinkiliDB.procs or {entries = {}}
    ShinkiliDB.cooldownBox = nil

    refreshAvailableSpells()
    sanitizeSettings()
    applySize()
    applyPosition()
    applyDefenseSize()
    applyDefensePosition()
    syncPlacementControls()
    updateSpellState()
    refreshMinimapButton()

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

    if event == "PLAYER_ENTERING_WORLD" then
        refreshMinimapButton()
    end

    updateSpellState()
    if state.optionsOpen then
        updateEditorControls()
        updateMappingRows()
    end
end)
