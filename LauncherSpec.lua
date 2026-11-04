-- Entry point of the Zenial Chat settings page (/zchat settings).
local _, ns = ...
ns.LauncherSpec = {
    openSettings = function()
        local handler = _G.SlashCmdList and _G.SlashCmdList.ZENIALCHAT
        if type(handler) == "function" then handler("settings") end
    end,
}
