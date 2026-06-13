GLOBAL.setfenv(1, GLOBAL)

local tuning = {
    FROG_RAIN_LOCAL_MIN_ADVENTURE = 10,
    FROG_RAIN_LOCAL_MAX_ADVENTURE = 25,
}

for key, value in pairs(tuning) do
    if TUNING[key] then
        print("OVERRIDE: " .. key .. " in TUNING")
    end

    TUNING[key] = value
end