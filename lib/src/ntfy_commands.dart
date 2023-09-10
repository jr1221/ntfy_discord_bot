import 'dart:async';

import 'package:ntfy_discord_bot/src/db/database.dart';
import 'package:ntfy_discord_bot/src/wrappers.dart';

import './ntfy_interface.dart';
import 'package:ntfy_dart/ntfy_dart.dart' as ntfy;
import 'package:nyxx/nyxx.dart' hide MessageResponse;
import 'package:nyxx_commands/nyxx_commands.dart';

class NtfyCommand {
  // the class wrapping the underlying API library
  final State _state = State();

  // the queue of subcriptions to be begun or in progress
  final Map<User, StreamWrapper> _streamQueue = {};

  // the queue of poll queries to be made
  final Map<User, PollWrapper> _pollQueue = {};

  // the index of currently open subscriptions
  final Map<User, StreamSubscription<ntfy.MessageResponse>> _streamLine = {};

  // db
  final ConfDatabase database = ConfDatabase();

  NtfyCommand();

  // TODO actually run this code
  Future<void> shutdown(NyxxGateway client) async {
    _state.dispose();
    await database.close();
    await client.close();
  }

  // listen to the stream and index it appropriately in _streamLine
  void _notifyStreamAdd(User user, Stream<ntfy.MessageResponse> stream) {
    _streamLine[user] = stream.listen((event) {
      if (event.event == ntfy.EventTypes.message) {
        final messageEmbed = _messageToEmbed(event);
        _streamQueue[user]!.sendPlace.sendMessage(MessageBuilder(
            embeds: [messageEmbed],
            content: 'Subscribed message, send `/subscribe clear` to cancel'));
      }
    });
  }

  // close out the stream listen and remove it from the index (_streamLine) and the filter queue (_streamQueue)
  Future<void> _notifyStreamRemove(User user) async {
    await _streamLine[user]?.cancel();
    _streamQueue.remove(user);
    _streamLine.remove(user);
  }

  Future<Uri> _getBasepath(ChatContext context) async {
    return Uri.parse((await database
                .fetchBasepathDirective(context.guild?.id ?? context.user.id))
            ?.basePath ??
        'https://ntfy.sh/');
  }

  Future<void> _updateBasepath(ChatContext context, String changedUrl) async {
    await database.updateBasepath(
        context.guild?.id ?? context.user.id, changedUrl);
  }

  /// Converts multiple messages received from the API into one sendable discord nyxx message builder, for poll use only
  static MessageBuilder _messagesToDiscordComponents(
      List<ntfy.MessageResponse> messages) {
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
      embeds.add(_messageToEmbed(message));
    }

