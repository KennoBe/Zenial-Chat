-- The result view of the message search. It lies over the transcript and the composer; the
-- conversation below keeps its draft and scroll position while it is open.
local _,Z=...
local U=Z.UI
local RESTART_SECONDS=3
local ROW_HEIGHT=52
local TOGGLE_WIDTH,REMOVE_WIDTH=110,84
local LIST_TOP=86
local periods={{0,'Gesamter Zeitraum','Any time'},{1,'Heute','Today'},{7,'7 Tage','7 days'},{30,'30 Tage','30 days'}}
local function clock()return Z.Clock()end
U.searchMode='messages' -- or 'bookmarks': the same panel lists the bookmarks
local function escape(text)return(tostring(text):gsub('|','||'))end
-- Sidebar ------------------------------------------------------------------------------------
-- The sidebar filter runs in slices too. Its first slice runs at once, so a small archive gets
-- its result in the same frame as the key press.
function U.QueryChanged()
    U.listScroll=0
    U.sidebarSearch=U.query~=''and Z.Search.New(Z.store,U.query,{filter=U.ListFilter})or nil
    U.sidebarNext=nil;U.sidebarStarted=clock();U.sidebarStale=false
    if U.sidebarSearch then U.sidebarSearch:Step()end
    U.RefreshList()
end
-- New messages refresh the sidebar in the background. The open result list stays as it is, so that
-- it does not jump while being read; only deleted history makes it run again.
function U.SearchChanged(reason)
    U.sidebarStale=U.sidebarSearch~=nil
    if U.panelSearch and reason~='message'then U.panelStale=true end
end
-- Panel --------------------------------------------------------------------------------------
local function sinceFor(days)
    if days<=0 then return nil end
    local now=Z.Now()
    if days==1 then
        local h,m,s=Z.Format.Stamp('%H:%M:%S',now):match('^(%d+):(%d+):(%d+)$')
        if h then return now-(tonumber(h)*3600+tonumber(m)*60+tonumber(s))end
    end
    return now-days*86400
