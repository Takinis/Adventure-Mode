GLOBAL.setfenv(1, GLOBAL)

require("map/network")
local forest_map = require("map/forest_map")

local _Generate = forest_map.Generate

local active_worldgen_ctx = nil
local ABORT_EXTRA_WORMHOLES = {}

forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
    local oldctx = active_worldgen_ctx

    active_worldgen_ctx = {
        params = level ~= nil and level.overrides or nil,
        did_extra_wormholes = false,
    }

    local ok, ret = pcall(_Generate, prefab, map_width, map_height, tasks, level, level_type)

    active_worldgen_ctx = oldctx

    if not ok then
        if ret == ABORT_EXTRA_WORMHOLES then
            return nil
        end
        error(ret, 0)
    end

    return ret
end

local _GlobalPrePopulate = Graph.GlobalPrePopulate
Graph.GlobalPrePopulate = function(self, entities, width, height)
    local rets = { _GlobalPrePopulate(self, entities, width, height) }
    local ctx = active_worldgen_ctx
    local params = ctx ~= nil and ctx.params or nil

    if params ~= nil and (params.is_archipelago or params.is_two_worlds) and not ctx.did_extra_wormholes and self.parent == nil then

        print("Adding extra wormholes for world...")
        print("Is Archipelago, Huh? : ", params.is_archipelago)
        print("Is Two Worlds, Huh? : ", params.is_two_worlds)

        ctx.did_extra_wormholes = true

        self:SwapWormholesAndRoadsExtra(entities, width, height)

        if self.error == true then
            print("ERROR: Node ", self.error_string)
            error(ABORT_EXTRA_WORMHOLES, 0)
        end
    end

    return unpack(rets)
end

-- huh?
-- local _GlobalPostPopulate = Graph.GlobalPostPopulate
-- Graph.GlobalPostPopulate = function(self, entities, width, height)
--     local rets = { _GlobalPostPopulate(self, entities, width, height) }
--     local ctx = active_worldgen_ctx
--     local params = ctx ~= nil and ctx.params or nil

--     if params ~= nil
--         and params.is_archipelago
--         and not ctx.did_extra_wormholes
--         and self.parent == nil then

--         ctx.did_extra_wormholes = true

--         self:SwapWormholesAndRoadsExtra(entities, width, height)

--         if self.error == true then
--             print("ERROR: Node ", self.error_string)
--             error(ABORT_EXTRA_WORMHOLES, 0)
--         end
--     end

--     return unpack(rets)
-- end