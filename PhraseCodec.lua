-- Spelling codec for phrases sent to opponents without the addon. A table maps each letter A-Z to one input
-- character of a language; a phrase becomes one single-character word per letter. Pure logic, no client API.
local _,Z=...
local C={};Z.PhraseCodec=C
C.MAX_BYTES=255
C.VERSION='ZPT1'
C.SOURCES={computed=true,bundled=true,calibration=true,import=true}
local MAX_INPUT=8 -- bytes of one input character (a UTF-8 letter needs at most 4)
local function root()
    local db=Z.store and Z.store.db or _G.ZenialChatDB
    return type(db)=='table'and db or nil
end
-- One entry (a letter or the separator) must be exactly one valid UTF-8 character that is safe to send: no pipe,
-- no control character, no white space. Anything else could break a chat line or hide what the receiver reads.
local SPACES={[0x85]=true,[0xA0]=true,[0x1680]=true,[0x2028]=true,[0x2029]=true,[0x202F]=true,[0x205F]=true,[0x3000]=true}
local function validEntry(value)
    if type(value)~='string'or value==''or#value>4 then return false end
    -- No %s: it depends on the C locale and could match the byte 0xA0 inside a valid character such as a-grave (C3 A0).
    if value:find('[%z\1-\32\127|]')then return false end
    local b1=value:byte(1)
    local length,code
    if b1<0x80 then length,code=1,b1
    elseif b1>=0xC2 and b1<=0xDF then length,code=2,b1-0xC0
    elseif b1>=0xE0 and b1<=0xEF then length,code=3,b1-0xE0
    elseif b1>=0xF0 and b1<=0xF4 then length,code=4,b1-0xF0
    else return false end
    if#value~=length then return false end
    for i=2,length do
        local b=value:byte(i)
        if b<0x80 or b>0xBF then return false end
        code=code*64+(b-0x80)
    end
    if length==3 and(code<0x800 or(code>=0xD800 and code<=0xDFFF))then return false end
    if length==4 and(code<0x10000 or code>0x10FFFF)then return false end
    if SPACES[code]or(code>=0x2000 and code<=0x200A)then return false end
    -- invisible and bidirectional control characters
    if(code>=0x80 and code<=0x9F)or code==0xAD or(code>=0x200B and code<=0x200F)or(code>=0x2028 and code<=0x202E)
        or(code>=0x2060 and code<=0x206F)or code==0xFEFF or(code>=0xFFF9 and code<=0xFFFF)then return false end
    return true
