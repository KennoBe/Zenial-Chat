local _,Z=...
local R={};Z.Transcript=R
-- Only the newest messages are indexed when a conversation opens; scrolling towards the top extends
-- the range. Everything stays in the archive, this just keeps opening a huge conversation fast.
-- A jump far back indexes a stretch around its target (windowEnd), which grows the same way.
R.WINDOW=1500
R.WINDOW_STEP=1000
R.AROUND=500
local GROUP_SECONDS=300
local function characters(text)local _,n=text:gsub('[\128-\191]','');return#text-n end
local function estimate(text,width,size,spacing)
    local lines=0
    local plain=Z.Plain(text)
    if plain:find('\n',1,true)then
        for line in(plain..'\n'):gmatch('(.-)\n')do lines=lines+math.max(1,math.ceil(characters(line)*size*.52/math.max(40,width)))end
    else lines=math.max(1,math.ceil(characters(plain)*size*.52/math.max(40,width)))end
    return lines*(size+3+spacing)
end
local function messagePlain(msg)return msg.deleted and Z.L('Nachricht gelöscht','Message deleted')or msg.text or''end
local function avatar(s)
    if s.senderIcon=='none'then return 0 end
    return s.layoutStyle=='compact'and math.min(s.iconSize,24)or s.iconSize
end
local function bubbleLeft(s)return s.senderIcon=='none'and 8 or avatar(s)+14 end
-- With the default settings this is the row height the transcript always had.
local function rowHeight(info,s)
    if info.context then return info.dateHeight+34 end
    if s.layoutStyle=='classic'then return info.dateHeight+info.bodyHeight+3 end
    if s.layoutStyle=='compact'then return info.dateHeight+(info.grouped and 1 or 16)+info.bodyHeight+10+3 end
    return info.dateHeight+(info.grouped and 2 or 20)+info.bodyHeight+16+(s.timeFormat=='off'and 6 or 14)
end
local function groupedWith(previous,msg,s)
    if not s.groupMessages or s.layoutStyle=='classic'or not previous or previous.context or msg.context then return false end
    local last=previous.msg
    return last.sender==msg.sender and(last.outgoing==true)==(msg.outgoing==true)and(tonumber(msg.at)or 0)-(tonumber(last.at)or 0)<=GROUP_SECONDS
end
local function addRow(u,msg,i,width,size,s)
    local plain=messagePlain(msg);local previous=u.rowInfo[i-1]
    local classic=s.layoutStyle=='classic'
    local bodyMax=classic and math.max(90,width-16)or math.max(90,math.floor(width*.79)-bubbleLeft(s))
    local day=Z.Format.DayKey(msg.at)
    local dateHeight=s.dateSeparators and day~=(previous and previous.day)and 26 or 0
    local cached=u.measured[msg.id]
    local bodyHeight=cached and cached.text==plain and cached.height or estimate(plain,bodyMax,size,s.lineSpacing)
    local info={bodyMax=bodyMax,bodyHeight=bodyHeight,dateHeight=dateHeight,day=day,msg=msg,plain=plain,at=msg.at,context=msg.context}
    info.grouped=dateHeight==0 and groupedWith(previous,msg,s)
    info.height=rowHeight(info,s)
    u.rowInfo[i]=info;u.rowMessages[i]=msg
    u.prefix[i+1]=u.prefix[i]+info.height
end
-- True when the rows already indexed are untouched and only new messages were
-- appended, so the index can be extended instead of rebuilt.
local function appendOnly(u,conv,base,count)
    local n=u.indexCount
    if u.indexFull or not n or n<1 or not u.rowInfo or u.indexMessages~=conv.messages or count<=n then return false end
    for i=1,n do
        local info,msg=u.rowInfo[i],conv.messages[base+i]
        if not info or info.msg~=msg or info.at~=msg.at or info.context~=msg.context or info.plain~=messagePlain(msg)then return false end
    end
    return true
