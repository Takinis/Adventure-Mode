local AddLevelPreInitAny = AddLevelPreInitAny
GLOBAL.setfenv(1, GLOBAL)

local Levels = require("map/levels")

local function IsForestSurvivalLevel(level)
    local is_survival = Levels.GetTypeForLevelID(level.id) == LEVELTYPE.SURVIVAL
        or Levels.GetTypeForWorldGenID(level.id) == LEVELTYPE.SURVIVAL
        or Levels.GetTypeForSettingsID(level.id) == LEVELTYPE.SURVIVAL
    if not is_survival then
        return false
    end

    local location = type(level.location) == "string" and string.lower(level.location) or nil
    local overrides = type(level.overrides) == "table" and level.overrides or {}
    return location == "forest" and
        overrides.is_adventure ~= true and
        overrides.task_set ~= "HAMLET_SECONDARY" and
        overrides.task_set ~= "ADVENTURE_SECONDARY"
end

AddLevelPreInitAny(function(level)
    if not IsForestSurvivalLevel(level) then
        return
    end

    level.required_setpieces = level.required_setpieces or {}
    if table.contains(level.required_setpieces, "AdventurePortalLayout") then
        return
    end

    table.insert(level.required_setpieces, "AdventurePortalLayout")
end)
