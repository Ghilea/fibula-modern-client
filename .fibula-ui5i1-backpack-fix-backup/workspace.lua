FibulaWorkspace = {}

local SETTINGS_KEY = 'FibulaWorkspace'
local state = nil
local characterName = nil
local restoreOpenPaths = nil
local restoringContainers = false
local restoreFinishEvent = nil
local retryEvents = {}

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

local function cancelEvent(event)
    if event then
        removeEvent(event)
    end
end

local function cancelRetries()
    for _, event in ipairs(retryEvents) do
        cancelEvent(event)
    end
    retryEvents = {}
end

local function getCharacterName()
    local name = safe(function()
        return g_game.getCharacterName()
    end, '')

    name = tostring(name or '')
    if name == '' then
        return nil
    end

    return name
end

local function loadState()
    local char = getCharacterName()
    if not char then
        return false
    end

    characterName = char

    local all = g_settings.getNode(SETTINGS_KEY) or {}
    if type(all[char]) ~= 'table' then
        all[char] = {}
    end

    state = all[char]

    if type(state.character) ~= 'table' then
        state.character = {}
    end

    if type(state.minimap) ~= 'table' then
        state.minimap = {}
    end

    if type(state.containers) ~= 'table' then
        state.containers = {}
    end

    if type(state.openContainerPaths) ~= 'table' then
        state.openContainerPaths = {}
    end

    return true
end

local function saveState()
    if not characterName or not state then
        return
    end

    local all = g_settings.getNode(SETTINGS_KEY) or {}
    all[characterName] = state
    g_settings.setNode(SETTINGS_KEY, all)
end

local function saveWidgetPosition(widget, target)
    if not widget or widget:isDestroyed() or not target then
        return
    end

    local pos = widget:getPosition()
    if not pos then
        return
    end

    target.position = pointtostring(pos)
    saveState()
end

local function restoreWidgetPosition(widget, target)
    if not widget or widget:isDestroyed() or not target or not target.position then
        return false
    end

    local ok, point = pcall(function()
        return topoint(target.position)
    end)

    if not ok or not point then
        return false
    end

    widget:setPosition(point)
    return true
end

local function wrapDragPersistence(widget, key, saveFn)
    if not widget or widget:isDestroyed() then
        return
    end

    widget.fibulaWorkspaceHooks = widget.fibulaWorkspaceHooks or {}

    if widget.fibulaWorkspaceHooks[key] then
        return
    end

    widget.fibulaWorkspaceHooks[key] = true

    local previous = widget.onDragLeave

    widget.onDragLeave = function(self, droppedWidget, mousePos)
        local result = true

        if previous then
            local ok, value = pcall(previous, self, droppedWidget, mousePos)
            if ok and value ~= nil then
                result = value
            end
        end

        scheduleEvent(function()
            if self and not self:isDestroyed() then
                saveFn(self)
            end
        end, 1)

        return result
    end
end

local function getInventoryUi()
    local inventory = modules.game_inventory
    if not inventory or not inventory.inventoryController then
        return nil
    end

    return inventory.inventoryController.ui
end

local function getMinimapUi()
    local minimap = modules.game_minimap
    if not minimap or not minimap.mapController then
        return nil
    end

    return minimap.mapController.ui
end

local function attachCharacter()
    if not state and not loadState() then
        return false
    end

    local widget = getInventoryUi()
    if not widget or widget:isDestroyed() then
        return false
    end

    if not widget.fibulaWorkspaceCharacterAttached then
        widget.fibulaWorkspaceCharacterAttached = true

        wrapDragPersistence(widget, 'character', function(self)
            saveWidgetPosition(self, state.character)
        end)

        local previousVisibility = widget.onVisibilityChange

        widget.onVisibilityChange = function(self, visible)
            if previousVisibility then
                pcall(previousVisibility, self, visible)
            end

            -- game_wowpopup hides Character during logout. Do not let teardown
            -- overwrite the user's actual open/closed preference.
            if not g_game.isOnline() then
                return
            end

            state.character.open = visible == true

            if visible then
                -- prepareInventory() in game_wowpopup applies its default
                -- position each time Character is opened. Re-apply the saved
                -- position after that function has finished.
                scheduleEvent(function()
                    if self and not self:isDestroyed() and self:isVisible() then
                        restoreWidgetPosition(self, state.character)
                        self:raise()
                    end
                end, 1)
            else
                saveWidgetPosition(self, state.character)
                return
            end

            saveState()
        end
    end

    restoreWidgetPosition(widget, state.character)

    if state.character.open == true then
        widget:show()
        widget:raise()
    elseif state.character.open == false then
        widget:hide()
    end

    return true
end

local function attachMinimap()
    if not state and not loadState() then
        return false
    end

    local widget = getMinimapUi()
    if not widget or widget:isDestroyed() then
        return false
    end

    wrapDragPersistence(widget, 'minimap', function(self)
        saveWidgetPosition(self, state.minimap)
    end)

    restoreWidgetPosition(widget, state.minimap)
    return true
