-- Native-XP model plus the actual weight-training Core and optional existing
-- protein-boost Core/XP modules. No game save or enabled list is accessed.
-- The Python runner supplies module paths and WEIGHT_PROTEIN_TEST_AVAILABLE.
local function run()
    local moduleNames = {
        "SuQingWeightTraining/Core",
        "SuQingProteinTrainingBoost/Core",
        "SuQingProteinTrainingBoost/XP",
    }
    local saved = {
        Perks = Perks, SandboxVars = SandboxVars, getGameTime = getGameTime,
        isClient = isClient, isServer = isServer, Events = Events,
        addXpNoMultiplier = addXpNoMultiplier,
        SuQingWeightTraining = SuQingWeightTraining,
        SuQingProteinTrainingBoost = SuQingProteinTrainingBoost,
        modules = {},
    }
    for _, name in ipairs(moduleNames) do saved.modules[name] = package.loaded[name] end
    local passed, now, handlers = 0, 100, {}
    local MAXIMUM = 487500
    local names = { "Fitness", "Strength", "Sprinting", "Sneak", "Nimble", "Lightfoot" }
    local B, protein

    local function near(actual, expected, label)
        assert(math.abs(actual - expected) < 0.00001,
            (label or "XP") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end

    local function fitnessAllowed(player)
        -- This follows the installed Nutrition.canAddFitnessXp path. It is a
        -- trait gate, not a guessed threshold on the displayed kilograms.
        local traits = player.traits
        local severe = traits.EMACIATED or traits.OBESE or traits.VERY_UNDERWEIGHT
        local weightTrouble = severe or traits.OVERWEIGHT
        local level = player.levels[Perks.Fitness] or 0
        if level >= 9 and weightTrouble then return false end
        if level >= 6 and severe then return false end
        return true
    end

    local function proteinFactor(player, skill)
        if skill ~= Perks.Strength then return 1 end
        if player.proteins > 50 and player.proteins < 300 then return 1.5 end
        if player.proteins < -300 then return 0.7 end
        return 1
    end

    local function initialSkillFactor(player, skill)
        local passive = skill == Perks.Fitness or skill == Perks.Strength
        local excludedReduction = passive or skill == Perks.Sprinting
        local boost = player.boosts[skill]
        local factor = 1
        if boost == nil or boost == 0 then
            if not excludedReduction then factor = 0.25 end
        elseif boost == 1 then
            if skill == Perks.Sprinting then factor = 1.25 end
        elseif boost == 2 then
            if not passive then factor = 1.33 end
        elseif boost >= 3 and not passive then
            factor = 1.66
        end
        if player.traits.FAST_LEARNER and not passive then factor = factor * 1.3 end
        if player.traits.SLOW_LEARNER and not excludedReduction then factor = factor * 0.7 end
        return factor
    end

    local function newPlayer(proteins)
        local p = {
            proteins = proteins or 0, totals = {}, calls = {}, primary = {}, events = {},
            levels = {}, traits = {}, boosts = {}, books = {}, global = 5, useGlobal = true,
            individual = {}, data = { strengthUpTimer = 20000, fitnessUpTimer = 18000,
                strengthMod = 7, fitnessMod = 8 },
        }
        p.levels[Perks.Fitness], p.levels[Perks.Strength] = 8, 9
        local xp = {}
        function p:getModData() return self.data end
        function p:getXp() return xp end
        function p:getPerkLevel(skill) return self.levels[skill] or 0 end
        function p:isDead() return false end
        function p:getNutrition()
            return { getProteins = function() return p.proteins end,
                canAddFitnessXp = function() return fitnessAllowed(p) end }
        end
        function xp:getXP(skill) return p.totals[skill] or 0 end
        function xp:AddXP(skill, amount, ...)
            local extraCount = select("#", ...)
            local callLua, doBoost = ...
            p.calls[#p.calls + 1] = { skill = skill, input = amount, extraCount = extraCount,
                callLua = callLua, doBoost = doBoost }
            if extraCount == 0 then
                p.primary[#p.primary + 1] = { skill = skill, input = amount }
            else
                assert(extraCount == 4 and callLua == false and doBoost == false,
                    "unexpected supplemental native AddXP signature")
            end

            if skill == Perks.Fitness and not fitnessAllowed(p) then return end
            -- Nutrition runs even when doBoost=false, like the installed class.
            amount = amount * proteinFactor(p, skill)
            local before = self:getXP(skill)
            if amount >= 0 and before >= MAXIMUM then return end
            if doBoost ~= false then
                amount = amount * initialSkillFactor(p, skill)
                local book = p.books[skill] or 1
                if book > 1 then amount = amount * book end
                amount = amount * (p.useGlobal and p.global or (p.individual[skill] or 1))
            end
            local after = math.max(0, math.min(MAXIMUM, before + amount))
            p.totals[skill] = after
            amount = after - before

            -- The native method commits XP before Events.AddXP, and still
            -- emits the event when callLua=false. Do not suppress recursion in
            -- this model: the actual protein module must handle its own lock.
            p.events[skill] = (p.events[skill] or 0) + 1
            if amount > 0 and skill == Perks.Strength then
                p.data.strengthUpTimer = math.max(-50000, p.data.strengthUpTimer - 3000)
            elseif amount > 0 and skill == Perks.Fitness then
                p.data.fitnessUpTimer = math.max(-50000, p.data.fitnessUpTimer - 3000)
            end
            for _, handler in ipairs(handlers) do handler(p, skill, amount) end
        end
        return p
    end

    local function assertPrimary(p, count, amount)
        assert(#p.primary == count, "unexpected number of ordinary AddXP grants")
        for _, call in ipairs(p.primary) do near(call.input, amount, "raw weight-training input") end
    end

    local function test(name, callback)
        callback()
        passed = passed + 1
        print("PASS weight native XP: " .. name)
    end

    local ok, err = pcall(function()
        Perks = {}
        for _, name in ipairs(names) do
            local id = name
            Perks[id] = {
                getId = function() return id end,
                getName = function() return id end,
                getTotalXpForLevel = function() return MAXIMUM end,
            }
        end
        SandboxVars = { SuQingWeightTraining = { XPMultiplier = 1 } }
        getGameTime = function() return { getWorldAgeHours = function() return now end } end
        isClient, isServer = function() return false end, function() return false end
        Events = { AddXP = {
            Add = function(handler) handlers[#handlers + 1] = handler end,
            Remove = function(handler)
                for i = #handlers, 1, -1 do if handlers[i] == handler then table.remove(handlers, i) end end
            end,
        } }
        addXpNoMultiplier = function(player, skill, amount)
            return player:getXp():AddXP(skill, amount, false, false, false, false)
        end
        SuQingWeightTraining = nil
        package.loaded[moduleNames[1]] = nil
        B = require "SuQingWeightTraining/Core"
        assert(#handlers == 0, "weight-training Core installed an AddXP after-listener")

        test("six raw grants retain native initial-skill factors and global five", function()
            local p = newPlayer()
            assert(B.Grant(p, 1, 5) == 6)
            assertPrimary(p, 6, 25)
            near(p:getXp():getXP(Perks.Fitness), 125)
            near(p:getXp():getXP(Perks.Strength), 125)
            near(p:getXp():getXP(Perks.Sprinting), 125, "Sprinting is excluded from zero-skill reduction")
            for _, name in ipairs({ "Sneak", "Nimble", "Lightfoot" }) do
                near(p:getXp():getXP(Perks[name]), 31.25, name .. " native zero-skill reduction")
            end
        end)

        test("normalised one retains old five while fractional rates reach native XP intact", function()
            for _, case in ipairs({ { 0.1, 0.5, 2.5, 0.625 }, { 0.35, 1.75, 8.75, 2.1875 },
                { 1, 5, 25, 6.25 }, { 4, 20, 100, 25 }, { 20, 100, 500, 125 } }) do
                local p = newPlayer()
                SandboxVars.SuQingWeightTraining.XPMultiplier = case[1]
                local attempted, detail = B.Grant(p, 1)
                assert(attempted == 6 and #detail == 6)
                assertPrimary(p, 6, case[2])
                near(p:getXp():getXP(Perks.Fitness), case[3])
                near(p:getXp():getXP(Perks.Sprinting), case[3])
                near(p:getXp():getXP(Perks.Sneak), case[4])
                for _, row in ipairs(detail) do near(row.input, case[2]) end
                assert(SandboxVars.SuQingWeightTraining.XPMultiplier == case[1])
            end
            SandboxVars.SuQingWeightTraining.XPMultiplier = 1
        end)

        test("normal nutrition boosts Strength but never Fitness", function()
            local p = newPlayer(100)
            B.Grant(p, 1, 5)
            near(p:getXp():getXP(Perks.Strength), 187.5)
            near(p:getXp():getXP(Perks.Fitness), 125)
        end)

        test("saved multiplier twenty stays twenty and now supplies one hundred raw XP", function()
            local p = newPlayer()
            SandboxVars.SuQingWeightTraining.XPMultiplier = 20
            local attempted, detail = B.Grant(p, 1)
            assert(attempted == 6 and #detail == 6)
            assertPrimary(p, 6, 100)
            near(p:getXp():getXP(Perks.Fitness), 500)
            near(p:getXp():getXP(Perks.Strength), 500)
            assert(SandboxVars.SuQingWeightTraining.XPMultiplier == 20)
            SandboxVars.SuQingWeightTraining.XPMultiplier = 1
        end)

        test("independent sandbox values replace rather than multiply global", function()
            local p = newPlayer()
            p.useGlobal, p.global = false, 99
            for i, name in ipairs(names) do p.individual[Perks[name]] = i + 1 end
            B.Grant(p, 1, 5)
            near(p:getXp():getXP(Perks.Fitness), 50)
            near(p:getXp():getXP(Perks.Strength), 75)
            near(p:getXp():getXP(Perks.Sprinting), 100)
            near(p:getXp():getXP(Perks.Sneak), 31.25)
            near(p:getXp():getXP(Perks.Nimble), 37.5)
            near(p:getXp():getXP(Perks.Lightfoot), 43.75)
        end)

        test("descriptor, book, and Fast Learner factors remain native", function()
            local p = newPlayer()
            p.boosts[Perks.Sneak], p.books[Perks.Sneak] = 2, 3
            p.traits.FAST_LEARNER = true
            B.Grant(p, 1, 5)
            near(p:getXp():getXP(Perks.Sneak), 25 * 1.33 * 1.3 * 3 * 5)
            near(p:getXp():getXP(Perks.Strength), 125, "passive Fast Learner exclusion")
            near(p:getXp():getXP(Perks.Sprinting), 162.5)
        end)

        test("level-ten skills are skipped before calling the native API", function()
            local p = newPlayer()
            p.levels[Perks.Fitness], p.levels[Perks.Strength] = 10, 10
            assert(B.Grant(p, 1, 5) == 4)
            assertPrimary(p, 4, 25)
            for _, call in ipairs(p.calls) do
                assert(call.skill ~= Perks.Fitness and call.skill ~= Perks.Strength)
            end
            for _, name in ipairs(names) do p.levels[Perks[name]] = 10 end
            local previous = #p.calls
            assert(B.Grant(p, 1, 5) == 0 and #p.calls == previous)
        end)

        test("accumulated whole minutes scale only the raw award", function()
            local p = newPlayer()
            B.Grant(p, 3, 5)
            assertPrimary(p, 6, 75)
            near(p:getXp():getXP(Perks.Fitness), 375)
            near(p:getXp():getXP(Perks.Sneak), 93.75)
        end)

        test("fitness trait gates at six and nine are not bypassed", function()
            for _, case in ipairs({ { 5, "OBESE", true }, { 6, "OBESE", false },
                { 8, "OVERWEIGHT", true }, { 9, "OVERWEIGHT", false } }) do
                local p = newPlayer()
                p.levels[Perks.Fitness], p.traits[case[2]] = case[1], true
                B.Grant(p, 1, 5)
                near(p:getXp():getXP(Perks.Fitness), case[3] and 125 or 0)
                assertPrimary(p, 6, 25)
            end
        end)

        if WEIGHT_PROTEIN_TEST_AVAILABLE then
            SuQingProteinTrainingBoost = nil
            package.loaded[moduleNames[2]], package.loaded[moduleNames[3]] = nil, nil
            protein = require "SuQingProteinTrainingBoost/Core"
            local XP = require "SuQingProteinTrainingBoost/XP"
            assert(XP.Install())
            assert(#handlers == 1, "expected only the existing protein XP listener")

            test("actual protein bridge multiplies only the two passive awards once", function()
                local p = newPlayer(100)
                assert(protein.AddDose(p, 0.5))
                local attempted, detail = B.Grant(p, 1, 5)
                assert(attempted == 6 and #detail == 6)
                assertPrimary(p, 6, 25)
                assert(#p.calls == 8, "protein bridge recursively or repeatedly supplemented XP")
                near(p:getXp():getXP(Perks.Fitness), 1250)
                near(p:getXp():getXP(Perks.Strength), 1875)
                near(p:getXp():getXP(Perks.Sprinting), 125)
                near(p:getXp():getXP(Perks.Nimble), 31.25)
                assert(p.data.strengthUpTimer == 17000 and p.data.fitnessUpTimer == 15000,
                    "protein supplementation repeated the native training-decay timer update")
                assert(p.data.strengthMod == 7 and p.data.fitnessMod == 8)
                assert(#handlers == 1)
                for _, row in ipairs(detail) do
                    assert(row.input == 25 and row.reason == "awarded")
                    if row.skill == "Fitness" then near(row.actual, 1250)
                    elseif row.skill == "Strength" then near(row.actual, 1875) end
                end
            end)

            test("multiplier twenty and actual protein bridge expose final observed award details", function()
                local p = newPlayer(100)
                SandboxVars.SuQingWeightTraining.XPMultiplier = 20
                assert(protein.AddDose(p, 0.5))
                local attempted, detail = B.Grant(p, 1)
                assert(attempted == 6 and #detail == 6)
                assertPrimary(p, 6, 100)
                assert(#p.calls == 8 and #handlers == 1)
                for _, row in ipairs(detail) do
                    assert(row.input == 100 and row.reason == "awarded")
                    if row.skill == "Fitness" then near(row.actual, 5000)
                    elseif row.skill == "Strength" then near(row.actual, 7500) end
                end
                near(p:getXp():getXP(Perks.Fitness), 5000)
                near(p:getXp():getXP(Perks.Strength), 7500)
                assert(SandboxVars.SuQingWeightTraining.XPMultiplier == 20)
                SandboxVars.SuQingWeightTraining.XPMultiplier = 1
            end)

            test("fractional and default rates receive the actual protein bonus exactly once", function()
                for _, case in ipairs({ { 0.1, 0.5, 25, 37.5, 0.625 },
                    { 0.35, 1.75, 87.5, 131.25, 2.1875 }, { 1, 5, 250, 375, 6.25 } }) do
                    local p = newPlayer(100)
                    assert(protein.AddDose(p, 0.5))
                    local attempted, detail = B.Grant(p, 1, case[1])
                    assert(attempted == 6 and #p.calls == 8 and #handlers == 1)
                    assertPrimary(p, 6, case[2])
                    near(p:getXp():getXP(Perks.Fitness), case[3])
                    near(p:getXp():getXP(Perks.Strength), case[4])
                    near(p:getXp():getXP(Perks.Nimble), case[5])
                    for _, row in ipairs(detail) do
                        near(row.input, case[2])
                        if row.skill == "Fitness" then near(row.actual, case[3])
                        elseif row.skill == "Strength" then near(row.actual, case[4]) end
                    end
                    assert(p.data.strengthUpTimer == 17000 and p.data.fitnessUpTimer == 15000)
                end
            end)

            test("actual protein bridge respects low-protein and exact boundary factors", function()
                for _, case in ipairs({ { -400, 875 }, { 50, 1250 }, { 300, 1250 }, { -300, 1250 } }) do
                    local p = newPlayer(case[1])
                    assert(protein.AddDose(p, 0.5))
                    B.Grant(p, 1, 5)
                    near(p:getXp():getXP(Perks.Strength), case[2])
                    near(p:getXp():getXP(Perks.Fitness), 1250)
                    assert(#p.calls == 8)
                end
            end)

            test("expired protein leaves normal training and nutrition intact", function()
                local p = newPlayer(100)
                assert(protein.AddDose(p, 0.5))
                now = now + 3
                B.Grant(p, 1, 5)
                near(p:getXp():getXP(Perks.Fitness), 125)
                near(p:getXp():getXP(Perks.Strength), 187.5)
                assert(#p.calls == 6)
            end)

            test("protein cannot revive fitness XP blocked by nutrition", function()
                local p = newPlayer(100)
                p.levels[Perks.Fitness], p.traits.OVERWEIGHT = 9, true
                assert(protein.AddDose(p, 0.5))
                local _, detail = B.Grant(p, 1, 5)
                near(p:getXp():getXP(Perks.Fitness), 0)
                near(p:getXp():getXP(Perks.Strength), 1875)
                assert(p.events[Perks.Fitness] == nil and #p.calls == 7)
                for _, row in ipairs(detail) do
                    if row.skill == "Fitness" then assert(row.reason == "native-rule" and row.actual == 0) end
                end
            end)

            test("native level-ten XP cap remains intact with an active protein dose", function()
                local p = newPlayer(100)
                p.totals[Perks.Fitness], p.totals[Perks.Strength] = MAXIMUM - 1, MAXIMUM - 1
                assert(protein.AddDose(p, 0.5))
                B.Grant(p, 1, 5)
                near(p:getXp():getXP(Perks.Fitness), MAXIMUM)
                near(p:getXp():getXP(Perks.Strength), MAXIMUM)
                assert(#p.calls == 6, "the protein bridge supplemented an already capped skill")
            end)
        else
            print("SKIP weight native XP: external protein sources were not supplied")
        end
    end)

    Perks, SandboxVars, getGameTime = saved.Perks, saved.SandboxVars, saved.getGameTime
    isClient, isServer, Events = saved.isClient, saved.isServer, saved.Events
    addXpNoMultiplier = saved.addXpNoMultiplier
    SuQingWeightTraining, SuQingProteinTrainingBoost = saved.SuQingWeightTraining, saved.SuQingProteinTrainingBoost
    for _, name in ipairs(moduleNames) do package.loaded[name] = saved.modules[name] end
    if not ok then error(err, 0) end
    return passed
end

return { run = run }
