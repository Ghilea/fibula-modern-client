AutoLoot = {}

local window
local enabledButton
local modeButton
local closeSourceButton
local statusLabel
local ignoredPanel
local acceptedPanel
local ignoredCountLabel
local acceptedCountLabel

local boundRoot
local originalUIItemMouseRelease
local hookedUIItemMouseRelease

local originalProcessMouseAction
local hookedProcessMouseAction
local armedSourceId
local armedSourcePosition
local armedUntil = 0

local activeSource
local activeTarget
local pendingSource
local openedTargetAutomatically = false
local preferredBackpackContainerId = nil
local containersBeforeSource = {}
local lootRunId = 0

local ignoredLookup = {}
local acceptedLookup = {}

local defaults = {
    enabled = true,
    mode = 'all_except_ignored',
    closeSource = true,
    delay = 280,
    ignored = {},
    accepted = {}
}

AutoLoot.settings = {}

local function copyArray(source)
    local result = {}
    for _, value in ipairs(source or {}) do
        table.insert(result, tonumber(value))
    end
    return result
end

local function loadDefaults()
    AutoLoot.settings = {
        enabled = defaults.enabled,
        mode = defaults.mode,
        closeSource = defaults.closeSource,
        delay = defaults.delay,
        ignored = {},
        accepted = {}
    }
end

local function settingsKey()
    local player = g_game.getLocalPlayer()
    local name = player and player:getName() or 'default'
    name = (name or 'default'):lower():gsub('%s+', '_'):gsub('[^%w_%-]', '')
    return 'fibula_autoloot_' .. name
end

local function rebuildLookups()
    ignoredLookup = {}
    acceptedLookup = {}

    for _, id in ipairs(AutoLoot.settings.ignored or {}) do
        ignoredLookup[tonumber(id)] = true
    end

    for _, id in ipairs(AutoLoot.settings.accepted or {}) do
        acceptedLookup[tonumber(id)] = true
    end
end

local function loadSettings()
    loadDefaults()

    local saved = g_settings.getNode(settingsKey())
    if saved then
        if saved.enabled ~= nil then
            AutoLoot.settings.enabled = saved.enabled == true or saved.enabled == 1
        end

        if saved.mode == 'all_except_ignored' or saved.mode == 'only_accepted' then
            AutoLoot.settings.mode = saved.mode
        end

        if saved.closeSource ~= nil then
            AutoLoot.settings.closeSource = saved.closeSource == true or saved.closeSource == 1
        end

        local delay = tonumber(saved.delay)
        if delay then
            AutoLoot.settings.delay = math.max(180, math.min(1000, delay))
        end

        AutoLoot.settings.ignored = copyArray(saved.ignored)
        AutoLoot.settings.accepted = copyArray(saved.accepted)
    end

    rebuildLookups()
end

local function saveSettings()
    g_settings.setNode(settingsKey(), {
        enabled = AutoLoot.settings.enabled,
        mode = AutoLoot.settings.mode,
        closeSource = AutoLoot.settings.closeSource,
        delay = AutoLoot.settings.delay,
        ignored = AutoLoot.settings.ignored,
        accepted = AutoLoot.settings.accepted
    })
end

local function setStatus(text)
    if statusLabel then
        statusLabel:setText(text or '')
    end

    if text and text ~= '' then
        g_logger.info('[Fibula AutoLoot] ' .. text)
    end
end

local function listContains(list, id)
    id = tonumber(id)
    for _, value in ipairs(list or {}) do
        if tonumber(value) == id then
            return true
        end
    end
    return false
end

local function removeFromList(list, id)
    id = tonumber(id)
    for i = #list, 1, -1 do
        if tonumber(list[i]) == id then
            table.remove(list, i)
        end
    end
end

local function addToList(list, id)
    id = tonumber(id)
    if not id or id <= 0 or listContains(list, id) then
        return
    end
    table.insert(list, id)
end

local function itemLabel(id)
    local name = ''
    pcall(function()
        local thing = g_things.getThingType(id, ThingCategoryItem)
        if thing and thing.getName then
            name = thing:getName() or ''
        end
    end)

    if name and name ~= '' then
        return string.format('%s\nID %d', name, id)
    end

    return string.format('Item ID %d', id)
end

