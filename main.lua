--[[
    MobileOutput v2
    A mobile-friendly Roblox client Output console.

    New in v2:
      - Filter tabs (All / Info / Warn / Error) with live counts
      - Timestamps and color accent bars on every line
      - Tap a line to copy it, "Copy" button copies everything visible
      - Smart auto-scroll (pauses when you scroll up, "Jump to latest" button)
      - Smooth minimize / restore animation with error count in the title
      - Window stays on-screen, resize is clamped, press feedback on touch
      - Pre-fills recent log history when launched
]]

local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

--==================================================
-- SETTINGS
--==================================================

local MAX_MESSAGES = 150
local MAX_MESSAGE_LENGTH = 2000
local PREFILL_HISTORY = true
local FONT_SIZE = 13

local HEADER_H = 44
local FILTER_H = 34
local MIN_W, MIN_H = 280, 220
local MAX_W, MAX_H = 650, 600
local MINI_W = 220

--==================================================
-- EXECUTOR ENVIRONMENT
--==================================================

local env = _G

if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)

    if ok and type(result) == "table" then
        env = result
    end
end

-- Clean up a previous copy if this script is run again.
if type(env.MobileOutputCleanup) == "function" then
    pcall(env.MobileOutputCleanup)
end

local function getRequestFunction()
    if type(env.request) == "function" then
        return env.request
    end

    if type(env.http_request) == "function" then
        return env.http_request
    end

    if type(env.syn) == "table"
        and type(env.syn.request) == "function" then
        return env.syn.request
    end

    return nil
end

local requestFunction = getRequestFunction()
local clipboardFunction = env.setclipboard or env.toclipboard or env.set_clipboard

local function downloadAsset(filename, url)
    local fileExists = env.isfile
    local saveFile = env.writefile
    local getAsset = env.getcustomasset or env.getsynasset

    if type(fileExists) ~= "function"
        or type(saveFile) ~= "function"
        or type(getAsset) ~= "function"
        or type(requestFunction) ~= "function" then
        return nil
    end

    local ok, result = pcall(function()
        if not fileExists(filename) then
            local response = requestFunction({
                Url = url,
                Method = "GET",
            })

            assert(
                response and response.StatusCode == 200,
                "Image download failed: " .. filename
            )

            saveFile(filename, response.Body)
        end

        return getAsset(filename)
    end)

    if ok then
        return result
    end

    warn("[MobileOutput] " .. tostring(result))
    return nil
end

local IMAGE_BASE = "https://raw.githubusercontent.com/YetYoursTruly/OutputMobile/main/Images/"

-- Local filenames are versioned so old cached (dark) copies are ignored.
local minimizeIcon = downloadAsset("MobileOutput_v2_minimize-2.png", IMAGE_BASE .. "minimize-2.png")
local maximizeIcon = downloadAsset("MobileOutput_v2_maximize.png", IMAGE_BASE .. "maximize.png")
local resizeIcon = downloadAsset("MobileOutput_v2_handle-bottom-right.png", IMAGE_BASE .. "handle-bottom-right.png")

--==================================================
-- THEME
--==================================================

local Colors = {
    Background = Color3.fromRGB(13, 21, 30),
    Surface = Color3.fromRGB(21, 36, 49),
    Header = Color3.fromRGB(24, 42, 57),
    Border = Color3.fromRGB(47, 74, 93),

    Accent = Color3.fromRGB(94, 190, 235),
    Info = Color3.fromRGB(150, 205, 232),
    Warning = Color3.fromRGB(245, 210, 125),
    Error = Color3.fromRGB(240, 140, 140),

    Text = Color3.fromRGB(225, 237, 245),
    Muted = Color3.fromRGB(125, 152, 170),
    Button = Color3.fromRGB(40, 64, 82),
    CloseButton = Color3.fromRGB(94, 52, 62),
}

local KIND_COLORS = {
    info = Colors.Info,
    warn = Colors.Warning,
    error = Colors.Error,
}

local KIND_NAMES = {
    info = "INFO",
    warn = "WARN",
    error = "ERROR",
}

--==================================================
-- HELPERS
--==================================================

local connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function new(className, props, parent)
    local instance = Instance.new(className)

    for key, value in pairs(props) do
        instance[key] = value
    end

    instance.Parent = parent
    return instance
