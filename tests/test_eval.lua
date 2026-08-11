#!/usr/bin/env lua
-- Unit tests for ShinkiliEval against a stubbed WoW API.
--
-- Two contracts under test:
--   1. Castability separates "confirmed uncastable" from "cannot tell", and
--      never treats transient resource starvation as a hard block.
--   2. A SimC entry passes only when EVERY gate was actually read and satisfied.

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

local secrets = setmetatable({}, {__mode = "k"})
local function makeSecret()
    local box = {}
    secrets[box] = true
    return box
end
issecretvalue = function(value)
    return secrets[value] == true
end

CreateFrame = function()
    return {Hide = function() end}
end
UIParent = {}

C_Secrets = {
    ShouldAurasBeSecret = function()
        return false
    end,
    ShouldCooldownsBeSecret = function()
        return false
    end,
    GetPowerTypeSecrecy = function(powerType)
        return powerType == 3 and 2 or 0 -- energy secret, everything else plain
    end,
}

local usable = {}        -- spellId -> {usable, noPower}
local overrides = {}     -- spellId -> display id
local cooldownStructs = {}
local charges = {}
local ranges = {}
local auras = {}
local powers = {[4] = {current = 4, max = 5}}

C_Spell = {
    IsSpellUsable = function(spellId)
        local entry = usable[spellId]
        if not entry then
            return true, false
        end
        return entry[1], entry[2]
    end,
    GetOverrideSpell = function(spellId)
        return overrides[spellId] or spellId
    end,
    GetSpellCooldown = function(spellId)
        return cooldownStructs[spellId]
    end,
    GetSpellCharges = function(spellId)
        return charges[spellId]
    end,
    IsSpellInRange = function(spellId)
        return ranges[spellId]
    end,
    GetSpellPowerCost = function()
        return {}
    end,
}

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellId)
        return auras[spellId]
    end,
}

local actionSlots = {}   -- slot -> spellId
local actionUsable = {}  -- slot -> {usable, noPower}
GetActionInfo = function(slot)
    local spellId = actionSlots[slot]
    if not spellId then
        return nil
    end
    return "spell", spellId
end
C_ActionBar = {
    IsUsableAction = function(slot)
        local entry = actionUsable[slot]
        if not entry then
            return nil, nil
        end
        return entry[1], entry[2]
    end,
}

UnitPower = function(_, powerType)
    local entry = powers[powerType]
    return entry and entry.current or nil
end
UnitPowerMax = function(_, powerType)
    local entry = powers[powerType]
    return entry and entry.max or 0
end

local plateCount = 1
C_NamePlate = {
    GetNamePlates = function()
        local out = {}
        for i = 1, plateCount do
            out[i] = {namePlateUnitToken = "nameplate" .. i}
        end
        return out
    end,
}
UnitCanAttack = function()
    return true
end
UnitIsDead = function()
    return false
end
UnitExists = function()
    return true
end
UnitHealth = function()
    return 100
end
UnitHealthMax = function()
    return 100
end
IsSpellOverlayed = function()
    return false
end
GetTime = function()
    return 0
end
InCombatLockdown = function()
    return false
end

dofile(root .. "../Shinkili/ShinkiliSecret.lua")
dofile(root .. "../Shinkili/ShinkiliTrack.lua")
dofile(root .. "../Shinkili/ShinkiliEval.lua")
local Eval = ShinkiliEval
local Secret = ShinkiliSecret

local dotState = {}
ShinkiliTrack.isDotActiveOnTarget = function(spellId)
    return dotState[spellId]
end
ShinkiliTrack.getChargesRemaining = function()
    return nil
end

--------------------------------------------------------------------------------
-- Display ids
--------------------------------------------------------------------------------

overrides[10] = 11
Eval.beginPass()
check("override resolves to display id", Eval.getDisplaySpellId(10) == 11)
check("plain id passes through", Eval.getDisplaySpellId(12) == 12)

