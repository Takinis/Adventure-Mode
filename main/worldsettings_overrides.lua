GLOBAL.setfenv(1, GLOBAL)

local WorldSettings_Overrides = require("worldsettings_overrides")
local SEASON_HARSH_LENGTHS = ToolUtil.GetUpvalue(WorldSettings_Overrides.Post.winter, "SEASON_HARSH_LENGTHS")

-- Bruh.
if SEASON_HARSH_LENGTHS ~= nil then
    SEASON_HARSH_LENGTHS.veryveryshortseason = 3
else
    print("[Adventure Mode] Failed to hook SEASON_HARSH_LENGTHS")
end
