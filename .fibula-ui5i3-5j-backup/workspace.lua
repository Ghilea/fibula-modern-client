FibulaWorkspace = {}

local SETTINGS_KEY = 'FibulaWorkspace'
local state = nil
local characterName = nil
local restoreOpenPaths = nil
local restoringContainers = false
local restoreFinishEvent = nil
local retryEvents = {}

local originalOpen = nil
local hookedOpen = nil
local pendingNestedOpens = {}

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

local rootBackpackCid = nil

local function isProtectedOrCorpseName(name)
    name = tostring(name or ''):lower()

    if name:find('depot', 1, true) or
       name:find('locker', 1, true) or
       name:find('inbox', 1, true) then
        return true
    end

    -- Do not ever classify obvious corpse windows as the equipped backpack.
    if name:find('dead ', 1, true) == 1 or
       name:find('slain ', 1, true) == 1 or
       name:find('remains', 1, true) then
        return true
    end

    return false
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

    if item:getId() ~= backpack:getId() then
        return false
    end

    local cid = container:getId()

    -- Once identified, keep the exact server container id for this session.
    if rootBackpackCid ~= nil then
        return cid == rootBackpackCid
    end

    -- Best signal: the opened container item is literally the equipped item.
    if item == backpack then
        rootBackpackCid = cid
        return true
    end

    -- Next-best signal: both item objects still report the same inventory slot.
    local samePosition = safe(function()
        return positionsEqual(item:getPosition(), backpack:getPosition())
    end, false)

    if samePosition then
        rootBackpackCid = cid
        return true
    end

    -- Fibula 7.72 may clone/recreate the Item object during container-open and
    -- lose the inventory-slot position on that clone. The root equipped
    -- backpack is still an unparented container with the same item id and the
    -- server name "backpack"/"bag". Accept that narrowly, while excluding
    -- depot/corpses.
    local hasParent = safe(function()
        return container:hasParent()
    end, true)

    local name = tostring(safe(function()
        return container:getName()
    end, '') or '')

    local lowerName = name:lower()
    local backpackLike =
        lowerName:find('backpack', 1, true) ~= nil or
        lowerName:find('bag', 1, true) ~= nil

    if not hasParent and
       backpackLike and
       not isProtectedOrCorpseName(name) then
        rootBackpackCid = cid

        g_logger.info(string.format(
            '[Fibula Workspace] identified equipped backpack by legacy fallback: cid=%d item=%d name=%s',
            cid,
            item:getId(),
            name
        ))

        return true
    end

    return false
end

local buildContainerPath

local function findContainerById(cid)
    for _, container in pairs(g_game.getContainers()) do
        if container:getId() == cid then
            return container
        end
    end

    return nil
end

local function prunePendingNestedOpens()
    local cutoff = g_clock.millis() - 2500

    for i = #pendingNestedOpens, 1, -1 do
        if pendingNestedOpens[i].createdAt < cutoff then
            table.remove(pendingNestedOpens, i)
        end
    end
end

local function rememberNestedOpen(item)
    if not item then
        return
    end

    local pos = safe(function()
        return item:getPosition()
    end)

    if not pos or tonumber(pos.x) ~= 65535 then
        return
    end

    local y = tonumber(pos.y)
    local slot = tonumber(pos.z)

    if not y or y < 64 or y >= 128 or slot == nil then
        return
    end

    local parentCid = y - 64
    local parent = findContainerById(parentCid)
    if not parent then
        return
    end

    local parentPath = buildContainerPath and buildContainerPath(parent) or nil
    if not parentPath then
        return
    end

    local itemId = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    if itemId <= 0 then
        return
    end

    prunePendingNestedOpens()

    local path = string.format(
        '%s/%d:%d',
        parentPath,
        slot,
        itemId
    )

    table.insert(pendingNestedOpens, {
        path = path,
        parentCid = parentCid,
        slot = slot,
        itemId = itemId,
        createdAt = g_clock.millis()
    })

    g_logger.info(
        '[Fibula Workspace] pending nested open: ' .. path
    )
end

local function consumePendingNestedOpen(container)
    if not container then
        return nil
    end

    prunePendingNestedOpens()

    local item = container:getContainerItem()
    if not item then
        return nil
    end

    local itemId = tonumber(safe(function()
        return item:getId()
    end, 0)) or 0

    if itemId <= 0 then
        return nil
    end

    for index, record in ipairs(pendingNestedOpens) do
        if record.itemId == itemId then
            table.remove(pendingNestedOpens, index)
            container.fibulaWorkspacePath = record.path

            g_logger.info(
                '[Fibula Workspace] matched nested open: ' ..
                record.path
            )

            return record.path
        end
    end

    return nil
end

buildContainerPath = function(container, seen)
    if not container then
        return nil
    end

    if container.fibulaWorkspacePath then
        return container.fibulaWorkspacePath
    end

    if isEquippedBackpackContainer(container) then
        container.fibulaWorkspacePath = 'backpack'
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

    local path = string.format(
        '%s/%d:%d',
        parentPath,
        slot,
        item:getId()
    )

    container.fibulaWorkspacePath = path
    return path
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

