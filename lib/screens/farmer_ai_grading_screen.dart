import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/grading_strings.dart';
import '../config/theme.dart';
import '../models/grading/crop_option.dart';
import '../models/grading/grade_result.dart';
import '../services/grain_grading_service.dart';
import '../utils/harvest_machine_capture.dart';

/// Real AI grain-grading flow wired to the vendored FastAPI service.
/// One decision per screen (crop → grain photo → moisture → result), tuned for
/// low-literacy, Marathi/Hindi-first use. See docs/11_grain_grading_integration.md.
class FarmerAiGradingScreen extends StatefulWidget {
  const FarmerAiGradingScreen({super.key});

  @override
  State<FarmerAiGradingScreen> createState() => _FarmerAiGradingScreenState();
}

enum _Step { crop, grain, moisture, result }

class _FarmerAiGradingScreenState extends State<FarmerAiGradingScreen> {
  final GrainGradingService _service = GrainGradingService();
  final TextEditingController _manualMoistureCtrl = TextEditingController();

  _Step _step = _Step.crop;
  bool _loadingCrops = true;
  bool _grading = false;
  bool _notConfigured = false;

  List<CropOption> _crops = const [];
  CropOption? _crop;
  CropVariety? _variety;

  Uint8List? _grainBytes;
  String _grainName = 'grain.jpg';
  Uint8List? _moistureBytes;
  String _moistureName = 'moisture.jpg';

  GradeResult? _result;

  Map<String, String> get _farmArgs {
    final args = Get.arguments;
    if (args is Map) {
      return {
        'farmName': '${args['farmName'] ?? 'Rajur Millet Plot'}',
        'crop': '${args['crop'] ?? 'Finger Millet'}',
        'village': '${args['village'] ?? 'Rajur'}',
      };
    }
    return const {
      'farmName': 'Rajur Millet Plot',
      'crop': 'Finger Millet',
      'village': 'Rajur',
    };
  }

  @override
  void initState() {
    super.initState();
    _loadCrops();
  }

