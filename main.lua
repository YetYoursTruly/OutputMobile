
--[[
    MobileOutput
    A mobile-friendly Roblox client Output console.
]]

local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

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

local minimizeIcon = downloadAsset(
    "minimize-2.png",
    "https://raw.githubusercontent.com/YetYoursTruly/OutputMobile/main/Images/minimize-2.png"
)

local resizeIcon = downloadAsset(
    "handle-bottom-right.png",
    "https://raw.githubusercontent.com/YetYoursTruly/OutputMobile/main/Images/handle-bottom-right.png"
)

--==================================================
-- COLORS
--==================================================

local Colors = {
    Background = Color3.fromRGB(17, 27, 38),
    Header = Color3.fromRGB(28, 49, 65),
    Border = Color3.fromRGB(48, 75, 94),

    Info = Color3.fromRGB(117, 190, 224),
    Warning = Color3.fromRGB(245, 210, 125),
    Error = Color3.fromRGB(239, 137, 137),

    Text = Color3.fromRGB(225, 237, 245),
    Muted = Color3.fromRGB(150, 174, 190),
    Button = Color3.fromRGB(43, 68, 84),
}

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

local gui = Instance.new("ScreenGui")
gui.Name = "MobileOutput"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.new(0.92, 0, 0.52, 0)
window.Position = UDim2.new(0.04, 0, 0.22, 0)
window.BackgroundColor3 = Colors.Background
window.BorderSizePixel = 0
window.ClipsDescendants = true
window.Active = true
window.ZIndex = 1
window.Parent = gui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 10)
windowCorner.Parent = window

local windowStroke = Instance.new("UIStroke")
windowStroke.Color = Colors.Border
windowStroke.Thickness = 1
windowStroke.Transparency = 0.25
windowStroke.Parent = window

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(250, 220)
sizeConstraint.MaxSize = Vector2.new(650, 600)
sizeConstraint.Parent = window

--==================================================
-- HEADER
--==================================================

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Colors.Header
header.BorderSizePixel = 0
header.Active = true
header.ZIndex = 2
header.Parent = window

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

