-- Cold-start integration: real registries, Items, Runtime and Bootstrap.
-- Native game objects are fixtures; no Java/ZombieBuddy bridge is provided.
local function run()
    local saved = {
        Perks=Perks, SandboxVars=SandboxVars, getGameTime=getGameTime,
        getTimestampMs=getTimestampMs, getPlayer=getPlayer, isClient=isClient,
        isServer=isServer, Events=Events, ResourceLocation=ResourceLocation,
        ItemBodyLocation=ItemBodyLocation, BodyLocations=BodyLocations,
        SuQingWeightTraining=SuQingWeightTraining, print=print, require=require,
        suqingWeightTrainingJavaReady=suqingWeightTrainingJavaReady,
        suqingWeightTrainingJavaFault=suqingWeightTrainingJavaFault,
        suqingWeightTrainingMovementEligible=suqingWeightTrainingMovementEligible,
        ZombieBuddy=ZombieBuddy,
    }
    local moduleNames={"SuQingWeightTraining/Core","SuQingWeightTraining/Items",
        "SuQingWeightTraining/Runtime","SuQingWeightTraining/StatusUI","NPCs/BodyLocations"}
    local savedModules={}
    for _,name in ipairs(moduleNames) do savedModules[name]=package.loaded[name] end
    local B,passed=nil,0
    local BOOTSTRAP="SuQingWeightTraining/42/media/lua/client/SuQingWeightTraining_Bootstrap.lua"
    local function equal(actual,expected,label)
        assert(actual==expected,(label or "value")..": "..tostring(actual).." ~= "..tostring(expected))
    end
    local function close(actual,expected,label)
        assert(math.abs(actual-expected)<0.000001,
            (label or "value")..": "..tostring(actual).." ~= "..tostring(expected))
    end
    local function list(values)
        return {size=function() return #values end,get=function(_,i) return values[i+1] end}
    end

    local function fixture(options)
        options=options or {}
        local f={clock={hour=10,stamp=1000,day=60},logs={},events={},uiCalls=0}
        print=function(...)
            local parts={}
            for i=1,select("#",...) do parts[i]=tostring(select(i,...)) end
            f.logs[#f.logs+1]=table.concat(parts," ")
        end
        isClient,isServer=function() return false end,function() return false end
        suqingWeightTrainingJavaReady=nil
        suqingWeightTrainingJavaFault=nil
        suqingWeightTrainingMovementEligible=nil
        ZombieBuddy=nil
        SandboxVars={SuQingWeightTraining={XPMultiplier=options.multiplier or 1}}
        getGameTime=function() return {
            getWorldAgeHours=function() return f.clock.hour end,
            getMinutesPerDay=function() return f.clock.day end,
        } end
        getTimestampMs=function() return f.clock.stamp end
        Events=setmetatable({}, {__index=function(self,name)
            local handlers={}
            f.events[name]=handlers
            local event={Add=function(handler) handlers[#handlers+1]=handler end,
                Remove=function(handler)
                    for i=#handlers,1,-1 do if handlers[i]==handler then table.remove(handlers,i) end end
                end}
            rawset(self,name,event)
            return event
        end})
        local registered={}
        ResourceLocation={of=function(id) return id end}
        ItemBodyLocation={get=function(id) return registered[id] end,
            register=function(id) registered[id]={id=id}; return registered[id] end}
        BodyLocations={getGroup=function() return {getOrCreateLocation=function(_,location) return location end} end}
        package.loaded["NPCs/BodyLocations"]=true
        dofile("SuQingWeightTraining/42/media/registries.lua")
        package.loaded["SuQingWeightTraining/Items"]=nil
        require "SuQingWeightTraining/Items"

        local belt={weight=10,data={}}
        function belt:getFullType() return B.ITEM_TYPE end
        function belt:getModData() return self.data end
        function belt:getActualWeight() return self.weight end
        function belt:getWeight() return self.weight end
        function belt:setActualWeight(value) self.weight=value end
        function belt:setWeight(value) self.weight=value end
        function belt:setCustomWeight() end
        function belt:getInventory() return nil end
        function belt:getScriptItem() return {getActualWeight=function() return 10 end} end
        function belt:syncItemFields() end
        local p={worn=belt,inventoryItems={belt},moving=true,vehicle=nil,asleep=false,dead=false,
            x=100,y=100,z=0,data={},awards={},calls=0,levels={},nativeFactor=options.nativeFactor or 1}
        function p:isLocalPlayer() return not self.remote end
        function p:isPlayerMoving() return self.moving end
        function p:getVehicle() return self.vehicle end
        function p:isAsleep() return self.asleep end
        function p:isDead() return self.dead end
        function p:isClimbing() return self.climbing or false end
        function p:isOnFloor() return self.prone or false end
        function p:isGrappling() return self.grappling or false end
        function p:isBeingGrappled() return self.grappled or false end
        function p:getX() return self.x end
        function p:getY() return self.y end
        function p:getZ() return self.z end
        function p:getModData() return self.data end
        function p:getPerkLevel(perk) return self.levels[perk] or 4 end
        function p:getWornItem(location)
            if location==registered["suqingweighttraining:suqingtrainingbelt"] then return self.worn end
        end
        function p:getWornItems()
            local values={}
            if self.worn then values[1]={getItem=function() return self.worn end} end
            return list(values)
        end
        function p:getInventory() return {getItems=function() return list(self.inventoryItems) end} end
        local xp={}
        function xp:getXP(perk) return p.awards[perk] or 0 end
        function xp:AddXP(perk,input,...)
            equal(select("#",...),0,"Runtime must use ordinary native AddXP")
            p.calls=p.calls+1
            if p.failNative then error("fixture native failure") end
            if p.blockedSkill~=perk then
                p.awards[perk]=(p.awards[perk] or 0)+input*p.nativeFactor
            end
        end
        function p:getXp() return xp end
        f.player,f.belt=p,belt
        getPlayer=function() return f.player end
        package.loaded["SuQingWeightTraining/Runtime"]=nil
        package.loaded["SuQingWeightTraining/StatusUI"]={Install=function()
            f.uiCalls=f.uiCalls+1
            if options.uiInstallError then error("fixture optional UI install failure") end
        end}
        local realRequire=saved.require
        require=function(name)
            if options.uiRequireError and name=="SuQingWeightTraining/StatusUI" then
                error("fixture optional UI load failure")
            end
            return realRequire(name)
        end
        local loaded,loadError=pcall(dofile,BOOTSTRAP)
        require=realRequire
        if not loaded then error(loadError,0) end
        f.R=B.Runtime
        function f.fire(name,...)
            local handlers=f.events[name] or {}
            for _,handler in ipairs(handlers) do handler(...) end
        end
        function f.start()
            assert(f.events.OnGameStart and #f.events.OnGameStart==1,"Bootstrap did not register real OnGameStart")
            assert(f.events.OnPlayerUpdate and #f.events.OnPlayerUpdate==1,"Bootstrap did not register real OnPlayerUpdate")
            f.fire("OnGameStart")
            f.fire("OnPlayerUpdate",p)
        end
        function f.advance(minutes,distance,target)
            target=target or p
            f.clock.hour=f.clock.hour+minutes/60
            f.clock.stamp=f.clock.stamp+minutes*f.clock.day/24*1000
            target.x=target.x+(distance or 0.1)
            f.fire("OnPlayerUpdate",target)
        end
        function f.walk(minutes,target)
            local remaining=minutes
            while remaining>0.000000001 do
                local step=math.min(0.04,remaining)
                f.advance(step,step*2.5,target)
                remaining=remaining-step
            end
        end
        function f.status() return f.R.GetStatus(p) end
        return f
    end

    local function test(name,callback)
        callback()
        passed=passed+1
        saved.print("PASS weight pure-Lua startup: "..name)
    end
    local ok,err=pcall(function()
        Perks={Fitness="Fitness",Strength="Strength",Sprinting="Sprinting",Sneak="Sneak",Nimble="Nimble",Lightfoot="Lightfoot"}
        SuQingWeightTraining=nil
        package.loaded["SuQingWeightTraining/Core"]=nil
        B=require "SuQingWeightTraining/Core"
        equal(B.VERSION,"0.3.2","pure-Lua version")
        equal(B.BASE_XP_PER_MINUTE,5,"normalised base XP")

        test("real Bootstrap works without Java or ZombieBuddy globals",function()
            local f=fixture({multiplier=20,nativeFactor=2})
            equal(suqingWeightTrainingJavaReady,nil); equal(suqingWeightTrainingMovementEligible,nil)
            equal(suqingWeightTrainingJavaFault,nil); equal(ZombieBuddy,nil)
            f.start(); f.walk(0.6)
            equal(f.player.calls,0,"partial minute must not award XP")
            close(f.status().remainderMinutes,0.6)
            equal(f.status().phase,"training"); equal(f.status().multiplier,20)
            f.walk(0.4)
            for _,name in ipairs(B.SKILLS) do equal(f.player.awards[name],200,name) end
            equal(f.player.calls,6); equal(f.status().lastMinutes,1)
            equal(#f.status().lastAward,6); equal(f.status().fault,nil)
            for _,row in ipairs(f.status().lastAward) do
                equal(row.input,100); equal(row.actual,200); equal(row.reason,"awarded")
            end
            equal(SandboxVars.SuQingWeightTraining.XPMultiplier,20,"saved multiplier retained")
            equal(#(f.events.AddXP or {}),0,"new weight mod must not subscribe to AddXP")
        end)
        test("real callbacks retain fractional settings and unchanged whole-minute timing",function()
            for _,case in ipairs({{0.1,0.5},{0.35,1.75},{1,5},{4,20},{20,100}}) do
                local f=fixture({multiplier=case[1]})
                f.start(); f.walk(0.6)
                equal(f.player.calls,0); close(f.status().remainderMinutes,0.6)
                equal(f.status().multiplier,case[1])
                f.walk(0.4)
                equal(f.player.calls,6); equal(f.status().lastMinutes,1)
                for _,name in ipairs(B.SKILLS) do close(f.player.awards[name],case[2],name) end
                for _,row in ipairs(f.status().lastAward) do
                    close(row.input,case[2]); close(row.actual,case[2]); equal(row.reason,"awarded")
                end
                equal(SandboxVars.SuQingWeightTraining.XPMultiplier,case[1],"setting must not be rescaled")
                close(f.status().remainderMinutes,0)
            end
        end)
        test("missing saved option uses new one without touching saved progress",function()
            local f=fixture()
            SandboxVars.SuQingWeightTraining.XPMultiplier=nil
            f.player.data[B.MOD_DATA_KEY]={schema=1,remainderMinutes=0.6}
            f.start(); f.walk(0.4)
            equal(f.status().multiplier,1); equal(f.player.calls,6)
            equal(f.player.data[B.MOD_DATA_KEY].schema,1)
            close(f.status().remainderMinutes,0)
            for _,row in ipairs(f.status().lastAward) do equal(row.input,5); equal(row.actual,5) end
            equal(SandboxVars.SuQingWeightTraining.XPMultiplier,nil,"fallback must not rewrite sandbox data")
        end)
        test("optional UI require failure cannot block registered XP callbacks",function()
            local f=fixture({uiRequireError=true}); f.start(); f.walk(1)
            equal(f.player.calls,6); equal(f.status().phase,"training"); equal(f.status().fault,nil)
        end)
        test("optional UI installation failure cannot block XP",function()
            local f=fixture({uiInstallError=true}); f.start(); f.walk(1)
            equal(f.uiCalls,1); equal(f.player.calls,6); equal(f.status().fault,nil)
        end)
        test("schema-one remainder survives reload without offline credit",function()
            local f=fixture(); f.start(); f.walk(0.6)
            equal(f.player.data[B.MOD_DATA_KEY].schema,1)
            close(f.player.data[B.MOD_DATA_KEY].remainderMinutes,0.6)
            f.clock.hour=f.clock.hour+100; f.clock.stamp=f.clock.stamp+100000
            f.start(); equal(f.player.calls,0)
            close(f.status().remainderMinutes,0.6)
            f.walk(0.4); equal(f.player.calls,6)
            close(f.status().remainderMinutes,0)
        end)
        test("inventory or hand ownership does not count as wearing",function()
            local f=fixture(); f.player.worn=nil; f.player.primaryHand=f.belt
            f.start(); f.walk(1)
            equal(f.player.calls,0); equal(f.status().phase,"inactive"); equal(f.status().reason,"not-worn")
        end)
        test("remove and rewear transitions preserve only earned remainder",function()
            local f=fixture(); f.start(); f.walk(0.6)
            f.player.worn=nil; f.walk(1)
            equal(f.status().phase,"inactive"); close(f.status().remainderMinutes,0.6)
            f.player.worn=f.belt; f.fire("OnPlayerUpdate",f.player)
            equal(f.player.calls,0); f.walk(0.4); equal(f.player.calls,6)
        end)
        test("paused world clock and wall pushing earn nothing",function()
            local f=fixture(); f.start()
            f.advance(0,0.1)
            equal(f.status().phase,"paused"); equal(f.status().reason,"clock-idle-or-reset")
            f.advance(1,0)
            equal(f.player.calls,0); equal(f.status().reason,"no-displacement")
            close(f.status().remainderMinutes,0)
        end)
        test("vehicle movement and exit transition are excluded",function()
            local f=fixture(); f.start(); f.player.vehicle={}; f.walk(1)
            equal(f.player.calls,0); equal(f.status().reason,"vehicle")
            f.player.vehicle=nil; f.fire("OnPlayerUpdate",f.player)
            equal(f.player.calls,0); f.walk(1); equal(f.player.calls,6)
        end)
        test("climbing prone grapple sleep and death cannot train",function()
            for _,field in ipairs({"climbing","prone","grappling","grappled","asleep","dead"}) do
                local f=fixture(); f.player[field]=true; f.start(); f.walk(1)
                equal(f.player.calls,0,field); equal(f.status().phase,"paused",field)
            end
        end)
        test("optional activity APIs may be absent without becoming a hard gate",function()
            local f=fixture()
            f.player.isClimbing=nil; f.player.isOnFloor=nil; f.player.isGrappling=nil; f.player.isBeingGrappled=nil
            f.start(); f.walk(1); equal(f.player.calls,6); equal(f.status().fault,nil)
        end)
        test("teleport or long callback gaps reset the sampling baseline",function()
            local f=fixture(); f.start(); f.advance(0.04,500)
            equal(f.status().reason,"position-jump"); equal(f.player.calls,0)
            f.clock.stamp=f.clock.stamp+6000; f.advance(0.04,0.1)
            equal(f.status().reason,"sample-gap"); equal(f.player.calls,0)
            f.walk(1); equal(f.player.calls,6)
        end)
        test("remote player callbacks cannot create training state",function()
            local f=fixture(); f.player.remote=true; f.start(); f.walk(1)
            equal(f.player.calls,0); equal(f.player.data[B.MOD_DATA_KEY],nil)
        end)
        test("native failure is latched per player and is never replayed",function()
            local f=fixture(); f.player.failNative=true; f.start(); f.walk(1)
            assert(f.status().fault); equal(f.status().phase,"fault"); equal(f.player.calls,1)
            f.player.failNative=false; f.walk(1); equal(f.player.calls,1)
            close(f.status().remainderMinutes,0)
            f.start(); f.walk(1); equal(f.player.calls,7); equal(f.status().fault,nil)
        end)
        test("optional migration is called but cannot prevent XP on failure",function()
            local f=fixture(); local migrate=B.MigrateInventory; local calls=0
            B.MigrateInventory=function(player)
                equal(player,f.player); calls=calls+1; error("fixture optional migration failure")
            end
            f.start(); f.walk(1)
            equal(calls,1); equal(f.player.calls,6); equal(f.status().fault,nil)
            B.MigrateInventory=migrate
        end)
        test("absence of a migration helper is not a training dependency",function()
            local f=fixture(); local migrate=B.MigrateInventory
            B.MigrateInventory=nil
            f.start(); f.walk(1); equal(f.player.calls,6)
            B.MigrateInventory=migrate
        end)
        test("native-rule and max-level results are visible in lastAward",function()
            local f=fixture(); f.player.blockedSkill=Perks.Fitness; f.player.levels[Perks.Strength]=10
            f.start(); f.walk(1)
            equal(f.player.calls,5)
            for _,row in ipairs(f.status().lastAward) do
                if row.skill=="Fitness" then equal(row.actual,0); equal(row.reason,"native-rule")
                elseif row.skill=="Strength" then equal(row.actual,0); equal(row.reason,"max-level") end
            end
        end)
    end)

    Perks,SandboxVars,getGameTime=saved.Perks,saved.SandboxVars,saved.getGameTime
    getTimestampMs,getPlayer,isClient,isServer=saved.getTimestampMs,saved.getPlayer,saved.isClient,saved.isServer
    Events,ResourceLocation,ItemBodyLocation,BodyLocations=saved.Events,saved.ResourceLocation,saved.ItemBodyLocation,saved.BodyLocations
    SuQingWeightTraining=saved.SuQingWeightTraining
    suqingWeightTrainingJavaReady=saved.suqingWeightTrainingJavaReady
    suqingWeightTrainingJavaFault=saved.suqingWeightTrainingJavaFault
    suqingWeightTrainingMovementEligible=saved.suqingWeightTrainingMovementEligible
    ZombieBuddy=saved.ZombieBuddy
    print,require=saved.print,saved.require
    for _,name in ipairs(moduleNames) do package.loaded[name]=savedModules[name] end
    if not ok then error(err,0) end
    return passed
end

return {run=run}
