local LoadPOFile = LoadPOFile
GLOBAL.setfenv(1, GLOBAL)

local locale = LOC.GetLocaleCode()
local is_chinese = locale == "zh" or locale == "zhr" or locale == "zht"

STRINGS.UI.SANDBOXMENU.ADVENTURECHAPTER = "Chapter %d of %d"

if is_chinese then
    LoadPOFile("strings/chinese.po", locale)
    TranslateStringTable(STRINGS)
end
