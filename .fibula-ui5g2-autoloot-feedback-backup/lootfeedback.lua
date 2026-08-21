FibulaLootFeedback = {}

local holder = nil
local entries = {}
local registeredModes = {}
local originalDisplay = nil
local routeReplaced = false

local WIDTH = 360
local ROW_HEIGHT = 28
local GAP = 4
local MAX_ROWS = 4
local HOLDER_HEIGHT = MAX_ROWS * ROW_HEIGHT + (MAX_ROWS - 1) * GAP
local HOLD_MS = 3200
local FADE_MS = 450

local lastMessage = nil
local lastMessageAt = 0

local function textMessageModule()
    return modules and modules.game_textmessage or nil
end

local function textMessageTypes()
    local mod = textMessageModule()
    return mod and mod.MessageTypes or nil
end

local function textMessageSettings()
    local mod = textMessageModule()
    return mod and mod.MessageSettings or nil
end

local function now()
    return g_clock.millis()
end

local function clean(text)
    text = tostring(text or '')
    text = text:gsub('\r', '')
    text = text:gsub('^%s+', '')
    text = text:gsub('%s+$', '')
    return text
end

local function isValuableMode(mode)
    return MessageModes and
        MessageModes.ValuableLoot ~= nil and
        mode == MessageModes.ValuableLoot
end

local function isExplicitLootMode(mode)
    if not MessageModes then
        return false
    end

    return (MessageModes.Loot ~= nil and mode == MessageModes.Loot) or
           (MessageModes.ValuableLoot ~= nil and mode == MessageModes.ValuableLoot)
end

