FibulaConditions = {}

local root
local holder
local lastStates = -1
local retryEvents = {}

local ICON_SIZE = 24
local ICON_INNER = 18
local ICON_GAP = 3
local MAX_PER_ROW = 8
local MAX_ROWS = 2
local MAX_ICONS = MAX_PER_ROW * MAX_ROWS

local buffStateNames = {
    'ManaShield',
    'NewManaShield',
    'Haste',
    'PartyBuff',
    'Mentored'
}

local debuffStateNames = {
    'Poison',
    'Burn',
    'Energy',
    'Drunk',
    'Paralyze',
    'Swords',
    'Drowning',
    'Freezing',
    'Dazzled',
    'Cursed',
    'PzBlock',
    'Bleeding',
    'Rooted',
    'Feared',
    'Agony',
    'Powerless'
}

local fallbackConditions = {
    Poison        = { name = 'Poisoned',        clip = 1  },
    Burn          = { name = 'Burning',         clip = 2  },
    Energy        = { name = 'Electrified',     clip = 3  },
    Drunk         = { name = 'Drunk',           clip = 4  },
    ManaShield    = { name = 'Magic Shield',    clip = 5  },
    Paralyze      = { name = 'Paralysed',       clip = 6  },
    Haste         = { name = 'Haste',            clip = 7  },
    Swords        = { name = 'Combat',           clip = 8  },
    Drowning      = { name = 'Drowning',         clip = 9  },
    Freezing      = { name = 'Freezing',         clip = 10 },
    Dazzled       = { name = 'Dazzled',          clip = 11 },
    Cursed        = { name = 'Cursed',           clip = 12 },
    PartyBuff     = { name = 'Strengthened',     clip = 13 },
    PzBlock       = { name = 'Protection Block', clip = 14 },
    Bleeding      = { name = 'Bleeding',         clip = 16 },
    Rooted        = { name = 'Rooted',           clip = 20 },
    Feared        = { name = 'Feared',           clip = 21 },
    NewManaShield = { name = 'Magic Shield',     clip = 27 },
    Agony         = { name = 'Agony',            clip = 28 },
    Powerless     = { name = 'Powerless',        clip = 33 },
    Mentored      = { name = 'Mentored',         clip = 34 }
}

local function cancelRetries()
    for _, event in ipairs(retryEvents) do
        if event then
            removeEvent(event)
        end
    end
    retryEvents = {}
end

local function safeStates(player)
    if not player or not player.getStates then
        return 0
    end

    local ok, states = pcall(function()
        return player:getStates()
    end)

    return ok and tonumber(states) or 0
end

local function stateActive(states, flag)
    if not flag or flag <= 0 then
        return false
    end

    if Player and Player.isStateActive then
        local ok, active = pcall(function()
            return Player.isStateActive(states, flag)
        end)

        if ok then
            return active == true
        end
    end

    return math.floor(states / flag) % 2 == 1
end

local function findConditionByState(flag)
    if not ConditionIcons then
        return nil
    end

    for _, condition in ipairs(ConditionIcons) do
        if condition and condition.state == flag then
            return condition
        end
    end

    return nil
end

local function stateDefinition(stateName, positive)
    local flag = PlayerStates and PlayerStates[stateName] or nil
    if not flag then
        return nil
    end

    local condition = findConditionByState(flag)
    local fallback = fallbackConditions[stateName] or {}

    return {
        key = stateName,
        state = flag,
        positive = positive == true,
        name = condition and condition.name or fallback.name or stateName,
        tooltip = condition and (condition.tooltipBar or condition.tooltip)
            or fallback.name
            or stateName,
        path = condition and condition.path or nil,
        clip = condition and condition.clip or fallback.clip or 1
    }
end

local function createPanel(parent, id, x, y, w, h)
    local widget = g_ui.createWidget('Panel', parent)
    widget:setId(id)
    widget:breakAnchors()
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:setMarginTop(y)
    widget:setMarginLeft(x)
    widget:setSize({ width = w, height = h })
    return widget
end

local function resourceExists(path)
    if not path or path == '' or not g_resources or not g_resources.fileExists then
        return false
    end

    local ok, exists = pcall(function()
        return g_resources.fileExists(path)
    end)

    return ok and exists == true
end

local function normalizeResourcePath(path)
    if not path or path == '' then
        return nil
    end

    path = tostring(path)
    if path:sub(1, 1) ~= '/' then
        path = '/' .. path
    end
    return path
end

local function findDirectImage(definition)
    local path = normalizeResourcePath(definition.path)
    if path and resourceExists(path) then
        return path
    end
    return nil
end

local function findAtlasSource()
    -- Upstream OTClient ships the classic status atlas at this location.
    -- Check before assigning it so a custom checkout never produces a texture
    -- error just because the asset was removed.
    if resourceExists('/images/game/states/player-state-flags.png') then
        return '/images/game/states/player-state-flags'
    end

    if resourceExists('/images/game/states/player-state-flags') then
        return '/images/game/states/player-state-flags'
    end

    return nil
end

local function ensureFallbackMark(icon, definition)
    local mark = icon:getChildById('stateFallbackMark')

    if not mark then
        mark = g_ui.createWidget('Label', icon)
        mark:setId('stateFallbackMark')
        mark:setPhantom(true)
        mark:setFont('verdana-11px-rounded')
        mark:setTextAlign(AlignCenter)
        mark:setColor(definition.positive and '#e4cf79' or '#e59b9b')
        mark:breakAnchors()
        mark:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        mark:addAnchor(AnchorRight, 'parent', AnchorRight)
        mark:addAnchor(AnchorTop, 'parent', AnchorTop)
        mark:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    end

    local text = tostring(definition.name or definition.key or '?')
    mark:setText(text:sub(1, 1):upper())
    mark:show()
