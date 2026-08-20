WowPopup = {}

local root
local inventoryUi
local minimapUi
local utilityDock
local boundWidget
local inventoryPrepared = false

local character = {
    name = nil,
    stats = nil,
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
        character.name:setText(player:getName() or 'Character')
    end

    if character.preview then
        character.preview:setCreature(player)
    end

    if character.stats then
        character.stats:setText(string.format(
            'Lv %d     Cap %s     Soul %s',
            player:getLevel() or 0,
            tostring(player:getFreeCapacity() or 0),
            tostring(player:getSoul() or 0)
        ))
    end
end

local function buildCharacterLayout()
    if not inventoryUi or not inventoryUi.onPanel then
        return false
    end

    local panel = inventoryUi.onPanel

    inventoryUi:setWidth(402)
    inventoryUi:setHeight(246)
    inventoryUi:setImageSource('')
    inventoryUi:setBackgroundColor('#071019f0')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#607a98')
    inventoryUi.moveOnlyToMain = false

    panel:setImageSource('')
    panel:setBackgroundColor('#071019e8')

    -- Remove every decorative widget created by previous experimental passes.
    for _, id in ipairs({
        'wowHeaderPanel', 'wowBodyLeft', 'wowBodyCenter', 'wowBodyRight',
        'wowFooter', 'wowCharacterBody', 'wowCharacterFooter',
        'wowCharacterPreviewFrame',
        'wowCharacterHp', 'wowCharacterMana', 'wowCharacterXp',
        'wowCharacterLevel', 'wowCharacterCap', 'wowCharacterSoul',
        'wowCombatLabel', 'wowMoveLabel', 'wowModesLabel',
        'wowCharacterStats'
    }) do
        destroyChild(panel, id)
    end

    -- Character in WoW is equipment + identity. Combat stance controls do not
    -- belong in this window, so keep them out of the way entirely.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel',
        'attack', 'balanced', 'defense',
        'standPosture', 'followPosture', 'pvp', 'stop'
    }) do
        hideChild(panel, id)
    end

    character.name = createLabel(panel, 'wowCharacterName',
        'Character', 18, 10, 150, 16, '#f1d58b')

    character.stats = createLabel(panel, 'wowCharacterStats',
        '', 176, 10, 188, 16, '#b8c3d0')

    -- Player preview in the middle with no opaque background block.
    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end

    character.preview:breakAnchors()
    character.preview:setPosition({ x = 148, y = 54 })
    character.preview:setSize({ width = 106, height = 118 })
    character.preview:setBackgroundColor('#00000000')
    character.preview:setBorderWidth(0)
    character.preview:setPhantom(true)
    character.preview:show()
    character.preview:raise()

    -- Equipment slots remain children of inventoryController.ui.onPanel.
    -- This is important because the native inventory update code addresses
    -- them through ui.helmet/ui.amulet/etc.
    moveChild(panel, 'helmet',   184, 38)

    moveChild(panel, 'amulet',    44, 50)
    moveChild(panel, 'sword',     44, 96)
    moveChild(panel, 'ring',      44, 142)

    moveChild(panel, 'backpack', 324, 50)
    moveChild(panel, 'shield',   324, 96)
    moveChild(panel, 'tools',    324, 142)

    moveChild(panel, 'armor',     98, 72)
    moveChild(panel, 'legs',      98, 118)
    moveChild(panel, 'boots',    184, 174)

    createLabel(panel, 'wowLeftEquipmentLabel', 'EQUIPMENT',
        18, 208, 120, 16, '#71839a')
    createLabel(panel, 'wowRightEquipmentLabel', 'INVENTORY',
        292, 208, 92, 16, '#71839a')

    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end

    character.close:setText('X')
    character.close:breakAnchors()
    character.close:setPosition({ x = 372, y = 7 })
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

