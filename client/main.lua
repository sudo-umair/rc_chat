-----------------------------------------------------------------------------
-- rc_chat client — NUI bridge, input handling, compat with default chat API
-----------------------------------------------------------------------------

local chatOpen   = false
local nuiLoaded  = false
local isTyping   = false

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------

local function debugPrint(...)
    if Config.Debug then
        print('[rc_chat]', ...)
    end
end

local function rgbToHex(color)
    if type(color) ~= 'table' then return nil end
    return ('#%02X%02X%02X'):format(
        math.floor(color[1] or 255),
        math.floor(color[2] or 255),
        math.floor(color[3] or 255)
    )
end

local function sendToFeed(payload)
    SendNUIMessage({
        action  = 'addMessage',
        message = payload,
    })
end

-----------------------------------------------------------------------------
-- Settings persistence (KVP)
-----------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    offsetX    = 0,       -- % offset from the default position
    offsetY    = 0,
    fontSize   = 100,     -- % scale
    fontWeight = 300,
    visibility = 'fade',  -- 'fade' (auto-hide) | 'always' (permanent) | 'hidden'
}

local function loadSettings()
    local raw = GetResourceKvpString('rc_chat_settings')
    if raw then
        local ok, parsed = pcall(json.decode, raw)
        if ok and type(parsed) == 'table' then
            return parsed
        end
    end
    return DEFAULT_SETTINGS
end

local function saveSettings(settings)
    SetResourceKvp('rc_chat_settings', json.encode(settings))
end

-----------------------------------------------------------------------------
-- Open / close
-----------------------------------------------------------------------------

local function openChat()
    if chatOpen or not nuiLoaded then return end
    chatOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openInput' })
end

local function closeChat()
    if not chatOpen then return end
    chatOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeInput' })

    if isTyping then
        isTyping = false
        TriggerServerEvent('rc_chat:typing', false)
    end
end

RegisterCommand('rc_chat_open', openChat, false)
RegisterKeyMapping('rc_chat_open', 'Open chat', 'keyboard', 't')

-- Block the chat key while dead / in pause menu
CreateThread(function()
    while true do
        Wait(250)
        if chatOpen and IsPauseMenuActive() then
            closeChat()
        end
    end
end)

-----------------------------------------------------------------------------
-- NUI callbacks
-----------------------------------------------------------------------------

RegisterNUICallback('loaded', function(_, cb)
    nuiLoaded = true

    SendNUIMessage({
        action = 'init',
        config = {
            fadeTimeout      = Config.FadeTimeout,
            suggestionLimit  = Config.SuggestionLimit,
            maxMessageLength = Config.MaxMessageLength,
            maxHistory       = Config.MaxHistory,
            placeholder      = Strings.input_placeholder,
            typingText       = Strings.is_typing,
        },
        settings = loadSettings(),
    })

    -- ask the server for command suggestions
    TriggerServerEvent('rc_chat:ready')
    cb('ok')
end)

RegisterNUICallback('chatResult', function(data, cb)
    closeChat()

    if not data.canceled and data.message and data.message ~= '' then
        local message = data.message

        if message:sub(1, 1) == '/' then
            -- commands are executed through the FiveM command system;
            -- unregistered ones are forwarded to the server automatically
            ExecuteCommand(message:sub(2))
        else
            -- plain chat is disabled
            sendToFeed({
                badge = Strings.system,
                color = '#CCAA00',
                text  = Strings.plain_disabled,
            })
        end
    end

    cb('ok')
end)

RegisterNUICallback('typing', function(data, cb)
    if Config.TypingIndicator.enabled then
        local typing = data.typing == true
        if typing ~= isTyping then
            isTyping = typing
            TriggerServerEvent('rc_chat:typing', typing)
        end
    end
    cb('ok')
end)

RegisterNUICallback('saveSettings', function(data, cb)
    if type(data.settings) == 'table' then
        saveSettings(data.settings)
    end
    cb('ok')
end)

-----------------------------------------------------------------------------
-- Emergency call locations & blips (commands with attachLocation/attachBlip)
-----------------------------------------------------------------------------

