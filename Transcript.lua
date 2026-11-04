local _,Z=...
local R={};Z.Transcript=R
local function stamp(at,format)return Z.Call(date,format,tonumber(at)or 0)or''end
local function characters(text)local _,n=text:gsub('[\128-\191]','');return#text-n end
local function estimate(text,width,size)
    local lines=0
    for line in(Z.Plain(text)..'\n'):gmatch('(.-)\n')do lines=lines+math.max(1,math.ceil(characters(line)*size*.52/math.max(40,width)))end
    return lines*(size+3)
end
local function messagePlain(msg)return msg.deleted and Z.L('Nachricht gelöscht','Message deleted')or msg.text or''end
local function addRow(u,msg,i,width,size)
    local plain=messagePlain(msg);local previous=u.rowInfo[i-1]
    local bodyMax=math.max(90,math.floor(width*.79)-48)
    local day=stamp(msg.at,'%Y-%m-%d');local dateHeight=day~=(previous and previous.day)and 26 or 0
    local cached=u.measured[msg.id];local bodyHeight=cached and cached.text==plain and cached.height or estimate(plain,bodyMax,size)
    local height=dateHeight+22+bodyHeight+28
    if msg.context then height=dateHeight+34 end
    u.rowInfo[i]={bodyMax=bodyMax,bodyHeight=bodyHeight,dateHeight=dateHeight,day=day,height=height,msg=msg,plain=plain,at=msg.at,context=msg.context}
    u.prefix[i+1]=u.prefix[i]+height
end
-- True when the rows already indexed are untouched and only new messages were
-- appended, so the index can be extended instead of rebuilt.
local function appendOnly(u,conv)
    local n=u.indexCount
    if u.indexFull or not n or n<1 or not u.rowInfo or u.indexMessages~=conv.messages or #conv.messages<=n then return false end
    for i=1,n do
        local info,msg=u.rowInfo[i],conv.messages[i]
        if not info or info.msg~=msg or info.at~=msg.at or info.context~=msg.context or info.plain~=messagePlain(msg)then return false end
    end
    return true
