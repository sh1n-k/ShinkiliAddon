local addonName = ...

-- Grouped into one table on purpose: this file is a single Lua chunk and Lua
-- caps a chunk at 200 locals. luacheck does not catch a violation but the game
-- refuses to load the addon, so top-level `local` slots are a scarce resource.
-- See tests/test_load.lua and the guardrail in AGENTS.md.
local C = {
    LEGACY_MAPPING_SLOTS = 12,
    VISIBLE_MAPPING_ROWS = 5,
    MAPPING_ROW_HEIGHT = 28,
    PRIORITY_VISIBLE_ROWS = 6,
    PRIORITY_ROW_HEIGHT = 28,
    GCD_SPELL_ID = 61304,
    OPTIONS_WIDTH = 900,
    OPTIONS_HEIGHT = 760,
    BLACKLIST_TOGGLE_BUTTON = "ShinkiliBlacklistToggleButton",
}

local FRAME_STRATA_LIST = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local Logic = ShinkiliLogic
local Locale = ShinkiliLocale
local Secret = ShinkiliSecret
local Eval = ShinkiliEval

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
    frameStrata = "FULLSCREEN_DIALOG",
    frameLevel = 200,
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
        frameStrata = "FULLSCREEN_DIALOG",
        frameLevel = 190,
        entries = {},
    },
    procs = {
        entries = {},
    },
    blacklist = {
        enabled = false,
        toggleKey = nil,
        entries = {},
        cooldowns = {},
    },
    -- Rank mode: among AC live candidates, Assist order (false) or SimC order (true).
    simcAssist = true,
    -- Account-wide: yellow interrupt bar above the main box.
    interruptEnabled = true,
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
    activeProcColorIndex = nil,
    defenseSpellId = nil,
    recommendReason = nil,
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
    blacklistEditorSpellId = nil,
    cooldownEditorSpellId = nil,
    bindingListen = false,
    pendingBlacklistBinding = false,
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

-- Pack local-only feature state into one upvalue to stay under Lua's 200-local cap.
local feature = {}

-- Target interrupt signal for KeySim: real Show/Hide only (no alpha-only hide).
-- Yellow solid when target cast is known-interruptible; hidden when shielded/secret/unknown.
feature.interruptBox = CreateFrame("Frame", "ShinkiliInterruptIndicator", UIParent, "BackdropTemplate")
feature.interruptBox:SetFrameStrata(square:GetFrameStrata())
feature.interruptBox:SetFrameLevel(square:GetFrameLevel() + 5)
feature.interruptBox:EnableMouse(false)
feature.interruptBox:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 2,
})
feature.interruptBox:SetBackdropColor(1.00, 1.00, 0.00, 1.00)
feature.interruptBox:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
feature.interruptBox:Hide()

local label = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
-- Default: above main box. Raised above interrupt box only while the signal is shown.
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

local toastFrame = CreateFrame("Frame", "ShinkiliToastFrame", UIParent)
toastFrame:SetSize(420, 56)
toastFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
toastFrame:SetFrameStrata("TOOLTIP")
toastFrame:SetFrameLevel(500)
toastFrame:Hide()
local toastText = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
toastText:SetPoint("CENTER")
toastText:SetTextColor(0.20, 1.00, 0.60, 1)
toastText:SetShadowOffset(1, -1)
toastText:SetShadowColor(0, 0, 0, 0.95)

local blacklistToggleButton = CreateFrame("Button", C.BLACKLIST_TOGGLE_BUTTON, UIParent)
blacklistToggleButton:SetSize(1, 1)
blacklistToggleButton:Hide()

local bindingCaptureFrame = CreateFrame("Frame", "ShinkiliBindingCapture", UIParent, "BackdropTemplate")
bindingCaptureFrame:SetAllPoints(UIParent)
bindingCaptureFrame:EnableMouse(true)
bindingCaptureFrame:EnableKeyboard(true)
bindingCaptureFrame:EnableMouseWheel(true)
bindingCaptureFrame:SetFrameStrata("TOOLTIP")
bindingCaptureFrame:SetFrameLevel(1000)
bindingCaptureFrame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
bindingCaptureFrame:SetBackdropColor(0, 0, 0, 0.55)
bindingCaptureFrame:SetBackdropBorderColor(0, 0, 0, 0)
bindingCaptureFrame:Hide()
bindingCaptureFrame.text = bindingCaptureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bindingCaptureFrame.text:SetPoint("CENTER", 0, 40)
bindingCaptureFrame.text:SetTextColor(0.20, 1.00, 0.60, 1)
bindingCaptureFrame.text:SetShadowOffset(1, -1)
bindingCaptureFrame.text:SetShadowColor(0, 0, 0, 0.95)

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
local blacklistRows = {}
local blacklistScrollFrame
local emptyBlacklistText
local cooldownExcludeRows = {}
local cooldownExcludeScrollFrame
local emptyCooldownExcludeText
local optionsLayout
local controlId = 0
local updateEditorControls
local updateMappingRows
local updateDefenseRows
local updateProcRows
local updateBlacklistRows
local updateCooldownExcludeRows
local syncPlacementControls
local updateCooldownSpiral
local refreshMinimapButton
local refreshDefenseBox
local selectOptionsTab
local refreshOptionsLocale
local applyFrameLayers
local applyBlacklistBinding
local setBlacklistEnabled
local showBlacklistToast
local updateSpellState
local getSimcSpecKey
local function db()
    return ShinkiliDB
end

local function clamp(value, minimum, maximum)
    return Logic.clamp(value, minimum, maximum)
end

local function trim(text)
    return Logic.trim(text)
end

function feature.characterKey()
    local name, realm = UnitFullName("player")
    if (not realm or realm == "") and GetNormalizedRealmName then
        realm = GetNormalizedRealmName()
    end
    if (not realm or realm == "") and GetRealmName then
        realm = GetRealmName()
    end
    return Logic.characterKey(name, realm)
end

--- Bind per-character placement + per-spec lists into the live settings root.
--- The spec bucket the live settings were last loaded from. Persisting must
--- target THIS, not whatever GetSpecialization() answers right now:
--- PLAYER_SPECIALIZATION_CHANGED already reports the incoming spec, so using the
--- live value writes the outgoing spec's lists into the incoming spec's bucket
--- and destroys it.
local boundSpecKey

function feature.bindMappings()
    local settings = db()
    if not settings then
        return
    end
    local key = feature.characterKey()
    Logic.migrateLegacyCharMappings(settings, key, settings.legacyMappingsCharacter)
    if key then
        Logic.rehomeNameOnlyCharMappings(settings, key)
    end
    Logic.migrateCharSpecProfiles(settings, key)

    if not key then
        if type(settings.mappings) ~= "table" then
            settings.mappings = {}
        end
        return
    end

    local charProfile = Logic.ensureCharProfile(settings, key)
    if not charProfile then
        return
    end

    if settings.pendingMappingsReset then
        charProfile.seed = Logic.emptySpecProfile()
        charProfile.specs = {}
        settings.charMappings = type(settings.charMappings) == "table" and settings.charMappings or {}
        settings.charMappings[key] = {}
        settings.pendingMappingsReset = nil
    end

    Logic.applyCharPlacementToSettings(settings, charProfile.placement)

    local specKey = getSimcSpecKey and getSimcSpecKey() or nil
    boundSpecKey = specKey
    if not specKey then
        -- Spec unknown yet: keep seed lists live so UI is not empty before talent load.
        Logic.applySpecToSettings(settings, charProfile.seed or Logic.emptySpecProfile())
        if type(charProfile.seed) == "table" and type(charProfile.seed.mappings) == "table" then
            settings.mappings = Logic.deepCopy(charProfile.seed.mappings)
        end
        settings.charMappings = type(settings.charMappings) == "table" and settings.charMappings or {}
        settings.charMappings[key] = settings.mappings
        return
    end

    local spec = Logic.ensureSpecProfile(charProfile, specKey)
    Logic.applySpecToSettings(settings, spec)
    -- Do not prune defense/proc entries here. sanitizeSettings always follows
    -- bind with persistMappings, so mutating live lists would write the pruned
    -- set into charProfiles and permanently drop rows when a talent is swapped
    -- or the spellbook is briefly incomplete at login. Unlearned rows stay listed;
    -- runtime castability already treats them as unusable.
    -- Keep legacy charMappings pointer in sync for older paths.
    settings.charMappings = type(settings.charMappings) == "table" and settings.charMappings or {}
    settings.charMappings[key] = settings.mappings
end

--- Write live settings back into char placement + the bound spec bucket.
function feature.persistMappings()
    local settings = db()
    if not settings then
        return
    end
    local key = feature.characterKey()
    if not key then
        return
    end

    local charProfile = Logic.ensureCharProfile(settings, key)
    if not charProfile then
        return
    end

    charProfile.placement = Logic.captureCharPlacementFromSettings(settings)

    local specKey = boundSpecKey or (getSimcSpecKey and getSimcSpecKey() or nil)
    if specKey then
        local captured = Logic.captureSpecFromSettings(settings)
        charProfile.specs = type(charProfile.specs) == "table" and charProfile.specs or {}
        charProfile.specs[specKey] = captured
        if type(charProfile.seed) ~= "table" then
            charProfile.seed = Logic.deepCopy(captured)
        end
    end

    settings.charMappings = type(settings.charMappings) == "table" and settings.charMappings or {}
    settings.charMappings[key] = type(settings.mappings) == "table" and settings.mappings or {}
end

function feature.applyInterruptLayout()
    local settings = db()
    if not settings then
        return
    end
    local width, height, gap = Logic.interruptBoxLayout(settings.size)
    local box = feature.interruptBox
    box:SetSize(width, height)
    box:ClearAllPoints()
    box:SetPoint("BOTTOM", square, "TOP", 0, gap)
end

--- Re-anchoring a FontString forces a layout pass, and this runs on the 20Hz
--- ticker, so only move the label when the state actually flips.
local labelAnchoredToInterrupt

function feature.setLabelForInterrupt(showInterrupt)
    showInterrupt = showInterrupt and true or false
    if labelAnchoredToInterrupt == showInterrupt then
        return
    end
    labelAnchoredToInterrupt = showInterrupt
    label:ClearAllPoints()
    if showInterrupt then
        label:SetPoint("BOTTOM", feature.interruptBox, "TOP", 0, 4)
    else
        label:SetPoint("BOTTOM", square, "TOP", 0, 6)
    end
end

--- True when UnitCastingInfo/UnitChannelInfo reported a cast name without using it in `if`.
--- Secret names mean "casting, unreadable label"; plain nil/empty means not casting.
--- Always test isSecret before any comparison — equality on secret values is unsafe in 12.0.
function feature.hasCastName(name)
    if Secret.isSecret(name) then
        return true
    end
    if name == nil then
        return false
    end
    if type(name) == "string" then
        return name ~= ""
    end
    return false
end

--- Target cast interruptibility. Returns isCasting, notInterruptible, accessible.
function feature.getTargetCastInterruptInfo()
    if UnitCastingInfo then
        local ok, name, _, _, _, _, _, _, notInterruptible = pcall(UnitCastingInfo, "target")
        if ok and feature.hasCastName(name) then
            local plain = Secret.plainBool(notInterruptible)
            if plain == nil then
                return true, nil, false
            end
            return true, plain, true
        end
    end

    if UnitChannelInfo then
        local ok, name, _, _, _, _, _, notInterruptible = pcall(UnitChannelInfo, "target")
        if ok and feature.hasCastName(name) then
            local plain = Secret.plainBool(notInterruptible)
            if plain == nil then
                return true, nil, false
            end
            return true, plain, true
        end
    end

    return false, nil, false
end

function feature.refreshInterrupt()
    local settings = db()
    if not settings or settings.interruptEnabled == false then
        feature.interruptBox:Hide()
        feature.setLabelForInterrupt(false)
        return
    end
    local isCasting, notInterruptible, accessible = feature.getTargetCastInterruptInfo()
    local show = Logic.shouldShowInterruptIndicator(isCasting, notInterruptible, accessible)
    -- The box is parented to UIParent and only anchored to the square, so it
    -- would otherwise float alone when the main box is hidden.
    if show and not square:IsShown() then
        show = false
    end
    local box = feature.interruptBox
    if show then
        box:SetBackdropColor(1.00, 1.00, 0.00, 1.00)
        box:SetAlpha(1)
        box:Show()
        feature.setLabelForInterrupt(true)
    else
        box:Hide()
        feature.setLabelForInterrupt(false)
    end
end

