part of 'ntfy_commands.dart';

// db
final ConfDatabase database = ConfDatabase();

ChatGroup get serverCommand => ChatGroup(
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
              await ntfyCommand.updateBasepath(context, changedUrl);
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
                      'The server URL is: ${await ntfyCommand.getBasepath(context)}'));
            })),
        ChatCommand(
            'reset',
            'Reset the server URL to default (ntfy.sh)',
            id('server-reset', (ChatContext context) async {
              await ntfyCommand.updateBasepath(context, 'https://ntfy.sh/');
              context.respond(MessageBuilder(
                  content:
                      'Server successfully changed to https://ntfy.sh/ !  This is saved on a per-guild basis, or per-user if it is a DM.'));
            })),
      ],
    );
