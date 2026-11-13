local addonName, Z = ...

local Store = {}
Store.__index = Store
Z.Store = Store

local defaults = {
    alphaActive = .98, alphaInactive = .94, scale = 1, fontSize = 14,
    sidebar = 'auto', previews = true, locked = false, focusOnOpen = false,
    autoOpen = false, publicChannels = false, enabledChannels = {},
    minimapHidden = false, minimapAngle = 200,
    -- Every default below reproduces the look and behavior from before these options existed.
    nameFormat = 'full', senderIcon = 'class', raceIconQuality = 'hd', iconSize = 34, classColors = true,
    timeFormat = 'hm', timeZone = 'local', dateSeparators = true,
    channelLabels = 'full', sidebarCompact = false,
    layoutStyle = 'bubbles', groupMessages = false, fontFace = 'noto', fontOutline = 'none', lineSpacing = 0,
    urlLinks = true, quoteFormat = 'sender',
    inputHistory = true, inputHistoryScope = 'conversation',
    rememberScroll = true, fadeEnabled = false, fadeAfter = 30, fadeAlpha = .25,
    searchHistoryEnabled = false,
    retentionCount = 0, retentionDays = 0,
    toastDuration = 5, suppressInCombat = false,
}
local enumerations = {
    nameFormat = { full = true, first = true, last = true, initialLast = true, firstInitial = true, initials = true },
    senderIcon = { class = true, race = true, none = true },
    raceIconQuality = { hd = true, sd = true },
    timeFormat = { hm = true, hms = true, date = true, relative = true, off = true },
    timeZone = { ['local'] = true, server = true },
    channelLabels = { full = true, short = true, number = true },
    layoutStyle = { bubbles = true, compact = true, classic = true },
    fontFace = { noto = true, friz = true, arial = true, morpheus = true, skurri = true },
    fontOutline = { none = true, OUTLINE = true, THICKOUTLINE = true },
    quoteFormat = { text = true, sender = true, time = true },
    inputHistoryScope = { conversation = true, global = true },
}
local SENT_PER_CONVERSATION, SENT_GLOBAL, SEARCH_HISTORY, PEOPLE_LIMIT = 30, 100, 10, 20000

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function valueOr(value, fallback)
    if value == nil then return fallback end
    return value
end

local function notify(self, reason, key)
    if type(self.Z.Changed) == 'function' then self.Z.Changed(reason, key) end
end

local function ensureTable(parent, key)
    if type(parent[key]) ~= 'table' then parent[key] = {} end
    return parent[key]
end

