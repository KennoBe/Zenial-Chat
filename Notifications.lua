local _,Z=...
local N={};Z.Notifications=N
-- PlaySound takes a SoundKit id only; no unchecked channel argument, silent if the kit is missing.
function N.PlayTell()
    local kit=type(SOUNDKIT)=='table'and SOUNDKIT.TELL_MESSAGE
    if kit and PlaySound then Z.Call(PlaySound,kit)end
end
-- At most one sound per second for incoming messages, so a burst does not ping repeatedly.
-- The options test button calls PlayTell directly and is not limited.
local SOUND_INTERVAL=1
-- Sounds offered in the options, as far as this client defines them. Volume is not selectable:
-- PlaySound only takes a sound kit and a channel.
N.SOUNDS={{'TELL_MESSAGE','Flüstern','Whisper'},{'UI_BNET_TOAST','Battle.net','Battle.net'},{'RAID_WARNING','Schlachtzugswarnung','Raid warning'},
    {'READY_CHECK','Bereitschaftscheck','Ready check'},{'IG_PLAYER_INVITE','Einladung','Invitation'},{'MAP_PING','Kartensignal','Map ping'},
    {'LFG_ROLE_CHECK','Rollencheck','Role check'},{'ALARM_CLOCK_WARNING_2','Wecker','Alarm clock'}}
local DEFAULT_KITS={raidWarning='RAID_WARNING'}
function N.KitName(category,pref)
    local name=pref and pref.soundKit or DEFAULT_KITS[category]or'TELL_MESSAGE'
    return type(SOUNDKIT)=='table'and SOUNDKIT[name]and name or'TELL_MESSAGE'
end
function N.PlayKit(name)
    local kit=type(SOUNDKIT)=='table'and SOUNDKIT[name]
    if kit and PlaySound then Z.Call(PlaySound,kit)end
end
local function playIncoming(category,pref)
    local now=GetTime()
    if N.lastIncomingSound and now-N.lastIncomingSound<SOUND_INTERVAL then return end
    N.lastIncomingSound=now;N.PlayKit(N.KitName(category,pref))
end
local function inCombat()
    return Z.Call(UnitAffectingCombat,'player')==true or Z.Call(InCombatLockdown)==true
end
function N.Incoming(conv,message,added)
    if not added or not conv or not message or message.outgoing or message.context or message.deleted then return end
    if Z.IsVisibleAtEnd(conv.key)then return end
    local category=Z.Store.Group(conv.kind);if category=='people'then category=conv.kind=='BN_WHISPER'and'bnet'or'whispers'end
    if message.raidWarning then category='raidWarning'end
    local pref=Z.store.settings.notifications[category]or{}
    -- A conversation set to "always" alerts whatever its chat type does; muting still wins.
    local always=conv.notify=='always'
    local quiet=conv.muted or Z.store.settings.suppressInCombat and inCombat()
    if not quiet then
        if pref.sound or always then playIncoming(category,pref)end
        if pref.toast or always then N.Toast(conv,message)end
    end
    if Z.store.settings.autoOpen and(conv.kind=='WHISPER'or conv.kind=='BN_WHISPER')then
        -- Opening is explicitly opt-in; never change an already visible chat, steal focus or open in combat.
        if not inCombat()and(not Z.UI.frame or not Z.UI.frame:IsShown())then Z.UI.Select(conv.key)end
    end
end
N.DEFAULT_POS={point='TOPRIGHT',relPoint='TOPRIGHT',x=-28,y=-140}
local FADE_SECONDS=.35
-- Saved position if present and plausibly on screen; otherwise the unchanged default anchor.
local function position()
    local pos=Z.store and Z.store.settings.toastPos
    if type(pos)=='table'and UIParent then
        local w,h=UIParent:GetWidth(),UIParent:GetHeight()
        if type(w)=='number'and type(h)=='number'and math.abs(pos.x)<=w and math.abs(pos.y)<=h then return pos end
    end
    return N.DEFAULT_POS
end
function N.ApplyPosition()
    local f=N.frame;if not f then return end
    local pos=position();f:ClearAllPoints();f:SetPoint(pos.point,UIParent,pos.relPoint,pos.x,pos.y)
end
function N.SavePosition()
    local f=N.frame;if not f then return end
    local point,relative,relPoint,x,y=f:GetPoint(1)
    if relative~=UIParent and relative~=nil then N.ApplyPosition();return end -- only UIParent-relative anchors are stored
    Z.store.settings.toastPos={point=point,relPoint=relPoint or point,x=x,y=y}
