import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../controllers/farm_controller.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../controllers/survey_controller.dart';
import '../config/offline_form_seed.dart';
import '../config/ui_strings.dart';
import '../models/form_config.dart';
import '../services/form_config_service.dart';
import '../services/location_service.dart';
import '../services/map_tile_cache_service.dart';
import '../services/offline_survey_queue_service.dart';
import '../services/secure_app_storage.dart';
import '../services/sheets_sync_service.dart';
import '../services/survey_service.dart';
import '../utils/polygon_geometry.dart';

const _incomeSourceOrder = [
  'farming',
  'private_job',
  'govt_job',
  'business',
  'other',
];

const _incomeSourceEnglishLabels = {
  'farming': 'Farming',
  'private_job': 'Private Job',
  'govt_job': 'Government Job',
  'business': 'Business',
  'other': 'Other',
};

class FormController extends GetxController {
  final _surveyService = SurveyService();
  final _configService = FormConfigService();
  final _sheetsSyncService = SheetsSyncService();
  final _locationService = LocationService();
  final _mapTileCacheService = MapTileCacheService();
  final _offlineQueueService = OfflineSurveyQueueService();
  final _secureStorage = SecureAppStorage();

  // Config state
  final sections = <FormSectionConfig>[].obs;
  final dropdownOptions = <String, List<String>>{}.obs;
  final dropdownOptionLabels = <String, Map<String, Map<String, String>>>{}.obs;
  final isConfigLoaded = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;

  // Form state
  final currentStep = 0.obs;
  final isSubmitting = false.obs;
  final formKey = GlobalKey<FormState>();
  final visitedSteps = <int>{0}.obs;

  String? editId;
  bool _suppressDraftSave = false;
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
  TextEditingController auxTextController(String key) =>
      _textControllers.putIfAbsent(key, () {
        final controller = TextEditingController();
        controller.addListener(saveDraft);
        return controller;
      });
  Rxn<bool> boolValue(String key) => _boolValues[key]!;
  Rxn<String> dropdownValue(String key) => _stringValues[key]!;
  Rxn<DateTime> dateValue(String key) => _dateValues[key]!;
  RxDouble autoCalcValue(String key) => _autoCalcValues[key]!;
  Rxn<List<List<double>>> polygonValue(String key) => _polygonValues[key]!;
  RxList<String> multiSelectValue(String key) =>
      _multiSelectValues[key] ?? <String>[].obs;

  LocationResult? get capturedLocation => _capturedLocation;
  Map<String, dynamic> toFlatJson() => _buildJson();

