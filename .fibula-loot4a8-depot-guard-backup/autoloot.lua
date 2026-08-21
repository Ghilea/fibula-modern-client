AutoLoot = {}

-- UI ------------------------------------------------------------------------

local window
local enabledButton
local closeSourceButton
local statusLabel
local filterPanel
local filterCountLabel
local filterPageLabel
local prevPageButton
local nextPageButton
local filterPage = 1
local FILTER_PAGE_SIZE = 40

local boundRoot
local originalUIItemMouseRelease
local hookedUIItemMouseRelease
local originalUIItemItemChange
local hookedUIItemItemChange
local originalProcessMouseAction
local hookedProcessMouseAction

-- Loot state ----------------------------------------------------------------

local activeTarget
local traversalFrames = {}
local pendingNestedOpen
local pendingParentReturn
local ignoreClose = {}
local pendingRootSource
local awaitingBackpackOpen = false

local preferredBackpackContainerId
local containersBeforeSource = {}

local armedSourceId
local armedSourcePosition
local armedUntil = 0
local lastSourceKey
local lastSourceAt = 0
local lootRunId = 0

-- Filter state ---------------------------------------------------------------

local ignoredLookup = {}
local knownLookup = {}

local defaults = {
    enabled = true,
    closeSource = true,
    delay = 280,
    ignored = {},
    known = {}
}

AutoLoot.settings = {}

-- Settings ------------------------------------------------------------------

local function copyArray(source)
    local result = {}

    for _, value in ipairs(source or {}) do
        local id = tonumber(value)
        if id then
            table.insert(result, id)
        end
    end

    return result
end

local function addUnique(list, id)
    id = tonumber(id)
    if not id then
        return false
    end

    for _, value in ipairs(list) do
        if tonumber(value) == id then
            return false
        end
    end

    table.insert(list, id)
    return true
end

local function removeValue(list, id)
    id = tonumber(id)

    for i = #list, 1, -1 do
        if tonumber(list[i]) == id then
            table.remove(list, i)
        end
    end
end

local function loadDefaults()
    AutoLoot.settings = {
        enabled = defaults.enabled,
        closeSource = defaults.closeSource,
        delay = defaults.delay,
        ignored = {},
        known = {}
    }
end

local function settingsKey()
    local player = g_game.getLocalPlayer()
    local name = player and player:getName() or 'default'

    name = (name or 'default')
        :lower()
        :gsub('%s+', '_')
        :gsub('[^%w_%-]', '')

    return 'fibula_autoloot_' .. name
end

local function rebuildLookups()
    ignoredLookup = {}
    knownLookup = {}

    for _, id in ipairs(AutoLoot.settings.ignored or {}) do
        ignoredLookup[tonumber(id)] = true
    end

    for _, id in ipairs(AutoLoot.settings.known or {}) do
        knownLookup[tonumber(id)] = true
    end
end

local function saveSettings()
    g_settings.setNode(settingsKey(), {
        enabled = AutoLoot.settings.enabled,
        closeSource = AutoLoot.settings.closeSource,
        delay = AutoLoot.settings.delay,
        ignored = AutoLoot.settings.ignored,
        known = AutoLoot.settings.known
    })
end

local function loadSettings()
    loadDefaults()

    local saved = g_settings.getNode(settingsKey())

    if saved then
        if saved.enabled ~= nil then
            AutoLoot.settings.enabled =
                saved.enabled == true or saved.enabled == 1
        end

        if saved.closeSource ~= nil then
            AutoLoot.settings.closeSource =
                saved.closeSource == true or saved.closeSource == 1
        end

        local delay = tonumber(saved.delay)
        if delay then
            AutoLoot.settings.delay =
                math.max(180, math.min(1000, delay))
        end

        AutoLoot.settings.ignored = copyArray(saved.ignored)
        AutoLoot.settings.known = copyArray(saved.known)

        -- Older 4A versions had an Always Loot list.
        -- Default now means Loot, so only remember those item IDs.
        for _, id in ipairs(copyArray(saved.accepted)) do
            addUnique(AutoLoot.settings.known, id)
        end
    end

    for _, id in ipairs(AutoLoot.settings.ignored) do
        addUnique(AutoLoot.settings.known, id)
    end

    table.sort(AutoLoot.settings.known)
    table.sort(AutoLoot.settings.ignored)
    rebuildLookups()
end

local function setStatus(text)
    if statusLabel then
        statusLabel:setText(text or '')
    end

    if text and text ~= '' then
        g_logger.info('[Fibula AutoLoot] ' .. text)
    end
end

local function rememberItemId(id)
    id = tonumber(id)

    if not id or knownLookup[id] then
        return false
    end

    knownLookup[id] = true
    table.insert(AutoLoot.settings.known, id)
    table.sort(AutoLoot.settings.known)
    saveSettings()
    return true
end

