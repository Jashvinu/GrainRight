import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/chat_message.dart';
import '../models/form_config.dart';
import '../models/survey_launch.dart';
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

enum _CropGroup { riceRagi, bajraOther }

class ChatSurveyController extends GetxController {
  static const cursorDraftKey = 'chat_form_cursor';
  static const _riceRagiCrops = {'paddy', 'nachani'};
  static const _bajraOtherCrops = {'bajra', 'other'};

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
    final launch = SurveyLaunchArgs.from(Get.arguments);
    final id = launch.mode == SurveyLaunchMode.edit ? launch.surveyId : null;
    if (id != null) formController.prepareEdit(id);
    if (launch.mode == SurveyLaunchMode.newSurvey) {
      await _clearStoredDraft();
    }
    await formController.loadConfig();
    if (!formController.isConfigLoaded.value) {
      isReady.value = true;
      messages.add(
        BotTextMessage(
          formController.errorMessage.value.isEmpty
              ? 'The form could not be loaded. Please try again.'
              : formController.errorMessage.value,
        ),
      );
      return;
    }
    if (launch.mode == SurveyLaunchMode.newSurvey) {
      formController.startFreshSurvey();
      await _clearDraftCursor();
    }
    var restoredDraft = false;
    int? restoredCursor;
    if (id != null) {
      await formController.loadSurvey(id);
    } else if (launch.mode == SurveyLaunchMode.resumeDraft &&
        await formController.hasDraft()) {
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
      await _showNext(immediate: true);
      return;
    }