end
C.ValidEntry=validEntry
local function alphabet()
    local list={};for i=0,25 do list[#list+1]=string.char(65+i)end
    return list
end
-- Letters without an entry in the table, in alphabet order.
local function absent(tbl)
    local missing,letters={},type(tbl)=='table'and type(tbl.letters)=='table'and tbl.letters or{}
    for _,letter in ipairs(alphabet())do
        local value=letters[letter]
        if not validEntry(value)then missing[#missing+1]=letter end
    end
    local separator=type(tbl)=='table'and tbl.separator
    if type(separator)=='string'and separator~=''and not validEntry(separator)then missing[#missing+1]='_'end
    return missing
end
-- A user table with the matching build wins over a bundled one with the matching build, which wins over a user
-- table of another build.
function C.Pick(languageId,currentBuild)
    local db=root();local saved=db and type(db.phraseTables)=='table'and db.phraseTables[languageId]or nil
    if type(saved)~='table'then saved=nil end
    local bundled=type(Z.PhraseTables)=='table'and Z.PhraseTables[languageId]or nil
    if type(bundled)~='table'then bundled=nil end
    if saved and saved.build==currentBuild then return saved end
    if bundled and bundled.build==currentBuild then return bundled end
    return saved
end
function C.Status(tbl,currentBuild)
    if type(tbl)~='table'or type(tbl.letters)~='table'then return'missing',{}end
    local missing=absent(tbl)
    if tbl.build~=currentBuild then return'outdated',missing end
    if #missing>0 then return'incomplete',missing end
    return'ready',missing
end
-- phrase: letters A-Z and spaces (lower case is folded up). Letters without an entry are listed in `missing`
-- and shown as `_` in the preview; they are left out of the text and never replaced.
function C.Encode(phrase,tbl)
    if type(phrase)~='string'then return nil,'empty'end
    if type(tbl)~='table'or type(tbl.letters)~='table'then return nil,'no_table'end
    phrase=phrase:upper():gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    if phrase==''then return nil,'empty'end
    if phrase:find('[^A-Z ]')then return nil,'invalid_chars'end
    local separator=type(tbl.separator)=='string'and tbl.separator~=''and tbl.separator or nil
    if separator and not validEntry(separator)then return nil,'invalid_table'end
    for letter in phrase:gmatch('[A-Z]')do
        local value=tbl.letters[letter]
        if type(value)=='string'and value~=''and not validEntry(value)then return nil,'invalid_table'end
    end
    local tokens,preview,missing,seen,words={},{},{},{},{}
    for word in phrase:gmatch('%S+')do words[#words+1]=word end
    for index,word in ipairs(words)do
        if index>1 and separator then tokens[#tokens+1]=separator end
        local shown={}
        for letter in word:gmatch('.')do
            local value=tbl.letters[letter]
            if type(value)=='string'and value~=''then
                tokens[#tokens+1]=value;shown[#shown+1]=letter
            else
                shown[#shown+1]='_'
                if not seen[letter]then seen[letter]=true;missing[#missing+1]=letter end
            end
        end
        preview[#preview+1]=table.concat(shown)
    end
    local text=table.concat(tokens,' ')
    if #text>C.MAX_BYTES then return nil,'too_long'end
    return{text=text,preview=table.concat(preview,separator and' 'or''),missing=missing,bytes=#text}
end
local function chars(word)
    local count=0
    for _ in word:gmatch('[%z\1-\127\194-\244][\128-\191]*')do count=count+1 end
    return count
end
-- Reads a received line: at least 3 words, at least 70% of them single characters. Returns those characters
-- joined, upper-cased. The line is not mapped back through a table.
function C.Despell(text)
    if not Z.Safe(text)or type(text)~='string'then return nil end
    local total,singles,out,gap=0,0,{},false
    for word in text:gmatch('%S+')do
        total=total+1
        if chars(word)==1 then
            singles=singles+1
            if word:find('^[a-z]$')then gap=#out>0
            else
                if gap then out[#out+1]=' ';gap=false end
                out[#out+1]=word
            end
        end
    end
    if total<3 or singles*10<total*7 then return nil end
    local result=table.concat(out):upper()
    if result==''then return nil end
    return result
end
local function hex(value)return(value:gsub('.',function(c)return string.format('%02X',c:byte())end))end
local function unhex(value)
    if value==''or#value%2~=0 or value:find('[^0-9A-Fa-f]')then return nil end
    return(value:gsub('..',function(h)return string.char(tonumber(h,16))end))
end
-- ZPT1:<lang>:<build>:A=<hex>,B=<hex>,...,_=<hex separator>,~=<source>
function C.Export(tbl)
    if type(tbl)~='table'or type(tbl.letters)~='table'then return nil,'format'end
    local lang=tostring(tbl.language)
    if not lang:match('^[%w_%-]+$')or type(tbl.build)~='number'then return nil,'format'end
    local parts={}
    for _,letter in ipairs(alphabet())do
        local value=tbl.letters[letter]
        if type(value)=='string'and value~=''and#value<=MAX_INPUT then parts[#parts+1]=letter..'='..hex(value)end
    end
    if type(tbl.separator)=='string'and tbl.separator~=''and#tbl.separator<=MAX_INPUT then parts[#parts+1]='_='..hex(tbl.separator)end
    return C.VERSION..':'..lang..':'..string.format('%d',tbl.build)..':'..table.concat(parts,',')
end
function C.Import(code,currentBuild)
    if not Z.Safe(code)or type(code)~='string'then return nil,'format'end
    code=code:gsub('^%s+',''):gsub('%s+$','')
    local head,lang,build,body=code:match('^(%w+):([%w_%-]+):(%d+):(.*)$')
    if not head then return nil,'format'end
    if head~=C.VERSION then return nil,head:match('^ZPT%d+$')and'version'or'format'end
    local letters,separator,count={}
    for part in body:gmatch('[^,]+')do
        local key,value=part:match('^(.)=(%x+)$')
        value=value and unhex(value)
        if not value or#value>MAX_INPUT or not validEntry(value)then return nil,'format'end
        if key=='_'then separator=value
        elseif key:match('^[A-Z]$')and not letters[key]then letters[key]=value;count=(count or 0)+1
        else return nil,'format'end
    end
    if not count then return nil,'format'end
    return{language=tonumber(lang)or lang,build=tonumber(build),pool=1,letters=letters,separator=separator,source='import',at=Z.Now and Z.Now()or 0}
end
