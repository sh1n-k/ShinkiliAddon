-- Shinkili secret-value layer (WoW 12.0 "Midnight").
--
-- 12.0 turns cooldown remaining, aura duration/stacks, primary resources and
-- player health into SECRET VALUES: issecretvalue(v) is true and the value must
-- not be read, compared or branched on. A secret value KEEPS ITS LUA TYPE, so
-- `type(v) ~= "boolean"` never detects one -- issecretvalue is the only probe
-- that works.
--
-- Every accessor here is TRI-STATE: true / false / nil, where nil means
-- "unknown -- the caller must fail open". The pick pipeline reads nil as
-- "SimC is not allowed to override Blizzard's Assisted Combat pick", which is
-- what keeps the recommendation from ever being worse than plain AC.

ShinkiliSecret = ShinkiliSecret or {}
local Secret = ShinkiliSecret

local pcall = pcall
local type = type
local tonumber = tonumber

local NEVER_SECRET_LEVEL = 0 -- Enum.SecrecyLevel.NeverSecret

--------------------------------------------------------------------------------
-- Secret primitives
--------------------------------------------------------------------------------

--- True when the value is a 12.0 secret. Never branch on a value before this.
function Secret.isSecret(value)
    if issecretvalue == nil then
        return false
    end
    local ok, verdict = pcall(issecretvalue, value)
    return ok and verdict == true
end

