FibulaBagPolish = {}

local DEFAULT_COLUMNS = 4
local CELL_SIZE = 34
local CELL_SPACING = 3

local function safeHide(parent, id)
    if not parent then
        return
    end

    local widget = parent:recursiveGetChildById(id)
    if widget then
        widget:hide()
    end
end

local function isBagLikeContainer(container)
    if not container then
        return false
    end

    local item = container:getContainerItem()
    if not item then
        return false
    end

    -- Leave corpse windows alone. This module is only visual polish for
    -- backpacks/bags/normal containers.
    if item:isLyingCorpse() then
        return false
    end

    return item:isContainer()
end

local function calculateGeometry(container)
    local capacity = math.max(1, tonumber(container:getCapacity()) or 1)
    local columns = math.min(DEFAULT_COLUMNS, capacity)
    local rows = math.max(1, math.ceil(capacity / columns))

    local gridWidth =
        columns * CELL_SIZE +
        math.max(0, columns - 1) * CELL_SPACING

    local gridHeight =
        rows * CELL_SIZE +
        math.max(0, rows - 1) * CELL_SPACING

    -- contentsPanel already has 6px internal padding on all sides in the
    -- standard ContainerWindow style. Give it another 5px outer margin.
    -- This makes left/right and top/bottom breathing room visually equal.
    local windowWidth = math.max(169, gridWidth + 22)
    local windowHeight = gridHeight + 39

    return {
        columns = columns,
        rows = rows,
        gridWidth = gridWidth,
        gridHeight = gridHeight,
        windowWidth = windowWidth,
        windowHeight = windowHeight
    }
end

local function polishCapacityLabel(window)
    if not window then
        return
    end

    local cap = window:recursiveGetChildById('fibulaCapacityLabel')
    if not cap then
        return
    end

    cap:breakAnchors()
    cap:addAnchor(AnchorTop, 'parent', AnchorTop)
    cap:addAnchor(AnchorRight, 'parent', AnchorRight)
    cap:setMarginTop(2)
    cap:setMarginRight(20)
    cap:setSize({ width = 62, height = 14 })
    cap:setTextAlign(AlignCenter)
    cap:setColor('#f1d58b')
    cap:setFont('verdana-11px-rounded')
    cap:show()
    cap:raise()
end

local function polishTitle(window)
    if not window then
        return
    end

    local title = window:recursiveGetChildById('miniwindowTitle')
    if title then
        title:breakAnchors()
        title:addAnchor(AnchorTop, 'parent', AnchorTop)
        title:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        title:addAnchor(AnchorRight, 'parent', AnchorRight)
        title:setMarginTop(2)
        title:setMarginLeft(20)
        title:setMarginRight(84)
        title:setHeight(14)
        title:setColor('#d8d8d8')
        title:setFont('verdana-11px-rounded')
        title:show()
        title:raise()
    end

    local close = window:recursiveGetChildById('closeButton')
    if close then
        close:breakAnchors()
        close:addAnchor(AnchorTop, 'parent', AnchorTop)
        close:addAnchor(AnchorRight, 'parent', AnchorRight)
        close:setMarginTop(2)
        close:setMarginRight(3)
        close:setSize({ width = 12, height = 12 })
        close:show()
        close:raise()
    end
end

local function polishContents(container, geometry)
    local window = container.window
    local contents = container.itemsPanel or
        (window and window:recursiveGetChildById('contentsPanel'))

    if not window or not contents then
        return
    end

    local scrollbar = window:recursiveGetChildById('miniwindowScrollBar')
    if scrollbar then
        scrollbar:setOn(false)
        scrollbar:hide()
    end

    -- Remove the inherited right-side scrollbar reservation and make the
    -- content area symmetrical inside the window.
    contents:breakAnchors()
    contents:addAnchor(AnchorTop, 'parent', AnchorTop)
    contents:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    contents:addAnchor(AnchorRight, 'parent', AnchorRight)
    contents:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    contents:setMarginTop(20)
    contents:setMarginLeft(5)
    contents:setMarginRight(5)
    contents:setMarginBottom(5)

    -- Do not let this ScrollablePanel force a visual scrollbar back on.
    contents:setOn(false)
    contents:show()

    window:setWidth(geometry.windowWidth)
    window:setHeight(geometry.windowHeight)
    window:setContentMinimumHeight(geometry.gridHeight)
    window:setContentMaximumHeight(geometry.gridHeight + 12)
end

function FibulaBagPolish.polish(container)
    if not isBagLikeContainer(container) or not container.window then
        return
    end

    local window = container.window
    local geometry = calculateGeometry(container)

    -- Keep only the actual close button. Separate bag windows make the
    -- inherited parent/up, lock, minimize, filter and "new window" controls
    -- unnecessary clutter.
    for _, id in ipairs({
        'minimizeButton',
        'lockButton',
        'toggleFilterButton',
        'contextMenuButton',
        'newWindowButton',
        'upButton',
        'bottomResizeBorder',
        'miniborder',
        'separator'
    }) do
        safeHide(window, id)
    end

    local pagePanel = window:recursiveGetChildById('pagePanel')
    if pagePanel and not container:hasPages() then
        pagePanel:hide()
    end

    polishTitle(window)
    polishContents(container, geometry)
    polishCapacityLabel(window)

    window:setBackgroundColor('#071019f2')
    window:setBorderWidth(1)
    window:setBorderColor('#42566f')

    window:show()
    window:raise()
end

local function delayedPolish(container)
    -- game_containers finishes building and sizing the window in its own
    -- Container.onOpen callback. Re-apply after that work has settled.
    scheduleEvent(function()
        if container and container.window then
            FibulaBagPolish.polish(container)
        end
    end, 1)

    scheduleEvent(function()
        if container and container.window then
            FibulaBagPolish.polish(container)
        end
    end, 80)
end

local function onContainerOpen(container)
    delayedPolish(container)
end

local function onContainerSizeChange(container)
    delayedPolish(container)
end

local function onContainerUpdateItem(container)
    -- Item count changes can cause the stock module to revisit layout/scroll.
    -- Keep the clean container geometry stable.
    scheduleEvent(function()
        if container and container.window then
            FibulaBagPolish.polish(container)
        end
    end, 20)
end

local function refreshAll()
    for _, container in pairs(g_game.getContainers()) do
        delayedPolish(container)
    end
end

local function onGameStart()
    scheduleEvent(refreshAll, 150)
    scheduleEvent(refreshAll, 700)
end

function FibulaBagPolish.init()
    connect(Container, {
        onOpen = onContainerOpen,
        onSizeChange = onContainerSizeChange,
        onUpdateItem = onContainerUpdateItem
    })

    connect(g_game, {
        onGameStart = onGameStart
    })

    if g_game.isOnline() then
        onGameStart()
    end
end

function FibulaBagPolish.terminate()
    disconnect(Container, {
        onOpen = onContainerOpen,
        onSizeChange = onContainerSizeChange,
        onUpdateItem = onContainerUpdateItem
    })

    disconnect(g_game, {
        onGameStart = onGameStart
    })
end
