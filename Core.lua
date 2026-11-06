local addonName,Z=...
_G.ZenialChat=Z
Z.VERSION='0.1.3'
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
    if not text:find('|',1,true)then return text end -- most messages have no markup at all
    return text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|H.-|h(.-)|h','%1'):gsub('|T.-|t',''):gsub('|A.-|a',''):gsub('|K.-|k',''):gsub('||','|')
end
-- The native chat link handlers own the player menu and its available actions.
function Z.PlayerLink(c,msg,label)
    if not Z.Safe(c,msg,label)or type(c)~='table'or type(label)~='string'then return label end
    if msg and msg.senderPending then return label end
    local function name(value)
        return Z.Safe(value)and type(value)=='string'and value~=''and not value:find('[|:%c]')and value or nil
    end
    local function id(value)
        if not Z.Safe(value)then return nil end
        if type(value)=='string'and value:match('^%d+$')then return value end
        if type(value)=='number'and value>=0 and value<math.huge and value%1==0 then return string.format('%.0f',value)end
    end
    local kind,parts
    if c.kind=='BN_WHISPER'and not(msg and msg.outgoing)then
        if not name(c.target)then return label end
        local account=id(Z.adapter and Z.adapter:ResolveAccount(c.target))
        if not account or account=='0'or not name(c.name)then return label end
        kind='BNplayer';parts={c.name,account,0}
    else
        local target=msg and(msg.outgoing and msg.ownCharacter or msg.sender)or c.target
        if msg and msg.outgoing and c.kind=='BN_WHISPER'then target=msg.ownCharacter end
        if not name(target)then return label end
        kind='player';parts={target}
    end
    if not kind then return label end
    local text=Z.Call(LinkUtil and LinkUtil.FormatLink,kind,label,unpack(parts))
    if type(text)~='string'then return label end
    return text,text:match('|H([^|]+)|h')
end
function Z.IsVisibleAtEnd(key)
    local u=Z.UI
    return u and u.frame and u.frame:IsShown()and not u.settingsPanel:IsShown()and not(u.searchPanel and u.searchPanel:IsShown())and Z.store.db.ui.selected==key and u.atEnd==true or false
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
