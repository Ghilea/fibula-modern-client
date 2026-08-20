WowPopup = {}

local root
local inventoryUi
local minimapUi
local utilityPanel
local boundWidget
local inventoryPrepared = false
local buttonsMoved = false

local character = {
    name = nil,
    preview = nil,
    close = nil
}

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
    return r and r:getSize() or nil
end

local function hideChild(parent, id)
    if not parent then return end
    local widget = parent:getChildById(id)
    if widget then widget:hide() end
end

local function destroyChild(parent, id)
    if not parent then return end
    local widget = parent:getChildById(id)
    if widget then widget:destroy() end
end

local function moveChild(parent, id, x, y)
    if not parent then return nil end
    local widget = parent:getChildById(id)
    if not widget then return nil end

    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
    widget:show()
    widget:raise()
    return widget
end

local function createLabel(parent, id, text, x, y, width, height, color)
    local widget = parent:getChildById(id)
    if not widget then
        widget = g_ui.createWidget('Label', parent)
        widget:setId(id)
    end

    widget:setText(text or '')
    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = width, height = height })

    if color then
        widget:setColor(color)
    end

    widget:show()
    widget:raise()
    return widget
end

local function updateCharacter()
    if not inventoryUi or not inventoryUi.onPanel then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if character.name then
        character.name:setText(string.format(
            '%s   Lv. %d',
            player:getName() or 'Character',
            player:getLevel() or 0
        ))
    end

    if character.preview then
        character.preview:setCreature(player)
    end
end

local function buildCharacterLayout()
    if not inventoryUi or not inventoryUi.onPanel then
        return false
    end

    local panel = inventoryUi.onPanel

    inventoryUi:setWidth(382)
    inventoryUi:setHeight(236)
    inventoryUi:setImageSource('')
    inventoryUi:setBackgroundColor('#071019f0')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#607a98')
    inventoryUi.moveOnlyToMain = false

    panel:setImageSource('')
    panel:setBackgroundColor('#071019e8')

    -- Remove all custom widgets from the earlier experimental passes.
    for _, id in ipairs({
        'wowHeaderPanel', 'wowBodyLeft', 'wowBodyCenter', 'wowBodyRight',
        'wowFooter', 'wowCharacterBody', 'wowCharacterFooter',
        'wowCharacterPreviewFrame',
        'wowCharacterHp', 'wowCharacterMana', 'wowCharacterXp',
        'wowCharacterLevel', 'wowCharacterCap', 'wowCharacterSoul',
        'wowCombatLabel', 'wowMoveLabel', 'wowModesLabel',
        'wowCharacterStats', 'wowLeftEquipmentLabel', 'wowRightEquipmentLabel',
        'wowCharacterTitle'
    }) do
        destroyChild(panel, id)
    end

    -- Keep Character focused on gear only.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel',
        'attack', 'balanced', 'defense',
        'standPosture', 'followPosture', 'pvp', 'stop'
    }) do
        hideChild(panel, id)
    end

    character.name = createLabel(
        panel,
        'wowCharacterName',
        'Character',
        18, 10, 250, 18,
        '#f1d58b'
    )

    -- The stock Creature style has /images/ui/panel_flat, which caused the
    -- large grey rectangle seen behind the player preview. Clear it explicitly.
    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end

    character.preview:breakAnchors()
    character.preview:setPosition({ x = 139, y = 52 })
    character.preview:setSize({ width = 104, height = 112 })
    character.preview:setImageSource('')
    character.preview:setBackgroundColor('#00000000')
    character.preview:setBorderWidth(0)
    character.preview:setPhantom(true)
    character.preview:show()
    character.preview:raise()

    -- Ten native inventory slots. They stay direct children of onPanel because
    -- inventory.lua updates them through ui.helmet/ui.amulet/etc.
    moveChild(panel, 'helmet',   174, 38)

    moveChild(panel, 'amulet',    42, 48)
    moveChild(panel, 'sword',     42, 94)
    moveChild(panel, 'ring',      42, 140)

    moveChild(panel, 'backpack', 304, 48)
    moveChild(panel, 'shield',   304, 94)
    moveChild(panel, 'tools',    304, 140)

    moveChild(panel, 'armor',     94, 72)
    moveChild(panel, 'legs',      94, 118)
    moveChild(panel, 'boots',    174, 168)

    createLabel(panel, 'wowGearHint',
        'Equipment', 18, 202, 100, 16, '#71839a')

    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end

    character.close:setText('X')
    character.close:breakAnchors()
    character.close:setPosition({ x = 352, y = 7 })
    character.close:setSize({ width = 18, height = 17 })
    character.close:setBackgroundColor('#101925dc')
    character.close:setBorderWidth(1)
    character.close:setBorderColor('#536986')
    character.close.onClick = function()
        inventoryUi:hide()
    end
    character.close:show()
    character.close:raise()

    updateCharacter()
    return true
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

    if inventoryUi.onPanel then
        inventoryUi:setOn(true)
        inventoryUi.onPanel:show()
        if inventoryUi.offPanel then
            inventoryUi.offPanel:hide()
        end
    end

    buildCharacterLayout()
    inventoryUi:setPosition({ x = 24, y = 136 })

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
    minimapUi:setWidth(148)
    minimapUi:setHeight(132)
    minimapUi:setImageSource('')
    minimapUi:setBackgroundColor('#071019dc')
    minimapUi:setBorderWidth(1)
    minimapUi:setBorderColor('#607a9a')
    minimapUi:setPosition({
        x = math.max(16, rsize.width - 148 - 24),
        y = 24
    })

    minimapUi:show()
    minimapUi:raise()
    return true
