WowPopup = {}

local root
local inventoryUi
local minimapUi
local boundWidget
local inventoryPrepared = false
local containerEventsConnected = false

local function chatIsActive()
    local console = modules.game_console
    return console and console.isChatEnabled and console.isChatEnabled()
end

local function canHandleGameKey()
    return g_game.isOnline() and not chatIsActive()
end

local function rootGeometry()
    root = root or (modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel())
    if not root then
        return nil
    end

    local pos = root:getPosition()
    local size = root:getSize()

    return {
        x = pos and pos.x or 0,
        y = pos and pos.y or 0,
        width = size and size.width or 0,
        height = size and size.height or 0
    }
end

local function prepareInventory()
    local inventory = modules.game_inventory
    if not inventory or not inventory.inventoryController or not inventory.inventoryController.ui then
        return false
    end

    inventoryUi = inventory.inventoryController.ui
    root = modules.game_interface.getRootPanel()

    if not inventoryUi or not root then
        return false
    end

    if inventoryUi:getParent() ~= root then
        inventoryUi:setParent(root)
    end

    inventoryUi:breakAnchors()
    inventoryUi.moveOnlyToMain = false
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#42546d')

    local geometry = rootGeometry()
    if geometry then
        inventoryUi:setPosition({
            x = geometry.x + 28,
            y = geometry.y + 145
        })
    end

    if not inventoryPrepared then
        inventoryUi:hide()
        inventoryPrepared = true
    end

    return true
end

local function positionMinimap()
    local mapModule = modules.game_minimap
    if not mapModule or not mapModule.mapController or not mapModule.mapController.ui then
        return false
    end

    minimapUi = mapModule.mapController.ui
    root = modules.game_interface.getRootPanel()

    if not minimapUi or not root then
        return false
    end

    if minimapUi:getParent() ~= root then
        minimapUi:setParent(root)
    end

    minimapUi:breakAnchors()
    minimapUi.moveOnlyToMain = false
    minimapUi:setBorderWidth(1)
    minimapUi:setBorderColor('#42546d')

    local geometry = rootGeometry()
    local mapSize = minimapUi:getSize()

    if geometry and mapSize then
        minimapUi:setPosition({
            x = geometry.x + math.max(16, geometry.width - mapSize.width - 24),
            y = geometry.y + 24
        })
    end

    minimapUi:show()
    minimapUi:raise()
    return true
end

local function toggleInventory()
    if not canHandleGameKey() then
        return false
    end

    if not prepareInventory() then
        return false
    end

    if inventoryUi:isVisible() then
        inventoryUi:hide()
    else
        prepareInventory()
        inventoryUi:show()
        inventoryUi:raise()
    end

    return true
end

local function positionsEqual(a, b)
    if not a or not b then
        return false
    end
    return a.x == b.x and a.y == b.y and a.z == b.z
end

local function isBackpackContainer(container, backpack)
    if not container or not backpack then
        return false
    end

    local containerItem = container:getContainerItem()
    if not containerItem then
        return false
    end

    if containerItem == backpack then
        return true
    end

    if containerItem:getId() ~= backpack:getId() then
        return false
    end

    local samePosition = false
    pcall(function()
        samePosition = positionsEqual(containerItem:getPosition(), backpack:getPosition())
    end)

    if samePosition then
        return true
    end

    return not container:hasParent()
end

local function findOpenBackpack(backpack)
    for _, container in pairs(g_game.getContainers()) do
        if isBackpackContainer(container, backpack) then
            return container
        end
    end
    return nil
end

local function positionContainerWindow(container)
    if not container or not container.window then
        return
    end

    root = modules.game_interface.getRootPanel()
    if not root then
        return
    end

    local window = container.window

    if window:getParent() ~= root then
        window:setParent(root)
    end

    window:breakAnchors()
    window:setBorderWidth(1)
    window:setBorderColor('#42546d')

    local geometry = rootGeometry()
    local windowSize = window:getSize()

    if geometry and windowSize then
        local cascade = 0
        for _, candidate in pairs(g_game.getContainers()) do
            if candidate ~= container and candidate.window and candidate.window:getParent() == root then
                cascade = cascade + 1
            end
        end

        cascade = math.min(cascade, 5)

        window:setPosition({
            x = geometry.x + math.max(16, geometry.width - windowSize.width - 28 - cascade * 18),
            y = geometry.y + math.max(80, geometry.height - windowSize.height - 32 - cascade * 18)
        })
    end

    window:show()
    window:raise()
end

local function onContainerOpen(container)
    scheduleEvent(function()
        positionContainerWindow(container)
    end, 80)
end

local function toggleBackpack()
    if not canHandleGameKey() then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end

    local backpack = player:getInventoryItem(InventorySlotBack)
    if not backpack then
        return true
    end

    local openContainer = findOpenBackpack(backpack)
    if openContainer then
        g_game.close(openContainer)
        return true
    end

    g_game.use(backpack)
    return true
end

local function bindKeys()
    if boundWidget then
        return
    end

    root = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if not root then
        return
    end

    boundWidget = root

    -- I = Character/Equipment.
    -- C intentionally remains diagonal south-east movement.
    g_keyboard.bindKeyDown('I', toggleInventory, boundWidget)
    g_keyboard.bindKeyDown('B', toggleBackpack, boundWidget)
end

local function unbindKeys()
    if not boundWidget then
        return
    end

    g_keyboard.unbindKeyDown('I', toggleInventory, boundWidget)
    g_keyboard.unbindKeyDown('B', toggleBackpack, boundWidget)
    boundWidget = nil
end

local function connectContainerEvents()
    if containerEventsConnected then
        return
    end

    connect(Container, {
        onOpen = onContainerOpen
    })

    containerEventsConnected = true
end

local function disconnectContainerEvents()
    if not containerEventsConnected then
        return
    end

    disconnect(Container, {
        onOpen = onContainerOpen
    })

    containerEventsConnected = false
end

local function setupFloatingUi()
    bindKeys()
    prepareInventory()
    positionMinimap()
    connectContainerEvents()

    for _, container in pairs(g_game.getContainers()) do
        scheduleEvent(function()
            positionContainerWindow(container)
        end, 100)
    end
end

local function onGameStart()
    scheduleEvent(setupFloatingUi, 250)
    scheduleEvent(positionMinimap, 700)
end

local function onGameEnd()
    if inventoryUi then
        inventoryUi:hide()
    end
end

function WowPopup.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    scheduleEvent(setupFloatingUi, 500)

    if g_game.isOnline() then
        onGameStart()
    end
end

function WowPopup.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    unbindKeys()
    disconnectContainerEvents()

    inventoryUi = nil
    minimapUi = nil
    root = nil
end
