import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/locale_text.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../services/policy_disclosure_service.dart';
import '../utils/harvest_machine_capture.dart';
import '../widgets/app_back_button.dart';

class FarmStatusUpdateResult {
  final String message;
  final String question;
  final String stage;
  final DateTime updatedAt;
  final Uint8List? photoBytes;
  final String? photoName;

  const FarmStatusUpdateResult({
    required this.message,
    required this.question,
    required this.stage,
    required this.updatedAt,
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
    _messages
      ..add(_StatusMessage(isUser: false, text: _farmContextText))
      ..add(_StatusMessage(isUser: false, text: _stageQuestionText));

    if (widget.lifecycleContext != null &&
        widget.lifecycleContext!.trim().isNotEmpty) {
      _messages.add(
        _StatusMessage(isUser: false, text: widget.lifecycleContext!.trim()),
      );
    }

    if (widget.priorStatus != null && widget.priorStatus!.trim().isNotEmpty) {
      _messages.add(
        _StatusMessage(
          isUser: false,
          text: UiStrings.f('current_status_value', {
            'value': widget.priorStatus,
          }),
        ),
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
    final canUsePhoto = await PolicyDisclosureService.confirmPhotoUse(context);
    if (!canUsePhoto) return;

    final result = await pickHarvestMachineImage();
    if (result == null) return;
    if (!mounted) return;

    setState(() {
      _photoBytes = result.bytes;
      _photoName = result.name;
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
        photoBytes: _photoBytes,
        photoName: _photoName,
      ),
    );
  }

  String get _cropName => UiStrings.option(widget.crop);

  String get _varietyName => UiStrings.option(widget.variety);

  String get _farmContextText {
    return '${UiStrings.t('selected_farm')}: ${widget.farmName}\n'
        '${UiStrings.t('crop_label')}: $_cropName • ${UiStrings.t('variety')}: $_varietyName\n'
        '${UiStrings.t('location')}: ${UiStrings.label(widget.location)}\n'
        '${UiStrings.t('growth')}: ${UiStrings.f('day_stage', {'day': LocaleText.number(widget.daysAfterSowing), 'stage': UiStrings.option(widget.stage)})}';
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
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                itemCount: _messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _messages[index];
                  return Align(
                    alignment: item.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: item.isUser ? AppTheme.greenPale : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: item.isUser
                              ? const Color(0xFFB7D6BE)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Text(
                        item.text,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_photoBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.memory(_photoBytes!, fit: BoxFit.cover),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _quickReplies)
                    ActionChip(
                      label: Text(item),
                      onPressed: () => _applyQuickSuggestion(item),
                    ),
                ],
              ),
            ),
            if (_photoName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _photoName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: UiStrings.t('status_chat_hint'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: UiStrings.t('attach_photo'),
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                  IconButton(
                    tooltip: UiStrings.t('send'),
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitStatus,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(UiStrings.t('submit_status')),
                ),
              ),
            ),
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
