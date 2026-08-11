-- Shinkili evaluation layer.
--
-- Everything that answers "what does the game say about this spell right now?"
-- lives here: display-id resolution, castability, and SimC gate verdicts. It
-- sits on ShinkiliSecret (tri-state secret-safe reads) and ShinkiliTrack (local
-- cooldown / charge / DoT reconstruction).
--
-- The whole layer keeps the same contract: true / false / "unknown". Unknown is
-- never upgraded to a guess, because the pick pipeline uses it to decide that
-- SimC may NOT override Blizzard's live Assisted Combat recommendation.

ShinkiliEval = ShinkiliEval or {}
local Eval = ShinkiliEval
local Secret = ShinkiliSecret

local pcall = pcall
local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring

--------------------------------------------------------------------------------
-- Per-pass memo
--
-- The pick runs 20 times a second and asks the same questions about the same
-- spells many times inside one pass (pool build, blacklist match, gate probes,
-- colour lookup). These caches are wiped at the top of every pass, so an answer
-- can never outlive the frame it was read in.
--------------------------------------------------------------------------------

local displayIdCache = {}
local castabilityCache = {}
local cooldownCache = {}
local buffCache = {}
local dotCache = {}
local passScalars = {}

local function clearTable(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

function Eval.beginPass()
    Secret.resetPassCache()
    clearTable(displayIdCache)
    clearTable(castabilityCache)
    clearTable(cooldownCache)
    clearTable(buffCache)
    clearTable(dotCache)
    clearTable(passScalars)
end

-- Tri-state values cannot be memoised directly (nil is a real answer), so they
-- are boxed. Only three values are ever stored, so the boxes are shared module
-- constants rather than a fresh table per key -- this runs 20 times a second
-- over every spell in the pool and the garbage adds up.
local BOX_TRUE = {true}
local BOX_FALSE = {false}
local BOX_NIL = {}

local function memoTriState(cache, key, compute)
    if key == nil then
        -- Malformed data reaches here (an entry or gate with no id). Writing a
        -- nil key would throw; there is nothing to answer about anyway.
        return nil
    end
    local boxed = cache[key]
    if boxed ~= nil then
        return boxed[1]
    end
    local value = compute(key)
    cache[key] = (value == true and BOX_TRUE) or (value == false and BOX_FALSE) or BOX_NIL
    return value
end

--- Display / transform spell id (action-bar override form). Also used by the
--- mapping lookup so a colour bound to the book id still matches.
function Eval.getDisplaySpellId(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return spellId
    end
    local cached = displayIdCache[spellId]
    if cached then
        return cached
    end

    local resolved = spellId
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, override = pcall(C_Spell.GetOverrideSpell, spellId)
        if ok then
            override = Secret.plainNumber(override)
            if override and override > 0 then
                resolved = override
            end
        end
    end
    displayIdCache[spellId] = resolved
    return resolved
end

--------------------------------------------------------------------------------
-- Castability: "can the character actually press this right now?"
--
-- Every input is tri-state (true / false / nil-unknown) so the pick pipeline can
-- tell a confirmed-bad spell from one we simply cannot read. Only confirmed-bad
-- states exclude a spell; unknown always fails open to Blizzard's own pick.
--------------------------------------------------------------------------------

local CAST_READY = "ready"
local CAST_NO_RESOURCE = "no_resource"
local CAST_UNUSABLE = "unusable"
local CAST_OUT_OF_RANGE = "out_of_range"
local CAST_ON_COOLDOWN = "on_cd"
local CAST_UNKNOWN = "unknown"

local ACTION_SLOT_MAX = 180

local slotUsability = {}
local spellSlotMap

function Eval.invalidateActionBars()
    spellSlotMap = nil
    for slot in pairs(slotUsability) do
        slotUsability[slot] = nil
    end
end

local function rebuildSpellSlotMap()
    spellSlotMap = {}
    if not GetActionInfo then
        return
    end
    for slot = 1, ACTION_SLOT_MAX do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" then
            id = tonumber(id)
            if id and id > 0 and not spellSlotMap[id] then
                spellSlotMap[id] = slot
            end
        end
    end
end

--- ACTION_USABLE_CHANGED payload: array of {slot, usable, noMana}. The action
--- bar keeps reporting usability when C_Spell.IsSpellUsable turns secret.
function Eval.onActionUsableChanged(changes)
    if type(changes) ~= "table" then
        return
    end
    for _, change in ipairs(changes) do
        local slot = type(change) == "table" and tonumber(change.slot) or nil
        if slot then
            local usable = Secret.plainBool(change.usable)
            if usable == nil then
                -- An all-unknown entry would mask the live read for this slot
                -- until the next bar event; drop it and let the API answer.
                slotUsability[slot] = nil
            else
                local entry = slotUsability[slot]
                if entry then
                    entry.usable = usable
                    entry.noPower = Secret.plainBool(change.noMana)
                else
                    slotUsability[slot] = {
                        usable = usable,
                        noPower = Secret.plainBool(change.noMana),
                    }
                end
            end
        end
    end
end

local function getActionBarUsability(spellId, displayId)
    if not spellSlotMap then
        rebuildSpellSlotMap()
    end
    local slot = spellSlotMap[spellId] or (displayId and spellSlotMap[displayId])
    if not slot then
        return nil, nil
    end
    local cached = slotUsability[slot]
    if cached then
        return cached.usable, cached.noPower
    end
    if not (C_ActionBar and C_ActionBar.IsUsableAction) then
        return nil, nil
    end
    local ok, usable, noPower = pcall(C_ActionBar.IsUsableAction, slot)
    if not ok then
        return nil, nil
    end
    usable = Secret.plainBool(usable)
    noPower = Secret.plainBool(noPower)
    if usable ~= nil then
        -- Seed the cache so the next tick is a table lookup; ACTION_USABLE_CHANGED
        -- keeps it current and any bar change wipes it.
        slotUsability[slot] = {usable = usable, noPower = noPower}
    end
    return usable, noPower
end

--- Does the player currently have this spell as a castable known form?
--- true / false / nil(unknown). Talent choice nodes matter: picking the
--- passive side of Ravager/Whirling Blade leaves the active id unlearned, while
--- IsSpellUsable can still report the active id as ready. Fail open when no API
--- answers so tests and older clients keep the previous behaviour.
local function isSpellLearnedActive(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return nil
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok and known == true then
            return true
        end
        if ok and known == false then
            return false
        end
    end
    -- Some override/transform forms only show up here.
    if IsSpellKnownOrOverridesKnown then
        local ok, known = pcall(IsSpellKnownOrOverridesKnown, spellId)
        if ok and known == true then
            return true
        end
        if ok and known == false and not IsPlayerSpell then
            return false
        end
    end
    return nil
end

--- usable(tri), notEnoughPower(tri). The game evaluates form, stance, stealth,
--- and many cast conditions for us. Talent *choice-node* ownership is handled
--- separately by isSpellLearnedActive -- do not rely on usable alone for that.
local function readSpellUsable(spellId, displayId)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, spellId)
        if ok then
            local plainUsable = Secret.plainBool(usable)
            local plainNoPower = Secret.plainBool(noPower)
            -- Both halves must be readable. "Cannot cast" with an unreadable
            -- reason is not enough to tell a form/stance block (a hard filter)
            -- apart from resource starvation (never a filter), so fall through
            -- to the action bar rather than guessing.
            if plainUsable == true or (plainUsable == false and plainNoPower ~= nil) then
                return plainUsable, plainNoPower
            end
        end
    end

    local barUsable, barNoPower = getActionBarUsability(spellId, displayId)
    if barUsable == true or (barUsable == false and barNoPower ~= nil) then
        return barUsable, barNoPower
    end

    if IsUsableSpell then
        local ok, usable, noPower = pcall(IsUsableSpell, spellId)
        if ok then
            local plainUsable = Secret.plainBool(usable)
            local plainNoPower = Secret.plainBool(noPower)
            if plainUsable == true or (plainUsable == false and plainNoPower ~= nil) then
                return plainUsable, plainNoPower
            end
        end
    end

    return nil, nil
end

--- Charge-spell verdict, or nil when this is not a charge spell at all.
--- true = no charge banked, false = at least one, nil = charge spell but the
--- count is not knowable right now.
local function chargeVerdict(spellId, maxCharges, recharging, currentCharges)
    if not (maxCharges and maxCharges > 1) then
        return nil, false
    end
    -- currentCharges is secret in combat but plain outside it; prefer the real
    -- number over our reconstruction whenever the client hands it over.
    if currentCharges ~= nil then
        return currentCharges <= 0, true
    end
    -- isActive is NeverSecret; "not recharging" can only mean full charges.
    if recharging == false then
        return false, true
    end
    local remaining = ShinkiliTrack and ShinkiliTrack.getChargesRemaining
        and ShinkiliTrack.getChargesRemaining(spellId)
    if remaining ~= nil then
        return remaining <= 0, true
    end
    return nil, true
end

local function computeCooldownBlocked(spellId)
    -- Most spells have no charges; skip the per-pass API call once the
    -- out-of-combat scan has proven that for this one. The scan can be wrong
    -- (spell data not loaded yet, recharge length unreadable), so the skip is
    -- re-checked below before it is ever allowed to BLOCK a spell.
    local skippedChargeRead = ShinkiliTrack and ShinkiliTrack.isChargeSpell
        and ShinkiliTrack.isChargeSpell(spellId) == false
    if not skippedChargeRead then
        local verdict, isChargeSpell = chargeVerdict(spellId, Secret.getSpellChargeInfo(spellId))
        if isChargeSpell then
            return verdict
        end
    end

    local blocked = Secret.isSpellOnRealCooldown(spellId)
    if blocked == true and skippedChargeRead then
        -- About to hard-filter the spell out of the pool on the strength of a
        -- scan that said "no charges". A charge spell with one banked has a
        -- recharge running and reads exactly like this, so pay for the API call
        -- here -- on the blocking path only, never on the ready path.
        local verdict, isChargeSpell = chargeVerdict(spellId, Secret.getSpellChargeInfo(spellId))
        if isChargeSpell then
            return verdict
        end
    end
    return blocked
end

--- true = no cast available right now, false = one is available, nil = unknown.
--- Memoised whole: castability and the `cd` gate both ask, and the charge branch
--- is a live API read plus a recharge advance.
local function isSpellCooldownBlocked(spellId)
    return memoTriState(cooldownCache, spellId, computeCooldownBlocked)
end

local function computeSpellCastability(spellId)
    local displayId = Eval.getDisplaySpellId(spellId)
    local usableDisplayId = displayId
    if displayId == spellId then
        usableDisplayId = nil
    end

    -- Ownership before usability. An unlearned (or passive-side) spell must not
    -- survive as "ready" just because IsSpellUsable is optimistic.
    local learned = isSpellLearnedActive(spellId)
    if learned ~= true and displayId and displayId ~= spellId then
        local learnedDisplay = isSpellLearnedActive(displayId)
        if learnedDisplay == true then
            learned = true
        elseif learned == false and learnedDisplay == false then
            learned = false
        elseif learned == nil then
            learned = learnedDisplay
        end
    end
    if learned == false then
        return CAST_UNUSABLE
    end

    local usable, notEnoughPower = readSpellUsable(spellId, usableDisplayId)
    local resourceShort = false
    if usable == false then
        if notEnoughPower == true then
            resourceShort = true
        elseif notEnoughPower == false then
            return CAST_UNUSABLE
        else
            -- Cannot cast, reason unreadable. Blocking here would hard-filter a
            -- merely resource-starved spell out of the pool.
            return CAST_UNKNOWN
        end
    end

    if Secret.isSpellOutOfRange(spellId) == true then
        return CAST_OUT_OF_RANGE
    end

    local cooldownBlocked = isSpellCooldownBlocked(spellId)
    if cooldownBlocked == true then
        return CAST_ON_COOLDOWN
    end

    if resourceShort then
        return CAST_NO_RESOURCE
    end
    if usable == nil or cooldownBlocked == nil then
        return CAST_UNKNOWN
    end
    return CAST_READY
end

function Eval.getCastability(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return CAST_UNKNOWN
    end
    local cached = castabilityCache[spellId]
    if cached then
        return cached
    end
    local verdict = computeSpellCastability(spellId)
    castabilityCache[spellId] = verdict
    return verdict
end

-- Confirmed-uncastable verdicts. Resource starvation is deliberately absent:
-- it refills every GCD, so excluding on it churns the colour each press. This is
-- the same policy as BLOCKING_CASTABILITY in ShinkiliLogic, which the pick
-- pipeline applies to the candidate pool; keep the two in step.
local CAST_BLOCKING = {
    [CAST_UNUSABLE] = true,
    [CAST_OUT_OF_RANGE] = true,
    [CAST_ON_COOLDOWN] = true,
}

--- Main-box policy: show it unless the game confirms it cannot be pressed.
function Eval.isPickable(spellId)
    if not spellId then
        return false
    end
    return CAST_BLOCKING[Eval.getCastability(spellId)] ~= true
end

--- Defense box availability. Stricter than the main box: a defensive you cannot
--- afford is not an answer, so `no_resource` hides it too. `unknown` still shows
--- -- when every probe is blind, a dark defense box is worse than an optimistic
--- one, and the old fail-closed behaviour blanked it for all of combat.
function Eval.isUsableForDisplay(spellId)
    if not spellId then
        return false
    end
    local verdict = Eval.getCastability(spellId)
    return verdict == CAST_READY or verdict == CAST_UNKNOWN
end

function Eval.isProcActive(spellId)
    if not spellId then
        return false
    end

    if IsSpellOverlayed then
        local ok, active = pcall(IsSpellOverlayed, spellId)
        if ok and Secret.plainBool(active) == true then
            return true
        end
    end

    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, active = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellId)
        if ok and Secret.plainBool(active) == true then
            return true
        end
    end

    return false
end

--- Hostile nameplate count. UnitIsDead is health-derived and health is secret in
--- 12.0, so every read goes through plainBool: an unreadable "dead" must not be
--- treated as alive OR as dead by accident of truthiness.
local function isLiveHostile(unit)
    if not unit or not UnitCanAttack then
        return false
    end
    local okAttack, attackable = pcall(UnitCanAttack, "player", unit)
    if not okAttack or Secret.plainBool(attackable) ~= true then
        return false
    end
    if UnitIsDead then
        local okDead, dead = pcall(UnitIsDead, unit)
        if okDead and Secret.plainBool(dead) == true then
            return false
        end
    end
    return true
end

local function computeHostileNameplates()
    local count = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                if isLiveHostile(plate and plate.namePlateUnitToken) then
                    count = count + 1
                end
            end
        end
    end
    if count == 0 and Secret.hasTarget() and isLiveHostile("target") then
        count = 1
    end
    return count
end

function Eval.countHostileNameplates()
    local cached = passScalars.nameplates
    if cached == nil then
        cached = computeHostileNameplates()
        passScalars.nameplates = cached
    end
    return cached
end

--------------------------------------------------------------------------------
-- SimC gate evaluation
--
-- Three-state on purpose. "unknown" is not "pass": a SimC step is only allowed
-- to outrank Blizzard's live pick when every one of its conditions was actually
-- read, so an unreadable input costs the step its promotion instead of turning
-- into a guess.
--------------------------------------------------------------------------------

local GATE_PASS = "pass"
local GATE_FAIL = "fail"
local GATE_UNKNOWN = "unknown"

local function compareNumbers(value, op, threshold)
    if op == ">=" then
        return value >= threshold
    elseif op == "<=" then
        return value <= threshold
    elseif op == ">" then
        return value > threshold
    elseif op == "<" then
        return value < threshold
    elseif op == "=" or op == "==" then
        return value == threshold
    elseif op == "!=" then
        return value ~= threshold
    end
    return nil
end

local function boolVerdict(value)
    if value == nil then
        return GATE_UNKNOWN
    end
    return value and GATE_PASS or GATE_FAIL
end

local function evaluateSimcGate(gate, entryId)
    if type(gate) ~= "table" or not gate.t then
        return GATE_UNKNOWN
    end
    local kind = gate.t

    if kind == "cd" then
        -- SimC's cooldown conditions almost always name a DIFFERENT spell
        -- ("cobra_shot if cooldown.bestial_wrath.remains>gcd"), and the upstream
        -- flattener drops that reference. Substituting the entry's own cooldown
        -- would be a vacuous pass: Stage C already requires `ready`, which means
        -- the entry's own cooldown is not running. Without the referenced id
        -- there is nothing to evaluate.
        if not gate.id then
            return GATE_UNKNOWN
        end
        -- Charge-aware, so a 2-charge spell with a charge banked does not report
        -- "on cooldown" here while castability says "ready".
        local onCooldown = isSpellCooldownBlocked(Eval.getDisplaySpellId(gate.id))
        if onCooldown == nil then
            return GATE_UNKNOWN
        end
        if gate.neg then
            return onCooldown and GATE_PASS or GATE_FAIL
        end
        return onCooldown and GATE_FAIL or GATE_PASS
    end

    if kind == "buff" then
        if not gate.id then
            return GATE_UNKNOWN
        end
        -- No overlay fallback here on purpose. IsSpellOverlayed answers "is this
        -- spell highlighted", not "is buff X up", so using it to resolve an
        -- unreadable aura would promote a SimC entry off a guess -- exactly the
        -- thing the tri-state contract exists to prevent.
        local active = memoTriState(buffCache, gate.id, Secret.isBuffActive)
        if active == nil then
            return GATE_UNKNOWN
        end
        if gate.neg then
            if active == false and not Secret.hasObservedAura(gate.id) then
                -- "Absent" turns a negated gate into a PASS, so it has to be
                -- real absence. The upstream flattener resolves buff tokens
                -- through a castable-spell index, so an aura whose id differs
                -- from its cast id (Death and Decay casts 43265, buffs 188290)
                -- would read absent forever and hand out a free promotion.
                return GATE_UNKNOWN
            end
            return active and GATE_FAIL or GATE_PASS
        end
        return active and GATE_PASS or GATE_FAIL
    end

    if kind == "dot" then
        -- Polarity matters and the upstream flattener discards it: SimC's
        -- `dot.x.ticking` (the DoT must be UP) and `!dot.x.ticking` (it must be
        -- MISSING) both arrive as a bare {t="dot",id}. Guessing one reading
        -- inverts the other, so an unmarked gate is not evaluable.
        if gate.neg == nil then
            return GATE_UNKNOWN
        end
        local dotId = gate.id or entryId
        local active = memoTriState(dotCache, dotId, Eval.isDotActive)
        if active == nil then
            return GATE_UNKNOWN
        end
        -- neg = the DoT must be absent; otherwise it must be present.
        if gate.neg then
            return active and GATE_FAIL or GATE_PASS
        end
        return active and GATE_PASS or GATE_FAIL
    end

    if kind == "execute" then
        -- The upstream flattener keeps neither the comparison nor the threshold,
        -- and most of these lines are actually `target.time_to_die>N` or
        -- `target.health.pct>N` -- i.e. "NOT in execute range". Reading them as
        -- "in execute range" inverts them, so without an operator there is
        -- nothing to evaluate.
        if not (gate.op and gate.n) then
            return GATE_UNKNOWN
        end
        local fraction = passScalars.targetHealth
        if fraction == nil then
            fraction = Secret.getTargetHealthFraction()
            passScalars.targetHealth = fraction or false
        elseif fraction == false then
            fraction = nil
        end
        if fraction == nil then
            return GATE_UNKNOWN
        end
        return boolVerdict(compareNumbers(fraction * 100, gate.op, gate.n))
    end

    if kind == "resource" then
        if not (gate.res and gate.op and gate.n) then
            return GATE_UNKNOWN
        end
        local count = Secret.getResourceCount(gate.res)
        if count == nil then
            return GATE_UNKNOWN
        end
        return boolVerdict(compareNumbers(count, gate.op, gate.n))
    end

    if kind == "targets" then
        if not (gate.op and gate.n) then
            return GATE_UNKNOWN
        end
        return boolVerdict(compareNumbers(Eval.countHostileNameplates(), gate.op, gate.n))
    end

    return GATE_UNKNOWN
end

--- Is this spell's DoT live on the current target? Delegates to the tracker;
--- unknown when the tracker is absent or has not observed it.
function Eval.isDotActive(spellId)
    if not (ShinkiliTrack and type(ShinkiliTrack.isDotActiveOnTarget) == "function") then
        return nil
    end
    return ShinkiliTrack.isDotActiveOnTarget(spellId)
end

--- Per-gate breakdown for /sk why. Not on the hot path.
function Eval.describeEntry(entry)
    local details = {}
    if type(entry) ~= "table" then
        return details
    end
    if entry.delegated == true then
        details[#details + 1] = {kind = "delegated", verdict = GATE_UNKNOWN}
    end
    local entryId = Eval.getDisplaySpellId(entry.id)
    local gates = entry.gates
    if type(gates) == "table" and #gates > 0 then
        for _, gate in ipairs(gates) do
            details[#details + 1] = {
                kind = type(gate) == "table" and tostring(gate.t) or "?",
                verdict = evaluateSimcGate(gate, entryId),
            }
        end
    elseif entry.delegated ~= true then
        -- Gateless entries are judged by the self-redundancy veto, which would
        -- otherwise print as "fail" with no reason attached.
        -- `x ~= true` would fold "unreadable" into "confirmed absent", and the
        -- whole point of this report is showing which inputs could not be read.
        local function selfVerdict(value)
            if value == nil then
                return GATE_UNKNOWN
            end
            return value == true and GATE_FAIL or GATE_PASS
        end
        details[#details + 1] = {
            kind = "self-buff",
            verdict = selfVerdict(memoTriState(buffCache, entryId, Secret.isBuffActive)),
        }
        details[#details + 1] = {
            kind = "self-dot",
            verdict = selfVerdict(memoTriState(dotCache, entryId, Eval.isDotActive)),
        }
    end
    return details
end

--- pass only when every gate is provably satisfied, fail on the first proven
--- violation, unknown when anything could not be read.
function Eval.evaluateEntry(entry)
    if type(entry) ~= "table" then
        return GATE_UNKNOWN
    end
    -- `delegated` means SimC's real condition needs a value the client cannot
    -- read at all, so the ordering is unverifiable no matter what the gates say.
    if entry.delegated == true then
        return GATE_UNKNOWN
    end

    -- Judge the same id the pipeline checks castability on, or an override spell
    -- would have its gates and its castability answered for two different spells.
    local entryId = Eval.getDisplaySpellId(entry.id)
    local gates = entry.gates
    if type(gates) ~= "table" or #gates == 0 then
        -- An unconditional APL line: SimC really does cast this whenever it is
        -- available, so it stays promotable. The one thing we can still check
        -- for free is self-redundancy -- re-applying an effect that is already
        -- up is never what the APL meant.
        if memoTriState(buffCache, entryId, Secret.isBuffActive) == true then
            return GATE_FAIL
        end
        if memoTriState(dotCache, entryId, Eval.isDotActive) == true then
            return GATE_FAIL
        end
        return GATE_PASS
    end

    local verdict = GATE_PASS
    for _, gate in ipairs(gates) do
        local result = evaluateSimcGate(gate, entryId)
        if result == GATE_FAIL then
            return GATE_FAIL
        end
        if result == GATE_UNKNOWN then
            verdict = GATE_UNKNOWN
        end
    end
    return verdict
end

return Eval
