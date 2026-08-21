FibulaTooltips = {}

local refreshEvent = nil
local styledTooltip = false
local REFRESH_MS = 550

local ACTION_FALLBACK = {
    [1] = 'Self',
    [2] = 'Target',
    [3] = 'Crosshair',
    [9] = 'Cursor'
}

local ACTION_LABELS = {
    Equip = 'Equip',
    Use = 'Use',
    UseOnYourself = 'Self',
    UseOnTarget = 'Target',
    SelectUseTarget = 'Crosshair',
    UseAtCursorPosition = 'Cursor',
    chatText = 'Cast / text',
    specialAction = 'Special action'
}

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

local function cleanText(value)
    if value == nil then
        return ''
    end

    local text = tostring(value)
    text = text:gsub('\r', '')
    text = text:gsub('^%s+', '')
    text = text:gsub('%s+$', '')
    return text
end

local function addLine(lines, label, value)
    value = cleanText(value)
    if value == '' then
        return
    end

    if label and label ~= '' then
        table.insert(lines, label .. ': ' .. value)
    else
        table.insert(lines, value)
    end
end

local function formatSeconds(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then
        return nil
    end

    local seconds = ms / 1000
    if math.floor(seconds) == seconds then
        return string.format('%d s', seconds)
    end

    return string.format('%.1f s', seconds)
end

local function itemName(item)
    if not item then
        return ''
    end

    local name = cleanText(safe(function()
        return item:getName()
    end, ''))

    if name ~= '' and name:lower() ~= 'item' then
        return name
    end

    local id = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    if id > 0 and g_things and g_things.getThingType then
        local thingType = safe(function()
            return g_things.getThingType(id, ThingCategoryItem)
        end)

        if thingType then
            name = cleanText(safe(function()
                return thingType:getName()
            end, ''))

            if name ~= '' and name:lower() ~= 'item' then
                return name
            end
        end
    end

    if id > 0 then
        return string.format('Item #%d', id)
    end

    return 'Item'
end

local function itemNativeDescription(item)
    if not item then
        return ''
    end

    local text = cleanText(safe(function()
        return item:getTooltip()
    end, ''))

    if #text > 420 then
        text = text:sub(1, 417) .. '...'
    end

    return text
end

local function buildItemTooltip(item)
    if not item then
        return nil
    end

    local id = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    if id <= 0 then
        return nil
    end

    local lines = {}
    table.insert(lines, itemName(item))

    local stackable = safe(function()
        return item:isStackable()
    end, false)

    local count = tonumber(safe(function()
        return item:getCount()
    end, 1)) or 1

    if stackable or count > 1 then
        addLine(lines, 'Count', count)
    end

    if safe(function() return item:isContainer() end, false) then
        addLine(lines, 'Type', 'Container')
    elseif safe(function() return item:isFluidContainer() end, false) then
        addLine(lines, 'Type', 'Fluid container')
    end

    local native = itemNativeDescription(item)
    local title = cleanText(lines[1])

    -- Old 7.72 normally has no extended item tooltip packet. If another
    -- source has already populated one, preserve it rather than invent stats.
    if native ~= '' and native ~= title then
        table.insert(lines, '')
        table.insert(lines, native)
    end

    addLine(lines, 'Client ID', id)

    return table.concat(lines, '\n')
end

local function actionName(cache)
    if not cache then
        return nil
    end

    local actionbar = modules and modules.game_actionbar
    local raw = nil

    if actionbar and actionbar.getActionName then
        raw = safe(function()
            return actionbar.getActionName(cache.actionType)
        end)
    end

    if raw and ACTION_LABELS[raw] then
        return ACTION_LABELS[raw]
    end

    if raw and cleanText(raw) ~= '' then
        return cleanText(raw)
    end

    return ACTION_FALLBACK[tonumber(cache.actionType)]
end

local function actionItemCount(button, cache)
    if not button or not cache then
        return nil
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local itemId = tonumber(cache.itemId) or 0
    if itemId <= 0 and button.item then
        itemId = tonumber(safe(function()
            return button.item:getItemId()
        end, 0)) or 0
    end

    if itemId <= 0 then
        return nil
    end

    local tier = tonumber(cache.upgradeTier) or 0

    return tonumber(safe(function()
        return player:getInventoryCount(itemId, tier)
    end))
end

local function buildActionTooltip(button)
    if not button or not button.item then
        return nil
    end

    local cache = button.cache or {}
    local item = safe(function()
        return button.item:getItem()
    end)

    local spell = cache.spellData
    local title = ''

    if spell then
        title = cleanText(spell.name)
    end

    if title == '' and item then
        title = itemName(item)
    end

    if title == '' then
        title = cleanText(cache.param)
    end

    if title == '' then
        title = 'Action'
    end

    local lines = { title }

    if cache.isSpell then
        local words = cleanText(spell and spell.words or cache.param)
        addLine(lines, 'Words', words)

        if spell then
            if tonumber(spell.level) and tonumber(spell.level) > 0 then
                addLine(lines, 'Level', spell.level)
            end
            if tonumber(spell.mana) and tonumber(spell.mana) > 0 then
                addLine(lines, 'Mana', spell.mana)
            end
            if tonumber(spell.soul) and tonumber(spell.soul) > 0 then
                addLine(lines, 'Soul', spell.soul)
            end
            local cooldown = formatSeconds(spell.exhaustion)
            if cooldown then
                addLine(lines, 'Cooldown', cooldown)
            end
        end
    elseif cache.isRuneSpell and spell then
        -- The spell table attached to a rune item describes its CONJURE spell,
        -- not the rune-use cost. Label it explicitly so old Tibia data is not
        -- presented as something it is not.
        addLine(lines, 'Rune', spell.name)

        if cleanText(spell.words) ~= '' then
            addLine(lines, 'Conjure', spell.words)
        end
    end

    local action = actionName(cache)
    if action then
        addLine(lines, 'Action', action)
    end

    local hotkey = cleanText(cache.hotkey)
    if hotkey ~= '' then
        addLine(lines, 'Hotkey', hotkey)
    end

    local count = actionItemCount(button, cache)
    if count ~= nil and (tonumber(cache.itemId) or 0) > 0 then
        addLine(lines, 'Carried', count)
    end

    if not cache.isSpell and not cache.isRuneSpell and item then
        local native = itemNativeDescription(item)
        if native ~= '' and native ~= title then
            table.insert(lines, '')
            table.insert(lines, native)
        end
    end

    return table.concat(lines, '\n')
end

local function rememberAndSet(widget, text, kind)
    if not widget or not text or text == '' then
        return
    end

    if widget.fibulaTooltipOriginalCaptured ~= true then
        widget.fibulaTooltipOriginal = safe(function()
            return widget:getTooltip()
        end)
        widget.fibulaTooltipOriginalCaptured = true
    end

    widget.fibulaTooltipOwned = true
    widget.fibulaTooltipKind = kind
    widget:setTooltip(text)
end

local function styleNativeTooltip()
    if not rootWidget then
        return
    end

    local label = safe(function()
        return rootWidget:recursiveGetChildById('toolTip')
    end)

    if not label then
        return
    end

    label:setBackgroundColor('#071019f4')
    label:setColor('#e8e1cf')
    label:setBorderColor('#7a633d')
    label:setBorderWidth(1)
    label:setFont('verdana-11px-rounded')
    label:setTextAlign(AlignLeft)
    label:setTextOffset(topoint('5 3'))

    styledTooltip = true
end

local function polishActionbars(actionWidgets)
    local actionbar = modules and modules.game_actionbar
    if not actionbar then
        return
    end

    for _, bar in pairs(actionbar.actionBars or {}) do
        if bar and bar.tabBar then
            for _, button in pairs(bar.tabBar:getChildren()) do
                if button and button.item then
                    actionWidgets[button.item] = true

                    local tooltip = buildActionTooltip(button)
                    if tooltip then
                        rememberAndSet(button.item, tooltip, 'action')
                    end
                end
            end
        end
    end
end

local function scanItems(widget, actionWidgets, depth)
    if not widget or depth > 18 then
        return
    end

    if widget:getClassName() == 'UIItem' and not actionWidgets[widget] then
        local item = safe(function()
            return widget:getItem()
        end)

        if item then
            local tooltip = buildItemTooltip(item)
            if tooltip then
                rememberAndSet(widget, tooltip, 'item')
            end
        end
    end

    for _, child in pairs(widget:getChildren() or {}) do
        scanItems(child, actionWidgets, depth + 1)
    end
end

function FibulaTooltips.refresh()
    if not g_game.isOnline() then
        return
    end

    styleNativeTooltip()

    local actionWidgets = {}
    polishActionbars(actionWidgets)

    local gameRoot = modules.game_interface and
        modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil

    if gameRoot then
        scanItems(gameRoot, actionWidgets, 0)
    end
end

local function startRefresh()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end

    local function tick()
        FibulaTooltips.refresh()
        refreshEvent = scheduleEvent(tick, REFRESH_MS)
    end

    refreshEvent = scheduleEvent(tick, 180)
end

local function onGameStart()
    scheduleEvent(function()
        FibulaTooltips.refresh()
        startRefresh()
    end, 350)
end

local function onGameEnd()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end
end

local function restoreWidgets(widget, depth)
    if not widget or depth > 18 then
        return
    end

    if widget.fibulaTooltipOwned then
        if widget.fibulaTooltipOriginal and
           cleanText(widget.fibulaTooltipOriginal) ~= '' then
            widget:setTooltip(widget.fibulaTooltipOriginal)
        else
            widget:removeTooltip()
        end

        widget.fibulaTooltipOwned = nil
        widget.fibulaTooltipKind = nil
        widget.fibulaTooltipOriginal = nil
        widget.fibulaTooltipOriginalCaptured = nil
    end

    for _, child in pairs(widget:getChildren() or {}) do
        restoreWidgets(child, depth + 1)
    end
end

function FibulaTooltips.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    styleNativeTooltip()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Tooltip] UI 5D ready')
end

function FibulaTooltips.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end

    local gameRoot = modules.game_interface and
        modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil

    if gameRoot then
        restoreWidgets(gameRoot, 0)
    end

    -- Restore corelib's default plain tooltip skin for a clean module unload.
    if styledTooltip and rootWidget then
        local label = safe(function()
            return rootWidget:recursiveGetChildById('toolTip')
        end)

        if label then
            label:setBackgroundColor('#c0c0c0ff')
            label:setColor('#3f3f3fff')
            label:setBorderColor('#4c4c4cff')
            label:setBorderWidth(1)
            label:setTextOffset(topoint('5 3'))
        end
    end

    styledTooltip = false
end