-- "Strawberry Ave, Davis" from world coordinates
local function resolveLocationText(location)
    local streetHash = GetStreetNameAtCoord(location.x, location.y, location.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local zone = GetLabelText(GetNameOfZone(location.x, location.y, location.z))

    if zone == 'NULL' then zone = nil end
    if street == '' then street = nil end

    if street and zone and street ~= zone then
        return ('%s, %s'):format(street, zone)
    end
    return street or zone or Strings.location_unknown
end

-- Temporary flashing blip at the caller's position
local function createCallBlip(location, label)
    local cfg = Config.CallBlip
    local blip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, false)
    if cfg.flash then
        SetBlipFlashes(blip, true)
    end

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or '15')
    EndTextCommandSetBlipName(blip)

    SetTimeout(cfg.duration * 1000, function()
        RemoveBlip(blip)
    end)
end

-----------------------------------------------------------------------------
-- rc_chat events
-----------------------------------------------------------------------------

RegisterNetEvent('rc_chat:message', function(payload)
    if payload.location then
        if payload.location.showStreet then
            payload.locationText = resolveLocationText(payload.location)
        end
        if payload.location.blip then
            createCallBlip(payload.location, payload.badge)
        end
    end
    sendToFeed(payload)
end)

RegisterNetEvent('rc_chat:clear', function()
    SendNUIMessage({ action = 'clear' })
end)

RegisterNetEvent('rc_chat:typingUpdate', function(playerId, playerName, typing)
    SendNUIMessage({
        action = 'typingUpdate',
        id     = playerId,
        name   = playerName,
        typing = typing,
    })
end)

-----------------------------------------------------------------------------
-- Compatibility with the default chat resource API
--
-- Other resources (including es_extended) talk to the chat through these
-- events / exports. They keep working unchanged.
-----------------------------------------------------------------------------

-- chat:addMessage supports several payload shapes:
--   'plain string'
--   { args = { 'message' } }
--   { args = { 'author', 'message' }, color = { r, g, b }, multiline = true }
--   { template = '<div>...</div>', args = { ... } }
local function convertLegacyMessage(message)
    if type(message) == 'string' then
        return { text = message, escape = true }
    end

    if type(message) ~= 'table' then return nil end

    local payload = {
        color     = rgbToHex(message.color),
        multiline = message.multiline,
        template  = message.template,
        escape    = true,   -- legacy payloads are not pre-escaped; the NUI escapes them
    }

    local args = message.args or {}
    if #args >= 2 then
        payload.badge = tostring(args[1])
        local parts = {}
        for i = 2, #args do
            parts[#parts + 1] = tostring(args[i])
        end
        payload.text = table.concat(parts, ' ')
    elseif #args == 1 then
        payload.text = tostring(args[1])
    else
        payload.text = ''
    end

    -- templates receive the raw args for {0} {1} substitution
    if message.template then
        payload.templateArgs = args
    end

    return payload
end

local function addMessage(message)
    local payload = convertLegacyMessage(message)
    if payload then
        sendToFeed(payload)
    end
end

RegisterNetEvent('chat:addMessage', addMessage)
exports('addMessage', addMessage)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    SendNUIMessage({
        action     = 'addSuggestion',
        suggestion = { name = name, help = help or '', params = params },
    })
end)

RegisterNetEvent('chat:addSuggestions', function(suggestions)
    for _, suggestion in ipairs(suggestions) do
        SendNUIMessage({
            action     = 'addSuggestion',
            suggestion = suggestion,
        })
    end
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    SendNUIMessage({
        action = 'removeSuggestion',
        name   = name,
    })
end)

RegisterNetEvent('chat:addTemplate', function(id, html)
    SendNUIMessage({
        action   = 'addTemplate',
        id       = id,
        template = html,
    })
end)

RegisterNetEvent('chat:clear', function()
    SendNUIMessage({ action = 'clear' })
end)

-----------------------------------------------------------------------------
-- Register suggestions for locally-registered commands of other resources
-- (same behaviour as the default chat resource)
-----------------------------------------------------------------------------

CreateThread(function()
    -- wait for the NUI to be ready before pushing suggestions
    while not nuiLoaded do Wait(100) end
    Wait(500)

    local registered = GetRegisteredCommands()
    for _, command in ipairs(registered) do
        -- skip our own internal command
        if command.name ~= 'rc_chat_open' then
            SendNUIMessage({
                action     = 'addSuggestion',
                suggestion = { name = '/' .. command.name, help = '', hidden = true },
            })
        end
    end
end)
