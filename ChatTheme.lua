local _,Z=...
-- Thin chat layer on the shared theme (Theme.lua, ThemeSkin.lua, ThemeKit.lua): colours come from the shared palette,
-- surfaces, buttons, fields, tabs, chips and menus from the shared skin. What stays chat specific is the message font,
-- the sender icons, the class colours of names and the window opacity.
local T=Z.Theme
local C={};Z.ChatTheme=C
-- Chat colour key -> key of the shared palette (the one place of the mapping).
-- bubble: message of someone else (raised graphite card); own and selected: warm gold-brown, clearly apart from
-- the cool graphite of the other bubbles and of the conversation list.
C.palette={shell='bg',sidebar='side',surface='panel',field='inset',line='line',text='text',muted='dim',
    gold='gold',goldBright='goldBright',red='danger',border='edge',bubble='panelRaised',own='chipOnBg',selected='chipOnBg'}
local FILL_ALPHA={shell=.995,sidebar=.995,surface=.985,field=.99}
C.colors={}
for key,paletteKey in pairs(C.palette)do C.colors[key]={T.PaletteColor(paletteKey,FILL_ALPHA[key])}end
-- Message text only: Noto Sans and the client fonts that can be chosen for it.
C.font='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-Regular.ttf'
C.bold='Interface\\AddOns\\ZenialChat\\Media\\NotoSans-SemiBold.ttf'
C.icons={COMMUNITY='Interface\\GossipFrame\\GossipGossipIcon',GUILD='Interface\\Icons\\INV_Shirt_GuildTabard_01',
    OFFICER='Interface\\Icons\\INV_Misc_Note_01',PARTY='Interface\\Icons\\INV_Misc_GroupNeedMore',
    RAID='Interface\\Icons\\INV_Misc_GroupNeedMore',INSTANCE_CHAT='Interface\\Icons\\INV_Misc_GroupNeedMore',
    WHISPER='Interface\\GossipFrame\\GossipGossipIcon',BN_WHISPER='Interface\\FriendsFrame\\Battlenet-Portrait',
    CHANNEL='Interface\\GossipFrame\\GossipGossipIcon',general='Interface\\GossipFrame\\GossipGossipIcon',
    horde='Interface\\Icons\\INV_BannerPVP_01',alliance='Interface\\Icons\\INV_BannerPVP_02'}
-- Symbols of the settings pages: names of the shared icon atlas.
C.pageIcons={appearance='layers',messages='whisper',behavior='settings',notifications='bell',history='history',blizzard='addons'}
-- Client fonts for the message text.
C.fontFaces={friz='Fonts\\FRIZQT__.TTF',arial='Fonts\\ARIALN.TTF',morpheus='Fonts\\MORPHEUS.TTF',skurri='Fonts\\SKURRI.TTF'}
C.backgrounds={}
function C.Color(key)local c=C.colors[key]or C.colors.text;return c[1],c[2],c[3]end
-- A chat colour key or any key of the shared palette.
local function borderColor(key)return T.PaletteColor(C.palette[key]or key)end
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
-- The font of the interface is the one of the client (as in the other ZENIAL addons).
local uiFace
local function interfaceFace()
    if uiFace then return uiFace end
    uiFace='Fonts\\FRIZQT__.TTF'
    local object=GameFontHighlight
    if type(object)=='table'and type(object.GetFont)=='function'then
        local ok,file=pcall(object.GetFont,object)
        if ok and type(file)=='string'and file~=''then uiFace=file end
    end
    return uiFace
end
local function paintText(f,color)
    f:SetTextColor(C.Color(color or'text'));f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
    if f.SetShadowOffset then f:SetShadowOffset(0,-1);f:SetShadowColor(0,0,0,.45)end
end
function C.Font(f,size,_,color)
    setFont(f,interfaceFace(),size or 14,'');paintText(f,color)
