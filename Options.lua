local _,Z=...
local U=Z.UI
local pages={{'appearance','Darstellung','Appearance'},{'behavior','Verhalten','Behavior'},{'notifications','Benachrichtigungen','Notifications'},{'history','Verlauf & Daten','History & data'}}
local function add(kind,label,options)
    local row=options or{};row.kind=kind;row.label=label;U.optionSpecs[#U.optionSpecs+1]=row;return row
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
        add('section',Z.L('Fenster','Window'))
        add('check',Z.L('Position und Größe sperren','Lock position and size'),{key='locked'})
        add('action',Z.L('Position und Größe zurücksetzen','Reset position and size'),{run=U.ResetGeometry})
    elseif U.settingsPage=='behavior'then
        add('section',Z.L('Eingabe & Fenster','Input & window'))
        add('check',Z.L('Eingabe beim Öffnen fokussieren','Focus composer when opening'),{key='focusOnOpen'})
        add('check',Z.L('Bei Direktnachrichten automatisch öffnen','Open automatically for direct messages'),{key='autoOpen'})
        add('note',Z.L('Enter sendet · Shift+Enter fügt einen Zeilenumbruch ein. Escape löst zuerst den Eingabefokus.','Enter sends · Shift+Enter inserts a new line. Escape first releases input focus.'))
        add('note',Z.L('Tastenkürzel: WoW → Tastenbelegung → Zenial Chat. /zchat öffnet das Fenster.','Shortcut: WoW → Key Bindings → Zenial Chat. /zchat opens the window.'))
        add('section',Z.L('Zenial Community','Zenial Community'))
        local community=Z.adapter.community
        add('choice',Z.L('Community','Community'),{get=function()return s.clubId end,choices=function()
            local result={};for _,club in ipairs(community:Clubs())do result[#result+1]={tostring(club.id),club.name}end;return result
        end,set=function(id)community:SelectClub(id);U.RebuildOptions()end})
        for _,slot in ipairs({{'general','Allgemein','General'},{'horde','Horde','Horde'},{'alliance','Allianz','Alliance'}})do
            local name=slot[1]
            add('choice',Z.L(slot[2],slot[3]),{get=function()return s.streams[name]end,choices=function()
                local result={};for _,stream in ipairs(community:Streams(s.clubId))do result[#result+1]={tostring(stream.id),stream.name}end;return result
            end,set=function(id)community:SetStream(name,id);U.RebuildOptions()end})
        end
        add('note',Z.L('Es werden bestehende Community-Kanäle verwendet. Bei gleichnamigen Kanälen wählst du das Ziel hier ausdrücklich aus.','Existing community channels are used. Select the exact destination here when names are ambiguous.'))
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
        for _,group in ipairs({{'whispers','Direktnachrichten','Direct messages'},{'guild','Gilde & Offizier','Guild & officer'},{'groups','Gruppen','Groups'},{'community','Community','Community'},{'channels','Öffentliche Kanäle','Public channels'}})do
            local key=group[1];local label=Z.L(group[2],group[3])
            add('section',label)
            for _,setting in ipairs({{'sound','Ton abspielen','Play sound'},{'toast','Hinweis anzeigen','Show notification'}})do
                local field=setting[1]
                add('check',Z.L(setting[2],setting[3]),{get=function()return s.notifications[key][field]end,set=function(value)s.notifications[key][field]=value end})
            end
        end
        add('action',Z.L('Benachrichtigungston testen','Test notification sound'),{run=function()Z.Notifications.PlayTell()end})
        add('action',Z.L('Hinweisposition zurücksetzen','Reset notification position'),{run=function()Z.Notifications.ResetPosition()end})
        add('note',Z.L('Den Hinweis verschiebst du mit gedrückter linker Maustaste; ein einfacher Klick öffnet das Gespräch.','Drag the notification with the left mouse button to move it; a plain click opens the conversation.'))
    else
        add('section',Z.L('Dein lokales Archiv','Your local archive'))
        add('note',Z.L('Nachrichten bleiben dauerhaft erhalten, bis du sie selbst löschst. Das Archiv wird auf diesem Computer über deine Charaktere geteilt.','Messages remain until you delete them. The archive is shared across your characters on this computer.'))
        add('note',Z.L('Gespräch schließen blendet es aus und erhält den Verlauf. Verlauf löschen leert nur das lokale Archiv. Alte Community-Nachrichten können später wieder geladen werden.','Closing a conversation preserves its history. Clearing history only empties the local archive. Older community messages can be loaded again later.'))
        add('action',Z.L('Verlauf des ausgewählten Gesprächs löschen …','Clear selected conversation history …'),{run=function()
            local c=Z.store:Get(Z.store.db.ui.selected)
            if not c then U.Notice(Z.L('Wähle zuerst ein Gespräch.','Select a conversation first.'));return end
            U.Confirm(Z.L('Lokalen Verlauf von ','Clear local history for ')..c.name..'?',function()Z.store:Clear(c.key)end)
        end})
        add('action',Z.L('Alle lokalen Verläufe löschen …','Clear all local history …'),{run=function()
            U.Confirm(Z.L('Alle lokalen Verläufe löschen? Community-Nachrichten können später erneut geladen werden.','Clear all local history? Community messages can be loaded again later.'),function()Z.store:ClearAll()end)
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
