-- Hostile nameplate count bar: five equal cells filled left to right.
-- One fill color. Visibility is combat-only or always, from options.

ShinkiliEnemies = ShinkiliEnemies or {}
local Enemies = ShinkiliEnemies

local CELL_COUNT = ShinkiliLogic.ENEMY_CELL_COUNT or 5
local EMPTY_RGBA = {0.16, 0.16, 0.16, 0.9}

local deps = {}
local initialized = false
local bar
local cells = {}
local eventFrame
local optionsPanel
local controlId = 0

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

local function getChannel()
    local settings = getSettings()
    if type(settings.enemies) ~= "table" then
        settings.enemies = {}
    end
    return settings.enemies
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
        return deps.getPaletteColor(index)
    end
    return 0.85, 0.55, 0.15, 1
end

local function colorName(index)
    if deps.getColorName then
        return deps.getColorName(index)
    end
    return tostring(index)
end

local function clamp(value, minimum, maximum)
    return ShinkiliLogic.clamp(value, minimum, maximum)
end

local function parseInteger(text)
    return ShinkiliLogic.parseInteger(text)
end

local function playerInCombat()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if not UnitAffectingCombat then
        return false
    end
    local ok, value = pcall(UnitAffectingCombat, "player")
    if not ok then
        return false
    end
    if ShinkiliSecret and ShinkiliSecret.plainBool then
        return ShinkiliSecret.plainBool(value) == true
    end
    return value == true
end

local function hostileCount()
    if ShinkiliEval and ShinkiliEval.countHostileNameplates then
        return ShinkiliEval.countHostileNameplates() or 0
    end
    return 0
end

local function makeEdit(parent, labelText, width, onApply)
    controlId = controlId + 1
    local holder = CreateFrame("Frame", "ShinkiliEnemiesInput" .. controlId, parent)
    holder:SetSize(width, 44)
    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText(labelText)
    holder.input = CreateFrame("EditBox", "ShinkiliEnemiesEdit" .. controlId, holder, "InputBoxTemplate")
    holder.input:SetSize(width, 28)
    holder.input:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -4)
    holder.input:SetAutoFocus(false)
    holder.input:SetMaxLetters(8)
    local function applyValue()
        onApply(holder.input:GetText())
    end
    holder.input:SetScript("OnEnterPressed", function(self)
        applyValue()
        self:ClearFocus()
    end)
    holder.input:SetScript("OnEditFocusLost", applyValue)
    return holder
end

local function applyBarLayout()
    if not bar then
        return
    end
    local channel = getChannel()
    local width = channel.width or 160
    local height = channel.height or 28
    bar:SetSize(width, height)
    bar:ClearAllPoints()
    bar:SetPoint(
        channel.point or "CENTER",
        UIParent,
        channel.relativePoint or "CENTER",
        channel.x or 0,
        channel.y or -180
    )
    bar:SetFrameStrata(channel.frameStrata or "FULLSCREEN_DIALOG")
    bar:SetFrameLevel(channel.frameLevel or 185)

    local gap = 2
    local innerWidth = width - 4
    local innerHeight = height - 4
    local cellWidth = (innerWidth - gap * (CELL_COUNT - 1)) / CELL_COUNT
    for index = 1, CELL_COUNT do
        local cell = cells[index]
        if cell then
            cell:ClearAllPoints()
            cell:SetSize(cellWidth, innerHeight)
            cell:SetPoint("LEFT", bar, "LEFT", 2 + (index - 1) * (cellWidth + gap), 0)
        end
    end
end

local function paintCells(filled)
    local channel = getChannel()
    local r, g, b, a = paletteColor(channel.colorIndex or 3)
    filled = ShinkiliLogic.filledEnemyCells(filled, CELL_COUNT)
    for index = 1, CELL_COUNT do
        local cell = cells[index]
        if cell then
            if index <= filled then
                cell:SetVertexColor(r, g, b, a or 1)
            else
                cell:SetVertexColor(EMPTY_RGBA[1], EMPTY_RGBA[2], EMPTY_RGBA[3], EMPTY_RGBA[4])
            end
        end
    end