end

local function addCorner(instance, radius)
    return new("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, instance)
end

local function addPadding(instance, left, right, top, bottom)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, instance)
end

local function tween(instance, props, duration)
    TweenService:Create(
        instance,
        TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props
    ):Play()
end

local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function escapeRich(text)
    text = string.gsub(text, "&", "&amp;")
    text = string.gsub(text, "<", "&lt;")
    text = string.gsub(text, ">", "&gt;")
    return text
end

local function isPointerStart(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

--==================================================
-- CLEAN UP OLD GUI
--==================================================

local oldGui = CoreGui:FindFirstChild("MobileOutput")

if oldGui then
    oldGui:Destroy()
end

--==================================================
-- GUI SETUP
--==================================================

local gui = new("ScreenGui", {
    Name = "MobileOutput",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Start with a size that fits the current screen.
local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)

local startWidth = math.clamp(math.floor(viewport.X * 0.92), MIN_W, MAX_W)
local startHeight = math.clamp(math.floor(viewport.Y * 0.55), MIN_H, MAX_H)

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(startWidth, startHeight),
    Position = UDim2.fromOffset(
        math.max(0, math.floor((viewport.X - startWidth) / 2)),
        math.floor(viewport.Y * 0.16)
    ),
    BackgroundColor3 = Colors.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
}, gui)

addCorner(window, 12)

local windowStroke = new("UIStroke", {
    Color = Colors.Border,
    Thickness = 1,
    Transparency = 0.2,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, window)

--==================================================
-- HEADER
--==================================================

local header = new("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundColor3 = Colors.Header,
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 2,
}, window)

addCorner(header, 12)

-- Squares the lower corners of the header (hidden when minimized).
local headerFill = new("Frame", {
    Name = "HeaderFill",
    Position = UDim2.new(0, 0, 1, -12),
    Size = UDim2.new(1, 0, 0, 12),
    BackgroundColor3 = Colors.Header,
    BorderSizePixel = 0,
    ZIndex = 2,
}, header)

local headerLine = new("Frame", {
    Name = "HeaderLine",
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Colors.Border,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    ZIndex = 3,
}, header)

local statusDot = new("Frame", {
    Name = "StatusDot",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 13, 0.5, 0),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = Colors.Accent,
    BorderSizePixel = 0,
    ZIndex = 3,
}, header)

addCorner(statusDot, 4)

local titleLabel = new("TextLabel", {
    Name = "Title",
    Position = UDim2.new(0, 28, 0, 0),
    Size = UDim2.new(1, -204, 1, 0),
    BackgroundTransparency = 1,
    Text = "Output",
    TextColor3 = Colors.Text,
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 3,
}, header)

--==================================================
-- HEADER BUTTONS
--==================================================

local function createHeaderButton(name, text, width, rightOffset, baseColor)
    local button = new("TextButton", {
        Name = name,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -rightOffset, 0.5, 0),
        Size = UDim2.fromOffset(width, 30),
        BackgroundColor3 = baseColor or Colors.Button,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = Colors.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        ZIndex = 4,
    }, header)

    addCorner(button, 8)

    -- Hover for mouse, press feedback for touch.
    connect(button.MouseEnter, function()
        tween(button, { BackgroundTransparency = 0 }, 0.12)
    end)

    connect(button.MouseLeave, function()
        tween(button, { BackgroundTransparency = 0.35 }, 0.15)
    end)

    connect(button.InputBegan, function(input)
        if isPointerStart(input) then
            tween(button, { BackgroundTransparency = 0 }, 0.05)
        end
    end)

    connect(button.InputEnded, function(input)
        if isPointerStart(input) then
            tween(button, { BackgroundTransparency = 0.35 }, 0.2)
        end
    end)

    return button
end

local closeButton = createHeaderButton("CloseButton", "×", 30, 7, Colors.CloseButton)
closeButton.TextSize = 22
closeButton.Font = Enum.Font.Gotham

local minimizeButton = createHeaderButton("MinimizeButton", "", 30, 43)
local clearButton = createHeaderButton("ClearButton", "Clear", 44, 79)
local copyButton = createHeaderButton("CopyButton", "Copy", 44, 127)

local minimizeImage

