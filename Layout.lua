local addonName, Z = ...

local Layout = {}
Z.Layout = Layout

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function clean(value, fallback)
    if not finite(value) then return fallback end
    return value
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function autoMode(width)
    if width >= 960 then return 'full' end
    if width >= 760 then return 'names' end
    return 'icons'
end

local function resolveAuto(width, previousMode)
    if previousMode == 'icons' then
        if width >= 984 then return 'full' end
        if width >= 784 then return 'names' end
        return 'icons'
    elseif previousMode == 'names' then
        if width < 760 then return 'icons' end
        if width >= 984 then return 'full' end
        return 'names'
    elseif previousMode == 'full' then
        if width < 760 then return 'icons' end
        if width < 960 then return 'names' end
        return 'full'
    end
    return autoMode(width)
end

function Layout.Resolve(width, height, settings, previousMode)
    settings = type(settings) == 'table' and settings or {}
    width = math.max(540, clean(width, 1060))
    height = math.max(360, clean(height, 680))
    local mode = settings.sidebar
    local manualNames = mode == 'names'
    if mode ~= 'full' and mode ~= 'names' and mode ~= 'icons' then
        mode = resolveAuto(width, previousMode)
    end
    local manualNameWidth = clamp(180 + (width - 540) * (30 / 220), 180, 210)
    local sidebarWidth = mode == 'full' and 300 or (mode == 'icons' and 60 or (manualNames and manualNameWidth or 210))
    return {
        width = width, height = height, mode = mode, sidebarWidth = sidebarWidth,
        showPreview = mode == 'full' and settings.previews ~= false, iconOnly = mode == 'icons',
        contentWidth = math.max(0, width - sidebarWidth), settingsStacked = width < 760,
        titleHeight = 40, headerHeight = 58, composerHeight = 74,
    }
end

function Layout.Clamp(width, height, requestedScale, screenWidth, screenHeight)
    width = math.max(540, clean(width, 1060))
    height = math.max(360, clean(height, 680))
    requestedScale = clamp(clean(requestedScale, 1), .75, 1.5)
    screenWidth = math.max(0, clean(screenWidth, width * requestedScale))
    screenHeight = math.max(0, clean(screenHeight, height * requestedScale))
    width = math.max(540, math.min(width, screenWidth / requestedScale - 16))
    height = math.max(360, math.min(height, screenHeight / requestedScale - 16))
    local effectiveScale = math.min(requestedScale, screenWidth / (width + 16), screenHeight / (height + 16))
    if not finite(effectiveScale) then effectiveScale = requestedScale end
    return width, height, effectiveScale
end

local function firstIntersecting(prefix, position, count)
    local low, high = 1, count + 1
    while low < high do
        local mid = math.floor((low + high) / 2)
        if prefix[mid + 1] <= position then low = mid + 1 else high = mid end
    end
    return low
end

local function lastIntersecting(prefix, position, count)
    local low, high = 1, count + 1
    while low < high do
        local mid = math.floor((low + high) / 2)
        if prefix[mid] < position then low = mid + 1 else high = mid end
    end
    return low - 1
end

function Layout.VisibleRange(prefix, scroll, viewport, overscan)
    if type(prefix) ~= 'table' or #prefix < 2 then return 1, 0 end
    local count = #prefix - 1
    scroll = math.max(0, clean(scroll, 0))
    viewport = math.max(0, clean(viewport, 0))
    overscan = math.max(0, math.floor(clean(overscan, 0)))
    if viewport == 0 then return 1, 0 end
    local first = firstIntersecting(prefix, scroll, count)
    if first > count then return count + 1, count end
    local last = lastIntersecting(prefix, scroll + viewport, count)
    if last < first then last = first end
    first = math.max(1, first - overscan)
    last = math.min(count, last + overscan)
    return first, last
end

function Layout.CaptureAnchor(prefix, scroll, messages)
    if type(prefix) ~= 'table' or type(messages) ~= 'table' or #messages == 0 then return nil end
    local count = math.min(#messages, #prefix - 1)
    if count <= 0 then return nil end
    scroll = math.max(0, clean(scroll, 0))
    local index = firstIntersecting(prefix, scroll, count)
    if index > count then index = count end
    local rowHeight = math.max(0, prefix[index + 1] - prefix[index])
    return { id = messages[index].id, offset = clamp(scroll - prefix[index], 0, rowHeight) }
end

function Layout.RestoreAnchor(anchor, prefix, messages)
    if type(anchor) ~= 'table' or type(prefix) ~= 'table' or type(messages) ~= 'table' then return 0 end
    local count = math.min(#messages, #prefix - 1)
    for i = 1, count do
        if messages[i].id == anchor.id then
            local rowHeight = math.max(0, prefix[i + 1] - prefix[i])
            local offset = clamp(clean(anchor.offset, 0), 0, rowHeight)
            return math.max(0, prefix[i] + offset)
        end
    end
    return 0
end

return Layout
