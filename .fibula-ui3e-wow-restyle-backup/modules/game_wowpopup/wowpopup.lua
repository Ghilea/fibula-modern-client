WowPopup = {}

local root
local inventoryUi
local minimapUi
local boundWidget
local inventoryPrepared = false

local character = {
    title = nil,
    name = nil,
    previewFrame = nil,
    preview = nil,
    hp = nil,
    mana = nil,
    xp = nil,
    level = nil,
    cap = nil,
    soul = nil,
    close = nil,
    combatLabel = nil,
    moveLabel = nil
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
    if widget then
        widget:hide()
    end
end

local function moveChild(parent, id, x, y)
    if not parent then return nil end
    local widget = parent:getChildById(id)
    if not widget then return nil end

    widget:breakAnchors()
    widget:setPosition({ x = x, y = y })
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
    if color then widget:setColor(color) end
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
    return widget
end

local function createProgress(parent, id, x, y, width, height, color)
    local widget = parent:getChildById(id)
    if not widget then
        widget = g_ui.createWidget('UIProgressBar', parent)
        widget:setId(id)
    end

    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = width, height = height })
    widget:setBackgroundColor(color)
    widget:setBorderWidth(1)
    widget:setBorderColor('#050607')
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

    local health = player:getHealth() or 0
    local maxHealth = player:getMaxHealth() or 0
    local mana = player:getMana() or 0
    local maxMana = player:getMaxMana() or 0
    local levelPercent = player:getLevelPercent() or 0

    local healthPercent = maxHealth > 0 and math.max(0, math.min(100, (health * 100) / maxHealth)) or 0
    local manaPercent = maxMana > 0 and math.max(0, math.min(100, (mana * 100) / maxMana)) or 0

    if character.hp then
        character.hp:setPercent(healthPercent)
        character.hp:setText(string.format('%d / %d', health, maxHealth))
    end

    if character.mana then
        character.mana:setPercent(manaPercent)
        character.mana:setText(string.format('%d / %d', mana, maxMana))
    end

    if character.xp then
        character.xp:setPercent(levelPercent)
        character.xp:setText(string.format('XP %.1f%%', levelPercent))
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
    if not inventoryUi or not inventoryUi.onPanel then
        return false
    end

    local panel = inventoryUi.onPanel

    inventoryUi:setWidth(440)
    inventoryUi:setHeight(344)
    inventoryUi:setBackgroundColor('#080d14ec')
    inventoryUi:setBorderWidth(1)
    inventoryUi:setBorderColor('#637b99')
    inventoryUi.moveOnlyToMain = false

    panel:setBackgroundColor('#080d14e0')

    -- Remove the old compact Tibia header/combat clutter. The actual equipment
    -- widgets remain native and fully interactive.
    for _, id in ipairs({
        'changeSize', 'blessings', 'purseButton',
        'expert', 'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox',
        'icons', 'soulPanel', 'capacityPanel'
    }) do
        hideChild(panel, id)
    end

    character.title = createLabel(panel, 'wowCharacterTitle', 'CHARACTER', 16, 8, 180, 18, '#f0d58b')
    character.name = createLabel(panel, 'wowCharacterName', 'Character', 152, 36, 138, 18, '#f4df9b')

    character.previewFrame = createPanel(panel, 'wowCharacterPreviewFrame', 158, 58, 124, 134, '#05080d88', '#536986')

    character.preview = panel:getChildById('wowCharacterPreview')
    if not character.preview then
        character.preview = g_ui.createWidget('Creature', panel)
        character.preview:setId('wowCharacterPreview')
    end
    character.preview:setPosition({ x = 166, y = 66 })
    character.preview:setSize({ width = 108, height = 116 })
    character.preview:setPhantom(true)

    -- Equipment arranged around the player preview.
    moveChild(panel, 'helmet',   203, 24)
    moveChild(panel, 'amulet',    72, 68)
    moveChild(panel, 'sword',     72, 112)
    moveChild(panel, 'ring',      72, 156)

    moveChild(panel, 'backpack', 334, 68)
    moveChild(panel, 'shield',   334, 112)
    moveChild(panel, 'tools',    334, 156)

    moveChild(panel, 'armor',    116, 82)
    moveChild(panel, 'legs',     116, 126)
    moveChild(panel, 'boots',    203, 199)

    character.hp = createProgress(panel, 'wowCharacterHp', 22, 238, 186, 18, '#2f8f46')
    character.mana = createProgress(panel, 'wowCharacterMana', 22, 262, 186, 16, '#315fb5')
    character.xp = createProgress(panel, 'wowCharacterXp', 22, 284, 186, 14, '#7540a8')

    character.level = createLabel(panel, 'wowCharacterLevel', 'Level', 232, 238, 180, 18, '#d5dbe3')
    character.cap = createLabel(panel, 'wowCharacterCap', 'Capacity', 232, 262, 180, 18, '#d5dbe3')
    character.soul = createLabel(panel, 'wowCharacterSoul', 'Soul', 232, 284, 180, 18, '#d5dbe3')

    character.combatLabel = createLabel(panel, 'wowCombatLabel', 'Combat', 18, 316, 54, 16, '#8795a8')
    character.moveLabel = createLabel(panel, 'wowMoveLabel', 'Move', 182, 316, 40, 16, '#8795a8')

    -- Keep native combat controls, but move them into a dedicated footer.
    moveChild(panel, 'attack',        74, 310)
    moveChild(panel, 'balanced',      98, 310)
    moveChild(panel, 'defense',      122, 310)

    moveChild(panel, 'standPosture',  224, 310)
    moveChild(panel, 'followPosture', 248, 310)
    moveChild(panel, 'pvp',           294, 309)
    moveChild(panel, 'stop',          360, 313)

    -- Small close button in the new header.
    character.close = panel:getChildById('wowCharacterClose')
    if not character.close then
        character.close = g_ui.createWidget('UIButton', panel)
        character.close:setId('wowCharacterClose')
    end
    character.close:setText('X')
    character.close:setPosition({ x = 410, y = 7 })
    character.close:setSize({ width = 20, height = 18 })
    character.close:setBackgroundColor('#101925d8')
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
    inventoryUi:setPosition({ x = 24, y = 142 })

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

    -- Reserve the entire top-right utility strip so nothing overlaps.
    local optionsReserve = 224
    minimapUi:setPosition({
        x = math.max(16, rsize.width - 178 - optionsReserve),
        y = 36
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
    if not canHandleGameKey() then
        return false
    end

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
