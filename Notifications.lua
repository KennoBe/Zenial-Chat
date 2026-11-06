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
local function playIncoming()
    local now=GetTime()
    if N.lastIncomingSound and now-N.lastIncomingSound<SOUND_INTERVAL then return end
    N.lastIncomingSound=now;N.PlayTell()
end
local function inCombat()
    return Z.Call(UnitAffectingCombat,'player')==true or Z.Call(InCombatLockdown)==true
end
function N.Incoming(conv,message,added)
    if not added or not conv or not message or message.outgoing or message.context or message.deleted then return end
    if Z.IsVisibleAtEnd(conv.key)then return end
    local category=Z.Store.Group(conv.kind);if category=='people'then category='whispers'end
    local pref=Z.store.settings.notifications[category]or{}
    if not conv.muted then
        if pref.sound then playIncoming()end
        if pref.toast then N.Toast(conv,message)end
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
function N.Toast(conv,message)
    local T=Z.Theme
    if not N.frame then
        local f=T.Frame(UIParent,'shell','gold');N.frame=f;f:SetSize(320,90);f:SetFrameStrata('DIALOG')
        f:SetClampedToScreen(true);f:SetMovable(true);N.ApplyPosition();buildFade(f)
        f.title=T.Text(f,'',13,true,'goldBright');T.Place(f.title,14,12,270,20,f)
        f.body=T.Text(f,'',12,false,'text');f.body:SetWordWrap(true);T.Place(f.body,14,35,290,42,f)
        -- Left-drag moves the toast; a plain click still opens the conversation.
        f:EnableMouse(true);f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart',function(self)N.dragging=true;N.dragged=true;self:StartMoving()end)
        f:SetScript('OnDragStop',function(self)self:StopMovingOrSizing();N.dragging=false;N.SavePosition()end)
        f:SetScript('OnMouseUp',function()
            if N.dragged then N.dragged=false;return end
            local key=f.key;f:Hide();Z.UI.Select(key)
        end)
        f:SetScript('OnUpdate',function(_,elapsed)
            if N.dragging then N.left=5;return end -- stay visible while being moved
            if N.fading then return end
            N.left=N.left-elapsed;if N.left<=0 then finish(f)end
        end)
        f:SetScript('OnHide',function(self)if self.fade then self.fade:Stop()end;N.fading=false;N.dragging=false;self:SetAlpha(1)end)
        f.close=Z.CloseButton(f,function()f:Hide()end,Z.L('Schließen','Close'));T.Place(f.close,288,6,25,24,f)
    end
    N.frame.key=conv.key;N.frame.title:SetText(conv.name);N.frame.body:SetText(Z.Plain(message.text):gsub('[\r\n]+',' '))
    N.left=5;N.fading=false;N.dragged=false;if N.frame.fade then N.frame.fade:Stop()end;N.frame:SetAlpha(1);N.frame:Show()
end