end
-- Message text honours the chosen font, outline and line spacing. Its base is Noto Sans in the weight asked for.
function C.MessageFont(f,size,bold,color)
    setFont(f,bold and C.bold or C.font,size or 14,'');paintText(f,color)
    local s=Z.store.settings;local face=C.fontFaces[s.fontFace]
    local flags=s.fontOutline~='none'and s.fontOutline or''
    if face or flags~=''then
        if not tryFont(f,face or(bold and C.bold or C.font),size or 14,flags)then
            setFont(f,bold and C.bold or C.font,size or 14,'')
        end
    end
    if f.SetSpacing then f:SetSpacing(s.lineSpacing or 0)end
end
function C.Text(parent,text,size,bold,color)
    local f=parent:CreateFontString(nil,'OVERLAY');C.Font(f,size,bold,color);f:SetText(text or'');return f
end
function C.Place(frame,x,y,w,h,parent)
    frame:ClearAllPoints();frame:SetPoint('TOPLEFT',parent or frame:GetParent(),'TOPLEFT',x,-y);frame:SetSize(math.max(1,w),math.max(1,h))
end
-- Flat panel of the shared skin; the fill follows the window opacity (C.Opacity).
function C.Panel(frame,kind,border)
    kind=kind or'surface';local fill=C.colors[kind]or C.colors.surface
    T.Panel(frame,'surface')
    frame:SetBackdropColor(fill[1],fill[2],fill[3],fill[4])
    frame:SetBackdropBorderColor(borderColor(border or'border'))
    frame.zenialBackgroundKind=kind;C.backgrounds[#C.backgrounds+1]=frame
    return frame
end
function C.Frame(parent,kind,border)
    return C.Panel(CreateFrame('Frame',nil,parent,'BackdropTemplate'),kind,border)
end
-- The chat window itself: shared window frame (edge, gold line, shadow); its own fill is transparent, the panels carry the opacity.
function C.Window(frame)
    T.Window(frame)
    frame.zenialBackgroundKind='shell';frame.opacityMultiplier=0;C.backgrounds[#C.backgrounds+1]=frame
    return frame
end
-- Dialogs and notices: raised card with gold line and shadow, opaque.
function C.Dialog(parent)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');T.Shell(f);return f
end
-- Menus: the popup of the shared dropdowns.
function C.Menu(parent)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');T.StylePopup(f);return f
end
function C.Opacity(alpha)
    for _,f in ipairs(C.backgrounds)do local c=C.colors[f.zenialBackgroundKind]or C.colors.surface
        f:SetBackdropColor(c[1],c[2],c[3],(f.previewOpacity or alpha)*(f.opacityMultiplier or 1))
    end
end
function C.Line(parent,x,y,width)
    local line=parent:CreateTexture(nil,'BORDER');T.Tint(line,'SetColorTexture','line');C.Place(line,x,y,width,1,parent);return line
end
function C.Tooltip(owner,title,detail)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:ClearLines();GameTooltip:AddLine(title,T.PaletteColor('goldBright'))
    if detail and detail~=''then local r,g,b=T.PaletteColor('text');GameTooltip:AddLine(detail,r,g,b,true)end
    GameTooltip:Show()
end
-- Caption (and symbol) colour per state; the skin colours the text of its own buttons the same way.
local HOVER={secondary='goldBright',primary='primaryText',danger='goldText',ghost='goldBright',tab='text'}
local function stateKey(b)
    local enabled=not b.IsEnabled or b:IsEnabled()
    if not enabled or b.zenialSelected then return T.ButtonTextKey(b)end
    if b.zenialHover then return HOVER[b.zenialVariant or'secondary']or'goldBright'end
    return T.ButtonTextKey(b)
end
local function paint(b)
    local key=stateKey(b)
    if b.label then T.Tint(b.label,'SetTextColor',key)end
    if b.glyph and b.symbol then T.Tint(b.symbol,'SetVertexColor',b.glyphKey or key)end
end
-- variant: secondary (default), primary (the one gold main action of a view), danger, ghost or tab.
local VARIANT={own='primary',primary='primary',danger='danger',ghost='ghost',tab='tab'}
function C.Button(parent,label,fn,style)
    local f=CreateFrame('Button',nil,parent)
    f.label=C.Text(f,label,12,false,'text')
    f.label:SetPoint('TOPLEFT',f,'TOPLEFT',5,-3);f.label:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-5,3)
    f.label:SetWordWrap(false);f.label:SetJustifyH('CENTER');f.label:SetJustifyV('MIDDLE')
    f:SetScript('OnClick',fn)
    f:SetScript('OnEnter',function(self)if self.tip then C.Tooltip(self,self.tip)end end)
    f:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    local variant=VARIANT[style]or'secondary'
    if variant=='tab'then T.StyleTab(f)else T.StyleButton(f,variant)end
    for _,event in ipairs({'OnEnter','OnLeave','OnEnable','OnDisable'})do
        f:HookScript(event,function(self)paint(self)end)
    end
    paint(f)
    return f
end
function C.Tab(parent,label,fn)return C.Button(parent,label,fn,'tab')end
-- Marks a button as the chosen one: tab selection, chip state or a gold edge.
function C.SetActive(b,on)
    on=on==true
    if b.zenialChipFill then b:SetChecked(on);return end
    if b.zenialVariant=='tab'then T.SetSelected(b,on);paint(b);return end
    if not b.activeEdges and T.Edges then
        b.activeEdges=T.Edges(b,'OVERLAY');T.TintEdges(b.activeEdges,'gold')
    end
    if b.activeEdges then for _,edge in pairs(b.activeEdges)do edge:SetShown(on)end end
end
-- Two-state chip (categories, languages, filters); chip.label is its caption, chip.tip its tooltip.
function C.Chip(parent,label,fn)
    local chip=T.Chip(parent,label,90,22,fn);chip.label=chip.text
    chip:HookScript('OnEnter',function(self)if self.tip then C.Tooltip(self,self.tip)end end)
    chip:HookScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
    return chip
end
-- A button that opens a menu: the shared dropdown look, the caption keeps clear of the arrow.
function C.Dropdown(button)
    T.StyleDropdown(button)
    button.label:ClearAllPoints();button.label:SetPoint('TOPLEFT',button,'TOPLEFT',8,-3);button.label:SetPoint('BOTTOMRIGHT',button,'BOTTOMRIGHT',-26,3)
    button.label:SetJustifyH('LEFT');paint(button)
    return button
end
-- Fixed colour of the symbol of a button whatever the state (a favourite star).
function C.GlyphColor(button,key)
    button.glyphKey=key;if button.symbol then T.Tint(button.symbol,'SetVertexColor',key or stateKey(button))end
end
-- SetAtlas has no success return on Forever. Check availability when possible;
-- nil is a normal result, while an explicit false or an error needs a fallback.
local function setAtlas(texture,atlas)
    if not atlas or not texture.SetAtlas then return false end
    if C_Texture and C_Texture.GetAtlasInfo and not Z.Call(C_Texture.GetAtlasInfo,atlas)then return false end
    local ok,applied=pcall(texture.SetAtlas,texture,atlas,false)
    return ok and applied~=false
end
-- Symbol of a button from the shared icon atlas (T.iconCells); it takes the colour of the caption state.
function C.Glyph(button,name,size)
    if not button.symbol then button.symbol=button:CreateTexture(nil,'ARTWORK')end
    button.symbol:ClearAllPoints();button.symbol:SetPoint('CENTER');button.symbol:SetSize(size or 18,size or 18)
    T.SetIcon(button.symbol,name,'textSoft');button.glyph=name
    button.label:SetText('');paint(button);return button.symbol
end
-- Symbol from a client texture or atlas (no counterpart in the shared atlas).
function C.ButtonIcon(button,texture,atlas,size)
    if not button.symbol then button.symbol=button:CreateTexture(nil,'ARTWORK')end
    button.symbol:ClearAllPoints();button.symbol:SetPoint('CENTER');button.symbol:SetSize(size or 19,size or 19)
    button.glyph=nil;button.symbol:SetVertexColor(1,1,1,1)
    if not setAtlas(button.symbol,atlas)then
        button.symbol:SetTexture(texture);button.symbol:SetTexCoord(0,1,0,1)
    end
    button.label:SetText('');return button.symbol
end
function C.ScrollBar(parent,onValue)return T.CreateScrollBar(parent,onValue)end
function C.NameColor(font,classFile)
    local colors=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or'']
    if colors and Z.Safe(colors.r,colors.g,colors.b)then font:SetTextColor(colors.r,colors.g,colors.b);return end
    local palette={MAGE={.45,.69,1},WARRIOR={.90,.74,.38},PRIEST={.90,.91,.96},DRUID={1,.58,.20},
        HUNTER={.62,.82,.42},ROGUE={1,.90,.40},WARLOCK={.69,.55,.92},PALADIN={.96,.58,.76},SHAMAN={.27,.58,1}}
    local c=palette[classFile or'']or C.colors.goldBright;font:SetTextColor(unpack(c))
