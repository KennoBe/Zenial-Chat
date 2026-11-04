local _,Z=...
local T={};Z.Theme=T
T.colors={shell={.07,.078,.09},sidebar={.085,.094,.105},surface={.10,.112,.128},
    bubble={.125,.14,.16},own={.12,.205,.295},gold={.78,.60,.28},goldBright={1,.81,.39},
    border={.32,.28,.20},text={.93,.93,.91},muted={.64,.67,.71},selected={.23,.20,.13},
    red={.72,.12,.105},field={.035,.044,.056},line={.20,.22,.25}}
T.font='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-Regular.ttf'
T.bold='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-SemiBold.ttf'
T.icons={COMMUNITY='Interface\\GossipFrame\\GossipGossipIcon',GUILD='Interface\\Icons\\INV_Shirt_GuildTabard_01',
    OFFICER='Interface\\Icons\\INV_Misc_Note_01',PARTY='Interface\\Icons\\INV_Misc_GroupLooking',
    RAID='Interface\\Icons\\INV_Misc_GroupLooking',INSTANCE_CHAT='Interface\\LFGFrame\\UI-LFG-PORTRAIT',
    WHISPER='Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon',BN_WHISPER='Interface\\FriendsFrame\\Battlenet-Portrait',
    CHANNEL='Interface\\GossipFrame\\GossipGossipIcon',general='Interface\\GossipFrame\\GossipGossipIcon',
    horde='Interface\\TargetingFrame\\UI-PVP-Horde',alliance='Interface\\TargetingFrame\\UI-PVP-Alliance',
    appearance='Interface\\Icons\\Trade_Engineering',behavior='Interface\\Icons\\INV_Misc_Gear_01',
    notifications='Interface\\Icons\\INV_Misc_Bell_01',history='Interface\\Icons\\INV_Misc_Book_09'}
T.backgrounds={}
function T.Color(key)return unpack(T.colors[key]or T.colors.text)end
function T.Font(f,size,bold,color)
    local ok=pcall(f.SetFont,f,bold and T.bold or T.font,size or 14,'')
    if not ok then f:SetFont('Fonts\\ARIALN.TTF',size or 14,'')end
    f:SetTextColor(T.Color(color or'text'));f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
    if f.SetShadowOffset then f:SetShadowOffset(0,-1);f:SetShadowColor(0,0,0,.45)end
end
function T.Text(parent,text,size,bold,color)
    local f=parent:CreateFontString(nil,'OVERLAY');T.Font(f,size,bold,color);f:SetText(text or'');return f
end
function T.Place(frame,x,y,w,h,parent)
    frame:ClearAllPoints();frame:SetPoint('TOPLEFT',parent or frame:GetParent(),'TOPLEFT',x,-y);frame:SetSize(math.max(1,w),math.max(1,h))
end
function T.Panel(frame,kind,border)
    local color=T.colors[kind or'surface'];frame:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',
        edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2}})
    frame:SetBackdropColor(color[1],color[2],color[3],1)
    frame:SetBackdropBorderColor(T.Color(border or'border'))
    frame.zenialBackgroundKind=kind or'surface';T.backgrounds[#T.backgrounds+1]=frame
    return frame
end
function T.Frame(parent,kind,border)
    return T.Panel(CreateFrame('Frame',nil,parent,'BackdropTemplate'),kind,border)
end
function T.Button(parent,label,fn,style)
    local f=CreateFrame('Button',nil,parent,'BackdropTemplate');T.Panel(f,style or'surface','border')
    f.opacityMultiplier=.3
    f.label=T.Text(f,label,13,true,'text')
    f.label:SetPoint('TOPLEFT',f,'TOPLEFT',5,-3);f.label:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-5,3)
    f.label:SetWordWrap(false);f.label:SetJustifyH('CENTER');f.label:SetJustifyV('MIDDLE')
    f:SetScript('OnClick',fn)
    local glow=f:CreateTexture(nil,'HIGHLIGHT');glow:SetAllPoints();glow:SetColorTexture(1,.78,.30,.09)
    f:SetScript('OnEnter',function(self)if self.tip then T.Tooltip(self,self.tip)end end)
    f:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    return f
end
function T.ButtonIcon(button,texture,atlas)
    if not button.symbol then button.symbol=button:CreateTexture(nil,'ARTWORK')end
    button.symbol:ClearAllPoints();button.symbol:SetPoint('CENTER');button.symbol:SetSize(19,19)
    button.symbol:SetTexture(texture)
    if atlas and button.symbol.SetAtlas then pcall(button.symbol.SetAtlas,button.symbol,atlas,false)end
    button.label:SetText('');return button.symbol
end
function T.NameColor(font,classFile)
    local colors=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or'']
    if colors and Z.Safe(colors.r,colors.g,colors.b)then font:SetTextColor(colors.r,colors.g,colors.b);return end
    local palette={MAGE={.45,.69,1},WARRIOR={.90,.74,.38},PRIEST={.90,.91,.96},DRUID={1,.58,.20},
        HUNTER={.62,.82,.42},ROGUE={1,.90,.40},WARLOCK={.69,.55,.92},PALADIN={.96,.58,.76},SHAMAN={.27,.58,1}}
    local c=palette[classFile or'']or T.colors.goldBright;font:SetTextColor(unpack(c))
end
function T.Tooltip(owner,title,detail)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:ClearLines();GameTooltip:AddLine(title,1,.82,.4)
    if detail and detail~=''then GameTooltip:AddLine(detail,.85,.87,.9,true)end
    GameTooltip:Show()
end
function T.Input(parent)
    local bg=T.Frame(parent,'field','border');bg.opacityMultiplier=.35;local f=CreateFrame('EditBox',nil,bg)
    f:SetAutoFocus(false);f:SetTextInsets(10,10,6,6);f:SetFont(T.font,14,'');f:SetTextColor(T.Color('text'))
    f:SetAlpha(1);f.background=bg;f:SetPoint('TOPLEFT',bg,'TOPLEFT',2,-2);f:SetPoint('BOTTOMRIGHT',bg,'BOTTOMRIGHT',-2,2)
    return f,bg
end
function T.Icon(parent,conversation)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');T.Panel(f,'field','gold')
    f.opacityMultiplier=.35
    f.texture=f:CreateTexture(nil,'ARTWORK');f.texture:SetPoint('TOPLEFT',5,-5);f.texture:SetPoint('BOTTOMRIGHT',-5,5)
    T.SetIcon(f,conversation or{})
    return f
end
function T.SetIcon(icon,c)
    local coords=c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
    icon.texture:SetTexCoord(0,1,0,1)
    if coords then icon.texture:SetTexture('Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES');icon.texture:SetTexCoord(unpack(coords))
    else icon.texture:SetTexture(T.icons[c.slot or'']or T.icons[c.kind]or'Interface\\Icons\\INV_Misc_GroupLooking')end
end
function T.Opacity(alpha)
    for _,f in ipairs(T.backgrounds)do local c=T.colors[f.zenialBackgroundKind]or T.colors.surface
        f:SetBackdropColor(c[1],c[2],c[3],(f.previewOpacity or alpha)*(f.opacityMultiplier or 1))
    end
end
function T.Line(parent,x,y,width)
    local line=parent:CreateTexture(nil,'BORDER');line:SetColorTexture(T.Color('line'));T.Place(line,x,y,width,1,parent);return line
end
