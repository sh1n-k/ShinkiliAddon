-- Player health / primary-power solid-color boxes for KeySim pixel sensing.
-- Color is chosen in-engine via UnitHealthPercent / UnitPowerPercent + a Step
-- ColorCurve. Lua never compares or arithmetics the returned color.

ShinkiliVitals = ShinkiliVitals or {}
local Vitals = ShinkiliVitals

local PLACEHOLDER_RGBA = {0.25, 0.25, 0.25, 0.55}
local STRATA_LIST = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local deps = {}
local initialized = false
local available = false
local boxes = {}
local eventFrame
local optionsPanel
local controlId = 0

local function detectAvailable()
    return C_CurveUtil ~= nil
        and C_CurveUtil.CreateColorCurve ~= nil
        and CreateColor ~= nil
        and UnitHealthPercent ~= nil
        and UnitPowerPercent ~= nil
        and Enum ~= nil
        and Enum.LuaCurveType ~= nil
        and Enum.LuaCurveType.Step ~= nil
end

local function L(key)
    if deps.L then
        return deps.L(key)
    end
    return key
end

local function getSettings()
    if deps.getSettings then
        return deps.getSettings() or {}
    end
    return {}
end

local function getChannel(kind)
    local settings = getSettings()
    local vitals = type(settings.vitals) == "table" and settings.vitals or {}
    return type(vitals[kind]) == "table" and vitals[kind] or {}
end

local function persist()
    if deps.persist then
        deps.persist()
    end
end

local function isOptionsOpen()
    return deps.isOptionsOpen and deps.isOptionsOpen() == true
end

local function paletteColor(index)
    if deps.getPaletteColor then
        local r, g, b, a = deps.getPaletteColor(index)
        return r, g, b, a
    end
    return 0.2, 0.2, 0.2, 1
end

local function clamp(value, minimum, maximum)
    return ShinkiliLogic.clamp(value, minimum, maximum)
end

local function parseInteger(text)
    return ShinkiliLogic.parseInteger(text)
end

