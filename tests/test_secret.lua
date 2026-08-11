#!/usr/bin/env lua
-- Unit tests for ShinkiliSecret against a stubbed WoW API.
--
-- The point of this file is the tri-state contract: every accessor must answer
-- true / false / nil, and must never let a secret value reach a branch.

local root = arg[0]:match("(.*/)")

local failures = 0

local function check(name, condition, detail)
    if condition then
        print("  OK  " .. name)
    else
        failures = failures + 1
        print("  FAIL  " .. name .. (detail and (" — " .. detail) or ""))
    end
end

--------------------------------------------------------------------------------
-- Stub environment
--------------------------------------------------------------------------------

local secretRegistry = setmetatable({}, {__mode = "k"})
local function makeSecret(tag)
    local box = {tag = tag}
    secretRegistry[box] = true
    return box
end

issecretvalue = function(value)
    return secretRegistry[value] == true
end

-- Scratch Cooldown widget the DurationObject probe drives.
local probe = {shown = false, fed = nil, available = true}
local fakeCooldown = {
    SetCooldownFromDurationObject = function(_, durationObject)
        probe.fed = durationObject
        probe.shown = (durationObject ~= nil) and durationObject.running == true
    end,
    IsShown = function()
        return probe.shown
    end,
    SetCooldown = function()
        probe.shown = false
    end,
}

CreateFrame = function(kind)
    if kind == "Frame" then
        return {Hide = function() end}
    end
    if not probe.available then
        return {Hide = function() end} -- no SetCooldownFromDurationObject
    end
    return fakeCooldown
end
UIParent = {}

C_Secrets = {
    aurasSecret = false,
    cooldownsSecret = false,
    powerSecrecy = {},
    ShouldAurasBeSecret = function()
        return C_Secrets.aurasSecret
    end,
    ShouldCooldownsBeSecret = function()
        return C_Secrets.cooldownsSecret
    end,
    GetPowerTypeSecrecy = function(powerType)
        local level = C_Secrets.powerSecrecy[powerType]
        return level == nil and 0 or level
    end,
}

local cooldownDurations = {}
local cooldownStructs = {}
local charges = {}
local powerValues = {}
local playerAuras = {}
local rangeVerdicts = {}
local targetHealth = nil

C_Spell = {
    GetSpellCooldownDuration = function(spellId)
        return cooldownDurations[spellId]
    end,
    GetSpellCooldown = function(spellId)
        return cooldownStructs[spellId]
    end,
    GetSpellCharges = function(spellId)
        return charges[spellId]
    end,
    IsSpellInRange = function(spellId)
        return rangeVerdicts[spellId]
    end,
}

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellId)
        return playerAuras[spellId]
    end,
    GetAuraDuration = function(_, instanceId)
        return cooldownDurations["aura" .. tostring(instanceId)]
    end,
    IsAuraFilteredOutByInstanceID = function(_, instanceId)
        return instanceId ~= 1
    end,
}

UnitPower = function(_, powerType, fractional)
    local entry = powerValues[powerType]
    if not entry then
        return nil
    end
    return fractional and entry.rawFractional or entry.current
end
UnitPowerMax = function(_, powerType)
    -- Real API: without the unmodified flag this is already display-scaled.
    local entry = powerValues[powerType]
    return entry and entry.max or 0
end
local displayMod = {}
UnitPowerDisplayMod = function(powerType)
    return displayMod[powerType]
end

local targetExists = true
UnitExists = function()
    return targetExists
end
UnitHealth = function()
    return targetHealth
end
UnitHealthMax = function()
    return 100
end
InCombatLockdown = function()
    return false
end

dofile(root .. "../Shinkili/ShinkiliSecret.lua")
local Secret = ShinkiliSecret

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local secretBox = makeSecret("bool")

check("isSecret detects registered secret", Secret.isSecret(secretBox) == true)
check("isSecret false for plain value", Secret.isSecret(true) == false)
check("plainBool passes real true", Secret.plainBool(true) == true)
check("plainBool passes real false", Secret.plainBool(false) == false)
check("plainBool nil stays nil", Secret.plainBool(nil) == nil)
-- The crux: a secret must become nil, never a branchable boolean.
check("plainBool secret becomes nil", Secret.plainBool(secretBox) == nil)
check("plainBool legacy 1 becomes true", Secret.plainBool(1) == true)
check("plainNumber secret becomes nil", Secret.plainNumber(makeSecret("n")) == nil)
check("plainNumber passes number", Secret.plainNumber(7) == 7)
check("plainNumber rejects string", Secret.plainNumber("7") == nil)

--------------------------------------------------------------------------------
-- Secrecy gates
--------------------------------------------------------------------------------

