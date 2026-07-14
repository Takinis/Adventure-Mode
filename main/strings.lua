local AddSimPostInit = AddSimPostInit
local LoadPOFile = LoadPOFile
GLOBAL.setfenv(1, GLOBAL)

local locale = LOC.GetLocaleCode()
local is_chinese = locale == "zh" or locale == "zhr" or locale == "zht"

STRINGS.UI.SANDBOXMENU.ADVENTURECHAPTER = "Chapter %d of %d"

STRINGS.UI.WORLDRESETDIALOG.REGEN_MSG_ADVENTURE = "Everyone is dead. Everyone will return to the main world in: %d"
STRINGS.UI.WORLDRESETDIALOG.RESET_BUTTON_ADVENTURE = "Return Now"
STRINGS.UI.HUD.TELEPORTATO_PLAYER_CONFIRMED = "Player %s has confirmed."
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_TITLE = "Return to the Original World"
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_BODY = "Are you sure you want to return to the original world?"
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_NEXT_CHAPTER_CONFIRM_TITLE = "The current world will be destroyed, begin the next Adventure Mode chapter? Every living player must confirm activation."

AddSimPostInit(function()
    if TheWorld.is_adventure then
        STRINGS.UI.WORLDRESETDIALOG.REGEN_MSG = STRINGS.UI.WORLDRESETDIALOG.REGEN_MSG_ADVENTURE
        STRINGS.UI.WORLDRESETDIALOG.RESET_BUTTON = STRINGS.UI.WORLDRESETDIALOG.RESET_BUTTON_ADVENTURE
    end
end)

if is_chinese then
    LoadPOFile("strings/chinese.po", locale)
    TranslateStringTable(STRINGS)
end
