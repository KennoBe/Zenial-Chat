local _,Z=...
local U={rows={},headers={},listScroll=0,dirty=false,settingsPage='appearance'};Z.UI=U
local function selected()return Z.store and Z.store:Get(Z.store.db.ui.selected)end
local function textTime(at)return Z.Format.Stamp('%H:%M',at or 0)end
local titles={guild={'Gilde','Guild'},groups={'Gruppen','Groups'},people={'Direktnachrichten','Direct messages'},channels={'Kanäle','Channels'}}
local function caption(group)local a=titles[group]or{'Gespräche','Conversations'};return Z.L(a[1],a[2])end
function U.Notice(message)
    U.Build();U.notice:SetText(message or'');U.notice:SetShown(message~=nil and message~='')
end
function U.RequestRefresh(reason,key)
    U.dirty=true
    if reason=='message'or reason=='clear'or reason=='clear-all'then
        if not key or Z.store and key==Z.store.db.ui.selected then U.indexDirty=true end
        U.lastActivity=Z.Clock()
        if U.SearchChanged then U.SearchChanged(reason)end
    end
end
function U.SetAtEnd(value)U.atEnd=value==true end
function U.ScrollTo(value)
    if not U.frame then return end
    U.scroll=math.max(0,math.min(U.maximum or 0,tonumber(value)or 0));U.atEnd=(U.maximum or 0)-U.scroll<=2
    Z.Transcript.Render(U)
end
function U.SaveGeometry()
    if not U.frame then return end
    local d=Z.store.db.ui;d.width,d.height=U.frame:GetWidth(),U.frame:GetHeight()
    local x,y=U.frame:GetCenter();local px,py=UIParent:GetCenter();local scale=U.frame:GetScale()
    if x and y and px and py then d.x=x-px/scale;d.y=y-py/scale end
end
function U.SetSetting(key,value)
    Z.store.settings[key]=value;Z.Format.ResetDayCache()
    if U.frame then U.indexDirty=true;U.indexFull=true;U.Layout();U.Refresh();U.UpdateAlpha()end
end
function U.UpdateAlpha()
    if not U.frame then return end
    local active=U.frame:IsMouseOver()or U.input:HasFocus()or U.search:HasFocus()
    local value=active and Z.store.settings.alphaActive or Z.store.settings.alphaInactive
    if U.currentAlpha~=value then U.currentAlpha=value;Z.Theme.Opacity(value)end
end
function U.ResetGeometry()
    local d=Z.store.db.ui;d.width,d.height,d.x,d.y=1060,680,0,0;Z.store.settings.locked=false
    U.frame:ClearAllPoints();U.frame:SetPoint('CENTER',UIParent,'CENTER',0,0);U.frame:SetSize(1060,680);U.Layout()
end
function U.RestoreRecovery(attempt)
    if not attempt then return end
    local c=selected();if not c then return end
    if U.input:GetText()~=''then
        U.Notice(Z.L('Dein neuer Entwurf bleibt erhalten. Kopiere den fehlgeschlagenen Text aus dem Auswahlfeld.','Your new draft is kept. Copy the failed message from the recovery field.'))
        U.ShowCopy(attempt.text);return
    end
    U.input:SetText(attempt.text);Z.adapter:DismissRecovery(attempt.id);U.recovery:Hide();U.input:SetFocus()
