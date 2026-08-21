-- Fibula Smart Rune Maker
--
-- One-button rune conjuring for the old hand-based rune mechanic:
--   find required source item (normally Blank Rune)
--   temporarily free/equip a hand if needed
--   cast the rune spell
--   move the created rune back into the source bag
--   restore the original hand equipment

local transaction = nil
local scheduledEvents = {}

local POLL_MS = 90
local MOVE_TIMEOUT_MS = 1800
local CONJURE_TIMEOUT_MS = 2600

local function rememberEvent(event)
    if event then
        table.insert(scheduledEvents, event)
    end
    return event
end

local function cancelEvents()
    for _, event in ipairs(scheduledEvents) do
        if event then
            removeEvent(event)
        end
    end
    scheduledEvents = {}
end

local function log(text)
    g_logger.info('[Fibula RuneMaker] ' .. tostring(text))
end

local function status(text, failure)
    log(text)

    local textMessage = modules.game_textmessage
    if not textMessage then
        return
    end

    if failure and textMessage.displayFailureMessage then
        textMessage.displayFailureMessage(text)
    elseif textMessage.displayStatusMessage then
        textMessage.displayStatusMessage(text)
    end
end

local function copyPosition(pos)
    if not pos then
        return nil
    end

    return {
        x = pos.x,
        y = pos.y,
        z = pos.z
    }
end

local function handPosition(slot)
    return {
        x = 65535,
        y = slot,
        z = 0
    }
end

local function isHandPosition(pos)
    if not pos or pos.x ~= 65535 then
        return false
    end

    return pos.y == InventorySlotLeft or pos.y == InventorySlotRight
end

local function getPlayer()
    return g_game.getLocalPlayer()
end

local function findContainerById(containerId)
    if containerId == nil then
        return nil
    end

    for _, container in pairs(g_game.getContainers()) do
        if container:getId() == containerId then
            return container
        end
    end

    return nil
end

local function itemMatches(item, id, subType, tier)
    if not item or item:getId() ~= id then
        return false
    end

    if subType ~= nil and subType >= 0 and item:getSubType() ~= subType then
        return false
    end

    if tier ~= nil and item.getTier and item:getTier() ~= tier then
        return false
    end

    return true
end

local function findItemInContainer(container, id, subType, tier)
    if not container then
        return nil
    end

    for _, item in ipairs(container:getItems()) do
        if itemMatches(item, id, subType, tier) then
            return item
        end
    end

    return nil
end

local function findSourceItem(sourceId)
    -- g_game.findPlayerItem searches equipped inventory first and then the
    -- containers currently known to the client.
    if g_game.findPlayerItem then
        local item = g_game.findPlayerItem(sourceId, -1, 0)
        if item then
            return item
        end
    end

    local player = getPlayer()
    if player then
        for slot = InventorySlotFirst, InventorySlotLast do
            local item = player:getInventoryItem(slot)
            if item and item:getId() == sourceId then
                return item
            end
        end
    end

    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item:getId() == sourceId then
                return item
            end
        end
    end

    return nil
end

local function getItemParentContainer(item)
    if not item or not item.getParentContainer then
        return nil
    end

    local ok, container = pcall(function()
        return item:getParentContainer()
    end)

    if ok then
        return container
    end

    return nil
end

local function containerHasFreeSlot(container)
    return container and container:getItemsCount() < container:getCapacity()
end

local function containerIsPlayerLike(container)
    if not container then
        return false
    end

    if container:hasParent() then
        return true
    end

    local item = container:getContainerItem()
    if not item then
        return false
    end

    local pos = item:getPosition()
    return pos and pos.x == 65535
end

local function getEquippedBackpackRoot()
    local player = getPlayer()
    if not player then
        return nil
    end

    local backpack = player:getInventoryItem(InventorySlotBack)
    if not backpack then
        return nil
    end

    for _, container in pairs(g_game.getContainers()) do
        local item = container:getContainerItem()
        if item and
           not container:hasParent() and
           item:getId() == backpack:getId() and
           containerIsPlayerLike(container) then
            return container
        end
    end

    return nil
