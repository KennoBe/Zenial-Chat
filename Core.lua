local addonName,Z=...
_G.ZenialChat=Z
Z.VERSION='0.1.0-beta.3'
function Z.L(de,en)return GetLocale and GetLocale()=='deDE'and de or en or de end
function Z.Safe(...)
    for i=1,select('#',...)do
        local value=select(i,...)
        if type(issecretvalue)=='function'then local ok,secret=pcall(issecretvalue,value);if not ok or secret then return false end end
        if type(value)=='table'and type(canaccesstable)=='function'then local ok,access=pcall(canaccesstable,value);if not ok or not access then return false end end
    end
    return true
end
function Z.Call(fn,...)
    if type(fn)~='function'then return nil end
    local ok,a,b,c,d,e=pcall(fn,...);if ok and Z.Safe(a,b,c,d,e)then return a,b,c,d,e end
end
-- Native close button when the template exists on this client; otherwise the themed text button.
-- Both variants run exactly `fn` on click and show the same tooltip.
function Z.CloseButton(parent,fn,tip)
    local b
    if CreateFrame then
        local ok,frame=pcall(CreateFrame,'Button',nil,parent,'UIPanelCloseButton')
        if ok and type(frame)=='table'then
            b=frame;b.zenialNative=true
            b:SetScript('OnClick',fn)
            b:SetScript('OnEnter',function(self)if self.tip and Z.Theme then Z.Theme.Tooltip(self,self.tip)end end)
            b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
        end
    end
    if not b then b=Z.Theme.Button(parent,'×',fn)end
    b.tip=tip;return b
end
function Z.Now()return Z.Call(GetServerTime)or Z.Call(time)or 0 end
function Z.Clock()return Z.Call(GetTime)or 0 end
function Z.Plain(text)
    if not Z.Safe(text)or type(text)~='string'then return''end
    return text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|H.-|h(.-)|h','%1'):gsub('|T.-|t',''):gsub('|A.-|a',''):gsub('|K.-|k',''):gsub('||','|')
end
function Z.IsVisibleAtEnd(key)
    local u=Z.UI
    return u and u.frame and u.frame:IsShown()and not u.settingsPanel:IsShown()and Z.store.db.ui.selected==key and u.atEnd==true or false
end
function Z.Changed(reason,key)
    if Z.UI and Z.UI.RequestRefresh then Z.UI.RequestRefresh(reason,key)end
end
function Z.Initialize()
    if Z.ready then return end
    if type(ZenialChatDB)~='table'or not Z.Safe(ZenialChatDB)then ZenialChatDB={}end
    Z.store=Z.Store.New(ZenialChatDB,Z.Now)
    Z.adapter=Z.Adapter.New(Z.store,_G)
    Z.adapter:RefreshIdentity()
    Z.ready=true
end
