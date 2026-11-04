-- Native chat boundary. All sends run synchronously from the caller's hardware action.
local _,Z=...
local A={};Z.Adapter=A;A.__index=A
local unpack=unpack
local groups={PARTY=true,RAID=true,INSTANCE_CHAT=true}
local labels={GUILD='Guild',OFFICER='Officers',PARTY='Party',RAID='Raid',INSTANCE_CHAT='Instance'}
local germanLabels={GUILD='Gilde',OFFICER='Offizier',PARTY='Gruppe',RAID='Schlachtzug',INSTANCE_CHAT='Instanz'}
local function label(kind)return Z.L and Z.L(germanLabels[kind],labels[kind])or labels[kind]end
A.events={'PLAYER_ENTERING_WORLD','PLAYER_GUILD_UPDATE','GROUP_ROSTER_UPDATE','CHANNEL_UI_UPDATE','CHANNEL_COUNT_UPDATE',
 'BN_FRIEND_INFO_CHANGED','BN_FRIEND_ACCOUNT_ONLINE','BN_FRIEND_ACCOUNT_OFFLINE',
 'CHAT_MSG_WHISPER','CHAT_MSG_WHISPER_INFORM','CHAT_MSG_BN_WHISPER','CHAT_MSG_BN_WHISPER_INFORM',
 'CHAT_MSG_GUILD','CHAT_MSG_OFFICER','CHAT_MSG_PARTY','CHAT_MSG_PARTY_LEADER','CHAT_MSG_RAID','CHAT_MSG_RAID_LEADER',
 'CHAT_MSG_INSTANCE_CHAT','CHAT_MSG_INSTANCE_CHAT_LEADER','CHAT_MSG_CHANNEL','CHAT_MSG_SYSTEM',
 'CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE','CHAT_MSG_RESTRICTED','CHAT_MSG_CHANNEL_NOTICE_USER',
 'CLUB_ADDED','CLUB_REMOVED','CLUB_UPDATED','CLUB_MEMBER_UPDATED','CLUB_STREAM_ADDED','CLUB_STREAM_REMOVED','CLUB_STREAM_UPDATED',
 'CLUB_MESSAGE_ADDED','CLUB_MESSAGE_UPDATED','CLUB_MESSAGE_HISTORY_RECEIVED','CLUB_ERROR','INITIAL_CLUBS_LOADED'}
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
local function L(de,en)return Z.L and Z.L(de,en)or en end
local function now()return Z.Now and Z.Now()or time and time()or 0 end
local function clock()return Z.Clock and Z.Clock()or now()end
local function changed(reason,key)if Z.Changed then Z.Changed(reason,key)end end
function A.New(store,api)
 local self=setmetatable({store=store,api=api or _G,me={},attempts={},recoveries={},serial=0,session=tostring(now())..':'..tostring(clock())},A)
 if Z.Community then self.community=Z.Community.New(self,store,self.api)end
 self:RefreshIdentity();return self
end
function A:FullName(name,realm)
 name=self:Text(name);realm=self:Text(realm)
 if not name or name==''then return nil end
 -- Native full-name strings remain intact, including multi-hyphen Forever names.
 if not self.regionalNames and not name:find('-',1,true)and realm and realm~=''then return name..'-'..realm end
 return name
