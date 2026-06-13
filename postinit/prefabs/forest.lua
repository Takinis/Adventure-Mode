local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("forest", function(inst)
    if ShardGameIndex:IsAdventureActive() then
        inst:DoTaskInTime(0, function(inst)
            if inst.has_ocean then 
                inst.WaveComponent:SetWaveTexture("images/wave.tex")
                inst.Map:SetUndergroundFadeHeight(0)
                inst.Map:AlwaysDrawWaves(true)
                inst.Map:DoOceanRender(false)
            end
        end)
    end

    if not TheWorld.ismastersim then
        return
    end
end)