local _,Z=...
local U=Z.UI
-- The settings are a view inside the chat window (Window, embedded) with one Form per page.
local Form,Window=Z.Form,Z.Window
local function t(de,en)return{de,en}end
local function tr(value)
    if type(value)=='table'then return Z.L(value[1],value[2])end
    return value
end
local pages={
    {key='appearance',title=t('Darstellung','Appearance')},
    {key='messages',title=t('Nachrichten','Messages')},
    {key='behavior',title=t('Verhalten','Behavior')},
    {key='notifications',title=t('Benachrichtigungen','Notifications')},
    {key='history',title=t('Verlauf & Daten','History & data')},
    {key='blizzard',title=t('Blizzard Chat','Blizzard Chat')},
}
U.settingsPages=pages
local function percent(v)return math.floor(v*100+.5)..' %'end
local function whole(v)return tostring(math.floor(v))end
local function seconds(v)return math.floor(v)..' s'end
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
local function selectedConversation()return Z.store:Get(Z.store.db.ui.selected)end
-- The page being shown is read again after a change (rows that depend on a value, texts with counts).
function U.RefreshSettings()
    local view=U.settingsView;local key=view and view:CurrentPage();local page=key and view:Page(key)
    if page and page.refresh then page.refresh()end
end
function U.RebuildOptions()
    local view=U.settingsView;if not view then return end
    local key=view:CurrentPage();if key then view:Rebuild(key)end
end
-- A limit that would delete something asks first; nothing is removed if the answer is no.
local function retentionSetter(view,key,label)
    return function(v)
        local s=Z.store.settings
        local count=key=='retentionCount'and v or s.retentionCount
        local days=key=='retentionDays'and v or s.retentionDays
        local n=Z.store:CountPrunable(count,days)
        local function apply()s[key]=v;Z.store:PruneAll();U.RefreshSettings()end
        if n>0 then
            view:Confirm({title=label,accept=t('Löschen','Delete'),variant='danger',onAccept=apply,
                text=string.format(Z.L('%d Nachrichten werden dauerhaft gelöscht. Fortfahren?','%d messages will be deleted for good. Continue?'),n)})
        else apply()end
    end
end
-- Every setting is read from and written to the live settings table; U.SetSetting lays the window out again.
local function context()
    return{tr=tr,default=function(key)return Z.Store.Defaults[key]end,
        read=function(key)return Z.store.settings[key]end,write=function(key,value)U.SetSetting(key,value)end,
        changed=function()U.RefreshSettings()end}
end
local function newForm(page,view)
    local form=Form.New(context(),page.content,view.formWidth)
    page.form=form
    page.refresh=function()
        form:Refresh();page.content:SetHeight(math.max(1,form:Height()))
        -- Rows built or changed now need the opacity of the window as well (the preview).
        Z.ChatTheme.Opacity(U.currentAlpha or Z.store.settings.alphaActive)
    end
    return form
end
local function toggle(form,key,de,en,extra)
    local spec={key=key,label=t(de,en)};for k,v in pairs(extra or{})do spec[k]=v end
    return form:Toggle(spec)
end
local function slider(form,key,de,en,min,max,step,format,extra)
    local spec={key=key,label=t(de,en),min=min,max=max,step=step,format=format,live=true};for k,v in pairs(extra or{})do spec[k]=v end
    return form:Slider(spec)
end
local function choice(form,key,de,en,options,extra)
    local spec={key=key,label=t(de,en),options=options};for k,v in pairs(extra or{})do spec[k]=v end
    return form:Select(spec)
end
local function note(form,de,en,extra)
    local spec={text=t(de,en)};for k,v in pairs(extra or{})do spec[k]=v end
    return form:Note(spec)