end
-- Up and Down walk through what was sent. The draft that was being typed is put aside while
-- browsing and comes back after the newest entry. In a text with several lines the arrows keep
-- moving the cursor until it reaches the first or the last line.
function U.HistoryArrow(key)
    local c=selected();if not c or not Z.store.settings.inputHistory then return end
    if key~='UP'and key~='DOWN'then return end
    local text=U.input:GetText();local cursor=U.input:GetCursorPosition()
    if key=='UP'and text:sub(1,cursor):find('\n',1,true)then return end
    if key=='DOWN'and(not U.historyPos or text:sub(cursor+1):find('\n',1,true))then return end
    local list=Z.store:SentList(c.key);if#list==0 then return end
    local position=U.historyPos
    if key=='UP'then
        if not position then U.historyDraft=text;position=#list else position=math.max(1,position-1)end
    else position=position+1 end
    local value
    if position>#list then position=nil;value=U.historyDraft or''else value=list[position]end
    U.historyPos=position;U.historyValue=value
    U.loadingDraft=true;U.input:SetText(value);U.loadingDraft=false
    U.input:SetCursorPosition(#value)
    if not position then U.historyDraft=nil end
end
local function endHistory()U.historyPos=nil;U.historyDraft=nil end
function U.Submit()
    local c=selected();if not c then return end
    local text=U.input:GetText();local ok,err=Z.adapter:Send(c,text)
    if ok then Z.store:AddSent(c.key,text);endHistory();U.input:SetText('');Z.store:SetDraft(c.key,'');U.Notice('');U.RequestRefresh('message',c.key)
    else U.Notice(err or Z.L('Nachricht konnte nicht gesendet werden.','Message could not be sent.'))end
end
-- Installed once; chains through whatever function was there at install time and
-- only claims a link while this window is shown and its input has focus.
local function installLinks()
    U.linkInstalled=U.linkInstalled or{}
    local function install(owner,key)
        if U.linkInstalled[key]or type(owner)~='table'or type(owner[key])~='function'then return end
        local original=owner[key]
        owner[key]=function(link,...)
            if not U.linkInserting and U.frame and U.input and U.frame:IsShown()and U.input:HasFocus()and Z.Safe(link)and type(link)=='string'then
                U.linkInserting=true;local ok,err=pcall(U.input.Insert,U.input,link);U.linkInserting=false
                if not ok then error(err,0)end
                return true
            end
            return original(link,...)
        end
        U.linkInstalled[key]=true
    end
    install(ChatFrameUtil,'InsertLink');install(_G,'ChatEdit_InsertLink')
end
-- terms (optional) highlights what was searched for in the opened conversation.
function U.Select(key,messageId,terms)
    U.Build();local c=Z.store:Get(key);if not c then return end
    local old=selected()
    if old and U.loadedKey==old.key then Z.store:SetDraft(old.key,U.historyPos and U.historyDraft or U.input:GetText())end
    endHistory()
    -- Leaving a conversation while reading further up keeps the place for the way back.
    U.scrollMemory=U.scrollMemory or{}
    if old and old.key~=key then U.scrollMemory[old.key]=not U.atEnd and U.anchor or nil end
    if U.searchPanel then U.searchPanel:Hide();U.panelSearch=nil end
    U.highlightId=messageId;U.highlightKey=key;U.highlightTerms=terms
    U.input:ClearFocus();Z.store:Select(key);Z.store:SetClosed(key,false)
    U.loadingDraft=true;U.input:SetText(c.draft or'');U.loadingDraft=false;U.loadedKey=key
    U.settingsPanel:Hide();U.chatPanel:Show();U.back:Hide();U.settingsNav:Hide();U.listPanel:Show()
    local remembered=not messageId and old and old.key~=key and Z.store.settings.rememberScroll and(c.unread or 0)==0 and U.scrollMemory[key]or nil
    U.indexDirty=true;U.indexFull=true;U.indexSignature=nil;U.anchor=remembered;U.scroll=0;U.atEnd=not messageId and not remembered
    U.windowKey=nil;Z.Transcript.PrepareWindow(U,c,messageId or remembered and remembered.id or nil)
    U.frame:Show();U.Layout();U.Refresh()
    if messageId then Z.Transcript.Reveal(U,c,messageId)end
end
function U.Open()
    if not Z.ready then Z.Initialize()end
    U.Build();U.frame:Show();U.Layout();U.Refresh()
    if Z.store.settings.focusOnOpen and selected()and not U.settingsPanel:IsShown()then U.input:SetFocus()end
end
function U.Toggle()
    if U.frame and U.frame:IsShown()then U.frame:Hide()else U.Open()end
end
function U.ShowMenu(anchor,items,atCursor)
    if U.menu then U.menu:Hide()end
    local T=Z.Theme;local menu=U.menu or T.Frame(U.frame,'shell','gold');U.menu=menu
    menu:SetFrameStrata('TOOLTIP');menu:SetSize(250,#items*30+12);menu:ClearAllPoints()
    if atCursor then
        -- The cursor starts inside the corner, so leaving the menu is what closes it.
        local x,y=GetCursorPosition();local scale=menu:GetEffectiveScale()
        menu:SetClampedToScreen(true);menu:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',x/scale-6,y/scale+6)
        local idle=0
        menu:SetScript('OnUpdate',function(self,elapsed)
            if self:IsMouseOver()then idle=0 else idle=idle+elapsed;if idle>=.4 then self:Hide()end end
        end)
    else
        menu:SetPoint('TOPRIGHT',anchor,'BOTTOMRIGHT',0,-2);menu:SetScript('OnUpdate',nil)
    end
    menu.buttons=menu.buttons or{}
    for i,item in ipairs(items)do
        local b=menu.buttons[i]or T.Button(menu,'',nil);menu.buttons[i]=b
        b.label:SetText(item.text);b:SetScript('OnClick',function()menu:Hide();item.run()end);T.Place(b,6,6+(i-1)*30,238,28,menu);b:Show()
    end
    for i=#items+1,#menu.buttons do menu.buttons[i]:Hide()end;menu:Show()
end
function U.Confirm(text,action)
    local T=Z.Theme
    U.input:ClearFocus();U.search:ClearFocus()
    if not U.confirm then
        local f=T.Frame(U.frame,'shell','gold');f:SetFrameStrata('DIALOG');f:SetSize(360,150);f:SetPoint('CENTER');f.label=T.Text(f,'',14,false)
        T.Place(f.label,18,18,324,65,f);f.label:SetWordWrap(true)
        f.yes=T.Button(f,Z.L('Löschen','Delete'),function()local callback=f.action;f:Hide();callback()end)
        f.no=T.Button(f,Z.L('Abbrechen','Cancel'),function()f:Hide()end)
        T.Place(f.yes,18,108,150,28,f);T.Place(f.no,192,108,150,28,f);U.confirm=f
    end
    U.confirm.label:SetText(text);U.confirm.action=action;U.confirm:Show()
end
-- large is for long texts such as an excerpt or an export.
function U.ShowCopy(text,title,large)
    if not U.copy then
        local T=Z.Theme;local f=T.Frame(U.frame,'shell','gold');f:SetPoint('CENTER');f:SetFrameStrata('DIALOG')
        f.edit,f.background=T.Input(f);f.edit:SetMultiLine(true)
        -- Long text scrolls inside the frame instead of running out of it.
        f.scroll=CreateFrame('ScrollFrame',nil,f.background);f.scroll:SetClipsChildren(true);f.scroll:SetPoint('TOPLEFT',f.background,'TOPLEFT',2,-2);f.scroll:SetPoint('BOTTOMRIGHT',f.background,'BOTTOMRIGHT',-2,2)
        f.edit:ClearAllPoints();f.scroll:SetScrollChild(f.edit)
        f.scroll:EnableMouseWheel(true);f.scroll:SetScript('OnMouseWheel',function(self,delta)
            self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*40)))
        end)
        f.edit:SetScript('OnCursorChanged',function(_,_,y,_,height)
            local top=f.scroll:GetVerticalScroll();local view=f.scroll:GetHeight();y=-y
            if y<top then f.scroll:SetVerticalScroll(y)elseif y+height>top+view then f.scroll:SetVerticalScroll(y+height-view)end
        end)
        f.title=T.Text(f,'',13,true);f.title:SetPoint('TOPLEFT',12,-12)
        f.close=Z.CloseButton(f,function()f.edit:ClearFocus();f:Hide()end,Z.L('Schließen','Close'))
        f.edit:SetScript('OnEscapePressed',function(self)self:ClearFocus();f:Hide()end);U.copy=f
    end
    local width,height=large and 620 or 420,large and 420 or 180
    do
        local f=U.copy;local T=Z.Theme
        f:SetSize(width,height);T.Place(f.background,12,40,width-24,height-60,f)
        f.title:SetWidth(width-70);T.Place(f.close,width-38,7,28,26,f)
        f.edit:SetWidth(width-32);f.edit:SetHeight(height-64)
    end
    -- The same native dialog serves selection/search/new-target workflows.
    -- Remove old callbacks before assigning content to a different workflow.
    U.copy.edit:SetScript('OnTextChanged',nil)
    U.copy.edit:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
    U.copy.edit:SetMultiLine(true)
    U.copy.title:SetText(title or Z.L('Text kopieren · Strg+C','Copy text · Ctrl+C'))
    U.copy.scroll:SetVerticalScroll(0)
    U.copy:Show();U.copy.edit:SetText(text or'');U.copy.edit:SetFocus();U.copy.edit:HighlightText()
