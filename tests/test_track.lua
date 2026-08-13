#!/usr/bin/env lua
-- Unit tests for ShinkiliTrack against a stubbed WoW API.
--
-- The contract under test: the tracker may answer true or false only when it has
-- actually observed the state, and must answer nil otherwise so the pick
-- pipeline falls back to Blizzard's own recommendation.

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

issecretvalue = function()
    return false
end

CreateFrame = function()
    return {Hide = function() end}
end
UIParent = {}

local cooldownsSecret = false
C_Secrets = {
    ShouldAurasBeSecret = function()
        return false
    end,
    ShouldCooldownsBeSecret = function()
        return cooldownsSecret
    end,
    GetPowerTypeSecrecy = function()
        return 0
    end,
}

local baseCooldownMs = {}
local chargeInfo = {}
local realCooldown = {} -- spellId -> bool, drives C_Spell.GetSpellCooldown.isActive

GetSpellBaseCooldown = function(spellId)
    return baseCooldownMs[spellId]
end

C_Spell = {
    GetSpellCharges = function(spellId)
        return chargeInfo[spellId]
    end,
    GetSpellCooldown = function(spellId)
        local active = realCooldown[spellId]
        if active == nil then
            return nil
        end
        return {isActive = active}
    end,
}

local targetAuras = {}
local targetExists = true

C_UnitAuras = {
    GetUnitAuras = function()
        return targetAuras
    end,
    IsAuraFilteredOutByInstanceID = function(_, instanceId)
        return instanceId >= 900 -- 900+ belongs to someone else
    end,
}

UnitExists = function()
    return targetExists
end

local clock = 1000
GetTime = function()
    return clock
end

dofile(root .. "../Shinkili/ShinkiliSecret.lua")
dofile(root .. "../Shinkili/ShinkiliTrack.lua")
local Track = ShinkiliTrack
Track.timeSource = function()
    return clock
end

--------------------------------------------------------------------------------
-- Base cooldown scan + local cooldown
--------------------------------------------------------------------------------

baseCooldownMs[10] = 30000 -- 30s
baseCooldownMs[11] = 0 -- no real cooldown
Track.scanSpells({10, 11})

check("untracked spell is unknown", Track.isOnLocalCooldown(99) == nil)
check("zero base cooldown is never on cooldown", Track.isOnLocalCooldown(11) == false)
check("scanned spell with no cast is unknown", Track.isOnLocalCooldown(10) == nil)

Track.noteSpellCast(10)
check("cast starts local cooldown", Track.isOnLocalCooldown(10) == true)

clock = clock + 29
check("cooldown still running before expiry", Track.isOnLocalCooldown(10) == true)
clock = clock + 2
check("cooldown clears after expiry", Track.isOnLocalCooldown(10) == false)

-- Casting a spell we never scanned must not invent a cooldown.
Track.noteSpellCast(98)
check("unscanned cast stays unknown", Track.isOnLocalCooldown(98) == nil)

-- Secret combat state must not poison the static cache.
cooldownsSecret = true
baseCooldownMs[12] = 45000
Track.scanSpells({12})
check("scan skipped while cooldowns secret", Track.isOnLocalCooldown(12) == nil)
cooldownsSecret = false
Track.scanSpells({12})
Track.noteSpellCast(12)
check("scan works once readable again", Track.isOnLocalCooldown(12) == true)

--------------------------------------------------------------------------------
-- AC pick oracle
--------------------------------------------------------------------------------

clock = clock + 1
Track.noteSpellCast(10)
Track.noteSpellRecommended(10)
check("fresh cast survives the pick oracle", Track.isOnLocalCooldown(10) == true)

clock = clock + 2 -- past RECOMMEND_GRACE
Track.noteSpellRecommended(10)
-- The entry is dropped, so the tracker goes back to "unknown" rather than
-- claiming the spell is down. Only the dangerous direction (a false on-cooldown)
-- is corrected here.
check("stale entry expired by the pick oracle", Track.isOnLocalCooldown(10) == nil)

--------------------------------------------------------------------------------
-- Engine-truth cooldown correction
--------------------------------------------------------------------------------