-- The memo must not survive a new pass.
overrides[10] = 99
check("display id memoised inside a pass", Eval.getDisplaySpellId(10) == 11)
Eval.beginPass()
check("new pass re-reads the override", Eval.getDisplaySpellId(10) == 99)
overrides[10] = nil

--------------------------------------------------------------------------------
-- Castability
--------------------------------------------------------------------------------

local function freshPass()
    Eval.beginPass()
end

freshPass()
cooldownStructs[100] = {isActive = false}
check("usable and off cooldown is ready", Eval.getCastability(100) == "ready")

freshPass()
usable[101] = {false, false}
cooldownStructs[101] = {isActive = false}
check("structurally unusable is unusable", Eval.getCastability(101) == "unusable")

-- Talent / choice-node ownership: IsSpellUsable can still say ready for an
-- active id the player did not take (Prot Ravager passive side). IsPlayerSpell
-- is the filter; when the API is absent the path fails open (tests above).
freshPass()
local knownSpells = {[120] = true}
IsPlayerSpell = function(spellId)
    return knownSpells[spellId] == true
end
usable[120] = {true, false}
cooldownStructs[120] = {isActive = false}
usable[121] = {true, false}
cooldownStructs[121] = {isActive = false}
check("learned spell with usable ready stays ready", Eval.getCastability(120) == "ready")
check("unlearned spell is unusable even when IsSpellUsable is true", Eval.getCastability(121) == "unusable")
check("unlearned is not pickable", Eval.isPickable(121) == false)
-- Display-id form known, base id not: still allowed (override chains).
overrides[122] = 123
knownSpells[123] = true
usable[122] = {true, false}
cooldownStructs[122] = {isActive = false}
check("known via display override is ready", Eval.getCastability(122) == "ready")
overrides[122] = nil
IsPlayerSpell = nil

freshPass()
usable[102] = {false, true}
cooldownStructs[102] = {isActive = false}
check("resource starvation is not a hard block", Eval.getCastability(102) == "no_resource")

freshPass()
cooldownStructs[103] = {isActive = true}
check("real cooldown blocks", Eval.getCastability(103) == "on_cd")

freshPass()
cooldownStructs[104] = {isActive = false}
ranges[104] = false
check("confirmed out of range blocks", Eval.getCastability(104) == "out_of_range")

freshPass()
cooldownStructs[105] = {isActive = false}
ranges[105] = makeSecret()
check("secret range does not block", Eval.getCastability(105) == "ready")

-- Cooldown unreadable: not ready, but not blocked either.
freshPass()
check("unreadable cooldown is unknown", Eval.getCastability(106) == "unknown")

-- Usable secret: the action bar is the readable stand-in.
freshPass()
usable[107] = {makeSecret(), makeSecret()}
cooldownStructs[107] = {isActive = false}
actionSlots[3] = 107
actionUsable[3] = {false, false}
check("action bar covers a secret usable", Eval.getCastability(107) == "unusable")

freshPass()
Eval.onActionUsableChanged({{slot = 3, usable = true, noMana = false}})
check("ACTION_USABLE_CHANGED updates the slot cache", Eval.getCastability(107) == "ready")

freshPass()
Eval.invalidateActionBars()
actionUsable[3] = {false, true}
check("bar invalidation re-reads usability", Eval.getCastability(107) == "no_resource")

-- Charge spells stay castable while a charge is banked.
freshPass()
charges[108] = {maxCharges = 2, isActive = false}
check("charge spell not recharging is ready", Eval.getCastability(108) == "ready")

freshPass()
charges[109] = {maxCharges = 2, isActive = true}
check("recharging charge spell with unknown count is unknown", Eval.getCastability(109) == "unknown")

freshPass()
ShinkiliTrack.getChargesRemaining = function(spellId)
    return spellId == 109 and 0 or nil
end
check("recharging with zero tracked charges blocks", Eval.getCastability(109) == "on_cd")

