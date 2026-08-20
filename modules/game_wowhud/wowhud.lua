WowHud = {}

local root
local playerFrame
local targetFrame
local playerPortrait
local targetPortrait
local playerName
local playerLevel
local playerHealth
local playerMana
local playerExperience
local targetName
local targetHealth

-- Fibula Modern UI switches.
local HIDE_STANDARD_HEALTH_MANA = true
local HIDE_STANDARD_STATS_BARS = true
local HIDE_STORE_BUTTON = true
local FULLSCREEN_GAME_CANVAS = true
local TRANSPARENT_SIDE_CONTAINERS = true
local TRANSPARENT_CHAT_BACKGROUND = true
local HIDE_LEGACY_SIDE_ACTION_BARS = true
local HIDE_LEGACY_SPLITTER = true

local function clampPercent(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

local function percent(current, maximum)
    current = tonumber(current) or 0
    maximum = tonumber(maximum) or 0
    if maximum <= 0 then
        return 0
    end
    return clampPercent((current * 100) / maximum)
end

local function setCreatureSafely(widget, creature)
    if widget and creature then
        widget:setCreature(creature)
    end
end

local function hideWidgetById(parent, id)
    if not parent then return end
    local widget = parent:recursiveGetChildById(id)
    if widget then
        widget:hide()
    end
end

local function makeContainerTransparent(parent, id)
    if not parent then return end
    local widget = parent:recursiveGetChildById(id)
    if widget then
        widget:setImageSource('')
    end
end

local function applyFullscreenCanvas()
    if not FULLSCREEN_GAME_CANVAS then
        return
    end

    local interface = modules.game_interface
    if not interface then
        return
    end

    local gameRoot = interface.getRootPanel and interface.getRootPanel() or nil
    local map = interface.getMapPanel and interface.getMapPanel() or nil
    if not gameRoot or not map then
        return
    end

    -- The stock interface reserves space for sidebars, action bars and chat.
    -- Make the actual map a background canvas filling the complete game root.
    gameRoot:breakAnchors()
    gameRoot:fill('parent')

    map:breakAnchors()
    map:fill('parent')
    map:setMarginTop(0)
    map:setMarginBottom(0)
    map:setMarginLeft(0)
    map:setMarginRight(0)
    map:setOn(true)              -- stock style switches map padding from 4 -> 0
    map:setImageSource('')       -- remove the stock gray map frame

    -- Important: UIGameMap defaults to keeping the old Tibia viewport aspect ratio.
    -- When the client window is wider than that ratio, the map is letterboxed and
    -- whatever is behind it (the login/background artwork) becomes visible on the sides.
    -- Disable that behaviour so the map renderer itself uses the entire widget.
    map:setKeepAspectRatio(false)
    map:setLimitVisibleRange(false)

    map:lower()

    if TRANSPARENT_SIDE_CONTAINERS then
        local containers = {
            'gameLeftPanel',
            'gameLeftExtraPanel',
            'gameMainRightPanel',
            'gameRightPanel',
            'gameRightExtraPanel'
        }
        for _, id in ipairs(containers) do
            makeContainerTransparent(gameRoot, id)
        end
    end

    if TRANSPARENT_CHAT_BACKGROUND then
        makeContainerTransparent(gameRoot, 'gameBottomPanel')
    end

    if HIDE_LEGACY_SIDE_ACTION_BARS then
        hideWidgetById(gameRoot, 'gameLeftActionPanel')
        hideWidgetById(gameRoot, 'gameRightActionPanel')
        hideWidgetById(gameRoot, 'lockLeftPanel')
        hideWidgetById(gameRoot, 'lockRightPanel')
    end

    if HIDE_LEGACY_SPLITTER then
        hideWidgetById(gameRoot, 'bottomSplitter')
        hideWidgetById(gameRoot, 'leftIncreaseSidePanels')
        hideWidgetById(gameRoot, 'leftDecreaseSidePanels')
        hideWidgetById(gameRoot, 'rightIncreaseSidePanels')
        hideWidgetById(gameRoot, 'rightDecreaseSidePanels')
    end
end

local function hideStandardUi()
    if HIDE_STANDARD_HEALTH_MANA then
        local healthModule = modules.game_healthinfo
        if healthModule and healthModule.healthManaController and healthModule.healthManaController.ui then
            healthModule.healthManaController.ui:hide()
        end
    end

    if HIDE_STANDARD_STATS_BARS then
        local interfaceModule = modules.game_interface
        if interfaceModule and interfaceModule.StatsBar and interfaceModule.StatsBar.hideAll then
            interfaceModule.StatsBar.hideAll()
        end
    end

    if HIDE_STORE_BUTTON then
        local mainPanel = modules.game_mainpanel
        if mainPanel and mainPanel.optionsController and mainPanel.optionsController.ui then
            local onPanel = mainPanel.optionsController.ui.onPanel
            local storePanel = onPanel and onPanel.store
            if storePanel then
                local storeButton = storePanel:getChildById('Store shop')
                if storeButton then
                    storeButton:hide()
                end
            end
        end

        if mainPanel and mainPanel.reloadMainPanelSizes then
            mainPanel.reloadMainPanelSizes()
        end
    end
end

local function updatePlayer()
    if not root then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        playerFrame:hide()
        return
    end

    playerFrame:show()
    setCreatureSafely(playerPortrait, player)

    playerName:setText(player:getName() or 'Player')

    local level = player:getLevel() or 0
    playerLevel:setText(string.format('Lv. %d', level))

    local health = player:getHealth() or 0
    local maxHealth = player:getMaxHealth() or 0
    playerHealth:setPercent(percent(health, maxHealth))
    playerHealth:setText(string.format('%d / %d', health, maxHealth))

    local mana = player:getMana() or 0
    local maxMana = player:getMaxMana() or 0
    playerMana:setPercent(percent(mana, maxMana))
    playerMana:setText(string.format('%d / %d', mana, maxMana))

    local levelPercent = clampPercent(player:getLevelPercent() or 0)
    playerExperience:setPercent(levelPercent)
    playerExperience:setText(string.format('XP %.1f%%', levelPercent))

    local experience = player:getExperience()
    if experience then
        playerExperience:setTooltip(string.format(
            'Experience: %s\nLevel progress: %.1f%%',
            tostring(experience),
            levelPercent
        ))
    end
end

local function updateTarget()
    if not root then
        return
    end

    local creature = g_game.getAttackingCreature()
    if not creature then
        targetFrame:hide()
        return
    end

    targetFrame:show()
    setCreatureSafely(targetPortrait, creature)
    targetName:setText(creature:getName() or 'Target')

    local hp = clampPercent(creature:getHealthPercent())
    targetHealth:setPercent(hp)
    targetHealth:setText(string.format('%d%%', math.floor(hp + 0.5)))
end

local function applyModernUi()
    applyFullscreenCanvas()
    hideStandardUi()
end

local function onGameStart()
    if root then
        root:show()
        root:raise()
    end

    updatePlayer()
    updateTarget()

    -- Several stock modules apply layout shortly after login, so re-apply
    -- the fullscreen layout after their startup events have completed.
    applyModernUi()
    scheduleEvent(applyModernUi, 100)
    scheduleEvent(applyModernUi, 400)
    scheduleEvent(applyModernUi, 1000)
end

local function onGameEnd()
    if root then
        root:hide()
    end
end

local function onPlayerChanged()
    updatePlayer()
end

local function onCreatureHealthPercentChange(creature)
    if creature and creature == g_game.getAttackingCreature() then
        updateTarget()
    end
end

local function onAttackingCreatureChange()
    updateTarget()
end

function WowHud.init()
    root = g_ui.loadUI('wowhud', modules.game_interface.getRootPanel())

    playerFrame = root:getChildById('playerFrame')
    targetFrame = root:getChildById('targetFrame')

    playerPortrait = playerFrame:getChildById('playerPortrait')
    playerName = playerFrame:getChildById('playerName')
    playerLevel = playerFrame:getChildById('playerLevel')
    playerHealth = playerFrame:getChildById('playerHealth')
    playerMana = playerFrame:getChildById('playerMana')
    playerExperience = playerFrame:getChildById('playerExperience')

    targetPortrait = targetFrame:getChildById('targetPortrait')
    targetName = targetFrame:getChildById('targetName')
    targetHealth = targetFrame:getChildById('targetHealth')

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onAttackingCreatureChange = onAttackingCreatureChange
    })

    connect(LocalPlayer, {
        onHealthChange = onPlayerChanged,
        onManaChange = onPlayerChanged,
        onExperienceChange = onPlayerChanged,
        onLevelChange = onPlayerChanged,
        onChangeName = onPlayerChanged
    })

    connect(Creature, {
        onHealthPercentChange = onCreatureHealthPercentChange
    })

    applyModernUi()
    scheduleEvent(applyModernUi, 250)

    if g_game.isOnline() then
        onGameStart()
    else
        root:hide()
    end
end

function WowHud.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onAttackingCreatureChange = onAttackingCreatureChange
    })

    disconnect(LocalPlayer, {
        onHealthChange = onPlayerChanged,
        onManaChange = onPlayerChanged,
        onExperienceChange = onPlayerChanged,
        onLevelChange = onPlayerChanged,
        onChangeName = onPlayerChanged
    })

    disconnect(Creature, {
        onHealthPercentChange = onCreatureHealthPercentChange
    })

    if root then
        root:destroy()
        root = nil
    end
end
