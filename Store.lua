local addonName, Z = ...

local Store = {}
Store.__index = Store
Z.Store = Store

local defaults = {
    alphaActive = .98, alphaInactive = .94, scale = 1, fontSize = 14,
    sidebar = 'auto', previews = true, locked = false, focusOnOpen = false,
    autoOpen = false, publicChannels = false, enabledChannels = {},
    clubId = nil, streams = {},
    minimapHidden = false, minimapAngle = 200,
}

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
        minimapAngle = { -360, 360 },
    }
    for key, bounds in pairs(numericBounds) do
        local value = settings[key]
        if not isFiniteNumber(value) or value < bounds[1] or value > bounds[2] then
            settings[key] = defaults[key]
        end
    end
    local booleanKeys = { 'previews', 'locked', 'focusOnOpen', 'autoOpen', 'publicChannels', 'minimapHidden' }
    for _, key in ipairs(booleanKeys) do
        if type(settings[key]) ~= 'boolean' then settings[key] = defaults[key] end
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
    if type(settings.streams) ~= 'table' then settings.streams = {} end
    local notificationDefaults = {
        whispers = { sound = true, toast = true },
        guild = { sound = false, toast = false },
        groups = { sound = false, toast = false },
        community = { sound = false, toast = false },
        channels = { sound = false, toast = false },
    }
    local notifications = ensureTable(settings, 'notifications')
    for group, values in pairs(notificationDefaults) do
        local saved = ensureTable(notifications, group)
        for key, default in pairs(values) do
            if type(saved[key]) ~= 'boolean' then saved[key] = default end
        end
    end
end

local function lower(value)
    return string.lower(tostring(value or ''))
end

local kindGroups = {
    COMMUNITY = 'community', GUILD = 'guild', OFFICER = 'guild',
    PARTY = 'groups', RAID = 'groups', INSTANCE_CHAT = 'groups',
    WHISPER = 'people', BN_WHISPER = 'people', CHANNEL = 'channels',
}
local groupOrder = { community = 1, guild = 2, groups = 3, people = 4, channels = 5 }

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
    elseif kind == 'COMMUNITY' then
        parts[#parts + 1] = encode(spec.clubId)
        parts[#parts + 1] = encode(spec.streamId)
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
            self._messageIndexes[conversation.key] = {}
            indexConversation(self, conversation)
        else
            self.conversations[key] = nil
        end
    end
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
            target = spec.target, scope = spec.scope, clubId = spec.clubId, streamId = spec.streamId,
            channelName = spec.channelName, classFile = spec.classFile, messages = {}, draft = '',
            unread = 0, pinned = false, muted = false, closed = false, last = 0,
        }
        self.conversations[key] = conversation
        self._messageIndexes[key] = {}
        notify(self, 'conversation', key)
    else
        conversation.kind = conversation.kind or string.upper(tostring(spec.kind or ''))
        for _, field in ipairs({ 'name', 'target', 'scope', 'clubId', 'streamId', 'channelName', 'classFile' }) do
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

function Store:Clear(key)
    local conversation = self:Get(key); if not conversation then return false end
    conversation.messages = {}; conversation.unread = 0; conversation.historySync=nil; self._messageIndexes[conversation.key] = {}
    notify(self, 'clear', conversation.key)
    return true
end
function Store:ClearAll()
    for key, conversation in pairs(self.conversations) do
        conversation.messages = {}; conversation.unread = 0; conversation.historySync=nil; self._messageIndexes[conversation.key or key] = {}
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

function Store:List(query)
    query = lower(Store.Plain(query))
    local results = {}
    for _, conversation in pairs(self.conversations) do
        local matches = query == '' or string.find(lower(Store.Plain(conversation.name)), query, 1, true)
            or string.find(lower(Store.Plain(conversation.target)), query, 1, true)
        if query ~= '' and not matches then matches = self:Search(conversation, query) ~= nil end
        if (query ~= '' or not conversation.closed) and matches then results[#results + 1] = conversation end
    end
    table.sort(results, function(a, b)
        local ga = groupOrder[Store.Group(a.kind)] or 99
        local gb = groupOrder[Store.Group(b.kind)] or 99
        if ga ~= gb then return ga < gb end
        if a.pinned ~= b.pinned then return a.pinned == true end
        if a.kind=='COMMUNITY'and b.kind=='COMMUNITY'then
            local slots={general=1,horde=2,alliance=3}
            local sa,sb=slots[a.slot]or 4,slots[b.slot]or 4
            if sa~=sb then return sa<sb end
        end
        if a.last ~= b.last then return (a.last or 0) > (b.last or 0) end
        local an, bn = lower(a.name), lower(b.name)
        if an ~= bn then return an < bn end
        return tostring(a.key) < tostring(b.key)
    end)
    return results
end

return Store