end
function A:Scope()return(self.me.realm or'?')..':'..(self.me.faction or'?')end
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
 local guild,_,_,guildRealm=self:Call(p.GetGuildInfo,'player');guild=self:Text(guild)
 local club=self:Call(p.C_Club and p.C_Club.GetGuildClubId)
 self.guildScope=guild and((self:Safe(club)and club and'club:'..tostring(club))or (self:Text(guildRealm)or realm or'?')..':'..guild)or nil
 for _,kind in ipairs({'GUILD','OFFICER'})do if self.guildScope then self.store:Ensure({kind=kind,name=label(kind),scope=self.guildScope})end end
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
 if self.community then self.community:Discover()end
 changed('identity')
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
 local result={};for i=1,#r,3 do local id,name=r[i],self:Text(r[i+1]);if self:Safe(id)and type(id)=='number'and id>0 and name then result[#result+1]={id=id,name=name,selected=self.store.settings.enabledChannels[name:lower()]==true}end end
 return result
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
function A:FailAttempt(a,errorText)
 if not a or a.state~='pending'then return end
 a.state='failed';local r={id=a.id,text=a.text,error=errorText or L('Senden fehlgeschlagen','Send failed'),key=a.key};self.recoveries[#self.recoveries+1]=r;changed('recovery',a.key)
end
function A:FailMatching(predicate,errorText)
 local match
 for _,a in ipairs(self.attempts)do if a.state=='pending'and clock()-a.at<=10 and predicate(a)then if match then return end;match=a end end
 self:FailAttempt(match,errorText)
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
function A:Send(c,text)
 if not c or not self:Text(text)or not text:find('%S')then return false,L('Gib eine Nachricht ein.','Enter a message.')end
 local max=c.kind=='BN_WHISPER'and 500 or c.kind=='COMMUNITY'and 512 or 255
 if #text>max then return false,L('Nachricht überschreitet das native Limit ('..max..' Bytes).','Message exceeds the native limit ('..max..' bytes).')end
 if c.kind=='COMMUNITY'then if not self.community then return false,L('Community-API nicht verfügbar.','Community API unavailable.')end;return self.community:Send(c,text)end
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
 local a=self:NewAttempt(c,text);local ok,result
 if c.kind=='BN_WHISPER'then ok,result=pcall(fn,target,text)else ok,result=pcall(fn,text,c.kind,nil,target)end
 if not ok or result==false then a.state='failed';return false,self:Text(result)or L('Senden fehlgeschlagen.','Send failed.'),a.id end
 return true,nil,a.id
end
function A:OnEvent(event,...)
 if event:find('^CLUB_')or event=='INITIAL_CLUBS_LOADED'then if self.community then return self.community:OnEvent(event,...)end;return end
 if event=='PLAYER_ENTERING_WORLD'or event=='PLAYER_GUILD_UPDATE'or event=='GROUP_ROSTER_UPDATE'or event=='CHANNEL_UI_UPDATE'or event=='CHANNEL_COUNT_UPDATE'then self:QueueIdentity();return end
 local args={...}
 if event=='CHAT_MSG_SYSTEM'then
  -- The native not-found format carries the exact target; other system errors are unrelated.
  local fmt=self:Text(self.api.ERR_CHAT_PLAYER_NOT_FOUND_S);local text=self:Text(args[1])
  if fmt and text then local pattern=fmt:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1'):gsub('%%%%s','(.+)');local target=text:match('^'..pattern..'$')
   if target then self:FailMatching(function(a)return a.kind=='WHISPER'and a.target==target end,text)end
  end;return
 end
 if event=='CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE'then
  local tag=self:Account(args[13]);if tag then self:FailMatching(function(a)return a.kind=='BN_WHISPER'and a.target==tag end,self:Text(args[1])or L('Empfänger offline.','Recipient offline.'))end;return
 end
 if event=='CHAT_MSG_RESTRICTED'then return end -- No attempt token or reliable target.
 local kind=event:match('^CHAT_MSG_(.+)$');if not kind then return end
 local inform=kind=='WHISPER_INFORM'or kind=='BN_WHISPER_INFORM'
 kind=kind:gsub('_INFORM$',''):gsub('_LEADER$','')
 if not(labels[kind]or kind=='WHISPER'or kind=='BN_WHISPER'or kind=='CHANNEL')then return end
 local text,sender=self:Text(args[1]),self:Text(args[2]);if not text or not sender then return end
 local c
 if kind=='WHISPER'then local target=self:FullName(sender,self.me.realm);c=self.store:Ensure({kind=kind,target=target,name=sender,scope=self.me.realm})
 elseif kind=='BN_WHISPER'then local tag,name=self:Account(args[13]);if not tag then return end;c=self.store:Ensure({kind=kind,target=tag,name=name})
 elseif kind=='CHANNEL'then
  local base=self:Text(args[9]);if not base or not self.store.settings.publicChannels or not self.store.settings.enabledChannels[base:lower()]then return end
  c=self:ChannelConversation(base)
 elseif kind=='GUILD'or kind=='OFFICER'then if not self.guildScope then return end;c=self.store:Ensure({kind=kind,name=label(kind),scope=self.guildScope})
 else if not self.groupKind or kind~=self.groupKind then return end;c=self.store:Ensure({kind=kind,name=label(kind),scope=self.me.name or self:Scope()})end
 local guid=self:Text(args[12]);local outgoing=inform or guid and guid==self.me.guid or sender==self.me.name
 local senderClass
 if not outgoing and guid and guid:match('^Player%-')then
  local _,class=self:Call(self.api.GetPlayerInfoByGUID,guid);senderClass=self:Text(class)
  if senderClass==''then senderClass=nil end
  if senderClass then c.classFile=senderClass end
 end
 if outgoing then self:Confirm(c,text)end
 self.serial=self.serial+1;local line=self:Safe(args[11])and args[11]
 local id=line and line~=0 and'chat:'..self:Scope()..':'..self.session..':'..tostring(line)or'local:'..self.session..':'..self.serial
 local row={id=id,at=now(),sender=outgoing and self.me.name or sender,text=text,outgoing=outgoing==true,ownCharacter=outgoing and self.me.name or nil,senderClass=outgoing and self.me.classFile or senderClass}
 local msg,added=self.store:Append(c,row,Z.IsVisibleAtEnd and Z.IsVisibleAtEnd(c.key)or false)
 return c,msg,added
end