end

local function getEquippedBackpack()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    return player:getInventoryItem(InventorySlotBack)
end

local function positionsEqual(a, b)
    if not a or not b then
        return false
    end

    return a.x == b.x and
           a.y == b.y and
           a.z == b.z
end

local function isEquippedBackpackContainer(container)
    if not container then
        return false
    end

    local backpack = getEquippedBackpack()
    local item = container:getContainerItem()

    if not backpack or not item then
        return false
    end

    if item == backpack then
        return true
    end

    if item:getId() ~= backpack:getId() then
        return false
    end

    local samePosition = safe(function()
        return positionsEqual(item:getPosition(), backpack:getPosition())
    end, false)

    if samePosition then
        return true
    end

    return not container:hasParent()
end

local function findContainerById(cid)
    for _, container in pairs(g_game.getContainers()) do
        if container:getId() == cid then
            return container
        end
    end

    return nil
end

local function buildContainerPath(container, seen)
    if not container then
        return nil
    end

    if isEquippedBackpackContainer(container) then
        return 'backpack'
    end

    seen = seen or {}
    local cid = container:getId()

    if seen[cid] then
        return nil
    end

    seen[cid] = true

    local item = container:getContainerItem()
    if not item then
        return nil
    end

    local pos = safe(function()
        return item:getPosition()
    end)

    if not pos or tonumber(pos.x) ~= 65535 then
        return nil
    end

    local y = tonumber(pos.y)
    local slot = tonumber(pos.z)

    -- Nested container position:
    -- x=65535, y=(parentCid | 0x40), z=slot
    if not y or y < 64 or y >= 128 or slot == nil then
        return nil
    end

    local parentCid = y - 64
    local parent = findContainerById(parentCid)

    if not parent then
        return nil
    end

    local parentPath = buildContainerPath(parent, seen)
    if not parentPath then
        return nil
    end

    return string.format(
        '%s/%d:%d',
        parentPath,
        slot,
        item:getId()
    )
end

local function getContainerState(path)
    if not state then
        return nil
    end

    if type(state.containers[path]) ~= 'table' then
        state.containers[path] = {}
    end

    return state.containers[path]
end

local function saveContainerPosition(container)
    if not container or not container.window or container.window:isDestroyed() then
        return
    end

    local path = buildContainerPath(container)
    if not path then
        return
    end

    local containerState = getContainerState(path)
    saveWidgetPosition(container.window, containerState)
end

local function restoreContainerPosition(container)
    if not container or not container.window or container.window:isDestroyed() then
        return
    end

    local path = buildContainerPath(container)
    if not path then
        return
    end

    local containerState = getContainerState(path)
    restoreWidgetPosition(container.window, containerState)
end

local function attachContainerWindow(container)
    if not container or not container.window or container.window:isDestroyed() then
        return false
    end

    local path = buildContainerPath(container)
    if not path then
        -- Ground corpses, depot and other server-side storage are deliberately
        -- excluded. Only the equipped backpack tree is persistent.
        return false
    end

    local window = container.window

    wrapDragPersistence(window, 'container:' .. path, function()
        saveContainerPosition(container)
    end)

    -- game_wowpopup positions container windows after ~80 ms and bag polish
    -- settles after ~80 ms. Restore after both have run.
    scheduleEvent(function()
        if container and container.window and not container.window:isDestroyed() then
            restoreContainerPosition(container)
        end
    end, 120)

    scheduleEvent(function()
        if container and container.window and not container.window:isDestroyed() then
            restoreContainerPosition(container)
        end
    end, 240)

    return true
end

local function snapshotOpenContainers()
    if not state or restoringContainers then
        return
    end

    local openPaths = {}

    for _, container in pairs(g_game.getContainers()) do
        local path = buildContainerPath(container)

        if path and container.window and not container.window:isDestroyed() then
            table.insert(openPaths, path)
            saveContainerPosition(container)
        end
    end

    table.sort(openPaths)
    state.openContainerPaths = openPaths

    local backpackOpen = false
    for _, path in ipairs(openPaths) do
        if path == 'backpack' then
            backpackOpen = true
            break
        end
    end

    state.backpackOpen = backpackOpen
    saveState()
end

local function pathDepth(path)
    local _, slashes = tostring(path):gsub('/', '')
    return slashes
end

local function copyArray(input)
    local output = {}
    for _, value in ipairs(input or {}) do
        table.insert(output, value)
    end
    return output
end

