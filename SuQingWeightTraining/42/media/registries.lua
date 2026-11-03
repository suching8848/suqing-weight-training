-- B42 executes this registry phase before item and recipe parsing.
SuQingWeightTraining = SuQingWeightTraining or {}
local B = SuQingWeightTraining
B.BODY_LOCATION_NAME = "SuQingTrainingBelt"
B.BODY_LOCATION_ID = "suqingweighttraining:suqingtrainingbelt"

local ok, result = pcall(function()
    if not ItemBodyLocation or not ItemBodyLocation.get or not ItemBodyLocation.register
        or not ResourceLocation or not ResourceLocation.of then
        error("required B42 body-location registry API is unavailable")
    end
    local id = ResourceLocation.of(B.BODY_LOCATION_ID)
    local location = ItemBodyLocation.get(id)
    if not location then location = ItemBodyLocation.register(B.BODY_LOCATION_ID) end
    if not location then error("training-belt body-location registration returned nil") end
    return location
end)

B.itemRegistryReady = ok
if ok then
    B.itemBodyLocation = result
    B.itemRegistryError = nil
else
    B.itemBodyLocation = nil
    B.itemRegistryError = tostring(result)
    print("[SuQingWeightTraining] ERROR: body-location registration failed: " .. B.itemRegistryError)
end
