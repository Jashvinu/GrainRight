import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/survey_controller.dart';
import '../models/form_config.dart';
import '../services/form_config_service.dart';
import '../services/location_service.dart';
import '../services/survey_service.dart';

class FormController extends GetxController {
  final _surveyService = SurveyService();
  final _configService = FormConfigService();
  final _locationService = LocationService();

  // Config state
  final sections = <FormSectionConfig>[].obs;
  final dropdownOptions = <String, List<String>>{}.obs;
  final isConfigLoaded = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;

  // Form state
  final currentStep = 0.obs;
  final isSubmitting = false.obs;
  final formKey = GlobalKey<FormState>();
  final visitedSteps = <int>{0}.obs;

  String? editId;
  bool get isEditMode => editId != null;
  int get totalSteps => sections.length;

  // Dynamic field storage
  final _textControllers = <String, TextEditingController>{};
  final _boolValues = <String, Rxn<bool>>{};
  final _stringValues = <String, Rxn<String>>{};
  final _dateValues = <String, Rxn<DateTime>>{};
  final _autoCalcValues = <String, RxDouble>{};
  final _polygonValues = <String, Rxn<List<List<double>>>>{};
  final _multiSelectValues = <String, RxList<String>>{};

  // Location + time
  final locationStatus = LocationStatus.idle.obs;
  LocationResult? _capturedLocation;
  DateTime? _formStartedAt;

  // Millet land picker state
  final milletLandMode = 'total'.obs;
  final milletLandTotal = 0.0.obs;
  final _milletLandControllers = <String, TextEditingController>{};

  // Accessors for DynamicField
  TextEditingController textController(String key) => _textControllers[key]!;
  Rxn<bool> boolValue(String key) => _boolValues[key]!;
  Rxn<String> dropdownValue(String key) => _stringValues[key]!;
  Rxn<DateTime> dateValue(String key) => _dateValues[key]!;
  RxDouble autoCalcValue(String key) => _autoCalcValues[key]!;
  Rxn<List<List<double>>> polygonValue(String key) => _polygonValues[key]!;
  RxList<String> multiSelectValue(String key) =>
      _multiSelectValues[key] ?? <String>[].obs;

  LocationResult? get capturedLocation => _capturedLocation;

  String get locationSummary {
    switch (locationStatus.value) {
      case LocationStatus.fetching:
        return 'Getting location...';
      case LocationStatus.acquired:
        final loc = _capturedLocation!;
        return '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)} (±${loc.accuracy.toStringAsFixed(0)}m)';
      case LocationStatus.denied:
        return 'Location permission denied';
      case LocationStatus.unavailable:
        return 'GPS unavailable';
      case LocationStatus.idle:
        return '';
    }
  }

  TextEditingController milletLandController(String milletType) {
    return _milletLandControllers.putIfAbsent(milletType, () {
      final c = TextEditingController();
      c.addListener(_updateMilletLandTotal);
      return c;
    });
  }

  void _updateMilletLandTotal() {
    if (milletLandMode.value != 'per_type') return;
    final total = _milletLandControllers.values
        .map((c) => double.tryParse(c.text) ?? 0.0)
        .fold(0.0, (a, b) => a + b);
    _textControllers['land_under_millet']?.text =
        total > 0 ? total.toString() : '';
    milletLandTotal.value = total;
  }

  void clearMilletLandAreas() {
    for (final c in _milletLandControllers.values) {
      c.text = '';
    }
    milletLandTotal.value = 0.0;
  }

  @override
  void onInit() {
    super.onInit();
    ever(currentStep, (step) {
      visitedSteps.add(step);
      saveDraft();
    });
  }

  Future<void> loadConfig() async {
    hasError.value = false;
    isConfigLoaded.value = false;
    _formStartedAt = DateTime.now().toUtc();

    // Kick off location fetch in parallel with config load
    if (!isEditMode) _fetchLocation();

    try {
      final results = await Future.wait([
        _configService.fetchFormConfig(),
        _configService.fetchDropdownOptions(),
      ]);
      sections.value = results[0] as List<FormSectionConfig>;
      dropdownOptions.value = results[1] as Map<String, List<String>>;
      _initializeFieldControllers();
      isConfigLoaded.value = true;
      if (!isEditMode) await loadDraft();
    } catch (e, st) {
      debugPrint('[FormController.loadConfig] $e\n$st');
      hasError.value = true;
      errorMessage.value = _friendlyError(e);
    }
  }

