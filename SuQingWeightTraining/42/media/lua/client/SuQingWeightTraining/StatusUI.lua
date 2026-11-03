local B = require "SuQingWeightTraining/Core"
-- UI availability never controls training. Bootstrap also loads this module
-- after registering the independent Runtime callbacks.
pcall(require, "ISUI/ISPanel")

local U = {}
B.StatusUI = U
-- Visibility is manual and session-only; old saved preferences are ignored.
U.visibleFor = setmetatable({}, {__mode = "k"})
U.REFRESH_MS = 250

local fallback = {
    Title = "Weight training", Show = "Show weight training status",
    Training = "Training", Paused = "Paused", Fault = "Training paused after an error",
    Inactive = "Inactive", Multiplier = "Training multiplier: x%1",
    Next = "Next award: %1 game seconds of valid movement",
    Recent = "Last award: %1 game minute(s)", NoAward = "No award recorded yet",
    Row = "%1: %2 (base %3)", Max = "%1: +0 (maximum level)",
    Native = "%1: +0 (native XP rule)", Empty = "%1: --",
    Fitness = "Fitness", Strength = "Strength", Sprinting = "Sprinting",
    Sneak = "Sneaking", Nimble = "Nimble", Lightfoot = "Lightfooted",
    NotWorn = "belt not worn", Stopped = "not moving", Vehicle = "in a vehicle",
    Asleep = "asleep", Dead = "character dead", Climbing = "climbing",
    Prone = "on the ground", Grappled = "grappling or being grappled",
    Baseline = "taking the first movement sample",
    Equipment = "equipment changed", Invalid = "invalid sample",
    DayLength = "day length changed", Clock = "game clock paused or reset",
    Gap = "movement sample gap", Displacement = "no body movement",
    Jump = "position changed too far", Moving = "valid movement",
    Other = "waiting for valid movement",
}

local reasonKeys = {
    ["not-worn"] = "NotWorn", stopped = "Stopped", vehicle = "Vehicle",
    asleep = "Asleep", dead = "Dead", climbing = "Climbing", prone = "Prone", grappled = "Grappled",
    baseline = "Baseline", ["equipment-change"] = "Equipment",
    ["invalid-sample"] = "Invalid", ["day-length-change"] = "DayLength",
    ["clock-idle-or-reset"] = "Clock", ["sample-gap"] = "Gap",
    ["no-displacement"] = "Displacement", ["position-jump"] = "Jump",
    moving = "Moving", inactive = "Other", fault = "Fault",
}

local function text(key, ...)
    local id = "UI_SuQingWeightTraining_" .. key
    if getText then
        local ok, result = pcall(getText, id, ...)
        if ok and result and result ~= id then return result end
    end
    local result = fallback[key] or key
    local values = {...}
    for index, value in ipairs(values) do
        result = string.gsub(result, "%%" .. index, function() return tostring(value) end)
    end
    return result
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function number(value)
    if not finite(value) then return "--" end
    local valueText = string.format("%.2f", value)
    valueText = string.gsub(valueText, "0+$", "")
    return (string.gsub(valueText, "%.$", ""))
end

