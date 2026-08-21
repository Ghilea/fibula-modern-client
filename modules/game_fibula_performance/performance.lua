FibulaPerformance = {}

local sampleEvent = nil
local applied = false
local savedFloorFading = 500
local savedForceEffectOptimization = false

local function getOption(name, fallback)
    if not modules.client_options or not modules.client_options.getOption then
        return fallback
    end
    local ok, value = pcall(function()
        return modules.client_options.getOption(name)
    end)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

local function getMapPanel()
    if modules.game_interface and modules.game_interface.getMapPanel then
        return modules.game_interface.getMapPanel()
    end
    return nil
end

local function logFps()
    sampleEvent = nil
    if not g_game.isOnline() then
        return
    end

    g_logger.info(string.format(
        '[Fibula PERF] graphics=%s processing=%s max=%s target=%s',
        tostring(g_app.getGraphicsFps()),
        tostring(g_app.getProcessingFps()),
        tostring(g_app.getMaxFps()),
        tostring(g_app.getTargetFps())
    ))
end

local function applyProfile()
    if applied or not g_game.isOnline() or g_game.getClientVersion() >= 780 then
        return
    end

    savedFloorFading = tonumber(getOption('floorFading', 500)) or 500
    savedForceEffectOptimization = getOption('forceEffectOptimization', false) == true

    g_app.optimize(true)
    g_app.forceEffectOptimization(true)

    local panel = getMapPanel()
    if panel and panel.setFloorFading then
        panel:setFloorFading(100)
    end

    applied = true
    sampleEvent = scheduleEvent(logFps, 3000)

    g_logger.info(
        '[Fibula PERF] PERF 2.1 active ' ..
        '(effect optimization on, floor fade 100ms, frame pacing untouched)'
    )
end

local function restoreProfile()
    if sampleEvent then
        removeEvent(sampleEvent)
        sampleEvent = nil
    end

    if not applied then
        return
    end

    g_app.forceEffectOptimization(savedForceEffectOptimization)

    local panel = getMapPanel()
    if panel and panel.setFloorFading then
        panel:setFloorFading(savedFloorFading)
    end

    applied = false
end

local function onGameStart()
    scheduleEvent(applyProfile, 150)
end

local function onGameEnd()
    restoreProfile()
end

function FibulaPerformance.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info('[Fibula PERF] PERF 2.1 module ready')
end

function FibulaPerformance.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    restoreProfile()
end