end

local function findTemporaryContainer(sourceItem)
    -- Prefer the bag containing the Blank Rune. This keeps the temporary
    -- weapon/shield move local and predictable.
    local parent = getItemParentContainer(sourceItem)
    if containerHasFreeSlot(parent) then
        return parent
    end

    -- Then prefer the equipped root backpack.
    local rootBackpack = getEquippedBackpackRoot()
    if containerHasFreeSlot(rootBackpack) then
        return rootBackpack
    end

    -- Last resort: another open player-side bag with room. Do not use a
    -- ground corpse/root container as temporary equipment storage.
    for _, container in pairs(g_game.getContainers()) do
        if containerHasFreeSlot(container) and containerIsPlayerLike(container) then
            return container
        end
    end

    return nil
end

local function freeSlotPosition(container)
    if not containerHasFreeSlot(container) then
        return nil
    end

    return container:getSlotPosition(container:getItemsCount())
end

local function chooseHand(player, sourceItem)
    local sourcePos = sourceItem and sourceItem:getPosition() or nil

    if isHandPosition(sourcePos) then
        return sourcePos.y, true
    end

    local left = player:getInventoryItem(InventorySlotLeft)
    local right = player:getInventoryItem(InventorySlotRight)

    -- Avoid touching equipped gear whenever an empty hand already exists.
    if not left then
        return InventorySlotLeft, false
    end

    if not right then
        return InventorySlotRight, false
    end

    -- In this client's inventory mapping, InventorySlotLeft is the normal
    -- weapon slot. If both hands are occupied, temporarily replace that one.
    return InventorySlotLeft, false
end

local function pollUntil(predicate, success, timeout, timedOut)
    local start = g_clock.millis()

    local function check()
        if not transaction or not g_game.isOnline() then
            return
        end

        local ok, result = pcall(predicate)
        if ok and result then
            success()
            return
        end

        if g_clock.millis() - start >= timeout then
            if timedOut then
                timedOut()
            end
            return
        end

        rememberEvent(scheduleEvent(check, POLL_MS))
    end

    rememberEvent(scheduleEvent(check, POLL_MS))
end

local function finish(message, failure)
    cancelEvents()
    transaction = nil

    if message then
        status(message, failure)
    end
end

local function findMovedHandItem()
    if not transaction or not transaction.originalHandId then
        return nil
    end

    local temp = findContainerById(transaction.tempContainerId)
    local item = findItemInContainer(
        temp,
        transaction.originalHandId,
        transaction.originalHandSubType,
        transaction.originalHandTier
    )

    if item then
        return item
    end

    -- Fallback if the user rearranged/closed containers during the short
    -- transaction.
    if g_game.findPlayerItem then
        return g_game.findPlayerItem(
            transaction.originalHandId,
            transaction.originalHandSubType or -1,
            transaction.originalHandTier or 0
        )
    end

    return nil
end

local function restoreOriginalHand()
    if not transaction then
        return
    end

    if not transaction.originalHandId then
        finish('Rune created.')
        return
    end

    local player = getPlayer()
    if not player then
        finish('Rune created, but equipment restore failed.', true)
        return
    end

    local current = player:getInventoryItem(transaction.handSlot)
    if current and itemMatches(
        current,
        transaction.originalHandId,
        transaction.originalHandSubType,
        transaction.originalHandTier
    ) then
        finish('Rune created. Equipment restored.')
        return
    end

    local original = findMovedHandItem()
    if not original then
        finish('Rune created, but original hand item could not be found.', true)
        return
    end

    g_game.move(
        original,
        handPosition(transaction.handSlot),
        original:getCount()
    )

    pollUntil(
        function()
            local hand = getPlayer():getInventoryItem(transaction.handSlot)
            return itemMatches(
                hand,
                transaction.originalHandId,
                transaction.originalHandSubType,
                transaction.originalHandTier
            )
        end,
        function()
            finish('Rune created. Equipment restored.')
        end,
        MOVE_TIMEOUT_MS,
        function()
            finish('Rune created, but equipment restore timed out.', true)
        end
    )