function U.BuildLines(status)
    local phase = status.phase or "inactive"
    local title = ({training = "Training", paused = "Paused", fault = "Fault", inactive = "Inactive"})[phase] or "Inactive"
    local reason = reasonKeys[status.reason] or "Other"
    local stateText = text(title)
    if title ~= reason then stateText = stateText .. " - " .. text(reason) end
    local remainder = finite(status.remainderMinutes) and status.remainderMinutes or 0
    remainder = math.max(0, math.min(1, remainder))
    local seconds = math.ceil((1 - remainder) * 60 - 0.000001)
    local lines = {
        text("Title"), stateText, text("Multiplier", number(status.multiplier)),
        text("Next", seconds),
    }
    local records, hasRecords = {}, false
    for _, entry in ipairs(status.lastAward or {}) do
        records[entry.skill] = entry
        hasRecords = true
    end
    if hasRecords then
        lines[#lines + 1] = text("Recent", number(status.lastMinutes))
    else
        lines[#lines + 1] = text("NoAward")
    end
    for _, skill in ipairs(B.SKILLS) do
        local label = text(skill)
        local entry = records[skill]
        if not entry then
            lines[#lines + 1] = text("Empty", label)
        elseif entry.reason == "max-level" then
            lines[#lines + 1] = text("Max", label)
        elseif entry.reason == "native-rule" then
            lines[#lines + 1] = text("Native", label)
        else
            local amount = finite(entry.actual) and entry.actual or 0
            local signed = (amount >= 0 and "+" or "") .. number(amount)
            lines[#lines + 1] = text("Row", label, signed, number(entry.input))
        end
    end
    return lines
end

local function localPlayer(index)
    if getSpecificPlayer then
        local player = getSpecificPlayer(index or 0)
        if player then return player end
    end
    if getPlayer then return getPlayer() end
    return nil
end

function U.GetPreference(player)
    return player ~= nil and U.visibleFor[player] == true
end

function U.WantsVisible(player)
    return U.GetPreference(player)
end

local function hide()
    if U.panel and U.panel.setVisible then pcall(U.panel.setVisible, U.panel, false) end
end

local function fail(error)
    hide()
    if not U.failed then
        U.failed = tostring(error)
        print("[SuQingWeightTraining] status display unavailable; training callbacks are unchanged: " .. U.failed)
    end
    return false
end

local function createPanel()
    if not ISPanel or not ISPanel.derive or not UIFont or not UIFont.Small or not getTextManager then return nil end
    if not U.Panel then
        local panelClass = ISPanel:derive("SuQingWeightTrainingStatusPanel")
        function panelClass:render()
            -- Rendering only consumes cached strings, never Runtime/XP APIs.
            for index, line in ipairs(self.statusLines or {}) do
                self:drawText(line, 10, 8 + (index - 1) * self.lineHeight, 1, 1, 1, 1, UIFont.Small)
            end
        end
        U.Panel = panelClass
    end
    local screenWidth = getCore and getCore():getScreenWidth() or 1280
    local panel = U.Panel:new(math.max(20, screenWidth - 420), 180, 400, 210)
    panel.moveWithMouse = true
    panel.backgroundColor = {r = 0.04, g = 0.04, b = 0.04, a = 0.8}
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    return panel
end

local function display(player, status)
    if not status or not U.WantsVisible(player, status) then hide(); return end
    U.panel = U.panel or createPanel()
    if not U.panel then return end
    local panel = U.panel
    local manager = getTextManager()
    panel.lineHeight = manager:getFontHeight(UIFont.Small) + 3
    panel.statusLines = U.lines
    local width = 240
    for _, line in ipairs(U.lines) do width = math.max(width, manager:MeasureStringX(UIFont.Small, line) + 20) end
    local screenWidth = getCore and getCore():getScreenWidth() or 1280
    width = math.min(width, math.max(200, screenWidth - 40))
    panel:setWidth(width)
    panel:setHeight(#U.lines * panel.lineHeight + 16)
    if panel:getX() + width > screenWidth then panel:setX(math.max(0, screenWidth - width - 20)) end
    panel:setVisible(true)
end

local function refresh(forceDisplay)
    local player = localPlayer()
    if not player then hide(); U.player = nil; return end
    if U.player ~= player then
        U.player = player
        U.lastRead = nil
        U.status = nil
    end
    local timestamp = getTimestampMs and getTimestampMs()
    if not finite(timestamp) then hide(); return end
    local due = not U.lastRead or timestamp < U.lastRead or timestamp - U.lastRead >= U.REFRESH_MS
    if due then
        U.lastRead = timestamp
        local runtime = B.Runtime
        if not runtime or type(runtime.GetStatus) ~= "function" then hide(); return end
        U.status = runtime.GetStatus(player)
        U.lines = U.status and U.BuildLines(U.status) or nil
    elseif not forceDisplay then
        return
    end
    if U.status and U.lines then display(player, U.status) else hide() end
end

function U.Refresh(forceDisplay)
    if U.failed then return false end
    local ok, error = pcall(refresh, forceDisplay)
    if not ok then return fail(error) end
    return true
end

function U.Toggle(player)
    local ok, error = pcall(function()
        U.visibleFor[player] = not U.WantsVisible(player)
        U.Refresh(true)
    end)
    if not ok then return fail(error) end
    return true
end

function U.ContainsBelt(items)
    for _, entry in ipairs(items or {}) do
        if entry and entry.getFullType and entry:getFullType() == B.ITEM_TYPE then return true end
        if type(entry) == "table" and type(entry.items) == "table" then
            for _, item in ipairs(entry.items) do
                if item and item.getFullType and item:getFullType() == B.ITEM_TYPE then return true end
            end
        end
    end
    return false
end

function U.OnContextMenu(index, context, items)
    local ok, error = pcall(function()
        local player = localPlayer(index)
        if not player or not U.ContainsBelt(items) then return end
        local option = context:addOption(text("Show"), player, U.Toggle)
        local checked = U.WantsVisible(player, U.status)
        if context.setOptionChecked then context:setOptionChecked(option, checked)
        else option.checkMark = checked end
    end)
    if not ok then return fail(error) end
    return true
end

function U.OnGameStart()
    if U.panel and U.panel.removeFromUIManager then pcall(U.panel.removeFromUIManager, U.panel) end
    U.visibleFor = setmetatable({}, {__mode = "k"})
    U.panel, U.player, U.status, U.lines, U.lastRead, U.failed = nil, nil, nil, nil, nil, nil
    return U.Refresh(true)
end

function U.OnTick()
    return U.Refresh(false)
end

function U.Install()
    if U.installed then return true end
    if not Events or not Events.OnGameStart or not Events.OnTick
        or not Events.OnFillInventoryObjectContextMenu then return false end
    -- Each UI callback catches its own errors; none is called by Runtime.
    Events.OnGameStart.Add(U.OnGameStart)
    Events.OnTick.Add(U.OnTick)
    Events.OnFillInventoryObjectContextMenu.Add(U.OnContextMenu)
    U.installed = true
    return true
end

return U
