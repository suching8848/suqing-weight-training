-- Controlled early-registry and equipped-item fixtures. No player/save is opened.
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local registered, registrationCalls = {}, 0
ResourceLocation = { of = function(value) return value end }
ItemBodyLocation = {
    get = function(id) return registered[id] end,
    register = function(id)
        registrationCalls = registrationCalls + 1
        assert(id:find(":", 1, true), "B42 custom slots require a namespace")
        assert(not registered[id], "duplicate registration must be prevented before native register")
        local slot = { id = id }
        registered[id] = slot
        return slot
    end,
}

local beltSlot = { id = "base:belt" }
local webbingSlot = { id = "base:webbing" }
local group = { locations = { [beltSlot] = true, [webbingSlot] = true }, additions = 0 }
function group:getOrCreateLocation(location)
    if not self.locations[location] then
        self.locations[location] = true
        self.additions = self.additions + 1
    end
    return location
end
function group:setExclusive()
    error("the independent training slot must not create an exclusivity relation")
end
BodyLocations = { getGroup = function(name)
    assert(name == "Human", "unexpected body-location group")
    return group
end }
package.loaded["NPCs/BodyLocations"] = true
local onCreatePlayer, onInventoryContext = {}, {}
Events = {
    OnCreatePlayer = { Add = function(fn) onCreatePlayer[#onCreatePlayer + 1] = fn end },
    OnFillInventoryObjectContextMenu = { Add = function(fn) onInventoryContext[#onInventoryContext + 1] = fn end },
}

dofile("SuQingWeightTraining/42/media/registries.lua")
local B = SuQingWeightTraining
local trainingSlot = registered["suqingweighttraining:suqingtrainingbelt"]
equal(B.itemRegistryReady, true, "early registry succeeded")
equal(B.itemBodyLocation, trainingSlot, "registered slot identity retained")
equal(registrationCalls, 1, "one initial slot registration")
equal(group.locations[trainingSlot], nil, "registry phase does not reorder human slots")

dofile("SuQingWeightTraining/42/media/registries.lua")
equal(registrationCalls, 1, "repeated registry execution reuses existing slot")
equal(B.itemBodyLocation, trainingSlot, "repeat does not replace existing native identity")

local loaded = require "SuQingWeightTraining/Items"
equal(loaded, B, "Items returns the shared module table")
equal(B.ITEM_TYPE, "SuQingWeightTraining.TrainingBelt", "stable item FullType")
equal(B.ITEM_FULL_TYPE, B.ITEM_TYPE, "FullType alias")
equal(B.BODY_LOCATION_ID, "suqingweighttraining:suqingtrainingbelt", "namespaced body slot")
equal(B.GetBodyLocation(), trainingSlot, "slot resolves through native registry API")
equal(group.locations[trainingSlot], true, "Items adds custom human slot")
equal(group.additions, 1, "only the training slot is added")
equal(group.locations[beltSlot], true, "normal belt slot remains")
equal(group.locations[webbingSlot], true, "existing chest-rig slot remains")
equal(B.EnsureBodyLocation(), true, "slot registration is safely repeatable")
equal(group.additions, 1, "repeat creates no additional human slot")
equal(B.ITEM_WEIGHT, 10, "native item weight target")
equal(B.ITEM_WEIGHT_VERSION, 2, "saved-item migration schema")
equal(#onCreatePlayer, 1, "one creation-time inventory migration handler")
equal(#onInventoryContext, 1, "one selected-item migration handler")

local function item(fullType)
    local value = { data = {}, actualWeight = 1, displayWeight = 1, customWeight = false, setterCalls = 0 }
    function value:getFullType() return fullType end
    function value:getModData() return self.data end
    function value:setActualWeight(weight)
        self.actualWeight = weight
        self.setterCalls = self.setterCalls + 1
    end
    function value:setWeight(weight)
        self.displayWeight = weight
        self.setterCalls = self.setterCalls + 1
    end
    function value:setCustomWeight(custom)
        self.customWeight = custom
        self.setterCalls = self.setterCalls + 1
    end
    return value
end
local ordinaryBelt = item("Base.Belt2")
local existingRig = item("Base.Bag_ChestRig_083")
local trainingBelt = item(B.ITEM_TYPE)
local player = {
    worn = { [beltSlot] = ordinaryBelt, [webbingSlot] = existingRig },
    primaryHand = trainingBelt,
    inventory = { trainingBelt },
}
function player:getWornItem(location) return self.worn[location] end

equal(B.GetWornBelt(player), nil, "carried/held belt is not worn")
equal(trainingBelt.setterCalls, 0, "worn check does not migrate a carried belt")
equal(B.IsWorn(player), false, "holding does not activate training")
player.primaryHand = nil
equal(B.IsWorn(player), false, "inventory ownership does not activate training")
player.worn[beltSlot] = trainingBelt
equal(B.IsWorn(player), false, "wrong slot is not accepted as the training slot")
player.worn[beltSlot] = ordinaryBelt
player.worn[trainingSlot] = trainingBelt
equal(B.GetWornBelt(player), trainingBelt, "returns the actual equipped instance")
equal(trainingBelt.actualWeight, 10, "old worn belt receives native actual weight")
equal(trainingBelt.displayWeight, 10, "old worn belt receives display weight")
equal(trainingBelt.customWeight, true, "native custom-weight save flag enabled")
equal(trainingBelt.data[B.ITEM_WEIGHT_VERSION_KEY], 2, "migration marked only after setters")
equal(B.IsWorn(player), true, "correctly worn belt detected")
equal(trainingBelt.setterCalls, 3, "repeated worn checks do not repeat setters")
equal(player.worn[beltSlot], ordinaryBelt, "wearing training belt preserves existing belt")
equal(player.worn[webbingSlot], existingRig, "wearing training belt preserves existing chest rig")

local secondBelt = item(B.ITEM_TYPE)
player.worn[trainingSlot] = secondBelt
equal(B.GetWornBelt(player), secondBelt, "instance replacement remains observable to Runtime")
player.worn[trainingSlot] = existingRig
equal(B.IsWorn(player), false, "another item in the slot is not a training belt")
player.worn[trainingSlot] = nil
equal(B.GetWornBelt(player), nil, "removal is immediately observable")
equal(B.GetWornBelt(nil), nil, "missing player rejected")
equal(B.GetWornBelt({}), nil, "missing worn-item API rejected")

local migrated, changed = B.MigrateBelt(trainingBelt)
equal(migrated, true, "already migrated belt accepted")
equal(changed, false, "already migrated belt unchanged")
equal(B.MigrateBelt(ordinaryBelt), false, "foreign belt never migrated")
equal(ordinaryBelt.setterCalls, 0, "ordinary belt weight remains untouched")
equal(existingRig.setterCalls, 0, "chest-rig weight remains untouched")
equal(B.MigrateBelt(nil), false, "nil item rejected")
equal(B.MigrateBelt({}), false, "non-item rejected")
local futureBelt = item(B.ITEM_TYPE)
futureBelt.data[B.ITEM_WEIGHT_VERSION_KEY] = 3
futureBelt.actualWeight = 12
equal(B.MigrateBelt(futureBelt), true, "future migration version is preserved")
equal(futureBelt.setterCalls, 0, "future version is not downgraded")
equal(futureBelt.actualWeight, 12, "migration is not a per-frame weight override")

local brokenBelt = item(B.ITEM_TYPE)
brokenBelt.setWeight = function() error("controlled setter failure") end
equal(B.MigrateBelt(brokenBelt), false, "setter failure deferred")
equal(brokenBelt.data[B.ITEM_WEIGHT_VERSION_KEY], nil, "partial migration is not marked complete")
player.worn[trainingSlot] = brokenBelt
equal(B.GetWornBelt(player), brokenBelt, "migration failure does not hide the actually worn item")
brokenBelt.setWeight = function(self, weight) self.displayWeight = weight end
equal(B.MigrateBelt(brokenBelt), true, "failed migration can retry")
equal(brokenBelt.displayWeight, 10, "retry repairs remaining native field")
equal(brokenBelt.data[B.ITEM_WEIGHT_VERSION_KEY], 2, "retry records completed migration")

local function container(values)
    local value = { values = values or {}, scans = 0 }
    function value:getItems()
        self.scans = self.scans + 1
        return {
            size = function() return #value.values end,
            get = function(_, i) return value.values[i + 1] end,
        }
    end
    return value
end
local directOld = item(B.ITEM_TYPE)
local nestedOld = item(B.ITEM_TYPE)
local rootInventory = container({ ordinaryBelt, directOld })
local bagInventory = container({ nestedOld, existingRig })
local bag = item("Base.Bag_Schoolbag")
function bag:getInventory() return bagInventory end
rootInventory.values[#rootInventory.values + 1] = bag
local cycleBag = item("Base.Bag_Schoolbag")
function cycleBag:getInventory() return rootInventory end
bagInventory.values[#bagInventory.values + 1] = cycleBag
local inventoryPlayer = { getInventory = function() return rootInventory end }
equal(B.MigrateInventory(inventoryPlayer), 2, "once-only startup scan migrates direct and nested belts")
equal(directOld.actualWeight, 10, "direct inventory belt weight migrated")
equal(nestedOld.actualWeight, 10, "nested bag belt weight migrated")
equal(bag.setterCalls, 0, "container weight is not altered")
equal(rootInventory.scans, 1, "cycle does not repeat root scan")
equal(bagInventory.scans, 1, "nested inventory visited once")
local laterOld = item(B.ITEM_TYPE)
rootInventory.values[#rootInventory.values + 1] = laterOld
equal(B.MigrateInventory(inventoryPlayer), 0, "same inventory is not rescanned")
equal(rootInventory.scans, 1, "second call avoids inventory iteration")
equal(laterOld.setterCalls, 0, "later items wait for an on-demand migration")
equal(B.MigrateInventory(nil), 0, "missing startup player safely ignored")
equal(B.MigrateInventory({}), 0, "missing inventory API safely ignored")

local createOld = item(B.ITEM_TYPE)
local createInventory = container({ createOld })
onCreatePlayer[1](0, { getInventory = function() return createInventory end })
equal(createOld.actualWeight, 10, "OnCreatePlayer covers a player unavailable at OnGameStart")
onCreatePlayer[1](0, { getInventory = function() return createInventory end })
equal(createInventory.scans, 1, "creation handler remains once per inventory")

local groundOld = item(B.ITEM_TYPE)
local dummy = item(B.ITEM_TYPE)
local stackOld = item(B.ITEM_TYPE)
onInventoryContext[1](0, {}, { groundOld, { items = { dummy, stackOld, stackOld } }, laterOld, ordinaryBelt })
equal(groundOld.actualWeight, 10, "selected ground belt migrates without a world scan")
equal(stackOld.actualWeight, 10, "actual selected stack member migrated")
equal(stackOld.setterCalls, 3, "duplicate stack selection remains idempotent")
equal(dummy.setterCalls, 0, "native stack dummy skipped")
equal(laterOld.actualWeight, 10, "later acquired old belt migrates on selection")
equal(rootInventory.scans, 1, "selected-item handler does not rescan inventory")
equal(ordinaryBelt.setterCalls, 0, "selected foreign items remain untouched")
onInventoryContext[1](0, {}, nil)

print("weight-training item fixtures passed: " .. tostring(checks))
return checks
