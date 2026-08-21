FibulaChatQol = {}

local fallbackButton = nil
local panel = nil
local root = nil

local originalPanelEnter = nil
local originalSwitchChat = nil
local enterHandler = nil

local lastEnterAt = 0

local function consoleModule()
    return modules and modules.game_console or nil
end

local function getConsolePanel()
    local console = consoleModule()
    return console and console.consolePanel or nil
end

local function getConsoleEdit()
    local console = consoleModule()
    return console and console.consoleTextEdit or nil
end

local function focusConsoleEdit()
    local edit = getConsoleEdit()

    if not edit or not edit:isVisible() then
        return
    end

    edit:focus()
end

local function requestChannels()
    if not g_game.isOnline() then
        return
    end

    g_game.requestChannels()
    g_logger.info('[Fibula Chat] requested server channel list')
end

local function makeFallbackChannelsButton(consolePanel)
    if fallbackButton and not fallbackButton:isDestroyed() then
        return fallbackButton
    end

    fallbackButton = g_ui.createWidget('UIButton', consolePanel)
    fallbackButton:setId('fibulaChannelsButton')
    fallbackButton:setText('Channels')
    fallbackButton:setTooltip('Open channel list (Ctrl+O)')
    fallbackButton:setSize({ width = 62, height = 18 })
    fallbackButton:setFont('verdana-10px-rounded')
    fallbackButton:setBackgroundColor('#071019e8')
    fallbackButton:setBorderWidth(1)
    fallbackButton:setBorderColor('#53615f')
    fallbackButton:setColor('#ddd8cc')

    fallbackButton:breakAnchors()
    fallbackButton:addAnchor(AnchorTop, 'parent', AnchorTop)
    fallbackButton:addAnchor(AnchorRight, 'parent', AnchorRight)
    fallbackButton:setMarginTop(1)
    fallbackButton:setMarginRight(5)

    fallbackButton.onClick = requestChannels
    fallbackButton:show()
    fallbackButton:raise()

    return fallbackButton
end

local function exposeChannelsButton()
    local consolePanel = getConsolePanel()
    if not consolePanel or consolePanel:isDestroyed() then
        return false
    end

    local stock = consolePanel:recursiveGetChildById('channelsButton')

    if stock then
        stock:setVisible(true)
        stock:setEnabled(true)

        if stock:getWidth() <= 0 then
            stock:setWidth(16)
        end

        if stock:getHeight() <= 0 then
            stock:setHeight(16)
        end

        stock:setTooltip('Open channel list (Ctrl+O)')
        stock.onClick = requestChannels
        stock:raise()

        g_logger.info('[Fibula Chat] stock Channels button enabled')
        return true
    end

    makeFallbackChannelsButton(consolePanel)
    g_logger.info('[Fibula Chat] fallback Channels button created')
    return true
end

local function repairSwitchChatFocus()
    local console = consoleModule()

    if not console or originalSwitchChat then
        return
    end

    if type(console.switchChat) ~= 'function' then
        return
    end

    originalSwitchChat = console.switchChat

    console.switchChat = function(enabled)
        local result = originalSwitchChat(enabled)

        if enabled then
            -- switchChat makes the edit visible and swaps the Keybind mode,
            -- but the stock function does not focus the edit. Force focus
            -- after its visibility/layout changes are complete.
            scheduleEvent(focusConsoleEdit, 1)
        end

        return result
    end

    g_logger.info('[Fibula Chat] switchChat focus repair installed')
end

local function restoreSwitchChatFocus()
    local console = consoleModule()

    if originalSwitchChat and console and console.switchChat then
        console.switchChat = originalSwitchChat
    end

    originalSwitchChat = nil
end

local function handleEnter()
    if not g_game.isOnline() then
        return false
    end

    local now = g_clock.millis()

    -- The handler is installed on both consolePanel and gameRootPanel so it
    -- works regardless of focus. Prevent the same physical key event from
    -- toggling twice while still allowing normal typed-message sending below.
    if now - lastEnterAt < 35 then
        local edit = getConsoleEdit()
        return edit and edit:getText() == ''
    end

    lastEnterAt = now

    local console = consoleModule()
    local edit = getConsoleEdit()

    if not console or not edit then
        return false
    end

    if not edit:isVisible() then
        -- Use the console's own state transition so Chat On/Off labels,
        -- WASD bindings and Keybind chat mode all remain coherent.
        if console.switchChatOnCall then
            console.switchChatOnCall()
        elseif console.toggleChat then
            console.toggleChat()
        end

        scheduleEvent(focusConsoleEdit, 1)

        g_logger.info('[Fibula Chat] Enter opened chat input')
        return true
    end

    local text = tostring(edit:getText() or '')

    if text == '' then
        -- Empty Enter is a true toggle back to WASD regardless of the
        -- returnDisablesChat option. This fixes the state where the user had
        -- to click the Chat Off button manually.
        if console.toggleChat then
            console.toggleChat()
        elseif console.switchChat then
            console.switchChat(false)
        end

        if root then
            scheduleEvent(function()
                if root and not root:isDestroyed() then
                    root:focus()
                end
            end, 1)
        end

        g_logger.info('[Fibula Chat] Enter closed empty chat input')
        return true
    end

    -- Non-empty Enter is deliberately NOT consumed here. The stock
    -- "Send current chat line" Keybind remains responsible for sending.
    return false
end

local function installEnterRepair()
    if enterHandler then
        return
    end

    local console = consoleModule()
    panel = getConsolePanel()
    root = modules.game_interface and
        modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil

    if not console or not panel or not root then
        return
    end

    originalPanelEnter = console.switchChatOnCall

    -- The stock direct Enter binding lives on consolePanel. It is exactly what
    -- becomes unreliable when focus is outside the console, so replace that
    -- binding with one focus-independent handler.
    if originalPanelEnter then
        g_keyboard.unbindKeyDown(
            'Enter',
            originalPanelEnter,
            panel
        )
    end

    enterHandler = handleEnter

    g_keyboard.bindKeyDown(
        'Enter',
        enterHandler,
        panel
    )

    g_keyboard.bindKeyDown(
        'Enter',
        enterHandler,
        root
    )

    g_logger.info(
        '[Fibula Chat] focus-independent Enter toggle installed'
    )
end

local function uninstallEnterRepair()
    if enterHandler then
        if panel then
            g_keyboard.unbindKeyDown(
                'Enter',
                enterHandler,
                panel
            )
        end

        if root then
            g_keyboard.unbindKeyDown(
                'Enter',
                enterHandler,
                root
            )
        end
    end

    if originalPanelEnter and panel then
        g_keyboard.bindKeyDown(
            'Enter',
            originalPanelEnter,
            panel
        )
    end

    enterHandler = nil
    originalPanelEnter = nil
    panel = nil
    root = nil
end

local function attachUi()
    exposeChannelsButton()
    repairSwitchChatFocus()
    installEnterRepair()
end

local function onGameStart()
    scheduleEvent(attachUi, 80)
end

function FibulaChatQol.init()
    connect(g_game, {
        onGameStart = onGameStart
    })

    scheduleEvent(attachUi, 100)

    g_logger.info(
        '[Fibula Chat] UI 5J.1 channel selector + Enter repair ready'
    )
end

function FibulaChatQol.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart
    })

    uninstallEnterRepair()
    restoreSwitchChatFocus()

    if fallbackButton and not fallbackButton:isDestroyed() then
        fallbackButton:destroy()
    end

    fallbackButton = nil
end
