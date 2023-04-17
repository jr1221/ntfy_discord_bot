import './ntfy_interface.dart';
import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:nyxx/nyxx.dart' hide ActionTypes;
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

class NtfyCommand {
  final State _state;

  final Map<IUser, PublishableMessage> _publishQueue = {};
  final Map<IUser, PollWrapper> _pollQueue = {};

  NtfyCommand() : _state = State();

  /// Converts multiple messages received from the API into one sendable discord nyxx message builder
  static ComponentMessageBuilder _messagesToDiscordComponents(
      List<MessageResponse> messages) {
    ComponentMessageBuilder leadMessage = ComponentMessageBuilder();
    List<EmbedBuilder> embedMessages = [];

    for (final message in messages.reversed) {
      embedMessages.add(_messageToDiscordBuilder(message));
    }
    if (embedMessages.length > 10) {
      leadMessage.content =
          'Cannot show ${embedMessages.length - 10} additional messages, please filter for them!';
      embedMessages.removeRange(10, embedMessages.length);
    }
    leadMessage.embeds = embedMessages.reversed.toList();
    if (leadMessage.embeds == null || leadMessage.embeds!.isEmpty) {
      leadMessage.content = 'There are no cached messages to display!';
    }
    return leadMessage;
  }

  /// Converts a message received from the ntfy API into a pretty discord message
  static EmbedBuilder _messageToDiscordBuilder(MessageResponse message) {
    EmbedBuilder messageEmbed = EmbedBuilder()
      ..author = (EmbedAuthorBuilder()..name = message.topic)
      ..timestamp = message.time
      ..title = message.title
      ..description = message.message
      ..url = message.click?.toString()
      ..footer = (EmbedFooterBuilder()..text = message.id);

    if (message.priority != null) {
      messageEmbed.color = _priorityToDiscordColor(message.priority!);
    }

    if (message.tags != null) {
      messageEmbed.addField(name: 'Tags', content: message.tags!.join(','));
    }
    if (message.attachment != null) {
      messageEmbed.addField(
          name: message.attachment!.name, content: message.attachment!.url);
    }
    if (message.actions != null) {
      for (final action in message.actions!) {
        switch (action.action) {
          case ActionTypes.view:
            messageEmbed.addField(
                name: action.label, content: '(view action) ${action.url}');
            break;
          case ActionTypes.broadcast:
            messageEmbed.addField(
                name: action.label,
                content:
                    '(broadcast action) ${action.intent == null ? '' : 'intent: ${action.intent}'}. ${action.extras == null ? '' : 'extras: ${action.extras}'} ');
            break;
          case ActionTypes.http:
            messageEmbed.addField(
                name: action.label,
                content:
                    '(http action) ${action.method ?? 'POST'} ${action.url}. ${action.headers == null ? '' : 'headers: ${action.headers}'}. ${action.body == null ? '' : 'body: ${action.body}'}.');
            break;
        }
      }
    }

    return messageEmbed;
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

  /// Root list of commands associated with the bot
  List<ChatCommand> get commands => [
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
                    /*        content:
                        'For the bot to reply to you with the message you subscribed to, use /subscribe with your topic.  '
                        'This can be done with multiple topics, just remember to CLEAR the list of topics when you are done') */
                    content: 'Not currently supported.')
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
        ChatCommand(
            'publish',
            'Send a message',
            id('publish', (IChatContext context,
                @Description('Unique topic name')
                    String topic,
                [@Description('schedule message to send at ISO 8601 date')
                    DateTime? schedSet,
                @Description('cache values on server')
                    bool? cache,
                @Description('use FCM to send messages')
                    bool? firebase]) async {
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
                final apiResponse =
                    await _state.publish(_publishQueue[event.user]!);
                event.respond(ComponentMessageBuilder()
                  ..embeds = [_messageToDiscordBuilder(apiResponse)]
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
              final pollFilterButtonId = ComponentId.generate();
              final pollPriorityId = ComponentId.generate();
              final pollFetchButtonId = ComponentId.generate();

              if (topics.split(',').isNotEmpty) {
                _pollQueue[context.user] = PollWrapper(topics.split(','))
                  ..since = since
                  ..scheduled = scheduled;

                ComponentMessageBuilder askOpts = ComponentMessageBuilder()
                  ..componentRows = [
                    ComponentRowBuilder()
                      ..addComponent(
                          MultiselectBuilder(pollPriorityId.toString(), [
                        MultiselectOptionBuilder('minimum', 'min'),
                        MultiselectOptionBuilder('low', 'low'),
                        MultiselectOptionBuilder('none', 'none'),
                        MultiselectOptionBuilder('high', 'high'),
                        MultiselectOptionBuilder('maximum', 'max'),
                      ])
                            ..placeholder = 'Choose priority(s) to filter by'
                            ..maxValues = 4),
                    ComponentRowBuilder()
                      ..addComponent(ButtonBuilder('Fetch',
                          pollFetchButtonId.toString(), ButtonStyle.primary))
                      ..addComponent(ButtonBuilder('More filters',
                          pollFilterButtonId.toString(), ButtonStyle.secondary))
                  ];

                context.respond(askOpts);

                final ComponentId pollFilterInputMessageId =
                    ComponentId.generate();
                final ComponentId pollFilterInputTitleId =
                    ComponentId.generate();
                final ComponentId pollFilterInputTagsId =
                    ComponentId.generate();
                final ComponentId pollFilterInputIdId = ComponentId.generate();
                // handle poll filter button, responding with modal
                context.awaitButtonPress(pollFilterButtonId).then((event) =>
                    event.getModal(title: 'Add filters', components: [
                      (TextInputBuilder(pollFilterInputMessageId.toString(),
                          TextInputStyle.paragraph, 'By message')
                        ..placeholder = 'Enter exact message to filter by...'
                        ..required = false),
                      (TextInputBuilder(pollFilterInputTitleId.toString(),
                          TextInputStyle.short, 'By title')
                        ..placeholder = 'Enter exact title to filter by...'
                        ..required = false),
                      (TextInputBuilder(pollFilterInputTagsId.toString(),
                          TextInputStyle.short, 'By tag(s)')
                        ..placeholder =
                            'Enter comma separated list of tags to filter by...'
                        ..required = false),
                      (TextInputBuilder(pollFilterInputIdId.toString(),
                          TextInputStyle.short, 'By ID')
                        ..placeholder = 'Enter exact message ID to filter by...'
                        ..required = false),
                    ]) // handle filter modal, responding with confirmation
                        .then((event) {
                      if (_pollQueue[event.user]?.filters != null) {
                        _pollQueue[event.user]?.filters
                          ?..message =
                              event[pollFilterInputMessageId.toString()]
                                  .emptyToNull()
                          ..title = event[pollFilterInputTitleId.toString()]
                              .emptyToNull()
                          ..tags = event[pollFilterInputTagsId.toString()]
                              .emptyToNull()
                              ?.split(',')
                          ..id = event[pollFilterInputIdId.toString()]
                              .emptyToNull();
                      } else {
                        _pollQueue[event.user]?.filters = FilterOptions(
                            message: event[pollFilterInputMessageId.toString()]
                                .emptyToNull(),
                            title: event[pollFilterInputTitleId.toString()]
                                .emptyToNull(),
                            tags: event[pollFilterInputTagsId.toString()]
                                .emptyToNull()
                                ?.split(','),
                            id: event[pollFilterInputIdId.toString()]
                                .emptyToNull());
                      }
                      event.respond(MessageBuilder.content('Filters saved'));
                    }));
                // handle priorities multiselect, responding with confirmation
                context
                    .awaitMultiSelection<String>(
                  pollPriorityId,
                )
                    .then((event) {
                  final priorities = event.selected
                      .map<PriorityLevels>(
                          (e) => PriorityLevels.values.byName(e.toLowerCase()))
                      .toList();
                  if (_pollQueue[event.user]?.filters != null) {
                    _pollQueue[event.user]?.filters?.priority = priorities;
                  } else {
                    _pollQueue[event.user]?.filters =
                        FilterOptions(priority: priorities);
                  }
                  event.respond(MessageBuilder.content('Priority(s) saved!'));
                });

                // handle fetch button, responding with the results of the server poll
                context.awaitButtonPress(pollFetchButtonId).then((event) async {
                  if (_pollQueue[event.user] != null) {
                    final polled = await _state.poll(_pollQueue[event.user]!);

                    event.respond(_messagesToDiscordComponents(polled));
                    _pollQueue.remove(event.user);
                  }
                });
              } else {
                context.respond(MessageBuilder.content(
                    'Could not parse topics, please try again.'));
              }
            })),
        ChatCommand(
            'subscribe',
            'Configure bot responses when a message is sent',
            id('subscribe', (IChatContext context) {
              context.respond(MessageBuilder.content(
                  'This functionality is not yet available.  Please see /help to setup notifications for a message.'));
            }))
      ];

  Future<void> shutdown(INyxxWebsocket client) async {
    _state.dispose();
  }
}

/// A wrapper to store the poll request and send it to the ntfy state interface
class PollWrapper {
  List<String> topics;

  DateTime? since;

  bool? scheduled;

  FilterOptions? filters;

  PollWrapper(this.topics);
}

extension on String {
  String? emptyToNull() {
    return isNotEmpty ? this : null;
  }
}
