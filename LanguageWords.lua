-- Language parser nonsense words (Orcish, Common) as listed per word length. Reference data only, no UI.
-- Source: Warcraft Wiki (warcraft.wiki.gg), pages "Orcish (language)" and "Common (language)", retrieved 2026-11-13.
-- License: CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). The word lists are game data of Blizzard Entertainment.
-- This file is licensed under CC BY-SA 4.0 and NOT under the MIT license of the rest of the addon (see NOTICE.txt).
-- Changes: words folded to lowercase (ASCII); order and spelling (apostrophes, one hyphen) kept as on the wiki.
-- Format: [languageId]={name=,words={[length]={word,...}}}; Orcish = 1, Common = 7; length counts characters including ' and -.
local _,Z=...
local W={};Z.LanguageWords=W
W.DATA={
    [1]={name='Orcish',words={
            [1]={'a','n','g','o','l'},
            [2]={'ha','ko','no','mu','ag','ka','gi','il'},
            [3]={'lok','tar','kaz','ruk','kek','mog','zug','gul','nuk','aaz','kil','ogg'},
            [4]={'rega','nogu','tago','uruk','kagg','zaga','grom','ogar','gesh','thok','dogg','maka','maza'},
            [5]={'regas','nogah','kazum','magan',"no'bu",'golar','throm','zugas',"re'ka","no'ku","ro'th"},
            [6]={'thrakk','revash','nakazz','moguna',"no'gor","goth'a",'raznos','ogerin','gezzno','thukad','makogg',"aaz'no"},
            [7]={"lok'tar","gul'rok",'kazreth',"tov'osh","zil'nok","rath'is","kil'azi"},
            [8]={"throm'ka","osh'kava","gul'nath","kog'zela","ragath'a",'zuggossh',"moth'aga"},
            [9]={"tov'nokaz","osh'kazil","no'throma","gesh'nuka","lok'mogul","lok'bolar","ruk'ka'ha"},
            [10]={'regasnogah',"kazum'nobu","throm'bola","gesh'zugas","maza'rotha","ogerin'naz"},
            [11]={"thrakk'reva","kaz'goth'no","no'gor'goth","kil'azi'aga","zug-zug'ama","maza'thrakk"},
            [12]={"lokando'nash","ul'gammathar",'golgonnashar',"dalggo'mazah"},
            [13]={"khaz'rogg'ahn","moth'kazoroth"},
    }},
    [7]={name='Common',words={
            [1]={'a','e','i','o','u','y'},
            [2]={'an','ko','lo','lu','me','ne','re','ru','se','ti','va','ve'},
            [3]={'ash','bor','bur','far','gol','hir','lon','mod','nud','ras','ver','vil','vos'},
            [4]={'ador','agol','dana','goth','lars','noth','nuff','odes','ruff','thor','uden','veld','vohl','vrum'},
            [5]={'algos','barad','borne','melka','ergin','eynes','garde','gloin','majis','nagan','novas','regen','tiras','wirsh'},
            [6]={'aesire','aziris','daegil','danieb','ealdor','engoth','goibon','mandos','nevren','rogesh','rothas','ruftos','skilde','valesh','vandar','waldir'},
            [7]={'andovis','ewiddan','faergas','forthis','kaelsig','koshvel','lithtos','nandige','nostyec','novaedi','sturume','vassild'},
            [8]={'aldonoth','cynegold','endirvis','hamerung','landowar','lordaere','methrine','ruftvess','thorniss'},
            [9]={'aetwinter','danagarde','eloderung','firalaine','gloinador','gothalgos','regenthor','udenmajis','vandarwos','veldbarad'},
            [10]={'aelgestron','cynewalden','danavandar','dyrstigost','falhedring','vastrungen'},
            [11]={'agolandovis','bornevalesh','farlandowar','forthasador','thorlithtos','vassildador','wershaesire'},
            [12]={'adorstaerume','golveldbarad','mandosdaegil','nevrenrothas','waldirskilde'},
    }},
}

-- Fold ASCII letters only; string.lower may alter UTF-8 bytes in this environment.
local function fold(text)
    return(tostring(text):gsub('%u',function(c)return string.char(c:byte()+32)end))
end
local sets -- languageId -> length -> { word = true }
local function build()
    sets={}
    for id,lang in pairs(W.DATA)do
        local byLength={}
        for length,list in pairs(lang.words)do
            local set={}
            for _,word in ipairs(list)do set[word]=true end
            byLength[length]=set
        end
        sets[id]=byLength
    end
end
-- True when `word` is in the list of its length for that language (case-insensitive, ASCII).
function W.Has(languageId,word)
    if not sets then build()end
    if type(word)~='string'or not Z.Safe(word)then return false end
    word=fold(word)
    local byLength=sets[languageId]
    local set=byLength and byLength[#word]
    return set and set[word]==true or false
end
-- {languageId,length} for a known word, else nil. A word in both languages is reported as Orcish (1).
function W.Lookup(word)
    if type(word)~='string'or not Z.Safe(word)then return nil end
    word=fold(word)
    for _,id in ipairs({1,7})do
        if W.Has(id,word)then return{id,#word}end
    end
    return nil
end
-- True when the text has at least one word and at least 80 % of its words are in the list of their length for that language.
-- Words are split at whitespace; leading/trailing . , ! ? ; : " are stripped; empty words are ignored.
function W.IsGarble(text,languageId)
    if type(text)~='string'or not Z.Safe(text)then return false end
    local total,hits=0,0
    for raw in text:gmatch('%S+')do
        local word=raw:gsub('^[%.,!%?;:"]+',''):gsub('[%.,!%?;:"]+$','')
        if word~=''then
            total=total+1
            if W.Has(languageId,word)then hits=hits+1 end
        end
    end
    return total>0 and hits*5>=total*4 or false
end
