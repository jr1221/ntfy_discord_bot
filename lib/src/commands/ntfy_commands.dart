import 'dart:async';

import 'package:ntfy_discord_bot/src/db/database.dart';
import 'package:ntfy_discord_bot/src/wrappers.dart';

import '../ntfy_interface.dart';
import 'package:ntfy_dart/ntfy_dart.dart' as ntfy_lib;
import 'package:nyxx/nyxx.dart' hide MessageResponse;
import 'package:nyxx_commands/nyxx_commands.dart';

part 'help.dart';
part 'server.dart';
part 'publish.dart';
part 'poll.dart';
part 'subscribe.dart';

/// global ntfyCommand object
final ntfyCommand = NtfyCommand();

class NtfyCommand {
  /// Converts multiple messages received from the API into one sendable discord nyxx message builder, for poll use only
  static MessageBuilder _messagesToDiscordComponents(
      List<ntfy_lib.MessageResponse> messages) {
    List<EmbedBuilder> embeds = [];
    String? content;

    // ensure messages are less than 10, and greater than zero, then trim and notify.
    if (messages.length > 10) {
      content =
          'Cannot show ${messages.length - 10} additional messages, please filter for them!';
      messages.removeRange(10, messages.length);
    } else if (messages.isEmpty) {
      content = 'There are no cached messages to display!';
    }

    // add embeds for each message, reversed to ensure correct newer first, (cant reverse earlier because of trim)
    for (final message in messages.reversed) {
      embeds.add(messageToEmbed(message));
    }

    MessageBuilder response = MessageBuilder(embeds: embeds, content: content);
    return response;
  }

  /// Converts a message received from the ntfy API into a pretty discord message
  static EmbedBuilder messageToEmbed(ntfy_lib.MessageResponse message) {
    EmbedBuilder embed = EmbedBuilder(
        author: EmbedAuthorBuilder(name: message.topic),
        timestamp: message.time,
        title: message.title,
        description: message.message,
        url: Uri.tryParse(message.click?.toString() ?? ''),
        footer: EmbedFooterBuilder(text: message.id));

    if (message.priority != null) {
      embed.color = priorityToDiscordColor(message.priority!);
    }

    if (message.tags != null) {
      embed.fields?.add(EmbedFieldBuilder(
          name: 'Tags', value: message.tags!.join(','), isInline: false));
    }
    if (message.attachment != null) {
      embed.fields?.add(EmbedFieldBuilder(
          name: message.attachment!.name,
          value: message.attachment!.url.toString(),
          isInline: false));
    }
    if (message.actions != null) {
      for (final action in message.actions!) {
        switch (action.action) {
          case ntfy_lib.ActionTypes.view:
            embed.fields?.add(EmbedFieldBuilder(
                name: action.label,
                value: '(view action) ${action.url}',
                isInline: false));
            break;
          case ntfy_lib.ActionTypes.broadcast:
            embed.fields?.add(EmbedFieldBuilder(
                name: action.label,
                value:
                    '(broadcast action) ${action.intent == null ? '' : 'intent: ${action.intent}'}. ${action.extras == null ? '' : 'extras: ${action.extras}'} ',
                isInline: false));
            break;
          case ntfy_lib.ActionTypes.http:
            embed.fields?.add(EmbedFieldBuilder(
                name: action.label,
                value:
                    '(http action) ${action.method ?? 'POST'} ${action.url}. ${action.headers == null ? '' : 'headers: ${action.headers}'}. ${action.body == null ? '' : 'body: ${action.body}'}.',
                isInline: false));
            break;
        }
      }
    }
    if (message.expires != null) {
      embed.fields?.add(EmbedFieldBuilder(
          name: 'Expire time',
          value: message.expires!.toLocal().toString(),
          isInline: false));
    }

    return embed;
  }

  /// Fetches the discord color corresponding the PriorityLevel given in the MessageResponse
  static DiscordColor priorityToDiscordColor(
      ntfy_lib.PriorityLevels priorityLevel) {
    return DiscordColor.fromRgb(1, 1, 1);
    /* TODO
    return switch (priorityLevel) {
    
    n.PriorityLevels.min =>
         DiscordColor.gray;
       n.PriorityLevels.low =>
         DiscordColor.green;
       n.PriorityLevels.none =>
         DiscordColor.none;
       n.PriorityLevels.high =>
         DiscordColor.orange;
       n.PriorityLevels.max =>
         DiscordColor.red;
    }; */
  }

  // the class wrapping the underlying API library
  final State state = State();

  // the queue of subcriptions to be begun or in progress
  final Map<User, StreamWrapper> streamQueue = {};

  // the queue of poll queries to be made
  final Map<User, PollWrapper> pollQueue = {};

  // the index of currently open subscriptions
  final Map<User, StreamSubscription<ntfy_lib.MessageResponse>> streamLine = {};

  // TODO actually run this code
  Future<void> shutdown() async {
    state.dispose();
    await database.close();
  }

  Future<Uri> getBasepath(ChatContext context) async {
    return Uri.parse((await database
                .fetchBasepathDirective(context.guild?.id ?? context.user.id))
            ?.basePath ??
        'https://ntfy.sh/');
  }

  Future<void> updateBasepath(ChatContext context, String changedUrl) async {
    await database.updateBasepath(
        context.guild?.id ?? context.user.id, changedUrl);
  }

  // listen to the stream and index it appropriately in _streamLine
  void notifyStreamAdd(User user, Stream<ntfy_lib.MessageResponse> stream) {
    streamLine[user] = stream.listen((event) {
      if (event.event == ntfy_lib.EventTypes.message) {
        final messageEmbed = messageToEmbed(event);
        streamQueue[user]!.sendPlace.sendMessage(MessageBuilder(
            embeds: [messageEmbed],
            content: 'Subscribed message, send `/subscribe clear` to cancel'));
      }
    });
  }

