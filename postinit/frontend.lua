GLOBAL.setfenv(1, GLOBAL)

local _Fade = FrontEnd.Fade
function FrontEnd:Fade(...)
    if not AD_RPC_FN.ConsumeActivateFade(self, _Fade, ...) then
        return _Fade(self, ...)
    end
end
