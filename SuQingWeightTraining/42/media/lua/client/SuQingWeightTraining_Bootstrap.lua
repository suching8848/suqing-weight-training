if isClient() or isServer() then return end
local R = require "SuQingWeightTraining/Runtime"
Events.OnGameStart.Add(R.OnGameStart)
Events.OnPlayerUpdate.Add(R.OnPlayerUpdate)
-- The optional display must never block the training callbacks above.
local ok, UI = pcall(require, "SuQingWeightTraining/StatusUI")
if ok and UI and UI.Install then
    local installed, err = pcall(UI.Install)
    if not installed then print("[SuQingWeightTraining] WARNING: status display: " .. tostring(err)) end
elseif not ok then
    print("[SuQingWeightTraining] WARNING: status display unavailable: " .. tostring(UI))
end
