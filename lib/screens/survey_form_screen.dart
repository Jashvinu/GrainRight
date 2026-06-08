import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/icon_map.dart';
import '../config/theme.dart';
import '../config/translations.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/survey_launch.dart';
import '../services/location_service.dart';
import '../services/secure_app_storage.dart';
import '../widgets/dynamic_step.dart';

class SurveyFormScreen extends StatefulWidget {
  const SurveyFormScreen({super.key});

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen>
    with WidgetsBindingObserver {
  late final FormController c;
  late final LanguageController lang;
  final _secureStorage = SecureAppStorage();
  final _scrollController = ScrollController();
  List<GlobalKey> _chipKeys = [];
  int _previousStep = 0;
  bool _isForward = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = Get.put(FormController());
    lang = Get.find<LanguageController>();
    ever(c.currentStep, (step) {
      _isForward = step >= _previousStep;
      _previousStep = step;
      _scrollToActiveChip();
    });
    _loadData();
  }

  Future<void> _loadData() async {
    final launch = SurveyLaunchArgs.from(Get.arguments);
    final surveyId = launch.mode == SurveyLaunchMode.edit
        ? launch.surveyId
        : null;
    if (surveyId != null) c.prepareEdit(surveyId);
    if (launch.mode == SurveyLaunchMode.newSurvey) {
      await _clearStoredDraft();
    }
    await c.loadConfig();
    if (!c.isConfigLoaded.value) return;
    if (launch.mode == SurveyLaunchMode.newSurvey) {
      c.startFreshSurvey();
    }
    _chipKeys = List.generate(c.totalSteps, (_) => GlobalKey());
    if (surveyId != null) {
      await c.loadSurvey(surveyId);
    } else if (launch.mode == SurveyLaunchMode.resumeDraft) {
      final hasDraft = await c.hasDraft();
      if (hasDraft && mounted) {
        await c.loadDraft();
        Get.snackbar(
          _tr('Draft restored'),
          _tr('Your previous progress has been restored.'),
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save draft when app goes to background or is about to be killed
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      c.saveDraft();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Save draft one final time when leaving the screen
    c.saveDraft();
    _scrollController.dispose();
    Get.delete<FormController>();
    super.dispose();
  }

  void _scrollToActiveChip() {
    final step = _safeStep(_chipKeys.length);
    if (step == null) return;
    final key = _chipKeys[step];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  _ChipState _chipState(int i, int current, Set<int> visited) {
    if (i == current) return _ChipState.active;

    final filled = c.isStepFilled(i);
    if (filled) return _ChipState.visited;

    // Visited but no data filled = skipped
    if (visited.contains(i)) return _ChipState.skipped;

    // Not visited, but between filled/visited steps = skipped
    final maxVisited = visited.isEmpty
        ? 0
        : visited.reduce((a, b) => a > b ? a : b);
    if (i < maxVisited) return _ChipState.skipped;

    return _ChipState.upcoming;
  }

  String _tr(String text) {
    if (!lang.isMarathi) return text;
    return AppTranslations.translate(text);
  }

  Future<void> _switchToChat() async {
    await c.saveDraft();
    Get.offNamed('/form', arguments: _switchArguments());
  }

  Future<void> _clearStoredDraft() async {
    await c.clearDraft(suppressAutosave: true);
    await _secureStorage.remove('chat_form_cursor');
  }

  SurveyLaunchArgs _switchArguments() {
    return SurveyLaunchArgs.from(Get.arguments).forModeSwitch();
  }

  int? _safeStep(int totalSteps) {
    if (totalSteps <= 0) return null;
    final current = c.currentStep.value;
    final safe = current.clamp(0, totalSteps - 1).toInt();
    if (safe != current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.currentStep.value != safe) {
          c.currentStep.value = safe;
        }
      });
    }
    return safe;
  }

  void _goToStep(int step, int totalSteps) {
    if (totalSteps <= 0) return;
    c.currentStep.value = step.clamp(0, totalSteps - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Subscribe to language changes
      final _ = lang.language.value;

      if (c.hasError.value) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(_tr('Error')),
            actions: [_buildLanguageToggle(), _buildChatModeButton()],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.errorMessage.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_tr('Retry')),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (!c.isConfigLoaded.value) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(_tr('Loading...')),
            actions: [_buildLanguageToggle(), _buildChatModeButton()],
          ),
          body: const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          ),
        );
      }

      final totalSteps = c.totalSteps;
      if (totalSteps == 0) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(_tr('Error')),
            actions: [_buildLanguageToggle(), _buildChatModeButton()],
          ),
          body: Center(child: Text(_tr('No form configuration found.'))),
        );
      }

      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(c.isEditMode ? _tr('Edit Survey') : _tr('New Survey')),
          actions: [_buildLanguageToggle(), _buildChatModeButton()],
        ),
        body: Column(
          children: [
            // Step indicator bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Obx(() {
                final current = _safeStep(totalSteps) ?? 0;
                // Snapshot the visited set to ensure reactive rebuild
                final visited = c.visitedSteps.toSet();
                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: List.generate(totalSteps, (i) {
                      final state = _chipState(i, current, visited);
                      final section = c.sections[i];
                      final icon = resolveIcon(section.iconName);
                      final title = section.localizedTitle(context);
                      return GestureDetector(
                        key: i < _chipKeys.length ? _chipKeys[i] : null,
                        onTap: () => _goToStep(i, totalSteps),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: switch (state) {
                              _ChipState.active => AppTheme.green,
                              _ChipState.visited => AppTheme.greenPale,
                              _ChipState.skipped => const Color(0xFFFFF3CD),
                              _ChipState.upcoming => Colors.grey.shade100,
                            },
                            borderRadius: BorderRadius.circular(20),
                            border: state == _ChipState.skipped
                                ? Border.all(
                                    color: const Color(0xFFE2A613),
                                    width: 1.2,
                                  )
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: switch (state) {
                                  _ChipState.visited => const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: AppTheme.green,
                                    key: ValueKey('check'),
                                  ),
                                  _ChipState.skipped => const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Color(0xFFE2A613),
                                    key: ValueKey('warn'),
                                  ),
                                  _ => Icon(
                                    icon,
                                    size: 16,
                                    color: state == _ChipState.active
                                        ? Colors.white
                                        : AppTheme.textMuted,
                                    key: ValueKey('icon$i'),
                                  ),
                                },
                              ),
                              const SizedBox(width: 6),
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: state == _ChipState.active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: switch (state) {
                                    _ChipState.active => Colors.white,
                                    _ChipState.visited => AppTheme.green,
                                    _ChipState.skipped => const Color(
                                      0xFFB8860B,
                                    ),
                                    _ChipState.upcoming => AppTheme.textMuted,
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            // Location status pill
            Obx(() {
              final status = c.locationStatus.value;
              if (status == LocationStatus.idle) return const SizedBox.shrink();
              final isAcquired = status == LocationStatus.acquired;
              final isError =
                  status == LocationStatus.denied ||
                  status == LocationStatus.unavailable;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: isAcquired
                    ? AppTheme.greenPale
                    : isError
                    ? const Color(0xFFFFF3CD)
                    : Colors.grey.shade50,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == LocationStatus.fetching)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.green,
                        ),
                      )
                    else
                      Icon(
                        isAcquired
                            ? Icons.location_on_rounded
                            : Icons.location_off_rounded,
                        size: 14,
                        color: isAcquired
                            ? AppTheme.green
                            : const Color(0xFFB8860B),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _tr(c.locationSummary),
                        style: TextStyle(
                          fontSize: 11,
                          color: isAcquired
                              ? AppTheme.greenDark
                              : isError
                              ? const Color(0xFF856404)
                              : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
            // Form content
            Expanded(
              child: Form(
                key: c.formKey,
                child: Obx(() {
                  final step = _safeStep(totalSteps) ?? 0;
                  final section = c.sections[step];
                  final icon = resolveIcon(section.iconName);
                  final forward = _isForward;
                  final sectionTitle = section.localizedTitle(context);

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offsetIn = forward
                          ? const Offset(1.0, 0.0)
                          : const Offset(-1.0, 0.0);
                      final offsetOut = forward
                          ? const Offset(-1.0, 0.0)
                          : const Offset(1.0, 0.0);
                      // Determine if this is the incoming or outgoing child
                      final isIncoming = (child.key as ValueKey).value == step;
                      final tween = Tween<Offset>(
                        begin: isIncoming ? offsetIn : offsetOut,
                        end: Offset.zero,
                      );
                      return SlideTransition(
                        position: tween.animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [...previousChildren, ?currentChild],
                      );
                    },
                    child: SingleChildScrollView(
                      key: ValueKey(step),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.greenPale,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  icon,
                                  color: AppTheme.green,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_tr('Step')} ${step + 1} ${_tr('of')} $totalSteps',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      sectionTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.greenDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: (step + 1) / totalSteps,
                            ),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: value,
                                backgroundColor: AppTheme.greenPale,
                                color: AppTheme.green,
                                minHeight: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          DynamicStep(section: section),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Bottom nav bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Obx(() {
                final step = _safeStep(totalSteps) ?? 0;
                final isFirst = step == 0;
                final isLast = step == totalSteps - 1;
                return SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      if (!isFirst)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _goToStep(step - 1, totalSteps),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                            ),
                            label: Text(_tr('Back')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.green,
                              side: const BorderSide(color: AppTheme.green),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      if (!isFirst) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: c.isSubmitting.value
                              ? null
                              : () {
                                  if (isLast) {
                                    c.submit();
                                  } else {
                                    _goToStep(step + 1, totalSteps);
                                  }
                                },
                          icon: isLast
                              ? (c.isSubmitting.value
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded, size: 18))
                              : const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            isLast
                                ? (c.isSubmitting.value
                                      ? _tr('Submitting...')
                                      : _tr('Submit'))
                                : _tr('Continue'),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildLanguageToggle() {
    return Obx(() {
      final isMr = lang.isMarathi;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: lang.toggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.translate_rounded,
                  size: 16,
                  color: AppTheme.green,
                ),
                const SizedBox(width: 4),
                Text(
                  isMr ? 'EN' : 'मर',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.greenDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildChatModeButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: 'Use chat form',
        onPressed: _switchToChat,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
      ),
    );
  }
}

enum _ChipState { active, visited, skipped, upcoming }