end

local function positionUtilityPanel()
    local r = getRoot()
    local rsize = rootSize()

    if not r or not rsize or
       not modules.game_mainpanel or
       not modules.client_topmenu then
        return false
    end

    -- Use the client's own migration path. game_mainpanel already knows every
    -- option/special button and moves them to this TopMenuButtonsPanel while
    -- preserving callbacks, tooltips, order and visibility.
    if not buttonsMoved and modules.game_mainpanel.toggleExtendedViewButtons then
        modules.game_mainpanel.toggleExtendedViewButtons(true)
        buttonsMoved = true
    end

    utilityPanel = modules.client_topmenu.getRightGameButtonsPanel and
        modules.client_topmenu.getRightGameButtonsPanel() or nil

    if not utilityPanel then
        return false
    end

    if utilityPanel:getParent() ~= r then
        utilityPanel:setParent(r)
    end

    utilityPanel:breakAnchors()
    utilityPanel:setImageSource('')
    utilityPanel:setBackgroundColor('#071019d8')
    utilityPanel:setBorderWidth(1)
    utilityPanel:setBorderColor('#526782')

    local size = utilityPanel:getSize()
    local width = math.max(60, size.width or 60)
    local height = math.max(32, size.height or 32)

    utilityPanel:setPosition({
        x = math.max(16, rsize.width - width - 24),
        y = math.max(16, rsize.height - height - 24)
    })

    utilityPanel:show()
    utilityPanel:raise()
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

local function onPlayerChanged()
    updateCharacter()
end

local function refreshLayout()
    bindKeys()
    prepareInventory(false)
    positionMinimap()
    positionUtilityPanel()
end

local function onGameStart()
    scheduleEvent(refreshLayout, 200)
    scheduleEvent(refreshLayout, 800)
    scheduleEvent(refreshLayout, 1800)
    scheduleEvent(refreshLayout, 3200)
end

local function onGameEnd()
    if inventoryUi then
        inventoryUi:hide()
    end

    if utilityPanel then
        utilityPanel:hide()
    end
end

function WowPopup.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    connect(LocalPlayer, {
        onHealthChange = onPlayerChanged,
        onManaChange = onPlayerChanged,
        onExperienceChange = onPlayerChanged,
        onLevelChange = onPlayerChanged,
        onSoulChange = onPlayerChanged,
        onFreeCapacityChange = onPlayerChanged,
        onInventoryChange = onPlayerChanged
    })

    scheduleEvent(refreshLayout, 600)

    if g_game.isOnline() then
        onGameStart()
    end
end

function WowPopup.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    disconnect(LocalPlayer, {
        onHealthChange = onPlayerChanged,
        onManaChange = onPlayerChanged,
        onExperienceChange = onPlayerChanged,
        onLevelChange = onPlayerChanged,
        onSoulChange = onPlayerChanged,
        onFreeCapacityChange = onPlayerChanged,
        onInventoryChange = onPlayerChanged
    })

    unbindKeys()

    inventoryUi = nil
    minimapUi = nil
    utilityPanel = nil
    root = nil
end
