-- Display rules. Nothing here changes stored data: messages keep their full name, epoch time and
-- original text, and every format can be switched without touching the archive.
local _,Z=...
local F={};Z.Format=F
F.Fold=Z.Store.Fold
local function setting(key)local store=Z.store;return store and store.settings[key]end
-- First UTF-8 character.
local function firstChar(text)return text:match('^[%z\1-\127\194-\244][\128-\191]*')or text:sub(1,1)end
-- Only a client with regional names has "First Surname" characters, and only exactly two words
-- are read that way. Anything else (hyphens, three words, a BattleTag, a protected |K name) stays whole.
function F.SplitName(name)
    if type(name)~='string'or name==''or name:find('|',1,true)then return nil end
    if not(Z.adapter and Z.adapter.regionalNames)then return nil end
    local first,last=name:match('^(%S+) (%S+)$')
    if not first or first:find('-',1,true)or last:find('-',1,true)then return nil end
    return first,last
end
function F.Name(name,format)
    format=format or setting('nameFormat')or'full'
    if format=='full'then return name end
    local first,last=F.SplitName(name)
    if not first then return name end
    if format=='first'then return first
    elseif format=='last'then return last
    elseif format=='initialLast'then return firstChar(first)..'. '..last
    elseif format=='firstInitial'then return first..' '..firstChar(last)..'.'
    elseif format=='initials'then return firstChar(first)..'.'..firstChar(last)..'.'end
    return name
end
-- The label above a message. Battle.net names are never split: they are account names.
function F.SenderLabel(conv,msg)
    if msg.outgoing then
        local own=msg.ownCharacter and F.Name(msg.ownCharacter)
        return Z.L('Du','You')..(own and' · '..own or'')
    end
    if conv.kind=='BN_WHISPER'then return msg.sender or conv.name end
    return F.Name(msg.sender or conv.name)
end
-- Time ---------------------------------------------------------------------------------------
local offset,offsetKnown
-- Realm clock minus UTC, measured once per session. GetGameTime only reports hour and minute, so
-- this is rounded to a quarter of an hour and old messages use the current offset.
local function serverOffset()
    if offsetKnown then return offset end
    local hour,minute=Z.Call(GetGameTime)
    local now=Z.Now()
    if type(hour)~='number'or type(minute)~='number'or now<=0 then return nil end
    local h,m=(Z.Call(date,'!%H:%M',now)or''):match('^(%d+):(%d+)$')
    if not h then return nil end
    local diff=(hour*60+minute)-(tonumber(h)*60+tonumber(m))
    if diff>720 then diff=diff-1440 elseif diff<-720 then diff=diff+1440 end
    offset=math.floor(diff/15+.5)*15*60;offsetKnown=true
    return offset
end
function F.Stamp(format,at)
    at=tonumber(at)or 0
    if setting('timeZone')=='server'then
        local shift=serverOffset()
        if shift then return Z.Call(date,'!'..format,at+shift)or''end
    end
    return Z.Call(date,format,at)or''
end
local dayFrom,dayTo,dayKey=0,-1,nil
function F.ResetDayCache()dayFrom,dayTo,dayKey=0,-1,nil end
-- Most messages share a day with their neighbor, so the date call runs only when leaving the
-- cached range. The range stays clear of the edges of the day because of daylight saving changes.
function F.DayKey(at)
    at=tonumber(at)or 0
    if at>=dayFrom and at<dayTo then return dayKey end
    local text=F.Stamp('%Y-%m-%d %H:%M:%S',at)
    local day,h,m,s=text:match('^(%S+) (%d+):(%d+):(%d+)$')
    if not day then return text end
    local start=at-(tonumber(h)*3600+tonumber(m)*60+tonumber(s))
    dayFrom=math.min(at,start+3600);dayTo=math.max(at+1,start+82800);dayKey=day
    return day
end
function F.DayLabel(at)
    local now=Z.Now();local day=F.DayKey(at)
    if day==F.Stamp('%Y-%m-%d',now)then return Z.L('Heute','Today')end
    if day==F.Stamp('%Y-%m-%d',now-86400)then return Z.L('Gestern','Yesterday')end
    return F.Stamp('%d.%m.%Y',at)