C_Secrets.aurasSecret = true
check("areAurasSecret reads C_Secrets", Secret.areAurasSecret() == true)
C_Secrets.aurasSecret = false
check("areAurasSecret clears", Secret.areAurasSecret() == false)
C_Secrets.cooldownsSecret = true
check("areCooldownsSecret reads C_Secrets", Secret.areCooldownsSecret() == true)
C_Secrets.cooldownsSecret = false

--------------------------------------------------------------------------------
-- DurationObject probe + cooldown ladder
--------------------------------------------------------------------------------

check("probe available with widget", Secret.isProbeAvailable() == true)

cooldownDurations[100] = {running = true}
check("probe reports running cooldown", Secret.isSpellOnRealCooldown(100) == true)

cooldownDurations[101] = {running = false}
check("probe reports ready cooldown", Secret.isSpellOnRealCooldown(101) == false)

-- No duration object at all: engine says nothing is running.
check("probe nil duration means ready", Secret.isSpellOnRealCooldown(102) == false)

-- Ladder step 2: probe blind (duration API absent) -> NeverSecret booleans.
local savedDurationApi = C_Spell.GetSpellCooldownDuration
C_Spell.GetSpellCooldownDuration = nil

-- isActive is asked first: nothing running means no real cooldown, whatever
-- isOnGCD claims.
cooldownStructs[199] = {isOnGCD = false, isActive = false}
check("isActive false wins over isOnGCD false", Secret.isSpellOnRealCooldown(199) == false)

cooldownStructs[200] = {isOnGCD = true, isActive = true}
check("isOnGCD true with no tracker is unknown", Secret.isSpellOnRealCooldown(200) == nil)

cooldownStructs[201] = {isOnGCD = false, isActive = true}
check("isOnGCD false means on cooldown", Secret.isSpellOnRealCooldown(201) == true)

cooldownStructs[202] = {isActive = true}
check("isActive fills ambiguous isOnGCD", Secret.isSpellOnRealCooldown(202) == true)

cooldownStructs[203] = {isActive = false}
check("isActive false means ready", Secret.isSpellOnRealCooldown(203) == false)

-- Everything secret: unknown, and the local provider gets the last word.
cooldownStructs[204] = {isOnGCD = makeSecret("gcd"), isActive = makeSecret("active")}
check("all-secret struct is unknown", Secret.isSpellOnRealCooldown(204) == nil)

Secret.localCooldownProvider = function(spellId)
    if spellId == 204 then
        return true
    end
    return nil
end
check("local provider resolves unknown", Secret.isSpellOnRealCooldown(204) == true)
check("local provider nil stays unknown", Secret.isSpellOnRealCooldown(205) == nil)
-- isOnGCD == true only means the GCD is running; a real cooldown can be ticking
-- underneath it. With the probe blind, the local tracker is the only witness --
-- and "no witness" must stay unknown, never "ready".
cooldownStructs[206] = {isOnGCD = true, isActive = true}
check("isOnGCD true with no tracker stays unknown", Secret.isSpellOnRealCooldown(206) == nil)
Secret.localCooldownProvider = function(spellId)
    if spellId == 206 then
        return true
    end
    if spellId == 207 then
        return false
    end
    return nil
end
check("isOnGCD true respects a tracked real cooldown", Secret.isSpellOnRealCooldown(206) == true)
cooldownStructs[207] = {isOnGCD = true, isActive = true}
check("isOnGCD true respects a tracked ready spell", Secret.isSpellOnRealCooldown(207) == false)
Secret.localCooldownProvider = nil

C_Spell.GetSpellCooldownDuration = savedDurationApi

--------------------------------------------------------------------------------
-- Charges
--------------------------------------------------------------------------------

charges[300] = {maxCharges = 2, isActive = true, currentCharges = makeSecret("cc")}
local maxCharges, recharging, currentCharges = Secret.getSpellChargeInfo(300)
check("charge max readable", maxCharges == 2)
check("charge isActive readable", recharging == true)
check("charge current secret is nil", currentCharges == nil)

local noMax = Secret.getSpellChargeInfo(301)
check("missing charge info is nil", noMax == nil)

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

check("absent buff is false", Secret.isBuffActive(400) == false)

playerAuras[401] = {auraInstanceID = 11}
cooldownDurations["aura11"] = {running = true}
check("present buff with running duration is true", Secret.isBuffActive(401) == true)

playerAuras[402] = {auraInstanceID = 12}
cooldownDurations["aura12"] = {running = false}
check("present buff with stopped duration is false", Secret.isBuffActive(402) == false)

-- Record present but instance id secret: the record itself still proves presence.
playerAuras[403] = {auraInstanceID = makeSecret("inst")}
check("present buff with secret instance is true", Secret.isBuffActive(403) == true)

