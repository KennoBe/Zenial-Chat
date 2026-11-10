-- Optional native-chat configuration. No chat handlers, filters or message transport are replaced.
local _,Z=...
local N={roles={},visuals={}};Z.NativeChat=N
local definitions={
    {key='general',de='Allgemein',en='General',aliases={'Allgemein','General'},groups={'SAY','YELL','EMOTE','CHANNEL','SYSTEM','ERRORS'}},
    {key='guild',de='Gilde',en='Guild',aliases={'Gilde','Guild'},groups={'GUILD','OFFICER'}},
    {key='group',de='Gruppe',en='Group',aliases={'Gruppe','Group','Party'},groups={'PARTY','PARTY_LEADER','RAID','RAID_LEADER','INSTANCE_CHAT','INSTANCE_CHAT_LEADER','RAID_WARNING'}},
    {key='whisper',de='Flüstern',en='Whispers',aliases={'Flüstern','Whispers','Whisper'},groups={'WHISPER','BN_WHISPER'}},
    {key='system',de='System',en='System',aliases={'System'},groups={'SYSTEM','ERRORS','IGNORED','LOOT','MONEY','CURRENCY','COMBAT_XP_GAIN','COMBAT_HONOR_GAIN','COMBAT_FACTION_CHANGE','SKILL','OPENING','TRADESKILLS','PET_INFO','COMBAT_MISC_INFO','ACHIEVEMENT','COLLECTED_APPEARANCE','BG_HORDE','BG_ALLIANCE','BG_NEUTRAL','BN_INLINE_TOAST_ALERT'}},
}
N.definitions=definitions
local noise={LOOT=true,MONEY=true,CURRENCY=true,COMBAT_XP_GAIN=true,COMBAT_HONOR_GAIN=true,COMBAT_FACTION_CHANGE=true,SKILL=true,OPENING=true,TRADESKILLS=true,COMBAT_MISC_INFO=true,COLLECTED_APPEARANCE=true}
local critical={SYSTEM=true,ERRORS=true,IGNORED=true,MONSTER_BOSS_EMOTE=true,MONSTER_BOSS_WHISPER=true}
-- Readable names for the preview; unknown native groups fall back to their key.
local labels={
    SAY={'Sagen','Say'},YELL={'Schreien','Yell'},EMOTE={'Emotes','Emotes'},CHANNEL={'Öffentliche Kanäle','Public channels'},
    SYSTEM={'Systemmeldungen','System messages'},ERRORS={'Fehlermeldungen','Errors'},IGNORED={'Ignoriert-Hinweise','Ignore notices'},
    GUILD={'Gilde','Guild'},OFFICER={'Offiziere','Officers'},GUILD_ACHIEVEMENT={'Gildenerfolge','Guild achievements'},
    PARTY={'Gruppe','Party'},PARTY_LEADER={'Gruppenleiter','Party leader'},RAID={'Schlachtzug','Raid'},RAID_LEADER={'Schlachtzugsleiter','Raid leader'},
    RAID_WARNING={'Schlachtzugswarnungen','Raid warnings'},INSTANCE_CHAT={'Instanz','Instance'},INSTANCE_CHAT_LEADER={'Instanzleiter','Instance leader'},
    WHISPER={'Flüstern','Whispers'},BN_WHISPER={'Battle.net-Flüstern','Battle.net whispers'},BN_INLINE_TOAST_ALERT={'Battle.net-Hinweise','Battle.net alerts'},
    LOOT={'Beute','Loot'},MONEY={'Geld','Money'},CURRENCY={'Währungen','Currency'},COMBAT_XP_GAIN={'Erfahrung','Experience'},
    COMBAT_HONOR_GAIN={'Ehre','Honor'},COMBAT_FACTION_CHANGE={'Ruf','Reputation'},SKILL={'Fertigkeiten','Skills'},OPENING={'Öffnen','Opening'},
    TRADESKILLS={'Berufe','Professions'},PET_INFO={'Begleiter','Pet info'},COMBAT_MISC_INFO={'Sonstige Kampfinfos','Misc. combat info'},
    ACHIEVEMENT={'Erfolge','Achievements'},COLLECTED_APPEARANCE={'Gesammelte Vorlagen','Collected appearances'},
    BG_HORDE={'Schlachtfeld (Horde)','Battleground (Horde)'},BG_ALLIANCE={'Schlachtfeld (Allianz)','Battleground (Alliance)'},BG_NEUTRAL={'Schlachtfeld (neutral)','Battleground (neutral)'},
    MONSTER_SAY={'NPC-Sagen','NPC say'},MONSTER_YELL={'NPC-Schreien','NPC yell'},MONSTER_EMOTE={'NPC-Emotes','NPC emotes'},MONSTER_WHISPER={'NPC-Flüstern','NPC whispers'},
    MONSTER_BOSS_EMOTE={'Boss-Emotes','Boss emotes'},MONSTER_BOSS_WHISPER={'Boss-Flüstern','Boss whispers'},
}
local function label(g)local l=labels[g];return l and Z.L(l[1],l[2])or g end
local function labelList(groups)local out={};for i,g in ipairs(groups)do out[i]=label(g)end;return table.concat(out,', ')end
local function heading(text)return'|cffffd200'..text..'|r'end
local function copy(value)
    if type(value)~='table'then return value end
    local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
