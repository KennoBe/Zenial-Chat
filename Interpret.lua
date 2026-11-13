-- Honest reading of foreign-language lines (opposite faction). Pure logic, no UI.
-- Stages: 'guess' or 'unknown' only; 'exact' never comes from this module. No probabilities are produced.
local _,Z=...
local I={};Z.Interpret=I
I.MAX_LEARNED=2000
I.MAX_PHRASE_WORDS=8
I.MAX_SHOWN=3
local ELLIPSIS='\226\128\166' -- U+2026
local LANGUAGES={orcish=1,orcisch=1,common=7,gemeinsprache=7}

local function fold(text)
    return(tostring(text):gsub('%u',function(c)return string.char(c:byte()+32)end))
end
local function strip(word)
    return(word:gsub('^[%.,!%?;:\'"]+',''):gsub('[%.,!%?;:\'"]+$',''))
end
-- Lookup key of a word: ASCII-folded, without leading/trailing punctuation.
function I.Key(word)
    if type(word)~='string'then return''end
    return strip(fold(word))
end
-- Client language name -> language ID (1 Orcish, 7 Common) or nil.
function I.LanguageId(name)
    if type(name)~='string'or not Z.Safe(name)then return nil end
    return LANGUAGES[fold(name)]
end
local function root()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    return type(db)=='table'and db or nil
end

-- Phrase index by word count, built once (rebuilt only if the phrase list is replaced).
local indexed,byCount
function I.Reset()indexed=nil;byCount=nil end
local function phrasesFor(count)
    local list=Z.InterpretData and Z.InterpretData.phrases
    if type(list)~='table'then return{}end
    if indexed~=list then
        indexed=list;byCount={}
        for _,p in ipairs(list)do
            if type(p)=='table'and type(p.w)=='table'then
                local n=#p.w
                byCount[n]=byCount[n]or{}
                table.insert(byCount[n],p)
            end
        end
    end
    return byCount[count]or{}
end

-- Best phrase (lowest rank, then data order) whose words can be picked one per candidate list.
local function matchPhrase(cands)
    local n=#cands
    if n<1 or n>I.MAX_PHRASE_WORDS then return nil end
    local best
    for _,p in ipairs(phrasesFor(n))do
        local ok=true
        for i=1,n do
            local hit=false
            for _,c in ipairs(cands[i])do if c.word==p.w[i]then hit=true;break end end
            if not hit then ok=false;break end
        end
        if ok and(not best or(tonumber(p.r)or 3)<(tonumber(best.r)or 3))then best=p end
    end
    return best
end

-- reading ('guess'|'unknown'), meaning (string|nil), detail (table|nil). Never raises.
-- detail.words[i] = {fake=<original word>, chosen=<shown text>|nil, alternatives={words not shown}}
function I.Read(message)
    local ok,reading,meaning,detail=pcall(function()
        if type(message)~='table'then return'unknown'end
        local text=message.text
        if not Z.Safe(text)or type(text)~='string'then return'unknown'end
        local letters=Z.PhraseCodec and Z.PhraseCodec.Despell(text)
        if letters then return'guess',letters,{kind='spelled'}end
        local lid=I.LanguageId(message.language)
        local G=Z.GarbleMap
        local entries,cands,any={},{},false
        for raw in text:gmatch('%S+')do
            local list={}
            if lid and G then list=G.Candidates(lid,I.Key(raw))end
            if#list>0 then any=true end
            entries[#entries+1]={fake=raw};cands[#cands+1]=list
        end
        if#entries==0 then return'unknown'end
        local complete=true
        for _,list in ipairs(cands)do if#list==0 then complete=false end end
        local phrase=complete and matchPhrase(cands)or nil
        local shown={}
        for i,e in ipairs(entries)do
            local list=cands[i]
            local chosen,used
            if#list==0 then
                chosen=ELLIPSIS;used={}
            elseif phrase then
                chosen=phrase.w[i];used={[chosen]=true}
            else
                local top,names=list[1],{list[1].word}
                for k=2,math.min(#list,I.MAX_SHOWN)do
                    if list[k].source==top.source and list[k].rank==top.rank then names[#names+1]=list[k].word else break end
                end
                chosen=table.concat(names,' / ');used={}
                for _,w in ipairs(names)do used[w]=true end
            end
            local alts={}
            for _,c in ipairs(list)do
                if not used[c.word]and#alts<I.MAX_SHOWN then alts[#alts+1]=c.word end
            end
            e.chosen=chosen;e.alternatives=alts;shown[#shown+1]=chosen
        end
        if not any then
            for _,e in ipairs(entries)do e.chosen=nil end
            return'unknown',nil,{words=entries}
        end
        return'guess',table.concat(shown,' '),{words=entries,kind=phrase and'phrase'or'words'}
    end)
    if not ok then return'unknown',nil,nil end
    return reading,meaning,detail
end

local function validLanguage(language)
    language=tonumber(language)
    return(language==1 or language==7)and language or nil
end
-- Stores a user correction. Returns true, or nil plus 'invalid' / 'limit'.
function I.Learn(language,fakeWord,meaning)
    language=validLanguage(language)
    if not language or not Z.Safe(fakeWord,meaning)or type(fakeWord)~='string'or type(meaning)~='string'then return nil,'invalid'end
    local key=I.Key((fakeWord:gsub('^%s+',''):gsub('%s+$','')))
    if key==''or#key>64 or key:find('%c')then return nil,'invalid'end
    meaning=meaning:gsub('^%s+',''):gsub('%s+$','')
    if meaning==''or#meaning>64 or meaning:find('%c')or meaning:find('|',1,true)then return nil,'invalid'end
    local db=root()
    if not db then return nil,'invalid'end
    local learned=type(db.learned)=='table'and db.learned or nil
    local list=learned and type(learned[language])=='table'and learned[language]or nil
    if not(list and list[key]~=nil)then
        local count=0
        if list then for _ in pairs(list)do count=count+1 end end
        if count>=I.MAX_LEARNED then return nil,'limit'end
    end
    if not learned then learned={};db.learned=learned end
    if not list then list={};learned[language]=list end
    list[key]=meaning
    return true
end
function I.Forget(language,fakeWord)
    language=validLanguage(language)
    if not language or not Z.Safe(fakeWord)or type(fakeWord)~='string'then return false end
    local key=I.Key(fakeWord)
    local db=root()
    local list=db and type(db.learned)=='table'and db.learned[language]
    if type(list)~='table'or list[key]==nil then return false end
    list[key]=nil
    return true
end
