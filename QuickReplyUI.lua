-- Quick replies in the chat window: a button left of the input and a list of saved templates above the composer.
-- A template is only ever inserted into the draft; nothing here sends.
local _,Z=...
local U=Z.UI
if not U then return end
local LIST_WIDTH,ROWS,ROW_HEIGHT,STEP=360,8,30,2
local SHIFT=40 -- room the button takes from the input
local offset=0
local function L(de,en)return Z.L(de,en)end
local function selected()return Z.store and Z.store:Get(Z.store.db.ui.selected)end
local function usable(c)return c~=nil and c.kind~='XFACTION'end
local function items()
    local P=Z.Phrases;local query=U.quickSearch:GetText()
    if query~=''then return P.Templates(query)end
    local list,seen={},{}
    local function add(t)if not seen[t.id]then seen[t.id]=true;list[#list+1]=t end end
    local all=P.Templates('')
    for _,t in ipairs(all)do if P.IsFavorite(t.id)then add(t)end end
    for _,t in ipairs(P.RecentTemplates())do add(t)end
    for _,t in ipairs(all)do add(t)end
    return list
end
-- Rows that fit above the composer (it takes the bottom 132 of the chat panel): a small window shows fewer.
local function fit()
    local room=U.chatPanel:GetHeight()-132-8-(46+4+28+8)
    return math.max(1,math.min(ROWS,math.floor(room/ROW_HEIGHT)))
end
local function placeList()
    local T=Z.Theme;local f=U.quickList;local shown=fit()
    local width=math.min(LIST_WIDTH,U.chatPanel:GetWidth()-20)
    local height=46+shown*ROW_HEIGHT+4+28+8
    T.Place(f,10,math.max(4,U.chatPanel:GetHeight()-132-height-4),width,height,U.chatPanel)
    T.Place(f.searchBox,8,8,width-16,32,f)
    T.Place(f.manage,8,46+shown*ROW_HEIGHT+4,width-16,28,f)
    return width,shown
end
local function refreshList()
    local f=U.quickList
    if not f or not f:IsShown()then return end
    local T=Z.Theme;local P=Z.Phrases
    local list=items()
    local width,shown=placeList()
    offset=math.max(0,math.min(math.max(0,#list-shown),offset))
    f.hint:SetShown(U.quickSearch:GetText()=='')
    for i=1,ROWS do
        local r=f.rows[i];local t=i<=shown and list[offset+i]or nil
        T.Place(r,8,46+(i-1)*ROW_HEIGHT,width-16,ROW_HEIGHT-2,f)
        if not t then r.template=nil;r:Hide()
        else
            r:Show();r.template=t;r.title:SetText(t.name);r.sub:SetText(t.text)
            T.Place(r.title,10,2,width-36,14,r);T.Place(r.sub,10,15,width-36,13,r)
        end
    end
    f.empty:SetShown(#list==0)
    f.empty:SetText(#P.Templates('')==0 and L('Noch keine Schnellantworten.','No quick replies yet.')or L('Keine Schnellantwort gefunden.','No quick reply found.'))
end
local function scroll(_,delta)offset=offset-delta*STEP;refreshList()end
local function buildList()
    if U.quickList then return end
    local T=Z.Theme
    local f=T.Frame(U.chatPanel,'shell','gold');U.quickList=f;f:EnableMouse(true);f:Hide()
    f:SetFrameLevel(U.chatPanel:GetFrameLevel()+40)
    f:EnableMouseWheel(true);f:SetScript('OnMouseWheel',scroll)
    U.quickSearch,f.searchBox=T.Input(f)
    f.hint=T.Text(f.searchBox,L('Vorlage suchen','Search templates'),13,false,'muted');T.Place(f.hint,12,8,200,18,f.searchBox)
    U.quickSearch:SetScript('OnTextChanged',function()offset=0;refreshList()end)
    U.quickSearch:SetScript('OnEscapePressed',function()U.CloseQuick()end)
    U.quickSearch:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
    f.rows={}
    for i=1,ROWS do
        local r=T.Button(f,'',nil,'surface');r.label:Hide();r.quickRow=true
        r.title=T.Text(r,'',12,true,'text');r.title:SetWordWrap(false)
        r.sub=T.Text(r,'',11,false,'muted');r.sub:SetWordWrap(false)
        r:SetScript('OnClick',function(self)if self.template then U.InsertTemplate(self.template.id)end end)
        r:EnableMouseWheel(true);r:SetScript('OnMouseWheel',scroll)
        f.rows[i]=r
    end
    f.empty=T.Text(f,'',12,false,'muted');T.Place(f.empty,18,56,300,20,f)
    f.manage=T.Button(f,L('Vorlagen verwalten …','Manage templates …'),function()
        U.CloseQuick()
        if Z.PhraseUI then pcall(Z.PhraseUI.Open,nil,'templates')end
    end)
end
function U.CloseQuick()
    if not U.quickList then return end
    U.quickSearch:ClearFocus();U.quickList:Hide()
end
function U.ToggleQuick()
    if U.quickList and U.quickList:IsShown()then U.CloseQuick();return end
    if not usable(selected())then return end
    buildList();offset=0
    U.quickSearch:SetText('')
    U.quickList:Show();refreshList();U.quickSearch:SetFocus()
end
-- The input makes room for the button; without a usable conversation it keeps its original place and width.
function U.LayoutQuick()
    if not U.composer or not U.metrics then return end
    local T=Z.Theme;local show=usable(selected())
    if show and not U.quick then
        U.quick=T.Button(U.composer,'',function()U.ToggleQuick()end);T.ButtonIcon(U.quick,T.icons.messages)
        U.quick.tip=L('Schnellantworten','Quick replies')
    end
    local content=U.chatPanel:GetWidth()
    local sendWidth=U.metrics.iconOnly and 38 or 100
    local shift=show and SHIFT or 0
    T.Place(U.inputBackground,10+shift,24,content-sendWidth-38-shift,38,U.composer)
    U.input:SetWidth(content-sendWidth-46-shift)
    T.Place(U.placeholder,12,9,math.max(40,content-sendWidth-70-shift),22,U.inputBackground)
    if U.quick then
        T.Place(U.quick,10,26,34,34,U.composer);U.quick:SetShown(show)
    end
    if not show then U.CloseQuick()end
    if U.quickList and U.quickList:IsShown()then refreshList()end
end
-- Puts the filled template into the draft of the selected conversation at the cursor. Never sends.
function U.InsertTemplate(id)
    local P=Z.Phrases;local c=selected()
    local t=P and P.GetTemplate(id)
    if not t or not usable(c)then return false end
    if not(U.frame and U.frame:IsShown())then U.Open()end
    local text,unresolved=P.Fill(t.text,P.Context(c))
    U.input:Insert(text);U.input:SetFocus()
    P.TouchTemplate(id);U.CloseQuick()
    if#unresolved>0 then U.Notice(L('Platzhalter ohne Wert bleiben im Text.','Placeholders without a value stay in the text.'))end
    return true
end
