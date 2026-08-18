-- Manual KeySim condition box: one toggle, one solid-color square.
-- Show/Hide only. Does not change recommendations.

ShinkiliFlag = ShinkiliFlag or {}
local Flag = ShinkiliFlag

local TOGGLE_BUTTON = "ShinkiliFlagToggleButton"
local PLACEHOLDER_RGBA = {0.25, 0.25, 0.25, 0.55}

local deps = {}
local initialized = false
local box
local eventFrame
local bindOwner
local toggleButton
local toastFrame
local toastText
local captureFrame
local optionsPanel
local controlId = 0
local bindingListen = false
local pendingBinding = false

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
    if type(settings.flag) ~= "table" then
        settings.flag = {}
    end
    return settings.flag
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
    return 0.55, 0.35, 0.85, 1
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

local function formatBindingKey(key)
    if not key or key == "" then
        return L("BLACKLIST_UNBOUND")
    end
    return key
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function applyBoxLayout()
    if not box then
        return
    end
    local channel = getChannel()
    local size = channel.size or 48
    box:SetSize(size, size)
    box:ClearAllPoints()
    box:SetPoint(
        channel.point or "CENTER",
        UIParent,
        channel.relativePoint or "CENTER",
        channel.x or 100,
        channel.y or -180
    )
    box:SetFrameStrata(channel.frameStrata or "FULLSCREEN_DIALOG")
    box:SetFrameLevel(channel.frameLevel or 180)
end

local function paintBox()
    if not box then
        return
    end
    local channel = getChannel()
    if channel.enabled == true then
        local r, g, b, a = paletteColor(channel.colorIndex or 7)
        box:SetBackdropColor(r, g, b, a or 1)
    else
        box:SetBackdropColor(
            PLACEHOLDER_RGBA[1],
            PLACEHOLDER_RGBA[2],
            PLACEHOLDER_RGBA[3],
            PLACEHOLDER_RGBA[4]
        )
    end
end

local function refreshBox()
    if not box then
        return
    end
    local channel = getChannel()
    local show = ShinkiliLogic.shouldShowFlagBox(
        channel.enabled == true,
        isOptionsOpen(),
        channel.locked ~= false
    )
    if show then
        paintBox()
        box:Show()
        box:EnableMouse(channel.locked == false)
    else
        box:Hide()
        box:EnableMouse(false)
    end
end

local function applyBinding()
    if not bindOwner then
        return
    end
    if inCombat() then
        pendingBinding = true
        return
    end
    pendingBinding = false
    if ClearOverrideBindings then
        ClearOverrideBindings(bindOwner)
    end
    local key = getChannel().toggleKey
    if key and key ~= "" and SetOverrideBindingClick then
        SetOverrideBindingClick(bindOwner, true, key, TOGGLE_BUTTON)
    end
end

local function showToast(enabled)
    if not toastFrame or not toastText then
        return
    end
    toastText:SetText(enabled and L("FLAG_TOAST_ON") or L("FLAG_TOAST_OFF"))
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

function Flag.refreshOptionsValues()
    if not optionsPanel then
        return
    end
    local channel = getChannel()
    if optionsPanel.enable then
        optionsPanel.enable:SetChecked(channel.enabled == true)
    end
    if optionsPanel.lock then
        optionsPanel.lock:SetChecked(channel.locked ~= false)
    end
    if optionsPanel.size and optionsPanel.size.input then
        optionsPanel.size.input:SetText(tostring(channel.size or 48))
    end
    if optionsPanel.x and optionsPanel.x.input then
        optionsPanel.x.input:SetText(tostring(channel.x or 100))
    end
    if optionsPanel.y and optionsPanel.y.input then
        optionsPanel.y.input:SetText(tostring(channel.y or -180))
    end
    if optionsPanel.level and optionsPanel.level.input then
        optionsPanel.level.input:SetText(tostring(channel.frameLevel or 180))
    end
    if optionsPanel.colorDropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(optionsPanel.colorDropdown, channel.colorIndex or 7)
        UIDropDownMenu_SetText(optionsPanel.colorDropdown, colorName(channel.colorIndex or 7))
    end
    if optionsPanel.strataDropdown and UIDropDownMenu_SetSelectedValue then
        local strata = channel.frameStrata or "FULLSCREEN_DIALOG"
        UIDropDownMenu_SetSelectedValue(optionsPanel.strataDropdown, strata)
        UIDropDownMenu_SetText(optionsPanel.strataDropdown, strata)
    end
    if optionsPanel.keyValue then
        if bindingListen then
            optionsPanel.keyValue:SetText(L("BLACKLIST_LISTENING"))
        else
            optionsPanel.keyValue:SetText(formatBindingKey(channel.toggleKey))
        end
    end
    if optionsPanel.bindButton then
        optionsPanel.bindButton:SetText(bindingListen and L("BLACKLIST_LISTENING") or L("BLACKLIST_BIND"))
    end
