GLOBAL = _G
LEVELTYPE =
{
    SURVIVAL = "SURVIVAL",
    ADVENTURE = "ADVENTURE",
}

local preinit = nil
AddLevelPreInitAny = function(fn)
    preinit = fn
end

table.contains = function(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

package.loaded["map/levels"] =
{
    GetTypeForLevelID = function(id)
        return id == "adventure" and LEVELTYPE.ADVENTURE or LEVELTYPE.SURVIVAL
    end,
    GetTypeForWorldGenID = function()
        return nil
    end,
    GetTypeForSettingsID = function()
        return nil
    end,
}

dofile("postinit/map/levels/forest.lua")
assert(type(preinit) == "function")

local forest =
{
    id = "forest",
    location = "forest",
    overrides = { task_set = "default" },
    required_setpieces = {},
}
preinit(forest)
assert(table.contains(forest.required_setpieces, "AdventurePortalLayout"))

local cave =
{
    id = "cave",
    location = "cave",
    overrides = { task_set = "cave_default" },
    required_setpieces = {},
}
preinit(cave)
assert(not table.contains(cave.required_setpieces, "AdventurePortalLayout"))

local secondary =
{
    id = "secondary",
    location = "cave",
    overrides = { task_set = "ADVENTURE_SECONDARY", is_adventure = true },
    required_setpieces = {},
}
preinit(secondary)
assert(not table.contains(secondary.required_setpieces, "AdventurePortalLayout"))

local adventure =
{
    id = "adventure",
    location = "forest",
    overrides = { task_set = "adventure", is_adventure = true },
    required_setpieces = {},
}
preinit(adventure)
assert(not table.contains(adventure.required_setpieces, "AdventurePortalLayout"))

print("adventure_portal_worldgen_test: ok")
