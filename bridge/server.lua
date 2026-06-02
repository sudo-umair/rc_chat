-----------------------------------------------------------------------------
-- Framework bridge — uniform player API over ESX and QBCore
--
-- Exposes (server-side global):
--   Bridge.Framework            -> 'esx' | 'qb' | 'none'
--   Bridge.GetJob(src)          -> job name string or nil
--   Bridge.IsAdmin(src)         -> boolean
--   Bridge.GetCharacterName(src)-> RP character name or nil
-----------------------------------------------------------------------------

Bridge = {
    Framework = 'none',
}

local ESX, QBCore

local function tryDetectFramework()
    local wantEsx = Config.Framework == 'esx' or Config.Framework == 'auto'
    local wantQb  = Config.Framework == 'qb' or Config.Framework == 'auto'

    if wantEsx and GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Bridge.Framework = 'esx'
        return true
    end

    if wantQb and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Bridge.Framework = 'qb'
        return true
    end

    return false
end

-- the framework may start after rc_chat — keep retrying for a while
CreateThread(function()
    for _ = 1, 60 do
        if tryDetectFramework() then
            if Config.Debug then
                print(('[rc_chat] framework: %s'):format(Bridge.Framework))
            end
            return
        end
        Wait(1000)
    end
    print('[rc_chat] WARNING: no framework detected — job/admin checks will rely on ace permissions only')
end)

-----------------------------------------------------------------------------

function Bridge.GetJob(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            return xPlayer.getJob().name
        end
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            return player.PlayerData.job.name
        end
    end
    return nil
end

function Bridge.IsAdmin(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local group = xPlayer.getGroup()
            for _, allowed in ipairs(Config.AdminGroups.esx) do
                if group == allowed then return true end
            end
        end
    elseif Bridge.Framework == 'qb' then
        for _, allowed in ipairs(Config.AdminGroups.qb) do
            if QBCore.Functions.HasPermission(src, allowed) then return true end
        end
    end
    -- ace permission fallback works on any framework (add_ace group.admin rcchat.admin allow)
    return IsPlayerAceAllowed(src, 'rcchat.admin')
end

function Bridge.GetCharacterName(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            return xPlayer.getName()
        end
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            local info = player.PlayerData.charinfo
            return ('%s %s'):format(info.firstname, info.lastname)
        end
    end
    return nil
end
