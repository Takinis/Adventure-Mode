local AddSimPostInit = AddSimPostInit
local LoadPOFile = LoadPOFile
GLOBAL.setfenv(1, GLOBAL)

local locale = LOC.GetLocaleCode()
local is_chinese = locale == "zh" or locale == "zhr" or locale == "zht"

STRINGS.UI.SANDBOXMENU.ADVENTURECHAPTER = "Chapter %d of %d"
STRINGS.UI.ADVENTUREMODE_PRESENTATION_WAIT = {
    TITLE = "Waiting for Other Players",
    PROGRESS = "Players ready: %d / %d\n%s",
}

STRINGS.UI.WORLDRESETDIALOG.REGEN_MSG_ADVENTURE = "Everyone is dead. Everyone will return to the main world in: %d"
STRINGS.UI.WORLDRESETDIALOG.RESET_BUTTON_ADVENTURE = "Return Now"
STRINGS.UI.HUD.TELEPORTATO_PLAYER_CONFIRMED = "Player %s has confirmed."
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_TITLE = "Return to the Original World"
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_BODY = "Are you sure you want to return to the original world?"
STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_NEXT_CHAPTER_CONFIRM_TITLE = "The current world will be destroyed, begin the next Adventure Mode chapter? Every living player must confirm activation."
STRINGS.UI.BUILTINCOMMANDS.ADVENTUREMODE_ENTER = {
    PRETTYNAME = "Enter Adventure Mode",
    DESC = "Vote to enter Adventure Mode.",
    VOTETITLEFMT = "Enter Adventure Mode?",
    VOTENAMEFMT = "vote to enter Adventure Mode",
    VOTEPASSEDFMT = "Entering Adventure Mode in 5 seconds...",
    VOTEFAILEDFMT = "The vote to enter Adventure Mode has failed.",
}
STRINGS.UI.ADVENTUREMODE_VOTE = {
    ACTIVE = "Another vote is already in progress.",
    ALREADY_ACTIVE = "Adventure Mode is already active.",
    FAILED = "Unable to start the Adventure Mode vote.",
    MASTER_ONLY = "The Adventure Mode vote must be started from the Master world.",
    PENDING = "An Adventure Mode vote is already being started.",
    TOO_FAR = "Move closer to the Adventure Portal.",
}
STRINGS.UI.PLAYERSTATUSSCREEN.VOTECANNOTSTART.ADVENTUREMODE = "The Adventure Mode vote is no longer available."
STRINGS.UI.ENDGAME = {
    TITLE = "The End.",
    BODY1 = "And so the cycle continues. Will ",
    BODY2 = " ever escape?\n Perhaps %s too will tire of this wretched place, and use %s new powers to tempt the unsuspecting.\n\nThe mysterious beings that control this place still lurk in the shadows, and new challenges will soon be revealed.\n\n\nUntil then,\n- The Don't Starve Team -",
    YES = "For Science!",
}
STRINGS.UI.GENDERSTRINGS = {
    MALE = { ONE = "he", TWO = "his" },
    FEMALE = { ONE = "she", TWO = "her" },
    ROBOT = { ONE = "they", TWO = "their" },
}

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