end
function F.Time(at,format)
    format=format or setting('timeFormat')or'hm'
    if format=='off'then return''end
    if format=='hms'then return F.Stamp('%H:%M:%S',at)end
    if format=='date'then return F.Stamp('%d.%m.%Y %H:%M',at)end
    if format=='relative'then return F.DayLabel(at)..' '..F.Stamp('%H:%M',at)end
    return F.Stamp('%H:%M',at)
end
function F.FullTime(at)return F.Stamp('%d.%m.%Y %H:%M:%S',at)end
-- Labels -------------------------------------------------------------------------------------
local shortLabels={GUILD={'G','G'},OFFICER={'O','O'},PARTY={'Gr','P'},RAID={'SZ','R'},INSTANCE_CHAT={'I','I'}}
-- What a conversation is called on screen. Its key, target and channel name are never affected.
function F.ConversationLabel(c)
    if not c then return''end
    if c.alias and c.alias~=''then return c.alias end
    if c.kind=='WHISPER'then return F.Name(c.name)end
    if c.kind=='BN_WHISPER'then return c.name end
    if c.kind=='XFACTION'then return Z.L('Gegnerische Fraktion','Opposite faction')end
    local mode=setting('channelLabels')or'full'
    if mode=='full'then return c.name end
    if c.kind=='CHANNEL'then
        local number=mode=='number'and Z.adapter and Z.adapter:ChannelNumber(c.channelName)
        if number then return'['..number..']'end
        return tostring(c.name):match('^[^%s%-]+')or c.name
    end
    local short=shortLabels[c.kind]
    return short and Z.L(short[1],short[2])or c.name
