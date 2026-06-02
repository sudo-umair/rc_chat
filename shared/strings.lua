-----------------------------------------------------------------------------
-- All user-facing text in one place
-----------------------------------------------------------------------------

Strings = {
    -- System badge
    system = 'SYSTEM',

    -- Input
    input_placeholder = 'Type a /command...',

    -- Errors / hints (sent as system messages)
    plain_disabled       = 'Plain chat is disabled — use a command like /ooc, /me or /twt. Type / to see all commands.',
    unknown_command      = 'Unknown command: /%s',
    usage                = 'Usage: /%s <%s>',
    message_too_long     = 'Message too long (max %d characters).',
    perm_denied          = 'You do not have permission to use this command.',
    perm_denied_job      = 'You do not have the required job to use this command.',
    blocked_profanity    = 'Your message contains blocked words and was not sent.',
    blocked_html         = 'Your message was blocked for containing disallowed code.',
    spam_cooldown        = 'You are sending messages too quickly.',
    spam_repeated        = 'Stop repeating the same message.',
    command_cooldown     = 'You must wait %d more seconds before using /%s again.',
    chat_cleared         = 'Chat cleared.',
    chat_cleared_by      = 'Chat was cleared by staff.',

    -- Chat mute
    you_are_muted        = 'You are muted from chat.',
    you_are_muted_timed  = 'You are muted from chat for %d more minute(s).',
    mute_usage           = 'Usage: /%s <player id> [minutes]',
    unmute_usage         = 'Usage: /%s <player id>',
    mute_invalid_target  = 'No player online with id %d.',
    mute_target_staff    = 'You cannot mute another staff member.',
    mute_applied         = 'Muted %s (id %d) for %d minute(s).',
    mute_applied_perm    = 'Muted %s (id %d) until unmuted or server restart.',
    mute_received_timed  = 'You have been muted from chat by staff for %d minute(s).',
    mute_received        = 'You have been muted from chat by staff.',
    unmute_applied       = 'Unmuted %s (id %d).',
    unmute_received      = 'You have been unmuted — you can use the chat again.',
    not_muted            = '%s (id %d) is not muted.',

    -- Emergency call location
    location_unknown = 'Unknown location',

    -- Typing indicator
    is_typing = 'is typing...',

    -- Command help (clear/clearall/mute)
    clear_help      = 'Clear your own chat window',
    clearall_help   = 'Clear the chat for every player (staff only)',
    mutechat_help   = 'Mute a player from chat (staff only)',
    unmutechat_help = 'Unmute a player (staff only)',

    -- Discord log lines
    log_profanity  = 'Player **%s** (id %d) tried to send profanity: "%s"',
    log_spam       = 'Player **%s** (id %d) is spamming: "%s"',
    log_mute       = 'Staff **%s** muted **%s** (id %d) for %d minute(s)',
    log_mute_perm  = 'Staff **%s** muted **%s** (id %d) until unmuted or restart',
    log_unmute     = 'Staff **%s** unmuted **%s** (id %d)',
}

-- _L('usage', 'ooc', 'message') -> 'Usage: /ooc <message>'
function _L(key, ...)
    local str = Strings[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end