local function createFilterIcon(parent, id, x, y, listName)
    local widget = g_ui.createWidget('UIItem', parent)
    widget:setSize({ width = 32, height = 32 })
    widget:setPosition({ x = x, y = y })
    widget:setItemId(id)
    widget:setTooltip(itemLabel(id) .. '\nLeft-click to remove')
    widget:setBorderWidth(1)
    widget:setBorderColor('#35485f')

    pcall(function()
        widget:setVirtual(true)
    end)

    widget.onMouseRelease = function(self, mousePos, mouseButton)
        if mouseButton ~= MouseLeftButton or not self:containsPoint(mousePos) then
            return false
        end

        if listName == 'ignored' then
            removeFromList(AutoLoot.settings.ignored, id)
        else
            removeFromList(AutoLoot.settings.accepted, id)
        end

        rebuildLookups()
        saveSettings()
        AutoLoot.refreshWindow()
        return true
    end

    return widget
end

local function populateFilterPanel(panel, list, listName)
    if not panel then
        return
    end

    panel:destroyChildren()

    local maxVisible = 10
    for index, id in ipairs(list or {}) do
        if index > maxVisible then
            break
        end

        local i = index - 1
        local col = i % 10
        local row = math.floor(i / 10)
        createFilterIcon(panel, tonumber(id), 4 + col * 36, 4 + row * 36, listName)
    end
end

local function button(parent, id, text, x, y, w, h, callback)
    local widget = g_ui.createWidget('UIButton', parent)
    widget:setId(id)
    widget:setText(text)
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = w, height = h })
    widget:setBackgroundColor('#101925dd')
    widget:setBorderWidth(1)
    widget:setBorderColor('#536986')
    widget.onClick = callback
    return widget
end

local function label(parent, id, text, x, y, w, h, color)
    local widget = g_ui.createWidget('Label', parent)
    widget:setId(id)
    widget:setText(text)
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = w, height = h })
    if color then
        widget:setColor(color)
    end
    return widget
end

local function makePanel(parent, id, x, y, w, h)
    local widget = g_ui.createWidget('Panel', parent)
    widget:setId(id)
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = w, height = h })
    widget:setBackgroundColor('#050a11b8')
    widget:setBorderWidth(1)
    widget:setBorderColor('#35485f')
    return widget
end

local function buildWindow()
    if window and not window:isDestroyed() then
        return
    end

    local root = modules.game_interface.getRootPanel()
    if not root then
        return
    end

    window = g_ui.createWidget('Panel', root)
    window:setId('fibulaAutoLootWindow')
    window:setSize({ width = 390, height = 314 })
    window:setBackgroundColor('#071019f2')
    window:setBorderWidth(1)
    window:setBorderColor('#607a98')
    window:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    window:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

    label(window, 'title', 'AUTO LOOT', 14, 10, 120, 18, '#f1d58b')

    local closeButton = button(window, 'close', 'X', 358, 8, 22, 20, function()
        window:hide()
    end)

    enabledButton = button(window, 'enabled', '', 14, 38, 112, 24, function()
        AutoLoot.settings.enabled = not AutoLoot.settings.enabled
        saveSettings()
        AutoLoot.refreshWindow()
    end)

    modeButton = button(window, 'mode', '', 134, 38, 242, 24, function()
        if AutoLoot.settings.mode == 'all_except_ignored' then
            AutoLoot.settings.mode = 'only_accepted'
        else
            AutoLoot.settings.mode = 'all_except_ignored'
        end
        saveSettings()
        AutoLoot.refreshWindow()
    end)

    closeSourceButton = button(window, 'closeSource', '', 14, 68, 180, 22, function()
        AutoLoot.settings.closeSource = not AutoLoot.settings.closeSource
        saveSettings()
        AutoLoot.refreshWindow()
    end)

    button(window, 'clearIgnored', 'Clear Never Loot', 202, 68, 174, 22, function()
        AutoLoot.settings.ignored = {}
        rebuildLookups()
        saveSettings()
        AutoLoot.refreshWindow()
    end)

    label(window, 'instructions1',
        'Ctrl + right-click item  = toggle Never Loot',
        14, 98, 360, 16, '#b8c3d0')

    label(window, 'instructions2',
        'Shift + right-click item = toggle Always Loot',
        14, 115, 360, 16, '#b8c3d0')

    ignoredCountLabel = label(window, 'ignoredCount', 'NEVER LOOT', 14, 140, 150, 16, '#d88f8f')
    ignoredPanel = makePanel(window, 'ignoredPanel', 14, 158, 362, 42)

    acceptedCountLabel = label(window, 'acceptedCount', 'ALWAYS LOOT', 14, 208, 150, 16, '#8fd89b')
    acceptedPanel = makePanel(window, 'acceptedPanel', 14, 226, 362, 42)

    statusLabel = label(window, 'status', '', 14, 278, 360, 22, '#9eb0c4')
    window:hide()