--- Coerce a possibly-secret / possibly-legacy (1/nil) value into true/false,
--- or nil when it cannot be read. Always use this before an `if`.
function Secret.plainBool(value)
    if value == nil then
        return nil
    end
    if Secret.isSecret(value) then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    -- Legacy APIs answer 1/0 (GetSpellCooldown's `enabled`) or 1/nil. 0 is
    -- truthy in Lua, so it has to be normalised explicitly.
    if type(value) == "number" then
        return value ~= 0
    end
    return value and true or false
end

--- Readable number, or nil when absent/secret.
function Secret.plainNumber(value)
    if value == nil or Secret.isSecret(value) then
        return nil
    end
    if type(value) ~= "number" then
        return nil
    end
    return value
end

--------------------------------------------------------------------------------
-- Live secrecy gates
--
-- C_Secrets predicates are plain booleans that flip at combat edges. They are a
-- better "is this readable right now" signal than InCombatLockdown because they
-- stay correct if Blizzard changes which contexts are restricted.
--------------------------------------------------------------------------------

local function apiSecretFlag(reader)
    if reader then
        local ok, verdict = pcall(reader)
        if ok then
            local plain = Secret.plainBool(verdict)
            if plain ~= nil then
                return plain
            end
        end
    end
    if InCombatLockdown then
        local ok, inCombat = pcall(InCombatLockdown)
        if ok then
            return Secret.plainBool(inCombat) == true
        end
    end
    return false
end

function Secret.areAurasSecret()
    return apiSecretFlag(C_Secrets and C_Secrets.ShouldAurasBeSecret)
end

function Secret.areCooldownsSecret()
    return apiSecretFlag(C_Secrets and C_Secrets.ShouldCooldownsBeSecret)
end

--------------------------------------------------------------------------------
-- DurationObject probe
--
-- A DurationObject carries a SECRET remaining time, but when it is fed to a
-- native Cooldown widget the engine drives that widget's shown state from it,
-- and Cooldown:IsShown() is a plain widget boolean. So "is it running?" is
-- recoverable without ever touching the secret number. The remaining TIME stays
-- unreadable -- anything needing a number (dot.remains < N) is out of reach.
--
-- This leans on engine behaviour that is almost certainly not an intended public
-- contract. `/sk why` reports probe health so a patch that closes it is visible,
-- and every caller has a fallback ladder ending in "unknown -> defer to AC".
--------------------------------------------------------------------------------

local scratchCooldown
local scratchResolved = false

local function getScratchCooldown()
    if scratchResolved then
        return scratchCooldown
    end
    scratchResolved = true
    if not CreateFrame then
        return nil
    end
    local okHolder, holder = pcall(CreateFrame, "Frame", nil, UIParent)
    if not okHolder or not holder then
        return nil
    end
    holder:Hide() -- parent hidden: the probe frame never renders
    local okCd, cd = pcall(CreateFrame, "Cooldown", nil, holder, "CooldownFrameTemplate")
    if not okCd or not cd or not cd.SetCooldownFromDurationObject then
        return nil
    end
    -- A fresh Cooldown starts shown; the very first probe would otherwise read
    -- that leftover state instead of the duration it was just handed.
    pcall(cd.Hide, cd)
    scratchCooldown = cd
    return cd
end

--- true = duration running, false = not running, nil = probe unavailable.
local function durationObjectActive(durationObject)
    local cd = getScratchCooldown()
    if not cd then
        return nil -- no probe: we know nothing, including about a nil duration
    end
    if durationObject == nil then
        return false -- engine reports no running duration at all
    end
    if not pcall(cd.SetCooldownFromDurationObject, cd, durationObject) then
        return nil
    end
    local okShown, shown = pcall(cd.IsShown, cd)
    pcall(cd.SetCooldown, cd, 0, 0) -- reset so the next probe reads fresh
    if not okShown then
        return nil
    end
    return Secret.plainBool(shown)
end

--- Is the probe usable at all on this client? Diagnostics only.
function Secret.isProbeAvailable()
    return getScratchCooldown() ~= nil
end

--------------------------------------------------------------------------------
-- Cooldown / charges
--------------------------------------------------------------------------------

--- Optional hook installed by ShinkiliTrack: (spellId) -> true/false/nil.
--- Consulted only after the engine-truth ladder comes up unknown.
Secret.localCooldownProvider = nil

--- True while the spell is on a REAL cooldown (GCD excluded).
--- Ladder: DurationObject probe -> NeverSecret cooldown booleans -> local
--- tracker -> unknown.
function Secret.isSpellOnRealCooldown(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return nil
    end

    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, durationObject = pcall(C_Spell.GetSpellCooldownDuration, spellId, true)
        if ok then
            local active = durationObjectActive(durationObject)
            if active ~= nil then
                return active
            end
        end
    end

    local function askLocalTracker()
        if type(Secret.localCooldownProvider) ~= "function" then
            return nil
        end
        local ok, verdict = pcall(Secret.localCooldownProvider, spellId)
        if ok then
            return verdict
        end
        return nil
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellId)
        if ok and type(info) == "table" then
            -- Both fields are NeverSecret. isActive is asked FIRST because it is
            -- the unambiguous one: nothing running means no real cooldown, no
            -- matter what isOnGCD says.
            local active = Secret.plainBool(info.isActive)
            if active == false then
                return false
            end

            -- Something is running. isOnGCD says what:
            --   false -> a real cooldown (definitive for spells Blizzard flags)
            --   true  -> the GCD, but a real cooldown may tick underneath it, so
            --            only the local tracker can tell; unknown if it has not
            --            observed this spell. Claiming "ready" here would let
            --            SimC promote a spell that is on a 90s cooldown.
            --   nil   -> ambiguous; a readable isActive==true settles it.
            local onGcd = Secret.plainBool(info.isOnGCD)
            if onGcd == false then
                return true
            end
            if onGcd == true then
                return askLocalTracker()
            end
            if active == true then
                return true
            end
        end
    end

    return askLocalTracker()
end

--- maxCharges|nil, recharging(true/false/nil), currentCharges|nil.
--- maxCharges and isActive are NeverSecret in combat; currentCharges is secret,
--- which is exactly why ShinkiliTrack keeps its own count.
function Secret.getSpellChargeInfo(spellId)
    spellId = tonumber(spellId)
    if not spellId or not (C_Spell and C_Spell.GetSpellCharges) then
        return nil, nil, nil
    end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellId)
    if not ok or type(info) ~= "table" then
        return nil, nil, nil
    end
    return Secret.plainNumber(info.maxCharges),
        Secret.plainBool(info.isActive),
        Secret.plainNumber(info.currentCharges)
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

