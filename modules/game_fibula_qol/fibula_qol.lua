FibulaQol = {}

local originalProcessMouseAction
local hookedProcessMouseAction

local magicBar
local playerFrame
local experienceBar

local function getGameRoot()
    local interface = modules.game_interface
    return interface and interface.getRootPanel and interface.getRootPanel() or nil
end

local function hideCharacterCapacity()
    local inventory = modules.game_inventory
    if not inventory or not inventory.inventoryController then
        return
    end

    local ui = inventory.inventoryController.ui
    if not ui then
        return
    end

    local capacity = ui:recursiveGetChildById('capacityPanel')
    if capacity then
        capacity:hide()
    end
end

local function getEquippedBackpack()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local backpack = player:getInventoryItem(InventorySlotBack)
    if backpack and backpack:isContainer() then
        return backpack
    end

    return nil
end

local function isEquippedBackpackContainer(container)
    if not container or container:hasParent() then
        return false
    end

    local backpack = getEquippedBackpack()
    if not backpack then
        return false
    end

    local containerItem = container:getContainerItem()
    if not containerItem then
        return false
    end

    return containerItem:getId() == backpack:getId()
end

local function updateCapacityLabel(container)
    if not container or not container.window or not isEquippedBackpackContainer(container) then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local window = container.window
    local topBar = window:recursiveGetChildById('miniwindowTopBar')
    if not topBar then
        return
    end

    local label = topBar:getChildById('fibulaCapacityLabel')
    if not label then
        label = g_ui.createWidget('Label', topBar)
        label:setId('fibulaCapacityLabel')
        label:setColor('#f1d58b')
        label:setFont('verdana-11px-rounded')
        label:setTextAlign(AlignCenter)
        label:setPhantom(true)

        label:breakAnchors()
        label:addAnchor(AnchorRight, 'parent', AnchorRight)
        label:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        label:setMarginRight(48)
        label:setSize({ width = 74, height = 16 })
    end

    local cap = tonumber(player:getFreeCapacity()) or 0

    if math.floor(cap) == cap then
        label:setText(string.format('Cap %d', cap))
    else
        label:setText(string.format('Cap %.1f', cap))
    end

    label:show()
    label:raise()
end

local function refreshCapacityLabels()
    for _, container in pairs(g_game.getContainers()) do
        if isEquippedBackpackContainer(container) then
            updateCapacityLabel(container)
        end
    end
end

local function onContainerOpen(container)
    -- game_containers creates/attaches the MiniWindow during its own onOpen
    -- callback. Run once immediately after this event and once after layout.
    scheduleEvent(function()
        updateCapacityLabel(container)
    end, 1)

    scheduleEvent(function()
        updateCapacityLabel(container)
    end, 80)
end

local function onFreeCapacityChange()
    refreshCapacityLabels()
end

local function isNestedManualContainer(thing)
    if not thing or not thing:isItem() or not thing:isContainer() then
        return false
    end

    return thing:getParentContainer() ~= nil
end

local function installContainerWindowHook()
    local interface = modules.game_interface
    if not interface or not interface.processMouseAction or originalProcessMouseAction then
        return
    end

    originalProcessMouseAction = interface.processMouseAction

    hookedProcessMouseAction = function(
        menuPosition,
        mouseButton,
        autoWalkPos,
        lookThing,
        useThing,
        creatureThing,
        attackCreature
    )
        -- Manual nested bag opening:
        --
        -- Stock OTClient normally calls:
        --   g_game.open(useThing, useThing:getParentContainer())
        -- which explicitly reuses the parent container id/window.
        --
        -- Calling g_game.open(useThing) without a previous container asks
        -- Game::open() for a free container id, so the backpack stays open
        -- and the nested bag receives its own ContainerWindow.
        --
        -- AutoLoot is unaffected because its recursive traversal calls
        -- g_game.open(item, parentContainer) directly and does not come
        -- through this mouse-action branch.
        if mouseButton == MouseRightButton and
           g_keyboard.getModifiers() == KeyboardNoModifier and
           isNestedManualContainer(useThing) then

            g_game.open(useThing)

            g_logger.info(string.format(
                '[Fibula Bags] opened nested container %d in a new window',
                useThing:getId()
            ))

            return true
        end

        return originalProcessMouseAction(
            menuPosition,
            mouseButton,
            autoWalkPos,
            lookThing,
            useThing,
            creatureThing,
            attackCreature
        )
    end

    interface.processMouseAction = hookedProcessMouseAction
end

