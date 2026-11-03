local B = require "SuQingWeightTraining/Core"
local tests = {}
local function test(name, callback) tests[#tests + 1] = {name, callback} end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local function contains(lines, fragment)
    for _, line in ipairs(lines) do if string.find(line, fragment, 1, true) then return true end end
    return false
end

-- A small panel fixture exercises the lifecycle without duplicating drawing.
ISPanel = {}
function ISPanel:derive()
    local derived = {}; derived.__index = derived
    setmetatable(derived, {__index = self})
    return derived
end
function ISPanel:new(x, y, width, height)
    return setmetatable({x=x, y=y, width=width, height=height}, self)
end
function ISPanel:initialise() end
function ISPanel:instantiate() end
function ISPanel:addToUIManager() self.added = true end
function ISPanel:removeFromUIManager() self.added = false end
function ISPanel:setVisible(value) self.visible = value end
function ISPanel:setWidth(value) self.width = value end
function ISPanel:setHeight(value) self.height = value end
function ISPanel:getX() return self.x end
function ISPanel:setX(value) self.x = value end
function ISPanel:drawText() end
package.loaded["ISUI/ISPanel"] = true
-- Match the game's Kahlua environment, which exposes pairs/ipairs but not next.
next = nil
UIFont = {Small = "small"}
getTextManager = function() return {
    getFontHeight = function() return 12 end,
    MeasureStringX = function(_, _, value) return #value * 7 end,
} end
getCore = function() return {getScreenWidth = function() return 1280 end} end
getText = function(key) return key end
local milliseconds = 1000
getTimestampMs = function() return milliseconds end
local currentPlayer
getSpecificPlayer = function(index) if index == 0 then return currentPlayer end end
getPlayer = function() return currentPlayer end
local calls = 0
local status
local events = {}
local function event()
    local callbacks = {}
    return {callbacks=callbacks, Add=function(callback) callbacks[#callbacks+1]=callback end}
end
Events = {OnGameStart=event(), OnTick=event(), OnFillInventoryObjectContextMenu=event()}
B.GetWornBelt = function(player) return player.belt end
B.Runtime = {GetStatus=function() calls=calls+1; return status end}
-- UI must never need these write/XP paths.
B.GetState = function() error("UI created training state") end
B.Observe = function() error("UI changed training time") end
B.Grant = function() error("UI granted XP") end
local U = require "SuQingWeightTraining/StatusUI"
local function reset(worn)
    milliseconds = milliseconds + 1000
    currentPlayer = {data={}, belt=worn and {} or nil}
    function currentPlayer:getModData() return self.data end
    function currentPlayer:getXp() error("UI sampled native XP") end
    status = {phase=worn and "training" or "inactive", reason=worn and "moving" or "not-worn",
        multiplier=20, remainderMinutes=0.25, lastMinutes=0, lastAward={}}
    calls = 0
    U.OnGameStart()
    return currentPlayer
end

test("install is idempotent and independent of runtime events", function()
    assert(U.Install()); assert(U.Install())
    equal(#Events.OnGameStart.callbacks, 1); equal(#Events.OnTick.callbacks, 1)
    equal(#Events.OnFillInventoryObjectContextMenu.callbacks, 1)
    equal(Events.OnPlayerUpdate, nil)
end)

test("wearing and moving on entry never opens the status panel", function()
    local player = reset(true)
    equal(U.panel, nil); equal(U.GetPreference(player), false)
    equal(calls, 1); equal(player.data[B.MOD_DATA_KEY], nil)
    assert(contains(U.lines, "x20")); assert(contains(U.lines, "45 game seconds"))
    milliseconds = milliseconds + 250; U.OnTick(); equal(U.panel, nil)
    player.belt = nil; status.phase="inactive"; status.reason="not-worn"
    milliseconds = milliseconds + 250; U.OnTick(); equal(U.panel, nil)
    equal(player.data[B.MOD_DATA_KEY], nil)
end)

test("status reads are limited to one per 250 real milliseconds", function()
    local player=reset(true); U.Toggle(player)
    for _=1,20 do milliseconds=milliseconds+10; U.OnTick() end
    equal(calls, 1)
    U.Refresh(true); equal(calls, 1)
    milliseconds=milliseconds+50; U.OnTick(); equal(calls, 2)
    U.panel:render(); U.panel:render(); equal(calls, 2)
end)

test("old saved true cannot open the panel or change training state", function()
    local player=reset(false)
    player.data.SuQingWeightTrainingShowPanel=true
    player.data[B.MOD_DATA_KEY]={schema=1,remainderMinutes=0.625}
    U.OnGameStart(); equal(U.panel, nil); equal(U.GetPreference(player),false)
    assert(U.Toggle(player)); equal(U.GetPreference(player),true)
    assert(U.panel, "panel missing: " .. tostring(U.failed)); assert(U.panel.visible)
    assert(U.Toggle(player)); equal(U.GetPreference(player),false)
    equal(U.panel.visible, false); equal(player.data[B.MOD_DATA_KEY].remainderMinutes, 0.625)
    equal(player.data.SuQingWeightTrainingShowPanel,true)
    U.OnGameStart(); equal(U.panel, nil)
end)

test("belt context menu opens closes and reentry always hides the panel", function()
    local player=reset(true)
    local belt={getFullType=function() return B.ITEM_TYPE end}
    local other={getFullType=function() return "Base.Belt2" end}
    local context={options={}}
    function context:addOption(label,target,callback)
        local option={label=label,target=target,callback=callback}; self.options[#self.options+1]=option; return option
    end
    function context:setOptionChecked(option,value) option.checkMark=value end
    U.OnContextMenu(0,context,{other}); equal(#context.options,0)
    U.OnContextMenu(0,context,{{items={belt,belt}},belt}); equal(#context.options,1)
    local option=context.options[1]; equal(option.checkMark,false); equal(option.target,player)
    option.callback(option.target); equal(U.GetPreference(player),true); assert(U.panel.visible)
    U.OnContextMenu(0,context,{belt})
    local openOption=context.options[2]; equal(openOption.checkMark,true)
    openOption.callback(openOption.target); equal(U.GetPreference(player),false); equal(U.panel.visible,false)
    openOption.callback(openOption.target); assert(U.panel.visible)
    U.OnGameStart(); equal(U.panel,nil); equal(U.GetPreference(player),false)
    U.OnContextMenu(0,context,{belt}); equal(context.options[3].checkMark,false)
    equal(player.data.SuQingWeightTrainingShowPanel,nil)
    equal(player.data[B.MOD_DATA_KEY],nil)
end)

test("a new character does not inherit another character's open panel", function()
    local first=reset(true); U.Toggle(first); assert(U.panel.visible)
    currentPlayer={data={},belt={}}
    function currentPlayer:getModData() return self.data end
    equal(U.GetPreference(currentPlayer),false)
    U.Refresh(true); equal(U.panel.visible,false)
    equal(U.GetPreference(first),true)
end)

test("actual six XP increments distinguish max level and native zero", function()
    local s={phase="paused",reason="stopped",multiplier=20,remainderMinutes=0.5,lastMinutes=1,lastAward={
        {skill="Fitness",input=100,actual=0,reason="max-level"},
        {skill="Strength",input=100,actual=7500,reason="awarded"},
        {skill="Sprinting",input=100,actual=500,reason="awarded"},
        {skill="Sneak",input=100,actual=125,reason="awarded"},
        {skill="Nimble",input=100,actual=0,reason="native-rule"},
        {skill="Lightfoot",input=100,actual=125,reason="awarded"},
    }}
    local lines=U.BuildLines(s)
    equal(#lines,11)
    assert(contains(lines,"not moving")); assert(contains(lines,"30 game seconds"))
    assert(contains(lines,"Fitness: +0 (maximum level)")); assert(contains(lines,"Strength: +7500 (base 100)"))
    assert(contains(lines,"Nimble: +0 (native XP rule)")); assert(contains(lines,"Lightfooted: +125"))
end)

test("new default one is displayed without substituting the old default five", function()
    local lines=U.BuildLines({phase="training",reason="moving",multiplier=1,remainderMinutes=0,lastMinutes=1,
        lastAward={{skill="Strength",input=5,actual=5,reason="awarded"}}})
    equal(lines[3],"Training multiplier: x1")
    assert(contains(lines,"Strength: +5 (base 5)"))
    assert(not contains(lines,"base 25"))
end)

test("fractional point-one multiplier and half-XP input remain fractional", function()
    local lines=U.BuildLines({phase="training",reason="moving",multiplier=0.1,remainderMinutes=0,lastMinutes=1,
        lastAward={{skill="Sneak",input=0.5,actual=0.125,reason="awarded"}}})
    equal(lines[3],"Training multiplier: x0.1")
    -- Keep the existing two-decimal display. C/Lua and Java/Kahlua may round
    -- the exact half-cent tie differently, but neither may discard the fraction.
    assert(contains(lines,"Sneaking: +0.12 (base 0.5)") or contains(lines,"Sneaking: +0.13 (base 0.5)"))
    assert(not contains(lines,"base 2.5"))
end)

test("point-three-five multiplier uses detail input without another base-five multiplication", function()
    local lines=U.BuildLines({phase="training",reason="moving",multiplier=0.35,remainderMinutes=0,lastMinutes=1,
        lastAward={{skill="Nimble",input=1.75,actual=0.4375,reason="awarded"}}})
    equal(lines[3],"Training multiplier: x0.35")
    assert(contains(lines,"Nimble: +0.44 (base 1.75)"))
    assert(not contains(lines,"base 8.75"))
end)

test("missing panel API leaves Runtime available and no UI fault", function()
    local original=ISPanel; ISPanel=nil
    local player=reset(true); U.Toggle(player)
    equal(U.panel,nil); equal(U.failed,nil); assert(B.Runtime.GetStatus)
    ISPanel=original
end)

test("UI status failure is isolated and does not alter Runtime", function()
    local player=reset(true); U.Toggle(player); assert(U.panel.visible)
    local original=B.Runtime.GetStatus
    B.Runtime.GetStatus=function() error("injected UI status error") end
    milliseconds=milliseconds+250
    equal(U.OnTick(),false); assert(U.failed); equal(B.Runtime.fault,nil)
    B.Runtime.GetStatus=original
    U.OnGameStart(); equal(U.failed,nil); equal(U.panel,nil)
    U.Toggle(player); assert(U.panel.visible)
end)

function tests.run()
    for _, entry in ipairs(tests) do entry[2]() end
    print("status UI: " .. #tests .. " cases PASS")
    return #tests
end
return tests
