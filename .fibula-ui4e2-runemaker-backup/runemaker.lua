-- Fibula Smart Rune Maker 4E.1
--
-- Generic spell-send hook:
-- instead of depending only on one action-bar code path, intercept g_game.talk()
-- and detect rune-conjuring spells no matter whether they came from chat,
-- action bar, spell list or another hotkey path.

local transaction = nil
local scheduledEvents = {}
local originalTalk = nil
local hookedTalk = nil

local POLL_MS = 90
local MOVE_TIMEOUT_MS = 1800
local CONJURE_TIMEOUT_MS = 2800

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

local function normalizeWords(text)
    return tostring(text or '')
        :lower()
        :gsub('^%s+', '')
        :gsub('%s+$', '')
        :gsub('%s+', ' ')
end

local function findSpellData(words)
    local normalized = normalizeWords(words)

    if Spells and Spells.getSpellDataByParamWords then
        local ok, data = pcall(function()
            return Spells.getSpellDataByParamWords(normalized)
        end)

        if ok and data then
            return data
        end
    end

    -- Fallback for older/custom action paths: scan the loaded SpellInfo table
    -- directly for exact spell words.
    if SpellInfo then
        for _, spellSet in pairs(SpellInfo) do
            if type(spellSet) == 'table' then
                for _, data in pairs(spellSet) do
                    if type(data) == 'table' and data.words and
                       normalizeWords(data.words) == normalized then
                        return data
                    end
                end
            end
        end
    end

    return nil
end

local function rawTalk(text)
    if originalTalk then
        return originalTalk(text)
    end
end

local function copyPosition(pos)
    if not pos then
        return nil
    end

    return { x = pos.x, y = pos.y, z = pos.z }
end

local function handPosition(slot)
    return { x = 65535, y = slot, z = 0 }
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
    local parent = getItemParentContainer(sourceItem)
    if containerHasFreeSlot(parent) then
        return parent
    end

    local rootBackpack = getEquippedBackpackRoot()
    if containerHasFreeSlot(rootBackpack) then
        return rootBackpack
    end

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

    if not left then
        return InventorySlotLeft, false
    end

    if not right then
        return InventorySlotRight, false
    end

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

    local sourceContainer = findContainerById(transaction.sourceContainerId)

    if containerHasFreeSlot(sourceContainer) then
        return freeSlotPosition(sourceContainer)
    end

    if transaction.sourcePosition and
       transaction.sourcePosition.x == 65535 and
       transaction.sourcePosition.y < 64 then
        return copyPosition(transaction.sourcePosition)
    end

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

    log(string.format(
        'created item %d detected in hand; moving it back to bag',
        createdId
    ))

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
                restoreOriginalHand,
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

    log(string.format(
        'casting "%s" with source item %d in hand slot %d',
        transaction.words,
        transaction.sourceId,
        transaction.handSlot
    ))

    -- Bypass our own g_game.talk hook for the actual prepared cast.
    rawTalk(transaction.words)

    pollUntil(
        function()
            local player = getPlayer()
            local hand = player and player:getInventoryItem(transaction.handSlot) or nil

            return not hand or hand:getId() ~= transaction.sourceId
        end,
        moveCreatedRuneAway,
        CONJURE_TIMEOUT_MS,
        function()
            status(
                'Rune spell did not transform the source item; restoring equipment.',
                true
            )
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
        finish(
            string.format(
                'Required rune source item %d disappeared before it could be equipped.',
                transaction.sourceId
            ),
            true
        )
        return
    end

    log(string.format(
        'moving source item %d into hand slot %d',
        transaction.sourceId,
        transaction.handSlot
    ))

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
            finish('Could not equip the Blank Rune/source item.', true)
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
            'Both hands are occupied. Open a player bag with at least one free slot.',
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

    if sourceId <= 0 then
        return false
    end

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
                'Rune spell detected, but source item %d was not found. Keep the Blank Rune in an open backpack/bag for this test.',
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

    log(string.format(
        'rune spell detected: words="%s" source=%d sourcePos=%s,%s,%s handSlot=%d',
        tostring(words),
        sourceId,
        sourcePos and tostring(sourcePos.x) or 'nil',
        sourcePos and tostring(sourcePos.y) or 'nil',
        sourcePos and tostring(sourcePos.z) or 'nil',
        handSlot
    ))

    if alreadyInHand then
        log('source item already in hand; sending rune spell directly')
        rawTalk(words)
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

local function installTalkHook()
    if originalTalk or not g_game or not g_game.talk then
        return
    end

    originalTalk = g_game.talk

    hookedTalk = function(text)
        local spellData = findSpellData(text)
        local sourceId = spellData and tonumber(spellData.source) or 0

        if spellData then
            log(string.format(
                'talk intercepted: "%s" spell="%s" type=%s source=%d',
                tostring(text),
                tostring(spellData.name or '?'),
                tostring(spellData.type or '?'),
                sourceId
            ))
        end

        if spellData and sourceId > 0 then
            return castRuneSpell(text, spellData)
        end

        return originalTalk(text)
    end

    g_game.talk = hookedTalk
    log('generic g_game.talk hook installed')
end

local function uninstallTalkHook()
    if originalTalk and g_game and g_game.talk == hookedTalk then
        g_game.talk = originalTalk
    end

    originalTalk = nil
    hookedTalk = nil
end

local function onGameEnd()
    cancelEvents()
    transaction = nil
end

function init()
    connect(g_game, {
        onGameEnd = onGameEnd
    })

    installTalkHook()
    log('Smart Rune Maker 4E.1 ready')
end

function terminate()
    disconnect(g_game, {
        onGameEnd = onGameEnd
    })

    cancelEvents()
    transaction = nil
    uninstallTalkHook()
end
