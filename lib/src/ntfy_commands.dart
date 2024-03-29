import 'dart:async';

import 'package:ntfy_discord_bot/src/db/database.dart';
import 'package:ntfy_discord_bot/src/wrappers.dart';

import './ntfy_interface.dart';
import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:nyxx/nyxx.dart' hide ActionTypes, EventTypes;
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

class NtfyCommand {
  // the class wrapping the underlying API library
  final State _state = State();

  // the queue of messages to be published
  final Map<IUser, PublishableMessage> _publishQueue = {};

  // the queue of poll queries to be made
  final Map<IUser, PollWrapper> _pollQueue = {};

  // the queue of subcriptions to be begun or in progress
  final Map<IUser, StreamWrapper> _streamQueue = {};

  // the index of currently open subscriptions
  final Map<IUser, StreamSubscription<MessageResponse>> _streamLine = {};

  // db
  final ConfDatabase database = ConfDatabase();

  NtfyCommand();

  Future<void> shutdown(INyxxWebsocket client) async {
    _state.dispose();
    await database.close();
    await client.dispose();
  }

  // listen to the stream and index it appropriately in _streamLine
  void _notifyStreamAdd(IUser user, Stream<MessageResponse> stream) {
    _streamLine[user] = stream.listen((event) {
      if (event.event == EventTypes.message) {
        final messageEmbed = _messageToEmbed(event);
        _streamQueue[user]!.sendPlace.sendMessage(ComponentMessageBuilder()
          ..embeds = [messageEmbed]
          ..content = 'Subscribed message, send `/subscribe clear` to cancel');
      }
    });
  }

  // close out the stream listen and remove it from the index (_streamLine) and the filter queue (_streamQueue)
  Future<void> _notifyStreamRemove(IUser user) async {
    await _streamLine[user]?.cancel();
    _streamQueue.remove(user);
    _streamLine.remove(user);
  }

  Future<Uri> _getBasepath(IChatContext context) async {
    return Uri.parse((await database
                .fetchBasepathDirective(context.guild?.id ?? context.user.id))
            ?.basePath ??
        'https://ntfy.sh/');
  }

  Future<void> _updateBasepath(IChatContext context, String changedUrl) async {
    await database.updateBasepath(
        context.guild?.id ?? context.user.id, changedUrl);
  }

  /// Converts multiple messages received from the API into one sendable discord nyxx message builder, for poll use only
  static ComponentMessageBuilder _messagesToDiscordComponents(
      List<MessageResponse> messages) {
    ComponentMessageBuilder response = ComponentMessageBuilder();
    List<EmbedBuilder> embeds = [];

    // ensure messages are less than 10, and greater than zero, then trim and notify.
    if (messages.length > 10) {
      response.content =
          'Cannot show ${messages.length - 10} additional messages, please filter for them!';
      messages.removeRange(10, messages.length);
    } else if (messages.isEmpty) {
      response.content = 'There are no cached messages to display!';
    }

    // add embeds for each message, reversed to ensure correct newer first, (cant reverse earlier because of trim)
    for (final message in messages.reversed) {
      embeds.add(_messageToEmbed(message));
    }

    response.embeds = embeds;

    return response;
  }

  /// Converts a message received from the ntfy API into a pretty discord message
  static EmbedBuilder _messageToEmbed(MessageResponse message) {
    EmbedBuilder embed = EmbedBuilder()
      ..author = (EmbedAuthorBuilder()..name = message.topic)
      ..timestamp = message.time
      ..title = message.title
      ..description = message.message
      ..url = message.click?.toString()
      ..footer = (EmbedFooterBuilder()..text = message.id);

    if (message.priority != null) {
      embed.color = _priorityToDiscordColor(message.priority!);
    }

    if (message.tags != null) {
      embed.addField(name: 'Tags', content: message.tags!.join(','));
    }
    if (message.attachment != null) {
      embed.addField(
          name: message.attachment!.name, content: message.attachment!.url);
    }
    if (message.actions != null) {
      for (final action in message.actions!) {
        switch (action.action) {
          case ActionTypes.view:
            embed.addField(
                name: action.label, content: '(view action) ${action.url}');
            break;
          case ActionTypes.broadcast:
            embed.addField(
                name: action.label,
                content:
                    '(broadcast action) ${action.intent == null ? '' : 'intent: ${action.intent}'}. ${action.extras == null ? '' : 'extras: ${action.extras}'} ');
            break;
          case ActionTypes.http:
            embed.addField(
                name: action.label,
                content:
                    '(http action) ${action.method ?? 'POST'} ${action.url}. ${action.headers == null ? '' : 'headers: ${action.headers}'}. ${action.body == null ? '' : 'body: ${action.body}'}.');
            break;
        }
      }
    }
    if (message.expires != null) {
      embed.addField(name: 'Expire time', content: message.expires!.toLocal());
    }

    return embed;
  }