end

local function refreshBar()
    if not bar then
        return
    end
    local channel = getChannel()
    local show = ShinkiliLogic.shouldShowEnemyBox(
        channel.enabled ~= false,
        playerInCombat(),
        isOptionsOpen(),
        channel.locked ~= false,
        channel.combatOnly ~= false
    )
    if show then
        paintCells(hostileCount())
        bar:Show()
        bar:EnableMouse(channel.locked == false)
    else
        bar:Hide()
        bar:EnableMouse(false)
    end
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local channel = getChannel()
    channel.point = "CENTER"
    channel.relativePoint = "CENTER"
    channel.x = math.floor((x or 0) + 0.5)
    channel.y = math.floor((y or 0) + 0.5)
    applyBarLayout()
    persist()
    if Enemies.refreshOptionsValues then
        Enemies.refreshOptionsValues()
    end
end

local function initColorDropdown(dropdown)
    if not UIDropDownMenu_Initialize then
        return
    end
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then
            return
        end
        local paletteSize = deps.paletteSize or 27
        local info = UIDropDownMenu_CreateInfo()
        for index = 2, paletteSize do
            info.text = colorName(index)
            info.value = index
            info.func = function()
                getChannel().colorIndex = index
                if UIDropDownMenu_SetSelectedValue then
                    UIDropDownMenu_SetSelectedValue(dropdown, index)
                end
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(dropdown, colorName(index))
                end
                persist()
                refreshBar()
            end
            info.checked = getChannel().colorIndex == index
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function initStrataDropdown(dropdown)
    local function getStrata()
        return getChannel().frameStrata or "FULLSCREEN_DIALOG"
    end
    local function setStrata(strata)
        getChannel().frameStrata = strata
        applyBarLayout()
    end
    if deps.initStrataDropdown then
        deps.initStrataDropdown(dropdown, getStrata, setStrata)
    end
end

function Enemies.refresh()
    if not initialized then
        return
    end
    refreshBar()
end

function Enemies.applyLayout()
    if not initialized then
        return
    end
    applyBarLayout()
    refreshBar()
end

function Enemies.refreshOptionsValues()
    if not optionsPanel then
        return
    end
    local channel = getChannel()
    if optionsPanel.enable then
        optionsPanel.enable:SetChecked(channel.enabled ~= false)
    end
    if optionsPanel.combatOnly then
        optionsPanel.combatOnly:SetChecked(channel.combatOnly ~= false)
    end
    if optionsPanel.lock then
        optionsPanel.lock:SetChecked(channel.locked ~= false)
    end
    if optionsPanel.width and optionsPanel.width.input then
        optionsPanel.width.input:SetText(tostring(channel.width or 160))
    end
    if optionsPanel.height and optionsPanel.height.input then
        optionsPanel.height.input:SetText(tostring(channel.height or 28))
    end
    if optionsPanel.x and optionsPanel.x.input then
        optionsPanel.x.input:SetText(tostring(channel.x or 0))
    end
    if optionsPanel.y and optionsPanel.y.input then
        optionsPanel.y.input:SetText(tostring(channel.y or -180))
    end
    if optionsPanel.level and optionsPanel.level.input then
        optionsPanel.level.input:SetText(tostring(channel.frameLevel or 185))
    end
    if optionsPanel.colorDropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(optionsPanel.colorDropdown, channel.colorIndex or 3)
        UIDropDownMenu_SetText(optionsPanel.colorDropdown, colorName(channel.colorIndex or 3))
    end
    if optionsPanel.strataDropdown and UIDropDownMenu_SetSelectedValue then
        local strata = channel.frameStrata or "FULLSCREEN_DIALOG"
        UIDropDownMenu_SetSelectedValue(optionsPanel.strataDropdown, strata)
        UIDropDownMenu_SetText(optionsPanel.strataDropdown, strata)
    end
end

