WowPopup = {}

local root
local inventoryUi
local minimapUi
local boundWidget
local inventoryPrepared = false

local character = {
    title = nil,
    name = nil,
    preview = nil,
    level = nil,
    cap = nil,
    soul = nil,
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

local function getChildren(widget)
    if not widget or not widget.getChildren then return {} end
    return widget:getChildren() or {}
end

local function findDescendantById(widget, id)
    if not widget or not id then return nil end
    if widget.getId and widget:getId() == id then
        return widget
    end
    for _, child in ipairs(getChildren(widget)) do
        local found = findDescendantById(child, id)
        if found then return found end
    end
    return nil
end

local function findAnyDescendant(widget, ids)
    for _, id in ipairs(ids) do
        local found = findDescendantById(widget, id)
        if found then return found end
    end
    return nil
end

local function hideChild(parent, id)
    if not parent then return end
    local widget = parent:getChildById(id)
    if widget then widget:hide() end
end

local function moveChild(parent, id, x, y)
    if not parent then return nil end
    local widget = parent:getChildById(id)
    if not widget then return nil end
    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
    widget:show()
    return widget
end

local function createLabel(parent, id, text, x, y, width, height, color, font)
    local widget = parent:getChildById(id)
    if not widget then
        widget = g_ui.createWidget('Label', parent)
        widget:setId(id)
    end
    widget:setText(text or '')
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = width, height = height })
    if color then widget:setColor(color) end
    if font then widget:setFont(font) end
    widget:show()
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
    if bg then widget:setBackgroundColor(bg) end
    if border then
        widget:setBorderWidth(1)
        widget:setBorderColor(border)
    end
    widget:show()
    return widget
end

local function styleFrame(widget, bg, border)
    if not widget then return end
    widget:setBackgroundColor(bg)
    widget:setBorderWidth(1)
    widget:setBorderColor(border)
end

local function updateCharacter()
    if not inventoryUi or not inventoryUi.onPanel then return end
    local player = g_game.getLocalPlayer()
    if not player then return end

    if character.name then
        character.name:setText(player:getName() or 'Character')
    end
    if character.preview then
        character.preview:setCreature(player)
    end
    if character.level then
        character.level:setText(string.format('Level  %d', player:getLevel() or 0))
    end
    if character.cap then
        character.cap:setText(string.format('Capacity  %s', tostring(player:getFreeCapacity() or 0)))
    end
    if character.soul then
        character.soul:setText(string.format('Soul  %s', tostring(player:getSoul() or 0)))
    end
end

local function buildCharacterLayout()
    if not inventoryUi or not inventoryUi.onPanel then return false end
    local panel = inventoryUi.onPanel

    inventoryUi:setWidth(454)
    inventoryUi:setHeight(304)
    styleFrame(inventoryUi, '#08111aec', '#627b98')
    inventoryUi.moveOnlyToMain = false

    panel:setBackgroundColor('#08111ae0')

    -- Hide compact / duplicate native widgets that do not fit the new layout.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel'
    }) do
        hideChild(panel, id)
    end

    -- Decorative sections
    createPanel(panel, 'wowHeaderPanel', 0, 0, 454, 32, '#0e1622ee', '#627b98')
    createPanel(panel, 'wowBodyLeft', 16, 44, 116, 160, '#060b12a8', '#42546d')
    createPanel(panel, 'wowBodyCenter', 142, 44, 170, 160, '#060b12a8', '#42546d')
    createPanel(panel, 'wowBodyRight', 322, 44, 116, 160, '#060b12a8', '#42546d')
    createPanel(panel, 'wowFooter', 16, 228, 422, 56, '#0b121bd8', '#42546d')

    character.title = createLabel(panel, 'wowCharacterTitle', 'CHARACTER', 18, 8, 140, 16, '#f1d487')
    character.name = createLabel(panel, 'wowCharacterName', 'Character', 164, 10, 180, 16, '#f4df9b')

    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end
    character.preview:setPosition({ x = 173, y = 60 })
    character.preview:setSize({ width = 110, height = 130 })
    character.preview:setPhantom(true)

    -- Native equipment slots arranged around preview
    moveChild(panel, 'helmet',   208, 42)

    moveChild(panel, 'amulet',    56, 60)
    moveChild(panel, 'sword',     56, 106)
    moveChild(panel, 'ring',      56, 152)

    moveChild(panel, 'backpack',  364, 60)
    moveChild(panel, 'shield',    364, 106)
    moveChild(panel, 'tools',     364, 152)

    moveChild(panel, 'armor',     148, 82)
    moveChild(panel, 'legs',      148, 128)
    moveChild(panel, 'boots',     208, 182)

    character.level = createLabel(panel, 'wowCharacterLevel', 'Level', 334, 60, 92, 16, '#d7dde7')
    character.cap   = createLabel(panel, 'wowCharacterCap',   'Capacity', 334, 82, 92, 16, '#d7dde7')
    character.soul  = createLabel(panel, 'wowCharacterSoul',  'Soul', 334, 104, 92, 16, '#d7dde7')

    createLabel(panel, 'wowCombatLabel', 'Combat', 22, 244, 46, 16, '#95a3b5')
    createLabel(panel, 'wowMoveLabel', 'Move', 174, 244, 40, 16, '#95a3b5')
    createLabel(panel, 'wowModesLabel', 'Mode', 286, 244, 36, 16, '#95a3b5')

    moveChild(panel, 'attack',        72, 239)
    moveChild(panel, 'balanced',      96, 239)
    moveChild(panel, 'defense',      120, 239)

    moveChild(panel, 'standPosture',  214, 239)
    moveChild(panel, 'followPosture', 238, 239)

    moveChild(panel, 'pvp',           330, 238)
    moveChild(panel, 'stop',          380, 242)

    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end
    character.close:setText('X')
    character.close:setPosition({ x = 424, y = 7 })
    character.close:setSize({ width = 18, height = 16 })
    character.close:setBackgroundColor('#0f1823d8')
    character.close:setBorderWidth(1)
    character.close:setBorderColor('#536986')
    character.close.onClick = function()
        inventoryUi:hide()
    end

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
    if not inventoryUi or not r then return false end

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
    if not minimapUi or not r or not rsize then return false end

    if minimapUi:getParent() ~= r then
        minimapUi:setParent(r)
    end

    minimapUi:breakAnchors()
    minimapUi.moveOnlyToMain = false
    minimapUi:setWidth(148)
    minimapUi:setHeight(132)
    styleFrame(minimapUi, '#08111ad8', '#607a9a')
    minimapUi:setPosition({
        x = math.max(16, rsize.width - 148 - 24),
        y = 24
    })
    minimapUi:show()
    minimapUi:raise()
    return true