-- currentCharges is plain out of combat; the real number must win over our
-- reconstruction whenever the client hands it over.
freshPass()
charges[112] = {maxCharges = 2, isActive = true, currentCharges = 1}
cooldownStructs[112] = {isActive = false}
ShinkiliTrack.getChargesRemaining = function(spellId)
    return spellId == 112 and 0 or nil
end
check("readable currentCharges beats the reconstruction", Eval.getCastability(112) == "ready")
freshPass()
charges[112].currentCharges = 0
check("readable zero currentCharges blocks", Eval.getCastability(112) == "on_cd")

-- Known-zero from the tracker must exclude even if the OOC scan said "not a
-- charge spell" (that scan can be wrong; an explicit 0 is safe).
freshPass()
charges[115] = {maxCharges = 2, isActive = true}
cooldownStructs[115] = {isActive = false}
usable[115] = {true, false}
ShinkiliTrack.isChargeSpell = function()
    return false
end
ShinkiliTrack.getChargesRemaining = function(spellId)
    return spellId == 115 and 0 or nil
end
check("known zero tracked charges blocks despite non-charge scan",
    Eval.getCastability(115) == "on_cd")
ShinkiliTrack.isChargeSpell = function()
    return nil
end
ShinkiliTrack.getChargesRemaining = function()
    return nil
end

-- A spell the scan proved has no charges must not pay for a GetSpellCharges
-- call every pass.
freshPass()
local chargeApiCalls = 0
local savedChargeApi = C_Spell.GetSpellCharges
C_Spell.GetSpellCharges = function(spellId)
    chargeApiCalls = chargeApiCalls + 1
    return savedChargeApi(spellId)
end
ShinkiliTrack.isChargeSpell = function()
    return false
end
cooldownStructs[113] = {isActive = false}
Eval.getCastability(113)
check("known non-charge spell skips the charge API", chargeApiCalls == 0)
-- A stale "no charges" scan must not hard-filter a spell that does have one
-- banked: the recharge running underneath reads exactly like a cooldown.
freshPass()
charges[114] = {maxCharges = 2, isActive = true}
cooldownStructs[114] = {isActive = true}
ShinkiliTrack.isChargeSpell = function()
    return false
end
ShinkiliTrack.getChargesRemaining = function(spellId)
    return spellId == 114 and 1 or nil
end
check("a wrong no-charge scan cannot hard-block", Eval.getCastability(114) == "ready")
ShinkiliTrack.getChargesRemaining = function()
    return nil
end
freshPass()
check("an unresolvable charge count is unknown, not blocked",
    Eval.getCastability(114) == "unknown")

ShinkiliTrack.isChargeSpell = function()
    return nil
end
C_Spell.GetSpellCharges = savedChargeApi

ShinkiliTrack.getChargesRemaining = function()
    return nil
end

-- "Cannot cast, reason unreadable" must not become a hard block: that would
-- filter a merely resource-starved spell out of the pool entirely.
freshPass()
usable[110] = {false, makeSecret()}
cooldownStructs[110] = {isActive = false}
check("unusable with a secret reason is unknown", Eval.getCastability(110) == "unknown")

-- An all-unknown ACTION_USABLE_CHANGED entry must not mask the live read.
freshPass()
Eval.invalidateActionBars()
actionSlots[4] = 111
actionUsable[4] = {true, false}
usable[111] = {makeSecret(), makeSecret()}
cooldownStructs[111] = {isActive = false}
check("live action-bar read works", Eval.getCastability(111) == "ready")
Eval.onActionUsableChanged({{slot = 4, usable = makeSecret(), noMana = makeSecret()}})
freshPass()
check("unknown slot update does not mask the live read", Eval.getCastability(111) == "ready")

--------------------------------------------------------------------------------
-- Defense box
--------------------------------------------------------------------------------

freshPass()
check("ready defensive shows", Eval.isUsableForDisplay(100) == true)
check("on-cooldown defensive hides", Eval.isUsableForDisplay(103) == false)
check("unaffordable defensive hides", Eval.isUsableForDisplay(102) == false)
check("unreadable defensive still shows", Eval.isUsableForDisplay(106) == true)

