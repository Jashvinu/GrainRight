import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/grading_strings.dart';
import '../config/locale_text.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../controllers/farm_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/grading/crop_option.dart';
import '../models/grading/grade_result.dart';
import '../models/satellite/farm_model.dart';
import '../services/grain_grading_service.dart';
import '../utils/harvest_machine_capture.dart';
import '../widgets/app_back_button.dart';
import '../widgets/fpc_bottom_nav.dart';

/// Standalone AI grain-grading flow.
/// Farm/batch → moisture OCR/confirmation → grain photo → result.
class FarmerAiGradingScreen extends StatefulWidget {
  const FarmerAiGradingScreen({super.key});

  @override
  State<FarmerAiGradingScreen> createState() => _FarmerAiGradingScreenState();
}

enum _Step { setup, moisture, grain, result }

class _FarmerAiGradingScreenState extends State<FarmerAiGradingScreen> {
  final GrainGradingService _service = GrainGradingService();
  final TextEditingController _manualMoistureCtrl = TextEditingController();
  final TextEditingController _batchCtrl = TextEditingController();
  final TextEditingController _bagSizeCtrl = TextEditingController(text: '50');
  final TextEditingController _bagCountCtrl = TextEditingController(text: '1');

  _Step _step = _Step.setup;
  bool _loadingCrops = true;
  bool _readingMoisture = false;
  bool _grading = false;
  bool _notConfigured = false;

  List<CropOption> _crops = const [];
  CropOption? _crop;
  CropVariety? _variety;

  Uint8List? _grainBytes;
  String _grainName = 'grain.jpg';
  Uint8List? _moistureBytes;
  String _moistureName = 'moisture.jpg';
  String? _moistureImagePath;
  MoistureOcrResult? _moistureReading;

  GradeResult? _result;

  Map<String, dynamic> get _routeArgs {
    final args = Get.arguments;
    return args is Map ? Map<String, dynamic>.from(args) : const {};
  }

  String _arg(String key, [String fallback = '']) {
    final value = _routeArgs[key];
    final text = value == null ? '' : '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  bool get _isFpcMode => _arg('mode').toLowerCase() == 'fpc';

  String get _actorRole => _isFpcMode ? 'fpc' : 'farmer';

  String get _fpcCustomerId => _arg('fpcCustomerId');

  String get _fpcCustomerName => _arg('fpcCustomerName', _arg('farmerName'));

  String get _farmLocation =>
      _arg('farmLocation', _arg('location', _arg('village')));

  Map<String, String> get _farmArgs {
    return {
      'farmName': _arg('farmName'),
      'farmId': _arg('farmId'),
      'crop': _arg('crop', 'Finger Millet'),
      'variety': _arg('variety', 'Local'),
      'village': _farmLocation,
      'product': _arg('product'),
      'actorRole': _actorRole,
      'fpcCustomerId': _fpcCustomerId,
      'fpcCustomerName': _fpcCustomerName,
    };
  }

  Farm? get _selectedRemoteFarm {
    if (_isFpcMode) return null;
    if (!Get.isRegistered<FarmController>()) return null;
    return Get.find<FarmController>().selectedFarm.value;
  }

  String get _farmId {
    final remote = _selectedRemoteFarm?.id ?? '';
    if (remote.trim().isNotEmpty) return remote.trim();
    return (_farmArgs['farmId'] ?? '').trim();
  }

  String get _farmName {
    final remote = _selectedRemoteFarm?.name ?? '';
    if (remote.trim().isNotEmpty) return remote.trim();
    return (_farmArgs['farmName'] ?? '').trim();
  }

  String get _farmerId {
    final argFarmerId = _arg('farmerId');
    if (argFarmerId.isNotEmpty) return argFarmerId;
    if (_isFpcMode && _fpcCustomerId.isNotEmpty) return _fpcCustomerId;
    if (!Get.isRegistered<MainAuthController>()) return '';
    return Get.find<MainAuthController>().verifiedFarmer.value?.farmerId ?? '';
  }

  String get _farmerName {
    final argFarmerName = _arg('farmerName');
    if (argFarmerName.isNotEmpty) return argFarmerName;
    if (_isFpcMode && _fpcCustomerName.isNotEmpty) return _fpcCustomerName;
    if (!Get.isRegistered<MainAuthController>()) return '';
    return Get.find<MainAuthController>().verifiedFarmer.value?.farmerName ?? '';
  }

  bool get _setupComplete {
    return _crop != null &&
        _batchCtrl.text.trim().isNotEmpty &&
        double.tryParse(_bagSizeCtrl.text.trim()) != null &&
        int.tryParse(_bagCountCtrl.text.trim()) != null &&
        _farmerId.isNotEmpty &&
        _farmName.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _batchCtrl.text = _batchId();
    _loadCrops();
  }

  @override
  void dispose() {
    _manualMoistureCtrl.dispose();
    _batchCtrl.dispose();
    _bagSizeCtrl.dispose();
    _bagCountCtrl.dispose();
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
      final loaded = crops.isEmpty ? _fallbackCrops : crops;
      setState(() {
        _crops = loaded;
        _crop = _initialCrop(loaded);
        _variety = _crop!.varieties.isNotEmpty ? _crop!.varieties.first : null;
        _loadingCrops = false;
      });
    } on GradingException catch (_) {
      // Catalog is non-critical: fall back to a built-in crop so grading still
      // works even when the catalog endpoint is unreachable.
      setState(() {
        _crops = _fallbackCrops;
        _crop = _initialCrop(_crops);
        _variety = _crop!.varieties.isNotEmpty ? _crop!.varieties.first : null;
        _loadingCrops = false;
      });
    }
  }