local function childSegmentsFor(parentPath)
    local children = {}
    local prefix = parentPath .. '/'

    for _, path in ipairs(restoreOpenPaths or {}) do
        if path:sub(1, #prefix) == prefix then
            local remainder = path:sub(#prefix + 1)

            if remainder ~= '' and not remainder:find('/', 1, true) then
                local slot, itemId = remainder:match('^(%d+):(%d+)$')

                if slot and itemId then
                    table.insert(children, {
                        path = path,
                        slot = tonumber(slot),
                        itemId = tonumber(itemId)
                    })
                end
            end
        end
    end

    table.sort(children, function(a, b)
        return a.slot < b.slot
    end)

    return children
end

local function isPathAlreadyOpen(targetPath)
    for _, container in pairs(g_game.getContainers()) do
        if buildContainerPath(container) == targetPath then
            return true
        end
    end

    return false
end

local function restoreChildren(container)
    if not restoringContainers or not container then
        return
    end

    local parentPath = buildContainerPath(container)
    if not parentPath then
        return
    end

    local children = childSegmentsFor(parentPath)

    for index, child in ipairs(children) do
        scheduleEvent(function()
            if not restoringContainers or not g_game.isOnline() then
                return
            end

            if isPathAlreadyOpen(child.path) then
                return
            end

            local item = container:getItem(child.slot)

            if not item or item:getId() ~= child.itemId then
                g_logger.info(string.format(
                    '[Fibula Workspace] nested restore skipped: %s slot/id changed',
                    child.path
                ))
                return
            end

            local isContainer = safe(function()
                return item:isContainer()
            end, false)

            if not isContainer then
                return
            end

            -- No previousContainer parameter: keep the separate floating bag
            -- window behavior used by the current client.
            g_game.open(item)

            g_logger.info(
                '[Fibula Workspace] reopening ' .. child.path
            )
        end, 120 + ((index - 1) * 180))
    end
end

local function finishContainerRestore()
    restoringContainers = false
    restoreOpenPaths = nil
    restoreFinishEvent = nil

    scheduleEvent(function()
        snapshotOpenContainers()
    end, 200)
end

local function findOpenBackpackContainer()
    for _, container in pairs(g_game.getContainers()) do
        if isEquippedBackpackContainer(container) then
            return container
        end
    end

    return nil
end

local function ensureBackpackOpen()
    if not state or state.backpackOpen ~= true then
        return true
    end

    local already = findOpenBackpackContainer()
    if already then
        attachContainerWindow(already)
        restoreChildren(already)
        return true
    end

    local backpack = getEquippedBackpack()
    if not backpack then
        return false
    end

    -- Use the same operation as the existing B hotkey.
    g_game.use(backpack)

    g_logger.info(
        '[Fibula Workspace] reopening equipped backpack'
    )

    return true
end

local function beginContainerRestore()
    if not state then
        return
    end

    restoreOpenPaths = copyArray(state.openContainerPaths)

    local wantsBackpack = state.backpackOpen == true

    if not wantsBackpack then
        restoringContainers = false
        restoreOpenPaths = nil
        return
    end

    restoringContainers = true

    cancelEvent(restoreFinishEvent)
    restoreFinishEvent = scheduleEvent(
        finishContainerRestore,
        5000
    )

    for _, delay in ipairs({ 450, 900, 1500 }) do
        local event
        event = scheduleEvent(function()
            ensureBackpackOpen()
            table.removevalue(retryEvents, event)
        end, delay)

        table.insert(retryEvents, event)
    end
end

local function onContainerOpen(container)
    -- Let game_containers, wowpopup and bag polish finish creating the window.
    scheduleEvent(function()
        attachContainerWindow(container)

        if restoringContainers then
            restoreChildren(container)
        else
            snapshotOpenContainers()
        end
    end, 100)
end

local function onContainerClose()
    scheduleEvent(function()
        snapshotOpenContainers()
    end, 80)
end

local function restoreStaticWindows()
    attachCharacter()

    -- game_wowpopup positions minimap again at ~700ms after login.
    -- Apply saved workspace position after that.
    scheduleEvent(attachMinimap, 850)
    scheduleEvent(attachCharacter, 850)
end

local function scheduleStaticRetries()
    for _, delay in ipairs({ 500, 900, 1400 }) do
        local event
        event = scheduleEvent(function()
            restoreStaticWindows()
            table.removevalue(retryEvents, event)
        end, delay)

        table.insert(retryEvents, event)
    end
end

local function onGameStart()
    cancelRetries()

    state = nil
    characterName = nil

    if not loadState() then
        return
    end

    scheduleStaticRetries()
    beginContainerRestore()

    g_logger.info(
        '[Fibula Workspace] restoring workspace for ' ..
        characterName
    )
end

local function onGameEnd()
    cancelRetries()
    cancelEvent(restoreFinishEvent)
    restoreFinishEvent = nil

    -- Do not force any windows closed here. Their last user-driven state is
    -- already stored by visibility/container events.
    restoringContainers = false
    restoreOpenPaths = nil
end

function FibulaWorkspace.init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    connect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose
    })

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info(
        '[Fibula Workspace] UI 5I workspace persistence ready'
    )
end

function FibulaWorkspace.terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    disconnect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose
    })

    cancelRetries()
    cancelEvent(restoreFinishEvent)

    restoreFinishEvent = nil
    restoringContainers = false
    restoreOpenPaths = nil
    state = nil
    characterName = nil
end
