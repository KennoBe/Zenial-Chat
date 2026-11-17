-- Page "Schnellantworten" of the Vorlagen popup: list, search, categories and the editor for text templates.
-- Nothing here sends. "Übernehmen" asks the chat window (Z.UI.InsertTemplate) to put the text into the draft.
local _,Z=...
local V=Z.PhraseUI
if not V or not V.RegisterPage then return end -- popup missing in a client that was updated without a restart
local WIDTH,HEIGHT=520,574
local ROW_HEIGHT,MAX_ROWS,STEP=34,8,3
local EDIT_TOP=HEIGHT-216
local PER_ROW,MAX_CATEGORIES=5,9
local pg,rows,catButtons,items,offset,selectedId,filter,errorText,confirmId,updating,visibleRows
local function T()return Z.ChatTheme end
local function L(de,en)return Z.L(de,en)end
local errorTexts={
    empty=function()return L('Text fehlt.','Text is missing.')end,
    invalid_chars=function()return L('Das Zeichen | und Steuerzeichen sind nicht erlaubt.','The character | and control characters are not allowed.')end,
    too_long=function()return L('Name, Kategorie oder Text ist zu lang.','Name, category or text is too long.')end,
    limit=function()return L('Zu viele Schnellantworten.','Too many quick replies.')end,
    missing=function()return L('Diese Schnellantwort gibt es nicht mehr.','This quick reply no longer exists.')end,
}
local function describe(code)local e=errorTexts[code];return e and e()or tostring(code)end
-- Entries are {header=text} or {template=table}. A search text or a category gives a flat list.
local function buildItems()
    local P=Z.Phrases
    local query=pg.search:GetText()
    local list={}
    if query~=''or filter then
        for _,t in ipairs(P.Templates(query,filter))do list[#list+1]={template=t}end
        return list
    end
    local favorites,rest={},{}
    for _,t in ipairs(P.Templates(''))do if P.IsFavorite(t.id)then favorites[#favorites+1]=t else rest[#rest+1]=t end end
    if#favorites>0 then
        list[#list+1]={header=L('Favoriten','Favorites')}
        for _,t in ipairs(favorites)do list[#list+1]={template=t}end
        if#rest>0 then list[#list+1]={header=L('Weitere','More')}end
    end
    for _,t in ipairs(rest)do list[#list+1]={template=t}end
    return list
end
local function maxOffset()return math.max(0,#items-(visibleRows or MAX_ROWS))end
local function setOffset(value)offset=math.max(0,math.min(maxOffset(),math.floor(value+.5)));V.Refresh()end
local function loadEditor(t)
    selectedId=t and t.id or nil
    pg.name:SetText(t and t.name or'');pg.category:SetText(t and t.category or'');pg.text:SetText(t and t.text or'')
end
local function choose(id)
    local t=Z.Phrases.GetTemplate(id)
    if not t then return end
    confirmId=nil;errorText=nil;loadEditor(t);V.Refresh()
end
local function save()
    local id,code=Z.Phrases.SaveTemplate(selectedId,pg.name:GetText(),pg.text:GetText(),pg.category:GetText())
    confirmId=nil
    if id then errorText=nil;loadEditor(Z.Phrases.GetTemplate(id))
    else
        errorText=describe(code)
        if code=='missing'then selectedId=nil end
    end
    V.Refresh()
end
local function delete()
    if not selectedId then return end
    if confirmId~=selectedId then confirmId=selectedId;V.Refresh();return end
    Z.Phrases.RemoveTemplate(selectedId)
    confirmId=nil;errorText=nil;loadEditor(nil);V.Refresh()
end
local function new()confirmId=nil;errorText=nil;loadEditor(nil);V.Refresh()end
local function use()
    local U=Z.UI
    if not selectedId or not U or not U.InsertTemplate then return end
    if not pcall(U.InsertTemplate,selectedId)then errorText=L('Einfügen nicht möglich.','Could not insert.');V.Refresh()end
end
local function insert(token)pg.text:Insert(token);pg.text:SetFocus()end
local function counter()
    local n=#pg.text:GetText()
    pg.counter:SetText(n..'/255');pg.counter:SetTextColor(T().Color(n>255 and'red'or'muted'))
end
local function row(index)
    if rows[index]then return rows[index]end
    local theme=T()
    local r=theme.Button(pg.list,'',nil);r.label:Hide()
    r.title=theme.Text(r,'',12,true,'text');r.title:SetWordWrap(false)
    r.sub=theme.Text(r,'',11,false,'muted');r.sub:SetWordWrap(false)
    r.star=theme.Button(r,'',function()
        if r.template then Z.Phrases.ToggleFavorite(r.template.id);V.Refresh()end
    end,'ghost');theme.Glyph(r.star,'star',18)
    r.star.tip=L('Favorit','Favorite')
    r:SetScript('OnClick',function(self)if self.template then choose(self.template.id)end end)
    r:EnableMouseWheel(true);r:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    rows[index]=r;return r
end
local function refresh()
    local theme,P=T(),Z.Phrases
    -- categories: "All" plus the used ones, two rows at most; the rest is reached through the search
    local categories=P.TemplateCategories()
    local known={};for _,c in ipairs(categories)do known[c]=true end
    if filter and not known[filter]then filter=nil end
    local keys={''};for i=1,math.min(#categories,MAX_CATEGORIES)do keys[#keys+1]=categories[i]end
    local cw=math.floor((WIDTH-24-(PER_ROW-1)*6)/PER_ROW)
    for i=1,PER_ROW*2 do
        local b=catButtons[i];local key=keys[i]
        if key then
            if not b then
                b=theme.Chip(pg,'',function(self)filter=self.category~=''and self.category or nil;offset=0;V.Refresh()end)
                catButtons[i]=b
            end
            b.category=key;b.label:SetText(key==''and L('Alle','All')or key)
            theme.Place(b,12+((i-1)%PER_ROW)*(cw+6),40+math.floor((i-1)/PER_ROW)*30,cw,26,pg);b:Show()
            local active=(key==''and filter==nil)or key==filter
            theme.SetActive(b,active)
        elseif b then b:Hide()end
    end
    -- list
    local listTop=40+math.ceil(#keys/PER_ROW)*30+4
    visibleRows=math.min(MAX_ROWS,math.floor((EDIT_TOP-6-listTop)/ROW_HEIGHT))
    theme.Place(pg.list,12,listTop,WIDTH-24-18,visibleRows*ROW_HEIGHT,pg)
    theme.Place(pg.scrollbar,WIDTH-12-14,listTop,14,visibleRows*ROW_HEIGHT,pg)
    items=buildItems()
    offset=math.max(0,math.min(maxOffset(),offset or 0))
    local width=pg.list:GetWidth()
    for i=1,MAX_ROWS do
        local r=row(i);local item=i<=visibleRows and items[offset+i]or nil
        theme.Place(r,0,(i-1)*ROW_HEIGHT,width,ROW_HEIGHT-3,pg.list)
        if not item then r.template=nil;r:Hide()
        else
            r:Show()
            if item.header then
                r.template=nil;r.title:SetText(item.header);r.title:SetTextColor(theme.Color('goldBright'));r.sub:SetText('')
                theme.Place(r.title,10,8,width-20,16,r);r.star:Hide();theme.SetActive(r,false)
            else
                local t=item.template;r.template=t
                r.title:SetText(t.name);r.title:SetTextColor(theme.Color('text'));r.sub:SetText(t.text)
                theme.Place(r.title,10,3,width-56,15,r);theme.Place(r.sub,10,17,width-56,13,r)
                theme.Place(r.star,width-38,3,32,ROW_HEIGHT-9,r);r.star:Show()
                theme.GlyphColor(r.star,P.IsFavorite(t.id)and'goldBright'or'dim')
                theme.SetActive(r,t.id==selectedId)
            end
        end
    end
    updating=true
    pg.scrollbar:SetMinMaxValues(0,maxOffset());pg.scrollbar:SetValue(offset);pg.scrollbar:SetShown(maxOffset()>0)
    updating=false
    pg.empty:SetShown(#items==0)
    pg.empty:SetText(#P.Templates('')==0 and L('Noch keine Schnellantworten.','No quick replies yet.')or L('Keine Schnellantwort gefunden.','No quick reply found.'))
    -- editor
    counter()
    local hasInsert=Z.UI and Z.UI.InsertTemplate~=nil
    pg.use:SetShown(hasInsert);pg.use:SetEnabled(selectedId~=nil)
    pg.delete:SetEnabled(selectedId~=nil)
    pg.delete.label:SetText(confirmId and confirmId==selectedId and L('Wirklich löschen?','Really delete?')or L('Löschen','Delete'))
    pg.error:SetText(errorText or'')
end
local function build(page,width,height)
    local theme=T()
    pg=page;rows={};catButtons={};items={};offset=0
    pg.search=theme.Input(pg)
    theme.Place(pg.search.background,12,4,width-24,30,pg)
    pg.search:SetScript('OnTextChanged',function()offset=0;V.Refresh()end)
    pg.search:SetScript('OnEscapePressed',function()V.Close()end)
    pg.search:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
    pg.list=CreateFrame('Frame',nil,pg);pg.list:SetClipsChildren(true)
    pg.list:EnableMouseWheel(true);pg.list:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    pg.scrollbar=theme.ScrollBar(pg,function(value)if not updating then setOffset(value)end end)
    pg.empty=theme.Text(pg.list,'',12,false,'muted');theme.Place(pg.empty,10,10,width-60,20,pg.list)
    -- editor: Name, Kategorie, Text with counter, token buttons, actions
    local function field(label,y,max)
        local caption=theme.Text(pg,label,12,false,'muted');theme.Place(caption,12,EDIT_TOP+y+7,84,16,pg)
        local edit,background=theme.Input(pg);theme.Place(background,100,EDIT_TOP+y,width-112,28,pg)
        edit:SetMaxLetters(max)
        edit:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
        edit:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
        return edit
    end
    pg.name=field(L('Name','Name'),0,40)
    pg.category=field(L('Kategorie','Category'),34,24)
    pg.text=field(L('Text','Text'),68,Z.Phrases.MAX_TEMPLATE_BYTES)
    pg.text:SetScript('OnTextChanged',counter)
    pg.counter=theme.Text(pg,'',11,false,'muted');theme.Place(pg.counter,12,EDIT_TOP+68+25,84,14,pg)
    local tokens={{L('Gegenüber','Partner'),'{name}'},{L('Ich','Me'),'{me}'},{L('Gebiet','Zone'),'{zone}'},{L('Ziel','Target'),'{target}'}}
    local tw=math.floor((width-112-3*6)/4)
    for i,entry in ipairs(tokens)do
        local b=theme.Button(pg,entry[1],function()insert(entry[2])end)
        theme.Place(b,100+(i-1)*(tw+6),EDIT_TOP+102,tw,26,pg)
    end
    local bw=math.floor((width-24-3*6)/4)
    local function action(index,label,fn,style)
        local b=theme.Button(pg,label,fn,style);theme.Place(b,12+(index-1)*(bw+6),EDIT_TOP+136,bw,28,pg);return b
    end
    pg.use=action(1,L('Übernehmen','Use'),use)
    pg.save=action(2,L('Speichern','Save'),save,'primary')
    pg.delete=action(3,L('Löschen','Delete'),delete,'danger')
    pg.new=action(4,L('Neu','New'),new)
    pg.error=theme.Text(pg,'',11,false,'red');pg.error:SetWordWrap(true);theme.Place(pg.error,12,EDIT_TOP+170,width-24,28,pg)
end
V.RegisterPage('templates',{order=1,label=function()return L('Schnellantworten','Quick replies')end,build=build,refresh=refresh,
    show=function()errorText=nil;confirmId=nil;pg.search:SetFocus()end,
    hide=function()for _,edit in ipairs({pg.search,pg.name,pg.category,pg.text})do edit:ClearFocus()end end})