function Enemies.refreshLocale()
    if not optionsPanel then
        return
    end
    if optionsPanel.title then
        optionsPanel.title:SetText(L("ENEMIES_TITLE"))
    end
    if optionsPanel.subtitle then
        optionsPanel.subtitle:SetText(L("ENEMIES_SUBTITLE"))
    end
    if optionsPanel.enable and optionsPanel.enable.text then
        optionsPanel.enable.text:SetText(L("ENEMIES_ENABLE"))
    end
    if optionsPanel.combatOnly and optionsPanel.combatOnly.text then
        optionsPanel.combatOnly.text:SetText(L("ENEMIES_COMBAT_ONLY"))
    end
    if optionsPanel.lock and optionsPanel.lock.text then
        optionsPanel.lock.text:SetText(L("LOCK"))
    end
    if optionsPanel.colorLabel then
        optionsPanel.colorLabel:SetText(L("ENEMIES_FILL_COLOR"))
    end
    if optionsPanel.width and optionsPanel.width.label then
        optionsPanel.width.label:SetText(L("ENEMIES_WIDTH"))
    end
    if optionsPanel.height and optionsPanel.height.label then
        optionsPanel.height.label:SetText(L("ENEMIES_HEIGHT"))
    end
    if optionsPanel.x and optionsPanel.x.label then
        optionsPanel.x.label:SetText(L("X"))
    end
    if optionsPanel.y and optionsPanel.y.label then
        optionsPanel.y.label:SetText(L("Y"))
    end
    if optionsPanel.layerLabel then
        optionsPanel.layerLabel:SetText(L("FRAME_LAYER"))
    end
    if optionsPanel.level and optionsPanel.level.label then
        optionsPanel.level.label:SetText(L("FRAME_LEVEL"))
    end
    Enemies.refreshOptionsValues()
    if initialized then
        refreshBar()
    end
end

