FibulaLootFeedback = {}

local holder = nil
local entries = {}
local pending = {}

local originalMove = nil
local hookedMove = nil

local WIDTH = 360
local ROW_HEIGHT = 34
local GAP = 4
local MAX_ROWS = 4
local HOLDER_HEIGHT = MAX_ROWS * ROW_HEIGHT + (MAX_ROWS - 1) * GAP
local HOLD_MS = 3200
local FADE_MS = 450
local PENDING_TTL = 1800

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

local function now()
    return g_clock.millis()
end

local function decodeContainerId(position)
    if not position then
        return nil
    end

    local x = tonumber(position.x)
    local y = tonumber(position.y)

    -- Container::getSlotPosition() uses:
    --   { 0xffff, containerId | 0x40, slot }
    if x ~= 65535 or not y or y < 64 or y >= 128 then
        return nil
    end

    return y - 64
end

local function getMapRoot()
    if modules.game_interface and modules.game_interface.getRootPanel then
        return modules.game_interface.getRootPanel()
    end
    return nil
end

local function buildUi()
    if holder and not holder:isDestroyed() then
        return true
    end

    local root = getMapRoot()
    if not root then
        return false
    end

    holder = g_ui.createWidget('Panel', root)
    holder:setId('fibulaLootToastHolder')
    holder:setPhantom(true)
    holder:setBackgroundColor('#00000000')
    holder:setBorderWidth(0)

    holder:breakAnchors()
    holder:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    holder:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    holder:setMarginBottom(150)
    holder:setSize({ width = WIDTH, height = HOLDER_HEIGHT })
    holder:show()
    holder:raise()

    return true
end

local function cancelEntryEvents(entry)
    if not entry then
        return
    end

    if entry.hideEvent then
        removeEvent(entry.hideEvent)
        entry.hideEvent = nil
    end

    if entry.destroyEvent then
        removeEvent(entry.destroyEvent)
        entry.destroyEvent = nil
    end

    if entry.widget and entry.widget.fadeEvent then
        removeEvent(entry.widget.fadeEvent)
        entry.widget.fadeEvent = nil
    end
end

local function relayout()
    if not holder or holder:isDestroyed() then
        return
    end

    local count = #entries

    for index, entry in ipairs(entries) do
        local widget = entry.widget
        if widget and not widget:isDestroyed() then
            local fromBottom = count - index
            local y = HOLDER_HEIGHT - ROW_HEIGHT - fromBottom * (ROW_HEIGHT + GAP)

            widget:breakAnchors()
            widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            widget:addAnchor(AnchorTop, 'parent', AnchorTop)
            widget:setMarginLeft(0)
            widget:setMarginTop(y)
            widget:setSize({ width = WIDTH, height = ROW_HEIGHT })
            widget:raise()
        end
    end
end

local function removeEntry(entry)
    if not entry then
        return
    end

    cancelEntryEvents(entry)
    table.removevalue(entries, entry)

    if entry.widget and not entry.widget:isDestroyed() then
        entry.widget:destroy()
    end

    relayout()
end

local function clearEntries()
    local copy = {}
    for _, entry in ipairs(entries) do
        table.insert(copy, entry)
    end

    for _, entry in ipairs(copy) do
        removeEntry(entry)
    end

    entries = {}
end

local function prunePending()
    local cutoff = now() - PENDING_TTL

    for i = #pending, 1, -1 do
        if pending[i].createdAt < cutoff then
            g_logger.info(string.format(
                '[Fibula Loot] pending expired item=%d requested=%d sourceCid=%s targetCid=%s',
                pending[i].itemId,
                pending[i].requestedCount,
                tostring(pending[i].sourceCid),
                tostring(pending[i].targetCid)
            ))
            table.remove(pending, i)
        end
    end
end

local function itemDisplayName(itemId, item)
    local name = safe(function()
        return item:getName()
    end, '')

    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')

    if name ~= '' and name:lower() ~= 'item' then
        return name
    end

    local thingType = safe(function()
        return g_things.getThingType(itemId, ThingCategoryItem)
    end)

    if thingType then
        local thingName = safe(function()
            return thingType:getName()
        end, '')

        thingName = tostring(thingName or ''):gsub('^%s+', ''):gsub('%s+$', '')

        if thingName ~= '' and thingName:lower() ~= 'item' then
            return thingName
        end
    end

    return string.format('Item #%d', itemId)