-- Ids we have actually seen as a player aura. The upstream flattener resolves a
-- SimC buff TOKEN through a castable-spell index, so a buff whose aura id
-- differs from its cast id (Death and Decay casts 43265, buffs 188290) arrives
-- with the wrong id and would read as "permanently absent".
local observedAuraIds = {}

--- True once this id has ever resolved to a real player aura. Callers that turn
--- "absent" into a PASS must check this first.
function Secret.hasObservedAura(spellId)
    spellId = tonumber(spellId)
    return spellId ~= nil and observedAuraIds[spellId] == true
end

--- Secrecy level of a spell's aura: 0 = never secret, >0 = may be hidden in
--- combat, nil = the engine will not say.
local function getAuraSecrecy(spellId)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then
        return nil
    end
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, spellId)
    if not ok then
        return nil
    end
    return Secret.plainNumber(level)
end

--- True while the player's own buff `spellId` is up. false = confirmed absent,
--- nil = unreadable.
---
--- The by-spell lookups (GetPlayerAuraBySpellID and friends) are documented
--- `RequiresNonSecretAura`, so for a ContextuallySecret aura they return nil
--- WHILE THE BUFF IS UP. A missing record is therefore only evidence of absence
--- when the engine tells us this particular aura is never secret.
function Secret.isBuffActive(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return nil
    end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if not ok then
        return nil
    end

    if aura == nil then
        if getAuraSecrecy(spellId) == NEVER_SECRET_LEVEL then
            return false -- the lookup works for this aura, so it really is absent
        end
        if not Secret.areAurasSecret() then
            return false -- nothing is hidden right now, so absence is real
        end
        return nil -- the aura may simply be unreadable
    end

    if type(aura) ~= "table" then
        return nil
    end
    observedAuraIds[spellId] = true
    -- A record exists, so the buff is on us. The duration probe only downgrades
    -- that when the engine hands us a duration AND says it stopped running; an
    -- aura with no duration object at all is permanent, not absent.
    local instanceId = Secret.plainNumber(aura.auraInstanceID)
    if instanceId and C_UnitAuras.GetAuraDuration then
        local okDur, durationObject = pcall(C_UnitAuras.GetAuraDuration, "player", instanceId)
        if okDur and durationObject ~= nil and durationObjectActive(durationObject) == false then
            return false
        end
    end
    return true
end

--- True when the aura instance on `unit` is a harmful aura the player applied.
--- Engine-side evaluation from the NeverSecret instance id, so it stays readable
--- in combat. nil = cannot tell.
function Secret.isOwnDebuffInstance(unit, instanceId)
    if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then
        return nil
    end
    if not unit or not instanceId then
        return nil
    end
    local ok, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instanceId, "HARMFUL|PLAYER")
    if not ok then
        return nil
    end
    local plain = Secret.plainBool(filteredOut)
    if plain == nil then
        return nil
    end
    return plain == false
end

--------------------------------------------------------------------------------
-- Resources
--
-- Secondary resources (combo points, runes, holy power, chi, soul shards,
-- arcane charges, essence) are NOT secret in 12.0; primary ones (mana, energy,
-- rage, focus) are. Rather than hardcode that split we ask the engine per power
-- type, so the readable set widens automatically if Blizzard relaxes a flag.
--------------------------------------------------------------------------------

-- SimC resource token -> Enum.PowerType value.
local RESOURCE_POWER_TYPE = {
    mana = 0,
    rage = 1,
    focus = 2,
    energy = 3,
    combo_points = 4,
    rune = 5,
    runic_power = 6,
    soul_shard = 7,
    astral_power = 8,
    holy_power = 9,
    maelstrom = 11,
    chi = 12,
    insanity = 13,
    arcane_charges = 16,
    fury = 17,
    pain = 18,
    essence = 19,
}

-- SimC counts soul shards fractionally and the client reports them scaled. The
-- scale is NOT assumed: UnitPowerDisplayMod supplies it, and without that answer
-- the resource reads unknown rather than being off by a factor of ten.
local FRACTIONAL_RESOURCE = {
    soul_shard = true,
}

