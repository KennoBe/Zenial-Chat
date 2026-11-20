-- Native chat boundary. All sends run synchronously from the caller's hardware action.
local _,Z=...
local A={};Z.Adapter=A;A.__index=A
local unpack=unpack
local groups={PARTY=true,RAID=true,INSTANCE_CHAT=true}
local labels={GUILD='Guild',OFFICER='Officers',PARTY='Party',RAID='Raid',INSTANCE_CHAT='Instance'}
local germanLabels={GUILD='Gilde',OFFICER='Offizier',PARTY='Gruppe',RAID='Schlachtzug',INSTANCE_CHAT='Instanz'}
local function L(de,en)return Z.L and Z.L(de,en)or en end
-- A guild conversation is named after its guild: "ZENIAL – Chat", "ZENIAL – Offizier-Chat". The key never uses the name.
local guildSuffix={GUILD={'Chat','Chat'},OFFICER={'Offizier-Chat','Officer chat'}}
local function label(kind,guild)
 local suffix=type(guild)=='string'and guild~=''and guildSuffix[kind]
 if suffix then return guild..' – '..L(suffix[1],suffix[2])end
 return Z.L and Z.L(germanLabels[kind],labels[kind])or labels[kind]
end
A.Label=label
local guildKinds={GUILD=true,OFFICER=true}
-- Officer privileges of a rank (C_GuildInfo.GuildControlGetRankFlags). The Forever guild control has one
-- officer flag that grants the officer channel; there is no separate listen or speak flag.
A.OFFICER_FLAG=22
A.events={'PLAYER_ENTERING_WORLD','PLAYER_GUILD_UPDATE','GROUP_ROSTER_UPDATE','CHANNEL_UI_UPDATE','CHANNEL_COUNT_UPDATE',
 'BN_FRIEND_INFO_CHANGED','BN_FRIEND_ACCOUNT_ONLINE','BN_FRIEND_ACCOUNT_OFFLINE',
 'CHAT_MSG_WHISPER','CHAT_MSG_WHISPER_INFORM','CHAT_MSG_BN_WHISPER','CHAT_MSG_BN_WHISPER_INFORM',
 'CHAT_MSG_GUILD','CHAT_MSG_OFFICER','CHAT_MSG_PARTY','CHAT_MSG_PARTY_LEADER','CHAT_MSG_RAID','CHAT_MSG_RAID_LEADER',
 'CHAT_MSG_INSTANCE_CHAT','CHAT_MSG_INSTANCE_CHAT_LEADER','CHAT_MSG_RAID_WARNING','CHAT_MSG_CHANNEL','CHAT_MSG_SYSTEM',
 'CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE','CHAT_MSG_RESTRICTED','CHAT_MSG_CHANNEL_NOTICE_USER',
 'GUILD_RANKS_UPDATE','GUILD_ROSTER_UPDATE','FRIENDLIST_UPDATE','UNIT_CONNECTION','CAN_LOCAL_WHISPER_TARGET_RESPONSE'}
-- Status-only events: they update the online status and never redraw the whole window.
A.quiet={BN_FRIEND_INFO_CHANGED=true,BN_FRIEND_ACCOUNT_ONLINE=true,BN_FRIEND_ACCOUNT_OFFLINE=true,GUILD_ROSTER_UPDATE=true,
 FRIENDLIST_UPDATE=true,UNIT_CONNECTION=true,CAN_LOCAL_WHISPER_TARGET_RESPONSE=true}
function A:Safe(...)
 for i=1,select('#',...)do local v=select(i,...)
  if type(self.api.issecretvalue)=='function'then local ok,secret=pcall(self.api.issecretvalue,v);if not ok or secret then return false end end
 end
 if Z.Safe then local ok,safe=pcall(Z.Safe,...);if not ok or not safe then return false end end
 return true
end
function A:Call(fn,...)
 if type(fn)~='function'then return nil end
 local r={pcall(fn,...)};if not r[1]then return nil end
 return unpack(r,2,6)
end
function A:Text(v)return self:Safe(v)and type(v)=='string'and v or nil end
function A:Table(v)return self:Safe(v)and type(v)=='table'and v or nil end
local function now()return Z.Now and Z.Now()or time and time()or 0 end
local function clock()return Z.Clock and Z.Clock()or now()end
local function changed(reason,key)if Z.Changed then Z.Changed(reason,key)end end
function A.New(store,api)
 local self=setmetatable({store=store,api=api or _G,me={},attempts={},recoveries={},serial=0,session=tostring(now())..':'..tostring(clock()),access={}},A)
 if Z.Presence then self.presence=Z.Presence.New(self)end
 self:MigrateGuilds();self:RefreshIdentity();return self
