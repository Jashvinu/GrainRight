import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../models/satellite/farm_chat_message_model.dart';
import '../utils/harvest_machine_capture.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class FarmStatusUpdateResult {
  final String message;
  final String question;
  final String stage;
  final DateTime updatedAt;
  final Uint8List? photoBytes;
  final String? photoName;
  final List<FarmChatMessageDraft> transcript;
  final Map<String, dynamic> weatherSnapshot;
  final Map<String, dynamic> farmContext;

  const FarmStatusUpdateResult({
    required this.message,
    required this.question,
    required this.stage,
    required this.updatedAt,
    this.transcript = const <FarmChatMessageDraft>[],
    this.weatherSnapshot = const <String, dynamic>{},
    this.farmContext = const <String, dynamic>{},
    this.photoBytes,
    this.photoName,
  });
}

class FarmerStatusChatScreen extends StatefulWidget {
  final String farmName;
  final String crop;
  final String variety;
  final String location;
  final String stage;
  final int daysAfterSowing;
  final String stageQuestion;
  final String? lifecycleContext;
  final String? priorStatus;
  final Map<String, dynamic> weatherSnapshot;
  final Map<String, dynamic> farmContext;
  final bool requiresPhoto;

  const FarmerStatusChatScreen({
    super.key,
    required this.farmName,
    required this.crop,
    required this.variety,
    required this.location,
    required this.stage,
    required this.daysAfterSowing,
    required this.stageQuestion,
    this.lifecycleContext,
    this.priorStatus,
    this.weatherSnapshot = const <String, dynamic>{},
    this.farmContext = const <String, dynamic>{},
    required this.requiresPhoto,
  });

  @override
  State<FarmerStatusChatScreen> createState() => _FarmerStatusChatScreenState();
}

