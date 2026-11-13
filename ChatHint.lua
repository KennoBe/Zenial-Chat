-- Translation hint for foreign-language SAY/YELL lines in the normal chat window (XF9-T05).
-- SHIPPED STATE: OFF. Whether the client processes the link type "addon:" and delivers the click to the addon is unverified
-- (ingame check G5). H.VERIFIED_BUILD stays nil until that check has passed and is then set by hand; until then
-- H.Supported() is false, the filters change nothing and no link is ever created, so no broken link can appear.
local _,Z=...
local H={};Z.ChatHint=H
H.VERIFIED_BUILD=nil
local PREFIX='addon:ZenialChat:xf:'
local MARK='|Haddon:ZenialChat:xf:'
local filtersInstalled={}
local routes={}
local lastLink,lastAt
local function safeCall(fn,...)local ok,value=pcall(fn,...);if ok then return value end end
local function build()
    if type(GetBuildInfo)~='function'then return nil end
    local ok,value=pcall(function()return(select(4,GetBuildInfo()))end)
    return ok and value or nil
end
local function routeCount()
    local n=0
    for _ in pairs(routes)do n=n+1 end
    return n
end
-- True only for the verified client build and when at least one way to receive the click could be installed.
function H.Supported()
    local verified=H.VERIFIED_BUILD
    if type(verified)~='number'then return false end
    if build()~=verified then return false end
    return routeCount()>0
end
local function hintText(lineID)
    return' |cff9d9d9d'..MARK..lineID..'|h['..Z.L('Mit ZENIAL übersetzen','Translate with ZENIAL')..']|h|r'
end
-- Returns the new text or nil (nothing to do). Raises on unexpected errors; the caller runs it in pcall.
local function compute(...)
    if not H.Supported()then return nil end
    local store,adapter=Z.store,Z.adapter
    if not Z.ready or not store or not adapter or not store.settings or store.settings.xfChatHint~=true then return nil end
    local text=adapter:Text((...))
    local sender=adapter:Text((select(2,...)))
    local language=adapter:Text((select(3,...)))
    local guid=adapter:Text((select(12,...)))
    local line=select(11,...)
    if not text or not language or language==''or not sender or sender==''then return nil end
    if not adapter:Safe(line)or type(line)~='number'or line<=0 then return nil end
    local me=adapter.me or{}
    if(guid and guid==me.guid)or sender==me.name then return nil end
    if text:find(MARK,1,true)then return nil end
    local O=Z.Opposite
    if type(O)~='table'then return nil end
    if type(O.skip)=='function'then
        local ok,skipped=pcall(O.skip,text);if ok and skipped then return nil end
    end
    if O.Speaks(language)then return nil end
    return text..hintText(string.format('%d',line))
end
-- Chat filter: never hides a line. Returns false (unchanged) or false plus all original arguments with arg1 replaced.
local function filter(_,_,...)
    local ok,newText=pcall(compute,...)
    if not ok or type(newText)~='string'then return false end
    return false,newText,select(2,...)
end
-- Pure: recognises addon:ZenialChat:xf:<lineID> and opens the message. false for every other link.
function H.OnLink(link)
    if type(link)~='string'or(Z.Safe and not Z.Safe(link))then return false end
    local lineID=link:match('^'..PREFIX..'(%d+)$')
    if not lineID then return false end
    local O=Z.Opposite
    if type(O)~='table'or type(O.OpenMessage)~='function'then return false end
    local id='xf:'..lineID
    local store,me=Z.store,Z.adapter and Z.adapter.me
    local present=false
    if store and me and me.realm and me.realm~=''and me.faction and me.faction~=''then
        local key=Z.Store.Key({kind='XFACTION',scope=me.realm,target=me.faction})
        present=safeCall(store.IndexOf,store,key,id)~=nil
    end
    if not present then
        local bridge=Z.CommunityBridge
        local replaced=type(bridge)=='table'and type(bridge.Replacement)=='function'and safeCall(bridge.Replacement,lineID)
        if type(replaced)=='string'and replaced~=''then id=replaced end
    end
    pcall(O.OpenMessage,id)
    return true
end
local function clock()
    local t=type(GetTime)=='function'and safeCall(GetTime)
    return type(t)=='number'and t or 0
end
-- The client may report one click through both routes; the same link within one second opens the message once.
local function onClick(...)
    local link
    for i=1,3 do
        local value=select(i,...)
        if type(value)=='string'and value:sub(1,#PREFIX)==PREFIX then link=value;break end
    end
    if not link then return end
    local at=clock()
    if link==lastLink and lastAt and at>=lastAt and at-lastAt<1 then return end
    lastLink,lastAt=link,at
    pcall(H.OnLink,link)
end
local function installRoutes()
    if not routes.registry and type(EventRegistry)=='table'and type(EventRegistry.RegisterCallback)=='function'then
        local ok=pcall(EventRegistry.RegisterCallback,EventRegistry,'SetItemRef',onClick,H)
        if ok then routes.registry=true end
    end
    if not routes.hook and type(hooksecurefunc)=='function'and type(SetItemRef)=='function'then
        local ok=pcall(hooksecurefunc,'SetItemRef',onClick)
        if ok then routes.hook=true end
    end
end
-- Idempotent. Installs the filters (they act only while Supported() is true and the setting is on) and the click routes.
function H.Initialize()
    do
        local add=(type(ChatFrameUtil)=='table'and ChatFrameUtil.AddMessageEventFilter)or ChatFrame_AddMessageEventFilter
        if type(add)=='function'then
            for _,event in ipairs({'CHAT_MSG_SAY','CHAT_MSG_YELL'})do
                if not filtersInstalled[event]and pcall(add,event,filter)then filtersInstalled[event]=true end
            end
        end
    end
    installRoutes()
end