local function saveContainerPosition(container, force)
    if not container or not container.window or container.window:isDestroyed() then
        return
    end

    local path = buildContainerPath(container)
    if not path then
        return
    end

    -- While a persisted container is being restored, other one-shot layout
    -- code may still move it. Ignore those automatic moves so they cannot
    -- overwrite the last user-selected position.
    if container.fibulaWorkspaceStabilizing and not force then
        return
    end

    local containerState = getContainerState(path)
    saveWidgetPosition(container.window, containerState)

    local pos = container.window:getPosition()
    g_logger.info(string.format(
        '[Fibula Workspace] saved %s position=%s',
        path,
        pointtostring(pos)
    ))
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
    if restoreWidgetPosition(container.window, containerState) then
        g_logger.info(string.format(
            '[Fibula Workspace] restored %s position=%s',
            path,
            tostring(containerState.position)
        ))
    end
end

function FibulaWorkspace.getSavedContainerPosition(container)
    if not state or not container then
        return nil
    end

    local path = buildContainerPath(container)

    if not path then
        path = consumePendingNestedOpen(container)
    end

    if not path then
        return nil
    end

    local containerState = getContainerState(path)
    if not containerState or not containerState.position then
        return nil
    end

    local ok, point = pcall(function()
        return topoint(containerState.position)
    end)

    if not ok then
        return nil
    end

    return point
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
    local containerState = getContainerState(path)
    local hasSavedPosition =
        containerState and
        containerState.position ~= nil

    container.fibulaWorkspaceUserMoved = false
    container.fibulaWorkspaceStabilizing = hasSavedPosition == true

    wrapDragPersistence(window, 'container:' .. path, function()
        -- A real drag by the player immediately wins over restore stabilization.
        -- From this point onward we stop re-applying the old position and save
        -- the newly chosen one.
        container.fibulaWorkspaceUserMoved = true
        container.fibulaWorkspaceStabilizing = false
        saveContainerPosition(container, true)
    end)

    if hasSavedPosition then
        -- Do not depend on the exact implementation or timing of wowpopup /
        -- bag-polish. Re-apply the saved position across the finite startup
        -- window where those modules can perform one-shot layout passes.
        -- There is no permanent polling.
        for _, delay in ipairs({
            40, 120, 260, 550, 900, 1400, 2200, 3200, 4200
        }) do
            scheduleEvent(function()
                if not container or
                   not container.window or
                   container.window:isDestroyed() or
                   container.fibulaWorkspaceUserMoved then
                    return
                end

                restoreContainerPosition(container)
            end, delay)
        end

        scheduleEvent(function()
            if not container or
               not container.window or
               container.window:isDestroyed() then
                return
            end

            if not container.fibulaWorkspaceUserMoved then
                restoreContainerPosition(container)
            end

            container.fibulaWorkspaceStabilizing = false

            g_logger.info(
                '[Fibula Workspace] position stabilized: ' .. path
            )
        end, 4400)
    end

    g_logger.info(string.format(
        '[Fibula Workspace] container attached: cid=%d path=%s name=%s savedPosition=%s',
        container:getId(),
        path,
        tostring(safe(function() return container:getName() end, '')),
        tostring(containerState and containerState.position or 'none')
    ))

    return true
end

local function snapshotOpenContainers(preserveIfEmpty)
    if not state or restoringContainers then
        return
    end

    local openPaths = {}

    for _, container in pairs(g_game.getContainers()) do
        local path = buildContainerPath(container)

        if path and container.window and not container.window:isDestroyed() then
            table.insert(openPaths, path)

            if not container.fibulaWorkspaceStabilizing then
                saveContainerPosition(container)
            end
        end
    end

    table.sort(openPaths)

    if preserveIfEmpty and #openPaths == 0 then
        return
    end

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
    -- Capture a stable nested path before any later layout code needs it.
    if not buildContainerPath(container) then
        consumePendingNestedOpen(container)
    end

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

local function installOpenHook()
    if originalOpen or type(g_game.open) ~= 'function' then
        return
    end

    originalOpen = g_game.open

    hookedOpen = function(item, previousContainer)
        rememberNestedOpen(item)
        return originalOpen(item, previousContainer)
    end

    g_game.open = hookedOpen

    g_logger.info(
        '[Fibula Workspace] nested container open correlation hook installed'
    )
end

local function uninstallOpenHook()
    if originalOpen and g_game.open == hookedOpen then
        g_game.open = originalOpen
    end

    originalOpen = nil
    hookedOpen = nil
    pendingNestedOpens = {}
end

local function onGameStart()
    cancelRetries()

    state = nil
    characterName = nil
    rootBackpackCid = nil
    pendingNestedOpens = {}

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

    -- Capture any still-open player bags if they are still present. If another
    -- module already cleaned the containers, preserve the previously saved
    -- state rather than overwriting it with an empty list.
    snapshotOpenContainers(true)

    rootBackpackCid = nil
    pendingNestedOpens = {}
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

    installOpenHook()

    if g_game.isOnline() then
        onGameStart()
    end

    g_logger.info(
        '[Fibula Workspace] UI 5I.2b workspace-only container persistence ready'
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

    uninstallOpenHook()
    cancelRetries()
    cancelEvent(restoreFinishEvent)

    restoreFinishEvent = nil
    restoringContainers = false
    restoreOpenPaths = nil
    state = nil
    characterName = nil
end
