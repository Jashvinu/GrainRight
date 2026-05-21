import 'package:millets_now/models/form_config.dart';

sealed class ChatMessage {
  final String id;
  final DateTime at;

  ChatMessage({String? id, DateTime? at})
    : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      at = at ?? DateTime.now();
}

class BotTextMessage extends ChatMessage {
  final String text;
  final List<String>? quickReplies;

  BotTextMessage(this.text, {this.quickReplies, super.id, super.at});
}

class UserTextMessage extends ChatMessage {
  final String text;

  UserTextMessage(this.text, {super.id, super.at});
}

class BotFieldPromptMessage extends ChatMessage {
  final FormFieldConfig field;

  BotFieldPromptMessage(this.field, {super.id, super.at});
}

class UserFieldAnswerMessage extends ChatMessage {
  final FormFieldConfig field;
  final String displayValue;

  UserFieldAnswerMessage(this.field, this.displayValue, {super.id, super.at});
}

class PolygonPromptMessage extends ChatMessage {
  final FormFieldConfig field;

  PolygonPromptMessage(this.field, {super.id, super.at});
}

class PolygonAnswerMessage extends ChatMessage {
  final List<List<double>> coords;
  final double areaHectares;

  PolygonAnswerMessage(this.coords, this.areaHectares, {super.id, super.at});
}

class RepeatGroupPromptMessage extends ChatMessage {
  final String groupKey;
  final String title;
  final String? cropRole;

  RepeatGroupPromptMessage(
    this.groupKey, {
    required this.title,
    this.cropRole,
    super.id,
    super.at,
  });
}

class RepeatGroupAnswerMessage extends ChatMessage {
  final String title;
  final int rowCount;

  RepeatGroupAnswerMessage(this.title, this.rowCount, {super.id, super.at});
}

class SummaryMessage extends ChatMessage {
  final Map<String, dynamic> snapshot;

  SummaryMessage(this.snapshot, {super.id, super.at});
}

class TypingIndicatorMessage extends ChatMessage {
  TypingIndicatorMessage({super.id, super.at});
}