    MessageBuilder response = MessageBuilder(embeds: embeds, content: content);
    return response;
  }

  /// Converts a message received from the ntfy API into a pretty discord message
  static EmbedBuilder _messageToEmbed(ntfy.MessageResponse message) {
    EmbedBuilder embed = EmbedBuilder(
        author: EmbedAuthorBuilder(name: message.topic),
        timestamp: message.time,
        title: message.title,
        description: message.message,
        url: Uri.tryParse(message.click?.toString() ?? ''),
        footer: EmbedFooterBuilder(text: message.id));

    if (message.priority != null) {
      embed.color = _priorityToDiscordColor(message.priority!);
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
          case ntfy.ActionTypes.view:
            embed.fields?.add(EmbedFieldBuilder(
                name: action.label,
                value: '(view action) ${action.url}',
                isInline: false));
            break;
          case ntfy.ActionTypes.broadcast:
            embed.fields?.add(EmbedFieldBuilder(
                name: action.label,
                value:
                    '(broadcast action) ${action.intent == null ? '' : 'intent: ${action.intent}'}. ${action.extras == null ? '' : 'extras: ${action.extras}'} ',
                isInline: false));
            break;
          case ntfy.ActionTypes.http:
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
  static DiscordColor _priorityToDiscordColor(
      ntfy.PriorityLevels priorityLevel) {
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

  /// build the filter selection message, ugily abstracted for both polling and subscribing
  Future<void> _sendFilterSelection(ChatContext context, bool isPoll) async {
    // the queue, abstracted from both PollWrapper and StreamWrapper, set based on isPoll
    Map<User, ParentWrapper> queue;

    // the button that ends the interaction, different based on isPoll
    String terminationButtonLabel;

    if (isPoll) {
      queue = _pollQueue;
      terminationButtonLabel = 'Fetch';
    } else {
      queue = _streamQueue;
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
            .map<ntfy.PriorityLevels>(
                (e) => ntfy.PriorityLevels.values.byName(e.toLowerCase()))
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
            final polled = await _state.poll(
                _pollQueue[event.user]!, await _getBasepath(context));

            event.respond(
                _messagesToDiscordComponents(polled.reversed.toList()));
            _pollQueue.remove(event.user);
          } else {
            // if subscribe, fetch stream and notify a construction of a listener, then confirm
            final stream = await _state.get(
                _streamQueue[event.user]!, await _getBasepath(context));
            _notifyStreamAdd(event.user, stream);
            event.respond(MessageBuilder(content: 'Successfully subscribed'));
          }
        }
      },
    );
  }

  /// Root list of commands associated with the bot
  List<ChatCommandComponent> get commands => [
        ChatCommand(
            'help',
            'Get info about ntfy connector',
            id('help', (ChatContext context) {
              EmbedBuilder aboutEmbed =
                  EmbedBuilder(title: 'About Ntfy', fields: [
                EmbedFieldBuilder(
                    name: 'What can this do?',
                    value:
                        'This feature can send push notifications to phones, websites, and other internet connected devices using the ntfy software suite',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'How do I get started?',
                    value:
                        'Read the below info, then use /publish and set the topic name to send your first message, and receive messages on the devices using the download links below',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'Topics',
                    value:
                        'Each ntfy message is sent to a topic which the receiver decides to listen to. '
                        ' It can be named anything, but anyone can also use this topic name and send messages to you, so pick something hard to guess!',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'Send a message',
                    value:
                        'Use /publish to send a message, inputting your topic.  A screen will be sent back askng for extra configurations.  '
                        'These basic options are self explanatory',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'Receive a message on device',
                    value:
                        'To receive the message you send, use the web, android, or ios apps (or the API described on the site) and add your unique topic when prompted',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'Receive a message on discord',
                    value:
                        'To receive messages live, use /subscribe.  Only one initiate request is active at once, but multiple topcis can be listened to.',
                    isInline: false),
                EmbedFieldBuilder(
                    name: 'More tips',
                    value:
                        'Messages are usually not stored for a long period of time, so your receiver must be on and setup BEFORE you publish. To get old messages, use the /poll option.  '
                        'NOTICE: Messages are not encrypted in any way, and can be plainly read on the bot and ntfy API server.  Do not share sensitive data!',
                    isInline: false)
              ]);

              MessageBuilder aboutResponse = MessageBuilder(embeds: [
                aboutEmbed
              ], components: [
                ActionRowBuilder(components: [
                  ButtonBuilder(
                      style: ButtonStyle.link,
                      label: 'Web receiver',
                      url: Uri.parse('https://ntfy.sh/app')),
                  ButtonBuilder(
                      style: ButtonStyle.link,
                      label: 'Android receiver',
                      url: Uri.parse(
                          'https://play.google.com/store/apps/details?id=io.heckel.ntfy')),
                  ButtonBuilder(
                      style: ButtonStyle.link,
                      label: 'IOS receiver',
                      url: Uri.parse(
                          'https://apps.apple.com/us/app/ntfy/id1625396347')),
                  ButtonBuilder(
                      style: ButtonStyle.link,
                      label: 'Ntfy Site',
                      url: Uri.parse('https://ntfy.sh/'))
                ])
              ]);

              context.respond(aboutResponse);
            })),
        ChatGroup(
          'server',
          'View and modify the server URL, saved per-guild',
          children: [
            ChatCommand(
              'set',
              'Set the server URL',
              id('server-set', (ChatContext context,
                  @Description('new ntfy URL') String changedUrl) async {
                if (Uri.tryParse(changedUrl) == null) {
                  context.respond(MessageBuilder(
                      content: 'Url $changedUrl improperly formatted!'));
                } else {
                  await _updateBasepath(context, changedUrl);
                  context.respond(MessageBuilder(
                      content:
                          'Server successfully changed to $changedUrl !  This is saved on a per-guild basis, or per-user if it is a DM.'));
                }
              }),
            ),
            ChatCommand(
                'get',
                'Get the server URL',
                id('server-get', (ChatContext context) async {
                  context.respond(MessageBuilder(
                      content:
                          'The server URL is: ${await _getBasepath(context)}'));
                })),
            ChatCommand(
                'reset',
                'Reset the server URL to default (ntfy.sh)',
                id('server-reset', (ChatContext context) async {
                  await _updateBasepath(context, 'https://ntfy.sh/');
                  context.respond(MessageBuilder(
                      content:
                          'Server successfully changed to https://ntfy.sh/ !  This is saved on a per-guild basis, or per-user if it is a DM.'));
                })),
          ],
        ),
        ChatCommand(
            'publish',
            'Send a message',
            id('publish', (
              ChatContext context,
              @Description('Unique topic name') String topic, [
              @Description('schedule message to send at ISO 8601 date')
              DateTime? schedSet,
              @Description('cache values on server') bool? cache,
              @Description('use FCM to send messages') bool? firebase,
              @Description('number to call (pro/self hosted feature)')
              String? call,
            ]) async {
              final publishPrioritySelectId = ComponentId.generate();
              final publishButtonId = ComponentId.generate();
              final publishOptsButtonId = ComponentId.generate();
              final publishAdvOptsButtonId = ComponentId.generate();
              final publishViewActionButtonId = ComponentId.generate();
              final publishBroadcastActionButtonId = ComponentId.generate();
              final publishHttpActionButtonId = ComponentId.generate();

              // add topic, cache, delay, and firebase to message
              // _publishQueue[context.user] =

              final tempPubMessage = MutablePublishableMessage(topic: topic)
                ..cache = cache
                ..firebase = firebase
                ..call = call
                ..delay = schedSet;

              MessageBuilder askOps = MessageBuilder(
                  content:
                      'Configure your message below: (can only click each button once).',
                  components: [
                    ActionRowBuilder(components: [
                      SelectMenuBuilder(
                          type: MessageComponentType.stringSelect,
                          customId: publishPrioritySelectId.toString(),
                          options: [
                            SelectMenuOptionBuilder(
                                label: 'minimum', value: 'min'),
                            SelectMenuOptionBuilder(label: 'low', value: 'low'),
                            SelectMenuOptionBuilder(
                                label: 'none',
                                value: 'none',
                                description: 'Default'),
                            SelectMenuOptionBuilder(
                                label: 'high', value: 'high'),
                            SelectMenuOptionBuilder(
                                label: 'maximum', value: 'max'),
                          ],
                          placeholder: '(Optional) Select a priority level')
                    ]),
                    ActionRowBuilder(components: [
                      ButtonBuilder(
                          style: ButtonStyle.danger,
                          label: 'View',
                          customId: publishViewActionButtonId.toString()),
                      ButtonBuilder(
                        style: ButtonStyle.danger,
                        label: 'Broadcast',
                        customId: publishBroadcastActionButtonId.toString(),
                      ),
                      ButtonBuilder(
                        style: ButtonStyle.danger,
                        label: 'HTTP',
                        customId: publishHttpActionButtonId.toString(),
                      )
                    ]),
                    ActionRowBuilder(components: [
                      ButtonBuilder(
                        style: ButtonStyle.primary,
                        label: 'Publish',
                        customId: publishButtonId.toString(),
                      ),
                      ButtonBuilder(
                        style: ButtonStyle.primary,
                        label: 'Customize',
                        customId: publishOptsButtonId.toString(),
                      ),
                      ButtonBuilder(
                        style: ButtonStyle.primary,
                        label: 'Advanced',
                        customId: publishAdvOptsButtonId.toString(),
                      )
                    ])
                  ]);

              await context.respond(askOps);

              // handle priority selection, responding with confirmation
              context
                  .awaitSelection<String>(publishPrioritySelectId)
                  .then((event) {
                tempPubMessage.priority = ntfy.PriorityLevels.values
                    .byName(event.selected.toLowerCase());
                event.acknowledge();
              });

              final ComponentId publishOptsInputMessageId =
                  ComponentId.generate();
              final ComponentId publishOptsInputTitleId =
                  ComponentId.generate();
              final ComponentId publishOptsInputTagsId = ComponentId.generate();
              final ComponentId publishOptsInputAttachmentId =
                  ComponentId.generate();
              final ComponentId publishOptsInputFilenameId =
                  ComponentId.generate();

              // handle customize (opts) button, responding with modal
              context.awaitButtonPress(publishOptsButtonId).then((event) =>
                  event.getModal(
                    title: 'Create message',
                    components: [
                      TextInputBuilder(
                          customId: publishOptsInputMessageId.toString(),
                          style: TextInputStyle.paragraph,
                          label: 'Message',
                          isRequired: false,
                          placeholder: 'Enter message here...'),
                      TextInputBuilder(
                          customId: publishOptsInputTitleId.toString(),
                          style: TextInputStyle.short,
                          label: 'Title',
                          isRequired: false,
                          placeholder: 'Enter title here...'),
                      TextInputBuilder(
                          customId: publishOptsInputTagsId.toString(),
                          style: TextInputStyle.short,
                          label: 'Tags & Emojis',
                          isRequired: false,
                          placeholder: 'Enter comma seperated list here...'),
                      TextInputBuilder(
                          customId: publishOptsInputAttachmentId.toString(),
                          style: TextInputStyle.short,
                          label: 'URL of Attachment',
                          isRequired: false,
                          placeholder: 'Enter URL of attachment here...'),
                      TextInputBuilder(
                          customId: publishOptsInputFilenameId.toString(),
                          style: TextInputStyle.short,
                          label: 'Filename of attachment',
                          isRequired: false,
                          placeholder: 'Enter filename of attachment here...'),
                    ],
                  ) // handle opts modal, responding with confirmation
                      .then((event) async {
                    tempPubMessage.message =
                        event[publishOptsInputMessageId.toString()]!
                            .emptyToNull();
                    event[publishOptsInputMessageId.toString()];
                    tempPubMessage.title =
                        event[publishOptsInputTitleId.toString()]!
                            .emptyToNull();
                    tempPubMessage.tags =
                        event[publishOptsInputTagsId.toString()]!
                            .emptyToNull()
                            ?.split(',');

                    // if empty return null else return Uri.tryParse attachment url
                    tempPubMessage.attach = event[
                                    publishOptsInputAttachmentId.toString()]!
                                .emptyToNull() ==
                            null
                        ? null
                        : Uri.tryParse(
                            event[publishOptsInputAttachmentId.toString()]!);

                    tempPubMessage.filename =
                        event[publishOptsInputFilenameId.toString()]!
                            .emptyToNull();

                    await event.respond(MessageBuilder(
                        content:
                            'Info saved.  Remember to click Publish to send your message!'));
                  }));

              final ComponentId publishAdvOptsInputEmailId =
                  ComponentId.generate();
              final ComponentId publishAdvOptsInputClickId =
                  ComponentId.generate();
              final ComponentId publishAdvOptsInputIconId =
                  ComponentId.generate();
              final ComponentId publishAdvOptsInputAuthUsernameId =
                  ComponentId.generate();
              final ComponentId publishAdvOptsInputAuthPasswordId =
                  ComponentId.generate();
              // handle advanced opts button, responding with modal
              context.awaitButtonPress(publishAdvOptsButtonId).then((event) =>
                  event.getModal(
                    title: 'Advanced options',
                    components: [
                      TextInputBuilder(
                          customId: publishAdvOptsInputEmailId.toString(),
                          style: TextInputStyle.short,
                          label: 'Email',
                          isRequired: false,
                          placeholder: 'Enter email to be notified here...'),
                      TextInputBuilder(
                          customId: publishAdvOptsInputClickId.toString(),
                          style: TextInputStyle.short,
                          label: 'Click URL',
                          isRequired: false,
                          placeholder:
                              'Enter url to open when clicked on android...'),
                      TextInputBuilder(
                          customId: publishAdvOptsInputIconId.toString(),
                          style: TextInputStyle.short,
                          label: 'Icon URL',
                          isRequired: false,
                          placeholder: 'Enter icon URL to see on android...'),
                      TextInputBuilder(
                          customId:
                              publishAdvOptsInputAuthUsernameId.toString(),
                          style: TextInputStyle.short,
                          label: 'Authorization',
                          isRequired: false,
                          placeholder: 'Enter username here...'),
                      TextInputBuilder(
                          customId:
                              publishAdvOptsInputAuthPasswordId.toString(),
                          style: TextInputStyle.short,
                          label: ' ',
                          isRequired: false,
                          placeholder: 'Enter password here...'),
                    ],
                  ) // handle adv opts modal, responding with confirmation
                      .then((event) {
                    String extraProblems = '';

                    tempPubMessage.email =
                        event[publishAdvOptsInputEmailId.toString()]!
                            .emptyToNull();

                    // if Uri.tryParse click url is null, add notif to extra problems
                    tempPubMessage.click = Uri.tryParse(
                        event[publishAdvOptsInputClickId.toString()]!);
                    if (tempPubMessage.click == null) {
                      extraProblems += 'Invalid click URL\n';
                    }

                    // if icon is empty return null else return Uri.tryParse icon
                    tempPubMessage.icon =
                        event[publishAdvOptsInputIconId.toString()]!
                                    .emptyToNull() ==
                                null
                            ? null
                            : Uri.tryParse(
                                event[publishAdvOptsInputIconId.toString()]!);

                    // if auth user + password not empty add auth
                    if (event[publishAdvOptsInputAuthUsernameId.toString()]!
                            .isNotEmpty &&
                        event[publishAdvOptsInputAuthUsernameId.toString()]!
                            .isNotEmpty) {
                      tempPubMessage.basicAuthorization = (
                        username: event[
                            publishAdvOptsInputAuthUsernameId.toString()]!,
                        password:
                            event[publishAdvOptsInputAuthUsernameId.toString()]!
                      );
                      // if one or other auth user + password not empty notif that auth set failed
                    } else if (event[
                                publishAdvOptsInputAuthUsernameId.toString()]!
                            .isNotEmpty ||
                        event[publishAdvOptsInputAuthPasswordId.toString()]!
                            .isNotEmpty) {
                      extraProblems +=
                          'Must give username and password for auth!\n'; // TODO support access token
                    }

                    event.respond(MessageBuilder(
                        content:
                            '$extraProblems Advanced info saved.  Remember to click Publish to send your message!'));
                  }));

              final ComponentId publishViewActionInputLabelId =
                  ComponentId.generate();
              final ComponentId publishViewActionInputUrlId =
                  ComponentId.generate();
              final ComponentId publishViewActionInputClearId =
                  ComponentId.generate();
              // handle view action button, responding with modal
              context.awaitButtonPress(publishViewActionButtonId).then(
                  (event) =>
                      event.getModal(title: 'Add view action', components: [
                        TextInputBuilder(
                            customId: publishViewActionInputLabelId.toString(),
                            style: TextInputStyle.short,
                            label: 'Label',
                            isRequired: true,
                            placeholder: 'Enter action button label...'),
                        TextInputBuilder(
                            customId: publishViewActionInputUrlId.toString(),
                            style: TextInputStyle.short,
                            label: 'URL',
                            isRequired: true,
                            placeholder: 'Enter URL to open...'),
                        TextInputBuilder(
                            customId: publishViewActionInputClearId.toString(),
                            style: TextInputStyle.short,
                            label: 'Clear?',
                            isRequired: false,
                            placeholder:
                                'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle view modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        Uri? url;
                        bool? clear;

                        // notif of url invalid
                        url = Uri.tryParse(
                            event[publishViewActionInputUrlId.toString()]!);
                        if (url == null) {
                          extraProblems += 'Invalid URL\n';
                        }

                        // parse clear to true or false, set to default false if failure
                        if (event[publishViewActionInputClearId.toString()]!
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[
                                    publishViewActionInputClearId.toString()]!
                                .toLowerCase() ==
                            'false') {
                          clear = false;
                        } else {
                          extraProblems +=
                              'Invalid clear (not true or false)\n';
                          clear = false;
                        }

                        //  url not null (since valid one required), send confirmation, else send warning
                        if (url != null) {
                          tempPubMessage.actions.add(ntfy.Action.viewAction(
                              label: event[
                                  publishViewActionInputLabelId.toString()]!,
                              url: url,
                              clear: clear));

                          await event.respond(MessageBuilder(
                              content:
                                  '$extraProblems View action saved.  Remember to click Publish to send your message!'));
                        } else {
                          await event.respond(MessageBuilder(
                              content:
                                  '$extraProblems Failure: Please resend command and change your input to try again!'));
                        }
                      }));

              final ComponentId publishBroadcastActionInputLabelId =
                  ComponentId.generate();
              final ComponentId publishBroadcastActionInputIntentId =
                  ComponentId.generate();
              final ComponentId publishBroadcastActionInputExtrasId =
                  ComponentId.generate();
              final ComponentId publishBroadcastActionInputClearId =
                  ComponentId.generate();
              // handle broadcast button, responding with modal
              context.awaitButtonPress(publishBroadcastActionButtonId).then(
                  (event) => event
                          .getModal(title: 'Add broadcast action', components: [
                        TextInputBuilder(
                            customId:
                                publishBroadcastActionInputLabelId.toString(),
                            style: TextInputStyle.short,
                            label: 'Label',
                            isRequired: true,
                            placeholder: 'Enter action button label...'),
                        TextInputBuilder(
                            customId:
                                publishBroadcastActionInputIntentId.toString(),
                            style: TextInputStyle.short,
                            label: 'Intent',
                            isRequired: true,
                            placeholder:
                                'Enter android intent name (default io.heckel.ntfy.USER_ACTION)...'),
                        TextInputBuilder(
                            customId:
                                publishBroadcastActionInputExtrasId.toString(),
                            style: TextInputStyle.short,
                            label: 'Extras',
                            isRequired: true,
                            placeholder:
                                'Enter android intent extras as <param>=<value>,<param>=<value>...'),
                        TextInputBuilder(
                            customId:
                                publishBroadcastActionInputClearId.toString(),
                            style: TextInputStyle.short,
                            label: 'Clear?',
                            isRequired: false,
                            placeholder:
                                'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle broadcast modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        // parse clear setting to default (false) and notif if not parsed
                        bool? clear;
                        if (event[publishBroadcastActionInputClearId
                                    .toString()]!
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[publishBroadcastActionInputClearId
                                    .toString()]!
                                .toLowerCase() ==
                            'false') {
                          clear = false;
                        } else {
                          extraProblems +=
                              'Invalid clear (not true or false)\n';
                          clear = false;
                        }

                        // parse extras, warning if not parsed, null if not present
                        Map<String, String>? extras = {};
                        if (event[
                                publishBroadcastActionInputExtrasId.toString()]!
                            .isNotEmpty) {
                          try {
                            for (final splitComma in event[
                                    publishBroadcastActionInputExtrasId
                                        .toString()]!
                                .split(',')) {
                              extras[splitComma.split('=').first] =
                                  splitComma.split('=').last;
                            }
                          } catch (_) {
                            extraProblems +=
                                'Error parsing extras.  Ensure format is correct\n';
                            extras = null;
                          }
                        } else {
                          extras = null;
                        }

                        // add action with parsed
                        tempPubMessage.actions.add(ntfy.Action.broadcastAction(
                          label: event[
                              publishBroadcastActionInputLabelId.toString()]!,
                          intent: event[
                              publishBroadcastActionInputIntentId.toString()],
                          extras: extras,
                          clear: clear,
                        ));
                        await event.respond(MessageBuilder(
                            content:
                                '$extraProblems View action saved.  Remember to click Publish to send your message!'));
                      }));

              final ComponentId publishHttpActionInputLabelId =
                  ComponentId.generate();
              final ComponentId publishHttpActionInputUrlId =
                  ComponentId.generate();
              final ComponentId publishHttpActionInputHeadersId =
                  ComponentId.generate();
              final ComponentId publishHttpActionInputBodyId =
                  ComponentId.generate();
              final ComponentId publishHttpActionInputClearId =
                  ComponentId.generate();
              // handle http button, responding with modal
              context.awaitButtonPress(publishHttpActionButtonId).then(
                  (event) =>
                      event.getModal(title: 'Add HTTP action', components: [
                        TextInputBuilder(
                            customId: publishHttpActionInputLabelId.toString(),
                            style: TextInputStyle.short,
                            label: 'Label',
                            isRequired: true,
                            placeholder: 'Enter action button label...'),
                        TextInputBuilder(
                            customId: publishHttpActionInputUrlId.toString(),
                            style: TextInputStyle.short,
                            label: 'URL',
                            isRequired: true,
                            placeholder: 'Enter URL to open...'),
                        TextInputBuilder(
                            customId:
                                publishHttpActionInputHeadersId.toString(),
                            style: TextInputStyle.short,
                            label: 'Headers',
                            isRequired: false,
                            placeholder:
                                'Enter headers as <param>=<value>,<param>=<value>...'),
                        TextInputBuilder(
                            customId: publishHttpActionInputBodyId.toString(),
                            style: TextInputStyle.short,
                            label: 'Body',
                            isRequired: false,
                            placeholder: 'Enter http body...'),
                        TextInputBuilder(
                            customId: publishHttpActionInputClearId.toString(),
                            style: TextInputStyle.short,
                            label: 'Clear?',
                            isRequired: false,
                            placeholder:
                                'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle http modal, responding with confirmation
                          .then((httpModalEvent) async {
                        // if url valid (since required) continue
                        if (Uri.tryParse(httpModalEvent[
                                publishHttpActionInputUrlId.toString()]!) !=
                            null) {
                          String extraProblems = '';

                          // parse clear, if fail set to default (false) and notif
                          bool clear;
                          if (httpModalEvent[
                                      publishHttpActionInputClearId.toString()]!
                                  .toLowerCase() ==
                              'true') {
                            clear = true;
                          } else if (httpModalEvent[
                                      publishHttpActionInputClearId.toString()]!
                                  .toLowerCase() ==
                              'false') {
                            clear = false;
                          } else if ((httpModalEvent[
                                  publishHttpActionInputClearId.toString()]!)
                              .isNotEmpty) {
                            extraProblems +=
                                'Invalid clear (not true or false)\n';
                            clear = false;
                          } else {
                            clear = false;
                          }

                          // parse headers, if empty null, if fail notif and set to null
                          Map<String, String>? headers = {};
                          if (httpModalEvent[
                                  publishHttpActionInputHeadersId.toString()]!
                              .isNotEmpty) {
                            try {
                              for (final splitComma in httpModalEvent[
                                      publishHttpActionInputHeadersId
                                          .toString()]!
                                  .split(',')) {
                                headers[splitComma.split('=').first] =
                                    splitComma.split('=').last;
                              }
                            } catch (_) {
                              extraProblems +=
                                  'Error parsing headers.  Ensure format is correct\n';
                              headers = null;
                            }
                          } else {
                            headers = null;
                          }

                          // handle http action select and add HTTP action, responding with confirmation
                          httpModalEvent.getSelection<String>(
                              ['POST', 'PUT', 'GET'],
                              MessageBuilder(
                                  content:
                                      '$extraProblems View action saved.  Choose the request method from the dropdown to finalize.'),
                              toMultiSelect: (value) {
                            final builder = SelectMenuOptionBuilder(
                                label: value, value: value);
                            if (value == 'POST') {
                              builder.description = 'recommended';
                            }
                            return builder;
                          }).then((httpTypeSelect) {
                            // must use context.user here unfortunately
                            tempPubMessage.actions.add(ntfy.Action.httpAction(
                                label: httpModalEvent[
                                    publishHttpActionInputLabelId.toString()]!,
                                url: Uri.parse(httpModalEvent[
                                    publishHttpActionInputUrlId.toString()]!),
                                headers: headers,
                                method: ntfy.MethodTypes.values
                                    .byName(httpTypeSelect.toLowerCase()),
                                body: httpModalEvent[
                                    publishHttpActionInputBodyId.toString()],
                                clear: clear));
                            httpModalEvent.respond(MessageBuilder(
                                content: 'Method $httpTypeSelect saved!'));
                          });
                        } else {
                          await httpModalEvent.respond(MessageBuilder(
                              content:
                                  'Please check your inputted URL and try again!'));
                        }
                      }));

// handle publish button, responding with message receipt returned by server
              context.awaitButtonPress(publishButtonId).then((event) async {
                await event.acknowledge();
                final apiResponse = await _state.publish(
                    tempPubMessage.generate(), await _getBasepath(context));
                event.respond(MessageBuilder(
                    embeds: [_messageToEmbed(apiResponse)],
                    content: 'How the message will look over discord:'));
              });
            })),
        ChatCommand(
            'poll',
            'search recently sent messages',
            id('poll', (
              ChatContext context,
              @Name('topic')
              @Description('topic or topics to search by, comma separated')
              String topics, [
              @Description('more recent than this ISO 8601 date')
              DateTime? since,
              @Description('also show messages scheduled to sent')
              bool? scheduled,
            ]) async {
              if (topics.split(',').isNotEmpty) {
                _pollQueue[context.user] = PollWrapper(topics.split(','))
                  ..since = since
                  ..scheduled = scheduled;
              } else {
                await context.respond(MessageBuilder(
                    content: 'Could not parse topics, please try again.'));
                return;
              }
              await _sendFilterSelection(context, true);
            })),
        ChatGroup('subscribe', 'Configure bot responses when a message is sent',
            children: [
              ChatCommand(
                  'initiate',
                  'Create a new subscription, overwriting old one!',
                  id('subscribe-initiate', (ChatContext context,
                      @Name('topic')
                      @Description(
                          'topic or topics to listen to, comma separated')
                      String topics,
                      [@Name('channel')
                      @Description(
                          'channel to send messages to, or blank for this channel')
                      TextChannel? channel,
                      @Name('dm')
                      @Description('send messages to DM instead of channel')
                      bool useDM = false]) async {
                    // provision to delete current stream if initiate is called twice, basically calls clear
                    if (_streamLine[context.user] != null) {
                      await _notifyStreamRemove(context.user);
                    }

                    if (topics.split(',').isNotEmpty) {
                      TextChannel sendPlace;
                      if (useDM) {
                        sendPlace = (await context.user.manager
                            .createDm(context.user.id));
                      } else {
                        sendPlace = (channel ?? context.channel);
                      }
                      _streamQueue[context.user] = StreamWrapper(
                          topics.split(','),
                          sendPlace,
                          await _getBasepath(context));
                    } else {
                      await context.respond(MessageBuilder(
                          content:
                              'Could not parse topics, please try again.'));
                      return;
                    }
                    await _sendFilterSelection(context, false);
                  })),
              ChatCommand(
                  'get',
                  'See the current subscription',
                  id('subscribe-get', (ChatContext context) {
                    final opts = _streamQueue[context.user];
                    if (opts != null) {
                      final embed = EmbedBuilder(
                          author: EmbedAuthorBuilder(
                              iconUrl: context.user.avatar.url,
                              name: context.user.globalName ?? ' '),
                          color: _priorityToDiscordColor(
                              // use last priority or none to get estimate of what is being filtered
                              opts.filters?.priority?.last ??
                                  ntfy.PriorityLevels.none),
                          url: Uri.tryParse(
                              '${opts.basePath}${opts.topics.last}'),
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
                      context.respond(MessageBuilder(
                          content: 'No subscription configured'));
                    }
                  })),
              ChatCommand(
                  'clear',
                  'Clear current subscription',
                  id('subscribe-clear', (ChatContext context) {
                    _notifyStreamRemove(context.user);
                    context.respond(MessageBuilder(
                        content: 'Subscription successfully cleared'));
                  })),
            ]),
      ];
}

extension on String {
  String? emptyToNull() {
    return isNotEmpty ? this : null;
  }
}
