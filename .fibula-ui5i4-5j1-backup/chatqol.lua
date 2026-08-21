FibulaChatQol = {}

local KEY_CATEGORY = 'Chat'
local KEY_ACTION = 'Fibula Open Chat Input'

local fallbackButton = nil
local keybindInstalled = false

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

local function requestChannels()
    if not g_game.isOnline() then
        return
    end

    g_game.requestChannels()
    g_logger.info('[Fibula Chat] requested server channel list')
end

local function makeFallbackChannelsButton(panel)
    if fallbackButton and not fallbackButton:isDestroyed() then
        return fallbackButton
    end

    fallbackButton = g_ui.createWidget('UIButton', panel)
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
    local panel = getConsolePanel()
    if not panel or panel:isDestroyed() then
        return false
    end

    local stock = panel:recursiveGetChildById('channelsButton')

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

    makeFallbackChannelsButton(panel)
    g_logger.info('[Fibula Chat] fallback Channels button created')
    return true
end

local function openChatFromWalkMode()
    if not g_game.isOnline() then
        return false
    end

    local console = consoleModule()
    local edit = getConsoleEdit()

    if not console or not edit then
        return false
    end

    -- CHAT_MODE.OFF is the WASD/walk mode. Only act when the edit really is
    -- hidden; normal Enter-to-send remains owned by game_console.
    if edit:isVisible() then
        return false
    end

    if console.switchChatOnCall then
        console.switchChatOnCall()

        scheduleEvent(function()
            local currentEdit = getConsoleEdit()
            if currentEdit and currentEdit:isVisible() then
                currentEdit:focus()
            end
        end, 1)

        return true
    end

    if console.switchChat then
        console.switchChat(true)
        edit:focus()
        return true
    end

    return false
end

local function installEnterBinding()
    if keybindInstalled then
        return
    end

    local root = modules.game_interface and modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil

    if not root or not Keybind then
        return
    end

    local index = KEY_CATEGORY .. '_' .. KEY_ACTION

    if Keybind.defaultKeybinds and Keybind.defaultKeybinds[index] then
        Keybind.delete(KEY_CATEGORY, KEY_ACTION)
    end

    Keybind.new(
        KEY_CATEGORY,
        KEY_ACTION,
        {
            [CHAT_MODE.ON] = '',
            [CHAT_MODE.OFF] = 'Enter'
        },
        {
            [CHAT_MODE.ON] = '',
            [CHAT_MODE.OFF] = ''
        },
        ''
    )

    if not Keybind.defaultKeybinds or not Keybind.defaultKeybinds[index] then
        g_logger.warning(
            '[Fibula Chat] could not register Enter for CHAT_MODE.OFF; key is already reserved'
        )
        return
    end

    Keybind.bind(
        KEY_CATEGORY,
        KEY_ACTION,
        {
            {
                type = KEY_DOWN,
                callback = openChatFromWalkMode
            }
        },
        root
    )

    keybindInstalled = true
    g_logger.info('[Fibula Chat] Enter walk-mode chat binding installed')
end

local function uninstallEnterBinding()
    if not keybindInstalled or not Keybind then
        return
    end

    Keybind.delete(KEY_CATEGORY, KEY_ACTION)
    keybindInstalled = false
end

local function attachUi()
    exposeChannelsButton()
    installEnterBinding()
end

local function onGameStart()
    -- console UI is already persistent, but defer one tick in case login-side
    -- UI modules are still applying their visibility settings.
    scheduleEvent(attachUi, 80)
end

function FibulaChatQol.init()
    connect(g_game, {
        onGameStart = onGameStart
    })

    scheduleEvent(attachUi, 100)

    g_logger.info(
        '[Fibula Chat] UI 5J channels + reliable Enter ready'
    )
end

function FibulaChatQol.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart
    })

    uninstallEnterBinding()

    if fallbackButton and not fallbackButton:isDestroyed() then
        fallbackButton:destroy()
    end

    fallbackButton = nil
end