local function applyDefaults(settings)
    -- Raise the previous default pair while preserving individually chosen opacity.
    if settings.alphaActive == .94 and settings.alphaInactive == .75 then
        settings.alphaActive, settings.alphaInactive = defaults.alphaActive, defaults.alphaInactive
    end
    local numericBounds = {
        alphaActive = { 0, 1 }, alphaInactive = { 0, 1 },
        scale = { .75, 1.5 }, fontSize = { 12, 20 },
        minimapAngle = { -360, 360 }, iconSize = { 16, 48 }, lineSpacing = { 0, 8 },
        fadeAfter = { 5, 300 }, fadeAlpha = { 0, 1 }, toastDuration = { 2, 15 },
        retentionCount = { 0, 1000000 }, retentionDays = { 0, 36500 },
    }
    for key, bounds in pairs(numericBounds) do
        local value = settings[key]
        if not isFiniteNumber(value) or value < bounds[1] or value > bounds[2] then
            settings[key] = defaults[key]
        end
    end
    local booleanKeys = { 'previews', 'locked', 'focusOnOpen', 'autoOpen', 'publicChannels', 'minimapHidden',
        'classColors', 'dateSeparators', 'sidebarCompact', 'groupMessages', 'urlLinks', 'inputHistory',
        'rememberScroll', 'fadeEnabled', 'searchHistoryEnabled', 'suppressInCombat' }
    for _, key in ipairs(booleanKeys) do
        if type(settings[key]) ~= 'boolean' then settings[key] = defaults[key] end
    end
    for key, allowed in pairs(enumerations) do
        if not allowed[settings[key]] then settings[key] = defaults[key] end
    end
    if settings.sidebar ~= 'auto' and settings.sidebar ~= 'names' and settings.sidebar ~= 'icons' then
        settings.sidebar = defaults.sidebar
    end
    -- Optional moved toast position; nil keeps the built-in default anchor.
    local anchors = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
        RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
    local pos = settings.toastPos
    if pos ~= nil and not (type(pos) == 'table' and anchors[pos.point] and anchors[pos.relPoint]
        and isFiniteNumber(pos.x) and isFiniteNumber(pos.y)) then
        settings.toastPos = nil
    end
    if type(settings.enabledChannels) ~= 'table' then settings.enabledChannels = {} end
    -- Left behind by versions with Community chats.
    settings.clubId, settings.streams = nil, nil
    local notificationDefaults = {
        whispers = { sound = true, toast = true },
        guild = { sound = false, toast = false },
        groups = { sound = false, toast = false },
        channels = { sound = false, toast = false },
        bnet = { sound = true, toast = true },
        -- The client plays its own raid warning sound; a second one stays opt-in.
        raidWarning = { sound = false, toast = false },
        opposite = { sound = false, toast = false },
    }
    local notifications = ensureTable(settings, 'notifications')
    notifications.community = nil
    -- Battle.net used to share the whisper switches: an existing choice carries over once.
    if type(notifications.bnet) ~= 'table' and type(notifications.whispers) == 'table' then
        notifications.bnet = { sound = notifications.whispers.sound, toast = notifications.whispers.toast }
    end
    for group, values in pairs(notificationDefaults) do
        local saved = ensureTable(notifications, group)
        for key, default in pairs(values) do
            if type(saved[key]) ~= 'boolean' then saved[key] = default end
        end
        if saved.soundKit ~= nil and type(saved.soundKit) ~= 'string' then saved.soundKit = nil end
    end
end

local function lower(value)
    return string.lower(tostring(value or ''))
end

local upperToLower = {}
for byte = 65, 90 do upperToLower[string.char(byte)] = string.char(byte + 32) end

-- Case folding for searches. string.lower only knows ASCII; this also covers Latin-1 letters such
-- as Ä/Ö/Ü and keeps the byte length. Conversation keys keep using lower(): they must stay stable.
function Store.Fold(value)
    -- Explicit table: string.lower may follow the C locale and damage UTF-8 bytes.
    local text = tostring(value or ''):gsub('[A-Z]', upperToLower)
    if not text:find('\195', 1, true) then return text end
    return (text:gsub('\195([\128-\158])', function(byte)
        if byte == '\151' then return nil end
        return '\195' .. string.char(byte:byte() + 32)
    end))
end

local kindGroups = {
    GUILD = 'guild', OFFICER = 'guild',
    PARTY = 'groups', RAID = 'groups', INSTANCE_CHAT = 'groups',
    WHISPER = 'people', BN_WHISPER = 'people', CHANNEL = 'channels',
    XFACTION = 'opposite',
}
local groupOrder = { guild = 1, groups = 2, people = 3, channels = 4, opposite = 5 }

function Store.Group(kind)
    return kindGroups[string.upper(tostring(kind or ''))]
end

local function encode(value)
    local text = lower(value)
    return (text:gsub('([^%w])', function(char) return string.format('%%%02x', string.byte(char)) end))
end