end

local function destinationForCreatedRune()
    if not transaction then
        return nil
    end

    -- Best destination is the bag that originally contained the Blank Rune.
    -- Removing the blank leaves one free slot there.
    local sourceContainer = findContainerById(transaction.sourceContainerId)
    if containerHasFreeSlot(sourceContainer) then
        return freeSlotPosition(sourceContainer)
    end

    -- If the source was an equipment slot rather than a bag, return the
    -- finished rune to that exact slot.
    if transaction.sourcePosition and
       transaction.sourcePosition.x == 65535 and
       transaction.sourcePosition.y < 64 then
        return copyPosition(transaction.sourcePosition)
    end

    -- Fallback to another player container with room.
    local rootBackpack = getEquippedBackpackRoot()
    if containerHasFreeSlot(rootBackpack) then
        return freeSlotPosition(rootBackpack)
    end

    for _, container in pairs(g_game.getContainers()) do
        if containerHasFreeSlot(container) and containerIsPlayerLike(container) then
            return freeSlotPosition(container)
        end
    end

    return nil
end

local function moveCreatedRuneAway()
    if not transaction then
        return
    end

    local player = getPlayer()
    local hand = player and player:getInventoryItem(transaction.handSlot) or nil

    -- Some old servers may consume the blank and place the produced rune
    -- elsewhere. If the hand is already empty, just restore equipment.
    if not hand then
        restoreOriginalHand()
        return
    end

    local destination = destinationForCreatedRune()
    if not destination then
        finish(
            'Rune was created but there is no free bag slot to restore your equipment.',
            true
        )
        return
    end

    local createdId = hand:getId()
    transaction.createdRuneId = createdId

    g_game.move(hand, destination, hand:getCount())

    pollUntil(
        function()
            local now = getPlayer():getInventoryItem(transaction.handSlot)
            return not now or now:getId() ~= createdId
        end,
        restoreOriginalHand,
        MOVE_TIMEOUT_MS,
        function()
            finish('Could not move the created rune back into your bag.', true)
        end
    )
end

local function recoverAfterFailedSpell()
    if not transaction then
        return
    end

    local player = getPlayer()
    local hand = player and player:getInventoryItem(transaction.handSlot) or nil

    if hand and hand:getId() == transaction.sourceId then
        local destination = destinationForCreatedRune()

        if destination then
            g_game.move(hand, destination, 1)

            pollUntil(
                function()
                    local now = getPlayer():getInventoryItem(transaction.handSlot)
                    return not now or now:getId() ~= transaction.sourceId
                end,
                function()
                    if transaction then
                        restoreOriginalHand()
                    end
                end,
                MOVE_TIMEOUT_MS,
                function()
                    finish('Rune spell failed and Blank Rune restore timed out.', true)
                end
            )
            return
        end
    end

    restoreOriginalHand()
end

local function castPreparedSpell()
    if not transaction then
        return
    end

    transaction.castAt = g_clock.millis()

    log(string.format(
        'casting "%s" with source item %d in hand slot %d',
        transaction.words,
        transaction.sourceId,
        transaction.handSlot
    ))

    g_game.talk(transaction.words)

    pollUntil(
        function()
            local player = getPlayer()
            local hand = player and player:getInventoryItem(transaction.handSlot) or nil

            -- Successful classic rune conjuring replaces the Blank Rune with
            -- another item ID. A server that removes it outright is also
            -- treated as success and we proceed to restore equipment.
            return not hand or hand:getId() ~= transaction.sourceId
        end,
        moveCreatedRuneAway,
        CONJURE_TIMEOUT_MS,
        function()
            status('Rune spell did not transform the Blank Rune; restoring equipment.', true)
            recoverAfterFailedSpell()
        end
    )
end