end

local function positionUtilityButtons()
    local r = getRoot()
    local rsize = rootSize()
    if not r or not rsize then return false end

    local topMenu = modules.client_topmenu and (modules.client_topmenu.topMenu or
        (modules.client_topmenu.getTopMenu and modules.client_topmenu.getTopMenu())) or nil
    if not topMenu then
        topMenu = findAnyDescendant(r, { 'topMenu', 'clientTopMenu' })
    end
    if not topMenu then return false end

    local rightPanel = findAnyDescendant(topMenu, {
        'rightButtonsPanel', 'rightGameButtonsPanel', 'topRightButtonsPanel',
        'gameButtonsPanel', 'rightPanel'
    })

    if not rightPanel then return false end

    rightPanel:breakAnchors()
    rightPanel:setPosition({
        x = math.max(16, rsize.width - rightPanel:getWidth() - 24),
        y = math.max(16, rsize.height - rightPanel:getHeight() - 22)
    })
    rightPanel:raise()
    return true
end

local function positionsEqual(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function isBackpackContainer(container, backpack)
    if not container or not backpack then return false end

    local containerItem = container:getContainerItem()
    if not containerItem then return false end
    if containerItem == backpack then return true end
    if containerItem:getId() ~= backpack:getId() then return false end

    local samePosition = false
    pcall(function()
        samePosition = positionsEqual(containerItem:getPosition(), backpack:getPosition())
    end)
    if samePosition then return true end

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
    if not canHandleGameKey() then return false end
    local player = g_game.getLocalPlayer()
    if not player then return false end

    local backpack = player:getInventoryItem(InventorySlotBack)
    if not backpack then return true end

    local openContainer = findOpenBackpack(backpack)
    if openContainer then
        g_game.close(openContainer)
        return true
    end

    g_game.use(backpack)
    return true
end

local function toggleInventory()
    if not canHandleGameKey() then return false end
    if not prepareInventory(false) then return false end

    if inventoryUi:isVisible() then
        inventoryUi:hide()
    else
        prepareInventory(true)
    end
    return true
end

local function bindKeys()
    if boundWidget then return end
    boundWidget = getRoot()
    if not boundWidget then return end

    g_keyboard.bindKeyDown('I', toggleInventory, boundWidget, true)
    g_keyboard.bindKeyDown('B', toggleBackpack, boundWidget, true)
end

local function unbindKeys()
    if not boundWidget then return end
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
    positionUtilityButtons()
    positionMinimap()
end

local function onGameStart()
    scheduleEvent(refreshLayout, 150)
    scheduleEvent(refreshLayout, 500)
    scheduleEvent(refreshLayout, 1200)
end

local function onGameEnd()
    if inventoryUi then inventoryUi:hide() end
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
