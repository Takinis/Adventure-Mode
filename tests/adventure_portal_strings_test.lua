GLOBAL = _G
LOC =
{
    GetLocaleCode = function()
        return "en"
    end,
}
AddSimPostInit = function()
end
LoadPOFile = function()
end
TranslateStringTable = function()
end

STRINGS =
{
    UI =
    {
        SANDBOXMENU = {},
        WORLDRESETDIALOG = {},
        HUD = {},
        BUILTINCOMMANDS = {},
        ADVENTUREMODE_VOTE = {},
        PLAYERSTATUSSCREEN = { VOTECANNOTSTART = {} },
        ENDGAME = {},
        GENDERSTRINGS = {},
    },
    CHARACTERS = {},
}

dofile("main/strings.lua")

local expected =
{
    "GENERIC",
    "WILSON",
    "WILLOW",
    "WOLFGANG",
    "WENDY",
    "WX78",
    "WICKERBOTTOM",
    "WOODIE",
    "WAXWELL",
    "WATHGRITHR",
    "WEBBER",
    "WINONA",
    "WORTOX",
    "WORMWOOD",
    "WARLY",
    "WURT",
    "WALTER",
    "WANDA",
    "WES",
    "WONKEY",
}

local seen = {}
for _, character in ipairs(expected) do
    local line = STRINGS.CHARACTERS[character].ACTIONFAIL.ADVENTURE_PORTAL.WRONG_WORLD
    assert(type(line) == "string" and line ~= "")
    assert(seen[line] == nil)
    seen[line] = character
end

print("adventure_portal_strings_test: ok")
