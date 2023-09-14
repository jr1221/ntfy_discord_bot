part of 'ntfy_commands.dart';

ChatCommand get helpCommand => ChatCommand(
    'help',
    'Get info about ntfy connector',
    id('help', (ChatContext context) {
      EmbedBuilder aboutEmbed = EmbedBuilder(title: 'About Ntfy', fields: [
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
              url:
                  Uri.parse('https://apps.apple.com/us/app/ntfy/id1625396347')),
          ButtonBuilder(
              style: ButtonStyle.link,
              label: 'Ntfy Site',
              url: Uri.parse('https://ntfy.sh/'))
        ])
      ]);

      context.respond(aboutResponse);
    }));
