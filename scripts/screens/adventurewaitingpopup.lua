local GenericWaitingPopup = require("screens/redux/genericwaitingpopup")

local AdventureWaitingPopup = Class(GenericWaitingPopup, function(self)
    GenericWaitingPopup._ctor(
        self,
        "AdventureWaitingPopup",
        STRINGS.UI.ADVENTUREMODE_PRESENTATION_WAIT.TITLE,
        nil,
        true
    )
    self.black:SetTint(0, 0, 0, 1)
    self.ready = 0
    self.total = 0
end)

function AdventureWaitingPopup:SetProgress(ready, total)
    self.ready = math.max(0, math.floor(ready or 0))
    self.total = math.max(self.ready, math.floor(total or 0))
end

function AdventureWaitingPopup:OnUpdate(dt)
    self.time = self.time + dt
    if self.time > .75 then
        self.progress = self.progress % 5 + 1
        self.time = 0
    end

    self.dialog.body:SetString(string.format(
        STRINGS.UI.ADVENTUREMODE_PRESENTATION_WAIT.PROGRESS,
        self.ready,
        self.total,
        string.rep(".", self.progress)
    ))
end

return AdventureWaitingPopup