end
local function windowFor(total)return total>R.WINDOW and total-R.WINDOW or 0 end
function R.Index(u,conv)
    local width=u.viewport:GetWidth();local s=Z.store.settings;local size=s.fontSize
    local signature=table.concat({conv.key,width,size,s.layoutStyle,s.senderIcon,s.iconSize,s.lineSpacing,s.fontFace,s.fontOutline,s.timeFormat,tostring(s.groupMessages),tostring(s.dateSeparators),tostring(s.urlLinks)},':')
    if u.indexSignature~=signature then u.measured={};u.indexDirty=true;u.indexFull=true;u.indexSignature=signature end
    local total=#conv.messages
    if u.windowKey~=conv.key or(u.windowBase or 0)>=total then u.windowKey=conv.key;u.windowBase=windowFor(total);u.windowEnd=nil;u.indexDirty=true;u.indexFull=true end
    if u.windowEnd and u.windowEnd>=total then u.windowEnd=nil;u.indexDirty=true end
    local base=u.windowBase;local count=(u.windowEnd or total)-base
    if not u.indexDirty and u.indexCount==count then return end
    -- Keep the ID captured at the last render: native backfill has already
    -- mutated the message array by the time this function runs again.
    local oldAnchor=not u.atEnd and u.anchor
    local first=1
    if appendOnly(u,conv,base,count)then first=u.indexCount+1
    else u.prefix={0};u.rowInfo={};u.rowMessages={}end
    for i=first,count do addRow(u,conv.messages[base+i],i,width,size,s)end
    u.indexFull=false
    u.indexMessages=conv.messages;u.indexCount=count;u.indexDirty=false
    u.maximum=math.max(0,u.prefix[#u.prefix]-u.viewport:GetHeight())
    if u.atEnd then u.scroll=u.maximum
    elseif oldAnchor then u.scroll=math.min(u.maximum,Z.Layout.RestoreAnchor(oldAnchor,u.prefix,u.rowMessages))end
end
-- Makes sure a message (a search hit, a remembered position) is inside the indexed range.
function R.PrepareWindow(u,conv,id)
    local total=#conv.messages;local same=u.windowKey==conv.key
    local base=same and u.windowBase or windowFor(total);local stop=same and u.windowEnd or nil
    local index=id and Z.store:IndexOf(conv.key,id)
    if index and(index<=base or(stop and index>stop))then
        if total-index<R.WINDOW then base,stop=windowFor(total),nil
        else base,stop=math.max(0,index-R.AROUND),index+R.AROUND end
    end
    if not same or u.windowBase~=base or u.windowEnd~=stop then
        u.windowKey=conv.key;u.windowBase=base;u.windowEnd=stop;u.indexDirty=true;u.indexFull=true
    end
end
-- Back to the newest message, also out of a stretch further back.
function R.GoNewest(u)
    u.highlightTerms=nil;u.highlightId=nil
    if u.windowEnd then
        local conv=Z.store:Get(Z.store.db.ui.selected)
        u.windowEnd=nil;u.windowBase=windowFor(conv and #conv.messages or 0);u.indexDirty=true;u.indexFull=true;u.atEnd=true
        u.Refresh()
    else u.ScrollTo(u.maximum or 0)end
end
-- Scrolls to a message and leaves the messages before it in view.
function R.Reveal(u,conv,id)
    local index=Z.store:IndexOf(conv.key,id);if not index then return end
    local row=index-(u.windowBase or 0)
    if u.prefix[row]then u.ScrollTo(math.max(0,u.prefix[row]-u.viewport:GetHeight()/3))end
end
local function loadOlder(u)
    u.windowBase=math.max(0,u.windowBase-R.WINDOW_STEP);u.indexDirty=true;u.indexFull=true
end
local function loadNewer(u)
    u.windowEnd=u.windowEnd+R.WINDOW_STEP;u.indexDirty=true;u.indexFull=true
end
local function handleLink(self,link,text,button)
    if not Z.Safe(link,text,button)or type(link)~='string'then return end
    local url=link:match('^zchaturl:(.+)$')
    if url then Z.UI.ShowCopy(url,Z.L('Adresse kopieren · Strg+C','Copy address · Ctrl+C'));return end
    if link:match('^zchattime:')then
        if self.message and IsShiftKeyDown and IsShiftKeyDown()then Z.UI.QuoteMessage(self.message,'time')end
        return
    end
    Z.Call(SetItemRef,link,text,button or'LeftButton',DEFAULT_CHAT_FRAME)
end
local function timeLink(label)return'|Hzchattime:0|h'..label..'|h'end
local function personTooltip(owner,conv,msg)
    local name=msg.outgoing and msg.ownCharacter or msg.sender or conv.name
    if conv.kind=='BN_WHISPER'and not msg.outgoing then name=conv.name end
    local plain=Z.Plain(name);if plain==''then plain=Z.Plain(conv.name)end
    local person=Z.store:Person(name)
    local class=person and person.className
    if not class and msg.senderClass and LOCALIZED_CLASS_NAMES_MALE then class=LOCALIZED_CLASS_NAMES_MALE[msg.senderClass]end
    local parts={}
    if class then parts[#parts+1]=class end
    if person and person.raceName then parts[#parts+1]=person.raceName end
    if conv.kind=='BN_WHISPER'and conv.target then parts[#parts+1]=conv.target end
    Z.Theme.Tooltip(owner,plain,table.concat(parts,' · '))
end
local function handleLinkEnter(self,link)
    self.overLink=true
    if not Z.Safe(link)or type(link)~='string'then return end
    local msg=self.message;local conv=Z.store:Get(Z.store.db.ui.selected)
    if link:match('^zchaturl:')then Z.Theme.Tooltip(self,link:match('^zchaturl:(.+)$')or'',Z.L('Klicken zum Kopieren. Addons können keinen Browser öffnen.','Click to copy. Addons cannot open a browser.'));return end
    if link:match('^zchattime:')then
        if msg then Z.Theme.Tooltip(self,Z.Format.FullTime(msg.at),Z.L('Shift-Klick zitiert die Nachricht in die Eingabe.','Shift-click quotes the message into the input.'))end
        return
    end
    if link:match('^player:')or link:match('^BNplayer:')then
        if msg and conv then personTooltip(self,conv,msg)end
        return
    end
    if link:match('^trade:')then return end
    if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_CURSOR');local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link);if ok then GameTooltip:Show()end end
end
local function handleLinkLeave(self)self.overLink=false;if GameTooltip then GameTooltip:Hide()end end
local function bubble(u,index)
    if u.bubbles[index]then return u.bubbles[index]end
    local T=Z.Theme;local row=CreateFrame('Frame',nil,u.canvas)
    row.date=T.Text(row,'',11,false,'muted');row.date:SetJustifyH('CENTER')
    row.icon=T.Icon(row,{kind='WHISPER'})
    row.author=T.Text(row,'',12,true,'goldBright');row.author:SetWordWrap(false)
    row.bodyFrame=T.Frame(row,'bubble','line');row.body=T.Text(row.bodyFrame,'',14,false,'text');row.body:SetWordWrap(true);row.body:SetNonSpaceWrap(true)
    row.time=T.Text(row,'',10,false,'muted');row.time:SetJustifyH('RIGHT')
    row.context=T.Text(row,'',11,false,'muted');row.context:SetJustifyH('CENTER')
    row:EnableMouse(true);row:SetHyperlinksEnabled(true)
    row:SetScript('OnHyperlinkClick',handleLink)
    row:SetScript('OnHyperlinkEnter',handleLinkEnter)
    row:SetScript('OnHyperlinkLeave',handleLinkLeave)
    row.bodyFrame:SetHyperlinksEnabled(true)
    row.bodyFrame:SetScript('OnHyperlinkClick',handleLink)
    row.bodyFrame:EnableMouse(true)
    row.bodyFrame:SetScript('OnMouseUp',function(self,button)
        if button=='RightButton'and not self.overLink then u.MessageMenu(self,self.message)end
    end)
    row.bodyFrame:SetScript('OnHyperlinkEnter',handleLinkEnter)
    row.bodyFrame:SetScript('OnHyperlinkLeave',handleLinkLeave)
    for _,f in ipairs({row,row.bodyFrame})do
        f:EnableMouseWheel(true);f:SetScript('OnMouseWheel',function(_,delta)u.ScrollTo(u.scroll-delta*60)end)
    end
    u.bubbles[index]=row;return row
end
local function senderClass(conv,msg)
    if msg.senderClass then return msg.senderClass end
    if msg.outgoing then return nil end
    local person=Z.store:Person(msg.sender)
    if person and person.class then return person.class end
    return conv.kind=='WHISPER'and conv.classFile or nil
end
local function placeBubble(u,row,conv,msg,info,w,text,s,highlighted)
    local T=Z.Theme;local style=s.layoutStyle;local own=msg.outgoing==true
    local classic=style=='classic';local compact=style=='compact'
    local class=senderClass(conv,msg)
    local plainName=Z.Format.SenderLabel(conv,msg)
    if msg.raidWarning then plainName=plainName..' · '..Z.L('Schlachtzugswarnung','Raid warning')end
    local stampText=Z.Format.Time(msg.at)..(msg.edited and' · '..Z.L('bearbeitet','edited')or'')
    T.MessageFont(row.body,s.fontSize,false,msg.deleted and'muted'or msg.raidWarning and'goldBright'or'text')
    local bodyText=text
    if classic then
        local nameColor=T.NameHex(s.classColors and class or nil)
        local who=Z.PlayerLink(conv,msg,'|cff'..nameColor..plainName..'|r')
        local icon=s.senderIcon~='none'and not own and T.InlineIcon(s,class,Z.store:Person(msg.sender),math.max(12,s.fontSize))or''
        local prefix=s.timeFormat~='off'and timeLink('|cffa79c84'..stampText..'|r')..' 'or''
        bodyText=prefix..icon..(icon~=''and' 'or'')..who..': '..text
    end
    row.body:SetText(bodyText)
    local bodyWidth=classic and info.bodyMax or math.min(info.bodyMax,math.max(100,math.ceil(row.body:GetUnboundedStringWidth())+2))
    row.body:SetWidth(bodyWidth);row.body:SetHeight(10000)
    local real=math.max(s.fontSize+3,row.body:GetStringHeight())
    local measured=false
    if math.abs(real-info.bodyHeight)>.5 then
        u.measured[msg.id]={text=info.plain,height=real};info.bodyHeight=real;measured=true
    end
    local bg,bgAlpha=own and'own'or'bubble',own and.95 or.9
    if classic then bg,bgAlpha='shell',0 end
    row.bodyFrame.zenialBackgroundKind=bg;row.bodyFrame.opacityMultiplier=bgAlpha
    local color=T.colors[bg];row.bodyFrame:SetBackdropColor(color[1],color[2],color[3],(u.currentAlpha or.94)*bgAlpha)
    local r,g,b=T.Color(highlighted and'gold'or'line')
    row.bodyFrame:SetBackdropBorderColor(r,g,b,(highlighted or not classic)and 1 or 0)
    if classic then
        row.icon:Hide();row.author:Hide();row.time:Hide()
        T.Place(row.bodyFrame,0,info.dateHeight,w,real+3,row);T.Place(row.body,8,1,bodyWidth,real+2,row.bodyFrame)
        return measured
    end
    local bw=bodyWidth+24;local left=bubbleLeft(s)
    local x=own and math.max(4,w-bw-10)or left
    local y=info.dateHeight+(compact and(info.grouped and 1 or 16)or(info.grouped and 2 or 20))
    local pad=compact and 5 or 7
    T.Place(row.bodyFrame,x,y,bw,real+(compact and 10 or 16),row)
    T.Place(row.body,12,pad,bodyWidth,real+2,row.bodyFrame)
    row.author:SetShown(not info.grouped)
    if not info.grouped then
        T.MessageFont(row.author,12,true,'goldBright')
        row.author:SetText((Z.PlayerLink(conv,msg,plainName)));row.author:SetJustifyH(own and'RIGHT'or'LEFT')
        if compact and s.timeFormat~='off'then T.Place(row.author,x,info.dateHeight,math.max(40,bw-90),16,row)
        else T.Place(row.author,x,info.dateHeight,bw,18,row)end
        T.NameColor(row.author,s.classColors and class or nil)
    end
    local size=avatar(s)
    if own or size==0 or info.grouped then row.icon:Hide()
    else
        row.icon:Show();T.SetSenderIcon(row.icon,s,conv,class,Z.store:Person(msg.sender))
        T.Place(row.icon,5,compact and info.dateHeight or y-8,size,size,row)
    end
    local showTime=s.timeFormat~='off'and not(compact and info.grouped)
    row.time:SetShown(showTime)
    if showTime then
        row.time:SetText(timeLink(stampText))
        if compact then T.Place(row.time,x,info.dateHeight+1,bw,14,row)
        else T.Place(row.time,x,y+real+18,bw,14,row)end
    end
    return measured
end
function R.Render(u,secondPass)
    local conv=Z.store:Get(Z.store.db.ui.selected)
    if not conv then for _,row in ipairs(u.bubbles)do row:Hide()end;return end
    -- Inside a stretch further back the newest message is not on screen, whatever the scrollbar says.
    if u.windowEnd then u.atEnd=false end
    R.Index(u,conv)
    -- Near an edge of the indexed range: extend it. The anchor keeps the reading position.
    local nearTop=(u.windowBase or 0)>0 and not u.atEnd and(u.scroll or 0)<=u.viewport:GetHeight()
    local nearBottom=u.windowEnd and(u.maximum or 0)-(u.scroll or 0)<=u.viewport:GetHeight()
    if nearTop or nearBottom then
        -- The anchor of the last render may be far away: the scroll position has moved since then.
        u.anchor=Z.Layout.CaptureAnchor(u.prefix,u.scroll,u.rowMessages)
        if nearTop then loadOlder(u)end
        if nearBottom then loadNewer(u)end
        R.Index(u,conv)
    end
    local T=Z.Theme;local h=u.viewport:GetHeight();local w=u.viewport:GetWidth();local s=Z.store.settings
    u.scroll=math.max(0,math.min(u.maximum or 0,u.scroll or 0))
    local first,last=Z.Layout.VisibleRange(u.prefix,u.scroll,h,2);local used=0;local firstChanged
    for i=first,last do
        local info=u.rowInfo[i];local msg=info and info.msg
        if msg and info then
            used=used+1;local row=bubble(u,used);local top=u.prefix[i]-u.scroll
            T.Place(row,0,top,w,info.height,u.canvas);row:Show()
            row.message=msg
            if info.dateHeight>0 then
                row.date:SetText(Z.Format.DayLabel(msg.at));T.Place(row.date,8,2,w-16,20,row);row.date:Show()
            else row.date:Hide()end
            if msg.context then
                row.icon:Hide();row.author:Hide();row.bodyFrame:Hide();row.time:Hide();row.context:Show()
                row.context:SetText(Z.Plain(msg.text));T.Place(row.context,12,info.dateHeight+5,w-24,22,row)
            else
                row.context:Hide();row.bodyFrame:Show();row.author:Show();row.time:Show()
                -- Rows are recycled: a link hovered in the previous message no longer exists here.
                if row.bodyFrame.message~=msg then row.bodyFrame.message=msg;row.bodyFrame.overLink=false end
                local text=msg.deleted and Z.L('Nachricht gelöscht','Message deleted')or msg.text or''
                if not msg.deleted then
                    if s.urlLinks then text=Z.Format.Linkify(text)end
                    if u.highlightKey==conv.key and u.highlightTerms then text=Z.Format.Highlight(text,u.highlightTerms)end
                end
                local highlighted=msg.id==u.highlightId or msg.id==u.rangeStart
                if placeBubble(u,row,conv,msg,info,w,text,s,highlighted)then
                    info.height=rowHeight(info,s);if not firstChanged then firstChanged=i end
                end
            end
        end
    end
    for i=used+1,#u.bubbles do u.bubbles[i]:Hide()end
    if firstChanged then
        -- Measured heights differ from the estimate: only the offsets after them move.
        local oldAnchor=not u.atEnd and u.anchor
        for i=firstChanged,#u.rowInfo do u.prefix[i+1]=u.prefix[i]+u.rowInfo[i].height end
        u.maximum=math.max(0,u.prefix[#u.prefix]-h)
        if u.atEnd then u.scroll=u.maximum
        elseif oldAnchor then u.scroll=math.min(u.maximum,Z.Layout.RestoreAnchor(oldAnchor,u.prefix,u.rowMessages))end
        if not secondPass then return R.Render(u,true)end
        u.dirty=true
    end
    u.atEnd=(u.maximum or 0)-u.scroll<=2 and not u.windowEnd
    u.scrollBarUpdating=true;u.scrollbar:SetMinMaxValues(0,math.max(1,u.maximum or 0));u.scrollbar:SetValue(u.scroll);u.scrollBarUpdating=false
    u.scrollbar:SetShown((u.maximum or 0)>0)
    local unread=tonumber(conv.unread)or 0
    u.newest.label:SetText(unread>0 and string.format(Z.L('%d neue · Zu den neuesten Nachrichten','%d new · Go to newest messages'),unread)or Z.L('Zu den neuesten Nachrichten','Go to newest messages'))
    u.newest:SetShown(not u.atEnd and#conv.messages>0)
    u.anchor=Z.Layout.CaptureAnchor(u.prefix,u.scroll,u.rowMessages)
    if Z.IsVisibleAtEnd(conv.key)then Z.store:MarkRead(conv.key)end
    u.empty:SetShown(#conv.messages==0)
end
function R.Build(u)
    u.viewport=CreateFrame('ScrollFrame',nil,u.chatPanel);u.viewport:SetClipsChildren(true)
    u.canvas=CreateFrame('Frame',nil,u.viewport);u.viewport:SetScrollChild(u.canvas)
    u.bubbles={};u.prefix={0};u.rowMessages={};u.scroll=0;u.atEnd=true;u.measured={};u.indexDirty=true;u.indexFull=true
    u.viewport:EnableMouseWheel(true);u.viewport:SetScript('OnMouseWheel',function(_,delta)u.ScrollTo(u.scroll-delta*60)end)
    u.scrollbar=CreateFrame('Slider',nil,u.chatPanel,'BackdropTemplate');Z.Theme.Panel(u.scrollbar,'field','line')
    u.scrollbar:SetOrientation('VERTICAL');u.scrollbar:SetValueStep(1);u.scrollbar:SetThumbTexture('Interface\\Buttons\\UI-ScrollBar-Knob')
    u.scrollbar:SetScript('OnValueChanged',function(_,value)if not u.scrollBarUpdating then u.ScrollTo(value)end end)
    u.empty=Z.Theme.Text(u.viewport,Z.L('Hier beginnt euer Gespräch.','Your conversation starts here.'),14,false,'muted');u.empty:SetJustifyH('CENTER')
    u.newest=Z.Theme.Button(u.chatPanel,Z.L('Zu den neuesten Nachrichten','Go to newest messages'),function()R.GoNewest(u)end,'own')
    u.newest:Hide()
end
