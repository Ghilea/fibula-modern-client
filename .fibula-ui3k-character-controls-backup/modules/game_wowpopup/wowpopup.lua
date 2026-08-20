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

local equipmentSlots = {
    helmet   = InventorySlotHead,
    amulet   = InventorySlotNeck,
    backpack = InventorySlotBack,
    armor    = InventorySlotBody,
    shield   = InventorySlotRight,
    sword    = InventorySlotLeft,
    legs     = InventorySlotLeg,
    boots    = InventorySlotFeet,
    ring     = InventorySlotFinger,
    tools    = InventorySlotAmmo
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

local function moveEquipment(parent, id, x, y)
    local widget = parent and parent:getChildById(id) or nil
    if not widget then
        return nil
    end

    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = 34, height = 34 })
    widget:setImageSource('/images/inventory/containerslot')
    widget:show()
    widget:raise()

    if widget.item then
        widget.item:setSize({ width = 34, height = 34 })
        widget.item:show()
    end

    return widget
end

local function ensureNativeInventoryExpanded()
    local inventory = modules.game_inventory
    if not inventory or not inventory.inventoryController or not inventory.inventoryController.ui then
        return false
    end

    inventoryUi = inventory.inventoryController.ui

    -- Important: inventory.lua owns a LOCAL inventoryShrink flag. Merely calling
    -- inventoryUi:setOn(true) does not change that flag, so inventoryEvent may
    -- keep updating offPanel (or return early) while our floating onPanel is shown.
    -- Toggle through the native public function so its internal state and setting
    -- are both put back into expanded mode.
    if g_settings.getBoolean('mainpanel_shrink_inventory') and inventory.changeInventorySize then
        inventory.changeInventorySize()
    end

    inventoryUi:setOn(true)

    if inventoryUi.onPanel then
        inventoryUi.onPanel:show()
    end

    if inventoryUi.offPanel then
        inventoryUi.offPanel:hide()
    end

    return true
end

local function syncEquipmentItems()
    if not inventoryUi or not inventoryUi.onPanel then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    -- First ask the native module to refresh its own slots. This keeps duration,
    -- charges, tier markers and its normal inventory semantics.
    if modules.game_inventory and modules.game_inventory.reloadInventory then
        modules.game_inventory.reloadInventory()
    end

    -- Then mirror the item directly as a safety net. This uses the same native
    -- MainInventoryItem/UIItem widgets, so drag/use behaviour stays attached.
    for id, slot in pairs(equipmentSlots) do
        local slotWidget = inventoryUi.onPanel:getChildById(id)

        if slotWidget then
            local item = player:getInventoryItem(slot)
            local itemWidget = slotWidget.item or slotWidget:getChildById('item')
            local placeholder = slotWidget:getChildById(id)

            if itemWidget then
                itemWidget:setItem(item)
                itemWidget:setSize({ width = 34, height = 34 })
                itemWidget:show()
                itemWidget:raise()
            end

            if placeholder then
                placeholder:setEnabled(not item)
                placeholder:show()
            end

            slotWidget:show()
            slotWidget:raise()
        end
    end
end

local function updateCharacter()
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

    syncEquipmentItems()
end

