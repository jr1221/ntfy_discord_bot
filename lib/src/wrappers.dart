import 'package:ntfy_dart/ntfy_dart.dart';
import 'package:nyxx/nyxx.dart';

abstract class ParentWrapper {
  List<String> topics;

  FilterOptions? filters;

  ParentWrapper(this.topics);
}

/// A wrapper to store the stream request and send it to the ntfy state interface
class StreamWrapper extends ParentWrapper {
  TextChannel sendPlace;

  Uri basePath;

  StreamWrapper(super.topics, this.sendPlace, this.basePath);
}

/// A wrapper to store the poll request and send it to the ntfy state interface
class PollWrapper extends ParentWrapper {
  DateTime? since;

  bool? scheduled;

  PollWrapper(super.topics);
}

class MutableFilterOptions {
  String? id;

  String? message;

  String? title;

  List<PriorityLevels>? priority;

  List<String>? tags;

  FilterOptions generate() => FilterOptions(
      id: id, message: message, title: title, priority: priority, tags: tags);
}

class MutablePublishableMessage {
  String topic;

  String? message;

  String? title;

  String? filename;

  DateTime? delay;

  String? email;

  String? call;

  List<String>? tags;

  PriorityLevels? priority;

  List<Action> actions = [];

  Uri? click;

  Uri? attach;

  Uri? icon;

  ({String username, String password})? basicAuthorization;

  ({String accessToken})? tokenAuthorization;

  bool? cache;

  bool? firebase;

  MutablePublishableMessage({required this.topic});

  PublishableMessage generate() {
    if (basicAuthorization != null) {
      return PublishableMessage.withAuthentication(
          topic: topic,
          message: message,
          title: title,
          filename: filename,
          delay: delay,
          email: email,
          call: call,
          priority: priority,
          actions: actions,
          tags: tags,
          click: click,
          attach: attach,
          icon: icon,
          cache: cache,
          firebase: firebase,
          username: basicAuthorization!.username,
          password: basicAuthorization!.password);
    } else if (tokenAuthorization != null) {
      return PublishableMessage.withTokenAuthentication(
          topic: topic,
          message: message,
          title: title,
          filename: filename,
          delay: delay,
          email: email,
          call: call,
          priority: priority,
          actions: actions,
          tags: tags,
          click: click,
          attach: attach,
          icon: icon,
          cache: cache,
          firebase: firebase,
          accessToken: tokenAuthorization!.accessToken);
    } else {
      return PublishableMessage(
          topic: topic,
          message: message,
          title: title,
          filename: filename,
          delay: delay,
          email: email,
          call: call,
          priority: priority,
          actions: actions,
          tags: tags,
          click: click,
          attach: attach,
          icon: icon,
          cache: cache,
          firebase: firebase);
    }
  }
}
