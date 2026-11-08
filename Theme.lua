local _,Z=...
local T={};Z.Theme=T
-- Stone and gold, same hues as T.palette in _dev/shared/Theme.lua (this addon keeps its own theme file).
local function hex(value)
    local r,g,b=value:match('^(%x%x)(%x%x)(%x%x)$')
    return{tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255}
end
T.colors={shell=hex('100e0b'),sidebar=hex('15120e'),surface=hex('1b1812'),
    bubble=hex('231f17'),own=hex('3a2e12'),gold=hex('ffd100'),goldBright=hex('ffe05c'),
    border=hex('8f7433'),text=hex('f1ead8'),muted=hex('a79c84'),selected=hex('3d2f0a'),
    red=hex('c23b2a'),field=hex('0b0a07'),line=hex('3a3222')}
T.font='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-Regular.ttf'
T.bold='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-SemiBold.ttf'
T.icons={COMMUNITY='Interface\\GossipFrame\\GossipGossipIcon',GUILD='Interface\\Icons\\INV_Shirt_GuildTabard_01',
    OFFICER='Interface\\Icons\\INV_Misc_Note_01',PARTY='Interface\\Icons\\INV_Misc_GroupNeedMore',
    RAID='Interface\\Icons\\INV_Misc_GroupNeedMore',INSTANCE_CHAT='Interface\\Icons\\INV_Misc_GroupNeedMore',
    WHISPER='Interface\\GossipFrame\\GossipGossipIcon',BN_WHISPER='Interface\\FriendsFrame\\Battlenet-Portrait',
    CHANNEL='Interface\\GossipFrame\\GossipGossipIcon',general='Interface\\GossipFrame\\GossipGossipIcon',
    horde='Interface\\Icons\\INV_BannerPVP_01',alliance='Interface\\Icons\\INV_BannerPVP_02',
    appearance='Interface\\Icons\\Trade_Engineering',behavior='Interface\\Icons\\INV_Misc_Gear_01',
    notifications='Interface\\Icons\\INV_Misc_Bell_01',history='Interface\\Icons\\INV_Misc_Book_09',
    messages='Interface\\Icons\\INV_Letter_15',blizzard='Interface\\WorldMap\\GEAR_64GREY'}
-- Client fonts for the message text. The interface itself keeps Noto Sans.
T.fontFaces={friz='Fonts\\FRIZQT__.TTF',arial='Fonts\\ARIALN.TTF',morpheus='Fonts\\MORPHEUS.TTF',skurri='Fonts\\SKURRI.TTF'}
T.backgrounds={}
function T.Color(key)return unpack(T.colors[key]or T.colors.text)end
-- FontString/EditBox:SetFont reports failure as false as well as throwing.
local function tryFont(f,face,size,flags)
    local ok,applied=pcall(f.SetFont,f,face,size,flags)
    return ok and applied==true
end
local function setFont(f,face,size,flags)
    if not tryFont(f,face,size,flags)and not tryFont(f,'Fonts\\ARIALN.TTF',size,'')then
        f:SetFontObject(GameFontHighlight)
    end
end
function T.Font(f,size,bold,color)
    setFont(f,bold and T.bold or T.font,size or 14,'')
    f:SetTextColor(T.Color(color or'text'));f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
    if f.SetShadowOffset then f:SetShadowOffset(0,-1);f:SetShadowColor(0,0,0,.45)end
end
-- Message text honours the chosen font, outline and line spacing; defaults equal T.Font.
function T.MessageFont(f,size,bold,color)
    T.Font(f,size,bold,color)
    local s=Z.store.settings;local face=T.fontFaces[s.fontFace]
    local flags=s.fontOutline~='none'and s.fontOutline or''
    if face or flags~=''then
        if not tryFont(f,face or(bold and T.bold or T.font),size or 14,flags)then
            setFont(f,bold and T.bold or T.font,size or 14,'')
        end
    end
    if f.SetSpacing then f:SetSpacing(s.lineSpacing or 0)end
end
function T.Text(parent,text,size,bold,color)
    local f=parent:CreateFontString(nil,'OVERLAY');T.Font(f,size,bold,color);f:SetText(text or'');return f
end
function T.Place(frame,x,y,w,h,parent)
    frame:ClearAllPoints();frame:SetPoint('TOPLEFT',parent or frame:GetParent(),'TOPLEFT',x,-y);frame:SetSize(math.max(1,w),math.max(1,h))
end
function T.Panel(frame,kind,border)
    local color=T.colors[kind or'surface'];frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',
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
    f.opacityMultiplier=.9
    f.label=T.Text(f,label,13,true,'text')
    f.label:SetPoint('TOPLEFT',f,'TOPLEFT',5,-3);f.label:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-5,3)
    f.label:SetWordWrap(false);f.label:SetJustifyH('CENTER');f.label:SetJustifyV('MIDDLE')
    f:SetScript('OnClick',fn)
    local glow=f:CreateTexture(nil,'HIGHLIGHT');glow:SetAllPoints();glow:SetColorTexture(1,.78,.30,.09)
    f:SetScript('OnEnter',function(self)if self.tip then T.Tooltip(self,self.tip)end end)
    f:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    return f
end
-- SetAtlas has no success return on Forever. Check availability when possible;
-- nil is a normal result, while an explicit false or an error needs a fallback.
local function setAtlas(texture,atlas)
    if not atlas or not texture.SetAtlas then return false end
    if C_Texture and C_Texture.GetAtlasInfo and not Z.Call(C_Texture.GetAtlasInfo,atlas)then return false end
    local ok,applied=pcall(texture.SetAtlas,texture,atlas,false)
    return ok and applied~=false
