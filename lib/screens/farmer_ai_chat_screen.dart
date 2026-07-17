import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/auth_controller.dart';
import '../controllers/farm_controller.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/satellite/farm_assistant_model.dart';
import '../models/satellite/farm_alert_model.dart';
import '../models/satellite/farm_model.dart';
import '../services/satellite_service.dart';
import '../utils/harvest_machine_capture.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class FarmerAiChatScreen extends StatefulWidget {
  final String? farmId;
  final String? farmName;
  final String? crop;
  final String? variety;
  final String? location;
  final String? farmerPhone;
  final String? farmerId;
  final String? growthStage;
  final int? daysAfterSowing;
  final double bottomContentInset;

  const FarmerAiChatScreen({
    super.key,
    this.farmId,
    this.farmName,
    this.crop,
    this.variety,
    this.location,
    this.farmerPhone,
    this.farmerId,
    this.growthStage,
    this.daysAfterSowing,
    this.bottomContentInset = 12,
  });

  @override
  State<FarmerAiChatScreen> createState() => _FarmerAiChatScreenState();
}

class _FarmerAiChatScreenState extends State<FarmerAiChatScreen> {
  static const _quickPromptKeys = [
    'ai_chat_prompt_photo',
    'ai_chat_prompt_disease',
    'ai_chat_prompt_water',
    'ai_chat_prompt_next_action',
    'ai_chat_prompt_yield',
  ];