-- Squares the lower corners of the header.
local headerFill = Instance.new("Frame")
headerFill.Name = "HeaderFill"
headerFill.Position = UDim2.new(0, 0, 0, 10)
headerFill.Size = UDim2.new(1, 0, 0, 34)
headerFill.BackgroundColor3 = Colors.Header
headerFill.BorderSizePixel = 0
headerFill.ZIndex = 2
headerFill.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Size = UDim2.new(0, 90, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Output"
titleLabel.TextColor3 = Colors.Text
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamMedium
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 3
titleLabel.Parent = header

--==================================================
-- HEADER BUTTONS
--==================================================

local function createHeaderButton(name, text, width, rightOffset)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AnchorPoint = Vector2.new(1, 0.5)
    button.Position = UDim2.new(1, -rightOffset, 0.5, 0)
    button.Size = UDim2.new(0, width, 0, 30)
    button.BackgroundColor3 = Colors.Button
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = text
    button.TextColor3 = Colors.Text
    button.TextSize = 15
    button.Font = Enum.Font.GothamMedium
    button.ZIndex = 4
    button.Parent = header

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    button.MouseEnter:Connect(function()
        button.BackgroundTransparency = 0
    end)

    button.MouseLeave:Connect(function()
        button.BackgroundTransparency = 1
    end)

    return button
end

local closeButton = createHeaderButton(
    "CloseButton",
    "×",
    30,
    7
)

closeButton.TextSize = 23

local minimizeButton = createHeaderButton(
    "MinimizeButton",
    "",
    30,
    43
)

if minimizeIcon then
    local icon = Instance.new("ImageLabel")
    icon.Name = "MinimizeIcon"
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.Size = UDim2.fromOffset(17, 17)
    icon.BackgroundTransparency = 1
    icon.Image = minimizeIcon
    icon.ImageColor3 = Colors.Text
    icon.ScaleType = Enum.ScaleType.Fit
    icon.ZIndex = 5
    icon.Parent = minimizeButton
else
    minimizeButton.Text = "−"
    minimizeButton.TextSize = 22
end

local clearButton = createHeaderButton(
    "ClearButton",
    "Clear",
    48,
    79
)

clearButton.TextSize = 12

--==================================================
-- OUTPUT AREA
--==================================================

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.new(0, 0, 0, 44)
content.Size = UDim2.new(1, 0, 1, -44)
content.BackgroundColor3 = Colors.Background
content.BorderSizePixel = 0
content.ZIndex = 1
content.Parent = window

local scrolling = Instance.new("ScrollingFrame")
scrolling.Name = "Messages"
scrolling.Position = UDim2.new(0, 8, 0, 7)
scrolling.Size = UDim2.new(1, -16, 1, -14)
scrolling.BackgroundTransparency = 1
scrolling.BorderSizePixel = 0
scrolling.ScrollBarThickness = 4
scrolling.ScrollBarImageColor3 = Colors.Border
scrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrolling.ScrollingDirection = Enum.ScrollingDirection.Y
scrolling.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scrolling.ClipsDescendants = true
scrolling.ZIndex = 1
scrolling.Parent = content

local listLayout = Instance.new("UIListLayout")
listLayout.Name = "MessageLayout"
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrolling

local listPadding = Instance.new("UIPadding")
listPadding.PaddingBottom = UDim.new(0, 25)
listPadding.PaddingRight = UDim.new(0, 3)
listPadding.Parent = scrolling

--==================================================
-- RESIZE HANDLE
--==================================================

local resizeHandle = Instance.new("ImageButton")
resizeHandle.Name = "ResizeHandle"
resizeHandle.AnchorPoint = Vector2.new(1, 1)
resizeHandle.Position = UDim2.new(1, -4, 1, -4)
resizeHandle.Size = UDim2.fromOffset(22, 22)
resizeHandle.BackgroundTransparency = 1
resizeHandle.BorderSizePixel = 0
resizeHandle.AutoButtonColor = false
resizeHandle.Image = resizeIcon or ""
resizeHandle.ImageColor3 = Colors.Muted
resizeHandle.ScaleType = Enum.ScaleType.Fit
resizeHandle.ZIndex = 10
resizeHandle.Parent = window

-- If the custom image cannot be loaded, show a simple fallback.
if not resizeIcon then
    resizeHandle.Image = ""
    resizeHandle.BackgroundTransparency = 1

    local fallback = Instance.new("TextLabel")
    fallback.Name = "ResizeFallback"
    fallback.Size = UDim2.fromScale(1, 1)
    fallback.BackgroundTransparency = 1
    fallback.Text = "◢"
    fallback.TextColor3 = Colors.Muted
    fallback.TextSize = 17
    fallback.Font = Enum.Font.Gotham
    fallback.ZIndex = 11
    fallback.Parent = resizeHandle
end

--==================================================
-- WINDOW DRAGGING
--==================================================

local dragging = false
local dragInput = nil
local dragStart = nil
local dragStartPosition = nil

local function beginDragging(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    dragging = true
    dragStart = input.Position
    dragStartPosition = window.Position

    if input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    else
        dragInput = nil
    end

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragging = false
            dragInput = nil
        end
    end)
end

header.InputBegan:Connect(beginDragging)
titleLabel.InputBegan:Connect(beginDragging)

--==================================================
-- WINDOW RESIZING
--==================================================

local resizing = false
local resizeInput = nil
local resizeStart = nil
local resizeStartSize = nil

resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    resizing = true
    resizeStart = input.Position
    resizeStartSize = window.Size

    if input.UserInputType == Enum.UserInputType.Touch then
        resizeInput = input
    else
        resizeInput = nil
    end

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            resizing = false
            resizeInput = nil
        end
    end)
end)