N.Copy=copy
function N.Options(source)
    source=type(source)=='table'and Z.Safe(source)and source or{}
    local out={include={},unreadTabs={}}
    for _,key in ipairs({'unread','flash','compactTabs','hideButtons','hideBackground'})do out[key]=source[key]==true end
    out.moveSystem=source.moveSystem~=false
    out.timestamps=({keep=true,off=true,hm=true,hms=true})[source.timestamps]and source.timestamps or'keep'
    out.classColors=({keep=true,on=true,off=true})[source.classColors]and source.classColors or'keep'
    for _,d in ipairs(definitions)do out.include[d.key]=not(type(source.include)=='table'and source.include[d.key]==false)end
    if type(source.unreadTabs)=='table'and Z.Safe(source.unreadTabs)then
        for id,value in pairs(source.unreadTabs)do if type(id)=='string'and id:match('^%d+$')and value==false then out.unreadTabs[id]=false end end
    end
    return out
end
function N.Record()
    local db=Z.store.db
    if type(db.nativeChat)~='table'then db.nativeChat={}end
    local key=Z.Call(UnitGUID,'player')or Z.adapter.me.name
    if type(key)~='string'or key==''then return nil end
    if type(db.nativeChat[key])~='table'then db.nativeChat[key]={prefs=N.Options(),roles={}}end
    local record=db.nativeChat[key]
    if type(record.roles)~='table'then record.roles={}end
    record.prefs=N.Options(record.prefs)
    return record
end
function N.Settings()local r=N.Record();return r and r.prefs or N.Options()end
function N.InCombat()
    if type(InCombatLockdown)~='function'then return true end
    local ok,value=pcall(InCombatLockdown);return not ok or not Z.Safe(value)or value~=false
end
function N.Conflict()
    if ZenialUI and type(ZenialUI.ModuleEnabled)=='function'and Z.Call(ZenialUI.ModuleEnabled,'chat')then
        return Z.L('ZENIAL UI verwaltet bereits den Blizzard-Chat. Deaktiviere dort zuerst das Chat-Modul.','ZENIAL UI already manages Blizzard chat. Disable its chat module first.')
    end
    for _,addon in ipairs({'Prat-3.0','Chatter','ElvUI','Chattynator','Glass','LS_Glass'})do
        if C_AddOns and Z.Call(C_AddOns.IsAddOnLoaded,addon)then return Z.L('Ein anderes Chat-Addon ist aktiv: ','Another chat addon is active: ')..addon end
    end
end
local function allowed(frame)
    if not frame or not Z.Safe(frame)then return false end
    for _,method in ipairs({'IsForbidden','IsProtected'})do
        if frame[method]then local ok,v=pcall(frame[method],frame);if not ok or not Z.Safe(v)or v~=false then return false end end
    end
    return Z.Safe(frame.isTemporary,frame.chatTarget)and not frame.isTemporary and not frame.chatTarget
end
local function maxWindows()
    local n=Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS or 10
    return Z.Safe(n)and type(n)=='number'and math.max(1,math.min(20,n))or 10
