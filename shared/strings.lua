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

    -- Typing indicator
    is_typing = 'is typing...',

    -- Command help (clear/clearall)
    clear_help    = 'Clear your own chat window',
    clearall_help = 'Clear the chat for every player (staff only)',

    -- Discord log lines
    log_profanity = 'Player **%s** (id %d) tried to send profanity: "%s"',
    log_spam      = 'Player **%s** (id %d) is spamming: "%s"',
}

-- _L('usage', 'ooc', 'message') -> 'Usage: /ooc <message>'
function _L(key, ...)
    local str = Strings[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end
