-- Calibration of the spelling table with a second player of the other faction (two clients next to each other).
-- Sender: each click sends ONE probe line of single-character words (SAY). Receiver: listens to exactly that
-- sender and measures which input character turns into which letter. Word probes measure word -> garbled word.
-- Nothing here sends on its own: no timer, no event, no loop. Chat is only sent from K.SendNext*Probe, which the
-- settings page calls from a click.
local _,Z=...
local K={};Z.Calibration=K
K.POOL_VERSION=1
K.BASE=12 -- probe i has BASE+i words, so the word count identifies the probe
K.PAD='A' -- filler word, an ASCII letter of the pool (measured several times on purpose)
K.PER_PROBE=12 -- pool characters per probe
K.TIMEOUT=600 -- seconds a listening session lasts
K.WORD_LINE_MAX=255
-- Input characters of pool version 1, order is part of the version: A-Z, a-z, 0-9, then multi-byte letters.
local function buildPool()
    local list={}
    for i=0,25 do list[#list+1]=string.char(65+i)end
    for i=0,25 do list[#list+1]=string.char(97+i)end
    for i=0,9 do list[#list+1]=string.char(48+i)end
    local extra='ÄÖÜäöüßÀÁÂÃÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÙÚÛÝàáâãåçèéêëìíîïñòóôõùúûý'
    local n=0
    for ch in extra:gmatch('[\194-\244][\128-\191]*')do
        n=n+1;if n>40 then break end
        list[#list+1]=ch
    end
    return list
end
K.POOL=buildPool()

local sender={probe=0,word=0} -- number of probes already sent in this sender session
function K.ResetSender()sender={probe=0,word=0}end
local function api()return Z.adapter and Z.adapter.api or _G end
local function now()return Z.Now and Z.Now()or 0 end
local function root()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    return type(db)=='table'and db or nil
end

-- ---------------------------------------------------------------- character probes ---
function K.ProbeCount()return math.ceil(#K.POOL/K.PER_PROBE)end
-- Probe i (1-based): text and the list of input characters in word order (including filler words).
function K.Probe(i)
    i=tonumber(i)
    if not i or i<1 or i>K.ProbeCount()or i~=math.floor(i)then return nil end
    local chars={}
    for n=(i-1)*K.PER_PROBE+1,math.min(i*K.PER_PROBE,#K.POOL)do chars[#chars+1]=K.POOL[n]end
    while#chars<K.BASE+i do chars[#chars+1]=K.PAD end
    return table.concat(chars,' '),chars
end
-- Next probe not sent yet in this sender session; moves on to the following one. nil when all were sent.
function K.NextProbe()
    local i=sender.probe+1
    local text=K.Probe(i)
    if not text then return nil end
    sender.probe=i
    return text,i
end
local function transmit(text)
    local p=api()
    local chat=type(p.C_ChatInfo)=='table'and p.C_ChatInfo.SendChatMessage or p.SendChatMessage
    if type(chat)~='function'then return false,'no_api'end
    local ok=pcall(chat,text,'SAY')
    if not ok then return false,'error'end
    return true,'sent'
end
-- One click, one line. The probe only counts as sent when the call did not fail.
function K.SendNextProbe()
    local i=sender.probe+1
    local text=K.Probe(i)
    if not text then return false,'done'end
    local ok,code=transmit(text)
    if ok then sender.probe=i end
    return ok,code
end

-- ---------------------------------------------------------------- word probes ---
local wordCache
local function wordLines()
    local data=Z.InterpretData and Z.InterpretData.words
    if type(data)~='table'then return{}end
    if wordCache and wordCache.source==data and wordCache.max==K.WORD_LINE_MAX and wordCache.size==#data then return wordCache.lines end
    local lines,current,length={},{},0
    local function flush()
        if#current>0 then lines[#lines+1]=current;current={};length=0 end
    end
    for _,entry in ipairs(data)do
        local word=type(entry)=='table'and entry.w
        if type(word)=='string'and word:match('^[a-z]+$')then
            local extra=#word+(#current>0 and 1 or 0)
            if length+extra>K.WORD_LINE_MAX then flush();extra=#word end
            current[#current+1]=word;length=length+extra
        end
    end
    flush()
    for _,words in ipairs(lines)do
        local seq={};for n,word in ipairs(words)do seq[n]=#word end
        words.key=table.concat(seq,',')
    end
    wordCache={source=data,max=K.WORD_LINE_MAX,size=#data,lines=lines}
    return lines
end
function K.WordProbeCount()return#wordLines()end
function K.WordProbe(i)
    local words=wordLines()[tonumber(i)or 0]
    if not words then return nil end
    return table.concat(words,' '),words
end
function K.NextWordProbe()
    local i=sender.word+1
    local text=K.WordProbe(i)
    if not text then return nil end
    sender.word=i
    return text,i
end
function K.SendNextWordProbe()
    local i=sender.word+1
    local text=K.WordProbe(i)
    if not text then return false,'done'end
    local ok,code=transmit(text)
    if ok then sender.word=i end
    return ok,code
end

-- ---------------------------------------------------------------- receiving ---
K.session=nil
local function newSession(mode,guid)
    K.session={mode=mode,guid=guid,start=now(),rejected=0,conflicts=0,seen={},results={},pairs={},pairConflicts=0}
    return K.session
end
local function validGuid(guid)return type(guid)=='string'and guid~=''and Z.Safe(guid)end
function K.Listen(senderGuid)
    if not validGuid(senderGuid)then return false,'no_guid'end
    newSession('chars',senderGuid);return true,'listening'
end
function K.ListenWords(senderGuid)
    if not validGuid(senderGuid)then return false,'no_guid'end
    newSession('words',senderGuid);return true,'listening'
end
function K.Stop()K.session=nil end
function K.Listening()return K.session~=nil end
-- Guid of the current target when it is a player with a readable GUID.
function K.TargetGuid()
    local p=api()
    if type(p.UnitGUID)~='function'then return nil end
    local ok,guid=pcall(p.UnitGUID,'target')
    if not ok or not validGuid(guid)or not guid:match('^Player%-')then return nil end
    return guid
end
function K.ListenTarget(words)
    local guid=K.TargetGuid()
    if not guid then return false,'no_target'end
    if words then return K.ListenWords(guid)end
    return K.Listen(guid)
end

local function utf8len(word)
    local n=0
    for _ in word:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end
    return n
end
local function charsLine(session,words,language)
    local index=#words-K.BASE
    local _,inputs=K.Probe(index)
    if not inputs or#inputs~=#words then session.rejected=session.rejected+1;return end
    if session.language and session.language~=language then session.rejected=session.rejected+1;return end
    session.language=language;session.seen[index]=true
    for n,input in ipairs(inputs)do
        local word=words[n]
        local result='bad'
        if word:match('^%u$')then result=word elseif word:match('^%l$')then result='separator'end
        local set=session.results[input]
        if not set then set={};session.results[input]=set;set.count=0 end
        if not set[result]then
            set[result]=true;set.count=set.count+1
            if set.count==2 then session.conflicts=session.conflicts+1 end
        end
    end
end
local function wordsLine(session,words,language)
    local seq={};for n,word in ipairs(words)do seq[n]=utf8len(word)end
    local key=table.concat(seq,',')
    local found
    for i,line in ipairs(wordLines())do
        if line.key==key then
            if found then session.rejected=session.rejected+1;return end -- ambiguous
            found=i
        end
    end
    if not found then session.rejected=session.rejected+1;return end
    if session.language and session.language~=language then session.rejected=session.rejected+1;return end
    session.language=language;session.seen[found]=true
    for n,source in ipairs(wordLines()[found])do
        local old=session.pairs[source]
        if old==nil then session.pairs[source]=words[n]
        elseif old~=words[n]then session.pairConflicts=session.pairConflicts+1 end
    end
end
local function handle(event,...)
    if event~='CHAT_MSG_SAY'then return end
    local session=K.session;if not session then return end
    if now()-session.start>K.TIMEOUT then K.session=nil;return end
    local text,name,language=...
    local guid=select(12,...)
    if not Z.Safe(text,name,language,guid)or type(text)~='string'or type(name)~='string'or type(language)~='string'then return end
    if not validGuid(guid)or guid~=session.guid then return end
    local words={};for word in text:gmatch('%S+')do words[#words+1]=word end
    local lid=Z.Interpret and Z.Interpret.LanguageId and Z.Interpret.LanguageId(language)
    if#words==0 or not lid then session.rejected=session.rejected+1;return end
    if session.mode=='chars'then charsLine(session,words,lid)else wordsLine(session,words,lid)end
end
-- Never raises. Only CHAT_MSG_SAY of the listened sender counts.
function K.OnEvent(event,...)
    local ok=pcall(handle,event,...)
    return ok
end

-- ---------------------------------------------------------------- results ---
local function alphabet()
    local list={};for i=0,25 do list[#list+1]=string.char(65+i)end
    return list
end
function K.Result()
    local session=K.session
    local summary={letters=0,missing=alphabet(),conflicts=session and session.conflicts or 0,
        rejected=session and session.rejected or 0,probes='0/'..K.ProbeCount()}
    if not session or session.mode~='chars'or not session.language then return nil,summary end
    local seen=0;for _ in pairs(session.seen)do seen=seen+1 end
    summary.probes=seen..'/'..K.ProbeCount()
    local letters,separator={}
    for _,input in ipairs(K.POOL)do
        local set=session.results[input]
        if set and set.count==1 then
            for result in pairs(set)do
                if result=='separator'then separator=separator or input
                elseif result~='bad'and result~='count'and not letters[result]then letters[result]=input end
            end
        end
    end
    local missing,count={},0
    for _,letter in ipairs(alphabet())do
        if letters[letter]then count=count+1 else missing[#missing+1]=letter end
    end
    summary.letters=count;summary.missing=missing
    local G=Z.GarbleMap
    local tbl={language=session.language,build=G and G.CurrentBuild()or nil,pool=K.POOL_VERSION,letters=letters,
        separator=separator,source='calibration',at=now()}
    return tbl,summary
end
function K.WordResult()
    local session=K.session
    local summary={words=0,conflicts=session and session.pairConflicts or 0,rejected=session and session.rejected or 0,
        lines='0/'..K.WordProbeCount()}
    if not session or session.mode~='words'or not session.language then return nil,summary end
    local pairs_,seen,count={},0,0
    for word,fake in pairs(session.pairs)do pairs_[word]=fake;count=count+1 end
    for _ in pairs(session.seen)do seen=seen+1 end
    summary.words=count;summary.lines=seen..'/'..K.WordProbeCount()
    local G=Z.GarbleMap
    return{language=session.language,build=G and G.CurrentBuild()or nil,pairs=pairs_},summary
end
-- Lua table literal for GarbleData.lua; nothing is written anywhere.
function K.ExportWords()
    local tbl=K.WordResult()
    if not tbl or next(tbl.pairs)==nil then return nil,'empty'end
    local names={};for word in pairs(tbl.pairs)do names[#names+1]=word end
    table.sort(names)
    local out={string.format('{ language = %d, build = %s, pairs = {',tbl.language,tostring(tbl.build))}
    for _,word in ipairs(names)do out[#out+1]=string.format('  [%q] = %q,',word,tbl.pairs[word])end
    out[#out+1]='} }'
    return table.concat(out,'\n')
end

-- ---------------------------------------------------------------- tables for the sender ---
-- Import of a code made by the listener; stored per language ID.
function K.Import(code)
    local C=Z.PhraseCodec;if not C then return false,'format'end
    local G=Z.GarbleMap
    local tbl,err=C.Import(code,G and G.CurrentBuild()or nil)
    if not tbl then return false,err end
    local db=root();if not db then return false,'no_store'end
    if type(db.phraseTables)~='table'then db.phraseTables={}end
    db.phraseTables[tbl.language]=tbl
    return true,'imported'
end
function K.ExportCode()
    local tbl=K.Result()
    if not tbl then return nil,'empty'end
    local count=0;for _ in pairs(tbl.letters)do count=count+1 end
    if count==0 then return nil,'empty'end
    return Z.PhraseCodec.Export(tbl)
end

-- Own language ID: GetDefaultLanguage, otherwise by faction (Horde 1, Alliance 7).
function K.OwnLanguageId()
    local p=api()
    if type(p.GetDefaultLanguage)=='function'then
        local ok,name,id=pcall(p.GetDefaultLanguage)
        if ok and Z.Safe(name,id)and type(id)=='number'then return id end
    end
    local faction=Z.adapter and Z.adapter.me and Z.adapter.me.faction
    if faction=='Horde'then return 1 elseif faction=='Alliance'then return 7 end
    return nil
end
local languageNames={[1]={'Orcisch','Orcish'},[7]={'Gemeinsprache','Common'}}
local sourceNames={calibration={'Kalibrierung','calibration'},import={'Import','import'},bundled={'mitgeliefert','bundled'},computed={'berechnet','computed'}}
function K.LanguageLabel(id)
    local n=languageNames[id]
    if n then return Z.L(n[1],n[2])end
    return Z.L('Sprache ','Language ')..tostring(id)
end
-- Status line for the settings page.
function K.StatusText(languageId)
    local C=Z.PhraseCodec;local G=Z.GarbleMap
    if not languageId then return Z.L('Eigene Sprache unbekannt.','Own language unknown.')end
    local build=G and G.CurrentBuild()or nil
    local tbl=C.Pick(languageId,build)
    local status,missing=C.Status(tbl,build)
    local text
    if status=='missing'then text=Z.L('fehlt','missing')
    elseif status=='outdated'then text=Z.L('veraltet','outdated')
    elseif status=='incomplete'then text=Z.L('unvollständig (fehlend: ','incomplete (missing: ')..table.concat(missing,', ')..')'
    else text=Z.L('bereit','ready')end
    local label=K.LanguageLabel(languageId)..': '..text
    local source=tbl and sourceNames[tbl.source]
    if source then label=label..' · '..Z.L('Herkunft: ','source: ')..Z.L(source[1],source[2])end
    return label,status
end