end
local function startPanel(keepScroll)
    local text=U.searchInput:GetText()
    local key=U.searchScope=='conversation'and U.searchKey or nil
    if U.searchMode=='bookmarks'then
        -- Short and held in memory: the list is complete at once. results are bookmark entries here.
        local list=Z.Bookmarks and Z.Bookmarks.List(text,{key=key,since=sinceFor(U.searchDays or 0)})or{}
        U.panelSearch={bookmarks=true,done=true,count=#list,results=list,terms={}}
        U.panelStale=false;if not keepScroll then U.searchListScroll=0 end
        U.RefreshSearchPanel();return
    end
    U.panelSearch=Z.Search.New(Z.store,text,{key=key,since=sinceFor(U.searchDays or 0),filter=U.ListFilter})
    U.panelStale=false;U.searchListScroll=0
    U.panelSearch:Step();U.RefreshSearchPanel()
end
local function resultRow(index)
    if U.searchRows[index]then return U.searchRows[index]end
    local T=Z.ChatTheme;local row=T.Button(U.searchList,'',nil)
    row.label:Hide()
    row.title=T.Text(row,'',11,true,'goldBright');row.title:SetWordWrap(false)
    row.snippet=T.Text(row,'',12,false,'text');row.snippet:SetWordWrap(false)
    row:SetScript('OnClick',function(self)if self.bookmark then U.OpenBookmark(self.bookmark)else U.JumpToHit(self.hit)end end)
    row:SetScript('OnEnter',function(self)
        if self.bookmark and GameTooltip then
            -- Time and the full text, nothing else. A pipe in a message is text, never markup.
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:ClearLines()
            GameTooltip:AddLine(Z.Format.FullTime(self.bookmark.at),1,.82,.4)
            GameTooltip:AddLine(escape(Z.Plain(self.bookmark.text)),.85,.87,.9,true)
            GameTooltip:Show();return
        end
        if not self.hit or not GameTooltip then return end
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:ClearLines()
        GameTooltip:AddLine(Z.Format.FullTime(self.hit.msg.at),1,.82,.4)
        for _,line in ipairs(Z.Search.Context(Z.store,self.hit,2))do
            if line.current then GameTooltip:AddLine(line.text,1,.82,.1,true)else GameTooltip:AddLine(line.text,.85,.87,.9,true)end
        end
        GameTooltip:Show()
    end)
    row:EnableMouseWheel(true);row:SetScript('OnMouseWheel',function(_,delta)U.ScrollSearch(delta)end)
    U.searchRows[index]=row;return row
end
function U.ScrollSearch(delta)
    U.searchListScroll=math.max(0,(U.searchListScroll or 0)-delta*ROW_HEIGHT);U.RefreshSearchPanel()
end
local function listMessages(run)
    local results=run and run.results or{}
    local T=Z.ChatTheme;local width=U.searchList:GetWidth();local height=U.searchList:GetHeight()
    U.searchListScroll=math.min(U.searchListScroll or 0,math.max(0,#results*ROW_HEIGHT-height))
    local first=math.floor(U.searchListScroll/ROW_HEIGHT)+1;local used=0
    for i=first,math.min(#results,first+math.ceil(height/ROW_HEIGHT))do
        local hit=results[i];local conv=Z.store:Get(hit.key)
        if conv then
            used=used+1;local row=resultRow(used);row.hit=hit;row.bookmark=nil;row:Show()
            if row.remove then row.remove:Hide()end
            T.Place(row,0,(i-1)*ROW_HEIGHT-U.searchListScroll,width,ROW_HEIGHT-4,U.searchList)
            local who=hit.msg.outgoing and hit.msg.ownCharacter or hit.msg.sender
            row.title:SetText(Z.Format.ConversationLabel(conv)..' · '..Z.Plain(who)..' · '..Z.Format.Stamp('%d.%m.%Y %H:%M',hit.msg.at))
            T.Place(row.title,10,6,width-20,16,row)
            row.snippet:SetText(Z.Format.Highlight(Z.Search.Snippet(hit.msg,run.terms),run.terms))
            T.Place(row.snippet,10,25,width-20,18,row)
        end
    end
    for i=used+1,#U.searchRows do U.searchRows[i]:Hide()end
    local status
    if not run or run.empty then status=Z.L('Mindestens zwei Zeichen. Absender: von:Name, ganzer Name: von:"Vorname Nachname"','At least two characters. Sender: from:Name, full name: from:"First Last"')
    elseif run.done then
        status=string.format(Z.L('%d Treffer','%d results'),run.count)
        if run.count>#results then status=status..string.format(Z.L(' · die neuesten %d angezeigt',' · newest %d shown'),#results)end
    else status=string.format(Z.L('Suche läuft … %d Treffer','Searching … %d results'),run.count)end
    U.searchStatus:SetText(status)
end
-- A bookmark whose message is gone still reads: its own copy is listed and says so.
local function listBookmarks(run)
    local results=run and run.results or{}
    local T=Z.ChatTheme;local width=U.searchList:GetWidth();local height=U.searchList:GetHeight()
    U.searchListScroll=math.min(U.searchListScroll or 0,math.max(0,#results*ROW_HEIGHT-height))
    local first=math.floor(U.searchListScroll/ROW_HEIGHT)+1;local used=0
    for i=first,math.min(#results,first+math.ceil(height/ROW_HEIGHT))do
        local entry=results[i]
        used=used+1;local row=resultRow(used);row.bookmark=entry;row.hit=nil;row:Show()
        T.Place(row,0,(i-1)*ROW_HEIGHT-U.searchListScroll,width,ROW_HEIGHT-4,U.searchList)
        if not row.remove then
            row.remove=T.Button(row,Z.L('Entfernen','Remove'),function()if row.bookmark then U.RemoveBookmark(row.bookmark)end end)
        end
        T.Place(row.remove,width-REMOVE_WIDTH-8,4,REMOVE_WIDTH,22,row);row.remove:Show()
        local who=Z.Plain(entry.sender)
        if who==''and entry.outgoing then who=Z.L('Du','You')end
        local parts={Z.Plain(entry.conv)}
        if who~=''then parts[#parts+1]=who end
        parts[#parts+1]=Z.Format.Stamp('%d.%m.%Y %H:%M',entry.at)
        local title=table.concat(parts,' · ')
        if not Z.Bookmarks.Exists(entry)then title=title..Z.L(' · nicht mehr im Verlauf',' · no longer in the history')end
        row.title:SetText(escape(title));T.Place(row.title,10,6,width-REMOVE_WIDTH-28,16,row)
        local line=Z.Plain(entry.text):match('^[^\r\n]*')or''
        if #line>200 then
            local stop=200
            while stop>0 and(line:byte(stop+1)or 0)>=128 and(line:byte(stop+1)or 0)<192 do stop=stop-1 end
            line=line:sub(1,stop)..'…'
        end
        row.snippet:SetText(escape(line));T.Place(row.snippet,10,25,width-20,18,row)
    end
    for i=used+1,#U.searchRows do U.searchRows[i]:Hide()end
    if Z.Bookmarks and Z.Bookmarks.Count()>0 then U.searchStatus:SetText(string.format(Z.L('%d Lesezeichen','%d bookmarks'),#results))
    else U.searchStatus:SetText(Z.L('Noch keine Lesezeichen. Rechtsklick auf eine Nachricht setzt eines.','No bookmarks yet. Right-click a message to add one.'))end
end
function U.RefreshSearchPanel()
    local panel=U.searchPanel;if not panel or not panel:IsShown()then return end
    local bookmarks=U.searchMode=='bookmarks'
    if bookmarks then listBookmarks(U.panelSearch)else listMessages(U.panelSearch)end
    local conv=U.searchKey and Z.store:Get(U.searchKey)
    U.searchScopeButton.label:SetText(U.searchScope=='conversation'and conv and Z.Format.ConversationLabel(conv)or Z.L('Alle Gespräche','All conversations'))
    for _,period in ipairs(periods)do if period[1]==(U.searchDays or 0)then U.searchPeriodButton.label:SetText(Z.L(period[2],period[3]))end end
    U.searchHistoryButton:SetShown(Z.store.settings.searchHistoryEnabled==true and not bookmarks)
    Z.ChatTheme.SetActive(U.searchBookmarksButton,bookmarks)
end
function U.LayoutSearch()
    if not U.searchPanel then return end
    local T=Z.ChatTheme;local w=U.chatPanel:GetWidth();local h=U.chatPanel:GetHeight()
    T.Place(U.searchPanel,5,62,w-10,h-68,U.chatPanel)
    local pw=w-10;local ph=h-68
    -- Field, mode button and close button share the top row; without the bookmark module the field keeps the room.
    local has=Z.Bookmarks~=nil;local toggleX=pw-40-TOGGLE_WIDTH-6
    T.Place(U.searchBox,8,8,has and toggleX-14 or pw-54,32,U.searchPanel)
    T.Place(U.searchBookmarksButton,toggleX,10,TOGGLE_WIDTH,28,U.searchPanel);U.searchBookmarksButton:SetShown(has)
    T.Place(U.searchClose,pw-40,10,28,28,U.searchPanel)
    T.Place(U.searchScopeButton,8,46,math.min(190,(pw-24)*.38),30,U.searchPanel)
    T.Place(U.searchPeriodButton,math.min(190,(pw-24)*.38)+14,46,math.min(140,(pw-24)*.28),30,U.searchPanel)
    local statusX=math.min(190,(pw-24)*.38)+math.min(140,(pw-24)*.28)+22
    T.Place(U.searchHistoryButton,statusX,46,34,30,U.searchPanel)
    T.Place(U.searchStatus,statusX+(Z.store.settings.searchHistoryEnabled and U.searchMode~='bookmarks'and 42 or 0),50,math.max(40,pw-statusX-50),32,U.searchPanel)
    T.Place(U.searchList,8,LIST_TOP,pw-16,math.max(40,ph-LIST_TOP-8),U.searchPanel)
    U.RefreshSearchPanel()
end
local function buildPanel()
    if U.searchPanel then return end
    local T=Z.ChatTheme
    local f=T.Frame(U.chatPanel,'shell','line');U.searchPanel=f;f:EnableMouse(true);f:Hide()
    f:SetFrameLevel(U.chatPanel:GetFrameLevel()+30)
    U.searchInput,U.searchBox=T.Input(f)
    U.searchInput:SetScript('OnTextChanged',function()if U.searchPanel:IsShown()then startPanel()end end)
    U.searchInput:SetScript('OnEscapePressed',function()U.CloseSearch()end)
    U.searchInput:SetScript('OnEnterPressed',function(self)if U.searchMode~='bookmarks'then Z.store:AddSearchHistory(self:GetText())end;self:ClearFocus()end)
    U.searchClose=Z.CloseButton(f,function()U.CloseSearch()end,Z.L('Suche schließen','Close search'))
    U.searchBookmarksButton=T.Chip(f,Z.L('Lesezeichen','Bookmarks'),function()
        U.searchMode=U.searchMode=='bookmarks'and'messages'or'bookmarks';startPanel()
    end);U.searchBookmarksButton.tip=Z.L('Lesezeichen zeigen','Show bookmarks')
    U.searchScopeButton=T.Dropdown(T.Button(f,'',function(self)
        local items={{text=Z.L('Alle Gespräche','All conversations'),run=function()U.searchScope='all';startPanel()end}}
        local conv=U.searchKey and Z.store:Get(U.searchKey)
        if conv then items[2]={text=Z.Format.ConversationLabel(conv),run=function()U.searchScope='conversation';startPanel()end}end
        U.ShowMenu(self,items)
    end))
    U.searchPeriodButton=T.Dropdown(T.Button(f,'',function(self)
        local items={}
        for _,period in ipairs(periods)do items[#items+1]={text=Z.L(period[2],period[3]),run=function()U.searchDays=period[1];startPanel()end}end
        U.ShowMenu(self,items)
    end))
    U.searchHistoryButton=T.Button(f,'…',function(self)
        local items={};local list=Z.store:SearchHistory()
        for i=#list,1,-1 do local text=list[i];items[#items+1]={text=text,run=function()U.searchInput:SetText(text);U.searchInput:SetCursorPosition(#text)end}end
        if#items==0 then items[1]={text=Z.L('Noch kein Suchverlauf','No search history yet'),run=function()end}end
        U.ShowMenu(self,items)
    end);U.searchHistoryButton.tip=Z.L('Suchverlauf','Search history')
    U.searchStatus=T.Text(f,'',11,false,'muted');U.searchStatus:SetWordWrap(true)
    U.searchList=CreateFrame('Frame',nil,f);U.searchList:SetClipsChildren(true)
    U.searchList:EnableMouseWheel(true);U.searchList:SetScript('OnMouseWheel',function(_,delta)U.ScrollSearch(delta)end)
    U.searchRows={}
end
local function openPanel(mode,scopeKey,query)
    U.Build();buildPanel()
    U.searchMode=mode;U.panelSearch=nil -- the other mode's list must not be drawn for a moment
    -- The title bar button also works from the settings: back to the chat first.
    if mode=='bookmarks'and U.settingsPanel:IsShown()then
        U.CloseSettings();U.Layout()
    end
    local current=Z.store:Get(Z.store.db.ui.selected)
    U.searchScope=scopeKey and'conversation'or'all'
    U.searchKey=scopeKey or current and current.key or nil
    U.input:ClearFocus();U.search:ClearFocus()
    U.searchPanel:Show();U.LayoutSearch()
    U.searchInput:SetText(query or'')
    startPanel()
    U.searchInput:SetFocus()
end
-- scopeKey limits the search to one conversation; without it the search covers all of them.
function U.OpenSearch(scopeKey,query)openPanel('messages',scopeKey,query)end
-- The bookmarks of all conversations, field empty.
function U.OpenBookmarks()openPanel('bookmarks',nil,'')end
function U.OpenBookmark(entry)
    if not entry then return end
    if Z.Bookmarks and Z.Bookmarks.Exists(entry)then
        U.searchInput:ClearFocus();U.searchPanel:Hide()
        -- An officer chat without the right to read stays closed; the own copy of the bookmark is still shown.
        if U.Select(entry.key,entry.id)==false then U.ShowCopy(Z.Plain(entry.text))end
    else U.ShowCopy(Z.Plain(entry.text))end
end
function U.RemoveBookmark(entry)
    if not Z.Bookmarks then return end
    Z.Bookmarks.Remove(entry.key,entry.id);startPanel(true);U.Refresh()
end
function U.CloseSearch()
    if not U.searchPanel then return end
    U.searchInput:ClearFocus();U.searchPanel:Hide();U.panelSearch=nil
    U.Refresh()
end
function U.JumpToHit(hit)
    if not hit then return end
    local run=U.panelSearch;local terms=run and run.terms or nil
    Z.store:AddSearchHistory(U.searchInput:GetText())
    U.searchInput:ClearFocus();U.searchPanel:Hide()
    U.Select(hit.key,hit.msg.id,terms)
end
-- Called about 30 times a second while the window is shown; idle unless a search is running.
function U.SearchTick()
    local run=U.sidebarSearch
    if run and not run.done then
        if run:Step()or run.done then U.listDirty=true end
    elseif U.sidebarNext then
        -- The new run replaces the old one only when complete: the list must not shrink in between.
        U.sidebarNext:Step()
        if U.sidebarNext.done then U.sidebarSearch=U.sidebarNext;U.sidebarNext=nil;U.listDirty=true end
    elseif run and U.sidebarStale and clock()-(U.sidebarStarted or 0)>=RESTART_SECONDS then
        U.sidebarNext=Z.Search.New(Z.store,U.query,{filter=U.ListFilter});U.sidebarStarted=clock();U.sidebarStale=false
    end
    if U.listDirty then U.listDirty=false;U.RefreshList()end
    local panelRun=U.panelSearch
    if panelRun and U.searchPanel:IsShown()then
        if not panelRun.done then panelRun:Step();U.RefreshSearchPanel()
        elseif U.panelStale then startPanel()end
    end
end