  @override
  void dispose() {
    _manualMoistureCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadCrops() async {
    setState(() {
      _loadingCrops = true;
      _notConfigured = false;
    });
    if (!_service.isConfigured) {
      setState(() {
        _loadingCrops = false;
        _notConfigured = true;
      });
      return;
    }
    try {
      final crops = await _service.fetchCrops();
      setState(() {
        _crops = crops.isEmpty ? _fallbackCrops : crops;
        _crop = _crops.first;
        _variety = _crop!.varieties.isNotEmpty ? _crop!.varieties.first : null;
        _loadingCrops = false;
      });
    } on GradingException catch (_) {
      // Catalog is non-critical: fall back to a built-in crop so grading still
      // works even when the catalog endpoint is unreachable.
      setState(() {
        _crops = _fallbackCrops;
        _crop = _crops.first;
        _variety = _crop!.varieties.isNotEmpty ? _crop!.varieties.first : null;
        _loadingCrops = false;
      });
    }
  }

  static const List<CropOption> _fallbackCrops = [
    CropOption(
      value: 'finger_millets',
      label: 'Finger Millet (Ragi)',
      varieties: [CropVariety(value: 'local', label: 'Local')],
    ),
  ];

  Future<void> _pick({
    required bool grain,
    required HarvestMachineImageSource source,
  }) async {
    final result = await pickHarvestMachineImage(source: source);
    if (result == null) return;
    setState(() {
      if (grain) {
        _grainBytes = result.bytes;
        _grainName = result.name;
      } else {
        _moistureBytes = result.bytes;
        _moistureName = result.name;
      }
    });
  }

  Future<void> _analyze() async {
    final crop = _crop;
    final grain = _grainBytes;
    if (crop == null || grain == null) return;
    final manual = double.tryParse(_manualMoistureCtrl.text.trim());
    if (_moistureBytes == null && manual == null) {
      Get.snackbar(
        GradingStrings.t('step_moisture'),
        GradingStrings.t('moisture_hint'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() {
      _grading = true;
      _step = _Step.result;
      _result = null;
    });
    try {
      final result = await _service.analyze(
        grainImageBytes: grain,
        grainImageName: _grainName,
        moistureImageBytes: _moistureBytes,
        moistureImageName: _moistureName,
        manualMoisturePercent: _moistureBytes == null ? manual : null,
        cropType: crop.value,
        cropVariety: _variety?.value ?? '',
      );
      setState(() {
        _result = result;
        _grading = false;
      });
    } on GradingException catch (e) {
      setState(() => _grading = false);
      Get.snackbar(
        GradingStrings.t('error_generic'),
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
      setState(() => _step = _Step.moisture);
    }
  }

  void _goToHarvestQr() {
    final result = _result;
    if (result == null) return;
    final farm = _farmArgs;
    final moisture = result.moisturePercent;
    Get.toNamed('/farmer/harvest-qr', arguments: {
      ...farm,
      'crop': _crop?.label ?? farm['crop'],
      'variety': _variety?.label ?? 'Local',
      'grade': result.grade,
      'score': result.confidenceOverall?.round().toString() ?? '--',
      'moisture': moisture != null ? '${moisture.toStringAsFixed(1)}%' : '--',
      'moistureSource': result.moistureSource.isEmpty ? '--' : result.moistureSource,
      'grader': 'AI grading',
      'batchId': _batchId(),
    });
  }

  String _batchId() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'KF-HV-$date-${now.millisecondsSinceEpoch % 10000}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text(GradingStrings.t('title'))),
      body: SafeArea(
        child: _notConfigured
            ? _NotConfiguredState(onRetry: _loadCrops)
            : Column(
                children: [
                  _StepBar(current: _step),
                  Expanded(child: _buildStep()),
                ],
              ),
      ),
    );
  }

  Widget _buildStep() {
    if (_loadingCrops) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_step) {
      case _Step.crop:
        return _CropStep(
          crops: _crops,
          selectedCrop: _crop,
          selectedVariety: _variety,
          onCrop: (c) => setState(() {
            _crop = c;
            _variety = c.varieties.isNotEmpty ? c.varieties.first : null;
          }),
          onVariety: (v) => setState(() => _variety = v),
          onNext: () => setState(() => _step = _Step.grain),
        );
      case _Step.grain:
        return _PhotoStep(
          key: const ValueKey('grain'),
          title: GradingStrings.t('take_grain_photo'),
          hint: GradingStrings.t('grain_hint'),
          icon: Icons.grain_rounded,
          bytes: _grainBytes,
          onCamera: () => _pick(grain: true, source: HarvestMachineImageSource.camera),
          onGallery: () => _pick(grain: true, source: HarvestMachineImageSource.gallery),
          onBack: () => setState(() => _step = _Step.crop),
          onNext: _grainBytes == null
              ? null
              : () => setState(() => _step = _Step.moisture),
        );
      case _Step.moisture:
        return _MoistureStep(
          bytes: _moistureBytes,
          manualController: _manualMoistureCtrl,
          onCamera: () => _pick(grain: false, source: HarvestMachineImageSource.camera),
          onGallery: () => _pick(grain: false, source: HarvestMachineImageSource.gallery),
          onBack: () => setState(() => _step = _Step.grain),
          onAnalyze: _analyze,
          onManualChanged: (_) => setState(() {}),
        );
      case _Step.result:
        if (_grading) return const _GradingProgress();
        final result = _result;
        if (result == null) return const _GradingProgress();
        return _ResultStep(
          result: result,
          onFeedback: () => _openFeedback(result),
          onHarvestQr: _goToHarvestQr,
          onAgain: () => setState(() {
            _step = _Step.crop;
            _grainBytes = null;
            _moistureBytes = null;
            _manualMoistureCtrl.clear();
            _result = null;
          }),
        );
    }
  }

  Future<void> _openFeedback(GradeResult result) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedbackSheet(current: result.grade),
    );
    if (picked == null) return;
    try {
      await _service.submitFeedback(
        analysisId: result.analysisId,
        trueGrade: picked,
        trueMoistureRisk: result.moistureRisk,
      );
      Get.snackbar(
        GradingStrings.t('feedback_thanks'),
        '',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on GradingException catch (e) {
      Get.snackbar(GradingStrings.t('error_generic'), e.message,
          snackPosition: SnackPosition.BOTTOM);
    }
  }
}

// ─── Step indicator ──────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final _Step current;
  const _StepBar({required this.current});

