-- Shinkili local state tracker.
--
-- 12.0 hides cooldown remaining, charge counts and target-debuff identity behind
-- secret values. Three NeverSecret signals let us rebuild the parts the pick
-- pipeline needs:
--   1. Our own casts (UNIT_SPELLCAST_SUCCEEDED spellID is readable).
--   2. Base cooldown / recharge lengths, scanned OUT of combat and cached.
--   3. The Assisted Combat pick itself -- Blizzard never recommends an
--      uncastable spell, so the pick expires any stale entry we are holding
--      (proc-driven resets and charge refunds fire no cast event).
--
-- Everything answers tri-state: true / false / nil-unknown. Guessing "ready"
-- would let SimC override Blizzard on a spell that is actually down, so the
-- tracker returns nil whenever it has not genuinely observed the state.

ShinkiliTrack = ShinkiliTrack or {}
local Track = ShinkiliTrack
local Secret = ShinkiliSecret

local pcall = pcall
local type = type
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local tremove = table.remove

-- Below this a "cooldown" is just the GCD and not worth tracking.
local MIN_TRACKABLE_CD = 3.0
-- The AC pick lags a just-completed cast, so an entry younger than this is the
-- cast we just observed rather than a stale one.
local RECOMMEND_GRACE = 1.5
-- How long after casting a DoT we assume it is still up without confirmation.
local DOT_FALLBACK_WINDOW = 30.0
-- Max gap between our cast and the debuff appearing in addedAuras.
local DOT_BRIDGE_WINDOW = 2.0

local baseCooldown = {}   -- spellId -> seconds (0 means "no real cooldown")
local chargeSpec = {}     -- spellId -> {maxCharges, rechargeSeconds}
local activeCooldown = {} -- spellId -> {startTime, endTime}
local chargeState = {}    -- spellId -> {current, maxCharges, rechargeEnd, rechargeDuration}

local dotApplied = {}     -- spellId -> {expiry, instances = {}, hadInstance}
local dotInstances = {}   -- auraInstanceID -> spellId
local dotPendingCasts = {}
-- Only ids the active spec actually gates on. Queueing every cast would let a
-- filler consume the aura slot the real DoT was waiting for, and the FIFO bridge
-- would then bind the instance to the wrong spell.
local dotWatch = {}
-- Distinct from "the list is empty": before the spec is known we must not guess
-- which casts are DoTs, and a spec with no dot gates must track none of them.
local dotWatchConfigured = false

--- Injectable for tests; defaults to the game clock.
Track.timeSource = nil

local function now()
    if Track.timeSource then
        return Track.timeSource()
    end
    if GetTime then
        return GetTime()
    end
    return 0
end

--------------------------------------------------------------------------------
-- Static spell data (scanned out of combat)
--------------------------------------------------------------------------------

--- Base cooldown in seconds, or nil when it has not been readable yet.
--- GetSpellBaseCooldown is secret in combat, so an unreadable value is never
--- cached -- the next out-of-combat pass fills it in.
local function scanBaseCooldown(spellId)
    if baseCooldown[spellId] ~= nil then
        return baseCooldown[spellId]
    end
    if Secret.areCooldownsSecret() then
        return nil
    end
    if not GetSpellBaseCooldown then
        return nil
    end
    local ok, milliseconds = pcall(GetSpellBaseCooldown, spellId)
    if not ok then
        return nil
    end
    milliseconds = Secret.plainNumber(milliseconds)
    if milliseconds == nil then
        return nil
    end

    local seconds = milliseconds > 0 and (milliseconds / 1000) or 0

    -- Charge spells report a zero base cooldown; their real gate is the
    -- per-charge recharge time.
    local maxCharges, _, _ = Secret.getSpellChargeInfo(spellId)
    if maxCharges and maxCharges > 1 then
        local recharge = seconds
        if C_Spell and C_Spell.GetSpellCharges then
            local okCharges, info = pcall(C_Spell.GetSpellCharges, spellId)
            if okCharges and type(info) == "table" then
                local duration = Secret.plainNumber(info.cooldownDuration)
                if duration and duration > 0 then
                    recharge = duration
                end
            end
        end
        if recharge > 0 then
            chargeSpec[spellId] = {maxCharges = maxCharges, rechargeSeconds = recharge}
        end
    end

    baseCooldown[spellId] = seconds
    return seconds