local function classifyLoot(mode, text)
    text = clean(text)
    if text == '' then
        return false, false, nil, nil
    end

    local lower = text:lower()
    local explicit = isExplicitLootMode(mode)

    local classic = lower:match('^loot of ') ~= nil
    local modern = lower:match('^you looted ') ~= nil or
                   lower:match('^you found ') ~= nil

    if not explicit and not classic and not modern then
        return false, false, nil, nil
    end

    local body = text

    -- Classic Tibia:
    --   Loot of a rat: a gold coin.
    -- Preserve the exact item part but omit the corpse prefix from the toast.
    if classic then
        local extracted = text:match('^[Ll]oot of .-:%s*(.+)$')
        if extracted and extracted ~= '' then
            body = extracted
        end
    end

    local normalized = body:lower():gsub('[%.!]+$', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if normalized == 'nothing' or normalized == 'nothing.' then
        return false, false, nil, nil
    end

    return true, isValuableMode(mode), body, text
end

local function buildUi()
    if holder and not holder:isDestroyed() then
        return true
    end

    if not modules.game_interface or not modules.game_interface.getRootPanel then
        return false
    end

    local root = modules.game_interface.getRootPanel()
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

local function compactBody(body)
    body = clean(body)

    if #body <= 66 then
        return body
    end

    return body:sub(1, 63) .. '...'
end

local function showToast(body, fullText, valuable)
    if not buildUi() then
        return
    end

    local timestamp = now()

    -- Old servers can occasionally expose the same text through two callbacks.
    if lastMessage == fullText and timestamp - lastMessageAt < 250 then
        return
    end

    lastMessage = fullText
    lastMessageAt = timestamp

    while #entries >= MAX_ROWS do
        removeEntry(entries[1])
    end

    local widget = g_ui.createWidget('Panel', holder)
    widget:setId('fibulaLootToast')
    widget:setPhantom(false)
    widget:setBackgroundColor('#071019ed')
    widget:setBorderWidth(1)
    widget:setBorderColor(valuable and '#9a7a2f' or '#4d625e')
    widget:setTooltip(fullText)

    local accent = g_ui.createWidget('Panel', widget)
    accent:setPhantom(true)
    accent:setBackgroundColor(valuable and '#b9953f' or '#6f8d86')
    accent:setBorderWidth(0)
    accent:breakAnchors()
    accent:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    accent:addAnchor(AnchorTop, 'parent', AnchorTop)
    accent:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    accent:setWidth(3)

    makeLabel(
        widget,
        'lootType',
        valuable and 'VALUABLE' or 'LOOT',
        10,
        58,
        valuable and '#e4c66f' or '#a9c3bc',
        'verdana-10px-rounded'
    )

    makeLabel(
        widget,
        'lootText',
        compactBody(body),
        72,
        WIDTH - 82,
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

local function suppressScreenAndCallOriginal(mode, text)
    if not originalDisplay then
        return
    end

    local saved = {}

    -- Preserve the original console routing and coloring, but suppress only the
    -- old center/status screen label for this one loot message. This avoids a
    -- duplicate notification while keeping Server Log/Loot chat behavior.
    local settings = textMessageSettings()
    if settings then
        for _, setting in pairs(settings) do
            if type(setting) == 'table' and setting.screenTarget ~= nil then
                saved[setting] = setting.screenTarget
                setting.screenTarget = nil
            end
        end
    end

    local ok, err = pcall(originalDisplay, mode, text)

    for setting, screenTarget in pairs(saved) do
        setting.screenTarget = screenTarget
    end

    if not ok then
        g_logger.error('[Fibula Loot] original text message handler failed: ' .. tostring(err))
    end
end

local function onTextMessage(mode, text)
    local isLoot, valuable, body, fullText = classifyLoot(mode, text)

    if not isLoot then
        if routeReplaced and originalDisplay then
            originalDisplay(mode, text)
        end
        return
    end

    if g_game.getClientVersion() <= 0 or g_game.getClientVersion() >= 780 then
        if routeReplaced and originalDisplay then
            originalDisplay(mode, text)
        end
        return
    end

    g_logger.info('[Fibula Loot] recognized: ' .. fullText)
    showToast(body, fullText, valuable)

    if routeReplaced then
        suppressScreenAndCallOriginal(mode, text)
    end
end

local function collectModes()
    local seen = {}
    local modes = {}
    local types = textMessageTypes()

    if types then
        for mode, _ in pairs(types) do
            if type(mode) == 'number' and not seen[mode] then
                seen[mode] = true
                table.insert(modes, mode)
            end
        end
    end

    return modes
end

local function installMessageRoute()
    registeredModes = collectModes()
    g_logger.info(string.format('[Fibula Loot] discovered %d text message modes', #registeredModes))
    originalDisplay =
        modules.game_textmessage and
        modules.game_textmessage.displayMessage or nil

    routeReplaced = false

    if originalDisplay then
        local replaced = 0

        for _, mode in ipairs(registeredModes) do
            if unregisterMessageMode(mode, originalDisplay) then
                registerMessageMode(mode, onTextMessage)
                replaced = replaced + 1
            end
        end

        if replaced == #registeredModes and replaced > 0 then
            routeReplaced = true
            g_logger.info('[Fibula Loot] text-message route installed')
            return
        end

        -- Partial replacement is not safe. Restore anything we changed and
        -- fall back to passive observation.
        for _, mode in ipairs(registeredModes) do
            unregisterMessageMode(mode, onTextMessage)
            unregisterMessageMode(mode, originalDisplay)
            registerMessageMode(mode, originalDisplay)
        end
    end

    for _, mode in ipairs(registeredModes) do
        registerMessageMode(mode, onTextMessage)
    end

    g_logger.info('[Fibula Loot] passive message observer installed')
end

local function uninstallMessageRoute()
    for _, mode in ipairs(registeredModes) do
        unregisterMessageMode(mode, onTextMessage)
    end

    if routeReplaced and originalDisplay then
        for _, mode in ipairs(registeredModes) do
            registerMessageMode(mode, originalDisplay)
        end
    end

    registeredModes = {}
    routeReplaced = false
    originalDisplay = nil
end

local function clearToasts()
    local copy = {}
    for _, entry in ipairs(entries) do
        table.insert(copy, entry)
    end

    for _, entry in ipairs(copy) do
        removeEntry(entry)
    end

    entries = {}
    lastMessage = nil
    lastMessageAt = 0
end

local function onGameStart()
    clearToasts()
    scheduleEvent(buildUi, 150)
end

local function onGameEnd()
    clearToasts()
end

function FibulaLootFeedback.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    installMessageRoute()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Loot] UI 5G.1 loot route fix ready')
end

function FibulaLootFeedback.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    uninstallMessageRoute()
    clearToasts()

    if holder and not holder:isDestroyed() then
        holder:destroy()
    end

    holder = nil
end