  @override
  Widget build(BuildContext context) {
    const steps = [_Step.crop, _Step.grain, _Step.moisture, _Step.result];
    const labels = ['step_crop', 'step_grain', 'step_moisture', 'step_result'];
    const icons = [
      Icons.eco_rounded,
      Icons.grain_rounded,
      Icons.water_drop_rounded,
      Icons.verified_rounded,
    ];
    final activeIndex = steps.indexOf(current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: List.generate(steps.length, (i) {
          final done = i < activeIndex;
          final active = i == activeIndex;
          final color = (done || active) ? AppTheme.green : AppTheme.textMuted;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        color: i == 0
                            ? Colors.transparent
                            : (done || active ? AppTheme.green : const Color(0xFFE2E7DC)),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: (done || active) ? AppTheme.green : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (done || active) ? AppTheme.green : const Color(0xFFD9E0D6),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        done ? Icons.check_rounded : icons[i],
                        size: 18,
                        color: (done || active) ? Colors.white : AppTheme.textMuted,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 4,
                        color: i == steps.length - 1
                            ? Colors.transparent
                            : (done ? AppTheme.green : const Color(0xFFE2E7DC)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  GradingStrings.t(labels[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 1: crop ────────────────────────────────────────────────────────────

class _CropStep extends StatelessWidget {
  final List<CropOption> crops;
  final CropOption? selectedCrop;
  final CropVariety? selectedVariety;
  final ValueChanged<CropOption> onCrop;
  final ValueChanged<CropVariety> onVariety;
  final VoidCallback onNext;

  const _CropStep({
    required this.crops,
    required this.selectedCrop,
    required this.selectedVariety,
    required this.onCrop,
    required this.onVariety,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final varieties = selectedCrop?.varieties ?? const [];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _StepTitle(text: GradingStrings.t('choose_crop'), icon: Icons.eco_rounded),
              const SizedBox(height: 12),
              ...crops.map((c) => _SelectTile(
                    label: c.label,
                    icon: Icons.grass_rounded,
                    selected: c.value == selectedCrop?.value,
                    onTap: () => onCrop(c),
                  )),
              if (varieties.isNotEmpty) ...[
                const SizedBox(height: 20),
                _StepTitle(text: GradingStrings.t('choose_variety'), icon: Icons.spa_rounded),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: varieties
                      .map((v) => ChoiceChip(
                            label: Text(v.label),
                            selected: v.value == selectedVariety?.value,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: v.value == selectedVariety?.value
                                  ? Colors.white
                                  : AppTheme.textDark,
                            ),
                            onSelected: (_) => onVariety(v),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        _BottomBar(
          primaryLabel: GradingStrings.t('next'),
          primaryIcon: Icons.arrow_forward_rounded,
          onPrimary: selectedCrop == null ? null : onNext,
        ),
      ],
    );
  }
}

// ─── Step 2: photo (grain) ───────────────────────────────────────────────────

class _PhotoStep extends StatelessWidget {
  final String title;
  final String hint;
  final IconData icon;
  final Uint8List? bytes;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  const _PhotoStep({
    super.key,
    required this.title,
    required this.hint,
    required this.icon,
    required this.bytes,
    required this.onCamera,
    required this.onGallery,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _StepTitle(text: title, icon: icon),
              const SizedBox(height: 6),
              Text(hint, style: const TextStyle(color: AppTheme.textMuted, height: 1.4)),
              const SizedBox(height: 16),
              _PhotoPreview(bytes: bytes, icon: icon),
              const SizedBox(height: 16),
              _CaptureButtons(onCamera: onCamera, onGallery: onGallery, hasPhoto: bytes != null),
            ],
          ),
        ),
        _BottomBar(
          onBack: onBack,
          primaryLabel: GradingStrings.t('next'),
          primaryIcon: Icons.arrow_forward_rounded,
          onPrimary: onNext,
        ),
      ],
    );
  }
}

// ─── Step 3: moisture ────────────────────────────────────────────────────────

class _MoistureStep extends StatelessWidget {
  final Uint8List? bytes;
  final TextEditingController manualController;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onBack;
  final VoidCallback onAnalyze;
  final ValueChanged<String> onManualChanged;

  const _MoistureStep({
    required this.bytes,
    required this.manualController,
    required this.onCamera,
    required this.onGallery,
    required this.onBack,
    required this.onAnalyze,
    required this.onManualChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canAnalyze =
        bytes != null || double.tryParse(manualController.text.trim()) != null;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _StepTitle(
                text: GradingStrings.t('take_moisture_photo'),
                icon: Icons.water_drop_rounded,
              ),
              const SizedBox(height: 6),
              Text(GradingStrings.t('moisture_hint'),
                  style: const TextStyle(color: AppTheme.textMuted, height: 1.4)),
              const SizedBox(height: 16),
              _PhotoPreview(bytes: bytes, icon: Icons.speed_rounded),
              const SizedBox(height: 16),
              _CaptureButtons(onCamera: onCamera, onGallery: onGallery, hasPhoto: bytes != null),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(GradingStrings.t('enter_moisture'),
                      style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: manualController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: onManualChanged,
                decoration: InputDecoration(
                  labelText: GradingStrings.t('moisture_percent'),
                  suffixText: '%',
                  prefixIcon: const Icon(Icons.percent_rounded),
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          onBack: onBack,
          primaryLabel: GradingStrings.t('check_grade'),
          primaryIcon: Icons.verified_rounded,
          onPrimary: canAnalyze ? onAnalyze : null,
        ),
      ],
    );
  }
}

// ─── Step 4: progress + result ───────────────────────────────────────────────

class _GradingProgress extends StatelessWidget {
  const _GradingProgress();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 5),
          ),
          const SizedBox(height: 20),
          Text(GradingStrings.t('checking'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              GradingStrings.t('checking_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultStep extends StatelessWidget {
  final GradeResult result;
  final VoidCallback onFeedback;
  final VoidCallback onHarvestQr;
  final VoidCallback onAgain;

  const _ResultStep({
    required this.result,
    required this.onFeedback,
    required this.onHarvestQr,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _GradeHero(result: result),
              if (result.manualReviewRequired) ...[
                const SizedBox(height: 12),
                _ReviewBanner(),
              ],
              const SizedBox(height: 12),
              _MoistureCard(result: result),
              if (result.signalHighlights.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SignalChips(signals: result.signalHighlights),
              ],
              const SizedBox(height: 12),
              _WhyCard(result: result),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onFeedback,
                icon: const Icon(Icons.flag_outlined),
                label: Text(GradingStrings.t('looks_wrong')),
              ),
            ],
          ),
        ),
        _BottomBar(
          backLabel: GradingStrings.t('grade_again'),
          onBack: onAgain,
          primaryLabel: GradingStrings.t('generate_qr'),
          primaryIcon: Icons.qr_code_2_rounded,
          onPrimary: onHarvestQr,
        ),
      ],
    );
  }
}

class _GradeHero extends StatelessWidget {
  final GradeResult result;
  const _GradeHero({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(result.grade);
    final confidence = result.confidenceOverall;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.78)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              result.grade,
              style: TextStyle(color: color, fontSize: 52, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GradingStrings.t('grade_label'),
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _gradeWord(result.grade),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                if (confidence != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${GradingStrings.t('confidence')}: ${confidence.round()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _gradeWord(String grade) {
    switch (grade) {
      case 'A':
        return 'Grade A';
      case 'B':
        return 'Grade B';
      default:
        return 'Grade C';
    }
  }
}

class _ReviewBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DB),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.gold),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_search_rounded, color: AppTheme.earth),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              GradingStrings.t('needs_human_check'),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.earth),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoistureCard extends StatelessWidget {
  final GradeResult result;
  const _MoistureCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final risk = result.moistureRisk;
    final color = _riskColor(risk);
    final percent = result.moisturePercent;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.water_drop_rounded, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(GradingStrings.t('moisture_label'),
                      style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_riskLabel(risk),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
                ],
              ),
            ),
            if (percent != null)
              Text('${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _SignalChips extends StatelessWidget {
  final List<String> signals;
  const _SignalChips({required this.signals});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: signals
          .map((s) => Chip(
                avatar: const Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: AppTheme.green),
                label: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
              ))
          .toList(),
    );
  }
}