end

function Flag.setEnabled(enabled, showNotice)
    getChannel().enabled = enabled and true or false
    persist()
    refreshBox()
    Flag.refreshOptionsValues()
    if showNotice ~= false then
        showToast(getChannel().enabled == true)
    end
end

function Flag.toggle()
    Flag.setEnabled(getChannel().enabled ~= true, true)
end

function Flag.stopBindingListen()
    bindingListen = false
    if captureFrame then
        captureFrame:Hide()
        captureFrame:SetScript("OnKeyDown", nil)
        captureFrame:SetScript("OnMouseDown", nil)
        captureFrame:SetScript("OnMouseWheel", nil)
    end
    Flag.refreshOptionsValues()
end

local function buildModifierPrefix()
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    return prefix
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

local function saveToggleKey(bindingKey)
    getChannel().toggleKey = bindingKey
    Flag.stopBindingListen()
    applyBinding()
    persist()
    Flag.refreshOptionsValues()
end

local function startBindingListen()
    if not captureFrame then
        return
    end
    bindingListen = true
    captureFrame.text:SetText(L("FLAG_CAPTURING"))
    captureFrame:Show()
    captureFrame:EnableKeyboard(true)
    if captureFrame.SetPropagateKeyboardInput then
        captureFrame:SetPropagateKeyboardInput(false)
    end

    captureFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            Flag.stopBindingListen()
            return
        end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
            or key == "LALT" or key == "RALT" or key == "LMETA" or key == "RMETA" then
            return
        end
        saveToggleKey(buildModifierPrefix() .. key)
    end)

    captureFrame:SetScript("OnMouseDown", function(_, button)
        local mapped = mouseButtonToBinding(button)
        if not mapped then
            return
        end
        local mods = buildModifierPrefix()
        if mods == "" and (mapped == "BUTTON1" or mapped == "BUTTON2") then
            return
        end
        saveToggleKey(mods .. mapped)
    end)

    captureFrame:SetScript("OnMouseWheel", function(_, delta)
        local wheel = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        saveToggleKey(buildModifierPrefix() .. wheel)
    end)

    Flag.refreshOptionsValues()
end

local function onDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local channel = getChannel()
    channel.point = "CENTER"
    channel.relativePoint = "CENTER"
    channel.x = math.floor((x or 0) + 0.5)
    channel.y = math.floor((y or 0) + 0.5)
    applyBoxLayout()
    persist()
    Flag.refreshOptionsValues()
end

local function makeEdit(parent, labelText, width, onApply)
    controlId = controlId + 1
    local holder = CreateFrame("Frame", "ShinkiliFlagInput" .. controlId, parent)
    holder:SetSize(width, 44)
    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", 0, 0)
    holder.label:SetText(labelText)
    holder.input = CreateFrame("EditBox", "ShinkiliFlagEdit" .. controlId, holder, "InputBoxTemplate")
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
                refreshBox()
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
        applyBoxLayout()
    end
    if deps.initStrataDropdown then
        deps.initStrataDropdown(dropdown, getStrata, setStrata)
    end
end

function Flag.refresh()
    if not initialized then
        return
    end
    refreshBox()
end

function Flag.applyLayout()
    if not initialized then
        return
    end
    applyBoxLayout()
    applyBinding()
    refreshBox()
end

function Flag.refreshLocale()
    if not optionsPanel then
        return
    end
    if optionsPanel.title then
        optionsPanel.title:SetText(L("FLAG_TITLE"))
    end
    if optionsPanel.subtitle then
        optionsPanel.subtitle:SetText(L("FLAG_SUBTITLE"))
    end
    if optionsPanel.enable and optionsPanel.enable.text then
        optionsPanel.enable.text:SetText(L("FLAG_ENABLE"))
    end
    if optionsPanel.lock and optionsPanel.lock.text then
        optionsPanel.lock.text:SetText(L("LOCK"))
    end
    if optionsPanel.colorLabel then
        optionsPanel.colorLabel:SetText(L("FLAG_COLOR"))
    end
    if optionsPanel.size and optionsPanel.size.label then
        optionsPanel.size.label:SetText(L("SIZE"))
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
    if optionsPanel.keyLabel then
        optionsPanel.keyLabel:SetText(L("FLAG_TOGGLE_KEY"))
    end
    if optionsPanel.bindButton then
        optionsPanel.bindButton:SetText(L("BLACKLIST_BIND"))
    end
    if optionsPanel.clearButton then
        optionsPanel.clearButton:SetText(L("BLACKLIST_CLEAR_KEY"))
    end
    if optionsPanel.bindHint then
        optionsPanel.bindHint:SetText(L("FLAG_BIND_HINT"))
    end
    if optionsPanel.bindWarn then
        optionsPanel.bindWarn:SetText(L("FLAG_BIND_WARN"))
    end
    Flag.refreshOptionsValues()
    if initialized then
        refreshBox()
    end