local function sanitizeFrameLevel(value, defaultLevel)
    return ShinkiliLogic.sanitizeFrameLevel(value, defaultLevel)
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function createBox(name)
    local box = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:EnableMouse(false)
    box:RegisterForDrag("LeftButton")
    box:SetBackdrop({
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    box:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill:SetTexture("Interface/Buttons/WHITE8X8")
    box.fill:SetPoint("TOPLEFT", 2, -2)
    box.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    box:Hide()
    return box
end

local function applyBoxLayout(kind)
    local box = boxes[kind]
    local channel = getChannel(kind)
    if not box then
        return
    end
    local size = channel.size or 48
    box:SetSize(size, size)
    box:ClearAllPoints()
    box:SetPoint(
        channel.point or "CENTER",
        UIParent,
        channel.relativePoint or "CENTER",
        channel.x or 0,
        channel.y or 0
    )
    if box.SetFrameStrata then
        box:SetFrameStrata(channel.frameStrata or "FULLSCREEN_DIALOG")
    end
    if box.SetFrameLevel then
        box:SetFrameLevel(channel.frameLevel or 190)
    end
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local channel = getChannel(self.vitalsKind)
    channel.point = "CENTER"
    channel.relativePoint = "CENTER"
    channel.x = math.floor((x or 0) + 0.5)
    channel.y = math.floor((y or 0) + 0.5)
    applyBoxLayout(self.vitalsKind)
    persist()
    if Vitals.refreshOptionsValues then
        Vitals.refreshOptionsValues()
    end
end

local function makeColor(r, g, b, a)
    if not CreateColor then
        return nil
    end
    local ok, color = pcall(CreateColor, r, g, b, a)
    if ok then
        return color
    end
    return nil
end

-- Curve domain is the 0-1 health/power fraction (wiki / JustAC). Whether the
-- live client is [0,1] vs [0,100] is 인게임 미검증; Step boundary pixels too.
local function rebuildCurve(box)
    if not available or not box then
        return
    end
    local channel = getChannel(box.vitalsKind)
    local threshold = tonumber(channel.threshold) or 35
    local t = threshold / 100
    local belowR, belowG, belowB, belowA = paletteColor(channel.belowColorIndex)
    local aboveR, aboveG, aboveB, aboveA = paletteColor(channel.aboveColorIndex)
    local belowColor = makeColor(belowR, belowG, belowB, belowA)
    local aboveColor = makeColor(aboveR, aboveG, aboveB, aboveA)
    if not belowColor or not aboveColor then
        return
    end

    local curve = box.curve
    if not curve then
        local ok, created = pcall(C_CurveUtil.CreateColorCurve)
        if not ok or not created then
            return
        end
        curve = created
        box.curve = curve
        if curve.SetType then
            pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
        end
    end
    if curve.ClearPoints then
        pcall(curve.ClearPoints, curve)
    end
    pcall(curve.AddPoint, curve, 0, belowColor)
    pcall(curve.AddPoint, curve, t, aboveColor)
end

local function rebuildCurves()
    rebuildCurve(boxes.health)
    rebuildCurve(boxes.power)
end

local function paintPlaceholder(box)
    local fill = box.fill
    if fill and fill.SetVertexColor then
        fill:SetVertexColor(PLACEHOLDER_RGBA[1], PLACEHOLDER_RGBA[2], PLACEHOLDER_RGBA[3], PLACEHOLDER_RGBA[4])
    end
    box:Show()
end

local function paintLive(box)
    if not available or not box.curve then
        return
    end
    local ok, color
    if box.vitalsKind == "health" then
        ok, color = pcall(UnitHealthPercent, "player", false, box.curve)
    else
        local powerType
        if UnitPowerType then
            local typeOk, resolved = pcall(UnitPowerType, "player")
            if typeOk then
                powerType = resolved
            end
        end
        ok, color = pcall(UnitPowerPercent, "player", powerType, false, box.curve)
    end
    if not ok or color == nil then
        return
    end
    local fill = box.fill
    if not fill or not fill.SetVertexColor then
        return
    end
    -- Pass the engine color through untouched. Do not read, compare, or print it.
    local okPaint, painted = pcall(function()
        if color.GetRGBA then
            fill:SetVertexColor(color:GetRGBA())
            return true
        end
        if color.GetRGB then
            fill:SetVertexColor(color:GetRGB())
            return true
        end
        return false
    end)
    if okPaint and painted then
        box:Show()
    end
end

local function refreshChannel(kind)
    local box = boxes[kind]
    if not box then
        return
    end
    local channel = getChannel(kind)
    local preview = isOptionsOpen() or channel.locked == false
    if not available then
        box:Hide()
        box:EnableMouse(false)
        return
    end
    if channel.enabled == true then
        paintLive(box)
        box:EnableMouse(channel.locked == false)
    elseif preview then
        paintPlaceholder(box)
        box:EnableMouse(channel.locked == false)
    else
        box:Hide()
        box:EnableMouse(false)
    end
end

function Vitals.refreshPreview()
    if not initialized then
        return
    end
    refreshChannel("health")
    refreshChannel("power")
    if Vitals.refreshLocale then
        Vitals.refreshLocale()
    end
end

function Vitals.applyLayout()
    if not initialized then
        return
    end
    available = detectAvailable()
    applyBoxLayout("health")
    applyBoxLayout("power")
    if available then
        rebuildCurves()
    end
    Vitals.refreshPreview()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function onEvent(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit and unit ~= "player" then
            return
        end
        refreshChannel("health")
        return
    end
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        if unit and unit ~= "player" then
            return
        end
        refreshChannel("power")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        refreshChannel("health")
        refreshChannel("power")
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        if unit ~= nil and unit ~= "player" then
            return
        end
        Vitals.applyLayout()
    end
end

local function registerEvents(frame)
    if frame.RegisterUnitEvent then
        pcall(frame.RegisterUnitEvent, frame, "UNIT_HEALTH", "player")
        pcall(frame.RegisterUnitEvent, frame, "UNIT_MAXHEALTH", "player")
        local ok = pcall(frame.RegisterUnitEvent, frame, "UNIT_POWER_FREQUENT", "player")
        if not ok then
            pcall(frame.RegisterUnitEvent, frame, "UNIT_POWER_UPDATE", "player")
        end
    elseif frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, "UNIT_HEALTH")
        pcall(frame.RegisterEvent, frame, "UNIT_MAXHEALTH")
        local ok = pcall(frame.RegisterEvent, frame, "UNIT_POWER_FREQUENT")
        if not ok then
            pcall(frame.RegisterEvent, frame, "UNIT_POWER_UPDATE")
        end
    end
    if frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
        pcall(frame.RegisterEvent, frame, "PLAYER_SPECIALIZATION_CHANGED")
    end
    frame:SetScript("OnEvent", onEvent)
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

local function colorName(index)
    if deps.getColorName then
        return deps.getColorName(index)
    end
    return tostring(index)
end

local function colorMenuText(index)
    if deps.colorMenuText then
        return deps.colorMenuText(index)
    end
    return colorName(index)
end

local function makeEdit(parent, labelText, width, onApply)
    controlId = controlId + 1
    local holder = CreateFrame("Frame", "ShinkiliVitalsInput" .. controlId, parent)
    holder:SetSize(width, 40)
    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText(labelText)
    holder.input = CreateFrame("EditBox", "ShinkiliVitalsValue" .. controlId, holder, "InputBoxTemplate")
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
        self:ClearFocus()
    end)
    return holder
end

local function initColorDropdown(dropdown, kind, field)
    if not UIDropDownMenu_Initialize then
        return
    end
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then
            return
        end
        local info = UIDropDownMenu_CreateInfo()
        local paletteSize = deps.paletteSize or 27
        for index = 2, paletteSize do
            info.text = colorMenuText(index)
            info.value = index
            info.func = function()
                local channel = getChannel(kind)
                channel[field] = index
                if UIDropDownMenu_SetSelectedValue then
                    UIDropDownMenu_SetSelectedValue(dropdown, index)
                end
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(dropdown, colorName(index))
                end
                rebuildCurve(boxes[kind])
                persist()
                Vitals.refreshPreview()
            end
            info.checked = getChannel(kind)[field] == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function initStrataDropdown(dropdown, kind)
    local function getStrata()
        return getChannel(kind).frameStrata or "FULLSCREEN_DIALOG"
    end
    local function setStrata(strata)
        getChannel(kind).frameStrata = strata
        applyBoxLayout(kind)
    end
    if deps.initStrataDropdown then
        deps.initStrataDropdown(dropdown, getStrata, setStrata)
        return
    end
    if not UIDropDownMenu_Initialize then
        return
    end
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then
            return
        end
        local info = UIDropDownMenu_CreateInfo()
        for _, strata in ipairs(STRATA_LIST) do
            info.text = strata
            info.value = strata
            info.func = function()
                setStrata(strata)
                if UIDropDownMenu_SetSelectedValue then
                    UIDropDownMenu_SetSelectedValue(dropdown, strata)
                end
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(dropdown, strata)
                end
                persist()
            end
            info.checked = getStrata() == strata
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function createChannelColumn(parent, kind, titleKey, xOffset)
    local column = CreateFrame("Frame", nil, parent)
    column:SetPoint("TOPLEFT", xOffset, -48)
    column:SetSize(410, 520)

    local title = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(L(titleKey))
    column.title = title

    local enable = CreateFrame("CheckButton", "ShinkiliVitalsEnable" .. kind, column, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    if enable.text then
        enable.text:SetText(L("VITALS_ENABLED"))
    end
    enable:SetScript("OnClick", function(self)
        getChannel(kind).enabled = self:GetChecked() and true or false
        persist()
        Vitals.refreshPreview()
    end)
    column.enable = enable

    local lockCheck = CreateFrame("CheckButton", "ShinkiliVitalsLock" .. kind, column, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -2)
    if lockCheck.text then
        lockCheck.text:SetText(L("LOCK"))
    end
    lockCheck:SetScript("OnClick", function(self)
        getChannel(kind).locked = self:GetChecked() and true or false
        persist()
        Vitals.refreshPreview()
    end)
    column.lock = lockCheck

    local thresholdHolder = makeEdit(column, L("VITALS_THRESHOLD"), 80, function(text)
        local value = parseInteger(text)
        local channel = getChannel(kind)
        if not value then
            column.threshold.input:SetText(tostring(channel.threshold or 35))
            return
        end
        channel.threshold = clamp(value, 1, 99)
        column.threshold.input:SetText(tostring(channel.threshold))
        rebuildCurve(boxes[kind])
        persist()
        Vitals.refreshPreview()
    end)
    thresholdHolder:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -8)
    column.threshold = thresholdHolder

    local aboveLabel = column:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    aboveLabel:SetPoint("TOPLEFT", thresholdHolder, "BOTTOMLEFT", 0, -8)
    aboveLabel:SetText(L("VITALS_COLOR_ABOVE"))
    column.aboveLabel = aboveLabel

    local aboveDropdown = CreateFrame("Frame", "ShinkiliVitalsAbove" .. kind, column, "UIDropDownMenuTemplate")
    aboveDropdown:SetPoint("TOPLEFT", aboveLabel, "BOTTOMLEFT", -16, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(aboveDropdown, 150)
    end
    initColorDropdown(aboveDropdown, kind, "aboveColorIndex")
    column.aboveDropdown = aboveDropdown

    local belowLabel = column:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    belowLabel:SetPoint("TOPLEFT", aboveDropdown, "BOTTOMLEFT", 16, -6)
    belowLabel:SetText(L("VITALS_COLOR_BELOW"))
    column.belowLabel = belowLabel

    local belowDropdown = CreateFrame("Frame", "ShinkiliVitalsBelow" .. kind, column, "UIDropDownMenuTemplate")
    belowDropdown:SetPoint("TOPLEFT", belowLabel, "BOTTOMLEFT", -16, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(belowDropdown, 150)
    end
    initColorDropdown(belowDropdown, kind, "belowColorIndex")
    column.belowDropdown = belowDropdown

    local sizeHolder = makeEdit(column, L("SIZE"), 64, function(text)
        local value = parseInteger(text)
        local channel = getChannel(kind)
        if not value then
            column.size.input:SetText(tostring(channel.size or 48))
            return
        end
        channel.size = clamp(value, 24, 300)
        applyBoxLayout(kind)
        persist()
        Vitals.refreshPreview()
        column.size.input:SetText(tostring(channel.size))
    end)
    sizeHolder:SetPoint("TOPLEFT", belowDropdown, "BOTTOMLEFT", 16, -8)
    column.size = sizeHolder

    local xHolder = makeEdit(column, L("X"), 64, function(text)
        local value = parseInteger(text)
        local channel = getChannel(kind)
        if not value then
            column.x.input:SetText(tostring(channel.x or 0))
            return
        end
        channel.x = clamp(value, -1000, 1000)
        channel.point = "CENTER"
        channel.relativePoint = "CENTER"
        applyBoxLayout(kind)
        persist()
        column.x.input:SetText(tostring(channel.x))
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 12, 0)
    column.x = xHolder

    local yHolder = makeEdit(column, L("Y"), 64, function(text)
        local value = parseInteger(text)
        local channel = getChannel(kind)
        if not value then
            column.y.input:SetText(tostring(channel.y or 0))
            return
        end
        channel.y = clamp(value, -1000, 1000)
        channel.point = "CENTER"
        channel.relativePoint = "CENTER"
        applyBoxLayout(kind)
        persist()
        column.y.input:SetText(tostring(channel.y))
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 12, 0)
    column.y = yHolder

    local layerLabel = column:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layerLabel:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -10)
    layerLabel:SetText(L("FRAME_LAYER"))
    column.layerLabel = layerLabel

    local strataDropdown = CreateFrame("Frame", "ShinkiliVitalsStrata" .. kind, column, "UIDropDownMenuTemplate")
    strataDropdown:SetPoint("TOPLEFT", layerLabel, "BOTTOMLEFT", -16, -4)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(strataDropdown, 160)
    end
    initStrataDropdown(strataDropdown, kind)
    column.strataDropdown = strataDropdown

    local levelHolder = makeEdit(column, L("FRAME_LEVEL"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel(kind)
        if not value then
            column.level.input:SetText(tostring(channel.frameLevel or 190))
            return
        end
        channel.frameLevel = sanitizeFrameLevel(value, 190)
        applyBoxLayout(kind)
        persist()
        column.level.input:SetText(tostring(channel.frameLevel))
    end)
    levelHolder:SetPoint("TOPLEFT", strataDropdown, "BOTTOMLEFT", 16, -4)
    column.level = levelHolder

    return column
end

local function syncColumn(column, kind)
    if not column then
        return
    end
    local channel = getChannel(kind)
    if column.enable then
        column.enable:SetChecked(channel.enabled == true)
    end
    if column.lock then
        column.lock:SetChecked(channel.locked ~= false)
    end
    if column.threshold and column.threshold.input then
        column.threshold.input:SetText(tostring(channel.threshold or 35))
    end
    if column.size and column.size.input then
        column.size.input:SetText(tostring(channel.size or 48))
    end
    if column.x and column.x.input then
        column.x.input:SetText(tostring(channel.x or 0))
    end
    if column.y and column.y.input then
        column.y.input:SetText(tostring(channel.y or 0))
    end
    if column.level and column.level.input then
        column.level.input:SetText(tostring(channel.frameLevel or 190))
    end
    if column.aboveDropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(column.aboveDropdown, channel.aboveColorIndex or 2)
        UIDropDownMenu_SetText(column.aboveDropdown, colorName(channel.aboveColorIndex or 2))
    end
    if column.belowDropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(column.belowDropdown, channel.belowColorIndex or 5)
        UIDropDownMenu_SetText(column.belowDropdown, colorName(channel.belowColorIndex or 5))
    end
    if column.strataDropdown and UIDropDownMenu_SetSelectedValue then
        local strata = channel.frameStrata or "FULLSCREEN_DIALOG"
        UIDropDownMenu_SetSelectedValue(column.strataDropdown, strata)
        UIDropDownMenu_SetText(column.strataDropdown, strata)
    end
end

function Vitals.refreshOptionsValues()
    if not optionsPanel then
        return
    end
    syncColumn(optionsPanel.healthColumn, "health")
    syncColumn(optionsPanel.powerColumn, "power")
end

function Vitals.refreshLocale()
    if optionsPanel then
    if optionsPanel.title then
        optionsPanel.title:SetText(L("VITALS_TITLE"))
    end
    if optionsPanel.subtitle then
        optionsPanel.subtitle:SetText(L("VITALS_SUBTITLE"))
    end
    if optionsPanel.unavailable then
        optionsPanel.unavailable:SetText(L("VITALS_UNAVAILABLE"))
        if available then
            optionsPanel.unavailable:Hide()
        else
            optionsPanel.unavailable:Show()
        end
    end
    local function relabel(column, titleKey)
        if not column then
            return
        end
        if column.title then
            column.title:SetText(L(titleKey))
        end
        if column.enable and column.enable.text then
            column.enable.text:SetText(L("VITALS_ENABLED"))
        end
        if column.lock and column.lock.text then
            column.lock.text:SetText(L("LOCK"))
        end
        if column.threshold and column.threshold.label then
            column.threshold.label:SetText(L("VITALS_THRESHOLD"))
        end
        if column.aboveLabel then
            column.aboveLabel:SetText(L("VITALS_COLOR_ABOVE"))
        end
        if column.belowLabel then
            column.belowLabel:SetText(L("VITALS_COLOR_BELOW"))
        end
        if column.size and column.size.label then
            column.size.label:SetText(L("SIZE"))
        end
        if column.x and column.x.label then
            column.x.label:SetText(L("X"))
        end
        if column.y and column.y.label then
            column.y.label:SetText(L("Y"))
        end
        if column.layerLabel then
            column.layerLabel:SetText(L("FRAME_LAYER"))
        end
        if column.level and column.level.label then
            column.level.label:SetText(L("FRAME_LEVEL"))
        end
    end
    relabel(optionsPanel.healthColumn, "VITALS_HEALTH")
    relabel(optionsPanel.powerColumn, "VITALS_POWER")
    Vitals.refreshOptionsValues()
    end
    -- Reset Defaults calls refreshOptionsLocale after bind, not applyAllLayout.
    -- Re-apply visibility so a just-disabled box does not stay painted.
    if initialized then
        refreshChannel("health")
        refreshChannel("power")
    end
end

function Vitals.createOptionsPanel(panel, panelDeps)
    if panelDeps then
        for key, value in pairs(panelDeps) do
            deps[key] = value
        end
    end
    optionsPanel = panel
    if not panel or not CreateFrame then
        return panel
    end

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText(L("VITALS_TITLE"))
    panel.title = title

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("VITALS_SUBTITLE"))
    panel.subtitle = subtitle

    local unavailable = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unavailable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
    unavailable:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    unavailable:SetJustifyH("LEFT")
    unavailable:SetText(L("VITALS_UNAVAILABLE"))
    panel.unavailable = unavailable
    if available then
        unavailable:Hide()
    end

    panel.healthColumn = createChannelColumn(panel, "health", "VITALS_HEALTH", 8)
    panel.powerColumn = createChannelColumn(panel, "power", "VITALS_POWER", 440)
    Vitals.refreshOptionsValues()
    return panel
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Vitals.init(newDeps)
    deps = type(newDeps) == "table" and newDeps or {}
    available = detectAvailable()
    if not CreateFrame then
        initialized = true
        available = false
        return
    end
    if not boxes.health then
        boxes.health = createBox("ShinkiliHealthBox")
        boxes.health.vitalsKind = "health"
        boxes.health:SetScript("OnDragStart", function(self)
            if getChannel("health").locked == false then
                self:StartMoving()
            end
        end)
        boxes.health:SetScript("OnDragStop", onDragStop)
    end
    if not boxes.power then
        boxes.power = createBox("ShinkiliPowerBox")
        boxes.power.vitalsKind = "power"
        boxes.power:SetScript("OnDragStart", function(self)
            if getChannel("power").locked == false then
                self:StartMoving()
            end
        end)
        boxes.power:SetScript("OnDragStop", onDragStop)
    end
    if not eventFrame then
        eventFrame = CreateFrame("Frame", "ShinkiliVitalsEvents")
        registerEvents(eventFrame)
    end
    initialized = true
    Vitals.applyLayout()
end

return Vitals
