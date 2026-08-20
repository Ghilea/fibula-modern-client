function g_game.getRsa()
    return G.currentRsa
end

function g_game.findPlayerItem(itemId, subType, tier)
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
        for slot = InventorySlotFirst, InventorySlotLast do
            local item = localPlayer:getInventoryItem(slot)
            if item and item:getId() == itemId and (subType == -1 or item:getSubType() == subType) then
                return item
            end
        end
    end

    return g_game.findItemInContainers(itemId, subType, tier or 0)
end

local FIBULA_RSA =
    '1383589175496555516011359225459202586510792493206302029176020005709263' ..
    '3777016865440010286201615729363127788858889729156186543913276783223694' ..
    '7553872456033140205555218536070792283327632773558457562430692973109061' ..
    '0648493194549821256887431982702763941291218917953531792497825482714796' ..
    '25552587457164097090236827371'

function g_game.chooseRsa(host)
    if host == 'world.fibula.app' then
        g_game.setRsa(FIBULA_RSA)
        g_game.setCustomOs(OsTypes.Windows)
        return
    end

    if G.currentRsa ~= CIPSOFT_RSA and G.currentRsa ~= OTSERV_RSA then
        return
    end

    if host:ends('.tibia.com') or host:ends('.cipsoft.com') then
        g_game.setRsa(CIPSOFT_RSA)

        if g_app.getOs() == 'windows' then
            g_game.setCustomOs(OsTypes.Windows)
        else
            g_game.setCustomOs(OsTypes.Linux)
        end
    else
        if G.currentRsa == CIPSOFT_RSA then
            g_game.setCustomOs(-1)
        end
        g_game.setRsa(OTSERV_RSA)
    end

    if g_game.getClientVersion() <= 772 then
        g_game.setCustomOs(2)
    end
end

function g_game.setRsa(rsa, e)
    e = e or '65537'
    g_crypt.rsaSetPublicKey(rsa, e)
    G.currentRsa = rsa
end

function g_game.isOfficialTibia()
    return G.currentRsa == CIPSOFT_RSA
end

local supportedClients = {
    740, 741, 750, 755, 760, 770, 772, 780, 781, 782, 790, 792, 800, 810, 811, 820, 821, 822, 830, 831, 840,
    842, 850, 853, 854, 855, 857, 860, 861, 862, 870, 871, 900, 910, 920, 931, 940, 943, 944, 951, 952, 953,
    954, 960, 961, 963, 970, 971, 972, 973, 980, 981, 982, 983, 984, 985, 986, 1000, 1001, 1002, 1010, 1011,
    1012, 1013, 1020, 1021, 1022, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1050,
    1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1070, 1071, 1072, 1073,
    1074, 1075, 1076, 1080, 1081, 1082, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100,
    1281, 1285, 1286, 1287, 1291,
    1300, 1310, 1311, 1314, 1316, 1320, 1321, 1322, 1332, 1334, 1336, 1337, 1340,
    1400, 1405, 1410, 1412,
    1500, 1501, 1503, 1510, 1511, 1512, 1513, 1514, 1520, 1521, 1522, 1523, 1524, 1525
}

function g_game.getSupportedClients()
    return supportedClients
end

g_gameConfig.setLastSupportedVersion(supportedClients[#supportedClients])

-- The client version and protocol version where
-- unsynchronized for some releases, not sure if this
-- will be the normal standard.

-- Client Version: Publicly given version when
-- downloading Cipsoft client.

-- Protocol Version: Previously was the same as
-- the client version, but was unsychronized in some
-- releases, now it needs to be verified and added here
-- if it does not match the client version.

-- Reason for defining both: The server now requires a
-- Client version and Protocol version from the client.

-- Important: Use getClientVersion for specific protocol
-- features to ensure we are using the proper version.

function g_game.getClientProtocolVersion(client)
    local clients = {
        [980] = 971,
        [981] = 973,
        [982] = 974,
        [983] = 975,
        [984] = 976,
        [985] = 977,
        [986] = 978,
        [1001] = 979,
        [1002] = 980
    }
    return clients[client] or client
end

if not G.currentRsa then
    g_game.setRsa(OTSERV_RSA)
end

function g_game.closeContainerByItemId(itemId, tier)
    if not itemId then
        return false
    end
    local containersToClose = {}
    for _, container in pairs(g_game.getContainers()) do
        local containerItem = container:getContainerItem()
        if containerItem and containerItem:getId() == itemId then
            local containerTier = containerItem.getTier and containerItem:getTier() or nil
            if not tier or containerTier == tier then
                table.insert(containersToClose, container)
            end
        end
    end
    for _, container in ipairs(containersToClose) do
        g_game.close(container)
    end
    return #containersToClose > 0
end
