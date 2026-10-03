local AddClassPostConstruct = AddClassPostConstruct
GLOBAL.setfenv(1, GLOBAL)

AddClassPostConstruct("widgets/playerdeathnotification", function(self)
    self._adventure_return_requested = false
    self.inst:ListenForEvent("adventure_return_result", function(_, data)
        if data == nil or data.success ~= true then
            self._adventure_return_requested = false
            self.reset_hold_time = 0
        end
    end, TheWorld)

    local _DoRegenWorld = self.DoRegenWorld
    function self:DoRegenWorld()
        if not TheWorld:IsAdventureActive() then
            return _DoRegenWorld(self)
        end

        if self.started and self.owner.Network:IsServerAdmin() and not self._adventure_return_requested then
            self._adventure_return_requested = true
            self.reset_hold_time = 0
            SendModRPCToServer(GetModRPC("AdventureMode", "ReturnAfterDeath"))
        end
    end

    local _StopRegenTimer = self.StopRegenTimer
    function self:StopRegenTimer(...)
        self._adventure_return_requested = false
        return _StopRegenTimer(self, ...)
    end

    local _Reset = self.Reset
    function self:Reset()
        if not TheWorld:IsAdventureActive() then
            return _Reset(self)
        end

        if self.started and self.owner.Network:IsServerAdmin() then
            local function cancel()
                self.regen_confirm = nil
                TheFrontEnd:PopScreen()
            end

            local function confirm()
                self.regen_confirm = nil
                self:DoRegenWorld()
            end

            local PopupDialogScreen = require("screens/redux/popupdialog")
            self.regen_confirm = PopupDialogScreen(
                STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_TITLE,
                STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_RETURN_CONFIRM_BODY,
                {
                    { text = STRINGS.UI.PAUSEMENU.YES, cb = confirm },
                    { text = STRINGS.UI.PAUSEMENU.NO, cb = cancel },
                }
            )
            TheFrontEnd:PushScreen(self.regen_confirm)
        end
    end
end)