  // close out the stream listen and remove it from the index (_streamLine) and the filter queue (_streamQueue)
  Future<void> notifyStreamRemove(User user) async {
    await streamLine[user]?.cancel();
    streamQueue.remove(user);
    streamLine.remove(user);
  }

  /// build the filter selection message, ugily abstracted for both polling and subscribing
  Future<void> sendFilterSelection(ChatContext context, bool isPoll) async {
    // the queue, abstracted from both PollWrapper and StreamWrapper, set based on isPoll
    Map<User, ParentWrapper> queue;

    // the button that ends the interaction, different based on isPoll
    String terminationButtonLabel;

    if (isPoll) {
      queue = pollQueue;
      terminationButtonLabel = 'Fetch';
    } else {
      queue = streamQueue;
      terminationButtonLabel = 'Subscribe';
    }

    final filterButtonId = ComponentId.generate();
    final prioritySelectId = ComponentId.generate();
    final endButtonId = ComponentId.generate();

    MessageBuilder askOpts = MessageBuilder(components: [
      ActionRowBuilder(components: [
        SelectMenuBuilder(
            type: MessageComponentType.stringSelect,
            customId: prioritySelectId.toString(),
            options: [
              SelectMenuOptionBuilder(label: 'minimum', value: 'min'),
              SelectMenuOptionBuilder(label: 'low', value: 'low'),
              SelectMenuOptionBuilder(label: 'none', value: 'none'),
              SelectMenuOptionBuilder(label: 'high', value: 'high'),
              SelectMenuOptionBuilder(label: 'maximum', value: 'max'),
            ],
            placeholder: 'Choose priority(s) to filter by',
            maxValues: 4),
      ]),
      ActionRowBuilder(components: [
        ButtonBuilder(
            label: terminationButtonLabel,
            customId: endButtonId.toString(),
            style: ButtonStyle.primary),
        ButtonBuilder(
            label: 'More filters',
            customId: filterButtonId.toString(),
            style: ButtonStyle.secondary)
      ])
    ]);

    context.respond(askOpts);

    final tempFilter = MutableFilterOptions();

    final ComponentId filterInputMessageId = ComponentId.generate();
    final ComponentId filterInputTitleId = ComponentId.generate();
    final ComponentId filterInputTagsId = ComponentId.generate();
    final ComponentId filterInputIdId = ComponentId.generate();
    // handle poll filter button, responding with modal
    context.awaitButtonPress(filterButtonId).then(
          (event) => event.getModal(
            title: 'Add filters',
            components: [
              (TextInputBuilder(
                  customId: filterInputMessageId.toString(),
                  style: TextInputStyle.paragraph,
                  label: 'By message',
                  placeholder: 'Enter exact message to filter by...',
                  isRequired: false)),
              (TextInputBuilder(
                  customId: filterInputTitleId.toString(),
                  style: TextInputStyle.short,
                  label: 'By title',
                  placeholder: 'Enter exact title to filter by...',
                  isRequired: false)),
              (TextInputBuilder(
                  customId: filterInputTagsId.toString(),
                  style: TextInputStyle.short,
                  label: 'By tag(s)',
                  placeholder:
                      'Enter comma separated list of tags to filter by...',
                  isRequired: false)),
              (TextInputBuilder(
                  customId: filterInputIdId.toString(),
                  style: TextInputStyle.short,
                  label: 'By ID',
                  placeholder: 'Enter exact message ID to filter by...',
                  isRequired: false)),
            ],
          ) // handle filter modal, responding with confirmation
              .then(
            (event) {
              tempFilter
                ..message =
                    event[filterInputMessageId.toString()]!.emptyToNull()
                ..title = event[filterInputTitleId.toString()]!.emptyToNull()
                ..tags = event[filterInputTagsId.toString()]!
                    .emptyToNull()
                    ?.split(',')
                ..id = event[filterInputIdId.toString()]!.emptyToNull();

              event.respond(MessageBuilder(content: 'Filters saved'));
            },
          ),
        );

    // handle priorities multiselect, responding with confirmation
    context.awaitMultiSelection<String>(prioritySelectId).then(
      (event) {
        // makes priority listings pretty by stripping enum class name
        final priorities = event.selected
            .map<ntfy_lib.PriorityLevels>(
                (e) => ntfy_lib.PriorityLevels.values.byName(e.toLowerCase()))
            .toList();

        tempFilter.priority = priorities;

        event.respond(MessageBuilder(content: 'Priority(s) saved!'));
      },
    );

    // handle fetch button, responding with the results of the server poll
    context.awaitButtonPress(endButtonId).then(
      (event) async {
        if (queue[event.user] != null) {
          queue[event.user]!.filters = tempFilter.generate();
          // if poll, construct polling response, respond, and remove query from queue
          if (isPoll) {
            final polled = await state.poll(
                pollQueue[event.user]!, await getBasepath(context));

            event.respond(
                _messagesToDiscordComponents(polled.reversed.toList()));
            pollQueue.remove(event.user);
          } else {
            // if subscribe, fetch stream and notify a construction of a listener, then confirm
            final stream = await state.get(
                streamQueue[event.user]!, await getBasepath(context));
            notifyStreamAdd(event.user, stream);
            event.respond(MessageBuilder(content: 'Successfully subscribed'));
          }
        }
      },
    );
  }

  /// Root list of commands associated with the bot
  List<ChatCommandComponent> get commands => [
        helpCommand,
        serverCommand,
        publishCommand,
        pollCommand,
        subscribeCommand,
      ];
}

extension on String {
  String? emptyToNull() {
    return isNotEmpty ? this : null;
  }
}
