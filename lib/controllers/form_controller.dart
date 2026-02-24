import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/survey_controller.dart';
import '../models/form_config.dart';
import '../services/form_config_service.dart';
import '../services/survey_service.dart';

class FormController extends GetxController {
  final _surveyService = SurveyService();
  final _configService = FormConfigService();

  // Config state
  final sections = <FormSectionConfig>[].obs;
  final dropdownOptions = <String, List<String>>{}.obs;
  final isConfigLoaded = false.obs;

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

  // Accessors for DynamicField
  TextEditingController textController(String key) => _textControllers[key]!;
  Rxn<bool> boolValue(String key) => _boolValues[key]!;
  Rxn<String> dropdownValue(String key) => _stringValues[key]!;
  Rxn<DateTime> dateValue(String key) => _dateValues[key]!;
  RxDouble autoCalcValue(String key) => _autoCalcValues[key]!;

  @override
  void onInit() {
    super.onInit();
    ever(currentStep, (step) => visitedSteps.add(step));
  }

  Future<void> loadConfig() async {
    final results = await Future.wait([
      _configService.fetchFormConfig(),
      _configService.fetchDropdownOptions(),
    ]);
    sections.value = results[0] as List<FormSectionConfig>;
    dropdownOptions.value = results[1] as Map<String, List<String>>;
    _initializeFieldControllers();
    isConfigLoaded.value = true;
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
            _textControllers[field.fieldKey] = TextEditingController();
          case 'dropdown':
            _stringValues[field.fieldKey] = Rxn<String>();
          case 'boolean':
            _boolValues[field.fieldKey] = Rxn<bool>();
          case 'date':
            _dateValues[field.fieldKey] = Rxn<DateTime>();
          case 'auto_calc':
            _autoCalcValues[field.fieldKey] = 0.0.obs;
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

  /// Returns true if at least one visible field in the section has data.
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
          if (_textControllers[key]!.text.isNotEmpty) return true;
        case 'dropdown':
          if (_stringValues[key]!.value != null) return true;
        case 'boolean':
          if (_boolValues[key]!.value != null) return true;
        case 'date':
          if (_dateValues[key]!.value != null) return true;
        case 'auto_calc':
          if (_autoCalcValues[key]!.value != 0) return true;
      }
    }
    return false;
  }

  // --- Edit mode ---

  Future<void> loadSurvey(String id) async {
    editId = id;
    final data = await _surveyService.fetchById(id);
    _populateFromJson(data.toJson());
    // In edit mode add the id back and mark all steps visited
    visitedSteps.addAll(List.generate(totalSteps, (i) => i).toSet());
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
          case 'date':
            _dateValues[key]!.value = DateTime.tryParse(raw.toString());
          case 'dropdown':
            _stringValues[key]!.value = raw.toString();
          case 'boolean':
            _boolValues[key]!.value = raw as bool;
          case 'auto_calc':
            final v = _toDouble(raw);
            if (v != null) _autoCalcValues[key]!.value = v;
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
          case 'auto_calc':
            final v = _autoCalcValues[key]!.value;
            value = v != 0 ? v : null;
        }

        if (value != null) map[key] = value;
      }
    }
    return map;
  }

  Future<void> submit() async {
    // Only validate fields on the current step (others aren't in the tree)
    final formState = formKey.currentState;
    if (formState != null && !formState.validate()) {
      Get.snackbar('Validation', 'Please fill in the required fields on this step');
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
      // Reload survey list before navigating back
      if (Get.isRegistered<SurveyController>()) {
        Get.find<SurveyController>().loadSurveys();
      }
      isSubmitting.value = false;
      Get.back();
      Get.snackbar('Success', isEditMode ? 'Survey updated' : 'Survey submitted');
    } catch (e) {
      isSubmitting.value = false;
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

  @override
  void onClose() {
    for (final ctrl in _textControllers.values) {
      ctrl.dispose();
    }
    super.onClose();
  }
}
