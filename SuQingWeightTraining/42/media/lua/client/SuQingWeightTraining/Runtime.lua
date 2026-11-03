local B = require "SuQingWeightTraining/Core"
require "SuQingWeightTraining/Items"
local R = {}
B.Runtime = R
R.sessions = setmetatable({}, {__mode = "k"})

local function sessionFor(player)
    local session = R.sessions[player]
    if not session then
        session = {phase = "inactive", reason = "not-worn"}
        R.sessions[player] = session
    end
    return session
end

local function fault(player, message)
    local session = sessionFor(player)
    if session.fault then return end
    session.fault = tostring(message)
    session.phase, session.reason = "fault", "fault"
    session.sample = nil
    print("[SuQingWeightTraining] ERROR: training paused for this player: " .. session.fault)
    if HaloTextHelper and getText then
        HaloTextHelper.addText(player, getText("IGUI_SuQingWeightTraining_Error"))
    end
end

-- Standard Lua game APIs only. Observe also requires actual coordinate movement.
local function activity(player, belt)
    if not belt then return false, "not-worn" end
    if player:isDead() then return false, "dead" end
    if player:isAsleep() then return false, "asleep" end
    if player:getVehicle() ~= nil then return false, "vehicle" end
    if player.isClimbing and player:isClimbing() then return false, "climbing" end
    if player.isOnFloor and player:isOnFloor() then return false, "prone" end
    if (player.isGrappling and player:isGrappling())
        or (player.isBeingGrappled and player:isBeingGrappled()) then return false, "grappled" end
    if not player:isPlayerMoving() then return false, "stopped" end
    return true, "moving"
end

function R.Update(player)
    if not player or not player:isLocalPlayer() then return end
    local session = sessionFor(player)
    if session.fault then return end
    local gameTime = getGameTime()
    local belt = B.GetWornBelt(player)
    local eligible, reason = activity(player, belt)
    local now = {
        belt = belt, eligible = eligible, moving = eligible,
        vehicle = player:getVehicle() ~= nil,
        asleep = player:isAsleep(), dead = player:isDead(),
        x = player:getX(), y = player:getY(), z = player:getZ(),
        hour = gameTime:getWorldAgeHours(), stamp = getTimestampMs(),
        minutesPerDay = gameTime:getMinutesPerDay(),
    }
    local old = session.sample
    session.sample = now
    session.phase = belt and "paused" or "inactive"
    session.reason = reason
    if not belt and not (old and old.belt) then return end
    local state = B.GetState(player)
    local minutes, observed = B.Observe(state, old, now)
    if eligible then
        session.reason = observed
        if observed == "moving" then session.phase = "training" end
    end
    if minutes > 0 then
        -- Consume the minute before calling native XP; failures are never replayed.
        local count, details = B.Grant(player, minutes)
        session.lastAward = details
        session.lastMinutes = minutes
        session.lastAwardAt = now.hour
        local summary = {}
        for _, detail in ipairs(details) do
            summary[#summary + 1] = detail.skill .. "+" .. tostring(detail.actual)
                .. "(" .. detail.reason .. ")"
        end
        print("[SuQingWeightTraining] awarded " .. tostring(minutes) .. " game minute(s), multiplier="
            .. tostring(B.GetMultiplier()) .. ", eligible skills=" .. tostring(count) .. ": "
            .. table.concat(summary, ", "))
    end
end

function R.OnPlayerUpdate(player)
    if not player or not player:isLocalPlayer() then return end
    local ok, err = pcall(R.Update, player)
    if not ok then fault(player, err) end
end

function R.GetStatus(player)
    local session = player and R.sessions[player]
    local data = player and player:getModData()
    local state = data and data[B.MOD_DATA_KEY]
    local remainder = type(state) == "table" and state.remainderMinutes or 0
    if not B.IsFinite(remainder) or remainder < 0 or remainder >= 1 then remainder = 0 end
    return {
        phase = session and session.phase or "inactive",
        reason = session and session.reason or "not-worn",
        multiplier = B.GetMultiplier(), remainderMinutes = remainder,
        lastAward = session and session.lastAward,
        lastMinutes = session and session.lastMinutes,
        fault = session and session.fault,
    }
end

function R.OnGameStart()
    R.sessions = setmetatable({}, {__mode = "k"})
    local player = getPlayer and getPlayer()
    if player and B.MigrateInventory then
        local ok, err = pcall(B.MigrateInventory, player)
        if not ok then print("[SuQingWeightTraining] WARNING: belt migration: " .. tostring(err)) end
    end
    print("[SuQingWeightTraining] v" .. B.VERSION .. " pure Lua loaded; XP multiplier="
        .. tostring(B.GetMultiplier()) .. "; native item weight=10, no forced movement penalty")
end

return R