--------------------------------------------------------------------------------
-- Nameplate counting under secret values
--------------------------------------------------------------------------------

freshPass()
plateCount = 3
check("live hostiles counted", Eval.countHostileNameplates() == 3)

-- UnitIsDead is health-derived and health is secret; a secret must not be read
-- as "alive" by truthiness.
UnitIsDead = function()
    return makeSecret()
end
freshPass()
check("secret dead flag does not inflate the count", Eval.countHostileNameplates() == 3)
UnitIsDead = function()
    return true
end
freshPass()
check("dead hostiles excluded, target fallback applies", Eval.countHostileNameplates() == 0)
UnitIsDead = function()
    return false
end
plateCount = 0
freshPass()
check("target fallback counts one", Eval.countHostileNameplates() == 1)
plateCount = 1

--------------------------------------------------------------------------------
-- SimC gates
--------------------------------------------------------------------------------

freshPass()
check("no gates passes", Eval.evaluateEntry({id = 200}) == "pass")

-- An unconditional APL line still must not re-apply something already up.
auras[205] = {auraInstanceID = 9}
freshPass()
check("gateless entry blocked by its own active buff",
    Eval.evaluateEntry({id = 205}) == "fail")
dotState[206] = true
freshPass()
check("gateless entry blocked by its own live dot",
    Eval.evaluateEntry({id = 206}) == "fail")
dotState[206] = nil
freshPass()
check("delegated entry is always unknown",
    Eval.evaluateEntry({id = 200, delegated = true}) == "unknown")
check("non-table entry is unknown", Eval.evaluateEntry(200) == "unknown")
check("unknown gate type is unknown",
    Eval.evaluateEntry({id = 200, gates = {{t = "wat"}}}) == "unknown")

-- Malformed data must not crash the per-pass memo with a nil table key.
check("entry with no id is unknown, not an error", (function()
    -- Reaches memoTriState with a nil key via the cd gate's reference lookup.
    local ok, verdict = pcall(Eval.evaluateEntry, {gates = {{t = "cd", id = 999999}}})
    return ok and verdict == "unknown"
end)())
check("dot gate with no id anywhere is unknown, not an error", (function()
    local ok, verdict = pcall(Eval.evaluateEntry, {gates = {{t = "dot", neg = true}}})
    return ok and verdict == "unknown"
end)())
check("gateless entry with no id is unknown, not an error", (function()
    local ok, verdict = pcall(Eval.evaluateEntry, {})
    return ok and verdict == "pass"
end)())
check("buff gate with no id is unknown", (function()
    local ok, verdict = pcall(Eval.evaluateEntry, {id = 201, gates = {{t = "buff"}}})
    return ok and verdict == "unknown"
end)())

-- Gates must judge the same id castability judges: an override spell would
-- otherwise have its condition and its castability answered for two spells.
overrides[280] = 281
cooldownStructs[280] = {isActive = true}
cooldownStructs[281] = {isActive = false}
auras[281] = {auraInstanceID = 41}
freshPass()
Secret.isBuffActive(281)
freshPass()
check("gates resolve the entry id through the display form",
    Eval.evaluateEntry({id = 280}) == "fail")
overrides[280] = nil

-- cd
freshPass()
-- SimC's cooldown conditions name another spell and the upstream flattener drops
-- the reference, so a bare {t="cd"} is not evaluable. Reading it as the entry's
-- own cooldown would be a vacuous pass: Stage C already demands `ready`.
cooldownStructs[201] = {isActive = false}
check("bare cd gate is unknown", Eval.evaluateEntry({id = 201, gates = {{t = "cd"}}}) == "unknown")
check("cd gate with a reference id passes when that spell is ready",
    Eval.evaluateEntry({id = 202, gates = {{t = "cd", id = 201}}}) == "pass")
cooldownStructs[202] = {isActive = true}
check("cd gate with a reference id fails when that spell is down",
    Eval.evaluateEntry({id = 201, gates = {{t = "cd", id = 202}}}) == "fail")
