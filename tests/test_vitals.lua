#!/usr/bin/env lua
-- Stubs drive the shipped ShinkiliVitals module and Logic.sanitizeSettings.

local root = arg[0]:match("(.*/)")
package.path = root .. "../Shinkili/?.lua;" .. package.path

local failures = 0

local function check(name, condition, detail)
    if condition then
        print("  OK  " .. name)
    else
        failures = failures + 1
        print("  FAIL  " .. name .. (detail and (" — " .. detail) or ""))
    end
end

local addPointCount = 0
local lastVertex = {}
local named = {}
local eventHandler

local function makeTexture()
    local tex = {}
    function tex:SetTexture() end
    function tex:SetPoint() end
    function tex:SetVertexColor(r, g, b, a)
        lastVertex[self] = {r, g, b, a}
        self.lastVertex = lastVertex[self]
    end
    return tex
end

local function makeFontString()
    local fs = {text = ""}
    function fs:SetPoint() end
    function fs:SetText(text) self.text = text end
    function fs:SetWidth() end
    function fs:SetJustifyH() end
    function fs:Hide() self.shown = false end
    function fs:Show() self.shown = true end
    function fs:GetText() return self.text end
    return fs
end

local function makeFrame(name)
    local frame = {
        shown = false,
        mouse = false,
        scripts = {},
        point = {"CENTER", nil, "CENTER", 0, 0},
        fill = nil,
    }
    function frame:SetMovable() end
    function frame:SetClampedToScreen() end
    function frame:EnableMouse(on) self.mouse = on and true or false end
    function frame:RegisterForDrag() end
    function frame:SetBackdrop() end
    function frame:SetBackdropBorderColor() end
    function frame:SetBackdropColor() end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:IsShown() return self.shown == true end
    function frame:SetSize(w, h) self.w, self.h = w, h end
    function frame:GetWidth() return self.w or 410 end
    function frame:ClearAllPoints() end
    function frame:SetPoint(p, rel, rp, x, y)
        self.point = {p, rel, rp, x, y}
    end
    function frame:GetPoint()
        return self.point[1], self.point[2], self.point[3], self.point[4], self.point[5]
    end
    function frame:SetFrameStrata(s) self.strata = s end
    function frame:SetFrameLevel(n) self.level = n end
    function frame:CreateTexture()
        self.fill = makeTexture()
        return self.fill
    end
    function frame:CreateFontString()
        return makeFontString()
    end
    function frame:SetScript(hook, fn)
        self.scripts[hook] = fn
        if hook == "OnEvent" then
            eventHandler = fn
        end
    end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:IsMoving() return self.moving == true end
    function frame:RegisterEvent() return true end
    function frame:RegisterUnitEvent() return true end
    function frame:GetChecked() return self.checked == true end
    function frame:SetChecked(v) self.checked = v and true or false end
    function frame:SetAutoFocus() end
    function frame:SetMaxLetters() end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text or "" end
    function frame:ClearFocus() end
    if name then
        named[name] = frame
        _G[name] = frame
    end
    return frame
end

CreateFrame = function(_, name)
    return makeFrame(name)
end
UIParent = makeFrame("UIParent")

