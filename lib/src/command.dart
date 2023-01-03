import 'dart:io';

import './interface.dart';
import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:nyxx/nyxx.dart' hide ActionTypes;
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

class NtfyCommand {
  final State _state;

  // <---- PUBLISH COMPONENT IDs ---->

  // Publish root buttons
  static const String _publishViewActionButtonId = 'publish-viewaction-button';
  static const String _publishBroadcastActionButtonId =
      'publish-broadcastaction-button';
  static const String _publishHttpActionButtonId = 'publish-httpaction-button';
  static const String _publishOptsButtonId = 'publish-opts-button';
  static const String _publishButtonId = 'publish-blank-button';
  static const String _publishAdvOptsButtonId = 'publish-advopts-button';

  // Publish root priority select
  static const String _publishPrioritySelectId = 'publish-priority-select';

  // Publish basic options keys
  static const String _publishOptsInputMessageId = 'publish-opts-modal-message';
  static const String _publishOptsInputTitleId = 'publish-opts-modal-title';
  static const String _publishOptsInputFilenameId =
      'publish-opts-modal-filename';
  static const String _publishOptsInputTagsId = 'publish-opts-modal-tags';
  static const String _publishOptsInputAttachmentId =
      'publish-opts-modal-attachment';

  // Publish advanced options keys
  static const String _publishAdvOptsInputEmailId =
      'publish-advopts-modal-email';
  static const String _publishAdvOptsInputClickId =
      'publish-advopts-modal-click';
  static const String _publishAdvOptsInputIconId = 'publish-advopts-modal-icon';
  static const String _publishAdvOptsInputAuthUsernameId =
      'publish-advopts-modal-authusername';
  static const String _publishAdvOptsInputAuthPasswordId =
      'publish-advopts-modal-authpassword';

  // Publish view action keys
  static const String _publishViewActionInputLabelId =
      'publish-viewaction-modal-label';
  static const String _publishViewActionInputUrlId =
      'publish-viewaction-modal-url';
  static const String _publishViewActionInputClearId =
      'publish-viewaction-modal-clear';

  // Publish broadcast action keys
  static const String _publishBroadcastActionInputLabelId =
      'publish-broadcastaction-modal-label';
  static const String _publishBroadcastActionInputIntentId =
      'publish-broadcastaction-modal-intent';
  static const String _publishBroadcastActionInputExtrasId =
      'publish-broadcastaction-modal-extras';
  static const String _publishBroadcastActionInputClearId =
      'publish-broadcastaction-modal-clear';

  // Publish http action keys
  static const String _publishHttpActionInputLabelId =
      'publish-httpaction-modal-label';
  static const String _publishHttpActionInputUrlId =
      'publish-httpaction-modal-url';
  static const String _publishHttpActionInputHeadersId =
      'publish-httpaction-modal-headers';
  static const String _publishHttpActionInputBodyId =
      'publish-httpaction-modal-body';
  static const String _publishHttpActionInputClearId =
      'publish-httpaction-modal-clear';

  // <---- POLL COMPONENT IDs ---->

  // Poll root buttons
  static const String _pollFetchButtonId = 'poll-fetch-button';
  static const String _pollFilterButtonId = 'poll-filter-button';

  // Poll root priority select
  static const String _pollPriorityId = 'poll-priority-multiselect';

