import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/chat_message.dart';
import '../models/form_config.dart';
import '../services/secure_app_storage.dart';
import '../utils/polygon_geometry.dart';
import '../utils/pii_masking.dart';

sealed class _ChatStep {
  int get sectionIndex;
}

class _FieldStep extends _ChatStep {
  @override
  final int sectionIndex;
  final FormFieldConfig field;

  _FieldStep(this.field, this.sectionIndex);
}

class _RepeatStep extends _ChatStep {
  @override
  final int sectionIndex;
  final String groupKey;
  final String title;
  final String? cropRole;

  _RepeatStep(
    this.groupKey,
    this.title, {
    required this.sectionIndex,
    this.cropRole,
  });
}

class ChatSurveyController extends GetxController {
  static const _cursorDraftKey = 'chat_form_cursor';

  final FormController formController;
  final LanguageController languageController;
  final _secureStorage = SecureAppStorage();

  ChatSurveyController({
    required this.formController,
    required this.languageController,
  });

  final messages = <ChatMessage>[].obs;
  final activeField = Rxn<FormFieldConfig>();
  final isReady = false.obs;
  final isSubmitting = false.obs;

  List<_ChatStep> _steps = [];
  int _cursor = 0;
  bool _completed = false;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  Future<void> _start() async {
    final id = Get.arguments as String?;
    if (id != null) formController.prepareEdit(id);
    await formController.loadConfig();
    var restoredDraft = false;
    int? restoredCursor;
    if (id != null) {
      await formController.loadSurvey(id);
    } else if (await formController.hasDraft()) {
      await formController.loadDraft();
      restoredCursor = await _loadDraftCursor();
      restoredDraft = true;
    }
    _steps = _buildSteps();
    isReady.value = true;

    if (restoredDraft) {
      _cursor = _clampCursor(restoredCursor ?? _cursorForCurrentSection());
      messages.add(
        BotTextMessage(
          'Your saved survey is restored. Continuing from the last question.',
        ),
      );
      await _showNext();
      return;
    }

    messages.add(
      BotTextMessage(
        "Welcome, I'm your survey assistant",
        quickReplies: const ['English', 'हिन्दी', 'मराठी'],
      ),
    );
  }

  Future<void> chooseLanguage(String language) async {
    final code = switch (language) {
      'हिन्दी' => 'hi',
      'मराठी' => 'mr',
      _ => 'en',
    };
    await languageController.setLanguage(code);
    formController.setValue('language', code);
    _steps = _buildSteps();
    _cursor = 0;
    await _saveProgress();
    messages.add(UserTextMessage(language));
    await _showNext();
  }

  Future<void> continueFromField(BuildContext context) async {
    final field = activeField.value;
    if (field == null) return;

    if (field.isRequired && !_hasAnswer(field)) {
      Get.snackbar('Required', 'Please answer this question');
      return;
    }
    final formatError = _formatError(field);
    if (formatError != null) {
      Get.snackbar('Invalid format', formatError);
      return;
    }

    final display = _displayValue(field, context);
    messages.add(UserFieldAnswerMessage(field, display));
    await _advanceToNext();
  }

  Future<void> skipField() async {
    final field = activeField.value;
    if (field == null || field.isRequired) return;
    messages.add(UserTextMessage('Skipped'));
    await _advanceToNext();
  }

  Future<void> acceptPolygon(List<List<double>> coords) async {
    final field = activeField.value;
    if (field == null) return;
    formController.setPolygon(field.fieldKey, coords);
    final ring = PolygonGeometry.fromGeoJsonRing(coords);
    messages.add(
      PolygonAnswerMessage(coords, PolygonGeometry.areaHectares(ring)),
    );
    await _advanceToNext();
  }

  Future<void> saveRepeatGroup({
    required String groupKey,
    required String title,
    String? cropRole,
    required List<Map<String, dynamic>> rows,
  }) async {
    updateRepeatGroupRows(groupKey: groupKey, cropRole: cropRole, rows: rows);
    messages.add(RepeatGroupAnswerMessage(title, rows.length));
    await _advanceToNext();
  }

  void updateRepeatGroupRows({
    required String groupKey,
    String? cropRole,
    required List<Map<String, dynamic>> rows,
  }) {
    switch (groupKey) {
      case 'kharif_crops':
      case 'other_crops':
        formController.setKharifRows(rows);
      case 'main_crop_yearly':
        formController.setYearlyRows(rows);
      case 'crop_practices':
        final role =
            cropRole ??
            (rows.isNotEmpty ? rows.first['crop_role']?.toString() : null);
        final existing = formController.practiceRows
            .where((row) => row['crop_role'] != role)
            .toList();
        final normalizedRows = role == null
            ? rows
            : rows.map((row) => {...row, 'crop_role': role}).toList();
        formController.setPracticeRows([...existing, ...normalizedRows]);
    }
  }

  Future<void> submit() async {
    isSubmitting.value = true;
    final submitted = await formController.submit(popOnSuccess: false);
    isSubmitting.value = false;
    if (!submitted) return;
    _completed = true;
    await _clearDraftCursor();
    if (Get.previousRoute == '/surveys') {
      Get.back();
    } else {
      Get.offNamed('/surveys');
    }
  }