local function sanitizeConfig()
    return {
        sizeDefault = defaults.size,
        xDefault = defaults.x,
        yDefault = defaults.y,
        pointDefault = defaults.point,
        relativePointDefault = defaults.relativePoint,
        legacyMappingSlots = C.LEGACY_MAPPING_SLOTS,
        colorPaletteSize = #COLOR_PALETTE,
        markerPaletteSize = #MARKER_PALETTE,
        reservedOverrideSize = #RESERVED_OVERRIDE_PALETTE,
        defaultOverrides = defaults.overrides,
        defenseDefaults = defaults.defense,
        frameDefaults = {
            frameStrata = defaults.frameStrata,
            frameLevel = defaults.frameLevel,
            defenseFrameStrata = defaults.defense.frameStrata,
            defenseFrameLevel = defaults.defense.frameLevel,
        },
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

function feature.colorMenuText(colorIndex)
    local name = getColorName(colorIndex)
    local entry = COLOR_PALETTE[colorIndex]
    if not entry or not entry.rgba then
        return name
    end
    local r = math.floor((entry.rgba[1] or 0) * 255 + 0.5)
    local g = math.floor((entry.rgba[2] or 0) * 255 + 0.5)
    local b = math.floor((entry.rgba[3] or 0) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x■■|r %s", r, g, b, name)
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

--- Match mapping by base id or display/override id (KeySim colors stay bound to book ids).
local function findMappingIndexBySpell(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end

    local displayId = Eval.getDisplaySpellId(spellId)
    for index, mapping in ipairs(db().mappings) do
        local mid = tonumber(mapping.spellId)
        if mid then
            if mid == spellId or mid == displayId then
                return index
            end
            local mdisp = Eval.getDisplaySpellId(mid)
            if mdisp == spellId or mdisp == displayId then
                return index
            end
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

local function matchesSearch(spellId, searchText)
    return Logic.matchesSearch(spellId, getSpellNameSafe(spellId), searchText or state.searchText)
end

local function getSpellPriority(spellId)
    local priority = state.recentSpellRanks[spellId] or 0
    if state.currentSpellId and spellId == state.currentSpellId then
        priority = priority + 1000000
    end
    return priority
end

local function compareSpellEntries(left, right)
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

-- searchText nil → Main tab search; pass "" for unfiltered pickers (Defense/Procs).
-- stableNameSort: name order for option pickers (combat must not reshuffle the list).
local function getFilteredAvailableSpells(searchText, stableNameSort)
    local query = searchText
    if query == nil then
        query = state.searchText
    end

    local filtered = {}
    for _, spellInfo in ipairs(state.availableSpells) do
        if matchesSearch(spellInfo.spellId, query) then
            table.insert(filtered, spellInfo)
        end
    end

    if stableNameSort then
        table.sort(filtered, function(left, right)
            if left.name == right.name then
                return left.spellId < right.spellId
            end
            return left.name < right.name
        end)
    else
        table.sort(filtered, compareSpellEntries)
    end
    return filtered
end

local function buildMappingEntries()
    local entries = {}

    for index, mapping in ipairs(db().mappings) do
        if mapping.spellId and matchesSearch(mapping.spellId, state.searchText) then
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

    table.sort(entries, compareSpellEntries)
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

local getSpellCooldownInfo

local function pickActivePriorityEntry(entries, isActive)
    if type(entries) ~= "table" then
        return nil
    end

    local activeSet = {}
    for _, entry in ipairs(entries) do
        if entry.enabled ~= false and entry.spellId and isActive(entry.spellId) then
            activeSet[entry.spellId] = true
        end
    end

    return Logic.pickPriorityEntry(entries, activeSet)
end

--- A proc overlay means the game is highlighting the spell, but it can still be
--- out of range or on cooldown. Filter those, but NOT `no_resource`: this is a
--- main-box path and resource starvation refills every GCD, so excluding on it
--- would make the colour blink off and on at 20Hz. Permanent/cooldown exclusions
--- also apply: a blacklisted skill must never paint the main box via proc.
local function isProcUsable(spellId)
    if not Eval.isProcActive(spellId) or not Eval.isPickable(spellId) then
        return false
    end
    local blacklist = db().blacklist
    if type(blacklist) ~= "table" then
        return true
    end
    return not Logic.isSpellExcluded(
        blacklist.entries,
        blacklist.cooldowns,
        spellId,
        blacklist.enabled == true,
        Eval.getDisplaySpellId(spellId),
        Eval.getDisplaySpellId
    )
end

local function getActiveProcEntry()
    return pickActivePriorityEntry(db().procs and db().procs.entries, isProcUsable)
end

local function getActiveDefenseEntry()
    local defense = db().defense
    if not defense or defense.enabled == false then
        return nil
    end
    return pickActivePriorityEntry(defense.entries, Eval.isUsableForDisplay)
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
        return state.activeProcColorIndex or getAssignedColorIndex(state.activeProcSpellId)
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

local function getBlacklistSettings()
    local settings = db()
    settings.blacklist = type(settings.blacklist) == "table" and settings.blacklist or {
        enabled = false,
        toggleKey = nil,
        entries = {},
        cooldowns = {},
    }
    settings.blacklist.entries = type(settings.blacklist.entries) == "table" and settings.blacklist.entries or {}
    settings.blacklist.cooldowns = type(settings.blacklist.cooldowns) == "table" and settings.blacklist.cooldowns or {}
    return settings.blacklist
end

getSimcSpecKey = function()
    if not UnitClass then
        return nil
    end
    local _, classFile = UnitClass("player")
    if not classFile then
        return nil
    end
    local specIndex = GetSpecialization and GetSpecialization() or nil
    if not specIndex or specIndex < 1 then
        return nil
    end
    return Logic.specKey(classFile, specIndex)
end

--- Live AC triple for position-1:
---   primary  = GetNextCastSpell(false) include hidden (KeySim: full AC pick)
---   lookahead = GetNextCastSpell(true) highlight / visible-bar only (JustAC GetHighlightCastSpell)
---   rotation = GetRotationSpells (validated)
--- JustAC default profile uses visible-only for both; we keep include-hidden primary for
--- higher single-box quality, with highlight as BL/suppress substitute.
local function collectAcPositionInputs()
    local primary, lookahead, rotation = nil, nil, nil

    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        local okPrimary, p = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if okPrimary and type(p) == "number" and p > 0 then
            primary = p
        end
        local okHl, h = pcall(C_AssistedCombat.GetNextCastSpell, true)
        if okHl and type(h) == "number" and h > 0 then
            lookahead = h
        end
    end

    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        local okRot, rot = pcall(C_AssistedCombat.GetRotationSpells)
        if okRot and type(rot) == "table" and #rot > 0 then
            local clean = {}
            for i = 1, #rot do
                local id = rot[i]
                if type(id) ~= "number" or id <= 0 then
                    clean = nil
                    break
                end
                clean[i] = id
            end
            rotation = clean
        end
    end

    return primary, lookahead, rotation
end

--- SimC priority entries for the current spec and target count, plus the labels
--- /sk why prints. nil when rank mode is off or the spec has no bundled data.
local function getSimcContextForPick(simcAssist)
    if not simcAssist or not ShinkiliSimcData then
        return nil, nil, nil
    end
    local specKey = getSimcSpecKey()
    local specTable = Logic.getSimcSpecTable(ShinkiliSimcData, specKey)
    local useAoe = Eval.countHostileNameplates() >= 3
    return Logic.getSimcContextEntries(specTable, useAoe), specKey, useAoe and "aoe" or "st"
end

--- collectDetail is only set by /sk why: the diagnostic table allocates, and
--- this runs 20 times a second.
--- Shared by the pick and by /sk why so the report can never claim a spell the
--- box is not showing.
local function isAssistedCombatAvailable()
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable or not C_AssistedCombat.GetNextCastSpell then
        return false
    end
    local ok, available = pcall(C_AssistedCombat.IsAvailable)
    return ok and Secret.plainBool(available) == true
end

local function getCurrentRecommendedSpellId(collectDetail)
    state.recommendReason = nil

    if not isAssistedCombatAvailable() then
        return nil
    end

    local primary, lookahead, rotation = collectAcPositionInputs()

    -- Blizzard never recommends an uncastable spell, so its pick is a readiness
    -- oracle: it expires any stale local cooldown/charge entry we are holding
    -- (proc-driven resets and refunds fire no cast event).
    if ShinkiliTrack then
        -- Not ipairs over a literal: a nil primary would silently skip the
        -- lookahead, and the oracle is what un-sticks a stale cooldown entry.
        local function noteOracle(picked)
            if not picked then
                return
            end
            ShinkiliTrack.noteSpellRecommended(picked)
            local pickedDisplay = Eval.getDisplaySpellId(picked)
            if pickedDisplay ~= picked then
                ShinkiliTrack.noteSpellRecommended(pickedDisplay)
            end
        end
        noteOracle(primary)
        noteOracle(lookahead)
    end

    local blacklist = getBlacklistSettings()
    local simcAssist = db().simcAssist ~= false

    local simcEntries = getSimcContextForPick(simcAssist)

    local spellId, reason, detail = Logic.pickRecommendation(primary, lookahead, rotation, simcEntries, {
        blacklistEntries = blacklist.entries,
        blacklistCooldowns = blacklist.cooldowns,
        blacklistEnabled = blacklist.enabled == true,
        simcAssist = simcAssist,
        displayOf = Eval.getDisplaySpellId,
        castability = Eval.getCastability,
        gateVerdict = Eval.evaluateEntry,
        collectDetail = collectDetail == true,
    })
    state.recommendReason = reason
    return spellId, detail
end

--- Pre-cache base cooldowns and charge specs for everything the pick may weigh.
--- Out of combat only: GetSpellBaseCooldown returns secrets in combat.
local SIMC_CONTEXTS = {"st", "aoe"}

local function addDotWatch(dotIds, dotId)
    if not dotId then
        return
    end
    dotIds[#dotIds + 1] = dotId
    local dotDisplay = Eval.getDisplaySpellId(dotId)
    if dotDisplay ~= dotId then
        dotIds[#dotIds + 1] = dotDisplay
    end
end

local function scanTrackedSpells()
    if not ShinkiliTrack then
        return
    end

    local _, _, rotation = collectAcPositionInputs()
    if rotation then
        ShinkiliTrack.scanSpells(rotation)
    end

    local dotIds = {}
    local specTable = ShinkiliSimcData and Logic.getSimcSpecTable(ShinkiliSimcData, getSimcSpecKey())
    if type(specTable) == "table" then
        for _, context in ipairs(SIMC_CONTEXTS) do
            local entries = specTable[context]
            if type(entries) == "table" then
                local ids = {}
                for index = 1, #entries do
                    local entry = entries[index]
                    local entryId = type(entry) == "table" and entry.id or entry
                    ids[#ids + 1] = entryId

                    -- ONLY ids the spec gates a DoT on. Adding every entry id
                    -- here looks tempting (it would let the self-redundancy guard
                    -- see a gateless DoT) but it makes the tracker treat every
                    -- rotation cast as a DoT application: the 30s post-cast
                    -- window then reports a plain filler as "live", and the FIFO
                    -- aura bridge lets that filler steal a real DoT's instance.
                    if type(entry) == "table" and type(entry.gates) == "table" then
                        for _, gate in ipairs(entry.gates) do
                            if type(gate) == "table" and gate.t == "dot" then
                                addDotWatch(dotIds, gate.id or entryId)
                            end
                        end
                    end
                end
                ShinkiliTrack.scanSpells(ids)
            end
        end
    end
    -- Before the spec is known there is nothing to configure; saying "this spec
    -- has no DoTs" would be a claim we cannot make yet.
    ShinkiliTrack.setDotWatchList(specTable and dotIds or nil)

    local settings = db()
    local defense = settings and settings.defense
    if defense and type(defense.entries) == "table" then
        local ids = {}
        for _, entry in ipairs(defense.entries) do
            ids[#ids + 1] = entry.spellId
        end
        ShinkiliTrack.scanSpells(ids)
    end
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

getSpellCooldownInfo = function(spellId)
    if not spellId then
        return nil
    end

    -- `x or 0` is a truthiness branch, and in 12.0 these fields can be secret.
    -- Everything numeric goes through plainNumber first; nil is preserved so the
    -- caller can tell "unreadable" from a real zero.
    if GetSpellCooldown then
        local ok, startTime, duration, enabled, modRate = pcall(GetSpellCooldown, spellId)
        if ok then
            return Secret.plainNumber(startTime), Secret.plainNumber(duration),
                Secret.plainBool(enabled), Secret.plainNumber(modRate)
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellId)
        if ok and type(info) == "table" then
            return Secret.plainNumber(info.startTime), Secret.plainNumber(info.duration),
                Secret.plainBool(info.isEnabled), Secret.plainNumber(info.modRate)
        end
    end

    return nil
end

--- opts.skipBind: keep live root lists (after an in-UI edit) instead of reloading
--- from charProfiles, which would wipe unsaved inserts.
--- Named `opts`, not `options`: that name is the options-window frame at module
--- scope, and shadowing it here would be silent.
local function sanitizeSettings(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.skipBind ~= true then
        feature.bindMappings()
    end
    Logic.sanitizeSettings(db(), sanitizeConfig())
    feature.persistMappings()
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
    feature.applyInterruptLayout()
    if applyFrameLayers then
        applyFrameLayers()
    end
end

applyFrameLayers = function()
    local settings = db()
    local strata = settings.frameStrata or defaults.frameStrata
    local level = settings.frameLevel or defaults.frameLevel
    square:SetFrameStrata(strata)
    square:SetFrameLevel(level)
    spiral:SetFrameLevel(level + 10)
    markerDot:SetFrameLevel(level + 20)
    moveGlowOuter:SetFrameStrata(strata)
    moveGlowMid:SetFrameStrata(strata)
    moveGlowInner:SetFrameStrata(strata)
    moveGlowOuter:SetFrameLevel(math.max(1, level - 3))
    moveGlowMid:SetFrameLevel(math.max(1, level - 2))
    moveGlowInner:SetFrameLevel(math.max(1, level - 1))
    feature.interruptBox:SetFrameStrata(strata)
    feature.interruptBox:SetFrameLevel(level + 5)

    local defense = settings.defense or defaults.defense
    local dStrata = defense.frameStrata or defaults.defense.frameStrata
    local dLevel = defense.frameLevel or defaults.defense.frameLevel
    defenseBox:SetFrameStrata(dStrata)
    defenseBox:SetFrameLevel(dLevel)
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
    feature.persistMappings()
    if updateDefenseRows then
        updateDefenseRows()
    end
end

defenseBox:SetScript("OnDragStart", function(self)
    if db().defense and not db().defense.locked then
        self:StartMoving()
    end
end)
defenseBox:SetScript("OnDragStop", onDefenseDragStop)

local function formatBindingKey(key)
    if not key or key == "" then
        return L("BLACKLIST_UNBOUND")
    end
    return key
end

local function buildModifierPrefix()
    local parts = {}
    if IsAltKeyDown and IsAltKeyDown() then
        table.insert(parts, "ALT")
    end
    if IsControlKeyDown and IsControlKeyDown() then
        table.insert(parts, "CTRL")
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        table.insert(parts, "SHIFT")
    end
    if #parts == 0 then
        return ""
    end
    return table.concat(parts, "-") .. "-"
end

local function mouseButtonToBinding(button)
    if button == "LeftButton" then
        return "BUTTON1"
    end
    if button == "RightButton" then
        return "BUTTON2"
    end
    if button == "MiddleButton" then
        return "BUTTON3"
    end
    if button == "Button4" then
        return "BUTTON4"
    end
    if button == "Button5" then
        return "BUTTON5"
    end
    return nil
end

local function stopBindingListen()
    state.bindingListen = false
    bindingCaptureFrame:Hide()
    bindingCaptureFrame:SetScript("OnKeyDown", nil)
    bindingCaptureFrame:SetScript("OnMouseDown", nil)
    bindingCaptureFrame:SetScript("OnMouseWheel", nil)
    if updateBlacklistRows then
        updateBlacklistRows()
    end
end

local function saveToggleKey(bindingKey)
    local blacklist = getBlacklistSettings()
    blacklist.toggleKey = bindingKey
    stopBindingListen()
    applyBlacklistBinding()
    feature.persistMappings()
    if updateBlacklistRows then
        updateBlacklistRows()
    end
end

local function startBindingListen()
    state.bindingListen = true
    bindingCaptureFrame.text:SetText(L("BLACKLIST_CAPTURING"))
    bindingCaptureFrame:Show()
    bindingCaptureFrame:EnableKeyboard(true)
    if bindingCaptureFrame.SetPropagateKeyboardInput then
        bindingCaptureFrame:SetPropagateKeyboardInput(false)
    end

    bindingCaptureFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            stopBindingListen()
            return
        end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
            or key == "LALT" or key == "RALT" or key == "LMETA" or key == "RMETA" then
            return
        end
        saveToggleKey(buildModifierPrefix() .. key)
    end)

    bindingCaptureFrame:SetScript("OnMouseDown", function(_, button)
        local mapped = mouseButtonToBinding(button)
        if not mapped then
            return
        end
        -- Match Blizzard keybind UI: plain left/right click is not a bind.
        local mods = buildModifierPrefix()
        if mods == "" and (mapped == "BUTTON1" or mapped == "BUTTON2") then
            return
        end
        saveToggleKey(mods .. mapped)
    end)

    bindingCaptureFrame:SetScript("OnMouseWheel", function(_, delta)
        local wheel = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        saveToggleKey(buildModifierPrefix() .. wheel)
    end)

    if updateBlacklistRows then
        updateBlacklistRows()
    end
end

showBlacklistToast = function(enabled)
    toastText:SetText(enabled and L("BLACKLIST_TOAST_ON") or L("BLACKLIST_TOAST_OFF"))
    toastFrame:SetAlpha(1)
    toastFrame:Show()
    toastFrame.elapsed = 0
    toastFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.45 then
            self:SetAlpha(1)
            return
        end
        local fade = self.elapsed - 0.45
        if fade >= 0.225 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            self:SetAlpha(1)
            return
        end
        self:SetAlpha(1 - (fade / 0.225))
    end)
end

applyBlacklistBinding = function()
    if InCombatLockdown and InCombatLockdown() then
        state.pendingBlacklistBinding = true
        return
    end
    state.pendingBlacklistBinding = false
    if ClearOverrideBindings then
        ClearOverrideBindings(addon)
    end
    local blacklist = getBlacklistSettings()
    local key = blacklist.toggleKey
    if key and key ~= "" and SetOverrideBindingClick then
        SetOverrideBindingClick(addon, true, key, C.BLACKLIST_TOGGLE_BUTTON)
    end
end

setBlacklistEnabled = function(enabled, showToast)
    local blacklist = getBlacklistSettings()
    blacklist.enabled = enabled and true or false
    sanitizeSettings({skipBind = true})
    updateSpellState()
    if showToast ~= false then
        showBlacklistToast(blacklist.enabled)
    end
    if updateBlacklistRows then
        updateBlacklistRows()
    end
end

local function toggleBlacklistEnabled()
    local blacklist = getBlacklistSettings()
    setBlacklistEnabled(not blacklist.enabled, true)
end

blacklistToggleButton:SetScript("OnClick", function()
    toggleBlacklistEnabled()
end)

refreshDefenseBox = function()
    local defense = db().defense
    local entry = getActiveDefenseEntry()
    state.defenseSpellId = entry and entry.spellId or nil

    if not defense or defense.enabled == false then
        -- StopMovingOrSizing does not fire OnDragStop; commit coords first.
        if defenseBox.IsMoving and defenseBox:IsMoving() then
            onDefenseDragStop(defenseBox)
        end
        defenseBox:Hide()
        defenseBox:EnableMouse(false)
        return
    end

    -- Do not re-apply saved position/size here: the 20Hz ticker calls this path
    -- and would snap the box back while the user is dragging (main box never
    -- reapplies position on refresh for the same reason).
    local unlockedPreview = defense.locked == false
    local showPlaceholder = unlockedPreview or state.optionsOpen

    if entry then
        defenseBox:Show()
        defenseBox:SetBackdropColor(getPaletteColor(entry.colorIndex))
        defenseBox:SetAlpha(1)
        defenseLabel:SetText(getSpellNameSafe(entry.spellId))
        defenseLabel:Show()
    elseif showPlaceholder then
        defenseBox:Show()
        defenseBox:SetBackdropColor(0.25, 0.25, 0.25, 0.55)
        defenseBox:SetAlpha(1)
        defenseLabel:SetText(L("DEFENSE_BOX_LABEL"))
        defenseLabel:Show()
    else
        if defenseBox.IsMoving and defenseBox:IsMoving() then
            onDefenseDragStop(defenseBox)
        end
        defenseBox:Hide()
    end

    if defense.locked ~= false and defenseBox.IsMoving and defenseBox:IsMoving() then
        onDefenseDragStop(defenseBox)
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

local function recommendReasonLabel(reason)
    if state.activeProcSpellId then
        return L("WHY_PROC")
    end
    if reason == "ac_primary" then
        return L("WHY_AC_PRIMARY")
    end
    if reason == "ac_lookahead" then
        return L("WHY_AC_LOOKAHEAD")
    end
    if reason == "ac_candidate" then
        return L("WHY_AC_CANDIDATE")
    end
    if reason == "simc_verified" then
        return L("WHY_SIMC_VERIFIED")
    end
    if reason == "none" then
        return L("WHY_NONE")
    end
    return nil
end

local function updateCurrentSpellText()
    if not currentSpellText then
        return
    end

    local lines = {}
    local shown = state.activeProcSpellId or state.currentSpellId
    if shown then
        local text = string.format(L("CURRENT_RECOMMENDATION"), getSpellNameSafe(shown))
        local why = recommendReasonLabel(state.recommendReason)
        if why then
            text = text .. " · " .. why
        end
        table.insert(lines, text)
    else
        local text = string.format(L("CURRENT_RECOMMENDATION"), L("CURRENT_NONE"))
        local why = recommendReasonLabel(state.recommendReason or "none")
        if why then
            text = text .. " · " .. why
        end
        table.insert(lines, text)
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

    -- Cooldown numbers are secret in 12.0 combat; branching on them raw is the
    -- one thing the whole secret layer exists to avoid. Unreadable -> no spiral.
    local startTime, duration, enabled, modRate = getSpellCooldownInfo(C.GCD_SPELL_ID)
    if not startTime or not duration or enabled == false or duration <= 0 then
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
    feature.refreshInterrupt()
    updateCurrentSpellText()
end

updateSpellState = function()
    Eval.beginPass()
    local nextSpellId = getCurrentRecommendedSpellId()
    state.currentCastState, state.currentCastSpellId = getCurrentCastState()
    if nextSpellId and nextSpellId ~= state.currentSpellId then
        rememberRecommendedSpell(nextSpellId)
    end
    state.currentSpellId = nextSpellId

    local procEntry = getActiveProcEntry()
    state.activeProcSpellId = procEntry and procEntry.spellId or nil
    state.activeProcColorIndex = procEntry and procEntry.colorIndex or nil

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
    feature.persistMappings()
end

square:SetScript("OnDragStart", function(self)
    if not db().locked then
        self:StartMoving()
    end
end)
square:SetScript("OnDragStop", onDragStop)

local function getEditorMode()
    if state.editorSpellId and findMappingIndexBySpell(state.editorSpellId) then
        return L("SAVE")
    end
    return L("ADD")
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
        clearInfo.text = L("SELECT_SPELL")
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
        clearInfo.text = L("UNASSIGNED")
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
            info.text = feature.colorMenuText(colorIndex)
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
    row:SetSize(layout.listWidth, C.MAPPING_ROW_HEIGHT)

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
    UIDropDownMenu_SetText(editorSpellDropdown, state.editorSpellId and getSpellNameSafe(state.editorSpellId) or L("SELECT_SPELL"))

    UIDropDownMenu_SetSelectedValue(editorColorDropdown, state.editorColorIndex or 1)
    UIDropDownMenu_SetText(editorColorDropdown, getColorName(state.editorColorIndex or 1))

    editorActionButton:SetText(getEditorMode())
    editorActionButton:SetEnabled(state.editorSpellId ~= nil)

    local mainPanel = optionsPanels and optionsPanels.main
    if mainPanel and mainPanel.mapCurrentButton then
        -- Use ticker state only — do not re-run the pick pipeline from UI refresh.
        mainPanel.mapCurrentButton:SetEnabled(state.currentSpellId ~= nil)
    end

    editorPreviewButton:SetEnabled(previewSpellId ~= nil and previewColorIndex ~= nil)
    if previewSpellId and previewColorIndex and state.previewSpellId == previewSpellId and state.previewColorIndex == previewColorIndex then
        editorPreviewButton:SetText(L("HIDE"))
    else
        editorPreviewButton:SetText(L("SHOW"))
    end

    if editorMapping and not state.editorColorIndex then
        UIDropDownMenu_SetText(editorColorDropdown, L("UNASSIGNED"))
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

    sanitizeSettings({skipBind = true})
    syncEditorSelection()
end

local function saveEditorMapping()
    if not state.editorSpellId then
        return
    end

    local mapping, mappingIndex = getMappingBySpell(state.editorSpellId)
    local colorIndex = state.editorColorIndex
    if not colorIndex then
        if mapping then
            -- Editing an existing row with the dropdown on "Unassigned" is not a
            -- request to recolour it; auto-assign is for adding a new row only.
            return
        end
        colorIndex = Logic.getFirstFreeColorIndex(db().mappings, mappingIndex, #COLOR_PALETTE)
        if not colorIndex then
            print("|cff33ff99Shinkili|r " .. L("MSG_MAP_NO_COLOR"))
            return
        end
        state.editorColorIndex = colorIndex
    end

    if mapping then
        mapping.colorIndex = colorIndex
        mapping.moveGlow = state.editorMoveGlow == true
        if not mapping.markerIndex then
            mapping.markerIndex = getSuggestedMarkerIndex(mappingIndex)
        end
    else
        table.insert(db().mappings, {
            spellId = state.editorSpellId,
            colorIndex = colorIndex,
            markerIndex = getSuggestedMarkerIndex(nil),
            moveGlow = state.editorMoveGlow == true,
        })
    end

    if state.previewSpellId == state.editorSpellId then
        state.previewMoveGlow = state.editorMoveGlow == true
    end

    sanitizeSettings({skipBind = true})
    syncEditorSelection()
end

--- Map the current Assisted Combat / SimC pick to the first free color.
--- Uses the pick pipeline (not a proc override display). Skips if already mapped.
function feature.mapCurrentRecommendation()
    Eval.beginPass()
    local spellId = getCurrentRecommendedSpellId() or state.currentSpellId
    if not spellId then
        print("|cff33ff99Shinkili|r " .. L("MSG_MAP_NONE"))
        return false
    end

    if findMappingIndexBySpell(spellId) then
        print("|cff33ff99Shinkili|r " .. string.format(L("MSG_MAP_ALREADY"), getSpellNameSafe(spellId)))
        return false
    end

    feature.bindMappings()
    local mappings = db().mappings
    if type(mappings) ~= "table" then
        mappings = {}
        db().mappings = mappings
    end

    local colorIndex = Logic.getFirstFreeColorIndex(mappings, nil, #COLOR_PALETTE)
    if not colorIndex then
        print("|cff33ff99Shinkili|r " .. L("MSG_MAP_NO_COLOR"))
        return false
    end

    table.insert(mappings, {
        spellId = spellId,
        colorIndex = colorIndex,
        markerIndex = getSuggestedMarkerIndex(nil),
        moveGlow = false,
    })

    state.editorSpellId = spellId
    state.editorColorIndex = colorIndex
    state.editorMoveGlow = false
    rememberRecommendedSpell(spellId)

    sanitizeSettings({skipBind = true})
    syncEditorSelection()
    if state.optionsOpen then
        updateEditorControls()
        updateMappingRows()
    end
    refreshVisibility()

    print("|cff33ff99Shinkili|r " .. string.format(
        L("MSG_MAP_DONE"),
        getSpellNameSafe(spellId),
        getColorName(colorIndex)
    ))
    return true
end

function updateMappingRows()
    if not options then
        return
    end

    local entries = buildMappingEntries()
    local totalRows = #entries
    local offset = 0

    if mappingScrollFrame then
        FauxScrollFrame_Update(mappingScrollFrame, totalRows, C.VISIBLE_MAPPING_ROWS, C.MAPPING_ROW_HEIGHT)
        offset = FauxScrollFrame_GetOffset(mappingScrollFrame)
    end

    for rowIndex = 1, C.VISIBLE_MAPPING_ROWS do
        local row = mappingRows[rowIndex]
        local entry = entries[offset + rowIndex]

        if entry then
            row:Show()
            row.spellText:SetText(entry.name)
            row.colorText:SetText(entry.colorIndex and getColorName(entry.colorIndex) or L("UNASSIGNED"))
            if entry.colorIndex then
                row.colorSwatch:SetBackdropColor(getPaletteColor(entry.colorIndex))
            else
                row.colorSwatch:SetBackdropColor(0.15, 0.15, 0.15, 1)
            end
            row.markerSwatch:SetBackdropColor(getMarkerColor(entry.markerIndex))
            row.glowCheck:SetChecked(entry.moveGlow == true)
            row.deleteButton:SetText(L("DELETE"))
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
                row.previewButton:SetText(L("HIDE"))
            else
                row.previewButton:SetText(L("SHOW"))
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
    holder.label:SetText(L("SEARCH"))

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
    local main = optionsPanels.main
    if main then
        if main.mainLevelInput then
            main.mainLevelInput:SetText(tostring(db().frameLevel or defaults.frameLevel))
        end
        if main.mainStrataDropdown then
            local strata = db().frameStrata or defaults.frameStrata
            UIDropDownMenu_SetSelectedValue(main.mainStrataDropdown, strata)
            UIDropDownMenu_SetText(main.mainStrataDropdown, strata)
        end
        if main.simcAssistCheck then
            main.simcAssistCheck:SetChecked(db().simcAssist ~= false)
        end
        if main.interruptEnable then
            main.interruptEnable:SetChecked(db().interruptEnabled ~= false)
        end
        if main.simcStatus then
            local key = getSimcSpecKey()
            local has = key and ShinkiliSimcData and Logic.getSimcSpecTable(ShinkiliSimcData, key)
            if has then
                main.simcStatus:SetText(string.format(L("SIMC_STATUS_OK"), key))
            else
                main.simcStatus:SetText(L("SIMC_STATUS_MISSING"))
            end
        end
        if main.simcAssistCheck and main.simcAssistCheck.text then
            main.simcAssistCheck.text:SetText(L("SIMC_ASSIST"))
        end
        if main.simcHint then
            main.simcHint:SetText(L("SIMC_ASSIST_HINT"))
        end
    end
    if updateDefenseRows then
        updateDefenseRows()
    end
    if updateProcRows then
        updateProcRows()
    end
    if updateBlacklistRows then
        updateBlacklistRows()
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
    settings.frameStrata = defaults.frameStrata
    settings.frameLevel = defaults.frameLevel
    settings.interruptEnabled = defaults.interruptEnabled
    settings.overrides = copyDefaultOverrides()
    settings.mappings = {}
    local charKey = feature.characterKey()
    settings.charMappings = type(settings.charMappings) == "table" and settings.charMappings or {}
    settings.charProfiles = type(settings.charProfiles) == "table" and settings.charProfiles or {}
    settings.defense = {
        enabled = defaults.defense.enabled,
        locked = defaults.defense.locked,
        size = defaults.defense.size,
        point = defaults.defense.point,
        relativePoint = defaults.defense.relativePoint,
        x = defaults.defense.x,
        y = defaults.defense.y,
        frameStrata = defaults.defense.frameStrata,
        frameLevel = defaults.defense.frameLevel,
        entries = {},
    }
    settings.procs = {entries = {}}
    settings.blacklist = {
        enabled = false,
        toggleKey = nil,
        entries = {},
        cooldowns = {},
    }
    settings.simcAssist = defaults.simcAssist
    settings.cooldownBox = nil

    -- Capture placement only AFTER defense and blacklist are back at defaults:
    -- capturing first stored the OLD defense box position and exclude keybind in
    -- the profile, and the following bind wrote them straight back into the live
    -- settings, so the reset appeared to half-fail.
    if charKey then
        settings.charMappings[charKey] = settings.mappings
        settings.charProfiles[charKey] = {
            placement = Logic.captureCharPlacementFromSettings(settings),
            seed = Logic.emptySpecProfile(),
            specs = {},
        }
        settings.pendingMappingsReset = nil
    else
        -- Character key not ready yet; bindMappings clears this character on next stable key.
        settings.pendingMappingsReset = true
    end

    state.editorSpellId = nil
    state.editorColorIndex = nil
    state.editorMoveGlow = false
    state.defenseEditorSpellId = nil
    state.defenseEditorColorIndex = 2
    state.procEditorSpellId = nil
    state.procEditorColorIndex = 2
    state.blacklistEditorSpellId = nil
    state.cooldownEditorSpellId = nil
    state.searchText = ""
    stopBindingListen()
    setPreview(nil)

    if searchInput then
        searchInput:SetText("")
    end

    applySize()
    applyPosition()
    applyDefenseSize()
    applyDefensePosition()
    applyFrameLayers()
    applyBlacklistBinding()
    sanitizeSettings()
    updateSpellState()
    refreshAllEditorViews()
    if refreshOptionsLocale then
        refreshOptionsLocale()
    end
    refreshVisibility()
    refreshMinimapButton()
end

function feature.confirmResetToDefaults()
    local dialogs = _G.StaticPopupDialogs
    local showPopup = _G.StaticPopup_Show
    if not dialogs or not showPopup then
        resetToDefaults()
        print("|cff33ff99Shinkili|r " .. L("MSG_RESET"))
        return
    end
    dialogs["SHINKILI_RESET_CONFIRM"] = {
        text = L("RESET_CONFIRM"),
        button1 = L("RESET_CONFIRM_YES"),
        button2 = L("RESET_CONFIRM_NO"),
        OnAccept = function()
            resetToDefaults()
            print("|cff33ff99Shinkili|r " .. L("MSG_RESET"))
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        exclusive = true,
        preferredIndex = 3,
    }
    showPopup("SHINKILI_RESET_CONFIRM")
end

function feature.addExcludeSpell(listKey, spellId)
    if not spellId then
        return false
    end
    local blacklist = getBlacklistSettings()
    local entries
    if listKey == "cooldowns" then
        blacklist.cooldowns = blacklist.cooldowns or {}
        entries = blacklist.cooldowns
    else
        blacklist.entries = blacklist.entries or {}
        entries = blacklist.entries
    end
    for _, entry in ipairs(entries) do
        if entry.spellId == spellId then
            entry.enabled = true
            sanitizeSettings({skipBind = true})
            return true
        end
    end
    table.insert(entries, {spellId = spellId, enabled = true})
    sanitizeSettings({skipBind = true})
    return true
end

local function createMainOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24
    local listWidth = contentWidth - 20
    local spellTextWidth = 250
    local colorTextWidth = 100
    local previewButtonWidth = 56
    local deleteButtonWidth = 56
    local deleteButtonLeft = listWidth - deleteButtonWidth - 8
    local previewButtonLeft = deleteButtonLeft - previewButtonWidth - 8
    local glowLeft = previewButtonLeft - 36
    -- Match createSavedMappingRow: marker(8+10) + gap12 + spell + gap12 = color swatch
    local spellHeaderX = 8 + 10 + 12
    local colorHeaderX = spellHeaderX + spellTextWidth + 12

    optionsLayout = {
        listWidth = listWidth,
        spellTextWidth = spellTextWidth,
        colorTextWidth = colorTextWidth,
        glowLeft = glowLeft,
        previewButtonLeft = previewButtonLeft,
        deleteButtonLeft = deleteButtonLeft,
        previewButtonWidth = previewButtonWidth,
        deleteButtonWidth = deleteButtonWidth,
        spellHeaderX = spellHeaderX,
        colorHeaderX = colorHeaderX,
        glowHeaderX = glowLeft + 2,
        showHeaderX = previewButtonLeft + 6,
        deleteHeaderX = deleteButtonLeft + 4,
    }

    local leftTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 8, -4)
    leftTitle:SetText(L("MAIN_TITLE"))
    frame.mainTitle = leftTitle

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("MAIN_SUBTITLE"))
    frame.mainSubtitle = subtitle

    currentSpellText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentSpellText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    currentSpellText:SetWidth(contentWidth - 120)
    currentSpellText:SetHeight(20)
    currentSpellText:SetJustifyH("LEFT")
    currentSpellText:SetWordWrap(false)
    currentSpellText:SetText(string.format(L("CURRENT_RECOMMENDATION"), L("CURRENT_NONE")))

    local mapCurrentButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    mapCurrentButton:SetSize(108, 22)
    mapCurrentButton:SetPoint("TOP", currentSpellText, "TOP", 0, 2)
    mapCurrentButton:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    mapCurrentButton:SetText(L("MAP_CURRENT"))
    mapCurrentButton:SetScript("OnClick", function()
        feature.mapCurrentRecommendation()
    end)
    frame.mapCurrentButton = mapCurrentButton

    local simcCheck = CreateFrame("CheckButton", addonName .. "SimcAssist", frame, "UICheckButtonTemplate")
    simcCheck:SetPoint("TOPLEFT", currentSpellText, "BOTTOMLEFT", 0, -4)
    simcCheck.text:SetText(L("SIMC_ASSIST"))
    simcCheck:SetScript("OnClick", function(self)
        db().simcAssist = self:GetChecked() and true or false
        updateSpellState()
        if frame.simcStatus then
            local key = getSimcSpecKey()
            local has = key and ShinkiliSimcData and Logic.getSimcSpecTable(ShinkiliSimcData, key)
            if has then
                frame.simcStatus:SetText(string.format(L("SIMC_STATUS_OK"), key))
            else
                frame.simcStatus:SetText(L("SIMC_STATUS_MISSING"))
            end
        end
    end)
    frame.simcAssistCheck = simcCheck

    -- Same row as SimC: avoids growing the bottom placement column (footer clash)
    -- and does not push the mapping list / overrides band downward.
    local interruptCheck = CreateFrame("CheckButton", addonName .. "InterruptEnable", frame, "UICheckButtonTemplate")
    interruptCheck:SetPoint("LEFT", simcCheck, "LEFT", math.floor(contentWidth * 0.55), 0)
    interruptCheck.text:SetText(L("INTERRUPT_ENABLE"))
    interruptCheck:SetScript("OnClick", function(self)
        db().interruptEnabled = self:GetChecked() and true or false
        feature.refreshInterrupt()
    end)
    frame.interruptEnable = interruptCheck

    local simcStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simcStatus:SetPoint("TOPLEFT", simcCheck, "BOTTOMLEFT", 28, -2)
    simcStatus:SetWidth(contentWidth - 28)
    simcStatus:SetJustifyH("LEFT")
    frame.simcStatus = simcStatus

    local simcHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simcHint:SetPoint("TOPLEFT", simcStatus, "BOTTOMLEFT", 0, -2)
    simcHint:SetWidth(math.floor(contentWidth * 0.52))
    simcHint:SetJustifyH("LEFT")
    simcHint:SetText(L("SIMC_ASSIST_HINT"))
    frame.simcHint = simcHint

    local interruptHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    interruptHint:SetPoint("TOPLEFT", interruptCheck, "BOTTOMLEFT", 28, -2)
    interruptHint:SetWidth(math.floor(contentWidth * 0.42))
    interruptHint:SetJustifyH("LEFT")
    interruptHint:SetText(L("INTERRUPT_HINT"))
    frame.interruptHint = interruptHint

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", simcHint, "BOTTOMLEFT", -28, -8)
    editorLabel:SetText(L("QUICK_EDITOR"))
    frame.editorLabel = editorLabel

    local editorRow1 = CreateFrame("Frame", nil, frame)
    editorRow1:SetSize(contentWidth, 40)
    editorRow1:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -4)

    local searchHolder = createSearchInput(editorRow1, 120)
    searchHolder:SetPoint("LEFT", 0, 0)
    searchInput = searchHolder.input
    frame.searchHolder = searchHolder

    editorSpellDropdown = CreateFrame("Frame", addonName .. "EditorSpellDropdown", editorRow1, "UIDropDownMenuTemplate")
    editorSpellDropdown:SetPoint("LEFT", searchHolder, "RIGHT", 0, -6)
    UIDropDownMenu_SetWidth(editorSpellDropdown, 360)
    UIDropDownMenu_JustifyText(editorSpellDropdown, "LEFT")
    initializeSpellDropdown(editorSpellDropdown)

    local editorRow2 = CreateFrame("Frame", nil, frame)
    editorRow2:SetSize(contentWidth, 28)
    editorRow2:SetPoint("TOPLEFT", editorRow1, "BOTTOMLEFT", 0, -4)

    editorColorDropdown = CreateFrame("Frame", addonName .. "EditorColorDropdown", editorRow2, "UIDropDownMenuTemplate")
    editorColorDropdown:SetPoint("LEFT", -12, -2)
    UIDropDownMenu_SetWidth(editorColorDropdown, 160)
    UIDropDownMenu_JustifyText(editorColorDropdown, "LEFT")
    initializeColorDropdown(editorColorDropdown)

    editorActionButton = CreateFrame("Button", nil, editorRow2, "GameMenuButtonTemplate")
    editorActionButton:SetSize(80, 22)
    editorActionButton:SetPoint("LEFT", editorColorDropdown, "RIGHT", 0, 2)
    editorActionButton:SetText(L("ADD"))
    editorActionButton:SetScript("OnClick", function()
        saveEditorMapping()
        updateEditorControls()
        updateMappingRows()
        refreshVisibility()
    end)

    editorPreviewButton = CreateFrame("Button", nil, editorRow2, "GameMenuButtonTemplate")
    editorPreviewButton:SetSize(80, 22)
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
    searchHint:SetPoint("TOPLEFT", editorRow2, "BOTTOMLEFT", 0, -4)
    searchHint:SetWidth(contentWidth)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetText(L("SEARCH_HINT"))
    frame.searchHint = searchHint

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", searchHint, "BOTTOMLEFT", 0, -8)
    listLabel:SetText(L("SAVED_MAPPINGS"))
    frame.listLabel = listLabel

    local listHeaders = CreateFrame("Frame", nil, frame)
    listHeaders:SetSize(listWidth, 16)
    listHeaders:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)
    frame.listHeaders = listHeaders

    local spellHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellHeader:SetPoint("LEFT", optionsLayout.spellHeaderX, 0)
    spellHeader:SetText(L("SPELL"))
    frame.spellHeader = spellHeader

    local colorHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorHeader:SetPoint("LEFT", optionsLayout.colorHeaderX, 0)
    colorHeader:SetText(L("COLOR"))
    frame.colorHeader = colorHeader

    local glowHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowHeader:SetPoint("LEFT", optionsLayout.glowHeaderX, 0)
    glowHeader:SetText(L("GLOW"))
    frame.glowHeader = glowHeader

    local showHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showHeader:SetPoint("LEFT", optionsLayout.showHeaderX, 0)
    showHeader:SetText(L("SHOW"))
    frame.showHeader = showHeader

    local deleteHeader = listHeaders:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deleteHeader:SetPoint("LEFT", optionsLayout.deleteHeaderX, 0)
    deleteHeader:SetText(L("DELETE"))
    frame.deleteHeader = deleteHeader

    mappingScrollFrame = CreateFrame("ScrollFrame", addonName .. "MappingsScrollFrame", frame, "FauxScrollFrameTemplate")
    mappingScrollFrame:SetPoint("TOPLEFT", listHeaders, "BOTTOMLEFT", 0, -2)
    mappingScrollFrame:SetSize(listWidth, C.VISIBLE_MAPPING_ROWS * C.MAPPING_ROW_HEIGHT)
    mappingScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, C.MAPPING_ROW_HEIGHT, updateMappingRows)
    end)

    for rowIndex = 1, C.VISIBLE_MAPPING_ROWS do
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

    local bottomWidth = contentWidth
    local overridesColumnWidth = math.floor((bottomWidth - 16) * 0.55)
    local placementColumnWidth = bottomWidth - overridesColumnWidth - 16

    local overridesColumn = CreateFrame("Frame", nil, frame)
    overridesColumn:SetSize(overridesColumnWidth, 170)
    overridesColumn:SetPoint("TOPLEFT", mappingScrollFrame, "BOTTOMLEFT", 0, -10)

    local overridesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overridesLabel:SetPoint("TOPLEFT", overridesColumn, "TOPLEFT", 0, 0)
    overridesLabel:SetText(L("STATE_OVERRIDES"))
    frame.overridesLabel = overridesLabel

    local overridesHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overridesHint:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -2)
    overridesHint:SetWidth(overridesColumnWidth - 4)
    overridesHint:SetJustifyH("LEFT")
    overridesHint:SetText(L("STATE_OVERRIDES_HINT"))
    frame.overridesHint = overridesHint

    local castingOverrideRow = createOverrideControl(overridesColumn, L("CASTING"), "casting", overridesColumnWidth, 150)
    castingOverrideRow:SetPoint("TOPLEFT", overridesHint, "BOTTOMLEFT", 0, -8)
    castingOverrideCheck = castingOverrideRow.check
    castingOverrideDropdown = castingOverrideRow.dropdown
    frame.castingOverrideRow = castingOverrideRow

    local channelingOverrideRow = createOverrideControl(overridesColumn, L("CHANNELING"), "channeling", overridesColumnWidth, 150)
    channelingOverrideRow:SetPoint("TOPLEFT", castingOverrideRow, "BOTTOMLEFT", 0, -4)
    channelingOverrideCheck = channelingOverrideRow.check
    channelingOverrideDropdown = channelingOverrideRow.dropdown
    frame.channelingOverrideRow = channelingOverrideRow

    local empowerOverrideRow = createOverrideControl(overridesColumn, L("EMPOWER"), "empower", overridesColumnWidth, 150)
    empowerOverrideRow:SetPoint("TOPLEFT", channelingOverrideRow, "BOTTOMLEFT", 0, -4)
    empowerOverrideCheck = empowerOverrideRow.check
    empowerOverrideDropdown = empowerOverrideRow.dropdown
    frame.empowerOverrideRow = empowerOverrideRow

    local placementColumn = CreateFrame("Frame", nil, frame)
    placementColumn:SetSize(placementColumnWidth, 190)
    placementColumn:SetPoint("TOPLEFT", overridesColumn, "TOPRIGHT", 16, 0)

    local placementLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placementLabel:SetPoint("TOPLEFT", placementColumn, "TOPLEFT", 0, 0)
    placementLabel:SetText(L("INDICATOR"))
    frame.placementLabel = placementLabel

    local sizeHolder = createPlacementInput(placementColumn, L("SIZE"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().size = clamp(value, 24, 300)
        applySize()
        syncPlacementControls()
        feature.persistMappings()
        refreshVisibility()
    end)
    sizeHolder:SetPoint("TOPLEFT", placementLabel, "BOTTOMLEFT", 0, -8)
    sizeInput = sizeHolder.input
    frame.sizeHolder = sizeHolder

    local xHolder = createPlacementInput(placementColumn, L("X"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().x = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
        feature.persistMappings()
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 10, 0)
    xInput = xHolder.input
    frame.xHolder = xHolder

    local yHolder = createPlacementInput(placementColumn, L("Y"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            syncPlacementControls()
            return
        end
        db().y = clamp(value, -1000, 1000)
        applyPosition()
        syncPlacementControls()
        feature.persistMappings()
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 10, 0)
    yInput = yHolder.input
    frame.yHolder = yHolder

    markerToggleCheck = CreateFrame("CheckButton", addonName .. "MarkerToggle", placementColumn, "UICheckButtonTemplate")
    markerToggleCheck:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -10)
    markerToggleCheck.text:SetText(L("SHOW_MARKER"))
    markerToggleCheck:SetScript("OnClick", function(self)
        db().showMarker = self:GetChecked() and true or false
        feature.persistMappings()
        refreshVisibility()
    end)

    lockToggleButton = CreateFrame("Button", nil, placementColumn, "GameMenuButtonTemplate")
    lockToggleButton:SetPoint("TOPLEFT", markerToggleCheck, "BOTTOMLEFT", 4, -8)
    lockToggleButton:SetSize(140, 22)
    lockToggleButton:SetText(L("UNLOCK"))
    lockToggleButton:SetScript("OnClick", function()
        db().locked = not db().locked
        feature.persistMappings()
        updateEditorControls()
        refreshVisibility()
    end)

    local layerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layerLabel:SetPoint("TOPLEFT", lockToggleButton, "BOTTOMLEFT", 0, -12)
    layerLabel:SetText(L("FRAME_LAYER"))
    frame.layerLabel = layerLabel

    local strataDropdown = CreateFrame("Frame", addonName .. "MainStrataDropdown", placementColumn, "UIDropDownMenuTemplate")
    strataDropdown:SetPoint("TOPLEFT", layerLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(strataDropdown, 160)
    UIDropDownMenu_Initialize(strataDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, strata in ipairs(FRAME_STRATA_LIST) do
            info.text = strata
            info.value = strata
            info.func = function()
                db().frameStrata = strata
                UIDropDownMenu_SetSelectedValue(strataDropdown, strata)
                UIDropDownMenu_SetText(strataDropdown, strata)
                applyFrameLayers()
                feature.persistMappings()
            end
            info.checked = (db().frameStrata or defaults.frameStrata) == strata
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(strataDropdown, db().frameStrata or defaults.frameStrata)
    UIDropDownMenu_SetText(strataDropdown, db().frameStrata or defaults.frameStrata)
    frame.mainStrataDropdown = strataDropdown

    local levelHolder = createPlacementInput(placementColumn, L("FRAME_LEVEL"), 72, function(text)
        local value = parseInteger(text)
        if not value then
            if frame.mainLevelInput then
                frame.mainLevelInput:SetText(tostring(db().frameLevel or defaults.frameLevel))
            end
            return
        end
        db().frameLevel = Logic.sanitizeFrameLevel(value, defaults.frameLevel)
        applyFrameLayers()
        feature.persistMappings()
        if frame.mainLevelInput then
            frame.mainLevelInput:SetText(tostring(db().frameLevel))
        end
    end)
    -- Beside strata (not under it) so the column stays within the bottom band.
    levelHolder:SetPoint("LEFT", strataDropdown, "RIGHT", 4, 2)
    frame.mainLevelInput = levelHolder.input
    frame.mainLevelHolder = levelHolder
    if frame.mainLevelInput then
        frame.mainLevelInput:SetText(tostring(db().frameLevel or defaults.frameLevel))
    end
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
            sanitizeSettings({skipBind = true})
            return
        end
    end
    table.insert(root.entries, {
        spellId = spellId,
        colorIndex = colorIndex,
        enabled = true,
    })
    sanitizeSettings({skipBind = true})
end

local function createPriorityRow(parent, _)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(math.max((parent:GetWidth() or 700) - 24, 600), C.PRIORITY_ROW_HEIGHT)

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
        FauxScrollFrame_Update(scrollFrame, total, C.PRIORITY_VISIBLE_ROWS, C.PRIORITY_ROW_HEIGHT)
        offset = FauxScrollFrame_GetOffset(scrollFrame)
    end

    for rowIndex = 1, C.PRIORITY_VISIBLE_ROWS do
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
            row.upButton:SetText(L("UP"))
            row.downButton:SetText(L("DOWN"))
            row.deleteButton:SetText(L("DELETE"))
            row.upButton:SetEnabled(entryIndex > 1)
            row.downButton:SetEnabled(entryIndex < total)
            -- Every one of these mutates the live list, so it has to persist:
            -- otherwise the next bind reloads the stored bucket and the edit is
            -- silently reverted the moment the options window reopens.
            row.enable:SetScript("OnClick", function(self)
                entry.enabled = self:GetChecked() and true or false
                sanitizeSettings({skipBind = true})
                refreshFn()
                refreshVisibility()
            end)
            row.upButton:SetScript("OnClick", function()
                Logic.movePriorityEntry(entries, entryIndex, -1)
                sanitizeSettings({skipBind = true})
                refreshFn()
                refreshVisibility()
            end)
            row.downButton:SetScript("OnClick", function()
                Logic.movePriorityEntry(entries, entryIndex, 1)
                sanitizeSettings({skipBind = true})
                refreshFn()
                refreshVisibility()
            end)
            row.deleteButton:SetScript("OnClick", function()
                table.remove(entries, entryIndex)
                sanitizeSettings({skipBind = true})
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
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText(L("DEFENSE_TITLE"))
    frame.defenseTitle = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("DEFENSE_SUBTITLE"))
    frame.defenseSubtitle = subtitle

    local enableCheck = CreateFrame("CheckButton", addonName .. "DefenseEnable", frame, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    enableCheck.text:SetText(L("DEFENSE_ENABLE"))
    enableCheck:SetScript("OnClick", function(self)
        db().defense.enabled = self:GetChecked() and true or false
        feature.persistMappings()
        refreshDefenseBox()
    end)
    frame.defenseEnable = enableCheck

    local lockCheck = CreateFrame("CheckButton", addonName .. "DefenseLock", frame, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -2)
    lockCheck.text:SetText(L("DEFENSE_LOCKED"))
    lockCheck:SetScript("OnClick", function(self)
        db().defense.locked = self:GetChecked() and true or false
        feature.persistMappings()
        refreshDefenseBox()
    end)
    frame.defenseLock = lockCheck

    local placementLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placementLabel:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -10)
    placementLabel:SetText(L("DEFENSE_PLACEMENT"))
    frame.defensePlacementLabel = placementLabel

    local sizeHolder = createPlacementInput(frame, L("SIZE"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            if frame.defenseSizeInput then
                frame.defenseSizeInput:SetText(tostring(db().defense.size or defaults.defense.size))
            end
            return
        end
        db().defense.size = clamp(value, 24, 300)
        applyDefenseSize()
        feature.persistMappings()
        refreshDefenseBox()
    end)
    sizeHolder:SetPoint("TOPLEFT", placementLabel, "BOTTOMLEFT", 0, -6)
    frame.defenseSizeInput = sizeHolder.input
    frame.defenseSizeHolder = sizeHolder

    local xHolder = createPlacementInput(frame, L("X"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            if frame.defenseXInput then
                frame.defenseXInput:SetText(tostring(db().defense.x or defaults.defense.x))
            end
            return
        end
        db().defense.x = clamp(value, -1000, 1000)
        db().defense.point = "CENTER"
        db().defense.relativePoint = "CENTER"
        applyDefensePosition()
        feature.persistMappings()
        refreshDefenseBox()
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 12, 0)
    frame.defenseXInput = xHolder.input
    frame.defenseXHolder = xHolder

    local yHolder = createPlacementInput(frame, L("Y"), 64, function(text)
        local value = parseInteger(text)
        if not value then
            if frame.defenseYInput then
                frame.defenseYInput:SetText(tostring(db().defense.y or defaults.defense.y))
            end
            return
        end
        db().defense.y = clamp(value, -1000, 1000)
        db().defense.point = "CENTER"
        db().defense.relativePoint = "CENTER"
        applyDefensePosition()
        feature.persistMappings()
        refreshDefenseBox()
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 12, 0)
    frame.defenseYInput = yHolder.input
    frame.defenseYHolder = yHolder

    local layerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layerLabel:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -10)
    layerLabel:SetText(L("FRAME_LAYER"))
    frame.defenseLayerLabel = layerLabel

    local strataDropdown = CreateFrame("Frame", addonName .. "DefenseStrataDropdown", frame, "UIDropDownMenuTemplate")
    strataDropdown:SetPoint("TOPLEFT", layerLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(strataDropdown, 160)
    UIDropDownMenu_Initialize(strataDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, strata in ipairs(FRAME_STRATA_LIST) do
            info.text = strata
            info.value = strata
            info.func = function()
                db().defense.frameStrata = strata
                UIDropDownMenu_SetSelectedValue(strataDropdown, strata)
                UIDropDownMenu_SetText(strataDropdown, strata)
                applyFrameLayers()
                feature.persistMappings()
            end
            info.checked = ((db().defense and db().defense.frameStrata) or defaults.defense.frameStrata) == strata
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local defenseStrata = (db().defense and db().defense.frameStrata) or defaults.defense.frameStrata
    UIDropDownMenu_SetSelectedValue(strataDropdown, defenseStrata)
    UIDropDownMenu_SetText(strataDropdown, defenseStrata)
    frame.defenseStrataDropdown = strataDropdown

    local dLevelHolder = createPlacementInput(frame, L("FRAME_LEVEL"), 72, function(text)
        local value = parseInteger(text)
        if not value then
            if frame.defenseLevelInput then
                frame.defenseLevelInput:SetText(tostring((db().defense and db().defense.frameLevel) or defaults.defense.frameLevel))
            end
            return
        end
        db().defense.frameLevel = Logic.sanitizeFrameLevel(value, defaults.defense.frameLevel)
        applyFrameLayers()
        feature.persistMappings()
        if frame.defenseLevelInput then
            frame.defenseLevelInput:SetText(tostring(db().defense.frameLevel))
        end
    end)
    dLevelHolder:SetPoint("TOPLEFT", strataDropdown, "BOTTOMLEFT", 16, -4)
    frame.defenseLevelInput = dLevelHolder.input
    frame.defenseLevelHolder = dLevelHolder
    if frame.defenseLevelInput then
        frame.defenseLevelInput:SetText(tostring((db().defense and db().defense.frameLevel) or defaults.defense.frameLevel))
    end

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", dLevelHolder, "BOTTOMLEFT", 0, -14)
    editorLabel:SetText(L("DEFENSE_ADD"))
    frame.defenseEditorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 36)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -4)

    local spellDropdown = CreateFrame("Frame", addonName .. "DefenseSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    spellDropdown:SetPoint("LEFT", 0, -2)
    UIDropDownMenu_SetWidth(spellDropdown, 300)
    UIDropDownMenu_JustifyText(spellDropdown, "LEFT")
    UIDropDownMenu_Initialize(spellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells("", true)) do
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
    frame.defenseSpellDropdown = spellDropdown

    local colorDropdown = CreateFrame("Frame", addonName .. "DefenseColorDropdown", editorRow, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("LEFT", spellDropdown, "RIGHT", -4, 0)
    UIDropDownMenu_SetWidth(colorDropdown, 140)
    UIDropDownMenu_Initialize(colorDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for index = 2, #COLOR_PALETTE do
            info.text = feature.colorMenuText(index)
            info.value = index
            info.func = function()
                state.defenseEditorColorIndex = index
                UIDropDownMenu_SetSelectedValue(colorDropdown, index)
                UIDropDownMenu_SetText(colorDropdown, getColorName(index))
            end
            info.checked = state.defenseEditorColorIndex == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(colorDropdown, state.defenseEditorColorIndex or 2)
    UIDropDownMenu_SetText(colorDropdown, getColorName(state.defenseEditorColorIndex or 2))

    local addButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addButton:SetSize(90, 22)
    addButton:SetPoint("LEFT", colorDropdown, "RIGHT", 4, 2)
    addButton:SetText(L("ADD"))
    addButton:SetScript("OnClick", function()
        upsertPriorityEntry("defense", state.defenseEditorSpellId, state.defenseEditorColorIndex or 2)
        updateDefenseRows()
        refreshDefenseBox()
    end)
    frame.defenseAddButton = addButton

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -10)
    listLabel:SetText(L("DEFENSE_LIST"))
    frame.defenseListLabel = listLabel

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -2)
    hint:SetWidth(contentWidth)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("DEFENSE_HINT"))
    frame.defenseHint = hint

    defenseScrollFrame = CreateFrame("ScrollFrame", addonName .. "DefenseScroll", frame, "FauxScrollFrameTemplate")
    defenseScrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    defenseScrollFrame:SetSize(contentWidth - 10, C.PRIORITY_VISIBLE_ROWS * C.PRIORITY_ROW_HEIGHT)
    defenseScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, C.PRIORITY_ROW_HEIGHT, updateDefenseRows)
    end)

    for rowIndex = 1, C.PRIORITY_VISIBLE_ROWS do
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
            if frame.defenseXInput then
                frame.defenseXInput:SetText(tostring(db().defense.x or defaults.defense.x))
            end
            if frame.defenseYInput then
                frame.defenseYInput:SetText(tostring(db().defense.y or defaults.defense.y))
            end
            if frame.defenseLevelInput then
                frame.defenseLevelInput:SetText(tostring(db().defense.frameLevel or defaults.defense.frameLevel))
            end
            if frame.defenseStrataDropdown then
                local strata = db().defense.frameStrata or defaults.defense.frameStrata
                UIDropDownMenu_SetSelectedValue(frame.defenseStrataDropdown, strata)
                UIDropDownMenu_SetText(frame.defenseStrataDropdown, strata)
            end
        end
        bindPriorityRows(defenseRows, defenseScrollFrame, emptyDefenseText, "defense", updateDefenseRows)
    end
end

local function createBlacklistOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText(L("BLACKLIST_TITLE"))
    frame.blacklistTitle = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("BLACKLIST_SUBTITLE"))
    frame.blacklistSubtitle = subtitle

    local filterHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterHint:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
    filterHint:SetWidth(contentWidth)
    filterHint:SetJustifyH("LEFT")
    filterHint:SetText(L("BLACKLIST_HINT"))
    frame.blacklistFilterHint = filterHint

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", filterHint, "BOTTOMLEFT", 0, -8)
    editorLabel:SetText(L("BLACKLIST_ADD"))
    frame.blacklistEditorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 36)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -2)

    local spellDropdown = CreateFrame("Frame", addonName .. "BlacklistSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    spellDropdown:SetPoint("LEFT", 0, -2)
    UIDropDownMenu_SetWidth(spellDropdown, 280)
    UIDropDownMenu_Initialize(spellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells("", true)) do
            info.text = spellInfo.name
            info.value = spellInfo.spellId
            info.func = function()
                state.blacklistEditorSpellId = spellInfo.spellId
                UIDropDownMenu_SetSelectedValue(spellDropdown, spellInfo.spellId)
                UIDropDownMenu_SetText(spellDropdown, spellInfo.name)
            end
            info.checked = state.blacklistEditorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local addButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addButton:SetSize(80, 22)
    addButton:SetPoint("LEFT", spellDropdown, "RIGHT", 4, 2)
    addButton:SetText(L("ADD"))
    addButton:SetScript("OnClick", function()
        if feature.addExcludeSpell("entries", state.blacklistEditorSpellId) then
            updateBlacklistRows()
            updateSpellState()
        end
    end)
    frame.blacklistAddButton = addButton

    -- Two shorter lists so blacklist + cooldown sections fit one tab.
    local BL_SECTION_ROWS = 3

    local addCurrentButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addCurrentButton:SetSize(100, 22)
    addCurrentButton:SetPoint("LEFT", addButton, "RIGHT", 6, 0)
    addCurrentButton:SetText(L("BLACKLIST_ADD_CURRENT"))
    addCurrentButton:SetScript("OnClick", function()
        -- Match the on-screen main box, not only the assist pick under a proc.
        local spellId = state.activeProcSpellId or state.currentSpellId
        if not spellId then
            return
        end
        state.blacklistEditorSpellId = spellId
        feature.addExcludeSpell("entries", spellId)
        updateBlacklistRows()
        updateSpellState()
    end)
    frame.blacklistAddCurrentButton = addCurrentButton

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", editorRow, "BOTTOMLEFT", 0, -8)
    listLabel:SetText(L("BLACKLIST_LIST"))
    frame.blacklistListLabel = listLabel

    blacklistScrollFrame = CreateFrame("ScrollFrame", addonName .. "BlacklistScroll", frame, "FauxScrollFrameTemplate")
    blacklistScrollFrame:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)
    blacklistScrollFrame:SetSize(contentWidth - 10, BL_SECTION_ROWS * C.PRIORITY_ROW_HEIGHT)
    blacklistScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, C.PRIORITY_ROW_HEIGHT, updateBlacklistRows)
    end)

    for rowIndex = 1, BL_SECTION_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(contentWidth - 24, C.PRIORITY_ROW_HEIGHT)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", blacklistScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", blacklistRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enable:SetPoint("LEFT", 0, 0)
        row.enable:SetSize(24, 24)
        row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.spellText:SetPoint("LEFT", row.enable, "RIGHT", 8, 0)
        row.spellText:SetWidth(420)
        row.spellText:SetJustifyH("LEFT")
        row.deleteButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        row.deleteButton:SetSize(70, 20)
        row.deleteButton:SetPoint("RIGHT", 0, 0)
        row.deleteButton:SetText(L("DELETE"))
        row:Hide()
        blacklistRows[rowIndex] = row
    end

    emptyBlacklistText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyBlacklistText:SetPoint("TOPLEFT", blacklistScrollFrame, "TOPLEFT", 8, -30)
    emptyBlacklistText:SetWidth(contentWidth - 40)
    emptyBlacklistText:SetJustifyH("LEFT")
    emptyBlacklistText:SetText(L("BLACKLIST_EMPTY"))
    emptyBlacklistText:Hide()

    local cdSection = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdSection:SetPoint("TOPLEFT", blacklistScrollFrame, "BOTTOMLEFT", 0, -10)
    cdSection:SetText(L("BLACKLIST_CD_SECTION"))
    frame.blacklistCdSection = cdSection

    local enableCheck = CreateFrame("CheckButton", addonName .. "BlacklistEnable", frame, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", cdSection, "BOTTOMLEFT", 0, -4)
    enableCheck.text:SetText(L("BLACKLIST_ENABLE"))
    enableCheck:SetScript("OnClick", function(self)
        setBlacklistEnabled(self:GetChecked() and true or false, false)
    end)
    frame.blacklistEnable = enableCheck

    local keyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keyLabel:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -4)
    keyLabel:SetText(L("BLACKLIST_TOGGLE_KEY"))
    frame.blacklistKeyLabel = keyLabel

    local keyValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keyValue:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    keyValue:SetWidth(220)
    keyValue:SetJustifyH("LEFT")
    frame.blacklistKeyValue = keyValue

    local bindButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    bindButton:SetSize(100, 22)
    bindButton:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -4)
    bindButton:SetText(L("BLACKLIST_BIND"))
    bindButton:SetScript("OnClick", function()
        if state.bindingListen then
            stopBindingListen()
        else
            startBindingListen()
        end
    end)
    frame.blacklistBindButton = bindButton

    local clearButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    clearButton:SetSize(80, 22)
    clearButton:SetPoint("LEFT", bindButton, "RIGHT", 8, 0)
    clearButton:SetText(L("BLACKLIST_CLEAR_KEY"))
    clearButton:SetScript("OnClick", function()
        getBlacklistSettings().toggleKey = nil
        stopBindingListen()
        applyBlacklistBinding()
        feature.persistMappings()
        updateBlacklistRows()
    end)
    frame.blacklistClearButton = clearButton

    local bindHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindHint:SetPoint("TOPLEFT", bindButton, "BOTTOMLEFT", 0, -4)
    bindHint:SetWidth(contentWidth)
    bindHint:SetJustifyH("LEFT")
    bindHint:SetText(L("BLACKLIST_BIND_HINT"))
    frame.blacklistBindHint = bindHint

    local bindWarn = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindWarn:SetPoint("TOPLEFT", bindHint, "BOTTOMLEFT", 0, -2)
    bindWarn:SetWidth(contentWidth)
    bindWarn:SetJustifyH("LEFT")
    bindWarn:SetText(L("BLACKLIST_BIND_WARN"))
    frame.blacklistBindWarn = bindWarn

    local cdHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdHint:SetPoint("TOPLEFT", bindWarn, "BOTTOMLEFT", 0, -4)
    cdHint:SetWidth(contentWidth)
    cdHint:SetJustifyH("LEFT")
    cdHint:SetText(L("BLACKLIST_CD_HINT"))
    frame.blacklistCdHint = cdHint

    local cdEditorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdEditorLabel:SetPoint("TOPLEFT", cdHint, "BOTTOMLEFT", 0, -6)
    cdEditorLabel:SetText(L("BLACKLIST_CD_ADD"))
    frame.blacklistCdEditorLabel = cdEditorLabel

    local cdEditorRow = CreateFrame("Frame", nil, frame)
    cdEditorRow:SetSize(contentWidth, 36)
    cdEditorRow:SetPoint("TOPLEFT", cdEditorLabel, "BOTTOMLEFT", 0, -2)

    local cdSpellDropdown = CreateFrame("Frame", addonName .. "CooldownExcludeSpellDropdown", cdEditorRow, "UIDropDownMenuTemplate")
    cdSpellDropdown:SetPoint("LEFT", 0, -2)
    UIDropDownMenu_SetWidth(cdSpellDropdown, 280)
    UIDropDownMenu_Initialize(cdSpellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells("", true)) do
            info.text = spellInfo.name
            info.value = spellInfo.spellId
            info.func = function()
                state.cooldownEditorSpellId = spellInfo.spellId
                UIDropDownMenu_SetSelectedValue(cdSpellDropdown, spellInfo.spellId)
                UIDropDownMenu_SetText(cdSpellDropdown, spellInfo.name)
            end
            info.checked = state.cooldownEditorSpellId == spellInfo.spellId
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local cdAddButton = CreateFrame("Button", nil, cdEditorRow, "GameMenuButtonTemplate")
    cdAddButton:SetSize(80, 22)
    cdAddButton:SetPoint("LEFT", cdSpellDropdown, "RIGHT", 4, 2)
    cdAddButton:SetText(L("ADD"))
    cdAddButton:SetScript("OnClick", function()
        if feature.addExcludeSpell("cooldowns", state.cooldownEditorSpellId) then
            updateCooldownExcludeRows()
            updateSpellState()
        end
    end)
    frame.blacklistCdAddButton = cdAddButton

    local cdAddCurrentButton = CreateFrame("Button", nil, cdEditorRow, "GameMenuButtonTemplate")
    cdAddCurrentButton:SetSize(100, 22)
    cdAddCurrentButton:SetPoint("LEFT", cdAddButton, "RIGHT", 6, 0)
    cdAddCurrentButton:SetText(L("BLACKLIST_ADD_CURRENT"))
    cdAddCurrentButton:SetScript("OnClick", function()
        local spellId = state.activeProcSpellId or state.currentSpellId
        if not spellId then
            return
        end
        state.cooldownEditorSpellId = spellId
        feature.addExcludeSpell("cooldowns", spellId)
        updateCooldownExcludeRows()
        updateSpellState()
    end)
    frame.blacklistCdAddCurrentButton = cdAddCurrentButton

    local cdListLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdListLabel:SetPoint("TOPLEFT", cdEditorRow, "BOTTOMLEFT", 0, -6)
    cdListLabel:SetText(L("BLACKLIST_CD_LIST"))
    frame.blacklistCdListLabel = cdListLabel

    cooldownExcludeScrollFrame = CreateFrame("ScrollFrame", addonName .. "CooldownExcludeScroll", frame, "FauxScrollFrameTemplate")
    cooldownExcludeScrollFrame:SetPoint("TOPLEFT", cdListLabel, "BOTTOMLEFT", 0, -6)
    cooldownExcludeScrollFrame:SetSize(contentWidth - 10, BL_SECTION_ROWS * C.PRIORITY_ROW_HEIGHT)
    cooldownExcludeScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, C.PRIORITY_ROW_HEIGHT, updateCooldownExcludeRows)
    end)

    for rowIndex = 1, BL_SECTION_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(contentWidth - 24, C.PRIORITY_ROW_HEIGHT)
        if rowIndex == 1 then
            row:SetPoint("TOPLEFT", cooldownExcludeScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", cooldownExcludeRows[rowIndex - 1], "BOTTOMLEFT", 0, 0)
        end
        row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enable:SetPoint("LEFT", 0, 0)
        row.enable:SetSize(24, 24)
        row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.spellText:SetPoint("LEFT", row.enable, "RIGHT", 8, 0)
        row.spellText:SetWidth(420)
        row.spellText:SetJustifyH("LEFT")
        row.deleteButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        row.deleteButton:SetSize(70, 20)
        row.deleteButton:SetPoint("RIGHT", 0, 0)
        row.deleteButton:SetText(L("DELETE"))
        row:Hide()
        cooldownExcludeRows[rowIndex] = row
    end

    emptyCooldownExcludeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyCooldownExcludeText:SetPoint("TOPLEFT", cooldownExcludeScrollFrame, "TOPLEFT", 8, -30)
    emptyCooldownExcludeText:SetWidth(contentWidth - 40)
    emptyCooldownExcludeText:SetJustifyH("LEFT")
    emptyCooldownExcludeText:SetText(L("BLACKLIST_CD_EMPTY"))
    emptyCooldownExcludeText:Hide()

    local function fillExcludeRows(entries, rows, scrollFrame, emptyText, rowCount, refreshFn)
        entries = entries or {}
        local total = #entries
        local offset = 0
        if scrollFrame then
            FauxScrollFrame_Update(scrollFrame, total, rowCount, C.PRIORITY_ROW_HEIGHT)
            offset = FauxScrollFrame_GetOffset(scrollFrame)
        end
        for rowIndex = 1, rowCount do
            local row = rows[rowIndex]
            local entry = entries[offset + rowIndex]
            if entry then
                local entryIndex = offset + rowIndex
                row:Show()
                row.enable:SetChecked(entry.enabled ~= false)
                row.spellText:SetText(getSpellNameSafe(entry.spellId))
                row.deleteButton:SetText(L("DELETE"))
                row.enable:SetScript("OnClick", function(self)
                    entry.enabled = self:GetChecked() and true or false
                    -- sanitizeBlacklistEntries rebuilds the array with fresh
                    -- tables, so the captured `entry`/`entries` become orphans.
                    -- Re-render to rebind the handlers, or a second click (and
                    -- the row's Delete) writes to a detached table.
                    sanitizeSettings({skipBind = true})
                    refreshFn()
                    updateSpellState()
                end)
                row.deleteButton:SetScript("OnClick", function()
                    table.remove(entries, entryIndex)
                    sanitizeSettings({skipBind = true})
                    refreshFn()
                    updateSpellState()
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

    updateCooldownExcludeRows = function()
        local blacklist = getBlacklistSettings()
        fillExcludeRows(
            blacklist.cooldowns,
            cooldownExcludeRows,
            cooldownExcludeScrollFrame,
            emptyCooldownExcludeText,
            BL_SECTION_ROWS,
            updateCooldownExcludeRows
        )
    end

    updateBlacklistRows = function()
        local blacklist = getBlacklistSettings()
        if frame.blacklistEnable then
            frame.blacklistEnable:SetChecked(blacklist.enabled == true)
        end
        if frame.blacklistKeyValue then
            if state.bindingListen then
                frame.blacklistKeyValue:SetText(L("BLACKLIST_LISTENING"))
            else
                frame.blacklistKeyValue:SetText(formatBindingKey(blacklist.toggleKey))
            end
        end
        if frame.blacklistBindButton then
            frame.blacklistBindButton:SetText(state.bindingListen and L("BLACKLIST_LISTENING") or L("BLACKLIST_BIND"))
        end

        fillExcludeRows(
            blacklist.entries,
            blacklistRows,
            blacklistScrollFrame,
            emptyBlacklistText,
            BL_SECTION_ROWS,
            updateBlacklistRows
        )
        if updateCooldownExcludeRows then
            updateCooldownExcludeRows()
        end
    end
end

local function createProcOptionsPanel(frame)
    local contentWidth = frame:GetWidth() - 24

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText(L("PROCS_TITLE"))
    frame.procTitle = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth(contentWidth)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("PROCS_SUBTITLE"))
    frame.procSubtitle = subtitle

    local editorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    editorLabel:SetText(L("PROCS_ADD"))
    frame.procEditorLabel = editorLabel

    local editorRow = CreateFrame("Frame", nil, frame)
    editorRow:SetSize(contentWidth, 36)
    editorRow:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -6)

    local spellDropdown = CreateFrame("Frame", addonName .. "ProcSpellDropdown", editorRow, "UIDropDownMenuTemplate")
    spellDropdown:SetPoint("LEFT", 0, -2)
    UIDropDownMenu_SetWidth(spellDropdown, 300)
    UIDropDownMenu_Initialize(spellDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, spellInfo in ipairs(getFilteredAvailableSpells("", true)) do
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
    colorDropdown:SetPoint("LEFT", spellDropdown, "RIGHT", -4, 0)
    UIDropDownMenu_SetWidth(colorDropdown, 140)
    UIDropDownMenu_Initialize(colorDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for index = 2, #COLOR_PALETTE do
            info.text = feature.colorMenuText(index)
            info.value = index
            info.func = function()
                state.procEditorColorIndex = index
                UIDropDownMenu_SetSelectedValue(colorDropdown, index)
                UIDropDownMenu_SetText(colorDropdown, getColorName(index))
            end
            info.checked = state.procEditorColorIndex == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(colorDropdown, state.procEditorColorIndex or 2)
    UIDropDownMenu_SetText(colorDropdown, getColorName(state.procEditorColorIndex or 2))

    local addButton = CreateFrame("Button", nil, editorRow, "GameMenuButtonTemplate")
    addButton:SetSize(90, 22)
    addButton:SetPoint("LEFT", colorDropdown, "RIGHT", 4, 2)
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
            if Eval.isProcActive(spellInfo.spellId) and not known[spellInfo.spellId] then
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
    suggestHint:SetPoint("TOPLEFT", suggestButton, "BOTTOMLEFT", 0, -4)
    suggestHint:SetWidth(contentWidth)
    suggestHint:SetJustifyH("LEFT")
    suggestHint:SetText(L("PROCS_SUGGEST_HINT"))
    frame.procSuggestHint = suggestHint

    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", suggestHint, "BOTTOMLEFT", 0, -10)
    listLabel:SetText(L("PROCS_LIST"))
    frame.procListLabel = listLabel

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -2)
    hint:SetWidth(contentWidth)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("PROCS_HINT"))
    frame.procHint = hint

    procScrollFrame = CreateFrame("ScrollFrame", addonName .. "ProcScroll", frame, "FauxScrollFrameTemplate")
    procScrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    procScrollFrame:SetSize(contentWidth - 10, C.PRIORITY_VISIBLE_ROWS * C.PRIORITY_ROW_HEIGHT)
    procScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, C.PRIORITY_ROW_HEIGHT, updateProcRows)
    end)

    for rowIndex = 1, C.PRIORITY_VISIBLE_ROWS do
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
            -- Keep enabled so the tab does not look "unavailable"; lock PUSHED state.
            button:SetButtonState("PUSHED", true)
        else
            button:SetButtonState("NORMAL", false)
        end
    end
    if tabKey == "defense" and updateDefenseRows then
        updateDefenseRows()
    elseif tabKey == "procs" and updateProcRows then
        updateProcRows()
    elseif tabKey == "blacklist" and updateBlacklistRows then
        updateBlacklistRows()
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
        if optionsTabs.blacklist then
            optionsTabs.blacklist:SetText(L("TAB_BLACKLIST"))
        end
    end
    if options.resetButton then
        options.resetButton:SetText(L("RESET_DEFAULTS"))
    end
    if options.closeButton then
        options.closeButton:SetText(L("CLOSE"))
    end
    if options.languageLabel then
        options.languageLabel:SetText(L("LANGUAGE"))
    end
    if options.langEn then
        options.langEn:SetText(L("LANG_EN"))
    end
    if options.langKo then
        options.langKo:SetText(L("LANG_KO"))
    end
    if options.minimapCheck and options.minimapCheck.text then
        options.minimapCheck.text:SetText(L("MINIMAP_BUTTON"))
        options.minimapCheck:SetChecked(db().showMinimapButton ~= false)
    end

    local main = optionsPanels.main
    if main then
        if main.mainTitle then main.mainTitle:SetText(L("MAIN_TITLE")) end
        if main.mainSubtitle then main.mainSubtitle:SetText(L("MAIN_SUBTITLE")) end
        if main.mapCurrentButton then main.mapCurrentButton:SetText(L("MAP_CURRENT")) end
        if main.editorLabel then main.editorLabel:SetText(L("QUICK_EDITOR")) end
        if main.searchHolder and main.searchHolder.label then
            main.searchHolder.label:SetText(L("SEARCH"))
        end
        if main.searchHint then main.searchHint:SetText(L("SEARCH_HINT")) end
        if main.listLabel then main.listLabel:SetText(L("SAVED_MAPPINGS")) end
        if main.spellHeader then main.spellHeader:SetText(L("SPELL")) end
        if main.colorHeader then main.colorHeader:SetText(L("COLOR")) end
        if main.glowHeader then main.glowHeader:SetText(L("GLOW")) end
        if main.showHeader then main.showHeader:SetText(L("SHOW")) end
        if main.deleteHeader then main.deleteHeader:SetText(L("DELETE")) end
        if main.overridesLabel then main.overridesLabel:SetText(L("STATE_OVERRIDES")) end
        if main.overridesHint then main.overridesHint:SetText(L("STATE_OVERRIDES_HINT")) end
        if main.placementLabel then main.placementLabel:SetText(L("INDICATOR")) end
        if main.layerLabel then main.layerLabel:SetText(L("FRAME_LAYER")) end
        if main.mainLevelHolder and main.mainLevelHolder.label then
            main.mainLevelHolder.label:SetText(L("FRAME_LEVEL"))
        end
        if main.sizeHolder and main.sizeHolder.label then main.sizeHolder.label:SetText(L("SIZE")) end
        if main.xHolder and main.xHolder.label then main.xHolder.label:SetText(L("X")) end
        if main.yHolder and main.yHolder.label then main.yHolder.label:SetText(L("Y")) end
        if main.interruptEnable and main.interruptEnable.text then
            main.interruptEnable.text:SetText(L("INTERRUPT_ENABLE"))
            main.interruptEnable:SetChecked(db().interruptEnabled ~= false)
        end
        if main.interruptHint then main.interruptHint:SetText(L("INTERRUPT_HINT")) end
        if markerToggleCheck and markerToggleCheck.text then
            markerToggleCheck.text:SetText(L("SHOW_MARKER"))
        end
        if castingOverrideCheck and castingOverrideCheck.text then
            castingOverrideCheck.text:SetText(L("CASTING"))
        end
        if channelingOverrideCheck and channelingOverrideCheck.text then
            channelingOverrideCheck.text:SetText(L("CHANNELING"))
        end
        if empowerOverrideCheck and empowerOverrideCheck.text then
            empowerOverrideCheck.text:SetText(L("EMPOWER"))
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
        if defense.defensePlacementLabel then defense.defensePlacementLabel:SetText(L("DEFENSE_PLACEMENT")) end
        if defense.defenseLayerLabel then defense.defenseLayerLabel:SetText(L("FRAME_LAYER")) end
        if defense.defenseLevelHolder and defense.defenseLevelHolder.label then
            defense.defenseLevelHolder.label:SetText(L("FRAME_LEVEL"))
        end
        if defense.defenseSizeHolder and defense.defenseSizeHolder.label then
            defense.defenseSizeHolder.label:SetText(L("SIZE"))
        end
        if defense.defenseXHolder and defense.defenseXHolder.label then
            defense.defenseXHolder.label:SetText(L("X"))
        end
        if defense.defenseYHolder and defense.defenseYHolder.label then
            defense.defenseYHolder.label:SetText(L("Y"))
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

    local blacklist = optionsPanels.blacklist
    if blacklist then
        if blacklist.blacklistTitle then blacklist.blacklistTitle:SetText(L("BLACKLIST_TITLE")) end
        if blacklist.blacklistSubtitle then blacklist.blacklistSubtitle:SetText(L("BLACKLIST_SUBTITLE")) end
        if blacklist.blacklistEnable and blacklist.blacklistEnable.text then
            blacklist.blacklistEnable.text:SetText(L("BLACKLIST_ENABLE"))
        end
        if blacklist.blacklistKeyLabel then blacklist.blacklistKeyLabel:SetText(L("BLACKLIST_TOGGLE_KEY")) end
        if blacklist.blacklistBindButton then blacklist.blacklistBindButton:SetText(L("BLACKLIST_BIND")) end
        if blacklist.blacklistClearButton then blacklist.blacklistClearButton:SetText(L("BLACKLIST_CLEAR_KEY")) end
        if blacklist.blacklistBindHint then blacklist.blacklistBindHint:SetText(L("BLACKLIST_BIND_HINT")) end
        if blacklist.blacklistBindWarn then blacklist.blacklistBindWarn:SetText(L("BLACKLIST_BIND_WARN")) end
        if blacklist.blacklistFilterHint then blacklist.blacklistFilterHint:SetText(L("BLACKLIST_HINT")) end
        if blacklist.blacklistEditorLabel then blacklist.blacklistEditorLabel:SetText(L("BLACKLIST_ADD")) end
        if blacklist.blacklistListLabel then blacklist.blacklistListLabel:SetText(L("BLACKLIST_LIST")) end
        if blacklist.blacklistAddButton then blacklist.blacklistAddButton:SetText(L("ADD")) end
        if blacklist.blacklistAddCurrentButton then
            blacklist.blacklistAddCurrentButton:SetText(L("BLACKLIST_ADD_CURRENT"))
        end
        if emptyBlacklistText then emptyBlacklistText:SetText(L("BLACKLIST_EMPTY")) end
        if blacklist.blacklistCdSection then blacklist.blacklistCdSection:SetText(L("BLACKLIST_CD_SECTION")) end
        if blacklist.blacklistCdHint then blacklist.blacklistCdHint:SetText(L("BLACKLIST_CD_HINT")) end
        if blacklist.blacklistCdEditorLabel then blacklist.blacklistCdEditorLabel:SetText(L("BLACKLIST_CD_ADD")) end
        if blacklist.blacklistCdListLabel then blacklist.blacklistCdListLabel:SetText(L("BLACKLIST_CD_LIST")) end
        if blacklist.blacklistCdAddButton then blacklist.blacklistCdAddButton:SetText(L("ADD")) end
        if blacklist.blacklistCdAddCurrentButton then
            blacklist.blacklistCdAddCurrentButton:SetText(L("BLACKLIST_ADD_CURRENT"))
        end
        if emptyCooldownExcludeText then emptyCooldownExcludeText:SetText(L("BLACKLIST_CD_EMPTY")) end
    end

    updateEditorControls()
    updateCurrentSpellText()
    if updateMappingRows then
        updateMappingRows()
    end
    if updateDefenseRows then
        updateDefenseRows()
    end
    if updateProcRows then
        updateProcRows()
    end
    if updateBlacklistRows then
        updateBlacklistRows()
    end