    _cursor = _firstFieldCursor('farmer_name') ?? _firstVisibleCursor() ?? 0;
    await _showNext(immediate: true);
  }

  Future<void> chooseLanguage(String language) async {
    final code = switch (language) {
      'हिन्दी' => 'hi',
      'मराठी' => 'mr',
      _ => 'en',
    };
    await setLanguageCode(code);
    messages.add(UserTextMessage(language));
  }

  Future<void> setLanguageCode(String code) async {
    await languageController.setLanguage(code);
    formController.setValue('language', code);
    _steps = _buildSteps();
    await _saveProgress();
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
    if (groupKey == 'kharif_crops') {
      _steps = _buildSteps();
    }
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

  Future<void> _showNext({bool immediate = false}) async {
    if (!immediate) {
      messages.add(TypingIndicatorMessage());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      messages.removeWhere((message) => message is TypingIndicatorMessage);
    }

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
    _cursor = _steps.length;
    activeField.value = null;
    final hasSummary = messages.any((message) => message is SummaryMessage);
    if (!hasSummary) {
      messages.add(SummaryMessage(formController.toFlatJson()));
    }
  }

  List<_ChatStep> _buildSteps() {
    return _buildStepsFromSections(
      sections: formController.sections.toList(),
      localizedFieldLabel: _localizedFieldLabel,
      localizedRepeatGroupTitle: _localizedRepeatGroupTitle,
      cropPracticeRoleOrder: _cropPracticeRoleOrder(),
    );
  }

  static List<_ChatStep> _buildStepsFromSections({
    required List<FormSectionConfig> sections,
    required String Function(FormFieldConfig field) localizedFieldLabel,
    required String Function(
      String groupKey,
      String? cropRole,
      bool isPrimaryCropSlot,
    )
    localizedRepeatGroupTitle,
    List<String> cropPracticeRoleOrder = const ['main', 'other'],
  }) {
    final steps = <_ChatStep>[];
    final configuredGroups = <String>{};
    final practiceRoleOrder = _normalizedPracticeRoleOrder(
      cropPracticeRoleOrder,
    );
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final repeatFields = section.fields
          .where((field) => field.repeatGroup != null)
          .toList();
      if (repeatFields.isNotEmpty) {
        for (final field in repeatFields) {
          if (_isManagedRepeatStep(field.repeatGroup, field.cropRole)) {
            continue;
          }
          final key = [
            field.repeatGroup,
            field.cropRole,
          ].whereType<String>().join(':');
          if (configuredGroups.add(key)) {
            steps.add(
              _RepeatStep(
                field.repeatGroup!,
                localizedFieldLabel(field),
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

    bool hasRepeatStep(_RepeatStep step) {
      return steps.any(
        (s) =>
            s is _RepeatStep &&
            s.groupKey == step.groupKey &&
            s.cropRole == step.cropRole,
      );
    }

    void insertAfterIndex(int index, _RepeatStep step) {
      if (hasRepeatStep(step)) return;
      steps.insert(index == -1 ? steps.length : index + 1, step);
    }

    void insertAfterField(String fieldKey, _RepeatStep step) {
      final index = steps.indexWhere(
        (s) => s is _FieldStep && s.field.fieldKey == fieldKey,
      );
      insertAfterIndex(index, step);
    }

    void insertAfterRepeat(
      String groupKey,
      String? cropRole,
      _RepeatStep step,
    ) {
      if (steps.any(
        (s) =>
            s is _RepeatStep &&
            s.groupKey == step.groupKey &&
            s.cropRole == step.cropRole,
      )) {
        return;
      }
      final index = steps.indexWhere((s) {
        return s is _RepeatStep &&
            s.groupKey == groupKey &&
            s.cropRole == cropRole;
      });
      insertAfterIndex(index, step);
    }

    int sectionIndexForField(String fieldKey) {
      for (var i = 0; i < sections.length; i++) {
        final section = sections[i];
        if (section.fields.any((field) => field.fieldKey == fieldKey)) {
          return i;
        }
      }
      return sections.isEmpty ? 0 : sections.length - 1;
    }

    insertAfterField(
      'main_crop_land_acre',
      _RepeatStep(
        'kharif_crops',
        localizedRepeatGroupTitle('kharif_crops', null, true),
        sectionIndex: sectionIndexForField('main_crop_land_acre'),
      ),
    );

    String anchorGroup = 'kharif_crops';
    String? anchorRole;
    for (var i = 0; i < practiceRoleOrder.length; i++) {
      final role = practiceRoleOrder[i];
      insertAfterRepeat(
        anchorGroup,
        anchorRole,
        _RepeatStep(
          'crop_practices',
          localizedRepeatGroupTitle('crop_practices', role, i == 0),
          sectionIndex: sectionIndexForField('main_crop_land_acre'),
          cropRole: role,
        ),
      );
      anchorGroup = 'crop_practices';
      anchorRole = role;
    }

    insertAfterRepeat(
      anchorGroup,
      anchorRole,
      _RepeatStep(
        'main_crop_yearly',
        localizedRepeatGroupTitle('main_crop_yearly', null, true),
        sectionIndex: sectionIndexForField('main_crop_land_acre'),
      ),
    );

    _moveFieldToStart(steps, 'farmer_name');
    return steps;
  }

  static bool _isManagedRepeatStep(String? groupKey, String? cropRole) {
    if (groupKey == 'kharif_crops' || groupKey == 'main_crop_yearly') {
      return true;
    }
    return groupKey == 'crop_practices' &&
        (cropRole == 'main' || cropRole == 'other');
  }

  static List<String> _normalizedPracticeRoleOrder(List<String> roles) {
    final output = <String>[];
    for (final role in roles) {
      if ((role == 'main' || role == 'other') && !output.contains(role)) {
        output.add(role);
      }
    }
    for (final role in const ['main', 'other']) {
      if (!output.contains(role)) output.add(role);
    }
    return output;
  }

  static void _moveFieldToStart(List<_ChatStep> steps, String fieldKey) {
    final index = steps.indexWhere(
      (step) => step is _FieldStep && step.field.fieldKey == fieldKey,
    );
    if (index <= 0) return;
    final step = steps.removeAt(index);
    steps.insert(0, step);
  }

  @visibleForTesting
  static List<String> debugStepKeysForSections(
    List<FormSectionConfig> sections, {
    List<String> cropPracticeRoleOrder = const ['main', 'other'],
  }) {
    final steps = _buildStepsFromSections(
      sections: sections,
      localizedFieldLabel: (field) => field.label,
      localizedRepeatGroupTitle: (groupKey, cropRole, isPrimaryCropSlot) {
        final key = cropRole == null ? groupKey : '$groupKey:$cropRole';
        if (groupKey != 'crop_practices') return key;
        return '${isPrimaryCropSlot ? 'main-slot' : 'other-slot'}:$key';
      },
      cropPracticeRoleOrder: cropPracticeRoleOrder,
    );
    return steps.map((step) {
      return switch (step) {
        _FieldStep(:final field) => field.fieldKey,
        _RepeatStep(:final groupKey, :final cropRole) =>
          cropRole == null ? 'repeat:$groupKey' : 'repeat:$groupKey:$cropRole',
      };
    }).toList();
  }

  @visibleForTesting
  static List<String> debugRepeatStepTitlesForSections(
    List<FormSectionConfig> sections, {
    List<String> cropPracticeRoleOrder = const ['main', 'other'],
  }) {
    final steps = _buildStepsFromSections(
      sections: sections,
      localizedFieldLabel: (field) => field.label,
      localizedRepeatGroupTitle: _englishRepeatGroupTitle,
      cropPracticeRoleOrder: cropPracticeRoleOrder,
    );
    return [
      for (final step in steps)
        if (step is _RepeatStep) step.title,
    ];
  }

  @visibleForTesting
  static List<String> debugCropPracticeRoleOrder({
    required dynamic mainCrop,
    required List<Map<String, dynamic>> kharifRows,
  }) {
    return _practiceRoleOrderFor(
      _primaryCropGroup(mainCrop: mainCrop, kharifRows: kharifRows),
    );
  }

  Future<void> _advanceToNext() async {
    activeField.value = null;
    _cursor = (_cursor + 1).clamp(0, _steps.length).toInt();
    await _saveProgress();
    await _showNext();
  }

  Future<void> _saveProgress() async {
    if (_completed || formController.isEditMode) return;
    _syncCurrentSection();
    await formController.saveDraft();
    await _secureStorage.writeInt(cursorDraftKey, _cursor);
  }

  Future<int?> _loadDraftCursor() async {
    return _secureStorage.readInt(cursorDraftKey);
  }

  Future<void> _clearDraftCursor() async {
    await _secureStorage.remove(cursorDraftKey);
  }

  Future<void> _clearStoredDraft() async {
    await formController.clearDraft(suppressAutosave: true);
    await _clearDraftCursor();
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

  int? _firstFieldCursor(String fieldKey) {
    final index = _steps.indexWhere(
      (step) => step is _FieldStep && step.field.fieldKey == fieldKey,
    );
    return index == -1 ? null : index;
  }

  int? _firstVisibleCursor() {
    for (var i = 0; i < _steps.length; i++) {
      final step = _steps[i];
      if (step is _FieldStep && formController.isFieldVisible(step.field)) {
        return i;
      }
      if (step is _RepeatStep &&
          _shouldShowRepeatGroup(step.groupKey, step.cropRole)) {
        return i;
      }
    }
    return null;
  }

  bool _shouldShowRepeatGroup(String groupKey, String? cropRole) {
    if (groupKey == 'kharif_crops') {
      return _cropGroupForValue(formController.valueFor('main_crop')) != null;
    }
    if (groupKey == 'crop_practices' &&
        (cropRole == 'main' || cropRole == 'other')) {
      return _selectedPrimaryCropGroup() != null;
    }
    if (groupKey == 'other_crops') {
      return _cropGroupForValue(formController.valueFor('main_crop')) != null;
    }
    return true;
  }

  List<String> _cropPracticeRoleOrder() {
    return _practiceRoleOrderFor(_selectedPrimaryCropGroup());
  }

  _CropGroup? _selectedPrimaryCropGroup() {
    return _primaryCropGroup(
      mainCrop: formController.valueFor('main_crop'),
      kharifRows: formController.kharifRows.toList(),
    );
  }

  static List<String> _practiceRoleOrderFor(_CropGroup? cropGroup) {
    return cropGroup == _CropGroup.bajraOther
        ? const ['other', 'main']
        : const ['main', 'other'];
  }

  static _CropGroup? _primaryCropGroup({
    required dynamic mainCrop,
    required List<Map<String, dynamic>> kharifRows,
  }) {
    for (final row in kharifRows) {
      final crop = row['crop_name']?.toString();
      final group = _cropGroupForValue(crop);
      if (group != null) return group;
    }
    return _cropGroupForValue(mainCrop);
  }

  static _CropGroup? _cropGroupForValue(dynamic value) {
    final crop = value?.toString();
    if (crop == null || crop.isEmpty) return null;
    if (_riceRagiCrops.contains(crop)) return _CropGroup.riceRagi;
    if (_bajraOtherCrops.contains(crop)) return _CropGroup.bajraOther;
    return null;
  }

  String _localizedFieldLabel(FormFieldConfig field) {
    return switch (languageController.language.value) {
      'hi' => field.labelHi?.isNotEmpty == true ? field.labelHi! : field.label,
      'mr' => field.labelMr?.isNotEmpty == true ? field.labelMr! : field.label,
      _ => field.label,
    };
  }

  String _localizedRepeatGroupTitle(
    String groupKey,
    String? cropRole,
    bool isPrimaryCropSlot,
  ) {
    final language = languageController.language.value;
    if (language == 'hi') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीफ फसलें',
        'other_crops' => 'ली गई अन्य फसलें',
        'main_crop_yearly' => 'मुख्य फसल उत्पादन इतिहास',
        'crop_practices' =>
          '${isPrimaryCropSlot ? 'मुख्य फसल कृषि' : 'अन्य फसल कृषि'} - ${_hindiCropPracticeGroupTitle(cropRole)}',
        _ => groupKey,
      };
    }
    if (language == 'mr') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीप पिके',
        'other_crops' => 'घेतलेली इतर पिके',
        'main_crop_yearly' => 'मुख्य पीक उत्पादन इतिहास',
        'crop_practices' =>
          '${isPrimaryCropSlot ? 'मुख्य पीक कृषी' : 'इतर पीक कृषी'} - ${_marathiCropPracticeGroupTitle(cropRole)}',
        _ => groupKey,
      };
    }
    return _englishRepeatGroupTitle(groupKey, cropRole, isPrimaryCropSlot);
  }

  static String _englishRepeatGroupTitle(
    String groupKey,
    String? cropRole,
    bool isPrimaryCropSlot,
  ) {
    return switch (groupKey) {
      'kharif_crops' => 'Kharif crops',
      'other_crops' => 'Other crops taken',
      'main_crop_yearly' => 'Main crop production history',
      'crop_practices' =>
        '${isPrimaryCropSlot ? 'Main Crop Agronomy' : 'Other Crop Agronomy'} - ${_englishCropPracticeGroupTitle(cropRole)}',
      _ => groupKey,
    };
  }

  static String _englishCropPracticeGroupTitle(String? cropRole) {
    return cropRole == 'other'
        ? 'Bajra/Other crop practices'
        : 'Rice/Ragi crop practices';
  }

  static String _hindiCropPracticeGroupTitle(String? cropRole) {
    return cropRole == 'other'
        ? 'बाजरा/अन्य फसल पद्धतियां'
        : 'चावल/रागी फसल पद्धतियां';
  }

  static String _marathiCropPracticeGroupTitle(String? cropRole) {
    return cropRole == 'other'
        ? 'बाजरी/इतर पीक पद्धती'
        : 'तांदूळ/नाचणी पीक पद्धती';
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
