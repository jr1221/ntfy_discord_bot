part of 'ntfy_commands.dart';

ChatGroup get subscribeCommand =>
    ChatGroup('subscribe', 'Configure bot responses when a message is sent',
        children: [
          ChatCommand(
              'initiate',
              'Create a new subscription, overwriting old one!',
              id('subscribe-initiate', (ChatContext context,
                  @Name('topic')
                  @Description('topic or topics to listen to, comma separated')
                  String topics,
                  [@Name('channel')
                  @Description(
                      'channel to send messages to, or blank for this channel')
                  TextChannel? channel,
                  @Name('dm')
                  @Description('send messages to DM instead of channel')
                  bool useDM = false]) async {
                // provision to delete current stream if initiate is called twice, basically calls clear
                if (ntfyCommand.streamLine[context.user] != null) {
                  await ntfyCommand.notifyStreamRemove(context.user);
                }

                if (topics.split(',').isNotEmpty) {
                  TextChannel sendPlace;
                  if (useDM) {
                    sendPlace =
                        (await context.user.manager.createDm(context.user.id));
                  } else {
                    sendPlace = (channel ?? context.channel);
                  }
                  ntfyCommand.streamQueue[context.user] = StreamWrapper(
                      topics.split(','),
                      sendPlace,
                      await ntfyCommand.getBasepath(context));
                } else {
                  await context.respond(MessageBuilder(
                      content: 'Could not parse topics, please try again.'));
                  return;
                }
                await ntfyCommand.sendFilterSelection(context, false);
              })),
          ChatCommand(
              'get',
              'See the current subscription',
              id('subscribe-get', (ChatContext context) {
                final opts = ntfyCommand.streamQueue[context.user];
                if (opts != null) {
                  final embed = EmbedBuilder(
                      author: EmbedAuthorBuilder(
                          iconUrl: context.user.avatar.url,
                          name: context.user.globalName ?? ' '),
                      color: NtfyCommand.priorityToDiscordColor(
                          // use last priority or none to get estimate of what is being filtered
                          opts.filters?.priority?.last ??
                              ntfy_lib.PriorityLevels.none),
                      url: Uri.tryParse('${opts.basePath}${opts.topics.last}'),
                      title: opts.topics.toString(),
                      description: 'Filters:');

                  if (opts.filters?.id != null) {
                    embed.fields?.add(EmbedFieldBuilder(
                        name: 'ID',
                        isInline: false,
                        value: opts.filters!.id.toString()));
                  }
                  if (opts.filters?.message != null) {
                    embed.fields?.add(EmbedFieldBuilder(
                        name: 'Message',
                        isInline: false,
                        value: opts.filters!.message.toString()));
                  }
                  if (opts.filters?.priority != null) {
                    embed.fields?.add(EmbedFieldBuilder(
                        name: 'Priorities',
                        isInline: false,
                        value: (opts.filters!.priority!.fold<String>(
                                '',
                                (previousValue, element) =>
                                    '$previousValue, ${element.name}'))
                            .substring(2)));
                  }
                  if (opts.filters?.tags != null) {
                    embed.fields?.add(EmbedFieldBuilder(
                        name: 'Tags',
                        isInline: false,
                        value: opts.filters!.tags!.join(', ')));
                  }
                  if (opts.filters?.title != null) {
                    embed.fields?.add(EmbedFieldBuilder(
                        name: 'Title',
                        isInline: false,
                        value: opts.filters!.title.toString()));
                  }

                  context.respond(MessageBuilder(embeds: [embed]));
                } else {
                  context.respond(
                      MessageBuilder(content: 'No subscription configured'));
                }
              })),
          ChatCommand(
              'clear',
              'Clear current subscription',
              id('subscribe-clear', (ChatContext context) {
                ntfyCommand.notifyStreamRemove(context.user);
                context.respond(MessageBuilder(
                    content: 'Subscription successfully cleared'));
              })),
        ]);