end
function T.ButtonIcon(button,texture,atlas,size)
    if not button.symbol then button.symbol=button:CreateTexture(nil,'ARTWORK')end
    button.symbol:ClearAllPoints();button.symbol:SetPoint('CENTER');button.symbol:SetSize(size or 19,size or 19)
    if not setAtlas(button.symbol,atlas)then
        button.symbol:SetTexture(texture);button.symbol:SetTexCoord(0,1,0,1)
    end
    button.label:SetText('');return button.symbol
end
function T.NameColor(font,classFile)
    local colors=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or'']
    if colors and Z.Safe(colors.r,colors.g,colors.b)then font:SetTextColor(colors.r,colors.g,colors.b);return end
    local palette={MAGE={.45,.69,1},WARRIOR={.90,.74,.38},PRIEST={.90,.91,.96},DRUID={1,.58,.20},
        HUNTER={.62,.82,.42},ROGUE={1,.90,.40},WARLOCK={.69,.55,.92},PALADIN={.96,.58,.76},SHAMAN={.27,.58,1}}
    local c=palette[classFile or'']or T.colors.goldBright;font:SetTextColor(unpack(c))
end
local function hexByte(value)return string.format('%02x',math.floor(math.max(0,math.min(1,value))*255+.5))end
-- The color of T.NameColor as markup, for names written inside a text.
function T.NameHex(classFile)
    local holder={SetTextColor=function(self,r,g,b)self.r,self.g,self.b=r,g,b end}
    T.NameColor(holder,classFile)
    return hexByte(holder.r)..hexByte(holder.g)..hexByte(holder.b)
end
function T.Tooltip(owner,title,detail)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:ClearLines();GameTooltip:AddLine(title,1,.82,.4)
    if detail and detail~=''then GameTooltip:AddLine(detail,.85,.87,.9,true)end
    GameTooltip:Show()
end
function T.Input(parent)
    local bg=T.Frame(parent,'field','border');bg.opacityMultiplier=.95;local f=CreateFrame('EditBox',nil,bg)
    f:SetAutoFocus(false);f:SetTextInsets(10,10,6,6);setFont(f,T.font,14,'');f:SetTextColor(T.Color('text'))
    f:SetAlpha(1);f.background=bg;f:SetPoint('TOPLEFT',bg,'TOPLEFT',2,-2);f:SetPoint('BOTTOMRIGHT',bg,'BOTTOMRIGHT',-2,2)
    return f,bg
end
function T.Icon(parent,conversation)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');T.Panel(f,'field','gold')
    f.opacityMultiplier=.95
    f.texture=f:CreateTexture(nil,'ARTWORK');f.texture:SetPoint('TOPLEFT',3,-3);f.texture:SetPoint('BOTTOMRIGHT',-3,3)
    T.SetIcon(f,conversation or{})
    return f
end
function T.SetIcon(icon,c)
    local coords=c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
    if c.classFile and setAtlas(icon.texture,'groupfinder-icon-class-'..c.classFile:lower())then return end
    icon.texture:SetTexCoord(0,1,0,1)
    if coords then icon.texture:SetTexture('Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES');icon.texture:SetTexCoord(unpack(coords))
    else icon.texture:SetTexture(T.icons[c.slot]or T.icons[c.kind]or'Interface\\Icons\\INV_Misc_GroupLooking')end
end
local CLASS_TEXTURE='Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES'
-- The atlas of a known race, if this client really has it. Unknown means no race icon, never a guess.
local function raceAtlas(s,person)
    if not person or type(person.race)~='string'or type(GetRaceAtlas)~='function'then return nil end
    local gender=person.sex==2 and'male'or person.sex==3 and'female'
    if not gender then return nil end
    local atlas=Z.Call(GetRaceAtlas,person.race:lower(),gender,s.raceIconQuality=='hd')
    if type(atlas)~='string'then return nil end
    if C_Texture and C_Texture.GetAtlasInfo and not Z.Call(C_Texture.GetAtlasInfo,atlas)then return nil end
    return atlas
end
-- The picture next to a message: race if chosen and known, otherwise the class, otherwise the chat type.
function T.SetSenderIcon(icon,s,conv,class,person)
    if s.senderIcon=='race'and icon.texture.SetAtlas then
        local atlas=raceAtlas(s,person)
        if atlas then
            icon.texture:SetTexCoord(0,1,0,1)
            if setAtlas(icon.texture,atlas)then return end
        end
    end
    T.SetIcon(icon,{kind=conv.kind,classFile=class})
end
-- The same picture as a text escape, for the classic list.
function T.InlineIcon(s,class,person,size)
    if s.senderIcon=='race'then
        local atlas=raceAtlas(s,person)
        if atlas then return string.format('|A:%s:%d:%d|a',atlas,size,size)end
    end
    local coords=class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not coords then return''end
    return string.format('|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t',CLASS_TEXTURE,size,size,coords[1]*256,coords[2]*256,coords[3]*256,coords[4]*256)
end
function T.Opacity(alpha)
    for _,f in ipairs(T.backgrounds)do local c=T.colors[f.zenialBackgroundKind]or T.colors.surface
        f:SetBackdropColor(c[1],c[2],c[3],(f.previewOpacity or alpha)*(f.opacityMultiplier or 1))
    end
end
function T.Line(parent,x,y,width)
    local line=parent:CreateTexture(nil,'BORDER');line:SetColorTexture(T.Color('line'));T.Place(line,x,y,width,1,parent);return line
end
