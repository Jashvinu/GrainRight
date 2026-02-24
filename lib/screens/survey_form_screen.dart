import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/icon_map.dart';
import '../config/theme.dart';
import '../controllers/form_controller.dart';
import '../widgets/dynamic_step.dart';

class SurveyFormScreen extends StatefulWidget {
  const SurveyFormScreen({super.key});

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  late final FormController c;
  final _scrollController = ScrollController();
  List<GlobalKey> _chipKeys = [];
  int _previousStep = 0;
  bool _isForward = true;

  @override
  void initState() {
    super.initState();
    c = Get.put(FormController());
    _init();
  }

  Future<void> _init() async {
    await c.loadConfig();
    _chipKeys = List.generate(c.totalSteps, (_) => GlobalKey());
    final surveyId = Get.arguments as String?;
    if (surveyId != null) {
      await c.loadSurvey(surveyId);
    }
    if (mounted) setState(() {});
    ever(c.currentStep, (step) {
      _isForward = step >= _previousStep;
      _previousStep = step;
      _scrollToActiveChip();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    Get.delete<FormController>();
    super.dispose();
  }

  void _scrollToActiveChip() {
    if (c.currentStep.value >= _chipKeys.length) return;
    final key = _chipKeys[c.currentStep.value];
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
    final maxVisited =
        visited.isEmpty ? 0 : visited.reduce((a, b) => a > b ? a : b);
    if (i < maxVisited) return _ChipState.skipped;

    return _ChipState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!c.isConfigLoaded.value) {
        return Scaffold(
          appBar: AppBar(title: const Text('Loading...')),
          body: const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          ),
        );
      }

      final totalSteps = c.totalSteps;
      if (totalSteps == 0) {
        return Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: const Center(child: Text('No form configuration found.')),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(c.isEditMode ? 'Edit Survey' : 'New Survey'),
        ),
        body: Column(
          children: [
            // Step indicator bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Obx(() {
                final current = c.currentStep.value;
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
                      return GestureDetector(
                        key: i < _chipKeys.length ? _chipKeys[i] : null,
                        onTap: () => c.currentStep.value = i,
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
                                    color: const Color(0xFFE2A613), width: 1.2)
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
                                section.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: state == _ChipState.active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: switch (state) {
                                    _ChipState.active => Colors.white,
                                    _ChipState.visited => AppTheme.green,
                                    _ChipState.skipped =>
                                      const Color(0xFFB8860B),
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
            // Form content
            Expanded(
              child: Form(
                key: c.formKey,
                child: Obx(() {
                  final step = c.currentStep.value;
                  final section = c.sections[step];
                  final icon = resolveIcon(section.iconName);
                  final forward = _isForward;

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
                      final isIncoming =
                          (child.key as ValueKey).value == step;
                      final tween = Tween<Offset>(
                        begin: isIncoming ? offsetIn : offsetOut,
                        end: Offset.zero,
                      );
                      return SlideTransition(
                        position: tween.animate(animation),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
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
                                child:
                                    Icon(icon, color: AppTheme.green, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Step ${step + 1} of $totalSteps',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    section.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.greenDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            tween:
                                Tween(begin: 0, end: (step + 1) / totalSteps),
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
                final isFirst = c.currentStep.value == 0;
                final isLast = c.currentStep.value == totalSteps - 1;
                return SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      if (!isFirst)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => c.currentStep.value--,
                            icon: const Icon(Icons.arrow_back_rounded,
                                size: 18),
                            label: const Text('Back'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.green,
                              side: const BorderSide(color: AppTheme.green),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
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
                                    c.currentStep.value++;
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
                              : const Icon(Icons.arrow_forward_rounded,
                                  size: 18),
                          label: Text(isLast
                              ? (c.isSubmitting.value
                                  ? 'Submitting...'
                                  : 'Submit')
                              : 'Continue'),
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
}

enum _ChipState { active, visited, skipped, upcoming }
