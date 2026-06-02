Config = {}

-----------------------------------------------------------------------------
-- General
-----------------------------------------------------------------------------

Config.Debug = false   -- print diagnostics to server & client (F8) consoles

-- Framework: 'auto' detects es_extended / qb-core at runtime
Config.Framework = 'auto'   -- 'auto' | 'esx' | 'qb'

-- Groups that count as "admin" for adminOnly commands, /clearall and
-- moderation exemptions
Config.AdminGroups = {
    esx = { 'mod', 'admin', 'superadmin' },
    qb  = { 'mod', 'admin', 'god' },
}

-----------------------------------------------------------------------------
-- Chat behaviour
-----------------------------------------------------------------------------

Config.MaxMessageLength = 144     -- max characters in a single message
Config.MaxHistory       = 100     -- messages kept in the NUI feed
Config.FadeTimeout      = 10000   -- ms after the last message before the feed fades out
Config.SuggestionLimit  = 5       -- max autocomplete suggestions shown while typing

-- Plain text (no command) is disabled: players must always use a /command.
-- When they try anyway, they get this hint (see locales).
Config.AllowPlainMessages = false

-----------------------------------------------------------------------------
-- Anti-spam
-----------------------------------------------------------------------------

Config.AntiSpam = {
    enabled        = true,
    cooldown       = 1000,   -- min ms between messages per player
    maxRepeats     = 3,      -- identical messages in a row before blocking
    exemptAdmins   = true,
    logToConsole   = true,
    webhook        = '',     -- Discord webhook URL for spam reports ('' = disabled)
}

-----------------------------------------------------------------------------
-- Profanity filter
-----------------------------------------------------------------------------

Config.Profanity = {
    enabled      = true,
    exemptAdmins = false,
    logToConsole = true,
    webhook      = '',       -- Discord webhook URL for blocked messages ('' = disabled)
    blockedWords = {
        -- Spanish
        'puta', 'mierda', 'pendejo', 'cabrón', 'cabron', 'gilipollas', 'imbecil',
        'marica', 'maricon', 'perra', 'concha', 'hdp', 'puto', 'zorra', 'culero',
        'pelotudo', 'pendeja', 'mongolo', 'hijo de puta', 'hijoputa', 'hijo de perra',
        'concha de tu madre', 'conchetumadre', 'pajero', 'boludo', 'forro',
        'chupapija', 'malparido', 'polla', 'coño', 'puta madre', 'putamadre',
        'hijueputa', 'culiao', 'culiado', 'qliao', 'qlo', 'weon', 'huevon', 'mamon',
        'pinga', 'malnacido', 'putita', 'putazo', 'puton', 'zorrita',
        'ptm', 'lpm', 'ctm', 'vrg',
        -- English
        'fuck', 'fucking', 'motherfucker', 'wtf', 'shit', 'bitch', 'cunt', 'dick',
        'pussy', 'asshole', 'bastard', 'retard', 'retarded', 'whore', 'slut',
        'son of a bitch', 'sonofabitch', 'dumbass', 'jackass', 'dickhead',
        'faggot', 'fag', 'nigger', 'nigga', 'cocksucker', 'prick', 'cock', 'twat',
        'wanker', 'jerkoff', 'shithead', 'dickface', 'fuckface', 'scumbag',
    },
}

-----------------------------------------------------------------------------
-- Chat mute — staff can mute individual players from chat
-----------------------------------------------------------------------------

Config.Mute = {
    muteCommand    = 'mutechat',     -- /mutechat <id> [minutes]
    unmuteCommand  = 'unmutechat',   -- /unmutechat <id>
    defaultMinutes = 10,             -- duration when no minutes argument is given (0 = until unmuted / restart)
    webhook        = '',             -- Discord webhook URL for mute/unmute actions ('' = disabled)
}

-----------------------------------------------------------------------------
-- Emergency call blips — used by commands with attachBlip = true (/911)
-----------------------------------------------------------------------------