  // Poll filter modal keys
  static const String _pollFilterInputMessageId = 'poll-filter-modal-message';
  static const String _pollFilterInputTitleId = 'poll-filter-modal-title';
  static const String _pollFilterInputTagsId = 'poll-filter-modal-tags';
  static const String _pollFilterInputIdId = 'poll-filter-modal-id';

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
            'info',
            'Get info about the bot',
            id('info', (IChatContext context) {
              EmbedBuilder infoEmbed = EmbedBuilder()
                ..title = 'Bot Info'
                ..description = 'See technical info'
                ..timestamp = DateTime.now()
                ..addField(
                    name: 'Library',
                    content: '[Nyxx](https://nyxx.l7ssha.xyz/)',
                    inline: true)
                ..addFooter((footer) {
                  footer.text =
                      'Dart SDK ${Platform.version.split("(").first} on ${Platform.operatingSystem.onlyFirstCaps()}';
                });

              ComponentMessageBuilder infoResponse = ComponentMessageBuilder()
                ..embeds = [infoEmbed]
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(LinkButtonBuilder(
                      'Source', 'https://github.com/jr1221/ntfy_discord_bot')));

              context.respond(infoResponse);
            })),
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
              // add topic, cache, delay, and firebase to message
              _publishQueue[context.user] = PublishableMessage(topic: topic)
                ..cache = cache
                ..firebase = firebase
                ..delay = schedSet;

              ComponentMessageBuilder askOps = ComponentMessageBuilder()
                ..content =
                    'Configure your message below: (can only click each button once).'
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(MultiselectBuilder(_publishPrioritySelectId, [
                    MultiselectOptionBuilder('minimum', 'min'),
                    MultiselectOptionBuilder('low', 'low'),
                    MultiselectOptionBuilder('none', 'none')
                      ..description = 'Default',
                    MultiselectOptionBuilder('high', 'high'),
                    MultiselectOptionBuilder('maximum', 'max'),
                  ])
                    ..placeholder = '(Optional) Select a priority level'))
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(ButtonBuilder(
                      'View', _publishViewActionButtonId, ButtonStyle.danger))
                  ..addComponent(ButtonBuilder('Broadcast',
                      _publishBroadcastActionButtonId, ButtonStyle.danger))
                  ..addComponent(ButtonBuilder(
                      'HTTP', _publishHttpActionButtonId, ButtonStyle.danger)))
                ..addComponentRow(ComponentRowBuilder()
                  ..addComponent(ButtonBuilder(
                      'Publish', _publishButtonId, ButtonStyle.primary))
                  ..addComponent(ButtonBuilder(
                      'Customize', _publishOptsButtonId, ButtonStyle.primary))
                  ..addComponent(ButtonBuilder('Advanced',
                      _publishAdvOptsButtonId, ButtonStyle.secondary)));

              await context.respond(askOps);

              // handle priority selection, responding with confirmation
              context
                  .awaitSelection<String>(_publishPrioritySelectId)
                  .then((event) {
                _publishQueue[event.user]?.priority =
                    PriorityLevels.values.byName(event.selected.toLowerCase());
                event.respond(ComponentMessageBuilder()
                  ..content = 'Priority of ${event.selected} saved!'
                  ..componentRows = []);
              });

              // handle publish button, responding with message receipt returned by server
              context.awaitButtonPress(_publishButtonId).then((event) async {
                await event.acknowledge();
                final apiResponse =
                    await _state.publish(_publishQueue[event.user]!);
                event.respond(ComponentMessageBuilder()
                  ..embeds = [_messageToDiscordBuilder(apiResponse)]
                  ..content = 'How the message will look over discord:');
                _publishQueue.remove(event.user);
              });

              // handle customize (opts) button, responding with modal
              context.awaitButtonPress(_publishOptsButtonId).then((event) =>
                  event.getModal(
                    title: 'Create message',
                    components: [
                      (TextInputBuilder(_publishOptsInputMessageId,
                          TextInputStyle.paragraph, 'Message')
                        ..required = false
                        ..placeholder = 'Enter message here...'),
                      (TextInputBuilder(_publishOptsInputTitleId,
                          TextInputStyle.short, 'Title')
                        ..required = false
                        ..placeholder = 'Enter title here...'),
                      (TextInputBuilder(_publishOptsInputTagsId,
                          TextInputStyle.short, 'Tags & Emojis')
                        ..required = false
                        ..placeholder = 'Enter comma seperated list here...'),
                      (TextInputBuilder(_publishOptsInputAttachmentId,
                          TextInputStyle.short, 'URL of Attachment')
                        ..required = false
                        ..placeholder = 'Enter URL of attachment here...'),
                      (TextInputBuilder(_publishOptsInputFilenameId,
                          TextInputStyle.short, 'Filename of attachment')
                        ..required = false
                        ..placeholder = 'Enter filename of attachment here...'),
                    ],
                  ) // handle opts modal, responding with confirmation
                      .then((event) async {
                    _publishQueue[event.user]?.message =
                        event[_publishOptsInputMessageId].emptyToNull();
                    event[_publishOptsInputMessageId];
                    _publishQueue[event.user]?.title =
                        event[_publishOptsInputTitleId].emptyToNull();
                    _publishQueue[event.user]?.tags =
                        event[_publishOptsInputTagsId]
                            .emptyToNull()
                            ?.split(',');

                    // if empty return null else return Uri.tryParse attachment url
                    _publishQueue[event.user]
                        ?.attach = event[_publishOptsInputAttachmentId]
                                .emptyToNull() ==
                            null
                        ? null
                        : Uri.tryParse(event[_publishOptsInputAttachmentId]);

                    _publishQueue[event.user]?.filename =
                        event[_publishOptsInputFilenameId].emptyToNull();

                    await event.respond(MessageBuilder.content(
                        'Info saved.  Remember to click Publish to send your message!'));
                  }));

              // handle advanced opts button, responding with modal
              context.awaitButtonPress(_publishAdvOptsButtonId).then((event) =>
                  event.getModal(
                    title: 'Advanced options',
                    components: [
                      (TextInputBuilder(_publishAdvOptsInputEmailId,
                          TextInputStyle.short, 'Email')
                        ..required = false
                        ..placeholder = 'Enter email to be notified here...'),
                      (TextInputBuilder(_publishAdvOptsInputClickId,
                          TextInputStyle.short, 'Click URL')
                        ..required = false
                        ..placeholder =
                            'Enter url to open when clicked on android...'),
                      (TextInputBuilder(_publishAdvOptsInputIconId,
                          TextInputStyle.short, 'Icon URL')
                        ..required = false
                        ..placeholder = 'Enter icon URL to see on android...'),
                      (TextInputBuilder(_publishAdvOptsInputAuthUsernameId,
                          TextInputStyle.short, 'Authorization')
                        ..required = false
                        ..placeholder = 'Enter username here...'),
                      (TextInputBuilder(_publishAdvOptsInputAuthPasswordId,
                          TextInputStyle.short, ' ')
                        ..required = false
                        ..placeholder = 'Enter password here...'),
                    ],
                  ) // handle adv opts modal, responding with confirmation
                      .then((event) {
                    String extraProblems = '';

                    _publishQueue[event.user]?.email =
                        event[_publishAdvOptsInputEmailId].emptyToNull();

                    // if Uri.tryParse click url is null, add notif to extra problems
                    _publishQueue[event.user]?.click =
                        Uri.tryParse(event[_publishAdvOptsInputClickId]);
                    if (_publishQueue[event.user]?.click == null) {
                      extraProblems += 'Invalid click URL\n';
                    }

                    // if icon is empty return null else return Uri.tryParse icon
                    _publishQueue[event.user]?.icon =
                        event[_publishAdvOptsInputIconId].emptyToNull() == null
                            ? null
                            : Uri.tryParse(event[_publishAdvOptsInputIconId]);

                    // if auth user + password not empty add auth
                    if (event[_publishAdvOptsInputAuthUsernameId].isNotEmpty &&
                        event[_publishAdvOptsInputAuthUsernameId].isNotEmpty) {
                      _publishQueue[event.user]?.addAuthentication(
                          username: event[_publishAdvOptsInputAuthUsernameId],
                          password: event[_publishAdvOptsInputAuthUsernameId]);
                      // if one or other auth user + password not empty notif that auth set failed
                    } else if (event[_publishAdvOptsInputAuthUsernameId]
                            .isNotEmpty ||
                        event[_publishAdvOptsInputAuthUsernameId].isNotEmpty) {
                      extraProblems +=
                          'Must give username and password for auth!\n';
                    }

                    event.respond(MessageBuilder.content(
                        '$extraProblems Advanced info saved.  Remember to click Publish to send your message!'));
                  }));

              // handle view action button, responding with modal
              context.awaitButtonPress(_publishViewActionButtonId).then(
                  (event) =>
                      event.getModal(title: 'Add view action', components: [
                        (TextInputBuilder(_publishViewActionInputLabelId,
                            TextInputStyle.short, 'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(_publishViewActionInputUrlId,
                            TextInputStyle.short, 'URL')
                          ..required = true
                          ..placeholder = 'Enter URL to open...'),
                        (TextInputBuilder(_publishViewActionInputClearId,
                            TextInputStyle.short, 'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle view modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        Uri? url;
                        bool? clear;

                        // notif of url invalid
                        url = Uri.tryParse(event[_publishViewActionInputUrlId]);
                        if (url == null) {
                          extraProblems += 'Invalid URL\n';
                        }

                        // parse clear to true or false, set to default false if failure
                        if (event[_publishViewActionInputClearId]
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[_publishViewActionInputClearId]
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
                              label: event[_publishViewActionInputLabelId],
                              url: url,
                              clear: clear);

                          await event.respond(MessageBuilder.content(
                              '$extraProblems View action saved.  Remember to click Publish to send your message!'));
                        } else {
                          await event.respond(MessageBuilder.content(
                              '$extraProblems Failure: Please resend command and change your input to try again!'));
                        }
                      }));

              // handle broadcast button, responding with modal
              context.awaitButtonPress(_publishBroadcastActionButtonId).then(
                  (event) => event
                          .getModal(title: 'Add broadcast action', components: [
                        (TextInputBuilder(_publishBroadcastActionInputLabelId,
                            TextInputStyle.short, 'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(_publishBroadcastActionInputIntentId,
                            TextInputStyle.short, 'Intent')
                          ..required = false
                          ..placeholder =
                              'Enter android intent name (default io.heckel.ntfy.USER_ACTION)...'),
                        (TextInputBuilder(_publishBroadcastActionInputExtrasId,
                            TextInputStyle.short, 'Extras')
                          ..required = false
                          ..placeholder =
                              'Enter android intent extras as <param>=<value>,<param>=<value>...'),
                        (TextInputBuilder(_publishBroadcastActionInputClearId,
                            TextInputStyle.short, 'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle broadcast modal, responding with confirmation
                          .then((event) async {
                        String extraProblems = '';

                        // parse clear setting to default (false) and notif if not parsed
                        bool? clear;
                        if (event[_publishBroadcastActionInputClearId]
                                .toLowerCase() ==
                            'true') {
                          clear = true;
                        } else if (event[_publishBroadcastActionInputClearId]
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
                        if (event[_publishBroadcastActionInputExtrasId]
                            .isNotEmpty) {
                          try {
                            for (final splitComma
                                in event[_publishBroadcastActionInputExtrasId]
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
                          label: event[_publishBroadcastActionInputLabelId],
                          intent: event[_publishBroadcastActionInputIntentId],
                          extras: extras,
                          clear: clear,
                        );
                        await event.respond(MessageBuilder.content(
                            '$extraProblems View action saved.  Remember to click Publish to send your message!'));
                      }));

              // handle http button, responding with modal
              context.awaitButtonPress(_publishHttpActionButtonId).then(
                  (event) =>
                      event.getModal(title: 'Add HTTP action', components: [
                        (TextInputBuilder(_publishHttpActionInputLabelId,
                            TextInputStyle.short, 'Label')
                          ..required = true
                          ..placeholder = 'Enter action button label...'),
                        (TextInputBuilder(_publishHttpActionInputUrlId,
                            TextInputStyle.short, 'URL')
                          ..required = true
                          ..placeholder = 'Enter URL to open...'),
                        (TextInputBuilder(_publishHttpActionInputHeadersId,
                            TextInputStyle.short, 'Headers')
                          ..required = false
                          ..placeholder =
                              'Enter headers as <param>=<value>,<param>=<value>...'),
                        (TextInputBuilder(_publishHttpActionInputBodyId,
                            TextInputStyle.short, 'Body')
                          ..required = false
                          ..placeholder = 'Enter http body...'),
                        (TextInputBuilder(_publishHttpActionInputClearId,
                            TextInputStyle.short, 'Clear?')
                          ..required = false
                          ..placeholder =
                              'default: false -- Clear notification after opened (true/false)...'),
                      ]) // handle http modal, responding with confirmation
                          .then((httpModalEvent) async {
                        // if url valid (since required) continue
                        if (Uri.tryParse(
                                httpModalEvent[_publishHttpActionInputUrlId]) !=
                            null) {
                          String extraProblems = '';

                          // parse clear, if fail set to default (false) and notif
                          bool clear;
                          if (httpModalEvent[_publishHttpActionInputClearId]
                                  .toLowerCase() ==
                              'true') {
                            clear = true;
                          } else if (httpModalEvent[
                                      _publishHttpActionInputClearId]
                                  .toLowerCase() ==
                              'false') {
                            clear = false;
                          } else {
                            extraProblems +=
                                'Invalid clear (not true or false)\n';
                            clear = false;
                          }

                          // parse headers, if empty null, if fail notif and set to null
                          Map<String, String>? headers = {};
                          if (httpModalEvent[_publishHttpActionInputHeadersId]
                              .isNotEmpty) {
                            try {
                              for (final splitComma in httpModalEvent[
                                      _publishHttpActionInputHeadersId]
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
                                    _publishHttpActionInputLabelId],
                                url: Uri.parse(httpModalEvent[
                                    _publishHttpActionInputUrlId]),
                                headers: headers,
                                method: MethodTypes.values
                                    .byName(httpTypeSelect.toLowerCase()),
                                body: httpModalEvent[
                                    _publishHttpActionInputBodyId],
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

                ComponentMessageBuilder askOpts = ComponentMessageBuilder()
                  ..componentRows = [
                    ComponentRowBuilder()
                      ..addComponent(MultiselectBuilder(_pollPriorityId, [
                        MultiselectOptionBuilder('minimum', 'min'),
                        MultiselectOptionBuilder('low', 'low'),
                        MultiselectOptionBuilder('none', 'none'),
                        MultiselectOptionBuilder('high', 'high'),
                        MultiselectOptionBuilder('maximum', 'max'),
                      ])
                        ..placeholder = 'Choose priority(s) to filter by'
                        ..maxValues = 4),
                    ComponentRowBuilder()
                      ..addComponent(ButtonBuilder(
                          'Fetch', _pollFetchButtonId, ButtonStyle.primary))
                      ..addComponent(ButtonBuilder('More filters',
                          _pollFilterButtonId, ButtonStyle.secondary))
                  ];

                context.respond(askOpts);

                // handle poll filter button, responding with modal
                context.awaitButtonPress(_pollFilterButtonId).then((event) =>
                    event.getModal(title: 'Add filters', components: [
                      (TextInputBuilder(_pollFilterInputMessageId,
                          TextInputStyle.paragraph, 'By message')
                        ..placeholder = 'Enter exact message to filter by...'
                        ..required = false),
                      (TextInputBuilder(_pollFilterInputTitleId,
                          TextInputStyle.short, 'By title')
                        ..placeholder = 'Enter exact title to filter by...'
                        ..required = false),
                      (TextInputBuilder(_pollFilterInputTagsId,
                          TextInputStyle.short, 'By tag(s)')
                        ..placeholder =
                            'Enter comma separated list of tags to filter by...'
                        ..required = false),
                      (TextInputBuilder(
                          _pollFilterInputIdId, TextInputStyle.short, 'By ID')
                        ..placeholder = 'Enter exact message ID to filter by...'
                        ..required = false),
                    ]) // handle filter modal, responding with confirmation
                        .then((event) {
                      if (_pollQueue[event.user]?.filters != null) {
                        _pollQueue[event.user]?.filters
                          ?..message =
                              event[_pollFilterInputMessageId].emptyToNull()
                          ..title = event[_pollFilterInputTitleId].emptyToNull()
                          ..tags = event[_pollFilterInputTagsId]
                              .emptyToNull()
                              ?.split(',')
                          ..id = event[_pollFilterInputIdId].emptyToNull();
                      } else {
                        _pollQueue[event.user]?.filters = FilterOptions(
                            message:
                                event[_pollFilterInputMessageId].emptyToNull(),
                            title: event[_pollFilterInputTitleId].emptyToNull(),
                            tags: event[_pollFilterInputTagsId]
                                .emptyToNull()
                                ?.split(','),
                            id: event[_pollFilterInputIdId].emptyToNull());
                      }
                      event.respond(MessageBuilder.content('Filters saved'));
                    }));
                // handle priorities multiselect, responding with confirmation
                context
                    .awaitMultiSelection<String>(
                  _pollPriorityId,
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
                context
                    .awaitButtonPress(_pollFetchButtonId)
                    .then((event) async {
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

  String onlyFirstCaps() {
    String lowered = toLowerCase();
    return lowered.substring(0, 1).toUpperCase() + lowered.substring(1);
  }
}
