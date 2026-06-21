local AddLevelPreInitAny = AddLevelPreInitAny
GLOBAL.setfenv(1, GLOBAL)

local Levels = require("map/levels")

local function IsSurvivalLevel(level)
    return Levels.GetTypeForLevelID(level.id) == LEVELTYPE.SURVIVAL
        or Levels.GetTypeForWorldGenID(level.id) == LEVELTYPE.SURVIVAL
        or Levels.GetTypeForSettingsID(level.id) == LEVELTYPE.SURVIVAL
end

AddLevelPreInitAny(function(level)
    if not IsSurvivalLevel(level) then
        return
    end

    level.required_setpieces = level.required_setpieces or {}
    if table.contains(level.required_setpieces, "AdventurePortalLayout") then
        return
    end

    table.insert(level.required_setpieces, "AdventurePortalLayout")
end)
