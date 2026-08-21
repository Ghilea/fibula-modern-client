FibulaViewport = {}

local gameMapPanel = nil
local monitorEvent = nil
local lastSignature = nil

local SAFE_WIDTH = 15
local SAFE_HEIGHT = 11
local CHECK_MS = 700

local function safeCall(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function getMapPanel()
    if modules.game_interface and modules.game_interface.getMapPanel then
        return modules.game_interface.getMapPanel()
    end

    local root = modules.game_interface and modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel() or nil

    if root then
        return root:recursiveGetChildById('gameMapPanel')
    end

    return nil
end

local function sizeSignature(panel)
    if not panel then
        return 'nil'
    end

    local panelSize = safeCall(function()
        return panel:getSize()
    end)

    local visible = safeCall(function()
        return panel:getVisibleDimension()
    end)

    local zoom = safeCall(function()
        return panel:getZoom()
    end)

    local keepAspect = safeCall(function()
        return panel:isKeepAspectRatioEnabled()
    end)

    local limitRange = safeCall(function()
        return panel:isLimitVisibleRangeEnabled()
    end)

    return string.format(
        'panel=%sx%s visible=%sx%s zoom=%s keepAspect=%s limitRange=%s',
        panelSize and tostring(panelSize.width) or '?',
        panelSize and tostring(panelSize.height) or '?',
        visible and tostring(visible.width) or '?',
        visible and tostring(visible.height) or '?',
        tostring(zoom or '?'),
        tostring(keepAspect),
        tostring(limitRange)
    )
end

local function logViewportIfChanged(panel)
    local signature = sizeSignature(panel)

    if signature ~= lastSignature then
        lastSignature = signature
        g_logger.info('[Fibula Viewport] ' .. signature)
    end
end

local function applyStableViewport(force)
    if not g_game.isOnline() then
        return false
    end

    local panel = getMapPanel()
    if not panel then
        return false
    end

    gameMapPanel = panel

    local visible = safeCall(function()
        return panel:getVisibleDimension()
    end)

    local keepAspect = safeCall(function()
        return panel:isKeepAspectRatioEnabled()
    end)

    local limitRange = safeCall(function()
        return panel:isLimitVisibleRangeEnabled()
    end)

    local zoom = tonumber(safeCall(function()
        return panel:getZoom()
    end)) or SAFE_HEIGHT

    local needsReset =
        force or
        keepAspect ~= false or
        limitRange ~= true or
        not visible or
        visible.width > SAFE_WIDTH or
        visible.height > SAFE_HEIGHT or
        zoom > SAFE_HEIGHT

    if needsReset then
        -- Important combination for Fibula 7.72:
        --
        -- keepAspectRatio(false):
        --   the map widget itself continues filling the fullscreen UI instead
        --   of producing letterbox/side gutters.
        --
        -- visibleDimension + limitVisibleRange(true):
        --   MapView no longer expands the requested world width every time the
        --   desktop/window aspect ratio changes.
        --
        -- This keeps the rendering surface fullscreen while capping the amount
        -- of old-protocol world data the client attempts to draw.
        -- Keep drawing the already-cached backing-buffer edge tiles while the
        -- followed creature is between tiles. Without this, MapView's
        -- direction-dependent viewport clipping can expose a thin empty strip
        -- during the 32px walk offset even though the same area is valid while
        -- standing still.
        panel:setDrawViewportEdge(true)

        panel:setKeepAspectRatio(false)
        panel:setVisibleDimension({
            width = SAFE_WIDTH,
            height = SAFE_HEIGHT
        })
        panel:setLimitVisibleRange(true)
        panel:setMaxZoomOut(SAFE_HEIGHT)

        if zoom > SAFE_HEIGHT then
            panel:setZoom(SAFE_HEIGHT)
        end

        safeCall(function()
            panel:updateMapRect()
        end)

        g_logger.info(string.format(
            '[Fibula Viewport] stabilized to max %dx%d',
            SAFE_WIDTH,
            SAFE_HEIGHT
        ))
    end

    logViewportIfChanged(panel)
    return true
end

local function startMonitor()
    if monitorEvent then
        removeEvent(monitorEvent)
        monitorEvent = nil
    end

    local function check()
        if g_game.isOnline() then
            applyStableViewport(false)
        end
        monitorEvent = scheduleEvent(check, CHECK_MS)
    end

    monitorEvent = scheduleEvent(check, 250)
end

local function onGameStart()
    lastSignature = nil

    -- game_interface performs some of its own view-mode setup immediately
    -- after login, so re-apply after those callbacks have settled.
    scheduleEvent(function()
        applyStableViewport(true)
    end, 100)

    scheduleEvent(function()
        applyStableViewport(true)
    end, 500)

    scheduleEvent(function()
        applyStableViewport(true)
    end, 1200)

    startMonitor()
end

local function onGameEnd()
    if monitorEvent then
        removeEvent(monitorEvent)
        monitorEvent = nil
    end

    gameMapPanel = nil
    lastSignature = nil
end

function FibulaViewport.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula Viewport] UI 5C.3 movement-edge fix ready')
end

function FibulaViewport.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if monitorEvent then
        removeEvent(monitorEvent)
        monitorEvent = nil
    end

    gameMapPanel = nil
    lastSignature = nil
end