end

--- Pre-cache static data for a list of spell ids. Out of combat only.
function Track.scanSpells(spellIds)
    if type(spellIds) ~= "table" or Secret.areCooldownsSecret() then
        return
    end
    for _, spellId in ipairs(spellIds) do
        spellId = tonumber(spellId)
        if spellId and spellId > 0 then
            scanBaseCooldown(spellId)
        end
    end
end

local function clearStaticCaches()
    for key in pairs(baseCooldown) do
        baseCooldown[key] = nil
    end
    for key in pairs(chargeSpec) do
        chargeSpec[key] = nil
    end
end

--------------------------------------------------------------------------------
-- Charges
--------------------------------------------------------------------------------

local function advanceRecharge(state, current)
    -- A nil count means we never proved how many charges were banked; recharge
    -- arithmetic on an unknown is how a spent spell starts reading as ready.
    if state.current == nil or state.current >= state.maxCharges or state.rechargeDuration <= 0 then
        return
    end
    while state.current < state.maxCharges and state.rechargeEnd > 0 and current >= state.rechargeEnd do
        state.current = state.current + 1
        if state.current >= state.maxCharges then
            state.rechargeEnd = 0
        else
            state.rechargeEnd = state.rechargeEnd + state.rechargeDuration
        end
    end
end

