# ntfy_discord_bot

### [Add Ntfy Connector to you server](https://discord.com/api/oauth2/authorize?client_id=1059635059398819953&permissions=0&scope=bot)

This bot allows you to send and poll for messages in the [ntfy](https://ntfy.sh) API.  

Slash Command Features in a channel or DM:
 - Publish messages with all customizations
 - Poll messages with all filters
 - Subscribe to topics with all filters (once per user)

All interface features available on the web or cURL platforms are supported through slash command arguments and modals.  
The modals add a few clicks to actually publishing the message, but allow for greater customization.  

To-do/Features not supported:
 - Re-opening a modal after submitting it. (i.e. you can only change advanced options once without starting over)
 - Preset publishing options on a per-channel or per-user basis
 - Subscriptions that extend past bot lifetimes
 - Subscriptions with multiple independent filtering profiles

### NOTICE: Messages are not encrypted in any way, and can be plainly read on the bot and ntfy API server.  Do not share sensitive data!

### Example of usage (see /help for more info):
https://user-images.githubusercontent.com/53871299/210292190-eeefa801-15f5-4b93-973c-fe2aad2ce25d.mp4

## Configuring

Requirements:
 - A discord dev account with a bot configured
 - Dart version 3.0.0 or greater

Get and unpack the [latest version](https://github.com/jr1221/ntfy_discord_bot/releases) of the source code.

Run the code. Define the discord API token using `--define=API_TOKEN=<YOUR_TOKEN_HERE>`.  Optionally, also define the server ID of which you want to have the commands appear with as `--define=GUILD_ID=<YOUR_GUILD_ID_HERE>`.
Note that if you do not specify a guild, the bot will show slash commands in all servers it is added to.  The downside of this is that it takes one hour for slash command signatures to update/appear in global slash commands.

`dart --define=API_TOKEN=<AAAAAAAAAAAAAAAAAAAAAAA> --define=GUILD_ID=AAAAAAAA ./path/to/project/bin/ntfy_discord_bot.dart`

At this time compiling may be a challenge due to dart:mirrors, see [nyxx-compile](https://github.com/nyxx-discord/nyxx_commands/blob/dev/bin/compile.dart).

### Contributing
Contributions are accepted and encouraged.  Use standard dart format and latest nyxx_commands 5.0 conventions.