-- The by-spell aura lookup is RequiresNonSecretAura: for a ContextuallySecret
-- aura it returns nil WHILE THE BUFF IS UP, so a missing record is only evidence
-- of absence when the engine says this aura is never secret.
C_Secrets.auraSecrecy = {}
C_Secrets.GetSpellAuraSecrecy = function(spellId)
    return C_Secrets.auraSecrecy[spellId]
end

C_Secrets.auraSecrecy[410] = 0
check("absent never-secret buff is confirmed absent", Secret.isBuffActive(410) == false)

C_Secrets.auraSecrecy[411] = 2 -- ContextuallySecret
C_Secrets.aurasSecret = true
check("absent contextually-secret buff is unknown", Secret.isBuffActive(411) == nil)

C_Secrets.auraSecrecy[412] = nil
check("unknown secrecy while auras hidden is unknown", Secret.isBuffActive(412) == nil)
C_Secrets.aurasSecret = false
check("unknown secrecy with auras readable is absent", Secret.isBuffActive(412) == false)
-- Out of combat nothing is hidden, so even a contextually-secret aura's absence
-- is provable -- otherwise no opener entry could ever be promoted.
check("contextually-secret absence is provable out of combat",
    Secret.isBuffActive(411) == false)
C_Secrets.GetSpellAuraSecrecy = nil

-- A record with no duration object at all is a permanent aura, not an absent one.
playerAuras[404] = {auraInstanceID = 77}
check("permanent buff without a duration stays active", Secret.isBuffActive(404) == true)

-- An id that has never resolved to a real aura must not be reported as a
-- trustworthy absence: SimC buff tokens can flatten to a CAST id.
check("never-seen aura id is not observed", Secret.hasObservedAura(9999) == false)
check("aura id becomes observed once it resolves", (function()
    playerAuras[420] = {auraInstanceID = 21}
    Secret.isBuffActive(420)
    return Secret.hasObservedAura(420) == true
end)())

check("own debuff instance detected", Secret.isOwnDebuffInstance("target", 1) == true)
check("foreign debuff instance rejected", Secret.isOwnDebuffInstance("target", 2) == false)

--------------------------------------------------------------------------------
-- Resources
--------------------------------------------------------------------------------

powerValues[4] = {current = 3, max = 5}
check("readable resource returns count", Secret.getResourceCount("combo_points") == 3)

C_Secrets.powerSecrecy[3] = 2 -- energy flagged secret
powerValues[3] = {current = 50, max = 100}
check("secret-flagged resource is unknown", Secret.getResourceCount("energy") == nil)

check("unknown token is unknown", Secret.getResourceCount("bananas") == nil)

-- Fractional resources must not assume a scale: without UnitPowerDisplayMod the
-- answer is unknown rather than off by a factor of ten.
powerValues[7] = {current = 0, rawFractional = 25, max = 5}
check("fractional resource without display mod is unknown",
    Secret.getResourceCount("soul_shard") == nil)
displayMod[7] = 10
check("fractional resource uses the engine scale", Secret.getResourceCount("soul_shard") == 2.5)
displayMod[7] = 0
check("nonsense display mod is unknown", Secret.getResourceCount("soul_shard") == nil)
displayMod[7] = 10

-- A resource the character does not have must read unknown, not zero.
powerValues[12] = {current = 0, max = 0}
check("zero-max resource is unknown", Secret.getResourceCount("chi") == nil)

--------------------------------------------------------------------------------
-- Target state
--------------------------------------------------------------------------------

targetHealth = 15
check("target health fraction", Secret.getTargetHealthFraction() == 0.15)
targetHealth = makeSecret("hp")
check("secret target health is unknown", Secret.getTargetHealthFraction() == nil)
targetHealth = 50
targetExists = false
Secret.resetPassCache()
check("no target means unknown health", Secret.getTargetHealthFraction() == nil)
targetExists = true
Secret.resetPassCache()

rangeVerdicts[600] = false
check("out of range confirmed", Secret.isSpellOutOfRange(600) == true)
rangeVerdicts[601] = true
check("in range confirmed", Secret.isSpellOutOfRange(601) == false)
check("no range info is unknown", Secret.isSpellOutOfRange(602) == nil)
rangeVerdicts[603] = makeSecret("range")
check("secret range is unknown", Secret.isSpellOutOfRange(603) == nil)
targetExists = false
-- Target presence is memoised per pass, so a stale answer must survive until
-- the pass is reset -- and must not survive past it.
check("target presence is memoised inside a pass", Secret.isSpellOutOfRange(600) == true)
Secret.resetPassCache()
check("no target means range unknown", Secret.isSpellOutOfRange(600) == nil)
targetExists = true
Secret.resetPassCache()

--------------------------------------------------------------------------------

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
