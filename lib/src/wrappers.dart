import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:nyxx/nyxx.dart';

abstract class ParentWrapper {
  List<String> topics;

  FilterOptions? filters;

  ParentWrapper(this.topics);
}

/// A wrapper to store the stream request and send it to the ntfy state interface
class StreamWrapper extends ParentWrapper {
  ISend sendPlace;

  Uri basePath;

  StreamWrapper(super.topics, this.sendPlace, this.basePath);
}

/// A wrapper to store the poll request and send it to the ntfy state interface
class PollWrapper extends ParentWrapper {
  DateTime? since;

  bool? scheduled;

  PollWrapper(super.topics);
}