end
-- A single-line prompt in the copy window; Enter hands the text over.
function U.Prompt(title,text,fn)
    U.ShowCopy(text or'',title);U.copy.edit:SetMultiLine(false)
    U.copy.edit:SetScript('OnEnterPressed',function(self)
        local value=self:GetText();self:ClearFocus();U.copy:Hide();fn(value)
    end)
end
-- Puts a quote at the cursor. Nothing is sent until the user does it.
function U.QuoteMessage(msg,mode)
    local c=selected();if not c or not msg or msg.deleted then return end
    U.input:SetFocus();U.input:Insert(Z.Format.Quote(c,msg,mode))
end
function U.OpenWhisper(name)
    local native=Z.adapter:FullName(name,Z.adapter.me.realm)or name
    local c=Z.store:Ensure({kind='WHISPER',target=native,name=name,scope=Z.adapter.me.realm})
    U.Select(c.key);U.input:SetFocus()
end
function U.ExportConversation(c)
    local text,shown,total=Z.Format.Export(c)
    local title=Z.L('Verlauf exportieren · Strg+C','Export history · Ctrl+C')
    if shown<total then title=string.format(Z.L('Die neuesten %d von %d Nachrichten · Strg+C','Newest %d of %d messages · Ctrl+C'),shown,total)end
    U.ShowCopy(text,title,true)
end
function U.ConversationMenu(anchor,c)
    if not c then return end
    U.ShowMenu(anchor,{
        {text=Z.L('Neue Nachricht …','New message …'),run=U.StartConversation},
        {text=c.pinned and Z.L('Lösen','Unpin')or Z.L('Anpinnen','Pin'),run=function()Z.store:SetPinned(c.key,not c.pinned)end},
        {text=c.muted and Z.L('Stummschaltung aufheben','Unmute')or Z.L('Stummschalten','Mute'),run=function()Z.store:SetMuted(c.key,not c.muted)end},
        {text=Z.L('Gespräch schließen','Close conversation'),run=function()Z.store:SetClosed(c.key,true);if selected()==c then Z.store:Select(nil);U.Refresh()end end},
        {text=Z.L('Verlauf löschen …','Clear history …'),run=function()U.Confirm(Z.L('Diesen lokalen Verlauf löschen?','Clear this local history?'),function()Z.store:Clear(c.key)end)end},
        {text=Z.L('In diesem Gespräch suchen …','Search this conversation …'),run=function()U.OpenSearch(c.key)end},
        {text=Z.L('Anzeigenamen ändern …','Change display name …'),run=function()
            U.Prompt(Z.L('Anzeigename · Leer lässt den Originalnamen','Display name · Empty keeps the original name'),c.alias or'',function(value)Z.store:SetAlias(c.key,value)end)
        end},
        {text=c.notify=='always'and Z.L('Hinweise: nach Chatart','Alerts: by chat type')or Z.L('Hinweise: immer','Alerts: always'),run=function()Z.store:SetNotify(c.key,c.notify~='always'and'always'or nil)end},
        {text=Z.L('Verlauf exportieren …','Export history …'),run=function()U.ExportConversation(c)end},
    })
