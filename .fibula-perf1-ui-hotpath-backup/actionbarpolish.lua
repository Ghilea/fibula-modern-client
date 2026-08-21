FibulaActionbarPolish = {}

local refreshEvent = nil
local originalExecuteAction = nil
local hookedExecuteAction = nil
local REFRESH_MS = 220

local MODE_INFO = {
    [1] = { text = 'S', color = '#70d58a' },
    [2] = { text = 'T', color = '#e36b6b' },
    [3] = { text = 'X', color = '#e8c66d' },
    [9] = { text = 'C', color = '#6da9e8' }
}

local function mod()
    return modules and modules.game_actionbar or nil
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function valid(widget)
    if not widget then return false end
    local destroyed = safe(function() return widget:isDestroyed() end)
    return destroyed ~= true
end

local function ensureModeBadge(button)
    local badge = button:getChildById('fibulaModeBadge')
    if badge then return badge end

    badge = g_ui.createWidget('Label', button)
    badge:setId('fibulaModeBadge')
    badge:setSize({ width = 11, height = 10 })
    badge:setFont('verdana-8px-rounded')
    badge:setTextAlign(AlignCenter)
    badge:setBackgroundColor('#071019e8')
    badge:setBorderWidth(1)
    badge:setBorderColor('#33445a')
    badge:setPhantom(true)
    badge:breakAnchors()
    badge:addAnchor(AnchorTop, 'parent', AnchorTop)
    badge:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    badge:setMarginTop(1)
    badge:setMarginLeft(1)
    badge:hide()
    return badge
end

local function updateModeBadge(button, cache)
    local badge = ensureModeBadge(button)
    local info = cache and MODE_INFO[tonumber(cache.actionType)] or nil
    if not info then
        badge:hide()
        return
    end
    badge:setText(info.text)
    badge:setColor(info.color)
    badge:setBorderColor(info.color)
    badge:show()
    badge:raise()
end

local function formatHotkey(text)
    text = tostring(text or '')
    if text == '' then return '' end
    text = text:gsub('Ctrl%+', 'C')
    text = text:gsub('Shift%+', 'S')
    text = text:gsub('Alt%+', 'A')
    text = text:gsub('Num%+', 'N')
    if #text > 6 then text = text:sub(1, 6) end
    return text
end

local function polishHotkey(button, cache)
    local label = button:getChildById('hotkeyLabel')
    if not label then return end

    label:setColor('#eadfb7')
    label:setFont('verdana-8px-rounded')
    safe(function() label:setBackgroundColor('#071019c8') end)

    if cache and cache.hotkey and tostring(cache.hotkey) ~= '' then
        label:setText(formatHotkey(cache.hotkey))
    end
    label:raise()
end

local function polishCooldown(button)
    local cooldown = button:getChildById('cooldown')
    if not cooldown then return end

    safe(function() cooldown:setBackgroundColor('#05070bdc') end)
    safe(function() cooldown:setBorderColor('#8c7bad') end)
    safe(function() cooldown:setColor('#ffffff') end)
    safe(function() cooldown:setFont('verdana-11px-rounded') end)
    safe(function() cooldown:showProgress(true) end)
    safe(function() cooldown:showTime(true) end)
end

local function getItemCount(button, cache, player)
    if not button.item or not cache then return nil end

    local itemId = tonumber(cache.itemId) or 0
    if itemId <= 0 then
        itemId = tonumber(button.item:getItemId()) or 0
    end
    if itemId <= 0 then return nil end

    local tier = 0
    if g_game.getFeature(GameThingUpgradeClassification) then
        tier = tonumber(cache.upgradeTier) or 0
    end

    local count = safe(function()
        return player:getInventoryCount(itemId, tier)
    end)
    return tonumber(count) or 0
end

local function polishItemState(button, cache, player)
    if not button.item then return end
    local count = getItemCount(button, cache, player)
    if count == nil then return end

    safe(function() button.item:setDisplayCount(count) end)
    button.item:setOpacity(count <= 0 and 0.38 or 1.0)
end

local function polishButton(button, player)
    if not valid(button) or not button.item then return end
    local cache = button.cache or {}

    polishItemState(button, cache, player)
    updateModeBadge(button, cache)
    polishHotkey(button, cache)
    polishCooldown(button)

    local activeSpell = button:getChildById('activeSpell')
    if activeSpell then activeSpell:raise() end

    local badge = button:getChildById('fibulaModeBadge')
    if badge then badge:raise() end

    local hotkey = button:getChildById('hotkeyLabel')
    if hotkey then hotkey:raise() end
end

local function eachButton(callback)
    local actionbar = mod()
    if not actionbar then return end

    for _, bar in pairs(actionbar.actionBars or {}) do
        if valid(bar) and bar.tabBar then
            for _, button in pairs(bar.tabBar:getChildren()) do
                if button and button.item then
                    callback(button)
                end
            end
        end
    end
end

function FibulaActionbarPolish.refresh()
    if not g_game.isOnline() then return end
    local player = g_game.getLocalPlayer()
    if not player then return end

    eachButton(function(button)
        polishButton(button, player)
    end)
end

local function predictedCooldown(button)
    if not button or not button.cache then return end
    local cache = button.cache
    if not (cache.isSpell or cache.isRuneSpell) then return end

    local data = cache.spellData
    if not data then return end

    local duration = tonumber(data.exhaustion) or 0
    if duration <= 0 then return end

    local now = g_clock.millis()
    if button.fibulaPredictedCooldownAt and
       now - button.fibulaPredictedCooldownAt < 120 then
        return
    end
    button.fibulaPredictedCooldownAt = now

    local actionbar = mod()
    if actionbar and actionbar.updateCooldown then
        safe(function() actionbar.updateCooldown(button, duration) end)
    elseif button.cooldown then
        safe(function()
            button.cooldown:showProgress(true)
            button.cooldown:showTime(true)
            button.cooldown:setDuration(duration)
            button.cooldown:start()
        end)
    end
end

local function installExecuteHook()
    local actionbar = mod()
    if not actionbar or originalExecuteAction then return end
    if type(actionbar.onExecuteAction) ~= 'function' then return end

    originalExecuteAction = actionbar.onExecuteAction
    hookedExecuteAction = function(button, isPress)
        local result = originalExecuteAction(button, isPress)
        predictedCooldown(button)
        scheduleEvent(FibulaActionbarPolish.refresh, 20)
        return result
    end

    actionbar.onExecuteAction = hookedExecuteAction
    g_logger.info('[Fibula Actionbar] execute hook installed')
end

local function uninstallExecuteHook()
    local actionbar = mod()
    if originalExecuteAction and actionbar and actionbar.onExecuteAction == hookedExecuteAction then
        actionbar.onExecuteAction = originalExecuteAction
    end
    originalExecuteAction = nil
    hookedExecuteAction = nil
end

local function scheduleRefresh()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end

    local function tick()
        FibulaActionbarPolish.refresh()
        refreshEvent = scheduleEvent(tick, REFRESH_MS)
    end

    refreshEvent = scheduleEvent(tick, 80)
end

local function onGameStart()
    scheduleEvent(function()
        installExecuteHook()
        FibulaActionbarPolish.refresh()
        scheduleRefresh()
    end, 450)
end

local function onGameEnd()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end
end

function FibulaActionbarPolish.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    installExecuteHook()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Actionbar] UI 5B ready')
end

function FibulaActionbarPolish.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end

    uninstallExecuteHook()

    eachButton(function(button)
        local badge = button:getChildById('fibulaModeBadge')
        if badge then badge:destroy() end
        if button.item then button.item:setOpacity(1.0) end
    end)
end