Config.CallBlip = {
    sprite   = 1,      -- blip icon (https://docs.fivem.net/docs/game-references/blips/)
    color    = 1,      -- 1 = red
    scale    = 1.0,
    flash    = true,   -- flash when the blip first appears
    duration = 60,     -- seconds before the blip disappears from the map
}

-----------------------------------------------------------------------------
-- Typing indicator — nearby players see "<name> is typing..."
-----------------------------------------------------------------------------

Config.TypingIndicator = {
    enabled  = true,
    distance = 8.0,    -- metres
}

-----------------------------------------------------------------------------
-- Commands
--
-- Every chat command is defined here — no code changes needed to add one.
--
-- Fields:
--   name           : the command players type (without the slash)
--   help           : description shown in the autocomplete suggestion
--   params         : name of the expected parameter (shown in suggestion)
--   badge          : text shown in the colored badge (defaults to name uppercased)
--   color          : badge accent color (hex)
--   nameMode       : 'fivem' (player/FiveM name) | 'character' (RP name) | 'hidden'
--   showId         : show the sender's server id next to the badge
--
-- Sending restrictions:
--   jobs           : only these jobs may send (nil = everyone)
--   adminOnly      : only Config.AdminGroups members may send
--   cooldown       : per-command per-player cooldown in seconds (nil = none)
--
-- Delivery (default = broadcast to everyone):
--   proximityRadius: only players within N metres receive it
--   toJobs         : only players with one of these jobs receive it
--   toAdmins       : only admins receive it
--
-- Moderation:
--   allowHTML      : allow raw HTML in the message (dangerous — admins only)
--   blockProfanity : run the message through the profanity filter
--
-- Location (emergency calls):
--   attachLocation : append the sender's street / area to the message
--   attachBlip     : receivers get a temporary map blip at the sender's
--                    position (see Config.CallBlip); the sender gets no blip
-----------------------------------------------------------------------------

Config.Commands = {
    {
        name           = 'ooc',
        help           = 'Out-of-character global chat',
        params         = 'message',
        badge          = 'OOC',
        color          = '#CCAA00',
        nameMode       = 'fivem',
        showId         = true,
        blockProfanity = true,
    },
    {
        name            = 'oocl',
        help            = 'Out-of-character local chat (nearby players only)',
        params          = 'message',
        badge           = 'OOC LOCAL',
        color           = '#2DD4BF',
        nameMode        = 'fivem',
        showId          = true,
        proximityRadius = 15.0,
        blockProfanity  = true,
    },
    -- NOTE: /me is intentionally NOT defined here — rc_me already registers it
    -- (3D bubbles above the player). Registering it twice would make both fire.
    -- If you don't run rc_me, add a 'me' entry following the same pattern as 'do'.
    {
        name            = 'do',
        help            = 'Describe the environment or scene',
        params          = 'message',
        badge           = 'DO',
        color           = '#4ADE80',
        nameMode        = 'character',
        proximityRadius = 15.0,
        blockProfanity  = false,
    },
    {
        name           = 'twt',
        help           = 'Send a tweet',
        params         = 'message',
        badge          = 'TWEET',
        color          = '#38BDF8',
        nameMode       = 'character',
        blockProfanity = true,
    },
    {
        name           = 'anon',
        help           = 'Send an anonymous tweet',
        params         = 'message',
        badge          = 'ANON',
        color          = '#94A3B8',
        nameMode       = 'hidden',
        blockProfanity = true,
    },
    {
        name           = 'rpol',
        help           = 'Internal police radio',
        params         = 'message',
        badge          = 'POLICE RADIO',
        color          = '#818CF8',
        nameMode       = 'character',
        showId         = true,
        jobs           = { 'police' },
        toJobs         = { 'police' },
        blockProfanity = false,
    },
    {
        name           = 'police',
        help           = 'Police announcement to the whole city',
        params         = 'message',
        badge          = 'POLICE',
        color          = '#60A5FA',
        nameMode       = 'character',
        jobs           = { 'police' },
        blockProfanity = false,
    },
    {
        name           = 'ems',
        help           = 'EMS announcement to the whole city',
        params         = 'message',
        badge          = 'EMS',
        color          = '#F87171',
        nameMode       = 'character',
        jobs           = { 'ambulance' },
        blockProfanity = false,
    },
    {
        name           = 'mechanic',
        help           = 'Mechanic announcement to the whole city',
        params         = 'message',
        badge          = 'MECHANIC',
        color          = '#FB923C',
        nameMode       = 'character',
        jobs           = { 'mechanic' },
        blockProfanity = false,
    },
    {
        name           = '911',
        help           = 'Call the police — only on-duty officers see the call',
        params         = 'message',
        badge          = '911',
        color          = '#3B82F6',
        nameMode       = 'character',
        showId         = true,
        toJobs         = { 'police' },
        cooldown       = 30,
        blockProfanity = true,
        attachLocation = true,
        attachBlip     = true,
    },
    {
        name           = '912',
        help           = 'Call EMS — only on-duty medics see the call',
        params         = 'message',
        badge          = '912',
        color          = '#EF4444',
        nameMode       = 'character',
        showId         = true,
        toJobs         = { 'ambulance' },
        cooldown       = 30,
        blockProfanity = true,
        attachLocation = true,
        attachBlip     = true,
    },
    {
        name           = 'adminchat',
        help           = 'Staff-only chat',
        params         = 'message',
        badge          = 'STAFF',
        color          = '#C084FC',
        nameMode       = 'fivem',
        showId         = true,
        adminOnly      = true,
        toAdmins       = true,
        allowHTML      = false,
        blockProfanity = false,
    },
}

-----------------------------------------------------------------------------
-- Utility commands (not message commands)
-----------------------------------------------------------------------------

Config.ClearCommand    = 'clear'      -- clear your own chat
Config.ClearAllCommand = 'clearall'   -- clear chat for everyone (admin only)
