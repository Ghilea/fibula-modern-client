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

    -- IMPORTANT: UIWidget:setPosition() is screen-space. Earlier Character
    -- versions used setPosition() on child widgets, so dragging the parent
    -- window caused the children to appear to slide around inside it.
    -- Every child below is now anchored to its PARENT and positioned only
    -- through margins. The whole layout therefore moves as one unit.
    local function anchorWidget(widget, x, y, w, h)
        if not widget then return nil end

        widget:breakAnchors()
        widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        widget:addAnchor(AnchorTop, 'parent', AnchorTop)
        widget:setMarginLeft(x)
        widget:setMarginTop(y)

        if w and h then
            widget:setSize({ width = w, height = h })
        end

        widget:show()
        widget:raise()
        return widget
    end

    local function anchorSlot(id, x, y)
        local widget = panel:getChildById(id)
        if not widget then return nil end

        anchorWidget(widget, x, y, 34, 34)
        widget:setImageSource('/images/inventory/containerslot')

        if widget.item then
            widget.item:setSize({ width = 34, height = 34 })
            widget.item:show()
            widget.item:raise()
        end

        return widget
    end

    local function anchorLabel(id, text, x, y, w, h, color)
        local widget = panel:getChildById(id)
        if not widget then
            widget = g_ui.createWidget('Label', panel)
            widget:setId(id)
        end

        widget:setText(text or '')
        if color then widget:setColor(color) end
        return anchorWidget(widget, x, y, w, h)
    end

    local function anchorFrame(id, x, y, w, h, bg, border)
        local widget = panel:getChildById(id)
        if not widget then
            widget = g_ui.createWidget('Panel', panel)
            widget:setId(id)
        end

        widget:setBackgroundColor(bg or '#0b1420c8')
        widget:setBorderWidth(1)
        widget:setBorderColor(border or '#42566f')
        widget:setPhantom(true)
        anchorWidget(widget, x, y, w, h)
        widget:lower()
        return widget
    end

    inventoryUi:setWidth(326)
    inventoryUi:setHeight(264)
    inventoryUi:setImageSource('')
    inventoryUi:setBackgroundColor('#071019f2')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#607a98')
    inventoryUi.moveOnlyToMain = false

    -- Make the actual content panel fill the draggable Character window.
    panel:breakAnchors()
    panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    panel:addAnchor(AnchorRight, 'parent', AnchorRight)
    panel:addAnchor(AnchorTop, 'parent', AnchorTop)
    panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    panel:setMarginLeft(0)
    panel:setMarginRight(0)
    panel:setMarginTop(0)
    panel:setMarginBottom(0)
    panel:setImageSource('')
    panel:setBackgroundColor('#071019ea')
    panel:show()

    -- Remove custom remnants from all previous Character experiments.
    for _, id in ipairs({
        'wowHeaderPanel', 'wowBodyLeft', 'wowBodyCenter', 'wowBodyRight',
        'wowFooter', 'wowCharacterBody', 'wowCharacterFooter',
        'wowCharacterPreviewFrame', 'wowCharacterPreviewBorder',
        'wowCharacterPreview', 'wowCharacterDivider',
        'wowCharacterHp', 'wowCharacterMana', 'wowCharacterXp',
        'wowCharacterLevel', 'wowCharacterCap', 'wowCharacterSoul',
        'wowCombatLabel', 'wowMoveLabel', 'wowModesLabel',
        'wowCharacterStats', 'wowLeftEquipmentLabel', 'wowRightEquipmentLabel',
        'wowCharacterTitle', 'wowGearHint', 'wowEquipmentTitle', 'wowPreviewTitle',
        'wowCharacterSubTitle', 'wowCombatTitle', 'wowPvpTitle',
        'wowSlotFrame', 'wowControlFrame', 'wowEquipmentFrame', 'wowSettingsFrame'
    }) do
        destroyChild(panel, id)
    end

    -- Keep unrelated classic controls out of this popup.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton', 'expert',
        'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'standPosture', 'followPosture', 'stop'
    }) do
        hideChild(panel, id)
    end

    character.preview = nil

    character.name = anchorLabel(
        'wowCharacterName',
        'Character',
        14, 10, 246, 18,
        '#f1d58b'
    )

    anchorLabel('wowCharacterSubTitle', 'EQUIPMENT', 18, 38, 100, 15, '#7f91a8')
    anchorLabel('wowCombatTitle', 'FIGHTING STYLE', 168, 106, 120, 15, '#7f91a8')
    anchorLabel('wowPvpTitle', 'PVP MODE', 168, 164, 90, 15, '#7f91a8')

    -- Proper margins around both groups.
    anchorFrame('wowEquipmentFrame', 12, 54, 134, 190, '#0b1420c6', '#40546d')
    anchorFrame('wowSettingsFrame', 158, 54, 154, 190, '#0b1420b8', '#40546d')

    -- Centered 2 x 5 equipment grid inside the left frame.
    anchorSlot('helmet',   28,  66)
    anchorSlot('amulet',   88,  66)
    anchorSlot('armor',    28, 102)
    anchorSlot('backpack', 88, 102)
    anchorSlot('legs',     28, 138)
    anchorSlot('sword',    88, 138)
    anchorSlot('boots',    28, 174)
    anchorSlot('shield',   88, 174)
    anchorSlot('ring',     28, 210)
    anchorSlot('tools',    88, 210)

    -- Native capacity display.
    -- The stock Capacity widget is designed as a two-line box (Cap + value).
    -- Earlier versions forced it to 18px high, making both labels overlap.
    local capacity = panel:getChildById('capacityPanel')
    if capacity then
        anchorWidget(capacity, 170, 60, 128, 36)
        capacity:setImageSource('')
        capacity:setBackgroundColor('#0a131dd8')
        capacity:setBorderWidth(1)
        capacity:setBorderColor('#42566f')

        local capChildren = capacity:getChildren() or {}
        if capChildren[1] then
            capChildren[1]:setColor('#8fa4bd')
            capChildren[1]:setFont('verdana-11px-rounded')
        end
        if capChildren[2] then
            capChildren[2]:setColor('#f1d58b')
            capChildren[2]:setFont('verdana-11px-rounded')
        end
    end

    -- Native fighting style controls.
    local attack = panel:getChildById('attack')
    local balanced = panel:getChildById('balanced')
    local defense = panel:getChildById('defense')

    if attack then anchorWidget(attack, 172, 126, 20, 20) end
    if balanced then anchorWidget(balanced, 208, 126, 20, 20) end
    if defense then anchorWidget(defense, 244, 126, 20, 20) end

    -- Native PvP control.
    -- Keep the stock 44x21 size because its image is a 44px-wide state atlas.
    local pvp = panel:getChildById('pvp')
    if pvp then
        anchorWidget(pvp, 172, 186, 44, 21)
    end

    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end

    character.close:setText('X')
    character.close:setBackgroundColor('#101925dc')
    character.close:setBorderWidth(1)
    character.close:setBorderColor('#536986')
    character.close.onClick = function()
        inventoryUi:hide()
    end
    anchorWidget(character.close, 302, 8, 16, 16)

    -- Native refresh + the existing safety sync.
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
