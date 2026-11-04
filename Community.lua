-- Native subscribed-club streams only: discovery never joins or changes permissions.
local _,Z=...
local C={};Z.Community=C;C.__index=C
local slots={general={Allgemein=true,General=true},horde={Horde=true},alliance={Allianz=true,Alliance=true}}
function C.New(adapter,store,api)
 local self=setmetatable({adapter=adapter,store=store,api=api or _G,pending={},memberPending={}},C)
 for _,c in pairs(store.db.conversations or{})do if c.kind=='COMMUNITY'then for _,row in ipairs(c.messages or{})do if row.senderPending then self:RememberMember(c,row)end end end end
 return self
end
local function L(de,en)return Z.L and Z.L(de,en)or en end
local function clock()return Z.Clock and Z.Clock()or Z.Now and Z.Now()or 0 end
function C:Id(value)
 if not self.adapter:Safe(value)then return nil end
 if type(value)=='string'and value:match('^%d+$')then return value end
 if type(value)=='number'and value>0 and value==math.floor(value)then return string.format('%.0f',value)end
end
function C:Native()return self.api.C_Club or{}end
function C:Clubs()
 local cache=self.cache;if cache and cache.clubs then return cache.clubs end
 local result=self:ReadClubs();if cache then cache.clubs=result end
 return result