  final _service = SatelliteService();
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messages.addAll([
      _ChatMessage(
        isUser: false,
        key: 'ai_chat_welcome',
      ),
    ]);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isSending) return;
    setState(() {
      _isSending = true;
      _messages.add(_ChatMessage(isUser: true, text: prompt));
      _messages.add(const _ChatMessage(isUser: false, key: 'ai_chat_thinking'));
      _promptController.clear();
    });
    _scrollToBottom();

    try {
      final answer = await _askAssistant(prompt);
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: _formatAnswer(answer),
        );
      });
    } on _MissingFarmContextException {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = const _ChatMessage(
          isUser: false,
          key: 'ai_chat_sync_required',
          isError: true,
        );
      });
    } on SatelliteApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: _apiErrorText(error),
          isError: true,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = const _ChatMessage(
          isUser: false,
          key: 'ai_chat_retry',
          isError: true,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _startDiseasePhotoFlow() async {
    if (_isSending) return;
    final source = await _chooseImageSource();
    if (source == null) return;

    setState(() {
      _isSending = true;
      _messages.add(const _ChatMessage(isUser: true, key: 'ai_chat_photo_user'));
      _messages.add(
        const _ChatMessage(isUser: false, key: 'ai_chat_photo_thinking'),
      );
    });
    _scrollToBottom();

    try {
      final diagnosis = await _captureAndDiagnoseDiseasePhoto(source);
      if (diagnosis == null) {
        if (!mounted) return;
        setState(() {
          _messages[_messages.length - 1] = const _ChatMessage(
            isUser: false,
            key: 'ai_chat_photo_cancelled',
            isError: true,
          );
        });
        return;
      }

      FarmAssistantAnswer? farmAdvice;
      try {
        farmAdvice = await _askAssistant(_photoFollowUpPrompt(diagnosis));
      } catch (_) {
        farmAdvice = null;
      }

      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: _formatPhotoAnswer(diagnosis, farmAdvice),
        );
      });
    } on _MissingFarmContextException {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = const _ChatMessage(
          isUser: false,
          key: 'ai_chat_sync_required',
          isError: true,
        );
      });
    } on SatelliteApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: error.statusCode == 401 || error.statusCode == 403
              ? UiStrings.t('ai_chat_login_required')
              : _apiErrorText(error),
          isError: true,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = const _ChatMessage(
          isUser: false,
          key: 'image_capture_retry',
          isError: true,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  Future<HarvestMachineImageSource?> _chooseImageSource() {
    return showModalBottomSheet<HarvestMachineImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text(UiStrings.t('open_camera')),
                subtitle: Text(UiStrings.t('ai_chat_photo_camera_subtitle')),
                onTap: () => Navigator.pop(
                  context,
                  HarvestMachineImageSource.camera,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(UiStrings.t('select_from_gallery')),
                subtitle: Text(UiStrings.t('ai_chat_photo_gallery_subtitle')),
                onTap: () => Navigator.pop(
                  context,
                  HarvestMachineImageSource.gallery,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<FarmPhotoDiagnosis?> _captureAndDiagnoseDiseasePhoto(
    HarvestMachineImageSource source,
  ) async {
    await _ensureFarmContext();
    final farmId = _effectiveFarmId;
    final jwt = _jwt;
    if (farmId == null || _effectiveFarmerPhone == null || jwt.trim().isEmpty) {
      throw const _MissingFarmContextException();
    }

    final shot = await pickHarvestMachineImage(source: source);
    if (shot == null) return null;
    final path = await _service.uploadDiseasePhoto(
      bytes: shot.bytes,
      farmId: farmId,
      jwt: jwt,
    );
    return _service.diagnoseDiseasePhoto(
      jwt: jwt,
      body: {
        'farm_id': farmId,
        'storage_path': path,
        'crop': _effectiveCrop ?? 'millet',
        'growth_stage': _effectiveGrowthStage ?? 'unknown',
        'language': _language,
        'disease_spotted': UiStrings.t('ai_chat_photo_user'),
        'description': UiStrings.f('ai_chat_photo_upload_description', {
          'farm': _effectiveFarmName ?? UiStrings.t('ai_chat_active_farm'),
        }),
        'satellite_context': {
          'source': 'ai_farm_assistant_chat',
          'farm_name': _effectiveFarmName,
          'crop': _effectiveCrop,
          'variety': _effectiveVariety,
          'location': _effectiveLocation,
          'growth_stage': _effectiveGrowthStage,
          'days_after_sowing': widget.daysAfterSowing,
          'farmer_phone_present': _effectiveFarmerPhone != null,
        },
      },
    );
  }

  Future<FarmAssistantAnswer> _askAssistant(String prompt) {
    return _askAssistantRemote(prompt);
  }

  Future<FarmAssistantAnswer> _askAssistantRemote(String prompt) async {
    await _ensureFarmContext();
    final farmId = _effectiveFarmId;
    final phone = _effectiveFarmerPhone;
    final jwt = _jwt;
    if (farmId == null || phone == null || jwt.trim().isEmpty) {
      throw const _MissingFarmContextException();
    }

    return _service.askFarmAssistant(
      farmId: farmId,
      farmerPhone: phone,
      farmerId: _effectiveFarmerId,
      question: prompt,
      jwt: jwt,
      language: _language,
      farmName: _effectiveFarmName,
      crop: _effectiveCrop,
      variety: _effectiveVariety,
      location: _effectiveLocation,
      growthStage: _effectiveGrowthStage,
      daysAfterSowing: widget.daysAfterSowing,
    );
  }

  Future<void> _ensureFarmContext() async {
    if (_effectiveFarmId != null &&
        _effectiveFarmerPhone != null &&
        _jwt.trim().isNotEmpty) {
      return;
    }
    if (!Get.isRegistered<FarmController>()) return;
    final farmCtrl = Get.find<FarmController>();
    if (farmCtrl.isLoading.value) return;
    await farmCtrl.loadFarms(forceRefresh: true);
  }

  Farm? get _controllerFarm {
    if (!Get.isRegistered<FarmController>()) return null;
    return Get.find<FarmController>().selectedFarm.value;
  }

  String? get _effectiveFarmId =>
      _clean(widget.farmId) ?? _clean(_controllerFarm?.id);

  String? get _effectiveFarmName =>
      _clean(widget.farmName) ?? _clean(_controllerFarm?.name);

  String? get _effectiveCrop =>
      _clean(widget.crop) ?? _clean(_controllerFarm?.crop);

  String? get _effectiveVariety =>
      _clean(widget.variety) ?? _clean(_controllerFarm?.variety);

  String? get _effectiveLocation => _clean(widget.location);

  String? get _effectiveGrowthStage =>
      _clean(widget.growthStage) ?? _clean(_controllerFarm?.currentStatusStage);

  String? get _effectiveFarmerPhone {
    final widgetPhone = _phoneDigits(widget.farmerPhone);
    if (widgetPhone != null) return widgetPhone;
    if (!Get.isRegistered<MainAuthController>()) return null;
    return _phoneDigits(
      Get.find<MainAuthController>().verifiedFarmer.value?.phone,
    );
  }

  String? get _effectiveFarmerId {
    final widgetFarmerId = _clean(widget.farmerId);
    if (widgetFarmerId != null) return widgetFarmerId;
    if (!Get.isRegistered<MainAuthController>()) return null;
    return _clean(Get.find<MainAuthController>().verifiedFarmer.value?.farmerId);
  }

  String get _jwt {
    if (!Get.isRegistered<AuthController>()) return '';
    return Get.find<AuthController>().accessToken.value;
  }

  String get _language {
    if (!Get.isRegistered<LanguageController>()) return 'en';
    final value = Get.find<LanguageController>().language.value;
    return {'en', 'hi', 'mr'}.contains(value) ? value : 'en';
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _phoneDigits(String? value) {
    final digits = value?.replaceAll(RegExp(r'\D'), '');
    return digits == null || digits.length < 10
        ? null
        : digits.substring(digits.length - 10);
  }

  String _welcomeText() {
    final parts = [
      if (_effectiveFarmName != null) UiStrings.label(_effectiveFarmName!),
      if (_effectiveCrop != null)
        '${UiStrings.option(_effectiveCrop!)}${_effectiveVariety != null ? ' • ${UiStrings.option(_effectiveVariety!)}' : ''}',
    ];
    final subject = parts.isEmpty
        ? UiStrings.t('ai_chat_active_farm')
        : parts.join(' • ');

    return UiStrings.f('ai_chat_welcome', {'subject': subject});
  }

  String _formatAnswer(FarmAssistantAnswer answer) {
    final lines = <String>[];
    if (answer.answer.trim().isNotEmpty) {
      lines.add(answer.answer.trim());
    }
    if (answer.actions.isNotEmpty) {
      lines.add(
        '${UiStrings.t('ai_chat_next_steps')}\n${answer.actions.map((item) => '- $item').join('\n')}',
      );
    }
    if (answer.warnings.isNotEmpty) {
      lines.add(
        '${UiStrings.t('ai_chat_cautions')}\n${answer.warnings.map((item) => '- $item').join('\n')}',
      );
    }
    return lines.isEmpty ? UiStrings.t('ai_chat_retry') : lines.join('\n\n');
  }

  String _apiErrorText(SatelliteApiException error) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return UiStrings.t('ai_chat_login_required');
    }
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (error.statusCode == 404 ||
        lower.contains('function') && lower.contains('not found')) {
      return UiStrings.t('ai_chat_service_not_ready');
    }
    if (lower.contains('farm not found') ||
        lower.contains('farm_id') ||
        lower.contains('farmer')) {
      return UiStrings.t('ai_chat_sync_required');
    }
    return UiStrings.f('ai_chat_service_error', {
      'error': message.isEmpty ? UiStrings.t('ai_chat_retry') : message,
    });
  }

  String _formatPhotoAnswer(
    FarmPhotoDiagnosis diagnosis,
    FarmAssistantAnswer? farmAdvice,
  ) {
    final confidence = '${(diagnosis.confidence * 100).round()}%';
    final lines = <String>[
      UiStrings.t('ai_chat_photo_result'),
      '${UiStrings.t('ai_chat_visual_findings')}: ${diagnosis.diagnosis}',
      '${UiStrings.t('ai_chat_confidence')}: $confidence • ${UiStrings.t('ai_chat_severity')}: ${UiStrings.option(diagnosis.severity)}',
    ];
    if (diagnosis.evidence.isNotEmpty) {
      lines.add(
        '${UiStrings.t('ai_chat_evidence')}\n${diagnosis.evidence.map((item) => '- $item').join('\n')}',
      );
    }
    if (diagnosis.differential.isNotEmpty) {
      lines.add(
        '${UiStrings.t('ai_chat_possible_causes')}\n${diagnosis.differential.map((item) => '- $item').join('\n')}',
      );
    }
    if (diagnosis.scoutAction.trim().isNotEmpty) {
      lines.add(
        '${UiStrings.t('ai_chat_scout_action')}\n${diagnosis.scoutAction.trim()}',
      );
    }
    if (farmAdvice != null) {
      final advice = _formatAnswer(farmAdvice).trim();
      if (advice.isNotEmpty) {
        lines.add('${UiStrings.t('ai_chat_farm_advice')}\n$advice');
      }
    }
    return lines.join('\n\n');
  }

  String _photoFollowUpPrompt(FarmPhotoDiagnosis diagnosis) {
    return [
      UiStrings.t('ai_chat_photo_followup_question'),
      '${UiStrings.t('ai_chat_visual_findings')}: ${diagnosis.diagnosis}',
      '${UiStrings.t('ai_chat_severity')}: ${UiStrings.option(diagnosis.severity)}',
      '${UiStrings.t('ai_chat_confidence')}: ${(diagnosis.confidence * 100).round()}%',
      if (diagnosis.evidence.isNotEmpty)
        '${UiStrings.t('ai_chat_evidence')}: ${diagnosis.evidence.join('; ')}',
      if (diagnosis.differential.isNotEmpty)
        '${UiStrings.t('ai_chat_possible_causes')}: ${diagnosis.differential.join(', ')}',
      if (diagnosis.scoutAction.trim().isNotEmpty)
        '${UiStrings.t('ai_chat_scout_action')}: ${diagnosis.scoutAction.trim()}',
    ].join('\n');
  }

  String _messageText(_ChatMessage item) {
    if (item.key == 'ai_chat_welcome') {
      return _welcomeText();
    }
    if (item.key != null) return UiStrings.t(item.key!);
    return item.text;
  }

  void _sendQuickPrompt(String key) {
    if (_isSending) return;
    final value = UiStrings.t(key);
    _promptController.text = value;
    _promptController.selection = TextSelection.collapsed(offset: value.length);
    _sendPrompt();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _quickPromptBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final spacing = columns == 3 ? 8.0 : 7.0;
        final chipWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: [
            for (final key in _quickPromptKeys)
              SizedBox(
                width: chipWidth,
                child: _QuickPromptChip(
                  icon: _quickPromptIcon(key),
                  label: UiStrings.t(key),
                  onPressed: _isSending
                      ? null
                      : key == 'ai_chat_prompt_photo'
                      ? () {
                          _startDiseasePhotoFlow();
                        }
                      : () => _sendQuickPrompt(key),
                ),
              ),
          ],
        );
      },
    );
  }

  IconData _quickPromptIcon(String key) {
    return switch (key) {
      'ai_chat_prompt_photo' => Icons.add_a_photo_rounded,
      'ai_chat_prompt_disease' => Icons.health_and_safety_rounded,
      'ai_chat_prompt_water' => Icons.water_drop_rounded,
      'ai_chat_prompt_next_action' => Icons.task_alt_rounded,
      'ai_chat_prompt_yield' => Icons.trending_up_rounded,
      _ => Icons.auto_awesome_rounded,
    };
  }

  Widget _farmContextPanel() {
    final farmName = _effectiveFarmName ?? UiStrings.t('ai_chat_active_farm');
    final crop = _effectiveCrop;
    final variety = _effectiveVariety;
    final stage = _effectiveGrowthStage;
    final days = widget.daysAfterSowing;
    final subtitle = [
      if (crop != null) UiStrings.option(crop),
      if (variety != null) UiStrings.option(variety),
      if (stage != null) UiStrings.option(stage),
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
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
                      UiStrings.label(farmName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty || days != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (subtitle.isNotEmpty)
                  _ContextPill(
                    icon: Icons.eco_rounded,
                    label: subtitle,
                  ),
                if (days != null)
                  _ContextPill(
                    icon: Icons.today_rounded,
                    label: UiStrings.f('days_after_sowing_value', {
                      'days': days,
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _messageBody(_ChatMessage item) {
    final text = SelectableText(
      _messageText(item),
      style: TextStyle(
        color: item.isUser
            ? Colors.white
            : item.isError
            ? const Color(0xFF7F1D1D)
            : AppTheme.textDark,
        height: 1.42,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
      ),
    );
    if (item.key != 'ai_chat_thinking' &&
        item.key != 'ai_chat_photo_thinking') {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Flexible(child: text),
      ],
    );
  }

  Widget _messageTile(BuildContext context, _ChatMessage item) {
    final isUser = item.isUser;
    final bubbleColor = isUser
        ? AppTheme.greenDark
        : item.isError
        ? const Color(0xFFFFF1F2)
        : Colors.white;
    final borderColor = isUser
        ? AppTheme.greenDark
        : item.isError
        ? const Color(0xFFFECACA)
        : const Color(0xFFE3EAE1);
    final foregroundColor = isUser
        ? Colors.white
        : item.isError
        ? const Color(0xFF7F1D1D)
        : AppTheme.greenDark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth < 520
            ? constraints.maxWidth * 0.84
            : 430.0;
        return Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              _MessageAvatar(
                icon: item.isError
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome_rounded,
                color: foregroundColor,
                backgroundColor:
                    item.isError ? const Color(0xFFFFE4E6) : AppTheme.greenPale,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 6),
                    bottomRight: Radius.circular(isUser ? 6 : 18),
                  ),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: isUser ? Colors.white : AppTheme.textDark,
                  ),
                  child: _messageBody(item),
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 8),
              const _MessageAvatar(
                icon: Icons.person_rounded,
                color: Colors.white,
                backgroundColor: AppTheme.greenDark,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _composer() {
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, widget.bottomContentInset),
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
          _quickPromptBar(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tooltip(
                message: UiStrings.t('ai_chat_prompt_photo'),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: _isSending
                        ? null
                        : () {
                            _startDiseasePhotoFlow();
                          },
                    icon: const Icon(Icons.add_a_photo_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.greenPale,
                      foregroundColor: AppTheme.greenDark,
                      disabledBackgroundColor: const Color(0xFFF1F5EF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
                    controller: _promptController,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendPrompt(),
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: UiStrings.t('ask_about_farm'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      hintStyle: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
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
                  onPressed: _isSending ? null : () => _sendPrompt(),
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    disabledBackgroundColor: AppTheme.green.withValues(
                      alpha: 0.55,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _composerReservedSpace(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 390) return 244;
    if (width < 560) return 232;
    return 190;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('ai_chat_title')),
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
                  _composerReservedSpace(context) + widget.bottomContentInset,
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _composer(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final String? key;
  final bool isError;

  const _ChatMessage({
    required this.isUser,
    this.text = '',
    this.key,
    this.isError = false,
  });
}

class _QuickPromptChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _QuickPromptChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.greenDark),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xFFF4F7F4),
      disabledColor: const Color(0xFFF1F5EF),
      side: const BorderSide(color: Color(0xFFE0E7E2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(
        color: AppTheme.textDark,
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContextPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E9DD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.greenDark),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const _MessageAvatar({
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }
}

class _MissingFarmContextException implements Exception {
  const _MissingFarmContextException();
}