check("negated cd gate inverts",
    Eval.evaluateEntry({id = 201, gates = {{t = "cd", id = 202, neg = true}}}) == "pass")
check("cd gate unknown when the referenced spell is unreadable",
    Eval.evaluateEntry({id = 201, gates = {{t = "cd", id = 203}}}) == "unknown")

-- The cd gate must not disagree with castability on a charge spell.
freshPass()
charges[205] = {maxCharges = 2, isActive = true}
cooldownStructs[205] = {isActive = true}
ShinkiliTrack.getChargesRemaining = function(spellId)
    return spellId == 205 and 1 or nil
end
check("cd gate on a charge spell sees the banked charge",
    Eval.evaluateEntry({id = 206, gates = {{t = "cd", id = 205}}}) == "pass")
check("castability agrees with the cd gate", Eval.getCastability(205) == "ready")
ShinkiliTrack.getChargesRemaining = function()
    return nil
end

-- buff
freshPass()
auras[300] = {auraInstanceID = 1}
check("positive buff gate passes when up",
    Eval.evaluateEntry({id = 210, gates = {{t = "buff", id = 300}}}) == "pass")
check("positive buff gate fails when down",
    Eval.evaluateEntry({id = 211, gates = {{t = "buff", id = 301}}}) == "fail")
check("negative buff gate fails when up",
    Eval.evaluateEntry({id = 212, gates = {{t = "buff", id = 300, neg = true}}}) == "fail")
-- 301 has never resolved to a real aura, so its "absence" is not evidence.
check("negative buff gate on an unseen id is unknown",
    Eval.evaluateEntry({id = 213, gates = {{t = "buff", id = 301, neg = true}}}) == "unknown")

-- Once the aura has been seen at least once, absence becomes provable.
auras[301] = {auraInstanceID = 31}
freshPass()
check("negative buff gate fails while that buff is up",
    Eval.evaluateEntry({id = 213, gates = {{t = "buff", id = 301, neg = true}}}) == "fail")
auras[301] = nil
freshPass()
check("negative buff gate passes once the seen buff drops",
    Eval.evaluateEntry({id = 213, gates = {{t = "buff", id = 301, neg = true}}}) == "pass")

-- An unreadable aura stays unknown. The spell-overlay API answers "is this spell
-- highlighted", not "is buff X up", so it must never rescue a buff gate.
local savedGetAura = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = nil
IsSpellOverlayed = function()
    return true
end
freshPass()
check("unreadable buff stays unknown despite an overlay",
    Eval.evaluateEntry({id = 214, gates = {{t = "buff", id = 302}}}) == "unknown")
check("unreadable negative buff stays unknown",
    Eval.evaluateEntry({id = 215, gates = {{t = "buff", id = 302, neg = true}}}) == "unknown")
C_UnitAuras.GetPlayerAuraBySpellID = savedGetAura
IsSpellOverlayed = function()
    return false
end

-- isProcActive itself must not branch on a secret return.
IsSpellOverlayed = function()
    return makeSecret()
end
check("secret overlay does not read as a proc", Eval.isProcActive(999) == false)
IsSpellOverlayed = function()
    return false
end

-- dot
freshPass()
dotState[400] = true
dotState[401] = false
-- Polarity is load-bearing: SimC's `dot.x.ticking` and `!dot.x.ticking` both
-- flatten to a bare {t="dot",id}, and guessing one inverts the other.
check("dot gate without polarity is unknown",
    Eval.evaluateEntry({id = 220, gates = {{t = "dot", id = 400}}}) == "unknown")
check("negated dot gate fails while the dot is live",
    Eval.evaluateEntry({id = 220, gates = {{t = "dot", id = 400, neg = true}}}) == "fail")
check("negated dot gate passes when the dot is gone",
    Eval.evaluateEntry({id = 221, gates = {{t = "dot", id = 401, neg = true}}}) == "pass")