  Future<void> persistProgress() async {
    if (_completed || formController.isEditMode) return;
    await _saveProgress();
  }

  Future<void> _showNext() async {
    messages.add(TypingIndicatorMessage());
    await Future<void>.delayed(const Duration(milliseconds: 350));
    messages.removeWhere((message) => message is TypingIndicatorMessage);

    while (_cursor < _steps.length) {
      final step = _steps[_cursor];
      switch (step) {
        case _FieldStep(:final field):
          if (!formController.isFieldVisible(field)) {
            _cursor++;
            continue;
          }
          await _saveProgress();
          activeField.value = field;
          if (field.inputType == 'polygon' ||
              field.inputType == 'polygon_pencil') {
            messages.add(PolygonPromptMessage(field));
          } else {
            messages.add(BotFieldPromptMessage(field));
          }
          return;
        case _RepeatStep(:final groupKey, :final title, :final cropRole):
          if (!_shouldShowRepeatGroup(groupKey, cropRole)) {
            _cursor++;
            continue;
          }
          await _saveProgress();
          activeField.value = null;
          messages.add(
            RepeatGroupPromptMessage(
              groupKey,
              title: title,
              cropRole: cropRole,
            ),
          );
          return;
      }
    }

    await _saveProgress();
    messages.add(SummaryMessage(formController.toFlatJson()));
  }

  List<_ChatStep> _buildSteps() {
    final steps = <_ChatStep>[];
    final configuredGroups = <String>{};
    for (
      var sectionIndex = 0;
      sectionIndex < formController.sections.length;
      sectionIndex++
    ) {
      final section = formController.sections[sectionIndex];
      final repeatFields = section.fields
          .where((field) => field.repeatGroup != null)
          .toList();
      if (repeatFields.isNotEmpty) {
        for (final field in repeatFields) {
          final key = [
            field.repeatGroup,
            field.cropRole,
          ].whereType<String>().join(':');
          if (configuredGroups.add(key)) {
            steps.add(
              _RepeatStep(
                field.repeatGroup!,
                _localizedFieldLabel(field),
                sectionIndex: sectionIndex,
                cropRole: field.cropRole,
              ),
            );
          }
        }
      }

      for (final field in section.fields) {
        if (field.repeatGroup == null) {
          steps.add(_FieldStep(field, sectionIndex));
        }
      }
    }

    void insertAfter(String fieldKey, _RepeatStep step) {
      if (steps.any(
        (s) =>
            s is _RepeatStep &&
            s.groupKey == step.groupKey &&
            s.cropRole == step.cropRole,
      )) {
        return;
      }
      final index = steps.indexWhere((s) {
        if (s is _FieldStep) return s.field.fieldKey == fieldKey;
        if (s is _RepeatStep) return s.groupKey == fieldKey;
        return false;
      });
      steps.insert(index == -1 ? steps.length : index + 1, step);
    }

    insertAfter(
      'main_crop_land_acre',
      _RepeatStep(
        'kharif_crops',
        _localizedRepeatGroupTitle('kharif_crops', null),
        sectionIndex: _sectionIndexForField('main_crop_land_acre'),
      ),
    );
    insertAfter(
      'kharif_crops',
      _RepeatStep(
        'crop_practices',
        _localizedRepeatGroupTitle('crop_practices', 'main'),
        sectionIndex: _sectionIndexForField('main_crop_land_acre'),
        cropRole: 'main',
      ),
    );
    insertAfter(
      'crop_practices',
      _RepeatStep(
        'main_crop_yearly',
        _localizedRepeatGroupTitle('main_crop_yearly', null),
        sectionIndex: _sectionIndexForField('main_crop_land_acre'),
      ),
    );
    insertAfter(
      'makes_food_products',
      _RepeatStep(
        'crop_practices',
        _localizedRepeatGroupTitle('crop_practices', 'other'),
        sectionIndex: _sectionIndexForField('makes_food_products'),
        cropRole: 'other',
      ),
    );

    return steps;
  }

  Future<void> _advanceToNext() async {
    activeField.value = null;
    _cursor++;
    await _saveProgress();
    await _showNext();
  }

  Future<void> _saveProgress() async {
    if (_completed || formController.isEditMode) return;
    _syncCurrentSection();
    await formController.saveDraft();
    await _secureStorage.writeInt(_cursorDraftKey, _cursor);
  }

  Future<int?> _loadDraftCursor() async {
    return _secureStorage.readInt(_cursorDraftKey);
  }

  Future<void> _clearDraftCursor() async {
    await _secureStorage.remove(_cursorDraftKey);
  }

  void _syncCurrentSection() {
    if (_steps.isEmpty || formController.totalSteps == 0) return;
    final cursor = _cursor.clamp(0, _steps.length - 1);
    final sectionIndex = _steps[cursor].sectionIndex.clamp(
      0,
      formController.totalSteps - 1,
    );
    formController.currentStep.value = sectionIndex;
  }

  int _clampCursor(int cursor) {
    if (_steps.isEmpty) return 0;
    return cursor.clamp(0, _steps.length);
  }