class _FarmerStatusChatScreenState extends State<FarmerStatusChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_StatusMessage> _messages = [];
  String _draft = '';
  Uint8List? _photoBytes;
  String? _photoName;
  static const Map<String, List<String>> _stageQuickReplyKeys = {
    'Sowing': [
      'status_reply_germination_healthy',
      'status_reply_moisture_stress',
      'status_reply_need_irrigation_today',
      'status_reply_need_reinspection',
    ],
    'Establishment': [
      'status_reply_patchy_stands',
      'status_reply_good_germination',
      'status_reply_need_replanting',
      'status_reply_irrigation_done',
    ],
    'Vegetative': [
      'status_reply_growth_normal',
      'status_reply_weeds_observed',
      'status_reply_leaf_pale',
      'status_reply_watering_done',
    ],
    'Flowering': [
      'status_reply_flowering_good',
      'status_reply_pollen_drop_seen',
      'status_reply_need_moisture_topup',
      'status_reply_insect_attack',
    ],
    'Grain filling': [
      'status_reply_grains_filling',
      'status_reply_flower_drop_seen',
      'status_reply_low_moisture',
      'status_reply_need_support_recheck',
    ],
    'Maturity': [
      'status_reply_panicles_developed',
      'status_reply_grain_drying_normal',
      'status_reply_need_harvesting_support',
      'status_reply_check_moisture',
    ],
  };

  @override
  void initState() {
    super.initState();
    _messages.add(_StatusMessage(isUser: false, text: _stageQuestionText));

    if (widget.lifecycleContext != null &&
        widget.lifecycleContext!.trim().isNotEmpty) {
      _messages.add(
        _StatusMessage(isUser: false, text: widget.lifecycleContext!.trim()),
      );
    }

    if (widget.requiresPhoto) {
      _messages.add(
        _StatusMessage(
          isUser: false,
          text: UiStrings.f('stage_needs_field_photo', {'stage': widget.stage}),
        ),
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _appendMessage({required bool isUser, required String text}) {
    setState(() {
      _messages.add(_StatusMessage(isUser: isUser, text: text));
      if (isUser) {
        _draft = text;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showToast(UiStrings.t('write_farm_update_before_sending'));
      return;
    }
    _inputController.clear();
    _appendMessage(isUser: true, text: text);
    _appendMessage(
      isUser: false,
      text: UiStrings.f('status_note_saved_for_crop', {
        'crop': widget.crop,
        'variety': widget.variety,
      }),
    );
  }

  void _applyQuickSuggestion(String suggestion) {
    _inputController.text = suggestion;
    _sendMessage();
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto() async {
    final result = await pickHarvestMachineImage();
    if (result == null) return;
    if (!mounted) return;

    setState(() {
      _photoBytes = result.bytes;
      _photoName = result.name;
    });
  }

  void _removePhoto() {
    setState(() {
      _photoBytes = null;
      _photoName = null;
    });
  }

  Future<void> _submitStatus() async {
    if (_draft.trim().isEmpty) {
      _showToast(UiStrings.t('add_crop_status_before_submit'));
      return;
    }
    if (widget.requiresPhoto && _photoBytes == null) {
      _showToast(UiStrings.t('attach_photo_before_stage_submit'));
      return;
    }

    Navigator.pop(
      context,
      FarmStatusUpdateResult(
        message: _draft.trim(),
        question: widget.stageQuestion,
        stage: widget.stage,
        updatedAt: DateTime.now(),
        transcript: _transcript(),
        weatherSnapshot: widget.weatherSnapshot,
        farmContext: widget.farmContext,
        photoBytes: _photoBytes,
        photoName: _photoName,
      ),
    );
  }

  String get _cropName => UiStrings.option(widget.crop);

  String get _varietyName => UiStrings.option(widget.variety);

  String? get _weatherContextText {
    final weather = widget.farmContext['weather'] is Map
        ? Map<String, dynamic>.from(widget.farmContext['weather'] as Map)
        : widget.weatherSnapshot;
    if (weather.isEmpty) return null;
    final parts = <String>[];
    final rain24h = _num(weather['rain_24h_mm']);
    final rain7d = _num(weather['rain_7d_mm'] ?? weather['total_rain_mm']);
    final waterNeed = '${weather['water_need_label'] ?? ''}'.trim();
    final weatherSummary = '${weather['weather_summary'] ?? ''}'.trim();
    if (weatherSummary.isNotEmpty) parts.add(weatherSummary);
    if (rain24h != null) {
      parts.add('24h rain ${LocaleText.number(rain24h, fractionDigits: 1)} mm');
    }
    if (rain7d != null) {
      parts.add('7d rain ${LocaleText.number(rain7d, fractionDigits: 1)} mm');
    }
    if (waterNeed.isNotEmpty) parts.add(waterNeed);
    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }

  String get _stageQuestionText {
    return UiStrings.f('stage_question_for_crop', {
      'crop': widget.crop,
      'variety': widget.variety,
      'question': widget.stageQuestion,
    });
  }

  List<String> get _quickSuggestions => [
    UiStrings.f('quick_growth_normal_for_crop', {
      'crop': widget.crop,
      'variety': widget.variety,
    }),
    UiStrings.f('quick_irrigation_done_for_crop', {'crop': widget.crop}),
    UiStrings.f('quick_reinspection_for_crop', {'crop': widget.crop}),
    UiStrings.t('quick_unexpected_yellowing'),
  ];

  List<String> get _quickReplies {
    final fromStage = _stageQuickReplyKeys[widget.stage];
    final stageReplies = fromStage == null || fromStage.isEmpty
        ? _quickSuggestions
        : fromStage.map(UiStrings.t).toList(growable: false);
    return [
      ...stageReplies.take(3),
      UiStrings.f('quick_check_disease_spots', {
        'crop': widget.crop,
        'variety': widget.variety,
      }),
    ];
  }

  List<FarmChatMessageDraft> _transcript() {
    final now = DateTime.now().toUtc();
    return _messages
        .where((message) => message.text.trim().isNotEmpty)
        .map(
          (message) => FarmChatMessageDraft(
            role: message.isUser ? 'farmer' : 'assistant',
            source: 'status_chat',
            message: message.text.trim(),
            growthStage: widget.stage,
            daysAfterSowing: widget.daysAfterSowing,
            weatherSnapshot: widget.weatherSnapshot,
            farmContext: widget.farmContext,
            createdAt: now,
          ),
        )
        .toList(growable: false);
  }

  double? _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Widget _farmContextPanel() {
    final weatherText = _weatherContextText;
    final priorStatus = widget.priorStatus?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E9DD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: AppTheme.greenDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.label(widget.farmName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      UiStrings.label(widget.location),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusContextPill(
                icon: Icons.eco_rounded,
                label:
                    '${UiStrings.t('crop_label')}: $_cropName • ${UiStrings.t('variety')}: $_varietyName',
              ),
              _StatusContextPill(
                icon: Icons.timeline_rounded,
                label: UiStrings.f('day_stage', {
                  'day': LocaleText.number(widget.daysAfterSowing),
                  'stage': UiStrings.option(widget.stage),
                }),
              ),
              if (weatherText != null)
                _StatusContextPill(
                  icon: Icons.cloud_outlined,
                  label: weatherText,
                ),
              if (priorStatus.isNotEmpty)
                _StatusContextPill(
                  icon: Icons.history_rounded,
                  label: UiStrings.f('current_status_value', {
                    'value': priorStatus,
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageTile(BuildContext context, _StatusMessage item) {
    final maxWidth = MediaQuery.sizeOf(context).width < 520
        ? MediaQuery.sizeOf(context).width * 0.72
        : 430.0;
    return Row(
      mainAxisAlignment: item.isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!item.isUser) ...[
          const _StatusAvatar(
            icon: Icons.auto_awesome_rounded,
            color: AppTheme.greenDark,
            backgroundColor: AppTheme.greenPale,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: item.isUser ? AppTheme.greenDark : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(item.isUser ? 18 : 6),
                bottomRight: Radius.circular(item.isUser ? 6 : 18),
              ),
              border: Border.all(
                color: item.isUser
                    ? AppTheme.greenDark
                    : const Color(0xFFE3EAE1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: SelectableText(
              item.text,
              style: TextStyle(
                color: item.isUser ? Colors.white : AppTheme.textDark,
                height: 1.42,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
        if (item.isUser) ...[
          const SizedBox(width: 8),
          const _StatusAvatar(
            icon: Icons.person_rounded,
            color: Colors.white,
            backgroundColor: AppTheme.greenDark,
          ),
        ],
      ],
    );
  }

  Widget _quickReplyBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _quickReplies.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(
                Icons.bolt_rounded,
                size: 17,
                color: AppTheme.greenDark,
              ),
              label: Text(
                _quickReplies[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _applyQuickSuggestion(_quickReplies[index]),
              backgroundColor: const Color(0xFFF8FAF7),
              side: const BorderSide(color: Color(0xFFE1E9DD)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photoAttachment() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E9DD)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              _photoBytes!,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _photoName ?? UiStrings.t('attach_photo'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: _removePhoto,
            icon: const Icon(Icons.close_rounded),
            color: AppTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E9DF)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!keyboardVisible) ...[
            _quickReplyBar(),
            const SizedBox(height: 12),
          ],
          if (_photoBytes != null) ...[
            _photoAttachment(),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: UiStrings.t('attach_photo'),
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.greenPale,
                    foregroundColor: AppTheme.greenDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E9DF)),
                  ),
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: UiStrings.t('status_chat_hint'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filled(
                  tooltip: UiStrings.t('send'),
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitStatus,
              icon: const Icon(Icons.check_circle_rounded),
              label: Text(UiStrings.t('submit_status')),
            ),
          ),
        ],
      ),
    );
  }

  double _composerReservedSpace(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible) return _photoBytes == null ? 150 : 220;
    return _photoBytes == null ? 225 : 295;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(
          UiStrings.f('current_status_for_farm', {'farm': widget.farmName}),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView.separated(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  _composerReservedSpace(context),
                ),
                itemCount: _messages.length + 1,
                separatorBuilder: (_, index) =>
                    SizedBox(height: index == 0 ? 14 : 12),
                itemBuilder: (context, index) {
                  if (index == 0) return _farmContextPanel();
                  return _messageTile(context, _messages[index - 1]);
                },
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _composer(context)),
          ],
        ),
      ),
    );
  }
}

class _StatusMessage {
  final bool isUser;
  final String text;

  const _StatusMessage({required this.isUser, required this.text});
}

class _StatusContextPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusContextPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 64,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.greenDark),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const _StatusAvatar({
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }
}