end
-- Addons have no clipboard access: copying means the selected text in the copy window plus Ctrl+C.
function U.MessageMenu(anchor,msg)
    if not msg or msg.deleted then return end
    local text=Z.Plain(msg.text);if text==''then return end
    local c=selected()
    local items={{text=Z.L('Nachricht kopieren','Copy message'),run=function()U.ShowCopy(text)end}}
    local name=not msg.senderPending and Z.Plain(msg.outgoing and msg.ownCharacter or msg.sender)or''
    if name~=''then items[2]={text=Z.L('Name kopieren','Copy name'),run=function()U.ShowCopy(name)end}end
    if not c then U.ShowMenu(anchor,items,true);return end
    local function add(label,run)items[#items+1]={text=label,run=run}end
    add(Z.L('Mit Absender kopieren','Copy with sender'),function()U.ShowCopy(Z.Format.MessageLine(c,msg,'sender'))end)
    add(Z.L('Mit Zeit und Absender kopieren','Copy with time and sender'),function()U.ShowCopy(Z.Format.MessageLine(c,msg,'time'))end)
    add(Z.L('Zitieren','Quote'),function()U.QuoteMessage(msg)end)
    -- Character actions only for a real character name; a Battle.net account has its own native menu.
    if name~=''and not msg.outgoing and c.kind~='BN_WHISPER'then
        if c.kind~='WHISPER'then add(Z.L('Anflüstern','Whisper'),function()U.OpenWhisper(name)end)end
        local invite=C_PartyInfo and C_PartyInfo.InviteUnit
        if type(invite)=='function'then add(Z.L('In Gruppe einladen','Invite to group'),function()Z.Call(invite,name)end)end
    end
    add(Z.L('In diesem Gespräch suchen …','Search this conversation …'),function()U.OpenSearch(c.key)end)
    -- A stretch of messages: first the start, then the end, as a right-click on each.
    local start=U.rangeStart and Z.store:IndexOf(c.key,U.rangeStart)
    if start then
        local here=Z.store:IndexOf(c.key,msg.id) or start
        add(Z.L('Ausschnitt bis hier kopieren','Copy excerpt up to here'),function()
            local first,last=math.min(start,here),math.max(start,here)
            U.rangeStart=nil;U.Refresh();U.ShowCopy(Z.Format.Lines(c,first,last,'time'),nil,true)
        end)
        add(Z.L('Ausschnitt abbrechen','Cancel excerpt'),function()U.rangeStart=nil;U.Refresh()end)
    else
        add(Z.L('Ausschnitt ab hier …','Excerpt from here …'),function()
            U.rangeStart=msg.id;U.Refresh()
            U.Notice(Z.L('Rechtsklick auf die letzte Nachricht: Ausschnitt bis hier kopieren.','Right-click the last message: Copy excerpt up to here.'))
        end)
    end
    U.ShowMenu(anchor,items,true)
end
local function conversationRow(index)
    if U.rows[index]then return U.rows[index]end
    local T=Z.Theme;local row=CreateFrame('Button',nil,U.listCanvas,'BackdropTemplate');T.Panel(row,'sidebar','line')
    row.icon=T.Icon(row,{});row.name=T.Text(row,'',14,true);row.preview=T.Text(row,'',12,false,'muted')
    row.name:SetWordWrap(false);row.preview:SetWordWrap(false)
    row.divider=T.Line(row,4,48,100)
    row.time=T.Text(row,'',10,false,'muted');row.time:SetJustifyH('RIGHT')
    row.badge=T.Frame(row,'red','red');row.count=T.Text(row.badge,'',11,true);row.count:SetPoint('CENTER');row.count:SetJustifyH('CENTER')
    row:RegisterForClicks('LeftButtonUp','RightButtonUp')
    row:SetScript('OnClick',function(self,button)
        if button=='RightButton'then
            local c=self.conversation
            local text,link
            if c.kind=='WHISPER'or c.kind=='BN_WHISPER'then text,link=Z.PlayerLink(c,nil,c.name)end
            if link and type(SetItemRef)=='function'then
                if U.menu then U.menu:Hide()end
                Z.Call(SetItemRef,link,text,button,DEFAULT_CHAT_FRAME)
            else U.ConversationMenu(self,c)end
        else
            -- From the running search: the newest hit, with the search terms marked.
            local run=U.query~=''and U.sidebarSearch or nil
            local hit=run and run.hits[self.conversation.key]
            local match=not hit and not(run and run.done)and U.query~=''and Z.store:Search(self.conversation,U.query)
            U.Select(self.conversation.key,hit and hit.newest or match and match.id or nil,run and run.terms or nil)
        end
    end)
    row:SetScript('OnEnter',function(self)
        local c=self.conversation
        -- The full identity stays reachable whatever the list shows.
        if U.metrics.iconOnly then T.Tooltip(self,c.name,(c.unread or 0)..' '..Z.L('ungelesen','unread'))
        elseif Z.Format.ConversationLabel(c)~=c.name then T.Tooltip(self,c.name,c.target~=c.name and c.target or nil)end
    end)
    row:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    row:EnableMouseWheel(true);row:SetScript('OnMouseWheel',function(_,delta)U.listScroll=math.max(0,U.listScroll-delta*50);U.RefreshList()end)
    U.rows[index]=row;return row
end
function U.RefreshList()
    local run=U.query~=''and U.sidebarSearch or nil
    local T=Z.Theme;local list=Z.store:List(U.query or'',run and run.hits or nil);local width=U.metrics.sidebarWidth-16
    local compact=Z.store.settings.sidebarCompact and not U.metrics.iconOnly;local showPreview=U.metrics.showPreview and not compact
    local height=U.listViewport:GetHeight();local entries={};local y=0;local prior
    if run and not run.empty and(run.count>0 or not run.done)then entries[1]={summary=true,y=0,height=34};y=34 end
    for _,c in ipairs(list)do
        local include=c.kind~='CHANNEL'or U.query~=''or Z.store.settings.publicChannels and Z.store.settings.enabledChannels[(c.channelName or''):lower()]==true
        if include then
        local group=Z.Store.Group(c.kind)
        if group~=prior and not U.metrics.iconOnly then entries[#entries+1]={header=caption(group),y=y,height=26};y=y+26;prior=group end
        local rowHeight=compact and 34 or showPreview and 64 or U.metrics.iconOnly and 54 or 50
        entries[#entries+1]={conversation=c,y=y,height=rowHeight};y=y+rowHeight
        end
    end
    U.listScroll=math.min(U.listScroll,math.max(0,y-height));local rows,headers=0,0
    local summaryShown=false
    for _,entry in ipairs(entries)do
        local top=entry.y-U.listScroll
        if top+entry.height>=0 and top<height then
            if entry.summary then
                summaryShown=true
                if not U.searchSummary then U.searchSummary=T.Button(U.listCanvas,'',function()U.OpenSearch(nil,U.query)end,'own')end
                U.searchSummary.label:SetText(run.done and string.format(Z.L('%d Treffer anzeigen','Show %d results'),run.count)or string.format(Z.L('Suche … %d Treffer','Searching … %d results'),run.count))
                T.Place(U.searchSummary,0,top,width,entry.height-4,U.listCanvas);U.searchSummary:Show()
            elseif entry.header then
                headers=headers+1;local f=U.headers[headers]or T.Text(U.listCanvas,'',11,true,'muted');U.headers[headers]=f
                f:SetText(entry.header);T.Place(f,8,top+6,width-16,18,U.listCanvas);f:Show()
            else
                rows=rows+1;local row=conversationRow(rows);local c=entry.conversation;row.conversation=c
                T.Place(row,0,top,width,entry.height-2,U.listCanvas);row:Show()
                row.zenialBackgroundKind=c.key==Z.store.db.ui.selected and'selected'or'sidebar'
                row.opacityMultiplier=c.key==Z.store.db.ui.selected and.4 or 0
                local col=T.colors[row.zenialBackgroundKind];row:SetBackdropColor(col[1],col[2],col[3],(U.currentAlpha or.94)*row.opacityMultiplier)
                local r,g,b=T.Color('gold');row:SetBackdropBorderColor(r,g,b,c.key==Z.store.db.ui.selected and 1 or 0)
                T.Place(row.divider,5,entry.height-3,width-10,1,row)
                T.SetIcon(row.icon,c);local iconSize=compact and 24 or U.metrics.iconOnly and 38 or showPreview and 42 or 34
                T.Place(row.icon,5,(entry.height-iconSize)/2,iconSize,iconSize,row)
                local x=iconSize+15
                row.name:SetText((c.pinned and'• 'or'')..Z.Format.ConversationLabel(c)..(c.muted and'  ·'or''));T.Place(row.name,x,compact and 7 or showPreview and 9 or 14,width-x-(showPreview and 48 or 30),20,row)
                local last=c.messages[#c.messages];local preview=last and(last.deleted and Z.L('Nachricht gelöscht','Message deleted')or Z.Plain(last.text))or''
                if c.draft and c.draft~=''then preview=Z.L('Entwurf: ','Draft: ')..Z.Plain(c.draft)end
                row.preview:SetText(preview:gsub('[\r\n]+',' '));T.Place(row.preview,x,33,width-x-8,19,row)
                row.time:SetText(c.last and c.last>0 and textTime(c.last)or'');T.Place(row.time,width-43,8,35,14,row)
                row.name:SetShown(not U.metrics.iconOnly);row.preview:SetShown(showPreview);row.time:SetShown(showPreview)
                local unread=tonumber(c.unread)or 0;row.count:SetText(unread>99 and'99+'or tostring(unread))
                local bx=U.metrics.iconOnly and width-19 or width-27;local by=compact and 7 or showPreview and 34 or 17
                T.Place(row.badge,bx,by,23,19,row);row.badge:SetShown(unread>0)
            end
        end
    end
    for i=rows+1,#U.rows do U.rows[i]:Hide()end;for i=headers+1,#U.headers do U.headers[i]:Hide()end
    if U.searchSummary and not summaryShown then U.searchSummary:Hide()end
    U.listEmpty:SetShown(#list==0 and not U.metrics.iconOnly)
end
function U.Refresh()
    if not U.frame then return end
    U.dirty=false;U.RefreshList();local c=selected()
    -- The header always names the conversation in full; an own display name comes first.
    U.channelName:SetText(c and(c.alias and c.alias~=''and c.alias..' ('..c.name..')'or c.name)or Z.L('Deine Gespräche','Your conversations'))
    U.channelDetail:SetText(c and caption(Z.Store.Group(c.kind))or Z.L('Wähle ein Gespräch oder starte eine Nachricht.','Choose a conversation or start a message.'))
    Z.Theme.SetIcon(U.channelIcon,c or{kind='COMMUNITY'})
    if c then U.input:Enable()else U.input:Disable()end;U.send:SetEnabled(c~=nil)
    U.placeholder:SetShown(U.input:GetText()=='')
    Z.Transcript.Render(U)
    U.RefreshRecovery()
    Z.Theme.ButtonIcon(U.lock,Z.store.settings.locked and'Interface\\PetBattles\\PetBattle-LockIcon'or'Interface\\Icons\\INV_Misc_Key_01')
    U.lock.tip=Z.store.settings.locked and Z.L('Fenster gesperrt · Zum Entsperren klicken','Window locked · Click to unlock')or Z.L('Fenster entsperrt · Zum Sperren klicken','Window unlocked · Click to lock')
    U.UpdateAlpha()
    if U.RefreshSearchPanel then U.RefreshSearchPanel()end
end
-- Optional: the window fades out while nothing happens and returns on hover, typing or a new message.
local FADE_SPEED=2.5
function U.UpdateFade(elapsed)
    local s=Z.store.settings;local f=U.frame
    local target=1
    if s.fadeEnabled then
        local active=f:IsMouseOver()or U.input:HasFocus()or U.search:HasFocus()or U.settingsPanel:IsShown()
            or(U.copy and U.copy:IsShown())or(U.confirm and U.confirm:IsShown())or(U.searchPanel and U.searchPanel:IsShown())
        local now=Z.Clock()
        if active or not U.lastActivity then U.lastActivity=now end
        if now-U.lastActivity>=s.fadeAfter then target=s.fadeAlpha end
    end
    local current=U.fadeValue or 1
    if current==target then return end
    local step=elapsed*FADE_SPEED
    if current<target then current=math.min(target,current+step)else current=math.max(target,current-step)end
    U.fadeValue=current;f:SetAlpha(current)
end
function U.RefreshRecovery()
    local c=selected();local recoveries=c and Z.adapter:Recoveries(c.key)or{};U.recoveryAttempt=recoveries[1]
    U.recovery.label:SetText(U.recoveryAttempt and U.recoveryAttempt.unconfirmed and Z.L('Zustellung unbestätigt · Text anzeigen','Delivery unconfirmed · View text')or Z.L('Fehlgeschlagenen Text wiederherstellen','Restore failed message'))
    U.recovery:SetShown(#recoveries>0 and not U.settingsPanel:IsShown())
end
function U.Layout()
    if not U.frame or U.layoutRunning then return end;U.layoutRunning=true
    local T=Z.Theme;local s=Z.store.settings
    local w,h,scale=Z.Layout.Clamp(U.frame:GetWidth(),U.frame:GetHeight(),s.scale,UIParent:GetWidth(),UIParent:GetHeight())
    U.frame:SetScale(scale);U.frame:SetSize(w,h);U.frame:SetResizeBounds(540,360,math.max(540,UIParent:GetWidth()/scale-16),math.max(360,UIParent:GetHeight()/scale-16))
    U.metrics=Z.Layout.Resolve(w,h,s,U.metrics and U.metrics.mode)
    local sw=U.metrics.sidebarWidth;local content=w-sw-18
    T.Place(U.titleBar,5,5,w-10,35,U.frame);T.Place(U.brand,8,3,28,28,U.titleBar);T.Place(U.title,46,6,w-195,26,U.titleBar)
    T.Place(U.gear,w-129,7,34,28,U.frame);T.Place(U.lock,w-89,7,34,28,U.frame);T.Place(U.close,w-49,7,34,28,U.frame)
    T.Place(U.listPanel,7,43,sw-2,h-50,U.frame)
    T.Place(U.searchBackground,6,8,sw-14,32,U.listPanel)
    U.search:SetWidth(sw-22);U.search:SetHeight(28)
    U.searchHint:SetShown(not U.search:HasFocus()and U.search:GetText()==''and not U.metrics.iconOnly)
    U.searchIcon:SetShown(U.metrics.iconOnly);U.search:SetShown(not U.metrics.iconOnly)
    T.Place(U.searchIcon,8,8,sw-20,32,U.listPanel)
    T.Place(U.listViewport,6,48,sw-14,h-106,U.listPanel);U.listCanvas:SetSize(sw-14,h-106)
    T.Place(U.listEmpty,10,14,math.max(20,sw-36),80,U.listCanvas)
    T.Place(U.chatPanel,sw+7,43,content,h-50,U.frame)
    T.Place(U.channelIcon,14,10,40,40,U.chatPanel);T.Place(U.channelName,66,9,content-114,26,U.chatPanel)
    T.Place(U.channelDetail,66,36,content-114,18,U.chatPanel);T.Place(U.more,content-40,15,30,28,U.chatPanel)
    T.Place(U.viewport,10,67,content-29,h-205,U.chatPanel);U.canvas:SetSize(content-29,h-205)
    T.Place(U.empty,24,math.max(12,(h-205)/2-20),content-77,60,U.canvas)
    T.Place(U.scrollbar,content-15,68,8,h-207,U.chatPanel)
    local composerY=h-132
    T.Place(U.composer,5,composerY,content-10,76,U.chatPanel)
    local sendWidth=U.metrics.iconOnly and 38 or 100
    T.Place(U.send,content-sendWidth-20,25,sendWidth,34,U.composer)
    U.send.label:SetText(U.metrics.iconOnly and''or Z.L('Senden','Send'))
    U.send.label:ClearAllPoints();U.send.label:SetPoint('TOPLEFT',U.send,'TOPLEFT',27,-3);U.send.label:SetPoint('BOTTOMRIGHT',U.send,'BOTTOMRIGHT',-5,3)
    U.send.symbol:ClearAllPoints();U.send.symbol:SetPoint(U.metrics.iconOnly and'CENTER'or'LEFT',U.send,U.metrics.iconOnly and'CENTER'or'LEFT',U.metrics.iconOnly and 0 or 8,0)
    T.Place(U.inputBackground,10,24,content-sendWidth-38,38,U.composer)
    U.input:SetWidth(content-sendWidth-46);U.input:SetHeight(34)
    T.Place(U.placeholder,12,9,math.max(40,content-sendWidth-70),22,U.inputBackground)
    T.Place(U.notice,14,h-174,content-30,30,U.chatPanel)
    T.Place(U.newest,math.max(12,(content-270)/2),h-181,math.min(270,content-28),28,U.chatPanel)
    T.Place(U.recovery,14,h-181,math.min(300,content-28),28,U.chatPanel)
    T.Place(U.grip,w-25,h-25,20,20,U.frame);U.grip:SetShown(not s.locked)
    T.Place(U.settingsPanel,sw+7,43,content,h-50,U.frame)
    T.Place(U.settingsNav,7,43,sw-2,h-50,U.frame)
    T.Place(U.back,content-172,10,160,30,U.settingsPanel)
    U.frame:SetMovable(not s.locked);U.frame:SetResizable(not s.locked)
    if U.LayoutOptions then U.LayoutOptions()end
    if U.LayoutSearch then U.LayoutSearch()end
    U.indexDirty=true;U.indexFull=true;U.layoutRunning=false;U.Refresh()
end
function U.Build()
    if U.frame then return end
    local T=Z.Theme;local d=Z.store.db.ui
    local f=T.Frame(UIParent,'shell','gold');f.opacityMultiplier=0;U.frame=f;f:SetFrameStrata('MEDIUM');f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);f:SetResizable(true)
    f:SetSize(d.width,d.height);f:SetPoint('CENTER',UIParent,'CENTER',d.x,d.y);f:Hide()
    U.titleBar=T.Frame(f,'shell','line');U.titleBar:EnableMouse(true);U.titleBar:RegisterForDrag('LeftButton')
    U.brand=T.Icon(U.titleBar,{kind='COMMUNITY'})
    U.title=T.Text(U.titleBar,'Zenial Chat',20,true,'goldBright')
    U.titleBar:SetScript('OnDragStart',function()if not Z.store.settings.locked then f:StartMoving()end end)
    U.titleBar:SetScript('OnDragStop',function()f:StopMovingOrSizing();U.SaveGeometry()end)
    U.gear=T.Button(U.titleBar,'⚙',function()U.OpenSettings('appearance')end);U.gear.tip=Z.L('Einstellungen','Settings')
    T.ButtonIcon(U.gear,'Interface\\Icons\\Trade_Engineering','GM-icon-settings')
    U.lock=T.Button(U.titleBar,'◇',function()U.SetSetting('locked',not Z.store.settings.locked)end);U.lock.tip=Z.L('Position und Größe sperren','Lock position and size')
    U.close=Z.CloseButton(U.titleBar,function()f:Hide()end,Z.L('Schließen','Close'))
    U.listPanel=T.Frame(f,'sidebar','line')
    U.search,U.searchBackground=T.Input(U.listPanel);U.query=''
    U.searchHint=T.Text(U.searchBackground,Z.L('Gespräche suchen','Search conversations'),12,false,'muted');U.searchHint:SetPoint('LEFT',10,0)
    U.search:SetScript('OnTextChanged',function(self)U.query=self:GetText();U.QueryChanged();U.searchHint:SetShown(U.query==''and not self:HasFocus())end)
    U.search:SetScript('OnEnterPressed',function(self)
        Z.store:AddSearchHistory(self:GetText());self:ClearFocus()
        if U.sidebarSearch and not U.sidebarSearch.empty then U.OpenSearch(nil,U.query)end
    end)
    U.search:SetScript('OnEditFocusGained',function()U.searchHint:Hide()end)
    U.search:SetScript('OnEditFocusLost',function()U.searchHint:SetShown(U.search:GetText()=='')end)
    U.search:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
    U.searchIcon=T.Button(U.listPanel,'⌕',function()
        U.ShowCopy(U.query,Z.L('Gespräche und Nachrichten suchen','Search conversations and messages'));U.copy.edit:SetScript('OnTextChanged',function(self)U.query=self:GetText();U.QueryChanged()end)
        U.copy.edit:SetScript('OnEnterPressed',function(self)self:ClearFocus();U.copy:Hide()end)
    end);U.searchIcon.tip=Z.L('Gespräche und Nachrichten suchen','Search conversations and messages')
    T.ButtonIcon(U.searchIcon,'Interface\\Icons\\INV_Misc_Spyglass_03','communities-icon-searchmagnifyingglass')
    U.listViewport=CreateFrame('ScrollFrame',nil,U.listPanel);U.listViewport:SetClipsChildren(true)
    U.listCanvas=CreateFrame('Frame',nil,U.listViewport);U.listViewport:SetScrollChild(U.listCanvas)
    U.listViewport:EnableMouseWheel(true);U.listViewport:SetScript('OnMouseWheel',function(_,delta)U.listScroll=math.max(0,U.listScroll-delta*50);U.RefreshList()end)
    U.listEmpty=T.Text(U.listCanvas,Z.L('Noch keine Gespräche.\n\nStarte über ••• eine Nachricht.','No conversations yet.\n\nStart a message with •••.'),12,false,'muted');U.listEmpty:SetWordWrap(true)
    U.chatPanel=T.Frame(f,'shell','line')
    U.channelIcon=T.Icon(U.chatPanel,{kind='COMMUNITY'});U.channelName=T.Text(U.chatPanel,'',20,true);U.channelDetail=T.Text(U.chatPanel,'',12,false,'muted')
    U.more=T.Button(U.chatPanel,'•••',function(self)
        local c=selected();if c then U.ConversationMenu(self,c)
        else U.StartConversation()end
    end);U.more.tip=Z.L('Gesprächsmenü · Neue Nachricht','Conversation menu · New message')
    Z.Transcript.Build(U)
    U.composer=T.Frame(U.chatPanel,'shell','line');U.composer.opacityMultiplier=0
    U.input,U.inputBackground=T.Input(U.composer);U.input:SetMultiLine(true);U.input:SetHyperlinksEnabled(true)
    U.placeholder=T.Text(U.inputBackground,Z.L('Nachricht schreiben …','Write a message …'),13,false,'muted')
    U.input:SetScript('OnTextChanged',function(self)
        -- Any change to a recalled message makes it the draft, also an inserted link or quote.
        if U.historyPos and self:GetText()~=U.historyValue then U.historyPos=nil;U.historyDraft=nil end
        if not U.loadingDraft and not U.historyPos and selected()then Z.store:SetDraft(selected().key,self:GetText())end
        U.placeholder:SetShown(self:GetText()=='')
    end)
    U.input:SetScript('OnEditFocusGained',installLinks);installLinks()
    U.input:SetScript('OnEnterPressed',function(self)if IsShiftKeyDown and IsShiftKeyDown()then self:Insert('\n')else U.Submit()end end)
    U.input:SetScript('OnEscapePressed',function(self)if self:HasFocus()then self:ClearFocus()else f:Hide()end end)
    U.input:SetScript('OnArrowPressed',function(_,key)U.HistoryArrow(key)end)
    U.send=T.Button(U.composer,'',U.Submit,'own');T.ButtonIcon(U.send,'Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up');U.send.tip=Z.L('Nachricht senden · Enter','Send message · Enter')
    U.notice=T.Text(U.chatPanel,'',11,false,'goldBright');U.notice:SetWordWrap(true);U.notice:Hide()
    U.recovery=T.Button(U.chatPanel,Z.L('Fehlgeschlagenen Text wiederherstellen','Restore failed message'),function()U.RestoreRecovery(U.recoveryAttempt)end);U.recovery:Hide()
    U.settingsPanel=T.Frame(f,'shell','line');U.settingsPanel:Hide();U.settingsNav=T.Frame(f,'sidebar','line');U.settingsNav:Hide()
    U.back=T.Button(U.settingsPanel,Z.L('Zurück zum Chat','Back to chat'),function()
        U.settingsPanel:Hide();U.settingsNav:Hide();U.listPanel:Show();U.chatPanel:Show();U.back:Hide();U.Layout()
    end);U.back:Hide()
    U.grip=CreateFrame('Button',nil,f);U.grip.texture=U.grip:CreateTexture(nil,'ARTWORK');U.grip.texture:SetAllPoints();U.grip.texture:SetTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
    U.grip:SetScript('OnMouseDown',function()if not Z.store.settings.locked then f:StartSizing('BOTTOMRIGHT')end end)
    U.grip:SetScript('OnMouseUp',function()f:StopMovingOrSizing();U.Layout();U.SaveGeometry()end)
    f:SetScript('OnSizeChanged',function()if not U.layoutRunning then U.resizePending=true end end)
    f:SetScript('OnHide',function()U.input:ClearFocus();U.search:ClearFocus();U.SaveGeometry();if U.menu then U.menu:Hide()end end)
    f:SetScript('OnUpdate',function(_,elapsed)
        U.tick=(U.tick or 0)+elapsed
        U.recoveryTick=(U.recoveryTick or 0)+elapsed
        if U.recoveryTick>=1 then U.recoveryTick=0;U.RefreshRecovery()end
        if U.tick>=1/30 then
            local step=U.tick;U.tick=0
            if U.resizePending then U.resizePending=false;U.Layout();U.SaveGeometry()
            elseif U.dirty then U.Refresh()end
            U.SearchTick()
            U.UpdateFade(step)
            U.UpdateAlpha()
        end
    end)
    local name='ZenialChatFrame';_G[name]=f
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=name end
    local saved=selected()
    if saved then U.loadingDraft=true;U.input:SetText(saved.draft or'');U.loadingDraft=false;U.loadedKey=saved.key end
    U.Layout()
end
function U.ApplyMinimapVisibility()
    if U.minimapButton then U.minimapButton:SetShown(Z.store.settings.minimapHidden~=true)end
end
-- Probed: a client without a working menu API falls back to the settings.
local function openMinimapMenu(owner)
    if type(MenuUtil)~='table'or type(MenuUtil.CreateContextMenu)~='function'then return false end
    return(pcall(MenuUtil.CreateContextMenu,owner,function(_,root)
        root:CreateTitle('Zenial Chat')
        root:CreateButton(Z.L('Einstellungen','Settings'),function()U.OpenSettings('appearance')end)
        root:CreateButton(Z.L('Icon ausblenden','Hide icon'),function()
            Z.store.settings.minimapHidden=true;U.ApplyMinimapVisibility()
            if U.settingsPanel and U.settingsPanel:IsShown()then U.RebuildOptions()end
        end)
    end))
end
function U.CreateMinimapButton()
    if U.minimapButton or not Minimap then return end
    local settings=Z.store.settings
    U.minimapButton=Z.Launcher.CreateMinimapButton({
        name='ZenialChatMinimapButton',icon=Z.Theme.icons.COMMUNITY,defaultAngle=200,
        getAngle=function()return settings.minimapAngle end,
        setAngle=function(angle)settings.minimapAngle=angle end,
        onClick=function(self,mouseButton)
            if mouseButton~='RightButton'then U.Toggle()
            elseif not openMinimapMenu(self)then U.OpenSettings('appearance')end
        end,
        tooltip=function(tip)
            tip:AddLine('Zenial Chat')
            tip:AddLine(Z.L('Linksklick: Chat öffnen / schließen','Left-click: Open / close chat'),1,1,1)
            tip:AddLine(Z.L('Rechtsklick: Optionen','Right-click: Options'),1,1,1)
            tip:AddLine(Z.L('Befehl: /zchat','Command: /zchat'),1,1,1)
        end,
    })
    U.ApplyMinimapVisibility()
end
function U.StartConversation()
    U.ShowCopy('',Z.L('Neue Nachricht · Spielername oder BattleTag','New message · Player name or BattleTag'));U.copy.edit:SetMultiLine(false)
    U.copy.edit:SetScript('OnEnterPressed',function(self)
        local target=self:GetText():match('^%s*(.-)%s*$');if target==''then return end
        local kind=target:find('#',1,true)and'BN_WHISPER'or'WHISPER'
        local native=kind=='WHISPER'and Z.adapter:FullName(target,Z.adapter.me.realm)or target
        local c=Z.store:Ensure({kind=kind,target=native,name=target,scope=kind=='WHISPER'and Z.adapter.me.realm or nil})
        self:ClearFocus();U.copy:Hide();U.Select(c.key);U.input:SetFocus()
    end)
    U.Notice(Z.L('Vollständigen Spielernamen eingeben und Enter drücken.','Enter the full player name, then press Enter.'))
end
