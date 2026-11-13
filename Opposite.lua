-- Opposite-faction say/yell lines in a language the player does not speak. Capture only: nothing here sends.
local _,Z=...
local O={};Z.Opposite=O
O.events={'CHAT_MSG_SAY','CHAT_MSG_YELL'}
O.handles={CHAT_MSG_SAY='SAY',CHAT_MSG_YELL='YELL'}
-- Optional hook for a later step: skip(text) returning true keeps a protocol line out of the history.
O.skip=nil
local spoken
local function api()return Z.adapter and Z.adapter.api or _G end
local function now()return Z.Now and Z.Now()or time and time()or 0 end
-- True when the character speaks this language. Remembered for the session; the lookup is cheap but runs per line.
function O.Speaks(languageName)
    if type(languageName)~='string'or languageName==''then return false end
    if spoken==nil then spoken={} end
    if spoken[languageName]~=nil then return spoken[languageName]end
    local p=api()
    if type(p.GetNumLanguages)~='function'or type(p.GetLanguageByIndex)~='function'then return false end
    local okCount,count=pcall(p.GetNumLanguages)
    if not okCount or type(count)~='number'then return false end
    local found=false
    for i=1,count do
        local ok,name=pcall(p.GetLanguageByIndex,i)
        if ok and Z.Safe(name)and name==languageName then found=true;break end
    end
    spoken[languageName]=found
    return found
end
function O.Reset()spoken=nil end
-- Language names of each faction (English and German), compared with ASCII folding. A line in one of the player's
-- own faction languages is never an opposite-faction line, whatever the character happens to speak.
local OWN_LANGUAGES={
    Alliance={'common','gemeinsprache','darnassian','darnassisch','dwarvish','zwergisch','gnomish','gnomisch','draenei','draeneiisch'},
    Horde={'orcish','orcisch','taurahe','taurisch','zandali','trollisch','troll','gutterspeak','forsaken','gossensprache','thalassian','thalassisch'},
}
local ownSets={}
for faction,list in pairs(OWN_LANGUAGES)do
    local set={};for _,name in ipairs(list)do set[name]=true end
    ownSets[faction]=set
end
local function fold(text)return(text:gsub('%u',function(c)return string.char(c:byte()+32)end))end
-- True for a named language that the character does not speak and that does not belong to the own faction.
function O.IsOppositeLanguage(languageName)
    if type(languageName)~='string'or languageName==''then return false end
    if O.Speaks(languageName)then return false end
    local faction=Z.adapter and Z.adapter.me and Z.adapter.me.faction
    local own=faction and ownSets[faction]
    if own and own[fold(languageName)]then return false end
    return true
end
-- lineID -> stored message id, this session only (ids carry the session, line ids restart with every client start).
local lineIds,lineOrder,LINE_LIMIT={},{},200
local function rememberLine(line,id)
    local key=tostring(line)
    if lineIds[key]==nil then
        lineOrder[#lineOrder+1]=key
        if #lineOrder>LINE_LIMIT then lineIds[table.remove(lineOrder,1)]=nil end
    end
    lineIds[key]=id
end
function O.MessageIdForLine(lineID)
    if lineID==nil then return nil end
    return lineIds[tostring(lineID)]
end
-- Opens the phrase popup. channel 'SAY'|'YELL'|nil marks the preferred send button. Never raises, never sends.
function O.OpenPhrases(channel)
    if channel~='SAY'and channel~='YELL'then channel=nil end
    local ui=Z.PhraseUI
    if type(ui)~='table'or type(ui.Open)~='function'then return false end
    return(pcall(ui.Open,channel))
end
-- Opens the window on the opposite-faction conversation of this realm and faction and shows a message.
-- Never creates the conversation; an unknown id or a missing conversation only leaves the window open.
function O.OpenMessage(messageId)
    local ui=Z.UI
    if type(ui)~='table'or type(ui.Open)~='function'then return false end
    return(pcall(function()
        ui.Open()
        local store,me=Z.store,Z.adapter and Z.adapter.me
        if not store or not me or not me.realm or me.realm==''or not me.faction or me.faction==''then return end
        local key=Z.Store.Key({kind='XFACTION',scope=me.realm,target=me.faction})
        if not store:Get(key)then return end
        ui.Select(key,store:IndexOf(key,messageId)and messageId or nil)
    end))
end
local function handle(event,...)
    local channel=O.handles[event];if not channel then return end
    local adapter,store=Z.adapter,Z.store;if not adapter or not store then return end
    local text,sender,language=adapter:Text((...)),adapter:Text((select(2,...))),adapter:Text((select(3,...)))
    if not text or not sender or sender==''or not language or language==''then return end
    local guid=select(12,...)
    guid=adapter:Text(guid)
    local line=select(11,...)
    if not adapter:Safe(line)or type(line)~='number'or line==0 then return end
    local me=adapter.me or{}
    if(guid and guid==me.guid)or sender==me.name then return end
    if not me.realm or me.realm==''or not me.faction or me.faction==''then return end
    if type(O.skip)=='function'then
        local ok,skipped=pcall(O.skip,text);if ok and skipped then return end
    end
    if not O.IsOppositeLanguage(language)then return end
    local c=store:Ensure({kind='XFACTION',name=Z.L('Gegnerische Fraktion','Opposite faction'),scope=me.realm,target=me.faction})
    if not c then return end
    local id='xf:'..tostring(adapter.session or'0')..':'..string.format('%d',line)
    local row={id=id,at=now(),sender=sender,senderGuid=guid and guid:match('^Player%-')and guid or nil,
        channel=channel,language=language,text=text,reading='unknown',meaning=nil}
    local msg,added=store:Append(c,row,Z.IsVisibleAtEnd and Z.IsVisibleAtEnd(c.key)or false)
    if msg then rememberLine(line,id)end
    return c,msg,added
end
-- Never raises: the original chat event is untouched either way.
function O.OnEvent(event,...)
    local ok,c,msg,added=pcall(handle,event,...)
    if not ok then return nil end
    return c,msg,added
end