end
local function list(source)
    if type(source)~='table'or not Z.Safe(source)then error('Unreadable native chat configuration')end
    local out={}
    for _,v in pairs(source)do if not Z.Safe(v)or type(v)~='string'then error('Unreadable native chat configuration')end;out[#out+1]=v end
    return out
end
local function contains(items,value)for _,v in ipairs(items)do if v==value then return true end end;return false end
local function sameList(a,b)
    if #a~=#b then return false end
    for _,v in ipairs(a)do if not contains(b,v)then return false end end;return true
end
local function invoke(fn,...)
    local ok,result=pcall(fn,...);if not ok or result==false then error('Native chat operation failed')end
    return result
end
local function snapshot()
    local out={windows={},cvars={}}
    for id=1,maxWindows()do
        local f=_G['ChatFrame'..id]
        if f and not f.isTemporary then
            local name,size,_,_,_,_,shown,_,docked=FCF_GetChatWindowInfo(id)
            if not Z.Safe(name,shown,docked)or type(name)~='string'then error('Unreadable native chat window')end
            local active=FCF_IsChatWindowIndexActive(id)
            if not Z.Safe(active)or not(active==nil or active==false or active==true or active==1)then error('Unreadable native chat visibility')end
            out.windows[id]={id=id,name=name,active=active==true or active==1,docked=docked==true or docked==1,
                fontSize=Z.Safe(size)and type(size)=='number'and size>0 and size or nil,
                groups=list(f.messageTypeList),channels=list(f.channelList)}
        end
    end
    if C_CVar and C_CVar.GetCVar then
        for _,key in ipairs({'showTimestamps','chatClassColorOverride'})do local v=Z.Call(C_CVar.GetCVar,key);if type(v)=='string'then out.cvars[key]=v end end
    end
    local selected=GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and Z.Call(FCFDock_GetSelectedWindow,GENERAL_CHAT_DOCK)
    if selected and selected.GetID then out.selected=Z.Call(selected.GetID,selected)end
    return out
end
local function fingerprint(state)
    local parts={}
    for id=1,maxWindows()do local w=state.windows[id]
        if w then
            parts[#parts+1]=id..':'..string.format('%q',w.name)..':'..tostring(w.active)..':'..tostring(w.docked)
            for _,field in ipairs({'groups','channels'})do local values=copy(w[field]);table.sort(values);for _,v in ipairs(values)do parts[#parts+1]=field..':'..string.format('%q',v)end end
        end
    end
    for _,key in ipairs({'showTimestamps','chatClassColorOverride'})do parts[#parts+1]=key..':'..tostring(state.cvars[key])end
    return table.concat(parts,'|')
end
local required={'FCF_GetChatWindowInfo','FCF_IsChatWindowIndexActive','FCF_IsChatWindowIndexReserved','FCF_OpenNewWindow','FCF_SetWindowName','FCF_Close','FCF_DockFrame','FCF_UnDockFrame','SetChatWindowShown'}
local function ready()
    if N.InCombat()then return Z.L('Im Kampf sind keine Änderungen möglich.','Changes are unavailable in combat.')end
    local conflict=N.Conflict();if conflict then return conflict end
    for _,key in ipairs(required)do if type(_G[key])~='function'then return Z.L('Native Chat-API fehlt: ','Missing native chat API: ')..key end end
    if type(ChatTypeGroup)~='table'or not ChatTypeGroup.SYSTEM then return Z.L('Die nativen Nachrichtengruppen sind nicht verfügbar.','Native message groups are unavailable.')end
    if not N.Record()then return Z.L('Charakteridentität ist noch nicht verfügbar.','Character identity is not available yet.')end
end
local function checkFrame(id)
    local f=_G['ChatFrame'..id]
    if not allowed(f)then error('Chat frame is protected or unavailable: '..id)end
    for _,key in ipairs({'AddMessageGroup','RemoveMessageGroup','AddChannel','RemoveChannel'})do if type(f[key])~='function'then error('Missing native chat-frame method: '..key)end end
    return f
end
local function publicChannels()
    local out={}
    if not GetChannelList or not C_ChatInfo or not C_ChatInfo.GetChannelInfoFromIdentifier then error('Native channel information API unavailable')end
    local values={GetChannelList()}
    if not Z.Safe(unpack(values))then error('Unreadable channel list')end
    for i=1,#values,3 do
        local name=values[i+1]
        if type(name)=='string'then
            local info=Z.Call(C_ChatInfo.GetChannelInfoFromIdentifier,name)
            if type(info)=='table'and Z.Safe(info)and Z.Safe(info.zoneChannelID,info.shortcut)and type(info.zoneChannelID)=='number'and info.zoneChannelID>0 then
                out[#out+1]=type(info.shortcut)=='string'and info.shortcut~=''and info.shortcut or name
            end
        end
    end
    return out
end
local function eligible(id,state)return state.windows[id]and(id==1 or not FCF_IsChatWindowIndexReserved(id))and allowed(_G['ChatFrame'..id])end
function N.ListTabs()
    local out={}
    if not FCF_GetChatWindowInfo or not FCF_IsChatWindowIndexActive or not FCF_IsChatWindowIndexReserved then return out end
    for id=1,maxWindows()do
        local name=Z.Call(FCF_GetChatWindowInfo,id)
        local active=Z.Call(FCF_IsChatWindowIndexActive,id)
        if type(name)=='string'and(active==true or active==1)and(id==1 or Z.Call(FCF_IsChatWindowIndexReserved,id)==false)and allowed(_G['ChatFrame'..id])then out[#out+1]={id=id,name=name}end
    end
    return out
end
local function desiredCvars(prefs)
    local out={}
    if prefs.timestamps~='keep'then out.showTimestamps=({off='none',hm='%H:%M',hms='%H:%M:%S'})[prefs.timestamps]end
    if prefs.classColors~='keep'then out.chatClassColorOverride=prefs.classColors=='on'and'0'or'1'end
    return out
end
function N.Preview(mode,options)
    local reason=ready();if reason then return nil,reason end
    local ok,plan=pcall(function()
        local before=snapshot();local record=N.Record()
        local p={mode=mode or'setup',before=before,signature=fingerprint(before),prefs=N.Options(options or record.prefs),rows={},targets={},cvars={},touched={}}
        if p.mode=='restore'then
            if not record.backup then error(Z.L('Noch keine gesicherte Ausgangskonfiguration.','No original configuration has been saved yet.'))end
            p.backup=copy(record.backup);p.prefs=N.Options(p.backup.prefs)
            for id,w in pairs(p.backup.windows)do
                local current=before.windows[id];local created=p.backup.created and p.backup.created[id]
                local owned=created and current.name==created.name and(not created.complete or sameList(current.groups,created.groups)and sameList(current.channels,created.channels))
                if not w.active and current.name~=w.name and not owned then
                    p.rows[#p.rows+1]=string.format('%s (#%d): %s',current.name,id,Z.L('manuell geänderter eigener Tab bleibt erhalten','manually changed custom tab is preserved'))
                else
                    checkFrame(id);p.touched[id]=true;p.targets[id]=copy(w)
                    p.rows[#p.rows+1]=string.format('%s (#%d): %s',current.name,id,w.active and Z.L('Ausgangskonfiguration wiederherstellen','Restore original configuration')or Z.L('neu angelegten Tab schließen','Close assistant-created tab'))
                end
            end
            p.cvars=copy(p.backup.cvars)
        elseif p.mode=='display'then
            -- Counters and appearance only: no tab, group or channel changes.
            p.rows[#p.rows+1]=Z.L('Tab-Aufteilung, Nachrichtengruppen und Kanäle bleiben unverändert.','Tab layout, message groups and channels remain unchanged.')
            p.cvars=desiredCvars(p.prefs)
        else
            local used,selected,entries,roleTab={},{},{},{}
            for _,d in ipairs(definitions)do if p.prefs.include[d.key]then selected[d.key]=true end end
            local public=selected.general and publicChannels()or{}
            for _,d in ipairs(definitions)do if selected[d.key]then
                local id=d.key=='general'and 1 or nil
                local known=record.roles[d.key]
                if not id and known and type(known.id)=='number'and eligible(known.id,before)and before.windows[known.id].active then id=known.id end
                if not id then for n=1,maxWindows()do local w=before.windows[n];if w and w.active and eligible(n,before)and not used[n]then
                    for _,alias in ipairs(d.aliases)do if w.name:lower()==alias:lower()then id=n;break end end
                    if id then break end
                end end end
                local create=not id
                if not id then for n=1,maxWindows()do if before.windows[n]and not FCF_IsChatWindowIndexReserved(n)and not before.windows[n].active and not used[n]then id=n;break end end end
                if not id or used[id]then error(Z.L('Nicht genügend freie native Chatfenster. Es wird nichts geändert.','Not enough native chat windows. Nothing will be changed.'))end
                used[id]=true;checkFrame(id)
                local current=before.windows[id];local target=copy(current)
                target.active=true;target.create=create;target.role=d.key
                -- Existing custom titles remain intact. Generated/default DE/EN titles follow locale.
                local rename=create
                for _,alias in ipairs(d.aliases)do if current.name==alias then rename=true end end
                if rename and d.key~='general'then target.name=Z.L(d.de,d.en)end
                -- New tabs inherit the font size of General when it is readable.
                if create and before.windows[1]and before.windows[1].fontSize then target.fontSize=before.windows[1].fontSize end
                target.groups=create and{}or copy(current.groups);target.channels=create and{}or copy(current.channels)
                -- General keeps its subscriptions; extra tabs provide additional views.
                if d.key~='general'then
                    local remove={}
                    for _,other in ipairs(definitions)do if other.key~=d.key and selected[other.key]then
                        for _,g in ipairs(other.groups)do
                            if not critical[g]and not noise[g]then remove[g]=true end
                        end
                    end end
                    for i=#target.groups,1,-1 do if remove[target.groups[i]]then table.remove(target.groups,i)end end
                    for _,g in ipairs(d.groups)do if ChatTypeGroup[g]and not contains(target.groups,g)then target.groups[#target.groups+1]=g end end
                    if selected.general then for _,channel in ipairs(public)do
                        for i=#target.channels,1,-1 do if target.channels[i]==channel then table.remove(target.channels,i)end end
                    end end
                end
                p.targets[id]=target;p.touched[id]=true
                local add,del={},{}
                for _,g in ipairs(target.groups)do if not contains(current.groups,g)then add[#add+1]=g end end
                for _,g in ipairs(current.groups)do if not contains(target.groups,g)then del[#del+1]=g end end
                entries[#entries+1]={def=d,current=current,target=target,create=create,added=add,removed=del};roleTab[d.key]=target
            end end
            if next(p.targets)==nil then error(Z.L('Wähle mindestens einen Tab.','Select at least one tab.'))end
            p.rows[#p.rows+1]=Z.L('Zusätzliche Tabs zeigen die ausgewählten Nachrichtenarten. Allgemein behält seine bisherigen Nachrichtenarten und Kanäle. Bestehende Tabs behalten ihren Verlauf.','Additional tabs show the selected message types. General keeps its existing message types and channels. Existing tabs keep their history.')
            local generalName=before.windows[1]and before.windows[1].name or Z.L('Allgemein','General')
            for _,e in ipairs(entries)do
                local t,lines=e.target,{}
                if e.create then lines[1]=heading(t.name..' · '..Z.L('neuer Tab','new tab'))
                elseif e.current.name~=t.name then lines[1]=heading(t.name..' · '..string.format(Z.L('bestehender Tab, bisher "%s"','existing tab, previously "%s"'),e.current.name))
                else lines[1]=heading(t.name..' · '..Z.L('bestehender Tab','existing tab'))end
                if #e.added>0 then lines[#lines+1]='  '..(e.create and Z.L('Zeigt: ','Shows: ')or Z.L('Zeigt zusätzlich: ','Also shows: '))..labelList(e.added)end
                -- Removed message types are grouped by the tab that receives them.
                local order,byDest={},{}
                for _,g in ipairs(e.removed)do
                    local dest=''
                    for _,other in ipairs(definitions)do if other.key~=e.def.key and roleTab[other.key]and contains(other.groups,g)then dest=roleTab[other.key].name;break end end
                    if not byDest[dest]then byDest[dest]={};order[#order+1]=dest end
                    table.insert(byDest[dest],g)
                end
                for _,dest in ipairs(order)do
                    lines[#lines+1]='  '..(dest~=''and string.format(Z.L('Wandert nach %s: ','Moves to %s: '),dest)or Z.L('Nicht mehr angezeigt: ','No longer shown: '))..labelList(byDest[dest])
                end
                if #e.added==0 and #e.removed==0 then lines[#lines+1]='  '..Z.L('Nachrichtenarten bleiben unverändert.','Message types stay unchanged.')end
                if #t.channels>0 then lines[#lines+1]='  '..Z.L('Kanäle: ','Channels: ')..table.concat(t.channels,', ')end
                if e.create and t.fontSize then lines[#lines+1]='  '..string.format(Z.L('Schriftgröße %d wie %s','Font size %d, same as %s'),t.fontSize,generalName)end
                p.rows[#p.rows+1]=table.concat(lines,'\n')
            end
            p.cvars=desiredCvars(p.prefs)
        end
        local cvarNames={showTimestamps=Z.L('Zeitstempel','Timestamps'),chatClassColorOverride=Z.L('Klassenfarben für Namen','Class colors for names')}
        local cvarValues={showTimestamps={none=Z.L('Aus','Off'),['%H:%M']='HH:MM',['%H:%M:%S']='HH:MM:SS'},
            chatClassColorOverride={['0']=Z.L('An','On'),['1']=Z.L('Aus','Off'),['2']=Z.L('je Kanal','per channel')}}
        local function cvarValue(key,value)return cvarValues[key]and cvarValues[key][value]or tostring(value)end
        local function yes(value)return value and Z.L('ja','yes')or Z.L('nein','no')end
        local display={heading(Z.L('Darstellung & Zähler','Appearance & counters'))}
        for key in pairs(p.cvars)do
            if not C_CVar or not C_CVar.SetCVar or before.cvars[key]==nil then error('Native CVar unavailable: '..key)end
            display[#display+1]='  '..string.format(Z.L('%s: bisher %s, danach %s (gesamter Blizzard-Chat)','%s: currently %s, then %s (all Blizzard chat)'),cvarNames[key]or key,cvarValue(key,before.cvars[key]),cvarValue(key,p.cvars[key]))
        end
        local on,off={},{}
        for id=1,maxWindows()do local w=before.windows[id];if w and w.active and eligible(id,before)then
            local target=p.prefs.unread and p.prefs.unreadTabs[tostring(id)]~=false and on or off;target[#target+1]=w.name
        end end
        if p.prefs.unread then
            display[#display+1]='  '..Z.L('Ungelesen-Zähler an: ','Unread counters on: ')..(#on>0 and table.concat(on,', ')or'—')
            if #off>0 then display[#display+1]='  '..Z.L('Ungelesen-Zähler aus: ','Unread counters off: ')..table.concat(off,', ')end
        else display[#display+1]='  '..Z.L('Ungelesen-Zähler: aus','Unread counters: off')end
        display[#display+1]='  '..string.format(Z.L('Kompakte Tab-Schrift: %s · Zusätzliche Buttons ausblenden: %s · Hintergründe ausblenden: %s','Compact tab text: %s · Hide extra buttons: %s · Hide backgrounds: %s'),yes(p.prefs.compactTabs),yes(p.prefs.hideButtons),yes(p.prefs.hideBackground))
        p.rows[#p.rows+1]=table.concat(display,'\n')
        if p.mode=='setup'then
            p.rows[#p.rows+1]=Z.L('Allgemein bleibt unverändert; Nachrichten erscheinen dort weiterhin entsprechend deiner bisherigen Konfiguration.','General stays unchanged; messages continue to appear there according to your existing configuration.')
        end
        p.rows[#p.rows+1]=Z.L('Der ZENIAL-Messenger bleibt unverändert. Chatverlauf ist nicht Teil der Sicherung.','The ZENIAL messenger is unchanged. Chat history is not part of the backup.')
        return p
    end)
    if ok then return plan end
    return nil,tostring(plan)
end
local function restoreSelection(state)
    local frame=state.selected and _G['ChatFrame'..state.selected]
    if frame and FCF_IsChatWindowIndexActive(state.selected)and GENERAL_CHAT_DOCK and FCFDock_SelectWindow then invoke(FCFDock_SelectWindow,GENERAL_CHAT_DOCK,frame)end
end
local function applyWindow(w)
    local f=checkFrame(w.id)
    if w.create then
        local opened=invoke(FCF_OpenNewWindow,w.name,true)
        if opened~=f then error('Native window allocation changed; preview again')end
    end
    -- Optional cosmetic step: a missing or failing font API never blocks routing.
    if w.create and w.fontSize and type(FCF_SetChatWindowFontSize)=='function'then pcall(FCF_SetChatWindowFontSize,nil,f,w.fontSize)end
    if not w.active then invoke(FCF_Close,f)end
    local name=FCF_GetChatWindowInfo(w.id)
    if name~=w.name then invoke(FCF_SetWindowName,f,w.name)end
    local groups=list(f.messageTypeList)
    for _,g in ipairs(groups)do if not contains(w.groups,g)then invoke(f.RemoveMessageGroup,f,g)end end
    for _,g in ipairs(w.groups)do if not contains(groups,g)then invoke(f.AddMessageGroup,f,g)end end
    local channels=list(f.channelList)
    for _,c in ipairs(channels)do if not contains(w.channels,c)then invoke(f.RemoveChannel,f,c)end end
    for _,c in ipairs(w.channels)do if not contains(channels,c)then invoke(f.AddChannel,f,c)end end
    -- Some native operations fail silently (notably AddChannel). Verify actual
    -- routing rather than treating every void/nil return as proof of success.
    local actualGroups,actualChannels=list(f.messageTypeList),list(f.channelList)
    if #actualGroups~=#w.groups or #actualChannels~=#w.channels then error('Native routing did not match the preview')end
    for _,g in ipairs(w.groups)do if not contains(actualGroups,g)then error('Native message group was not applied')end end
    for _,c in ipairs(w.channels)do if not contains(actualChannels,c)then error('Native channel was not applied')end end
    if not w.create and w.active then
        if w.docked and not f.isDocked then invoke(FCF_DockFrame,f)elseif not w.docked and f.isDocked then invoke(FCF_UnDockFrame,f)end
        if not FCF_IsChatWindowIndexActive(w.id)then invoke(SetChatWindowShown,w.id,true);f:Show();local tab=_G[f:GetName()..'Tab'];if tab then tab:Show()end end
    end
end
function N.Apply(plan)
    local reason=ready();if reason then return false,reason end
    if type(plan)~='table'or not plan.before then return false,Z.L('Zuerst eine Vorschau öffnen.','Open a preview first.')end
    local ok,current=pcall(snapshot)
    if not ok or fingerprint(current)~=plan.signature then return false,Z.L('Die Chat-Konfiguration hat sich geändert. Bitte Vorschau erneut öffnen.','Chat configuration changed. Open the preview again.')end
    local record=N.Record()
    if not record.backup then record.backup={windows={},cvars={},created={},prefs=copy(record.prefs),roles=copy(record.roles),selected=current.selected}end
    record.backup.created=record.backup.created or{}
    if plan.mode~='restore'then
        for id in pairs(plan.touched)do if not record.backup.windows[id]then record.backup.windows[id]=copy(current.windows[id])end end
        for id,w in pairs(plan.targets)do if w.create then record.backup.created[id]={name=w.name,complete=false}end end
        for key in pairs(plan.cvars)do if record.backup.cvars[key]==nil then record.backup.cvars[key]=current.cvars[key]end end
    end
    local applied,err=pcall(function()
        for id=1,maxWindows()do if plan.targets[id]then applyWindow(plan.targets[id])end end
        for key,value in pairs(plan.cvars)do if current.cvars[key]~=value then
            invoke(C_CVar.SetCVar,key,value)
            if Z.Call(C_CVar.GetCVar,key)~=value then error('Native CVar was not applied')end
        end end
        restoreSelection(plan.mode=='restore'and plan.backup or current)
    end)
    if not applied then
        local rolled=pcall(function()
            for id=1,maxWindows()do if plan.touched[id]then applyWindow(current.windows[id])end end
            for key in pairs(plan.cvars)do
                invoke(C_CVar.SetCVar,key,current.cvars[key])
                if Z.Call(C_CVar.GetCVar,key)~=current.cvars[key]then error('Native CVar rollback incomplete')end
            end
            restoreSelection(current)
        end)
        return false,Z.L('Einrichtung fehlgeschlagen. ','Setup failed. ')..(rolled and Z.L('Änderungen zurückgenommen.','Changes rolled back.')or Z.L('Die Sicherung bleibt zur Wiederherstellung erhalten.','The backup remains available for recovery.'))
    end
    record.prefs=copy(plan.prefs)
    if plan.mode=='restore'then record.roles=copy(plan.backup.roles or{})
    else for id,w in pairs(plan.targets)do
        if w.role then record.roles[w.role]={id=id,name=w.name}end
        if record.backup.created[id]then record.backup.created[id]={name=w.name,groups=copy(w.groups),channels=copy(w.channels),complete=true}end
    end end
    N.RefreshAppearance();if Z.NativeChatUnread then Z.NativeChatUnread.Apply()end
    return true,Z.L('Blizzard-Chat-Konfiguration übernommen.','Blizzard chat configuration applied.')
end
local function styleRegion(saved,key,region,hide,mouse)
    if not region or not allowed(region)or not region.GetAlpha or not region.SetAlpha then return end
    local previous=saved[key]
    if hide and not previous then
        local alpha=Z.Call(region.GetAlpha,region);if type(alpha)~='number'then return end
        previous={alpha=alpha};saved[key]=previous
        if mouse and region.IsMouseEnabled then previous.mouse=Z.Call(region.IsMouseEnabled,region)end
        region:SetAlpha(0)
        if type(previous.mouse)=='boolean'then region:EnableMouse(false)end
    elseif not hide and previous then
        if Z.Call(region.GetAlpha,region)==0 then region:SetAlpha(previous.alpha)end
        if type(previous.mouse)=='boolean'and Z.Call(region.IsMouseEnabled,region)==false then region:EnableMouse(previous.mouse)end
        saved[key]=nil
    end
end
-- Only own reversible decoration; never replace Show/Hide/OnUpdate or native text.
function N.RefreshAppearance()
    if N.InCombat()then return end
    local prefs=N.Conflict()and N.Options()or N.Settings()
    local enabled=prefs.compactTabs or prefs.hideButtons or prefs.hideBackground
    if not enabled and next(N.visuals)==nil then return end
    for id=1,maxWindows()do local f=_G['ChatFrame'..id];local tab=_G['ChatFrame'..id..'Tab']
        if allowed(f)and allowed(tab)and(id==1 or FCF_IsChatWindowIndexReserved and not FCF_IsChatWindowIndexReserved(id))then
            local v=N.visuals[id]
            if not v then v={regions={}};N.visuals[id]=v end
            if tab.Text and tab.Text.GetFontObject then
                if prefs.compactTabs and not v.font then
                    local file,size,flags=Z.Call(tab.Text.GetFont,tab.Text)
                    if type(file)=='string'and type(size)=='number'and size>8 then
                        v.font={object=tab.Text:GetFontObject(),file=file,size=size,flags=flags}
                        pcall(tab.Text.SetFont,tab.Text,file,math.max(8,math.floor(size*.8+.5)),flags or'')
                    end
                elseif not prefs.compactTabs and v.font then
                    if v.font.object then tab.Text:SetFontObject(v.font.object)end
                    pcall(tab.Text.SetFont,tab.Text,v.font.file,v.font.size,v.font.flags or'');v.font=nil
                end
            end
            for _,field in ipairs(CHAT_FRAME_TEXTURES or{'Background','ButtonFrameBackground'})do styleRegion(v.regions,field,f[field],prefs.hideBackground,false)end
            styleRegion(v.regions,'buttonFrame',f.buttonFrame,prefs.hideButtons,true)
            if not enabled and not v.font and next(v.regions)==nil then N.visuals[id]=nil end
        end
    end
    N.globalVisuals=N.globalVisuals or{}
    for _,name in ipairs({'ChatFrameMenuButton','ChatFrameChannelButton','QuickJoinToastButton'})do styleRegion(N.globalVisuals,name,_G[name],prefs.hideButtons,true)end
    if GENERAL_CHAT_DOCK and FCFDock_UpdateTabs then FCFDock_UpdateTabs(GENERAL_CHAT_DOCK,true)end
end
function N.Initialize()
    if not Z.store then return end
    N.Record()
    if not N.lifecycle then
        local frame=CreateFrame('Frame');N.lifecycle=frame
        for _,event in ipairs({'PLAYER_REGEN_ENABLED','UPDATE_CHAT_WINDOWS','UPDATE_FLOATING_CHAT_WINDOWS','PLAYER_ENTERING_WORLD','ADDON_LOADED'})do pcall(frame.RegisterEvent,frame,event)end
        frame:SetScript('OnEvent',function()if Z.ready then N.Initialize()end end)
    end
    if not N.InCombat()and FCF_GetChatWindowInfo then N.RefreshAppearance();if Z.NativeChatUnread then Z.NativeChatUnread.Apply()end end
end