end
local function hexByte(value)return string.format('%02x',math.floor(math.max(0,math.min(1,value))*255+.5))end
-- The color of C.NameColor as markup, for names written inside a text.
function C.NameHex(classFile)
    local holder={SetTextColor=function(self,r,g,b)self.r,self.g,self.b=r,g,b end}
    C.NameColor(holder,classFile)
    return hexByte(holder.r)..hexByte(holder.g)..hexByte(holder.b)
end
function C.Input(parent)
    local bg=C.Frame(parent,'field','fieldEdge');bg.opacityMultiplier=.95;local f=CreateFrame('EditBox',nil,bg)
    f:SetAutoFocus(false);f:SetTextInsets(10,10,6,6);setFont(f,interfaceFace(),14,'');f:SetTextColor(C.Color('text'))
    f:SetAlpha(1);f.background=bg;f:SetPoint('TOPLEFT',bg,'TOPLEFT',2,-2);f:SetPoint('BOTTOMRIGHT',bg,'BOTTOMRIGHT',-2,2)
    -- The edge turns gold-dim while the field has the focus, as in every shared field.
    f:HookScript('OnEditFocusGained',function()bg:SetBackdropBorderColor(T.PaletteColor('goldDim'))end)
    f:HookScript('OnEditFocusLost',function()bg:SetBackdropBorderColor(T.PaletteColor('fieldEdge'))end)
    return f,bg