end
function R.Index(u,conv)
    local width=u.viewport:GetWidth();local size=Z.store.settings.fontSize
    local signature=conv.key..':'..width..':'..size
    if u.indexSignature~=signature then u.measured={};u.indexDirty=true;u.indexFull=true;u.indexSignature=signature end
    if not u.indexDirty and u.indexCount==#conv.messages then return end
    -- Keep the ID captured at the last render: native backfill has already
    -- mutated the message array by the time this function runs again.
    local oldAnchor=not u.atEnd and u.anchor
    local first=1
    if appendOnly(u,conv)then first=u.indexCount+1
    else u.prefix={0};u.rowInfo={}end
    for i=first,#conv.messages do addRow(u,conv.messages[i],i,width,size)end
    u.indexFull=false
    u.indexMessages=conv.messages;u.indexCount=#conv.messages;u.indexDirty=false
    u.maximum=math.max(0,u.prefix[#u.prefix]-u.viewport:GetHeight())
    if u.atEnd then u.scroll=u.maximum
    elseif oldAnchor then u.scroll=math.min(u.maximum,Z.Layout.RestoreAnchor(oldAnchor,u.prefix,conv.messages))end
end
local function bubble(u,index)
    if u.bubbles[index]then return u.bubbles[index]end
    local T=Z.Theme;local row=CreateFrame('Frame',nil,u.canvas)
    row.date=T.Text(row,'',11,false,'muted');row.date:SetJustifyH('CENTER')
    row.icon=T.Icon(row,{kind='WHISPER'})
    row.author=T.Text(row,'',12,true,'goldBright');row.author:SetWordWrap(false)
    row.bodyFrame=T.Frame(row,'bubble','line');row.body=T.Text(row.bodyFrame,'',14,false,'text');row.body:SetWordWrap(true);row.body:SetNonSpaceWrap(true)
    row.time=T.Text(row,'',10,false,'muted');row.time:SetJustifyH('RIGHT')
    row.context=T.Text(row,'',11,false,'muted');row.context:SetJustifyH('CENTER')
    row.bodyFrame:SetHyperlinksEnabled(true)
    row.bodyFrame:SetScript('OnHyperlinkClick',function(_,link,text,button)
        if Z.Safe(link,text,button)then Z.Call(SetItemRef,link,text,button or'LeftButton',DEFAULT_CHAT_FRAME)end
    end)
    row.bodyFrame:SetScript('OnHyperlinkEnter',function(self,link)
        if not Z.Safe(link)or type(link)~='string'or link:match('^trade:')or link:match('^player:')or link:match('^BNplayer:')then return end
        if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_CURSOR');local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link);if ok then GameTooltip:Show()end end
    end)
    row.bodyFrame:SetScript('OnHyperlinkLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    for _,f in ipairs({row,row.bodyFrame})do
        f:EnableMouseWheel(true);f:SetScript('OnMouseWheel',function(_,delta)u.ScrollTo(u.scroll-delta*60)end)
    end
    u.bubbles[index]=row;return row
end
function R.Render(u,secondPass)
    local conv=Z.store:Get(Z.store.db.ui.selected)
    if not conv then for _,row in ipairs(u.bubbles)do row:Hide()end;return end
    R.Index(u,conv)
    local T=Z.Theme;local h=u.viewport:GetHeight();local w=u.viewport:GetWidth()
    u.scroll=math.max(0,math.min(u.maximum or 0,u.scroll or 0))
    local first,last=Z.Layout.VisibleRange(u.prefix,u.scroll,h,2);local used=0;local measuredChanged=false
    for i=first,last do
        local msg=conv.messages[i];local info=u.rowInfo[i]
        if msg and info then
            used=used+1;local row=bubble(u,used);local top=u.prefix[i]-u.scroll
            T.Place(row,0,top,w,info.height,u.canvas);row:Show()
            if info.dateHeight>0 then
                local day=info.day==stamp(Z.Now(),'%Y-%m-%d')and Z.L('Heute','Today')or stamp(msg.at,'%d.%m.%Y')
                row.date:SetText(day);T.Place(row.date,8,2,w-16,20,row);row.date:Show()
            else row.date:Hide()end
            if msg.context then
                row.icon:Hide();row.author:Hide();row.bodyFrame:Hide();row.time:Hide();row.context:Show()
                row.context:SetText(Z.Plain(msg.text));T.Place(row.context,12,info.dateHeight+5,w-24,22,row)
            else
                row.context:Hide();row.bodyFrame:Show();row.author:Show();row.time:Show()
                local own=msg.outgoing==true;local text=msg.deleted and Z.L('Nachricht gelöscht','Message deleted')or msg.text or''
                T.Font(row.body,Z.store.settings.fontSize,false,msg.deleted and'muted'or'text');row.body:SetText(text)
                row.body:SetWidth(info.bodyMax);row.body:SetHeight(10000)
                local real=math.max(Z.store.settings.fontSize+3,row.body:GetStringHeight())
                if math.abs(real-info.bodyHeight)>.5 then
                    u.measured[msg.id]={text=text,height=real};measuredChanged=true
                end
                local plainWidth=math.min(info.bodyMax,math.max(100,characters(Z.Plain(text))*Z.store.settings.fontSize*.53))
                local bodyWidth=math.min(info.bodyMax,plainWidth);local bw=bodyWidth+24
                local x=own and math.max(4,w-bw-10)or 48;local y=info.dateHeight+20
                T.Place(row.bodyFrame,x,y,bw,info.bodyHeight+16,row)
                row.bodyFrame.zenialBackgroundKind=own and'own'or'bubble'
                row.bodyFrame.opacityMultiplier=own and.55 or.3
                local color=T.colors[row.bodyFrame.zenialBackgroundKind];row.bodyFrame:SetBackdropColor(color[1],color[2],color[3],(u.currentAlpha or.94)*row.bodyFrame.opacityMultiplier)
                T.Place(row.body,12,7,bodyWidth,info.bodyHeight+2,row.bodyFrame)
                -- Measure against precisely the width used by the native FontString.
                local finalHeight=math.max(Z.store.settings.fontSize+3,row.body:GetStringHeight())
                if math.abs(finalHeight-info.bodyHeight)>.5 then u.measured[msg.id]={text=text,height=finalHeight};measuredChanged=true end
                local name=own and(Z.L('Du','You')..(msg.ownCharacter and' · '..msg.ownCharacter or''))or(msg.sender or conv.name)
                row.author:SetText(name);row.author:SetJustifyH(own and'RIGHT'or'LEFT');T.Place(row.author,x,info.dateHeight,bw,18,row)
                T.NameColor(row.author,msg.senderClass or conv.classFile)
                if own then row.icon:Hide()else row.icon:Show();T.SetIcon(row.icon,{kind=conv.kind,classFile=msg.senderClass or conv.classFile});T.Place(row.icon,5,y-8,34,34,row)end
                row.time:SetText(stamp(msg.at,'%H:%M')..(msg.edited and' · '..Z.L('bearbeitet','edited')or''))
                T.Place(row.time,x,y+info.bodyHeight+18,bw,14,row)
            end
        end
    end
    for i=used+1,#u.bubbles do u.bubbles[i]:Hide()end
    if measuredChanged and not secondPass then u.indexDirty=true;u.indexFull=true;R.Index(u,conv);return R.Render(u,true)end
    u.atEnd=(u.maximum or 0)-u.scroll<=2
    u.scrollBarUpdating=true;u.scrollbar:SetMinMaxValues(0,math.max(1,u.maximum or 0));u.scrollbar:SetValue(u.scroll);u.scrollBarUpdating=false
    u.scrollbar:SetShown((u.maximum or 0)>0)
    u.newest:SetShown(not u.atEnd and#conv.messages>0)
    u.anchor=Z.Layout.CaptureAnchor(u.prefix,u.scroll,conv.messages)
    if Z.IsVisibleAtEnd(conv.key)then Z.store:MarkRead(conv.key)end
    u.empty:SetShown(#conv.messages==0)
end
function R.Build(u)
    u.viewport=CreateFrame('ScrollFrame',nil,u.chatPanel);u.viewport:SetClipsChildren(true)
    u.canvas=CreateFrame('Frame',nil,u.viewport);u.viewport:SetScrollChild(u.canvas)
    u.bubbles={};u.prefix={0};u.scroll=0;u.atEnd=true;u.measured={};u.indexDirty=true;u.indexFull=true
    u.viewport:EnableMouseWheel(true);u.viewport:SetScript('OnMouseWheel',function(_,delta)u.ScrollTo(u.scroll-delta*60)end)
    u.scrollbar=CreateFrame('Slider',nil,u.chatPanel,'BackdropTemplate');Z.Theme.Panel(u.scrollbar,'field','line')
    u.scrollbar:SetOrientation('VERTICAL');u.scrollbar:SetValueStep(1);u.scrollbar:SetThumbTexture('Interface\\Buttons\\UI-ScrollBar-Knob')
    u.scrollbar:SetScript('OnValueChanged',function(_,value)if not u.scrollBarUpdating then u.ScrollTo(value)end end)
    u.empty=Z.Theme.Text(u.viewport,Z.L('Hier beginnt euer Gespräch.','Your conversation starts here.'),14,false,'muted');u.empty:SetJustifyH('CENTER')
    u.newest=Z.Theme.Button(u.chatPanel,Z.L('Zu den neuesten Nachrichten','Go to newest messages'),function()u.ScrollTo(u.maximum or 0)end,'own')
    u.newest:Hide()
end