check("positive dot gate passes while the dot is live",
    Eval.evaluateEntry({id = 220, gates = {{t = "dot", id = 400, neg = false}}}) == "pass")
check("dot gate unknown when untracked",
    Eval.evaluateEntry({id = 222, gates = {{t = "dot", id = 402, neg = true}}}) == "unknown")

-- execute: the flattener drops the threshold, so only the extremes decide
-- Most upstream `execute` lines are actually `target.time_to_die>N` or
-- `health.pct>N` -- "NOT in execute range" -- so without the operator the gate
-- would be inverted half the time.
UnitHealth = function()
    return 10
end
freshPass()
check("execute gate without an operator is unknown",
    Eval.evaluateEntry({id = 230, gates = {{t = "execute"}}}) == "unknown")
check("execute gate with an operator passes below the threshold",
    Eval.evaluateEntry({id = 230, gates = {{t = "execute", op = "<=", n = 20}}}) == "pass")
check("inverted execute gate fails below the threshold",
    Eval.evaluateEntry({id = 230, gates = {{t = "execute", op = ">", n = 20}}}) == "fail")
UnitHealth = function()
    return 80
end
freshPass()
check("execute gate fails at high health",
    Eval.evaluateEntry({id = 231, gates = {{t = "execute", op = "<=", n = 20}}}) == "fail")
check("inverted execute gate passes at high health",
    Eval.evaluateEntry({id = 231, gates = {{t = "execute", op = ">", n = 20}}}) == "pass")
UnitHealth = function()
    return 100
end
freshPass()

-- resource
freshPass()
check("resource gate passes on a readable comparison",
    Eval.evaluateEntry({id = 240, gates = {{t = "resource", res = "combo_points", op = "<", n = 5}}}) == "pass")
check("resource gate fails on a readable comparison",
    Eval.evaluateEntry({id = 241, gates = {{t = "resource", res = "combo_points", op = ">=", n = 5}}}) == "fail")
check("secret resource is unknown",
    Eval.evaluateEntry({id = 242, gates = {{t = "resource", res = "energy", op = ">=", n = 50}}}) == "unknown")
check("unmapped resource is unknown",
    Eval.evaluateEntry({id = 243, gates = {{t = "resource", res = "bananas", op = ">=", n = 1}}}) == "unknown")

-- targets
freshPass()
plateCount = 4
check("targets gate reads nameplates",
    Eval.evaluateEntry({id = 250, gates = {{t = "targets", op = ">=", n = 3}}}) == "pass")
check("targets gate fails below the threshold",
    Eval.evaluateEntry({id = 251, gates = {{t = "targets", op = ">=", n = 8}}}) == "fail")
plateCount = 1

-- Aggregation
freshPass()
cooldownStructs[260] = {isActive = true}
cooldownStructs[261] = {isActive = false}
check("a single failed gate fails the entry",
    Eval.evaluateEntry({id = 262, gates = {{t = "cd", id = 260}, {t = "buff", id = 300}}}) == "fail")
check("a single unknown gate downgrades the entry",
    Eval.evaluateEntry({id = 262, gates = {{t = "cd", id = 261}, {t = "dot", id = 402, neg = true}}}) == "unknown")
check("all-satisfied gates pass",
    Eval.evaluateEntry({id = 262, gates = {{t = "cd", id = 261}, {t = "buff", id = 300}}}) == "pass")