end
function C.Icon(parent,conversation)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');C.Panel(f,'field','edge')
    f.opacityMultiplier=.95
    f.texture=f:CreateTexture(nil,'ARTWORK');f.texture:SetPoint('TOPLEFT',3,-3);f.texture:SetPoint('BOTTOMRIGHT',-3,3)
    C.SetIcon(f,conversation or{})
    return f
end
-- The banner of the other faction; unknown factions keep the generic group icon.
function C.OppositeIcon(faction)
    if faction=='Horde'then return C.icons.alliance end
    if faction=='Alliance'then return C.icons.horde end
    return'Interface\\Icons\\INV_Misc_GroupLooking'
end
function C.SetIcon(icon,c)
    local coords=c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
    if c.classFile and setAtlas(icon.texture,'groupfinder-icon-class-'..c.classFile:lower())then return end
    icon.texture:SetTexCoord(0,1,0,1)
    if coords then icon.texture:SetTexture('Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES');icon.texture:SetTexCoord(unpack(coords))
    else icon.texture:SetTexture(c.kind=='XFACTION'and C.OppositeIcon(c.target)or C.icons[c.slot]or C.icons[c.kind]or'Interface\\Icons\\INV_Misc_GroupLooking')end
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
function C.SetSenderIcon(icon,s,conv,class,person)
    if s.senderIcon=='race'and icon.texture.SetAtlas then
        local atlas=raceAtlas(s,person)
        if atlas then
            icon.texture:SetTexCoord(0,1,0,1)
            if setAtlas(icon.texture,atlas)then return end
        end
    end
    C.SetIcon(icon,{kind=conv.kind,classFile=class})
end
-- The same picture as a text escape, for the classic list.
function C.InlineIcon(s,class,person,size)
    if s.senderIcon=='race'then
        local atlas=raceAtlas(s,person)
        if atlas then return string.format('|A:%s:%d:%d|a',atlas,size,size)end
    end
    local coords=class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not coords then return''end
    return string.format('|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t',CLASS_TEXTURE,size,size,coords[1]*256,coords[2]*256,coords[3]*256,coords[4]*256)
end
