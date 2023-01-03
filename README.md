# ntfy_discord_bot

### [Add Ntfy Connector to you server](https://discord.com/api/oauth2/authorize?client_id=1059635059398819953&permissions=0&scope=bot)

This bot allows you to send and poll for messages in the [ntfy](https://ntfy.sh) API.  

Slash Command Features:
 - Publish messages with all customizations
 - Poll messages with all filters

All interface features are supported through slash command arguments and modals.  It is cumbersome but helpful if you would like to send or check notifications in a discord channel.

Subscribing to messages as they come in is not supported, and probably will not be.  Feel free to PR or fork to figure this out.
It probably requires some internal DB of the different streams, as well as a full add/delete/view of such streams on a per-user basis.
I may get around to trying this, but not for a while.

### 
NOTICE: Messages are not encrypted in any way, and can be plainly read on the bot and ntfy API server.  Do not share sensitive data!
