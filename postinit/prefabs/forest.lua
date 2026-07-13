local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("forest", function(inst)
    if TheWorld.is_adventure then
        TheWorld.Map:AlwaysDrawWaves(true)
        if TheWorld:IsAdventureLevel("ENDING") then -- 终章没有海洋特效
            TheWorld.Map:AlwaysDrawWaves(false)
        end
        TheWorld.Map:DoOceanRender(false)
        TheWorld.Map:SetUndergroundFadeHeight(12) -- 看起来效果最好
        
        TheWorld.WaveComponent:SetWaveParams(13.5, 2.5)                     -- wave texture u repeat, forward distance between waves
        TheWorld.WaveComponent:SetWaveSize(80, 3.5)                         -- wave mesh width and height
        TheWorld.WaveComponent:SetWaveTexture("images/wave.tex")
        TheWorld.WaveComponent:SetWaveEffect("shaders/waves.ksh")           -- See source\game\components\WaveRegion.h
        
        if TheWorld.components.ambientsound then
            TheWorld.components.ambientsound:SetWavesEnabled(false)
        end
    end

    if not TheWorld.ismastersim then
        return
    end

    if TheWorld.is_adventure then
        TheWorld:AddComponent("ad_frograin")
    end
end)