end

function Flag.createOptionsPanel(panel, panelDeps)
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
    title:SetText(L("FLAG_TITLE"))
    panel.title = title

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L("FLAG_SUBTITLE"))
    panel.subtitle = subtitle

    local enable = CreateFrame("CheckButton", "ShinkiliFlagEnable", panel, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -10)
    if enable.text then
        enable.text:SetText(L("FLAG_ENABLE"))
    end
    enable:SetScript("OnClick", function(self)
        Flag.setEnabled(self:GetChecked() and true or false, false)
    end)
    panel.enable = enable

    local lockCheck = CreateFrame("CheckButton", "ShinkiliFlagLock", panel, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -2)
    if lockCheck.text then
        lockCheck.text:SetText(L("LOCK"))
    end
    lockCheck:SetScript("OnClick", function(self)
        getChannel().locked = self:GetChecked() and true or false
        persist()
        refreshBox()
    end)
    panel.lock = lockCheck

    local colorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, -8)
    colorLabel:SetText(L("FLAG_COLOR"))
    panel.colorLabel = colorLabel

    local colorDropdown = CreateFrame("Frame", "ShinkiliFlagColor", panel, "UIDropDownMenuTemplate")
    colorDropdown:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", -16, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(colorDropdown, 180)
    end
    initColorDropdown(colorDropdown)
    panel.colorDropdown = colorDropdown

    local sizeHolder = makeEdit(panel, L("SIZE"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.size.input:SetText(tostring(channel.size or 48))
            return
        end
        channel.size = clamp(value, 24, 300)
        applyBoxLayout()
        persist()
        refreshBox()
        panel.size.input:SetText(tostring(channel.size))
    end)
    sizeHolder:SetPoint("TOPLEFT", colorDropdown, "BOTTOMLEFT", 16, -8)
    panel.size = sizeHolder

    local xHolder = makeEdit(panel, L("X"), 72, function(text)
        local value = parseInteger(text)
        local channel = getChannel()
        if not value then
            panel.x.input:SetText(tostring(channel.x or 100))
            return
        end
        channel.x = clamp(value, -1000, 1000)
        channel.point = "CENTER"
        channel.relativePoint = "CENTER"
        applyBoxLayout()
        persist()
        panel.x.input:SetText(tostring(channel.x))
    end)
    xHolder:SetPoint("LEFT", sizeHolder, "RIGHT", 12, 0)
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
        applyBoxLayout()
        persist()
        panel.y.input:SetText(tostring(channel.y))
    end)
    yHolder:SetPoint("LEFT", xHolder, "RIGHT", 12, 0)
    panel.y = yHolder

    local layerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layerLabel:SetPoint("TOPLEFT", sizeHolder, "BOTTOMLEFT", 0, -10)
    layerLabel:SetText(L("FRAME_LAYER"))
    panel.layerLabel = layerLabel

    local strataDropdown = CreateFrame("Frame", "ShinkiliFlagStrata", panel, "UIDropDownMenuTemplate")
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
            panel.level.input:SetText(tostring(channel.frameLevel or 180))
            return
        end
        channel.frameLevel = ShinkiliLogic.sanitizeFrameLevel(value, 180)
        applyBoxLayout()
        persist()
        panel.level.input:SetText(tostring(channel.frameLevel))
    end)
    levelHolder:SetPoint("TOPLEFT", strataDropdown, "BOTTOMLEFT", 16, -4)
    panel.level = levelHolder

    local keyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keyLabel:SetPoint("TOPLEFT", levelHolder, "BOTTOMLEFT", 0, -10)
    keyLabel:SetText(L("FLAG_TOGGLE_KEY"))
    panel.keyLabel = keyLabel

    local keyValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keyValue:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    keyValue:SetWidth(220)
    keyValue:SetJustifyH("LEFT")
    panel.keyValue = keyValue

    local bindButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    bindButton:SetSize(100, 22)
    bindButton:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -4)
    bindButton:SetText(L("BLACKLIST_BIND"))
    bindButton:SetScript("OnClick", function()
        if bindingListen then
            Flag.stopBindingListen()
        else
            startBindingListen()
        end
    end)
    panel.bindButton = bindButton

    local clearButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    clearButton:SetSize(80, 22)
    clearButton:SetPoint("LEFT", bindButton, "RIGHT", 8, 0)
    clearButton:SetText(L("BLACKLIST_CLEAR_KEY"))
    clearButton:SetScript("OnClick", function()
        getChannel().toggleKey = nil
        Flag.stopBindingListen()
        applyBinding()
        persist()
        Flag.refreshOptionsValues()
    end)
    panel.clearButton = clearButton

    local bindHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindHint:SetPoint("TOPLEFT", bindButton, "BOTTOMLEFT", 0, -4)
    bindHint:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    bindHint:SetJustifyH("LEFT")
    bindHint:SetText(L("FLAG_BIND_HINT"))
    panel.bindHint = bindHint

    local bindWarn = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindWarn:SetPoint("TOPLEFT", bindHint, "BOTTOMLEFT", 0, -2)
    bindWarn:SetWidth((panel.GetWidth and panel:GetWidth() or 860) - 24)
    bindWarn:SetJustifyH("LEFT")
    bindWarn:SetText(L("FLAG_BIND_WARN"))
    panel.bindWarn = bindWarn

    Flag.refreshOptionsValues()
    return panel
