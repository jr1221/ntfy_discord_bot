part of 'ntfy_commands.dart';

ChatCommand get pollCommand => ChatCommand(
    'poll',
    'search recently sent messages',
    id('poll', (
      ChatContext context,
      @Name('topic')
      @Description('topic or topics to search by, comma separated')
      String topics, [
      @Description('more recent than this ISO 8601 date') DateTime? since,
      @Description('also show messages scheduled to sent') bool? scheduled,
    ]) async {
      if (topics.split(',').isNotEmpty) {
        ntfyCommand.pollQueue[context.user] = PollWrapper(topics.split(','))
          ..since = since
          ..scheduled = scheduled;
      } else {
        await context.respond(MessageBuilder(
            content: 'Could not parse topics, please try again.'));
        return;
      }
      await ntfyCommand.sendFilterSelection(context, true);
    }));