class _WhyCard extends StatelessWidget {
  final GradeResult result;
  const _WhyCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String)>[
      if (result.brokenGrainPercent != null)
        ('Broken', '${result.brokenGrainPercent!.toStringAsFixed(0)}%'),
      if (result.foreignMatterPercent != null)
        ('Foreign matter', '${result.foreignMatterPercent!.toStringAsFixed(0)}%'),
      if (result.uniformityScore != null)
        ('Uniformity', result.uniformityScore!.toStringAsFixed(0)),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.tips_and_updates_outlined, color: AppTheme.green),
          title: Text(GradingStrings.t('why'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          children: [
            if (result.operatorSummary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(result.operatorSummary,
                    style: const TextStyle(color: AppTheme.textMuted, height: 1.45)),
              ),
            if (metrics.isNotEmpty)
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: metrics
                    .map((m) => _MetricPill(label: m.$1, value: m.$2))
                    .toList(),
              ),
            ...result.rejectReasons.map((r) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────────

class _StepTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  const _StepTitle({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _SelectTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppTheme.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: selected ? AppTheme.green : const Color(0xFFE5ECE2),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? AppTheme.green : AppTheme.textMuted),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppTheme.green),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final Uint8List? bytes;
  final IconData icon;
  const _PhotoPreview({required this.bytes, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Container(
        height: 220,
        width: double.infinity,
        color: const Color(0xFFF1EFE6),
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover)
            : Center(
                child: Icon(icon, size: 88, color: const Color(0xFFB7BCAE)),
              ),
      ),
    );
  }
}

class _CaptureButtons extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final bool hasPhoto;

  const _CaptureButtons({
    required this.onCamera,
    required this.onGallery,
    required this.hasPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.photo_camera_rounded),
            label: Text(hasPhoto ? GradingStrings.t('retake') : GradingStrings.t('camera')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(GradingStrings.t('gallery')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final String? backLabel;
  final VoidCallback? onBack;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;

  const _BottomBar({
    this.backLabel,
    this.onBack,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE5ECE2))),
        boxShadow: const [
          BoxShadow(color: Color(0x0C0B5D2A), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(backLabel ?? GradingStrings.t('back')),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(primaryIcon),
              label: Text(primaryLabel),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotConfiguredState extends StatelessWidget {
  final VoidCallback onRetry;
  const _NotConfiguredState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 72, color: AppTheme.textMuted),
            const SizedBox(height: 20),
            Text(GradingStrings.t('offline_title'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(GradingStrings.t('not_configured'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, height: 1.45)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(GradingStrings.t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  final String current;
  const _FeedbackSheet({required this.current});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late String _picked = widget.current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(GradingStrings.t('feedback_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Row(
            children: ['A', 'B', 'C'].map((g) {
              final selected = g == _picked;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _picked = g),
                    child: Container(
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? _gradeColor(g) : Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(
                          color: selected ? _gradeColor(g) : const Color(0xFFD9E0D6),
                          width: 1.6,
                        ),
                      ),
                      child: Text(g,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: selected ? Colors.white : AppTheme.textDark)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _picked),
            icon: const Icon(Icons.send_rounded),
            label: Text(GradingStrings.t('submit')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ],
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

Color _gradeColor(String grade) {
  switch (grade) {
    case 'A':
      return AppTheme.green;
    case 'B':
      return AppTheme.gold;
    default:
      return const Color(0xFFE07800);
  }
}

Color _riskColor(MoistureRisk risk) {
  switch (risk) {
    case MoistureRisk.low:
      return AppTheme.green;
    case MoistureRisk.moderate:
      return AppTheme.gold;
    case MoistureRisk.high:
      return const Color(0xFFE07800);
    case MoistureRisk.critical:
      return AppTheme.error;
    case MoistureRisk.unknown:
      return AppTheme.textMuted;
  }
}

String _riskLabel(MoistureRisk risk) {
  switch (risk) {
    case MoistureRisk.low:
      return GradingStrings.t('risk_low');
    case MoistureRisk.moderate:
      return GradingStrings.t('risk_moderate');
    case MoistureRisk.high:
      return GradingStrings.t('risk_high');
    case MoistureRisk.critical:
      return GradingStrings.t('risk_critical');
    case MoistureRisk.unknown:
      return GradingStrings.t('moisture_label');
  }
}