end
function A:Clock()return clock()end
function A:FullName(name,realm)
 name=self:Text(name);realm=self:Text(realm)
 if not name or name==''then return nil end
 -- Native full-name strings remain intact, including multi-hyphen Forever names.
 if not self.regionalNames and not name:find('-',1,true)and realm and realm~=''then return name..'-'..realm end
 return name
end
function A:Scope()return(self.me.realm or'?')..':'..(self.me.faction or'?')end
local function unusedGuildConversation(c)
 return c and next(c.messages)==nil and c.draft==''and c.unread==0 and c.last==0
  and not(c.pinned or c.muted or c.alias or c.notify or c.keep)and(not c.sent or next(c.sent)==nil)
end
function A:RefreshIdentity()
 local p=self.api
 local _,_,_,build=self:Call(p.GetBuildInfo)
 self.regionalNames=self:Call(p.RegionalUniqueNamesEnabled)==true or build==16001
 local name,realm=self:Call(p.UnitFullName,'player')
 if not self:Text(name)then name,realm=self:Call(p.UnitName,'player')end
 if self.regionalNames then
  local native=self:Text(self:Call(p.GetUnitName,'player',true))
  name=native or(self:Text(name)and self:Text(realm)and name..' '..realm)or name
  realm=self:Call(p.GetRealmName)
 end
 realm=self:Text(realm);if not realm or realm==''then realm=self:Text(self:Call(p.GetRealmName))end
 local _,class=self:Call(p.UnitClass,'player')
 self.me={name=self:FullName(name,realm),realm=realm,faction=self:Text(self:Call(p.UnitFactionGroup,'player')),guid=self:Text(self:Call(p.UnitGUID,'player')),classFile=self:Text(class)}
 self:RefreshGuild(realm)
 local instance=p.LE_PARTY_CATEGORY_INSTANCE or 2
 local inInstance=self:Call(p.IsInGroup,instance)==true
 local category=inInstance and instance or p.LE_PARTY_CATEGORY_HOME or 1
 local raid=self:Call(p.IsInRaid,category)==true
 local kind=inInstance and'INSTANCE_CHAT'or raid and'RAID'or self:Call(p.IsInGroup)==true and'PARTY'or nil
 self.groupKind=kind
 local signature={kind or'none'}
 local n=self:Call(p.GetNumGroupMembers,category);if not self:Safe(n)or type(n)~='number'then n=0 end
 if kind then
  signature[#signature+1]=self.me.guid or self.me.name or'?'
  for i=1,math.min(n,40)do local guid=self:Text(self:Call(p.UnitGUID,(raid and'raid'or'party')..i));if guid then signature[#signature+1]=guid end end
  table.sort(signature)
 end
 signature=table.concat(signature,'|')
 local previous=self.groupSignature;self.groupSignature=signature
 local previousConversation=self.groupConversation;self.groupConversation=nil
 if kind then
  local conv=self.store:Ensure({kind=kind,name=label(kind),scope=self.me.name or self:Scope()})
  self.groupConversation=conv
 end
 if previous and previous~=signature then
  local function marker(conv)
   if not conv then return end
   self.serial=self.serial+1;self.store:Append(conv,{id='context:'..self.session..':'..self.serial,at=now(),sender='',text=Z.L and Z.L('Gruppenzusammensetzung geändert','Group composition changed')or'Group composition changed',context=true,outgoing=false},true)
  end
  marker(previousConversation)
  if self.groupConversation~=previousConversation then marker(self.groupConversation)end
 end
 if self.store.settings.publicChannels then for _,ch in ipairs(self:JoinedChannels())do if ch.selected then self:ChannelConversation(ch.name)end end end
 self:SanitizeSelection()
 changed('identity')
end
-- Guilds ---------------------------------------------------------------------------------------
-- db.guilds[scope] holds what is known about a guild: name, realm, club id. The scope (club id, else
-- realm and name) stays the key of its conversations; the name is only shown.
local function guildBook(self)
 local book=self.store.db.guilds;if type(book)~='table'then book={};self.store.db.guilds=book end;return book
end
function A:Guild(scope)
 local book=self.store.db.guilds;local g=type(book)=='table'and type(scope)=='string'and book[scope]
 return type(g)=='table'and g or nil
end
-- A realm-and-name scope that a club id has since replaced belongs to that club's guild.
function A:CanonicalScope(scope)
 local links=self.store.db.guildScopes;local linked=type(links)=='table'and type(scope)=='string'and links[scope]
 return type(linked)=='string'and linked or scope
end
-- Older versions stored no guild names. A realm-and-name scope carries both; a club scope only through its
-- proven link. Anything else stays an unknown guild: nothing is guessed and nothing is merged.
function A:MigrateGuilds()
 local book=guildBook(self);local links={}
 if type(self.store.db.guildScopes)=='table'then
  for fallback,scope in pairs(self.store.db.guildScopes)do
   if type(fallback)=='string'and type(scope)=='string'and(not links[scope]or fallback<links[scope])then links[scope]=fallback end
  end
 end
 for _,c in pairs(self.store.conversations)do
  if guildKinds[c.kind]and type(c.scope)=='string'and c.scope~=''and type(book[c.scope])~='table'then
   local club=c.scope:match('^club:(.+)$')
   local source=club and links[c.scope]or not club and c.scope or nil
   local realm,name
   if source then realm,name=source:match('^(.-):(.+)$')end
   if name then book[c.scope]={name=name,realm=realm~=''and realm~='?'and realm or nil,club=club,fallback=source}
   else book[c.scope]={club=club,unknown=true}end
  end
 end
 for _,c in pairs(self.store.conversations)do
  local g=guildKinds[c.kind]and self:Guild(c.scope)
  if g and type(g.name)=='string'then c.name=label(c.kind,g.name)end
 end
end
-- The game reports a guild before its name only while the data is still loading: IsInGuild() is true, the name is nil.
function A:RefreshGuild(realm)
 local p=self.api
 local guild,_,_,guildRealm=self:Call(p.GetGuildInfo,'player');guild=self:Text(guild)
 local previousScope=self.guildScope
 self.guildPending=not guild and self:Call(p.IsInGuild)==true or nil
 if self.guildPending then return end
 local club=self:Call(p.C_Club and p.C_Club.GetGuildClubId)
 local fallback=guild and(self:Text(guildRealm)or realm or'?')..':'..guild
 local known=type(self.store.db.guildScopes)=='table'and self.store.db.guildScopes
 self.guildScope=nil
 if fallback then
  if self:Safe(club)and club then
   self.guildScope='club:'..tostring(club)
   -- Both native identifiers are known together; reuse that proven link across reloads.
   if not known then known={};self.store.db.guildScopes=known end
   known[fallback]=self.guildScope
  else self.guildScope=known and type(known[fallback])=='string'and known[fallback]or fallback end
  local book=guildBook(self);local g=type(book[self.guildScope])=='table'and book[self.guildScope]or{}
  -- A renamed guild keeps its club id: the name changes, the conversations stay.
  g.name=guild;g.realm=self:Text(guildRealm)or realm;g.fallback=fallback;g.unknown=nil
  if self:Safe(club)and club then g.club=tostring(club)end
  book[self.guildScope]=g
 end
 if previousScope~=self.guildScope then self.guildView=nil;self.officerHeard=nil end
 self:RefreshAccess(true)
 if not self.guildScope then return end
 for _,kind in ipairs({'GUILD','OFFICER'})do
  -- Without the officer right no active officer conversation is created; a stored one stays untouched.
  local canonical=(kind=='GUILD'or self.access.officerRead)and self.store:Ensure({kind=kind,name=label(kind,guild),scope=self.guildScope})or nil
  if not canonical then
   local stored=self.store:Get(Z.Store.Key({kind=kind,scope=self.guildScope}))
   if stored then stored.name=label(kind,guild)end
  end
  if fallback~=self.guildScope then
   local previous=self.store:Get(Z.Store.Key({kind=kind,scope=fallback}))
   -- Keep every archive and individual choice; only hide completely unused duplicates.
   if unusedGuildConversation(previous)then
    self.store:SetClosed(previous.key,true)
    if canonical and self.store.ui.selected==previous.key then self.store:Select(canonical.key)end
   end
  end
 end
end
-- What the own rank may do. Unknown stays unknown and grants nothing.
function A:ReadAccess()
 local access={}
 if not self.guildScope then return access end
 local p=self.api;local gi=type(p.C_GuildInfo)=='table'and p.C_GuildInfo or nil
 local function flag(v)if self:Safe(v)and type(v)=='boolean'then return v end end
 access.guildWrite=gi and flag(self:Call(gi.CanSpeakInGuildChat))
 local rank=gi and self.me.guid and self:Call(gi.GetGuildRankOrder,self.me.guid)
 if not(self:Safe(rank)and type(rank)=='number')then
  local _,_,index=self:Call(p.GetGuildInfo,'player');rank=self:Safe(index)and type(index)=='number'and index+1 or nil
 end
 local officer
 if rank==1 then officer=true -- the guild master holds every right
 else
  local flags=gi and rank and self:Table(self:Call(gi.GuildControlGetRankFlags,rank))
  -- No fallback to IsGuildOfficer: what it is derived from is not documented (possibly officer notes).
  officer=flags and flag(flags[A.OFFICER_FLAG])
 end
 access.officerWrite=officer==true
 -- The server sends officer messages only to ranks that may read them.
 access.officerRead=officer==true or self.officerHeard==self.guildScope
 access.officerKnown=officer~=nil
 return access
end
local function accessSignature(a)
 return tostring(a.guildWrite)..'|'..tostring(a.officerRead)..'|'..tostring(a.officerWrite)
end
-- Called on identity, rank and roster changes; quiet unless the rights really changed.
function A:RefreshAccess(silent)
 if self.guildPending then return false end
 local before=accessSignature(self.access or{})
 self.access=self:ReadAccess()
 if accessSignature(self.access)==before then return false end
 if self.guildScope and self.access.officerRead then
  local g=self:Guild(self.guildScope)
  self.store:Ensure({kind='OFFICER',name=label('OFFICER',g and g.name),scope=self.guildScope})
 end
 if not silent then self:SanitizeSelection();changed('access')end
 return true
end
-- The guild the sidebar shows: the current one unless an archive was chosen.
function A:GuildView()return self.guildView or self.guildScope end
function A:SetGuildView(scope)
 if type(scope)~='string'or scope==self.guildScope then scope=nil end
 if self.guildView==scope then return end
 self.guildView=scope;self:SanitizeSelection();changed('guildview')
end
-- One rule for every view and for sending. Returns listed, writable, reason:
-- reason 'archive' (another or a former guild, read only), 'permission' (no right to write),
-- 'officer' (no right to read the officer chat), 'xfaction' (read-only opposite faction).
function A:Access(c)
 if type(c)~='table'then return false,false end
 if c.kind=='XFACTION'then return true,false,'xfaction'end
 if not guildKinds[c.kind]then return true,true end
 local scope=self:CanonicalScope(c.scope);local view=self:GuildView()
 local listed=view~=nil and scope==view
 if self.guildScope and scope==self.guildScope then
  local a=self.access or{}
  if c.kind=='OFFICER'and not a.officerRead then return false,false,'officer'end
  if c.scope~=self.guildScope then return listed,false,'archive'end
  local write=c.kind=='OFFICER'and a.officerWrite==true or c.kind=='GUILD'and a.guildWrite~=false
  return listed,write,not write and'permission'or nil
 end
 return listed,false,'archive'
end
function A:Listed(c)return(self:Access(c))==true end
function A:CanWrite(c)local _,write=self:Access(c);return write==true end
function A:ReadOnlyText(reason)
 if reason=='archive'then return L('Chatarchiv · Nur lesen','Chat archive · Read only')end
 if reason=='permission'then return L('Nur lesen · Dein Rang darf hier nicht schreiben','Read only · Your rank may not write here')end
 if reason=='officer'then return L('Gilde nicht verfügbar.','Guild is unavailable.')end
end
-- A selected guild conversation that the current view no longer shows moves to the same chat of the
-- viewed guild, else to its guild chat, else the selection is cleared.
function A:SanitizeSelection()
 if self.guildPending then return end
 local store=self.store;local c=store:Get(store.ui.selected)
 if not c or not guildKinds[c.kind]or self:Listed(c)then return end
 local view=self:GuildView();local target
 if view then
  for _,kind in ipairs({c.kind,'GUILD'})do
   local candidate=not target and store:Get(Z.Store.Key({kind=kind,scope=view}))
   if candidate and self:Listed(candidate)then target=candidate end
  end
 end
 store:Select(target and target.key or nil)
end
-- The stored guilds for the picker: the current one first, then the archives by name.
function A:GuildList()
 local out,seen={},{}
 if self.guildScope then seen[self.guildScope]=true;out[1]={scope=self.guildScope,current=true}end
 local archives={}
 for _,c in pairs(self.store.conversations)do
  if guildKinds[c.kind]and type(c.scope)=='string'and not(c.closed and next(c.messages)==nil)then
   local scope=self:CanonicalScope(c.scope)
   if not seen[scope]then seen[scope]=true;archives[#archives+1]={scope=scope}end
  end
 end
 local names={}
 table.sort(archives,function(a,b)return a.scope<b.scope end)
 for _,entry in ipairs(archives)do out[#out+1]=entry end
 for _,entry in ipairs(out)do
  local g=self:Guild(entry.scope)
  entry.name=g and type(g.name)=='string'and g.name or nil;entry.realm=g and type(g.realm)=='string'and g.realm or nil
  if entry.name then names[entry.name]=(names[entry.name]or 0)+1 end
 end
 local unknown=0
 for _,entry in ipairs(out)do
  if entry.name then entry.label=names[entry.name]>1 and entry.realm and entry.name..' ('..entry.realm..')'or entry.name
  else unknown=unknown+1;entry.label=L('Unbekannte Gilde','Unknown guild')..(unknown>1 and' '..unknown or'')end
 end
 table.sort(archives,function(a,b)if a.label~=b.label then return a.label<b.label end;return a.scope<b.scope end)
 for i,entry in ipairs(archives)do out[(self.guildScope and 1 or 0)+i]=entry end
 return out
end
-- Roster/channel events arrive in bursts: one refresh runs IDENTITY_DELAY after the
-- first trigger (bounded, never postponed). Without a timer API it runs at once.
A.IDENTITY_DELAY=.5
function A:QueueIdentity()
 if self.identityQueued then return end
 local timer=self.api.C_Timer;local after=type(timer)=='table'and timer.After
 if type(after)~='function'then self:RefreshIdentity();return end
 self.identityQueued=true
 local ok=pcall(after,A.IDENTITY_DELAY,function()self.identityQueued=false;self:RefreshIdentity()end)
 if not ok then self.identityQueued=false;self:RefreshIdentity()end
end
function A:ChannelConversation(name)
 return self.store:Ensure({kind='CHANNEL',name=name,channelName=name,scope=self:Scope()})
end
function A:JoinedChannels()
 local r={}
 -- GetChannelList has a variable return count, unlike ordinary adapter calls.
 if type(self.api.GetChannelList)=='function'then local raw={pcall(self.api.GetChannelList)};if raw[1]then table.remove(raw,1);r=raw end end
 local result={};local numbers={}
 for i=1,#r,3 do local id,name=r[i],self:Text(r[i+1]);if self:Safe(id)and type(id)=='number'and id>0 and name then numbers[name:lower()]=id;result[#result+1]={id=id,name=name,selected=self.store.settings.enabledChannels[name:lower()]==true}end end
 self.channelNumbers=numbers
 return result
end
-- The current number of a joined channel. Numbers change when channels are reordered.
function A:ChannelNumber(name)
 name=self:Text(name);if not name then return nil end
 if not self.channelNumbers then self:JoinedChannels()end
 return self.channelNumbers and self.channelNumbers[name:lower()]
end
function A:SetChannel(name,enabled)
 name=self:Text(name);if not name or name==''then return false end
 self.store.settings.enabledChannels[name:lower()]=enabled==true
 if enabled and self.store.settings.publicChannels then self:ChannelConversation(name)end
 changed('channels');return true
end
function A:Account(id)
 if not self:Safe(id)or type(id)~='number'or id<=0 then return nil end
 local t=self:Table(self:Call(self.api.C_BattleNet and self.api.C_BattleNet.GetAccountInfoByID,id))
 if not t then return nil end
 local tag=self:Text(t.battleTag);if not tag or tag==''then return nil end
 return tag,self:Text(t.accountName)or tag,t
end
function A:ResolveAccount(tag)
 local p=self.api;local n=self:Call(p.BNGetNumFriends);if not self:Safe(n)or type(n)~='number'then return nil end
 for i=1,n do local info=self:Table(self:Call(p.C_BattleNet and p.C_BattleNet.GetFriendAccountInfo,i))
  if info and self:Text(info.battleTag)and info.battleTag:lower()==tag:lower()and self:Safe(info.bnetAccountID)then return info.bnetAccountID end
 end
end
function A:NewAttempt(c,text)
 self.serial=self.serial+1
 local a={id='attempt:'..self.session..':'..self.serial,key=c.key,text=text,kind=c.kind,target=c.target,at=clock(),state='pending'}
 self.attempts[#self.attempts+1]=a;return a
end
function A:Confirm(c,text)
 for i,a in ipairs(self.attempts)do if a.state=='pending'and a.key==c.key and a.text==text then a.state='confirmed';table.remove(self.attempts,i);return a end end
end
-- code names a known reason ('offline'). Then the text goes back into an empty draft at once (restored);
-- the recovery button stays the fallback for everything else.
function A:FailAttempt(a,errorText,code)
 if not a or a.state~='pending'then return end
 a.state='failed';local r={id=a.id,text=a.text,error=errorText or L('Senden fehlgeschlagen','Send failed'),key=a.key,code=code}
 local c=code and self.store:Get(a.key)
 if c and(c.draft or'')==''then self.store:SetDraft(c.key,a.text);r.restored=true end
 self.recoveries[#self.recoveries+1]=r;changed('recovery',a.key)
end
-- The game answers every send in order, so the oldest pending send of one conversation is the one that
-- failed. Matches in different conversations are never guessed. Returns the failed attempt.
function A:FailMatching(predicate,errorText,code)
 local match
 for _,a in ipairs(self.attempts)do
  if a.state=='pending'and clock()-a.at<=10 and predicate(a)then
   if not match then match=a elseif a.key~=match.key then return end
  end
 end
 self:FailAttempt(match,errorText,code);return match
end
local fold=function(v)return Z.Store and Z.Store.Fold(v)or string.lower(tostring(v or''))end
-- One comparable form of a character name: markup removed, the own realm added where the game leaves it
-- out, letters folded. Regional Forever names stay whole (a surname is never a realm).
function A:NameKey(name)
 name=self:Text(name);if not name or name==''then return nil end
 if name:find('|',1,true)and Z.Plain then name=Z.Plain(name)end
 name=name:match('^%s*(.-)%s*$');if name==''then return nil end
 return'w:'..fold(self:FullName(name,self.me.realm)or name)
end
-- True only when the client reports the chat lockdown with exactly true.
function A:Locked()
 local info=self.api.C_ChatInfo;return self:Call(type(info)=='table'and info.InChatMessagingLockdown or nil)==true
end
-- Opens the game's own chat line for a reply; the player sends from there. Returns opened, carried:
-- carried is true only when the text went into that line (the plain tell and Battle.net take none).
function A:OpenNative(c,text)
 local u=self.api.ChatFrameUtil;if type(c)~='table'or type(u)~='table'then return false,false end
 if c.kind=='WHISPER'then
  if type(u.SendTellWithMessage)=='function'then local ok=pcall(u.SendTellWithMessage,c.target,type(text)=='string'and text or'');return ok,ok end
  if type(u.SendTell)=='function'then return(pcall(u.SendTell,c.target)),false end
 elseif c.kind=='BN_WHISPER'and type(u.SendBNetTell)=='function'then return(pcall(u.SendBNetTell,c.name)),false end
 return false,false
end
-- 'pending' or 'failed'; nil once confirmed (the echo removes the attempt) or when the id is unknown.
function A:AttemptState(id)
 for _,a in ipairs(self.attempts)do if a.id==id and(a.state=='pending'or a.state=='failed')then return a.state end end
end
function A:Recoveries(key)
 local out={};for _,r in ipairs(self.recoveries)do if r.key==key then out[#out+1]=r end end
 -- Lack of an echo proves no failure. Keep the original available for a manual decision.
 for _,a in ipairs(self.attempts)do
  if a.key==key and a.state=='pending'and not a.reminderDismissed and clock()-a.at>10 then
   out[#out+1]={id=a.id,text=a.text,key=a.key,error=Z.L and Z.L('Zustellung unbestätigt','Delivery unconfirmed')or'Delivery unconfirmed',unconfirmed=true}
  end
 end
 return out
end
function A:DismissRecovery(id)
 for i=#self.recoveries,1,-1 do if self.recoveries[i].id==id then table.remove(self.recoveries,i);changed('recovery');return end end
 for _,a in ipairs(self.attempts)do if a.id==id and a.state=='pending'then a.reminderDismissed=true;changed('recovery',a.key);return end end
end
-- opts.force sends to a contact that is known to be offline (the player confirmed it). The fourth return
-- value names a refusal the caller can act on: 'offline' or 'readonly'.
function A:Send(c,text,opts)
 if not c or not self:Text(text)or not text:find('%S')then return false,L('Gib eine Nachricht ein.','Enter a message.')end
 -- The last word on read-only conversations, whatever the window shows.
 if guildKinds[c.kind]then
  local _,write,reason=self:Access(c)
  if not write then return false,self:ReadOnlyText(reason)or L('Gilde nicht verfügbar.','Guild is unavailable.'),nil,'readonly'end
 end
 local max=c.kind=='BN_WHISPER'and 500 or 255
 if #text>max then return false,L('Nachricht überschreitet das native Limit ('..max..' Bytes).','Message exceeds the native limit ('..max..' bytes).')end
 local p=self.api;local fn,target
 if c.kind=='BN_WHISPER'then target=c.target and self:ResolveAccount(c.target);fn=p.C_BattleNet and p.C_BattleNet.SendWhisper or p.BNSendWhisper
 elseif c.kind=='WHISPER'then target=c.target;fn=p.C_ChatInfo and p.C_ChatInfo.SendChatMessage or p.SendChatMessage
 elseif c.kind=='CHANNEL'then
  if not self.store.settings.publicChannels or not self.store.settings.enabledChannels[(c.channelName or''):lower()]or c.scope~=self:Scope()then return false,L('Kanal ist deaktiviert.','Channel is disabled.')end
  for _,ch in ipairs(self:JoinedChannels())do if ch.name:lower()==c.channelName:lower()then target=ch.id end end
  fn=p.C_ChatInfo and p.C_ChatInfo.SendChatMessage or p.SendChatMessage
 elseif c.kind=='GUILD'or c.kind=='OFFICER'then
  if not self.guildScope or c.scope~=self.guildScope then return false,L('Gilde nicht verfügbar.','Guild is unavailable.')end
  fn=p.C_ChatInfo and p.C_ChatInfo.SendChatMessage or p.SendChatMessage
 elseif groups[c.kind]then
  if c.kind~=self.groupKind or c.scope~=(self.me.name or self:Scope())then return false,L('Diese Gruppe ist nicht verfügbar.','This group is unavailable.')end
  fn=p.C_ChatInfo and p.C_ChatInfo.SendChatMessage or p.SendChatMessage
 else return false,L('Nicht unterstütztes Gespräch.','Unsupported conversation.')end
 if type(fn)~='function'or((c.kind=='WHISPER'or c.kind=='BN_WHISPER'or c.kind=='CHANNEL')and not target)then return false,L('Empfänger nicht verfügbar.','Recipient is unavailable.')end
 -- Only a reliably known offline state warns first; unknown is never treated as offline.
 if(c.kind=='WHISPER'or c.kind=='BN_WHISPER')and not(opts and opts.force)and self.presence and self.presence:State(c)=='offline'then
  return false,string.format(L('%s ist offline. Noch einmal senden, um es trotzdem zu versuchen.','%s is offline. Send again to try anyway.'),c.alias or c.name or'?'),nil,'offline'
 end
 local a=self:NewAttempt(c,text);local ok,result
 if c.kind=='BN_WHISPER'then ok,result=pcall(fn,target,text)else ok,result=pcall(fn,text,c.kind,nil,target)end
 if not ok or result==false then a.state='failed';return false,self:Text(result)or L('Senden fehlgeschlagen.','Send failed.'),a.id end
 return true,nil,a.id
end
function A:OnEvent(event,...)
 if self.presence then self.presence:OnEvent(event,...)end
 if event=='PLAYER_ENTERING_WORLD'or event=='PLAYER_GUILD_UPDATE'or event=='GROUP_ROSTER_UPDATE'or event=='CHANNEL_UI_UPDATE'or event=='CHANNEL_COUNT_UPDATE'then self:QueueIdentity();return end
 -- Rank and roster updates change rights only; while the guild name is still loading they complete the identity.
 if event=='GUILD_ROSTER_UPDATE'or event=='GUILD_RANKS_UPDATE'then if self.guildPending then self:QueueIdentity()else self:RefreshAccess()end;return end
 if self.guildPending and(event=='CHAT_MSG_GUILD'or event=='CHAT_MSG_OFFICER')then self:QueueIdentity()end
 if A.quiet[event]then return end
 local args={...}
 if event=='CHAT_MSG_SYSTEM'then
  -- The native not-found format carries the target as the game wrote it: with or without the own realm,
  -- in its own capitalisation. Both sides are compared in one form; other system errors are unrelated.
  local fmt=self:Text(self.api.ERR_CHAT_PLAYER_NOT_FOUND_S);local text=self:Text(args[1])
  if fmt and text then local pattern=fmt:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1'):gsub('%%%%s','(.+)');local target=text:match('^'..pattern..'$')
   local key=target and self:NameKey(target)
   if key then
    self:FailMatching(function(a)return a.kind=='WHISPER'and self:NameKey(a.target)==key end,L('Spieler ist nicht online – Nachricht nicht gesendet.','Player is not online – message not sent.'),'offline')
    if self.presence then self.presence:Observe(key,'offline','error')end
   end
  end;return
 end
 if event=='CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE'then
  local tag=self:Account(args[13])
  if tag then
   local text=self:Text(args[1]);local want=tag:lower()
   local function same(a)return a.kind=='BN_WHISPER'and type(a.target)=='string'and a.target:lower()==want end
   local reason=L('Battle.net-Freund ist offline – Nachricht nicht gesendet.','Battle.net friend is offline – message not sent.')
   -- The event repeats the refused text where the client provides it; that names the send exactly.
   if not(text and self:FailMatching(function(a)return same(a)and a.text==text end,reason,'offline'))then self:FailMatching(same,reason,'offline')end
   if self.presence then self.presence:Observe('b:'..fold(tag),'offline','error')end
  end;return
 end
 if event=='CHAT_MSG_RESTRICTED'then return end -- No attempt token or reliable target.
 local kind=event:match('^CHAT_MSG_(.+)$');if not kind then return end
 local inform=kind=='WHISPER_INFORM'or kind=='BN_WHISPER_INFORM'
 kind=kind:gsub('_INFORM$',''):gsub('_LEADER$','')
 -- A raid warning belongs to the group it was sent in; it has no conversation of its own.
 local raidWarning=kind=='RAID_WARNING'
 if raidWarning then kind=self.groupKind;if not kind then return end end
 if not(labels[kind]or kind=='WHISPER'or kind=='BN_WHISPER'or kind=='CHANNEL')then return end
 local text,sender=self:Text(args[1]),self:Text(args[2]);if not text or not sender then return end
 local c
 if kind=='WHISPER'then local target=self:FullName(sender,self.me.realm);c=self.store:Ensure({kind=kind,target=target,name=sender,scope=self.me.realm})
 elseif kind=='BN_WHISPER'then local tag,name=self:Account(args[13]);if not tag then return end;c=self.store:Ensure({kind=kind,target=tag,name=name})
 elseif kind=='CHANNEL'then
  local base=self:Text(args[9]);if not base or not self.store.settings.publicChannels or not self.store.settings.enabledChannels[base:lower()]then return end
  c=self:ChannelConversation(base)
 elseif kind=='GUILD'or kind=='OFFICER'then
  if not self.guildScope then return end
  local g=self:Guild(self.guildScope);c=self.store:Ensure({kind=kind,name=label(kind,g and g.name),scope=self.guildScope})
 else if not self.groupKind or kind~=self.groupKind then return end;c=self.store:Ensure({kind=kind,name=label(kind),scope=self.me.name or self:Scope()})end
 local guid=self:Text(args[12]);local outgoing=inform or guid and guid==self.me.guid or sender==self.me.name
 -- A received officer message proves the right to read; writing still needs the rank flag.
 if kind=='OFFICER'and not outgoing and self.officerHeard~=self.guildScope then self.officerHeard=self.guildScope;self:RefreshAccess()end
 -- A whisper or its echo shows the partner online at this moment.
 if self.presence and(kind=='WHISPER'or kind=='BN_WHISPER')then
  self.presence:Observe(kind=='WHISPER'and self:NameKey(c.target)or'b:'..fold(c.target),'online','message')
 end
 local senderClass
 if not outgoing and guid and guid:match('^Player%-')then
  local localClass,class,localRace,race,sex=self:Call(self.api.GetPlayerInfoByGUID,guid);senderClass=self:Text(class)
  if senderClass==''then senderClass=nil end
  -- Only a direct conversation has one person: a group must not take on the class of its last speaker.
  if senderClass and c.kind=='WHISPER'then c.classFile=senderClass end
  race=self:Text(race)
  if senderClass then
   self.store:SetPerson(sender,{class=senderClass,className=self:Text(localClass),race=race~=''and race or nil,raceName=self:Text(localRace),sex=self:Safe(sex)and type(sex)=='number'and sex or nil})
  end
 end
 if outgoing then self:Confirm(c,text)end
 self.serial=self.serial+1;local line=self:Safe(args[11])and args[11]
 local id=line and line~=0 and'chat:'..self:Scope()..':'..self.session..':'..tostring(line)or'local:'..self.session..':'..self.serial
 local row={id=id,at=now(),sender=outgoing and self.me.name or sender,text=text,outgoing=outgoing==true,ownCharacter=outgoing and self.me.name or nil,senderClass=outgoing and self.me.classFile or senderClass,senderGuid=not outgoing and guid and guid:match('^Player%-')and guid or nil,raidWarning=raidWarning or nil}
 local msg,added=self.store:Append(c,row,Z.IsVisibleAtEnd and Z.IsVisibleAtEnd(c.key)or false)
 return c,msg,added
end
