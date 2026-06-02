# rc_chat

Royal City Roleplay's chat for FiveM — a full, open replacement for the default `chat`
resource with badge-styled commands, moderation, a settings panel and a typing indicator.

![FiveM](https://img.shields.io/badge/FiveM-resource-orange) ![Lua](https://img.shields.io/badge/Lua-5.4-blue)

Built from scratch (no escrow, no encrypted files) to replace `jc_chat`.

## Features

- **Full `chat` replacement** — implements the default chat API (`chat:addMessage`,
  `chat:addSuggestion(s)`, `chat:removeSuggestion`, `chat:addTemplate`, `chat:clear`,
  `chatMessage`, `_chat:messageEntered`), so ESX and every other resource keep working unchanged
- **Badge-styled messages** — every command renders with its own colored badge
  (OOC, TWEET, POLICE, EMS, STAFF, …) in the Royal City gold/dark theme
- **Config-driven commands** — add a command purely in `config.lua`: badge, color,
  proximity radius, job whitelist, admin-only, per-command cooldown, delivery targeting
- **Command-only chat** — plain (non-command) chat is disabled; players get a hint to use `/ooc`, `/twt`, …
- **Emergency calls** — `/911` (police) and `/912` (EMS) reach only on-duty units, with the
  caller's street attached and a temporary flashing blip on the responders' map
- **Moderation** — profanity filter, anti-spam (cooldown + repeat detection), staff chat
  mute (`/mutechat`), Discord webhook logging, admin exemptions
- **Autocomplete suggestions** — command list with help text while typing, Tab to complete,
  arrow keys to navigate, sent-message history with ↑/↓
- **Typing indicator** — players within 8m see "<name> is typing…"
- **Settings panel** — chat position, font size and weight; persisted per player (KVP)
- **Idle fade** — the feed fades out ~10s after the last message; `T` brings it back
- **ESX + QBCore** — framework auto-detected; ace-permission fallback for standalone

## Installation

1. Drop `rc_chat` into your server's `resources` folder
2. **Remove / comment out the default chat** and jc_chat from your `server.cfg`:
   ```cfg
   # ensure chat        <- remove
   # ensure jc_chat     <- remove
   ensure rc_chat
   ```
3. Adjust `config.lua` to taste

> `fxmanifest.lua` declares `provide 'chat'`, so resources that depend on `chat` will
> accept `rc_chat` as a stand-in.

## Default commands

| Command | Badge | Delivery | Restriction |
|---|---|---|---|
| `/ooc` | OOC | everyone | — |
| `/oocl` | OOC LOCAL | 15 m proximity | — |
| `/do` | DO | 15 m proximity | — |
| `/twt` | TWEET | everyone | — |
| `/anon` | ANON TWEET (no name) | everyone | — |
| `/rpol` | POLICE RADIO | police only | `police` job |
| `/police` | POLICE | everyone | `police` job |
| `/ems` | EMS | everyone | `ambulance` job |
| `/mechanic` | MECHANIC | everyone | `mechanic` job |
| `/911` | 911 | police only + street + map blip | 30 s cooldown |
| `/912` | 912 | ambulance only + street + map blip | 30 s cooldown |
| `/adminchat` | STAFF | admins only | admin groups |
| `/clear` | — | clear own chat | — |
| `/clearall` | — | clear everyone's chat | admin groups |
| `/mutechat <id> [minutes]` | — | mute a player from chat | admin groups |
| `/unmutechat <id>` | — | lift a chat mute | admin groups |

> `/me` is intentionally not included — `rc_me` already provides it as 3D bubbles.
> If you don't run `rc_me`, add a `me` entry to `Config.Commands`.

## Adding a command

Add an entry to `Config.Commands` in `config.lua` — no code changes needed:

```lua
{
    name            = 'darkweb',          -- /darkweb
    help            = 'Send an anonymous darkweb message',
    params          = 'message',
    badge           = 'DARKWEB',
    color           = '#A78BFA',
    nameMode        = 'hidden',           -- 'fivem' | 'character' | 'hidden'
    showId          = false,              -- show sender server id
    -- sending restrictions
    jobs            = nil,                -- { 'police' } to job-restrict
    adminOnly       = false,
    cooldown        = nil,                -- seconds between uses
    -- delivery (default = broadcast)
    proximityRadius = nil,                -- only nearby players receive it
    toJobs          = nil,                -- only these jobs receive it
    toAdmins        = false,              -- only admins receive it
    -- moderation
    allowHTML       = false,
    blockProfanity  = true,
    -- location (emergency calls)
    attachLocation  = false,              -- append the sender's street / area to the message
    attachBlip      = false,              -- receivers get a temporary map blip (see Config.CallBlip)
}
```

## Admin permissions

Admin checks accept any of:

- ESX group in `Config.AdminGroups.esx` (default: `mod`, `admin`, `superadmin`)
- QBCore permission in `Config.AdminGroups.qb` (default: `mod`, `admin`, `god`)
- ace permission `rcchat.admin` (works standalone):
  ```cfg
  add_ace group.admin rcchat.admin allow
  ```

## Server exports

```lua
-- send a badge message to one player
exports.rc_chat:SendMessageToPlayer(playerId, message, color, badge)

-- send a badge message to everyone
exports.rc_chat:BroadcastMessage(message, color, badge)

-- send a badge message to players within radius of a player
exports.rc_chat:SendProximity(sourceId, radius, message, color, badge)

-- register an autocomplete suggestion
exports.rc_chat:AddSuggestion('/mycommand', 'Help text', { { name = 'param', help = '' } })

-- clear chat (playerId or -1 for everyone)
exports.rc_chat:ClearChat(playerId)
```

## Events for other resources

```lua
-- fired server-side whenever a player successfully sends a chat command
AddEventHandler('rc_chat:messageSent', function(source, commandName, text)
    -- e.g. log /twt messages to Discord
end)
```

The standard `chat:addMessage` client event also works exactly like the default chat:

```lua
TriggerClientEvent('chat:addMessage', playerId, {
    args = { 'Dispatch', 'Robbery in progress at Fleeca Bank' },
    color = { 255, 100, 100 },
})
```

## Configuration reference

| Section | Purpose |
|---|---|
| `Config.Framework` | `'auto'` (default), `'esx'` or `'qb'` |
| `Config.AdminGroups` | groups treated as staff |
| `Config.MaxMessageLength` | character limit per message |
| `Config.FadeTimeout` | ms before the feed fades out |
| `Config.AntiSpam` | cooldown, repeat detection, webhook |
| `Config.Profanity` | blocked word list, webhook |
| `Config.Mute` | mute/unmute command names, default duration, webhook |
| `Config.CallBlip` | sprite, color, flash and lifetime of emergency call blips |
| `Config.TypingIndicator` | enable + distance |
| `Config.Commands` | the command table (see above) |

## File structure

```
rc_chat/
├── fxmanifest.lua
├── config.lua            <- everything you'd want to edit
├── shared/strings.lua    <- all user-facing text
├── bridge/server.lua     <- ESX / QBCore abstraction
├── server/main.lua       <- routing, moderation, compat, exports
├── client/main.lua       <- NUI bridge, keybind, compat events
└── html/
    ├── index.html
    ├── style.css          <- Royal City theme
    └── script.js
```
