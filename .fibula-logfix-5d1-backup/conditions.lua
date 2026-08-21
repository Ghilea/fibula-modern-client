FibulaConditions = {}

local root
local holder
local buffRow
local debuffRow
local buffIcons
local debuffIcons
local lastStates = -1
local retryEvents = {}

local ICON_SIZE = 22
local ICON_GAP = 4
local LABEL_WIDTH = 42
local MAX_ICONS_PER_ROW = 9

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
    Poison      = { name = 'Poisoned',        clip = 1  },
    Burn        = { name = 'Burning',         clip = 2  },
    Energy      = { name = 'Electrified',     clip = 3  },
    Drunk       = { name = 'Drunk',           clip = 4  },
    ManaShield  = { name = 'Magic Shield',    clip = 5  },
    Paralyze    = { name = 'Paralysed',       clip = 6  },
    Haste       = { name = 'Haste',            clip = 7  },
    Swords      = { name = 'Combat',           clip = 8  },
    Drowning    = { name = 'Drowning',         clip = 9  },
    Freezing    = { name = 'Freezing',         clip = 10 },
    Dazzled     = { name = 'Dazzled',          clip = 11 },
    Cursed      = { name = 'Cursed',           clip = 12 },
    PartyBuff   = { name = 'Strengthened',     clip = 13 },
    PzBlock     = { name = 'Protection Block', clip = 14 },
    Bleeding    = { name = 'Bleeding',         clip = 16 },
    Rooted      = { name = 'Rooted',           clip = 20 },
    Feared      = { name = 'Feared',           clip = 21 },
    NewManaShield = { name = 'Magic Shield',   clip = 27 },
    Agony       = { name = 'Agony',            clip = 28 },
    Powerless   = { name = 'Powerless',        clip = 33 },
    Mentored    = { name = 'Mentored',         clip = 34 }
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

    if ok and states then
        return tonumber(states) or 0
    end

    return 0
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

    -- All PlayerStates flags are powers of two. This fallback works without
    -- depending on Lua's bit library and is exact for the state values used
    -- by the client.
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

local function stateDefinition(stateName)
    local flag = PlayerStates and PlayerStates[stateName] or nil
    if not flag then
        return nil
    end

    local condition = findConditionByState(flag)
    local fallback = fallbackConditions[stateName] or {}

    return {
        key = stateName,
        state = flag,
        name = condition and condition.name or fallback.name or stateName,
        tooltip = condition and (condition.tooltipBar or condition.tooltip)
            or fallback.name
            or stateName,
        path = condition and condition.path or nil,
        clip = condition and condition.clip or fallback.clip or 1
    }
end

local function createLabel(parent, id, text, x, y, w, h, color)
    local widget = g_ui.createWidget('Label', parent)
    widget:setId(id)
    widget:setText(text)
    widget:setColor(color)
    widget:setFont('verdana-11px-rounded')
    widget:setTextAlign(AlignCenter)

    widget:breakAnchors()
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:setMarginTop(y)
    widget:setMarginLeft(x)
    widget:setSize({ width = w, height = h })

    return widget
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

local function buildRow(parent, id, y, labelText, labelColor, borderColor)
    -- Start compact. refresh() expands only as far as the active icons need.
    local row = createPanel(parent, id, 0, y, LABEL_WIDTH + ICON_SIZE + 7, 25)
    row:setBackgroundColor('#071019d8')
    row:setBorderWidth(1)
    row:setBorderColor(borderColor)

    local label = createLabel(
        row,
        id .. 'Label',
        labelText,
        3, 4,
        LABEL_WIDTH - 5, 16,
        labelColor
    )

    local icons = createPanel(
        row,
        id .. 'Icons',
        LABEL_WIDTH, 1,
        ICON_SIZE, 23
    )
    icons:setBackgroundColor('#00000000')
    icons:setBorderWidth(0)
    icons.fibulaBorderColor = borderColor

    return row, icons
end

local function resizeRow(row, icons, count)
    if not row or not icons or count <= 0 then
        return 0
    end

    local iconsWidth =
        count * ICON_SIZE +
        math.max(0, count - 1) * ICON_GAP

    icons:setWidth(iconsWidth)

    local rowWidth = LABEL_WIDTH + iconsWidth + 5
    row:setWidth(rowWidth)

    return rowWidth
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

    local targetFrame = root:getChildById('targetFrame')
    local playerFrame = root:getChildById('playerFrame')

    if not playerFrame then
        return false
    end

    holder = g_ui.createWidget('Panel', root)
    holder:setId('fibulaConditionsHolder')
    holder:setSize({ width = 90, height = 56 })
    holder:setBackgroundColor('#00000000')
    holder:setBorderWidth(0)
    holder:setPhantom(false)

    -- Keep status rows completely clear of HP/Mana/XP/ML. The previous
    -- version anchored against targetFrame even while it was hidden, which
    -- produced the long empty strip visible across the HUD.
    holder:breakAnchors()
    holder:addAnchor(AnchorLeft, 'playerFrame', AnchorLeft)
    holder:addAnchor(AnchorTop, 'playerFrame', AnchorBottom)
    holder:setMarginTop(5)

    buffRow, buffIcons = buildRow(
        holder,
        'fibulaBuffRow',
        0,
        'BUFF',
        '#d9c36a',
        '#756633'
    )

    debuffRow, debuffIcons = buildRow(
        holder,
        'fibulaDebuffRow',
        30,
        'DEBUFF',
        '#d98b8b',
        '#7a3838'
    )

    holder:hide()
    return true