function Enemies.createOptionsPanel(panel, panelDeps)
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
    title:SetText(L("ENEMIES_TITLE"))
    panel.title = title

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("ENEMIES_SUBTITLE"))
    panel.subtitle = subtitle

    local enable = CreateFrame("CheckButton", "ShinkiliEnemiesEnable", panel, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -10)
    if enable.text then
        enable.text:SetText(L("ENEMIES_ENABLE"))
    end
    enable:SetScript("OnClick", function(self)
        getChannel().enabled = self:GetChecked() and true or false
        persist()
        refreshBar()
    end)
    panel.enable = enable

    local combatOnly = CreateFrame("CheckButton", "ShinkiliEnemiesCombatOnly", panel, "UICheckButtonTemplate")
    combatOnly:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -2)
    if combatOnly.text then
        combatOnly.text:SetText(L("ENEMIES_COMBAT_ONLY"))
    end
    combatOnly:SetScript("OnClick", function(self)
        getChannel().combatOnly = self:GetChecked() and true or false
        persist()
        refreshBar()
    end)
    panel.combatOnly = combatOnly

    local lockCheck = CreateFrame("CheckButton", "ShinkiliEnemiesLock", panel, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", combatOnly, "BOTTOMLEFT", 0, -2)
    if lockCheck.text then
        lockCheck.text:SetText(L("LOCK"))
    end
    lockCheck:SetScript("OnClick", function(self)
        getChannel().locked = self:GetChecked() and true or false
        persist()
        refreshBar()
    end)
    panel.lock = lockCheck

    local colorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, -8)
    colorLabel:SetText(L("ENEMIES_FILL_COLOR"))
    panel.colorLabel = colorLabel

    local colorDropdown = CreateFrame("Frame", "ShinkiliEnemiesColor", panel, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", -16, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(colorDropdown, 180)
    end
    initColorDropdown(colorDropdown)
    panel.colorDropdown = colorDropdown

    local widthHolder = makeEdit(panel, L("ENEMIES_WIDTH"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.width.input:SetText(tostring(channel.width or 160))
            return
        end
        channel.width = clamp(value, 80, 400)
        applyBarLayout()
        persist()
        refreshBar()
        panel.width.input:SetText(tostring(channel.width))
    end)
    widthHolder:SetPoint("TOPLEFT", colorDropdown, "BOTTOMLEFT", 16, -8)
    panel.width = widthHolder

    local heightHolder = makeEdit(panel, L("ENEMIES_HEIGHT"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.height.input:SetText(tostring(channel.height or 28))
            return
        end
        channel.height = clamp(value, 16, 80)
        applyBarLayout()
        persist()
        refreshBar()
        panel.height.input:SetText(tostring(channel.height))
    end)
    heightHolder:SetPoint("LEFT", widthHolder, "RIGHT", 12, 0)
    panel.height = heightHolder

    local xHolder = makeEdit(panel, L("X"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.x.input:SetText(tostring(channel.x or 0))
            return
        end
        channel.x = clamp(value, -1000, 1000)
        channel.point = "CENTER"
        channel.relativePoint = "CENTER"
        applyBarLayout()
        persist()
        panel.x.input:SetText(tostring(channel.x))
    end)
    xHolder:SetPoint("LEFT", heightHolder, "RIGHT", 12, 0)
    panel.x = xHolder

    local yHolder = makeEdit(panel, L("Y"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.y.input:SetText(tostring(channel.y or -180))
            return
        end
        channel.y = clamp(value, -1000, 1000)
        channel.point = "CENTER"
        channel.relativePoint = "CENTER"
        applyBarLayout()
        persist()
        panel.y.input:SetText(tostring(channel.y))
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 12, 0)
    panel.y = yHolder

    local layerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layerLabel:SetPoint("TOPLEFT", widthHolder, "BOTTOMLEFT", 0, -10)
    layerLabel:SetText(L("FRAME_LAYER"))
    panel.layerLabel = layerLabel

    local strataDropdown = CreateFrame("Frame", "ShinkiliEnemiesStrata", panel, "UIDropDownMenuTemplate")
    strataDropdown:SetPoint("TOPLEFT", layerLabel, "BOTTOMLEFT", -16, -4)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(strataDropdown, 180)
    end
    initStrataDropdown(strataDropdown)
    panel.strataDropdown = strataDropdown

    local levelHolder = makeEdit(panel, L("FRAME_LEVEL"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.level.input:SetText(tostring(channel.frameLevel or 185))
            return
        end
        channel.frameLevel = ShinkiliLogic.sanitizeFrameLevel(value, 185)
        applyBarLayout()
        persist()
        panel.level.input:SetText(tostring(channel.frameLevel))
    end)
    levelHolder:SetPoint("TOPLEFT", strataDropdown, "BOTTOMLEFT", 16, -4)
    panel.level = levelHolder

    Enemies.refreshOptionsValues()
    return panel
end

function Enemies.init(newDeps)
    deps = type(newDeps) == "table" and newDeps or {}
    if not CreateFrame then
        initialized = true
        return
    end
    if not bar then
        bar = CreateFrame("Frame", "ShinkiliEnemyBox", UIParent, "BackdropTemplate")
        bar:SetMovable(true)
        bar:SetClampedToScreen(true)
        bar:EnableMouse(false)
        bar:RegisterForDrag("LeftButton")
        bar:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        bar:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
        bar:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
        bar:SetScript("OnDragStart", function(self)
            if getChannel().locked == false then
                self:StartMoving()
            end
        end)
        bar:SetScript("OnDragStop", onDragStop)
        for index = 1, CELL_COUNT do
            local cell = bar:CreateTexture(nil, "ARTWORK")
            cell:SetTexture("Interface/Buttons/WHITE8X8")
            cells[index] = cell
        end
        bar:Hide()
    end
    if not eventFrame then
        eventFrame = CreateFrame("Frame", "ShinkiliEnemiesEvents")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:SetScript("OnEvent", function()
            refreshBar()
        end)
    end
    initialized = true
    Enemies.applyLayout()
end

return Enemies