local function collectChildren(parent, output)
    if not parent then return end
    local children = parent:getChildren() or {}
    for _, child in ipairs(children) do
        table.insert(output, child)
    end
end

local function ensureUtilityDock()
    local r = getRoot()
    local rsize = rootSize()
    local mainPanel = modules.game_mainpanel

    if not r or not rsize or not mainPanel or
       not mainPanel.optionsController or not mainPanel.optionsController.ui then
        return false
    end

    local optionsUi = mainPanel.optionsController.ui

    if not utilityDock or utilityDock:isDestroyed() then
        utilityDock = g_ui.createWidget('Panel', r)
        utilityDock:setId('wowUtilityDock')
    end

    utilityDock:breakAnchors()
    utilityDock:setImageSource('')
    utilityDock:setBackgroundColor('#071019dc')
    utilityDock:setBorderWidth(1)
    utilityDock:setBorderColor('#526782')

    -- Move the actual existing option buttons, not the empty wrapper window.
    -- Their native callbacks/tooltips remain attached to the button objects.
    local incoming = {}

    if optionsUi.onPanel then
        collectChildren(optionsUi.onPanel.options, incoming)
        collectChildren(optionsUi.onPanel.specials, incoming)
    end

    for _, button in ipairs(incoming) do
        if button and button:getId() ~= 'resizer' and button:isVisible() then
            button:setParent(utilityDock)
        end
    end

    -- Add an explicit logout button. The original top-menu logout remains
    -- hidden, while this one calls the same public game_interface function.
    local logout = utilityDock:getChildById('wowLogoutButton')
    if not logout then
        logout = g_ui.createWidget('UIButton', utilityDock)
        logout:setId('wowLogoutButton')
        logout:setText('Exit')
        logout:setTooltip('Logout')
        logout.onClick = function()
            if modules.game_interface and modules.game_interface.tryLogout then
                modules.game_interface.tryLogout(false)
            end
        end
    end
    logout:setSize({ width = 38, height = 20 })
    logout:setBackgroundColor('#101925d8')
    logout:setBorderWidth(1)
    logout:setBorderColor('#536986')
    logout:show()

    local topLogout = modules.client_topmenu and modules.client_topmenu.getButton and
        modules.client_topmenu.getButton('logoutButton') or nil
    if topLogout then
        topLogout:hide()
    end

    optionsUi:hide()

    local buttons = {}
    for _, child in ipairs(utilityDock:getChildren() or {}) do
        if child:isVisible() then
            table.insert(buttons, child)
        end
    end

    local columns = 6
    local cell = 24
    local rows = math.max(1, math.ceil(#buttons / columns))
    local width = columns * cell + 12
    local height = rows * cell + 12

    utilityDock:setSize({ width = width, height = height })

    for index, button in ipairs(buttons) do
        local i = index - 1
        local col = i % columns
        local row = math.floor(i / columns)

        button:breakAnchors()
        button:setPosition({
            x = 6 + col * cell,
            y = 6 + row * cell
        })

        if button:getId() ~= 'wowLogoutButton' then
            button:setSize({ width = 20, height = 20 })
        end

        button:show()
    end

    utilityDock:setPosition({
        x = math.max(16, rsize.width - width - 24),
        y = math.max(16, rsize.height - height - 24)
    })

    utilityDock:show()
    utilityDock:raise()
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
    ensureUtilityDock()
end

local function onGameStart()
    scheduleEvent(refreshLayout, 150)
    scheduleEvent(refreshLayout, 500)
    scheduleEvent(refreshLayout, 1200)
end

local function onGameEnd()
    if inventoryUi then
        inventoryUi:hide()
    end
    if utilityDock then
        utilityDock:hide()
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

    scheduleEvent(refreshLayout, 500)

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

    if utilityDock and not utilityDock:isDestroyed() then
        utilityDock:destroy()
    end

    inventoryUi = nil
    minimapUi = nil
    utilityDock = nil
    root = nil
end