local function buildCharacterLayout()
    if not inventoryUi or not inventoryUi.onPanel then
        return false
    end

    local panel = inventoryUi.onPanel

    -- IMPORTANT:
    -- Do not manually reposition the ten native MainInventoryItem widgets.
    -- inventory.otui already has a stable 3-column equipment layout and
    -- inventory.lua addresses those exact direct children by id.
    -- Keeping their original anchors fixes missing / displaced gear slots.
    inventoryUi:setWidth(338)
    inventoryUi:setHeight(188)
    inventoryUi:setImageSource('')
    inventoryUi:setBackgroundColor('#071019f2')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#607a98')
    inventoryUi.moveOnlyToMain = false

    panel:setImageSource('')
    panel:setBackgroundColor('#071019e8')

    -- Remove every custom layout remnant from older UI passes.
    for _, id in ipairs({
        'wowHeaderPanel', 'wowBodyLeft', 'wowBodyCenter', 'wowBodyRight',
        'wowFooter', 'wowCharacterBody', 'wowCharacterFooter',
        'wowCharacterPreviewFrame', 'wowCharacterPreviewBorder',
        'wowCharacterHp', 'wowCharacterMana', 'wowCharacterXp',
        'wowCharacterLevel', 'wowCharacterCap', 'wowCharacterSoul',
        'wowCombatLabel', 'wowMoveLabel', 'wowModesLabel',
        'wowCharacterStats', 'wowLeftEquipmentLabel', 'wowRightEquipmentLabel',
        'wowCharacterTitle', 'wowGearHint', 'wowEquipmentTitle',
        'wowPreviewTitle'
    }) do
        destroyChild(panel, id)
    end

    -- Character window = equipment + player preview.
    -- Keep unrelated classic controls outside this popup.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel',
        'attack', 'balanced', 'defense',
        'standPosture', 'followPosture', 'pvp', 'stop'
    }) do
        hideChild(panel, id)
    end

    -- Restore native equipment widgets to their original OTUI anchors.
    -- breakAnchors() from older experimental passes only existed at runtime;
    -- after restart these widgets are freshly loaded from inventory.otui.
    for _, id in ipairs({
        'amulet', 'helmet', 'backpack',
        'sword', 'ring', 'armor', 'legs', 'boots', 'shield', 'tools'
    }) do
        local slot = panel:getChildById(id)
        if slot then
            slot:show()
            slot:raise()
        end
    end

    -- Header
    character.name = createLabel(
        panel,
        'wowCharacterName',
        'Character',
        138, 12, 154, 18,
        '#f1d58b'
    )

    createLabel(
        panel,
        'wowEquipmentTitle',
        'EQUIPMENT',
        10, 12, 96, 16,
        '#7f91a8'
    )

    -- Player preview occupies the unused right half. No stock Creature
    -- panel_flat background.
    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end

    character.preview:breakAnchors()
    character.preview:setPosition({ x = 166, y = 42 })
    character.preview:setSize({ width = 126, height = 122 })
    character.preview:setImageSource('')
    character.preview:setBackgroundColor('#00000000')
    character.preview:setBorderWidth(0)
    character.preview:setPhantom(true)
    character.preview:show()
    character.preview:raise()

    -- Subtle divider, behind the preview and labels.
    local divider = panel:getChildById('wowCharacterDivider')
    if not divider then
        divider = g_ui.createWidget('Panel', panel)
        divider:setId('wowCharacterDivider')
    end
    divider:breakAnchors()
    divider:setPosition({ x = 126, y = 34 })
    divider:setSize({ width = 1, height = 136 })
    divider:setBackgroundColor('#40536b')
    divider:setPhantom(true)
    divider:show()
    divider:lower()

    -- Close button
    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end

    character.close:setText('X')
    character.close:breakAnchors()
    character.close:setPosition({ x = 310, y = 7 })
    character.close:setSize({ width = 18, height = 17 })
    character.close:setBackgroundColor('#101925dc')
    character.close:setBorderWidth(1)
    character.close:setBorderColor('#536986')
    character.close.onClick = function()
        inventoryUi:hide()
    end
    character.close:show()
    character.close:raise()

    -- Native refresh first, then our existing safety sync.
    if modules.game_inventory and modules.game_inventory.reloadInventory then
        modules.game_inventory.reloadInventory()
    end

    syncEquipmentItems()
    updateCharacter()
    return true
end
local function prepareInventory(forceVisible)
    local inventory = modules.game_inventory
    local r = getRoot()

    if not inventory or not r then
        return false
    end

    if not ensureNativeInventoryExpanded() then
        return false
    end

    if inventoryUi:getParent() ~= r then
        inventoryUi:setParent(r)
    end

    inventoryUi:breakAnchors()
    buildCharacterLayout()
    inventoryUi:setPosition({ x = 24, y = 136 })

    if forceVisible then
        syncEquipmentItems()
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
    scheduleEvent(refreshLayout, 700)
    scheduleEvent(refreshLayout, 1600)
    scheduleEvent(function()
        syncEquipmentItems()
    end, 2200)
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
