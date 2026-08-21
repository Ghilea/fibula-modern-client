FibulaLootFeedback = {}

local holder = nil
local entries = {}

local originalMove = nil
local hookedMove = nil

local WIDTH = 360
local ROW_HEIGHT = 34
local GAP = 4
local MAX_ROWS = 4
local HOLDER_HEIGHT = MAX_ROWS * ROW_HEIGHT + (MAX_ROWS - 1) * GAP
local HOLD_MS = 3200
local FADE_MS = 450

local pendingSeq = 0

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then
        return value
    end
    return fallback
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
    if not entry then return end

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
    if not entry then return end

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
        return
    end

    local speakType = {
        color = '#d8d2c2'
    }

    pcall(function()
        console.addText(text, speakType, tr('Server Log'))
    end)
end

local function showToast(itemId, count, name)
    if not buildUi() then
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

local function playerItemCount(itemId, tier)
    local player = g_game.getLocalPlayer()
    if not player or not player.getInventoryCount then
        return nil
    end

    return tonumber(safe(function()
        return player:getInventoryCount(itemId, tier or 0)
    end))
end

local function isAutoLootMove(item)
    if not item then
        return false
    end

    -- This field is written by the existing, already-working AutoLoot module
    -- immediately before it calls g_game.move(). We only OBSERVE it here.
    local tries = safe(function()
        return item.fibulaAutoLootTries
    end, nil)

    return tonumber(tries) ~= nil and tonumber(tries) > 0
end

local function installMoveHook()
    if originalMove or type(g_game.move) ~= 'function' then
        return
    end

    originalMove = g_game.move

    hookedMove = function(item, toPosition, count)
        local autoLoot = isAutoLootMove(item)

        if not autoLoot then
            return originalMove(item, toPosition, count)
        end

        local itemId = tonumber(safe(function()
            return item:getId()
        end, 0)) or 0

        local tier = tonumber(safe(function()
            return item:getTier()
        end, 0)) or 0

        local requestedCount = tonumber(count) or tonumber(safe(function()
            return item:getCount()
        end, 1)) or 1

        requestedCount = math.max(1, requestedCount)

        local name = itemDisplayName(itemId, item)
        local before = playerItemCount(itemId, tier)

        pendingSeq = pendingSeq + 1
        local seq = pendingSeq

        local result = originalMove(item, toPosition, count)

        -- Confirm from actual player inventory state rather than displaying an
        -- attempted move immediately. This makes the toast describe loot that
        -- really reached the player's inventory.
        scheduleEvent(function()
            if seq > pendingSeq or not g_game.isOnline() then
                return
            end

            local after = playerItemCount(itemId, tier)
            local acquired = nil

            if before ~= nil and after ~= nil then
                acquired = after - before
            end

            if acquired and acquired > 0 then
                local text = string.format('Looted: %dx %s', acquired, name)
                showToast(itemId, acquired, name)
                logToServerTab(text)

                g_logger.info(string.format(
                    '[Fibula Loot] confirmed autoloot item=%d count=%d',
                    itemId,
                    acquired
                ))
                return
            end

            -- Some old-client inventory-count paths can lag a little when a
            -- stack is merged. One delayed retry avoids false negatives.
            scheduleEvent(function()
                if not g_game.isOnline() then
                    return
                end

                local retryAfter = playerItemCount(itemId, tier)
                local retryAcquired = nil

                if before ~= nil and retryAfter ~= nil then
                    retryAcquired = retryAfter - before
                end

                if retryAcquired and retryAcquired > 0 then
                    local text = string.format('Looted: %dx %s', retryAcquired, name)
                    showToast(itemId, retryAcquired, name)
                    logToServerTab(text)

                    g_logger.info(string.format(
                        '[Fibula Loot] confirmed delayed autoloot item=%d count=%d',
                        itemId,
                        retryAcquired
                    ))
                else
                    g_logger.info(string.format(
                        '[Fibula Loot] autoloot move observed but inventory delta unavailable: item=%d requested=%d',
                        itemId,
                        requestedCount
                    ))
                end
            end, 180)
        end, 90)

        return result
    end

    g_game.move = hookedMove
    g_logger.info('[Fibula Loot] AutoLoot move observer installed')
end

local function uninstallMoveHook()
    if originalMove and g_game.move == hookedMove then
        g_game.move = originalMove
    end

    originalMove = nil
    hookedMove = nil
end

local function onGameStart()
    clearEntries()
    scheduleEvent(buildUi, 150)
end

local function onGameEnd()
    clearEntries()
end

function FibulaLootFeedback.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    installMoveHook()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Loot] UI 5G.2 AutoLoot feedback ready')
end

function FibulaLootFeedback.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    uninstallMoveHook()
    clearEntries()

    if holder and not holder:isDestroyed() then
        holder:destroy()
    end

    holder = nil
end