end
-- Text with markup ---------------------------------------------------------------------------
local closers={T='|t',A='|a',K='|k'}
-- Runs fn over the plain stretches of a text and copies every escape sequence untouched, so that
-- links, colors and textures cannot be damaged.
local function mapPlain(text,fn)
    local out={};local pos,n=1,#text
    while pos<=n do
        local bar=text:find('|',pos,true)
        if not bar then out[#out+1]=fn(text:sub(pos));break end
        if bar>pos then out[#out+1]=fn(text:sub(pos,bar-1))end
        local code=text:sub(bar+1,bar+1);local stop
        if code=='H'then
            local open=text:find('|h',bar+2,true)
            local close=open and text:find('|h',open+2,true)
            stop=close and close+1 or n
        elseif code=='c'then stop=math.min(n,bar+9)
        elseif closers[code]then
            local close=text:find(closers[code],bar+2,true)
            stop=close and close+1 or n
        elseif code=='r'or code=='|'or code=='n'then stop=bar+1
        else stop=bar end
        out[#out+1]=text:sub(bar,stop);pos=stop+1
    end
    return table.concat(out)
end
local BARE_DOMAINS={com=true,net=true,org=true,de=true,eu=true,gg=true,io=true,tv=true,gl=true,ly=true,info=true}
local function candidate(text,pos)
    local best,bestStop
    local function consider(a,b)if a and(not best or a<best)then best,bestStop=a,b end end
    consider(text:find('[Hh][Tt][Tt][Pp][Ss]?://[^%s<>"]+',pos))
    consider(text:find('[Ww][Ww][Ww]%.[^%s<>"]+',pos))
    local from=pos
    while true do
        local a,b=text:find('[%w][%w%-%.]*%.%a%a+[^%s<>"]*',from)
        if not a or(best and a>=best)then break end
        local before=a>1 and text:sub(a-1,a-1)or''
        local host=(text:sub(a,b):match('^[%w%-%.]+')or''):gsub('[%.%-]+$','')
        local tld=(host:match('%.(%a+)$')or''):lower()
        -- Not part of an e-mail address or of a word with non-ASCII letters.
        if BARE_DOMAINS[tld]and before~='@'and not before:match('[\128-\255]')then consider(a,b);break end
        from=b+1
    end
    return best,bestStop
end
local function linkifyPlain(text)
    local out={};local pos=1
    while true do
        local a,b=candidate(text,pos)
        if not a then out[#out+1]=text:sub(pos);break end
        local url=text:sub(a,b)
        -- Closing punctuation belongs to the sentence, not to the address.
        local trimmed=url:gsub('[%.,;:!%?%)%]}\'"]+$','')
        out[#out+1]=text:sub(pos,a-1)
        if trimmed==''then out[#out+1]=url
        else
            out[#out+1]='|Hzchaturl:'..trimmed..'|h|cff6fb7ff'..trimmed..'|r|h'
            out[#out+1]=url:sub(#trimmed+1)
        end
        pos=b+1
    end
    return table.concat(out)
end
function F.Linkify(text)
    if type(text)~='string'or text==''then return text end
    return mapPlain(text,linkifyPlain)
end
-- Marks search terms in the plain stretches. Fold keeps the byte length, so positions carry over.
function F.Highlight(text,terms)
    if type(text)~='string'or type(terms)~='table'or #terms==0 then return text end
    return mapPlain(text,function(plain)
        local folded=F.Fold(plain);local out={};local pos=1
        while pos<=#plain do
            local first,last
            for _,term in ipairs(terms)do
                local a,b=folded:find(term,pos,true)
                if a and(not first or a<first)then first,last=a,b end
            end
            if not first then break end
            out[#out+1]=plain:sub(pos,first-1)
            out[#out+1]='|cffff9f1c'..plain:sub(first,last)..'|r'
            pos=last+1
        end
        out[#out+1]=plain:sub(pos)
        return table.concat(out)
    end)
end
-- Copying and quoting ------------------------------------------------------------------------
local function fullSender(conv,msg)
    if msg.outgoing then
        local own=Z.Plain(msg.ownCharacter)
        return own~=''and own or Z.L('Du','You')
    end
    local name=Z.Plain(msg.sender)
    if name==''then name=Z.Plain(conv.name)end
    return name
end
-- mode: text, sender (with name) or time (with date, time and name). Always the complete identity.
function F.MessageLine(conv,msg,mode)
    local text=(Z.Plain(msg.text))
    if msg.context then return'— '..text..' —'end
    if mode=='sender'then return fullSender(conv,msg)..': '..text end
    if mode=='time'then return'['..F.FullTime(msg.at)..'] '..fullSender(conv,msg)..': '..text end
    return text
end
function F.Lines(conv,first,last,mode)
    local lines={}
    for i=first,last do
        local msg=conv.messages[i]
        if msg and not msg.deleted then lines[#lines+1]=F.MessageLine(conv,msg,mode)end
    end
    return table.concat(lines,'\n')
end
-- A large text in an edit box stalls the client, so an export holds a bounded, recent stretch.
local EXPORT_BYTES=60000
function F.Export(conv)
    local lines,bytes,i={},0,#conv.messages
    while i>=1 do
        local msg=conv.messages[i]
        if not msg.deleted then
            local line=F.MessageLine(conv,msg,'time')
            if bytes+#line+1>EXPORT_BYTES then break end
            bytes=bytes+#line+1;lines[#lines+1]=line
        end
        i=i-1
    end
    local ordered={}
    for k=#lines,1,-1 do ordered[#ordered+1]=lines[k]end
    return table.concat(ordered,'\n'),#ordered,#conv.messages
end
local function truncate(text,limit)
    if #text<=limit then return text end
    local cut=limit
    while cut>0 and(text:byte(cut+1)or 0)>=128 and(text:byte(cut+1)or 0)<192 do cut=cut-1 end
    return text:sub(1,cut)..'…'
end
-- Inserted into the composer, never sent by itself. Links become their plain label and a stray
-- pipe is replaced, because an unescaped one makes the client reject the whole message.
function F.Quote(conv,msg,mode)
    mode=mode or setting('quoteFormat')or'sender'
    local text=(Z.Plain(msg.text):gsub('[\r\n]+',' '):gsub('|','/'))
    text=truncate(text,180)
    if mode=='text'then return'"'..text..'" 'end
    local who=(fullSender(conv,msg):gsub('|','/'))
    if mode=='time'then return'> '..who..' ('..F.Stamp('%H:%M',msg.at)..'): '..text..' 'end
    return'> '..who..': '..text..' '
end
