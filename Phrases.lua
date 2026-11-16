-- Phrase list, favorites, recent use and own templates. State lives in ZenialChatDB.phrases (created on first use).
local _,Z=...
local P={};Z.Phrases=P
P.MAX_RECENT=10
P.MAX_CUSTOM=50
P.MAX_TEMPLATES=200
P.MAX_TEMPLATE_BYTES=500
local labels={
    greetings={'Begrüßung','Greetings'},help={'Hilfe','Help'},quest={'Quests','Quests'},pvp={'PvP','PvP'},
    trade={'Handel','Trade'},roleplay={'Rollenspiel','Roleplay'},misc={'Sonstiges','Misc'},custom={'Eigene','Custom'},
}
local fallback -- used when no saved-variables root exists, so calls never fail
local function chars(text)return(select(2,text:gsub('[^\128-\191]','')))end
local function clip(text,n) -- the first n characters, never cutting inside a multi-byte character
    local count,i=0,1
    while i<=#text do
        local b=text:byte(i);count=count+1
        if count>n then return text:sub(1,i-1)end
        i=i+(b>=240 and 4 or b>=224 and 3 or b>=192 and 2 or 1)
    end
    return text
end
local function plain(text)return type(text)=='string'and not text:find('[|%c]')end
-- Damaged quick replies are dropped on access: entries without string id and text, duplicates, unsafe characters.
local checkedList,checkedRecent,checkedCount -- what was last found sound; lists changed elsewhere are checked again
local function repairTemplates(s)
    if s.templates==checkedList and s.templateRecent==checkedRecent and type(checkedList)=='table'and#checkedList==checkedCount then return end
    local list,clean,seen=s.templates,{},{}
    if type(list)=='table'then
        for _,t in ipairs(list)do
            if type(t)=='table'and type(t.id)=='string'and t.id~=''and not seen[t.id]and plain(t.text)then
                if not plain(t.name)then t.name=clip(t.text,30)end
                if t.category~=nil and(not plain(t.category)or t.category=='')then t.category=nil end
                seen[t.id]=true;clean[#clean+1]=t
            end
        end
    end
    if type(list)~='table'or#clean~=#list then s.templates=clean end
    local recent,out,used=s.templateRecent,{},{}
    if type(recent)=='table'then
        for _,id in ipairs(recent)do
            if type(id)=='string'and seen[id]and not used[id]and#out<P.MAX_RECENT then used[id]=true;out[#out+1]=id end
        end
    end
    if type(recent)~='table'or#out~=#recent then s.templateRecent=out end
    checkedList,checkedRecent,checkedCount=s.templates,s.templateRecent,#s.templates
end
local function state()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    if type(db)~='table'then fallback=fallback or{};db=fallback end
    local s=db.phrases
    if type(s)~='table'then s={};db.phrases=s end
    if type(s.favorites)~='table'then s.favorites={}end
    if type(s.recent)~='table'then s.recent={}end
    if type(s.custom)~='table'then s.custom={}end
    repairTemplates(s)
    return s
end
function P.CategoryLabel(category)
    local l=labels[category];return l and Z.L(l[1],l[2])or tostring(category)
end
local function fold(text)
    -- Umlauts first: some C runtimes lower-case the lead byte of a multi-byte character.
    text=tostring(text or''):gsub('ä','a'):gsub('Ä','a'):gsub('ö','o'):gsub('Ö','o'):gsub('ü','u'):gsub('Ü','u'):gsub('ß','ss')
    return(text:lower())
end
local function find(id)
    for _,phrase in ipairs(Z.PhraseData.list)do if phrase.id==id then return phrase end end
    for _,phrase in ipairs(state().custom)do if phrase.id==id then return phrase end end
end
local function findTemplate(id)
    if type(id)~='string'then return nil end
    for _,t in ipairs(state().templates)do if t.id==id then return t end end
end
function P.Get(id)return find(id)end
function P.IsFavorite(id)return state().favorites[id]==true end
-- Every query term must occur in the German description, the English phrase or one of the alternatives.
function P.List(query,category)
    local terms={};for term in fold(query):gmatch('%S+')do terms[#terms+1]=term end
    if category==''then category=nil end
    local result={}
    local function consider(phrase)
        if category and phrase.category~=category then return end
        if #terms>0 then
            local hay={fold(phrase.de),fold(phrase.en)};for _,a in ipairs(phrase.alt or{})do hay[#hay+1]=fold(a)end
            hay=table.concat(hay,'\n')
            for _,term in ipairs(terms)do if not hay:find(term,1,true)then return end end
        end
        result[#result+1]=phrase
    end
    for _,phrase in ipairs(Z.PhraseData.list)do consider(phrase)end
    for _,phrase in ipairs(state().custom)do consider(phrase)end
    return result
end
-- First version (en, then alt) without missing letters, otherwise the one with the fewest gaps.
function P.Best(phrase,tbl)
    if type(phrase)~='table'then return nil,'empty'end
    local candidates={phrase.en};for _,a in ipairs(phrase.alt or{})do candidates[#candidates+1]=a end
    local best,code
    for _,text in ipairs(candidates)do
        local encoded,err=Z.PhraseCodec.Encode(text,tbl)
        if encoded then
            if not best or#encoded.missing<#best.missing then best=encoded end
            if#encoded.missing==0 then break end
        else code=code or err end
    end
    if not best then return nil,code or'empty'end
    return{text=best.text,preview=best.preview,missing=best.missing}
end
function P.ToggleFavorite(id)
    if not find(id)and not findTemplate(id)then return nil end
    local f=state().favorites
    if f[id]then f[id]=nil;return false end
    f[id]=true;return true
end
function P.Touch(id)
    if not find(id)then return false end
    local recent=state().recent
    for i=#recent,1,-1 do if recent[i]==id then table.remove(recent,i)end end
    table.insert(recent,1,id)
    while#recent>P.MAX_RECENT do table.remove(recent)end
    return true
end
function P.AddCustom(de,en)
    if type(en)~='string'then return nil,'empty'end
    en=en:upper():gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    if en==''then return nil,'empty'end
    if en:find('[^A-Z ]')then return nil,'invalid_chars'end
    local custom=state().custom
    if#custom>=P.MAX_CUSTOM then return nil,'limit'end
    local top=0
    for _,phrase in ipairs(custom)do top=math.max(top,tonumber(phrase.id:match('^custom_(%d+)$'))or 0)end
    local id='custom_'..(top+1)
    if type(de)~='string'or de:match('^%s*$')then de=en end
    custom[#custom+1]={id=id,category='custom',de=de,en=en,alt={}}
    return id
end
function P.RemoveCustom(id)
    local s=state()
    for i,phrase in ipairs(s.custom)do
        if phrase.id==id then
            table.remove(s.custom,i);s.favorites[id]=nil
            for j=#s.recent,1,-1 do if s.recent[j]==id then table.remove(s.recent,j)end end
            return true
        end
    end
    return false
end
function P.Recent()
    local result={}
    for _,id in ipairs(state().recent)do local phrase=find(id);if phrase then result[#result+1]=phrase end end
    return result
end
-- Quick replies: text templates that are only ever inserted into the draft, never sent from here.
function P.GetTemplate(id)return findTemplate(id)end
function P.Templates(query,category)
    local terms={};for term in fold(query):gmatch('%S+')do terms[#terms+1]=term end
    if category==''then category=nil end
    local result={}
    for _,t in ipairs(state().templates)do
        if not category or t.category==category then
            local hay=fold(t.name)..'\n'..fold(t.text)..'\n'..fold(t.category)
            local hit=true
            for _,term in ipairs(terms)do if not hay:find(term,1,true)then hit=false;break end end
            if hit then result[#result+1]=t end
        end
    end
    return result
end
function P.TemplateCategories()
    local seen,list={},{}
    for _,t in ipairs(state().templates)do if t.category and not seen[t.category]then seen[t.category]=true;list[#list+1]=t.category end end
    table.sort(list,function(a,b)local x,y=fold(a),fold(b);if x==y then return a<b end;return x<y end)
    return list
end
local function trim(text)return(text:gsub('^%s+',''):gsub('%s+$',''))end
function P.SaveTemplate(id,name,text,category)
    local list=state().templates
    local existing
    if id~=nil then
        existing=findTemplate(id);if not existing then return nil,'missing'end
    end
    text=type(text)=='string'and trim(text)or''
    if text==''then return nil,'empty'end
    name=type(name)=='string'and trim(name)or''
    category=type(category)=='string'and trim(category)or''
    if not plain(text)or not plain(name)or not plain(category)then return nil,'invalid_chars'end
    if#text>P.MAX_TEMPLATE_BYTES or chars(name)>40 or chars(category)>24 then return nil,'too_long'end
    if not existing and#list>=P.MAX_TEMPLATES then return nil,'limit'end
    if name==''then name=clip(text,30)end
    if category==''then category=nil end
    if existing then existing.name,existing.text,existing.category=name,text,category;return existing.id end
    local top=0
    for _,t in ipairs(list)do top=math.max(top,tonumber(t.id:match('^tpl_(%d+)$'))or 0)end
    id='tpl_'..(top+1)
    list[#list+1]={id=id,name=name,text=text,category=category}
    return id
end
function P.RemoveTemplate(id)
    local s=state()
    for i,t in ipairs(s.templates)do
        if t.id==id then
            table.remove(s.templates,i);s.favorites[id]=nil
            for j=#s.templateRecent,1,-1 do if s.templateRecent[j]==id then table.remove(s.templateRecent,j)end end
            return true
        end
    end
    return false
end
function P.TouchTemplate(id)
    if not findTemplate(id)then return false end
    local recent=state().templateRecent
    for i=#recent,1,-1 do if recent[i]==id then table.remove(recent,i)end end
    table.insert(recent,1,id)
    while#recent>P.MAX_RECENT do table.remove(recent)end
    return true
end
function P.RecentTemplates()
    local result={}
    for _,id in ipairs(state().templateRecent)do local t=findTemplate(id);if t then result[#result+1]=t end end
    return result
end
-- Replaces {name} {me} {zone} {target}; a token without a value stays in the text and is listed (e.g. '{zone}').
function P.Fill(text,ctx)
    if type(text)~='string'then return'',{}end
    ctx=type(ctx)=='table'and ctx or{}
    local unresolved,seen={},{}
    local filled=text:gsub('{(%a+)}',function(key)
        if key~='name'and key~='me'and key~='zone'and key~='target'then return nil end
        local value=ctx[key]
        if type(value)=='string'and value~=''and plain(value)then return value end
        if not seen[key]then seen[key]=true;unresolved[#unresolved+1]='{'..key..'}'end
    end)
    return filled,unresolved
end
function P.Context(conv)
    local ctx={}
    local function str(value)return type(value)=='string'and value~=''and Z.Safe(value)and value or nil end
    if type(conv)=='table'and(conv.kind=='WHISPER'or conv.kind=='BN_WHISPER')then ctx.name=str(conv.name)end
    ctx.me=str(Z.adapter and Z.adapter.me and Z.adapter.me.name)
    ctx.zone=str(Z.Call(GetRealZoneText))or str(Z.Call(GetZoneText))
    ctx.target=str(Z.Call(UnitName,'target'))
    return ctx
end
