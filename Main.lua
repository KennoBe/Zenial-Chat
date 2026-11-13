local _,Z=...
BINDING_HEADER_ZENIALCHAT='Zenial Chat'
BINDING_NAME_ZENIALCHAT_TOGGLE=Z.L('Zenial Chat öffnen / schließen','Open / close Zenial Chat')
SLASH_ZENIALCHAT1='/zchat';SLASH_ZENIALCHAT2='/zenialchat'
SlashCmdList.ZENIALCHAT=function(text)
    text=type(text)=='string'and text:match('^%s*(.-)%s*$')or''
    if text=='settings'or text=='config'or text=='einstellungen'then Z.UI.OpenSettings('appearance')
    elseif text=='phrases'then Z.Opposite.OpenPhrases()
    else Z.UI.Toggle()end
end
local frame=CreateFrame('Frame');Z.eventFrame=frame
frame:RegisterEvent('ADDON_LOADED');frame:RegisterEvent('PLAYER_LOGIN')
for _,event in ipairs(Z.Adapter.events or{})do pcall(frame.RegisterEvent,frame,event)end
for _,event in ipairs(Z.Opposite.events)do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event,...)
    if event=='ADDON_LOADED'then local name=...;if name=='ZenialChat'then Z.Initialize()elseif name=='ZenialCommunity'then pcall(Z.CommunityBridge.Connect)end;return end
    if not Z.ready then if event=='PLAYER_LOGIN'then Z.Initialize()else return end end
    if event=='PLAYER_LOGIN'then pcall(Z.CommunityBridge.Connect)end
    local c,row,added
    if Z.Opposite.handles[event]then c,row,added=Z.Opposite.OnEvent(event,...);if Z.Calibration then pcall(Z.Calibration.OnEvent,event,...)end else c,row,added=Z.adapter:OnEvent(event,...)end
    if event=='PLAYER_LOGIN'then Z.adapter:RefreshIdentity();Z.UI.CreateMinimapButton();Z.NativeChat.Initialize()end
    Z.Notifications.Incoming(c,row,added)
    Z.UI.RequestRefresh(event,c and c.key)
end)
