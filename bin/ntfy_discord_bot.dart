import 'package:ntfy_discord_bot/ntfy_discord_bot.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

/// Environment variables (pass in with --define=<KEY>=<VALUE>, system environment variables not supported!
/// API_TOKEN (required, from discord dev page)
/// GUILD_ID (optional, for single guild setup, leave unset to for global command registration)
Future<void> main() async {
  // check to ensure API_TOKEN is set, or else somewhat cryptic message is returned
  if (!bool.hasEnvironment('API_TOKEN')) {
    print(
        'Error: API_TOKEN env var unset. Use --define=<KEY>=<VALUE> to set it!');
    return;
  }

  CommandsPlugin commands = CommandsPlugin(
      prefix: null,
      // give GUILD_ID if set, else give null to scope slash commands as global
      guild: bool.hasEnvironment('GUILD_ID')
          ? Snowflake.parse(String.fromEnvironment('GUILD_ID'))
          : null,
      options: CommandsOptions(
          type: CommandType.slashOnly,
          defaultResponseLevel: ResponseLevel.public));

  final ntfyCommand = NtfyCommand();

  // add all commands included in ntfy_commands.dart
  for (final command in ntfyCommand.commands) {
    commands.addCommand(command);
  }

  // add info command from info_command.dart
  commands.addCommand(InfoCommand(startupTime: DateTime.now()).infoCommand);

  // create and add DateTime converter for Duration set in publishing and polling messages
  Converter<DateTime> dateTimeConverter =
      Converter<DateTime>((viewRaw, context) {
    String view = viewRaw.getQuotedWord();
    return DateTime.tryParse(view);
  });
  commands.addConverter(dateTimeConverter);

  // sanity check ensure commands are originating from slash commands
  commands.check(ChatCommandCheck());

  // handle errors a little more gracefully, most of the exceptions in here cannot be thrown by this app
  commands.onCommandError.listen((error) async {
    if (error is CommandInvocationException) {
      String? title;
      String? description;

      if (error is CheckFailedException) {
        // Should not really hit these with slash commands
        final failed = error.failed;

        if (failed is CooldownCheck) {
          title = 'Command on cooldown';
          description =
              "You can't use this command right now because it is on cooldown. Please wait ${failed.remaining(error.context).toString()} and try again.";
        } else {
          title = "You can't use this command! Reason: ${failed.name}";
          description =
              'This command can only be used by certain users in certain contexts.'
              ' Check that you have permission to execute the command, or contact a developer for more information.';
        }
      }

      // Should not hit these with slash commands
      else if (error is NotEnoughArgumentsException) {
        title = 'Not enough arguments';
        description = "You didn't provide enough arguments for this command."
            " Please try again and use the Slash Command menu for help, or contact a developer for more information.";
      } else if (error is BadInputException) {
        title = "Couldn't parse input";
        description =
            "Your command couldn't be executed because we were unable to understand your input."
            " Please try again with different inputs or contact a developer for more information.";
      } else if (error is UncaughtException) {
        print('Uncaught exception in command: ${error.exception}');
        title = 'A command threw an exception!';
        description =
            'Unfortunately, such problems are unrecoverable, please open a Github issue with steps to reproduce.';
      }

      // Send a generic response using above [title] and [description] fills
      final embed = EmbedBuilder()
        // TODO red? ..color = DiscordColor.red
        ..title = title ?? 'An error has occurred'
        ..description = description ??
            "Your command couldn't be executed because of an error. Please contact a developer for more information."
        ..footer = EmbedFooterBuilder(text: error.runtimeType.toString())
        ..timestamp = DateTime.now();

      await error.context.respond(MessageBuilder(embeds: [embed]));
      return;
    }

    if (error is BadInputException) {
      final context = error.context;
      if (error is ConverterFailedException &&
          context is InteractionChatContext) {
        await context.respond(MessageBuilder(
            content: '${error.input.getQuotedWord()} is not a valid date!'));
        return;
      }
    }

    print('Unhandled exception: $error');
  });

  await Nyxx.connectGatewayWithOptions(
    GatewayApiOptions(
      token: String.fromEnvironment('API_TOKEN'),
      intents: GatewayIntents.allUnprivileged,
      initialPresence: PresenceBuilder(
        isAfk: false,
        status: CurrentUserStatus.online,
        activities: [
          ActivityBuilder(
              name: 'Awaiting notifications...', type: ActivityType.watching)
        ],
      ),
    ),
    GatewayClientOptions(
      plugins: [CliIntegration(), IgnoreExceptions(), Logging(), commands],
      // shutdownHook: ntfyCommand.shutdown, TODO shutdown hook
      // TODO turn false all allowed mentions
    ),
  );

  // TODO print rate limit events if they happen
  /* outerBot.gateway.events.listen((event) {
    if (event is RateLimitedEvent)
    print(
        rateLimitedEvent.response?.reasonPhrase ?? rateLimitedEvent.toString());
  }); */
}
