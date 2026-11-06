local _,Z=...
local U=Z.UI
local pages={{'appearance','Darstellung','Appearance'},{'messages','Nachrichten','Messages'},{'behavior','Verhalten','Behavior'},{'notifications','Benachrichtigungen','Notifications'},{'history','Verlauf & Daten','History & data'}}
local function add(kind,label,options)
    local row=options or{};row.kind=kind;row.label=label;U.optionSpecs[#U.optionSpecs+1]=row;return row
end
-- A limit that would delete something asks first; nothing is removed if the answer is no.
local function retentionSetter(key)
    return function(v)
        local s=Z.store.settings
        local count=key=='retentionCount'and v or s.retentionCount
        local days=key=='retentionDays'and v or s.retentionDays
        local n=Z.store:CountPrunable(count,days)
        local function apply()s[key]=v;Z.store:PruneAll();U.RebuildOptions()end
        if n>0 then U.Confirm(string.format(Z.L('%d Nachrichten werden dauerhaft gelöscht. Fortfahren?','%d messages will be deleted for good. Continue?'),n),apply)
        else apply()end
    end
end
local function sizeLabel(bytes)
    if bytes>=1048576 then return string.format('%.1f MB',bytes/1048576)end
    return string.format('%.0f KB',bytes/1024)
end
local function soundChoices()
    local list={}
    for _,sound in ipairs(Z.Notifications.SOUNDS)do
        if type(SOUNDKIT)=='table'and SOUNDKIT[sound[1]]then list[#list+1]={sound[1],Z.L(sound[2],sound[3])}end
    end
    return list
end
local function buildSpecs()
    local s=Z.store.settings;U.optionSpecs={}
    if U.settingsPage=='appearance'then
        add('section',Z.L('Darstellung','Appearance'))
        add('slider',Z.L('Hintergrund aktiv','Active background'),{key='alphaActive',min=0,max=1,step=.01,format=function(v)return math.floor(v*100+.5)..' %'end})
        add('slider',Z.L('Hintergrund inaktiv','Inactive background'),{key='alphaInactive',min=0,max=1,step=.01,format=function(v)return math.floor(v*100+.5)..' %'end})
        add('note',Z.L('Schrift und Symbole bleiben gut lesbar.','Text and icons stay fully legible.'))
        add('section',Z.L('Größe & Lesbarkeit','Size & readability'))
        add('slider',Z.L('UI-Skalierung','UI scale'),{key='scale',min=.75,max=1.5,step=.05,format=function(v)return math.floor(v*100+.5)..' %'end})
        add('slider',Z.L('Schriftgröße','Font size'),{key='fontSize',min=12,max=20,step=1,format=function(v)return tostring(math.floor(v))end})
        add('choice',Z.L('Seitenleiste','Sidebar'),{key='sidebar',choices={{'auto',Z.L('Automatisch','Automatic')},{'names',Z.L('Namen','Names')},{'icons',Z.L('Symbole','Icons')}}})
        add('note',Z.L('Bei wenig Platz entfallen zuerst Vorschauen, danach Namen.','At smaller widths, previews hide first, then names.'))
        add('check',Z.L('Nachrichtenvorschau anzeigen','Show last-message previews'),{key='previews'})
        add('check',Z.L('Kompakte Seitenleiste','Compact sidebar'),{key='sidebarCompact'})
        add('choice',Z.L('Kanal- und Gruppennamen','Channel and group names'),{key='channelLabels',choices={{'full',Z.L('Vollständig','Full')},{'short',Z.L('Kurz (Gilde: G, Schlachtzug: SZ)','Short (Guild: G, Raid: R)')},{'number',Z.L('Kanalnummer','Channel number')}}})
        add('note',Z.L('Eigene Anzeigenamen vergibst du im Gesprächsmenü •••. Die Kanalnummer gilt nur für Kanäle, Gruppen zeigen dort ihr Kürzel.','Set your own display names in the ••• conversation menu. The number applies to channels only; groups show their short name.'))
        add('section',Z.L('Fenster','Window'))
        add('check',Z.L('Position und Größe sperren','Lock position and size'),{key='locked'})
        add('action',Z.L('Position und Größe zurücksetzen','Reset position and size'),{run=U.ResetGeometry})
        add('check',Z.L('Minimap-Icon ausblenden','Hide minimap icon'),{key='minimapHidden',after=U.ApplyMinimapVisibility})
        add('section',Z.L('Ausblenden','Fading'))
        add('check',Z.L('Fenster bei Inaktivität ausblenden','Fade the window when idle'),{key='fadeEnabled'})
        add('slider',Z.L('Ausblenden nach','Fade after'),{key='fadeAfter',min=5,max=300,step=5,format=function(v)return math.floor(v)..' s'end})
        add('slider',Z.L('Sichtbarkeit danach','Visibility afterwards'),{key='fadeAlpha',min=0,max=1,step=.05,format=function(v)return math.floor(v*100+.5)..' %'end})
        add('note',Z.L('Überfahren, Tippen oder eine neue Nachricht blenden das Fenster wieder ein.','Hovering, typing or a new message bring the window back.'))
    elseif U.settingsPage=='messages'then
        add('section',Z.L('Namen','Names'))
        add('choice',Z.L('Namensformat','Name format'),{key='nameFormat',choices={{'full',Z.L('Vorname Nachname','First Last')},{'first',Z.L('Nur Vorname','First name only')},{'last',Z.L('Nur Nachname','Last name only')},{'initialLast',Z.L('V. Nachname','F. Last')},{'firstInitial',Z.L('Vorname N.','First L.')},{'initials',Z.L('Initialen','Initials')}}})
        add('note',Z.L('Gilt nur für Charaktere mit genau Vor- und Nachname. Andere Namen und Battle.net-Konten bleiben vollständig. Beim Überfahren steht immer der ganze Name da.','Applies only to characters with exactly a first and a last name. Other names and Battle.net accounts stay complete. Hovering always shows the whole name.'))
        add('check',Z.L('Klassenfarben für Namen','Class colors for names'),{key='classColors'})
        add('section',Z.L('Symbole','Icons'))
        add('choice',Z.L('Symbol neben Nachrichten','Icon next to messages'),{key='senderIcon',choices={{'class',Z.L('Klasse','Class')},{'race',Z.L('Rasse','Race')},{'none',Z.L('Keines','None')}}})
        add('choice',Z.L('Rassensymbole','Race icons'),{key='raceIconQuality',choices={{'hd',Z.L('Hohe Auflösung','High resolution')},{'sd',Z.L('Standard','Standard')}}})
        add('slider',Z.L('Symbolgröße','Icon size'),{key='iconSize',min=16,max=48,step=2,format=function(v)return tostring(math.floor(v))end})
        add('note',Z.L('Die Rasse ist erst nach einer neuen Nachricht der Person bekannt. Bis dahin steht dort die Klasse, ist auch die unbekannt, das Chat-Symbol.','A race is known only after a new message from that person. Until then the class is shown and, if that is unknown too, the chat icon.'))
        add('section',Z.L('Zeit','Time'))
        add('choice',Z.L('Zeitstempel','Timestamps'),{key='timeFormat',choices={{'hm','14:05'},{'hms','14:05:30'},{'date','06.11.2026 14:05'},{'relative',Z.L('Heute 14:05','Today 14:05')},{'off',Z.L('Aus','Off')}}})
        add('choice',Z.L('Uhrzeit','Clock'),{key='timeZone',choices={{'local',Z.L('Lokale Zeit','Local time')},{'server',Z.L('Serverzeit','Server time')}}})
        add('note',Z.L('Die Serverzeit gilt mit dem heutigen Abstand auch für ältere Nachrichten; über eine Zeitumstellung hinweg kann sie um eine Stunde abweichen. Überfahren zeigt Datum und Sekunden, Shift-Klick zitiert.','Server time applies today\'s offset to older messages too, so across a clock change it can be off by an hour. Hovering shows date and seconds, shift-click quotes.'))
        add('check',Z.L('Datumstrenner anzeigen','Show date separators'),{key='dateSeparators'})
        add('section',Z.L('Layout','Layout'))
        add('choice',Z.L('Nachrichtenlayout','Message layout'),{key='layoutStyle',choices={{'bubbles',Z.L('Sprechblasen','Bubbles')},{'compact',Z.L('Kompakt','Compact')},{'classic',Z.L('Klassische Liste','Classic list')}}})
        add('check',Z.L('Aufeinanderfolgende Nachrichten gruppieren','Group consecutive messages'),{key='groupMessages'})
        add('choice',Z.L('Schriftart','Font'),{key='fontFace',choices={{'noto','Noto Sans'},{'friz','Friz Quadrata'},{'arial','Arial Narrow'},{'morpheus','Morpheus'},{'skurri','Skurri'}}})
        add('choice',Z.L('Textkontur','Text outline'),{key='fontOutline',choices={{'none',Z.L('Keine','None')},{'OUTLINE',Z.L('Dünn','Thin')},{'THICKOUTLINE',Z.L('Dick','Thick')}}})
        add('slider',Z.L('Zeilenabstand','Line spacing'),{key='lineSpacing',min=0,max=8,step=1,format=function(v)return tostring(math.floor(v))end})
        add('section',Z.L('Links & Zitate','Links & quotes'))
        add('check',Z.L('Webadressen erkennen','Detect web addresses'),{key='urlLinks'})
        add('note',Z.L('Ein Klick zeigt die Adresse zum Kopieren. Addons können keinen Browser öffnen.','A click shows the address for copying. Addons cannot open a browser.'))
        add('choice',Z.L('Zitat-Format','Quote format'),{key='quoteFormat',choices={{'text',Z.L('Nur Text','Text only')},{'sender',Z.L('Mit Absender','With sender')},{'time',Z.L('Mit Absender und Zeit','With sender and time')}}})
    elseif U.settingsPage=='behavior'then
        add('section',Z.L('Eingabe & Fenster','Input & window'))
        add('check',Z.L('Eingabe beim Öffnen fokussieren','Focus composer when opening'),{key='focusOnOpen'})
        add('check',Z.L('Bei Direktnachrichten automatisch öffnen (nicht im Kampf)','Open automatically for direct messages (not in combat)'),{key='autoOpen'})
        add('note',Z.L('Enter sendet · Shift+Enter fügt einen Zeilenumbruch ein. Escape löst zuerst den Eingabefokus.','Enter sends · Shift+Enter inserts a new line. Escape first releases input focus.'))
        add('check',Z.L('Gesendete Nachrichten mit Pfeil hoch/runter abrufen','Recall sent messages with arrow up/down'),{key='inputHistory'})
        add('choice',Z.L('Verlauf der Eingabe','Input history'),{key='inputHistoryScope',choices={{'conversation',Z.L('Je Gespräch','Per conversation')},{'global',Z.L('Für alle Gespräche','Across conversations')}}})
        add('check',Z.L('Leseposition je Gespräch merken','Remember reading position per conversation'),{key='rememberScroll'})
        add('check',Z.L('Suchverlauf speichern','Keep search history'),{key='searchHistoryEnabled'})
        add('note',Z.L('Tastenkürzel: WoW → Tastenbelegung → Zenial Chat. /zchat öffnet das Fenster.','Shortcut: WoW → Key Bindings → Zenial Chat. /zchat opens the window.'))
        add('section',Z.L('Öffentliche & eigene Kanäle','Public & custom channels'))
        add('check',Z.L('Öffentliche Kanäle im Messenger anbieten','Offer public channels in Messenger'),{key='publicChannels',after=function()U.RebuildOptions()end})
        if s.publicChannels then
            local channels=Z.adapter:JoinedChannels()
            for _,channel in ipairs(channels)do
                local name=channel.name
                add('check',name,{get=function()return s.enabledChannels[name:lower()]==true end,set=function(value)Z.adapter:SetChannel(name,value)end})
            end
            if#channels==0 then add('note',Z.L('Noch keine beigetretenen Kanäle verfügbar.','No joined channels available yet.'))end
        end
    elseif U.settingsPage=='notifications'then
        add('section',Z.L('Neue Nachrichten','New messages'))
        add('note',Z.L('Stummgeschaltete Gespräche behalten ihren Ungelesen-Zähler, spielen aber keinen Ton und zeigen keinen Hinweis.','Muted conversations keep unread counts, but do not play a sound or show a notification.'))
        add('note',Z.L('Der Client spielt bei Flüstern und Schlachtzugswarnungen selbst einen Ton. Ein Ton hier kommt zusätzlich hinzu; pro Sekunde spielt Zenial Chat höchstens einen.','The client plays its own sound for whispers and raid warnings. A sound here comes on top; Zenial Chat plays at most one per second.'))
        add('slider',Z.L('Hinweis-Dauer','Notice duration'),{key='toastDuration',min=2,max=15,step=1,format=function(v)return math.floor(v)..' s'end})
        add('check',Z.L('Im Kampf keine Töne und Hinweise','No sounds or notices in combat'),{key='suppressInCombat'})
        add('action',Z.L('Hinweis-Vorschau anzeigen','Show notice preview'),{run=function()Z.Notifications.Preview()end})
        for _,group in ipairs({{'whispers','Flüstern','Whispers'},{'bnet','Battle.net','Battle.net'},{'guild','Gilde & Offizier','Guild & officer'},{'groups','Gruppen','Groups'},{'raidWarning','Schlachtzugswarnungen','Raid warnings'},{'channels','Öffentliche Kanäle','Public channels'}})do
            local key=group[1];local label=Z.L(group[2],group[3])
            add('section',label)
            for _,setting in ipairs({{'sound','Ton abspielen','Play sound'},{'toast','Hinweis anzeigen','Show notification'}})do
                local field=setting[1]
                add('check',Z.L(setting[2],setting[3]),{get=function()return s.notifications[key][field]end,set=function(value)s.notifications[key][field]=value end})
            end
            add('choice',Z.L('Ton','Sound'),{choices=soundChoices,get=function()return Z.Notifications.KitName(key,s.notifications[key])end,set=function(value)
                s.notifications[key].soundKit=value;Z.Notifications.PlayKit(value)
            end})
        end
        add('action',Z.L('Benachrichtigungston testen','Test notification sound'),{run=function()Z.Notifications.PlayTell()end})
        add('action',Z.L('Hinweisposition zurücksetzen','Reset notification position'),{run=function()Z.Notifications.ResetPosition()end})
        add('note',Z.L('Den Hinweis verschiebst du mit gedrückter linker Maustaste; ein einfacher Klick öffnet das Gespräch.','Drag the notification with the left mouse button to move it; a plain click opens the conversation.'))
    else
        add('section',Z.L('Dein lokales Archiv','Your local archive'))
        local conversations,messages,bytes=Z.store:Stats()
        add('note',string.format(Z.L('%d Gespräche · %d Nachrichten · %s Text. Die Datei auf der Festplatte ist wegen der Zusatzdaten größer.','%d conversations · %d messages · %s of text. The file on disk is larger because of the extra data.'),conversations,messages,sizeLabel(bytes)))
        if s.retentionCount>0 or s.retentionDays>0 then
            add('note',Z.L('Ältere Nachrichten werden nach den Grenzen unten gelöscht. Das Archiv wird auf diesem Computer über deine Charaktere geteilt.','Older messages are deleted according to the limits below. The archive is shared across your characters on this computer.'))
        else
            add('note',Z.L('Nachrichten bleiben dauerhaft erhalten, bis du sie selbst löschst. Das Archiv wird auf diesem Computer über deine Charaktere geteilt.','Messages remain until you delete them. The archive is shared across your characters on this computer.'))
        end
        add('choice',Z.L('Höchstens pro Gespräch','Maximum per conversation'),{choices={{0,Z.L('Unbegrenzt','Unlimited')},{500,'500'},{1000,'1.000'},{5000,'5.000'},{10000,'10.000'},{50000,'50.000'}},get=function()return s.retentionCount end,set=retentionSetter('retentionCount')})
        add('choice',Z.L('Höchstes Alter','Maximum age'),{choices={{0,Z.L('Unbegrenzt','Unlimited')},{30,Z.L('30 Tage','30 days')},{90,Z.L('90 Tage','90 days')},{180,Z.L('180 Tage','180 days')},{365,Z.L('1 Jahr','1 year')}},get=function()return s.retentionDays end,set=retentionSetter('retentionDays')})
        do
            local c=Z.store:Get(Z.store.db.ui.selected)
            if c then
                add('check',string.format(Z.L('„%s“ von den Grenzen ausnehmen','Exempt "%s" from the limits'),Z.Format.ConversationLabel(c)),{get=function()return c.keep==true end,set=function(value)Z.store:SetKeep(c.key,value)end})
                add('action',Z.L('Ausgewähltes Gespräch exportieren …','Export selected conversation …'),{run=function()U.ExportConversation(c)end})
            end
        end
        add('note',Z.L('Gespräch schließen blendet es aus und erhält den Verlauf. Verlauf löschen leert nur das lokale Archiv.','Closing a conversation preserves its history. Clearing history only empties the local archive.'))
        add('action',Z.L('Verlauf des ausgewählten Gesprächs löschen …','Clear selected conversation history …'),{run=function()
            local c=Z.store:Get(Z.store.db.ui.selected)
            if not c then U.Notice(Z.L('Wähle zuerst ein Gespräch.','Select a conversation first.'));return end
            U.Confirm(Z.L('Lokalen Verlauf von ','Clear local history for ')..c.name..'?',function()Z.store:Clear(c.key)end)
        end})
        add('action',Z.L('Alle lokalen Verläufe löschen …','Clear all local history …'),{run=function()
            U.Confirm(Z.L('Alle lokalen Verläufe löschen?','Clear all local history?'),function()Z.store:ClearAll()end)
        end})
    end
end
local function value(spec)if spec.get then return spec.get()end;return Z.store.settings[spec.key]end
local function change(spec,v)
    if spec.set then spec.set(v)else U.SetSetting(spec.key,v)end
    if spec.after then spec.after()end
end
local function choices(spec)return type(spec.choices)=='function'and spec.choices()or spec.choices or{}end
local function control(index,spec)
    local T=Z.Theme;local key=spec.kind..':'..index
    if U.optionRows[key]then return U.optionRows[key]end
    local row=CreateFrame('Frame',nil,U.settingsContent);row.label=T.Text(row,'',13,false,'text');row.label:SetWordWrap(true)
    if spec.kind=='section'then T.Font(row.label,17,true,'goldBright')
    elseif spec.kind=='note'then T.Font(row.label,12,false,'muted')
    elseif spec.kind=='slider'then
        local track=T.Frame(row,'field','border');row.track=track
        local slider=CreateFrame('Slider',nil,track);row.slider=slider
        slider:SetOrientation('HORIZONTAL');slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
        slider:SetObeyStepOnDrag(true)
        row.number=T.Text(row,'',12,false,'text');row.number:SetJustifyH('RIGHT')
        slider:SetScript('OnValueChanged',function(_,v)
            if row.updating then return end
            local item=row.spec;local rounded=math.floor(v/item.step+.5)*item.step
            change(item,rounded)
        end)
    elseif spec.kind=='check'then
        row.check=CreateFrame('CheckButton',nil,row,'BackdropTemplate');T.Panel(row.check,'field','border')
        row.check:SetCheckedTexture('Interface\\Buttons\\UI-CheckBox-Check')
        row.check:SetScript('OnClick',function(self)change(row.spec,self:GetChecked()==true)end)
        row:EnableMouse(true);row:SetScript('OnMouseUp',function()local v=not value(row.spec);row.check:SetChecked(v);change(row.spec,v)end)
    elseif spec.kind=='choice'then
        row.button=T.Button(row,'',function(self)
            local item=row.spec;local menu={}
            for _,choice in ipairs(choices(item))do
                local id=choice[1]
                menu[#menu+1]={text=choice[2],run=function()change(item,id);U.LayoutOptions()end}
            end
            if#menu==0 then menu[1]={text=Z.L('Keine Auswahl verfügbar','No options available'),run=function()end}end
            U.ShowMenu(self,menu)
        end)
        row.button.arrow=row.button:CreateTexture(nil,'ARTWORK');row.button.arrow:SetTexture('Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up')
        row.button.arrow:SetPoint('RIGHT',row.button,'RIGHT',-7,0);row.button.arrow:SetSize(14,14)
    elseif spec.kind=='action'then row.button=T.Button(row,'',function()row.spec.run()end)end
    U.optionRows[key]=row;return row
end
function U.RebuildOptions()
    if not U.settingsScroll then return end
    buildSpecs();U.LayoutOptions()
end
function U.LayoutOptions()
    if not U.settingsScroll then return end
    local T=Z.Theme;local panel=U.settingsPanel;local w=panel:GetWidth();local h=panel:GetHeight()
    T.Place(U.optionsTitle,18,12,math.max(70,w-180),34,panel)
    T.Place(U.settingsScroll,16,66,w-38,h-109,panel);U.settingsContent:SetWidth(w-48)
    T.Place(U.optionsFooter,18,h-29,w-36,20,panel)
    T.Place(U.optionsScrollbar,w-15,67,8,h-111,panel)
    local navWidth=U.settingsNav:GetWidth();local compact=U.metrics.iconOnly
    for i,entry in ipairs(pages)do
        local b=U.optionTabs[i];T.Place(b,6,12+(i-1)*58,navWidth-12,52,U.settingsNav)
        T.Place(b.icon,7,8,34,34,b);T.Place(b.caption,50,16,math.max(1,navWidth-70),26,b)
        b.caption:SetShown(not compact);b.zenialBackgroundKind=entry[1]==U.settingsPage and'selected'or'sidebar'
        local c=T.colors[b.zenialBackgroundKind];b:SetBackdropColor(c[1],c[2],c[3],U.currentAlpha or.94)
    end
    local y=3;local used={};local pageWidth=w-54;local width=pageWidth;local stacked=width<540
    local showLivePreview=U.settingsPage=='appearance'and pageWidth>=650
    if showLivePreview and not U.optionsLivePreview then
        local f=T.Frame(U.settingsContent,'field','border');U.optionsLivePreview=f
        f.title=T.Text(f,Z.L('Vorschau','Preview'),11,true,'goldBright');T.Place(f.title,10,6,220,17,f)
        f.rows={}
        for i=1,3 do
            local row={icon=T.Icon(f,{}),name=T.Text(f,'',11,true),body=T.Text(f,'',10,false,'muted')}
            row.name:SetWordWrap(false);row.body:SetWordWrap(false);f.rows[i]=row
            T.Place(row.icon,9,26+(i-1)*27,21,21,f);T.Place(row.name,38,23+(i-1)*27,200,16,f);T.Place(row.body,38,37+(i-1)*27,200,15,f)
        end
    end
    if U.optionsLivePreview then
        U.optionsLivePreview:SetShown(showLivePreview)
        if showLivePreview then
            local f=U.optionsLivePreview;T.Place(f,pageWidth-255,39,255,112,U.settingsContent)
            f.previewOpacity=Z.store.settings.alphaInactive
            local c=Z.store:Get(Z.store.db.ui.selected);local messages=c and c.messages or{}
            for i,row in ipairs(f.rows)do
                local message=messages[math.max(1,#messages-3+i)]
                row.name:SetText(message and(message.outgoing and Z.L('Du','You')or message.sender)or Z.L('Kontakt','Contact'))
                row.body:SetText(message and Z.Plain(message.text)or Z.L('So sieht dein Gespräch aus.','This is your conversation preview.'))
                T.NameColor(row.name,message and message.senderClass);T.SetIcon(row.icon,{kind='WHISPER',classFile=message and message.senderClass})
            end
        end
    end
    for i,spec in ipairs(U.optionSpecs or{})do
        width=showLivePreview and i>=2 and i<=4 and pageWidth-280 or pageWidth
        local row=control(i,spec);row.spec=spec;row:Show();used[row]=true;row.label:SetText(spec.label)
        local height
        if spec.kind=='section'then height=stacked and 43 or 36;T.Place(row.label,0,9,width,25,row)
        elseif spec.kind=='note'then
            row.label:SetWidth(width);height=math.max(stacked and 39 or 28,row.label:GetStringHeight()+12);T.Place(row.label,0,3,width,height-8,row)
        elseif spec.kind=='check'then
            height=stacked and 42 or 36;T.Place(row.check,1,7,22,22,row);T.Place(row.label,34,7,width-38,29,row)
            row.check:SetChecked(value(spec)==true)
        elseif spec.kind=='slider'then
            height=stacked and 70 or 42
            local x=stacked and 0 or math.min(180,width*.42);local top=stacked and 33 or 10
            T.Place(row.label,0,10,stacked and width or x-10,24,row)
            T.Place(row.track,x,top+8,width-x-59,7,row);T.Place(row.slider,2,-10,width-x-63,27,row.track)
            T.Place(row.number,width-55,top+3,55,22,row)
            row.updating=true;row.slider:SetMinMaxValues(spec.min,spec.max);row.slider:SetValueStep(spec.step);row.slider:SetValue(value(spec));row.updating=false
            row.number:SetText(spec.format(value(spec)))
        elseif spec.kind=='choice'then
            height=stacked and 74 or 42;local x=stacked and 0 or math.min(180,width*.42)
            T.Place(row.label,0,10,stacked and width or x-10,24,row)
            local current=value(spec);local label=Z.L('Auswählen …','Choose …')
            for _,item in ipairs(choices(spec))do if tostring(item[1])==tostring(current)then label=item[2];break end end
            row.button.label:SetText(label);T.Place(row.button,x,stacked and 34 or 4,width-x,32,row)
        else
            height=stacked and 49 or 42;row.label:Hide();row.button.label:SetText(spec.label);T.Place(row.button,0,5,width,33,row)
        end
        T.Place(row,0,y,width,height,U.settingsContent);y=y+height
    end
    for _,row in pairs(U.optionRows)do if not used[row]then row:Hide()end end
    U.settingsContent:SetHeight(math.max(y,U.settingsScroll:GetHeight()))
    U.optionsMaxScroll=math.max(0,y-U.settingsScroll:GetHeight());U.optionsScroll=math.min(U.optionsScroll or 0,U.optionsMaxScroll)
    U.settingsScroll:SetVerticalScroll(U.optionsScroll)
    U.optionsUpdating=true;U.optionsScrollbar:SetMinMaxValues(0,math.max(1,U.optionsMaxScroll));U.optionsScrollbar:SetValue(U.optionsScroll);U.optionsUpdating=false
    U.optionsScrollbar:SetShown(U.optionsMaxScroll>0)
    -- New controls and the inactive sample need the current texture opacity
    -- even when hover/focus activity itself has not changed.
    T.Opacity(U.currentAlpha or Z.store.settings.alphaActive)
end
function U.OpenSettings(page)
    U.Open();U.settingsPage=page or'appearance'
    U.input:ClearFocus();U.search:ClearFocus();if U.menu then U.menu:Hide()end
    if not U.settingsScroll then
        local T=Z.Theme
        U.optionsTitle=T.Text(U.settingsPanel,Z.L('Einstellungen','Settings'),22,true)
        U.settingsScroll=CreateFrame('ScrollFrame',nil,U.settingsPanel);U.settingsScroll:SetClipsChildren(true)
        U.settingsContent=CreateFrame('Frame',nil,U.settingsScroll);U.settingsScroll:SetScrollChild(U.settingsContent)
        U.optionsScrollbar=CreateFrame('Slider',nil,U.settingsPanel,'BackdropTemplate');T.Panel(U.optionsScrollbar,'field','line')
        U.optionsScrollbar:SetOrientation('VERTICAL');U.optionsScrollbar:SetThumbTexture('Interface\\Buttons\\UI-ScrollBar-Knob')
        U.optionsScrollbar:SetScript('OnValueChanged',function(_,v)if not U.optionsUpdating then U.optionsScroll=v;U.settingsScroll:SetVerticalScroll(v)end end)
        U.settingsScroll:EnableMouseWheel(true);U.settingsScroll:SetScript('OnMouseWheel',function(_,delta)
            U.optionsScroll=math.max(0,math.min(U.optionsMaxScroll,U.optionsScroll-delta*40));U.settingsScroll:SetVerticalScroll(U.optionsScroll);U.LayoutOptions()
        end)
        U.optionsFooter=T.Text(U.settingsPanel,Z.L('Änderungen werden sofort gespeichert.','Changes are saved immediately.'),11,false,'muted')
        U.optionRows={};U.optionTabs={}
        for i,entry in ipairs(pages)do
            local id=entry[1];local b=T.Button(U.settingsNav,'',function()U.OpenSettings(id)end)
            b.icon=T.Icon(b,{slot=id});b.caption=T.Text(b,Z.L(entry[2],entry[3]),13,true)
            b.tip=Z.L(entry[2],entry[3]);U.optionTabs[i]=b
        end
    end
    U.optionsScroll=0;U.listPanel:Hide();U.chatPanel:Hide();U.settingsNav:Show();U.settingsPanel:Show();U.back:Show()
    buildSpecs();U.Layout()
end