function Store.Key(spec)
    if type(spec) ~= 'table' then return nil end
    if spec.key ~= nil then return tostring(spec.key) end
    local kind = string.upper(tostring(spec.kind or ''))
    local parts = { kind }
    if kind == 'WHISPER' or kind == 'BN_WHISPER' then
        parts[#parts + 1] = encode(spec.target)
        if spec.scope ~= nil then parts[#parts + 1] = encode(spec.scope) end
    elseif kind == 'XFACTION' then
        -- One fixed conversation per own realm and own faction: scope is the realm, target the faction.
        parts[#parts + 1] = encode(spec.scope)
        parts[#parts + 1] = encode(spec.target)
    elseif kind == 'CHANNEL' then
        parts[#parts + 1] = encode(spec.scope)
        parts[#parts + 1] = encode(spec.channelName or spec.target)
    else
        parts[#parts + 1] = encode(spec.scope or spec.target)
    end
    return table.concat(parts, ':')
end

function Store.Plain(text)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('|H[^|]-|h(.-)|h', '%1')
    text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
    text = text:gsub('|T[^|]-|t', ''):gsub('|A[^|]-|a', '')
    return text
end

local function indexConversation(self, conversation)
    local index = {}
    local messages = type(conversation.messages) == 'table' and conversation.messages or {}
    conversation.messages = messages
    for i, message in ipairs(messages) do
        if type(message) == 'table' and message.id ~= nil then index[tostring(message.id)] = i end
    end
    self._messageIndexes[conversation.key] = index
end

-- The opposite-faction conversation holds at most this many messages, whatever the retention settings say.
local OPPOSITE_LIMIT = 200

function Store.New(db, nowFn)
    if type(db) ~= 'table' then db = {} end
    local self = setmetatable({ Z = Z, db = db, now = type(nowFn) == 'function' and nowFn or function() return 0 end, _messageIndexes = {}, _localId = 0 }, Store)
    self.settings = ensureTable(db, 'settings')
    applyDefaults(self.settings)
    local ui = ensureTable(db, 'ui')
    if not isFiniteNumber(ui.width) or ui.width < 540 then ui.width = 1060 end
    if not isFiniteNumber(ui.height) or ui.height < 360 then ui.height = 680 end
    if not isFiniteNumber(ui.x) then ui.x = 0 end
    if not isFiniteNumber(ui.y) then ui.y = 0 end
    if ui.selected ~= nil and type(ui.selected) ~= 'string' then ui.selected = tostring(ui.selected) end
    self.ui = ui
    self.conversations = ensureTable(db, 'conversations')
    -- Community chats are gone; their cached conversations could no longer load anything.
    for key, conversation in pairs(self.conversations) do
        if type(conversation) == 'table' and conversation.kind == 'COMMUNITY' then
            self.conversations[key] = nil
            if ui.selected == tostring(conversation.key or key) then ui.selected = nil end
        end
    end
    for key, conversation in pairs(self.conversations) do
        if type(conversation) == 'table' then
            conversation.key = tostring(conversation.key or key)
            conversation.messages = type(conversation.messages) == 'table' and conversation.messages or {}
            conversation.draft = type(conversation.draft) == 'string' and conversation.draft or ''
            conversation.unread = isFiniteNumber(conversation.unread) and math.max(0, conversation.unread) or 0
            conversation.pinned = conversation.pinned == true
            conversation.muted = conversation.muted == true
            conversation.closed = conversation.closed == true
            conversation.last = isFiniteNumber(conversation.last) and conversation.last or 0
            -- A group has no class: earlier versions stored the class of whoever spoke last.
            if conversation.kind ~= 'WHISPER' then conversation.classFile = nil end
            if type(conversation.alias) ~= 'string' then conversation.alias = nil end
            if conversation.notify ~= 'always' then conversation.notify = nil end
            conversation.keep = conversation.keep == true or nil
            self._messageIndexes[conversation.key] = {}
            indexConversation(self, conversation)
        else
            self.conversations[key] = nil
        end
    end
    self.people = ensureTable(db, 'people')
    self._peopleCount = 0
    for _ in pairs(self.people) do self._peopleCount = self._peopleCount + 1 end
    for _, conversation in pairs(self.conversations) do self:CapOpposite(conversation) end
    if self.settings.retentionCount > 0 or self.settings.retentionDays > 0 then self:PruneAll() end
    return self
end

function Store:Get(key)
    return self.conversations[tostring(key or '')]
end

function Store:Ensure(spec)
    if type(spec) ~= 'table' then return nil end
    local key = Store.Key(spec)
    if not key or key == '' then return nil end
    local conversation = self.conversations[key]
    if not conversation then
        conversation = {
            key = key, kind = string.upper(tostring(spec.kind or '')), name = tostring(spec.name or spec.target or ''),
            target = spec.target, scope = spec.scope,
            channelName = spec.channelName, classFile = spec.classFile, messages = {}, draft = '',
            unread = 0, pinned = false, muted = false, closed = false, last = 0,
        }
        self.conversations[key] = conversation
        self._messageIndexes[key] = {}
        notify(self, 'conversation', key)
    else
        conversation.kind = conversation.kind or string.upper(tostring(spec.kind or ''))
        for _, field in ipairs({ 'name', 'target', 'scope', 'channelName', 'classFile' }) do
            if spec[field] ~= nil then conversation[field] = spec[field] end
        end
    end
    return conversation
end

local function messageTime(message)
    return isFiniteNumber(message.at) and message.at or 0
end

local function repositionMessage(conversation, message, oldIndex, index)
    local messages = conversation.messages
    local count = #messages
    table.remove(messages, oldIndex)
    local low, high = 1, count
    local at = messageTime(message)
    while low < high do
        local mid = math.floor((low + high) / 2)
        if messageTime(messages[mid]) <= at then low = mid + 1 else high = mid end
    end
    table.insert(messages, low, message)
    local first = math.min(oldIndex, low)
    local last = math.max(oldIndex, low)
    for i = first, last do index[tostring(messages[i].id)] = i end
end

function Store:Append(conversation, message, visibleAtEnd)
    if type(conversation) ~= 'table' or type(message) ~= 'table' then return nil, false end
    local key = tostring(conversation.key or '')
    local messages = conversation.messages
    if type(messages) ~= 'table' then messages = {}; conversation.messages = messages end
    local index = self._messageIndexes[key]
    if not index then indexConversation(self, conversation); index = self._messageIndexes[key] end
    if message.id == nil or tostring(message.id) == '' then
        repeat
            self._localId = self._localId + 1
            message.id = 'local-' .. tostring(self._localId)
        until index[tostring(message.id)] == nil
    end
    local id = tostring(message.id)
    local existingIndex = index[id]
    if existingIndex then
        local existing = messages[existingIndex]
        local changed = false
        local oldAt = messageTime(existing)
        for field, value in pairs(message) do
            if existing[field] ~= value then existing[field] = value; changed = true end
        end
        if existing.deleted and existing.text ~= '' then existing.text = ''; changed = true end
        if messageTime(existing) ~= oldAt then repositionMessage(conversation, existing, existingIndex, index) end
        if changed then notify(self, 'message', key) end
        return existing, false
    end

    local stored = {}
    for field, value in pairs(message) do stored[field] = value end
    stored.id = id
    if not isFiniteNumber(stored.at) then stored.at = self.now() end
    local count = #messages
    if count == 0 or messageTime(messages[count]) <= messageTime(stored) then
        messages[count + 1] = stored
        index[id] = count + 1
    else
        local low, high = 1, count + 1
        local at = messageTime(stored)
        while low < high do
            local mid = math.floor((low + high) / 2)
            if messageTime(messages[mid]) <= at then low = mid + 1 else high = mid end
        end
        table.insert(messages, low, stored)
        for i = low, #messages do index[tostring(messages[i].id)] = i end
    end
    conversation.last = math.max(isFiniteNumber(conversation.last) and conversation.last or 0, messageTime(stored))
    local incoming = stored.outgoing ~= true and stored.context ~= true
    if incoming then
        if not visibleAtEnd then conversation.unread = (tonumber(conversation.unread) or 0) + 1 end
        conversation.closed = false
    end
    self:Prune(conversation)
    self:CapOpposite(conversation)
    notify(self, 'message', key)
    return stored, true
end

function Store:Update(key, id, patch)
    local conversation = self:Get(key)
    if not conversation or type(patch) ~= 'table' then return nil end
    local index = self._messageIndexes[conversation.key] or {}
    local message = conversation.messages[index[tostring(id or '')] or -1]
    if not message then return nil end
    local oldAt = messageTime(message)
    local changed = false
    for field, value in pairs(patch) do
        if field ~= 'id' and message[field] ~= value then message[field] = value; changed = true end
    end
    if message.deleted and message.text ~= '' then message.text = ''; changed = true end
    if messageTime(message) ~= oldAt then repositionMessage(conversation, message, index[tostring(id)], index) end
    if changed then notify(self, 'message', conversation.key) end
    return message
end

function Store:SetDraft(key, text)
    local conversation = self:Get(key); if not conversation then return false end
    text = type(text) == 'string' and text or ''
    if conversation.draft ~= text then conversation.draft = text; notify(self, 'draft', conversation.key) end
    return true
end
function Store:Select(key)
    key = key ~= nil and tostring(key) or nil
    if self.ui.selected ~= key then self.ui.selected = key; notify(self, 'selection', key) end
end
function Store:MarkRead(key)
    local conversation = self:Get(key); if not conversation then return false end
    if conversation.unread ~= 0 then conversation.unread = 0; notify(self, 'read', conversation.key) end
    return true
end
function Store:SetPinned(key, value)
    local conversation = self:Get(key); if not conversation then return false end
    value = value == true
    if conversation.pinned ~= value then conversation.pinned = value; notify(self, 'pinned', conversation.key) end
    return true
end
function Store:SetMuted(key, value)
    local conversation = self:Get(key); if not conversation then return false end
    value = value == true
    if conversation.muted ~= value then conversation.muted = value; notify(self, 'muted', conversation.key) end
    return true
end
function Store:SetClosed(key, value)
    local conversation = self:Get(key); if not conversation then return false end
    value = value == true
    if conversation.closed ~= value then conversation.closed = value; notify(self, 'closed', conversation.key) end
    return true
end

function Store:SetAlias(key, text)
    local conversation = self:Get(key); if not conversation then return false end
    text = type(text) == 'string' and text:match('^%s*(.-)%s*$') or ''
    if text:find('|', 1, true) then return false end
    conversation.alias = text ~= '' and text or nil
    notify(self, 'alias', conversation.key)
    return true
end
function Store:SetNotify(key, mode)
    local conversation = self:Get(key); if not conversation then return false end
    conversation.notify = mode == 'always' and 'always' or nil
    notify(self, 'notify', conversation.key)
    return true
end
function Store:SetKeep(key, value)
    local conversation = self:Get(key); if not conversation then return false end
    conversation.keep = value == true or nil
    notify(self, 'keep', conversation.key)
    return true
end
function Store:IndexOf(key, id)
    local index = self._messageIndexes[tostring(key or '')]
    return index and index[tostring(id or '')] or nil
end

-- Removes one message by id and returns it, or nil when it does not exist.
function Store:RemoveMessage(key, id)
    local conversation = self:Get(key); if not conversation then return nil end
    local at = self:IndexOf(conversation.key, id); if not at then return nil end
    local removed = table.remove(conversation.messages, at)
    indexConversation(self, conversation)
    notify(self, 'clear', conversation.key)
    return removed
end

-- What is known about a sender. One entry per person instead of a copy on every message.
function Store:Person(name)
    if type(name) ~= 'string' or name == '' then return nil end
    return self.people[lower(name)]
end
function Store:SetPerson(name, fields)
    if type(name) ~= 'string' or name == '' or name:find('|', 1, true) then return end
    local key = lower(name)
    local person = self.people[key]
    if not person then
        if self._peopleCount >= PEOPLE_LIMIT then return end
        person = {}; self.people[key] = person; self._peopleCount = self._peopleCount + 1
    end
    for field, value in pairs(fields) do person[field] = value end
end

local function pushBounded(list, text, limit)
    if list[#list] ~= text then list[#list + 1] = text end
    while #list > limit do table.remove(list, 1) end
end
function Store:SentList(key)
    if self.settings.inputHistoryScope == 'global' then return ensureTable(self.db, 'sent') end
    local conversation = self:Get(key); if not conversation then return {} end
    return ensureTable(conversation, 'sent')
end
function Store:AddSent(key, text)
    if not self.settings.inputHistory or type(text) ~= 'string' or text == '' then return end
    local limit = self.settings.inputHistoryScope == 'global' and SENT_GLOBAL or SENT_PER_CONVERSATION
    pushBounded(self:SentList(key), text, limit)
end
function Store:SearchHistory() return ensureTable(self.db, 'searchHistory') end
function Store:AddSearchHistory(text)
    if not self.settings.searchHistoryEnabled or type(text) ~= 'string' or text == '' then return end
    local list = self:SearchHistory()
    for i = #list, 1, -1 do if list[i] == text then table.remove(list, i) end end
    pushBounded(list, text, SEARCH_HISTORY)
end

-- Retention never runs unless the user sets a limit; the defaults keep everything.
local function prunableCount(self, conversation, count, days)
    if conversation.keep then return 0 end
    local messages = conversation.messages
    local total, cut = #messages, 0
    if count > 0 and total > count then cut = total - count end
    if days > 0 then
        local now = self.now()
        if isFiniteNumber(now) and now > 1000000000 then
            local threshold = now - days * 86400
            while cut < total and messageTime(messages[cut + 1]) < threshold do cut = cut + 1 end
        end
    end
    return cut
end
local function removeOldest(self, conversation, cut)
    if cut <= 0 then return end
    local kept = {}
    for i = cut + 1, #conversation.messages do kept[#kept + 1] = conversation.messages[i] end
    conversation.messages = kept
    indexConversation(self, conversation)
    notify(self, 'clear', conversation.key)
end
-- Called for each new message, so a small overshoot is allowed: the array is rebuilt in batches.
function Store:Prune(conversation)
    local count = self.settings.retentionCount
    if count <= 0 or conversation.keep then return end
    if #conversation.messages <= count + math.max(20, math.floor(count * .05)) then return end
    removeOldest(self, conversation, prunableCount(self, conversation, count, self.settings.retentionDays))
end
function Store:CapOpposite(conversation)
    if conversation.kind ~= 'XFACTION' then return end
    local excess = #conversation.messages - OPPOSITE_LIMIT
    if excess > 0 then removeOldest(self, conversation, excess) end
end
function Store:PruneAll()
    for _, conversation in pairs(self.conversations) do
        removeOldest(self, conversation, prunableCount(self, conversation, self.settings.retentionCount, self.settings.retentionDays))
    end
end
function Store:CountPrunable(count, days)
    local total = 0
    for _, conversation in pairs(self.conversations) do total = total + prunableCount(self, conversation, count, days) end
    return total
end
function Store:Stats()
    local conversations, messages, bytes = 0, 0, 0
    for _, conversation in pairs(self.conversations) do
        conversations = conversations + 1
        messages = messages + #conversation.messages
        for _, message in ipairs(conversation.messages) do bytes = bytes + #tostring(message.text or '') end
    end
    return conversations, messages, bytes
end

function Store:Clear(key)
    local conversation = self:Get(key); if not conversation then return false end
    conversation.messages = {}; conversation.unread = 0; self._messageIndexes[conversation.key] = {}
    notify(self, 'clear', conversation.key)
    return true
end
function Store:ClearAll()
    for key, conversation in pairs(self.conversations) do
        conversation.messages = {}; conversation.unread = 0; self._messageIndexes[conversation.key or key] = {}
    end
    notify(self, 'clear-all', nil)
end

function Store:Search(conversation, query)
    if type(conversation) ~= 'table' then return nil end
    query = lower(Store.Plain(query))
    if query == '' then return nil end
    for _, message in ipairs(conversation.messages or {}) do
        if string.find(lower(Store.Plain(message.text)), query, 1, true) then return message end
    end
    return nil
end

-- messageHits (optional) is a table of conversation keys already known to contain the query, so
-- that a list refresh never scans all messages again. Without it the messages are scanned here.
function Store:List(query, messageHits)
    query = Store.Fold(Store.Plain(query))
    local results = {}
    for _, conversation in pairs(self.conversations) do
        local matches = query == '' or string.find(Store.Fold(Store.Plain(conversation.name)), query, 1, true)
            or string.find(Store.Fold(Store.Plain(conversation.target)), query, 1, true)
            or string.find(Store.Fold(conversation.alias), query, 1, true)
        if query ~= '' and not matches then
            if messageHits then matches = messageHits[conversation.key] ~= nil
            else matches = self:Search(conversation, query) ~= nil end
        end
        if (query ~= '' or not conversation.closed) and matches then results[#results + 1] = conversation end
    end
    table.sort(results, function(a, b)
        local ga = groupOrder[Store.Group(a.kind)] or 99
        local gb = groupOrder[Store.Group(b.kind)] or 99
        if ga ~= gb then return ga < gb end
        if a.pinned ~= b.pinned then return a.pinned == true end
        if a.last ~= b.last then return (a.last or 0) > (b.last or 0) end
        local an, bn = lower(a.name), lower(b.name)
        if an ~= bn then return an < bn end
        return tostring(a.key) < tostring(b.key)
    end)
    return results
end

return Store
