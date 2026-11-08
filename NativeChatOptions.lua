local _,Z=...
local U,N=Z.UI,Z.NativeChat
local O={};Z.NativeChatOptions=O
local draft
local function options()if not draft then draft=N.Options(N.Settings())end;return draft end
local function check(add,label,key)
    add('check',label,{get=function()return options()[key]end,set=function(value)options()[key]=value end})
end
local function preview(mode)
    local plan,reason=N.Preview(mode,options());local T=Z.Theme
    if not U.nativePreview then
        local f=T.Frame(U.frame,'shell','gold');U.nativePreview=f;f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:EnableMouse(true)
        f.title=T.Text(f,'',18,true,'goldBright')
        f.scroll=CreateFrame('ScrollFrame',nil,f);f.scroll:SetClipsChildren(true);f.scroll:EnableMouseWheel(true)
        f.content=CreateFrame('Frame',nil,f.scroll);f.scroll:SetScrollChild(f.content)
        f.body=T.Text(f.content,'',12,false);f.body:SetWordWrap(true)
        f.status=T.Text(f,'',12,false,'goldBright');f.status:SetWordWrap(true)
        f.cancel=T.Button(f,Z.L('Abbrechen','Cancel'),function()f:Hide()end)
        f.apply=T.Button(f,Z.L('Übernehmen','Apply'),function()
            if not f.plan then return end
            local ok,message=N.Apply(f.plan)
            if ok then draft=nil;f:Hide();U.RebuildOptions()
            else f.status:SetText(message);f.apply:Disable();f.plan=nil end
        end)
        f.scroll:SetScript('OnMouseWheel',function(self,delta)
            self:SetVerticalScroll(math.max(0,math.min(f.maxScroll or 0,self:GetVerticalScroll()-delta*40)))
        end)
    end
    local f=U.nativePreview;f.plan=plan
    local width=math.min(680,UIParent:GetWidth()-40);local height=math.min(520,UIParent:GetHeight()-60)
    f:SetSize(width,height)
    T.Place(f.title,18,14,width-36,28,f)
    f.title:SetText(mode=='restore'and Z.L('Gesicherte Ausgangskonfiguration','Saved original configuration')or Z.L('Blizzard-Chat einrichten · Vorschau','Set up Blizzard chat · Preview'))
    T.Place(f.scroll,18,52,width-36,height-160,f)
    f.content:SetWidth(width-42)
    f.body:SetWidth(width-48);f.body:SetText(plan and table.concat(plan.rows,'\n\n')or reason)
    local bodyHeight=f.body:GetStringHeight()+12
    T.Place(f.body,0,0,width-48,bodyHeight,f.content);f.content:SetHeight(bodyHeight)
    f.maxScroll=math.max(0,bodyHeight-f.scroll:GetHeight());f.scroll:SetVerticalScroll(0)
    T.Place(f.status,18,height-98,width-36,44,f)
    f.status:SetText(plan and Z.L('Nur nach Bestätigung werden die aufgeführten Tabs und Optionen geändert. Bestehende eigene Tabs bleiben erhalten.','Only confirmation changes the listed tabs and options. Existing custom tabs are preserved.')or'')
    T.Place(f.cancel,18,height-44,150,30,f);T.Place(f.apply,width-208,height-44,190,30,f)
    f.apply.label:SetText(mode=='restore'and Z.L('Wiederherstellen','Restore')or mode=='display'and Z.L('Übernehmen','Apply')or Z.L('Einrichtung übernehmen','Apply setup'))
    f.apply:SetEnabled(plan~=nil);f:Show()
