-- Optional bridge to the cross-faction API of Zenial Community. There is no TOC dependency: without Zenial Community
-- nothing here is active, and every call into the other addon runs in pcall so a failure there never reaches the chat.
local _,Z=...
local B={active=false,version=0};Z.CommunityBridge=B
local OWNER='ZenialChat'
local function now()return Z.Now and Z.Now()or time and time()or 0 end
-- The other side's API table, only when it is the version this bridge was written for.
local function remote()
    local ok,found=pcall(function()
        local community=_G.ZenialCommunity
        if type(community)~='table'then return nil end
        local xf=community.CrossFaction
        if type(xf)~='table'or xf.API_VERSION~=1 then return nil end
        return xf
    end)
    return ok and found or nil
end
-- pcall into the other addon: false when the API or the function is missing or raised.
local function call(name,...)
    local xf=remote()
    if not xf or type(xf[name])~='function'then return false end
    return pcall(xf[name],...)
end
local function refresh()
    local ui=Z.UI
    if type(ui)=='table'and type(ui.RequestRefresh)=='function'then pcall(ui.RequestRefresh,'xfstatus')end
end
local function skip(text)
    local okEnabled,enabled=call('IsEnabled')
    if not okEnabled or enabled~=true then return false end
    local ok,line=call('IsProtocolLine',text)
    return ok and line==true
end
local function onMessage(p)
    local adapter,store=Z.adapter,Z.store
    if type(p)~='table'or not adapter or not store then return end
    local me=adapter.me or{}
    if not me.realm or me.realm==''or not me.faction or me.faction==''then return end
    if type(p.text)~='string'or p.id==nil then return end
    local outgoing=p.outgoing==true
    if not outgoing then
        local ok,status=call('GetPlayerStatus',p.guid)
        -- Players of the own faction have nothing to do in the opposite-faction area; an unknown faction is accepted.
        if ok and type(status)=='table'and status.faction==me.faction then return end
    end
    local c=store:Ensure({kind='XFACTION',name=Z.L('Gegnerische Fraktion','Opposite faction'),scope=me.realm,target=me.faction})
    if not c then return end
    -- Message ids restart every session, so the time keeps entries of earlier sessions apart.
    local id='xfm:'..tostring(p.at)..':'..tostring(p.id)
    if store:IndexOf(c.key,id)then return end
    local row
    if outgoing then
        row={id=id,at=now(),sender=me.name,ownCharacter=me.name,senderClass=me.classFile,outgoing=true,channel=p.channel,
            text='',reading='exact',meaning=p.text}
    else
        local parts,language={},nil
        if type(p.lineIDs)=='table'then
            for _,lineID in ipairs(p.lineIDs)do
                local at=store:IndexOf(c.key,'xf:'..tostring(lineID))
                local old=at and c.messages[at]
                if old then
                    if type(old.text)=='string'and old.text~=''then parts[#parts+1]=old.text end
                    if not language and type(old.language)=='string'and old.language~=''then language=old.language end
                    store:RemoveMessage(c.key,'xf:'..tostring(lineID))
                end
            end
        end
        row={id=id,at=now(),sender=p.sender,senderGuid=type(p.guid)=='string'and p.guid:match('^Player%-')and p.guid or nil,
            channel=p.channel,language=language,text=table.concat(parts,' '),reading='exact',meaning=p.text}
    end
    local visible=Z.IsVisibleAtEnd and Z.IsVisibleAtEnd(c.key)or false
    local msg,added=store:Append(c,row,visible)
    if not outgoing and Z.Notifications and added then pcall(Z.Notifications.Incoming,c,msg,added)end
end
local function listener(event,payload)
    if event=='MESSAGE'then pcall(onMessage,payload)
    elseif event=='PLAYER'then B.version=B.version+1;refresh()
    elseif event=='INCOMPLETE'then refresh()end
end
-- Idempotent. True when Zenial Community's API is present and this addon listens to it.
function B.Connect()
    if B.active then return true end
    local xf=remote()
    if not xf or type(xf.RegisterListener)~='function'then return false end
    local ok,registered=pcall(xf.RegisterListener,OWNER,listener)
    if not ok or registered==false then return false end
    if Z.Opposite then Z.Opposite.skip=skip end
    B.active=true
    return true
end
-- 'CONFIRMED' | 'INCOMPATIBLE' | nil (unknown, no Community, or an error).
function B.Status(guid)
    if not B.active or type(guid)~='string'or guid==''or(Z.Safe and not Z.Safe(guid))then return nil end
    local ok,status=call('GetPlayerStatus',guid)
    if not ok or type(status)~='table'then return nil end
    local value=status.status
    if value=='CONFIRMED'or value=='INCOMPATIBLE'then return value end
    return nil
end
function B.IconPath()
    if not B.active then return nil end
    local xf=remote()
    local path=xf and xf.ICON_PATH
    if type(path)~='string'or path==''or path:find('[|%c]')then return nil end
    return path
end
-- Inline icon followed by a space for a confirmed player, otherwise an empty string.
function B.Icon(guid)
    if B.Status(guid)~='CONFIRMED'then return''end
    local path=B.IconPath()
    return path and'|T'..path..':0|t 'or''
end