local function equipSourceRune()
    if not transaction then
        return
    end

    local source = findSourceItem(transaction.sourceId)
    if not source then
        finish('Blank Rune disappeared before it could be equipped.', true)
        return
    end

    g_game.move(
        source,
        handPosition(transaction.handSlot),
        1
    )

    pollUntil(
        function()
            local player = getPlayer()
            local hand = player and player:getInventoryItem(transaction.handSlot) or nil
            return hand and hand:getId() == transaction.sourceId
        end,
        castPreparedSpell,
        MOVE_TIMEOUT_MS,
        function()
            finish('Could not equip the Blank Rune.', true)
        end
    )
end

local function freeSelectedHand()
    if not transaction then
        return
    end

    local player = getPlayer()
    local hand = player and player:getInventoryItem(transaction.handSlot) or nil

    if not hand then
        equipSourceRune()
        return
    end

    local source = findSourceItem(transaction.sourceId)
    local temp = findTemporaryContainer(source)

    if not temp then
        finish(
            'Both hands are occupied. Open a bag with at least one free slot.',
            true
        )
        return
    end

    local destination = freeSlotPosition(temp)
    if not destination then
        finish('No free temporary bag slot is available.', true)
        return
    end

    transaction.originalHandId = hand:getId()
    transaction.originalHandSubType = hand:getSubType()
    transaction.originalHandTier = hand.getTier and hand:getTier() or nil
    transaction.tempContainerId = temp:getId()

    log(string.format(
        'temporarily moving hand item %d from slot %d to container %d',
        transaction.originalHandId,
        transaction.handSlot,
        transaction.tempContainerId
    ))

    g_game.move(hand, destination, hand:getCount())

    pollUntil(
        function()
            return getPlayer():getInventoryItem(transaction.handSlot) == nil
        end,
        equipSourceRune,
        MOVE_TIMEOUT_MS,
        function()
            finish('Could not temporarily unequip the hand item.', true)
        end
    )
end

function castRuneSpell(words, spellData)
    if not g_game.isOnline() then
        return false
    end

    local sourceId = spellData and tonumber(spellData.source) or 0

    -- Returning false lets the normal action-bar path cast ordinary spells.
    if sourceId <= 0 then
        return false
    end

    -- A rune-maker transaction owns this action; never send the same spell
    -- twice while equipment is being shuffled.
    if transaction then
        status('Rune Maker is already preparing another rune.', true)
        return true
    end

    local player = getPlayer()
    if not player then
        return true
    end

    local source = findSourceItem(sourceId)
    if not source then
        status(
            string.format(
                'No required rune source item (%d) found. Keep a Blank Rune in an open backpack/bag.',
                sourceId
            ),
            true
        )
        return true
    end

    local sourcePos = copyPosition(source:getPosition())
    local sourceContainer = getItemParentContainer(source)
    local handSlot, alreadyInHand = chooseHand(player, source)

    transaction = {
        words = words,
        sourceId = sourceId,
        sourcePosition = sourcePos,
        sourceContainerId = sourceContainer and sourceContainer:getId() or nil,
        handSlot = handSlot,
        originalHandId = nil,
        originalHandSubType = nil,
        originalHandTier = nil,
        tempContainerId = nil
    }

    if alreadyInHand then
        -- The user deliberately already has the Blank Rune in hand. Do not
        -- move the resulting rune away because there is no equipment state to
        -- restore.
        log('source rune is already in hand; casting without equipment shuffle')
        g_game.talk(words)
        transaction = nil
        return true
    end

    status('Preparing Blank Rune...')

    local currentHand = player:getInventoryItem(handSlot)

    if currentHand then
        freeSelectedHand()
    else
        equipSourceRune()
    end

    return true
end

local function onGameEnd()
    cancelEvents()
    transaction = nil
end

function init()
    connect(g_game, {
        onGameEnd = onGameEnd
    })

    log('Smart Rune Maker ready')
end

function terminate()
    disconnect(g_game, {
        onGameEnd = onGameEnd
    })

    cancelEvents()
    transaction = nil
end
