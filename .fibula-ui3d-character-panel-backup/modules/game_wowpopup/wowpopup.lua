WowPopup = {}

local root
local inventoryUi
local minimapUi
local boundWidget
local inventoryPrepared = false

local function chatIsActive()
    local console = modules.game_console
    return console and console.isChatEnabled and console.isChatEnabled()
end

local function canHandleGameKey()
    return g_game.isOnline() and not chatIsActive()
end

local function getRoot()
    root = modules.game_interface and modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil
    return root
end

local function rootSize()
    local r = getRoot()
    if not r then
        return nil
    end
    return r:getSize()
end

local function prepareInventory(forceVisible)
    local inventory = modules.game_inventory
    if not inventory or not inventory.inventoryController or not inventory.inventoryController.ui then
        return false
    end

    inventoryUi = inventory.inventoryController.ui
    local r = getRoot()

    if not inventoryUi or not r then
        return false
    end

    if inventoryUi:getParent() ~= r then
        inventoryUi:setParent(r)
    end

    inventoryUi:breakAnchors()
    inventoryUi.moveOnlyToMain = false
    inventoryUi:setWidth(196)
    inventoryUi:setHeight(162)
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#536986')
    inventoryUi:setBackgroundColor('#080d14e0')

    if inventoryUi.onPanel then
        inventoryUi.onPanel:setBackgroundColor('#080d14d0')
    end

    if inventoryUi.onPanel then
        inventoryUi:setOn(true)
        inventoryUi.onPanel:show()
        if inventoryUi.offPanel then
            inventoryUi.offPanel:hide()
        end
    end

    inventoryUi:setPosition({ x = 24, y = 145 })

    if forceVisible then
        inventoryUi:show()
        inventoryUi:raise()
    elseif not inventoryPrepared then
        inventoryUi:hide()
    end

    inventoryPrepared = true
    return true
end

local function positionMinimap()
    local mapModule = modules.game_minimap
    if not mapModule or not mapModule.mapController or not mapModule.mapController.ui then
        return false
    end

    minimapUi = mapModule.mapController.ui
    local r = getRoot()
    local rsize = rootSize()

    if not minimapUi or not r or not rsize then
        return false
    end

    if minimapUi:getParent() ~= r then
        minimapUi:setParent(r)
    end

    minimapUi:breakAnchors()
    minimapUi.moveOnlyToMain = false
    minimapUi:setWidth(178)
    minimapUi:setHeight(132)
    minimapUi:setBorderWidth(1)
    minimapUi:setBorderColor('#607a9a')
    minimapUi:setBackgroundColor('#080d14d8')

    -- Keep the floating minimap left of the existing top-right option buttons.
    local optionsReserve = 208
    minimapUi:setPosition({
        x = math.max(16, rsize.width - 178 - optionsReserve),
        y = 34
    })

    minimapUi:show()
    minimapUi:raise()
    return true
end

local function toggleInventory()
    if not canHandleGameKey() then
        return false
    end

    if not prepareInventory(false) then
        return false
    end

    if inventoryUi:isVisible() then
        inventoryUi:hide()
    else
        prepareInventory(true)
    end

    return true
end

local function positionsEqual(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
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

    boundWidget = getRoot()
    if not boundWidget then
        return
    end

    g_keyboard.bindKeyDown('I', toggleInventory, boundWidget, true)
    g_keyboard.bindKeyDown('B', toggleBackpack, boundWidget, true)
end

local function unbindKeys()
    if not boundWidget then
        return
    end

    g_keyboard.unbindKeyDown('I', toggleInventory, boundWidget)
    g_keyboard.unbindKeyDown('B', toggleBackpack, boundWidget)
    boundWidget = nil
end

local function setupFloatingUi()
    bindKeys()
    prepareInventory(false)
    positionMinimap()
end

local function onGameStart()
    scheduleEvent(setupFloatingUi, 200)
    scheduleEvent(positionMinimap, 600)
    scheduleEvent(positionMinimap, 1200)
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

    inventoryUi = nil
    minimapUi = nil
    root = nil
end
