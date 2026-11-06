-- The result view of the message search. It lies over the transcript and the composer; the
-- conversation below keeps its draft and scroll position while it is open.
local _,Z=...
local U=Z.UI
local RESTART_SECONDS=3
local ROW_HEIGHT=52
local LIST_TOP=86
local periods={{0,'Gesamter Zeitraum','Any time'},{1,'Heute','Today'},{7,'7 Tage','7 days'},{30,'30 Tage','30 days'}}
local function clock()return Z.Clock()end
-- Sidebar ------------------------------------------------------------------------------------
-- The sidebar filter runs in slices too. Its first slice runs at once, so a small archive gets
-- its result in the same frame as the key press.
function U.QueryChanged()
    U.listScroll=0
    U.sidebarSearch=U.query~=''and Z.Search.New(Z.store,U.query)or nil
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
local function startPanel()
    local text=U.searchInput:GetText()
    local key=U.searchScope=='conversation'and U.searchKey or nil
    U.panelSearch=Z.Search.New(Z.store,text,{key=key,since=sinceFor(U.searchDays or 0)})
    U.panelStale=false;U.searchListScroll=0
    U.panelSearch:Step();U.RefreshSearchPanel()
end
local function resultRow(index)
    if U.searchRows[index]then return U.searchRows[index]end
    local T=Z.Theme;local row=T.Button(U.searchList,'',nil,'surface')
    row.label:Hide()
    row.title=T.Text(row,'',11,true,'goldBright');row.title:SetWordWrap(false)
    row.snippet=T.Text(row,'',12,false,'text');row.snippet:SetWordWrap(false)
    row:SetScript('OnClick',function(self)U.JumpToHit(self.hit)end)
    row:SetScript('OnEnter',function(self)
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
function U.RefreshSearchPanel()
    local panel=U.searchPanel;if not panel or not panel:IsShown()then return end
    local run=U.panelSearch;local results=run and run.results or{}
    local T=Z.Theme;local width=U.searchList:GetWidth();local height=U.searchList:GetHeight()
    U.searchListScroll=math.min(U.searchListScroll or 0,math.max(0,#results*ROW_HEIGHT-height))
    local first=math.floor(U.searchListScroll/ROW_HEIGHT)+1;local used=0
    for i=first,math.min(#results,first+math.ceil(height/ROW_HEIGHT))do
        local hit=results[i];local conv=Z.store:Get(hit.key)
        if conv then
            used=used+1;local row=resultRow(used);row.hit=hit;row:Show()
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
    local conv=U.searchKey and Z.store:Get(U.searchKey)
    U.searchScopeButton.label:SetText(U.searchScope=='conversation'and conv and Z.Format.ConversationLabel(conv)or Z.L('Alle Gespräche','All conversations'))
    for _,period in ipairs(periods)do if period[1]==(U.searchDays or 0)then U.searchPeriodButton.label:SetText(Z.L(period[2],period[3]))end end
    U.searchHistoryButton:SetShown(Z.store.settings.searchHistoryEnabled==true)
end
function U.LayoutSearch()
    if not U.searchPanel then return end
    local T=Z.Theme;local w=U.chatPanel:GetWidth();local h=U.chatPanel:GetHeight()
    T.Place(U.searchPanel,5,62,w-10,h-68,U.chatPanel)
    local pw=w-10;local ph=h-68
    T.Place(U.searchBox,8,8,pw-54,32,U.searchPanel)
    T.Place(U.searchClose,pw-40,10,28,28,U.searchPanel)
    T.Place(U.searchScopeButton,8,46,math.min(190,(pw-24)*.38),30,U.searchPanel)
    T.Place(U.searchPeriodButton,math.min(190,(pw-24)*.38)+14,46,math.min(140,(pw-24)*.28),30,U.searchPanel)
    local statusX=math.min(190,(pw-24)*.38)+math.min(140,(pw-24)*.28)+22
    T.Place(U.searchHistoryButton,statusX,46,34,30,U.searchPanel)
    T.Place(U.searchStatus,statusX+(Z.store.settings.searchHistoryEnabled and 42 or 0),50,math.max(40,pw-statusX-50),32,U.searchPanel)
    T.Place(U.searchList,8,LIST_TOP,pw-16,math.max(40,ph-LIST_TOP-8),U.searchPanel)
    U.RefreshSearchPanel()
end
local function buildPanel()
    if U.searchPanel then return end
    local T=Z.Theme
    local f=T.Frame(U.chatPanel,'shell','line');U.searchPanel=f;f:EnableMouse(true);f:Hide()
    f:SetFrameLevel(U.chatPanel:GetFrameLevel()+30)
    U.searchInput,U.searchBox=T.Input(f)
    U.searchInput:SetScript('OnTextChanged',function()if U.searchPanel:IsShown()then startPanel()end end)
    U.searchInput:SetScript('OnEscapePressed',function()U.CloseSearch()end)
    U.searchInput:SetScript('OnEnterPressed',function(self)Z.store:AddSearchHistory(self:GetText());self:ClearFocus()end)
    U.searchClose=Z.CloseButton(f,function()U.CloseSearch()end,Z.L('Suche schließen','Close search'))
    U.searchScopeButton=T.Button(f,'',function(self)
        local items={{text=Z.L('Alle Gespräche','All conversations'),run=function()U.searchScope='all';startPanel()end}}
        local conv=U.searchKey and Z.store:Get(U.searchKey)
        if conv then items[2]={text=Z.Format.ConversationLabel(conv),run=function()U.searchScope='conversation';startPanel()end}end
        U.ShowMenu(self,items)
    end)
    U.searchPeriodButton=T.Button(f,'',function(self)
        local items={}
        for _,period in ipairs(periods)do items[#items+1]={text=Z.L(period[2],period[3]),run=function()U.searchDays=period[1];startPanel()end}end
        U.ShowMenu(self,items)
    end)
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
-- scopeKey limits the search to one conversation; without it the search covers all of them.
function U.OpenSearch(scopeKey,query)
    U.Build();buildPanel()
    local current=Z.store:Get(Z.store.db.ui.selected)
    U.searchScope=scopeKey and'conversation'or'all'
    U.searchKey=scopeKey or current and current.key or nil
    U.input:ClearFocus();U.search:ClearFocus()
    U.searchPanel:Show();U.LayoutSearch()
    U.searchInput:SetText(query or'')
    startPanel()
    U.searchInput:SetFocus()
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
        U.sidebarNext=Z.Search.New(Z.store,U.query);U.sidebarStarted=clock();U.sidebarStale=false
    end
    if U.listDirty then U.listDirty=false;U.RefreshList()end
    local panelRun=U.panelSearch
    if panelRun and U.searchPanel:IsShown()then
        if not panelRun.done then panelRun:Step();U.RefreshSearchPanel()
        elseif U.panelStale then startPanel()end
    end
end
