import 'dart:io';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

class InfoCommand {
  ChatCommand get infoCommand => ChatCommand(
      'info',
      'Get info about the bot',
      id('info', (IChatContext context) {
        EmbedBuilder infoEmbed = EmbedBuilder()
          ..title = 'Bot Info'
          ..description = 'See technical info'
          ..author = (EmbedAuthorBuilder()..name = 'Jack1221#6744'..url = 'https://github.com/jr1221'..iconUrl = 'https://avatars.githubusercontent.com/u/53871299?v=4')
          ..timestamp = DateTime.now()
          ..addField(name: 'Cached guilds', content: context.client.guilds.length, inline: true)
          ..addField(name: 'Cached users', content: context.client.users.length, inline: true)
          ..addField(name: 'Cached channels', content: context.client.channels.length, inline: true)
          ..addField(
              name: 'Library',
              content: '[Nyxx](https://nyxx.l7ssha.xyz/) v${(context.client as INyxxWebsocket).version}',
              inline: true)
          ..addField(name: 'Shard', content:'${(context.guild?.shard.id ?? 0) + 1} of ${(context.client as INyxxWebsocket).shards}')
          ..addField(
              name: 'Uptime',
              content: (DateTime.now().difference(context.client.startTime)),
              inline: true)
          ..addField(name: 'Memory Usage', content: memoryUsage(), inline: true)
          ..addFooter((footer) {
            footer.text =
            'Dart SDK $platformVersion on $operatingSystemName';
          });

        ComponentMessageBuilder infoResponse = ComponentMessageBuilder()
          ..embeds = [infoEmbed]
          ..addComponentRow(ComponentRowBuilder()
            ..addComponent(
              LinkButtonBuilder(
                'Add Ntfy Connector to your server',
                (context.client as INyxxWebsocket).app.getInviteUrl(),
              ),
            )
            ..addComponent(
                LinkButtonBuilder('Source', 'https://github.com/jr1221/ntfy_discord_bot')));

        context.respond(infoResponse);
      }));

  String memoryUsage() {
    final current = (ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(2);
    final rss = (ProcessInfo.maxRss / 1024 / 1024).toStringAsFixed(2);
    return "$current/${rss}MB";
  }

  String get platformVersion => Platform.version.split("(").first;

  String get operatingSystemName => Platform.operatingSystem.onlyFirstCaps();
}

extension Capitalize on String {
  String onlyFirstCaps() {
    String lowered = toLowerCase();
    return lowered.substring(0, 1).toUpperCase() + lowered.substring(1);
  }
}