  Future<void> _fetchLocation() async {
    locationStatus.value = LocationStatus.fetching;
    final result = await _locationService.getCurrentLocation();
    if (result != null) {
      _capturedLocation = result;
      locationStatus.value = LocationStatus.acquired;
    } else {
      // Distinguish denied vs unavailable by re-checking
      final permission = await _locationService.getPermissionStatus();
      locationStatus.value = permission
          ? LocationStatus.unavailable
          : LocationStatus.denied;
    }
  }

  void _initializeFieldControllers() {
    for (final section in sections) {
      for (final field in section.fields) {
        switch (field.inputType) {
          case 'text':
          case 'numeric':
          case 'mobile':
          case 'aadhar':
          case 'currency':
          case 'acre':
          case 'millet_land_picker':
            _textControllers[field.fieldKey] = TextEditingController();
          case 'dropdown':
            _stringValues[field.fieldKey] = Rxn<String>();
          case 'boolean':
            _boolValues[field.fieldKey] = Rxn<bool>();
          case 'date':
            _dateValues[field.fieldKey] = Rxn<DateTime>();
          case 'polygon':
            _polygonValues[field.fieldKey] = Rxn<List<List<double>>>();
          case 'auto_calc':
            _autoCalcValues[field.fieldKey] = 0.0.obs;
          case 'multiselect':
            _multiSelectValues[field.fieldKey] = <String>[].obs;
        }
      }
    }
    _setupAutoCalcListeners();
  }

  void _setupAutoCalcListeners() {
    for (final section in sections) {
      for (final field in section.fields) {
        if (field.inputType == 'auto_calc' && field.autoCalcFormula != null) {
          final formula = field.autoCalcFormula!;
          final operands = (formula['operands'] as List).cast<String>();
          for (final operandKey in operands) {
            final ctrl = _textControllers[operandKey];
            ctrl?.addListener(() => _recalculate(field.fieldKey, formula));
          }
        }
      }
    }
  }

  void _recalculate(String targetKey, Map<String, dynamic> formula) {
    final op = formula['operation'] as String;
    final operands = (formula['operands'] as List).cast<String>();
    final values = operands
        .map((k) => double.tryParse(_textControllers[k]?.text ?? '') ?? 0.0)
        .toList();

    final result = switch (op) {
      'sum' => values.fold(0.0, (a, b) => a + b),
      'subtract' => values.length >= 2 ? values[0] - values[1] : 0.0,
      'multiply' => values.fold(1.0, (a, b) => a * b),
      'divide' =>
        values.length >= 2 && values[1] != 0 ? values[0] / values[1] : 0.0,
      _ => 0.0,
    };
    _autoCalcValues[targetKey]!.value = result;
  }

  bool isFieldVisible(FormFieldConfig field) {
    if (field.visibilityRule == null) return true;
    final rule = field.visibilityRule!;
    final dependsOn = rule['depends_on'] as String;
    final operator = rule['operator'] as String;
    final expectedValue = rule['value'];

    dynamic currentValue;
    if (_boolValues.containsKey(dependsOn)) {
      currentValue = _boolValues[dependsOn]!.value;
    } else if (_stringValues.containsKey(dependsOn)) {
      currentValue = _stringValues[dependsOn]!.value;
    } else if (_textControllers.containsKey(dependsOn)) {
      currentValue = _textControllers[dependsOn]!.text;
    } else if (_dateValues.containsKey(dependsOn)) {
      currentValue = _dateValues[dependsOn]!.value;
    }

    return switch (operator) {
      'equals' => currentValue == expectedValue,
      'not_equals' => currentValue != expectedValue,
      'not_null' => currentValue != null,
      _ => true,
    };
  }

  bool isStepFilled(int stepIndex) {
    if (stepIndex >= sections.length) return false;
    final section = sections[stepIndex];
    for (final field in section.fields) {
      if (!isFieldVisible(field)) continue;
      final key = field.fieldKey;
      switch (field.inputType) {
        case 'text':
        case 'numeric':
        case 'mobile':
        case 'aadhar':
        case 'currency':
        case 'acre':
        case 'millet_land_picker':
          if (_textControllers[key]!.text.isNotEmpty) return true;
        case 'dropdown':
          if (_stringValues[key]!.value != null) return true;
        case 'boolean':
          if (_boolValues[key]!.value != null) return true;
        case 'date':
          if (_dateValues[key]!.value != null) return true;
        case 'polygon':
          final poly = _polygonValues[key]!.value;
          if (poly != null && poly.isNotEmpty) return true;
        case 'auto_calc':
          if (_autoCalcValues[key]!.value != 0) return true;
        case 'multiselect':
          if (_multiSelectValues[key]!.isNotEmpty) return true;
      }
    }
    return false;
  }

