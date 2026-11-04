local _,Z=...
BINDING_HEADER_ZENIALCHAT='Zenial Chat'
BINDING_NAME_ZENIALCHAT_TOGGLE=Z.L('Zenial Chat öffnen / schließen','Open / close Zenial Chat')
SLASH_ZENIALCHAT1='/zchat';SLASH_ZENIALCHAT2='/zenialchat'
SlashCmdList.ZENIALCHAT=function(text)
    text=type(text)=='string'and text:match('^%s*(.-)%s*$')or''
    if text=='settings'or text=='config'or text=='einstellungen'then Z.UI.OpenSettings('appearance')
    else Z.UI.Toggle()end
end
local frame=CreateFrame('Frame');Z.eventFrame=frame
frame:RegisterEvent('ADDON_LOADED');frame:RegisterEvent('PLAYER_LOGIN')
for _,event in ipairs(Z.Adapter.events or{})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event,...)
    if event=='ADDON_LOADED'then local name=...;if name=='ZenialChat'then Z.Initialize()end;return end
    if not Z.ready then if event=='PLAYER_LOGIN'then Z.Initialize()else return end end
    local c,row,added=Z.adapter:OnEvent(event,...)
    if event=='PLAYER_LOGIN'then Z.adapter:RefreshIdentity()end
    Z.Notifications.Incoming(c,row,added)
    Z.UI.RequestRefresh(event,c and c.key)
end)
local historyTick=0
-- The 10 Hz history pump only runs while community history work is pending.
local function historyUpdate(_,elapsed)
    historyTick=historyTick+elapsed
    if historyTick>=.1 then
        historyTick=0
        local community=Z.adapter and Z.adapter.community
        if community and community.Tick then community:Tick()end
        if not community or not community.pending or next(community.pending)==nil then frame:SetScript('OnUpdate',nil)end
    end
end
function Z.WakeHistory()historyTick=0;frame:SetScript('OnUpdate',historyUpdate)end
