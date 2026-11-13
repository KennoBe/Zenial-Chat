-- Reverse lookup garbled word -> candidate source words for one language. Pure logic, no UI.
-- Sources in fixed order: learned (user corrections in ZenialChatDB.learned[language][fakeWord] = meaning),
-- measured (Z.GarbleData), computed (optional Z.GarbleComputed, same format; no data yet), public (single pairs below).
-- Public pairs: Warcraft Wiki (warcraft.wiki.gg), pages Orcish (language) and Common (language), CC BY-SA 4.0.
local _,Z=...
local G={};Z.GarbleMap=G
G.MAX_ENTRIES=4000
local sourceOrder={learned=1,measured=2,computed=3,public=4}
-- language ID -> { garbled = word }; Orcish = 1, Common = 7
local PUBLIC={[1]={kek='lol',lok='bur'},[7]={bur='lol'}}
local index={} -- language -> { build=, map={fake={ {word,rank,source} }}, count= }
local rankOf

-- Fold ASCII letters only; string.lower may alter UTF-8 bytes in this environment.
local function fold(text)
    return(tostring(text):gsub('%u',function(c)return string.char(c:byte()+32)end))
end
local function ranks()
    if not rankOf then
        rankOf={}
        for _,e in ipairs(Z.InterpretData and Z.InterpretData.words or{})do rankOf[e.w]=e.r end
    end
    return rankOf
end
local function rankFor(word)return ranks()[word]or 3 end
local function root()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    return type(db)=='table'and db or nil
end
-- Current client build (fourth return of GetBuildInfo); nil when unknown. Replaceable for tests.
function G.CurrentBuild()
    local info=_G.GetBuildInfo
    if type(info)~='function'then return nil end
    local ok,build=pcall(function()return(select(4,info()))end)
    return ok and tonumber(build)or nil
end
function G.Reset()index={};rankOf=nil end
function G.Size(languageId)
    local entry=index[tonumber(languageId)or-1]
    return entry and entry.count or 0
end

local function sortCandidates(list)
    table.sort(list,function(a,b)
        if sourceOrder[a.source]~=sourceOrder[b.source]then return sourceOrder[a.source]<sourceOrder[b.source]end
        if a.rank~=b.rank then return a.rank<b.rank end
        return a.word<b.word
    end)
end
-- Builds the reverse index for one language (measured, computed, public) for the given build.
function G.Build(languageId,build)
    languageId=tonumber(languageId)
    if not languageId then return end
    local entry={build=build,map={},count=0,seen={}}
    index[languageId]=entry
    local function add(fake,word,source)
        if entry.count>=G.MAX_ENTRIES then return end
        if type(fake)~='string'or type(word)~='string'or fake==''or word==''then return end
        fake=fold(fake)
        local key=fake..'\0'..word
        if entry.seen[key]then return end
        entry.seen[key]=true
        local list=entry.map[fake]
        if not list then list={};entry.map[fake]=list end
        list[#list+1]={word=word,rank=rankFor(word),source=source}
        entry.count=entry.count+1
    end
    local function addList(data,source)
        if type(data)~='table'or build==nil then return end
        for _,item in ipairs(data)do
            if type(item)=='table'and tonumber(item.language)==languageId and item.build==build and type(item.pairs)=='table'then
                local names={}
                for word in pairs(item.pairs)do if type(word)=='string'then names[#names+1]=word end end
                table.sort(names)
                for _,word in ipairs(names)do add(item.pairs[word],word,source)end
            end
        end
    end
    addList(Z.GarbleData,'measured')
    addList(Z.GarbleComputed,'computed')
    for fake,word in pairs(PUBLIC[languageId]or{})do add(fake,word,'public')end
    entry.seen=nil
    for _,list in pairs(entry.map)do sortCandidates(list)end
end

-- Candidate source words for a garbled word: array of {word, rank, source}, best first. Never fails.
function G.Candidates(languageId,fakeWord)
    languageId=tonumber(languageId)
    if not languageId or type(fakeWord)~='string'or fakeWord==''then return{} end
    local fake=fold(fakeWord)
    local result,have={},{}
    local function add(word,source)
        if have[word]then return end
        have[word]=true;result[#result+1]={word=word,rank=rankFor(word),source=source}
    end
    local db=root()
    local learned=db and type(db.learned)=='table'and db.learned[languageId]
    if type(learned)=='table'then
        for key,meaning in pairs(learned)do
            if type(key)=='string'and type(meaning)=='string'and meaning~=''and fold(key)==fake then add(meaning,'learned')end
        end
    end
    local build=G.CurrentBuild()
    local entry=index[languageId]
    if not entry or entry.build~=build then G.Build(languageId,build);entry=index[languageId]end
    for _,c in ipairs(entry and entry.map[fake]or{})do add(c.word,c.source)end
    sortCandidates(result)
    return result
end
