-- fuck klei
-- why? i don't know.
local Text = require "widgets/text"
GLOBAL.setfenv(1, GLOBAL)

local function utf8_iter(str)
    return str:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

function Text:SetOverflowWrappedString(str)
    str = str or ""

    local region_w, region_h = self:GetRegionSize()
    if region_w == nil or region_w <= 0 or self.inst.TextWidget.HasOverflow == nil then
        self:SetString(str)
        return str
    end

    local lines = {}
    local line = ""

    self:SetRegionSize(region_w, 10000)

    for ch in utf8_iter(str) do
        if ch == "\n" then
            table.insert(lines, line)
            line = ""
        else
            local test_line = line .. ch
            self.inst.TextWidget:SetString(test_line)

            if line ~= "" and self.inst.TextWidget:HasOverflow() then
                table.insert(lines, line)
                line = ch
            else
                line = test_line
            end
        end
    end

    table.insert(lines, line)

    local wrapped = table.concat(lines, "\n")
    self:SetRegionSize(region_w, region_h)
    self:SetString(wrapped)

    return wrapped
end

local function IsChineseOrJapaneseLanguage()
    local lang = LOC ~= nil and LOC.GetLanguage ~= nil and LOC.GetLanguage() or nil

    return lang == LANGUAGE.JAPANESE
        or lang == LANGUAGE.CHINESE_S
        or lang == LANGUAGE.CHINESE_T
        or lang == LANGUAGE.CHINESE_S_RAIL
end

if IsChineseOrJapaneseLanguage() then
    local TEMPLATES = require("widgets/redux/templates")
    local _CurlyWindow = TEMPLATES.CurlyWindow
    TEMPLATES.CurlyWindow = function(sizeX, sizeY, title_text, bottom_buttons, button_spacing, body_text)
        local has_body = body_text ~= nil
        local w = _CurlyWindow(sizeX, sizeY, title_text, bottom_buttons, button_spacing, has_body and "" or nil)

        if has_body and w.body ~= nil then
            w.body:EnableWordWrap(false)
            w.body:EnableWhitespaceWrap(false)
            w.body:SetOverflowWrappedString(body_text)
        end

        return w
    end
end

-- [01:04:33]: EnableWordWrap	function: 0x6000365d2600	
-- [01:04:33]: SetEditCursorColour	function: 0x6000365d0400	
-- [01:04:33]: SetVAnchor	function: 0x6000365d03c0	
-- [01:04:33]: SetColour	function: 0x6000365d0a40	
-- [01:04:33]: ShowEditCursor	function: 0x6000365d3f00	
-- [01:04:33]: SetFont	function: 0x6000365d2200	
-- [01:04:33]: SetHAnchor	function: 0x6000365d3400	
-- [01:04:33]: GetString	function: 0x6000365d17c0	
-- [01:04:33]: SetHorizontalSqueeze	function: 0x6000365d3ac0	
-- [01:04:33]: GetRegionSize	function: 0x6000365d1d40	
-- [01:04:33]: EnableWhitespaceWrap	function: 0x6000365d3000	
-- [01:04:33]: SetString	function: 0x6000365d2240	
-- [01:04:33]: SetSize	function: 0x6000365d2c00	
-- [01:04:33]: SetRegionSize	function: 0x6000365d3b40	
-- [01:04:33]: HasOverflow	function: 0x6000365d2f00	
-- [01:04:33]: ResetRegionSize	function: 0x6000365d2ac0	