if minimizeIcon then
    minimizeImage = new("ImageLabel", {
        Name = "MinimizeIcon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Image = minimizeIcon,
        ImageColor3 = Colors.Text,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 5,
    }, minimizeButton)
else
    minimizeButton.Text = "–"
    minimizeButton.TextSize = 20
end

-- Swaps the button between the minimize and maximize looks.
local function setMinimizeButtonLook(isMinimized)
    if minimizeImage then
        local icon = isMinimized and maximizeIcon or minimizeIcon

        if icon then
            minimizeImage.Image = icon
            minimizeImage.Visible = true
            minimizeButton.Text = ""
            return
        end

        minimizeImage.Visible = false
    end

    minimizeButton.Text = isMinimized and "□" or "–"
    minimizeButton.TextSize = isMinimized and 16 or 20
end

--==================================================
-- BODY (filters + messages)
--==================================================

local body = new("Frame", {
    Name = "Body",
    Position = UDim2.new(0, 0, 0, HEADER_H),
    Size = UDim2.new(1, 0, 1, -HEADER_H),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, window)

local filterBar = new("Frame", {
    Name = "Filters",
    Size = UDim2.new(1, 0, 0, FILTER_H),
    BackgroundTransparency = 1,
    ZIndex = 2,
}, body)

new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 4),
}, filterBar)

addPadding(filterBar, 10, 10, 0, 0)

local scrolling = new("ScrollingFrame", {
    Name = "Messages",
    Position = UDim2.new(0, 8, 0, FILTER_H + 2),
    Size = UDim2.new(1, -16, 1, -(FILTER_H + 8)),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Colors.Border,
    ScrollBarImageTransparency = 0.2,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
    ClipsDescendants = true,
}, body)

local listLayout = new("UIListLayout", {
    Name = "MessageLayout",
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, scrolling)

addPadding(scrolling, 0, 4, 2, 30)

local emptyLabel = new("TextLabel", {
    Name = "EmptyState",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 10),
    Size = UDim2.new(1, -40, 0, 40),
    BackgroundTransparency = 1,
    Text = "No messages yet",
    TextColor3 = Colors.Muted,
    TextSize = 14,
    Font = Enum.Font.GothamMedium,
    ZIndex = 2,
}, body)

local latestButton = new("TextButton", {
    Name = "LatestButton",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 12, 1, -10),
    Size = UDim2.new(0, 0, 0, 28),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = Colors.Accent,
    BorderSizePixel = 0,
    AutoButtonColor = true,
    Text = "Jump to latest",
    TextColor3 = Colors.Background,
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    Visible = false,
    ZIndex = 9,
}, body)

addCorner(latestButton, 14)
addPadding(latestButton, 12, 12, 0, 0)

--==================================================
-- RESIZE HANDLE + TOAST
--==================================================

local resizeHandle = new("ImageButton", {
    Name = "ResizeHandle",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -4, 1, -4),
    Size = UDim2.fromOffset(24, 24),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Image = resizeIcon or "",
    ImageColor3 = Colors.Muted,
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = 10,
}, window)

if not resizeIcon then
    new("TextLabel", {
        Name = "ResizeFallback",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "◢",
        TextColor3 = Colors.Muted,
        TextSize = 17,
        Font = Enum.Font.Gotham,
        ZIndex = 11,
    }, resizeHandle)
end

local toast = new("TextLabel", {
    Name = "Toast",
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -12),
    Size = UDim2.new(0, 0, 0, 28),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = Colors.Header,
    BorderSizePixel = 0,
    Text = "",
    TextColor3 = Colors.Text,
    TextSize = 12,
    Font = Enum.Font.GothamMedium,
    Visible = false,
    ZIndex = 12,
}, window)

addCorner(toast, 14)
addPadding(toast, 14, 14, 0, 0)

new("UIStroke", {
    Color = Colors.Border,
    Thickness = 1,
    Transparency = 0.2,
}, toast)

local toastToken = 0

local function showToast(text)
    toastToken += 1
    local token = toastToken

    toast.Text = text
    toast.Visible = true

    task.delay(1.4, function()
        if toastToken == token and toast.Parent then
            toast.Visible = false
        end
    end)
end

local function copyText(text)
    if type(clipboardFunction) ~= "function" then
        showToast("Clipboard not supported")
        return
    end

    local ok = pcall(clipboardFunction, text)
    showToast(ok and "Copied" or "Copy failed")
