-----------------------------------------------------------------------------
-- rc_chat server — command registration, message routing, moderation
-----------------------------------------------------------------------------

local lastMessageAt   = {}   -- [src] = game timer of last message (anti-spam)
local lastMessageText = {}   -- [src] = { text = string, count = number } (repeat detection)
local commandLastUsed = {}   -- [src] = { [commandName] = os.time() } (per-command cooldowns)
local mutedUntil      = {}   -- [license] = os.time() expiry (0 = until unmuted / restart)

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------

local function debugPrint(...)
    if Config.Debug then
        print('[rc_chat]', ...)
    end
end

-- Escape HTML so player input can never inject markup into the NUI
local function escapeHtml(text)
    return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- Truncate without splitting a UTF-8 codepoint
local function truncate(s, maxChars)
    local len = utf8.len(s)
    if not len then
        return s:sub(1, maxChars)
    end
    if len <= maxChars then
        return s
    end
    return s:sub(1, utf8.offset(s, maxChars + 1) - 1)
end

local function trim(s)
    return (s:gsub('^%s*(.-)%s*$', '%1'))
end

-- System message (gold badge) to one player
local function systemMessage(src, text)
    TriggerClientEvent('rc_chat:message', src, {
        badge = Strings.system,
        color = '#CCAA00',
        text  = text,
    })
end

-- Reply to a command issuer — chat message for players, console print for source 0
local function respond(src, text)
    if src == 0 then
        print('[rc_chat] ' .. text)
    else
        systemMessage(src, text)
    end
end

-- Discord webhook logging
local function sendWebhook(url, text)
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'rc_chat',
        embeds = {{
            description = text,
            color       = 13412864,   -- 0xCCAA00 gold
        }},
    }), { ['Content-Type'] = 'application/json' })
end

-----------------------------------------------------------------------------
-- Player checks
-----------------------------------------------------------------------------

local function hasJob(src, jobs)
    if not jobs or #jobs == 0 then return true end
    local job = Bridge.GetJob(src)
    if not job then return false end
    for _, allowed in ipairs(jobs) do
        if job == allowed then return true end
    end
    return false
end

local function resolveName(src, nameMode)
    if nameMode == 'hidden' then
        return nil
    elseif nameMode == 'character' then
        return Bridge.GetCharacterName(src) or GetPlayerName(src)
    else
        return GetPlayerName(src)
    end
end

-----------------------------------------------------------------------------
-- Chat mute
--
-- Mutes are keyed by license identifier so reconnecting doesn't lift them.
-----------------------------------------------------------------------------

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license') or ('src:%d'):format(src)
end

-- Remaining mute time in minutes (0 = muted until unmuted/restart), or nil if not muted
local function getMuteRemaining(src)
    local license = getLicense(src)
    local expiry = mutedUntil[license]
    if not expiry then return nil end
    if expiry == 0 then return 0 end

    local remaining = expiry - os.time()
    if remaining <= 0 then
        mutedUntil[license] = nil
        return nil
    end
    return math.ceil(remaining / 60)
end

-- If the player is muted, tell them and return true
local function rejectIfMuted(src)
    local remaining = getMuteRemaining(src)
    if not remaining then return false end

    if remaining > 0 then
        systemMessage(src, _L('you_are_muted_timed', remaining))
    else
        systemMessage(src, _L('you_are_muted'))
    end
    return true
end

-----------------------------------------------------------------------------
-- Moderation
-----------------------------------------------------------------------------

local function containsProfanity(text)
    local lowered = text:lower()
    for _, word in ipairs(Config.Profanity.blockedWords) do
        -- match whole words only (frontier pattern: non-alphanumeric boundaries)
        if lowered:find('%f[%w]' .. word:gsub('%W', '%%%0') .. '%f[%W]') then
            return true, word
        end
    end
    return false
end

-- Returns true if the message is allowed to go through
local function passesModeration(src, def, text, isAdmin)
    -- anti-spam: cooldown between messages
    if Config.AntiSpam.enabled and not (Config.AntiSpam.exemptAdmins and isAdmin) then
        local now = GetGameTimer()
        if lastMessageAt[src] and (now - lastMessageAt[src]) < Config.AntiSpam.cooldown then
            systemMessage(src, _L('spam_cooldown'))
            return false
        end

        -- anti-spam: identical message repeated
        local last = lastMessageText[src]
        if last and last.text == text then
            last.count = last.count + 1
            if last.count >= Config.AntiSpam.maxRepeats then
                systemMessage(src, _L('spam_repeated'))
                if Config.AntiSpam.logToConsole then
                    print(('[rc_chat] spam blocked from %s (%d): %s'):format(GetPlayerName(src), src, text))
                end
                sendWebhook(Config.AntiSpam.webhook, _L('log_spam', GetPlayerName(src), src, text))
                return false
            end
        else
            lastMessageText[src] = { text = text, count = 1 }
        end
    end

    -- profanity filter
    if Config.Profanity.enabled and def.blockProfanity and not (Config.Profanity.exemptAdmins and isAdmin) then
        local blocked = containsProfanity(text)
        if blocked then
            systemMessage(src, _L('blocked_profanity'))
            if Config.Profanity.logToConsole then
                print(('[rc_chat] profanity blocked from %s (%d): %s'):format(GetPlayerName(src), src, text))
            end
            sendWebhook(Config.Profanity.webhook, _L('log_profanity', GetPlayerName(src), src, text))
            return false
        end
    end

    return true