local function makeCurve()
    local points = {}
    return {
        points = points,
        SetType = function() end,
        ClearPoints = function()
            for i = #points, 1, -1 do
                points[i] = nil
            end
        end,
        AddPoint = function(_, x, color)
            addPointCount = addPointCount + 1
            points[#points + 1] = {x = x, color = color}
        end,
    }
end

C_CurveUtil = {
    CreateColorCurve = function()
        return makeCurve()
    end,
}
Enum = {LuaCurveType = {Step = "STEP", Linear = "LINEAR"}}
CreateColor = function(r, g, b, a)
    return {
        r = r, g = g, b = b, a = a,
        GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
        GetRGB = function(self) return self.r, self.g, self.b end,
    }
end

local healthReturn
local powerReturn
UnitHealthPercent = function(_, _, _)
    return healthReturn or CreateColor(0, 1, 0, 1)
end
UnitPowerPercent = function(_, _, _, _)
    return powerReturn or CreateColor(0, 0.45, 1, 1)
end
UnitPowerType = function()
    return 1
end

issecretvalue = function()
    return false
end

dofile(root .. "../Shinkili/ShinkiliLogic.lua")
dofile(root .. "../Shinkili/ShinkiliVitals.lua")

local Logic = ShinkiliLogic
local Vitals = ShinkiliVitals

local persistCount = 0
local optionsOpen = false
local settings = {
    vitals = {
        health = {
            enabled = false, threshold = 35,
            aboveColorIndex = 2, belowColorIndex = 5,
            locked = true, size = 48,
            point = "CENTER", relativePoint = "CENTER", x = -100, y = -120,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 190,
        },
        power = {
            enabled = false, threshold = 40,
            aboveColorIndex = 6, belowColorIndex = 4,
            locked = true, size = 48,
            point = "CENTER", relativePoint = "CENTER", x = -100, y = -60,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 190,
        },
    },
}

local palette = {
    [2] = {0.00, 1.00, 0.00, 1.00},
    [4] = {1.00, 0.50, 0.00, 1.00},
    [5] = {1.00, 0.00, 0.00, 1.00},
    [6] = {0.00, 0.45, 1.00, 1.00},
}

print("ShinkiliVitals")

Vitals.init({
    getSettings = function() return settings end,
    getPaletteColor = function(index)
        local rgba = palette[index] or {0.2, 0.2, 0.2, 1}
        return rgba[1], rgba[2], rgba[3], rgba[4]
    end,
    persist = function() persistCount = persistCount + 1 end,
    isOptionsOpen = function() return optionsOpen end,
    L = function(key) return key end,
    paletteSize = 27,
})

local healthBox = _G.ShinkiliHealthBox
local powerBox = _G.ShinkiliPowerBox

check("default health box exists", healthBox ~= nil)
check("default power box exists", powerBox ~= nil)
check("default health disabled stays hidden", healthBox:IsShown() == false)
check("default power disabled stays hidden", powerBox:IsShown() == false)
check("defaults enabled false",
    settings.vitals.health.enabled == false and settings.vitals.power.enabled == false)

local afterInitPoints = addPointCount
settings.vitals.health.enabled = true
Vitals.applyLayout()
if eventHandler then
    eventHandler(nil, "UNIT_HEALTH", "player")
    eventHandler(nil, "UNIT_HEALTH", "player")
    eventHandler(nil, "UNIT_HEALTH", "player")
    eventHandler(nil, "UNIT_POWER_FREQUENT", "player")
end
check("health events do not rebuild the curve", addPointCount == afterInitPoints + 4,
    "points=" .. tostring(addPointCount) .. " afterInit=" .. tostring(afterInitPoints))
check("enabled health box is shown after paint", healthBox:IsShown() == true)
check("enabled health fill reached SetVertexColor", healthBox.fill and healthBox.fill.lastVertex ~= nil)
check("power events do not paint a disabled box", powerBox:IsShown() == false)

settings.vitals.health.threshold = 20
Vitals.applyLayout()
check("settings change rebuilds the health curve", addPointCount > afterInitPoints + 4)

local compared = false
local arith = false
local secretColor = {
    GetRGBA = function() return 1, 0, 0, 1 end,
    GetRGB = function() return 1, 0, 0 end,
}
local secretMeta = {
    __lt = function() compared = true; error("compared", 0) end,
    __le = function() compared = true; error("compared", 0) end,
    __eq = function() compared = true; return false end,
    __add = function() arith = true; error("arith", 0) end,
    __sub = function() arith = true; error("arith", 0) end,
    __mul = function() arith = true; error("arith", 0) end,
    __div = function() arith = true; error("arith", 0) end,
}
setmetatable(secretColor, secretMeta)
issecretvalue = function(value)
    return value == secretColor
end
healthReturn = secretColor
healthBox.fill.lastVertex = nil
local okPaint = pcall(function()
    if eventHandler then
        eventHandler(nil, "UNIT_HEALTH", "player")
    end
end)
check("secret color paint does not throw", okPaint == true)
check("secret color still reaches SetVertexColor",
    healthBox.fill.lastVertex ~= nil
        and healthBox.fill.lastVertex[1] == 1
        and healthBox.fill.lastVertex[2] == 0)
check("secret color is not compared or arithmeticed", compared == false and arith == false)
issecretvalue = function() return false end
healthReturn = nil

local savedCurve = C_CurveUtil
C_CurveUtil = nil
local okMissing = pcall(function()
    Vitals.applyLayout()
end)
check("missing C_CurveUtil does not throw", okMissing == true)
check("missing C_CurveUtil hides health", healthBox:IsShown() == false)
check("missing C_CurveUtil hides power", powerBox:IsShown() == false)
C_CurveUtil = savedCurve
settings.vitals.health.enabled = true
Vitals.applyLayout()
check("health shown before locale refresh", healthBox:IsShown() == true)
settings.vitals.health.enabled = false
Vitals.refreshLocale()
check("refreshLocale hides a just-disabled box", healthBox:IsShown() == false)
Vitals.applyLayout()

print("ShinkiliVitals sanitize")

local function sanitizeWith(channel)
    local db = {
        size = 64, x = 0, y = -120, point = "CENTER", relativePoint = "CENTER",
        mappings = {},
        overrides = {},
        defense = {entries = {}},
        procs = {entries = {}},
        blacklist = {entries = {}, cooldowns = {}},
        vitals = {health = channel, power = {}},
    }
    Logic.sanitizeSettings(db, {
        sizeDefault = 64, xDefault = 0, yDefault = -120,
        pointDefault = "CENTER", relativePointDefault = "CENTER",
        legacyMappingSlots = 0,
        colorPaletteSize = 27,
        markerPaletteSize = 8,
        reservedOverrideSize = 6,
        defaultOverrides = {
            casting = {enabled = true, colorIndex = 1},
            channeling = {enabled = true, colorIndex = 2},
            empower = {enabled = true, colorIndex = 3},
        },
        vitalsDefaults = {
            health = {
                enabled = false, threshold = 35,
                aboveColorIndex = 2, belowColorIndex = 5,
                locked = true, size = 48, point = "CENTER", relativePoint = "CENTER",
                x = -100, y = -120, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 190,
            },
            power = {
                enabled = false, threshold = 40,
                aboveColorIndex = 6, belowColorIndex = 4,
                locked = true, size = 48, point = "CENTER", relativePoint = "CENTER",
                x = -100, y = -60, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 190,
            },
        },
    })
    return db.vitals.health
end

check("threshold 0 clamps to 1", sanitizeWith({threshold = 0}).threshold == 1)
check("threshold 100 clamps to 99", sanitizeWith({threshold = 100}).threshold == 99)
check("threshold abc uses default", sanitizeWith({threshold = "abc"}).threshold == 35)
check("threshold nil uses default", sanitizeWith({}).threshold == 35)
check("color index 1 falls back", sanitizeWith({aboveColorIndex = 1}).aboveColorIndex == 2)
check("color index 0 falls back", sanitizeWith({belowColorIndex = 0}).belowColorIndex == 5)
check("color index past palette falls back", sanitizeWith({aboveColorIndex = 99}).aboveColorIndex == 2)
check("enabled stays false by default", sanitizeWith({}).enabled == false)

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
