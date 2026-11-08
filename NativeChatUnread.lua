local _,Z=...
local U={};Z.NativeChatUnread=U
local states={};local globalHooks={}
local prefs={unread=false,flash=false,unreadTabs={}}
local PADDING=24
local function safe(...)return Z.Safe(...)end
local function call(fn,...)return Z.Call(fn,...)end
local function allowedFrame(frame)
    if not safe(frame)or type(frame)~='table'then return false end
    for _,method in ipairs({'IsForbidden','IsProtected'})do
        if type(frame[method])=='function'then
            local value=call(frame[method],frame)
            if value~=false then return false end
        end
    end
    return true
end
local function inCombat()return not Z.NativeChat or Z.NativeChat.InCombat()~=false end
local function enabled(state)
    return prefs.unread and prefs.unreadTabs[state.id]~=false
end
local function render(state,flash)
    if inCombat()or not state.badge or not allowedFrame(state.frame)or not allowedFrame(state.tab)then return end
    local visible=state.count>0 and enabled(state)
    state.badge.text:SetText(state.count>99 and'99+'or tostring(state.count))
    state.badge:SetShown(visible)
    if state.animation then
        state.animation:Stop()
        if visible and flash and prefs.flash then state.animation:Play()end
    end
end
local function reset(state,forget)
    state.count=0
    if forget then state.seen={};state.order={}end
    render(state)
end
local function remember(state,event,id)
    local key=event..':'..id
    if state.seen[key]then return false end
    state.seen[key]=true;state.order[#state.order+1]=key
    if #state.order>256 then state.seen[table.remove(state.order,1)]=nil end
    return true
end
local systemEvents={CHAT_MSG_SYSTEM=true,CHAT_MSG_SKILL=true,CHAT_MSG_CURRENCY=true,CHAT_MSG_MONEY=true,
    CHAT_MSG_LOOT=true,CHAT_MSG_OPENING=true,CHAT_MSG_TRADESKILLS=true}
local function incoming(event,args)
    if event=='CHAT_MSG_WHISPER_INFORM'or event=='CHAT_MSG_BN_WHISPER_INFORM'then return false end
    local guid,sender=args[12],args[2]
    if not safe(guid,sender)then return false end
    if systemEvents[event]and(guid==nil or guid=='')and(sender==nil or sender=='')then return true end
    local own=call(UnitGUID,'player')
    if type(guid)=='string'and guid~=''and type(own)=='string'and own~=''then return guid~=own end
    local name,realm=call(UnitFullName,'player')
    if type(sender)~='string'or type(name)~='string'or name==''then return false end
    -- Realm suffixes may use a different spelling. Equal character names are
    -- ambiguous without a GUID, so undercount rather than count our own echo.
    if sender:match('^([^-]+)')==name then return false end
    if event=='CHAT_MSG_WHISPER'or event=='CHAT_MSG_BN_WHISPER'then
        return sender~=''
    end
    -- Without a GUID, require explicit realm-qualified names on both sides.
    if type(realm)~='string'or realm==''then return false end
    if not sender:find('-',1,true)then return false end
    return sender~=name..'-'..realm
end
local function delivered(state,_,message,r,g,b,infoID,accessID,typeID,event,args)
    if not enabled(state)or not allowedFrame(state.frame)then return end
    if not safe(event,args)or type(event)~='string'or event:sub(1,9)~='CHAT_MSG_'or type(args)~='table'then return end
    local id=args[11]
    if not safe(id)or type(id)~='number'or id<=0 or id>=math.huge or id%1~=0 then return end
    if not incoming(event,args)then return end
    local shown=call(state.frame.IsShown,state.frame)
    if type(shown)~='boolean'then return end
    if not remember(state,event,id)then return end
    if shown then reset(state);return end
    state.count=state.count+1;render(state,true)
end
local function reflow(state)
    -- Avoid measuring names: whisper tab names can be secret. The native dock
    -- update chooses its fixed-width path and honours sizePadding itself.
    local docked=state.frame.isDocked
    if not safe(docked)or docked then return end
    local padding=state.tab.sizePadding
    if not safe(padding)then return end
    padding=padding or 0
    local width=call(state.tab.GetWidth,state.tab)
    if type(width)=='number'and width>20+padding and state.tab.Text then
        state.tab.Text:SetWidth(width-20-padding)
    end
end
local function decorate(state)
    if state.badge then return end
    local badge=CreateFrame('Frame',nil,state.tab);badge:SetSize(18,16)
    badge:SetPoint('RIGHT',state.tab,'RIGHT',-2,-5)
    local bg=badge:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.8,.57,.13,.35)
    local text=badge:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');text:SetAllPoints()
    text:SetJustifyH('CENTER');text:SetJustifyV('MIDDLE');text:SetTextColor(1,.87,.5,1)
    -- The inherited native font remains usable if SetFont returns false or throws.
    pcall(text.SetFont,text,'Fonts\\ARIALN.TTF',10,'')
    badge.text=text;badge:Hide();state.badge=badge
    if bg.CreateAnimationGroup then
        local ok,animation=pcall(function()
            local group=bg:CreateAnimationGroup()
            if group.SetLooping then group:SetLooping('NONE')end
            for i,values in ipairs({{1,.15},{.15,1}})do
                local alpha=group:CreateAnimation('Alpha');alpha:SetOrder(i);alpha:SetDuration(.25)
                alpha:SetFromAlpha(values[1]);alpha:SetToAlpha(values[2])
            end
            return group
        end)
        if ok then state.animation=animation end
    end