end

local function createOptionsFooter(frame)
    local languageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    languageLabel:SetPoint("BOTTOMLEFT", 16, 28)
    languageLabel:SetText(L("LANGUAGE"))
    frame.languageLabel = languageLabel

    local langEn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    langEn:SetSize(72, 20)
    langEn:SetPoint("LEFT", languageLabel, "RIGHT", 8, 0)
    langEn:SetText(L("LANG_EN"))
    langEn:SetScript("OnClick", function()
        db().locale = "en"
        refreshOptionsLocale()
        refreshAllEditorViews()
        refreshVisibility()
    end)
    frame.langEn = langEn

    local langKo = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    langKo:SetSize(72, 20)
    langKo:SetPoint("LEFT", langEn, "RIGHT", 6, 0)
    langKo:SetText(L("LANG_KO"))
    langKo:SetScript("OnClick", function()
        db().locale = "ko"
        refreshOptionsLocale()
        refreshAllEditorViews()
        refreshVisibility()
    end)
    frame.langKo = langKo

    local minimapCheck = CreateFrame("CheckButton", addonName .. "MinimapToggle", frame, "UICheckButtonTemplate")
    minimapCheck:SetPoint("LEFT", langKo, "RIGHT", 16, 0)
    minimapCheck.text:SetText(L("MINIMAP_BUTTON"))
    minimapCheck:SetScript("OnClick", function(self)
        db().showMinimapButton = self:GetChecked() and true or false
        refreshMinimapButton()
    end)
    frame.minimapCheck = minimapCheck

    local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", -16, 14)
    resetButton:SetSize(140, 24)
    resetButton:SetText(L("RESET_DEFAULTS"))
    resetButton:SetScript("OnClick", feature.confirmResetToDefaults)
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
        stopBindingListen()
        setPreview(nil)
        refreshVisibility()
    end)
