import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../controllers/chat_survey_controller.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/chat_message.dart';
import '../models/survey_launch.dart';
import '../widgets/chat/chat_answer_bar.dart';
import '../widgets/chat/bot_text_bubble.dart';
import '../widgets/chat/polygon_message_widget.dart';
import '../widgets/chat/repeat_group_prompt.dart';
import '../widgets/chat/summary_card.dart';
import '../widgets/chat/typing_indicator.dart';
import '../widgets/chat/user_text_bubble.dart';
import '../widgets/app_back_button.dart';

class ChatbotSurveyScreen extends StatefulWidget {
  const ChatbotSurveyScreen({super.key});

  @override
  State<ChatbotSurveyScreen> createState() => _ChatbotSurveyScreenState();
}

class _ChatbotSurveyScreenState extends State<ChatbotSurveyScreen>
    with WidgetsBindingObserver {
  late final String _formTag;
  late final String _chatTag;
  late final FormController _formController;
  late final ChatSurveyController _chatController;
  late final LanguageController _languageController;
  late final Worker _messageWorker;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _formTag = 'chat_form_${identityHashCode(this)}';
    _chatTag = 'chat_survey_${identityHashCode(this)}';
    _formController = Get.put(FormController(), tag: _formTag);
    _languageController = Get.find<LanguageController>();
    _chatController = Get.put(
      ChatSurveyController(
        formController: _formController,
        languageController: _languageController,
      ),
      tag: _chatTag,
    );
    _messageWorker = ever(_chatController.messages, (_) => _scrollToBottom());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageWorker.dispose();
    _scrollController.dispose();
    unawaited(_persistAndReleaseControllers());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_chatController.persistProgress());
    }
  }

  Future<void> _persistAndReleaseControllers() async {
    await _chatController.persistProgress();
    if (Get.isRegistered<ChatSurveyController>(tag: _chatTag)) {
      Get.delete<ChatSurveyController>(tag: _chatTag);
    }
    if (Get.isRegistered<FormController>(tag: _formTag)) {
      Get.delete<FormController>(tag: _formTag);
    }
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

  Future<void> _switchToClassic() async {
    await _chatController.persistProgress();
    Get.offNamed('/form/classic', arguments: _switchArguments());
  }

  SurveyLaunchArgs _switchArguments() {
    return SurveyLaunchArgs.from(Get.arguments).forModeSwitch();
  }

  Future<void> _setLanguage(String code) async {
    await _chatController.setLanguageCode(code);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('baseline_survey')),
        actions: [
          _buildLanguageMenu(),
          IconButton(
            tooltip: UiStrings.t('use_classic_form'),
            onPressed: _switchToClassic,
            icon: const Icon(Icons.article_outlined),
          ),
        ],
      ),
      body: Obx(() {
        final _ = _languageController.language.value;
        if (!_chatController.isReady.value) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        final visible = _visibleMessages(_chatController.messages);
        final activeField = _chatController.activeField.value;
        final inputType = activeField?.inputType;
        final showAnswerBar =
            inputType != null &&
            inputType != 'polygon' &&
            inputType != 'polygon_pencil';
        final answerField = showAnswerBar ? activeField : null;
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        final liftAnswerBar =
            inputType != null && _shouldLiftAnswerBar(inputType);
        final answerBottom = _answerBottomOffset(
          keyboardVisible: keyboardVisible,
          liftAnswerBar: liftAnswerBar,
        );
        final listBottomPadding = answerField != null
            ? _messageListBottomPadding(
                keyboardVisible: keyboardVisible,
                liftAnswerBar: liftAnswerBar,
              )
            : 18.0;

        return Stack(
          children: [
            Positioned.fill(
              child: ListView.separated(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPadding),
                itemCount: visible.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final message = visible[index];
                  return _messageWidget(context, message);
                },
              ),
            ),
            if (answerField != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: answerBottom,
                child: ChatAnswerBar(
                  key: ValueKey(answerField.fieldKey),
                  field: answerField,
                  formController: _formController,
                  onSubmit: () => _chatController.continueFromField(context),
                  onSkip: answerField.isRequired
                      ? null
                      : _chatController.skipField,
                  floating: true,
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildLanguageMenu() {
    return Obx(() {
      final code = _languageController.language.value;
      return PopupMenuButton<String>(
        tooltip: UiStrings.t('change_language'),
        initialValue: code,
        icon: const Icon(Icons.translate_rounded),
        onSelected: _setLanguage,
        itemBuilder: (context) => [
          PopupMenuItem(value: 'en', child: Text(UiStrings.t('language_english'))),
          PopupMenuItem(value: 'hi', child: Text(UiStrings.t('language_hindi'))),
          PopupMenuItem(value: 'mr', child: Text(UiStrings.t('language_marathi'))),
        ],
      );
    });
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

  bool _shouldLiftAnswerBar(String inputType) {
    return switch (inputType) {
      'text' ||
      'textarea' ||
      'numeric' ||
      'currency' ||
      'acre' ||
      'mobile' ||
      'aadhar' ||
      'millet_land_picker' ||
      'boolean' ||
      'dropdown' ||
      'multiselect' ||
      'date' ||
      'auto_calc' => true,
      _ => false,
    };
  }

  double _answerBottomOffset({
    required bool keyboardVisible,
    required bool liftAnswerBar,
  }) {
    if (liftAnswerBar) return 88.0;
    return keyboardVisible ? 8.0 : 24.0;
  }

  double _messageListBottomPadding({
    required bool keyboardVisible,
    required bool liftAnswerBar,
  }) {
    if (keyboardVisible && !liftAnswerBar) return 108.0;
    return liftAnswerBar ? 206.0 : 142.0;
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
          key: ValueKey('chat-repeat-$groupKey-${cropRole ?? ''}'),
          groupKey: groupKey,
          title: title,
          cropRole: cropRole,
          formController: _formController,
          initialRows: _repeatInitialRows(groupKey, cropRole),
          onChanged: (rows) => _chatController.updateRepeatGroupRows(
            groupKey: groupKey,
            cropRole: cropRole,
            rows: rows,
          ),
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

  List<Map<String, dynamic>> _repeatInitialRows(
    String groupKey,
    String? cropRole,
  ) {
    return switch (groupKey) {
      'kharif_crops' || 'other_crops' => _formController.kharifRows.toList(),
      'main_crop_yearly' => _formController.yearlyRows.toList(),
      'crop_practices' =>
        _formController.practiceRows
            .where((row) => row['crop_role'] == cropRole)
            .toList(),
      _ => const [],
    };
  }
}