end

local function makeLabel(parent, id, text, x, width, color, font)
    local label = g_ui.createWidget('Label', parent)
    label:setId(id)
    label:setText(text)
    label:setColor(color)
    label:setFont(font or 'verdana-11px-rounded')
    label:setTextAlign(AlignLeft)
    label:setPhantom(true)

    label:breakAnchors()
    label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    label:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    label:setMarginLeft(x)
    label:setWidth(width)
    label:setHeight(20)

    return label
end

local function logToServerTab(text)
    local console = modules.game_console
    if not console or not console.addText then
        g_logger.warning('[Fibula Loot] game_console.addText unavailable')
        return
    end

    local speakType = {
        color = '#d8d2c2'
    }

    local ok, err = pcall(function()
        console.addText(text, speakType, tr('Server Log'))
    end)

    if not ok then
        g_logger.error('[Fibula Loot] Server Log write failed: ' .. tostring(err))
    end
end

local function showToast(itemId, count, name)
    if not buildUi() then
        g_logger.warning('[Fibula Loot] toast UI root unavailable')
        return
    end

    while #entries >= MAX_ROWS do
        removeEntry(entries[1])
    end

    local widget = g_ui.createWidget('Panel', holder)
    widget:setId('fibulaLootToast')
    widget:setPhantom(false)
    widget:setBackgroundColor('#071019ed')
    widget:setBorderWidth(1)
    widget:setBorderColor('#4d625e')
    widget:setTooltip(string.format('Looted %dx %s (Client ID %d)', count, name, itemId))

    local accent = g_ui.createWidget('Panel', widget)
    accent:setPhantom(true)
    accent:setBackgroundColor('#6f8d86')
    accent:setBorderWidth(0)
    accent:breakAnchors()
    accent:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    accent:addAnchor(AnchorTop, 'parent', AnchorTop)
    accent:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    accent:setWidth(3)

    local itemWidget = g_ui.createWidget('UIItem', widget)
    itemWidget:setId('lootItem')
    itemWidget:setPhantom(true)
    itemWidget:setVirtual(true)
    itemWidget:setItemId(itemId)
    itemWidget:setItemCount(count)
    itemWidget:setShowCount(true)
    itemWidget:breakAnchors()
    itemWidget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    itemWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemWidget:setMarginLeft(8)
    itemWidget:setSize({ width = 30, height = 30 })

    makeLabel(
        widget,
        'lootType',
        'LOOT',
        44,
        42,
        '#a9c3bc',
        'verdana-10px-rounded'
    )

    local display = string.format('%dx %s', count, name)
    if #display > 48 then
        display = display:sub(1, 45) .. '...'
    end

    makeLabel(
        widget,
        'lootText',
        display,
        88,
        WIDTH - 98,
        '#eee8d8',
        'verdana-11px-rounded'
    )

    widget:setOpacity(0)

    local entry = {
        widget = widget
    }

    table.insert(entries, entry)
    relayout()

    if g_effects and g_effects.fadeIn then
        g_effects.fadeIn(widget, 120)
    else
        widget:setOpacity(1)
    end

    entry.hideEvent = scheduleEvent(function()
        entry.hideEvent = nil

        if not entry.widget or entry.widget:isDestroyed() then
            return
        end

        if g_effects and g_effects.fadeOut then
            g_effects.fadeOut(entry.widget, FADE_MS)
        else
            entry.widget:setOpacity(0)
        end

        entry.destroyEvent = scheduleEvent(function()
            entry.destroyEvent = nil
            removeEntry(entry)
        end, FADE_MS + 40)
    end, HOLD_MS)
end

local function isAutoLootMove(item)
    if not item then
        return false
    end

    local tries = safe(function()
        return item.fibulaAutoLootTries
    end, nil)

    return tonumber(tries) ~= nil and tonumber(tries) > 0
end

