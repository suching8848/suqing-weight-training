local B = require "SuQingWeightTraining/Core"
local tests, count = {}, 0
local function equal(a,b) assert(a==b, tostring(a).." ~= "..tostring(b)) end
local function close(a,b) assert(math.abs(a-b)<0.000001, tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) tests[#tests+1]={name,fn} end
local function sample(overrides)
    local s={belt="belt1",eligible=true,moving=true,vehicle=false,asleep=false,dead=false,
        x=100,y=100,z=0,hour=10,stamp=1000,minutesPerDay=60}
    for k,v in pairs(overrides or {}) do s[k]=v end
    return s
end
local function pair(minutes,overrides)
    local old=sample()
    local now=sample({hour=10+minutes/60,stamp=1100,x=100.1})
    for k,v in pairs(overrides or {}) do now[k]=v end
    return old,now
end
local function observe(minutes,overrides,remainder)
    local state={schema=1,remainderMinutes=remainder or 0}
    local old,now=pair(minutes,overrides)
    local earned,reason=B.Observe(state,old,now)
    return earned,state.remainderMinutes,reason
end
test("normalised base and default multiplier",function()
    equal(B.VERSION,"0.3.2"); equal(B.BASE_XP_PER_MINUTE,5)
    SandboxVars=nil; equal(B.GetMultiplier(),1)
    SandboxVars={}; equal(B.GetMultiplier(),1)
    SandboxVars={SuQingWeightTraining={}}; equal(B.GetMultiplier(),1)
end)
test("fractional/clamped multiplier",function()
    for _,p in ipairs({{-2,0.1},{0,0.1},{0.1,0.1},{0.35,0.35},{1,1},{5.9,5.9},{20,20},{500,20}}) do
        SandboxVars={SuQingWeightTraining={XPMultiplier=p[1]}}; equal(B.GetMultiplier(),p[2])
    end
end)
test("invalid multiplier fallback",function()
    for _,v in ipairs({false,"20",{},0/0,math.huge,-math.huge}) do
        SandboxVars={SuQingWeightTraining={XPMultiplier=v}}; equal(B.GetMultiplier(),1)
    end
end)
test("new persisted state",function()
    local data={}; local p={getModData=function() return data end}
    local state=B.GetState(p); equal(state.schema,1); equal(state.remainderMinutes,0)
    state.remainderMinutes=0.4; equal(B.GetState(p),state); close(B.GetState(p).remainderMinutes,0.4)
end)
test("corrupt remainder sanitised",function()
    local data={[B.MOD_DATA_KEY]={schema=1,remainderMinutes=math.huge}}
    equal(B.GetState({getModData=function() return data end}).remainderMinutes,0)
end)
test("future schema fails closed",function()
    equal(pcall(B.GetState,{getModData=function() return {[B.MOD_DATA_KEY]={schema=2}} end}),false)
end)
test("first sample baseline",function()
    local s={remainderMinutes=0.4}; equal(B.Observe(s,nil,sample()),0); close(s.remainderMinutes,0.4)
end)
test("subminute progress",function() local n,r=observe(0.4); equal(n,0); close(r,0.4) end)
test("one minute",function() local n,r=observe(1); equal(n,1); close(r,0) end)
test("carry partial minute",function() local n,r=observe(0.6,nil,0.7); equal(n,1); close(r,0.3) end)
test("batch complete minutes",function() local n,r=observe(2.5,nil,0.8); equal(n,3); close(r,0.3) end)
test("standing cannot train",function() local n,r,why=observe(1,{x=100}); equal(n,0); equal(why,"no-displacement"); equal(r,0) end)
test("wall push cannot train",function() local n=observe(1,{x=100,moving=true}); equal(n,0) end)
test("same clock cannot train",function() local n=observe(1,{hour=10}); equal(n,0) end)
test("clock reset cannot train",function() local n=observe(1,{hour=9}); equal(n,0) end)
test("equipment transition cannot train",function() local n=observe(1,{belt="belt2"}); equal(n,0) end)
test("no belt cannot train",function()
    local old,now=pair(1); now.belt=nil; equal(B.Observe({remainderMinutes=0},old,now),0)
end)
test("vehicle/sleep/death/ineligible/stopped cannot train",function()
    for k,v in pairs({vehicle=true,asleep=true,dead=true,eligible=false,moving=false}) do
        local n=observe(1,{[k]=v}); equal(n,0)
        local old,now=pair(1); old[k]=v; equal(B.Observe({remainderMinutes=0},old,now),0)
    end
end)
test("long real gap rejected",function() local n,r,why=observe(1,{stamp=7000}); equal(n,0); equal(why,"sample-gap") end)
test("long game gap rejected",function() local n=observe(4); equal(n,0) end)
test("timestamp reversal rejected",function() local n=observe(1,{stamp=500}); equal(n,0) end)
test("teleport and floor jump rejected",function()
    local n=observe(0.04,{x=400}); equal(n,0)
    n=observe(0.04,{z=2}); equal(n,0)
end)
test("invalid sample rejected",function() local n=observe(1,{x=0/0}); equal(n,0) end)
test("changing day length rejected",function() local n=observe(1,{minutesPerDay=120}); equal(n,0) end)
test("sixfold fast forward preserved",function()
    for _,speed in ipairs({1,6}) do
        local state={remainderMinutes=0}; local old=sample(); local total=0
        for i=1,25 do
            local now=sample({hour=10+i*0.04*speed/60,stamp=1000+i*100,x=100+i*0.1*speed})
            local n=B.Observe(state,old,now); total=total+n; old=now
        end
        equal(total,speed); close(state.remainderMinutes,0)
    end
end)
test("longer day follows game clock",function()
    local state={remainderMinutes=0}
    local old=sample({minutesPerDay=120})
    local now=sample({minutesPerDay=120,hour=10+1/60,stamp=6000,x=101})
    equal(B.Observe(state,old,now),1)
end)
test("native XP once per six skills",function()
    Perks={}; for _,name in ipairs(B.SKILLS) do Perks[name]=name end
    local calls,totals={},{}; local xp={getXP=function(_,perk) return totals[perk] or 0 end,
        AddXP=function(_,perk,amount,...)
        equal(select('#',...),0); calls[#calls+1]={perk,amount}
        totals[perk]=(totals[perk] or 0)+amount
    end}
    local p={getXp=function() return xp end,getPerkLevel=function() return 4 end}
    local attempted,detail=B.Grant(p,1,5)
    equal(attempted,6); equal(#calls,6); equal(#detail,6)
    for _,call in ipairs(calls) do equal(call[2],25) end
    for _,row in ipairs(detail) do
        equal(row.input,25); equal(row.actual,25); equal(row.reason,"awarded")
    end
end)
test("max skills skipped",function()
    local count,totals=0,{}; local p={getXp=function() return {
        getXP=function(_,perk) return totals[perk] or 0 end,
        AddXP=function(_,perk,n) count=count+1; totals[perk]=(totals[perk] or 0)+n end} end,
        getPerkLevel=function(_,perk) if perk==Perks.Fitness or perk==Perks.Strength then return 10 end return 4 end}
    local attempted,detail=B.Grant(p,1,5)
    equal(attempted,4); equal(count,4); equal(#detail,6)
    local skipped=0
    for _,row in ipairs(detail) do
        if row.skill=="Fitness" or row.skill=="Strength" then
            equal(row.reason,"max-level"); equal(row.actual,0); skipped=skipped+1
        end
    end
    equal(skipped,2)
end)
test("award details report observed native XP rather than raw inputs",function()
    local totals={}; local xp={getXP=function(_,perk) return totals[perk] or 100 end,
        AddXP=function(_,perk,n) totals[perk]=(totals[perk] or 100)+n*7 end}
    local p={getXp=function() return xp end,getPerkLevel=function() return 4 end}
    local attempted,detail=B.Grant(p,1,20)
    equal(attempted,6); equal(#detail,6)
    for _,row in ipairs(detail) do
        equal(row.input,100); equal(row.actual,700); equal(row.reason,"awarded")
    end
end)
test("native rules can block a grant without a false success amount",function()
    local totals={}; local xp={getXP=function(_,perk) return totals[perk] or 0 end,
        AddXP=function(_,perk,n)
            if perk~=Perks.Fitness then totals[perk]=(totals[perk] or 0)+n end
        end}
    local p={getXp=function() return xp end,getPerkLevel=function() return 4 end}
    local attempted,detail=B.Grant(p,1,5)
    equal(attempted,6)
    for _,row in ipairs(detail) do
        if row.skill=="Fitness" then equal(row.actual,0); equal(row.reason,"native-rule")
        else equal(row.actual,25); equal(row.reason,"awarded") end
    end
end)
test("fractional rates retain raw XP precision",function()
    for _,case in ipairs({{0.1,0.5},{0.35,1.75},{1,5},{20,100}}) do
        local calls,totals={},{}
        local xp={getXP=function(_,perk) return totals[perk] or 0 end,
            AddXP=function(_,perk,input,...)
                equal(select('#',...),0); calls[#calls+1]=input
                totals[perk]=(totals[perk] or 0)+input
            end}
        local p={getXp=function() return xp end,getPerkLevel=function() return 4 end}
        local attempted,detail=B.Grant(p,1,case[1])
        equal(attempted,6); equal(#calls,6)
        for _,input in ipairs(calls) do close(input,case[2]) end
        for _,row in ipairs(detail) do close(row.input,case[2]); close(row.actual,case[2]) end
    end
end)
test("new one four and twenty match old five twenty and one hundred",function()
    for _,case in ipairs({{1,5},{4,20},{20,100}}) do
        SandboxVars={SuQingWeightTraining={XPMultiplier=case[1]}}
        local totals={}
        local xp={getXP=function(_,perk) return totals[perk] or 0 end,
            AddXP=function(_,perk,input) totals[perk]=(totals[perk] or 0)+input end}
        local p={getXp=function() return xp end,getPerkLevel=function() return 4 end}
        local attempted,detail=B.Grant(p,1)
        equal(attempted,6); equal(SandboxVars.SuQingWeightTraining.XPMultiplier,case[1])
        for _,row in ipairs(detail) do equal(row.input,case[2]); equal(row.actual,case[2]) end
    end
end)
test("invalid explicit rates fail before native calls",function()
    local calls=0
    local p={getXp=function() calls=calls+1; error("must not reach native XP") end}
    for _,value in ipairs({-1,0,0.099,20.001,"1",{},0/0,math.huge,-math.huge}) do
        equal(pcall(B.Grant,p,1,value),false)
    end
    equal(calls,0)
end)
test("invalid/replayed fraction not granted",function()
    for _,value in ipairs({0,-1,0.5,"1",{},0/0,math.huge,-math.huge}) do
        equal(B.Grant({},value,0.35),0)
    end
end)
function tests.run()
    for _,t in ipairs(tests) do t[2](); count=count+1 end
    print("core: "..count.." cases PASS")
    return count
end
return tests
