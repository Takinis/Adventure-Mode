local Screen = require "widgets/screen"
local ImageButton = require "widgets/imagebutton"
local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"

local function GetEndGameText(character)
    local character_name = STRINGS.CHARACTER_NAMES[character]
        or STRINGS.NAMES[string.upper(character)]
        or character
    local gender_strings = STRINGS.UI.GENDERSTRINGS[GetGenderStrings(character)]
        or STRINGS.UI.GENDERSTRINGS.ROBOT

    return STRINGS.UI.ENDGAME.BODY1
        .. character_name
        .. string.format(STRINGS.UI.ENDGAME.BODY2, gender_strings.ONE, gender_strings.TWO)
end

local EndGameDialog = Class(Screen, function(self, buttons, character)
    Screen._ctor(self, "EndGameDialog")

    self.black = self:AddChild(Image("images/global.xml", "square.tex"))
    self.black:SetVRegPoint(ANCHOR_MIDDLE)
    self.black:SetHRegPoint(ANCHOR_MIDDLE)
    self.black:SetVAnchor(ANCHOR_MIDDLE)
    self.black:SetHAnchor(ANCHOR_MIDDLE)
    self.black:SetScaleMode(SCALEMODE_FILLSCREEN)
    self.black:SetTint(0, 0, 0, 1)

    self.proot = self:AddChild(Widget("ROOT"))
    self.proot:SetVAnchor(ANCHOR_MIDDLE)
    self.proot:SetHAnchor(ANCHOR_MIDDLE)
    self.proot:SetPosition(0, 0, 0)
    self.proot:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.bg = self.proot:AddChild(Image("images/adventure_endgame.xml", "panel_upsell.tex"))
    self.bg:SetVRegPoint(ANCHOR_MIDDLE)
    self.bg:SetHRegPoint(ANCHOR_MIDDLE)
    self.bg:SetScale(0.8, 0.8, 0.8)

    self.title = self.proot:AddChild(Text(TITLEFONT, 50))
    self.title:SetPosition(0, 180, 0)
    self.title:SetString(STRINGS.UI.ENDGAME.TITLE)

    self.text = self.proot:AddChild(Text(BODYTEXTFONT, 30))
    self.text:SetVAlign(ANCHOR_TOP)
    self.text:SetPosition(0, -60, 0)
    self.text:SetString(GetEndGameText(character))
    self.text:EnableWordWrap(true)
    self.text:SetRegionSize(700, 350)

    local button_width = 200
    local button_spacing = 20
    local spacing = button_width + button_spacing

    self.menu = self.proot:AddChild(Widget("menu"))
    local total_width = #buttons * button_width
    if #buttons > 1 then
        total_width = total_width + button_spacing * (#buttons - 1)
    end
    self.menu:SetPosition(-(total_width / 2) + button_width / 2, -220, 0)

    local position = Vector3(0, 0, 0)
    for _, button_data in ipairs(buttons) do
        local button = self.menu:AddChild(ImageButton())
        button:SetPosition(position)
        button:SetText(button_data.text)
        button:SetOnClick(function()
            TheFrontEnd:PopScreen(self)
            button_data.cb()
        end)
        button.text:SetColour(0, 0, 0, 1)
        button:SetFont(BUTTONFONT)
        button:SetTextSize(40)
        position = position + Vector3(spacing, 0, 0)
        self.default_focus = button
    end

    self.buttons = buttons
end)

return EndGameDialog
