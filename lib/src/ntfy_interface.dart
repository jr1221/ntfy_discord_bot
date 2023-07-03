import 'package:ntfy_dart/ntfy_dart.dart';

class State {
  final NtfyClient _client = NtfyClient();

  void changeBasePath(Uri basePath) {
    _client.changeBasePath(basePath);
  }

  Uri getBasePath() {
    return _client.basePath;
  }

  Future<MessageResponse> publish(PublishableMessage message) {
    return _client.publishMessage(message);
  }

  Future<List<MessageResponse>> poll(PollWrapper opts) {
    return _client.pollMessages(opts.topics,
        since: opts.since,
        scheduled: opts.scheduled ?? false,
        filters: opts.filters);
  }

  Future<Stream<MessageResponse>> get(StreamWrapper opts) async {
    return await _client.getMessageStream(opts.topics, filters: opts.filters);
  }

  void dispose() {
    _client.close();
  }
}

/// A wrapper to store the stream request and send it to the ntfy state interface
class StreamWrapper {
  List<String> topics;

  FilterOptions? filters;

  StreamWrapper(this.topics);
}

/// A wrapper to store the poll request and send it to the ntfy state interface
class PollWrapper extends StreamWrapper {
  DateTime? since;

  bool? scheduled;

  PollWrapper(super.topics);
}