end
-- The sample of the appearance page: three lines in the look of the conversation, at the inactive opacity.
local function previewRow(form)
    local sample
    form:Custom({anchor='preview',height=118,
        build=function(frame,width)
            local T=Z.ChatTheme
            local f=T.Frame(frame,'field','border');sample=f;U.optionsLivePreview=f;f.previewOpacity=Z.store.settings.alphaInactive
            f.title=T.Text(f,Z.L('Vorschau','Preview'),11,true,'goldBright');T.Place(f.title,10,6,220,17,f)
            f.rows={}
            for i=1,3 do
                local row={icon=T.Icon(f,{}),name=T.Text(f,'',11,true),body=T.Text(f,'',10,false,'muted')}
                row.name:SetWordWrap(false);row.body:SetWordWrap(false);f.rows[i]=row
            end
            T.Place(f,0,4,width,110,frame)
        end,
        refresh=function(frame,width)
            local T=Z.ChatTheme;local f=sample
            T.Place(f,0,4,width,110,frame);f.previewOpacity=Z.store.settings.alphaInactive
            local c=selectedConversation();local messages=c and c.messages or{}
            for i,row in ipairs(f.rows)do
                local message=messages[math.max(1,#messages-3+i)]
                T.Place(row.icon,9,26+(i-1)*27,21,21,f);T.Place(row.name,38,23+(i-1)*27,math.max(40,width-48),16,f);T.Place(row.body,38,37+(i-1)*27,math.max(40,width-48),15,f)
                row.name:SetText(message and(message.outgoing and Z.L('Du','You')or message.sender)or Z.L('Kontakt','Contact'))
                row.body:SetText(message and Z.Plain(message.text)or Z.L('So sieht dein Gespräch aus.','This is your conversation preview.'))
                T.NameColor(row.name,message and message.senderClass);T.SetIcon(row.icon,{kind='WHISPER',classFile=message and message.senderClass})
            end
        end})
end
local builders={}
function builders.appearance(page,view)
    local form=newForm(page,view)
    form:Card(t('Darstellung','Appearance'))
    slider(form,'alphaActive','Hintergrund aktiv','Active background',0,1,.01,percent)
    slider(form,'alphaInactive','Hintergrund inaktiv','Inactive background',0,1,.01,percent)
    note(form,'Schrift und Symbole bleiben gut lesbar.','Text and icons stay fully legible.')
    previewRow(form)
    form:Card(t('Größe & Lesbarkeit','Size & readability'))
    slider(form,'scale','UI-Skalierung','UI scale',.75,1.5,.05,percent)
    slider(form,'fontSize','Schriftgröße','Font size',12,20,1,whole)
    choice(form,'sidebar','Seitenleiste','Sidebar',{{'auto',Z.L('Automatisch','Automatic')},{'names',Z.L('Namen','Names')},{'icons',Z.L('Symbole','Icons')}})
    note(form,'Bei wenig Platz entfallen zuerst Vorschauen, danach Namen.','At smaller widths, previews hide first, then names.')
    toggle(form,'previews','Nachrichtenvorschau anzeigen','Show last-message previews')
    toggle(form,'sidebarCompact','Kompakte Seitenleiste','Compact sidebar')
    choice(form,'channelLabels','Kanal- und Gruppennamen','Channel and group names',{{'full',Z.L('Vollständig','Full')},{'short',Z.L('Kurz (Gilde: G, Schlachtzug: SZ)','Short (Guild: G, Raid: R)')},{'number',Z.L('Kanalnummer','Channel number')}})
    note(form,'Eigene Anzeigenamen vergibst du im Gesprächsmenü •••. Die Kanalnummer gilt nur für Kanäle, Gruppen zeigen dort ihr Kürzel.','Set your own display names in the ••• conversation menu. The number applies to channels only; groups show their short name.')
    form:Card(t('Fenster','Window'))
    toggle(form,'locked','Position und Größe sperren','Lock position and size')
    form:Buttons({anchor='resetGeometry',{text=t('Position und Größe zurücksetzen','Reset position and size'),onClick=function()U.ResetGeometry();U.RefreshSettings()end}})
    toggle(form,'minimapHidden','Minimap-Icon ausblenden','Hide minimap icon',{onChange=function()U.ApplyMinimapVisibility()end})
    form:Card(t('Ausblenden','Fading'))
    toggle(form,'fadeEnabled','Fenster bei Inaktivität ausblenden','Fade the window when idle')
    slider(form,'fadeAfter','Ausblenden nach','Fade after',5,300,5,seconds)
    slider(form,'fadeAlpha','Sichtbarkeit danach','Visibility afterwards',0,1,.05,percent)
    note(form,'Überfahren, Tippen oder eine neue Nachricht blenden das Fenster wieder ein.','Hovering, typing or a new message bring the window back.')
end
function builders.messages(page,view)
    local form=newForm(page,view)
    form:Card(t('Namen','Names'))
    choice(form,'nameFormat','Namensformat','Name format',{{'full',Z.L('Vorname Nachname','First Last')},{'first',Z.L('Nur Vorname','First name only')},{'last',Z.L('Nur Nachname','Last name only')},{'initialLast',Z.L('V. Nachname','F. Last')},{'firstInitial',Z.L('Vorname N.','First L.')},{'initials',Z.L('Initialen','Initials')}})
    note(form,'Gilt nur für Charaktere mit genau Vor- und Nachname. Andere Namen und Battle.net-Konten bleiben vollständig. Beim Überfahren steht immer der ganze Name da.','Applies only to characters with exactly a first and a last name. Other names and Battle.net accounts stay complete. Hovering always shows the whole name.')
    toggle(form,'classColors','Klassenfarben für Namen','Class colors for names')
    form:Card(t('Symbole','Icons'))
    choice(form,'senderIcon','Symbol neben Nachrichten','Icon next to messages',{{'class',Z.L('Klasse','Class')},{'race',Z.L('Rasse','Race')},{'none',Z.L('Keines','None')}})
    choice(form,'raceIconQuality','Rassensymbole','Race icons',{{'hd',Z.L('Hohe Auflösung','High resolution')},{'sd',Z.L('Standard','Standard')}})
    slider(form,'iconSize','Symbolgröße','Icon size',16,48,2,whole)
    note(form,'Die Rasse ist erst nach einer neuen Nachricht der Person bekannt. Bis dahin steht dort die Klasse, ist auch die unbekannt, das Chat-Symbol.','A race is known only after a new message from that person. Until then the class is shown and, if that is unknown too, the chat icon.')
    form:Card(t('Zeit','Time'))
    choice(form,'timeFormat','Zeitstempel','Timestamps',{{'hm','14:05'},{'hms','14:05:30'},{'date','06.11.2026 14:05'},{'relative',Z.L('Heute 14:05','Today 14:05')},{'off',Z.L('Aus','Off')}})
    choice(form,'timeZone','Uhrzeit','Clock',{{'local',Z.L('Lokale Zeit','Local time')},{'server',Z.L('Serverzeit','Server time')}})
    note(form,'Die Serverzeit gilt mit dem heutigen Abstand auch für ältere Nachrichten; über eine Zeitumstellung hinweg kann sie um eine Stunde abweichen. Überfahren zeigt Datum und Sekunden, Shift-Klick zitiert.','Server time applies today\'s offset to older messages too, so across a clock change it can be off by an hour. Hovering shows date and seconds, shift-click quotes.')
    toggle(form,'dateSeparators','Datumstrenner anzeigen','Show date separators')
    form:Card(t('Layout','Layout'))
    choice(form,'layoutStyle','Nachrichtenlayout','Message layout',{{'bubbles',Z.L('Sprechblasen','Bubbles')},{'compact',Z.L('Kompakt','Compact')},{'classic',Z.L('Klassische Liste','Classic list')}})
    toggle(form,'groupMessages','Aufeinanderfolgende Nachrichten gruppieren','Group consecutive messages')
    choice(form,'fontFace','Schriftart','Font',{{'noto','Noto Sans'},{'friz','Friz Quadrata'},{'arial','Arial Narrow'},{'morpheus','Morpheus'},{'skurri','Skurri'}})
    choice(form,'fontOutline','Textkontur','Text outline',{{'none',Z.L('Keine','None')},{'OUTLINE',Z.L('Dünn','Thin')},{'THICKOUTLINE',Z.L('Dick','Thick')}})
    slider(form,'lineSpacing','Zeilenabstand','Line spacing',0,8,1,whole)
    form:Card(t('Links & Zitate','Links & quotes'))
    toggle(form,'urlLinks','Webadressen erkennen','Detect web addresses')
    note(form,'Ein Klick zeigt die Adresse zum Kopieren. Addons können keinen Browser öffnen.','A click shows the address for copying. Addons cannot open a browser.')
    choice(form,'quoteFormat','Zitat-Format','Quote format',{{'text',Z.L('Nur Text','Text only')},{'sender',Z.L('Mit Absender','With sender')},{'time',Z.L('Mit Absender und Zeit','With sender and time')}})
end
-- One checkbox per joined channel; the list follows the channels the player has joined right now.
local CHANNEL_ROW=34
local function channelList(form)
    local count=0
    form:Custom({anchor='channels',
        visible=function()return Z.store.settings.publicChannels and#Z.adapter:JoinedChannels()>0 end,
        height=function()return math.max(1,count)*CHANNEL_ROW end,
        build=function(frame)frame.checks={}end,
        refresh=function(frame,width)
            local list=Z.adapter:JoinedChannels();count=#list
            for i,channel in ipairs(list)do
                local check=frame.checks[i]
                if not check then
                    check=CreateFrame('CheckButton',nil,frame,'UICheckButtonTemplate');check:SetSize(24,24);Z.Theme.StyleCheckbox(check)
                    check.label=Z.ChatTheme.Text(check,'',12,false,'text');check.label:SetPoint('LEFT',check,'RIGHT',6,0);check.label:SetWordWrap(false)
                    check:SetScript('OnClick',function(self)Z.adapter:SetChannel(self.channel,self:GetChecked()==true)end)
                    frame.checks[i]=check
                end
                check.channel=channel.name;check:ClearAllPoints();check:SetPoint('TOPLEFT',frame,'TOPLEFT',0,-((i-1)*CHANNEL_ROW+5))
                check.label:SetWidth(math.max(40,width-40));check.label:SetText(channel.name)
                check:SetChecked(Z.store.settings.enabledChannels[channel.name:lower()]==true);check:Show()
            end
            for i=count+1,#frame.checks do frame.checks[i]:Hide()end
        end})
end
local function calibrationButtons(form)
    local function notice(de,en)U.Notice(Z.L(de,en))end
    local C=Z.Calibration
    form:Buttons({anchor='calibrationActions',
        {text=t('Probe senden','Send probe'),onClick=function()
            local ok,code=C.SendNextProbe()
            if ok then notice('Probe gesendet.','Probe sent.')
            elseif code=='done'then C.ResetSender();notice('Alle Proben gesendet. Der nächste Klick beginnt von vorn.','All probes sent. The next click starts over.')
            else notice('Probe konnte nicht gesendet werden.','The probe could not be sent.')end
            U.RefreshSettings()
        end},
        {text=t('Zuhören (Ziel)','Listen (target)'),onClick=function()
            if C.ListenTarget(false)then notice('Höre dem Ziel zu (10 Minuten).','Listening to the target (10 minutes).')
            else notice('Wähle zuerst einen Spieler als Ziel.','Target a player first.')end
        end},
        {text=t('Ergebnis exportieren','Export result'),onClick=function()
            local code=C.ExportCode()
            if code then U.ShowCopy(code,Z.L('Kalibrierung für den Sender · Strg+C','Calibration for the sender · Ctrl+C'))
            else notice('Noch kein Ergebnis.','No result yet.')end
        end},
        {text=t('Code importieren','Import code'),onClick=function()
            U.Prompt(Z.L('Kalibrierungscode einfügen · Enter','Paste calibration code · Enter'),'',function(value)
                local ok=C.Import(value)
                notice(ok and'Tabelle importiert.'or'Der Code ist ungültig.',ok and'Table imported.'or'The code is invalid.')
                U.RefreshSettings()
            end)
        end},
        {text=t('Wortprobe senden','Send word probe'),onClick=function()
            local ok,code=C.SendNextWordProbe()
            if ok then notice('Wortprobe gesendet.','Word probe sent.')
            elseif code=='done'then C.ResetSender();notice('Alle Wortproben gesendet. Der nächste Klick beginnt von vorn.','All word probes sent. The next click starts over.')
            else notice('Wortprobe konnte nicht gesendet werden.','The word probe could not be sent.')end
        end},
        {text=t('Wortproben zuhören (Ziel)','Listen for word probes (target)'),onClick=function()
            if C.ListenTarget(true)then notice('Höre dem Ziel zu (10 Minuten).','Listening to the target (10 minutes).')
            else notice('Wähle zuerst einen Spieler als Ziel.','Target a player first.')end
        end},
        {text=t('Wortproben-Ergebnis exportieren','Export word probe result'),onClick=function()
            local text=C.ExportWords()
            if text then U.ShowCopy(text,Z.L('Wortpaare für GarbleData.lua · Strg+C','Word pairs for GarbleData.lua · Ctrl+C'),true)
            else notice('Noch kein Ergebnis.','No result yet.')end
        end}})
end
function builders.behavior(page,view)
    local form=newForm(page,view)
    form:Card(t('Eingabe & Fenster','Input & window'))
    toggle(form,'focusOnOpen','Eingabe beim Öffnen fokussieren','Focus composer when opening')
    note(form,'Enter sendet · Shift+Enter fügt einen Zeilenumbruch ein. Escape löst zuerst den Eingabefokus.','Enter sends · Shift+Enter inserts a new line. Escape first releases input focus.')
    toggle(form,'inputHistory','Gesendete Nachrichten mit Pfeil hoch/runter abrufen','Recall sent messages with arrow up/down')
    choice(form,'inputHistoryScope','Verlauf der Eingabe','Input history',{{'conversation',Z.L('Je Gespräch','Per conversation')},{'global',Z.L('Für alle Gespräche','Across conversations')}})
    toggle(form,'rememberScroll','Leseposition je Gespräch merken','Remember reading position per conversation')
    toggle(form,'searchHistoryEnabled','Suchverlauf speichern','Keep search history')
    note(form,'Tastenkürzel: WoW → Tastenbelegung → Zenial Chat. /zchat öffnet das Fenster.','Shortcut: WoW → Key Bindings → Zenial Chat. /zchat opens the window.')
    form:Card(t('Öffentliche & eigene Kanäle','Public & custom channels'))
    toggle(form,'publicChannels','Öffentliche Kanäle im Messenger anbieten','Offer public channels in Messenger')
    channelList(form)
    note(form,'Noch keine beigetretenen Kanäle verfügbar.','No joined channels available yet.',{anchor='noChannels',
        visible=function()return Z.store.settings.publicChannels and#Z.adapter:JoinedChannels()==0 end})
    -- Absent while a running client has not yet picked up the new TOC files (update without restart).
    if Z.Calibration then
        form:Card(t('Kalibrierung','Calibration'))
        note(form,'Für Spieler der anderen Fraktion: Ein Mitspieler dieser Fraktion mit Zenial Chat steht in Sagen-Reichweite. Jeder Klick sendet genau eine Zeile.','For the other faction: a player of that faction with Zenial Chat stands within say range. Each click sends exactly one line.')
        form:Note({anchor='calibrationStatus',text=function()return(Z.Calibration.StatusText(Z.Calibration.OwnLanguageId()))end})
        calibrationButtons(form)
    end
    form:Card(t('Übersetzungshinweis','Translation hint'))
    toggle(form,'xfChatHint','Übersetzungshinweis im Chat anzeigen','Show translation hint in chat')
    note(form,'Der Hinweis erscheint erst, wenn die Client-Unterstützung bestätigt ist.','The hint appears only once client support has been confirmed.')
end
-- One notification group: how it announces itself, whether it plays a sound, and which one. Wide: one line;
-- narrow: the name above the three controls.
local MATRIX_WIDE=520
local function matrixHead(form)
    local wide=true
    form:Custom({anchor='matrixHead',height=function()return wide and 24 or 1 end,
        visible=function()return true end,
        build=function(frame)
            local T=Z.ChatTheme
            frame.h1=T.Text(frame,Z.L('Hinweis','Notice'),11,true,'muted');frame.h2=T.Text(frame,Z.L('Ton','Sound'),11,true,'muted');frame.h3=T.Text(frame,Z.L('Klang','Tone'),11,true,'muted')
        end,
        refresh=function(frame,width)
            wide=width>=MATRIX_WIDE;local T=Z.ChatTheme
            local x0=math.min(180,width*.34);local noticeW=math.floor((width-x0)*.42);local soundX=x0+noticeW+10;local kitX=soundX+66
            T.Place(frame.h1,x0,5,noticeW,16,frame);T.Place(frame.h2,soundX,5,60,16,frame);T.Place(frame.h3,kitX,5,math.max(40,width-kitX),16,frame)
            for _,h in ipairs({frame.h1,frame.h2,frame.h3})do h:SetShown(wide)end
        end})
    return function()return wide end
end
local function matrixRow(form,group,isWide)
    local key=group[1];local label=Z.L(group[2],group[3]);local canReply=key=='whispers'or key=='bnet'
    local s=Z.store.settings;local wide=true
    local function pref()return s.notifications[key]end
    local notices={{'off',Z.L('Kein Hinweis','No notice')},{'small',Z.L('Kleiner Hinweis','Small notice')}}
    if canReply then notices[3]={'reply',Z.L('Hinweis mit Antwortfeld','Notice with reply field')}end
    form:Custom({anchor='matrix:'..key,height=function()return wide and 40 or 66 end,
        build=function(frame)
            local T=Z.ChatTheme
            frame.label=T.Text(frame,label,12,false,'text');frame.label:SetWordWrap(true)
            -- off: no notice; small: notice only; reply: notice with a reply line (direct messages only, no key elsewhere)
            frame.notice=Form.Dropdown(frame,{width=150,options=notices,tr=tr,
                get=function()
                    local p=pref();if p.toast~=true then return'off'end
                    return canReply and p.reply==true and'reply'or'small'
                end,
                set=function(value)
                    local p=pref()
                    if value=='off'then p.toast=false else p.toast=true;if canReply then p.reply=value=='reply'end end
                end})
            frame.check=CreateFrame('CheckButton',nil,frame,'UICheckButtonTemplate');frame.check:SetSize(24,24);Z.Theme.StyleCheckbox(frame.check)
            frame.check:SetScript('OnClick',function(self)pref().sound=self:GetChecked()==true end)
            frame.checkLabel=T.Text(frame,Z.L('Ton','Sound'),12,false,'text')
            frame.kit=Form.Dropdown(frame,{width=150,options=soundChoices,tr=tr,translate=false,placeholder=Z.L('Auswählen …','Choose …'),
                get=function()return Z.Notifications.KitName(key,pref())end,
                set=function(value)pref().soundKit=value;Z.Notifications.PlayKit(value)end})
        end,
        refresh=function(frame,width)
            local T=Z.ChatTheme;wide=isWide()
            frame.label:SetText(label)
            frame.check:SetChecked(pref().sound==true);frame.notice:Refresh();frame.kit:Refresh()
            if wide then
                local x0=math.min(180,width*.34);local noticeW=math.floor((width-x0)*.42);local soundX=x0+noticeW+10;local kitX=soundX+66
                T.Place(frame.label,0,10,x0-10,24,frame)
                frame.notice:ClearAllPoints();frame.notice:SetPoint('TOPLEFT',frame,'TOPLEFT',x0,-6);frame.notice:SetSize(noticeW,26)
                frame.check:ClearAllPoints();frame.check:SetPoint('TOPLEFT',frame,'TOPLEFT',soundX,-7);frame.checkLabel:Hide()
                frame.kit:ClearAllPoints();frame.kit:SetPoint('TOPLEFT',frame,'TOPLEFT',kitX,-6);frame.kit:SetSize(math.max(60,width-kitX),26)
            else
                local noticeW=math.floor((width-72)*.5);local kitW=width-72-noticeW
                T.Place(frame.label,0,4,width,18,frame)
                frame.notice:ClearAllPoints();frame.notice:SetPoint('TOPLEFT',frame,'TOPLEFT',0,-30);frame.notice:SetSize(noticeW,26)
                frame.check:ClearAllPoints();frame.check:SetPoint('TOPLEFT',frame,'TOPLEFT',noticeW+8,-31);T.Place(frame.checkLabel,noticeW+36,36,36,18,frame);frame.checkLabel:Show()
                frame.kit:ClearAllPoints();frame.kit:SetPoint('TOPLEFT',frame,'TOPLEFT',noticeW+72,-30);frame.kit:SetSize(math.max(60,kitW),26)
            end
        end})
end
function builders.notifications(page,view)
    local form=newForm(page,view)
    form:Card(t('Neue Nachrichten','New messages'))
    note(form,'Stummgeschaltete Gespräche behalten ihren Ungelesen-Zähler, spielen aber keinen Ton und zeigen keinen Hinweis.','Muted conversations keep unread counts, but do not play a sound or show a notification.')
    note(form,'Der Client spielt bei Flüstern und Schlachtzugswarnungen selbst einen Ton. Ein Ton hier kommt zusätzlich hinzu; pro Sekunde spielt Zenial Chat höchstens einen.','The client plays its own sound for whispers and raid warnings. A sound here comes on top; Zenial Chat plays at most one per second.')
    local isWide=matrixHead(form)
    for _,group in ipairs({{'whispers','Flüstern','Whispers'},{'bnet','Battle.net','Battle.net'},{'guild','Gilde & Offizier','Guild & officer'},{'groups','Gruppen','Groups'},{'raidWarning','Schlachtzugswarnungen','Raid warnings'},{'channels','Öffentliche Kanäle','Public channels'},{'opposite','Gegnerische Fraktion','Opposite faction'}})do
        matrixRow(form,group,isWide)
    end
    form:Card(t('Direktnachrichten','Direct messages'))
    toggle(form,'autoOpen','Bei Direktnachrichten automatisch öffnen (nicht im Kampf)','Open automatically for direct messages (not in combat)')
    form:Card(t('Hinweis','Notice'))
    slider(form,'toastDuration','Hinweis-Dauer','Notice duration',2,15,1,seconds)
    toggle(form,'suppressInCombat','Im Kampf keine Töne und Hinweise','No sounds or notices in combat')
    form:Buttons({anchor='noticeActions',
        {text=t('Hinweis-Vorschau anzeigen','Show notice preview'),onClick=function()Z.Notifications.Preview()end},
        {text=t('Benachrichtigungston testen','Test notification sound'),onClick=function()Z.Notifications.PlayTell()end},
        {text=t('Hinweisposition zurücksetzen','Reset notification position'),onClick=function()Z.Notifications.ResetPosition()end}})
    note(form,'Den Hinweis verschiebst du mit gedrückter linker Maustaste; ein einfacher Klick öffnet das Gespräch.','Drag the notification with the left mouse button to move it; a plain click opens the conversation.')
end
function builders.history(page,view)
    local form=newForm(page,view);local s=Z.store.settings
    local function hasConversation()return selectedConversation()~=nil end
    form:Card(t('Dein lokales Archiv','Your local archive'))
    form:Note({anchor='archiveStats',text=function()
        local conversations,messages,bytes=Z.store:Stats()
        return string.format(Z.L('%d Gespräche · %d Nachrichten · %s Text. Die Datei auf der Festplatte ist wegen der Zusatzdaten größer.','%d conversations · %d messages · %s of text. The file on disk is larger because of the extra data.'),conversations,messages,sizeLabel(bytes))
    end})
    form:Note({anchor='archiveKept',text=function()
        if s.retentionCount>0 or s.retentionDays>0 then
            return Z.L('Ältere Nachrichten werden nach den Grenzen unten gelöscht. Das Archiv wird auf diesem Computer über deine Charaktere geteilt.','Older messages are deleted according to the limits below. The archive is shared across your characters on this computer.')
        end
        return Z.L('Nachrichten bleiben dauerhaft erhalten, bis du sie selbst löschst. Das Archiv wird auf diesem Computer über deine Charaktere geteilt.','Messages remain until you delete them. The archive is shared across your characters on this computer.')
    end})
    form:Select({key='retentionCount',label=t('Höchstens pro Gespräch','Maximum per conversation'),
        options={{0,Z.L('Unbegrenzt','Unlimited')},{500,'500'},{1000,'1.000'},{5000,'5.000'},{10000,'10.000'},{50000,'50.000'}},
        get=function()return s.retentionCount end,set=retentionSetter(view,'retentionCount',Z.L('Höchstens pro Gespräch','Maximum per conversation'))})
    form:Select({key='retentionDays',label=t('Höchstes Alter','Maximum age'),
        options={{0,Z.L('Unbegrenzt','Unlimited')},{30,Z.L('30 Tage','30 days')},{90,Z.L('90 Tage','90 days')},{180,Z.L('180 Tage','180 days')},{365,Z.L('1 Jahr','1 year')}},
        get=function()return s.retentionDays end,set=retentionSetter(view,'retentionDays',Z.L('Höchstes Alter','Maximum age'))})
    form:Toggle({anchor='keepSelected',visible=hasConversation,
        label=function()
            local c=selectedConversation()
            return string.format(Z.L('„%s“ von den Grenzen ausnehmen','Exempt "%s" from the limits'),c and Z.Format.ConversationLabel(c)or'')
        end,
        get=function()local c=selectedConversation();return c~=nil and c.keep==true end,
        set=function(value)local c=selectedConversation();if c then Z.store:SetKeep(c.key,value)end end})
    form:Buttons({anchor='exportSelected',
        {text=t('Ausgewähltes Gespräch exportieren …','Export selected conversation …'),visible=hasConversation,onClick=function()
            local c=selectedConversation();if c then U.ExportConversation(c)end
        end}})
    note(form,'Gespräch schließen blendet es aus und erhält den Verlauf. Verlauf löschen leert nur das lokale Archiv.','Closing a conversation preserves its history. Clearing history only empties the local archive.')
    form:Buttons({anchor='clearActions',
        {text=t('Verlauf des ausgewählten Gesprächs löschen …','Clear selected conversation history …'),variant='danger',onClick=function()
            local c=selectedConversation()
            if not c then U.Notice(Z.L('Wähle zuerst ein Gespräch.','Select a conversation first.'));return end
            view:Confirm({title=t('Verlauf des ausgewählten Gesprächs löschen','Clear selected conversation history'),accept=t('Löschen','Delete'),variant='danger',
                text=Z.L('Lokalen Verlauf von ','Clear local history for ')..c.name..'?',
                onAccept=function()Z.store:Clear(c.key);U.RefreshSettings()end})
        end},
        {text=t('Alle lokalen Verläufe löschen …','Clear all local history …'),variant='danger',onClick=function()
            view:Confirm({title=t('Alle lokalen Verläufe löschen','Clear all local history'),accept=t('Löschen','Delete'),variant='danger',
                text=Z.L('Alle lokalen Verläufe löschen?','Clear all local history?'),
                onAccept=function()Z.store:ClearAll();U.RefreshSettings()end})
        end}})
end
function builders.blizzard(page,view)
    local form=newForm(page,view)
    Z.NativeChatOptions.Build(form,{note=note,toggle=toggle,select=select,t=t})
end
local function spec()
    local list={}
    for i,page in ipairs(pages)do
        list[i]={key=page.key,title=page.title,icon=Z.ChatTheme.pageIcons[page.key],build=builders[page.key]}
    end
    return{label='Chat',version=Z.VERSION,tr=tr,pages=list,embeddedNav='side',embeddedMinWidth=520,
        onPage=function(key)
            U.settingsPage=key
            if U.settingsView then
                U.settingsView:SetNote(key=='blizzard'and Z.L('Änderungen erst nach Vorschau bestätigen.','Confirm changes after preview.')or Z.L('Änderungen werden sofort gespeichert.','Changes are saved immediately.'))
            end
        end}
end
-- Title strip and the room below it for the view; called with every layout of the window.
function U.LayoutOptions()
    if not U.settingsBody then return end
    local T=Z.ChatTheme;local panel=U.settingsPanel;local w=panel:GetWidth();local h=panel:GetHeight()
    T.Place(U.optionsTitle,18,10,math.max(70,w-210),28,panel)
    T.Place(U.settingsBody,0,44,w,math.max(1,h-44),panel)
    if U.optionsLivePreview then U.optionsLivePreview.previewOpacity=Z.store.settings.alphaInactive end
    if U.settingsPanel:IsShown()then T.Opacity(U.currentAlpha or Z.store.settings.alphaActive)end
end
function U.OpenSettings(page)
    U.Open();U.settingsPage=page or'appearance'
    U.input:ClearFocus();U.search:ClearFocus();if U.menu then U.menu:Hide()end
    U.listPanel:Hide();U.chatPanel:Hide();U.settingsPanel:Show();U.back:Show();U.Layout()
    if not U.settingsView then U.settingsView=Window.New(spec(),U.settingsBody)end
    local view=U.settingsView
    -- The Blizzard page lists the chat tabs of this moment; it is built again every time.
    if U.settingsPage=='blizzard'then view:Rebuild('blizzard')end
    view:SelectPage(U.settingsPage);U.settingsPage=view:CurrentPage()or U.settingsPage
    view:Refresh()
end