end
O.Preview=preview
function O.Add(add)
    add('section',Z.L('Blizzard Chat','Blizzard Chat'))
    add('note',Z.L('Optionaler Assistent für den nativen Chat. Häkchen sind zunächst ein Entwurf; erst die bestätigte Vorschau ändert den Blizzard-Chat.','Optional setup for native chat. Checkboxes are a draft; only the confirmed preview changes Blizzard chat.'))
    local conflict=N.Conflict();if conflict then add('note',conflict)end
    add('action',Z.L('Chat automatisch einrichten …','Set up chat automatically …'),{run=function()preview('setup')end})
    add('section',Z.L('Geplante Tab-Aufteilung','Planned tab layout'))
    local details={
        general=Z.L('Sagen, Schreien, Emotes und beigetretene öffentliche Kanäle.','Say, yell, emotes and joined public channels.'),
        guild=Z.L('Gilde und Offizier.','Guild and officer.'),
        group=Z.L('Gruppe, Schlachtzug, Instanz und Schlachtzugswarnungen – einschließlich Anführer.','Party, raid, instance and raid warnings, including leaders.'),
        whisper=Z.L('Flüstern und Battle.net.','Whispers and Battle.net.'),
        system=Z.L('Loot, Ruf, Erfahrung, Quest- und sonstige Systemmeldungen.','Loot, reputation, experience, quest and other system messages.'),
    }
    for _,d in ipairs(N.definitions)do
        local key=d.key
        add('check',Z.L(d.de,d.en),{get=function()return options().include[key]end,set=function(v)options().include[key]=v end})
        add('note',details[key])
    end
    check(add,Z.L('Systemmeldungen aus Allgemein auslagern','Move system messages out of General'),'moveSystem')
    add('note',Z.L('SYSTEM bleibt in Allgemein als Auffanggruppe erhalten. Quest- und kritische Systemmeldungen lassen sich deshalb nicht vollständig auslagern. Nicht ausgewählte Tabs werden nicht umkonfiguriert.','SYSTEM stays in General as a safety net, so quest and critical system messages cannot be moved completely. Excluded tabs are not reconfigured.'))
    add('action',Z.L('Vorschau der geplanten Änderungen …','Preview planned changes …'),{run=function()preview('setup')end})
    add('section',Z.L('Native Tab-Zähler','Native tab counters'))
    check(add,Z.L('Ungelesen-Zähler aktivieren','Enable unread counters'),'unread')
    check(add,Z.L('Bei neuen Nachrichten dezent aufleuchten','Flash subtly for new messages'),'flash')
    add('note',Z.L('Eigene und nicht sicher auswertbare Nachrichten werden nicht gezählt. Zähler gelten nur für neue zugestellte Chatzeilen mit lesbarer Nachrichten-ID; sie starten nach /reload bei null.','Own messages and unsafe metadata are not counted. Counters cover newly delivered chat lines with readable message IDs; they restart at zero after /reload.'))
    for _,entry in ipairs(N.ListTabs())do local id=tostring(entry.id)
        add('check',string.format(Z.L('Zähler: %s (#%d)','Counter: %s (#%d)'),entry.name,entry.id),{get=function()return options().unreadTabs[id]~=false end,set=function(v)if v then options().unreadTabs[id]=nil else options().unreadTabs[id]=false end end})
    end
    add('section',Z.L('Native Darstellung','Native appearance'))
    check(add,Z.L('Kompakte Tab-Schrift','Compact tab text'),'compactTabs')
    check(add,Z.L('Zusätzliche Chat-Buttons ausblenden','Hide additional chat buttons'),'hideButtons')
    check(add,Z.L('Chat-Hintergrundelemente ausblenden','Hide chat background elements'),'hideBackground')
    add('choice',Z.L('Zeitstempel','Timestamps'),{get=function()return options().timestamps end,set=function(v)options().timestamps=v end,
        choices={{'keep',Z.L('Unverändert','Keep current')},{'off',Z.L('Aus','Off')},{'hm','HH:MM'},{'hms','HH:MM:SS'}}})
    add('choice',Z.L('Klassenfarben für Namen','Class colors for names'),{get=function()return options().classColors end,set=function(v)options().classColors=v end,
        choices={{'keep',Z.L('Unverändert','Keep current')},{'on',Z.L('An','On')},{'off',Z.L('Aus','Off')}}})
    add('note',Z.L('Zeitstempel und Klassenfarben verwenden native Einstellungen und gelten für den gesamten Blizzard-Chat. Eine native Option für kürzere Kanalpräfixe ist auf Forever nicht belegt; die Formate bleiben unverändert.','Timestamps and class colors use native settings and affect all Blizzard chat. A native shorter-channel-prefix option is not verified on Forever, so formats remain unchanged.'))
    add('action',Z.L('Nur Zähler & Darstellung übernehmen …','Apply counters & appearance only …'),{run=function()preview('display')end})
    add('note',Z.L('Ändert keine Tab-Aufteilung; zeigt vorher die betroffenen Tabs und Einstellungen.','Leaves the tab layout unchanged; lists affected tabs and settings first.'))
    add('section',Z.L('Sicherung & Wiederherstellung','Backup & restore'))
    add('note',Z.L('Die erste bestätigte Einrichtung sichert die betroffene Ausgangskonfiguration pro Charakter. Weitere Einrichtungen überschreiben diese Sicherung nicht. Chatverlauf ist nicht Bestandteil der Sicherung.','The first confirmed setup saves the affected original configuration per character. Later setups preserve that backup. Chat history is not included.'))
    add('action',Z.L('Standardkonfiguration wiederherstellen …','Restore original configuration …'),{run=function()preview('restore')end})
    add('note',Z.L('Stellt die gesicherte Konfiguration vor ZENIAL wieder her. Nur vom Assistenten neu angelegte Tabs werden nach Vorschau geschlossen.','Restores the saved configuration from before ZENIAL. Only assistant-created tabs are closed, after preview.'))
end