local function uninstallContainerWindowHook()
    local interface = modules.game_interface

    if originalProcessMouseAction and
       interface and
       interface.processMouseAction == hookedProcessMouseAction then
        interface.processMouseAction = originalProcessMouseAction
    end

    originalProcessMouseAction = nil
    hookedProcessMouseAction = nil
end

local function updateMagicBar()
    if not magicBar then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        magicBar:setPercent(0)
        magicBar:setText('ML 0   0%')
        return
    end

    local level = tonumber(player:getMagicLevel()) or 0
    local progress = tonumber(player:getMagicLevelPercent()) or 0

    progress = math.max(0, math.min(100, progress))

    magicBar:setPercent(progress)
    magicBar:setText(string.format(
        'ML %d   %.1f%%',
        level,
        progress
    ))

    magicBar:setTooltip(string.format(
        'Magic Level %d\nProgress: %.1f%%\nRemaining: %.1f%%',
        level,
        progress,
        100 - progress
    ))
end

local function buildMagicBar()
    local gameRoot = getGameRoot()
    if not gameRoot then
        return false
    end

    local wowRoot = gameRoot:recursiveGetChildById('wowHudRoot')
    if not wowRoot then
        return false
    end

    playerFrame = wowRoot:getChildById('playerFrame')
    if not playerFrame then
        return false
    end

    experienceBar = playerFrame:getChildById('playerExperience')
    if not experienceBar then
        return false
    end

    magicBar = playerFrame:getChildById('playerMagicLevel')

    if not magicBar then
        magicBar = g_ui.createWidget('UIProgressBar', playerFrame)
        magicBar:setId('playerMagicLevel')
        magicBar:setHeight(12)
        magicBar:setBackgroundColor('#9852be')
        magicBar:setBorderWidth(1)
        magicBar:setBorderColor('#050607')
        magicBar:setFont('verdana-11px-rounded')
    end

    -- Make room below the existing XP bar.
    playerFrame:setHeight(122)

    magicBar:breakAnchors()
    magicBar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    magicBar:addAnchor(AnchorRight, 'parent', AnchorRight)
    magicBar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    magicBar:setMarginLeft(0)
    magicBar:setMarginRight(0)
    magicBar:setMarginBottom(0)

    experienceBar:breakAnchors()
    experienceBar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    experienceBar:addAnchor(AnchorRight, 'parent', AnchorRight)
    experienceBar:addAnchor(AnchorBottom, 'playerMagicLevel', AnchorTop)
    experienceBar:setMarginLeft(0)
    experienceBar:setMarginRight(0)
    experienceBar:setMarginBottom(3)

    magicBar:show()
    magicBar:raise()
    experienceBar:show()
    experienceBar:raise()

    updateMagicBar()
    return true
end

local function ensureMagicBar()
    if buildMagicBar() then
        return
    end

    scheduleEvent(buildMagicBar, 150)
    scheduleEvent(buildMagicBar, 500)
    scheduleEvent(buildMagicBar, 1200)
end

local function onMagicLevelChange()
    if not magicBar then
        ensureMagicBar()
    end
    updateMagicBar()
end

local function onGameStart()
    ensureMagicBar()
    hideCharacterCapacity()

    scheduleEvent(hideCharacterCapacity, 100)
    scheduleEvent(hideCharacterCapacity, 500)
    scheduleEvent(refreshCapacityLabels, 100)
    scheduleEvent(refreshCapacityLabels, 500)
end

local function onGameEnd()
    magicBar = nil
    playerFrame = nil
    experienceBar = nil
end

function FibulaQol.init()
    hideCharacterCapacity()
    scheduleEvent(hideCharacterCapacity, 250)
    scheduleEvent(hideCharacterCapacity, 1000)

    installContainerWindowHook()

    connect(Container, {
        onOpen = onContainerOpen
    })

    connect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onMagicLevelChange = onMagicLevelChange,
        onBaseMagicLevelChange = onMagicLevelChange
    })

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ensureMagicBar()

    if g_game.isOnline() then
        onGameStart()
    end
end

function FibulaQol.terminate()
    disconnect(Container, {
        onOpen = onContainerOpen
    })

    disconnect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onMagicLevelChange = onMagicLevelChange,
        onBaseMagicLevelChange = onMagicLevelChange
    })

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    uninstallContainerWindowHook()

    if magicBar and not magicBar:isDestroyed() then
        magicBar:destroy()
    end

    magicBar = nil
    playerFrame = nil
    experienceBar = nil
end