  /// Fetches the discord color corresponding the PriorityLevel given in the MessageResponse
  static DiscordColor _priorityToDiscordColor(PriorityLevels priorityLevel) {
    switch (priorityLevel) {
      case PriorityLevels.min:
        return DiscordColor.gray;
      case PriorityLevels.low:
        return DiscordColor.green;
      case PriorityLevels.none:
        return DiscordColor.none;
      case PriorityLevels.high:
        return DiscordColor.orange;
      case PriorityLevels.max:
        return DiscordColor.red;
    }
  }

  /// build the filter selection message, ugily abstracted for both polling and subscribing
  Future<void> _sendFilterSelection(IChatContext context, bool isPoll) async {
    // the queue, abstracted from both PollWrapper and StreamWrapper, set based on isPoll
    Map<IUser, ParentWrapper> queue;

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

    ComponentMessageBuilder askOpts = ComponentMessageBuilder()
      ..componentRows = [
        ComponentRowBuilder()
          ..addComponent(MultiselectBuilder(prioritySelectId.toString(), [
            MultiselectOptionBuilder('minimum', 'min'),
            MultiselectOptionBuilder('low', 'low'),
            MultiselectOptionBuilder('none', 'none'),
            MultiselectOptionBuilder('high', 'high'),
            MultiselectOptionBuilder('maximum', 'max'),
          ])
            ..placeholder = 'Choose priority(s) to filter by'
            ..maxValues = 4),
        ComponentRowBuilder()
          ..addComponent(ButtonBuilder(terminationButtonLabel,
              endButtonId.toString(), ButtonStyle.primary))
          ..addComponent(ButtonBuilder(
              'More filters', filterButtonId.toString(), ButtonStyle.secondary))
      ];

    context.respond(askOpts);

    final ComponentId filterInputMessageId = ComponentId.generate();
    final ComponentId filterInputTitleId = ComponentId.generate();
    final ComponentId filterInputTagsId = ComponentId.generate();
    final ComponentId filterInputIdId = ComponentId.generate();
    // handle poll filter button, responding with modal
    context.awaitButtonPress(filterButtonId).then(
          (event) => event.getModal(
            title: 'Add filters',
            components: [
              (TextInputBuilder(filterInputMessageId.toString(),
                  TextInputStyle.paragraph, 'By message')
                ..placeholder = 'Enter exact message to filter by...'
                ..required = false),
              (TextInputBuilder(filterInputTitleId.toString(),
                  TextInputStyle.short, 'By title')
                ..placeholder = 'Enter exact title to filter by...'
                ..required = false),
              (TextInputBuilder(filterInputTagsId.toString(),
                  TextInputStyle.short, 'By tag(s)')
                ..placeholder =
                    'Enter comma separated list of tags to filter by...'
                ..required = false),
              (TextInputBuilder(
                  filterInputIdId.toString(), TextInputStyle.short, 'By ID')
                ..placeholder = 'Enter exact message ID to filter by...'
                ..required = false),
            ],
          ) // handle filter modal, responding with confirmation
              .then(
            (event) {
              if (queue[event.user]?.filters != null) {
                queue[event.user]?.filters
                  ?..message =
                      event[filterInputMessageId.toString()].emptyToNull()
                  ..title = event[filterInputTitleId.toString()].emptyToNull()
                  ..tags = event[filterInputTagsId.toString()]
                      .emptyToNull()
                      ?.split(',')
                  ..id = event[filterInputIdId.toString()].emptyToNull();
              } else {
                queue[event.user]?.filters = FilterOptions(
                    message:
                        event[filterInputMessageId.toString()].emptyToNull(),
                    title: event[filterInputTitleId.toString()].emptyToNull(),
                    tags: event[filterInputTagsId.toString()]
                        .emptyToNull()
                        ?.split(','),
                    id: event[filterInputIdId.toString()].emptyToNull());
              }
              event.respond(MessageBuilder.content('Filters saved'));
            },
          ),
        );

    // handle priorities multiselect, responding with confirmation
    context.awaitMultiSelection<String>(prioritySelectId).then(
      (event) {
        // makes priority listings pretty by stripping enum class name
        final priorities = event.selected
            .map<PriorityLevels>(
                (e) => PriorityLevels.values.byName(e.toLowerCase()))
            .toList();

        if (queue[event.user]?.filters != null) {
          queue[event.user]?.filters?.priority = priorities;
        } else {
          queue[event.user]?.filters = FilterOptions(priority: priorities);
        }

        event.respond(MessageBuilder.content('Priority(s) saved!'));
      },
    );

    // handle fetch button, responding with the results of the server poll
    context.awaitButtonPress(endButtonId).then(
      (event) async {
        if (queue[event.user] != null) {
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
            event.respond(MessageBuilder.content('Successfully subscribed'));
          }
        }
      },
    );
  }

  /// Root list of commands associated with the bot
  List<IChatCommandComponent> get commands => [
        ChatCommand(
            'help',
            'Get info about ntfy connector',
            id('help', (IChatContext context) {
              EmbedBuilder aboutEmbed = EmbedBuilder()
                ..title = 'About Ntfy'
                ..addField(
                    name: 'What can this do?',
                    content:
                        'This feature can send push notifications to phones, websites, and other internet connected devices using the ntfy software suite')
                ..addField(
                    name: 'How do I get started?',
                    content:
                        'Read the below info, then use /publish and set the topic name to send your first message, and receive messages on the devices using the download links below')
                ..addField(
                    name: 'Topics',
                    content:
                        'Each ntfy message is sent to a topic which the receiver decides to listen to. '
                        ' It can be named anything, but anyone can also use this topic name and send messages to you, so pick something hard to guess!')
                ..addField(
                    name: 'Send a message',
                    content:
                        'Use /publish to send a message, inputting your topic.  A screen will be sent back askng for extra configurations.  '
                        'These basic options are self explanatory')
                ..addField(
                    name: 'Receive a message on device',
                    content:
                        'To receive the message you send, use the web, android, or ios apps (or the API described on the site) and add your unique topic when prompted')
                ..addField(
                    name: 'Receive a message on discord',
                    content:
                        'To receive messages live, use /subscribe.  Only one initiate request is active at once, but multiple topcis can be listened to.')
                ..addField(
                    name: 'More tips',
                    content:
                        'Messages are usually not stored for a long period of time, so your receiver must be on and setup BEFORE you publish. To get old messages, use the /poll option.  '
                        'NOTICE: Messages are not encrypted in any way, and can be plainly read on the bot and ntfy API server.  Do not share sensitive data!');

              ComponentMessageBuilder aboutResponse = ComponentMessageBuilder()
                ..embeds = [aboutEmbed]
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(
                      LinkButtonBuilder('Web receiver', 'https://ntfy.sh/app'))
                  ..addComponent(LinkButtonBuilder('Android receiver',
                      'https://play.google.com/store/apps/details?id=io.heckel.ntfy'))
                  ..addComponent(LinkButtonBuilder('IOS receiver',
                      'https://apps.apple.com/us/app/ntfy/id1625396347'))
                  ..addComponent(
                      LinkButtonBuilder('Ntfy Site', 'https://ntfy.sh/')));

              context.respond(aboutResponse);
            })),
        ChatGroup(
          'server',
          'View and modify the server URL, saved per-guild',
          children: [
            ChatCommand(
              'set',
              'Set the server URL',
              id('server-set', (IChatContext context,
                  @Description('new ntfy URL') String changedUrl) async {
                if (Uri.tryParse(changedUrl) == null) {
                  context.respond(MessageBuilder.content(
                      'Url $changedUrl improperly formatted!'));
                } else {
                  await _updateBasepath(context, changedUrl);
                  context.respond(MessageBuilder.content(
                      'Server successfully changed to $changedUrl !  This is saved on a per-guild basis, or per-user if it is a DM.'));
                }
              }),
            ),
            ChatCommand(
                'get',
                'Get the server URL',
                id('server-get', (IChatContext context) async {
                  context.respond(MessageBuilder.content(
                      'The server URL is: ${await _getBasepath(context)}'));
                })),
            ChatCommand(
                'reset',
                'Reset the server URL to default (ntfy.sh)',
                id('server-reset', (IChatContext context) async {
                  await _updateBasepath(context, 'https://ntfy.sh/');
                  context.respond(MessageBuilder.content(
                      'Server successfully changed to https://ntfy.sh/ !  This is saved on a per-guild basis, or per-user if it is a DM.'));
                })),
          ],
        ),
        ChatCommand(
            'publish',
            'Send a message',
            id('publish', (
              IChatContext context,
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
              _publishQueue[context.user] = PublishableMessage(topic: topic)
                ..cache = cache
                ..firebase = firebase
                ..call = call
                ..delay = schedSet;

              ComponentMessageBuilder askOps = ComponentMessageBuilder()
                ..content =
                    'Configure your message below: (can only click each button once).'
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(
                      MultiselectBuilder(publishPrioritySelectId.toString(), [
                    MultiselectOptionBuilder('minimum', 'min'),
                    MultiselectOptionBuilder('low', 'low'),
                    MultiselectOptionBuilder('none', 'none')
                      ..description = 'Default',
                    MultiselectOptionBuilder('high', 'high'),
                    MultiselectOptionBuilder('maximum', 'max'),
                  ])
                        ..placeholder = '(Optional) Select a priority level'))
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(ButtonBuilder('View',
                      publishViewActionButtonId.toString(), ButtonStyle.danger))
                  ..addComponent(ButtonBuilder(
                      'Broadcast',
                      publishBroadcastActionButtonId.toString(),
                      ButtonStyle.danger))
                  ..addComponent(ButtonBuilder(
                      'HTTP',
                      publishHttpActionButtonId.toString(),
                      ButtonStyle.danger)))
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(ButtonBuilder('Publish',
                      publishButtonId.toString(), ButtonStyle.primary))
                  ..addComponent(ButtonBuilder('Customize',
                      publishOptsButtonId.toString(), ButtonStyle.primary))
                  ..addComponent(ButtonBuilder(
                      'Advanced',
                      publishAdvOptsButtonId.toString(),
                      ButtonStyle.secondary)));

              await context.respond(askOps);

              // handle priority selection, responding with confirmation
              context
                  .awaitSelection<String>(publishPrioritySelectId)
                  .then((event) {
                _publishQueue[event.user]?.priority =
                    PriorityLevels.values.byName(event.selected.toLowerCase());
                event.acknowledge();
              });

              // handle publish button, responding with message receipt returned by server
              context.awaitButtonPress(publishButtonId).then((event) async {
                await event.acknowledge();
                final apiResponse = await _state.publish(
                    _publishQueue[event.user]!, await _getBasepath(context));
                event.respond(ComponentMessageBuilder()
                  ..embeds = [_messageToEmbed(apiResponse)]
                  ..content = 'How the message will look over discord:');
                _publishQueue.remove(event.user);
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
                      (TextInputBuilder(publishOptsInputMessageId.toString(),
                          TextInputStyle.paragraph, 'Message')
                        ..required = false
                        ..placeholder = 'Enter message here...'),
                      (TextInputBuilder(publishOptsInputTitleId.toString(),
                          TextInputStyle.short, 'Title')
                        ..required = false
                        ..placeholder = 'Enter title here...'),
                      (TextInputBuilder(publishOptsInputTagsId.toString(),
                          TextInputStyle.short, 'Tags & Emojis')
                        ..required = false
                        ..placeholder = 'Enter comma seperated list here...'),
                      (TextInputBuilder(publishOptsInputAttachmentId.toString(),
                          TextInputStyle.short, 'URL of Attachment')
                        ..required = false
                        ..placeholder = 'Enter URL of attachment here...'),
                      (TextInputBuilder(publishOptsInputFilenameId.toString(),
                          TextInputStyle.short, 'Filename of attachment')
                        ..required = false
                        ..placeholder = 'Enter filename of attachment here...'),
                    ],
                  ) // handle opts modal, responding with confirmation
                      .then((event) async {
                    _publishQueue[event.user]?.message =
                        event[publishOptsInputMessageId.toString()]
                            .emptyToNull();
                    event[publishOptsInputMessageId.toString()];
                    _publishQueue[event.user]?.title =
                        event[publishOptsInputTitleId.toString()].emptyToNull();
                    _publishQueue[event.user]?.tags =
                        event[publishOptsInputTagsId.toString()]
                            .emptyToNull()
                            ?.split(',');

                    // if empty return null else return Uri.tryParse attachment url
                    _publishQueue[event.user]?.attach =
                        event[publishOptsInputAttachmentId.toString()]
                                    .emptyToNull() ==
                                null
                            ? null
                            : Uri.tryParse(
                                event[publishOptsInputAttachmentId.toString()]);

                    _publishQueue[event.user]?.filename =
                        event[publishOptsInputFilenameId.toString()]
                            .emptyToNull();

                    await event.respond(MessageBuilder.content(
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
                      (TextInputBuilder(publishAdvOptsInputEmailId.toString(),
                          TextInputStyle.short, 'Email')
                        ..required = false
                        ..placeholder = 'Enter email to be notified here...'),
                      (TextInputBuilder(publishAdvOptsInputClickId.toString(),
                          TextInputStyle.short, 'Click URL')
                        ..required = false
                        ..placeholder =
                            'Enter url to open when clicked on android...'),
                      (TextInputBuilder(publishAdvOptsInputIconId.toString(),
                          TextInputStyle.short, 'Icon URL')
                        ..required = false
                        ..placeholder = 'Enter icon URL to see on android...'),
                      (TextInputBuilder(
                          publishAdvOptsInputAuthUsernameId.toString(),
                          TextInputStyle.short,
                          'Authorization')
                        ..required = false
                        ..placeholder = 'Enter username here...'),
                      (TextInputBuilder(
                          publishAdvOptsInputAuthPasswordId.toString(),
                          TextInputStyle.short,
                          ' ')
                        ..required = false
                        ..placeholder = 'Enter password here...'),
                    ],
                  ) // handle adv opts modal, responding with confirmation
                      .then((event) {
                    String extraProblems = '';

                    _publishQueue[event.user]?.email =
                        event[publishAdvOptsInputEmailId.toString()]
                            .emptyToNull();

                    // if Uri.tryParse click url is null, add notif to extra problems
                    _publishQueue[event.user]?.click = Uri.tryParse(
                        event[publishAdvOptsInputClickId.toString()]);
                    if (_publishQueue[event.user]?.click == null) {
                      extraProblems += 'Invalid click URL\n';
                    }

                    // if icon is empty return null else return Uri.tryParse icon
                    _publishQueue[event.user]?.icon =
                        event[publishAdvOptsInputIconId.toString()]
                                    .emptyToNull() ==
                                null
                            ? null
                            : Uri.tryParse(
                                event[publishAdvOptsInputIconId.toString()]);

                    // if auth user + password not empty add auth
                    if (event[publishAdvOptsInputAuthUsernameId.toString()]
                            .isNotEmpty &&
                        event[publishAdvOptsInputAuthUsernameId.toString()]
                            .isNotEmpty) {
                      _publishQueue[event.user]?.addAuthentication(
                          username: event[
                              publishAdvOptsInputAuthUsernameId.toString()],
                          password: event[
                              publishAdvOptsInputAuthUsernameId.toString()]);
                      // if one or other auth user + password not empty notif that auth set failed
                    } else if (event[
                                publishAdvOptsInputAuthUsernameId.toString()]
                            .isNotEmpty ||
                        event[publishAdvOptsInputAuthPasswordId.toString()]
                            .isNotEmpty) {
                      extraProblems +=
                          'Must give username and password for auth!\n';
                    }

                    event.respond(MessageBuilder.content(
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
                        (TextInputBuilder(
                            publishViewActionInputLabelId.toString(),
                            TextInputStyle.short,
                            'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(
                            publishViewActionInputUrlId.toString(),
                            TextInputStyle.short,
                            'URL')
                          ..required = true
                          ..placeholder = 'Enter URL to open...'),
                        (TextInputBuilder(
                            publishViewActionInputClearId.toString(),
                            TextInputStyle.short,
                            'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle view modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        Uri? url;
                        bool? clear;

                        // notif of url invalid
                        url = Uri.tryParse(
                            event[publishViewActionInputUrlId.toString()]);
                        if (url == null) {
                          extraProblems += 'Invalid URL\n';
                        }

                        // parse clear to true or false, set to default false if failure
                        if (event[publishViewActionInputClearId.toString()]
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[
                                    publishViewActionInputClearId.toString()]
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
                          _publishQueue[event.user]?.addViewAction(
                              label: event[
                                  publishViewActionInputLabelId.toString()],
                              url: url,
                              clear: clear);

                          await event.respond(MessageBuilder.content(
                              '$extraProblems View action saved.  Remember to click Publish to send your message!'));
                        } else {
                          await event.respond(MessageBuilder.content(
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
                        (TextInputBuilder(
                            publishBroadcastActionInputLabelId.toString(),
                            TextInputStyle.short,
                            'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(
                            publishBroadcastActionInputIntentId.toString(),
                            TextInputStyle.short,
                            'Intent')
                          ..required = false
                          ..placeholder =
                              'Enter android intent name (default io.heckel.ntfy.USER_ACTION)...'),
                        (TextInputBuilder(
                            publishBroadcastActionInputExtrasId.toString(),
                            TextInputStyle.short,
                            'Extras')
                          ..required = false
                          ..placeholder =
                              'Enter android intent extras as <param>=<value>,<param>=<value>...'),
                        (TextInputBuilder(
                            publishBroadcastActionInputClearId.toString(),
                            TextInputStyle.short,
                            'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle broadcast modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        // parse clear setting to default (false) and notif if not parsed
                        bool? clear;
                        if (event[publishBroadcastActionInputClearId.toString()]
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[publishBroadcastActionInputClearId
                                    .toString()]
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
                                publishBroadcastActionInputExtrasId.toString()]
                            .isNotEmpty) {
                          try {
                            for (final splitComma in event[
                                    publishBroadcastActionInputExtrasId
                                        .toString()]
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
                        _publishQueue[event.user]?.addBroadcastAction(
                          label: event[
                              publishBroadcastActionInputLabelId.toString()],
                          intent: event[
                              publishBroadcastActionInputIntentId.toString()],
                          extras: extras,
                          clear: clear,
                        );
                        await event.respond(MessageBuilder.content(
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
                        (TextInputBuilder(
                            publishHttpActionInputLabelId.toString(),
                            TextInputStyle.short,
                            'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(
                            publishHttpActionInputUrlId.toString(),
                            TextInputStyle.short,
                            'URL')
                          ..required = true
                          ..placeholder = 'Enter URL to open...'),
                        (TextInputBuilder(
                            publishHttpActionInputHeadersId.toString(),
                            TextInputStyle.short,
                            'Headers')
                          ..required = false
                          ..placeholder =
                              'Enter headers as <param>=<value>,<param>=<value>...'),
                        (TextInputBuilder(
                            publishHttpActionInputBodyId.toString(),
                            TextInputStyle.short,
                            'Body')
                          ..required = false
                          ..placeholder = 'Enter http body...'),
                        (TextInputBuilder(
                            publishHttpActionInputClearId.toString(),
                            TextInputStyle.short,
                            'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle http modal, responding with confirmation
                          .then((httpModalEvent) async {
                        // if url valid (since required) continue
                        if (Uri.tryParse(httpModalEvent[
                                publishHttpActionInputUrlId.toString()]) !=
                            null) {
                          String extraProblems = '';

                          // parse clear, if fail set to default (false) and notif
                          bool clear;
                          if (httpModalEvent[
                                      publishHttpActionInputClearId.toString()]
                                  .toLowerCase() ==
                              'true') {
                            clear = true;
                          } else if (httpModalEvent[
                                      publishHttpActionInputClearId.toString()]
                                  .toLowerCase() ==
                              'false') {
                            clear = false;
                          } else if ((httpModalEvent[
                                  publishHttpActionInputClearId.toString()])
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
                                  publishHttpActionInputHeadersId.toString()]
                              .isNotEmpty) {
                            try {
                              for (final splitComma in httpModalEvent[
                                      publishHttpActionInputHeadersId
                                          .toString()]
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
                              MessageBuilder.content(
                                  '$extraProblems View action saved.  Choose the request method from the dropdown to finalize.'),
                              toMultiSelect: (value) {
                            final builder =
                                MultiselectOptionBuilder(value, value);
                            if (value == 'POST') {
                              builder.description = 'recommended';
                            }
                            return builder;
                          }).then((httpTypeSelect) {
                            // must use context.user here unfortunately
                            _publishQueue[context.user]?.addHttpAction(
                                label: httpModalEvent[
                                    publishHttpActionInputLabelId.toString()],
                                url: Uri.parse(httpModalEvent[
                                    publishHttpActionInputUrlId.toString()]),
                                headers: headers,
                                method: MethodTypes.values
                                    .byName(httpTypeSelect.toLowerCase()),
                                body: httpModalEvent[
                                    publishHttpActionInputBodyId.toString()],
                                clear: clear);
                            httpModalEvent.respond(MessageBuilder.content(
                                'Method $httpTypeSelect saved!'));
                          });
                        } else {
                          await httpModalEvent.respond(MessageBuilder.content(
                              'Please check your inputted URL and try again!'));
                        }
                      }));
            })),
        ChatCommand(
            'poll',
            'search recently sent messages',
            id('poll', (
              IChatContext context,
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
                await context.respond(MessageBuilder.content(
                    'Could not parse topics, please try again.'));
                return;
              }
              await _sendFilterSelection(context, true);
            })),
        ChatGroup('subscribe', 'Configure bot responses when a message is sent',
            children: [
              ChatCommand(
                  'initiate',
                  'Create a new subscription, overwriting old one!',
                  id('subscribe-initiate', (IChatContext context,
                      @Name('topic')
                      @Description(
                          'topic or topics to listen to, comma separated')
                      String topics,
                      [@Name('channel')
                      @Description(
                          'channel to send messages to, or blank for this channel')
                      ITextGuildChannel? channel,
                      @Name('dm')
                      @Description('send messages to DM instead of channel')
                      bool useDM = false]) async {
                    // provision to delete current stream if initiate is called twice, basically calls clear
                    if (_streamLine[context.user] != null) {
                      await _notifyStreamRemove(context.user);
                    }

                    if (topics.split(',').isNotEmpty) {
                      ISend sendPlace;
                      if (useDM) {
                        sendPlace = context.user;
                      } else {
                        sendPlace = channel ?? context.channel;
                      }
                      _streamQueue[context.user] = StreamWrapper(
                          topics.split(','),
                          sendPlace,
                          await _getBasepath(context));
                    } else {
                      await context.respond(MessageBuilder.content(
                          'Could not parse topics, please try again.'));
                      return;
                    }
                    await _sendFilterSelection(context, false);
                  })),
              ChatCommand(
                  'get',
                  'See the current subscription',
                  id('subscribe-get', (IChatContext context) {
                    final opts = _streamQueue[context.user];
                    if (opts != null) {
                      final embed = EmbedBuilder(
                          author: EmbedAuthorBuilder(
                              iconUrl: context.user.avatarUrl(),
                              name: context.user.globalName),
                          color: _priorityToDiscordColor(
                              // use last priority or none to get estimate of what is being filtered
                              opts.filters?.priority?.last ??
                                  PriorityLevels.none),
                          url: '${opts.basePath}${opts.topics.last}',
                          title: opts.topics.toString(),
                          description: 'Filters:');

                      if (opts.filters?.id != null) {
                        embed.addField(name: 'ID', content: opts.filters!.id);
                      }
                      if (opts.filters?.message != null) {
                        embed.addField(
                            name: 'Message', content: opts.filters!.message);
                      }
                      if (opts.filters?.priority != null) {
                        embed.addField(
                            name: 'Priorities',
                            content: (opts.filters!.priority!.fold<String>(
                                    '',
                                    (previousValue, element) =>
                                        '$previousValue, ${element.name}'))
                                .substring(2));
                      }
                      if (opts.filters?.tags != null) {
                        embed.addField(
                            name: 'Tags',
                            content: opts.filters!.tags!.join(', '));
                      }
                      if (opts.filters?.title != null) {
                        embed.addField(
                            name: 'Title', content: opts.filters!.title);
                      }

                      context.respond(MessageBuilder.embed(embed));
                    } else {
                      context.respond(
                          MessageBuilder.content('No subscription configured'));
                    }
                  })),
              ChatCommand(
                  'clear',
                  'Clear current subscription',
                  id('subscribe-clear', (IChatContext context) {
                    _notifyStreamRemove(context.user);
                    context.respond(MessageBuilder.content(
                        'Subscription successfully cleared'));
                  })),
            ]),
      ];
}

extension on String {
  String? emptyToNull() {
    return isNotEmpty ? this : null;
  }
}
