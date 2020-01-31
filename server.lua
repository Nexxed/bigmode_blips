-- how many milliseconds to wait before sending updates to all players again
-- based on player count for key, so you can slow down updates depending on how many players are connected
-- for 5 updates per second use 1000 / 5
local updateIntervals = {
    [256]   = 1000 * 5,     -- once every 5 seconds | during 256-1024 players
    [128]   = 1000 * 4,     -- once every 4 seconds | during 128-256 players
    [96]    = 1000 * 3,     -- once every 3 seconds | during 96-128 players
    [64]    = 1000 * 2,     -- once every 2 seconds | during 64-96 players
    [0]     = 1000          -- once every second    | during 0-64 players
}

local DEBUG = false

-- how many milliseconds to wait before sending an update to the next player in-loop
-- example: player A gets sent an update, server waits X milliseconds before sending to player B
-- can be useful for bandwidth reasons
local updateSpacing = 100

-- whether or not to transmit player names with blip updates
-- setting this to false will disable player names on blips!
-- works the same way as updateIntervals
local sendNames = {
    [0]     = true          -- when the player count is between 0 and 96, names will be enabled
}
-- this is currently unfinished, so just set 0 to whatever value you want for now



-- debug threshold limits
-- if enabled, it will notify you via server console that the server isn't meeting performance expectations
-- this is usually due to improper interval configuration that doesn't match your servers hardware

-- its recommended to leave this disabled unless you're testing high player counts or similar
-- since it can be used to identify if the script can "keep up" with the player count
local threadTimeWarnings = true
local mainThreadTimeThreshold = 10          -- parent thread
local updateThreadTimeThreshold = 10        -- blip updates thread



--- [[ CODENS HAPPENING HERE! DONT TOUCH! ]] ---
local lastBlipsUpdate = {}
local lastIntervalValue = 0
local shouldSendNames = false -- no, changing this instead of the option above won't do anything

function math.clamp(low, n, high)
    return math.min(math.max(n, low), high)
end

-- emitted when a player leaves the server
AddEventHandler("playerDropped", function()
    TriggerClientEvent("_bigmode:evaluateBlips", -1, source)
end)

-- this is the main update thread for pushing blip location updates to players
Citizen.CreateThread(function()
    while true do
        collectgarbage("collect") -- lua is not collecting garbage left by this script fast enough, this helps
        
        local mt_begin = GetGameTimer()

        -- get and store all of the currently-connected players
        local players = GetPlayers()


        -- iterate through the configured intervals and find the one that
        -- best suits the current number of players
        local updateInterval = 0
        local updateIntervalLimit = 0
        for limit, interval in pairs(updateIntervals) do
            if(limit <= #players) then
                updateInterval = interval
                updateIntervalLimit = limit
            end
        end

        if(lastIntervalValue ~= updateIntervalLimit) then
            lastIntervalValue = updateIntervalLimit
            print(string.format("[^2BigMode^7] Updated blip update interval to ^2%dms (%d) ^7due to ^2%d ^7players being connected.", updateInterval, updateIntervalLimit, #players))
        end


        -- iterate through the configured sendNames limits and find the one that
        -- best suits the current number of players
        local sendNamesLimit = 0
        for limit, sendName in pairs(sendNames) do
            if(limit <= #players) then
                shouldSendNames = sendName
                sendNamesLimit = limit
            end
        end


        if(#players > 0) then

            -- this is where the heavy-lifting is done in the loop
            -- so we create a new thread so we can quickly move-on without waiting
            Citizen.CreateThread(function()
                local up_begin = GetGameTimer()

                players = GetPlayers()

                local blips = GetBlipsOfPlayers(players)

                -- create another thread to quickly move-on to the next tick
                Citizen.CreateThread(function()
                    for index, player in ipairs(players) do
                        if(DoesEntityExist(GetPlayerPed(player))) then
                            TriggerClientEvent("_bigmode:updateBlips", player, blips)

                            Citizen.Wait(math.clamp(10, updateSpacing, 100))
                        end
                    end
                end)

                lastBlipsUpdate = blips

                -- if threadTimeWarnings is enabled, then calculate the time it took to run this thread
                -- and if its above the threshold then send a warning to the server console
                if(threadTimeWarnings) then
                    local up_loopTime = GetGameTimer() - up_begin
                    if(up_loopTime > updateThreadTimeThreshold) then
                        print(string.format("[^2BigMode^7] Update thread loopTime: ^3%i ms ^7(your server is ^1lagging ^7or ^3updateThreadTimeThreshold ^7is too low)", up_loopTime))
                    end
                end
            end)
        end

        -- if threadTimeWarnings is enabled, then calculate the time it took to run this thread
        -- and if its above the threshold then send a warning to the server console
        if(threadTimeWarnings) then
            local mt_loopTime = GetGameTimer() - mt_begin
            if(mt_loopTime > mainThreadTimeThreshold) then
                print(string.format("[^2BigMode^7] Main thread loopTime: ^1%i ms ^7(your server is ^1lagging ^7or ^1mainThreadTimeThreshold ^7is too low)", mt_loopTime))
            end
        end

        Citizen.Wait(updateInterval)
    end
end)

function GetBlipsOfPlayers(players)
    if DEBUG then
        return GetDebugBlipsOfPlayers()
    else
        return GetRealBlipsOfPlayers(players)
    end
end

-- iterate through the players table above and build an event object
-- that includes the players' server ID and their in-game position
function GetRealBlipsOfPlayers(players)
    local blips = {}
    for index, player in ipairs(players) do
        local playerPed = GetPlayerPed(player)

        -- check if ped exists to refrain from iterating potentially invalid player entities
        -- causes some players to not have blips if not double-checked
        if(DoesEntityExist(playerPed)) then
            local coords = GetEntityCoords(playerPed)

            -- build the blip object
            local obj = {}
            obj[BLIP_INDEX_PLAYER_ID]      = player
            obj[BLIP_INDEX_PED_NETWORK_ID] = NetworkGetNetworkIdFromEntity(playerPed)
            obj[BLIP_INDEX_COORDS]         = { coords.x, coords.y, coords.z }

            if(shouldSendNames) then
                obj[BLIP_INDEX_PLAYER_NAME] = GetPlayerName(player)
            end

            table.insert(blips, obj)
        end
    end

    return blips
end

function GetDebugBlipsOfPlayers()
    local blips = {}
    for i = 1, 1024 do
        local playerPed = -i

        local obj = {}
        obj[BLIP_INDEX_PLAYER_ID]      = -i
        obj[BLIP_INDEX_PED_NETWORK_ID] = -i
        obj[BLIP_INDEX_COORDS]         = { 
            math.random(-200000, 200000)/100.0,
            math.random(-400000, 400000)/100.0 + 1000.0,
            math.random(-100000, 100000)/100.0,
        }

        if(shouldSendNames) then
            obj[BLIP_INDEX_PLAYER_NAME] = 'Fake Player Blip #' .. i
        end

        table.insert(blips, obj)
    end

    return blips
end