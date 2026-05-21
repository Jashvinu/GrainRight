import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/chat_survey_controller.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/chat_message.dart';
import '../widgets/chat/chat_answer_bar.dart';
import '../widgets/chat/bot_text_bubble.dart';
import '../widgets/chat/polygon_message_widget.dart';
import '../widgets/chat/repeat_group_prompt.dart';
import '../widgets/chat/summary_card.dart';
import '../widgets/chat/typing_indicator.dart';
import '../widgets/chat/user_text_bubble.dart';

class ChatbotSurveyScreen extends StatefulWidget {
  const ChatbotSurveyScreen({super.key});

  @override
  State<ChatbotSurveyScreen> createState() => _ChatbotSurveyScreenState();
}

class _ChatbotSurveyScreenState extends State<ChatbotSurveyScreen>
    with WidgetsBindingObserver {
  static const _formTag = 'chat_form';

  late final FormController _formController;
  late final ChatSurveyController _chatController;
  late final Worker _messageWorker;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _formController = Get.put(FormController(), tag: _formTag);
    _chatController = Get.put(
      ChatSurveyController(
        formController: _formController,
        languageController: Get.find<LanguageController>(),
      ),
      tag: 'chat_survey',
    );
    _messageWorker = ever(_chatController.messages, (_) => _scrollToBottom());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageWorker.dispose();
    _scrollController.dispose();
    if (Get.isRegistered<ChatSurveyController>(tag: 'chat_survey')) {
      Get.delete<ChatSurveyController>(tag: 'chat_survey');
    }
    if (Get.isRegistered<FormController>(tag: _formTag)) {
      Get.delete<FormController>(tag: _formTag);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Baseline Survey'),
        actions: [
          IconButton(
            tooltip: 'Use classic form',
            onPressed: () =>
                Get.offNamed('/form/classic', arguments: Get.arguments),
            icon: const Icon(Icons.article_outlined),
          ),
        ],
      ),
      body: Obx(() {
        if (!_chatController.isReady.value) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        final visible = _visibleMessages(_chatController.messages);
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                itemCount: visible.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final message = visible[index];
                  return _messageWidget(context, message);
                },
              ),
            ),
            Obx(() {
              final field = _chatController.activeField.value;
              if (field == null ||
                  field.inputType == 'polygon' ||
                  field.inputType == 'polygon_pencil') {
                return const SizedBox.shrink();
              }
              return ChatAnswerBar(
                key: ValueKey(field.fieldKey),
                field: field,
                formController: _formController,
                onSubmit: () => _chatController.continueFromField(context),
                onSkip: field.isRequired ? null : _chatController.skipField,
              );
            }),
          ],
        );
      }),
    );
  }

  List<ChatMessage> _visibleMessages(List<ChatMessage> messages) {
    if (messages.isEmpty) return messages;
    final out = <ChatMessage>[];
    for (final m in messages.reversed) {
      out.insert(0, m);
      if (m is BotFieldPromptMessage ||
          m is BotTextMessage ||
          m is PolygonPromptMessage ||
          m is RepeatGroupPromptMessage ||
          m is SummaryMessage) {
        break;
      }
    }
    return out;
  }

  Widget _messageWidget(BuildContext context, ChatMessage message) {
    return switch (message) {
      BotTextMessage(:final text, :final quickReplies) => BotTextBubble(
        text: text,
        quickReplies: quickReplies,
        onQuickReply: _chatController.chooseLanguage,
      ),
      UserTextMessage(:final text) => UserTextBubble(text: text),
      BotFieldPromptMessage(:final field) => BotTextBubble(
        text: field.isRequired
            ? '${field.localizedLabel(context)} *'
            : field.localizedLabel(context),
      ),
      UserFieldAnswerMessage(:final displayValue) => UserTextBubble(
        text: displayValue,
      ),
      PolygonPromptMessage(:final field) => PolygonPromptWidget(
        field: field,
        onSaved: _chatController.acceptPolygon,
        onSkip: field.isRequired ? null : _chatController.skipField,
      ),
      PolygonAnswerMessage(:final coords, :final areaHectares) =>
        PolygonAnswerWidget(coords: coords, areaHectares: areaHectares),
      RepeatGroupPromptMessage(
        :final groupKey,
        :final title,
        :final cropRole,
      ) =>
        RepeatGroupPrompt(
          groupKey: groupKey,
          title: title,
          cropRole: cropRole,
          formController: _formController,
          onDone: (rows) => _chatController.saveRepeatGroup(
            groupKey: groupKey,
            title: title,
            cropRole: cropRole,
            rows: rows,
          ),
        ),
      RepeatGroupAnswerMessage(:final title, :final rowCount) => UserTextBubble(
        text: '$title: $rowCount saved',
      ),
      SummaryMessage(:final snapshot) => Obx(
        () => SummaryCard(
          snapshot: snapshot,
          isSubmitting: _chatController.isSubmitting.value,
          onSubmit: _chatController.submit,
        ),
      ),
      TypingIndicatorMessage() => const TypingIndicator(),
    };
  }
}