Track.noteSpellCast(10)
check("cooldown re-armed", Track.isOnLocalCooldown(10) == true)
realCooldown[10] = false -- engine says it is ready (haste / CDR)
Track.refreshCooldowns()
check("engine truth clears an early cooldown", Track.isOnLocalCooldown(10) == nil)
realCooldown[10] = nil

--------------------------------------------------------------------------------
-- Charges
--------------------------------------------------------------------------------

baseCooldownMs[20] = 0
chargeInfo[20] = {maxCharges = 2, isActive = false, cooldownDuration = 15, currentCharges = 2}
Track.scanSpells({20})

check("charge spell starts untracked", Track.getChargesRemaining(20) == nil)
check("scan records it as a charge spell", Track.isChargeSpell(20) == true)
check("scanned non-charge spell is known not to have charges", Track.isChargeSpell(10) == false)
check("unscanned spell charge status is unknown", Track.isChargeSpell(9999) == nil)
Track.noteSpellCast(20)
check("first cast leaves one charge", Track.getChargesRemaining(20) == 1)
Track.noteSpellCast(20)
check("second cast empties charges", Track.getChargesRemaining(20) == 0)

clock = clock + 15
check("recharge restores one charge", Track.getChargesRemaining(20) == 1)
clock = clock + 15
check("recharge restores to max", Track.getChargesRemaining(20) == 2)
clock = clock + 100
check("recharge never exceeds max", Track.getChargesRemaining(20) == 2)

-- isActive == false can only happen at full charges: snap a drifted count.
Track.noteSpellCast(20)
check("cast drops back to one", Track.getChargesRemaining(20) == 1)
chargeInfo[20].isActive = false
Track.refreshCharges()
check("isActive false snaps charges to full", Track.getChargesRemaining(20) == 2)

-- The count must never be invented. With currentCharges secret and no prior
-- observation, "how many are banked" is unknown -- guessing full is how a spell
-- with zero charges ends up reading `ready`.
Track.reset()
chargeInfo[21] = {maxCharges = 2, isActive = true, cooldownDuration = 15}
baseCooldownMs[21] = 0
Track.scanSpells({21})
Track.noteSpellCast(21)
check("unreadable charge count stays unknown", Track.getChargesRemaining(21) == nil)
check("the pick oracle cannot invent a charge either", (function()
    clock = clock + 5
    Track.noteSpellRecommended(21)
    return Track.getChargesRemaining(21) == nil
end)())
-- A readable count settles it.
chargeInfo[21].currentCharges = 0
Track.refreshCharges()
check("a readable count resolves the unknown", Track.getChargesRemaining(21) == 0)
chargeInfo[21].currentCharges = nil

-- Re-arm the earlier fixture for the oracle case below.
Track.reset()
Track.scanSpells({20})
Track.noteSpellCast(20)
Track.noteSpellCast(20)

-- The pick oracle also un-sticks a zero-charge entry.
check("charges emptied again", Track.getChargesRemaining(20) == 0)
clock = clock + 5
Track.noteSpellRecommended(20)
check("pick oracle restores a usable charge", Track.getChargesRemaining(20) == 1)

--------------------------------------------------------------------------------
-- Target DoTs
--------------------------------------------------------------------------------

-- Before the spec is known we must not guess which casts are DoTs; an empty
-- watch list means "this spec has none", not "track everything".
Track.resetDots()
targetAuras = {}
Track.noteDotCast(30)
check("unconfigured watch list tracks nothing", Track.isDotActiveOnTarget(30) == false)
Track.setDotWatchList({})
Track.noteDotCast(30)
check("empty watch list tracks nothing", Track.isDotActiveOnTarget(30) == false)

Track.setDotWatchList({30, 31, 32, 40})
Track.resetDots()
check("no debuffs at all means dot absent", Track.isDotActiveOnTarget(30) == false)

targetAuras = {{auraInstanceID = 901}} -- someone else's debuff
check("foreign debuff leaves dot unknown", Track.isDotActiveOnTarget(30) == nil)

Track.noteDotCast(30)
check("post-cast window reports dot active", Track.isDotActiveOnTarget(30) == true)

Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 5}}})
check("bridge confirms our instance", Track.isDotActiveOnTarget(30) == true)