--- true / false once the spell has been scanned out of combat, nil before that.
--- Lets the evaluator skip a per-pass GetSpellCharges call for the vast
--- majority of spells, which have no charges at all.
function Track.isChargeSpell(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end
    if chargeSpec[spellId] then
        return true
    end
    if baseCooldown[spellId] ~= nil then
        return false
    end
    return nil
end

--- Charges banked right now, or nil when the spell is not charge-tracked.
function Track.getChargesRemaining(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end
    local state = chargeState[spellId]
    if not state then
        return nil
    end
    advanceRecharge(state, now())
    return state.current
end

--------------------------------------------------------------------------------
-- Cooldowns
--------------------------------------------------------------------------------

--- true = we observed a cast and its cooldown is still running.
--- false = the spell provably has no real cooldown.
--- nil  = unknown; the caller must fail open to Blizzard's pick.
function Track.isOnLocalCooldown(spellId)
    spellId = tonumber(spellId)
    if not spellId then
        return nil
    end

    local entry = activeCooldown[spellId]
    if entry then
        if now() < entry.endTime then
            return true
        end
        activeCooldown[spellId] = nil
        return false
    end

    -- A scanned zero base cooldown is a real answer: this spell can never be
    -- "on cooldown", so it is always available from the cooldown side.
    local base = baseCooldown[spellId]
    if base ~= nil and base < MIN_TRACKABLE_CD and not chargeSpec[spellId] then
        return false
    end

    return nil
end

--- Record a cast. Called from UNIT_SPELLCAST_SUCCEEDED (player).
function Track.noteSpellCast(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return
    end
    local current = now()

    local spec = chargeSpec[spellId]
    if spec then
        local state = chargeState[spellId]
        if not state then
            -- Seed from the real count when the client will give it (plain out
            -- of combat). Assuming "full" instead would be an upward-only lie:
            -- every later correction raises the count, none lowers it, so a
            -- spell reset mid-combat at 0 charges would read ready forever.
            local _, _, readableCharges = Secret.getSpellChargeInfo(spellId)
            state = {
                current = readableCharges,
                maxCharges = spec.maxCharges,
                rechargeEnd = 0,
                rechargeDuration = spec.rechargeSeconds,
            }
            chargeState[spellId] = state
        end
        advanceRecharge(state, current)
        if state.current ~= nil and state.current > 0 then
            state.current = state.current - 1
        end
        if state.rechargeEnd <= 0 or state.rechargeEnd < current then
            state.rechargeEnd = current + state.rechargeDuration
        end
        return
    end

    local base = baseCooldown[spellId]
    if base and base >= MIN_TRACKABLE_CD then
        activeCooldown[spellId] = {startTime = current, endTime = current + base}
    end
end

-- The engine cross-check is a widget round-trip per tracked spell, and
-- SPELL_UPDATE_COOLDOWN fires on every GCD. Expiry sweeps stay free; the probe
-- runs at most this often.
local COOLDOWN_PROBE_INTERVAL = 0.2
local lastCooldownProbe = -1

--- SPELL_UPDATE_COOLDOWN sweep: drop entries the engine says are finished.
function Track.refreshCooldowns()
    local current = now()
    local probe = (current - lastCooldownProbe) >= COOLDOWN_PROBE_INTERVAL
    if probe then
        lastCooldownProbe = current
    end
    for spellId, entry in pairs(activeCooldown) do
        if current >= entry.endTime then
            activeCooldown[spellId] = nil
        elseif probe then
            -- Engine truth beats our timer: haste and CDR shorten the real one.
            if Secret.isSpellOnRealCooldown(spellId) == false then
                activeCooldown[spellId] = nil
            end
        end
    end
end

--- SPELL_UPDATE_CHARGES sweep. chargeInfo.isActive is NeverSecret; false means
--- no recharge is running, which is only possible at full charges.
function Track.refreshCharges()
    local current = now()
    for spellId, state in pairs(chargeState) do
        advanceRecharge(state, current)
        if state.current == nil or state.current < state.maxCharges then
            local _, recharging, readableCharges = Secret.getSpellChargeInfo(spellId)
            if readableCharges ~= nil then
                state.current = readableCharges
            elseif recharging == false then
                -- NeverSecret: no recharge running can only mean full charges.
                state.current = state.maxCharges
                state.rechargeEnd = 0
            end
        end
    end
end

--- Blizzard's Assisted Combat pick is a readiness oracle: it never recommends
--- an uncastable spell, so a stale entry it contradicts must go.
function Track.noteSpellRecommended(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return
    end
    local current = now()

    local entry = activeCooldown[spellId]
    if entry and (current - entry.startTime) > RECOMMEND_GRACE then
        activeCooldown[spellId] = nil
    end

    local state = chargeState[spellId]
    if state then
        advanceRecharge(state, current)
        if state.current ~= nil and state.current < 1 then
            local rechargeStart = state.rechargeEnd - state.rechargeDuration
            if state.rechargeEnd <= 0 or (current - rechargeStart) > RECOMMEND_GRACE then
                state.current = 1
            end
        end
    end
end

--- Combat exit: re-read the real cooldowns (plain out of combat) instead of
--- wiping, so cooldowns still ticking survive into the next pull.
function Track.resyncCooldowns()
    for spellId in pairs(activeCooldown) do
        if Secret.isSpellOnRealCooldown(spellId) == false then
            activeCooldown[spellId] = nil
        end
    end
    Track.refreshCharges()
end

--------------------------------------------------------------------------------
-- Target DoTs
--
-- Debuff identity is secret in combat, so a DoT is reconstructed from our own
-- casts plus the aura-instance bridge (auraInstanceID is NeverSecret and
-- IsAuraFilteredOutByInstanceID reports "harmful aura we cast" as a plain bool).
--------------------------------------------------------------------------------

local function dotEntry(spellId)
    local entry = dotApplied[spellId]
    if not entry then
        entry = {expiry = 0, instances = {}, hadInstance = false}
        dotApplied[spellId] = entry
    end
    return entry
end

--- Register the DoT ids the active spec gates on. Casts outside this set are
--- ignored by the bridge, which is what keeps a filler from stealing a DoT's
--- aura slot.
function Track.setDotWatchList(ids)
    for key in pairs(dotWatch) do
        dotWatch[key] = nil
    end
    dotWatchConfigured = type(ids) == "table"
    if not dotWatchConfigured then
        return
    end
    for _, id in ipairs(ids) do
        id = tonumber(id)
        if id and id > 0 then
            dotWatch[id] = true
        end
    end
end

--- Called on every player cast; ignored unless the spell is a watched DoT.
function Track.noteDotCast(spellId, alsoDisplayId)
    spellId = tonumber(spellId)
    if not spellId or not UnitExists then
        return
    end
    alsoDisplayId = tonumber(alsoDisplayId)
    -- Unconfigured means we do not know what a DoT is yet; tracking everything
    -- would make the gateless self-redundancy guard fail every spell we cast.
    if not dotWatchConfigured then
        return
    end
    if not dotWatch[spellId] and not (alsoDisplayId and dotWatch[alsoDisplayId]) then
        return
    end
    local okExists, exists = pcall(UnitExists, "target")
    if not okExists or Secret.plainBool(exists) ~= true then
        return
    end

    local current = now()
    local ids = {spellId}
    if alsoDisplayId and alsoDisplayId ~= spellId then
        ids[#ids + 1] = alsoDisplayId
    end
    for _, id in ipairs(ids) do
        local entry = dotEntry(id)
        entry.expiry = current + DOT_FALLBACK_WINDOW
        -- Clear the "was confirmed, then removed" latch only when nothing is
        -- live, which is the case it was blocking: a fresh application after the
        -- DoT fell off. Clearing it on a REFRESH would be wrong -- a refresh
        -- emits updatedAuraInstanceIDs, not addedAuras, so the latch would never
        -- be restored and the eventual removal would go unnoticed.
        if next(entry.instances) == nil then
            entry.hadInstance = false
        end
    end

    dotPendingCasts[#dotPendingCasts + 1] = {ids = ids, time = current}
    for i = #dotPendingCasts, 1, -1 do
        if current - dotPendingCasts[i].time > DOT_BRIDGE_WINDOW then
            tremove(dotPendingCasts, i)
        end
    end
end

--- UNIT_AURA on the target: bridge added debuffs to our casts, drop removed ones.
function Track.onTargetAuraUpdate(updateInfo)
    if type(updateInfo) ~= "table" then
        return
    end

    -- A full update carries neither addedAuras nor removedAuraInstanceIDs, so a
    -- removal it replaced would never be seen and a stale instance would pin the
    -- DoT to "live" for the rest of the fight.
    if Secret.plainBool(updateInfo.isFullUpdate) == true then
        Track.resetDots()
        return
    end

    if type(updateInfo.removedAuraInstanceIDs) == "table" then
        for _, rawInstanceId in ipairs(updateInfo.removedAuraInstanceIDs) do
            -- Normalised the same way as the add path, or a type mismatch would
            -- make removal a silent no-op and pin the DoT to "live".
            local instanceId = Secret.plainNumber(rawInstanceId)
            local ids = instanceId and dotInstances[instanceId]
            if ids then
                for _, id in ipairs(ids) do
                    local entry = dotApplied[id]
                    if entry then
                        entry.instances[instanceId] = nil
                    end
                end
                dotInstances[instanceId] = nil
            end
        end
    end

    if type(updateInfo.addedAuras) == "table" and #dotPendingCasts > 0 then
        local current = now()
        for i = #dotPendingCasts, 1, -1 do
            if current - dotPendingCasts[i].time > DOT_BRIDGE_WINDOW then
                tremove(dotPendingCasts, i)
            end
        end
        for _, aura in ipairs(updateInfo.addedAuras) do
            if #dotPendingCasts == 0 then
                break
            end
            local instanceId = type(aura) == "table" and Secret.plainNumber(aura.auraInstanceID) or nil
            if instanceId then
                -- Only harmful auras WE applied; nil (API missing) matches on
                -- timing alone rather than dropping the bridge entirely.
                local mine = Secret.isOwnDebuffInstance("target", instanceId)
                if mine ~= false then
                    local pending = tremove(dotPendingCasts, 1)
                    dotInstances[instanceId] = pending.ids
                    for _, id in ipairs(pending.ids) do
                        local entry = dotEntry(id)
                        entry.instances[instanceId] = true
                        entry.hadInstance = true
                    end
                end
            end
        end
    end
end

--- Number of harmful auras the player has on the target. The aura LIST and its
--- length stay plain in combat -- only the per-aura fields are secret -- so a
--- count of zero is a trustworthy "none of my DoTs are up".
local function countOwnDebuffsOnTarget()
    if not C_UnitAuras then
        return nil
    end
    if C_UnitAuras.GetUnitAuras then
        local ok, list = pcall(C_UnitAuras.GetUnitAuras, "target", "HARMFUL|PLAYER")
        if ok and type(list) == "table" then
            return #list
        end
    end
    -- No GetAuraDataByIndex fallback on purpose: that accessor is
    -- SecretWhenUnitAuraRestricted, so in combat it can stop early and report a
    -- confident zero for a target that is covered in our DoTs.
    return nil
end

--- true = the DoT is on the current target, false = confirmed absent,
--- nil = we have never observed it and cannot tell.
function Track.isDotActiveOnTarget(spellId)
    spellId = tonumber(spellId)
    if not spellId or not UnitExists then
        return nil
    end
    local okExists, exists = pcall(UnitExists, "target")
    if not okExists or Secret.plainBool(exists) ~= true then
        return nil
    end

    local entry = dotApplied[spellId]
    if entry then
        if next(entry.instances) ~= nil then
            return true
        end
        if entry.hadInstance then
            return false -- was confirmed, then removed (expiry, dispel, death)
        end
        if now() < entry.expiry then
            return true -- cast recently, bridge has not confirmed yet
        end
    end

    if countOwnDebuffsOnTarget() == 0 then
        return false
    end

    return nil
end

function Track.resetDots()
    for key in pairs(dotApplied) do
        dotApplied[key] = nil
    end
    for key in pairs(dotInstances) do
        dotInstances[key] = nil
    end
    for i = #dotPendingCasts, 1, -1 do
        tremove(dotPendingCasts, i)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Track.reset()
    lastCooldownProbe = -1
    for key in pairs(activeCooldown) do
        activeCooldown[key] = nil
    end
    for key in pairs(chargeState) do
        chargeState[key] = nil
    end
    Track.resetDots()
end

--- Single entry point the addon forwards game events to.
function Track.handleEvent(event, arg1, arg2, arg3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            Track.noteSpellCast(arg3)
            local displayId = ShinkiliEval and ShinkiliEval.getDisplaySpellId
                and ShinkiliEval.getDisplaySpellId(arg3) or nil
            Track.noteDotCast(arg3, displayId)
        end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        Track.refreshCooldowns()
        return
    end
    if event == "SPELL_UPDATE_CHARGES" then
        Track.refreshCharges()
        return
    end
    if event == "UNIT_AURA" then
        if arg1 == "target" then
            Track.onTargetAuraUpdate(arg2)
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        Track.resetDots()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        Track.resyncCooldowns()
        Track.resetDots()
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_ENTERING_WORLD" then
        clearStaticCaches()
        Track.reset()
        return
    end
end

function Track.getDiagnostics()
    local cooldowns, charges, dots = 0, 0, 0
    for _ in pairs(activeCooldown) do
        cooldowns = cooldowns + 1
    end
    for _ in pairs(chargeState) do
        charges = charges + 1
    end
    for _ in pairs(dotApplied) do
        dots = dots + 1
    end
    local scanned = 0
    for _ in pairs(baseCooldown) do
        scanned = scanned + 1
    end
    return {
        scannedSpells = scanned,
        activeCooldowns = cooldowns,
        chargeSpells = charges,
        trackedDots = dots,
        pendingDotCasts = #dotPendingCasts,
    }
end

-- The pick pipeline reaches local cooldown state through ShinkiliSecret's ladder.
Secret.localCooldownProvider = Track.isOnLocalCooldown

return Track