end
function N.ResetPosition()
    Z.store.settings.toastPos=nil;N.ApplyPosition()
end
-- Alpha fade through an AnimationGroup when the client offers it; otherwise hide immediately as before.
local function buildFade(f)
    if type(f.CreateAnimationGroup)~='function'then return end
    local ok,group=pcall(f.CreateAnimationGroup,f);if not ok or type(group)~='table'then return end
    local ok2,alpha=pcall(group.CreateAnimation,group,'Alpha');if not ok2 or type(alpha)~='table'then return end
    local ok3=pcall(function()
        alpha:SetFromAlpha(1);alpha:SetToAlpha(0);alpha:SetDuration(FADE_SECONDS);alpha:SetOrder(1)
        group:SetScript('OnFinished',function()N.fading=false;f:Hide();f:SetAlpha(1)end)
    end)
    if ok3 then f.fade=group end
end
local function finish(f)
    if f.fade and not N.fading then N.fading=true;f.fade:Play()
    elseif not f.fade then f:Hide()end
end
function N.Duration()return Z.store and Z.store.settings.toastDuration or 5 end
N.sent={} -- attempt id -> {key,text} of what the reply line sent; checked once after a while
local ROW_Y,PLAIN_ROW_Y=104,78
local function replyConversation(conv)
    if not conv.key or not Z.store or conv.kind~='WHISPER'and conv.kind~='BN_WHISPER'then return nil end
    local c=Z.store:Get(conv.key);local pref=Z.store.settings.notifications[conv.kind=='BN_WHISPER'and'bnet'or'whispers']
    return c and c.kind==conv.kind and pref and pref.reply==true and c or nil
end
local function subLine(conv,person)
    local k=conv.kind
    if k=='WHISPER'then
        local name=person and person.className;local word=Z.L('Flüstern','Whisper')
        return type(name)=='string'and name~=''and name..' · '..word or word
    elseif k=='BN_WHISPER'then return type(conv.target)=='string'and conv.target or''
    elseif k=='GUILD'or k=='OFFICER'then return Z.L('Gilde','Guild')
    elseif k=='PARTY'or k=='RAID'or k=='INSTANCE_CHAT'then return Z.L('Gruppe','Group')
    elseif k=='CHANNEL'then return Z.L('Kanal','Channel')
    elseif k=='XFACTION'then return Z.L('Gegnerische Fraktion','Opposite faction')end
    return''
end
-- Busy: the player is typing, an error waits for a decision, or the banner is being moved.
function N.Busy()
    local f=N.frame
    return f~=nil and f:IsShown()and(f.edit:HasFocus()or N.state=='error'or N.dragging==true)or false
