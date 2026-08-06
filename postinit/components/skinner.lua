local Skinner = require("components/skinner")
local CopySkinsFromPlayer = Skinner.CopySkinsFromPlayer
GLOBAL.setfenv(1, GLOBAL)

local function AssignCopiedItemSkins(anim_state, userid, character, skins)
    if table.contains(MODCHARACTERLIST, character) then
        -- Mod base builds are not Klei inventory items; clothing still requires ownership.
        anim_state:AssignItemSkins(userid, skins.body or "", skins.hand or "", skins.legs or "", skins.feet or "")
    else
        anim_state:AssignItemSkins(
            userid,
            skins.base or "",
            skins.body or "",
            skins.hand or "",
            skins.legs or "",
            skins.feet or ""
        )
    end
end

function Skinner:MakePuppetCopySkinsFromPlayer(character, userid, skins, monkey_curse, skin_mode, default_build)
    skin_mode = skin_mode or "normal_skin"
    default_build = default_build or character

    AssignCopiedItemSkins(self.inst.AnimState, userid, character, skins)

    local skin_data = GetSkinData(skins.base)
    local base_skin = skin_data.skins ~= nil and skin_data.skins[skin_mode] or default_build
    SetSkinsOnAnim(self.inst.AnimState, character, base_skin, skins, monkey_curse, skin_mode, default_build)

    self.copiedplayer_data =
    {
        prefab = character,
        userid = userid,
    }
    self.skin_name = skins.base or ""
    self.clothing.body = skins.body or ""
    self.clothing.hand = skins.hand or ""
    self.clothing.legs = skins.legs or ""
    self.clothing.feet = skins.feet or ""
    self.monkey_curse = monkey_curse
    self.skintype = skin_mode
end

function Skinner:CopySkinsFromPlayer(player, nocurses)
    if not TheWorld.is_adventure or not table.contains(MODCHARACTERLIST, player.prefab) then
        return CopySkinsFromPlayer(self, player, nocurses)
    end

    local player_skinner = player.components.skinner
    self:MakePuppetCopySkinsFromPlayer(
        player.prefab,
        player.userid,
        player_skinner:GetClothing(),
        not nocurses and player_skinner:GetMonkeyCurse() or nil,
        player_skinner:GetSkinMode(),
        player.prefab
    )
end
