-- Page "Gelernte Wörter" of the Vorlagen popup: the own meanings for words of the opposite faction (Z.Interpret).
local _,Z=...
local V=Z.PhraseUI
if not V or not V.RegisterPage then return end -- popup missing in a client that was updated without a restart
local WIDTH,HEIGHT=520,574
local ROWS,ROW_HEIGHT,STEP=8,34,3
local LIST_TOP=76
local EDIT_TOP=HEIGHT-214
local LANGUAGES={1,7}
local names={[1]={'Orcisch','Orcish'},[7]={'Gemeinsprache','Common'}}
local pg,rows,langButtons,items,offset,language,errorText,confirmAll,updating
local function T()return Z.ChatTheme end
local function L(de,en)return Z.L(de,en)end
local function I()return Z.Interpret end
local function invalidate()
    if Z.Transcript and Z.Transcript.Invalidate then pcall(Z.Transcript.Invalidate)end
end
local function opposite()
    local faction=Z.adapter and Z.adapter.me and Z.adapter.me.faction
    if faction=='Horde'then return 7 elseif faction=='Alliance'then return 1 end
end
-- The language with entries (the current one first), otherwise the language of the other faction, otherwise Orcish.
local function pick()
    local first=opposite()or 1
    local order={language or first}
    for _,id in ipairs({first,1,7})do if id~=order[1]then order[#order+1]=id end end
    for _,id in ipairs(order)do if I().CountLearned(id)>0 then return id end end
    return language or first
end
local function maxOffset()return math.max(0,#items-ROWS)end
local function setOffset(value)offset=math.max(0,math.min(maxOffset(),math.floor(value+.5)));V.Refresh()end
local function clearFields()pg.word:SetText('');pg.meaning:SetText('')end
local function setLanguage(id)
    language=id;confirmAll=nil;errorText=nil;offset=0;V.Refresh()
end
local function choose(entry)
    confirmAll=nil;errorText=nil;pg.word:SetText(entry.key);pg.meaning:SetText(entry.meaning);V.Refresh()
end
local function save()
    confirmAll=nil
    local word,meaning=pg.word:GetText(),pg.meaning:GetText()
    local ok,err=I().Learn(language,word,meaning)
    if ok then
        errorText=nil;pg.word:SetText(I().Key((word:gsub('^%s+',''):gsub('%s+$',''))));invalidate()
    elseif err=='limit'then errorText=L('Zu viele eigene Bedeutungen für diese Sprache. Vergiss zuerst einige.','Too many own meanings for this language. Forget some first.')
    else errorText=L('Ungültige Bedeutung: höchstens 64 Zeichen, keine Steuerzeichen und kein senkrechter Strich.','Invalid meaning: at most 64 characters, no control characters and no vertical bar.')end
    V.Refresh()
end
local function forget()
    confirmAll=nil;errorText=nil
    if I().Forget(language,pg.word:GetText())then invalidate();clearFields()end
    V.Refresh()
end
local function forgetAll()
    errorText=nil
    if not confirmAll then confirmAll=true;V.Refresh();return end
    confirmAll=nil;I().ForgetAll(language);invalidate();clearFields();V.Refresh()
end
local function row(index)
    if rows[index]then return rows[index]end
    local theme=T()
    local r=theme.Button(pg.list,'',nil);r.label:Hide()
    r.title=theme.Text(r,'',12,true,'text');r.title:SetWordWrap(false)
    r.sub=theme.Text(r,'',11,false,'muted');r.sub:SetWordWrap(false)
    r:SetScript('OnClick',function(self)if self.entry then choose(self.entry)end end)
    r:EnableMouseWheel(true);r:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    rows[index]=r;return r
end
local function refresh()
    local theme=T()
    language=language or pick()
    for i,id in ipairs(LANGUAGES)do
        local b=langButtons[id]
        b.label:SetText(L(names[id][1],names[id][2])..' · '..I().CountLearned(id))
        local active=id==language
        theme.SetActive(b,active)
    end
    items=I().Learned(language,pg.search:GetText())
    offset=math.max(0,math.min(maxOffset(),offset or 0))
    local width=pg.list:GetWidth()
    for i=1,ROWS do
        local r=row(i);local entry=items[offset+i]
        theme.Place(r,0,(i-1)*ROW_HEIGHT,width,ROW_HEIGHT-3,pg.list)
        if not entry then r.entry=nil;r:Hide()
        else
            r:Show();r.entry=entry
            -- A word may contain a pipe (it comes from chat or from the field): shown as text, never as markup.
            r.title:SetText((entry.key:gsub('|','||')));r.sub:SetText((entry.meaning:gsub('|','||')))
            theme.Place(r.title,10,3,width-20,15,r);theme.Place(r.sub,10,17,width-20,13,r)
            theme.SetActive(r,entry.key==I().Key(pg.word:GetText()))
        end
    end
    updating=true
    pg.scrollbar:SetMinMaxValues(0,maxOffset());pg.scrollbar:SetValue(offset);pg.scrollbar:SetShown(maxOffset()>0)
    updating=false
    local count=I().CountLearned(language)
    pg.empty:SetShown(#items==0)
    pg.empty:SetText(count==0 and L('Noch keine Wörter gelernt.','No words learned yet.')or L('Kein Wort gefunden.','No word found.'))
    pg.count:SetText(string.format(L('%d von %d','%d of %d'),count,I().MAX_LEARNED))
    pg.forgetAll.label:SetText(confirmAll and L('Wirklich alle vergessen?','Really forget all?')or L('Alle vergessen …','Forget all …'))
    pg.forgetAll:SetEnabled(count>0)
    pg.error:SetText(errorText or'')
end
local function build(page,width)
    local theme=T()
    pg=page;rows={};langButtons={};items={};offset=0
    local lw=math.floor((width-24-6)/2)
    for i,id in ipairs(LANGUAGES)do
        local b=theme.Chip(pg,'',function()setLanguage(id)end)
        theme.Place(b,12+(i-1)*(lw+6),4,lw,28,pg);langButtons[id]=b
    end
    pg.search=theme.Input(pg)
    theme.Place(pg.search.background,12,40,width-24,30,pg)
    pg.search:SetScript('OnTextChanged',function()offset=0;confirmAll=nil;V.Refresh()end)
    pg.search:SetScript('OnEscapePressed',function()V.Close()end)
    pg.search:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
    pg.list=CreateFrame('Frame',nil,pg);pg.list:SetClipsChildren(true)
    theme.Place(pg.list,12,LIST_TOP,width-24-18,ROWS*ROW_HEIGHT,pg)
    pg.list:EnableMouseWheel(true);pg.list:SetScript('OnMouseWheel',function(_,delta)setOffset(offset-delta*STEP)end)
    pg.scrollbar=theme.ScrollBar(pg,function(value)if not updating then setOffset(value)end end)
    theme.Place(pg.scrollbar,width-12-14,LIST_TOP,14,ROWS*ROW_HEIGHT,pg)
    pg.empty=theme.Text(pg.list,'',12,false,'muted');theme.Place(pg.empty,10,10,width-60,20,pg.list)
    local function field(label,y)
        local caption=theme.Text(pg,label,12,false,'muted');theme.Place(caption,12,EDIT_TOP+y+7,84,16,pg)
        local edit,background=theme.Input(pg);theme.Place(background,100,EDIT_TOP+y,width-112,28,pg)
        edit:SetMaxLetters(64)
        edit:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
        edit:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
        return edit
    end
    pg.word=field(L('Wort','Word'),0)
    pg.meaning=field(L('Bedeutung','Meaning'),34)
    local bw=math.floor((width-24-12)/3)
    local function action(index,label,fn,style)
        local b=theme.Button(pg,label,fn,style);theme.Place(b,12+(index-1)*(bw+6),EDIT_TOP+72,bw,28,pg);return b
    end
    action(1,L('Speichern','Save'),save,'primary')
    action(2,L('Vergessen','Forget'),forget,'danger')
    pg.forgetAll=action(3,'',forgetAll,'danger')
    pg.error=theme.Text(pg,'',11,false,'red');pg.error:SetWordWrap(true);theme.Place(pg.error,12,EDIT_TOP+108,width-24,28,pg)
    pg.count=theme.Text(pg,'',11,false,'muted');theme.Place(pg.count,12,EDIT_TOP+142,width-24,14,pg)
end
V.RegisterPage('words',{order=3,label=function()return L('Gelernte Wörter','Learned words')end,build=build,refresh=refresh,
    show=function()language=pick();errorText=nil;confirmAll=nil;offset=0;pg.search:SetFocus()end,
    hide=function()for _,edit in ipairs({pg.search,pg.word,pg.meaning})do edit:ClearFocus()end end})