end

local function applyConditionImage(icon, definition)
    local image = g_ui.createWidget('UIWidget', icon)
    image:setId('stateImage')
    image:setPhantom(true)
    image:breakAnchors()
    image:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    image:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    image:setSize({ width = ICON_INNER, height = ICON_INNER })

    local direct = findDirectImage(definition)
    if direct then
        image:setImageSource(direct)
        image:show()
        return
    end

    local atlas = findAtlasSource()
    if atlas then
        image:setImageSource(atlas)

        -- The legacy atlas uses 9x9 cells arranged horizontally. This is the
        -- same clip calculation used by OTClient's own StatusIconBar.
        local clipIndex = math.max(1, tonumber(definition.clip) or 1)
        local clipX = (clipIndex - 1) * 9

        -- This build expects a TRect, not a raw Lua string.
        image:setImageClip(torect(string.format('%d 0 9 9', clipX)))
        image:show()
        return
    end

    image:hide()
    ensureFallbackMark(icon, definition)
end

local function clearIcons()
    if holder then
        holder:destroyChildren()
    end
end

local function createConditionIcon(definition, index)
    local row = math.floor((index - 1) / MAX_PER_ROW)
    local column = (index - 1) % MAX_PER_ROW
    local x = column * (ICON_SIZE + ICON_GAP)
    local y = row * (ICON_SIZE + ICON_GAP)

    local icon = createPanel(
        holder,
        'fibulaCondition_' .. definition.key,
        x, y,
        ICON_SIZE, ICON_SIZE
    )

    -- No BUFF/DEBUFF label boxes. The icon itself carries the distinction:
    -- warm muted gold for buffs, muted red for debuffs.
    icon:setBackgroundColor('#071019e8')
    icon:setBorderWidth(1)
    icon:setBorderColor(definition.positive and '#746538' or '#773d3d')
    icon:setTooltip(definition.tooltip or definition.name or definition.key)
    icon:setPhantom(false)

    applyConditionImage(icon, definition)
    icon:show()
    icon:raise()

    return icon
end

local function gatherActive(states)
    local active = {}

    for _, stateName in ipairs(buffStateNames) do
        local definition = stateDefinition(stateName, true)
        if definition and stateActive(states, definition.state) then
            table.insert(active, definition)
        end
    end

    for _, stateName in ipairs(debuffStateNames) do
        local definition = stateDefinition(stateName, false)
        if definition and stateActive(states, definition.state) then
            table.insert(active, definition)
        end
    end

    return active
end

local function buildUi()
    local interface = modules.game_interface
    if not interface or not interface.getRootPanel then
        return false
    end

    local gameRoot = interface.getRootPanel()
    if not gameRoot then
        return false
    end

    root = gameRoot:recursiveGetChildById('wowHudRoot')
    if not root then
        return false
    end

    if holder and not holder:isDestroyed() then
        return true
    end

    local playerFrame = root:getChildById('playerFrame')
    if not playerFrame then
        return false
    end

    holder = g_ui.createWidget('Panel', root)
    holder:setId('fibulaConditionsHolder')
    holder:setBackgroundColor('#00000000')
    holder:setBorderWidth(0)
    holder:setPhantom(false)

    holder:breakAnchors()
    holder:addAnchor(AnchorLeft, 'playerFrame', AnchorLeft)
    holder:addAnchor(AnchorTop, 'playerFrame', AnchorBottom)
    holder:setMarginTop(5)
    holder:setSize({ width = ICON_SIZE, height = ICON_SIZE })
    holder:hide()

    return true
end

function FibulaConditions.refresh(force)
    if not buildUi() then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then
        holder:hide()
        return false
    end

    local states = safeStates(player)
    if not force and states == lastStates then
        return true
    end

    lastStates = states
    clearIcons()

    local active = gatherActive(states)
    local count = math.min(#active, MAX_ICONS)

    for i = 1, count do
        createConditionIcon(active[i], i)
    end

    if count == 0 then
        holder:hide()
        return true
    end

    local rows = math.min(MAX_ROWS, math.ceil(count / MAX_PER_ROW))
    local columns = math.min(MAX_PER_ROW, count)

    if rows > 1 then
        columns = MAX_PER_ROW
    end

    local width =
        columns * ICON_SIZE +
        math.max(0, columns - 1) * ICON_GAP

    local height =
        rows * ICON_SIZE +
        math.max(0, rows - 1) * ICON_GAP

    holder:setSize({ width = width, height = height })
    holder:show()
    holder:raise()

    return true
end

local function scheduleBuild()
    cancelRetries()

    for _, delay in ipairs({ 50, 200, 600, 1200 }) do
        local event
        event = scheduleEvent(function()
            FibulaConditions.refresh(true)
            table.removevalue(retryEvents, event)
        end, delay)

        table.insert(retryEvents, event)
    end
end

local function onStatesChange()
    FibulaConditions.refresh(true)
end

local function onGameStart()
    lastStates = -1
    scheduleBuild()
end

local function onGameEnd()
    cancelRetries()
    lastStates = -1

    if holder then
        holder:hide()
    end
end

function FibulaConditions.init()
    connect(LocalPlayer, {
        onStatesChange = onStatesChange
    })

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    scheduleBuild()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Conditions] UI 5E compact icon strip ready')
end

function FibulaConditions.terminate()
    cancelRetries()

    disconnect(LocalPlayer, {
        onStatesChange = onStatesChange
    })

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if holder and not holder:isDestroyed() then
        holder:destroy()
    end

    holder = nil
    root = nil
end
