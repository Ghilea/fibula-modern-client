FibulaAutoStack = {}

local originalUseWith = nil
local hookedUseWith = nil
local armedUntil = 0
local lastUseSourceId = 0
local merging = false

local ARM_MS = 1800
local MAX_STACK = 100

local function log(text)
    g_logger.info('[Fibula Stack] ' .. tostring(text))
end

local function isPlayerContainer(container)
    if not container then
        return false
    end

    if container:hasParent() then
        return true
    end

    local containerItem = container:getContainerItem()
    if not containerItem then
        return false
    end

    local pos = containerItem:getPosition()
    return pos and pos.x == 65535
end

local function shouldArmForUse(sourceThing, targetThing)
    if not sourceThing or not sourceThing.isItem or not sourceThing:isItem() then
        return false
    end

    -- We only care about carried/equipped tools. This deliberately avoids
    -- arming for map objects and most spell-rune use.
    local pos = sourceThing:getPosition()
    if not pos or pos.x ~= 65535 then
        return false
    end

    -- Fishing rods/tools are non-stackable. Runes/ammunition generally are
    -- stackable or charge-based and should not arm the "new stackable reward"
    -- window.
    if sourceThing:isStackable() then
        return false
    end

    -- Crosshair/tool actions against map items (water, holes, ropespots, etc.)
    -- come through useWith. If the action produces a stackable reward shortly
    -- afterwards, merge that reward automatically.
    return targetThing ~= nil
end

local function armToolReward(sourceId, reason)
    armedUntil = g_clock.millis() + ARM_MS
    lastUseSourceId = tonumber(sourceId) or 0

    log(string.format(
        'tool reward stacking armed for %d ms, source=%d via %s',
        ARM_MS,
        lastUseSourceId,
        tostring(reason or 'unknown')
    ))
end

local function onGameUseWith(pos, itemId, target, subType)
    -- This event is emitted by the actual outbound use-with action. It catches
    -- both manual right-click + target and action-bar crosshair use, even when
    -- a Lua wrapper around g_game.useWith is bypassed by another code path.
    if not pos or pos.x ~= 65535 or not itemId or not target then
        return
    end

    local source = g_game.findPlayerItem and g_game.findPlayerItem(itemId, -1, 0) or nil
    if source and not source:isStackable() then
        armToolReward(itemId, 'Game.onUseWith')
    end
end

local function sameStackKind(a, b)
    if not a or not b then
        return false
    end

    if a:getId() ~= b:getId() then
        return false
    end

    -- For stackables the relevant identity is item ID (+ tier when present).
    -- Do not use subtype as a stack key here; old protocol item metadata and
    -- count/subtype semantics differ between item classes.
    local aTier = a.getTier and a:getTier() or 0
    local bTier = b.getTier and b:getTier() or 0

    return aTier == bTier
end

local function findExistingStack(newItem, newContainer)
    -- Prefer an existing stack in the same container.
    if newContainer then
        for _, candidate in ipairs(newContainer:getItems()) do
            if candidate ~= newItem and
               candidate:isStackable() and
               candidate:getCount() < MAX_STACK and
               sameStackKind(candidate, newItem) then
                return candidate
            end
        end
    end

    -- Then search all other OPEN player-side bags/backpacks. Ground corpses
    -- and ground containers are deliberately excluded.
    for _, container in pairs(g_game.getContainers()) do
        if container ~= newContainer and isPlayerContainer(container) then
            for _, candidate in ipairs(container:getItems()) do
                if candidate ~= newItem and
                   candidate:isStackable() and
                   candidate:getCount() < MAX_STACK and
                   sameStackKind(candidate, newItem) then
                    return candidate
                end
            end
        end
    end

    return nil
end

local function tryMerge(container, item)
    if merging then
        return
    end

    if g_clock.millis() > armedUntil then
        return
    end

    if not isPlayerContainer(container) then
        return
    end

    if not item or not item:isStackable() then
        return
    end

    local count = item:getCount()
    if count <= 0 then
        return
    end

    local target = findExistingStack(item, container)
    if not target then
        return
    end

    local space = MAX_STACK - target:getCount()
    if space <= 0 then
        return
    end

    local moveCount = math.min(count, space)

    merging = true

    log(string.format(
        'auto-stacking reward item=%d count=%d onto existing=%d/%d after tool=%d',
        item:getId(),
        moveCount,
        target:getCount(),
        MAX_STACK,
        lastUseSourceId
    ))

    g_game.move(item, target:getPosition(), moveCount)

    scheduleEvent(function()
        merging = false
    end, 250)
end

local function onContainerAddItem(container, slot, item)
    if g_clock.millis() > armedUntil then
        return
    end

    -- Let the server/container update fully settle before moving the newly
    -- created item. This avoids racing the add packet itself.
    scheduleEvent(function()
        if item then
            tryMerge(container, item)
        end
    end, 80)
end

local function onContainerUpdateItem(container, slot, item, oldItem)
    if g_clock.millis() > armedUntil then
        return
    end

    -- Some old servers represent the fishing reward as an update rather than
    -- a clean add. Re-run the same merge logic after the packet settles.
    scheduleEvent(function()
        if item then
            tryMerge(container, item)
        end
    end, 80)
end

local function installUseWithHook()
    if originalUseWith or not g_game or not g_game.useWith then
        return
    end

    originalUseWith = g_game.useWith

    hookedUseWith = function(sourceThing, targetThing, subType)
        if shouldArmForUse(sourceThing, targetThing) then
            armToolReward(sourceThing:getId(), 'g_game.useWith wrapper')
        end

        return originalUseWith(sourceThing, targetThing, subType)
    end

    g_game.useWith = hookedUseWith
    log('g_game.useWith hook installed')
end

local function uninstallUseWithHook()
    if originalUseWith and g_game and g_game.useWith == hookedUseWith then
        g_game.useWith = originalUseWith
    end

    originalUseWith = nil
    hookedUseWith = nil
end

local function onGameEnd()
    armedUntil = 0
    lastUseSourceId = 0
    merging = false
end

function FibulaAutoStack.init()
    connect(Container, {
        onAddItem = onContainerAddItem,
        onUpdateItem = onContainerUpdateItem
    })

    connect(g_game, {
        onUseWith = onGameUseWith,
        onGameEnd = onGameEnd
    })

    installUseWithHook()
    log('Fishing/tool auto-stack 4G.2 ready')
end

function FibulaAutoStack.terminate()
    disconnect(Container, {
        onAddItem = onContainerAddItem,
        onUpdateItem = onContainerUpdateItem
    })

    disconnect(g_game, {
        onUseWith = onGameUseWith,
        onGameEnd = onGameEnd
    })

    uninstallUseWithHook()

    armedUntil = 0
    lastUseSourceId = 0
    merging = false
end
