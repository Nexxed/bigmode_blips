-- if you've opted to disable player names in server.lua and
-- then the script will use this name instead
-- %i is replaced with the players' Server ID
local defaultDormantNameFormat = "Dormant Player #%i"


--- [[ CODENS HAPPENING HERE! DONT TOUCH! ]] ---
local playerBlipHandles = {}
local latestBlipsUpdate = {}
local evaluationPlayers = {}

exports("GetDormantBlipHandles", function()
    return playerBlipHandles
end)

exports("GetLatestBlipsUpdate", function()
    return latestBlipsUpdate
end)

local function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function table.filter(table, it)
    local ret = {}
    for key, value in pairs(table) do
        if it(value, key, table) then
            ret[key] = value
        end
    end

    return ret
end

local function GetServerPlayerIds()
    -- get all the players that are currently in the same instance
    -- as the local player ("active" players)
    local rawPlayers = GetActivePlayers()

    -- make a new table for storing player server IDs
    local playerIDs = {}

    -- iterate raw_players using ipairs and insert their server ID
    -- into the player_ids table
    for index, player in ipairs(rawPlayers) do
        table.insert(playerIDs, GetPlayerServerId(player))
    end

    return playerIDs
end

local function Evaluate()

    -- iterate through the players needed to be removed
    for _, player in ipairs(evaluationPlayers) do

        -- iterate through every blip handle we currently have stored
        for player, blip in pairs(playerBlipHandles) do

            -- filter through the most recent blips update for blips belonging to this player
            local results = table.filter(latestBlipsUpdate, function(blip, key, blips)
                return blip[BLIP_INDEX_PLAYER_ID] == player
            end)

            -- if there are no blips belonging to this player, attempt to delete and dispose of handle
            if(#results == 0 and playerBlipHandles[player] ~= nil) then

                -- check if the blip handle does actually exist, if so, delete it
                if(DoesBlipExist(playerBlipHandles[player])) then
                    RemoveBlip(playerBlipHandles[player])
                end

                -- remove the player blip handle from storage
                playerBlipHandles[player] = nil
            end
        end
    end

    evaluationPlayers = {}
end

-- this is called when a player leaves the server so clients can clean-up old blips
RegisterNetEvent("_bigmode:evaluateBlips")
AddEventHandler("_bigmode:evaluateBlips", function(player)
    table.insert(evaluationPlayers, player)
end)

-- this is called when the server sends a new or updated batch of player data
RegisterNetEvent("_bigmode:updateBlips")
AddEventHandler("_bigmode:updateBlips", function(blips)
    latestBlipsUpdate = blips
    collectgarbage("collect") -- lua is not collecting this garbage quick enough, this helps

    if(#evaluationPlayers >= 1) then
        Evaluate()
    end

    Citizen.CreateThread(function()
        (function()
            -- iterate all dormant blips sent to us by the server
            for index, blip in pairs(blips) do
                local player = blip[BLIP_INDEX_PLAYER_ID]
                local pedNetworkId = blip[BLIP_INDEX_PED_NETWORK_ID]
                local playerPed = NetworkDoesEntityExistWithNetworkId(pedNetworkId) and NetworkGetEntityFromNetworkId(pedNetworkId) or nil

                -- if the player isn't in our instance and isn't our local player, draw this blip
                if((not DoesEntityExist(playerPed)) and player ~= GetPlayerServerId(PlayerId())) then

                    -- get the players name and coords from the blip
                    local coords = blip[BLIP_INDEX_COORDS]
                    local playerName = blip[BLIP_INDEX_PLAYER_NAME]

                    -- check if a blip already exists on the map for this player and
                    -- if there is then use the stored handle, otherwise, create a
                    -- new one and add it to the playerBlipHandles table
                    local blip = 0
                    if(playerBlipHandles[player] ~= nil and DoesBlipExist(playerBlipHandles[player])) then
                        blip = playerBlipHandles[player]

                        -- update the blips position
                        SetBlipCoords(blip, coords[1], coords[2], coords[3])
                    else
                        -- create the new blip
                        blip = AddBlipForCoord(coords[1], coords[2], coords[3])

                        -- set the dormant players' blip properties
                        SetBlipAlpha(blip, 180)
                        SetBlipSprite(blip, 1)
                        SetBlipScale(blip, 0.8)
                        SetBlipShrink(blip, 1)
                        SetBlipCategory(blip, 7)
                        SetBlipDisplay(blip, 6)

                        -- store the blip handle in the playerBlipHandles table using the players' server ID as key
                        playerBlipHandles[player] = blip
                    end

                    -- set the blip name to the players' name, or the default dormant name if not sent by the server
                    BeginTextCommandSetBlipName("STRING")
                    AddTextComponentString(playerName ~= nil and playerName or string.format(defaultDormantNameFormat, player))
                    EndTextCommandSetBlipName(blip)
                end
            end
        end)()
    end)
end)