  // --- Draft saving ---

  Future<void> saveDraft() async {
    if (isEditMode) return;
    try {
      final draft = <String, dynamic>{};
      for (final section in sections) {
        for (final field in section.fields) {
          final key = field.fieldKey;
          switch (field.inputType) {
            case 'text':
            case 'numeric':
            case 'mobile':
            case 'aadhar':
            case 'currency':
            case 'acre':
            case 'millet_land_picker':
              final t = _textControllers[key]?.text ?? '';
              if (t.isNotEmpty) draft[key] = t;
            case 'dropdown':
              final v = _stringValues[key]?.value;
              if (v != null) draft[key] = v;
            case 'boolean':
              final v = _boolValues[key]?.value;
              if (v != null) draft[key] = v;
            case 'date':
              final v = _dateValues[key]?.value;
              if (v != null) draft[key] = v.toIso8601String();
            case 'multiselect':
              final v = _multiSelectValues[key];
              if (v != null && v.isNotEmpty) draft[key] = v.toList();
            case 'auto_calc':
              break;
            case 'polygon':
              break;
          }
        }
      }
      // Save millet land picker extras
      draft['__millet_land_mode'] = milletLandMode.value;
      if (_milletLandControllers.isNotEmpty) {
        final areas = <String, String>{};
        _milletLandControllers.forEach((k, v) {
          if (v.text.isNotEmpty) areas[k] = v.text;
        });
        if (areas.isNotEmpty) draft['__millet_land_areas'] = areas;
      }
      draft['__current_step'] = currentStep.value;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('form_draft', jsonEncode(draft));
    } catch (e) {
      debugPrint('[FormController.saveDraft] $e');
    }
  }

  Future<void> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('form_draft');
      if (raw == null) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      _populateFromJson(draft);

      final mode = draft['__millet_land_mode'] as String?;
      if (mode != null) milletLandMode.value = mode;

      final areas = draft['__millet_land_areas'];
      if (areas is Map) {
        areas.forEach((k, v) {
          milletLandController(k.toString()).text = v.toString();
        });
        _updateMilletLandTotal();
      }

