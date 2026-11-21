-- Online status of direct-message contacts, kept in one place. Every source writes its own snapshot when
-- its native event arrives (coalesced); a lookup reads the newest valid observation and never walks a
-- contact list. Unknown is a state of its own: nothing here turns it into offline.
local _,Z=...
local P={};P.__index=P;Z.Presence=P
P.EVIDENCE_TTL=180   -- a whisper, its echo or an error tells the state at that moment only
P.ROSTER_TTL=900     -- the guild roster changes only when the client receives an update
P.PROBE_INTERVAL=60  -- at most one native reachability request per contact and minute
P.REBUILD_DELAY=1
local SOURCES={
    BN_FRIEND_INFO_CHANGED={'bnet'},BN_FRIEND_ACCOUNT_ONLINE={'bnet'},BN_FRIEND_ACCOUNT_OFFLINE={'bnet'},
    FRIENDLIST_UPDATE={'friends'},GUILD_ROSTER_UPDATE={'guild'},PLAYER_GUILD_UPDATE={'guild'},
    GROUP_ROSTER_UPDATE={'group'},UNIT_CONNECTION={'group'},
    PLAYER_ENTERING_WORLD={'bnet','friends','guild','group'},
}
local function fold(v)return Z.Store and Z.Store.Fold(v)or string.lower(tostring(v or''))end
function P.New(adapter)
    return setmetatable({adapter=adapter,sources={},evidence={},probed={},pending={},queued={}},P)
end
function P:Clock()return self.adapter:Clock()end
function P:Key(c)
    if type(c)~='table'then return nil end
    if c.kind=='WHISPER'then return self.adapter:NameKey(c.target)end
    if c.kind=='BN_WHISPER'and type(c.target)=='string'and c.target~=''then return'b:'..fold(c.target)end
end
-- state ('online' / 'offline' / nil), source
function P:Lookup(key)
    if not key then return nil end
    local t=self:Clock();local best,bestAt,source
    for name,s in pairs(self.sources)do
        local state=s.map[key]
        if state~=nil and not(s.ttl and t-s.at>s.ttl)and(not bestAt or s.at>bestAt)then best,bestAt,source=state,s.at,name end
    end
    local e=self.evidence[key]
    if e and t-e.at<=P.EVIDENCE_TTL and(not bestAt or e.at>=bestAt)then best,source=e.state,e.source end
    return best,source
end
function P:State(c)return(self:Lookup(self:Key(c)))end
local function notify(keys)if next(keys)and Z.Changed then Z.Changed('presence',keys)end end
function P:SetSource(name,map,ttl)
    local old=self.sources[name];local oldMap=old and old.map or{};local changed={}
    for k,v in pairs(map)do if oldMap[k]~=v then changed[k]=true end end
    for k in pairs(oldMap)do if map[k]==nil then changed[k]=true end end
    self.sources[name]={map=map,at=self:Clock(),ttl=ttl}
    notify(changed)
end
function P:Observe(key,state,source)
    if not key then return end
    local before=self:Lookup(key)
    self.evidence[key]={state=state,at=self:Clock(),source=source}
    if before~=state then notify({[key]=true})end
end
-- Sources ---------------------------------------------------------------------------------------
local function flag(a,v)if a:Safe(v)and type(v)=='boolean'then return v end end
local function count(a,v,limit)if a:Safe(v)and type(v)=='number'and v>0 then return math.min(math.floor(v),limit)end;return 0 end
function P:ReadBattleNet()
    local a=self.adapter;local p=a.api;local bn=type(p.C_BattleNet)=='table'and p.C_BattleNet or nil
    if not bn then return end
    local map={};local wow=a:Text(p.BNET_CLIENT_WOW)or'WoW'
    for i=1,count(a,a:Call(p.BNGetNumFriends),500)do
        local info=a:Table(a:Call(bn.GetFriendAccountInfo,i))
        local tag=info and a:Text(info.battleTag);local game=info and a:Table(info.gameAccountInfo)
        local online=game and flag(a,game.isOnline)
        if tag and tag~=''and online~=nil then map['b:'..fold(tag)]=online and'online'or'offline'end
        -- A friend playing WoW is also online as that character; the absence of it proves nothing.
        if online and a:Text(game.clientProgram)==wow then
            -- Since Forever 1.60.1 Live-Update 2 reading the realm of a game account can raise an error.
            local realmRead,realmValue=pcall(function()return game.realmName end)
            local realm=realmRead and a:Text(realmValue)or nil;local key=a:NameKey(a:FullName(a:Text(game.characterName),realm and(realm:gsub('%s',''))))
            if key then map[key]='online'end
        end
    end
    self:SetSource('bnet',map)