local function rememberItem(item)
    if not item or item:isContainer() then
        return false
    end

    return rememberItemId(item:getId())
end

-- UI helpers ----------------------------------------------------------------

local function anchorPlace(widget, x, y, w, h)
    if not widget then
        return
    end

    widget:breakAnchors()
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:setMarginTop(y)
    widget:setMarginLeft(x)

    if w and h then
        widget:setSize({
            width = w,
            height = h
        })
    end
end

local function makeButton(parent, id, text, x, y, w, h, callback)
    local widget = g_ui.createWidget('UIButton', parent)
    widget:setId(id)
    widget:setText(text)
    anchorPlace(widget, x, y, w, h)
    widget:setBackgroundColor('#101925dd')
    widget:setBorderWidth(1)
    widget:setBorderColor('#536986')
    widget.onClick = callback
    return widget
end

local function makeLabel(parent, id, text, x, y, w, h, color)
    local widget = g_ui.createWidget('Label', parent)
    widget:setId(id)
    widget:setText(text)
    anchorPlace(widget, x, y, w, h)

    if color then
        widget:setColor(color)
    end

    return widget
end

local function makePanel(parent, id, x, y, w, h)
    local widget = g_ui.createWidget('Panel', parent)
    widget:setId(id)
    anchorPlace(widget, x, y, w, h)
    widget:setBackgroundColor('#050a11d8')
    widget:setBorderWidth(1)
    widget:setBorderColor('#35485f')
    return widget
end

local function itemLabel(id)
    local name = ''

    pcall(function()
        local thing = g_things.getThingType(id, ThingCategoryItem)
        if thing and thing.getName then
            name = thing:getName() or ''
        end
    end)

    if name ~= '' then
        return string.format('%s\nID %d', name, id)
    end

    return string.format('Item ID %d', id)
end