local function addPending(item, toPosition, count)
    local itemId = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    if itemId <= 0 then
        return
    end

    local requestedCount = tonumber(count) or tonumber(safe(function()
        return item:getCount()
    end, 1)) or 1

    local sourcePos = safe(function()
        return item:getPosition()
    end, nil)

    local record = {
        itemId = itemId,
        requestedCount = math.max(1, requestedCount),
        sourceCid = decodeContainerId(sourcePos),
        targetCid = decodeContainerId(toPosition),
        name = itemDisplayName(itemId, item),
        createdAt = now()
    }

    table.insert(pending, record)
    prunePending()

    g_logger.info(string.format(
        '[Fibula Loot] pending item=%d requested=%d sourceCid=%s targetCid=%s',
        record.itemId,
        record.requestedCount,
        tostring(record.sourceCid),
        tostring(record.targetCid)
    ))
end

local function takePending(container, itemId)
    prunePending()

    local cid = tonumber(safe(function()
        return container:getId()
    end, -1))

    for index, record in ipairs(pending) do
        if record.itemId == itemId and
           (record.targetCid == nil or record.targetCid == cid) then
            table.remove(pending, index)
            return record, cid
        end
    end

    return nil, cid
end

local function confirm(container, item, acquired, source)
    if not container or not item then
        return
    end

    local itemId = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    acquired = tonumber(acquired) or 0

    if itemId <= 0 or acquired <= 0 then
        return
    end

    local record, cid = takePending(container, itemId)
    if not record then
        return
    end

    -- Never report more than the server-side destination event confirms.
    acquired = math.max(1, acquired)

    showToast(itemId, acquired, record.name)
    logToServerTab(string.format('Looted: %dx %s', acquired, record.name))

    g_logger.info(string.format(
        '[Fibula Loot] confirmed %s item=%d count=%d targetCid=%s',
        source,
        itemId,
        acquired,
        tostring(cid)
    ))
end

local function onContainerAddItem(container, slot, item)
    if not item then
        return
    end

    local count = tonumber(safe(function()
        return item:getCount()
    end, 1)) or 1

    confirm(container, item, count, 'container-add')
end

local function onContainerUpdateItem(container, slot, item, oldItem)
    if not item then
        return
    end

    local itemId = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    local newCount = tonumber(safe(function()
        return item:getCount()
    end, 1)) or 1

    local oldId = tonumber(safe(function()
        return oldItem:getId()
    end, 0)) or 0

    local oldCount = tonumber(safe(function()
        return oldItem:getCount()
    end, 0)) or 0

    local delta = newCount

    if oldItem and oldId == itemId then
        delta = newCount - oldCount
    end

    if delta > 0 then
        confirm(container, item, delta, 'container-update')
    end
end

local function installMoveHook()
    if originalMove or type(g_game.move) ~= 'function' then
        return
    end

    originalMove = g_game.move

    hookedMove = function(item, toPosition, count)
        if isAutoLootMove(item) then
            addPending(item, toPosition, count)
        end

        return originalMove(item, toPosition, count)
    end

    g_game.move = hookedMove
    g_logger.info('[Fibula Loot] AutoLoot move correlation hook installed')
end

local function uninstallMoveHook()
    if originalMove and g_game.move == hookedMove then
        g_game.move = originalMove
    end

    originalMove = nil
    hookedMove = nil
end

local function onGameStart()
    pending = {}
    clearEntries()
    scheduleEvent(buildUi, 150)
end

local function onGameEnd()
    pending = {}
    clearEntries()
end

function FibulaLootFeedback.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    connect(Container, {
        onAddItem = onContainerAddItem,
        onUpdateItem = onContainerUpdateItem
    })

    installMoveHook()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Loot] destination container observer installed')
    g_logger.info('[Fibula Loot] UI 5G.3 server-confirmed container feedback ready')
end

function FibulaLootFeedback.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    disconnect(Container, {
        onAddItem = onContainerAddItem,
        onUpdateItem = onContainerUpdateItem
    })

    uninstallMoveHook()
    pending = {}
    clearEntries()

    if holder and not holder:isDestroyed() then
        holder:destroy()
    end

    holder = nil
end