end
function P:ReadFriends()
    local a=self.adapter;local f=type(a.api.C_FriendList)=='table'and a.api.C_FriendList or nil
    if not f then return end
    local map={}
    for i=1,count(a,a:Call(f.GetNumFriends),200)do
        local info=a:Table(a:Call(f.GetFriendInfoByIndex,i))
        local key=info and a:NameKey(info.name);local connected=info and flag(a,info.connected)
        if key and connected~=nil then map[key]=connected and'online'or'offline'end
    end
    self:SetSource('friends',map)
end
function P:ReadGuild()
    local a=self.adapter;local p=a.api
    if not a.guildScope or type(p.GetGuildRosterInfo)~='function'then self:SetSource('guild',{},P.ROSTER_TTL);return end
    local map={}
    for i=1,count(a,a:Call(p.GetNumGuildMembers),1000)do
        -- The ninth return is the online flag; the adapter call keeps only five values.
        local ok,name,_,_,_,_,_,_,_,online=pcall(p.GetGuildRosterInfo,i)
        local key=ok and a:NameKey(name);online=ok and flag(a,online)
        if key and online~=nil then map[key]=online and'online'or'offline'end
    end
    self:SetSource('guild',map,P.ROSTER_TTL)
end
function P:ReadGroup()
    local a=self.adapter;local p=a.api;local map={}
    local raid=a:Call(p.IsInRaid)==true;local n=count(a,a:Call(p.GetNumGroupMembers),40)
    local prefix=raid and'raid'or'party';local last=raid and n or math.min(4,n-1)
    for i=1,last do
        local unit=prefix..i;local name
        if a.regionalNames then name=a:Text(a:Call(p.GetUnitName,unit,true))end
        if not name then local short,realm=a:Call(p.UnitFullName,unit);name=a:FullName(short,a:Text(realm)~=''and realm or a.me.realm)end
        local key=a:NameKey(name);local connected=flag(a,a:Call(p.UnitIsConnected,unit))
        if key and key~=a:NameKey(a.me.name)and connected~=nil then map[key]=connected and'online'or'offline'end
    end
    self:SetSource('group',map)
end
local readers={bnet=P.ReadBattleNet,friends=P.ReadFriends,guild=P.ReadGuild,group=P.ReadGroup}
function P:Rebuild(name)self.queued[name]=nil;local fn=readers[name];if fn then fn(self)end end
-- Native lists change in bursts: each source is read once REBUILD_DELAY after its first event.
function P:Queue(name)
    if self.queued[name]then return end
    local timer=self.adapter.api.C_Timer;local after=type(timer)=='table'and timer.After
    if type(after)~='function'then self:Rebuild(name);return end
    self.queued[name]=true
    if not pcall(after,P.REBUILD_DELAY,function()self:Rebuild(name)end)then self:Rebuild(name)end
end
-- Native reachability check for one contact, only on demand (a conversation is opened) and only while
-- its state is unknown. It needs the GUID from an earlier incoming message.
local function lastGuid(c)
    local messages=c.messages or{}
    for i=#messages,math.max(1,#messages-50),-1 do
        local m=messages[i];if m and not m.outgoing and type(m.senderGuid)=='string'then return m.senderGuid end
    end
end
function P:Probe(c)
    if type(c)~='table'or c.kind~='WHISPER'then return end
    local key=self:Key(c);if not key or self:Lookup(key)then return end
    local guid=lastGuid(c);if not guid then return end
    local info=self.adapter.api.C_ChatInfo;local fn=type(info)=='table'and info.RequestCanLocalWhisperTarget
    if type(fn)~='function'then return end
    local t=self:Clock();if self.probed[guid]and t-self.probed[guid]<P.PROBE_INTERVAL then return end
    self.probed[guid]=t;self.pending[guid]=key;pcall(fn,guid)
end
function P:OnProbe(guid,status)
    local key=type(guid)=='string'and self.pending[guid];if not key then return end
    self.pending[guid]=nil
    local enum=type(self.adapter.api.Enum)=='table'and self.adapter.api.Enum.ChatWhisperTargetStatus
    enum=type(enum)=='table'and enum or{}
    if not self.adapter:Safe(status)then return end
    if status==(enum.Offline or 2)then self:Observe(key,'offline','probe')
    elseif status==(enum.CanWhisper or 0)or status==(enum.CanWhisperGuild or 1)then self:Observe(key,'online','probe')end
end
function P:OnEvent(event,...)
    if event=='CAN_LOCAL_WHISPER_TARGET_RESPONSE'then self:OnProbe(...);return end
    local list=SOURCES[event];if not list then return end
    for _,name in ipairs(list)do self:Queue(name)end
end
return P