local function applyLootMarker(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    local item = widget:getItem()
    local marker = widget:getChildById('fibulaNeverLootMark')
    local ignored = item and ignoredLookup[item:getId()]

    if ignored then
        if not marker then
            marker = g_ui.createWidget('Label', widget)
            marker:setId('fibulaNeverLootMark')
            marker:setText('X')
            marker:setColor('#ff4f4f')
            marker:setTextAlign(AlignCenter)
            marker:setSize({
                width = 12,
                height = 12
            })
            marker:setPhantom(true)
            marker:breakAnchors()
            marker:addAnchor(AnchorTop, 'parent', AnchorTop)
            marker:addAnchor(AnchorRight, 'parent', AnchorRight)
            marker:setMarginTop(1)
            marker:setMarginRight(1)
        end

        marker:show()
        marker:raise()
        widget:setOpacity(0.52)
    else
        if marker then
            marker:destroy()
        end

        widget:setOpacity(1.0)
    end
end

local function refreshContainerMarkers()
    for _, container in pairs(g_game.getContainers()) do
        if container.itemsPanel then
            for slot = 0, container:getCapacity() - 1 do
                local widget =
                    container.itemsPanel:getChildById('item' .. slot)

                if widget then
                    applyLootMarker(widget)
                end
            end
        end
    end
end

local function toggleIgnored(itemId)
    itemId = tonumber(itemId)

    if not itemId then
        return
    end

    rememberItemId(itemId)

    if ignoredLookup[itemId] then
        ignoredLookup[itemId] = nil
        removeValue(AutoLoot.settings.ignored, itemId)

        setStatus(string.format(
            'Item %d restored to Default Loot',
            itemId
        ))
    else
        ignoredLookup[itemId] = true
        addUnique(AutoLoot.settings.ignored, itemId)
        table.sort(AutoLoot.settings.ignored)

        setStatus(string.format(
            'Item %d set to Never Loot',
            itemId
        ))
    end

    saveSettings()
    AutoLoot.refreshWindow()
    refreshContainerMarkers()
end

local function createFilterIcon(parent, id, x, y)
    local widget = g_ui.createWidget('UIItem', parent)

    widget:setSize({
        width = 34,
        height = 34
    })

    anchorPlace(widget, x, y, 34, 34)
    widget:setItemId(id)
    widget:setBorderWidth(1)
    widget:setBorderColor(
        ignoredLookup[id] and '#9c3e3e' or '#35485f'
    )

    widget:setTooltip(
        itemLabel(id) ..
        (
            ignoredLookup[id]
            and '\nNEVER LOOT\nClick to restore Default Loot'
            or '\nDEFAULT LOOT\nClick to set Never Loot'
        )
    )

    pcall(function()
        widget:setVirtual(true)
    end)

    widget.onMouseRelease = function(self, mousePos, mouseButton)
        if mouseButton ~= MouseLeftButton or
           not self:containsPoint(mousePos) then
            return false
        end

        toggleIgnored(id)
        return true
    end

    applyLootMarker(widget)
    return widget
end

local function rebuildFilterPage()
    if not filterPanel then
        return
    end

    filterPanel:destroyChildren()

    local total = #AutoLoot.settings.known
    local pages =
        math.max(1, math.ceil(total / FILTER_PAGE_SIZE))

    filterPage =
        math.max(1, math.min(filterPage, pages))

    local first =
        (filterPage - 1) * FILTER_PAGE_SIZE + 1

    local last =
        math.min(total, first + FILTER_PAGE_SIZE - 1)

    if total == 0 then
        makeLabel(
            filterPanel,
            'empty',
            'No loot item types seen yet.',
            12, 12, 280, 18,
            '#8999aa'
        )
    else
        local visibleIndex = 0

        for index = first, last do
            local id = AutoLoot.settings.known[index]
            local col = visibleIndex % 8
            local row = math.floor(visibleIndex / 8)

            createFilterIcon(
                filterPanel,
                id,
                12 + col * 45,
                12 + row * 42
            )

            visibleIndex = visibleIndex + 1
        end
    end

    filterCountLabel:setText(string.format(
        'LOOT FILTER (%d items)   Red X = Never Loot',
        total
    ))

    filterPageLabel:setText(string.format(
        'Page %d / %d',
        filterPage,
        pages
    ))

    prevPageButton:setEnabled(filterPage > 1)
    nextPageButton:setEnabled(filterPage < pages)
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
    window:setSize({
        width = 400,
        height = 350
    })
    window:setBackgroundColor('#071019f4')
    window:setBorderWidth(1)
    window:setBorderColor('#607a98')
    window:breakAnchors()
    window:addAnchor(
        AnchorHorizontalCenter,
        'parent',
        AnchorHorizontalCenter
    )
    window:addAnchor(
        AnchorVerticalCenter,
        'parent',
        AnchorVerticalCenter
    )

    makeLabel(
        window,
        'title',
        'AUTO LOOT',
        14, 10, 160, 18,
        '#f1d58b'
    )

    makeButton(
        window,
        'close',
        'X',
        366, 8, 22, 20,
        function()
            window:hide()
        end
    )

    enabledButton = makeButton(
        window,
        'enabled',
        '',
        14, 38, 118, 24,
        function()
            AutoLoot.settings.enabled =
                not AutoLoot.settings.enabled

            saveSettings()
            AutoLoot.refreshWindow()
        end
    )

    closeSourceButton = makeButton(
        window,
        'closeSource',
        '',
        140, 38, 246, 24,
        function()
            AutoLoot.settings.closeSource =
                not AutoLoot.settings.closeSource

            saveSettings()
            AutoLoot.refreshWindow()
        end
    )

    makeButton(
        window,
        'reset',
        'Reset Never Loot',
        14, 70, 142, 22,
        function()
            AutoLoot.settings.ignored = {}
            ignoredLookup = {}

            saveSettings()
            AutoLoot.refreshWindow()
            refreshContainerMarkers()

            setStatus(
                'All items restored to Default Loot'
            )
        end
    )

    makeLabel(
        window,
        'instruction',
        'Ctrl + right-click item: Default Loot <-> Never Loot',
        166, 73, 220, 18,
        '#b8c3d0'
    )

    filterCountLabel = makeLabel(
        window,
        'filterCount',
        '',
        14, 104, 372, 18,
        '#8fa4bd'
    )

    filterPanel = makePanel(
        window,
        'filterPanel',
        14, 126, 372, 184
    )

    prevPageButton = makeButton(
        window,
        'prevPage',
        '< Prev',
        14, 318, 72, 22,
        function()
            filterPage = filterPage - 1
            rebuildFilterPage()
        end
    )

    filterPageLabel = makeLabel(
        window,
        'filterPage',
        '',
        144, 320, 112, 18,
        '#9eb0c4'
    )
    filterPageLabel:setTextAlign(AlignCenter)

    nextPageButton = makeButton(
        window,
        'nextPage',
        'Next >',
        314, 318, 72, 22,
        function()
            filterPage = filterPage + 1
            rebuildFilterPage()
        end
    )

    statusLabel = makeLabel(
        window,
        'status',
        '',
        96, 320, 210, 18,
        '#9eb0c4'
    )
    statusLabel:hide()

    window:hide()
end

function AutoLoot.refreshWindow()
    if not window or window:isDestroyed() then
        return
    end

    enabledButton:setText(
        AutoLoot.settings.enabled
        and 'Auto Loot: ON'
        or 'Auto Loot: OFF'
    )

    closeSourceButton:setText(
        AutoLoot.settings.closeSource
        and 'Close corpse after loot: ON'
        or 'Close corpse after loot: OFF'
    )

    rebuildFilterPage()
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

-- UI item hooks --------------------------------------------------------------

local function installUIItemHooks()
    if not UIItem then
        return
    end

    if UIItem.onMouseRelease and
       not originalUIItemMouseRelease then
        originalUIItemMouseRelease =
            UIItem.onMouseRelease

        hookedUIItemMouseRelease =
            function(self, mousePosition, mouseButton)
                local item = self:getItem()

                if item and
                   mouseButton == MouseRightButton and
                   self:containsPoint(mousePosition) and
                   g_keyboard.isCtrlPressed() then
                    toggleIgnored(item:getId())
                    applyLootMarker(self)
                    return true
                end

                return originalUIItemMouseRelease(
                    self,
                    mousePosition,
                    mouseButton
                )
            end

        UIItem.onMouseRelease =
            hookedUIItemMouseRelease
    end

    if UIItem.onItemChange and
       not originalUIItemItemChange then
        originalUIItemItemChange =
            UIItem.onItemChange

        hookedUIItemItemChange = function(self)
            local result =
                originalUIItemItemChange(self)

            applyLootMarker(self)
            return result
        end

        UIItem.onItemChange =
            hookedUIItemItemChange
    end
end

local function uninstallUIItemHooks()
    if originalUIItemMouseRelease and
       UIItem and
       UIItem.onMouseRelease ==
           hookedUIItemMouseRelease then
        UIItem.onMouseRelease =
            originalUIItemMouseRelease
    end

    if originalUIItemItemChange and
       UIItem and
       UIItem.onItemChange ==
           hookedUIItemItemChange then
        UIItem.onItemChange =
            originalUIItemItemChange
    end

    originalUIItemMouseRelease = nil
    hookedUIItemMouseRelease = nil
    originalUIItemItemChange = nil
    hookedUIItemItemChange = nil
end

-- Mouse / corpse source ------------------------------------------------------

local function sourceKey(item)
    if not item then
        return nil
    end

    local pos = item:getPosition()

    if not pos then
        return tostring(item:getId())
    end

    return string.format(
        '%d:%d:%d:%d',
        item:getId(),
        pos.x or -1,
        pos.y or -1,
        pos.z or -1
    )
end

local function snapshotOpenContainers()
    containersBeforeSource = {}

    for _, container in pairs(
        g_game.getContainers()
    ) do
        containersBeforeSource[
            container:getId()
        ] = true
    end
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

    snapshotOpenContainers()

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

    return thing:isContainer() or
        thing:isLyingCorpse()
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

local function callOriginalMouseAction(
    menuPosition,
    mouseButton,
    autoWalkPos,
    lookThing,
    useThing,
    creatureThing,
    attackCreature
)
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

local function installProcessMouseActionHook()
    local interface =
        modules.game_interface

    if not interface or
       not interface.processMouseAction or
       originalProcessMouseAction then
        return
    end

    originalProcessMouseAction =
        interface.processMouseAction

    hookedProcessMouseAction =
        function(
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
               g_keyboard.getModifiers() ==
                   KeyboardNoModifier then

                local player =
                    g_game.getLocalPlayer()

                -- Important:
                -- a living creature standing over a corpse always
                -- keeps the stock attack/select behavior.
                if attackCreature and
                   attackCreature ~= player and
                   not attackCreature:isNpc() then
                    return callOriginalMouseAction(
                        menuPosition,
                        mouseButton,
                        autoWalkPos,
                        lookThing,
                        useThing,
                        creatureThing,
                        attackCreature
                    )
                end

                if creatureThing and
                   creatureThing ~= player and
                   not creatureThing:isNpc() then
                    return callOriginalMouseAction(
                        menuPosition,
                        mouseButton,
                        autoWalkPos,
                        lookThing,
                        useThing,
                        creatureThing,
                        attackCreature
                    )
                end

                g_logger.info(string.format(
                    '[Fibula AutoLoot] right-click seen: useThing={%s} lookThing={%s}',
                    describeThing(useThing),
                    describeThing(lookThing)
                ))

                local source

                if isGroundLootSource(useThing) then
                    source = useThing
                elseif isGroundLootSource(lookThing) then
                    source = lookThing
                end

                if source then
                    local key =
                        sourceKey(source)

                    local now =
                        g_clock.millis()

                    if key == lastSourceKey and
                       now - lastSourceAt < 350 then
                        return true
                    end

                    lastSourceKey = key
                    lastSourceAt = now

                    armSource(source)
                    g_game.open(source)

                    g_logger.info(string.format(
                        '[Fibula AutoLoot] requested open for source item %d',
                        source:getId()
                    ))

                    return true
                end
            end

            return callOriginalMouseAction(
                menuPosition,
                mouseButton,
                autoWalkPos,
                lookThing,
                useThing,
                creatureThing,
                attackCreature
            )
        end

    interface.processMouseAction =
        hookedProcessMouseAction

    g_logger.info(
        '[Fibula AutoLoot] processMouseAction hook installed'
    )
end

local function uninstallProcessMouseActionHook()
    local interface =
        modules.game_interface

    if originalProcessMouseAction and
       interface and
       interface.processMouseAction ==
           hookedProcessMouseAction then
        interface.processMouseAction =
            originalProcessMouseAction
    end

    originalProcessMouseAction = nil
    hookedProcessMouseAction = nil
    clearArmedSource()
end

-- Destination backpack ------------------------------------------------------

local function getEquippedBackpack()
    local player =
        g_game.getLocalPlayer()

    if not player then
        return nil
    end

    local backpack =
        player:getInventoryItem(
            InventorySlotBack
        )

    if backpack and backpack:isContainer() then
        return backpack
    end

    return nil
end

local function findContainerById(containerId)
    if containerId == nil then
        return nil
    end

    for _, container in pairs(
        g_game.getContainers()
    ) do
        if container:getId() == containerId then
            return container
        end
    end

    return nil
end

local function containerMatchesBackpack(
    container,
    backpack
)
    if not container or not backpack then
        return false
    end

    local item =
        container:getContainerItem()

    return item and
        item:getId() == backpack:getId()
end

local function pinBackpackContainer(
    container,
    reason
)
    if not container then
        return
    end

    preferredBackpackContainerId =
        container:getId()

    g_logger.info(string.format(
        '[Fibula AutoLoot] pinned backpack destination: cid=%d item=%d reason=%s',
        container:getId(),
        container:getContainerItem()
            and container:getContainerItem():getId()
            or -1,
        reason or 'unknown'
    ))
end

local function findOpenBackpack(backpack)
    if not backpack then
        return nil
    end

    if preferredBackpackContainerId ~= nil then
        local pinned =
            findContainerById(
                preferredBackpackContainerId
            )

        if pinned and
           containerMatchesBackpack(
               pinned,
               backpack
           ) then
            return pinned
        end

        preferredBackpackContainerId = nil
    end

    for _, container in pairs(
        g_game.getContainers()
    ) do
        if containersBeforeSource[
               container:getId()
           ] and
           not container:hasParent() and
           containerMatchesBackpack(
               container,
               backpack
           ) then
            pinBackpackContainer(
                container,
                'pre-existing root backpack'
            )

            return container
        end
    end

    return nil
end

local function describeOpenContainers()
    local parts = {}

    for _, container in pairs(
        g_game.getContainers()
    ) do
        local item =
            container:getContainerItem()

        if item then
            table.insert(
                parts,
                string.format(
                    'cid=%d item=%d parent=%s beforeSource=%s name=%s',
                    container:getId(),
                    item:getId(),
                    tostring(
                        container:hasParent()
                    ),
                    tostring(
                        containersBeforeSource[
                            container:getId()
                        ] == true
                    ),
                    tostring(
                        container:getName()
                    )
                )
            )
        end
    end

    if #parts == 0 then
        return '<none>'
    end

    return table.concat(parts, ' | ')
end

-- Loot traversal -------------------------------------------------------------

local function shouldLoot(item)
    if not item or item:isContainer() then
        return false
    end

    rememberItem(item)
    return not ignoredLookup[item:getId()]
end

local function findDestinationPosition(
    target,
    item
)
    if not target or not item then
        return nil
    end

    if item:isStackable() then
        local count = item:getCount()

        for index, targetItem in ipairs(
            target:getItems()
        ) do
            if targetItem:getId() ==
                   item:getId() and
               targetItem:getCount() < 100 then
                return target:getSlotPosition(
                    index - 1
                ), count
            end
        end
    end

    if target:getItemsCount() >=
       target:getCapacity() then
        return nil
    end

    local count =
        item:isStackable()
        and item:getCount()
        or 1

    return target:getSlotPosition(
        target:getItemsCount()
    ), count
end

local function scanKnownItems(container)
    local changed = false

    for _, item in ipairs(
        container:getItems()
    ) do
        if not item:isContainer() and
           rememberItem(item) then
            changed = true
        end
    end

    if changed then
        AutoLoot.refreshWindow()
    end

    refreshContainerMarkers()
end

local function frameContainsContainer(
    container
)
    for _, frame in ipairs(
        traversalFrames
    ) do
        if frame.container == container then
            return true
        end
    end

    return false
end

local function clearTraversal()
    traversalFrames = {}
    pendingNestedOpen = nil
    pendingParentReturn = nil
    ignoreClose = {}
end

local function finishLoot(message)
    local root =
        traversalFrames[1]
            and traversalFrames[1].container
            or nil

    lootRunId = lootRunId + 1

    clearTraversal()
    pendingRootSource = nil
    awaitingBackpackOpen = false

    if root and
       AutoLoot.settings.closeSource then
        pcall(function()
            g_game.close(root)
        end)
    end

    if message then
        setStatus(message)
    end
end

local processLoot

local function collectChildSlots(frame)
    frame.childSlots = {}
    frame.childIndex = 1

    -- This is done only AFTER all moveable ordinary items
    -- in this container have been processed. The remaining
    -- container slots therefore stay stable while we recurse.
    for slot = 0,
        frame.container:getCapacity() - 1 do

        local item =
            frame.container:getItem(slot)

        if item and item:isContainer() then
            table.insert(
                frame.childSlots,
                slot
            )
        end
    end
end

local function requestNextChild(
    frame,
    runId
)
    if not frame.childSlots then
        collectChildSlots(frame)
    end

    while frame.childIndex <=
          #frame.childSlots do

        local slot =
            frame.childSlots[
                frame.childIndex
            ]

        frame.childIndex =
            frame.childIndex + 1

        local item =
            frame.container:getItem(slot)

        if item and item:isContainer() then
            pendingNestedOpen = {
                runId = runId,
                parentFrame = frame,
                parentContainer =
                    frame.container,
                slot = slot,
                itemId = item:getId()
            }

            g_logger.info(string.format(
                '[Fibula AutoLoot] opening nested bag item=%d parentCid=%d slot=%d',
                item:getId(),
                frame.container:getId(),
                slot
            ))

            g_game.open(
                item,
                frame.container
            )

            scheduleEvent(function()
                if pendingNestedOpen and
                   pendingNestedOpen.runId ==
                       runId and
                   pendingNestedOpen.parentFrame ==
                       frame then

                    g_logger.info(string.format(
                        '[Fibula AutoLoot] nested bag open timed out: item=%d parentCid=%d',
                        pendingNestedOpen.itemId,
                        frame.container:getId()
                    ))

                    pendingNestedOpen = nil
                    processLoot(runId)
                end
            end, 1000)

            return true
        end
    end

    return false
end

local function requestParent(
    childFrame,
    runId
)
    local parentFrame =
        traversalFrames[
            #traversalFrames - 1
        ]

    if not parentFrame then
        finishLoot(
            'Auto loot finished'
        )
        return
    end

    pendingParentReturn = {
        runId = runId,
        childFrame = childFrame,
        childContainer =
            childFrame.container,
        parentFrame = parentFrame
    }

    g_logger.info(string.format(
        '[Fibula AutoLoot] returning to parent from cid=%d depth=%d',
        childFrame.container:getId(),
        #traversalFrames
    ))

    g_game.openParent(
        childFrame.container
    )

    scheduleEvent(function()
        if pendingParentReturn and
           pendingParentReturn.runId ==
               runId and
           pendingParentReturn.childFrame ==
               childFrame then

            g_logger.info(
                '[Fibula AutoLoot] parent return timed out'
            )

            finishLoot(
                'Nested loot stopped: could not return to parent'
            )
        end
    end, 1000)
end

processLoot = function(runId)
    if runId ~= lootRunId or
       not g_game.isOnline() then
        return
    end

    if pendingNestedOpen or
       pendingParentReturn then
        return
    end

    local target = activeTarget
    local frame =
        traversalFrames[
            #traversalFrames
        ]

    if not target or
       not frame or
       not frame.container then
        finishLoot('Loot stopped')
        return
    end

    local source = frame.container

    -- Loot one ordinary allowed item at a time.
    for _, item in ipairs(
        source:getItems()
    ) do
        if shouldLoot(item) and
           (item.fibulaAutoLootTries or 0) <
               3 then

            local toPosition, count =
                findDestinationPosition(
                    target,
                    item
                )

            if not toPosition then
                finishLoot(
                    'Backpack is full'
                )
                return
            end

            item.fibulaAutoLootTries =
                (item.fibulaAutoLootTries or 0) +
                1

            g_logger.info(string.format(
                '[Fibula AutoLoot] move item=%d count=%d sourceCid=%d -> targetCid=%d depth=%d',
                item:getId(),
                count,
                source:getId(),
                target:getId(),
                #traversalFrames
            ))

            g_game.move(
                item,
                toPosition,
                count
            )

            scheduleEvent(function()
                processLoot(runId)
            end, AutoLoot.settings.delay)

            return
        end
    end

    -- All normal items at this level are done.
    -- Now recurse into bags/containers.
    if requestNextChild(frame, runId) then
        return
    end

    if #traversalFrames > 1 then
        requestParent(frame, runId)
    else
        finishLoot(
            'Auto loot finished'
        )
    end
end

local function startLootWithTarget(
    rootSource,
    target
)
    clearTraversal()

    activeTarget = target
    pendingRootSource = nil
    awaitingBackpackOpen = false

    table.insert(
        traversalFrames,
        {
            container = rootSource,
            childSlots = nil,
            childIndex = 1
        }
    )

    scanKnownItems(rootSource)

    lootRunId = lootRunId + 1
    local runId = lootRunId

    g_logger.info(string.format(
        '[Fibula AutoLoot] destination backpack found: cid=%d item=%d parent=%s items=%d/%d',
        target:getId(),
        target:getContainerItem():getId(),
        tostring(target:hasParent()),
        target:getItemsCount(),
        target:getCapacity()
    ))

    setStatus(
        'Looting corpse and nested bags...'
    )

    scheduleEvent(function()
        processLoot(runId)
    end, 80)
end

local function beginLoot(
    rootSource,
    retry
)
    retry = retry or 0

    if not AutoLoot.settings.enabled or
       not g_game.isOnline() or
       not rootSource then
        return
    end

    local backpack =
        getEquippedBackpack()

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

    local target =
        findOpenBackpack(backpack)

    if target then
        startLootWithTarget(
            rootSource,
            target
        )
        return
    end

    if retry == 0 then
        awaitingBackpackOpen = true
        pendingRootSource = rootSource

        g_logger.info(string.format(
            '[Fibula AutoLoot] opening equipped backpack item %d',
            backpack:getId()
        ))

        g_game.open(backpack)
    end

    if retry >= 8 then
        awaitingBackpackOpen = false
        pendingRootSource = nil

        g_logger.info(string.format(
            '[Fibula AutoLoot] backpack lookup failed. equipped=%d openContainers=%s',
            backpack:getId(),
            describeOpenContainers()
        ))

        setStatus(
            'Could not find opened equipped backpack'
        )

        return
    end

    scheduleEvent(function()
        if pendingRootSource then
            beginLoot(
                rootSource,
                retry + 1
            )
        end
    end, 220)
end

-- Container events -----------------------------------------------------------

local function onContainerOpen(
    container,
    previousContainer
)
    if not AutoLoot.settings.enabled then
        return
    end

    -- Opening a nested container in this protocol commonly
    -- REUSES the parent's container id. OTClient creates the
    -- new Container, calls onOpen(previousContainer), then closes
    -- the previous object. Mark that following close as expected.
    if pendingNestedOpen and
       pendingNestedOpen.runId ==
           lootRunId then

        local expected =
            pendingNestedOpen

        local item =
            container:getContainerItem()

        local previousMatches =
            previousContainer and
            previousContainer ==
                expected.parentContainer

        local itemMatches =
            item and
            item:getId() ==
                expected.itemId

        if previousMatches or
           (container:hasParent() and
            itemMatches) then

            if previousContainer then
                ignoreClose[
                    previousContainer
                ] = true
            end

            pendingNestedOpen = nil

            table.insert(
                traversalFrames,
                {
                    container = container,
                    childSlots = nil,
                    childIndex = 1
                }
            )

            g_logger.info(string.format(
                '[Fibula AutoLoot] nested bag opened: cid=%d item=%d depth=%d items=%d/%d previousCid=%s',
                container:getId(),
                item and item:getId() or -1,
                #traversalFrames,
                container:getItemsCount(),
                container:getCapacity(),
                previousContainer
                    and tostring(
                        previousContainer:getId()
                    )
                    or 'nil'
            ))

            scanKnownItems(container)

            -- Let Game::processOpenContainer finish its expected close of the
            -- previous container before we start moving the child contents.
            scheduleEvent(function()
                if lootRunId > 0 and
                   traversalFrames[#traversalFrames] and
                   traversalFrames[#traversalFrames].container == container then

                    g_logger.info(string.format(
                        '[Fibula AutoLoot] processing nested bag: cid=%d depth=%d items=%d',
                        container:getId(),
                        #traversalFrames,
                        container:getItemsCount()
                    ))

                    processLoot(lootRunId)
                end
            end, 140)

            return
        end
    end

    -- After a nested bag is finished, g_game.openParent()
    -- reopens the parent into the SAME container id. Again,
    -- previousContainer is closed immediately after this event.
    if pendingParentReturn and
       pendingParentReturn.runId ==
           lootRunId then

        local expected =
            pendingParentReturn

        local previousMatches =
            previousContainer and
            previousContainer ==
                expected.childContainer

        if previousMatches or
           (
               previousContainer and
               previousContainer:getId() ==
                   expected.childContainer:getId()
           ) then

            if previousContainer then
                ignoreClose[
                    previousContainer
                ] = true
            end

            pendingParentReturn = nil

            -- Child frame is still the last frame.
            table.remove(
                traversalFrames,
                #traversalFrames
            )

            expected.parentFrame.container =
                container

            g_logger.info(string.format(
                '[Fibula AutoLoot] parent reopened: cid=%d depth=%d',
                container:getId(),
                #traversalFrames
            ))

            scanKnownItems(container)

            scheduleEvent(function()
                processLoot(lootRunId)
            end, 60)

            return
        end
    end

    local backpack =
        getEquippedBackpack()

    if awaitingBackpackOpen and
       pendingRootSource and
       backpack and
       container ~= pendingRootSource and
       containerMatchesBackpack(
           container,
           backpack
       ) then

        pinBackpackContainer(
            container,
            'explicit equipped-backpack open'
        )

        awaitingBackpackOpen = false

        local root =
            pendingRootSource

        scheduleEvent(function()
            if root then
                beginLoot(root, 1)
            end
        end, 60)

        return
    end

    -- User manually opened their root backpack.
    if not pendingRootSource and
       backpack and
       not previousContainer and
       not container:hasParent() and
       containerMatchesBackpack(
           container,
           backpack
       ) then

        pinBackpackContainer(
            container,
            'manual root backpack open'
        )
    end

    -- Root corpse/container opened from the explicit map click.
    if armedSourceId and
       g_clock.millis() <= armedUntil then

        local containerItem =
            container:getContainerItem()

        if containerItem and
           containerItem:getId() ==
               armedSourceId then

            clearArmedSource()

            setStatus(string.format(
                'Right-click source opened: item %d',
                containerItem:getId()
            ))

            beginLoot(container, 0)
            return
        end
    end

    if armedSourceId and
       g_clock.millis() > armedUntil then
        clearArmedSource()
    end
end

local function abortTraversal(reason)
    lootRunId = lootRunId + 1
    clearTraversal()
    pendingRootSource = nil
    awaitingBackpackOpen = false

    if reason then
        setStatus(reason)
    end
end

local function onContainerClose(container)
    -- The equipped backpack is the only close that must abort an active loot
    -- pass. It is a stable destination container (normally cid=0).
    if activeTarget == container then
        if preferredBackpackContainerId == container:getId() then
            preferredBackpackContainerId = nil
        end

        activeTarget = nil
        abortTraversal(
            'Loot stopped: backpack closed'
        )
        return
    end

    if preferredBackpackContainerId == container:getId() then
        preferredBackpackContainerId = nil
    end

    -- IMPORTANT FOR 7.72 / FIBULA:
    --
    -- Opening a nested bag commonly reuses the SAME server container id as
    -- its parent. Game::processOpenContainer installs the new Container first,
    -- calls newContainer:onOpen(previousContainer), and then calls
    -- previousContainer:onClose().
    --
    -- Lua userdata identity for that previous container is not reliable enough
    -- for an ignoreClose[userdata] table. The previous 4A.6 implementation
    -- therefore sometimes interpreted the protocol's expected replacement
    -- close as a manual close and killed the traversal immediately after the
    -- nested bag appeared.
    --
    -- While traversal is active, a close matching ANY current source frame by
    -- object OR by container id is treated as a navigation/replacement close.
    -- We do not abort. The newly opened child/parent frame remains authoritative.
    if #traversalFrames > 0 then
        local closingId = container:getId()

        for _, frame in ipairs(traversalFrames) do
            if frame.container == container or
               (frame.container and frame.container:getId() == closingId) then

                ignoreClose[container] = nil

                g_logger.info(string.format(
                    '[Fibula AutoLoot] ignored source/navigation close: cid=%d depth=%d',
                    closingId,
                    #traversalFrames
                ))

                return
            end
        end
    end

    -- Keep the old exact-object guard as a harmless fallback for any close
    -- that was explicitly tagged during onOpen().
    if ignoreClose[container] then
        ignoreClose[container] = nil

        g_logger.info(string.format(
            '[Fibula AutoLoot] ignored tagged replacement close: cid=%d',
            container:getId()
        ))

        return
    end
end

-- Lifecycle -----------------------------------------------------------------

local function bindKeys()
    if boundRoot then
        return
    end

    boundRoot =
        modules.game_interface.getRootPanel()

    if not boundRoot then
        return
    end

    g_keyboard.bindKeyDown(
        'Ctrl+Shift+L',
        AutoLoot.toggleWindow,
        boundRoot
    )
end

local function unbindKeys()
    if not boundRoot then
        return
    end

    g_keyboard.unbindKeyDown(
        'Ctrl+Shift+L',
        AutoLoot.toggleWindow,
        boundRoot
    )

    boundRoot = nil
end

local function onGameStart()
    loadSettings()
    buildWindow()
    AutoLoot.refreshWindow()
    bindKeys()

    preferredBackpackContainerId = nil
    containersBeforeSource = {}
    pendingRootSource = nil
    awaitingBackpackOpen = false
    clearTraversal()

    setStatus(
        'Ready - Default Loot; Ctrl+right-click toggles Never Loot'
    )
end

local function onGameEnd()
    lootRunId = lootRunId + 1
    activeTarget = nil
    pendingRootSource = nil
    awaitingBackpackOpen = false
    preferredBackpackContainerId = nil
    containersBeforeSource = {}
    clearArmedSource()
    clearTraversal()
    saveSettings()

    if window then
        window:hide()
    end
end

function AutoLoot.init()
    loadDefaults()
    buildWindow()
    installUIItemHooks()
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
    uninstallUIItemHooks()
    uninstallProcessMouseActionHook()

    if window and not window:isDestroyed() then
        window:destroy()
    end

    window = nil
    activeTarget = nil
    pendingRootSource = nil
end