  CropOption _initialCrop(List<CropOption> crops) {
    final desired = (_selectedRemoteFarm?.crop ?? _farmArgs['crop'] ?? '')
        .toLowerCase()
        .trim();
    if (desired.isEmpty) return crops.first;
    return crops.firstWhere(
      (crop) {
        final label = crop.label.toLowerCase();
        final value = crop.value.toLowerCase();
        return label.contains(desired) || desired.contains(label) || value == desired;
      },
      orElse: () => crops.first,
    );
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
        _moistureImagePath = null;
        _moistureReading = null;
      }
    });
  }

  Future<void> _readMoisture() async {
    final manual = double.tryParse(_manualMoistureCtrl.text.trim());
    if (_moistureBytes == null && manual == null) {
      Get.snackbar(
        GradingStrings.t('step_moisture'),
        GradingStrings.t('moisture_hint'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _readingMoisture = true);
    try {
      final reading = await _service.readMoisture(
        moistureImageBytes: _moistureBytes,
        moistureImageName: _moistureName,
        manualMoisturePercent: manual,
      );
      if (!mounted) return;
      setState(() {
        _readingMoisture = false;
        _moistureReading = reading;
        _moistureImagePath = reading.imagePath?.isEmpty == true
            ? null
            : reading.imagePath;
        if (reading.percent != null) {
          _manualMoistureCtrl.text = reading.percent!.toStringAsFixed(1);
        }
        _step = _Step.grain;
      });
    } on GradingException catch (e) {
      if (!mounted) return;
      setState(() => _readingMoisture = false);
      Get.snackbar(
        GradingStrings.t('error_generic'),
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _analyze() async {
    final crop = _crop;
    final grain = _grainBytes;
    if (crop == null || grain == null) return;
    final manual = double.tryParse(_manualMoistureCtrl.text.trim());
    if (_moistureImagePath == null && _moistureBytes == null && manual == null) {
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
        moistureImageBytes: _moistureImagePath == null ? _moistureBytes : null,
        moistureImageName: _moistureName,
        moistureImagePath: _moistureImagePath,
        manualMoisturePercent: manual,
        cropType: crop.value,
        cropVariety: _variety?.value ?? '',
        farmerId: _farmerId,
        farmId: _farmId,
        batchId: _batchCtrl.text.trim(),
        bagSizeKg: double.tryParse(_bagSizeCtrl.text.trim()),
        bagCount: int.tryParse(_bagCountCtrl.text.trim()),
        actorRole: _actorRole,
        fpcCustomerId: _isFpcMode ? _fpcCustomerId : null,
        fpcCustomerName: _isFpcMode ? _fpcCustomerName : null,
        source: _isFpcMode ? 'fpc_grain_grading' : 'farmer_grain_grading',
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
      setState(() => _step = _Step.grain);
    }
  }

  void _goToHarvestQr() {
    final result = _result;
    if (result == null) return;
    if (result.manualReviewRequired) {
      Get.snackbar(
        GradingStrings.t('needs_human_check'),
        GradingStrings.t('fpo_approval_required'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final bagSize = double.tryParse(_bagSizeCtrl.text.trim());
    final bagCount = int.tryParse(_bagCountCtrl.text.trim());
    if (_farmerId.isEmpty ||
        _farmId.isEmpty ||
        _farmName.isEmpty ||
        _batchCtrl.text.trim().isEmpty ||
        bagSize == null ||
        bagCount == null ||
        result.analysisId.isEmpty) {
      Get.snackbar(
        GradingStrings.t('generate_qr'),
        GradingStrings.t('complete_qr_details_first'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final farm = _farmArgs;
    final moisture = result.moisturePercent;
    Get.toNamed('/farmer/harvest-qr', arguments: {
      ...farm,
      'analysisId': result.analysisId,
      'farmId': _farmId,
      'farmName': _farmName,
      'farmerId': _farmerId,
      'farmerName': _farmerName,
      'crop': _crop?.label ?? farm['crop'],
      'variety': _variety?.label ?? 'Local',
      'grade': result.grade,
      'score': result.finalScore?.round().toString() ??
          result.confidenceOverall?.round().toString() ??
          '--',
      'moisture': moisture != null ? '${moisture.toStringAsFixed(1)}%' : '--',
      'moistureSource': result.moistureSource.isEmpty ? '--' : result.moistureSource,
      'grader': GradingStrings.t('ai_grading'),
      'batchId': _batchCtrl.text.trim(),
      'bagSizeKg': bagSize.toStringAsFixed(1),
      'bagCount': bagCount.toString(),
      'totalKg': (bagSize * bagCount).toStringAsFixed(1),
      'reviewStatus': 'approved',
      'actorRole': _actorRole,
      if (_isFpcMode) 'fpcCustomerId': _fpcCustomerId,
      if (_isFpcMode) 'fpcCustomerName': _fpcCustomerName,
    });
  }

  void _addResultToInventory() {
    final result = _result;
    if (result == null) return;
    if (result.manualReviewRequired) {
      Get.snackbar(
        GradingStrings.t('needs_human_check'),
        GradingStrings.t('fpo_approval_required'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final bagSize = double.tryParse(_bagSizeCtrl.text.trim());
    final bagCount = int.tryParse(_bagCountCtrl.text.trim());
    final moisture =
        result.moisturePercent ??
        double.tryParse(_manualMoistureCtrl.text.trim());
    if (bagSize == null ||
        bagCount == null ||
        bagSize <= 0 ||
        bagCount <= 0 ||
        moisture == null) {
      Get.snackbar(
        UiStrings.t('inventory'),
        GradingStrings.t('complete_qr_details_first'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Get.back<Map<String, dynamic>>(
      result: {
        'action': 'add_inventory',
        'batchId': _batchCtrl.text.trim(),
        'crop': _crop?.label ?? _farmArgs['crop'] ?? '',
        'variety': _variety?.label ?? _farmArgs['variety'] ?? 'Local',
        'bagSizeKg': bagSize,
        'bagCount': bagCount,
        'moisturePercent': moisture,
        'grade': result.grade,
        'gradeScore':
            result.finalScore?.round() ??
            result.confidenceOverall?.round() ??
            0,
        'gradeBasis': result.operatorSummary.isEmpty
            ? GradingStrings.t('ai_grading')
            : result.operatorSummary,
        'imageName': result.analysisId.isEmpty
            ? 'grain-grading'
            : result.analysisId,
      },
    );
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
      bottomNavigationBar:
          _isFpcMode ? const FpcBottomNavBar(current: FpcNavTab.grading) : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(
          _isFpcMode ? GradingStrings.t('fpc_title') : GradingStrings.t('title'),
        ),
      ),
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
      case _Step.setup:
        return _SetupStep(
          farmName: _farmName,
          farmLocation: _farmLocation,
          farmId: _farmId,
          farmerId: _farmerId,
          farmerName: _farmerName,
          actorLabel: _isFpcMode
              ? GradingStrings.t('fpc_customer_lot')
              : GradingStrings.t('farmer_farm_lot'),
          batchController: _batchCtrl,
          bagSizeController: _bagSizeCtrl,
          bagCountController: _bagCountCtrl,
          crops: _crops,
          selectedCrop: _crop,
          selectedVariety: _variety,
          onCrop: (c) => setState(() {
            _crop = c;
            _variety = c.varieties.isNotEmpty ? c.varieties.first : null;
          }),
          onVariety: (v) => setState(() => _variety = v),
          onChanged: () => setState(() {}),
          onNext: _setupComplete ? () => setState(() => _step = _Step.moisture) : null,
        );
      case _Step.grain:
        return _PhotoStep(
          key: const ValueKey('grain'),
          title: GradingStrings.t('take_grain_photo'),
          hint: GradingStrings.t('grain_hint'),
          icon: Icons.grain_rounded,
          bytes: _grainBytes,
          primaryLabel: GradingStrings.t('check_grade'),
          primaryIcon: Icons.verified_rounded,
          onCamera: () => _pick(grain: true, source: HarvestMachineImageSource.camera),
          onGallery: () => _pick(grain: true, source: HarvestMachineImageSource.gallery),
          onBack: () => setState(() => _step = _Step.moisture),
          onNext: _grainBytes == null ? null : _analyze,
        );
      case _Step.moisture:
        return _MoistureStep(
          bytes: _moistureBytes,
          reading: _moistureReading,
          readingMoisture: _readingMoisture,
          manualController: _manualMoistureCtrl,
          onCamera: () => _pick(grain: false, source: HarvestMachineImageSource.camera),
          onGallery: () => _pick(grain: false, source: HarvestMachineImageSource.gallery),
          onBack: () => setState(() => _step = _Step.setup),
          onReadMoisture: _readMoisture,
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
          onAddInventory: _isFpcMode ? null : _addResultToInventory,
          primaryLabel: _isFpcMode
              ? GradingStrings.t('generate_public_trace_qr')
              : GradingStrings.t('generate_qr'),
          onAgain: () => setState(() {
            _step = _Step.setup;
            _grainBytes = null;
            _moistureBytes = null;
            _moistureImagePath = null;
            _moistureReading = null;
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
    const steps = [_Step.setup, _Step.moisture, _Step.grain, _Step.result];
    const labels = ['step_setup', 'step_moisture', 'step_grain', 'step_result'];
    const icons = [
      Icons.inventory_2_rounded,
      Icons.water_drop_rounded,
      Icons.grain_rounded,
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

// ─── Step 1: setup ───────────────────────────────────────────────────────────

class _SetupStep extends StatelessWidget {
  final String farmName;
  final String farmLocation;
  final String farmId;
  final String farmerId;
  final String farmerName;
  final String actorLabel;
  final TextEditingController batchController;
  final TextEditingController bagSizeController;
  final TextEditingController bagCountController;
  final List<CropOption> crops;
  final CropOption? selectedCrop;
  final CropVariety? selectedVariety;
  final ValueChanged<CropOption> onCrop;
  final ValueChanged<CropVariety> onVariety;
  final VoidCallback onChanged;
  final VoidCallback? onNext;

  const _SetupStep({
    required this.farmName,
    required this.farmLocation,
    required this.farmId,
    required this.farmerId,
    required this.farmerName,
    required this.actorLabel,
    required this.batchController,
    required this.bagSizeController,
    required this.bagCountController,
    required this.crops,
    required this.selectedCrop,
    required this.selectedVariety,
    required this.onCrop,
    required this.onVariety,
    required this.onChanged,
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
              _StepTitle(
                text: GradingStrings.t('setup_batch'),
                icon: Icons.inventory_2_rounded,
              ),
              const SizedBox(height: 12),
              _ContextCard(
                farmName: farmName,
                farmLocation: farmLocation,
                farmId: farmId,
                farmerId: farmerId,
                farmerName: farmerName,
                actorLabel: actorLabel,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: batchController,
                readOnly: true,
                enableInteractiveSelection: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: GradingStrings.t('batch_id'),
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  suffixIcon: const Icon(Icons.lock_outline_rounded),
                  helperText: GradingStrings.t('generated_automatically'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bagSizeController,
                      onChanged: (_) => onChanged(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: GradingStrings.t('bag_kg'),
                        prefixIcon: const Icon(Icons.scale_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: bagCountController,
                      onChanged: (_) => onChanged(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: GradingStrings.t('bags'),
                        prefixIcon: const Icon(Icons.inventory_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _StepTitle(
                text: GradingStrings.t('choose_crop'),
                icon: Icons.eco_rounded,
              ),
              const SizedBox(height: 12),
              ...crops.map((c) => _SelectTile(
                    label: _gradingOptionLabel(c.label),
                    icon: Icons.grass_rounded,
                    selected: c.value == selectedCrop?.value,
                    onTap: () => onCrop(c),
                  )),
              if (varieties.isNotEmpty) ...[
                const SizedBox(height: 20),
                _StepTitle(
                  text: GradingStrings.t('choose_variety'),
                  icon: Icons.spa_rounded,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: varieties
                      .map((v) => ChoiceChip(
                            label: Text(_gradingOptionLabel(v.label)),
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
          onPrimary: onNext,
        ),
      ],
    );
  }
}

String _gradingOptionLabel(String label) {
  return switch (label.trim().toLowerCase()) {
    'finger millet (ragi)' => GradingStrings.t('finger_millet_ragi'),
    'local' => GradingStrings.t('local'),
    _ => label,
  };
}

class _ContextCard extends StatelessWidget {
  final String farmName;
  final String farmLocation;
  final String farmId;
  final String farmerId;
  final String farmerName;
  final String actorLabel;

  const _ContextCard({
    required this.farmName,
    required this.farmLocation,
    required this.farmId,
    required this.farmerId,
    required this.farmerName,
    required this.actorLabel,
  });

  @override
  Widget build(BuildContext context) {
    final missingFarmId = farmId.trim().isEmpty;
    final missingFarmer = farmerId.trim().isEmpty;
    final missingLocation = farmLocation.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: missingFarmId || missingFarmer
              ? AppTheme.gold
              : const Color(0xFFE5ECE2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.agriculture_rounded, color: AppTheme.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actorLabel,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _LotInfoLine(
                  label: GradingStrings.t('farmer'),
                  value:
                      farmerName.isEmpty
                          ? GradingStrings.t('farmer_name_unavailable')
                          : farmerName,
                ),
                const SizedBox(height: 6),
                _LotInfoLine(
                  label: GradingStrings.t('farm_name'),
                  value: farmName.isEmpty
                      ? GradingStrings.t('no_farm_selected')
                      : farmName,
                ),
                const SizedBox(height: 6),
                _LotInfoLine(
                  label: GradingStrings.t('location'),
                  value: missingLocation
                      ? GradingStrings.t('location_unavailable')
                      : farmLocation,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LotInfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _LotInfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
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
  final String primaryLabel;
  final IconData primaryIcon;
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
    this.primaryLabel = '',
    this.primaryIcon = Icons.arrow_forward_rounded,
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
          primaryLabel: primaryLabel.isEmpty
              ? GradingStrings.t('next')
              : primaryLabel,
          primaryIcon: primaryIcon,
          onPrimary: onNext,
        ),
      ],
    );
  }
}

// ─── Step 3: moisture ────────────────────────────────────────────────────────

class _MoistureStep extends StatelessWidget {
  final Uint8List? bytes;
  final MoistureOcrResult? reading;
  final bool readingMoisture;
  final TextEditingController manualController;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onBack;
  final VoidCallback onReadMoisture;
  final ValueChanged<String> onManualChanged;

  const _MoistureStep({
    required this.bytes,
    required this.reading,
    required this.readingMoisture,
    required this.manualController,
    required this.onCamera,
    required this.onGallery,
    required this.onBack,
    required this.onReadMoisture,
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
              if (reading != null) ...[
                const SizedBox(height: 14),
                _MoistureReadingCard(reading: reading!),
              ],
            ],
          ),
        ),
        _BottomBar(
          onBack: onBack,
          primaryLabel: readingMoisture
              ? GradingStrings.t('checking')
              : GradingStrings.t('read_moisture'),
          primaryIcon: readingMoisture
              ? Icons.hourglass_top_rounded
              : Icons.speed_rounded,
          onPrimary: canAnalyze && !readingMoisture ? onReadMoisture : null,
        ),
      ],
    );
  }
}

class _MoistureReadingCard extends StatelessWidget {
  final MoistureOcrResult reading;

  const _MoistureReadingCard({required this.reading});

  @override
  Widget build(BuildContext context) {
    final percent = reading.percent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed_rounded, color: AppTheme.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Moisture reading',
                  style: TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${reading.source}${reading.confidence == null ? '' : ' • ${(reading.confidence! * 100).round()}% confidence'}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            percent == null ? '--' : '${percent.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
  final VoidCallback? onAddInventory;
  final String primaryLabel;
  final VoidCallback onAgain;

  const _ResultStep({
    required this.result,
    required this.onFeedback,
    required this.onHarvestQr,
    required this.onAddInventory,
    required this.primaryLabel,
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
              _CloudModelAnalysisCard(result: result),
              const SizedBox(height: 12),
              _MoistureCard(result: result),
              if (result.signalHighlights.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SignalChips(signals: result.signalHighlights),
              ],
              const SizedBox(height: 12),
              _WhyCard(result: result),
              const SizedBox(height: 12),
              if (onAddInventory != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAddInventory,
                    icon: const Icon(Icons.inventory_2_rounded),
                    label: Text(UiStrings.t('add_product_inventory')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextButton.icon(
                onPressed: onFeedback,
                icon: const Icon(Icons.flag_outlined),
                label: Text(GradingStrings.t('looks_wrong')),
              ),
            ],
          ),
        ),
        _BottomBar(
          onBack: onAgain,
          primaryLabel: primaryLabel,
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
    final score = result.finalScore;
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
                  'Grade from cloud score',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _gradeWord(result.grade),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                if (score != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Score: ${score.round()}/100',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ] else if (confidence != null) ...[
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

class _CloudModelAnalysisCard extends StatelessWidget {
  final GradeResult result;

  const _CloudModelAnalysisCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final finalScore = result.finalScore;
    final grainScore = result.grainScore;
    final moistureScore = result.moistureScore;
    final modelGrade = result.modelGrade.isEmpty ? '--' : result.modelGrade;
    final scoreGrade = result.scoreGrade.isEmpty ? result.grade : result.scoreGrade;
    final moisture = result.moisturePercent;
    final rows = <Widget>[
      _AnalysisMetric(
        label: GradingStrings.t('cloud_score'),
        value: finalScore == null ? '--' : '${finalScore.round()}/100',
      ),
      _AnalysisMetric(label: GradingStrings.t('score_grade'), value: scoreGrade),
      _AnalysisMetric(
        label: GradingStrings.t('model_suggested'),
        value: modelGrade,
      ),
      _AnalysisMetric(
        label: GradingStrings.t('grain_score'),
        value: grainScore == null ? '--' : '${grainScore.round()}/100',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('moisture_score'),
        value: moistureScore == null ? '--' : '${moistureScore.round()}/100',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('moisture_label'),
        value: moisture == null
            ? _riskLabel(result.moistureRisk)
            : '${moisture.toStringAsFixed(1)}% - ${_riskLabel(result.moistureRisk)}',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('broken_grain'),
        value: result.brokenGrainPercent == null
            ? '--'
            : '${result.brokenGrainPercent!.toStringAsFixed(1)}%',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('foreign_matter'),
        value: result.foreignMatterPercent == null
            ? '--'
            : '${result.foreignMatterPercent!.toStringAsFixed(2)}%',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('damaged_grain'),
        value: result.damagedPercent == null
            ? '--'
            : '${result.damagedPercent!.toStringAsFixed(1)}%',
      ),
      _AnalysisMetric(
        label: GradingStrings.t('uniformity'),
        value: result.uniformityScore == null
            ? '--'
            : '${result.uniformityScore!.round()}/100',
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: AppTheme.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    GradingStrings.t('cloud_model_analysis'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The visible grade is calculated from the score received from the cloud grading response.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: rows),
            if (result.operatorSummary.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                result.operatorSummary,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisMetric extends StatelessWidget {
  final String label;
  final String value;

  const _AnalysisMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5ECE2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
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
              Text(UiStrings.f('percent_value', {
                'value': LocaleText.number(percent, fractionDigits: 1),
              }),
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
      if (result.damagedPercent != null)
        ('Damaged', '${result.damagedPercent!.toStringAsFixed(0)}%'),
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
  final VoidCallback? onBack;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;

  const _BottomBar({
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
            AppBackButton(onPressed: onBack),
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