end

function Flag.init(newDeps)
    deps = type(newDeps) == "table" and newDeps or {}
    if not CreateFrame then
        initialized = true
        return
    end
    if not box then
        box = CreateFrame("Frame", "ShinkiliFlagBox", UIParent, "BackdropTemplate")
        box:SetMovable(true)
        box:SetClampedToScreen(true)
        box:EnableMouse(false)
        box:RegisterForDrag("LeftButton")
        box:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        box:SetBackdropColor(PLACEHOLDER_RGBA[1], PLACEHOLDER_RGBA[2], PLACEHOLDER_RGBA[3], PLACEHOLDER_RGBA[4])
        box:SetBackdropBorderColor(0.05, 0.05, 0.05, 0.95)
        box:SetScript("OnDragStart", function(self)
            if getChannel().locked == false then
                self:StartMoving()
            end
        end)
        box:SetScript("OnDragStop", onDragStop)
        box:Hide()
    end
    if not bindOwner then
        bindOwner = CreateFrame("Frame", "ShinkiliFlagBindOwner")
    end
    if not toggleButton then
        toggleButton = CreateFrame("Button", TOGGLE_BUTTON, UIParent)
        toggleButton:SetSize(1, 1)
        toggleButton:Hide()
        toggleButton:SetScript("OnClick", function()
            Flag.toggle()
        end)
    end
    if not toastFrame then
        toastFrame = CreateFrame("Frame", "ShinkiliFlagToast", UIParent)
        toastFrame:SetSize(420, 56)
        toastFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        toastFrame:SetFrameStrata("TOOLTIP")
        toastFrame:SetFrameLevel(500)
        toastFrame:Hide()
        toastText = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        toastText:SetPoint("CENTER")
        toastText:SetTextColor(0.20, 1.00, 0.60, 1)
        toastText:SetShadowOffset(1, -1)
        toastText:SetShadowColor(0, 0, 0, 0.95)
    end
    if not captureFrame then
        captureFrame = CreateFrame("Frame", "ShinkiliFlagBindingCapture", UIParent, "BackdropTemplate")
        captureFrame:SetAllPoints(UIParent)
        captureFrame:EnableMouse(true)
        captureFrame:EnableKeyboard(true)
        captureFrame:EnableMouseWheel(true)
        captureFrame:SetFrameStrata("TOOLTIP")
        captureFrame:SetFrameLevel(1000)
        captureFrame:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        captureFrame:SetBackdropColor(0, 0, 0, 0.55)
        captureFrame:SetBackdropBorderColor(0, 0, 0, 0)
        captureFrame:Hide()
        captureFrame.text = captureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        captureFrame.text:SetPoint("CENTER", 0, 40)
        captureFrame.text:SetTextColor(0.20, 1.00, 0.60, 1)
        captureFrame.text:SetShadowOffset(1, -1)
        captureFrame.text:SetShadowColor(0, 0, 0, 0.95)
    end
    if not eventFrame then
        eventFrame = CreateFrame("Frame", "ShinkiliFlagEvents")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" and pendingBinding then
                applyBinding()
            end
        end)
    end
    initialized = true
    Flag.applyLayout()
end

return Flag
