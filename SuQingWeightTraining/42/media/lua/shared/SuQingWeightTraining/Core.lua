SuQingWeightTraining = SuQingWeightTraining or {}
local B = SuQingWeightTraining

B.VERSION = "0.3.2"
B.BASE_XP_PER_MINUTE = 5
B.ITEM_TYPE = "SuQingWeightTraining.TrainingBelt"
B.MOD_DATA_KEY = "SuQingWeightTraining"
B.SKILLS = {"Fitness", "Strength", "Sprinting", "Sneak", "Nimble", "Lightfoot"}
B.MAX_REAL_GAP_MS = 5000
B.MAX_GAME_GAP_HOURS = 0.05

function B.IsFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function B.GetMultiplier()
    local options = SandboxVars and SandboxVars.SuQingWeightTraining
    local value = options and options.XPMultiplier
    if not B.IsFinite(value) then return 1 end
    return math.max(0.1, math.min(20, value))
end

function B.GetState(player)
    local data = player:getModData()
    local state = data[B.MOD_DATA_KEY]
    if state == nil then
        state = {schema = 1, remainderMinutes = 0}
        data[B.MOD_DATA_KEY] = state
    elseif type(state) ~= "table" or state.schema ~= 1 then
        error("unsupported training progress schema")
    end
    if not B.IsFinite(state.remainderMinutes)
        or state.remainderMinutes < 0 or state.remainderMinutes >= 1 then
        state.remainderMinutes = 0
    end
    return state
end

-- Samples are session-only. Only the sub-minute remainder is persisted, so
-- loading a save or returning after a gap cannot award offline training.
function B.Observe(state, old, now)
    if not old then return 0, "baseline" end
    if not old.belt or old.belt ~= now.belt then return 0, "equipment-change" end
    if not old.eligible or not now.eligible or not old.moving or not now.moving
        or old.vehicle or now.vehicle or old.asleep or now.asleep or old.dead or now.dead then
        return 0, "inactive"
    end
    for _, key in ipairs({"x", "y", "z", "hour", "stamp", "minutesPerDay"}) do
        if not B.IsFinite(old[key]) or not B.IsFinite(now[key]) then return 0, "invalid-sample" end
    end
    if now.minutesPerDay <= 0 or now.minutesPerDay ~= old.minutesPerDay then
        return 0, "day-length-change"
    end
    local hours = now.hour - old.hour
    local milliseconds = now.stamp - old.stamp
    if hours <= 0 then return 0, "clock-idle-or-reset" end
    if hours > B.MAX_GAME_GAP_HOURS or milliseconds < 0 or milliseconds > B.MAX_REAL_GAP_MS then
        return 0, "sample-gap"
    end
    local dx, dy = now.x - old.x, now.y - old.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= 0.00001 then return 0, "no-displacement" end
    -- Convert elapsed world hours to simulation seconds at normal speed.
    -- This deliberately follows day length and fast-forward, unlike a fixed
    -- distance-per-real-second filter which can reject accelerated walking.
    local simulationSeconds = hours * now.minutesPerDay * 60 / 24
    if math.abs(now.z - old.z) > 1 or distance > 0.25 + 12 * simulationSeconds then
        return 0, "position-jump"
    end
    local total = state.remainderMinutes + hours * 60
    local minutes = math.floor(total + 0.0000001)
    state.remainderMinutes = math.max(0, total - minutes)
    return minutes, "moving"
end

-- Use normal native AddXP exactly once per skill. Sandbox/character/nutrition
-- modifiers run there; the existing protein-drink listener then multiplies
-- the actual Strength/Fitness award. No second post-award listener is added.
function B.Grant(player, minutes, multiplier)
    if not B.IsFinite(minutes) or minutes <= 0 or minutes ~= math.floor(minutes) then
        return 0
    end
    multiplier = multiplier or B.GetMultiplier()
    if not B.IsFinite(multiplier) or multiplier < 0.1 or multiplier > 20 then
        error("invalid training XP multiplier")
    end
    local input = minutes * B.BASE_XP_PER_MINUTE * multiplier
    local xp = player:getXp()
    local count = 0
    local details = {}
    for _, name in ipairs(B.SKILLS) do
        local perk = Perks[name]
        if not perk then error("missing native perk: " .. name) end
        local detail = {skill = name, input = input, actual = 0, reason = "max-level"}
        details[#details + 1] = detail
        if player:getPerkLevel(perk) < 10 then
            local before = xp:getXP(perk)
            xp:AddXP(perk, input)
            count = count + 1
            detail.actual = xp:getXP(perk) - before
            detail.reason = detail.actual > 0 and "awarded" or "native-rule"
        end
    end
    return count, details
end

return B