UserInputService.InputChanged:Connect(function(input)
    local isMouseMovement =
        input.UserInputType == Enum.UserInputType.MouseMovement

    if dragging and dragStart and dragStartPosition then
        local isActivePointer = isMouseMovement
            or (dragInput ~= nil and input == dragInput)

        if isActivePointer then
            local delta = input.Position - dragStart

            window.Position = UDim2.new(
                dragStartPosition.X.Scale,
                dragStartPosition.X.Offset + delta.X,
                dragStartPosition.Y.Scale,
                dragStartPosition.Y.Offset + delta.Y
            )
        end
    end

    if resizing and resizeStart and resizeStartSize then
        local isActivePointer = isMouseMovement
            or (resizeInput ~= nil and input == resizeInput)

        if isActivePointer then
            local delta = input.Position - resizeStart

            window.Size = UDim2.new(
                resizeStartSize.X.Scale,
                resizeStartSize.X.Offset + delta.X,
                resizeStartSize.Y.Scale,
                resizeStartSize.Y.Offset + delta.Y
            )
        end
    end
end)

--==================================================
-- MINIMIZE AND RESTORE
--==================================================

local minimized = false
local previousSize = window.Size
local previousPosition = window.Position

local function setMinimized(state)
    if minimized == state then
        return
    end

    if state then
        previousSize = window.Size
        previousPosition = window.Position

        minimized = true

        -- Collapse the entire window to a small header.
        window.Size = UDim2.fromOffset(180, 44)
        window.BackgroundColor3 = Colors.Header

        content.Visible = false
        resizeHandle.Visible = false
        windowStroke.Transparency = 0.45

        minimizeButton.Text = "□"

        local icon = minimizeButton:FindFirstChild("MinimizeIcon")
        if icon then
            icon.Visible = false
        end
    else
        minimized = false

        window.Size = previousSize
        window.Position = previousPosition
        window.BackgroundColor3 = Colors.Background

        content.Visible = true
        resizeHandle.Visible = true
        windowStroke.Transparency = 0.25

        minimizeButton.Text = ""

        local icon = minimizeButton:FindFirstChild("MinimizeIcon")
        if icon then
            icon.Visible = true
        end
    end
end

minimizeButton.Activated:Connect(function()
    setMinimized(not minimized)
end)

--==================================================
-- OUTPUT MESSAGES
--==================================================

local MAX_MESSAGES = 150
local FONT_SIZE = 14

local messageRows = {}
local messageCount = 0

local function clearMessages()
    for _, row in ipairs(messageRows) do
        if row and row.Parent then
            row:Destroy()
        end
    end

    table.clear(messageRows)
    messageCount = 0
    scrolling.CanvasPosition = Vector2.new(0, 0)
end

local function getMessageColor(messageType)
    if messageType == Enum.MessageType.MessageWarning then
        return Colors.Warning
    end

    if messageType == Enum.MessageType.MessageError then
        return Colors.Error
    end

    return Colors.Info
end

local function addMessage(message, messageType)
    if not gui.Parent then
        return
    end

    messageCount += 1

    local label = Instance.new("TextLabel")
    label.Name = "Message"
    label.Size = UDim2.new(1, -8, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.Code
    label.TextSize = FONT_SIZE
    label.TextColor3 = getMessageColor(messageType)
    label.Text = tostring(message)
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.RichText = false
    label.LayoutOrder = messageCount
    label.ZIndex = 2
    label.Parent = scrolling

    table.insert(messageRows, label)

    while #messageRows > MAX_MESSAGES do
        local oldest = table.remove(messageRows, 1)

        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end

    -- Scroll to the latest message after the layout updates.
    task.defer(function()
        if not scrolling.Parent then
            return
        end

        local canvasHeight = listLayout.AbsoluteContentSize.Y
        local viewHeight = scrolling.AbsoluteWindowSize.Y

        scrolling.CanvasPosition = Vector2.new(
            0,
            math.max(0, canvasHeight - viewHeight)
        )
    end)
end

clearButton.Activated:Connect(clearMessages)

--==================================================
-- CLOSE AND CLEANUP
--==================================================

local connections = {}

table.insert(
    connections,
    LogService.MessageOut:Connect(function(message, messageType)
        addMessage(message, messageType)
    end)
)

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

closeButton.Activated:Connect(cleanup)

--==================================================
-- DISPLAY
--==================================================

gui.Parent = CoreGui
