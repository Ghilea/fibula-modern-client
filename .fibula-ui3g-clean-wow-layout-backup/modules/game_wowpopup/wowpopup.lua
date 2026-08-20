WowPopup = {}

local root
local inventoryUi
local minimapUi
local boundWidget
local inventoryPrepared = false

local character = {
    name = nil,
    preview = nil,
    stats = nil,
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

local function createPanel(parent, id, x, y, width, height, bg, border)
    local widget = parent:getChildById(id)
    if not widget then
        widget = g_ui.createWidget('Panel', parent)
        widget:setId(id)
    end

    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = width, height = height })
    widget:setBackgroundColor(bg)

    if border then
        widget:setBorderWidth(1)
        widget:setBorderColor(border)
    end

    widget:show()
    widget:lower()
    return widget
end

local function createLabel(parent, id, text, x, y, width, height, color)
    local widget = parent:getChildById(id)
    if not widget then
        widget = g_ui.createWidget('Label', parent)
        widget:setId(id)
    end

    widget:setText(text or '')
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
            'Level %d     Capacity %s     Soul %s',
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

    inventoryUi:setWidth(454)
    inventoryUi:setHeight(286)
    inventoryUi:setBackgroundColor('#071019f2')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#617a98')
    inventoryUi.moveOnlyToMain = false

    panel:setBackgroundColor('#071019e8')

    -- Remove decorative widgets created by earlier passes so they cannot sit
    -- above the native equipment slots.
    for _, id in ipairs({
        'wowHeaderPanel', 'wowBodyLeft', 'wowBodyCenter', 'wowBodyRight',
        'wowFooter', 'wowCharacterPreviewFrame',
        'wowCharacterHp', 'wowCharacterMana', 'wowCharacterXp',
        'wowCharacterLevel', 'wowCharacterCap', 'wowCharacterSoul',
        'wowCombatLabel', 'wowMoveLabel', 'wowModesLabel'
    }) do
        destroyChild(panel, id)
    end

    -- Hide compact Tibia-only chrome that is duplicated in the new layout.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel'
    }) do
        hideChild(panel, id)
    end

    -- Simple dark-fantasy layering. These panels are always sent behind all
    -- native slots so equipment never disappears underneath styling.
    createPanel(panel, 'wowCharacterBody', 12, 38, 430, 170, '#050a1194', '#38495f')
    createPanel(panel, 'wowCharacterPreviewFrame', 162, 48, 130, 150, '#02060b78', '#536a86')
    createPanel(panel, 'wowCharacterFooter', 12, 218, 430, 52, '#0b141ed8', '#38495f')

    createLabel(panel, 'wowCharacterTitle', 'CHARACTER', 18, 10, 102, 16, '#efd283')
    character.name = createLabel(panel, 'wowCharacterName', 'Character', 130, 10, 120, 16, '#f3df9f')
    character.stats = createLabel(panel, 'wowCharacterStats', '', 254, 10, 174, 16, '#b7c1cf')

    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end
    character.preview:breakAnchors()
    character.preview:setPosition({ x = 173, y = 58 })
    character.preview:setSize({ width = 108, height = 126 })
    character.preview:setBackgroundColor('#00000000')
    character.preview:setPhantom(true)
    character.preview:show()
    character.preview:raise()

    -- Native equipment slots around the character preview.
    moveChild(panel, 'helmet',    210, 40)

    moveChild(panel, 'amulet',     58, 58)
    moveChild(panel, 'sword',      58, 104)
    moveChild(panel, 'ring',       58, 150)

    moveChild(panel, 'backpack',  362, 58)
    moveChild(panel, 'shield',    362, 104)
    moveChild(panel, 'tools',     362, 150)

    moveChild(panel, 'armor',     118, 80)
    moveChild(panel, 'legs',      118, 126)
    moveChild(panel, 'boots',     210, 174)

    -- Native combat / movement controls in one clean footer.
    createLabel(panel, 'wowCombatLabel', 'Combat', 22, 235, 44, 16, '#8f9db0')
    createLabel(panel, 'wowMoveLabel', 'Move', 170, 235, 38, 16, '#8f9db0')
    createLabel(panel, 'wowModesLabel', 'Mode', 278, 235, 38, 16, '#8f9db0')

    moveChild(panel, 'attack',         68, 230)
    moveChild(panel, 'balanced',       92, 230)
    moveChild(panel, 'defense',       116, 230)

    moveChild(panel, 'standPosture',  208, 230)
    moveChild(panel, 'followPosture', 232, 230)

    moveChild(panel, 'pvp',           320, 229)
    moveChild(panel, 'stop',          380, 233)

    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end

    character.close:setText('X')
    character.close:setPosition({ x = 426, y = 7 })
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
    inventoryUi:setPosition({ x = 24, y = 138 })

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
    minimapUi:setBackgroundColor('#071019dc')
    minimapUi:setBorderWidth(1)
    minimapUi:setBorderColor('#607a9a')

    -- Same 24px outer margin concept as the player frame on the left.
    minimapUi:setPosition({
        x = math.max(16, rsize.width - 148 - 24),
        y = 24
    })

    minimapUi:show()
    minimapUi:raise()
    return true
end

local function positionOptionsPanel()
    local mainPanel = modules.game_mainpanel
    if not mainPanel or not mainPanel.optionsController or not mainPanel.optionsController.ui then
        return false
    end

    local optionsUi = mainPanel.optionsController.ui
    local r = getRoot()
    local rsize = rootSize()

    if not optionsUi or not r or not rsize then
        return false
    end

    if optionsUi:getParent() ~= r then
        optionsUi:setParent(r)
    end

    optionsUi:breakAnchors()
    optionsUi.moveOnlyToMain = false
    optionsUi:setOn(true)
    optionsUi:setWidth(170)
    optionsUi:setHeight(76)
    optionsUi:setBackgroundColor('#071019cc')
    optionsUi:setBorderWidth(1)
    optionsUi:setBorderColor('#526782')

    if optionsUi.offPanel then
        optionsUi.offPanel:hide()
    end

    local onPanel = optionsUi.onPanel
    if onPanel then
        onPanel:show()

        if onPanel.store then
            onPanel.store:hide()
        end

        local resizer = onPanel:getChildById('resizer')
        if resizer then
            resizer:hide()
        end

        if onPanel.options then
            onPanel.options:breakAnchors()
            onPanel.options:setPosition({ x = 8, y = 8 })
            onPanel.options:setSize({ width = 108, height = 58 })
        end

        if onPanel.specials then
            onPanel.specials:breakAnchors()
            onPanel.specials:setPosition({ x = 120, y = 8 })
            onPanel.specials:setSize({ width = 44, height = 58 })
        end
    end

    optionsUi:setPosition({
        x = math.max(16, rsize.width - 170 - 24),
        y = math.max(16, rsize.height - 76 - 24)
    })

    optionsUi:show()
    optionsUi:raise()
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
    positionOptionsPanel()
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

    inventoryUi = nil
    minimapUi = nil
    root = nil
end