end

--==================================================
-- STATE
--==================================================

local entries = {}
local counts = { info = 0, warn = 0, error = 0 }
local currentFilter = "all"
local nextId = 0
local stickToBottom = true
local minimized = false
local expandedSize = window.Size

local tabs = {}

local FILTERS = {
    { id = "all", label = "All" },
    { id = "info", label = "Info" },
    { id = "warn", label = "Warn" },
    { id = "error", label = "Error" },
}

local function totalCount()
    return counts.info + counts.warn + counts.error
end

local function updateTitle()
    if minimized then
        if counts.error > 0 then
            titleLabel.Text = string.format("Output · %d err", counts.error)
            titleLabel.TextColor3 = Colors.Error
        elseif counts.warn > 0 then
            titleLabel.Text = string.format("Output · %d warn", counts.warn)
            titleLabel.TextColor3 = Colors.Warning
        else
            titleLabel.Text = "Output"
            titleLabel.TextColor3 = Colors.Text
        end
    else
        titleLabel.Text = "Output"
        titleLabel.TextColor3 = Colors.Text
    end
end

local function updateTabs()
    for _, filter in ipairs(FILTERS) do
        local tab = tabs[filter.id]
        local count = filter.id == "all" and totalCount() or counts[filter.id]

        if filter.id == "all" then
            tab.Text = string.format("All %d", count)
        elseif count > 0 then
            tab.Text = string.format("%s %d", filter.label, count)
        else
            tab.Text = filter.label
        end

        local active = currentFilter == filter.id
        tween(tab, {
            BackgroundColor3 = active and Colors.Accent or Colors.Button,
            BackgroundTransparency = active and 0 or 0.35,
            TextColor3 = active and Colors.Background or Colors.Muted,
        }, 0.12)
    end

    -- Status dot reflects the worst recent level.
    if counts.error > 0 then
        statusDot.BackgroundColor3 = Colors.Error
    elseif counts.warn > 0 then
        statusDot.BackgroundColor3 = Colors.Warning
    else
        statusDot.BackgroundColor3 = Colors.Accent
    end

    updateTitle()
end

local function scrollToBottom()
    scrolling.CanvasPosition = Vector2.new(
        0,
        math.max(0, scrolling.AbsoluteCanvasSize.Y - scrolling.AbsoluteWindowSize.Y)
    )
end

local function applyFilter()
    local anyVisible = false

    for _, entry in ipairs(entries) do
        local visible = currentFilter == "all" or currentFilter == entry.kind
        entry.row.Visible = visible

        if visible then
            anyVisible = true
        end
    end

    emptyLabel.Visible = not anyVisible
    emptyLabel.Text = #entries == 0 and "No messages yet" or "Nothing matches this filter"

    updateTabs()
end

local function setFilter(id)
    currentFilter = id
    stickToBottom = true
    applyFilter()
    task.defer(scrollToBottom)
end