end
function C:ReadClubs()
 local a=self.adapter;local p=self:Native();local result={}
 local guild=self:Id(a:Call(p.GetGuildClubId))
 local guildType=self.api.Enum and self.api.Enum.ClubType and self.api.Enum.ClubType.Guild or 2
 local clubs=a:Table(a:Call(p.GetSubscribedClubs))or{}
 for _,row in ipairs(clubs)do if a:Table(row)then local id=self:Id(row.clubId);local name=a:Text(row.name)
  if id and id~=guild and a:Safe(row.clubType)and row.clubType~=guildType and name then result[#result+1]={id=id,name=name,clubType=row.clubType}end
 end end
 return result
end
function C:FindClub(id)
 id=self:Id(id);if not id then return nil end
 for _,c in ipairs(self:Clubs())do if c.id==id then return c end end
end
function C:Streams(clubId)
 local club=self:FindClub(clubId);if not club then return{}end
 local cache=self.cache;if cache then cache.streams=cache.streams or{};if cache.streams[club.id]then return cache.streams[club.id]end end
 local result=self:ReadStreams(club);if cache then cache.streams[club.id]=result end
 return result
end
function C:ReadStreams(club)
 local a=self.adapter;local result={}
 for _,row in ipairs(a:Table(a:Call(self:Native().GetStreams,club.id))or{})do
  if a:Table(row)then local id=self:Id(row.streamId);local name=a:Text(row.name);if id and name then result[#result+1]={id=id,name=name}end end
 end
 return result
end
function C:FindStream(id)
 id=self:Id(id);if not id then return nil end
 for _,s in ipairs(self:Streams(self.store.settings.clubId))do if s.id==id then return s end end
end
function C:SelectClub(id)
 local club=self:FindClub(id);if not club then return false,L('Wähle eine abonnierte Community.','Choose a subscribed community.')end
 if self.store.settings.clubId~=club.id then self.store.settings.clubId=club.id;self.store.settings.streams={}end
 self:Discover();if Z.Changed then Z.Changed('community')end;return true
end
function C:SetStream(slot,streamId)
 if not slots[slot]then return false,L('Unbekannter Stream-Platz.','Unknown stream slot.')end
 if streamId==nil or streamId==''then self.store.settings.streams[slot]=nil
 else local stream=self:FindStream(streamId);if not stream then return false,L('Stream nicht verfügbar.','Stream unavailable.')end;self.store.settings.streams[slot]=stream.id;self:Conversation(stream.id)end
 if Z.Changed then Z.Changed('community')end;return true
end
-- Club and stream lists are read once per Discover and reused within it.
function C:Discover()
 if self.cache then return self:DiscoverNow()end
 self.cache={};local ok,err=pcall(self.DiscoverNow,self);self.cache=nil
 if not ok then error(err,0)end
end
function C:DiscoverNow()
 local settings=self.store.settings
 if not settings.clubId then
  local a=self.adapter;local z=a:Table(self.api.ZenialCommunity)
  local directory=z and a:Table(z.CommunityDirectory);local db=a:Table(self.api.ZenialCommunityDB)
  local config=directory and a:Table(directory.config)or db and a:Table(db.network)
  local candidates={};if directory then local bootstrap=self:Id(directory.BOOTSTRAP_ID);if bootstrap then candidates[#candidates+1]=bootstrap end end
  if config then for _,id in ipairs(a:Table(config.assignment)or{})do candidates[#candidates+1]=id end end
  for _,id in ipairs(candidates)do local club=self:FindClub(id);if club then settings.clubId=club.id;break end end
 end
 local club=self:FindClub(settings.clubId);if not club then return end
 settings.clubId=club.id
 local streams=self:Streams(club.id)
 for slot,names in pairs(slots)do
  if not settings.streams[slot]then
   local match;local count=0;for _,s in ipairs(streams)do if names[s.name]then match=s.id;count=count+1 end end
   if count==1 then settings.streams[slot]=match end
  end
  if settings.streams[slot]then self:Conversation(settings.streams[slot])end
 end
end
function C:Conversation(streamId)
 local stream=self:FindStream(streamId);if not stream then return nil end
 local slot;for _,candidate in ipairs({'general','horde','alliance'})do if tostring(self.store.settings.streams[candidate])==stream.id then slot=candidate;break end end
 if not slot then return nil end
 local c=self.store:Ensure({kind='COMMUNITY',clubId=self.store.settings.clubId,streamId=stream.id,name=stream.name});c.slot=slot;return c
end
function C:Available(c)
 return c and c.kind=='COMMUNITY'and c.clubId==self.store.settings.clubId and self:Conversation(c.streamId)~=nil
end
function C:Send(c,text)
 if not self:Available(c)then return false,L('Community-Stream nicht verfügbar.','Community stream unavailable.')end
 if not self.adapter:Text(text)or not text:find('%S')then return false,L('Gib eine Nachricht ein.','Enter a message.')end
 local plain=(Z.Plain or Z.Store.Plain)(text)
 if #text>512 or #plain>255 or #text-#plain>255 then return false,L('Nachricht überschreitet das native Community-Limit (255 sichtbar / 255 Markup-Bytes).','Message exceeds the native community limit (255 visible / 255 markup bytes).')end
 local fn=self:Native().SendMessage;if type(fn)~='function'then return false,L('Community-API nicht verfügbar.','Community API unavailable.')end
 local attempt=self.adapter:NewAttempt(c,text)
 local club=self:FindClub(c.clubId);attempt.clubType=club and club.clubType
 local ok,result=pcall(fn,c.clubId,c.streamId,text)
 if not ok or result==false then attempt.state='failed';return false,self.adapter:Text(result)or L('Senden fehlgeschlagen.','Send failed.'),attempt.id end
 return true,nil,attempt.id
end
function C:MessageId(id)
 local a=self.adapter;if not a:Table(id)then return nil end
 if not a:Safe(id.epoch,id.position)then return nil end
 local epoch=self:Id(id.epoch);local position=self:Id(id.position)
 -- Native positions and epochs can be zero.
 if id.epoch==0 then epoch='0'end;if id.position==0 then position='0'end
 if not epoch or not position then return nil end
 return 'club:'..epoch..':'..position,{epoch=id.epoch,position=id.position}
end
function C:RememberMember(c,row)
 if row.authorMemberId==nil then return end
 local members=self.memberPending[c.clubId]or{};self.memberPending[c.clubId]=members
 local member=tostring(row.authorMemberId);members[member]=members[member]or{}
 local conversation=members[member];conversation[c.key]=conversation[c.key]or{};conversation[c.key][row.id]=true
end
function C:ResolveMember(clubId,memberId)
 local a=self.adapter;if not a:Safe(memberId)then return end
 local members=self.memberPending[self:Id(clubId)];local pending=members and members[tostring(memberId)];if not pending then return end
 local info=a:Table(a:Call(self:Native().GetMemberInfo,clubId,memberId));local name=info and a:Text(info.name)
 if not name or name==''then return end
 for key,ids in pairs(pending)do for id in pairs(ids)do self.store:Update(key,id,{sender=name,senderPending=false})end end
 members[tostring(memberId)]=nil
end
function C:Ingest(c,info,history)
 local a=self.adapter;if not a:Table(info)then return end
 local id,native=self:MessageId(info.messageId);if not id or not a:Safe(info.destroyed,info.edited)then return end
 local author=a:Table(info.author);if not author then return end
 if not a:Safe(author.isSelf)then return end
 local text=info.destroyed and''or a:Text(info.content);if text==nil then return end
 if not a:Safe(author.name,author.memberId)then return end
 local memberId=(type(author.memberId)=='number'or type(author.memberId)=='string')and author.memberId or nil
 local name=a:Text(author.name)
 if not name and memberId~=nil then local member=a:Table(a:Call(self:Native().GetMemberInfo,c.clubId,memberId));name=member and a:Text(member.name)end
 local unresolved=not name or name==''
 if unresolved then name=Z.L and Z.L('Unbekanntes Mitglied','Unknown member')or'Unknown member'end
 local outgoing=author.isSelf==true
 -- Historical isSelf identifies the account; it does not identify the current character.
 local liveOwn=outgoing and not history
 if liveOwn then a:Confirm(c,text)end
 local epoch=tonumber(native.epoch)
 local row={id=id,at=epoch and epoch/1000000 or(Z.Now and Z.Now()or 0),sender=liveOwn and a.me.name or name,
  text=text,outgoing=outgoing,ownCharacter=liveOwn and a.me.name or nil,edited=info.edited==true,deleted=info.destroyed==true,
  authorMemberId=memberId,senderPending=unresolved and not liveOwn}
 if not history then self:HistorySync(c)end
 local wasClosed=c.closed
 local msg,added=self.store:Append(c,row,history or Z.IsVisibleAtEnd and Z.IsVisibleAtEnd(c.key)or false)
 if history then c.closed=wasClosed end
 if msg and row.senderPending then self:RememberMember(c,msg)end
 return c,msg,added
end
function C:Oldest(c)
 for _,message in ipairs(c.messages)do local epoch,position=message.id:match('^club:(%d+):(%d+)$');if epoch then return{epoch=tonumber(epoch),position=tonumber(position)}end end
end
function C:Newest(c)
 for i=#c.messages,1,-1 do local epoch,position=c.messages[i].id:match('^club:(%d+):(%d+)$');if epoch then return{epoch=tonumber(epoch),position=tonumber(position)}end end
end
function C:HistorySync(c)
 -- Keep table presence even when checkpoint is nil: partial imports are not a new baseline.
 if type(c.historySync)~='table'then c.historySync={checkpoint=self:Newest(c)}end
 return c.historySync
end
local function compareInteger(left,right)
 left=(type(left)=='number'and string.format('%.0f',left)or tostring(left)):gsub('^0+','')
 right=(type(right)=='number'and string.format('%.0f',right)or tostring(right)):gsub('^0+','')
 if #left~=#right then return #left<#right and-1 or 1 end
 return left==right and 0 or left<right and-1 or 1
end
local function compareIds(left,right)
 local epoch=compareInteger(left.epoch,right.epoch);if epoch~=0 then return epoch end
 return compareInteger(left.position,right.position)
end
function C:Backfill(c,newest)
 -- Unsolicited native history is a partial import too. Preserve the archive
 -- boundary before adding it, even if Zenial Chat has not requested history.
 self:HistorySync(c)
 local a=self.adapter;local p=self:Native()
 if not newest then
  local ranges=a:Table(a:Call(p.GetMessageRanges,c.clubId,c.streamId))or{}
  for _,r in ipairs(ranges)do if a:Table(r)and self:MessageId(r.newestMessageId)then newest=r.newestMessageId end end
 end
 if not newest then return nil,0 end
 local rows=a:Table(a:Call(p.GetMessagesBefore,c.clubId,c.streamId,newest,100))or{}
 -- Native API bounds the request. Also bound processing if an inconsistent provider returns more.
 local oldest,latest;local count=math.min(#rows,100)
 for i=1,count do
  local row=a:Table(rows[i]);local _,id=self:MessageId(row and row.messageId)
  if id and(not oldest or compareIds(id,oldest)<0)then oldest=id end
  if id and(not latest or compareIds(id,latest)>0)then latest=id end
  self:Ingest(c,row,true)
 end
 return oldest,count,latest
end
function C:ProcessPage(state,newest)
 if self.pending[state.c.key]~=state then return end
 state.waiting=false
 local oldest,count,latest=self:Backfill(state.c,state.cursor or newest)
 if not state.firstPage then state.latest=latest;state.firstPage=true end
 local beginning=oldest and self.adapter:Call(self:Native().IsBeginningOfStream,state.c.clubId,state.c.streamId,oldest)==true
 local complete=not state.older and(not oldest or count==0 or not state.baseline or compareIds(oldest,state.baseline)<=0 or beginning)
 local stop=state.older or complete
 if not stop then
  stop=state.cursor and compareIds(oldest,state.cursor)>=0
  local id=self:MessageId(oldest)
  if state.visited[id]then stop=true end
  if not stop then state.visited[id]=true;state.cursor=oldest;state.queued=true end
 end
 if stop then
  -- No-progress/timeouts never certify continuity. Live arrivals never change this fixed target.
  if complete and state.latest and state.c.historySync==state.sync then state.sync.checkpoint=state.latest end
  self.pending[state.c.key]=nil
 end
end
function C:RequestPage(state)
 local c=state.c;local fn=self:Native().RequestMoreMessagesBefore
 state.waiting=true;state.queued=false;state.at=clock()
 local ok,result=pcall(fn,c.clubId,c.streamId,state.cursor,100)
 if not ok then self.pending[c.key]=nil;return false,self.adapter:Text(result)or L('Verlaufsanfrage fehlgeschlagen.','History request failed.')end
 if result==true and self.pending[c.key]==state and state.waiting then self:ProcessPage(state)end
 return true
end
function C:RequestHistory(c,older)
 if not self:Available(c)then return false,L('Community-Stream nicht verfügbar.','Community stream unavailable.')end
 local fn=self:Native().RequestMoreMessagesBefore;if type(fn)~='function'then return false,L('Community-Verlauf nicht verfügbar.','Community history unavailable.')end
 local active=self.pending[c.key];if active and clock()-active.at<10 then return true end
 local sync=older~=true and self:HistorySync(c)or nil
 local state={c=c,sync=sync,older=older==true,baseline=sync and sync.checkpoint or nil,cursor=older==true and self:Oldest(c)or nil,at=clock(),visited={}}
 self.pending[c.key]=state;if Z.WakeHistory then Z.WakeHistory()end;return self:RequestPage(state)
end
function C:Tick()
 for key,state in pairs(self.pending)do
  if state.waiting and clock()-state.at>=10 then self.pending[key]=nil
  elseif state.queued then
   if self:Available(state.c)then self:RequestPage(state)else self.pending[key]=nil end
  end
 end
end
function C:OnEvent(event,...)
 local clubId,streamId,id=...
 if event=='CLUB_ERROR'then
  local actions=self.api.Enum and self.api.Enum.ClubActionType
  if actions and self.adapter:Safe(clubId,streamId,id)and clubId==actions.ErrorClubActionCreateMessage then
   self.adapter:FailMatching(function(a)return a.kind=='COMMUNITY'and a.clubType==id end,L('Community-Senden fehlgeschlagen (','Community send failed (')..tostring(streamId)..').')
  end;return
 end
 if event=='CLUB_MESSAGE_ADDED'or event=='CLUB_MESSAGE_UPDATED'or event=='CLUB_MESSAGE_HISTORY_RECEIVED'then
  if self:Id(clubId)~=self.store.settings.clubId then return end
  local c=self:Conversation(streamId);if not c then return end
  if event=='CLUB_MESSAGE_HISTORY_RECEIVED'then
   local a=self.adapter;if a:Table(id)and self:MessageId(id.newestMessageId)then
    local state=self.pending[c.key]
    if state and state.waiting then self:ProcessPage(state,id.newestMessageId)else self:Backfill(c,id.newestMessageId)end
   end;return
  end
  if not self:MessageId(id)then return end
  return self:Ingest(c,self.adapter:Call(self:Native().GetMessageInfo,clubId,streamId,id),false)
 end
 if event=='CLUB_MEMBER_UPDATED'then self:ResolveMember(clubId,streamId);return end
 self:Discover();if Z.Changed then Z.Changed('community')end
end
