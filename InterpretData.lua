-- Own starter basis for interpreting garbled foreign-language chat: frequent chat words and short phrases in
-- English and German, written from scratch (no third-party word lists). Pure data, no client API.
--
-- Z.InterpretData.words   = { {w='hello', r=1}, ... }    w: lower-case word (a-z, ä ö ü ß, digits only in
--                                                        abbreviations such as lf2m), r: group 1 (very common)
--                                                        to 3 (less common). The rank is an order, not a probability.
-- Z.InterpretData.phrases = { {w={'need','help'}, r=1}, ... }   word sequences; every word is also in `words`.
local _,Z=...
local D={words={},phrases={}};Z.InterpretData=D

local function addWords(rank,text)
    for w in text:gmatch('%S+')do D.words[#D.words+1]={w=w,r=rank}end
end
local function addPhrases(rank,lines)
    for _,line in ipairs(lines)do
        local seq={};for w in line:gmatch('%S+')do seq[#seq+1]=w end
        D.phrases[#D.phrases+1]={w=seq,r=rank}
    end
end

addWords(1,[[
hello hi hey yes no ok okay please thanks thank you ty sorry help need want lol gg wp brb afk
the and to a i we me my is it of for in on at can do not with this that are be go
group party join invite quest kill follow wait ready sure
hallo danke bitte ja nein hilfe gruppe ich du wir ist und der die das nicht mit ein auch noch
]])
addWords(2,[[
about see much time game done bis auf nach helfen hilf vielen zusammen bald im am an da doch problem dank anyone everyone has long
good bad great nice sweet awesome cool well played luck have fun bye goodbye welcome morning night evening
who what where when why how which here there now soon later again more some any all one two three four five
get got give take come stay run stop attack defend heal tank dps healer mage priest warrior rogue hunter
look looking lfg lfm lf1m lf2m lf3m raid dungeon boss mob mobs loot roll pass greed gold buy sell trade
price cheap auction mail bank vendor repair flight horde alliance enemy friend guild
north south east west left right up down back front behind inside outside near far
tschuss moin servus gut gute guten tag morgen abend nacht schon spiel gespielt viel gluck spass
wer was wo wann warum wie wieso hier dort jetzt gleich spater nochmal mehr alle
eins zwei drei vier funf sechs sieben acht neun zehn
kann kannst konnen will willst brauche brauchst suche suchen hast haben habe hat bin bist sind war
komm kommst komme mach machen geh gehen warte warten bereit los lass lasst
mein dein dir mir dich mich uns euch ihr sie er es
heiler schurke jager magier priester krieger
]])
addWords(3,[[
accept away angreifen basis braucht bruecke buying ding folge gehe gehts greif hab hierher inviting lets lf lieb meet needs out protect selling tor treffen turm turn verteidige watch zum zur schön für später tschüss müssen können wähle größe
leader leave kick ignore report mute block whisper say yell emote dance sit stand fly mount ride swim
fight duel flag capture base node bridge tower graveyard gate cave road path hill river lake forest mountain town city
camp inn shop store armor weapon sword axe bow staff shield potion food water herb ore leather cloth
level levels xp exp grind farm skill talent spec build gear item items bag bags slot
easy hard fast slow high low big small old new last first next
very really maybe never always often today tomorrow yesterday minute minutes hour hours
because but or so if then than too just only still already
stuff thing things people player players guy guys man woman kid
oops wow omg try hmm haha ahh uhh
dont cant wont isnt wasnt didnt
thx pls plz np nvm idk imo btw asap
verkaufe kaufe tausche preis silber kupfer tasche waffe ruestung
links rechts oben unten vorne hinten norden suden osten westen
aber oder wenn dann weil nur immer nie oft heute gestern
stunde minuten sekunde leute spieler freund freunde gilde mannschaft
langsam schnell leicht schwer klein gross alt neu erste letzte nachste
gewonnen verloren sterben tot tod leben heilen angriff verteidigen
schoen entschuldigung entschuldige tut leid kein keine keiner nichts
gerne genau richtig falsch moment fertig
]])

-- Phrases, one line each; rank 1 = very common.
addPhrases(1,{
    'thank you','thanks guys','need help','can you help','help me','hello everyone','hi there','good luck','have fun',
    'well played','good game','see you','one moment','wait for me','follow me','im ready','lets go','you too',
    'danke dir','vielen dank','guten morgen','guten abend','gute nacht','gut gespielt','viel gluck','viel spass',
    'brauche hilfe','kannst du helfen','hilf mir','folge mir','warte auf mich','ich bin bereit','bis spater',
    'hallo zusammen','bis bald','kein problem',
})
addPhrases(2,{
    'good morning','good evening','good night','nice to meet you','welcome back','how are you','what is that','where are you',
    'who needs this','anyone want','lf group','lfm dungeon','need tank','need healer','need dps','looking for group',
    'looking for more','invite me','please invite','join group','join the party','inviting you','accept the invite',
    'quest done','kill the boss','kill that mob','need this quest','who has quest','turn in quest','got the loot',
    'roll need','roll greed','pass on that','gold please','selling gold','buying gold','cheap price','how much',
    'to the left','to the right','go north','go south','go east','go west','stay here','stop attack','dont attack',
    'help here','heal me','watch out','run away','come back','come here','sorry about that','my bad',
    'wie gehts','wo bist du','was ist das','wer braucht das','suche gruppe','suche tank','suche heiler',
    'komm hierher','geh nach links','geh nach rechts','nicht angreifen','hab dich lieb','tut mir leid',
    'wie viel','bitte warte','ich komme','ich gehe','bin gleich da','danke schoen','gerne doch','kein ding',
})
addPhrases(3,{
    'good to see you','nice to see you','long time','one more time','this is fun','that was fun','thank you very much',
    'i am here','i need that','i want this','we need more','one two three','selling for gold','buying for gold',
    'meet at the gate','meet at the inn','at the bridge','at the tower','at the base','capture the flag',
    'protect the flag','kill the leader','defend the base','attack the base','sell my items','trade with me',
    'ich suche gruppe','ich brauche tank','ich verkaufe items','wir sind bereit','komm zum tor','komm zur bruecke',
    'treffen am turm','verteidige die basis','greif die basis an','lass uns gehen',
})
