-- Phrase list, favorites, recent use and own templates. State lives in ZenialChatDB.phrases (created on first use).
local _,Z=...
local P={};Z.Phrases=P
P.MAX_RECENT=10
P.MAX_CUSTOM=50
local labels={
    greetings={'Begrüßung','Greetings'},help={'Hilfe','Help'},quest={'Quests','Quests'},pvp={'PvP','PvP'},
    trade={'Handel','Trade'},roleplay={'Rollenspiel','Roleplay'},misc={'Sonstiges','Misc'},custom={'Eigene','Custom'},
}
local fallback -- used when no saved-variables root exists, so calls never fail
local function state()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    if type(db)~='table'then fallback=fallback or{};db=fallback end
    local s=db.phrases
    if type(s)~='table'then s={};db.phrases=s end
    if type(s.favorites)~='table'then s.favorites={}end
    if type(s.recent)~='table'then s.recent={}end
    if type(s.custom)~='table'then s.custom={}end
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
    if not find(id)then return nil end
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
