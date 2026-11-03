-- Item/slot helpers only. Training state and XP logic belong to Core/Runtime.
require "NPCs/BodyLocations"

SuQingWeightTraining = SuQingWeightTraining or {}
local B = SuQingWeightTraining
B.ITEM_TYPE = B.ITEM_TYPE or "SuQingWeightTraining.TrainingBelt"
B.ITEM_FULL_TYPE = B.ITEM_TYPE
B.BODY_LOCATION_NAME = "SuQingTrainingBelt"
B.BODY_LOCATION_ID = "suqingweighttraining:suqingtrainingbelt"
B.ITEM_WEIGHT = 10
B.ITEM_WEIGHT_VERSION = 2
B.ITEM_WEIGHT_VERSION_KEY = "SuQingWeightTrainingWeightVersion"

local migratedInventories = setmetatable({}, { __mode = "k" })

local function migrationWarning(reason)
    if B.itemMigrationWarningShown then return end
    B.itemMigrationWarningShown = true
    print("[SuQingWeightTraining] WARNING: belt weight migration was deferred: " .. tostring(reason))
end

function B.MigrateBelt(item)
    if not item or not item.getFullType or item:getFullType() ~= B.ITEM_TYPE then
        return false, false
    end
    if not item.getModData then return false, false end
    local data = item:getModData()
    if not data then return false, false end
    local version = data[B.ITEM_WEIGHT_VERSION_KEY]
    if type(version) == "number" and version >= B.ITEM_WEIGHT_VERSION then
        return true, false
    end
    if not item.setActualWeight or not item.setWeight or not item.setCustomWeight then
        migrationWarning("native item-weight APIs are unavailable")
        return false, false
    end
    local ok, reason = pcall(function()
        -- These native fields and the custom-weight save flag preserve an old
        -- saved belt's new weight across save/reload. Worn weight stays native.
        item:setActualWeight(B.ITEM_WEIGHT)
        item:setWeight(B.ITEM_WEIGHT)
        item:setCustomWeight(true)
        data[B.ITEM_WEIGHT_VERSION_KEY] = B.ITEM_WEIGHT_VERSION
    end)
    if not ok then
        migrationWarning(reason)
        return false, false
    end
    return true, true
end

function B.MigrateInventory(player)
    if not player or not player.getInventory then return 0 end
    local root = player:getInventory()
    if not root or not root.getItems or migratedInventories[root] then return 0 end
    local changed, visited = 0, {}
    local function visit(container)
        if not container or visited[container] or not container.getItems then return end
        visited[container] = true
        local items = container:getItems()
        if not items or not items.size or not items.get then return end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local _, migrated = B.MigrateBelt(item)
            if migrated then changed = changed + 1 end
            if item and item.getInventory then visit(item:getInventory()) end
        end
    end
    visit(root)
    migratedInventories[root] = true
    return changed
end

function B.OnCreatePlayerMigrate(_, player)
    B.MigrateInventory(player)
end

function B.OnInventoryContextMigrate(_, _, items)
    -- Cover old belts selected from the ground/containers without a world scan.
    -- Native inventory stacks repeat a dummy item at index 1; skip that entry.
    if type(items) ~= "table" then return end
    for _, entry in ipairs(items) do
        if entry and entry.getFullType then
            B.MigrateBelt(entry)
        elseif type(entry) == "table" and type(entry.items) == "table" then
            for i = 2, #entry.items do B.MigrateBelt(entry.items[i]) end
        end
    end
end

function B.GetBodyLocation()
    if not ItemBodyLocation or not ItemBodyLocation.get
        or not ResourceLocation or not ResourceLocation.of then return nil end
    return ItemBodyLocation.get(ResourceLocation.of(B.BODY_LOCATION_ID))
end

function B.EnsureBodyLocation()
    local location = B.GetBodyLocation()
    if not location or not BodyLocations or not BodyLocations.getGroup then return false end
    local group = BodyLocations.getGroup("Human")
    if not group or not group.getOrCreateLocation then return false end
    -- No exclusivity or hide-model relations: existing belt/webbing slots stay independent.
    group:getOrCreateLocation(location)
    return true
end

function B.GetWornBelt(player)
    if not player or not player.getWornItem then return nil end
    local location = B.GetBodyLocation()
    if not location then return nil end
    local item = player:getWornItem(location)
    if item and item.getFullType and item:getFullType() == B.ITEM_TYPE then
        B.MigrateBelt(item)
        return item
    end
    return nil
end

function B.IsWorn(player)
    return B.GetWornBelt(player) ~= nil
end

if not B.EnsureBodyLocation() then
    print("[SuQingWeightTraining] ERROR: independent training-belt body slot is unavailable")
end

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(B.OnCreatePlayerMigrate)
end
if Events and Events.OnFillInventoryObjectContextMenu then
    Events.OnFillInventoryObjectContextMenu.Add(B.OnInventoryContextMigrate)
end

return B
