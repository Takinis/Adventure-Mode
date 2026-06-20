local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("forest", function(inst)
    if ShardGameIndex:IsAdventureActive() then
        TheWorld.Map:AlwaysDrawWaves(true)
        TheWorld.Map:DoOceanRender(false)
        TheWorld.Map:SetUndergroundFadeHeight(-15)
        
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
end)