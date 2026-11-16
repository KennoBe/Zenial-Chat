-- Popup "Vorlagen" with pages (tabs). Page xf: spelled phrases to the other faction: search, pick, preview, then Say or Yell on click.
-- Other files add pages with V.RegisterPage. The popup never changes the selected conversation and never sends by itself.
local _,Z=...
local V={};Z.PhraseUI=V
local WIDTH,PAGE_HEIGHT=520,574
local TOP,TAB_HEIGHT=36,32 -- title strip; tab bar (only with several pages)
local ROWS,ROW_HEIGHT=10,34
local LIST_TOP=104
local STEP=3 -- list entries per mouse wheel notch
local f,rows,items,offset,selectedId,category,preferred,errorText,updating,editing
local pages,frames={},{} -- spec and page frame per page id
local function T()return Z.Theme end
local function L(de,en)return Z.L(de,en)end
local function tableAndStatus()
    local C,K,G=Z.PhraseCodec,Z.Calibration,Z.GarbleMap
    local build=G and G.CurrentBuild and G.CurrentBuild()or nil
    local id=K and K.OwnLanguageId and K.OwnLanguageId()or nil
    local tbl=C.Pick(id,build)
    local status=C.Status(tbl,build)
    return tbl,status,id
end
local errorTexts={
    empty=function()return L('Keine Phrase gewählt.','No phrase selected.')end,
    no_table=function()return L('Keine Zeichentabelle für deine Sprache.','No character table for your language.')end,
    invalid_chars=function()return L('Nur die Buchstaben A–Z und Leerzeichen sind erlaubt.','Only the letters A-Z and spaces are allowed.')end,
    too_long=function()return L('Die buchstabierte Phrase ist zu lang.','The spelled phrase is too long.')end,
    invalid_table=function()return L('Die Zeichentabelle enthält ungültige Zeichen. Kalibriere neu oder importiere einen anderen Code.','The character table contains invalid characters. Calibrate again or import another code.')end,
    limit=function()return L('Zu viele eigene Vorlagen.','Too many own templates.')end,
    missing=function()return L('Diese Vorlage gibt es nicht mehr.','This template no longer exists.')end,
    all_missing=function()return L('Alle Buchstaben fehlen in der Zeichentabelle, es wird nichts gesendet.','All letters are missing from the character table; nothing is sent.')end,
}
local function describe(code)local e=errorTexts[code];return e and e()or tostring(code)end
-- Entries are {header=text} or {phrase=table}. Search text or a category gives a flat list.
local function buildItems()
    local P=Z.Phrases
    local query=f and f.input and f.input:GetText()or''
    local list={}
    if query~=''or category then
        for _,phrase in ipairs(P.List(query,category))do list[#list+1]={phrase=phrase}end
        return list
    end
    local shown={}
    local function section(title,phrases)
        local fresh={}
        for _,phrase in ipairs(phrases)do if not shown[phrase.id]then shown[phrase.id]=true;fresh[#fresh+1]=phrase end end
        if#fresh==0 then return end
        list[#list+1]={header=title}
        for _,phrase in ipairs(fresh)do list[#list+1]={phrase=phrase}end
    end
    local all=P.List('')
    local favorites={}
    for _,phrase in ipairs(all)do if P.IsFavorite(phrase.id)then favorites[#favorites+1]=phrase end end
    section(L('Favoriten','Favorites'),favorites)
    section(L('Zuletzt verwendet','Recently used'),P.Recent())
    section(L('Eigene Vorlagen','Own templates'),P.List('','custom'))
    section(#list>0 and L('Weitere Phrasen','More phrases')or L('Alle Phrasen','All phrases'),all)
    return list
end
local function maxOffset()return math.max(0,#items-ROWS)end
local function setOffset(value)
    offset=math.max(0,math.min(maxOffset(),math.floor(value+.5)));V.Refresh()
end
local function selectPhrase(id)
    selectedId=id;errorText=nil;V.Refresh()
end
local function removeCustom(id)
    local U=Z.UI;if not U or not U.Build then return end
    local ok=pcall(function()
        U.Open()
        U.Confirm(L('Diese eigene Vorlage entfernen?','Remove this own template?'),function()
            Z.Phrases.RemoveCustom(id)
            if selectedId==id then selectedId=nil end
            V.Refresh()
        end)
    end)
    if not ok then errorText=L('Die Abfrage konnte nicht geöffnet werden.','The confirmation could not be opened.');V.Refresh()end
end
-- Own phrases are created and changed in two fields inside the popup (editing={id=nil|own id}).
local function startEdit(id)
    local phrase=id and Z.Phrases.Get(id)or nil
    editing={id=phrase and id or nil};errorText=nil
    f.editEn:SetText(phrase and phrase.en or'');f.editDe:SetText(phrase and phrase.de or'')
    V.Refresh();f.editEn:SetFocus()
end
local function stopEdit()
    editing=nil;errorText=nil;f.editEn:ClearFocus();f.editDe:ClearFocus();V.Refresh()
end
local function saveEdit()
    if not editing then return end
    local P=Z.Phrases;local en,de=f.editEn:GetText(),f.editDe:GetText()
    local id,code
    if editing.id then id,code=P.UpdateCustom(editing.id,de,en);if id then id=editing.id end
    else id,code=P.AddCustom(de,en)end
    if id then selectedId=id;editing=nil;errorText=nil;f.editEn:ClearFocus();f.editDe:ClearFocus()
    else errorText=describe(code)end
    V.Refresh()
end
local function row(index)
    if rows[index]then return rows[index]end
    local theme=T()
    local r=theme.Button(f.list,'',nil,'surface');r.label:Hide()
    r.title=theme.Text(r,'',12,true,'text');r.title:SetWordWrap(false)
    r.sub=theme.Text(r,'',11,false,'muted');r.sub:SetWordWrap(false)
    r.star=theme.Button(r,'☆',function()
        if r.phrase then Z.Phrases.ToggleFavorite(r.phrase.id);V.Refresh()end
    end)
    r.star.tip=L('Favorit','Favorite')
    r.edit=theme.Button(r,L('Ändern','Edit'),function()if r.phrase then startEdit(r.phrase.id)end end)
    if r.RegisterForClicks then r:RegisterForClicks('LeftButtonUp','RightButtonUp')end
    r:SetScript('OnClick',function(self,button)
        local phrase=self.phrase;if not phrase then return end
        if button=='RightButton'then
            if phrase.category=='custom'then removeCustom(phrase.id)end
        else selectPhrase(phrase.id)end
    end)
    r:EnableMouseWheel(true);r:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    rows[index]=r;return r
end
local function sendLabel(base,status)
    if status=='outdated'then return base..' '..L('(unzuverlässig)','(unreliable)')end
    return base
end
local function refreshXf()
    local theme=T();local P=Z.Phrases
    items=buildItems()
    offset=math.max(0,math.min(maxOffset(),offset or 0))
    local width=f.list:GetWidth()
    for i=1,ROWS do
        local r=row(i);local item=items[offset+i]
        theme.Place(r,0,(i-1)*ROW_HEIGHT,width,ROW_HEIGHT-3,f.list)
        if not item then r.phrase=nil;r:Hide()
        else
            r:Show()
            if item.header then
                r.phrase=nil;r.title:SetText(item.header);r.title:SetTextColor(theme.Color('goldBright'));r.sub:SetText('');r.edit:Hide()
                theme.Place(r.title,10,8,width-20,16,r);r.star:Hide()
                r:SetBackdropBorderColor(theme.Color('line'))
            else
                local phrase=item.phrase;r.phrase=phrase
                r.title:SetText(phrase.de);r.title:SetTextColor(theme.Color('text'));r.sub:SetText(phrase.en)
                local own=phrase.category=='custom'
                theme.Place(r.title,10,3,width-(own and 126 or 56),15,r);theme.Place(r.sub,10,17,width-(own and 126 or 56),13,r)
                theme.Place(r.edit,width-108,3,66,ROW_HEIGHT-9,r);r.edit:SetShown(own)
                theme.Place(r.star,width-38,3,32,ROW_HEIGHT-9,r);r.star:Show()
                r.star.label:SetText(P.IsFavorite(phrase.id)and'★'or'☆')
                r:SetBackdropBorderColor(theme.Color(phrase.id==selectedId and'gold'or'border'))
            end
        end
    end
    updating=true
    f.scrollbar:SetMinMaxValues(0,maxOffset());f.scrollbar:SetValue(offset)
    f.scrollbar:SetShown(maxOffset()>0)
    updating=false
    f.empty:SetShown(#items==0);f.empty:SetText(L('Keine Phrase gefunden.','No phrase found.'))
    for key,button in pairs(f.categories)do
        local active=(key==''and category==nil)or key==category
        button.label:SetTextColor(theme.Color(active and'goldBright'or'text'))
        button:SetBackdropBorderColor(theme.Color(active and'gold'or'border'))
    end
    -- Status of the character table, preview and warnings.
    local tbl,status,languageId=tableAndStatus()
    local K=Z.Calibration
    f.status:SetText(K and K.StatusText and(K.StatusText(languageId))or'')
    local phrase=selectedId and P.Get(selectedId)or nil
    local preview,warning=nil,nil
    if status=='missing'then
        warning=L('Keine Zeichentabelle für deine Sprache. Ohne Kalibrierung ist nicht bekannt, was der Empfänger liest. Die Kalibrierung findest du in den Einstellungen.',
            'No character table for your language. Without calibration it is unknown what the receiver reads. You find the calibration in the settings.')
    elseif not phrase then
        preview=L('Wähle eine Phrase aus der Liste.','Pick a phrase from the list.')
    else
        local best,code=P.Best(phrase,tbl)
        if not best then preview=describe(code)
        else
            preview=L('Der Empfänger liest: ','The receiver reads: ')..best.preview
            if#best.missing>0 then preview=preview..'\n'..L('Diese Buchstaben fehlen: ','These letters are missing: ')..table.concat(best.missing,', ')end
        end
        if status=='outdated'then
            warning=L('Die Zeichentabelle ist für einen anderen Client-Build. Die Vorschau ist unzuverlässig.','The character table is for another client build. The preview is unreliable.')
        end
    end
    f.preview:SetText(preview or'')
    f.warning:SetText(warning or'')
    f.error:SetText(errorText or'')
    local enabled=status~='missing'
    f.say.label:SetText(sendLabel(L('Sagen','Say'),status));f.yell.label:SetText(sendLabel(L('Schreien','Yell'),status))
    f.say:SetEnabled(enabled);f.yell:SetEnabled(enabled)
    for _,button in ipairs({f.say,f.yell})do
        local mark=preferred==button.channel
        button.label:SetTextColor(theme.Color(not enabled and'muted'or mark and'goldBright'or'text'))
        button:SetBackdropBorderColor(theme.Color(mark and'gold'or'border'))
    end
    local edit=editing~=nil
    for _,w in ipairs({f.status,f.preview,f.warning,f.say,f.yell,f.custom})do w:SetShown(not edit)end
    for _,w in ipairs({f.editEnBg,f.editDeBg,f.editEnLabel,f.editDeLabel,f.editSave,f.editCancel})do w:SetShown(edit)end
end
-- Runs inside the click handler of the button: one synchronous call, no retry.
local function send(channel)
    local P=Z.Phrases
    local phrase=selectedId and P.Get(selectedId)or nil
    if not phrase then errorText=describe('empty');V.Refresh();return end
    local tbl,status=tableAndStatus()
    if status=='missing'then errorText=describe('no_table');V.Refresh();return end
    local best,code=P.Best(phrase,tbl)
    if not best then errorText=describe(code);V.Refresh();return end
    if type(best.text)~='string'or best.text==''then errorText=describe('all_missing');V.Refresh();return end
    local call=(C_ChatInfo and C_ChatInfo.SendChatMessage)or SendChatMessage
    if type(call)~='function'then errorText=L('Senden ist in diesem Client nicht verfügbar.','Sending is not available in this client.');V.Refresh();return end
    local ok,err=pcall(call,best.text,channel)
    if not ok then
        errorText=L('Senden fehlgeschlagen: ','Sending failed: ')..(Z.Safe(err)and tostring(err)or'?');V.Refresh();return
    end
    errorText=nil;P.Touch(phrase.id);V.Refresh()
end
local function buildXf(page,width,height)
    local theme=T()
    rows={};items={};offset=0
    f.input,f.inputBackground=theme.Input(page);theme.Place(f.inputBackground,12,4,width-24,30,page)
    f.input:SetScript('OnTextChanged',function()offset=0;V.Refresh()end)
    f.input:SetScript('OnEscapePressed',function()V.Close()end)
    f.input:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
    -- Category bar: "All" plus the built-in categories, two rows.
    f.categories={}
    local keys={''};for _,key in ipairs(Z.PhraseData.categories)do keys[#keys+1]=key end
    local perRow=4;local cw=math.floor((width-24-(perRow-1)*6)/perRow)
    for i,key in ipairs(keys)do
        local b=theme.Button(page,key==''and L('Alle','All')or Z.Phrases.CategoryLabel(key),function()
            category=key~=''and key or nil;offset=0;V.Refresh()
        end)
        local col,line=(i-1)%perRow,math.floor((i-1)/perRow)
        theme.Place(b,12+col*(cw+6),40+line*30,cw,26,page);f.categories[key]=b
    end
    f.list=CreateFrame('Frame',nil,page);f.list:SetClipsChildren(true)
    theme.Place(f.list,12,LIST_TOP,width-24-18,ROWS*ROW_HEIGHT,page)
    f.list:EnableMouseWheel(true);f.list:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    f.scrollbar=CreateFrame('Slider',nil,page,'BackdropTemplate');theme.Panel(f.scrollbar,'field','line')
    f.scrollbar:SetOrientation('VERTICAL');f.scrollbar:SetValueStep(1);f.scrollbar:SetThumbTexture('Interface\\Buttons\\UI-ScrollBar-Knob')
    theme.Place(f.scrollbar,width-12-14,LIST_TOP,14,ROWS*ROW_HEIGHT,page)
    f.scrollbar:SetScript('OnValueChanged',function(_,value)if not updating then setOffset(value)end end)
    f.empty=theme.Text(f.list,'',12,false,'muted');theme.Place(f.empty,10,10,width-60,20,f.list)
    local y=LIST_TOP+ROWS*ROW_HEIGHT+6
    f.status=theme.Text(page,'',11,false,'muted');f.status:SetWordWrap(false);theme.Place(f.status,12,y,width-24,14,page)
    f.preview=theme.Text(page,'',13,false,'text');f.preview:SetWordWrap(true);theme.Place(f.preview,12,y+18,width-24,34,page)
    f.warning=theme.Text(page,'',11,false,'goldBright');f.warning:SetWordWrap(true);theme.Place(f.warning,12,y+54,width-24,30,page)
    f.error=theme.Text(page,'',11,false,'red');f.error:SetWordWrap(true);theme.Place(f.error,12,y+86,width-24,28,page)
    local by=height-40
    f.say=theme.Button(page,'',function()send('SAY')end);f.say.channel='SAY';theme.Place(f.say,12,by,170,28,page)
    f.yell=theme.Button(page,'',function()send('YELL')end);f.yell.channel='YELL';theme.Place(f.yell,190,by,170,28,page)
    f.custom=theme.Button(page,L('Eigene Vorlage …','Own template …'),function()startEdit(nil)end);theme.Place(f.custom,368,by,width-12-368,28,page)
    -- editor of an own phrase: phrase (A-Z) and description, in place of preview and send buttons
    local function field(label,y)
        local caption=theme.Text(page,label,12,false,'muted');theme.Place(caption,12,y+7,104,16,page)
        local edit,background=theme.Input(page);theme.Place(background,120,y,width-132,28,page)
        edit:SetScript('OnEscapePressed',stopEdit);edit:SetScript('OnEnterPressed',saveEdit)
        return edit,background,caption
    end
    f.editEn,f.editEnBg,f.editEnLabel=field(L('Phrase A–Z','Phrase A-Z'),y)
    f.editDe,f.editDeBg,f.editDeLabel=field(L('Beschreibung','Description'),y+34)
    f.editSave=theme.Button(page,L('Speichern','Save'),saveEdit);theme.Place(f.editSave,12,by,170,28,page)
    f.editCancel=theme.Button(page,L('Abbrechen','Cancel'),stopEdit);theme.Place(f.editCancel,190,by,170,28,page)
    page.editEn,page.editDe=f.editEn,f.editDe
    -- ESC closes the popup through the search field (OnEscapePressed) or the close button. The frame itself takes
    -- no keyboard input: a keyboard-enabled frame would swallow movement keys or need protected calls in combat.
end
local function ordered()
    local list={};for id,spec in pairs(pages)do list[#list+1]={id=id,spec=spec}end
    table.sort(list,function(a,b)if a.spec.order~=b.spec.order then return a.spec.order<b.spec.order end;return a.id<b.id end)
    return list
end
-- Window size, tab bar (only with more than one page) and page frames.
local function layout()
    local theme=T();local list=ordered();local tabs=#list>1
    local top=TOP+(tabs and TAB_HEIGHT or 0)
    f:SetSize(WIDTH,top+PAGE_HEIGHT)
    local width=math.floor((WIDTH-24-(#list-1)*6)/math.max(1,#list))
    for i,entry in ipairs(list)do
        local b=f.tabs[entry.id]
        if not b then local id=entry.id;b=theme.Button(f,'',function()V.SetPage(id)end);f.tabs[id]=b end
        theme.Place(b,12+(i-1)*(width+6),TOP,width,26,f)
        b.label:SetText(entry.spec.label());b:SetShown(tabs)
        local active=entry.id==V.page and tabs
        b.label:SetTextColor(theme.Color(active and'goldBright'or'text'));b:SetBackdropBorderColor(theme.Color(active and'gold'or'border'))
    end
    for _,page in pairs(frames)do theme.Place(page,0,top,WIDTH,PAGE_HEIGHT,f)end
end
local function build()
    if f then return end
    local theme=T()
    f=theme.Frame(UIParent,'shell','gold');f:SetFrameStrata('HIGH');f:SetSize(WIDTH,TOP+PAGE_HEIGHT);f:SetPoint('CENTER');f:EnableMouse(true)
    f:SetClampedToScreen(true);f:Hide()
    f.tabs={}
    f.title=theme.Text(f,L('Vorlagen','Templates'),14,true);f.title:SetPoint('TOPLEFT',12,-12)
    f.close=Z.CloseButton(f,function()V.Close()end,L('Schließen','Close'));theme.Place(f.close,WIDTH-38,7,28,26,f)
end
-- Pages: spec={order=,label=function()->string,build=function(page,width,height),refresh=function(page),
-- show=function(page) (optional, the page became the shown one), hide=function(page) (optional, release the keyboard)}.
-- build runs once, on the first time the page is shown; page is an own frame below the tab bar.
function V.RegisterPage(id,spec)
    if type(id)~='string'or type(spec)~='table'or type(spec.build)~='function'or type(spec.refresh)~='function'or type(spec.label)~='function'then return false end
    spec.order=tonumber(spec.order)or 100
    pages[id]=spec
    if f and f:IsShown()then layout()end
    return true
end
function V.Page(id)return frames[id]end
local function release()
    local spec,page=pages[V.page],frames[V.page]
    if spec and page and spec.hide then pcall(spec.hide,page)end
end
function V.SetPage(id)
    if not f or not pages[id]then return false end
    if V.page~=id then release()end
    for other,frame in pairs(frames)do if other~=id then frame:Hide()end end
    V.page=id
    local page=frames[id]
    if not page then page=CreateFrame('Frame',nil,f);frames[id]=page;pages[id].build(page,WIDTH,PAGE_HEIGHT)end
    page:Show();layout()
    if f:IsShown()then
        if pages[id].show then pages[id].show(page)end
        pages[id].refresh(page)
    end
    return true
end
function V.Refresh()
    if not f or not f:IsShown()then return end
    local spec,page=pages[V.page],frames[V.page]
    if spec and page then spec.refresh(page)end
end
V.RegisterPage('xf',{order=2,label=function()return L('Gegenfraktion','Other faction')end,build=buildXf,refresh=refreshXf,
    show=function()if f.input then f.input:SetFocus()end end,hide=function()editing=nil;if f.input then f.input:ClearFocus();f.editEn:ClearFocus();f.editDe:ClearFocus()end end})
-- channel: 'SAY' | 'YELL' | nil marks the preferred send button. Nothing is sent here.
-- pageId: a registered page; nil (or unknown) opens xf.
function V.Open(channel,pageId)
    if not Z.ready and Z.Initialize then Z.Initialize()end
    build()
    preferred=(channel=='SAY'or channel=='YELL')and channel or nil
    errorText=nil;offset=0;f:Show()
    V.SetPage(pages[pageId]and pageId or'xf')
end
function V.Close()
    if not f then return end
    release();f:Hide()
end
function V.IsShown()return f~=nil and f:IsShown()end