end

-----------------------------------------------------------------------------
-- Delivery
-----------------------------------------------------------------------------

local function getDeliveryTargets(src, def)
    -- proximity: players within N metres of the sender
    if def.proximityRadius then
        local targets = {}
        local sourceCoords = GetEntityCoords(GetPlayerPed(src))
        for _, playerId in ipairs(GetPlayers()) do
            local id = tonumber(playerId)
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 then
                if #(GetEntityCoords(ped) - sourceCoords) <= def.proximityRadius then
                    targets[#targets + 1] = id
                end
            end
        end
        return targets
    end

    -- job-restricted delivery (e.g. police radio, EMS calls)
    if def.toJobs then
        local targets = {}
        for _, playerId in ipairs(GetPlayers()) do
            local id = tonumber(playerId)
            if hasJob(id, def.toJobs) or id == src then
                targets[#targets + 1] = id
            end
        end
        return targets
    end

    -- admin-only delivery (staff chat)
    if def.toAdmins then
        local targets = {}
        for _, playerId in ipairs(GetPlayers()) do
            local id = tonumber(playerId)
            if Bridge.IsAdmin(id) or id == src then
                targets[#targets + 1] = id
            end
        end
        return targets
    end

    -- default: broadcast to everyone
    return nil   -- nil = TriggerClientEvent to -1
end

local function deliver(targets, payload)
    if targets == nil then
        TriggerClientEvent('rc_chat:message', -1, payload)
    else
        for _, id in ipairs(targets) do
            TriggerClientEvent('rc_chat:message', id, payload)
        end
    end
end

-----------------------------------------------------------------------------
-- Command handling
-----------------------------------------------------------------------------

local function handleChatCommand(def, src, rawText)
    local isAdmin = Bridge.IsAdmin(src)

    -- muted players can't send anything
    if rejectIfMuted(src) then
        return
    end

    -- permission: admin only
    if def.adminOnly and not isAdmin then
        systemMessage(src, _L('perm_denied'))
        return
    end

    -- permission: job whitelist
    if not hasJob(src, def.jobs) then
        systemMessage(src, _L('perm_denied_job'))
        return
    end

    -- per-command cooldown
    if def.cooldown then
        commandLastUsed[src] = commandLastUsed[src] or {}
        local lastUsed = commandLastUsed[src][def.name]
        if lastUsed then
            local elapsed = os.time() - lastUsed
            if elapsed < def.cooldown then
                systemMessage(src, _L('command_cooldown', def.cooldown - elapsed, def.name))
                return
            end
        end
    end

    -- text validation
    local text = trim(rawText)
    if text == '' then
        systemMessage(src, _L('usage', def.name, def.params or 'message'))
        return
    end
    if utf8.len(text) and utf8.len(text) > Config.MaxMessageLength then
        systemMessage(src, _L('message_too_long', Config.MaxMessageLength))
        return
    end
    text = truncate(text, Config.MaxMessageLength)

    -- moderation
    if not passesModeration(src, def, text, isAdmin) then
        return
    end

    -- sanitize (unless the command explicitly allows HTML and sender is admin)
    if not (def.allowHTML and isAdmin) then
        text = escapeHtml(text)
    end

    -- all checks passed — consume cooldowns
    lastMessageAt[src] = GetGameTimer()
    if def.cooldown then
        commandLastUsed[src][def.name] = os.time()
    end

    -- build payload
    local payload = {
        badge = def.badge or def.name:upper(),
        color = def.color or '#CCAA00',
        name  = resolveName(src, def.nameMode),
        id    = def.showId and src or nil,
        text  = text,
    }

    -- let other resources react / cancel ('rc_chat:messageSent' hook)
    TriggerEvent('rc_chat:messageSent', src, def.name, text)

    -- deliver
    local targets = getDeliveryTargets(src, def)
    deliver(targets, payload)

    debugPrint(('/%s from %s (%d): %s'):format(def.name, GetPlayerName(src), src, text))
end

-- Register every command from the config
CreateThread(function()
    for _, def in ipairs(Config.Commands) do
        RegisterCommand(def.name, function(source, args, rawCommand)
            if source == 0 then return end   -- ignore console
            -- preserve original spacing by stripping the command name off the raw string
            local text = rawCommand:sub(#def.name + 2)
            handleChatCommand(def, source, text)
        end, false)
    end

    -- /clear — clear own chat
    RegisterCommand(Config.ClearCommand, function(source)
        if source == 0 then return end
        TriggerClientEvent('rc_chat:clear', source)
        systemMessage(source, _L('chat_cleared'))
    end, false)

    -- /clearall — clear everyone's chat (admin only)
    RegisterCommand(Config.ClearAllCommand, function(source)
        if source == 0 then return end
        if not Bridge.IsAdmin(source) then
            systemMessage(source, _L('perm_denied'))
            return
        end
        TriggerClientEvent('rc_chat:clear', -1)
        TriggerClientEvent('rc_chat:message', -1, {
            badge = Strings.system,
            color = '#CCAA00',
            text  = _L('chat_cleared_by'),
        })
    end, false)

    -- /mutechat <id> [minutes] — mute a player from chat (admin / console)
    RegisterCommand(Config.Mute.muteCommand, function(source, args)
        if source ~= 0 and not Bridge.IsAdmin(source) then
            systemMessage(source, _L('perm_denied'))
            return
        end

        local targetId = math.tointeger(tonumber(args[1]))
        if not targetId then
            respond(source, _L('mute_usage', Config.Mute.muteCommand))
            return
        end
        if not GetPlayerName(targetId) then
            respond(source, _L('mute_invalid_target', targetId))
            return
        end
        if Bridge.IsAdmin(targetId) then
            respond(source, _L('mute_target_staff'))
            return
        end

        -- whole minutes only; 0 = until unmuted / restart
        local minutes    = math.max(0, math.floor(tonumber(args[2]) or Config.Mute.defaultMinutes))
        local targetName = GetPlayerName(targetId)
        local adminName  = source == 0 and 'Console' or GetPlayerName(source)

        if minutes > 0 then
            mutedUntil[getLicense(targetId)] = os.time() + math.floor(minutes * 60)
            respond(source, _L('mute_applied', targetName, targetId, minutes))
            systemMessage(targetId, _L('mute_received_timed', minutes))
            sendWebhook(Config.Mute.webhook, _L('log_mute', adminName, targetName, targetId, minutes))
        else
            mutedUntil[getLicense(targetId)] = 0
            respond(source, _L('mute_applied_perm', targetName, targetId))
            systemMessage(targetId, _L('mute_received'))
            sendWebhook(Config.Mute.webhook, _L('log_mute_perm', adminName, targetName, targetId))
        end
    end, false)

    -- /unmutechat <id> — lift a chat mute (admin / console)
    RegisterCommand(Config.Mute.unmuteCommand, function(source, args)
        if source ~= 0 and not Bridge.IsAdmin(source) then
            systemMessage(source, _L('perm_denied'))
            return
        end

        local targetId = math.tointeger(tonumber(args[1]))
        if not targetId then
            respond(source, _L('unmute_usage', Config.Mute.unmuteCommand))
            return
        end
        if not GetPlayerName(targetId) then
            respond(source, _L('mute_invalid_target', targetId))
            return
        end

        local license    = getLicense(targetId)
        local targetName = GetPlayerName(targetId)
        if not mutedUntil[license] then
            respond(source, _L('not_muted', targetName, targetId))
            return
        end

        mutedUntil[license] = nil
        respond(source, _L('unmute_applied', targetName, targetId))
        systemMessage(targetId, _L('unmute_received'))

        local adminName = source == 0 and 'Console' or GetPlayerName(source)
        sendWebhook(Config.Mute.webhook, _L('log_unmute', adminName, targetName, targetId))
    end, false)
end)

-----------------------------------------------------------------------------
-- Suggestions — sent to each client when they join
-----------------------------------------------------------------------------

local function buildSuggestions()
    local suggestions = {}
    for _, def in ipairs(Config.Commands) do
        suggestions[#suggestions + 1] = {
            name   = '/' .. def.name,
            help   = def.help or '',
            params = def.params and { { name = def.params, help = '' } } or nil,
        }
    end
    suggestions[#suggestions + 1] = { name = '/' .. Config.ClearCommand, help = _L('clear_help') }
    suggestions[#suggestions + 1] = { name = '/' .. Config.ClearAllCommand, help = _L('clearall_help') }
    suggestions[#suggestions + 1] = {
        name   = '/' .. Config.Mute.muteCommand,
        help   = _L('mutechat_help'),
        params = { { name = 'id', help = '' }, { name = 'minutes', help = '' } },
    }
    suggestions[#suggestions + 1] = {
        name   = '/' .. Config.Mute.unmuteCommand,
        help   = _L('unmutechat_help'),
        params = { { name = 'id', help = '' } },
    }
    return suggestions
end

RegisterNetEvent('rc_chat:ready', function()
    local src = source
    TriggerClientEvent('chat:addSuggestions', src, buildSuggestions())

    -- also suggest commands registered by other server resources (ace-filtered),
    -- same behaviour as the default chat resource
    local ownCommands = {}
    for _, def in ipairs(Config.Commands) do
        ownCommands[def.name] = true
    end
    ownCommands[Config.ClearCommand] = true
    ownCommands[Config.ClearAllCommand] = true
    ownCommands[Config.Mute.muteCommand] = true
    ownCommands[Config.Mute.unmuteCommand] = true

    local extra = {}
    for _, command in ipairs(GetRegisteredCommands()) do
        if not ownCommands[command.name] and IsPlayerAceAllowed(src, ('command.%s'):format(command.name)) then
            extra[#extra + 1] = { name = '/' .. command.name, help = '', hidden = true }
        end
    end
    if #extra > 0 then
        TriggerClientEvent('chat:addSuggestions', src, extra)
    end
end)

-----------------------------------------------------------------------------
-- Console announcements — `say <message>` from the server console / txAdmin
-----------------------------------------------------------------------------

RegisterCommand('say', function(source, _, rawCommand)
    if source ~= 0 then return end   -- console only; players use chat commands
    local text = trim(rawCommand:sub(4))
    if text == '' then return end
    TriggerClientEvent('rc_chat:message', -1, {
        badge = 'CONSOLE',
        color = '#CCAA00',
        text  = escapeHtml(text),
    })
end, true)

-----------------------------------------------------------------------------
-- Typing indicator — relayed only to nearby players
-----------------------------------------------------------------------------

if Config.TypingIndicator.enabled then
    RegisterNetEvent('rc_chat:typing', function(isTyping)
        local src = source
        local sourceCoords = GetEntityCoords(GetPlayerPed(src))
        for _, playerId in ipairs(GetPlayers()) do
            local id = tonumber(playerId)
            if id ~= src then
                local ped = GetPlayerPed(id)
                if ped and ped ~= 0 then
                    if #(GetEntityCoords(ped) - sourceCoords) <= Config.TypingIndicator.distance then
                        TriggerClientEvent('rc_chat:typingUpdate', id, src, GetPlayerName(src), isTyping)
                    end
                end
            end
        end
    end)
end

-----------------------------------------------------------------------------
-- Compatibility with the default chat resource API
-----------------------------------------------------------------------------

-- Legacy plain-message path (other resources may trigger this; players can't,
-- since plain chat is disabled in the NUI)
RegisterNetEvent('_chat:messageEntered', function(author, color, message)
    local src = source
    if not Config.AllowPlainMessages then
        systemMessage(src, _L('plain_disabled'))
        return
    end

    -- muted players can't use plain chat either
    if rejectIfMuted(src) then return end

    -- legacy chatMessage hook — other resources can CancelEvent() to block
    TriggerEvent('chatMessage', src, author, message)
    if WasEventCanceled() then return end

    TriggerClientEvent('rc_chat:message', -1, {
        badge = author,
        color = '#CCAA00',
        text  = escapeHtml(message),
    })
end)

-- Some resources clear chat via the server
RegisterNetEvent('chat:clear', function()
    TriggerClientEvent('rc_chat:clear', source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastMessageAt[src] = nil
    lastMessageText[src] = nil
    commandLastUsed[src] = nil
end)

-----------------------------------------------------------------------------
-- Exports
-----------------------------------------------------------------------------

-- Send a badge message to one player
exports('SendMessageToPlayer', function(playerId, message, color, badge)
    TriggerClientEvent('rc_chat:message', playerId, {
        badge = badge or Strings.system,
        color = color or '#CCAA00',
        text  = tostring(message),
    })
end)

-- Send a badge message to everyone
exports('BroadcastMessage', function(message, color, badge)
    TriggerClientEvent('rc_chat:message', -1, {
        badge = badge or Strings.system,
        color = color or '#CCAA00',
        text  = tostring(message),
    })
end)

-- Send a badge message to players near a source player
exports('SendProximity', function(sourceId, radius, message, color, badge)
    local sourceCoords = GetEntityCoords(GetPlayerPed(sourceId))
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then
            if #(GetEntityCoords(ped) - sourceCoords) <= radius then
                TriggerClientEvent('rc_chat:message', id, {
                    badge = badge or Strings.system,
                    color = color or '#CCAA00',
                    text  = tostring(message),
                })
            end
        end
    end
end)

-- Register an autocomplete suggestion for all players
exports('AddSuggestion', function(name, help, params)
    TriggerClientEvent('chat:addSuggestion', -1, name, help, params)
end)

-- Clear chat for one player (-1 for everyone)
exports('ClearChat', function(playerId)
    TriggerClientEvent('rc_chat:clear', playerId or -1)
end)