-- Diagnostics
local described = Eval.describeEntry({id = 262, gates = {{t = "cd", id = 261}, {t = "dot", id = 402, neg = true}}})
check("describeEntry lists every gate", #described == 2)
check("describeEntry reports verdicts",
    described[1].kind == "cd" and described[1].verdict == "pass"
        and described[2].kind == "dot" and described[2].verdict == "unknown")
-- A gateless entry is judged by the self-redundancy veto; /sk why has to say so
-- instead of printing "fail" with an empty gate list.
auras[205] = {auraInstanceID = 9}
freshPass()
Secret.isBuffActive(205)
freshPass()
local gatelessDetail = Eval.describeEntry({id = 205})
check("describeEntry explains a gateless veto",
    #gatelessDetail == 2 and gatelessDetail[1].kind == "self-buff"
        and gatelessDetail[1].verdict == "fail")

local savedAuraApi = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = nil
freshPass()
local unreadableDetail = Eval.describeEntry({id = 9001})
check("describeEntry reports an unreadable self-buff as unknown",
    unreadableDetail[1].kind == "self-buff" and unreadableDetail[1].verdict == "unknown")
C_UnitAuras.GetPlayerAuraBySpellID = savedAuraApi
freshPass()

local delegatedDetail = Eval.describeEntry({id = 262, delegated = true})
check("describeEntry surfaces delegated",
    #delegatedDetail == 1 and delegatedDetail[1].kind == "delegated")

--------------------------------------------------------------------------------
-- Per-pass memo actually deduplicates
--
-- Without a call count these probes could silently lose their memo: every gate
-- kind repeats the same spell id several times inside one pass, and each probe
-- is a widget round-trip or an aura scan at 20Hz.
--------------------------------------------------------------------------------

local counts = {cooldown = 0, aura = 0, charges = 0, plates = 0}
local savedCooldown = C_Spell.GetSpellCooldown
local savedAura = C_UnitAuras.GetPlayerAuraBySpellID
local savedCharges = C_Spell.GetSpellCharges
local savedPlates = C_NamePlate.GetNamePlates

C_Spell.GetSpellCooldown = function(spellId)
    counts.cooldown = counts.cooldown + 1
    return savedCooldown(spellId)
end
C_UnitAuras.GetPlayerAuraBySpellID = function(spellId)
    counts.aura = counts.aura + 1
    return savedAura(spellId)
end
C_Spell.GetSpellCharges = function(spellId)
    counts.charges = counts.charges + 1
    return savedCharges(spellId)
end
C_NamePlate.GetNamePlates = function()
    counts.plates = counts.plates + 1
    return savedPlates()
end

freshPass()
cooldownStructs[700] = {isActive = false}
auras[701] = {auraInstanceID = 12}
charges[700] = nil
for _ = 1, 4 do
    Eval.getCastability(700)
    Eval.evaluateEntry({id = 702, gates = {{t = "cd", id = 700}}})
    Eval.evaluateEntry({id = 703, gates = {{t = "buff", id = 701}}})
    Eval.evaluateEntry({id = 704, gates = {{t = "targets", op = ">=", n = 1}}})
end
check("cooldown probe runs once per pass", counts.cooldown == 1,
    "got " .. counts.cooldown)
check("aura probe runs once per pass", counts.aura == 1, "got " .. counts.aura)
check("charge probe runs once per pass", counts.charges == 1, "got " .. counts.charges)
check("nameplate scan runs once per pass", counts.plates == 1, "got " .. counts.plates)

freshPass()
Eval.getCastability(700)
check("a new pass re-probes", counts.cooldown == 2, "got " .. counts.cooldown)

-- beginPass must also clear Secret's pass-scoped scalars, or a target change
-- would not be seen until the next reload.
local existsCalls = 0
local savedUnitExists = UnitExists
UnitExists = function(unit)
    existsCalls = existsCalls + 1
    return savedUnitExists(unit)
end
freshPass()
ranges[705] = true
Eval.getCastability(705)
Eval.getCastability(706)
Eval.getCastability(707)
check("target presence is read once per pass", existsCalls == 1, "got " .. existsCalls)
freshPass()
Eval.getCastability(705)
check("beginPass resets the target cache", existsCalls == 2, "got " .. existsCalls)
UnitExists = savedUnitExists

C_Spell.GetSpellCooldown = savedCooldown
C_UnitAuras.GetPlayerAuraBySpellID = savedAura
C_Spell.GetSpellCharges = savedCharges
C_NamePlate.GetNamePlates = savedPlates

--------------------------------------------------------------------------------

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
