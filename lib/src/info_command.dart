import 'dart:io';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

class InfoCommand {
  final DateTime startupTime;

  InfoCommand({required this.startupTime});

  ChatCommand get infoCommand => ChatCommand(
      'info',
      'Get info about the bot',
      id('info', (ChatContext context) async {
        EmbedBuilder infoEmbed = EmbedBuilder(
            title: 'Bot Info',
            description: 'See technical info',
            author: EmbedAuthorBuilder(
                name: 'Jack1221#6744',
                url: Uri.parse('https://github.com/jr1221'),
                iconUrl: Uri.parse(
                    'https://avatars.githubusercontent.com/u/53871299?v=4')),
            timestamp: DateTime.now(),
            fields: [
              EmbedFieldBuilder(
                  name: 'Cached guilds',
                  value: context.client.guilds.cache.length.toString(),
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Cached users',
                  value: context.client.users.cache.length.toString(),
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Cached channels',
                  value: context.client.channels.cache.length.toString(),
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Library',
                  value:
                      '[Nyxx](${ApiOptions.nyxxRepositoryUrl}) v${ApiOptions.nyxxVersion}',
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Shard',
                  value:
                      '${(context.guild != null ? context.client.gateway.shardIdFor(context.guild?.id ?? Snowflake.zero) + 1 : '-1')} of ${context.client.gateway.shards.length}',
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Uptime',
                  value: (DateTime.now().difference(startupTime)).toString(),
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'To Resp. Latency',
                  value:
                      '${context.client.httpHandler.latency.inMilliseconds}ms',
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'API/Net Latency',
                  value:
                      '${context.client.httpHandler.realLatency.inMilliseconds}ms',
                  isInline: true),
              EmbedFieldBuilder(
                  name: 'Memory Usage', value: memoryUsage(), isInline: true),
            ],
            footer: EmbedFooterBuilder(
                text: 'Dart SDK $platformVersion on $operatingSystemName'));

        List<ActionRowBuilder> components = [
          ActionRowBuilder(components: [
            // TODO invite url button
            ButtonBuilder(
                style: ButtonStyle.link,
                label: 'Source Code',
                url: Uri.parse('https://github.com/jr1221/ntfy_discord_bot')),
          ])
        ];

        MessageBuilder infoResponse =
            MessageBuilder(embeds: [infoEmbed], components: components);

        context.respond(infoResponse);
      }));

  String memoryUsage() {
    final current = (ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(2);
    return '${current}MB';
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