end
local function attach(frame)
    if states[frame]or not allowedFrame(frame)or type(frame.AddMessage)~='function'then return end
    local name=call(frame.GetName,frame);local id=call(frame.GetID,frame)
    if type(name)~='string'or type(id)~='number'then return end
    if id~=1 and call(FCF_IsChatWindowIndexReserved,id)==true then return end
    local tab=_G[name..'Tab']
    if not allowedFrame(tab)or not tab.Text then return end
    local state={frame=frame,tab=tab,id=tostring(id),count=0,seen={},order={}}
    local ok=pcall(hooksecurefunc,frame,'AddMessage',function(...)delivered(state,...)end)
    if not ok then return end
    states[frame]=state
    frame:HookScript('OnShow',function()if enabled(state)then reset(state)end end)
end
local function hookGlobal(name,callback)
    if not globalHooks[name]and type(_G[name])=='function'then
        globalHooks[name]=pcall(hooksecurefunc,name,callback)
    end
end
function U.Apply()
    local n=Z.NativeChat
    local settings=n and n.Settings()
    prefs={unread=false,flash=false,unreadTabs={}}
    if settings and not n.Conflict()then
        prefs.unread=settings.unread==true;prefs.flash=settings.flash==true
        for id,value in pairs(settings.unreadTabs or{})do if value==false then prefs.unreadTabs[id]=false end end
    end
    if inCombat()then return end
    if type(hooksecurefunc)~='function'then return end
    local changed=false
    if prefs.unread then
        hookGlobal('FCFDock_SelectWindow',function(_,frame)local state=states[frame];if state and enabled(state)then reset(state)end end)
        hookGlobal('FCF_Close',function(frame,fallback)local state=states[fallback or frame];if state and enabled(state)then reset(state,true)end end)
        hookGlobal('FCF_OpenNewWindow',function()if prefs.unread then U.Apply()end end)
        hookGlobal('FCF_OpenTemporaryWindow',function()if prefs.unread then U.Apply()end end)
        for _,name in ipairs(CHAT_FRAMES or{})do
            if safe(name)and type(name)=='string'then attach(_G[name])end
        end
    end
    for _,state in pairs(states)do
        if allowedFrame(state.frame)and allowedFrame(state.tab)then
            local on=enabled(state)
            if on then decorate(state)else reset(state,true)end
            local padding=state.tab.sizePadding
            if safe(padding)then
                local wasNil=padding==nil
                padding=padding or 0
                if type(padding)=='number'then
                    if on and not state.padding then
                        state.paddingWasNil=wasNil;state.tab.sizePadding=padding+PADDING;state.padding=true;changed=true;reflow(state)
                    elseif not on and state.padding then
                        -- Native lifecycle code may have replaced the whole field.
                        -- In that case our contribution is already gone.
                        local restored=padding>=PADDING and padding-PADDING or padding
                        state.tab.sizePadding=restored
                        if restored==0 and state.paddingWasNil then state.tab.sizePadding=nil end
                        state.padding=false;changed=true;reflow(state)
                    end
                end
            end
            render(state)
        end
    end
    if changed and type(FCF_DockUpdate)=='function'then pcall(FCF_DockUpdate)end
end