  final kharifRows = <Map<String, dynamic>>[].obs;
  final yearlyRows = <Map<String, dynamic>>[].obs;
  final practiceRows = <Map<String, dynamic>>[].obs;

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
    _textControllers['land_under_millet']?.text = total > 0
        ? total.toString()
        : '';
    milletLandTotal.value = total;
  }

  void clearMilletLandAreas() {
    for (final c in _milletLandControllers.values) {
      c.text = '';
    }
    milletLandTotal.value = 0.0;
  }

  dynamic valueFor(String key) {
    if (_boolValues.containsKey(key)) return _boolValues[key]!.value;
    if (_stringValues.containsKey(key)) return _stringValues[key]!.value;
    if (_textControllers.containsKey(key)) return _textControllers[key]!.text;
    if (_dateValues.containsKey(key)) return _dateValues[key]!.value;
    if (_polygonValues.containsKey(key)) return _polygonValues[key]!.value;
    if (_multiSelectValues.containsKey(key)) {
      return _multiSelectValues[key]!.toList();
    }
    if (_autoCalcValues.containsKey(key)) return _autoCalcValues[key]!.value;
    return null;
  }

  void setValue(String key, dynamic value) {
    if (_boolValues.containsKey(key)) {
      setBool(key, value == true || value.toString() == 'true');
    } else if (_stringValues.containsKey(key)) {
      setDropdown(key, value?.toString());
    } else if (_textControllers.containsKey(key)) {
      setText(key, value?.toString() ?? '');
    } else if (_dateValues.containsKey(key)) {
      if (value is DateTime) {
        setDate(key, value);
      } else {
        setDate(key, DateTime.tryParse(value?.toString() ?? ''));
      }
    } else if (_polygonValues.containsKey(key)) {
      if (value is List<List<double>>) setPolygon(key, value);
    } else if (_multiSelectValues.containsKey(key)) {
      if (value is List) {
        setMultiSelect(key, value.map((e) => e.toString()).toList());
      }
    }
    saveDraft();
  }

  void setText(String key, String value) {
    _textControllers[key]?.text = value;
    saveDraft();
  }

  void setBool(String key, bool? value) {
    _boolValues[key]?.value = value;
    saveDraft();
  }

  void setDropdown(String key, String? value) {
    _stringValues[key]?.value = value;
    saveDraft();
  }

  void clearAuxText(String key) {
    _textControllers[key]?.clear();
    saveDraft();
  }

  void setDate(String key, DateTime? value) {
    _dateValues[key]?.value = value;
    saveDraft();
  }

  void setPolygon(String key, List<List<double>>? value) {
    _polygonValues[key]?.value = value;
    saveDraft();
  }

  void setMultiSelect(String key, List<String> values) {
    _multiSelectValues[key]?.assignAll(values);
    saveDraft();
  }

  void setKharifRows(List<Map<String, dynamic>> rows) {
    kharifRows.assignAll(rows);
    saveDraft();
  }

  void setYearlyRows(List<Map<String, dynamic>> rows) {
    yearlyRows.assignAll(rows);
    saveDraft();
  }

  void setPracticeRows(List<Map<String, dynamic>> rows) {
    practiceRows.assignAll(rows);
    saveDraft();
  }

  @override
  void onInit() {
    super.onInit();
    ever(currentStep, (step) {
      visitedSteps.add(step);
      saveDraft();
    });
  }

  void prepareEdit(String id) {
    editId = id;
  }

  void startFreshSurvey() {
    final previousSuppressDraftSave = _suppressDraftSave;
    _suppressDraftSave = true;
    try {
      editId = null;
      currentStep.value = 0;
      visitedSteps
        ..clear()
        ..add(0);

      for (final controller in _textControllers.values) {
        controller.clear();
      }
      for (final value in _boolValues.values) {
        value.value = null;
      }
      for (final value in _stringValues.values) {
        value.value = null;
      }
      for (final value in _dateValues.values) {
        value.value = null;
      }
      for (final value in _autoCalcValues.values) {
        value.value = 0;
      }
      for (final value in _polygonValues.values) {
        value.value = null;
      }
      for (final value in _multiSelectValues.values) {
        value.clear();
      }

      kharifRows.clear();
      yearlyRows.clear();
      practiceRows.clear();

      milletLandMode.value = 'total';
      milletLandTotal.value = 0;
      for (final controller in _milletLandControllers.values) {
        controller.clear();
      }

      _capturedLocation = null;
      if (locationStatus.value != LocationStatus.fetching) {
        locationStatus.value = LocationStatus.idle;
      }
      _formStartedAt = DateTime.now().toUtc();
    } finally {
      _suppressDraftSave = previousSuppressDraftSave;
    }
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
        _configService.fetchDropdownOptionRows(),
      ]);
      final loadedSections = results[0] as List<FormSectionConfig>;
      final loadedOptions = Map<String, List<String>>.from(
        results[1] as Map<String, List<String>>,
      );
      final loadedOptionLabels = _buildOptionLabelMap(
        results[2] as List<Map<String, dynamic>>,
      );
      _normalizeIncomeSourceOptions(loadedOptions, loadedOptionLabels);
      _ensureDiseaseDropdownOptionsFallback(loadedOptions, loadedOptionLabels);

      sections.value = _ensureRequiredFormFieldsFallback(
        _ensureDiseaseSectionFallback(loadedSections),
      );
      dropdownOptions.value = loadedOptions;
      dropdownOptionLabels.value = loadedOptionLabels;
      _initializeFieldControllers();
      isConfigLoaded.value = true;
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
      unawaited(
        _mapTileCacheService.prefetchWideRegion(
          latitude: result.latitude,
          longitude: result.longitude,
        ),
      );
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
          case 'textarea':
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
          case 'polygon_pencil':
            _polygonValues[field.fieldKey] = Rxn<List<List<double>>>();
          case 'auto_calc':
            _autoCalcValues[field.fieldKey] = 0.0.obs;
          case 'multiselect':
            _multiSelectValues[field.fieldKey] = <String>[].obs;
        }
      }
    }
    if (_stringValues.containsKey('disease_name')) {
      auxTextController('disease_name_other');
    }
    if (_stringValues.containsKey('affected_crop')) {
      auxTextController('affected_crop_other');
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
      'subtract' =>
        values.isEmpty
            ? 0.0
            : values.length == 1
            ? values[0]
            : values.skip(1).fold(values[0], (a, b) => a - b),
      'sum_then_subtract_last' =>
        values.isEmpty
            ? 0.0
            : values.length == 1
            ? values[0]
            : values.take(values.length - 1).fold(0.0, (a, b) => a + b) -
                  values.last,
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
    } else if (_multiSelectValues.containsKey(dependsOn)) {
      currentValue = _multiSelectValues[dependsOn]!.toList();
    }

    return switch (operator) {
      'equals' => currentValue == expectedValue,
      'not_equals' => currentValue != expectedValue,
      'not_null' => currentValue != null,
      'contains_any' =>
        expectedValue is List &&
            ((currentValue is List &&
                    currentValue.any((v) => expectedValue.contains(v))) ||
                (currentValue != null && expectedValue.contains(currentValue))),
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
        case 'textarea':
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
        case 'polygon_pencil':
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
    if (isEditMode || _suppressDraftSave) return;
    try {
      final draft = <String, dynamic>{};
      for (final section in sections) {
        for (final field in section.fields) {
          final key = field.fieldKey;
          switch (field.inputType) {
            case 'text':
            case 'textarea':
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
            case 'polygon_pencil':
              final v = _polygonValues[key]?.value;
              if (v != null && v.isNotEmpty) draft[key] = v;
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
      if (kharifRows.isNotEmpty) draft['__kharif_rows'] = kharifRows.toList();
      if (yearlyRows.isNotEmpty) draft['__yearly_rows'] = yearlyRows.toList();
      if (practiceRows.isNotEmpty) {
        draft['__practice_rows'] = practiceRows.toList();
      }
      for (final key in const ['disease_name_other', 'affected_crop_other']) {
        final value = _textControllers[key]?.text.trim();
        if (value != null && value.isNotEmpty) draft[key] = value;
      }
      draft['__current_step'] = currentStep.value;
      final now = DateTime.now().toUtc();
      draft['__updated_at'] = now.toIso8601String();
      draft['__expires_at'] = now.add(_draftRetention).toIso8601String();

      await _secureStorage.writeString(_draftKey, jsonEncode(draft));
    } catch (e) {
      debugPrint('[FormController.saveDraft] $e');
    }
  }

  Future<bool> hasDraft() async {
    try {
      final raw = await _secureStorage.readString(_draftKey);
      if (raw == null) return false;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      if (_isExpired(draft['__expires_at'])) {
        await clearDraft(suppressAutosave: true);
        return false;
      }
      // Check if there's any real data (not just metadata keys)
      final dataKeys = draft.keys.where((k) => !k.startsWith('__')).toList();
      if (dataKeys.isNotEmpty) return true;
      final step = draft['__current_step'];
      if (step is int && step > 0) return true;
      return draft['__kharif_rows'] is List ||
          draft['__yearly_rows'] is List ||
          draft['__practice_rows'] is List ||
          draft['__millet_land_areas'] is Map;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadDraft() async {
    try {
      final raw = await _secureStorage.readString(_draftKey);
      if (raw == null) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      if (_isExpired(draft['__expires_at'])) {
        await clearDraft(suppressAutosave: true);
        return;
      }
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

      final kharif = draft['__kharif_rows'];
      if (kharif is List) {
        kharifRows.assignAll(
          kharif.cast<Map>().map((row) => row.cast<String, dynamic>()),
        );
      }
      final yearly = draft['__yearly_rows'];
      if (yearly is List) {
        yearlyRows.assignAll(
          yearly.cast<Map>().map((row) => row.cast<String, dynamic>()),
        );
      }
      final practices = draft['__practice_rows'];
      if (practices is List) {
        practiceRows.assignAll(
          practices.cast<Map>().map((row) => row.cast<String, dynamic>()),
        );
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

  Future<void> clearDraft({bool suppressAutosave = false}) async {
    try {
      if (suppressAutosave) _suppressDraftSave = true;
      await _secureStorage.remove(_draftKey);
    } catch (_) {
    } finally {
      if (suppressAutosave) _suppressDraftSave = false;
    }
  }

  // --- Edit mode ---

  Future<void> loadSurvey(String id) async {
    try {
      editId = id;
      final data = await _surveyService.fetchEditableById(id);
      _populateFromJson(data);
      kharifRows.assignAll(_rowList(data[SurveyService.kharifRowsKey]));
      yearlyRows.assignAll(_rowList(data[SurveyService.yearlyRowsKey]));
      practiceRows.assignAll(_rowList(data[SurveyService.practiceRowsKey]));
      visitedSteps.addAll(List.generate(totalSteps, (i) => i).toSet());
    } catch (e, st) {
      debugPrint('[FormController.loadSurvey] $e\n$st');
      Get.snackbar('Could not open survey', _surveyLoadError(e));
    }
  }

  void _populateFromJson(Map<String, dynamic> json) {
    final source = Map<String, dynamic>.from(json);
    final extra = json['extra_details'];
    if (extra is Map) {
      extra.forEach(
        (key, value) => source.putIfAbsent(key.toString(), () => value),
      );
      final croppingPattern = extra['cropping_pattern'];
      if (croppingPattern is Map) {
        final disease = croppingPattern['disease'];
        if (disease is Map) {
          disease.forEach(
            (key, value) => source.putIfAbsent(key.toString(), () => value),
          );
        }
      }
    }
    for (final section in sections) {
      for (final field in section.fields) {
        final key = field.fieldKey;
        final raw = source[key];
        if (raw == null) continue;

        switch (field.inputType) {
          case 'text':
          case 'textarea':
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
            final areas = source['millet_land_areas'];
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
            _setDropdownFromStoredValue(field, raw.toString(), source);
          case 'boolean':
            if (raw is bool) _boolValues[key]!.value = raw;
          case 'polygon':
          case 'polygon_pencil':
            if (raw is Map && raw['type'] == 'Polygon') {
              final coords = raw['coordinates'] as List?;
              if (coords != null && coords.isNotEmpty) {
                final ring = coords[0] as List;
                _polygonValues[key]!.value = ring.map((pt) {
                  return [(pt[0] as num).toDouble(), (pt[1] as num).toDouble()];
                }).toList();
              }
            }
          case 'auto_calc':
            final v = _toDouble(raw);
            if (v != null) _autoCalcValues[key]!.value = v;
          case 'multiselect':
            if (raw is List) {
              _multiSelectValues[key]!.value = raw
                  .map((e) => e.toString())
                  .toList();
            }
        }
      }
    }
  }

  // --- Submission ---

  void _setDropdownFromStoredValue(
    FormFieldConfig field,
    String value,
    Map<String, dynamic> source,
  ) {
    if (field.fieldKey == 'disease_name') {
      _setDropdownOrOther(
        field.fieldKey,
        value,
        field.dropdownOptionsKey,
        'disease_name_other',
        source,
      );
      return;
    }
    if (field.fieldKey == 'affected_crop') {
      _setDropdownOrOther(
        field.fieldKey,
        value,
        'affected_crop_fallback',
        'affected_crop_other',
        source,
        extraOptions: affectedCropOptions,
      );
      return;
    }
    _stringValues[field.fieldKey]!.value = value;
  }

  void _setDropdownOrOther(
    String key,
    String value,
    String? optionKey,
    String otherKey,
    Map<String, dynamic> source, {
    List<String> extraOptions = const [],
  }) {
    final options = <String>{
      ...(dropdownOptions[optionKey] ?? const <String>[]),
      ...extraOptions,
    };
    final storedOther = source[otherKey]?.toString().trim();
    if (value == 'Other') {
      _stringValues[key]!.value = 'Other';
      if (storedOther != null && storedOther.isNotEmpty) {
        auxTextController(otherKey).text = storedOther;
      }
      return;
    }
    if (options.contains(value) || value.trim().isEmpty) {
      _stringValues[key]!.value = value.trim().isEmpty ? null : value;
      return;
    }
    _stringValues[key]!.value = 'Other';
    auxTextController(otherKey).text = value;
  }

  Map<String, dynamic> _buildJson() {
    final map = <String, dynamic>{};
    final extraDetails = <String, dynamic>{};
    for (final section in sections) {
      for (final field in section.fields) {
        if (!isFieldVisible(field)) continue;
        final key = field.fieldKey;
        dynamic value;

        switch (field.inputType) {
          case 'text':
          case 'textarea':
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
          case 'polygon_pencil':
            final points = _polygonValues[key]!.value;
            if (points != null && points.isNotEmpty) {
              value = {
                'type': 'Polygon',
                'coordinates': [points],
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
              if (areas.isNotEmpty) extraDetails['millet_land_areas'] = areas;
            }
        }

        if (value != null) {
          if (_parentExtraDetailKeys.contains(key)) {
            extraDetails[key] = value;
          }
          map[key] = value;
        }
      }
    }

    final diseasePayload = _buildDiseasePayload();
    if (diseasePayload.isNotEmpty) {
      map.addAll(diseasePayload);
    }

    map['total_cultivation_cost'] =
        _toDouble(map['total_cultivation_cost']) ?? 0.0;

    if (extraDetails.isNotEmpty) map['extra_details'] = extraDetails;
    // Attach location + start time (only on new submissions)
    if (!isEditMode) {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        map['user_id'] = currentUser.id;
      }
      if (Get.isRegistered<LanguageController>()) {
        map['language'] = Get.find<LanguageController>().language.value;
      }
      if (_capturedLocation != null) {
        map['location_lat'] = _capturedLocation!.latitude;
        map['location_lng'] = _capturedLocation!.longitude;
        map['location_accuracy_m'] = _capturedLocation!.accuracy;
      }
      if (_formStartedAt != null) {
        map['started_at'] = _formStartedAt!.toIso8601String();
      }
      map['submitted_at'] = DateTime.now().toUtc().toIso8601String();
    }

    return map;
  }

  Map<String, dynamic> _buildDiseasePayload() {
    final hasDiseaseConfig =
        _boolValues.containsKey('disease_present') ||
        _textControllers.containsKey('disease_name') ||
        _stringValues.containsKey('disease_name') ||
        _stringValues.containsKey('affected_crop') ||
        _stringValues.containsKey('disease_severity');
    if (!hasDiseaseConfig) return const {};

    final present = _boolValues['disease_present']?.value;
    final diseaseName = _fieldTextOrDropdown(
      'disease_name',
      otherKey: 'disease_name_other',
    );
    final affectedCrop = _fieldTextOrDropdown(
      'affected_crop',
      otherKey: 'affected_crop_other',
    );
    final severity = _stringValues['disease_severity']?.value;
    final symptoms = _cleanText('symptoms_observed');
    final treatment = _cleanText('treatment_taken');
    final hasAnyAnswer =
        present != null ||
        diseaseName != null ||
        affectedCrop != null ||
        severity != null ||
        symptoms != null ||
        treatment != null;
    if (!hasAnyAnswer) return const {};

    final includeDetails = present == true;
    return {
      'disease_present': present,
      'disease_name': includeDetails ? diseaseName : null,
      'affected_crop': includeDetails ? affectedCrop : null,
      'disease_severity': includeDetails ? severity : null,
      'symptoms_observed': includeDetails ? symptoms : null,
      'treatment_taken': includeDetails ? treatment : null,
    };
  }

  Future<bool> submit({bool popOnSuccess = true}) async {
    final formState = formKey.currentState;
    if (formState != null && !formState.validate()) {
      Get.snackbar(
        'Validation',
        'Please fill in the required fields on this step',
      );
      return false;
    }

    final invalidStep = _firstInvalidStep();
    if (invalidStep != null) {
      currentStep.value = invalidStep;
      Get.snackbar(
        'Validation',
        'Please fill in all required fields before submitting',
      );
      return false;
    }

    final authCtrl = Get.isRegistered<MainAuthController>()
        ? Get.find<MainAuthController>()
        : null;
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    final hasSignedInUser =
        authCtrl?.isAuthenticated ??
        (supabaseUser != null && !supabaseUser.isAnonymous);
    if (!isEditMode && !hasSignedInUser) {
      Get.snackbar(
        'Sign in required',
        'Please sign in before submitting a survey',
      );
      Get.toNamed('/login');
      return false;
    }

    isSubmitting.value = true;
    try {
      final isOnline = await _offlineQueueService.isOnline();
      final json = _buildJson();
      if (!isEditMode) {
        json['client_uuid'] =
            json['client_uuid']?.toString().trim().isNotEmpty == true
            ? json['client_uuid']
            : const Uuid().v4();
      }
      final kharif = kharifRows.toList();
      final yearly = yearlyRows.toList();
      final practices = practiceRows.toList();

      if (isEditMode && !isOnline) {
        isSubmitting.value = false;
        Get.snackbar(
          'Offline',
          'Editing an existing survey needs internet. Please try again when online.',
        );
        return false;
      }

      if (!isEditMode && !isOnline) {
        await _queueOfflineSubmission(json, kharif, yearly, practices);
        isSubmitting.value = false;
        if (popOnSuccess) Get.back();
        Get.snackbar(
          'Saved offline',
          'Survey saved on this device and will sync when internet returns.',
        );
        return true;
      }

      String? syncedSurveyId;
      try {
        if (isEditMode) {
          await _surveyService.updateWithChildren(
            editId!,
            json,
            kharif,
            yearly,
            practices,
          );
        } else {
          syncedSurveyId = await _surveyService.insertWithChildren(
            json,
            kharif,
            yearly,
            practices,
          );
        }
      } catch (e) {
        if (!isEditMode && _offlineQueueService.shouldQueueAfterError(e)) {
          await _queueOfflineSubmission(json, kharif, yearly, practices);
          isSubmitting.value = false;
          if (popOnSuccess) Get.back();
          Get.snackbar(
            'Saved offline',
            'Survey saved on this device and will sync when internet returns.',
          );
          return true;
        }
        rethrow;
      }

      await clearDraft(suppressAutosave: true);
      if (Get.isRegistered<SurveyController>()) {
        Get.find<SurveyController>().loadSurveys();
      }
      if (!isEditMode) {
        await _syncSubmittedSurveyToFarmerFarm(json, syncedSurveyId);
      }

      // Sync to Google Sheets in background (fire-and-forget)
      final sheetPayload = Map<String, dynamic>.from(json);
      _attachSheetChildSummaries(sheetPayload, kharif, yearly, practices);
      if (isEditMode) {
        sheetPayload['_id'] = editId;
      } else if (syncedSurveyId != null) {
        sheetPayload['_id'] = syncedSurveyId;
      }
      _sheetsSyncService.syncToSheet(sheetPayload);

      isSubmitting.value = false;
      if (popOnSuccess) {
        Get.back();
      }
      Get.snackbar(
        'Success',
        isEditMode ? 'Survey updated' : 'Survey submitted',
      );
      return true;
    } catch (e) {
      isSubmitting.value = false;
      debugPrint('[FormController.submit] $e');
      Get.snackbar('Error', 'Failed to submit: $e');
      return false;
    }
  }

  Future<void> _syncSubmittedSurveyToFarmerFarm(
    Map<String, dynamic> survey,
    String? surveyId,
  ) async {
    if (!Get.isRegistered<MainAuthController>()) return;
    final verifiedFarmer = Get.find<MainAuthController>().verifiedFarmer.value;
    if (verifiedFarmer == null) return;

    final points = _farmPolygonPoints(survey['farm_polygon']);
    if (points.length < 3) return;

    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : Get.put(FarmController());
    final farmerName = _stringValue(survey['farmer_name']).isNotEmpty
        ? _stringValue(survey['farmer_name'])
        : verifiedFarmer.farmerName;
    final village = _stringValue(survey['village']);
    final crop = _surveyCrop(survey);
    final farmName = [
      if (farmerName.isNotEmpty) farmerName,
      if (crop.isNotEmpty) crop,
      if (village.isNotEmpty) village,
    ].join(' - ');

    final saved = await farmCtrl.saveFarmRecord(
      name: farmName.isEmpty ? 'Recorded farm' : farmName,
      points: points,
      showSnackbars: false,
      waitForRemoteConfirmation: true,
      metadata: {
        if (crop.isNotEmpty) 'crop': crop,
        if (surveyId != null && surveyId.trim().isNotEmpty)
          'survey_id': surveyId.trim(),
        if (village.isNotEmpty) 'village': village,
        if (_stringValue(survey['main_crop_land_acre']).isNotEmpty)
          'main_crop_land_acre': survey['main_crop_land_acre'],
        if (_stringValue(survey['total_land_area_acre']).isNotEmpty)
          'total_land_area_acre': survey['total_land_area_acre'],
      },
    );
    if (saved != null) {
      await farmCtrl.loadFarms(forceRefresh: true, preferredFarmId: saved.id);
    } else if (farmCtrl.lastSaveErrorMessage.value.trim().isNotEmpty) {
      Get.snackbar(
        UiStrings.t('could_not_save_farm'),
        farmCtrl.lastSaveErrorMessage.value,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  List<LatLng> _farmPolygonPoints(dynamic polygon) {
    if (polygon is! Map) return const [];
    final coordinates = polygon['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return const [];
    final ring = coordinates.first;
    if (ring is! List) return const [];
    final points = <List<double>>[];
    for (final point in ring) {
      if (point is! List || point.length < 2) continue;
      final lng = _toDouble(point[0]);
      final lat = _toDouble(point[1]);
      if (lat == null || lng == null) continue;
      points.add([lng, lat]);
    }
    if (points.length < 3) return const [];
    return PolygonGeometry.fromGeoJsonRing(points);
  }

  String _surveyCrop(Map<String, dynamic> survey) {
    final mainCrop = _stringValue(survey['main_crop']);
    if (mainCrop == 'other') return _stringValue(survey['main_crop_other']);
    if (mainCrop.isEmpty) return '';
    return localizedOptionLabel('main_crop_v2', mainCrop);
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  void _attachSheetChildSummaries(
    Map<String, dynamic> sheetPayload,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) {
    sheetPayload['kharif_crop_production_units'] = kharif
        .where((row) => row['production_qty'] != null)
        .map((row) {
          final crop = row['crop_name']?.toString() ?? '';
          final value = row['production_qty']?.toString() ?? '';
          final unit = row['production_qty_unit']?.toString() ?? '';
          final prefix = crop.isEmpty ? '' : '$crop: ';
          return '$prefix$value${unit.isEmpty ? '' : ' $unit'}';
        })
        .join('; ');

    String yearlySummary(String valueKey, String unitKey) {
      return yearly
          .where((row) => row[valueKey] != null)
          .map((row) {
            final year = row['year']?.toString() ?? '';
            final value = row[valueKey]?.toString() ?? '';
            final unit = row[unitKey]?.toString() ?? '';
            final prefix = year.isEmpty ? '' : '$year: ';
            return '$prefix$value${unit.isEmpty ? '' : ' $unit'}';
          })
          .join('; ');
    }

    sheetPayload['main_crop_yearly_total_production_units'] = yearlySummary(
      'total_production',
      'total_production_unit',
    );
    sheetPayload['main_crop_yearly_yield_avg_per_acre_units'] = yearlySummary(
      'yield_avg_per_acre',
      'yield_avg_per_acre_unit',
    );
    sheetPayload['main_crop_yearly_home_consumption_units'] = yearlySummary(
      'home_consumption',
      'home_consumption_unit',
    );
    sheetPayload['main_crop_yearly_quantity_sold_units'] = yearlySummary(
      'quantity_sold',
      'quantity_sold_unit',
    );
    sheetPayload['main_crop_yearly_sold_where'] = yearly
        .where((row) => row['sold_where'] != null)
        .map((row) => '${row['year']}: ${row['sold_where']}')
        .join('; ');
    sheetPayload['main_crop_yearly_sold_where_other'] = yearly
        .where((row) => row['sold_where_other'] != null)
        .map((row) => '${row['year']}: ${row['sold_where_other']}')
        .join('; ');
    sheetPayload['crop_practice_spray_units'] = practices
        .map(_sprayUnitSummary)
        .where((value) => value.isNotEmpty)
        .join('; ');
  }

  String _sprayUnitSummary(Map<String, dynamic> row) {
    final role = row['crop_role']?.toString() ?? 'crop';
    final parts = <String>[];
    void addPart(String label, String valueKey, String unitKey) {
      final value = row[valueKey];
      if (value == null) return;
      final unit = row[unitKey]?.toString() ?? '';
      parts.add('$label $value${unit.isEmpty ? '' : ' $unit'}');
    }

    addPart('Matka', 'matka_per_acre', 'matka_per_acre_unit');
    addPart('Neem', 'neem_per_acre', 'neem_per_acre_unit');
    addPart('Jeevamrut', 'jeevamrut_per_acre', 'jeevamrut_per_acre_unit');
    addPart('Pesticide', 'pesticide_per_acre', 'pesticide_per_acre_unit');
    return parts.isEmpty ? '' : '$role: ${parts.join(', ')}';
  }

  Future<void> _queueOfflineSubmission(
    Map<String, dynamic> parent,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) async {
    parent['total_cultivation_cost'] =
        _toDouble(parent['total_cultivation_cost']) ?? 0.0;
    await _offlineQueueService.enqueue(
      parent: parent,
      kharifRows: kharif,
      yearlyRows: yearly,
      practiceRows: practices,
    );
    await clearDraft(suppressAutosave: true);
    if (Get.isRegistered<SurveyController>()) {
      await Get.find<SurveyController>().loadPendingSubmissions();
    }
  }

  // --- Helpers ---

  int? _firstInvalidStep() {
    for (var i = 0; i < sections.length; i++) {
      for (final field in sections[i].fields) {
        if (!isFieldVisible(field)) continue;
        if (field.isRequired && !_hasFieldValue(field)) return i;
        if (_fieldValidationError(field) != null) return i;
      }
    }
    return null;
  }

  bool _hasFieldValue(FormFieldConfig field) {
    final key = field.fieldKey;
    return switch (field.inputType) {
      'text' ||
      'textarea' ||
      'numeric' ||
      'mobile' ||
      'aadhar' ||
      'currency' ||
      'acre' ||
      'millet_land_picker' =>
        (_textControllers[key]?.text.trim().isNotEmpty ?? false),
      'dropdown' => _stringValues[key]?.value?.isNotEmpty ?? false,
      'boolean' => _boolValues[key]?.value != null,
      'date' => _dateValues[key]?.value != null,
      'polygon' ||
      'polygon_pencil' => _polygonValues[key]?.value?.isNotEmpty ?? false,
      'auto_calc' => _autoCalcValues[key]?.value != 0,
      'multiselect' => _multiSelectValues[key]?.isNotEmpty ?? false,
      _ => true,
    };
  }

  String localizedOptionLabel(String? optionKey, String value) {
    final labels = dropdownOptionLabels[optionKey]?[value];
    if (labels == null) return value;

    var languageCode = 'en';
    if (Get.isRegistered<LanguageController>()) {
      languageCode = Get.find<LanguageController>().language.value;
    }

    return switch (languageCode) {
      'hi' =>
        labels['hi']?.isNotEmpty == true
            ? labels['hi']!
            : labels['en'] ?? value,
      'mr' =>
        labels['mr']?.isNotEmpty == true
            ? labels['mr']!
            : labels['en'] ?? value,
      _ => labels['en']?.isNotEmpty == true ? labels['en']! : value,
    };
  }

  List<String> get affectedCropOptions {
    final values = <String>[];
    void add(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty || values.contains(text)) return;
      values.add(text);
    }

    add(_stringValues['main_crop']?.value);
    for (final row in kharifRows) {
      add(row['crop_name']?.toString());
    }
    for (final value in _affectedCropFallbackValues) {
      add(value);
    }
    return values;
  }

  String affectedCropLabel(String value) {
    if (value == 'Other') {
      return localizedOptionLabel('affected_crop_fallback', value);
    }
    final labels = dropdownOptionLabels['affected_crop_fallback']?[value];
    if (labels != null) {
      return localizedOptionLabel('affected_crop_fallback', value);
    }
    return localizedOptionLabel('main_crop_v2', value);
  }

  void _normalizeIncomeSourceOptions(
    Map<String, List<String>> options,
    Map<String, Map<String, Map<String, String>>> labels,
  ) {
    final current = options['income_sources_v2'];
    if (current == null) return;

    options['income_sources_v2'] = [
      for (final value in _incomeSourceOrder)
        if (current.contains(value)) value,
      for (final value in current)
        if (!_incomeSourceOrder.contains(value)) value,
    ];

    final incomeLabels = labels['income_sources_v2'];
    if (incomeLabels == null) return;
    for (final entry in _incomeSourceEnglishLabels.entries) {
      incomeLabels.putIfAbsent(entry.key, () => <String, String>{})['en'] =
          entry.value;
    }
  }

  List<FormSectionConfig> _ensureDiseaseSectionFallback(
    List<FormSectionConfig> loadedSections,
  ) {
    final sections = [...loadedSections];
    final fallbackFields = _buildDiseaseFallbackFields();
    final diseaseIndex = sections.indexWhere((s) => s.title == 'Disease');
    final diseaseSortOrder =
        sections.where((section) => section.title != 'Disease').fold<int>(0, (
          max,
          section,
        ) {
          return section.sortOrder > max ? section.sortOrder : max;
        }) +
        10;

    if (diseaseIndex == -1) {
      sections.add(
        FormSectionConfig(
          id: '__disease_section',
          sortOrder: diseaseSortOrder,
          title: 'Disease',
          titleHi: 'रोग',
          titleMr: 'रोग',
          iconName: 'eco_outlined',
          fields: fallbackFields,
        ),
      );
    } else {
      final existing = sections[diseaseIndex];
      final existingByKey = {
        for (final field in existing.fields) field.fieldKey: field,
      };
      final repairedFields = [
        for (final fallback in fallbackFields)
          _mergeDiseaseField(existingByKey[fallback.fieldKey], fallback),
        for (final field in existing.fields)
          if (!_diseaseFieldKeys.contains(field.fieldKey)) field,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      sections[diseaseIndex] = FormSectionConfig(
        id: existing.id,
        sortOrder: diseaseSortOrder,
        title: 'Disease',
        titleHi: 'रोग',
        titleMr: 'रोग',
        iconName: 'eco_outlined',
        fields: repairedFields,
      );
    }

    sections.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sections;
  }

  List<FormSectionConfig> _ensureRequiredFormFieldsFallback(
    List<FormSectionConfig> loadedSections,
  ) {
    final sections = [...loadedSections];
    final fallbackIncome = OfflineFormSeed.sections().firstWhereOrNull(
      (section) => section.title == 'Income & Food Products',
    );
    if (fallbackIncome == null) return sections;

    final incomeIndex = sections.indexWhere(
      (section) => section.title == 'Income & Food Products',
    );
    if (incomeIndex == -1) {
      sections.add(fallbackIncome);
      sections.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return sections;
    }

    final existing = sections[incomeIndex];
    final fallbackByKey = {
      for (final field in fallbackIncome.fields) field.fieldKey: field,
    };
    final existingByKey = {
      for (final field in existing.fields) field.fieldKey: field,
    };

    final repairedFields = [
      for (final field in existing.fields)
        field.fieldKey == 'total_cultivation_cost'
            ? _mergeFormField(
                field,
                fallbackByKey['total_cultivation_cost'] ?? field,
              )
            : field.fieldKey == 'total_annual_income'
            ? _mergeFormField(
                field,
                fallbackByKey['total_annual_income'] ?? field,
              )
            : field,
      if (!existingByKey.containsKey('total_cultivation_cost') &&
          fallbackByKey['total_cultivation_cost'] != null)
        fallbackByKey['total_cultivation_cost']!,
      if (!existingByKey.containsKey('total_annual_income') &&
          fallbackByKey['total_annual_income'] != null)
        fallbackByKey['total_annual_income']!,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    sections[incomeIndex] = FormSectionConfig(
      id: existing.id,
      sortOrder: existing.sortOrder,
      title: existing.title,
      titleHi: existing.titleHi,
      titleMr: existing.titleMr,
      iconName: existing.iconName,
      fields: repairedFields,
    );
    return sections;
  }

  FormFieldConfig _mergeFormField(
    FormFieldConfig existing,
    FormFieldConfig fallback,
  ) {
    return FormFieldConfig(
      id: existing.id,
      fieldKey: existing.fieldKey,
      label: fallback.label,
      inputType: fallback.inputType,
      sortOrder: fallback.sortOrder,
      isRequired: fallback.isRequired,
      validation: fallback.validation,
      visibilityRule: fallback.visibilityRule,
      autoCalcFormula: fallback.autoCalcFormula,
      dropdownOptionsKey: fallback.dropdownOptionsKey,
      hintText: fallback.hintText,
      labelHi: fallback.labelHi,
      labelMr: fallback.labelMr,
      hintTextHi: fallback.hintTextHi,
      hintTextMr: fallback.hintTextMr,
      suffixText: fallback.suffixText,
      cropRole: fallback.cropRole,
      repeatGroup: fallback.repeatGroup,
    );
  }

  List<FormFieldConfig> _buildDiseaseFallbackFields() {
    const visibleWhenDiseasePresent = <String, dynamic>{
      'depends_on': 'disease_present',
      'operator': 'equals',
      'value': true,
    };

    return [
      FormFieldConfig(
        id: '__disease_present',
        fieldKey: 'disease_present',
        label: 'Any Disease Observed?',
        inputType: 'boolean',
        sortOrder: 1,
        isRequired: false,
        validation: const {},
        labelHi: 'क्या कोई रोग दिखाई दिया?',
        labelMr: 'कोणताही रोग दिसला का?',
      ),
      FormFieldConfig(
        id: '__disease_name',
        fieldKey: 'disease_name',
        label: 'Disease Name',
        inputType: 'dropdown',
        sortOrder: 3,
        isRequired: false,
        validation: const {},
        visibilityRule: visibleWhenDiseasePresent,
        dropdownOptionsKey: 'disease_name_common',
        hintText: 'Select disease name',
        labelHi: 'रोग का नाम',
        labelMr: 'रोगाचे नाव',
      ),
      FormFieldConfig(
        id: '__affected_crop',
        fieldKey: 'affected_crop',
        label: 'Crop affected',
        inputType: 'dropdown',
        sortOrder: 2,
        isRequired: false,
        validation: const {},
        visibilityRule: visibleWhenDiseasePresent,
        dropdownOptionsKey: 'affected_crop_fallback',
        hintText: 'Select affected crop',
        labelHi: 'प्रभावित फसल',
        labelMr: 'बाधित पीक',
      ),
      FormFieldConfig(
        id: '__disease_severity',
        fieldKey: 'disease_severity',
        label: 'Disease Severity',
        inputType: 'dropdown',
        sortOrder: 4,
        isRequired: false,
        validation: const {},
        visibilityRule: visibleWhenDiseasePresent,
        dropdownOptionsKey: 'disease_severity',
        labelHi: 'रोग की गंभीरता',
        labelMr: 'रोगाची तीव्रता',
      ),
      FormFieldConfig(
        id: '__symptoms_observed',
        fieldKey: 'symptoms_observed',
        label: 'Symptoms Observed',
        inputType: 'textarea',
        sortOrder: 5,
        isRequired: false,
        validation: const {},
        visibilityRule: visibleWhenDiseasePresent,
        hintText: 'Write key symptoms',
        labelHi: 'देखे गए लक्षण',
        labelMr: 'दिसलेली लक्षणे',
      ),
      FormFieldConfig(
        id: '__treatment_taken',
        fieldKey: 'treatment_taken',
        label: 'Treatment Taken',
        inputType: 'textarea',
        sortOrder: 6,
        isRequired: false,
        validation: const {},
        visibilityRule: visibleWhenDiseasePresent,
        hintText: 'Fungicide, biocontrol, etc.',
        labelHi: 'किया गया उपचार',
        labelMr: 'केलेली उपाययोजना',
      ),
    ];
  }

  FormFieldConfig _mergeDiseaseField(
    FormFieldConfig? existing,
    FormFieldConfig fallback,
  ) {
    if (existing == null) return fallback;
    return FormFieldConfig(
      id: existing.id,
      fieldKey: fallback.fieldKey,
      label: fallback.label,
      inputType: fallback.inputType,
      sortOrder: fallback.sortOrder,
      isRequired: fallback.isRequired,
      validation: fallback.validation,
      visibilityRule: fallback.visibilityRule,
      autoCalcFormula: fallback.autoCalcFormula,
      dropdownOptionsKey: fallback.dropdownOptionsKey,
      hintText: fallback.hintText,
      labelHi: fallback.labelHi,
      labelMr: fallback.labelMr,
      hintTextHi: fallback.hintTextHi,
      hintTextMr: fallback.hintTextMr,
      suffixText: fallback.suffixText,
      cropRole: fallback.cropRole,
      repeatGroup: fallback.repeatGroup,
    );
  }

  void _ensureDiseaseDropdownOptionsFallback(
    Map<String, List<String>> options,
    Map<String, Map<String, Map<String, String>>> labels,
  ) {
    final values = options.putIfAbsent('disease_severity', () => <String>[]);
    for (final value in _diseaseSeverityValues) {
      if (!values.contains(value)) values.add(value);
    }

    final severityLabels = labels.putIfAbsent('disease_severity', () => {});
    for (final entry in _diseaseSeverityLabels.entries) {
      severityLabels.putIfAbsent(entry.key, () => entry.value);
    }

    _ensureOptionValues(
      options,
      labels,
      'disease_name_common',
      _diseaseNameValues,
      _diseaseNameLabels,
    );
    _ensureOptionValues(
      options,
      labels,
      'affected_crop_fallback',
      _affectedCropFallbackValues,
      _affectedCropFallbackLabels,
    );
  }

  void _ensureOptionValues(
    Map<String, List<String>> options,
    Map<String, Map<String, Map<String, String>>> labels,
    String optionKey,
    List<String> valuesToAdd,
    Map<String, Map<String, String>> labelsToAdd,
  ) {
    final values = options.putIfAbsent(optionKey, () => <String>[]);
    for (final value in valuesToAdd) {
      if (!values.contains(value)) values.add(value);
    }
    final optionLabels = labels.putIfAbsent(optionKey, () => {});
    for (final entry in labelsToAdd.entries) {
      final current = optionLabels.putIfAbsent(entry.key, () => entry.value);
      for (final localized in entry.value.entries) {
        if ((current[localized.key] ?? '').isEmpty) {
          current[localized.key] = localized.value;
        }
      }
    }
  }

  Map<String, Map<String, Map<String, String>>> _buildOptionLabelMap(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, Map<String, Map<String, String>>>{};
    for (final row in rows) {
      final key = row['option_key']?.toString();
      final value = row['value']?.toString();
      if (key == null || value == null) continue;
      map.putIfAbsent(key, () => {})[value] = {
        'en': row['label']?.toString() ?? value,
        'hi': row['label_hi']?.toString() ?? '',
        'mr': row['label_mr']?.toString() ?? '',
      };
    }
    return map;
  }

  String? _fieldValidationError(FormFieldConfig field) {
    final value = valueFor(field.fieldKey);
    if (value == null) return null;

    final text = switch (field.inputType) {
      'mobile' => value.toString().trim(),
      'aadhar' => value.toString().replaceAll(' ', '').trim(),
      'text' || 'textarea' => value.toString().trim(),
      _ => '',
    };
    if (text.isEmpty) return null;

    if (field.inputType == 'mobile' && !RegExp(r'^[0-9]{10}$').hasMatch(text)) {
      return 'Enter a 10 digit mobile number';
    }
    if (field.inputType == 'aadhar' && !RegExp(r'^[0-9]{12}$').hasMatch(text)) {
      return 'Enter a 12 digit Aadhaar number';
    }
    if ((field.inputType == 'text' || field.inputType == 'textarea') &&
        field.validation.containsKey('min_length')) {
      final minLength = field.validation['min_length'] as int;
      if (text.length < minLength) return 'Minimum $minLength characters';
    }
    if ((field.inputType == 'text' || field.inputType == 'textarea') &&
        field.validation.containsKey('max_length')) {
      final maxLength = field.validation['max_length'] as int;
      if (text.length > maxLength) return 'Maximum $maxLength characters';
    }
    if (field.validation.containsKey('regex')) {
      final regex = RegExp(field.validation['regex'] as String);
      if (!regex.hasMatch(text)) {
        return (field.validation['regex_message'] as String?) ??
            'Invalid format';
      }
    }
    return null;
  }

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

  String? _cleanText(String key) {
    final value = _textControllers[key]?.text.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _fieldTextOrDropdown(String key, {String? otherKey}) {
    if (_stringValues.containsKey(key)) {
      final value = _stringValues[key]?.value?.trim();
      if (value == null || value.isEmpty) return null;
      if (value == 'Other' && otherKey != null) return _cleanText(otherKey);
      return value;
    }
    return _cleanText(key);
  }

  static List<Map<String, dynamic>> _rowList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static String _surveyLoadError(Object e) {
    if (e is PostgrestException && e.code == 'PGRST116') {
      return 'This survey is not available for this login session. Refresh the list and try again.';
    }
    return _friendlyError(e);
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

const _parentExtraDetailKeys = <String>{};

const _draftKey = 'form_draft';
const _draftRetention = Duration(days: 7);

bool _isExpired(Object? raw) {
  final expiresAt = DateTime.tryParse(raw?.toString() ?? '');
  return expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt);
}

const _diseaseFieldKeys = {
  'disease_present',
  'disease_name',
  'affected_crop',
  'disease_severity',
  'symptoms_observed',
  'treatment_taken',
};

const _diseaseSeverityValues = ['Mild', 'Moderate', 'Severe'];

const _diseaseSeverityLabels = {
  'Mild': {'en': 'Mild', 'hi': 'हल्का', 'mr': 'सौम्य'},
  'Moderate': {'en': 'Moderate', 'hi': 'मध्यम', 'mr': 'मध्यम'},
  'Severe': {'en': 'Severe', 'hi': 'गंभीर', 'mr': 'गंभीर'},
};

const _diseaseNameValues = [
  'Blast',
  'Leaf blast',
  'Neck blast',
  'Finger blast',
  'Brown spot',
  'Sheath blight',
  'Bacterial leaf blight',
  'Bacterial leaf streak',
  'False smut',
  'Tungro',
  'Downy mildew',
  'Green ear disease',
  'Ergot',
  'Smut',
  'Rust',
  'Grain mold',
  'Foot rot',
  'Seedling blight',
  'Other',
];

const _diseaseNameLabels = {
  'Blast': {'en': 'Blast', 'hi': '', 'mr': 'करपा'},
  'Leaf blast': {'en': 'Leaf blast', 'hi': '', 'mr': 'पानावरील करपा'},
  'Neck blast': {'en': 'Neck blast', 'hi': '', 'mr': 'मान करपा'},
  'Finger blast': {'en': 'Finger blast', 'hi': '', 'mr': 'कणसावरील करपा'},
  'Brown spot': {'en': 'Brown spot', 'hi': '', 'mr': 'तपकिरी ठिपका'},
  'Sheath blight': {'en': 'Sheath blight', 'hi': '', 'mr': 'खोडावरील करपा'},
  'Bacterial leaf blight': {
    'en': 'Bacterial leaf blight',
    'hi': '',
    'mr': 'जीवाणूजन्य पान करपा',
  },
  'Bacterial leaf streak': {
    'en': 'Bacterial leaf streak',
    'hi': '',
    'mr': 'जीवाणूजन्य पान रेषा',
  },
  'False smut': {'en': 'False smut', 'hi': '', 'mr': 'खोटा काणी रोग'},
  'Tungro': {'en': 'Tungro', 'hi': '', 'mr': 'टुंग्रो रोग'},
  'Downy mildew': {'en': 'Downy mildew', 'hi': '', 'mr': 'केवडा रोग'},
  'Green ear disease': {
    'en': 'Green ear disease',
    'hi': '',
    'mr': 'हिरवा कणीस रोग',
  },
  'Ergot': {'en': 'Ergot', 'hi': '', 'mr': 'अरगट रोग'},
  'Smut': {'en': 'Smut', 'hi': '', 'mr': 'काणी रोग'},
  'Rust': {'en': 'Rust', 'hi': '', 'mr': 'तांबेरा रोग'},
  'Grain mold': {'en': 'Grain mold', 'hi': '', 'mr': 'दाणा बुरशी'},
  'Foot rot': {'en': 'Foot rot', 'hi': '', 'mr': 'खोड कुज'},
  'Seedling blight': {'en': 'Seedling blight', 'hi': '', 'mr': 'रोप करपा'},
  'Other': {'en': 'Other', 'hi': 'अन्य', 'mr': 'इतर'},
};

const _affectedCropFallbackValues = ['bajra', 'nachani', 'paddy', 'Other'];

const _affectedCropFallbackLabels = {
  'bajra': {'en': 'Bajra', 'hi': 'बाजरा', 'mr': 'बाजरी'},
  'nachani': {'en': 'Nachani (Ragi)', 'hi': 'रागी/नाचनी', 'mr': 'नाचणी'},
  'paddy': {'en': 'Paddy (Rice)', 'hi': 'धान', 'mr': 'भात'},
  'Other': {'en': 'Other', 'hi': 'अन्य', 'mr': 'इतर'},
};