end

local function createOptionsWindow()
    options = CreateFrame("Frame", "ShinkiliOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    options:SetSize(C.OPTIONS_WIDTH, C.OPTIONS_HEIGHT)
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
    local tabWidth = 88
    local tabGap = 4
    local function makeTab(key, labelKey, index)
        local button = CreateFrame("Button", nil, options, "GameMenuButtonTemplate")
        button:SetSize(tabWidth, 22)
        button:SetPoint("TOPLEFT", 14 + index * (tabWidth + tabGap), tabY)
        button:SetText(L(labelKey))
        button:SetScript("OnClick", function()
            selectOptionsTab(key)
        end)
        optionsTabs[key] = button
        return button
    end
    makeTab("main", "TAB_MAIN", 0)
    makeTab("defense", "TAB_DEFENSE", 1)
    makeTab("procs", "TAB_PROCS", 2)
    makeTab("blacklist", "TAB_BLACKLIST", 3)

    local panelTop = -56
    local panelHeight = C.OPTIONS_HEIGHT - 112
    local panelWidth = C.OPTIONS_WIDTH - 28

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

    local blacklistPanel = CreateFrame("Frame", nil, options)
    blacklistPanel:SetPoint("TOPLEFT", 14, panelTop)
    blacklistPanel:SetSize(panelWidth, panelHeight)
    createBlacklistOptionsPanel(blacklistPanel)
    blacklistPanel:Hide()
    optionsPanels.blacklist = blacklistPanel

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

    -- Layout matches LibDBIcon mainline (RaiderIO / Leatrix Plus).
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture(136467) -- Interface\\Minimap\\UI-Minimap-Background

    -- Concentric color discs, circular-clipped like RaiderIO icons.
    local iconMask = "Interface\\Minimap\\UI-Minimap-Background"
    local function addColorDisc(subLevel, size, r, g, b)
        local tex = button:CreateTexture(nil, "ARTWORK", nil, subLevel)
        tex:SetSize(size, size)
        tex:SetPoint("CENTER")
        tex:SetMask(iconMask)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(r, g, b, 1)
        return tex
    end
    addColorDisc(0, 18, 0.70, 0.20, 1.00) -- purple base (LibDBIcon icon size)
    addColorDisc(1, 12, 0.00, 0.90, 0.25) -- green mid
    addColorDisc(2, 7, 1.00, 0.82, 0.12)  -- gold core

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture(136430) -- Interface\\Minimap\\MiniMap-TrackingBorder
    border:SetPoint("TOPLEFT", button, "TOPLEFT")

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
    print(L("CMD_MAP"))
    print(L("CMD_LOCK"))
    print(L("CMD_UNLOCK"))
    print(L("CMD_MARKER"))
    print(L("CMD_MINIMAP"))
    print(L("CMD_SIZE"))
    print(L("CMD_RESET"))
    print(L("CMD_LANG"))
    print(L("CMD_BLACKLIST"))
    print(L("CMD_WHY"))
end

--------------------------------------------------------------------------------
-- /sk why
--
-- Without this the pick is unauditable: nothing else shows which SimC condition
-- was readable, which one vetoed a promotion, or whether the secret-value probe
-- still works after a patch. Chat stays truncated; the export EditBox gets the
-- full plain-text dump for agent paste.
--------------------------------------------------------------------------------

local WHY_CHAT_MAX_ROWS = 12

local function whyPrint(text)
    print("|cff33ff99Shinkili|r " .. text)
end

local function printWhyReport()
    -- Nested helpers keep the main chunk under Lua's 200-local cap.
    local function ensureWhyExportFrame()
        local export = feature.whyExport
        if export then
            return export
        end

        export = {}
        feature.whyExport = export

        local frame = CreateFrame("Frame", "ShinkiliWhyExport", UIParent, "BackdropTemplate")
        frame:SetSize(560, 420)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(1000)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:EnableKeyboard(true)
        frame:SetClampedToScreen(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
        frame:SetBackdropBorderColor(0.20, 1.00, 0.60, 0.85)
        frame:Hide()
        frame:SetScript("OnHide", function()
            if export.edit then
                export.edit:ClearFocus()
            end
        end)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetTextColor(0.20, 1.00, 0.60, 1)

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPRIGHT", -16, -18)
        hint:SetTextColor(0.75, 0.75, 0.75, 1)

        local scroll = CreateFrame("ScrollFrame", "ShinkiliWhyExportScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -42)
        scroll:SetPoint("BOTTOMRIGHT", -36, 48)

        local edit = CreateFrame("EditBox", "ShinkiliWhyExportEdit", scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(_G.GameFontHighlightSmall)
        edit:SetTextInsets(4, 4, 4, 4)
        edit:SetWidth(500)
        edit:SetScript("OnEscapePressed", function()
            frame:Hide()
        end)
        edit:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        scroll:SetScrollChild(edit)

        local close = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        close:SetSize(110, 24)
        close:SetPoint("BOTTOM", 0, 12)
        close:SetScript("OnClick", function()
            frame:Hide()
        end)

        local special = _G.UISpecialFrames
        if special then
            special[#special + 1] = "ShinkiliWhyExport"
        end

        export.frame = frame
        export.edit = edit
        export.scroll = scroll
        export.title = title
        export.hint = hint
        export.close = close
        return export
    end

    local function showWhyExport(text)
        local export = ensureWhyExportFrame()
        local body = text or ""
        export.title:SetText(L("WHY_REPORT_HEADER"))
        export.hint:SetText(L("WHY_EXPORT_HINT"))
        export.close:SetText(L("CLOSE"))
        export.edit:SetText(body)

        local lineCount = 1
        for _ in body:gmatch("\n") do
            lineCount = lineCount + 1
        end
        local scrollWidth = export.scroll:GetWidth()
        if scrollWidth and scrollWidth > 0 then
            export.edit:SetWidth(scrollWidth)
        end
        export.edit:SetHeight(math.max(320, lineCount * 14 + 16))
        export.scroll:SetVerticalScroll(0)

        export.frame:Show()
        export.edit:SetFocus()
        export.edit:HighlightText()
    end

    local function buildWhyReport()
        local chatLines = {}
        local exportLines = {}

        local function addBoth(text)
            chatLines[#chatLines + 1] = text
            exportLines[#exportLines + 1] = text
        end

        local function addListed(index, total, line)
            exportLines[#exportLines + 1] = line
            if index <= WHY_CHAT_MAX_ROWS then
                chatLines[#chatLines + 1] = line
            elseif index == WHY_CHAT_MAX_ROWS + 1 then
                chatLines[#chatLines + 1] = string.format("    ... %d more", total - WHY_CHAT_MAX_ROWS)
            end
        end

        Eval.beginPass()

        local secrets = Secret.getDiagnostics()
        local function addSecretHealth()
            addBoth(string.format("  secrets: probe=%s issecretvalue=%s auras=%s cooldowns=%s",
                secrets.probeAvailable and "ok" or "UNAVAILABLE",
                secrets.hasIsSecretValue and "yes" or "no",
                secrets.aurasSecret and "secret" or "plain",
                secrets.cooldownsSecret and "secret" or "plain"))
        end

        if not isAssistedCombatAvailable() then
            addBoth(L("WHY_REPORT_HEADER"))
            addBoth("  ac: unavailable - no recommendation is produced")
            -- Probe health is the reason this command exists; report it even when
            -- there is no pick to explain.
            addSecretHealth()
            return chatLines, exportLines
        end

        local simcAssist = db().simcAssist ~= false
        local primary, lookahead, rotation = collectAcPositionInputs()
        local simcEntries, specKey, context = getSimcContextForPick(simcAssist)
        local blacklist = getBlacklistSettings()

        local spellId, reason, detail = Logic.pickRecommendation(primary, lookahead, rotation, simcEntries, {
            blacklistEntries = blacklist.entries,
            blacklistCooldowns = blacklist.cooldowns,
            blacklistEnabled = blacklist.enabled == true,
            simcAssist = simcAssist,
            displayOf = Eval.getDisplaySpellId,
            castability = Eval.getCastability,
            gateVerdict = Eval.evaluateEntry,
            collectDetail = true,
        })

        addBoth(L("WHY_REPORT_HEADER"))
        if spellId then
            addBoth(string.format("  pick: %s (%d) - %s", getSpellNameSafe(spellId), spellId, tostring(reason)))
        else
            addBoth("  pick: none - " .. tostring(reason))
        end

        addSecretHealth()

        if ShinkiliTrack then
            local track = ShinkiliTrack.getDiagnostics()
            addBoth(string.format("  track: scanned=%d cooldowns=%d charges=%d dots=%d pending=%d",
                track.scannedSpells, track.activeCooldowns, track.chargeSpells,
                track.trackedDots, track.pendingDotCasts))
        end

        addBoth(string.format("  ac: primary=%s lookahead=%s rotation=%d",
            primary and tostring(primary) or "-",
            lookahead and tostring(lookahead) or "-",
            rotation and #rotation or 0))

        addBoth(string.format("  pool=%d castable=%d%s",
            detail.poolSize or 0,
            detail.castableSize or 0,
            detail.hardFilterEmpty and "  (all blocked - showing AC anyway)" or ""))
        for index, row in ipairs(detail.pool) do
            addListed(index, #detail.pool,
                string.format("    %s (%d) %s", getSpellNameSafe(row.id), row.id, row.castability))
        end

        if not simcAssist then
            addBoth("  simc: off")
            return chatLines, exportLines
        end
        if not simcEntries or #simcEntries == 0 then
            addBoth(string.format("  simc: no data for %s", specKey or "?"))
            return chatLines, exportLines
        end

        addBoth(string.format("  simc: %s/%s, %d entries", specKey or "?", context or "?", #simcEntries))
        for index, entry in ipairs(simcEntries) do
            local entryId = type(entry) == "table" and entry.id or entry
            local displayId = Eval.getDisplaySpellId(entryId)
            local marks = {}
            for _, gate in ipairs(Eval.describeEntry(entry)) do
                marks[#marks + 1] = gate.kind .. "=" .. gate.verdict
            end
            addListed(index, #simcEntries, string.format("    %s (%s) gates=%s cast=%s%s%s",
                getSpellNameSafe(displayId),
                tostring(displayId),
                Eval.evaluateEntry(entry),
                Eval.getCastability(displayId),
                #marks > 0 and ("  [" .. table.concat(marks, " ") .. "]") or "",
                (spellId == displayId) and "  <== pick" or ""))
        end

        return chatLines, exportLines
    end

    local chatLines, exportLines = buildWhyReport()
    for _, line in ipairs(chatLines) do
        whyPrint(line)
    end
    showWhyExport(table.concat(exportLines, "\n"))
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

    if command == "map" then
        feature.mapCurrentRecommendation()
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
        local raw = trim(value):lower()
        local normalized
        if raw == "en" then
            normalized = "en"
        elseif raw == "ko" or raw == "kr" or raw == "kokr" then
            normalized = "ko"
        else
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

    if command == "blacklist" then
        local normalized = trim(value):lower()
        if normalized == "on" then
            setBlacklistEnabled(true, true)
            print("|cff33ff99Shinkili|r " .. L("MSG_BLACKLIST_ON"))
            return
        end
        if normalized == "off" then
            setBlacklistEnabled(false, true)
            print("|cff33ff99Shinkili|r " .. L("MSG_BLACKLIST_OFF"))
            return
        end
        print("|cff33ff99Shinkili|r " .. L("MSG_BLACKLIST_USAGE"))
        return
    end

    if command == "reset" then
        feature.confirmResetToDefaults()
        return
    end

    if command == "why" then
        printWhyReport()
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
    ShinkiliDB.frameStrata = ShinkiliDB.frameStrata == nil and defaults.frameStrata or ShinkiliDB.frameStrata
    ShinkiliDB.frameLevel = ShinkiliDB.frameLevel == nil and defaults.frameLevel or ShinkiliDB.frameLevel
    ShinkiliDB.overrides = type(ShinkiliDB.overrides) == "table" and ShinkiliDB.overrides or copyDefaultOverrides()
    ShinkiliDB.charMappings = type(ShinkiliDB.charMappings) == "table" and ShinkiliDB.charMappings or {}
    if type(ShinkiliDB.mappings) ~= "table" then
        ShinkiliDB.mappings = {}
    end
    ShinkiliDB.defense = type(ShinkiliDB.defense) == "table" and ShinkiliDB.defense or {
        enabled = defaults.defense.enabled,
        locked = defaults.defense.locked,
        size = defaults.defense.size,
        point = defaults.defense.point,
        relativePoint = defaults.defense.relativePoint,
        x = defaults.defense.x,
        y = defaults.defense.y,
        frameStrata = defaults.defense.frameStrata,
        frameLevel = defaults.defense.frameLevel,
        entries = {},
    }
    ShinkiliDB.procs = type(ShinkiliDB.procs) == "table" and ShinkiliDB.procs or {entries = {}}
    ShinkiliDB.blacklist = type(ShinkiliDB.blacklist) == "table" and ShinkiliDB.blacklist or {
        enabled = false,
        toggleKey = nil,
        entries = {},
        cooldowns = {},
    }
    ShinkiliDB.charProfiles = type(ShinkiliDB.charProfiles) == "table" and ShinkiliDB.charProfiles or {}
    if ShinkiliDB.simcAssist == nil then
        ShinkiliDB.simcAssist = defaults.simcAssist
    end
    if ShinkiliDB.interruptEnabled == nil then
        ShinkiliDB.interruptEnabled = defaults.interruptEnabled
    end
    ShinkiliDB.cooldownBox = nil

    refreshAvailableSpells()
    sanitizeSettings()
    applySize()
    applyPosition()
    applyDefenseSize()
    applyDefensePosition()
    applyFrameLayers()
    applyBlacklistBinding()
    syncPlacementControls()
    updateSpellState()
    refreshMinimapButton()

    addon:RegisterEvent("PLAYER_LOGIN")
    addon:RegisterEvent("PLAYER_ENTERING_WORLD")
    addon:RegisterEvent("PLAYER_REGEN_ENABLED")
    addon:RegisterEvent("PLAYER_REGEN_DISABLED")
    addon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    addon:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    addon:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    addon:RegisterEvent("ACTION_USABLE_CHANGED")
    addon:RegisterEvent("SPELLS_CHANGED")
    -- Local cooldown / charge / DoT reconstruction (see ShinkiliTrack).
    if addon.RegisterUnitEvent then
        addon:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        addon:RegisterUnitEvent("UNIT_AURA", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
        addon:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    end
    addon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    addon:RegisterEvent("SPELL_UPDATE_CHARGES")
    addon:RegisterEvent("PLAYER_TARGET_CHANGED")
    addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    addon:RegisterEvent("PLAYER_TALENT_UPDATE")
    addon:RegisterEvent("TRAIT_CONFIG_UPDATED")

    scanTrackedSpells()

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.05, function()
            if not db() then
                return
            end
            local previousSpellId = state.currentSpellId
            local previousCastState = state.currentCastState
            local previousCastSpellId = state.currentCastSpellId
            local previousProc = state.activeProcSpellId
            local previousDefense = state.defenseSpellId
            local previousReason = state.recommendReason

            updateSpellState()

            local changed = state.currentSpellId ~= previousSpellId
                or state.currentCastState ~= previousCastState
                or state.currentCastSpellId ~= previousCastSpellId
                or state.activeProcSpellId ~= previousProc
                or state.defenseSpellId ~= previousDefense
                or state.recommendReason ~= previousReason

            if changed and state.optionsOpen then
                updateEditorControls()
                updateMappingRows()
            elseif state.optionsOpen then
                updateCurrentSpellText()
            end
        end)
    end
end

-- High-frequency state events: they only feed the tracker. Running the full
-- refresh on every aura tick and cooldown pulse would burn frames for nothing --
-- the 20Hz ticker already repaints. Target interrupt signal is handled separately.
local TRACKER_ONLY_EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_AURA = true,
    SPELL_UPDATE_COOLDOWN = true,
    SPELL_UPDATE_CHARGES = true,
}

local INTERRUPT_SIGNAL_EVENTS = {
    PLAYER_TARGET_CHANGED = true,
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
}

addon:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            initialize()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Character name/realm is reliable here; re-bind per-character/spec profiles.
        sanitizeSettings()
        applySize()
        applyPosition()
        applyDefenseSize()
        applyDefensePosition()
        applyFrameLayers()
        applyBlacklistBinding()
        if state.optionsOpen then
            refreshAllEditorViews()
        end
        updateSpellState()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and state.pendingBlacklistBinding then
        applyBlacklistBinding()
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Persist outgoing spec, then load the incoming bucket (seed clone if new).
        if arg1 == nil or arg1 == "player" then
            feature.persistMappings()
            sanitizeSettings()
            applySize()
            applyPosition()
            applyDefenseSize()
            applyDefensePosition()
            applyFrameLayers()
            applyBlacklistBinding()
            refreshAvailableSpells()
            scanTrackedSpells()
            if state.optionsOpen then
                refreshAllEditorViews()
            end
            updateSpellState()
        end
        -- fall through for tracker/cache refresh
    end

    -- Action-bar usability is the readable stand-in when C_Spell.IsSpellUsable
    -- turns secret, so the slot cache must follow every bar change.
    if event == "ACTION_USABLE_CHANGED" then
        Eval.onActionUsableChanged(arg1)
        return
    end

    if ShinkiliTrack then
        ShinkiliTrack.handleEvent(event, arg1, arg2, arg3)
    end

    -- Interrupt signal is independent of the pick pipeline; do not run full refresh.
    if INTERRUPT_SIGNAL_EVENTS[event] then
        feature.refreshInterrupt()
        return
    end

    if TRACKER_ONLY_EVENTS[event] then
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED"
        or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" then
        Eval.invalidateActionBars()
    end

    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshAvailableSpells()
    end

    -- Out of combat the base-cooldown and charge data is readable; refresh the
    -- static caches whenever the talent build or combat state could have moved.
    if event == "SPELLS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        scanTrackedSpells()
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