Track.onTargetAuraUpdate({removedAuraInstanceIDs = {5}})
check("removed instance reports dot absent", Track.isDotActiveOnTarget(30) == false)

-- A foreign aura must not consume our pending cast.
Track.resetDots()
Track.noteDotCast(31)
Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 950}}})
Track.onTargetAuraUpdate({removedAuraInstanceIDs = {950}})
check("foreign aura did not bind our cast", Track.isDotActiveOnTarget(31) == true)

-- Re-applying clears the confirmed-then-removed latch, otherwise the freshly
-- cast DoT keeps reading as a confident absence and the gate keeps telling the
-- player to cast it again.
Track.resetDots()
targetAuras = {{auraInstanceID = 901}}
Track.noteDotCast(30)
Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 6}}})
Track.onTargetAuraUpdate({removedAuraInstanceIDs = {6}})
check("dot reads absent after removal", Track.isDotActiveOnTarget(30) == false)
Track.noteDotCast(30)
check("recast clears the removal latch", Track.isDotActiveOnTarget(30) == true)

-- A pending cast older than the bridge window must not capture a later aura.
Track.resetDots()
Track.noteDotCast(31)
clock = clock + 3 -- past DOT_BRIDGE_WINDOW
Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 9}}})
Track.onTargetAuraUpdate({removedAuraInstanceIDs = {9}})
check("expired pending cast did not capture the aura",
    Track.isDotActiveOnTarget(31) == true)
clock = clock + 31
targetAuras = {{auraInstanceID = 901}}
check("and its window still expires normally", Track.isDotActiveOnTarget(31) == nil)

-- Unconfirmed cast eventually stops claiming the DoT is up.
clock = clock + 31
targetAuras = {{auraInstanceID = 901}}
check("stale unconfirmed window expires", Track.isDotActiveOnTarget(31) == nil)

-- A full aura update carries neither addedAuras nor removedAuraInstanceIDs, so a
-- removal it replaced would never be seen and the instance would pin the DoT to
-- "live" for the rest of the fight.
Track.resetDots()
targetAuras = {{auraInstanceID = 7}}
Track.noteDotCast(32)
Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 7}}})
check("instance confirmed before the full update", Track.isDotActiveOnTarget(32) == true)
Track.onTargetAuraUpdate({isFullUpdate = true})
targetAuras = {}
check("full update clears the stale instance map", Track.isDotActiveOnTarget(32) == false)

-- Only watched ids enter the bridge queue, so a filler cannot consume the aura
-- slot the real DoT was waiting for.
Track.resetDots()
Track.setDotWatchList({40})
targetAuras = {}
Track.noteDotCast(41) -- filler, not watched
Track.noteDotCast(40) -- the real DoT
Track.onTargetAuraUpdate({addedAuras = {{auraInstanceID = 8}}})
check("filler stayed out of the bridge queue", Track.isDotActiveOnTarget(41) == false)
check("watched dot got the instance", Track.isDotActiveOnTarget(40) == true)
Track.onTargetAuraUpdate({removedAuraInstanceIDs = {8}})
check("watched dot released on removal", Track.isDotActiveOnTarget(40) == false)
Track.setDotWatchList(nil)

targetExists = false
check("no target means dot unknown", Track.isDotActiveOnTarget(30) == nil)
targetExists = true

-- Without the plain-list API the count is unknowable; a confident zero here
-- would let every dot gate pass on no evidence.
local savedGetUnitAuras = C_UnitAuras.GetUnitAuras
C_UnitAuras.GetUnitAuras = nil
Track.resetDots()
check("no plain aura list means dot unknown", Track.isDotActiveOnTarget(50) == nil)
C_UnitAuras.GetUnitAuras = savedGetUnitAuras

-- 12.1: secret vectors and UNIT_AURA payloads must not be measured or walked.
Track.setDotWatchList({30})
Track.resetDots()
targetAuras = {}
local savedAurasSecret = C_Secrets.ShouldAurasBeSecret
C_Secrets.ShouldAurasBeSecret = function()
    return true
