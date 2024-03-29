import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:ntfy_discord_bot/src/wrappers.dart';

class State {
  final NtfyClient _client = NtfyClient();

  void changeBasePath(Uri basePath) {
    _client.changeBasePath(basePath);
  }

  Uri getBasePath() {
    return _client.basePath;
  }

  Future<MessageResponse> publish(PublishableMessage message, Uri basePath) {
    changeBasePath(basePath);
    return _client.publishMessage(message);
  }

  Future<List<MessageResponse>> poll(PollWrapper opts, Uri basePath) {
    changeBasePath(basePath);
    return _client.pollMessages(opts.topics,
        since: opts.since,
        scheduled: opts.scheduled ?? false,
        filters: opts.filters);
  }

  Future<Stream<MessageResponse>> get(StreamWrapper opts, Uri basePath) async {
    changeBasePath(basePath);
    return await _client.getMessageStream(opts.topics, filters: opts.filters);
  }

  void dispose() {
    _client.close();
  }
}