end

function AutoLoot.refreshWindow()
    if not window or window:isDestroyed() then
        return
    end

    enabledButton:setText(AutoLoot.settings.enabled and 'Auto Loot: ON' or 'Auto Loot: OFF')

    if AutoLoot.settings.mode == 'all_except_ignored' then
        modeButton:setText('Mode: Loot all except Never Loot')
    else
        modeButton:setText('Mode: Loot only Always Loot')
    end

    closeSourceButton:setText(
        AutoLoot.settings.closeSource and 'Close corpse after loot: ON' or 'Close corpse after loot: OFF'
    )

    ignoredCountLabel:setText(string.format('NEVER LOOT (%d)', #AutoLoot.settings.ignored))
    acceptedCountLabel:setText(string.format('ALWAYS LOOT (%d)', #AutoLoot.settings.accepted))

    populateFilterPanel(ignoredPanel, AutoLoot.settings.ignored, 'ignored')
    populateFilterPanel(acceptedPanel, AutoLoot.settings.accepted, 'accepted')
end

function AutoLoot.toggleWindow()
    buildWindow()
    if not window then
        return
    end

    if window:isVisible() then
        window:hide()
    else
        AutoLoot.refreshWindow()
        window:show()
        window:raise()
    end
end

local function toggleIgnored(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end

    if ignoredLookup[itemId] then
        removeFromList(AutoLoot.settings.ignored, itemId)
        setStatus(string.format('Removed item %d from Never Loot', itemId))
    else
        removeFromList(AutoLoot.settings.accepted, itemId)
        addToList(AutoLoot.settings.ignored, itemId)
        setStatus(string.format('Item %d added to Never Loot', itemId))
    end

    rebuildLookups()
    saveSettings()
    AutoLoot.refreshWindow()
end

local function toggleAccepted(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end

    if acceptedLookup[itemId] then
        removeFromList(AutoLoot.settings.accepted, itemId)
        setStatus(string.format('Removed item %d from Always Loot', itemId))
    else
        removeFromList(AutoLoot.settings.ignored, itemId)
        addToList(AutoLoot.settings.accepted, itemId)
        setStatus(string.format('Item %d added to Always Loot', itemId))
    end

    rebuildLookups()
    saveSettings()
    AutoLoot.refreshWindow()
end

local function installUIItemFilterHook()
    if not UIItem or not UIItem.onMouseRelease or originalUIItemMouseRelease then
        return
    end

    originalUIItemMouseRelease = UIItem.onMouseRelease

    hookedUIItemMouseRelease = function(self, mousePosition, mouseButton)
        local item = self:getItem()

        if item and mouseButton == MouseRightButton and self:containsPoint(mousePosition) then
            if g_keyboard.isCtrlPressed() then
                toggleIgnored(item:getId())
                return true
            elseif g_keyboard.isShiftPressed() then
                toggleAccepted(item:getId())
                return true
            end
        end

        return originalUIItemMouseRelease(self, mousePosition, mouseButton)
    end

    UIItem.onMouseRelease = hookedUIItemMouseRelease
end

local function uninstallUIItemFilterHook()
    if originalUIItemMouseRelease and UIItem and UIItem.onMouseRelease == hookedUIItemMouseRelease then
        UIItem.onMouseRelease = originalUIItemMouseRelease
    end

    originalUIItemMouseRelease = nil
    hookedUIItemMouseRelease = nil
end

local function clearArmedSource()
    armedSourceId = nil
    armedSourcePosition = nil
    armedUntil = 0
end

local function armSource(item)
    if not item then
        clearArmedSource()
        return
    end

    -- Snapshot containers that existed BEFORE the corpse was opened.
    -- A bag opened from inside the corpse can therefore never become our
    -- destination just because it has the same item id as the equipped bag.
    containersBeforeSource = {}
    for _, container in pairs(g_game.getContainers()) do
        containersBeforeSource[container:getId()] = true
    end

    armedSourceId = item:getId()
    armedSourcePosition = item:getPosition()
    armedUntil = g_clock.millis() + 1800

    local posText = 'unknown'
    if armedSourcePosition then
        posText = string.format(
            '%d,%d,%d',
            armedSourcePosition.x or -1,
            armedSourcePosition.y or -1,
            armedSourcePosition.z or -1
        )
    end

    setStatus(string.format(
        'Right-click source armed: item %d at %s',
        armedSourceId,
        posText
    ))
end

local function isGroundLootSource(thing)
    if not thing or not thing:isItem() then
        return false
    end

    local position = thing:getPosition()
    if not position or position.x == 65535 then
        return false
    end

    return thing:isContainer() or thing:isLyingCorpse()
end

local function describeThing(thing)
    if not thing or not thing:isItem() then
        return 'nil'
    end

    local position = thing:getPosition()
    local posText = 'no-pos'
    if position then
        posText = string.format(
            '%d,%d,%d',
            position.x or -1,
            position.y or -1,
            position.z or -1
        )
    end

    return string.format(
        'id=%d container=%s corpse=%s pos=%s',
        thing:getId(),
        tostring(thing:isContainer()),
        tostring(thing:isLyingCorpse()),
        posText
    )
end

local function installProcessMouseActionHook()
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
        if AutoLoot.settings.enabled and
           mouseButton == MouseRightButton and
           g_keyboard.getModifiers() == KeyboardNoModifier then

            g_logger.info(string.format(
                '[Fibula AutoLoot] right-click seen: useThing={%s} lookThing={%s}',
                describeThing(useThing),
                describeThing(lookThing)
            ))

            local source = nil

            if isGroundLootSource(useThing) then
                source = useThing
            elseif isGroundLootSource(lookThing) then
                source = lookThing
            end

            if source then
                armSource(source)

                -- Use the same operation the stock classic-control corpse path
                -- uses: open the item directly. This works for both normal
                -- containers and DAT-marked lying corpses.
                g_game.open(source)

                g_logger.info(string.format(
                    '[Fibula AutoLoot] requested open for source item %d',
                    source:getId()
                ))

                return true
            end
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

    g_logger.info('[Fibula AutoLoot] processMouseAction hook installed')
end

local function uninstallProcessMouseActionHook()
    local interface = modules.game_interface

    if originalProcessMouseAction and
       interface and
       interface.processMouseAction == hookedProcessMouseAction then
        interface.processMouseAction = originalProcessMouseAction
    end

    originalProcessMouseAction = nil
    hookedProcessMouseAction = nil
    clearArmedSource()
end
local function shouldLoot(item)
    if not item then
        return false
    end

    -- Never move/open bags or other containers found inside a corpse in 4A.
    -- This check intentionally happens before Always Loot.
    if item:isContainer() then
        return false
    end

    local id = item:getId()

    if acceptedLookup[id] then
        return true
    end

    if AutoLoot.settings.mode == 'only_accepted' then
        return false
    end

    return not ignoredLookup[id]
end

local function isGroundContainer(container)
    if not container then
        return false
    end

    local containerItem = container:getContainerItem()
    if not containerItem then
        return false
    end

    local position = containerItem:getPosition()
    if not position then
        return false
    end

    return position.x ~= 65535
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

local function isEquippedBackpackContainer(container, backpack)
    if not container or not backpack then
        return false
    end

    local item = container:getContainerItem()
    if not item then
        return false
    end

    -- Container-slot positions are encoded as:
    --   x = 0xffff
    --   y = containerId | 0x40
    --   z = slot
    -- so checking item.position.y against InventorySlotBack is incorrect.
    --
    -- OTClient's own looting code identifies opened destination containers by
    -- comparing container:getContainerItem():getId() with the configured
    -- backpack/container item id. Do the same here.
    if item == backpack then
        return true
    end

    return item:getId() == backpack:getId()
end

local function describeOpenContainers()
    local parts = {}

    for _, container in pairs(g_game.getContainers()) do
        local item = container:getContainerItem()
        if item then
            table.insert(parts, string.format(
                'cid=%d item=%d parent=%s name=%s',
                container:getId(),
                item:getId(),
                tostring(container:hasParent()),
                tostring(container:getName())
            ))
        end
    end

    if #parts == 0 then
        return '<none>'
    end

    return table.concat(parts, ' | ')
end

local function findOpenBackpack(backpack)
    if not backpack then
        return nil
    end

    -- First prefer the exact container instance that we already identified as
    -- the player's equipped backpack.
    if preferredBackpackContainerId ~= nil then
        for _, container in pairs(g_game.getContainers()) do
            if container:getId() == preferredBackpackContainerId and
               isEquippedBackpackContainer(container, backpack) then
                return container
            end
        end
        preferredBackpackContainerId = nil
    end

    -- Otherwise only accept a matching root container that was already open
    -- before the corpse was opened. New containers opened from inside the
    -- corpse are deliberately excluded.
    for _, container in pairs(g_game.getContainers()) do
        if containersBeforeSource[container:getId()] and
           not container:hasParent() and
           isEquippedBackpackContainer(container, backpack) then
            preferredBackpackContainerId = container:getId()
            g_logger.info(string.format(
                '[Fibula AutoLoot] pinned backpack destination: cid=%d item=%d',
                container:getId(),
                container:getContainerItem():getId()
            ))
            return container
        end
    end

    return nil
end

local function findDestinationPosition(target, item)
    if not target or not item then
        return nil
    end

    if item:isStackable() then
        local count = item:getCount()

        for index, targetItem in ipairs(target:getItems()) do
            if targetItem:getId() == item:getId() and targetItem:getCount() < 100 then
                return target:getSlotPosition(index - 1), count
            end
        end
    end

    if target:getItemsCount() >= target:getCapacity() then
        return nil
    end

    local count = item:isStackable() and item:getCount() or 1
    return target:getSlotPosition(target:getItemsCount()), count
end

local function finishLoot(source, target, message)
    activeSource = nil
    activeTarget = nil
    pendingSource = nil

    if source and AutoLoot.settings.closeSource then
        pcall(function()
            g_game.close(source)
        end)
    end

    -- Never close the player's backpack here. If it was already open, it must
    -- stay open; if AutoLoot had to open it, leaving it open is less surprising
    -- than toggling/closing the user's inventory window.
    openedTargetAutomatically = false

    if message then
        setStatus(message)
    end
end

local function processLoot(source, target, runId)
    if runId ~= lootRunId or not g_game.isOnline() then
        return
    end

    if not source or not target then
        finishLoot(source, target, 'Loot stopped')
        return
    end

    local nextItem = nil

    for _, item in ipairs(source:getItems()) do
        if shouldLoot(item) and (item.fibulaAutoLootTries or 0) < 3 then
            nextItem = item
            break
        end
    end

    if not nextItem then
        finishLoot(source, target, 'Auto loot finished')
        return
    end

    local toPosition, count = findDestinationPosition(target, nextItem)
    if not toPosition then
        finishLoot(source, target, 'Backpack is full')
        return
    end

    nextItem.fibulaAutoLootTries = (nextItem.fibulaAutoLootTries or 0) + 1

    g_game.move(nextItem, toPosition, count)

    scheduleEvent(function()
        processLoot(source, target, runId)
    end, AutoLoot.settings.delay)
end

local function beginLoot(source, retry)
    retry = retry or 0

    if not AutoLoot.settings.enabled or not g_game.isOnline() then
        return
    end

    if not source then
        return
    end

    local backpack = getEquippedBackpack()
    if not backpack then
        setStatus('No backpack equipped')
        return
    end

    if retry == 0 then
        g_logger.info(string.format(
            '[Fibula AutoLoot] equipped backpack item=%d openContainers=%s',
            backpack:getId(),
            describeOpenContainers()
        ))
    end

    local target = findOpenBackpack(backpack)

    if not target then
        if retry == 0 then
            openedTargetAutomatically = true
            pendingSource = source

            g_logger.info(string.format(
                '[Fibula AutoLoot] opening equipped backpack item %d',
                backpack:getId()
            ))

            g_game.open(backpack)
        end

        if retry >= 8 then
            openedTargetAutomatically = false
            pendingSource = nil

            g_logger.info(string.format(
                '[Fibula AutoLoot] backpack lookup failed. equipped=%d openContainers=%s',
                backpack:getId(),
                describeOpenContainers()
            ))

            setStatus('Could not find opened equipped backpack')
            return
        end

        scheduleEvent(function()
            beginLoot(source, retry + 1)
        end, 220)
        return
    end

    g_logger.info(string.format(
        '[Fibula AutoLoot] destination backpack found: cid=%d item=%d parent=%s items=%d/%d',
        target:getId(),
        target:getContainerItem():getId(),
        tostring(target:hasParent()),
        target:getItemsCount(),
        target:getCapacity()
    ))

    pendingSource = nil
    activeSource = source
    activeTarget = target
    lootRunId = lootRunId + 1
    local runId = lootRunId

    setStatus('Looting opened ground container...')

    scheduleEvent(function()
        processLoot(source, target, runId)
    end, 80)
end

local function onContainerOpen(container)
    if not AutoLoot.settings.enabled then
        return
    end

    -- If we are opening our equipped backpack automatically, resume the
    -- already-confirmed source loot pass.
    if pendingSource then
        local backpack = getEquippedBackpack()
        if backpack and isEquippedBackpackContainer(container, backpack) then
            preferredBackpackContainerId = container:getId()
            g_logger.info(string.format(
                '[Fibula AutoLoot] equipped backpack opened and pinned: cid=%d item=%d parent=%s',
                container:getId(),
                container:getContainerItem():getId(),
                tostring(container:hasParent())
            ))

            scheduleEvent(function()
                if pendingSource then
                    beginLoot(pendingSource, 1)
                end
            end, 60)
            return
        end
    end

    -- Only autoloot a source that was explicitly armed by the player's
    -- right-click on the game map.
    if armedSourceId and g_clock.millis() <= armedUntil then
        local containerItem = container:getContainerItem()

        if containerItem and containerItem:getId() == armedSourceId then
            clearArmedSource()
            setStatus(string.format(
                'Right-click source opened: item %d',
                containerItem:getId()
            ))
            beginLoot(container, 0)
            return
        end
    end

    if armedSourceId and g_clock.millis() > armedUntil then
        clearArmedSource()
    end
end

local function onContainerClose(container)
    if preferredBackpackContainerId == container:getId() then
        preferredBackpackContainerId = nil
    end

    if container == activeSource then
        activeSource = nil
        lootRunId = lootRunId + 1
    elseif container == activeTarget then
        activeTarget = nil
        lootRunId = lootRunId + 1
    end
end

local function bindKeys()
    if boundRoot then
        return
    end

    boundRoot = modules.game_interface.getRootPanel()
    if not boundRoot then
        return
    end

    g_keyboard.bindKeyDown('Ctrl+Shift+L', AutoLoot.toggleWindow, boundRoot)
end

local function unbindKeys()
    if not boundRoot then
        return
    end

    g_keyboard.unbindKeyDown('Ctrl+Shift+L', AutoLoot.toggleWindow, boundRoot)
    boundRoot = nil
end

local function onGameStart()
    loadSettings()
    buildWindow()
    AutoLoot.refreshWindow()
    bindKeys()
    setStatus('Ready - right-click a corpse/container to loot')
end

local function onGameEnd()
    lootRunId = lootRunId + 1
    activeSource = nil
    activeTarget = nil
    pendingSource = nil
    openedTargetAutomatically = false
    clearArmedSource()
    saveSettings()

    if window then
        window:hide()
    end
end

function AutoLoot.init()
    loadDefaults()
    buildWindow()
    installUIItemFilterHook()
    installProcessMouseActionHook()

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    connect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose
    })

    bindKeys()

    if g_game.isOnline() then
        onGameStart()
    else
        AutoLoot.refreshWindow()
    end
end

function AutoLoot.terminate()
    saveSettings()

    lootRunId = lootRunId + 1

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    disconnect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose
    })

    unbindKeys()
    uninstallUIItemFilterHook()
    uninstallProcessMouseActionHook()

    if window and not window:isDestroyed() then
        window:destroy()
    end

    window = nil
    activeSource = nil
    activeTarget = nil
    pendingSource = nil
end
