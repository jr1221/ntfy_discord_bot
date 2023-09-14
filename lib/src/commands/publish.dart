part of 'ntfy_commands.dart';

ChatCommand get publishCommand => ChatCommand(
    'publish',
    'Send a message',
    id('publish', (
      ChatContext context,
      @Description('Unique topic name') String topic, [
      @Description('schedule message to send at ISO 8601 date')
      DateTime? schedSet,
      @Description('cache values on server') bool? cache,
      @Description('use FCM to send messages') bool? firebase,
      @Description('number to call (pro/self hosted feature)') String? call,
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
                    SelectMenuOptionBuilder(label: 'minimum', value: 'min'),
                    SelectMenuOptionBuilder(label: 'low', value: 'low'),
                    SelectMenuOptionBuilder(
                        label: 'none', value: 'none', description: 'Default'),
                    SelectMenuOptionBuilder(label: 'high', value: 'high'),
                    SelectMenuOptionBuilder(label: 'maximum', value: 'max'),
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
          .then((event) async {
        tempPubMessage.priority =
            ntfy_lib.PriorityLevels.values.byName(event.selected.toLowerCase());
        await event.respond(MessageBuilder(
            content:
                'Info saved.  Remember to click Publish to send your message!'));
      });

      final ComponentId publishOptsInputMessageId = ComponentId.generate();
      final ComponentId publishOptsInputTitleId = ComponentId.generate();
      final ComponentId publishOptsInputTagsId = ComponentId.generate();
      final ComponentId publishOptsInputAttachmentId = ComponentId.generate();
      final ComponentId publishOptsInputFilenameId = ComponentId.generate();

      // handle customize (opts) button, responding with modal
      context
          .awaitButtonPress(publishOptsButtonId)
          .then((event) => event.getModal(
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
                    event[publishOptsInputMessageId.toString()]!.emptyToNull();
                event[publishOptsInputMessageId.toString()];
                tempPubMessage.title =
                    event[publishOptsInputTitleId.toString()]!.emptyToNull();
                tempPubMessage.tags = event[publishOptsInputTagsId.toString()]!
                    .emptyToNull()
                    ?.split(',');

                // if empty return null else return Uri.tryParse attachment url
                tempPubMessage.attach =
                    event[publishOptsInputAttachmentId.toString()]!
                                .emptyToNull() ==
                            null
                        ? null
                        : Uri.tryParse(
                            event[publishOptsInputAttachmentId.toString()]!);

                tempPubMessage.filename =
                    event[publishOptsInputFilenameId.toString()]!.emptyToNull();

                await event.respond(MessageBuilder(
                    content:
                        'Info saved.  Remember to click Publish to send your message!'));
              }));

      final ComponentId publishAdvOptsInputEmailId = ComponentId.generate();
      final ComponentId publishAdvOptsInputClickId = ComponentId.generate();
      final ComponentId publishAdvOptsInputIconId = ComponentId.generate();
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
                  placeholder: 'Enter url to open when clicked on android...'),
              TextInputBuilder(
                  customId: publishAdvOptsInputIconId.toString(),
                  style: TextInputStyle.short,
                  label: 'Icon URL',
                  isRequired: false,
                  placeholder: 'Enter icon URL to see on android...'),
              TextInputBuilder(
                  customId: publishAdvOptsInputAuthUsernameId.toString(),
                  style: TextInputStyle.short,
                  label: 'Authorization',
                  isRequired: false,
                  placeholder: 'Enter username here...'),
              TextInputBuilder(
                  customId: publishAdvOptsInputAuthPasswordId.toString(),
                  style: TextInputStyle.short,
                  label: ' ',
                  isRequired: false,
                  placeholder: 'Enter password here...'),
            ],
          ) // handle adv opts modal, responding with confirmation
              .then((event) {
            String extraProblems = '';

            tempPubMessage.email =
                event[publishAdvOptsInputEmailId.toString()]!.emptyToNull();

            // if Uri.tryParse click url is null, add notif to extra problems
            tempPubMessage.click =
                Uri.tryParse(event[publishAdvOptsInputClickId.toString()]!);
            if (tempPubMessage.click == null) {
              extraProblems += 'Invalid click URL\n';
            }

            // if icon is empty return null else return Uri.tryParse icon
            tempPubMessage.icon = event[publishAdvOptsInputIconId.toString()]!
                        .emptyToNull() ==
                    null
                ? null
                : Uri.tryParse(event[publishAdvOptsInputIconId.toString()]!);

            // if auth user + password not empty add auth
            if (event[publishAdvOptsInputAuthUsernameId.toString()]!
                    .isNotEmpty &&
                event[publishAdvOptsInputAuthUsernameId.toString()]!
                    .isNotEmpty) {
              tempPubMessage.basicAuthorization = (
                username: event[publishAdvOptsInputAuthUsernameId.toString()]!,
                password: event[publishAdvOptsInputAuthUsernameId.toString()]!
              );
              // if one or other auth user + password not empty notif that auth set failed
            } else if (event[publishAdvOptsInputAuthUsernameId.toString()]!
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

      final ComponentId publishViewActionInputLabelId = ComponentId.generate();
      final ComponentId publishViewActionInputUrlId = ComponentId.generate();
      final ComponentId publishViewActionInputClearId = ComponentId.generate();
      // handle view action button, responding with modal
      context.awaitButtonPress(publishViewActionButtonId).then((event) =>
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
            url = Uri.tryParse(event[publishViewActionInputUrlId.toString()]!);
            if (url == null) {
              extraProblems += 'Invalid URL\n';
            }

            // parse clear to true or false, set to default false if failure
            if (event[publishViewActionInputClearId.toString()]!
                    .toLowerCase() ==
                'true') {
              clear = true;
            } else if (event[publishViewActionInputClearId.toString()]!
                    .toLowerCase() ==
                'false') {
              clear = false;
            } else {
              extraProblems += 'Invalid clear (not true or false)\n';
              clear = false;
            }

            //  url not null (since valid one required), send confirmation, else send warning
            if (url != null) {
              tempPubMessage.actions.add(ntfy_lib.Action.viewAction(
                  label: event[publishViewActionInputLabelId.toString()]!,
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
      context.awaitButtonPress(publishBroadcastActionButtonId).then((event) =>
          event.getModal(title: 'Add broadcast action', components: [
            TextInputBuilder(
                customId: publishBroadcastActionInputLabelId.toString(),
                style: TextInputStyle.short,
                label: 'Label',
                isRequired: true,
                placeholder: 'Enter action button label...'),
            TextInputBuilder(
                customId: publishBroadcastActionInputIntentId.toString(),
                style: TextInputStyle.short,
                label: 'Intent',
                isRequired: false,
                placeholder:
                    'Enter android intent name (default io.heckel.ntfy.USER_ACTION)...'),
            TextInputBuilder(
                customId: publishBroadcastActionInputExtrasId.toString(),
                style: TextInputStyle.short,
                label: 'Extras',
                isRequired: false,
                placeholder:
                    'Enter android intent extras as <param>=<value>,<param>=<value>...'),
            TextInputBuilder(
                customId: publishBroadcastActionInputClearId.toString(),
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
            if (event[publishBroadcastActionInputClearId.toString()]!
                    .toLowerCase() ==
                'true') {
              clear = true;
            } else if (event[publishBroadcastActionInputClearId.toString()]!
                    .toLowerCase() ==
                'false') {
              clear = false;
            } else {
              extraProblems += 'Invalid clear (not true or false)\n';
              clear = false;
            }

            // parse extras, warning if not parsed, null if not present
            Map<String, String>? extras = {};
            if (event[publishBroadcastActionInputExtrasId.toString()]!
                .isNotEmpty) {
              try {
                for (final splitComma
                    in event[publishBroadcastActionInputExtrasId.toString()]!
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
            tempPubMessage.actions.add(ntfy_lib.Action.broadcastAction(
              label: event[publishBroadcastActionInputLabelId.toString()]!,
              intent: event[publishBroadcastActionInputIntentId.toString()],
              extras: extras,
              clear: clear,
            ));
            await event.respond(MessageBuilder(
                content:
                    '$extraProblems View action saved.  Remember to click Publish to send your message!'));
          }));

      final ComponentId publishHttpActionInputLabelId = ComponentId.generate();
      final ComponentId publishHttpActionInputUrlId = ComponentId.generate();
      final ComponentId publishHttpActionInputHeadersId =
          ComponentId.generate();
      final ComponentId publishHttpActionInputBodyId = ComponentId.generate();
      final ComponentId publishHttpActionInputClearId = ComponentId.generate();
      // handle http button, responding with modal
      context.awaitButtonPress(publishHttpActionButtonId).then((event) =>
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
                customId: publishHttpActionInputHeadersId.toString(),
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
            if (Uri.tryParse(
                    httpModalEvent[publishHttpActionInputUrlId.toString()]!) !=
                null) {
              String extraProblems = '';

              // parse clear, if fail set to default (false) and notif
              bool clear;
              if (httpModalEvent[publishHttpActionInputClearId.toString()]!
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
                extraProblems += 'Invalid clear (not true or false)\n';
                clear = false;
              } else {
                clear = false;
              }

              // parse headers, if empty null, if fail notif and set to null
              Map<String, String>? headers = {};
              if (httpModalEvent[publishHttpActionInputHeadersId.toString()]!
                  .isNotEmpty) {
                try {
                  for (final splitComma in httpModalEvent[
                          publishHttpActionInputHeadersId.toString()]!
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
                final builder =
                    SelectMenuOptionBuilder(label: value, value: value);
                if (value == 'POST') {
                  builder.description = 'recommended';
                }
                return builder;
              }).then((httpTypeSelect) {
                // must use context.user here unfortunately
                tempPubMessage.actions.add(ntfy_lib.Action.httpAction(
                    label: httpModalEvent[
                        publishHttpActionInputLabelId.toString()]!,
                    url: Uri.parse(httpModalEvent[
                        publishHttpActionInputUrlId.toString()]!),
                    headers: headers,
                    method: ntfy_lib.MethodTypes.values
                        .byName(httpTypeSelect.toLowerCase()),
                    body:
                        httpModalEvent[publishHttpActionInputBodyId.toString()],
                    clear: clear));
                httpModalEvent.respond(
                    MessageBuilder(content: 'Method $httpTypeSelect saved!'));
              });
            } else {
              await httpModalEvent.respond(MessageBuilder(
                  content: 'Please check your inputted URL and try again!'));
            }
          }));

// handle publish button, responding with message receipt returned by server
      context.awaitButtonPress(publishButtonId).then((event) async {
        await event.acknowledge();
        final apiResponse = await ntfyCommand.state.publish(
            tempPubMessage.generate(), await ntfyCommand.getBasepath(context));
        event.respond(MessageBuilder(
            embeds: [NtfyCommand.messageToEmbed(apiResponse)],
            content: 'How the message will look over discord:'));
      });
    }));