--- Current count for a SimC resource token, or nil when it cannot be trusted.
--- "unknown" always beats a confident zero, which would permanently sink every
--- `>=`-gated spender. Only the count is returned: the scaling relationship
--- between UnitPower and UnitPowerMax for fractional resources is unverified,
--- and no gate needs the maximum.
function Secret.getResourceCount(token)
    local powerType = RESOURCE_POWER_TYPE[token]
    if powerType == nil or not UnitPower or not UnitPowerMax then
        return nil
    end

    if C_Secrets and C_Secrets.GetPowerTypeSecrecy then
        local okLevel, level = pcall(C_Secrets.GetPowerTypeSecrecy, powerType)
        if not okLevel then
            return nil
        end
        local plainLevel = Secret.plainNumber(level)
        if plainLevel ~= NEVER_SECRET_LEVEL then
            return nil
        end
    end

    local fractional = FRACTIONAL_RESOURCE[token] or nil
    local scale = 1
    if fractional then
        if not UnitPowerDisplayMod then
            return nil
        end
        local okMod, mod = pcall(UnitPowerDisplayMod, powerType)
        mod = okMod and Secret.plainNumber(mod) or nil
        if not mod or mod <= 0 then
            return nil
        end
        scale = mod
    end

    local okCur, current = pcall(UnitPower, "player", powerType, fractional)
    local okMax, maximum = pcall(UnitPowerMax, "player", powerType)
    if not okCur or not okMax then
        return nil
    end

    current = Secret.plainNumber(current)
    maximum = Secret.plainNumber(maximum)
    -- A zero maximum means the character does not have this resource at all;
    -- reporting 0 would permanently satisfy every `<`-gated line.
    if current == nil or maximum == nil or maximum <= 0 then
        return nil
    end
    if scale ~= 1 then
        current = current / scale
    end
    return current
end

--------------------------------------------------------------------------------
-- Target state
--------------------------------------------------------------------------------

-- Reset by ShinkiliEval at the top of every evaluation pass. "Does the player
-- have a target" was being asked once per spell.
local passTargetExists

function Secret.resetPassCache()
    passTargetExists = nil
end

local function hasTarget()
    if passTargetExists ~= nil then
        return passTargetExists
    end
    local exists = false
    if UnitExists then
        local ok, value = pcall(UnitExists, "target")
        exists = ok and Secret.plainBool(value) == true
    end
    passTargetExists = exists
    return exists
end

Secret.hasTarget = hasTarget

--- Target health fraction in 0..1, or nil when unreadable. Used by SimC
--- `execute` gates; an unreadable value makes the gate unknown, never false.
function Secret.getTargetHealthFraction()
    if not UnitHealth or not UnitHealthMax or not hasTarget() then
        return nil
    end
    local okCur, current = pcall(UnitHealth, "target")
    local okMax, maximum = pcall(UnitHealthMax, "target")
    if not okCur or not okMax then
        return nil
    end
    current = Secret.plainNumber(current)
    maximum = Secret.plainNumber(maximum)
    if current == nil or maximum == nil or maximum <= 0 then
        return nil
    end
    return current / maximum
end

--- Confirmed out of range on the current target. The boolean from
--- IsSpellInRange is never secret (only the yardage is). nil = no range
--- requirement, no valid target, or unreadable -- all fail open.
function Secret.isSpellOutOfRange(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end
    if not (C_Spell and C_Spell.IsSpellInRange) or not hasTarget() then
        return nil
    end
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellId, "target")
    if not ok then
        return nil
    end
    local plain = Secret.plainBool(inRange)
    if plain == nil then
        return nil
    end
    return plain == false
end

--------------------------------------------------------------------------------
-- Diagnostics (/sk why)
--------------------------------------------------------------------------------

function Secret.getDiagnostics()
    return {
        hasIsSecretValue = issecretvalue ~= nil,
        hasSecretsApi = (C_Secrets ~= nil),
        probeAvailable = Secret.isProbeAvailable(),
        aurasSecret = Secret.areAurasSecret(),
        cooldownsSecret = Secret.areCooldownsSecret(),
    }
end

return Secret