end
check("secret aura list does not claim absence", Track.isDotActiveOnTarget(30) == nil)

Track.noteDotCast(30)
Track.onTargetAuraUpdate({
    addedAuras = {{auraInstanceID = 5}},
    removedAuraInstanceIDs = {5},
    isFullUpdate = true,
})
check("secret UNIT_AURA payload is ignored", Track.isDotActiveOnTarget(30) == true)
C_Secrets.ShouldAurasBeSecret = savedAurasSecret
clock = clock + 31
targetAuras = {{auraInstanceID = 901}}
check("post-cast window still expires after ignored payload",
    Track.isDotActiveOnTarget(30) == nil)

Track.resetDots()
targetAuras = {}
local secretList = {}
local savedIsSecret = issecretvalue
issecretvalue = function(value)
    return value == secretList
end
C_UnitAuras.GetUnitAuras = function()
    return secretList
end
check("secret vector length is unknown", Track.isDotActiveOnTarget(30) == nil)
C_UnitAuras.GetUnitAuras = savedGetUnitAuras

Track.resetDots()
Track.noteDotCast(30)
local secretAdded = {{auraInstanceID = 5}}
issecretvalue = function(value)
    return value == secretAdded
end
Track.onTargetAuraUpdate({addedAuras = secretAdded})
issecretvalue = savedIsSecret
clock = clock + 31
targetAuras = {{auraInstanceID = 901}}
check("secret addedAuras vector does not confirm the bridge",
    Track.isDotActiveOnTarget(30) == nil)

Track.resetDots()
targetAuras = {}
local flaggedList = {}
issecrettable = function(value)
    return value == flaggedList
end
C_UnitAuras.GetUnitAuras = function()
    return flaggedList
end
check("issecrettable vector length is unknown", Track.isDotActiveOnTarget(30) == nil)
C_UnitAuras.GetUnitAuras = savedGetUnitAuras
issecrettable = nil

-- resyncCooldowns must drop entries the engine says are finished.
Track.reset()
baseCooldownMs[60] = 30000
Track.scanSpells({60})
Track.noteSpellCast(60)
check("cooldown armed before resync", Track.isOnLocalCooldown(60) == true)
realCooldown[60] = false
Track.handleEvent("PLAYER_REGEN_ENABLED")
check("combat exit resync clears a finished cooldown", Track.isOnLocalCooldown(60) == nil)
realCooldown[60] = nil

-- Spec change wipes the static caches, so a scanned zero no longer answers.
baseCooldownMs[61] = 0
Track.scanSpells({61})
check("scanned zero cooldown answers", Track.isOnLocalCooldown(61) == false)
Track.handleEvent("PLAYER_SPECIALIZATION_CHANGED")
check("spec change clears the static cache", Track.isOnLocalCooldown(61) == nil)

-- The engine cross-check is a widget round-trip per tracked spell and
-- SPELL_UPDATE_COOLDOWN fires every GCD, so it must be throttled.
Track.reset()
baseCooldownMs[70] = 30000
Track.scanSpells({70})
Track.noteSpellCast(70)
local probeCalls = 0
local savedGetCooldown = C_Spell.GetSpellCooldown
C_Spell.GetSpellCooldown = function(spellId)
    probeCalls = probeCalls + 1
    return savedGetCooldown(spellId)
end
Track.refreshCooldowns()
local firstSweep = probeCalls
Track.refreshCooldowns()
Track.refreshCooldowns()
check("repeat cooldown sweeps inside the window do not re-probe",
    probeCalls == firstSweep and firstSweep > 0)
clock = clock + 1
Track.refreshCooldowns()
check("the sweep probes again after the throttle window", probeCalls > firstSweep)
C_Spell.GetSpellCooldown = savedGetCooldown

Track.setDotWatchList({30})
Track.resetDots()
Track.handleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 30)
check("event routing records the cast", Track.isDotActiveOnTarget(30) == true)
Track.handleEvent("PLAYER_TARGET_CHANGED")
targetAuras = {}
check("target change clears dot state", Track.isDotActiveOnTarget(30) == false)

--------------------------------------------------------------------------------

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