end
local function updateField(f)
    local text=f.edit:GetText();f.hint:SetShown(text==''and not f.edit:HasFocus())
    f.count:SetText(#text..'/'..f.max)
    if #text>f.max then f.count:SetTextColor(Z.Theme.Color('red'))else f.count:SetTextColor(Z.Theme.Color('muted'))end
end
-- Heights: 80 plain, 108 with the reply line, plus the bottom row (focus or error).
local function layout(f)
    local T=Z.Theme;local reply=f.replyKey~=nil;local failed=N.state=='error'
    local row=failed or f.edit:HasFocus()and reply;local y=reply and ROW_Y or PLAIN_ROW_Y
    f.editBg:SetShown(reply);f:SetHeight(row and y+20 or reply and 108 or 80)
    f.keys:SetShown(row and not failed);f.count:SetShown(row and not failed)
    f.open:SetShown(failed);f.native:SetShown(failed and f.nativeOffered==true)
    T.Place(f.keys,10,y,200,16,f);T.Place(f.count,230,y,80,16,f)
    T.Place(f.open,10,y-2,f.nativeOffered and 140 or 170,20,f);T.Place(f.native,156,y-2,154,20,f)
end
local function setBody(f,text,color)
    f.body:SetText(text);f.body:SetTextColor(Z.Theme.Color(color or'text'))
end
local function showError(f,message,native)
    N.state='error';f.nativeOffered=native==true;setBody(f,message,'red');layout(f)
end
-- Closes the current notice. Task 3 lets the next waiting conversation move up here.
function N.Dismiss()
    if N.frame then N.frame:Hide()end
end
function N.HideAll()
    if N.frame then N.frame:Hide()end
end
local function smallButton(parent,label,fn)
    local b=Z.Theme.Button(parent,label,fn);Z.Theme.Font(b.label,11,true,'text');b.label:SetJustifyH('CENTER');b.label:SetJustifyV('MIDDLE');b:Hide();return b
end
function N.Submit()
    local f=N.frame;local c=f and f.replyKey and Z.store:Get(f.replyKey);if not c then return end
    local text=f.edit:GetText();if not text:find('%S')then return end
    if N.state=='error'then N.state=nil;setBody(f,f.message or'')end
    if Z.adapter:Locked()then showError(f,Z.L('Senden ist gerade gesperrt.','Sending is locked right now.'),true);return end
    local ok,err,id=Z.adapter:Send(c,text)
    if not ok then showError(f,Z.L('Nicht gesendet: ','Not sent: ')..tostring(err or''));return end
    Z.store:AddSent(c.key,text);Z.store:SetDraft(c.key,'')
    if id then N.sent[id]={key=c.key,text=text}end
    f.edit:ClearFocus();N.Dismiss()
    local timer=C_Timer;if id and type(timer)=='table'and type(timer.After)=='function'then
        pcall(timer.After,11,function()N.CheckAttempt(id)end)
    end
end
local function buildFrame()
    local T=Z.Theme
    local f=T.Frame(UIParent,'shell','gold');N.frame=f;f:SetSize(320,80);f:SetFrameStrata('DIALOG')
    f:SetClampedToScreen(true);f:SetMovable(true);N.ApplyPosition();buildFade(f)
    f.icon=T.Icon(f,{});T.Place(f.icon,10,8,26,26,f)
    f.title=T.Text(f,'',13,true,'goldBright');T.Place(f.title,44,7,236,16,f)
    f.sub=T.Text(f,'',11,false,'muted');T.Place(f.sub,44,23,236,14,f)
    f.body=T.Text(f,'',12,false,'text');f.body:SetWordWrap(true);T.Place(f.body,10,42,300,30,f)
    if f.body.SetMaxLines then f.body:SetMaxLines(2)end
    f.edit,f.editBg=T.Input(f);T.Font(f.edit,12,false,'text');T.Place(f.editBg,10,76,300,24,f);f.max=255
    f.edit:SetTextInsets(8,8,2,2) -- the shared input insets are made for taller fields
    f.hint=T.Text(f.editBg,Z.L('Antworten …','Reply …'),12,false,'muted');T.Place(f.hint,12,6,250,14,f.editBg)
    f.keys=T.Text(f,Z.L('Enter sendet · Esc verlässt','Enter sends · Esc leaves'),11,false,'muted')
    f.count=T.Text(f,'',11,false,'muted');f.count:SetJustifyH('RIGHT')
    f.open=smallButton(f,Z.L('Im Chatfenster öffnen','Open in chat window'),function()
        local key=f.key;N.HideAll();if key then Z.UI.Select(key)end
    end)
    f.native=smallButton(f,Z.L('In der Chatzeile öffnen','Open in chat line'),function()
        local c=f.replyKey and Z.store:Get(f.replyKey);if not c then return end
        if Z.adapter:OpenNative(c,f.edit:GetText())then Z.store:SetDraft(c.key,'');N.Dismiss()
        else showError(f,Z.L('Die Chatzeile ließ sich nicht öffnen.','The chat line could not be opened.'),true)end
    end)
    f.edit:SetScript('OnTextChanged',function()
        if N.loading or not f.replyKey then return end
        Z.store:SetDraft(f.replyKey,f.edit:GetText());updateField(f)
    end)
    f.edit:SetScript('OnEditFocusGained',function()
        local u=Z.UI
        -- The open main window with this conversation takes over: one place to type.
        if f.replyKey and u and u.frame and u.input and u.frame:IsShown()and Z.store.db.ui.selected==f.replyKey then
            f.edit:ClearFocus();u.RequestRefresh('draft',f.replyKey);u.input:SetFocus();return
        end
        layout(f);updateField(f)
    end)
    f.edit:SetScript('OnEditFocusLost',function()N.left=N.Duration();layout(f);updateField(f)end)
    f.edit:SetScript('OnEnterPressed',function()N.Submit()end)
    f.edit:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
    N.edit=f.edit
    -- Left-drag moves the toast; a plain click still opens the conversation.
    f:EnableMouse(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function(self)N.dragging=true;N.dragged=true;self:StartMoving()end)
    f:SetScript('OnDragStop',function(self)self:StopMovingOrSizing();N.dragging=false;N.SavePosition()end)
    f:SetScript('OnMouseUp',function()
        if N.dragged then N.dragged=false;return end
        local key=f.key;N.HideAll();if key then Z.UI.Select(key)end
    end)
    f:SetScript('OnUpdate',function(_,elapsed)
        if N.Busy()then N.left=N.Duration();return end -- stay visible while typing, on an error or while being moved
        if N.fading then return end
        N.left=N.left-elapsed;if N.left<=0 then finish(f)end
    end)
    f:SetScript('OnHide',function(self)
        if self.fade then self.fade:Stop()end;N.fading=false;N.dragging=false;N.state=nil;self:SetAlpha(1);self.edit:ClearFocus()
    end)
    f.close=Z.CloseButton(f,function()N.Dismiss()end,Z.L('Schließen','Close'));T.Place(f.close,288,6,25,24,f)
    return f
end
-- Fills the banner for a conversation: icon, names, reply line. The message body is set by the caller.
local function present(f,conv)
    local T=Z.Theme;local store=Z.store
    local person=store and type(conv.name)=='string'and store:Person(conv.name)or nil
    local class=conv.classFile or person and person.class
    T.SetIcon(f.icon,{kind=conv.kind,classFile=class})
    f.key=conv.key;f.title:SetText(Z.Format.ConversationLabel(conv))
    if class then T.NameColor(f.title,class)else f.title:SetTextColor(T.Color('goldBright'))end
    f.sub:SetText(subLine(conv,person));N.state=nil;f.nativeOffered=false
    local c=replyConversation(conv);f.replyKey=c and c.key or nil
    if c then
        f.max=c.kind=='BN_WHISPER'and 500 or 255
        if f.edit.SetMaxBytes then f.edit:SetMaxBytes(f.max+1)end
        N.loading=true;f.edit:SetText(c.draft or'');N.loading=false;updateField(f)
    end
    layout(f)
end
local function show(f)
    N.left=N.Duration();N.fading=false;N.dragged=false;if f.fade then f.fade:Stop()end;f:SetAlpha(1);f:Show()
end
function N.Toast(conv,message)
    local f=N.frame or buildFrame()
    -- Typing, an error or a drag in progress is never taken away by a notice from someone else.
    if conv.key and N.Busy()and f.key~=conv.key then return end
    -- A burst from one conversation updates one notice and counts up instead of flickering.
    local running=f:IsShown()and conv.key and f.key==conv.key
    N.burst=running and(N.burst or 1)+1 or 1
    local keepBody=running and N.state=='error'
    if not running or not N.Busy()then present(f,conv)end
    local label=Z.Format.ConversationLabel(conv)
    f.title:SetText(N.burst>1 and label..' ('..N.burst..')'or label)
    f.message=(Z.Plain(message.text):gsub('[\r\n]+',' '))
    if not keepBody then setBody(f,f.message)end
    if running and N.Busy()then return end
    show(f)
end
-- A failed send that this banner made: show it again with the reason and give the text back.
function N.OnRecovery(key)
    if not key or not Z.adapter or not Z.store then return end
    for id,sent in pairs(N.sent)do
        if sent.key==key and Z.adapter:AttemptState(id)=='failed'then
            local reason
            for _,r in ipairs(Z.adapter:Recoveries(key))do if r.id==id and not r.unconfirmed then reason=r.error end end
            local c=Z.store:Get(key)
            if reason and c then
                local f=N.frame or buildFrame()
                if N.Busy()and f.key~=key then return end -- stays in the window's recovery line
                N.sent[id]=nil
                if(c.draft or'')==''then Z.store:SetDraft(key,sent.text);Z.adapter:DismissRecovery(id)end
                present(f,c);show(f);showError(f,reason,false)
            end
            return
        end
    end
end
-- Eleven seconds after sending: no echo and no error means the delivery is unconfirmed.
function N.CheckAttempt(id)
    local sent=N.sent[id];N.sent[id]=nil
    if not sent or not Z.adapter or not Z.store or Z.adapter:AttemptState(id)~='pending'then return end
    local c=Z.store:Get(sent.key);if not c then return end
    local f=N.frame or buildFrame();if N.Busy()and f.key~=sent.key then return end
    present(f,c);show(f);showError(f,Z.L('Zustellung unbestätigt.','Delivery unconfirmed.'),false)
end
-- Shows the notice with sample text, so that position and duration can be judged.
function N.Preview()
    N.Toast({name=Z.L('Vorschau','Preview')},{text=Z.L('So sieht ein Hinweis aus. Ziehen verschiebt ihn.','This is what a notice looks like. Drag to move it.')})
end
