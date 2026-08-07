local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

-- https://forums.kleientertainment.com/forums/topic/140904-tiles-changes-and-more/
local function tile_physics_init(inst, ...)
    -- PL's ocean collider
    inst.Map:AddTileCollisionSet(
        COLLISION.LAND_OCEAN_LIMITS,
        TileGroups.LandTiles, false,
        TileGroups.LandTiles, true,
        0.25, 128 -- 亚丹: 最后一个参数是在C层切分的碰撞体的大小, 值越小碰撞体重建越快, 但是不重建时的性能越差
    )
    -- standard impassable collider
    inst.Map:AddTileCollisionSet(
        COLLISION.GROUND,
        TileGroups.ImpassableTiles, true,
        TileGroups.ImpassableTiles, false,
        0.25, 128
    )
end

AddPrefabPostInit("forest", function(inst)
    if inst.is_adventure then
        inst.Map:AlwaysDrawWaves(true)
        if inst:IsAdventurePreset("ENDING") then -- 终章没有海洋特效
            inst.Map:AlwaysDrawWaves(false)
        end
        inst.Map:DoOceanRender(false)
        inst.Map:SetUndergroundFadeHeight(12) -- 看起来效果最好
        
        inst.WaveComponent:SetWaveParams(13.5, 2.5)                     -- wave texture u repeat, forward distance between waves
        inst.WaveComponent:SetWaveSize(80, 3.5)                         -- wave mesh width and height
        inst.WaveComponent:SetWaveTexture("images/wave.tex")
        inst.WaveComponent:SetWaveEffect("shaders/waves.ksh")           -- See source\game\components\WaveRegion.h
        
        if inst.components.ambientsound then
            inst.components.ambientsound:SetWavesEnabled(false)
        end

        inst.tile_physics_init = tile_physics_init
    end

    if not inst.ismastersim then
        return
    end

    if inst.is_adventure then
        inst:AddComponent("ad_frograin")
    end
end)