for index, filter in ipairs(FILTERS) do
    local tab = new("TextButton", {
        Name = filter.label .. "Tab",
        Size = UDim2.new(0, 0, 0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Colors.Button,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = filter.label,
        TextColor3 = Colors.Muted,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = index,
        ZIndex = 3,
    }, filterBar)

    addCorner(tab, 13)
    addPadding(tab, 9, 9, 0, 0)

    tabs[filter.id] = tab

    connect(tab.Activated, function()
        setFilter(filter.id)
    end)
end

--==================================================
-- MESSAGES
--==================================================

local function getKind(messageType)
    if messageType == Enum.MessageType.MessageError then
        return "error"
    end

    if messageType == Enum.MessageType.MessageWarning then
        return "warn"
    end

    return "info"
end

local function removeOldest()
    local oldest = table.remove(entries, 1)

    if oldest then
        counts[oldest.kind] = math.max(0, counts[oldest.kind] - 1)

        if oldest.row and oldest.row.Parent then
            oldest.row:Destroy()
        end
    end
end

local function addMessage(message, messageType, timestamp)
    if not gui.Parent then
        return
    end

    local text = tostring(message)

    if #text > MAX_MESSAGE_LENGTH then
        text = string.sub(text, 1, MAX_MESSAGE_LENGTH) .. "..."
    end

    local kind = getKind(messageType)
    local color = KIND_COLORS[kind]
    local timeText = os.date("%H:%M:%S", type(timestamp) == "number" and timestamp or os.time())

    nextId += 1

    local row = new("Frame", {
        Name = "Message",
        Size = UDim2.new(1, -6, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Colors.Surface,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        LayoutOrder = nextId,
        ZIndex = 2,
    }, scrolling)

    addCorner(row, 8)

    new("Frame", {
        Name = "Accent",
        Position = UDim2.new(0, 0, 0, 6),
        Size = UDim2.new(0, 3, 1, -12),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, row)

    local label = new("TextLabel", {
        Name = "Text",
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = FONT_SIZE,
        TextColor3 = color,
        RichText = true,
        Text = string.format(
            '<font color="%s" size="%d">%s</font>  %s',
            toHex(Colors.Muted),
            FONT_SIZE - 2,
            timeText,
            escapeRich(text)
        ),
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 2,
    }, row)

    addPadding(label, 4, 6, 6, 6)

    -- Invisible tap target: tap a line to copy it.
    local tapTarget = new("TextButton", {
        Name = "TapTarget",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
    }, row)

    connect(tapTarget.Activated, function()
        copyText(string.format("[%s] [%s] %s", timeText, KIND_NAMES[kind], text))
        row.BackgroundTransparency = 0
        tween(row, { BackgroundTransparency = 0.3 }, 0.35)
    end)

    counts[kind] += 1

    table.insert(entries, {
        id = nextId,
        row = row,
        kind = kind,
        text = text,
        time = timeText,
    })

    while #entries > MAX_MESSAGES do
        removeOldest()
    end

    row.Visible = currentFilter == "all" or currentFilter == kind

    if row.Visible then
        emptyLabel.Visible = false
    end

    updateTabs()
end

local function clearMessages()
    for _, entry in ipairs(entries) do
        if entry.row and entry.row.Parent then
            entry.row:Destroy()
        end
    end

    table.clear(entries)
    counts.info, counts.warn, counts.error = 0, 0, 0

    stickToBottom = true
    latestButton.Visible = false
    scrolling.CanvasPosition = Vector2.new(0, 0)

    applyFilter()
end

local function copyAll()
    local lines = {}

    for _, entry in ipairs(entries) do
        if currentFilter == "all" or currentFilter == entry.kind then
            table.insert(lines, string.format(
                "[%s] [%s] %s",
                entry.time,
                KIND_NAMES[entry.kind],
                entry.text
            ))
        end
    end

    if #lines == 0 then
        showToast("Nothing to copy")
        return
    end

    copyText(table.concat(lines, "\n"))
end

--==================================================
-- AUTO SCROLL
--==================================================

connect(scrolling:GetPropertyChangedSignal("CanvasPosition"), function()
    local maxY = math.max(0, scrolling.AbsoluteCanvasSize.Y - scrolling.AbsoluteWindowSize.Y)

    stickToBottom = scrolling.CanvasPosition.Y >= maxY - 24
    latestButton.Visible = not stickToBottom and #entries > 0
end)

connect(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    if stickToBottom then
        task.defer(scrollToBottom)
    end
end)

connect(latestButton.Activated, function()
    stickToBottom = true
    latestButton.Visible = false
    scrollToBottom()
end)

connect(clearButton.Activated, clearMessages)
connect(copyButton.Activated, copyAll)

--==================================================
-- WINDOW HELPERS
--==================================================

local function clampPosition(x, y, width)
    local screen = gui.AbsoluteSize

    return Vector2.new(
        math.clamp(x, 0, math.max(0, screen.X - width)),
        math.clamp(y, 0, math.max(0, screen.Y - HEADER_H))
    )
end

--==================================================
-- WINDOW DRAGGING
--==================================================

local dragging = false
local dragInput = nil
local dragStart = nil
local dragOrigin = nil

connect(header.InputBegan, function(input)
    if not isPointerStart(input) then
        return
    end

    dragging = true
    dragStart = input.Position
    dragOrigin = window.AbsolutePosition
    dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil

    local changed
    changed = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragging = false
            dragInput = nil
            changed:Disconnect()
        end
    end)
end)

--==================================================
-- WINDOW RESIZING
--==================================================

local resizing = false
local resizeInput = nil
local resizeStart = nil
local resizeOrigin = nil

connect(resizeHandle.InputBegan, function(input)
    if not isPointerStart(input) then
        return
    end

    resizing = true
    resizeStart = input.Position
    resizeOrigin = window.AbsoluteSize
    resizeInput = input.UserInputType == Enum.UserInputType.Touch and input or nil

    local changed
    changed = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            resizing = false
            resizeInput = nil
            changed:Disconnect()
        end
    end)
end)

connect(UserInputService.InputChanged, function(input)
    local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement

    if dragging and dragStart and dragOrigin then
        if isMouse or (dragInput ~= nil and input == dragInput) then
            local delta = input.Position - dragStart
            local position = clampPosition(
                dragOrigin.X + delta.X,
                dragOrigin.Y + delta.Y,
                window.AbsoluteSize.X
            )

            window.Position = UDim2.fromOffset(position.X, position.Y)
        end
    end

    if resizing and resizeStart and resizeOrigin then
        if isMouse or (resizeInput ~= nil and input == resizeInput) then
            local delta = input.Position - resizeStart
            local screen = gui.AbsoluteSize
            local origin = window.AbsolutePosition

            local width = math.clamp(
                resizeOrigin.X + delta.X,
                MIN_W,
                math.max(MIN_W, math.min(MAX_W, screen.X - origin.X))
            )

            local height = math.clamp(
                resizeOrigin.Y + delta.Y,
                MIN_H,
                math.max(MIN_H, math.min(MAX_H, screen.Y - origin.Y))
            )

            window.Size = UDim2.fromOffset(width, height)
            expandedSize = window.Size
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        resizing = false
    end
end)

--==================================================
-- MINIMIZE AND RESTORE
--==================================================

local function setMinimized(state)
    if minimized == state then
        return
    end

    minimized = state

    if state then
        expandedSize = window.Size

        body.Visible = false
        resizeHandle.Visible = false
        copyButton.Visible = false
        clearButton.Visible = false
        toast.Visible = false
        headerFill.Visible = false
        headerLine.Visible = false

        titleLabel.Size = UDim2.new(1, -112, 1, 0)

        setMinimizeButtonLook(true)

        tween(window, { Size = UDim2.fromOffset(MINI_W, HEADER_H) }, 0.2)
        tween(window, { BackgroundColor3 = Colors.Header }, 0.2)
    else
        body.Visible = true
        resizeHandle.Visible = true
        copyButton.Visible = true
        clearButton.Visible = true
        headerFill.Visible = true
        headerLine.Visible = true

        titleLabel.Size = UDim2.new(1, -204, 1, 0)

        setMinimizeButtonLook(false)

        -- Keep the restored window fully on-screen.
        local position = clampPosition(
            window.AbsolutePosition.X,
            window.AbsolutePosition.Y,
            expandedSize.X.Offset
        )

        window.Position = UDim2.fromOffset(position.X, position.Y)

        tween(window, { Size = expandedSize }, 0.2)
        tween(window, { BackgroundColor3 = Colors.Background }, 0.2)

        task.defer(function()
            if stickToBottom then
                scrollToBottom()
            end
        end)
    end

    updateTitle()
end

connect(minimizeButton.Activated, function()
    setMinimized(not minimized)
end)

--==================================================
-- CLOSE AND CLEANUP
--==================================================

local cleanedUp = false

local function cleanup()
    if cleanedUp then
        return
    end

    cleanedUp = true

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    if env.MobileOutputCleanup == cleanup then
        env.MobileOutputCleanup = nil
    end

    pcall(function()
        gui:Destroy()
    end)
end

env.MobileOutputCleanup = cleanup

connect(closeButton.Activated, cleanup)

--==================================================
-- START
--==================================================

applyFilter()

if PREFILL_HISTORY then
    local ok, history = pcall(function()
        return LogService:GetLogHistory()
    end)

    if ok and type(history) == "table" then
        local first = math.max(1, #history - MAX_MESSAGES + 1)

        for index = first, #history do
            local entry = history[index]
            addMessage(entry.message, entry.messageType, entry.timestamp)
        end
    end
end

connect(LogService.MessageOut, function(message, messageType)
    addMessage(message, messageType)
end)

gui.Parent = CoreGui

task.defer(scrollToBottom)