end

local function conditionImagePath(definition)
    if definition.path and definition.path ~= '' then
        local path = tostring(definition.path)

        -- ConditionIcons uses paths like:
        --   images/conditions/player-state-flags-07.png
        -- Without the leading slash OTClient resolves them relative to this
        -- module (/game_fibula_conditions/...), which is wrong.
        if path:sub(1, 1) ~= '/' then
            path = '/' .. path
        end

        return path
    end

    -- Fallback to the same per-condition PNG family used by gamelib/player.lua.
    local clip = math.max(1, tonumber(definition.clip) or 1)
    return string.format(
        '/images/conditions/player-state-flags-%02d.png',
        clip - 1
    )
end

local function applyConditionImage(icon, definition)
    local image = icon:getChildById('stateImage')
    if not image then
        image = g_ui.createWidget('UIWidget', icon)
        image:setId('stateImage')
        image:setPhantom(true)

        image:breakAnchors()
        image:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        image:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        image:setSize({ width = 18, height = 18 })
    end

    -- These are individual PNG files, not a sprite sheet. Do not call
    -- setImageClip at all. The previous 4D passed a Lua string to
    -- setImageClip(), but this build expects a TRect and threw at runtime.
    image:setImageSource(conditionImagePath(definition))
    image:show()
end

local function createConditionIcon(parent, definition, index, positive)
    local x = (index - 1) * (ICON_SIZE + ICON_GAP)
    local icon = createPanel(
        parent,
        'fibulaCondition_' .. definition.key,
        x, 0,
        ICON_SIZE, ICON_SIZE
    )

    icon:setBackgroundColor('#080c12e8')
    icon:setBorderWidth(1)
    icon:setBorderColor(positive and '#756633' or '#7a3838')
    icon:setTooltip(definition.tooltip or definition.name or definition.key)

    applyConditionImage(icon, definition)
    icon:show()
    icon:raise()

    return icon
end

local function clearIcons(panel)
    if panel then
        panel:destroyChildren()
    end
end

local function renderGroup(panel, stateNames, states, positive)
    clearIcons(panel)

    local count = 0

    for _, stateName in ipairs(stateNames) do
        local definition = stateDefinition(stateName)

        if definition and stateActive(states, definition.state) then
            count = count + 1

            if count <= MAX_ICONS_PER_ROW then
                createConditionIcon(
                    panel,
                    definition,
                    count,
                    positive
                )
            end
        end
    end

    return math.min(count, MAX_ICONS_PER_ROW)
end

function FibulaConditions.refresh(force)
    if not buildUi() then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then
        if holder then
            holder:hide()
        end
        return false
    end

    local states = safeStates(player)

    if not force and states == lastStates then
        return true
    end

    lastStates = states

    local buffs = renderGroup(
        buffIcons,
        buffStateNames,
        states,
        true
    )

    local debuffs = renderGroup(
        debuffIcons,
        debuffStateNames,
        states,
        false
    )

    buffRow:setVisible(buffs > 0)
    debuffRow:setVisible(debuffs > 0)

    local buffWidth = resizeRow(buffRow, buffIcons, buffs)
    local debuffWidth = resizeRow(debuffRow, debuffIcons, debuffs)
    holder:setWidth(math.max(1, buffWidth, debuffWidth))

    if buffs > 0 and debuffs > 0 then
        buffRow:setMarginTop(0)
        debuffRow:setMarginTop(28)
        holder:setHeight(53)
    elseif buffs > 0 then
        buffRow:setMarginTop(0)
        debuffRow:hide()
        holder:setHeight(25)
    elseif debuffs > 0 then
        buffRow:hide()
        debuffRow:setMarginTop(0)
        holder:setHeight(25)
    end

    holder:setVisible(buffs > 0 or debuffs > 0)

    if holder:isVisible() then
        holder:raise()
    end

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
    buffRow = nil
    debuffRow = nil
    buffIcons = nil
    debuffIcons = nil
end