      final step = draft['__current_step'] as int?;
      if (step != null && step > 0 && step < totalSteps) {
        currentStep.value = step;
        visitedSteps.addAll(List.generate(step + 1, (i) => i));
      }
    } catch (e) {
      debugPrint('[FormController.loadDraft] $e');
    }
  }

  Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('form_draft');
    } catch (_) {}
  }

  // --- Edit mode ---

  Future<void> loadSurvey(String id) async {
    try {
      editId = id;
      final data = await _surveyService.fetchById(id);
      _populateFromJson(data.toJson());
      visitedSteps.addAll(List.generate(totalSteps, (i) => i).toSet());
    } catch (e, st) {
      debugPrint('[FormController.loadSurvey] $e\n$st');
      Get.snackbar('Error', _friendlyError(e));
    }
  }

  void _populateFromJson(Map<String, dynamic> json) {
    for (final section in sections) {
      for (final field in section.fields) {
        final key = field.fieldKey;
        final raw = json[key];
        if (raw == null) continue;

        switch (field.inputType) {
          case 'text':
          case 'mobile':
            _textControllers[key]!.text = raw.toString();
          case 'aadhar':
            _textControllers[key]!.text = _formatAadhar(raw.toString());
          case 'numeric':
          case 'currency':
          case 'acre':
            final v = _toDouble(raw);
            _textControllers[key]!.text = v != null ? v.toString() : '';
          case 'millet_land_picker':
            final v = _toDouble(raw);
            _textControllers[key]!.text = v != null ? v.toString() : '';
            // Restore per-type areas if present
            final areas = json['millet_land_areas'];
            if (areas is Map && areas.isNotEmpty) {
              areas.forEach((milletType, landVal) {
                final c = milletLandController(milletType.toString());
                final dv = _toDouble(landVal);
                c.text = dv != null ? dv.toString() : '';
              });
              milletLandMode.value = 'per_type';
              _updateMilletLandTotal();
            }
          case 'date':
            _dateValues[key]!.value = DateTime.tryParse(raw.toString());
          case 'dropdown':
            _stringValues[key]!.value = raw.toString();
          case 'boolean':
            if (raw is bool) _boolValues[key]!.value = raw;
          case 'polygon':
            if (raw is Map && raw['type'] == 'Polygon') {
              final coords = raw['coordinates'] as List?;
              if (coords != null && coords.isNotEmpty) {
                final ring = coords[0] as List;
                _polygonValues[key]!.value = ring.map((pt) {
                  return [
                    (pt[0] as num).toDouble(),
                    (pt[1] as num).toDouble()
                  ];
                }).toList();
              }
            }
          case 'auto_calc':
            final v = _toDouble(raw);
            if (v != null) _autoCalcValues[key]!.value = v;
          case 'multiselect':
            if (raw is List) {
              _multiSelectValues[key]!.value =
                  raw.map((e) => e.toString()).toList();
            }
        }
      }
    }
  }

  // --- Submission ---

  Map<String, dynamic> _buildJson() {
    final map = <String, dynamic>{};
    for (final section in sections) {
      for (final field in section.fields) {
        final key = field.fieldKey;
        dynamic value;

        switch (field.inputType) {
          case 'text':
            final t = _textControllers[key]!.text;
            value = t.isNotEmpty ? t : null;
          case 'numeric':
          case 'currency':
          case 'acre':
            value = double.tryParse(_textControllers[key]!.text);
          case 'mobile':
            final t = _textControllers[key]!.text;
            value = t.isNotEmpty ? t : null;
          case 'aadhar':
            final raw = _textControllers[key]!.text.replaceAll(' ', '');
            value = raw.isNotEmpty ? raw : null;
          case 'date':
            final dt = _dateValues[key]!.value;
            value = dt != null
                ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
                : null;
          case 'dropdown':
            value = _stringValues[key]!.value;
          case 'boolean':
            value = _boolValues[key]!.value;
          case 'polygon':
            final points = _polygonValues[key]!.value;
            if (points != null && points.isNotEmpty) {
              value = {
                'type': 'Polygon',
                'coordinates': [points]
              };
            }
          case 'auto_calc':
            final v = _autoCalcValues[key]!.value;
            value = v != 0 ? v : null;
          case 'multiselect':
            final list = _multiSelectValues[key]!;
            value = list.isNotEmpty ? list.toList() : null;
          case 'millet_land_picker':
            final t = _textControllers[key]!.text;
            value = double.tryParse(t);
            if (milletLandMode.value == 'per_type' &&
                _milletLandControllers.isNotEmpty) {
              final areas = <String, dynamic>{};
              _milletLandControllers.forEach((k, c) {
                final v = double.tryParse(c.text);
                if (v != null && v > 0) areas[k] = v;
              });
              if (areas.isNotEmpty) map['millet_land_areas'] = areas;
            }
        }

        if (value != null) map[key] = value;
      }
    }
    // Attach location + start time (only on new submissions)
    if (!isEditMode) {
      if (_capturedLocation != null) {
        map['form_latitude'] = _capturedLocation!.latitude;
        map['form_longitude'] = _capturedLocation!.longitude;
        map['form_location_accuracy'] = _capturedLocation!.accuracy;
      }
      if (_formStartedAt != null) {
        map['form_started_at'] = _formStartedAt!.toIso8601String();
      }
    }

    return map;
  }

  Future<void> submit() async {
    final formState = formKey.currentState;
    if (formState != null && !formState.validate()) {
      Get.snackbar(
          'Validation', 'Please fill in the required fields on this step');
      return;
    }

    isSubmitting.value = true;
    try {
      final json = _buildJson();
      if (isEditMode) {
        await _surveyService.update(editId!, json);
      } else {
        await _surveyService.insert(json);
      }
      await clearDraft();
      if (Get.isRegistered<SurveyController>()) {
        Get.find<SurveyController>().loadSurveys();
      }
      isSubmitting.value = false;
      Get.back();
      Get.snackbar(
          'Success', isEditMode ? 'Survey updated' : 'Survey submitted');
    } catch (e) {
      isSubmitting.value = false;
      debugPrint('[FormController.submit] $e');
      Get.snackbar('Error', 'Failed to submit: $e');
    }
  }

  // --- Helpers ---

  String _formatAadhar(String raw) {
    final digits = raw.replaceAll(' ', '');
    if (digits.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _friendlyError(Object e) {
    if (e is PostgrestException && e.code == '525') {
      return 'Server is temporarily unavailable. Please try again in a moment.';
    }
    return 'Something went wrong. Please check your connection and try again.';
  }

  @override
  void onClose() {
    for (final ctrl in _textControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _milletLandControllers.values) {
      ctrl.dispose();
    }
    super.onClose();
  }
}