  int _cursorForCurrentSection() {
    final section = formController.currentStep.value;
    final index = _steps.indexWhere((step) => step.sectionIndex >= section);
    return index == -1 ? 0 : index;
  }

  int _sectionIndexForField(String fieldKey) {
    for (var i = 0; i < formController.sections.length; i++) {
      final section = formController.sections[i];
      if (section.fields.any((field) => field.fieldKey == fieldKey)) {
        return i;
      }
    }
    return formController.totalSteps == 0 ? 0 : formController.totalSteps - 1;
  }

  bool _shouldShowRepeatGroup(String groupKey, String? cropRole) {
    if (cropRole == 'other') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'bajra' || mainCrop == 'other';
    }
    if (groupKey == 'kharif_crops' || cropRole == 'main') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'paddy' || mainCrop == 'nachani';
    }
    if (groupKey == 'other_crops') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'bajra' || mainCrop == 'other';
    }
    return true;
  }

  String _localizedFieldLabel(FormFieldConfig field) {
    return switch (languageController.language.value) {
      'hi' => field.labelHi?.isNotEmpty == true ? field.labelHi! : field.label,
      'mr' => field.labelMr?.isNotEmpty == true ? field.labelMr! : field.label,
      _ => field.label,
    };
  }

  String _localizedRepeatGroupTitle(String groupKey, String? cropRole) {
    final language = languageController.language.value;
    if (language == 'hi') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीफ फसलें',
        'other_crops' => 'ली गई अन्य फसलें',
        'main_crop_yearly' => 'मुख्य फसल उत्पादन इतिहास',
        'crop_practices' =>
          cropRole == 'other' ? 'अन्य फसल पद्धतियां' : 'मुख्य फसल पद्धतियां',
        _ => groupKey,
      };
    }
    if (language == 'mr') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीप पिके',
        'other_crops' => 'घेतलेली इतर पिके',
        'main_crop_yearly' => 'मुख्य पीक उत्पादन इतिहास',
        'crop_practices' =>
          cropRole == 'other' ? 'इतर पीक पद्धती' : 'मुख्य पीक पद्धती',
        _ => groupKey,
      };
    }
    return switch (groupKey) {
      'kharif_crops' => 'Kharif crops',
      'other_crops' => 'Other crops taken',
      'main_crop_yearly' => 'Main crop production history',
      'crop_practices' =>
        cropRole == 'other' ? 'Other crop practices' : 'Main crop practices',
      _ => groupKey,
    };
  }

  bool _hasAnswer(FormFieldConfig field) {
    final value = formController.valueFor(field.fieldKey);
    return switch (field.inputType) {
      'text' ||
      'textarea' ||
      'numeric' ||
      'currency' ||
      'acre' ||
      'mobile' ||
      'aadhar' => value is String && value.trim().isNotEmpty,
      'dropdown' => value != null && value.toString().isNotEmpty,
      'boolean' => value != null,
      'date' => value is DateTime,
      'polygon' || 'polygon_pencil' => value is List && value.isNotEmpty,
      'multiselect' => value is List && value.isNotEmpty,
      'auto_calc' => true,
      _ => true,
    };
  }

  String? _formatError(FormFieldConfig field) {
    final value = formController.valueFor(field.fieldKey)?.toString() ?? '';
    if (value.trim().isEmpty) return null;
    if (field.inputType == 'mobile' &&
        !RegExp(r'^[0-9]{10}$').hasMatch(value.trim())) {
      return 'Enter a 10 digit mobile number';
    }
    if (field.inputType == 'aadhar' &&
        !RegExp(r'^[0-9]{12}$').hasMatch(value.replaceAll(' ', '').trim())) {
      return 'Enter a 12 digit Aadhaar number';
    }
    if ((field.inputType == 'text' || field.inputType == 'textarea') &&
        field.validation.containsKey('min_length')) {
      final minLength = field.validation['min_length'] as int;
      if (value.trim().length < minLength) {
        return 'Minimum $minLength characters';
      }
    }
    return null;
  }

  String _displayValue(FormFieldConfig field, BuildContext context) {
    final value = formController.valueFor(field.fieldKey);
    if (value == null) return 'Skipped';
    if (value is DateTime) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is List) {
      if (field.inputType == 'polygon' || field.inputType == 'polygon_pencil') {
        final coords = value.map((point) {
          final p = point as List;
          return [(p[0] as num).toDouble(), (p[1] as num).toDouble()];
        }).toList();
        final ring = PolygonGeometry.fromGeoJsonRing(coords);
        return '${PolygonGeometry.areaHectares(ring).toStringAsFixed(2)} ha';
      }
      return value
          .map(
            (item) => formController.localizedOptionLabel(
              field.dropdownOptionsKey,
              item.toString(),
            ),
          )
          .join(', ');
    }
    if (field.inputType == 'dropdown') {
      return formController.localizedOptionLabel(
        field.dropdownOptionsKey,
        value.toString(),
      );
    }
    if (field.inputType == 'aadhar') {
      return maskAadhaar(value.toString());
    }
    return value.toString();
  }
}
